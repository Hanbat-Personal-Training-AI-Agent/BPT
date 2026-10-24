"""중력 정렬 H36M-17 좌표의 반복별 지표와 근거. 모델·영상 없이 검증한다."""
import csv
from pathlib import Path

import numpy as np

from checks import Rejected

RULE_COLUMNS = ("fault_id", "exercise_id", "metric", "threshold", "severity", "title_ko", "body_ko", "device_key")
RULE_PATH = Path(__file__).with_name("deep_rules.csv")
CATALOG_PATH = Path(__file__).resolve().parent.parent.parent / "docs/coaching/fault_catalog.csv"


def load_rules():
    path = CATALOG_PATH if CATALOG_PATH.is_file() else RULE_PATH
    with path.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if not set(RULE_COLUMNS).issubset(reader.fieldnames or []):
            raise Rejected(422, "invalid_fault_catalog")
        rules = list(reader)
    try:
        for rule in rules:
            assert rule["severity"] in ("info", "warning", "critical")
            assert np.isfinite(float(rule["threshold"]))
            assert all(isinstance(rule[key], str) for key in RULE_COLUMNS)
    except (ValueError, TypeError, AssertionError):
        raise Rejected(422, "invalid_fault_catalog") from None
    return rules, path.name


def angle(a, b, c):
    u, v = a - b, c - b
    norm = np.linalg.norm(u, axis=-1) * np.linalg.norm(v, axis=-1)
    if np.any(norm < 1e-8):
        raise Rejected(422, "invalid_skeleton")
    return np.degrees(np.arccos(np.clip(np.sum(u * v, axis=-1) / norm, -1, 1)))


def frame_angles(joints, side):
    hip, knee, ankle, shoulder, elbow, wrist = ((4, 5, 6, 11, 12, 13) if side == "left"
                                               else (1, 2, 3, 14, 15, 16))
    pelvis = (joints[:, 1] + joints[:, 4]) / 2
    shoulders = (joints[:, 11] + joints[:, 14]) / 2
    return {"knee": angle(joints[:, hip], joints[:, knee], joints[:, ankle]),
            "hip": angle(joints[:, shoulder], joints[:, hip], joints[:, knee]),
            "elbow": angle(joints[:, shoulder], joints[:, elbow], joints[:, wrist]),
            "shoulder": angle(joints[:, hip], joints[:, shoulder], joints[:, elbow]),
            "torso": angle(shoulders, pelvis, pelvis + np.array([0, 1, 0]))}


def rounded(value):
    return round(float(value), 3)


