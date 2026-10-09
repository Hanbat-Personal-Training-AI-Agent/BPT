"""Evaluate rep counting, the side-view gate and form warnings on your own workout videos.

Drives pose-replay (the app's pose path + evaluators, ios/CalibrationEngineKit) on every video in a
folder for COCO17 and Halpe26, with the ready-pose check off (app default) and with its preset
(squat/row: hold the start pose 0.5 s before the first rep; push-up: off), then writes one Markdown report.

Ground-truth CSV (one row per video, header required):
    file,exercise,angle_deg,form,wrong_key,reps
    squat_side_0.mp4,squat,0,normal,,10
    row_30_swing.mp4,row,30,wrong,row_torso_swing,8
    pushup_front.mp4,pushup,front,normal,,10
  file       video file name inside --videos
  exercise   squat | pushup | row
  angle_deg  camera angle from the pure side view in degrees (0 = side), or front / back
  form       normal | wrong
  wrong_key  for form=wrong: the warning key the set is meant to trigger (e.g. pushup_hip_sag); else empty
  reps       true rep count
Rows with an empty file are skipped, so data/side_videos/labels_template.csv can be filled in place.

Usage:
    swift build -c release --package-path ios/CalibrationEngineKit --product pose-replay
    python scripts/eval_side_videos.py --videos ~/bpt_videos --truth ~/bpt_videos/truth.csv --out outputs/side_eval

Report (<out>/report.md): rep accuracy per video and per exercise × angle × model; shoulder width ÷
torso length (side-view gate metric, cutoff 0.56) per angle; per-key warning rate (fraction of counted
reps) normal vs wrong, and how often a wrong set's wrong_key fired; setup_full_body / tracking_lost
counts per set (and how many fired inside a counted rep). pytest tests/test_eval_side_videos.py
checks the parsing/aggregation without videos.
"""
import argparse
import csv
import json
import statistics
import subprocess
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_BINARY = REPO / "ios/CalibrationEngineKit/.build/release/pose-replay"
MODELS = ("coco17", "halpe26")
EXERCISE_FILE = {"squat": "squat", "pushup": "pushup", "row": "barbell_row"}
SIDE_CUTOFF = 0.56  # BarbellRowFormConfig.sideViewMaxShoulderRatio
COLUMNS = ["file", "exercise", "angle_deg", "form", "wrong_key", "reps"]
SETUP_KEYS = ("setup_full_body", "tracking_lost")


def read_truth(path):
    reader = csv.DictReader(open(path, newline=""))
    if set(COLUMNS) - set(reader.fieldnames or []):
        raise SystemExit(f"{path}: need columns {','.join(COLUMNS)}")
    rows = [r for r in reader if (r["file"] or "").strip()]  # empty file = unfilled template row
    if not rows:
        raise SystemExit(f"{path}: no rows with a file name")
    for r in rows:
        assert r["exercise"] in EXERCISE_FILE, r
        assert r["form"] in ("normal", "wrong"), r
        r["reps"] = int(r["reps"])
        r["wrong_key"] = r["wrong_key"].strip()
        r["angle_deg"] = r["angle_deg"].strip().lower()
    return rows


def shoulder_ratios(csv_path, min_conf=0.30):
    """Per-frame |left − right shoulder x| / torso length, as FormWarningTracker measures it."""
    out = []
    for r in csv.DictReader(open(csv_path)):
        p = {j: (float(r[f"j{j}_x"]), float(r[f"j{j}_y"]), float(r[f"j{j}_c"])) for j in (5, 6, 11, 12)}
        if min(v[2] for v in p.values()) < min_conf:
            continue
        torso = ((p[5][0] + p[6][0] - p[11][0] - p[12][0]) ** 2 + (p[5][1] + p[6][1] - p[11][1] - p[12][1]) ** 2) ** 0.5 / 2
        if torso > 1e-8:
            out.append(abs(p[5][0] - p[6][0]) / torso)
    return out


