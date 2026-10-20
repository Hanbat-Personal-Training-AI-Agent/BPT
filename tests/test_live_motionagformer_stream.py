"""LiveMotionAGFormer (past frames only) vs the offline reference and the Swift parity fixture."""
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from make_live3d_parity_fixture import H, W, fake_predict, run, sequence  # noqa: E402
from pose_feedback.body.live_motionagformer import run_live_motionagformer_sequence  # noqa: E402
from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints  # noqa: E402


class Runner:
    def predict_3d(self, window):
        return fake_predict(window)


def test_matches_offline_selected3d_after_warmup():
    """Streaming frame t = offline row 26 - L of window [t + L - 26, t + L] (same input, same time alignment)."""
    frames = [k.copy() for k in sequence(n=60, lost=(999, 999))]
    frames[20][:, 2] = 0.9  # no low frames
    for lookahead in (0, 5, 13):
        offline, _, _, _ = run_live_motionagformer_sequence(frames, Runner(), W, H, lookahead=lookahead)
        from pose_feedback.body.live_motionagformer import LiveMotionAGFormer
        live = LiveMotionAGFormer(fake_predict, lookahead=lookahead, constraints=Pose3DConstraints(enabled=False))
        out = []
        for i, k in enumerate(frames):
            out += live.push(i, k, W, H)
        out += live.flush()
        assert [r["frame"] for r in out] == list(range(60))
        first = 26 - lookahead
        for r in out:
            if r["frame"] < first:
                assert r["state"] == "warming_up" and r["raw"] is None
            else:
                assert r["state"] == "ok"
                np.testing.assert_allclose(r["raw"], offline[r["frame"]], atol=1e-6)


def test_fixture_is_current():
    fixture = json.loads((ROOT / "tests/fixtures/live3d_parity.json").read_text())
    frames = sequence()
    for want in fixture["fake"]:
        got = run(fake_predict, frames, want["lookahead"], want["cadence"])
        assert [f["state"] for f in got["frames"]] == [f["state"] for f in want["frames"]]
        assert got["inferences"] == want["inferences"]
        for g, w in zip(got["frames"], want["frames"]):
            if w["pose3d"] is not None:
                np.testing.assert_allclose(g["pose3d"], w["pose3d"], atol=1e-6)


def test_constraints_clamp_knee_and_keep_bone_lengths():
    j = np.zeros((17, 3))
    j[1], j[4] = [-0.1, 0, 0], [0.1, 0, 0]
    j[8] = [0, -0.5, 0]
    j[7] = j[8] / 2
    for hip, knee, ankle in ((1, 2, 3), (4, 5, 6)):
        j[knee] = j[hip] + [0, 0.45, 0]
        j[ankle] = j[knee] + [0, -0.4 * np.cos(np.radians(10)), 0.4 * np.sin(np.radians(10))]  # 170 deg flexion
    c = Pose3DConstraints(bone_lengths=False)
    out, report = c.apply(j)
    assert set(report["angle_corrections"]) == {"right_knee_flexion", "left_knee_flexion"}
    for hip, knee, ankle in ((1, 2, 3), (4, 5, 6)):
        u, v = out[hip] - out[knee], out[ankle] - out[knee]
        ang = np.degrees(np.arccos(np.dot(u, v) / np.linalg.norm(u) / np.linalg.norm(v)))
        assert abs(ang - 41.0) < 1e-6
        assert abs(np.linalg.norm(v) - 0.4) < 1e-9
    assert abs(report["angle_corrections"]["left_knee_flexion"] - 31.0) < 1e-6 and report["bad"]  # 10 -> 41 deg: moved 31 > 20


def test_flipped_knee_is_reflected_not_discarded():
    from pose_feedback.geometry.hinge_limit import knee_theta_deg
    j = np.zeros((17, 3))
    j[1], j[4] = [-0.1, 0, 0], [0.1, 0, 0]
    j[8] = [0, -0.5, 0]
    j[7] = j[8] / 2
    for hip, knee, ankle in ((1, 2, 3), (4, 5, 6)):
        j[ankle] = j[hip] + [0, 0.85, 0]
        j[knee] = j[hip] + [0, 0.45, 0.0]
    j[2][2] = 0.12  # right knee pushed the "wrong" way in depth: hyperextension-looking theta
    before = knee_theta_deg(j, "right")
    assert before < -30
    out, report = Pose3DConstraints(bone_lengths=False, reflect_flipped_knee=True).apply(j)
    assert report["knees_reflected"] == 1 and not report["bad"]
    assert knee_theta_deg(out, "right") > 30
    for p in (1, 3):
        assert abs(np.linalg.norm(out[2] - out[p]) - np.linalg.norm(j[2] - j[p])) < 1e-9


def test_hyperextended_knee_is_clamped_not_left_backwards():
    """theta = -25 (past the -15 clamp, short of the -30 flip): rotated onto -15, shin length kept, not invalid."""
    from pose_feedback.geometry.hinge_limit import knee_theta_deg
    j = np.zeros((17, 3))
    j[1], j[4] = [-0.1, 0, 0], [0.1, 0, 0]
    j[8] = [0, -0.5, 0]
    j[7] = j[8] / 2
    for hip, knee, ankle in ((1, 2, 3), (4, 5, 6)):
        j[knee] = j[hip] + [0, 0.45, 0]
        j[ankle] = j[knee] + [0, 0.4, 0]
    a = np.radians(25)
    j[3] = j[2] + 0.4 * np.array([0, np.cos(a), -np.sin(a)])
    before = knee_theta_deg(j, "right")
    assert before < -15
    out, report = Pose3DConstraints(bone_lengths=False).apply(j)
    assert abs(knee_theta_deg(out, "right") + 15) < 1e-9
    assert abs(report["knee_clamp_deg"] - (-15 - before)) < 1e-9
    assert abs(np.linalg.norm(out[3] - out[2]) - 0.4) < 1e-12
    assert report["invalid_joints"] == [] and not report["knee_hyperextended"]
