"""pose_feedback/body/form_metrics_3d.py fixture is current (Swift FormMetrics3DParityTests reads it)."""
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pose_feedback.body.form_metrics_3d import frame_metrics, sequence_rep_metrics  # noqa: E402


def test_fixture_is_current():
    for c in json.loads((ROOT / "tests/fixtures/form_metrics_3d_cases.json").read_text()):
        two_d = [{"hipY": 430.0, "shoulderY": 250.0, "torsoLength": float(np.hypot(42.0, 180.0))}] * len(c["poses"])
        got = sequence_rep_metrics(np.array(c["poses"]), [tuple(i) for i in c["intervals"]], c["exercise"], side="left",
                                   two_d=two_d)
        for g, w in zip(got, c["reps"]):
            assert set(g) == set(w)
            for k in w:
                assert abs(g[k] - w[k]) < 1e-9


def test_upright_torso_zero_and_plank_hip_sag():
    j = np.zeros((17, 3))
    j[1], j[4], j[8] = [-0.1, 0, 0], [0.1, 0, 0], [0, -0.5, 0]
    assert abs(frame_metrics(j)["torso"]) < 1e-9
    p = np.zeros((17, 3))
    p[1], p[4], p[0] = [-0.1, 0.3, 0], [0.1, 0.3, 0], [0, 0.3, 0]
    p[8], p[3], p[6] = [0, 0, -0.5], [-0.1, 0, 1.0], [0.1, 0, 1.0]
    assert abs(frame_metrics(p)["hipDeviation"] - 0.2) < 1e-9
