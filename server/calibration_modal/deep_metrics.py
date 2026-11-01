"""중력 정렬 H36M-17 좌표의 반복별 지표와 근거. 모델·영상 없이 검증한다."""
import csv
from pathlib import Path

import numpy as np

from checks import Rejected

RULE_COLUMNS = ("fault_id", "exercise_id", "metric", "threshold", "severity", "title_ko", "body_ko", "device_key")
RULE_PATH = Path(__file__).with_name("deep_rules.csv")
CATALOG_PATH = Path(__file__).resolve().parent.parent.parent / "docs/coaching/fault_catalog.csv"


TEAM_COLUMNS = ("exercise", "fault_id", "name_ko", "severity", "phase", "signal",
                "metric_definition", "threshold_strict", "threshold_standard", "threshold_relaxed",
                "measurable_now", "needs", "cue_ko", "sources")


def load_rule_catalog():
    path = CATALOG_PATH if CATALOG_PATH.is_file() else RULE_PATH
    with path.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        columns = set(reader.fieldnames or [])
        if set(TEAM_COLUMNS).issubset(columns):
            rows = list(reader)
            if any(not all(isinstance(row.get(key), str) for key in TEAM_COLUMNS) for row in rows):
                raise Rejected(422, "invalid_fault_catalog")
            # Team thresholds are expressions with units, variants and prerequisites. Never
            # turn P:R>15deg into a threshold for our different trunk standard deviation.
            return [], path.name, [{"key": row["fault_id"], "exercise": row["exercise"],
                                     "reason": "metric_contract_not_implemented"} for row in rows]
        if not set(RULE_COLUMNS).issubset(columns):
            raise Rejected(422, "invalid_fault_catalog")
        rules = list(reader)
    try:
        for rule in rules:
            assert rule["severity"] in ("info", "warning", "critical")
            assert np.isfinite(float(rule["threshold"]))
            assert all(isinstance(rule[key], str) for key in RULE_COLUMNS)
    except (ValueError, TypeError, AssertionError):
        raise Rejected(422, "invalid_fault_catalog") from None
    return rules, path.name, []


def load_rules():
    rules, source, _ = load_rule_catalog()
    return rules, source


# Exact reviewed contracts only. Do not parse arbitrary threshold expressions.
DEPTH_FADE_CONTRACTS = {
    "squat_depth_fade": ("squat", "D=mean(최근3회 k_min)-mean(처음3회 k_min); 최소 6회; 계획 ROM 변경 제외", "P:D>10deg", 10),
    "pushup_depth_fade": ("pushup", "D=mean(최근3회 e_min)-mean(처음3회 e_min); 최소 6회", "P:D>15deg", 15),
}


def catalog_measurements(reps, exercise, source):
    if source != CATALOG_PATH.name or not CATALOG_PATH.is_file():
        return []
    with CATALOG_PATH.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    output = []
    for row in rows:
        contract = DEPTH_FADE_CONTRACTS.get(row.get("fault_id"))
        if not contract or (row.get("exercise"), row.get("metric_definition"), row.get("threshold_standard")) != contract[:3] or exercise != contract[0]:
            continue
        enough = len(reps) >= 6
        chosen = reps[:3] + reps[-3:] if enough else []
        supported = enough and all(r["confidence"] >= .35 and finite_number(r.get("depthAngleDeg")) and r.get("metricValidity", {}).get("depthAngleDeg", {}).get("assessment") == "available" for r in chosen)
        reasons = ["same_view_variant_and_planned_rom_not_confirmed"]
        if not enough:
            reasons.append("requires_six_reps")
        elif not supported:
            reasons.append("invalid_geometry" if any(not finite_number(r.get("depthAngleDeg")) for r in chosen)
                           else "low_detection_support")
        output.append({"key": row["fault_id"], "metric": "recent3_mean_min_angle_minus_first3_mean_min_angle",
                       "value": rounded(np.mean([r["depthAngleDeg"] for r in reps[-3:]]) -
                                        np.mean([r["depthAngleDeg"] for r in reps[:3]])) if supported else None,
                       "unit": "deg", "threshold": contract[3], "thresholdProfile": "standard",
                       "assessment": "withheld", "reasons": reasons,
                       "baselineReps": [r["repIndex"] for r in reps[:3]] if enough else [],
                       "comparisonReps": [r["repIndex"] for r in reps[-3:]] if enough else []})
    return output