def metrics(joints, fps, manifest, confidence=None):
    """world(y 위), 미터. confidence는 프레임별 2D 검출 지지도로 정확도 확률이 아니다."""
    joints = np.asarray(joints, dtype=float)
    if (joints.ndim != 3 or joints.shape[1:] != (17, 3) or not np.isfinite(joints).all()
            or not np.isfinite(fps) or fps <= 0):
        raise Rejected(422, "invalid_skeleton")
    support = np.full(len(joints), .4) if confidence is None else np.asarray(confidence, dtype=float)
    if support.shape != (len(joints),) or not np.isfinite(support).all():
        raise Rejected(422, "invalid_confidence")
    support = np.clip(support, 0, 1)
    exercise = manifest["exerciseId"]
    primary = {"squat": "knee", "deadlift": "hip"}.get(exercise, "elbow")
    all_angles = {s: frame_angles(joints, s) for s in ("left", "right")}
    reps = []
    for rep in manifest["reps"]:
        start, end = [int(np.ceil(rep[key] * fps / 1000 - 1e-6)) for key in ("startMs", "endMs")]
        if start < 0 or end > len(joints) or end - start < 3:
            raise Rejected(422, "rep_out_of_video")
        angles = {k: v[start:end] for k, v in all_angles[rep["side"]].items()}
        signal = angles[primary]
        low, high = int(np.argmin(signal)), int(np.argmax(signal))
        # 로우는 팔꿈치를 굽힌 때가 위, 데드리프트는 고관절을 편 때가 위다.
        top, bottom = (low, high) if exercise == "barbell-row" else (high, low)
        turn = high if exercise == "deadlift" else low
        distance = np.abs(signal - signal[turn])
        left = right = turn
        while left > 0 and distance[left - 1] <= 3:
            left -= 1
        while right + 1 < len(signal) and distance[right + 1] <= 3:
            right += 1
        before, pause = left / fps, (right - left) / fps
        total = (rep["endMs"] - rep["startMs"]) / 1000
        after = max(0, total - before - pause)
        concentric_first = exercise in ("barbell-row", "deadlift")
        symmetry = {key: np.abs(all_angles["left"][key][start:end] - all_angles["right"][key][start:end])
                    for key in ("knee", "hip", "elbow", "shoulder")}
        # 몸통 이동을 뺀 손목 경로. 바벨 자체를 검출한 좌표로 해석하지 않는다.
        segment = joints[start:end]
        pelvis = (segment[:, 1] + segment[:, 4]) / 2
        wrists = segment[:, [13, 16]] - pelvis[:, None]
        mid = wrists.mean(axis=1)
        relative = mid - mid[0]
        trunk = ((segment[:, 11] + segment[:, 14]) / 2 - pelvis)
        samples = np.unique(np.linspace(0, end - start - 1, min(90, end - start)).astype(int))
        summary = {key: {"min": rounded(v.min()), "max": rounded(v.max()), "rom": rounded(np.ptp(v)),
                         "top": rounded(v[top]), "bottom": rounded(v[bottom])} for key, v in angles.items()}
        reps.append({**rep, "primaryJoint": primary, "anglesDeg": summary,
                     "topFrame": start + top, "bottomFrame": start + bottom,
                     "topTime": rounded((start + top) / fps), "bottomTime": rounded((start + bottom) / fps),
                     "depthAngleDeg": rounded(signal.min()), "romDeg": rounded(np.ptp(signal)),
                     "depthMeters": rounded(np.ptp(pelvis[:, 1])),
                     "tempoSeconds": {"eccentric": rounded(after if concentric_first else before),
                                      "pause": rounded(pause), "concentric": rounded(before if concentric_first else after),
                                      "total": rounded(total)},
                     "tempoOrder": "concentric_pause_eccentric" if concentric_first else "eccentric_pause_concentric",
                     "handPath": {"source": "wrist_midpoint_pelvis_relative", "unit": "m",
                                  "length": rounded(np.linalg.norm(np.diff(mid, axis=0), axis=1).sum()),
                                  "horizontalExcursion": rounded(np.linalg.norm(relative[:, [0, 2]], axis=1).max()),
                                  "verticalRange": rounded(np.ptp(mid[:, 1])),
                                  "samples": [{"t": rounded((start + int(i)) / fps),
                                               "left": np.round(wrists[i, 0], 4).tolist(),
                                               "right": np.round(wrists[i, 1], 4).tolist()} for i in samples]},
                     "symmetryDeg": {k: {"mean": rounded(v.mean()), "max": rounded(v.max())} for k, v in symmetry.items()},
                     "trunkStability": {"stdDeg": rounded(np.std(angles["torso"])),
                                        "rangeDeg": rounded(np.ptp(angles["torso"])),
                                        "swayMeters": rounded(np.linalg.norm(trunk[:, [0, 2]] - trunk[0, [0, 2]], axis=1).max())},
                     "confidence": rounded(support[start:end].mean()),
                     "_evidence": {"depthDriftDeg": start + low, "romDropDeg": start + low,
                                   "tempoDriftRatio": start + turn,
                                   "symmetryMaxDeg": start + int(np.argmax(symmetry[primary])),
                                   "trunkStdDeg": start + int(np.argmax(np.abs(angles["torso"] - np.median(angles["torso"]))))}})
    if not reps:
        raise Rejected(422, "invalid_reps")
    baseline = {key: float(np.median([r[key] for r in reps[:3]])) for key in ("romDeg", "depthAngleDeg")}
    base_tempo = float(np.median([r["tempoSeconds"]["total"] for r in reps[:3]]))
    rules, source = load_rules()
    faults = []
    for i, rep in enumerate(reps):
        drift = {"depthDriftDeg": rounded(rep["depthAngleDeg"] - baseline["depthAngleDeg"]),
                 "romDropDeg": rounded(baseline["romDeg"] - rep["romDeg"]),
                 "tempoDriftRatio": rounded(rep["tempoSeconds"]["total"] / base_tempo - 1)}
        rep["fatigueDrift"] = {**drift, "comparable": i >= 3}
        values = {**drift, "symmetryMaxDeg": rep["symmetryDeg"][primary]["max"],
                  "trunkStdDeg": rep["trunkStability"]["stdDeg"]}
        evaluated, findings, rep_faults = set(), set(), []
        evidence = rep.pop("_evidence")
        for rule in rules:
            metric = rule["metric"]
            if rule["exercise_id"] not in (exercise, "*") or metric not in values:
                continue
            if (metric in drift and i < 3) or rep["confidence"] < .35:
                continue
            device_key = rule["device_key"]
            if device_key:
                evaluated.add(device_key)
            threshold = float(rule["threshold"])
            if values[metric] <= threshold:
                continue
            if device_key:
                findings.add(device_key)
            frame = evidence[metric]
            fault = {"key": rule["fault_id"], "deviceKey": device_key or None, "rep": rep["repIndex"],
                     "severity": rule["severity"], "title": rule["title_ko"], "body": rule["body_ko"],
                     "metric": metric, "value": values[metric], "threshold": threshold,
                     "confidence": rounded(min(rep["confidence"], support[frame])),
                     "evidence": [{"frame": frame, "t": rounded(frame / fps), "view": "overlay"}]}
            faults.append(fault)
            rep_faults.append(fault)
        device = set(rep["onDeviceWarnings"])
        rep.update(serverWarnings=sorted(findings), evaluatedKeys=sorted(evaluated), faults=rep_faults,
                   comparison=("not_comparable" if not evaluated else
                               "agree" if device.intersection(evaluated) == findings else "different"),
                   unassessedDeviceWarnings=sorted(device - evaluated))
    summary = {"title": "총평", "body": (f"{len(reps)}회 움직임을 살펴봤어. 표시한 구간부터 같이 확인해 보자!" if faults
                                                else f"{len(reps)}회 기록했어! 반복마다 깊이와 리듬을 비교해 봐."),
               "severity": "warning" if faults else "info", "repCount": len(reps), "faultCount": len(faults)}
    timeline = [{"t": 0, "title": summary["title"], "body": summary["body"], "severity": summary["severity"], "rep": None}]
    for rep in reps:
        tempo = rep["tempoSeconds"]
        timeline.append({"t": rep["startMs"] / 1000, "title": f"{rep['repIndex']}회 · 움직임 살펴보기",
                         "body": f"가동 범위 {rep['romDeg']:.0f}°야. 늘림 {tempo['eccentric']:.1f}초 · 멈춤 {tempo['pause']:.1f}초 · 수축 {tempo['concentric']:.1f}초였어.",
                         "severity": "info", "rep": rep["repIndex"]})
    timeline += [{"t": f["evidence"][0]["t"], "title": f["title"], "body": f["body"], "severity": f["severity"], "rep": f["rep"]} for f in faults]
    timeline[1:] = sorted(timeline[1:], key=lambda item: item["t"])
    return {"schemaVersion": 1, "exerciseId": exercise, "fps": fps, "summary": summary, "reps": reps,
            "timeline": timeline, "faults": faults,
            "consistency": {"baselineReps": min(3, len(reps)), "romStdDeg": rounded(np.std([r["romDeg"] for r in reps])),
                            "tempoCv": rounded(np.std([r["tempoSeconds"]["total"] for r in reps]) / base_tempo)},
            "rules": {"source": source, "placeholder": source == RULE_PATH.name},
            "notes": ["최대 60초 영상에 온전히 담긴 반복만 살펴봤어.",
                      "3D 추정값이야. 손목 경로는 바벨 위치와 다를 수 있어.",
                      "신뢰도는 2D 검출 지지도야. 자세 판정이 맞을 확률은 아니야.",
                      "처음 3회와 비교한 변화야. 피로의 원인을 확정하진 않아."]}
