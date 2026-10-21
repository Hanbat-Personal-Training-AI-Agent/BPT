"""Existing-constraint/legacy-warning diagnostics, explicitly not human labels."""
import time

import numpy as np

from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints
from pose_feedback.body.form_metrics_3d import SIDE, frame_metrics, rep_metrics
from eval_lift_app_fit3d import judge_py, RULES_BY_EX
from .metrics import stats


def apply_existing_gates(corrected, invalid, exercise, variant, observation_passthrough=None,
                         expired_prediction_fallback=None):
    constraints = Pose3DConstraints(bone_lengths=True, reflect_flipped_knee=exercise == "squat")
    pose, bad = corrected.copy(), invalid.copy()
    times = []
    proposed = applied = restored = expired_restored = 0
    for t in range(21, len(pose)):
        began = time.perf_counter_ns()
        pose[t], report = constraints.apply(pose[t], project_bone_lengths=variant not in ("E", "G", "H"))
        changed = np.max(np.abs(pose[t] - corrected[t]), axis=1) > 1e-12
        proposed += int(changed.sum())
        if variant in ("G", "H") and observation_passthrough is not None:
            trusted = observation_passthrough[t]
            restored += int((changed & trusted).sum())
            pose[t, trusted] = corrected[t, trusted]
        if variant in ("G", "H") and expired_prediction_fallback is not None:
            expired = expired_prediction_fallback[t]
            expired_restored += int((changed & expired).sum())
            pose[t, expired] = corrected[t, expired]
        applied += int((np.max(np.abs(pose[t] - corrected[t]), axis=1) > 1e-12).sum())
        times.append((time.perf_counter_ns() - began) / 1e6)
        bad[t, report["invalid_joints"]] = True
    timing = stats(times)
    timing.update(constraint_proposed_joint_frames=proposed,
                  restored_trusted_joint_frames=restored,
                  restored_expired_fallback_joint_frames=expired_restored,
                  constraint_applied_joint_frames=applied,
                  scope="from frame21; gates/invalid retained after trusted/expired-fallback restoration")
    return pose, bad, timing


METRIC_INPUTS = {
    "elbow_min": ("elbow",), "elbow_max": ("elbow",),
    "knee_min": ("knee",), "knee_max": ("knee",), "hip_angle_max": ("hipAngle",),
    "torso_min": ("torso",), "torso_max": ("torso",), "torso_mean": ("torso",),
    "hip_dev_min": ("hipDeviation",), "hip_dev_max": ("hipDeviation",),
    "head_dev_change_min": ("headDeviation",), "head_dev_change_max": ("headDeviation",),
    "elbow_behind_max": ("elbowBehind",),
    "first_rep_top_wrist_ahead": ("elbow", "wristAhead"),
    "torso_at_bottom": ("knee", "torso"),
    "knee_ankle_gap_ratio_min": ("hipY", "kneeAnkleGapRatio"),
    **{name: ("knee", "torso", "hipY", "shoulderY", "torsoLength") for name in
       ("hips_first_torso_rise", "hips_first_hip_rise_speed", "hips_first_shoulder_rise_speed")},
}
RULE_METRICS = {
    "pushup_hip_sag": ("hip_dev_max",), "pushup_hip_pike": ("hip_dev_min",),
    "pushup_shallow": ("elbow_min",), "pushup_no_lockout": ("elbow_max",),
    "pushup_head_drop": ("head_dev_change_max",), "pushup_head_up": ("head_dev_change_min",),
    "pushup_hand_position": ("first_rep_top_wrist_ahead",), "pushup_depth_fade": ("elbow_min",),
    "squat_hips_first": ("hips_first_torso_rise", "hips_first_hip_rise_speed", "hips_first_shoulder_rise_speed"),
    "squat_shallow": ("knee_min",), "squat_no_lockout": ("knee_max", "hip_angle_max"),
    "squat_lean_drift": ("torso_at_bottom",), "squat_depth_fade": ("knee_min",),
    "valgus_if_front": ("knee_ankle_gap_ratio_min",),
    "row_torso_swing": ("torso_min", "torso_max"), "row_standing_up": ("torso_mean",),
    "row_short_pull": ("elbow_behind_max",), "row_head_up": ("head_dev_change_min",),
}
BASE_RULES = {"pushup_shallow", "squat_shallow", "row_standing_up", "row_short_pull"}
TREND_RULES = {"pushup_depth_fade", "squat_lean_drift", "squat_depth_fade"}
MAX_RULES = {"pushup_no_lockout", "squat_no_lockout"}


def supported_rule(rule, index, metrics):
    """Separate warmup/history readiness from unavailable current/history data."""
    if rule == "pushup_hand_position" and index != 0:
        return False, "not_applicable"
    if rule in BASE_RULES and index < 3 or rule in TREND_RULES and index < 5:
        return False, "history_warmup"
    keys = RULE_METRICS[rule]
    required = [index]
    if rule in BASE_RULES:
        required += list(range(3))
    elif rule in TREND_RULES:
        required += list(range(3)) + list(range(index - 2, index + 1))
    elif rule in MAX_RULES:
        required += list(range(index))
    ok = all(all(key in metrics[i] and np.isfinite(metrics[i][key]) for key in keys)
             for i in required)
    return ok, "available" if ok else "metric_or_history_unavailable"