def angle(a, b, c):
    u, v = a - b, c - b
    norm = np.linalg.norm(u, axis=-1) * np.linalg.norm(v, axis=-1)
    # A finite collapsed chain is invalid only for its dependent measurements.
    # Never remove the bad sample and recompute an attractive finite-subset ROM.
    cosine = np.full_like(norm, np.nan, dtype=float)
    np.divide(np.sum(u * v, axis=-1), norm, out=cosine, where=norm >= 1e-8)
    return np.degrees(np.arccos(np.clip(cosine, -1, 1)))


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


COCO_ANGLE_JOINTS = {
    "left": {"knee": [11, 13, 15], "hip": [5, 11, 13], "elbow": [5, 7, 9], "shoulder": [11, 5, 7]},
    "right": {"knee": [12, 14, 16], "hip": [6, 12, 14], "elbow": [6, 8, 10], "shoulder": [12, 6, 8]},
}
TRUNK_JOINTS = [5, 6, 11, 12]


def metric_support(joint_support, tracked, frame_support, start, end, joints):
    """Conservative support for every required joint/frame, not an accuracy probability."""
    reasons = []
    minimum = None
    if joint_support is None:
        reasons.append("joint_support_missing")
    else:
        minimum = float(joint_support[start:end, joints].min())
        if minimum < .35:
            reasons.append("low_joint_support")
    if tracked is None:
        reasons.append("tracking_mask_missing")
    elif not tracked[start:end].all():
        reasons.append("tracking_interpolated")
    if np.any(frame_support[start:end] < .35):
        reasons.append("low_detection_support")
    return {"assessment": "withheld" if reasons else "available", "reasons": reasons,
            "minimumJointSupport": None if minimum is None else round(minimum, 3)}


def rep_metric_support(joint_support, tracked, frame_support, start, end, side, primary):
    groups = dict(COCO_ANGLE_JOINTS[side], torso=TRUNK_JOINTS)
    groups.update(depthAngleDeg=groups[primary], romDeg=groups[primary], tempoSeconds=groups[primary],
                  depthMeters=[11, 12], handPath=[9, 10, 11, 12], trunkStdDeg=TRUNK_JOINTS,
                  symmetryMaxDeg=COCO_ANGLE_JOINTS["left"][primary] + COCO_ANGLE_JOINTS["right"][primary])
    # Entire spans include BOTH ROM extrema and all samples used in tempo/path/std metrics.
    return {name: metric_support(joint_support, tracked, frame_support, start, end, indices)
            for name, indices in groups.items()}


def rounded(value):
    return round(float(value), 3) if finite_number(value) else None


def finite_number(value):
    return isinstance(value, (int, float, np.number)) and bool(np.isfinite(value))


def whole_value(values, operation):
    """Use the entire declared span, or no value; never drop invalid samples."""
    values = np.asarray(values, dtype=float)
    return float(operation(values)) if values.size and np.isfinite(values).all() else None


def geometry_support(support, valid):
    if valid:
        return support
    return {**support, "assessment": "withheld", "reasons": [*support["reasons"], "invalid_geometry"]}


def difference(a, b):
    return rounded(a - b) if finite_number(a) and finite_number(b) else None


