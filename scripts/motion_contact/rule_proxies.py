"""Existing-constraint/legacy-warning diagnostics, explicitly not human labels."""
import time

import numpy as np

from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints
from pose_feedback.body.form_metrics_3d import frame_metrics, rep_metrics
from eval_lift_app_fit3d import judge_py, RULES_BY_EX
from .metrics import stats


def apply_existing_gates(corrected, invalid, exercise, variant):
    constraints = Pose3DConstraints(bone_lengths=variant not in ("E", "G", "H"),
                                    reflect_flipped_knee=exercise == "squat")
    pose, bad = corrected.copy(), invalid.copy()
    times = []
    for t in range(21, len(pose)):
        began = time.perf_counter_ns()
        pose[t], report = constraints.apply(pose[t])
        times.append((time.perf_counter_ns() - began) / 1e6)
        bad[t, report["invalid_joints"]] = True
    return pose, bad, stats(times)


def score_warning_proxies(o, reference, app_pose_crop, invalid, *, start=90):
    # This frozen existing mirror predates current gates in other branches.
    # Report its identity and limitations, never call this clinical FP/FN.
    side = "left" if o.keypoints[21:81, [5, 7, 9, 11, 13, 15], 2].mean() >= \
                     o.keypoints[21:81, [6, 8, 10, 12, 14, 16], 2].mean() else "right"
    sh, hp = (5, 11) if side == "left" else (6, 12)
    p = (app_pose_crop - app_pose_crop[:, :1]) * reference.metres_per_crop_unit[:, None, None]
    p[invalid] = np.nan
    up = np.array([0., -1., 0.])
    frames, truth = [], []
    for t in range(len(p)):
        d = o.keypoints[t, sh, :2] - o.keypoints[t, hp, :2]
        two = dict(hipY=float(o.keypoints[t, hp, 1]), shoulderY=float(o.keypoints[t, sh, 1]),
                   torsoLength=float(np.linalg.norm(d)))
        f, g = frame_metrics(p[t], side, up, two), frame_metrics(reference.joints_m[t], side, up, two)
        f["frame"] = g["frame"] = t
        frames.append(f)
        truth.append(g)
    intervals = [(s, e) for s, e in reference.rep_segments if s >= start and e < len(p) - 1 and e > s]
    measures, gt_measures, assessed = [], [], []
    critical = [0, 1, 2, 3, 4, 5, 6, 8, 11, 12, 13, 14, 15, 16]
    for i, (s, e) in enumerate(intervals):
        measures.append(rep_metrics(frames[s:e + 1], o.exercise, is_first_rep=i == 0))
        gt_measures.append(rep_metrics(truth[s:e + 1], o.exercise, is_first_rep=i == 0))
        assessed.append(float((~invalid[s:e + 1][:, critical]).all(1).mean()) >= .8)
    fired, gt_fired = judge_py(measures, o.exercise), judge_py(gt_measures, o.exercise)
    by_rule = {}
    for key in RULES_BY_EX[o.exercise]:
        pairs = [(key in p_, key in g_) for p_, g_, ok in zip(fired, gt_fired, assessed) if ok]
        by_rule[key] = dict(assessed_reps=len(pairs),
                           predicted_fires=sum(p_ for p_, _ in pairs),
                           gt_mirror_fires=sum(g_ for _, g_ in pairs),
                           disagreement_fp_proxy=sum(p_ and not g_ for p_, g_ in pairs),
                           disagreement_fn_proxy=sum(g_ and not p_ for p_, g_ in pairs))
    return dict(reps=len(intervals), assessed_reps=sum(assessed), abstained_reps=len(assessed) - sum(assessed),
                by_rule=by_rule,
                human_error_labels=False,
                note="Frozen legacy judge_py e05f1ac side-view mirror, not full current app gates. "
                     "GT rule disagreement and normal-demo fire proxies only; withheld warnings are abstentions, never TNs. "
                     "Both arms use observed 2D auxiliary heights; only 3D is replaced by score-reference joints.")