def score_warning_proxies(o, reference, app_pose_crop, invalid, *, start=90):
    # This frozen existing mirror predates current gates in other branches.
    # Report its identity and limitations, never call this clinical FP/FN.
    side = "left" if o.keypoints[21:81, [5, 7, 9, 11, 13, 15], 2].mean() >= \
                     o.keypoints[21:81, [6, 8, 10, 12, 14, 16], 2].mean() else "right"
    sh, hp = (5, 11) if side == "left" else (6, 12)
    p = (app_pose_crop - app_pose_crop[:, :1]) * reference.metres_per_crop_unit[:, None, None]
    p[invalid] = np.nan
    up = np.array([0., -1., 0.])
    k = SIDE[side]
    required_joints = {
        "elbow": [k[x] for x in ("shoulder", "elbow", "wrist")],
        "knee": [k[x] for x in ("hip", "knee", "ankle")],
        "hipAngle": [k[x] for x in ("shoulder", "hip", "knee")],
        "torso": [0, 8, 1, 4], "hipDeviation": [0, 8, 3, 6],
        "headDeviation": [10, 0, 8], "elbowBehind": [k["elbow"], 0, 8, 1, 4],
        "wristAhead": [k["shoulder"], k["elbow"], k["wrist"], 0, 8],
        "kneeAnkleGapRatio": [1, 4, 2, 5, 3, 6],
    }
    frames, truth = [], []
    for t in range(len(p)):
        d = o.keypoints[t, sh, :2] - o.keypoints[t, hp, :2]
        two = dict(hipY=float(o.keypoints[t, hp, 1]), shoulderY=float(o.keypoints[t, sh, 1]),
                   torsoLength=float(np.linalg.norm(d)))
        if not all(np.isfinite(v) for v in two.values()) or two["torsoLength"] <= 1e-8:
            two = {key: None for key in two}
        f, g = frame_metrics(p[t], side, up, two), frame_metrics(reference.joints_m[t], side, up, two)
        for key, joints in required_joints.items():
            if invalid[t, joints].any():
                f[key] = None
        f["frame"] = g["frame"] = t
        frames.append(f)
        truth.append(g)
    intervals = [(s, e) for s, e in reference.rep_segments if s >= start and e < len(p) - 1 and e > s]
    measures, gt_measures = [], []
    for i, (s, e) in enumerate(intervals):
        for source, destination in ((frames, measures), (truth, gt_measures)):
            portion = source[s:e + 1]
            m = rep_metrics(portion, o.exercise, is_first_rep=i == 0)
            # Suppress unsupported metrics before they can seed rule history.
            for name, inputs in METRIC_INPUTS.items():
                coverage = np.mean([all(f[key] is not None and np.isfinite(f[key]) for key in inputs)
                                    for f in portion])
                if coverage < .8:
                    m.pop(name, None)
            destination.append(m)
    fired, gt_fired = judge_py(measures, o.exercise), judge_py(gt_measures, o.exercise)
    by_rule, assessed_masks = {}, []
    for key in RULES_BY_EX[o.exercise]:
        support = [supported_rule(key, i, measures) for i in range(len(intervals))]
        gt_support = [supported_rule(key, i, gt_measures) for i in range(len(intervals))]
        assessed = [a[0] and b[0] for a, b in zip(support, gt_support)]
        assessed_masks.append(assessed)
        pairs = [(key in p_, key in g_) for p_, g_, ok in zip(fired, gt_fired, assessed) if ok]
        warmup = sum(a[1] == "history_warmup" for a in support)
        not_applicable = sum(a[1] == "not_applicable" for a in support)
        by_rule[key] = dict(reps=len(intervals), assessed_reps=len(pairs),
                           abstained_reps=len(intervals) - len(pairs) - warmup - not_applicable,
                           history_warmup_reps=warmup, not_applicable_reps=not_applicable,
                           predicted_fires=sum(p_ for p_, _ in pairs),
                           gt_mirror_fires=sum(g_ for _, g_ in pairs),
                           disagreement_fp_proxy=sum(p_ and not g_ for p_, g_ in pairs),
                           disagreement_fn_proxy=sum(g_ and not p_ for p_, g_ in pairs))
    any_assessed = int(np.any(np.asarray(assessed_masks), axis=0).sum()) if intervals else 0
    return dict(reps=len(intervals), assessed_reps=any_assessed, abstained_reps=len(intervals) - any_assessed,
                rep_coverage_definition="at least one rule assessed; use per-rule denominators for FP/FN",
                assessed_rule_reps=sum(x["assessed_reps"] for x in by_rule.values()),
                abstained_rule_reps=sum(x["abstained_reps"] for x in by_rule.values()),
                history_warmup_rule_reps=sum(x["history_warmup_reps"] for x in by_rule.values()),
                not_applicable_rule_reps=sum(x["not_applicable_reps"] for x in by_rule.values()),
                by_rule=by_rule,
                human_error_labels=False,
                note="Frozen legacy judge_py e05f1ac side-view mirror, not full current app gates. "
                     "GT rule disagreement and normal-demo fire proxies only; withheld warnings are abstentions, never TNs. "
                     "Per-rule metric and history support uses >=80% finite required-joint coverage; "
                     "unsupported metrics cannot seed baselines/trends. First-rep-only and warmup rules are separate. "
                     "Both arms use observed 2D auxiliary heights; only 3D is replaced by score-reference joints.")