def metrics(joints, fps, manifest, confidence=None, joint_confidence=None, tracked_mask=None):
    """world(y 위), 미터. confidence는 프레임별 2D 검출 지지도로 정확도 확률이 아니다."""
    joints = np.asarray(joints, dtype=float)
    if (joints.ndim != 3 or joints.shape[1:] != (17, 3) or not np.isfinite(joints).all()
            or not np.isfinite(fps) or fps <= 0):
        raise Rejected(422, "invalid_skeleton")
    joint_support = None if joint_confidence is None else np.asarray(joint_confidence, dtype=float)
    if joint_support is not None:
        if joint_support.shape != (len(joints), 17) or not np.isfinite(joint_support).all():
            raise Rejected(422, "invalid_joint_confidence")
        joint_support = np.clip(joint_support, 0, 1)
    tracked = None if tracked_mask is None else np.asarray(tracked_mask)
    if tracked is not None and (tracked.shape != (len(joints),) or tracked.dtype != np.bool_):
        raise Rejected(422, "invalid_tracking_mask")
    support = (np.zeros(len(joints)) if joint_support is None else joint_support.mean(axis=1)) if confidence is None else np.asarray(confidence, dtype=float)
    if support.shape != (len(joints),) or not np.isfinite(support).all():
        raise Rejected(422, "invalid_confidence")
    support = np.clip(support, 0, 1)
    exercise = manifest["exerciseId"]
    primary = {"squat": "knee", "deadlift": "hip"}.get(exercise, "elbow")
    all_angles = {s: frame_angles(joints, s) for s in ("left", "right")}
    if not any(np.isfinite(values).any() for side in all_angles.values() for values in side.values()):
        raise Rejected(422, "invalid_skeleton")
    reps = []
    for rep in manifest["reps"]:
        start, end = [int(np.ceil(rep[key] * fps / 1000 - 1e-6)) for key in ("startMs", "endMs")]
        if start < 0 or end > len(joints) or end - start < 3:
            raise Rejected(422, "rep_out_of_video")
        angles = {k: v[start:end] for k, v in all_angles[rep["side"]].items()}
        signal = angles[primary]
        valid_angles = {key: bool(np.isfinite(value).all()) for key, value in angles.items()}
        primary_valid = valid_angles[primary]
        low = high = top = bottom = turn = None
        before = pause = after = total = None
        if primary_valid:
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
        symmetry_valid = {key: bool(np.isfinite(value).all()) for key, value in symmetry.items()}
        # 몸통 이동을 뺀 손목 경로. 바벨 자체를 검출한 좌표로 해석하지 않는다.
        segment = joints[start:end]
        pelvis = (segment[:, 1] + segment[:, 4]) / 2
        wrists = segment[:, [13, 16]] - pelvis[:, None]
        mid = wrists.mean(axis=1)
        relative = mid - mid[0]
        trunk = ((segment[:, 11] + segment[:, 14]) / 2 - pelvis)
        hand_valid = all(np.isfinite(all_angles[side]["elbow"][start:end]).all() for side in all_angles)
        samples = np.unique(np.linspace(0, end - start - 1, min(90, end - start)).astype(int))
        summary = {key: {"min": rounded(whole_value(v, np.min)), "max": rounded(whole_value(v, np.max)),
                         "rom": rounded(whole_value(v, np.ptp)),
                         "top": rounded(v[top]) if valid_angles[key] and top is not None else None,
                         "bottom": rounded(v[bottom]) if valid_angles[key] and bottom is not None else None}
                   for key, v in angles.items()}
        validity = rep_metric_support(joint_support, tracked, support, start, end, rep["side"], primary)
        geometry = dict(valid_angles, depthAngleDeg=primary_valid, romDeg=primary_valid, tempoSeconds=primary_valid,
                        handPath=hand_valid, trunkStdDeg=valid_angles["torso"], symmetryMaxDeg=symmetry_valid[primary])
        validity = {key: geometry_support(value, geometry.get(key, True)) for key, value in validity.items()}
        if not primary_valid:
            # Other angles may remain usable, but their primary-selected phases do not.
            validity["phase"] = {**validity[primary], "reasons": list(validity[primary]["reasons"])}
        frame_of = lambda index: start + index if index is not None else None
        reps.append({**rep, "primaryJoint": primary, "anglesDeg": summary,
                     "metricValidity": validity,
                     "topFrame": frame_of(top), "bottomFrame": frame_of(bottom),
                     "topTime": rounded(frame_of(top) / fps) if top is not None else None,
                     "bottomTime": rounded(frame_of(bottom) / fps) if bottom is not None else None,
                     "depthAngleDeg": rounded(whole_value(signal, np.min)), "romDeg": rounded(whole_value(signal, np.ptp)),
                     "depthMeters": rounded(np.ptp(pelvis[:, 1])),
                     "tempoSeconds": {"eccentric": rounded(after if concentric_first else before),
                                      "pause": rounded(pause), "concentric": rounded(before if concentric_first else after),
                                      "total": rounded(total)},
                     "tempoOrder": "concentric_pause_eccentric" if concentric_first else "eccentric_pause_concentric",
                     "handPath": {"source": "wrist_midpoint_pelvis_relative", "unit": "m",
                                  "length": rounded(np.linalg.norm(np.diff(mid, axis=0), axis=1).sum()) if hand_valid else None,
                                  "horizontalExcursion": rounded(np.linalg.norm(relative[:, [0, 2]], axis=1).max()) if hand_valid else None,
                                  "verticalRange": rounded(np.ptp(mid[:, 1])) if hand_valid else None,
                                  "samples": [{"t": rounded((start + int(i)) / fps),
                                               "left": np.round(wrists[i, 0], 4).tolist(),
                                               "right": np.round(wrists[i, 1], 4).tolist()} for i in samples] if hand_valid else []},
                     "symmetryDeg": {k: {"mean": rounded(whole_value(v, np.mean)), "max": rounded(whole_value(v, np.max))} for k, v in symmetry.items()},
                     "trunkStability": {"stdDeg": rounded(whole_value(angles["torso"], np.std)),
                                        "rangeDeg": rounded(whole_value(angles["torso"], np.ptp)),
                                        "swayMeters": rounded(np.linalg.norm(trunk[:, [0, 2]] - trunk[0, [0, 2]], axis=1).max()) if valid_angles["torso"] else None},
                     "confidence": rounded(support[start:end].mean()),
                     "_evidence": {"depthDriftDeg": frame_of(low), "romDropDeg": frame_of(low),
                                   "tempoDriftRatio": frame_of(turn),
                                   "symmetryMaxDeg": start + int(np.argmax(symmetry[primary])) if symmetry_valid[primary] else None,
                                   "trunkStdDeg": start + int(np.argmax(np.abs(angles["torso"] - np.median(angles["torso"])))) if valid_angles["torso"] else None}})
    if not reps:
        raise Rejected(422, "invalid_reps")
    if not any(finite_number(a["min"]) for r in reps for a in r["anglesDeg"].values()):
        raise Rejected(422, "invalid_skeleton")
    baseline = {key: whole_value([r[key] for r in reps[:3]], np.median) for key in ("romDeg", "depthAngleDeg")}
    base_tempo = whole_value([r["tempoSeconds"]["total"] for r in reps[:3]], np.median)
    rules, source, unassessed_catalog = load_rule_catalog()
    faults = []
    drift_sources = {"depthDriftDeg": "depthAngleDeg", "romDropDeg": "romDeg", "tempoDriftRatio": "tempoSeconds"}
    baseline_supported = {metric: all(r["metricValidity"][source]["assessment"] == "available" for r in reps[:3])
                          for metric, source in drift_sources.items()}
    baseline_geometry = {"depthDriftDeg": finite_number(baseline["depthAngleDeg"]),
                         "romDropDeg": finite_number(baseline["romDeg"]), "tempoDriftRatio": finite_number(base_tempo)}
    for i, rep in enumerate(reps):
        drift = {"depthDriftDeg": difference(rep["depthAngleDeg"], baseline["depthAngleDeg"]),
                 "romDropDeg": difference(baseline["romDeg"], rep["romDeg"]),
                 "tempoDriftRatio": rounded(rep["tempoSeconds"]["total"] / base_tempo - 1)
                     if finite_number(rep["tempoSeconds"]["total"]) and finite_number(base_tempo) and base_tempo > 0 else None}
        for metric, metric_source in drift_sources.items():
            original = rep["metricValidity"][metric_source]
            reasons = list(original["reasons"])
            if i < 3:
                reasons.append("requires_baseline_reps")
            elif not baseline_supported[metric]:
                reasons.append("low_baseline_support")
                if not baseline_geometry[metric]:
                    reasons.append("invalid_baseline_geometry")
            observed_minima = [original["minimumJointSupport"]] + [r["metricValidity"][metric_source]["minimumJointSupport"] for r in reps[:3]]
            minimum = min(observed_minima) if all(v is not None for v in observed_minima) else None
            rep["metricValidity"][metric] = {**original, "assessment": "withheld" if reasons else "available", "reasons": reasons,
                                             "minimumJointSupport": minimum}
        rep["fatigueDrift"] = {**drift, "comparable": all(rep["metricValidity"][k]["assessment"] == "available" for k in drift)}
        values = {**drift, "symmetryMaxDeg": rep["symmetryDeg"][primary]["max"],
                  "trunkStdDeg": rep["trunkStability"]["stdDeg"]}
        rep["validity"] = {"confidenceSource": "missing" if confidence is None and joint_support is None else "2d_detection_support",
                           "detectionSupport": "insufficient" if rep["confidence"] < .35 else "available",
                           "reasons": (["missing_detection_support"] if confidence is None and joint_support is None else
                                       ["low_detection_support"] if rep["confidence"] < .35 else [])}
        if i >= 3 and not all(baseline_supported.values()):
            rep["validity"]["reasons"].append("low_baseline_support")
        if any("invalid_geometry" in v["reasons"] for v in rep["metricValidity"].values()):
            rep["validity"]["reasons"].append("invalid_geometry")
        if i >= 3 and not all(baseline_geometry.values()):
            rep["validity"]["reasons"].append("invalid_baseline_geometry")
        if joint_support is None:
            rep["validity"]["reasons"].append("joint_support_missing")
        if tracked is None:
            rep["validity"]["reasons"].append("tracking_mask_missing")
        elif not tracked[int(np.ceil(rep["startMs"] * fps / 1000 - 1e-6)):int(np.ceil(rep["endMs"] * fps / 1000 - 1e-6))].all():
            rep["validity"]["reasons"].append("tracking_interpolated")
        evaluated, findings, rep_faults = set(), set(), []
        evidence = rep.pop("_evidence")
        for rule in rules:
            metric = rule["metric"]
            if rule["exercise_id"] not in (exercise, "*") or metric not in values:
                continue
            if (rep["metricValidity"][metric]["assessment"] != "available"
                    or not finite_number(values[metric]) or evidence[metric] is None):
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
                     "confidence": rounded(min(rep["confidence"], support[frame], rep["metricValidity"][metric]["minimumJointSupport"])),
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
        if "invalid_geometry" in rep["validity"]["reasons"] and any(
                rep["metricValidity"][k]["assessment"] == "withheld" for k in ("romDeg", "tempoSeconds")):
            body = "관절값을 계산할 수 없는 구간이 있어 해당 측정은 보류했어. 다른 항목은 각각 확인해 줘."
        elif any(rep["metricValidity"][k]["assessment"] == "withheld" for k in ("romDeg", "tempoSeconds")):
            body = "필요한 관절이나 추적 지지도가 부족해 자세 판정을 보류했어. 상세 각도와 시간은 참고용 추정값이야."
        else:
            body = (f"추정 가동 범위 {rep['romDeg']:.0f}°야. 늘림 {tempo['eccentric']:.1f}초 · 멈춤 {tempo['pause']:.1f}초 · 수축 {tempo['concentric']:.1f}초로 추정했어.")
            if "invalid_baseline_geometry" in rep["validity"]["reasons"]:
                body += " 처음 3회의 관절값을 계산할 수 없어 반복 간 변화 판정은 보류했어."
            elif "low_baseline_support" in rep["validity"]["reasons"]:
                body += " 처음 3회의 검출 지지도가 부족해 반복 간 변화 판정은 보류했어."
        timeline.append({"t": rep["startMs"] / 1000, "title": f"{rep['repIndex']}회 · 움직임 살펴보기",
                         "body": body,
                         "severity": "info", "rep": rep["repIndex"]})
    timeline += [{"t": f["evidence"][0]["t"], "title": f["title"], "body": f["body"], "severity": f["severity"], "rep": f["rep"]} for f in faults]
    timeline[1:] = sorted(timeline[1:], key=lambda item: item["t"])
    return {"schemaVersion": 1, "exerciseId": exercise, "fps": fps, "summary": summary, "reps": reps,
            "timeline": timeline, "faults": faults, "unassessedCatalog": unassessed_catalog,
            "catalogMeasurements": catalog_measurements(reps, exercise, source),
            "consistency": {"baselineReps": min(3, len(reps)), "romStdDeg": rounded(whole_value([r["romDeg"] for r in reps], np.std)),
                            "tempoCv": rounded(whole_value([r["tempoSeconds"]["total"] for r in reps], np.std) / base_tempo)
                                if finite_number(base_tempo) and base_tempo > 0 and all(finite_number(r["tempoSeconds"]["total"]) for r in reps) else None},
            "rules": {"source": source, "placeholder": source == RULE_PATH.name},
            "notes": ["최대 60초 영상에 온전히 담긴 반복만 살펴봤어.",
                      "3D 추정값이야. 손목 경로는 바벨 위치와 다를 수 있어.",
                      "신뢰도는 2D 검출 지지도야. 자세 판정이 맞을 확률은 아니야.",
                      "회색 골격은 관절이나 추적 지지도가 부족한 부분이야. 지표마다 판정 가능 여부가 달라.",
                      "처음 3회와 비교한 변화야. 피로의 원인을 확정하진 않아."] +
                     (["코칭 카탈로그의 지표·변형 조건이 아직 연결되지 않아 해당 판정은 보류했어."] if unassessed_catalog else []) +
                     (["계산할 수 없는 관절 구간이 있어 해당 측정값은 보류했어. 보류한 항목은 정상이나 이상으로 확정하지 않았어."]
                      if any("invalid_geometry" in r["validity"]["reasons"] for r in reps) else [])}
