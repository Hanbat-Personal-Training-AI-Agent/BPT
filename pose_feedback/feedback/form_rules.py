"""Python mirror of FormWarningTracker.judge() (ios/Runner/NativePose/Evaluators/FormWarnings.swift) with the named
threshold presets of FormRulePreset: pose_feedback/rules/<name>.json (values override app_default.json; "off" lists rule
keys that never fire). Parity with Swift: tests/fixtures/form_rules_cases.json (scripts/make_form_rules_fixture.py,
FormRulePresetTests). Used by the rules-calib evaluation to re-judge per-rep metrics with other thresholds.
"""
import json
import math
from pathlib import Path

import numpy as np

RULES_DIR = Path(__file__).resolve().parents[1] / "rules"

# FormWarningTracker.rules order (keys only), the order judge() returns.
RULE_ORDER = {
    "pushup": ["setup_side_view", "pushup_hip_sag", "pushup_hip_pike", "pushup_shallow", "pushup_no_lockout",
               "pushup_head_drop", "pushup_head_up", "pushup_hand_position", "pushup_depth_fade",
               "pushup_depth_abs", "pushup_lockout_abs"],
    "squat": ["squat_hips_first", "squat_knee_valgus", "squat_shallow", "squat_heel_rise", "squat_no_lockout",
              "squat_lean_drift", "squat_depth_fade", "squat_depth_abs", "squat_torso_lean"],
    "barbell_row": ["setup_side_view", "row_torso_swing", "row_standing_up", "row_short_pull", "row_shrug", "row_head_up",
                    "row_hinge_shallow", "row_knees_locked", "row_knees_bent", "row_pull_high", "row_pull_low",
                    "row_uneven_pull", "row_elbow_flare", "row_wrist_lead", "row_straight_arm", "row_short_pull_abs"],
}

# rules-calib rule -> (config field, metric, op): fires when the field is set and metric op threshold.
NEW_RULES = {
    "pushup": [("pushup_depth_abs", "pushUp.depthAbsUpperArmInclineDegrees", "upper_arm_incline_max", "<"),
               ("pushup_lockout_abs", "pushUp.lockoutAbsElbowDegrees", "elbow_max", "<")],
    "squat": [("squat_depth_abs", "squat.depthAbsThighInclineDegrees", "thigh_incline_min", ">"),
              ("squat_torso_lean", "squat.torsoLeanOverTibiaDegrees", "torso_minus_tibia_at_bottom", ">")],
    "barbell_row": [("row_hinge_shallow", "row.hingeShallowTorsoDegrees", "torso_mean", "<"),
                    ("row_knees_locked", "row.kneesLockedDegrees", "knee_max", ">"),
                    ("row_knees_bent", "row.kneesBentDegrees", "knee_min", "<"),
                    ("row_pull_high", "row.pullHighWristTrunk", "pull_peak_wrist_trunk", ">"),
                    ("row_pull_low", "row.pullLowWristTrunk", "pull_peak_wrist_trunk", "<"),
                    ("row_uneven_pull", "row.unevenPullRatio", "pull_peak_asym", ">"),
                    ("row_elbow_flare", "row.elbowFlareDegrees", "pull_peak_flare", ">"),
                    ("row_wrist_lead", "row.wristLeadDegrees", "pull_peak_forearm_tilt", ">"),
                    ("row_straight_arm", "row.straightArmElbowDegrees", "elbow_min", ">"),
                    ("row_short_pull_abs", "row.shortPullAbsBehind", "elbow_behind_max", "<")],
}


def load_preset(name_or_path):
    """(values, off) for a preset name in pose_feedback/rules or a JSON path; values are merged over app_default."""
    base = json.loads((RULES_DIR / "app_default.json").read_text())
    p = Path(name_or_path)
    doc = json.loads((p if p.suffix == ".json" else RULES_DIR / f"{name_or_path}.json").read_text())
    values = dict(base["values"])
    values.update(doc.get("values", {}))
    return values, set(doc.get("off", []))


def _median(v):
    return float(np.median(v)) if len(v) else None


def _wrap(d):
    r = math.remainder(d, 360.0)
    return 180.0 if r == -180.0 else r


