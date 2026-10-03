"""Score calibration-replay CSVs against the fixture turn timeline.

Each fixture JSON maps output frames to source frames and marks the source frames chosen as
front (0°), rightfront (+60°), back (180°) and leftfront (300°). Yaw for every other frame is
interpolated between those marks, so it is an approximate label (marks were picked by eye).

Reports, per subject and overall:
- view classification of the shipped rules (Vision face + r + δ) against the old spec rules
  (RTMPose ear/face scores), on every unique source frame of the continuous (v2) fixtures
- captures from the held (v1) fixtures and their yaw error
- a left/right confusion matrix, and whether RTMPose's anatomical left/right joints sit on the side
  the turn angle predicts (cos yaw > 0: left shoulder on the image right)
- RTMPose keypoint confidence with the person crop vs the old full-frame stretch
- analysis time per frame

    swift run -c release --package-path ios/CalibrationEngineKit calibration-replay --lenient-pose \\
        outputs/calibration_dummy_videos/dummy_0*.mp4 outputs/calibration_dummy_videos/v2_continuous/dummy_0*.mp4
    python scripts/eval_calibration_replay.py
"""
import csv
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "outputs/calibration_dummy_videos"
REPLAY = ROOT / "outputs/calibration_replay"
SUBJECTS = ["dummy_01_male-3-sport", "dummy_02_female-3-sport", "dummy_03_male-4-sport"]
NOMINAL = {"front": 0, "rightfront": 60, "back": 180, "leftfront": 300}
VIEWS = list(NOMINAL)


def num(row, key):
    value = row.get(key, "")
    return float(value) if value not in ("", None) else None


def yaw_lookup(fixture):
    """Source frame -> approximate yaw in degrees, linear between the marked views."""
    marks = sorted((s["source_frame"], NOMINAL[s["view"]]) for s in fixture["segments"] if "source_frame" in s)
    xs, ys = [m[0] for m in marks], [m[1] for m in marks]

    def yaw(src):
        i = 0 if src <= xs[0] else len(xs) - 2 if src >= xs[-1] else max(k for k in range(len(xs) - 1) if xs[k] <= src)
        x0, x1, y0, y1 = xs[i], xs[i + 1], ys[i], ys[i + 1]
        return y0 + (y1 - y0) * (src - x0) / (x1 - x0)
    return yaw


def angle_error(a, b):
    return abs((a - b + 180) % 360 - 180)


def label(yaw):
    yaw %= 360
    if yaw <= 25 or yaw >= 335:
        return "front"
    if 35 <= yaw <= 85:
        return "rightfront"
    if 150 <= yaw <= 210:
        return "back"
    if 275 <= yaw <= 325:
        return "leftfront"
    return "between"


def reference(rows):
    held = [r for r in rows if num(r, "t") < 3.0 and num(r, "swT") is not None]
    med = lambda k: statistics.median(num(r, k) for r in held)
    return {"s": med("swT"), "h": med("hwT"), "o": med("nose"), "face": med("rtmFace")}


def r_delta(row, ref):
    r = 0.6 * num(row, "swT") / ref["s"] + 0.4 * num(row, "hwT") / ref["h"]
    return min(max(r, 0.0), 1.0), num(row, "nose") - ref["o"]


def classify_new(row, ref):
    """Mirror of CalibrationEngine.classify plus its pre-reference front check."""
    face = row["faceDetected"] == "1"
    yaw = num(row, "faceYaw")
    if face and abs(yaw or 0) <= 20 and abs(num(row, "nose")) <= 0.08:
        return "front"
    r, d = r_delta(row, ref)
    if 0.31 <= r <= 0.75 and face:
        if yaw is not None and abs(yaw) <= 20:
            return None
        if abs(d) >= 0.12:
            return "rightfront" if d > 0 else "leftfront"
        return None
    if r >= 0.90 and not face:  # CalibrationConfig.view.backMinR
        return "back"
    return None


def classify_spec(row, ref):
    """The original spec rules, driven by RTMPose face/ear scores."""
    face, el, er = num(row, "rtmFace"), num(row, "earL"), num(row, "earR")
    if face >= 0.5 and abs(num(row, "nose")) <= 0.08 and abs(el - er) <= 0.25:
        return "front"
    r, d = r_delta(row, ref)
    if 0.31 <= r <= 0.67:
        if el >= 0.4 and er >= 0.4 and face >= 0.5:
            return None
        if face >= 0.4 and abs(d) >= 0.12:
            if d > 0 and er >= 0.5 and el <= 0.3:
                return "rightfront"
            if d < 0 and el >= 0.5 and er <= 0.3:
                return "leftfront"
        return None
    if face <= min(0.35, 0.5 * ref["face"]) and el <= 0.3 and er <= 0.3 and r >= 0.85:
        return "back"
    return None


def score(frames, classify):
    hits = {v: [0, 0] for v in VIEWS}
    predictions, good, bad = 0, 0, 0
    for row, ref, yaw in frames:
        predicted = classify(row, ref)
        truth = label(yaw)
        if truth in hits:
            hits[truth][1] += 1
            hits[truth][0] += predicted == truth
        if predicted:
            predictions += 1
            err = angle_error(yaw, NOMINAL[predicted])
            good += err <= 30
            bad += err > 45
    recall = {v: (h / n if n else None, n) for v, (h, n) in hits.items()}
    return recall, predictions, good, bad


