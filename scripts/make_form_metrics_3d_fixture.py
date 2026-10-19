"""Writes tests/fixtures/form_metrics_3d_cases.json: pose_feedback/body/form_metrics_3d.py per-rep 3D metrics on
synthetic H36M17 reps, for ios FormMetrics3DParityTests (Swift FormWarningTracker.measure3D + metrics2D).

  conda run -n bpt-eval python -I scripts/make_form_metrics_3d_fixture.py
"""
import json
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pose_feedback.body.form_metrics_3d import sequence_rep_metrics  # noqa: E402


def squat_pose(depth, lean, valgus, rng):
    """Standing person facing -z (towards the camera), y down; depth 0..1 bends knees and hips."""
    j = np.zeros((17, 3))
    j[1], j[4] = [-0.12, 0, 0], [0.12, 0, 0]
    k = math.radians(100 * depth)
    for s, (hip, knee, ankle) in ((-1, (1, 2, 3)), (1, (4, 5, 6))):
        j[knee] = j[hip] + [s * (0.02 - valgus * depth), 0.45 * math.cos(k / 2), -0.45 * math.sin(k / 2)]
        j[ankle] = j[knee] + [s * 0.01, 0.42 * math.cos(k / 2), 0.42 * math.sin(k / 2)]
    t = math.radians(lean + 35 * depth)
    j[8] = [0, -0.5 * math.cos(t), -0.5 * math.sin(t)]
    j[7] = j[8] / 2
    j[9] = j[8] + [0, -0.1, -0.03]
    j[10] = j[8] + [0, -0.2, -0.05]
    for s, (sh, el, wr) in ((1, (11, 12, 13)), (-1, (14, 15, 16))):
        j[sh] = j[8] + [s * 0.18, 0, 0]
        j[el] = j[sh] + [s * 0.02, 0.1, -0.25]
        j[wr] = j[el] + [0, 0.0, -0.25]
    return j + rng.normal(0, 0.003, j.shape)


def pushup_pose(depth, sag, rng):
    """Plank along +z, face down (+y floor); depth 0..1 bends the elbows."""
    j = np.zeros((17, 3))
    j[1], j[4], j[0] = [-0.1, sag, 0], [0.1, sag, 0], [0, sag, 0]
    j[3], j[6] = [-0.1, 0.1 * depth, 1.0], [0.1, 0.1 * depth, 1.0]
    j[2], j[5] = (j[1] + j[3]) / 2, (j[4] + j[6]) / 2
    j[8] = [0, 0.25 * depth, -0.5]
    j[7] = (j[0] + j[8]) / 2
    j[9], j[10] = j[8] + [0, 0.02, -0.1], j[8] + [0, 0.04, -0.2]
    e = math.radians(80 * depth)
    for s, (sh, el, wr) in ((1, (11, 12, 13)), (-1, (14, 15, 16))):
        j[sh] = j[8] + [s * 0.18, 0, 0]
        j[wr] = [s * 0.2, 0.5, -0.5]
        j[el] = j[sh] + [s * 0.05, 0.25 * math.cos(e) + 0.0, 0.25 * math.sin(e)]
    return j + rng.normal(0, 0.003, j.shape)


def main():
    rng = np.random.default_rng(1)
    cases = []
    for exercise in ("squat", "pushup"):
        poses, intervals, t = [], [], 0
        for rep in range(4):
            start = t
            for f in range(30):
                d = 0.5 - 0.5 * math.cos(2 * math.pi * f / 29)
                poses.append(squat_pose(d, 5 + 2 * rep, 0.05 * rep, rng) if exercise == "squat"
                             else pushup_pose(d, 0.02 * rep, rng))
                t += 1
            intervals.append((start, t - 1))
        poses = np.round(np.stack(poses), 8)  # the Swift test reads these rounded values
        # 2D heights of the Swift test's constant COCO17 (near = left: shoulder 5 at (335, 250), hip 11 at (377, 430)).
        two_d = [{"hipY": 430.0, "shoulderY": 250.0, "torsoLength": math.hypot(42.0, 180.0)}] * len(poses)
        reps = sequence_rep_metrics(poses, intervals, exercise, side="left", two_d=two_d)
        cases.append({"exercise": exercise, "poses": poses.tolist(),
                      "intervals": intervals, "reps": reps})
    out = ROOT / "tests/fixtures/form_metrics_3d_cases.json"
    out.write_text(json.dumps(cases, separators=(",", ":")))
    print("wrote", out)


if __name__ == "__main__":
    main()