def run(binary, video, exercise, model, ready, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    base = out_dir / f"{Path(video).stem}_{EXERCISE_FILE[exercise]}_{model}"
    if not base.with_suffix(".json").exists():
        subprocess.run([str(binary), "--exercise", exercise, "--model", model, "--motion3d", "none", "--ready-pose", ready,
                        "--output-dir", str(out_dir), str(video)], check=True, stdout=subprocess.DEVNULL)
    return json.load(open(base.with_suffix(".json"))), base.with_suffix(".csv")


def setup_key_counts(j):
    """{key: (sent, sent inside a counted rep)} for the tracking guidance keys."""
    reps = [(r["start_frame"], r["end_frame"]) for r in j["reps"]]
    out = {}
    for key in SETUP_KEYS:
        frames = [e["frame"] for e in j["events"] if e["key"] == key]
        out[key] = (len(frames), sum(any(a <= f <= b for a, b in reps) for f in frames))
    return out


def pct(values, q):
    v = sorted(values)
    return v[min(len(v) - 1, int(q * (len(v) - 1) + 0.5))] if v else float("nan")


def summarize(results):
    """results: dicts with truth row fields + model, counted, warnings (list per rep), side_view_event, ratios."""
    lines = ["## 렙 카운트 (영상별)", "",
             "| 파일 | 운동 | 각도 | 자세 | 모델 | 준비자세 | 정답 | 셈 | 오차 | 측면 아님 안내 | setup_full_body (렙 중) | tracking_lost (렙 중) |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in results:
        sk = r.get("setup_keys", {})
        cell = lambda k: "{} ({})".format(*sk[k]) if k in sk else "-"
        lines.append(f"| {r['file']} | {r['exercise']} | {r['angle_deg']} | {r['form']} | {r['model']} | {r['ready']} | {r['reps']} | "
                     f"{r['counted']} | {r['counted'] - r['reps']:+d} | {'예' if r['side_view_event'] else ''} | "
                     f"{cell('setup_full_body')} | {cell('tracking_lost')} |")
    lines += ["", "## 렙 카운트 (운동 × 각도 × 모델 × 준비자세)", "",
              "| 운동 | 각도 | 모델 | 준비자세 | 세트 | 정확 일치 | 정답 렙 | 센 렙 | 절대오차 합 |", "|---|---|---|---|---|---|---|---|---|"]
    groups = defaultdict(list)
    for r in results:
        groups[(r["exercise"], r["angle_deg"], r["model"], r["ready"])].append(r)
    for (ex, ang, m, ready), g in sorted(groups.items()):
        lines.append(f"| {ex} | {ang} | {m} | {ready} | {len(g)} | {sum(r['counted'] == r['reps'] for r in g)} | "
                     f"{sum(r['reps'] for r in g)} | {sum(r['counted'] for r in g)} | {sum(abs(r['counted'] - r['reps']) for r in g)} |")

    lines += ["", f"## 측면 지표 (어깨폭 ÷ 몸통 길이, 컷오프 {SIDE_CUTOFF})", "",
              "| 각도 | 모델 | 영상 | 프레임 | p10 | 중앙값 | p90 | 컷오프 이하 프레임 |", "|---|---|---|---|---|---|---|---|"]
    base = [r for r in results if r["ready"] == "off"] or results  # pose and warnings: one condition
    by_angle = defaultdict(list)
    for r in base:
        by_angle[(r["angle_deg"], r["model"])].append(r)
    for (ang, m), g in sorted(by_angle.items()):
        v = [x for r in g for x in r["ratios"]]
        side = sum(x <= SIDE_CUTOFF for x in v) / len(v) if v else float("nan")
        lines.append(f"| {ang} | {m} | {len(g)} | {len(v)} | {pct(v, .1):.3f} | {pct(v, .5):.3f} | {pct(v, .9):.3f} | {side:.0%} |")

    lines += ["", "## 경고 발생률 (센 렙 중 비율, 정상 vs 잘못된 자세)", "",
              "| 운동 | 모델 | 키 | 정상 렙 | 정상 발생률 | 잘못 렙 | 잘못 발생률 |", "|---|---|---|---|---|---|---|"]
    rates = defaultdict(lambda: {"normal": [0, 0], "wrong": [0, 0]})
    keys = defaultdict(set)
    for r in base:
        for w in r["warnings"]:
            keys[(r["exercise"], r["model"])].update(w)
    for r in base:
        for k in keys[(r["exercise"], r["model"])] | ({r["wrong_key"]} if r["wrong_key"] else set()):
            c = rates[(r["exercise"], r["model"], k)][r["form"]]
            c[0] += sum(k in w for w in r["warnings"])
            c[1] += len(r["warnings"])
    for (ex, m, k), c in sorted(rates.items()):
        f = lambda a: f"{a[0] / a[1]:.0%}" if a[1] else "-"
        lines.append(f"| {ex} | {m} | {k} | {c['normal'][1]} | {f(c['normal'])} | {c['wrong'][1]} | {f(c['wrong'])} |")

    lines += ["", "## 잘못된 자세 세트: 의도한 키 적중", "", "| 파일 | 모델 | wrong_key | 그 키가 나온 렙 / 센 렙 |", "|---|---|---|---|"]
    for r in base:
        if r["form"] == "wrong" and r["wrong_key"]:
            lines.append(f"| {r['file']} | {r['model']} | {r['wrong_key']} | {sum(r['wrong_key'] in w for w in r['warnings'])}/{len(r['warnings'])} |")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--videos", required=True, type=Path)
    ap.add_argument("--truth", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--models", default=",".join(MODELS))
    ap.add_argument("--ready-pose", default="off,preset", help="off, preset or both (off,preset)")
    ap.add_argument("--pose-replay", default=DEFAULT_BINARY, type=Path)
    a = ap.parse_args()
    if not a.pose_replay.exists():
        raise SystemExit(f"{a.pose_replay} missing: swift build -c release --package-path ios/CalibrationEngineKit --product pose-replay")
    results = []
    for t in read_truth(a.truth):
        for m in a.models.split(","):
            for ready in a.ready_pose.split(","):
                j, csv_path = run(a.pose_replay, a.videos / t["file"], t["exercise"], m, ready, a.out / ready / m)
                results.append({**t, "model": m, "ready": ready, "counted": j["session"]["rep_count"],
                                "warnings": [rep["warnings"] for rep in j["reps"]],
                                "side_view_event": any(e["key"] == "setup_side_view" for e in j["events"]),
                                "setup_keys": setup_key_counts(j), "ratios": shoulder_ratios(csv_path)})
                print(t["file"], m, ready, j["session"]["rep_count"], "/", t["reps"], flush=True)
    (a.out / "report.md").write_text(summarize(results))
    print(a.out / "report.md")


if __name__ == "__main__":
    main()