def main():
    all_frames, conf_rows, timings = [], [], []
    print("자동 촬영 (v1, 3초 정지 구간, --lenient-pose 로 재생한 CSV 기준)")
    for subject in SUBJECTS:
        v1_rows = list(csv.DictReader(open(REPLAY / f"{subject}.csv")))
        v2_rows = list(csv.DictReader(open(REPLAY / f"v2_continuous__{subject}.csv")))
        ref = reference(v1_rows)
        for rows, fixture_path in ((v1_rows, FIXTURES / f"{subject}.json"),
                                   (v2_rows, FIXTURES / "v2_continuous" / f"{subject}.json")):
            fixture = json.loads(fixture_path.read_text())
            yaw = yaw_lookup(fixture)
            src = fixture["source_frame_for_each_output_frame"]
            if rows is v1_rows:
                caps = [(r["classified"], num(r, "t"), yaw(src[int(r["i"])])) for r in rows
                        if r["classified"] and ("촬영 완료" in r["guidance"] or "모두 끝났어요" in r["guidance"])]
                text = ", ".join(f"{v} {t:.2f}s(약 {y:.0f}°, 오차 {angle_error(y, NOMINAL[v]):.0f}°)" for v, t, y in caps)
                print(f"  {subject}: {len(caps)}/4  {text}")
                continue
            seen = set()
            for row in rows:
                s = src[int(row["i"])]
                timings.append(num(row, "analyzeMs"))
                if s in seen:
                    continue
                seen.add(s)
                conf_rows.append(row)
                if row["swT"]:
                    all_frames.append((row, ref, yaw(s)))

    print(f"\n방향 판정 (v2 연속 회전, 원본 프레임 {len(all_frames)}개, 정답 각도는 근사)")
    for name, fn in (("새 판정 (얼굴 검출 + r + δ)", classify_new), ("명세 원안 (RTMPose 귀·얼굴 점수)", classify_spec)):
        recall, predictions, good, bad = score(all_frames, fn)
        parts = ", ".join(f"{v} {r * 100:.0f}% ({n})" if r is not None else f"{v} -" for v, (r, n) in recall.items())
        print(f"  {name}")
        print(f"    정답 구간 안에서 맞게 판정한 비율: {parts}")
        if predictions:
            print(f"    판정 {predictions}회 중 방향 오차 30° 이내 {good}회({good / predictions:.0%}), 45° 초과 {bad}회({bad / predictions:.0%})")

    print("\n좌우를 구분한 혼동 행렬 (행 = 근사 정답, 열 = 판정, 새 판정)")
    cols = VIEWS + [None]
    names = {"front": "정면", "rightfront": "왼쪽(+60)", "back": "뒷면", "leftfront": "오른쪽(-60)", None: "판정 안 함"}
    print("    " + "".join(f"{names[c]:>12}" for c in cols))
    swaps = 0
    for truth in VIEWS + ["between"]:
        counts = {c: 0 for c in cols}
        for row, ref, yaw in all_frames:
            if label(yaw) == truth:
                counts[classify_new(row, ref)] += 1
        print(f"    {names.get(truth, '사이 구간'):<10}" + "".join(f"{counts[c]:>12}" for c in cols))
    for row, ref, yaw in all_frames:
        predicted = classify_new(row, ref)
        side = (yaw % 360) < 180  # turned towards the user's left half of the circle
        if predicted == "rightfront" and not side or predicted == "leftfront" and side:
            swaps += 1
    print(f"    왼쪽/오른쪽 사선을 반대로 판정한 프레임: {swaps}")

    print("\nRTMPose 관절 좌우 (어깨·골반의 좌우 순서가 회전각과 맞는지, 옆모습 ±30° 제외)")
    for name, lo, hi in (("앞쪽 (정면±60°)", -60, 60), ("뒤쪽 (뒷면±60°)", 120, 240)):
        ok_s = ok_h = n = 0
        for row, ref, yaw in all_frames:
            y = yaw % 360
            y = y - 360 if y > 180 and lo < 0 else y
            if not (lo <= y <= hi) or row.get("lrShoulder", "") == "":
                continue
            expected = 1 if math.cos(math.radians(yaw)) > 0 else -1
            n += 1
            ok_s += (num(row, "lrShoulder") > 0) == (expected > 0)
            ok_h += (num(row, "lrHip") > 0) == (expected > 0)
        print(f"  {name}: 프레임 {n}개, 어깨 좌우 맞음 {ok_s / n:.0%}, 골반 좌우 맞음 {ok_h / n:.0%}")

    crop = [num(r, "cropMeanReq") for r in conf_rows]
    stretch = [num(r, "stretchMeanReq") for r in conf_rows]
    crop_all = sum(r["cropAllReq"] == "1" for r in conf_rows) / len(conf_rows)
    stretch_all = sum(r["stretchAllReq"] == "1" for r in conf_rows) / len(conf_rows)
    print(f"\nRTMPose 키포인트 (필수 12관절, 프레임 {len(conf_rows)}개)")
    print(f"  평균 신뢰도      크롭 {statistics.mean(crop):.3f}  /  기존 늘리기 {statistics.mean(stretch):.3f}")
    print(f"  12관절 모두 ≥0.3 크롭 {crop_all:.0%}  /  기존 늘리기 {stretch_all:.0%}")
    t = sorted(x for x in timings if x is not None)
    print(f"\n분석 시간 (Mac, RTMPose+Vision, 720x1280): 중앙값 {statistics.median(t):.1f}ms, 95% {t[int(len(t) * .95)]:.1f}ms")


if __name__ == "__main__":
    main()