def judge_rep(m, history, exercise, values, off=(), side_view=None, baseline_reps=3, trend_reps=3, front_fraction=0.5):
    """Keys for one rep in rule order. side_view: the row's session gate (None = undecided -> per-rep front fraction)."""
    fired = set()

    def fire(key, cond):
        if cond and key not in off:
            fired.add(key)

    def over(n, t):
        return n in m and m[n] > t

    def under(n, t):
        return n in m and m[n] < t

    def base(n):
        if len(history) < baseline_reps:
            return None
        return _median([h[n] for h in history[:baseline_reps] if n in h])

    def over_base(n, t):
        b = base(n)
        return n in m and b is not None and m[n] - b > t

    def below_max(n, t):
        if n not in m:
            return False
        return max([h[n] for h in history if n in h] + [m[n]]) - m[n] > t

    def trend(n, t):
        al = list(history) + [m]
        if len(al) < 2 * trend_reps:
            return False
        f, l_ = [x[n] for x in al[:trend_reps] if n in x], [x[n] for x in al[-trend_reps:] if n in x]
        return len(f) == trend_reps and len(l_) == trend_reps and sum(l_) / trend_reps - sum(f) / trend_reps > t

    gate = (side_view if exercise == "barbell_row" else None)
    sv = gate if gate is not None else m.get("front_view_fraction", 0.0) < front_fraction
    first = len(history) == 0
    v = values
    if exercise == "pushup":
        fire("setup_side_view", first and not sv)
        if sv:
            fire("pushup_hip_sag", over("hip_dev_max", v["pushUp.hipSagDeviation"]))
            fire("pushup_hip_pike", under("hip_dev_min", -v["pushUp.hipPikeDeviation"]))
            fire("pushup_shallow", over_base("elbow_min", v["pushUp.shallowOverBaselineDegrees"]))
            fire("pushup_no_lockout", below_max("elbow_max", v["pushUp.noLockoutBelowSetMaxDegrees"]))
            fire("pushup_head_drop", over("head_dev_change_max", v["pushUp.headDropDeviation"]))
            fire("pushup_head_up", under("head_dev_change_min", -v["pushUp.headUpDeviation"]))
            if "first_rep_top_wrist_ahead" in m:
                a = m["first_rep_top_wrist_ahead"]
                fire("pushup_hand_position", a > v["pushUp.handForwardRatio"] or a < -v["pushUp.handBackwardRatio"])
            fire("pushup_depth_fade", trend("elbow_min", v["pushUp.depthFadeDegrees"]))
            _new(fire, m, v, "pushup")
    elif exercise == "squat":
        if sv:
            if all(q in m for q in ("hips_first_torso_rise", "hips_first_hip_rise_speed", "hips_first_shoulder_rise_speed")):
                fire("squat_hips_first", m["hips_first_torso_rise"] > v["squat.hipsFirstTorsoRiseDegrees"]
                     and m["hips_first_hip_rise_speed"] > m["hips_first_shoulder_rise_speed"])
            fire("squat_shallow", over_base("knee_min", v["squat.shallowOverBaselineDegrees"]))
            fire("squat_no_lockout", below_max("knee_max", v["squat.noLockoutBelowSetMaxDegrees"])
                 or below_max("hip_angle_max", v["squat.noLockoutBelowSetMaxDegrees"]))
            fire("squat_lean_drift", trend("torso_at_bottom", v["squat.leanDriftDegrees"]))
            fire("squat_depth_fade", trend("knee_min", v["squat.depthFadeDegrees"]))
            _new(fire, m, v, "squat")
        else:
            fire("squat_knee_valgus", under("knee_ankle_gap_ratio_min", v["squat.valgusKneeAnkleGapRatio"]))
    elif exercise == "barbell_row":
        fire("setup_side_view", first and not sv)
        if sv:
            if "torso_min" in m and "torso_max" in m:
                fire("row_torso_swing", m["torso_max"] - m["torso_min"] > v["row.torsoSwingRangeDegrees"])
            b = base("torso_mean")
            if "torso_mean" in m and b is not None:
                fire("row_standing_up", _wrap(b - m["torso_mean"]) > v["row.standingUpDegrees"])
            b = base("elbow_behind_max")
            if "elbow_behind_max" in m and b is not None:
                fire("row_short_pull", b - m["elbow_behind_max"] > v["row.shortPullBelowBaseline"])
            fire("row_head_up", under("head_dev_change_min", -v["row.headUpDeviation"]))
            _new(fire, m, v, "barbell_row")
    return [k for k in RULE_ORDER[exercise] if k in fired]


def _new(fire, m, v, exercise):
    for key, field, metric, op in NEW_RULES[exercise]:
        t = v.get(field)
        if t is not None and metric in m:
            fire(key, m[metric] < t if op == "<" else m[metric] > t)


def judge(ms, exercise, values, off=(), side_view=None, **kw):
    """judge_rep over a set (history = the earlier reps). side_view: None, a bool, or a list (one per rep)."""
    return [judge_rep(m, ms[:i], exercise, values, off, side_view[i] if isinstance(side_view, list) else side_view, **kw)
            for i, m in enumerate(ms)]
