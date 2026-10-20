import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from motion_contact.data import (BONES, Observations, ScoreReference, load_observations,
                                 load_predicted_profiles, normalize_observations, sha256)
from motion_contact.corruptions import corrupt_keypoints, infer_changed_xs
from motion_contact.metrics import pa_error, score_pose
from motion_contact.runner import online_profile, run_variant


def observation(n=280):
    t = np.arange(n) / 30
    p = np.zeros((n, 17, 3))
    base = np.array([[0, 0, 0], [.1, 0, 0], [.1, .45, .03], [.1, .9, 0],
                     [-.1, 0, 0], [-.1, .45, .03], [-.1, .9, 0], [0, -.2, 0],
                     [0, -.5, 0], [0, -.6, 0], [0, -.75, 0], [-.25, -.5, 0],
                     [-.4, -.25, .02], [-.5, 0, 0], [.25, -.5, 0], [.4, -.25, .02], [.5, 0, 0]])
    p[:] = base
    p[:, 13, 2] += .02 * np.sin(t)
    k = np.zeros((n, 26, 3))
    k[:, :, 2] = .9
    mapping = {5: 11, 6: 14, 7: 12, 8: 15, 9: 13, 10: 16, 11: 4, 12: 1,
               13: 5, 14: 2, 15: 6, 16: 3}
    for a, b in mapping.items():
        k[:, a, :2] = p[:, b, :2] * 300 + [450, 400]
    k[:, :5, :2] = [450, 160]
    x, crops = normalize_observations(k, (900, 900))
    pick = np.round(np.arange(n) * 50 / 30).astype(int)
    return Observations("s03_50591643_barbell_row", "s03", "50591643", "barbell_row",
                        p, k, x, crops, pick, np.tile([150, 100, 750, 850], (n, 1)), (900, 900), {})


def test_observation_loading_needs_no_gt_and_does_not_mutate_cache(tmp_path):
    o = observation()
    cached = tmp_path / (o.name + ".npz")
    pose = tmp_path / "pose2d.npz"
    np.savez(cached, L5=o.raw)
    np.savez(pose, halpe=o.keypoints, pick=o.pick, box=o.boxes, wh=o.image_size)
    before = sha256(cached)
    loaded = load_observations(cached, pose)
    assert np.array_equal(loaded.raw, o.raw)
    assert sha256(cached) == before
    assert not any("gt" in k.lower() or "reference" in k.lower() for k in loaded.__dict__)


def test_raw_boundary_is_invertible_and_online_profile_has_no_early_effect():
    o = observation()
    result = run_variant(o, "A")
    np.testing.assert_allclose(result["corrected"][21:], o.raw[21:] - o.raw[21:, :1], atol=1e-14)
    # Change late calibration observations: they must not affect earlier output.
    other = observation()
    other.raw[70:81, 13] *= 2
    baseline = run_variant(o, "E")
    changed = run_variant(other, "E")
    np.testing.assert_allclose(baseline["corrected"][:70], changed["corrected"][:70])
    assert baseline["profile_metadata"]["calibration_frames"] == [21, 80]


def test_mocap_fitted_shapes_are_not_accepted_as_runtime_profiles(tmp_path):
    path = tmp_path / "subjects.json"
    path.write_text(json.dumps({"s03": {"beta": [0] * 10, "calibrated_cm": [10] * 16, "mocap_cm": [10] * 16}}))
    (tmp_path / "manifest.json").write_text(json.dumps({
        "code_commit": "195c0f4575d2739906c437fad3e1d925b554b760",
        "outputs": {str(path): sha256(path)},
    }))
    with pytest.raises(AssertionError, match="not RGB calibration"):
        load_predicted_profiles([path])


def test_online_profile_rejects_less_than_30_usable_observations():
    o = observation()
    confidence = np.ones((len(o.raw), 17))
    confidence[21:81, 13] = 0
    confidence[21:50, 13] = .9
    assert "12-13" not in online_profile(o.raw, confidence)
    confidence[50, 13] = .9
    assert "12-13" in online_profile(o.raw, confidence)


def test_keypoint_stress_precedes_lifter_and_preserves_calibration_prefix():
    torch = pytest.importorskip("torch")
    o = observation()
    changed, damage = corrupt_keypoints(o)
    np.testing.assert_array_equal(changed[:81], o.keypoints[:81])
    assert damage[100:103].any() and not damage[:100].any()
    x, _ = normalize_observations(changed, o.image_size)

    class FakeModel:
        def __call__(self, frames):
            return frames * 2

    # Original raw is deliberately unrelated: untouched windows must preserve it.
    raw, report = infer_changed_xs(FakeModel(), x, o.normalized, o.raw, limit=270)
    np.testing.assert_array_equal(raw[:95], o.raw[:95])
    windows = np.clip(np.arange(270)[:, None] + 5 - 26 + np.arange(27), 0, len(x) - 1)
    affected = np.any(x != o.normalized, axis=(1, 2))[windows].any(1)
    np.testing.assert_allclose(raw[:270][affected], (x[windows] * 2)[:, 21][affected])
    assert report["recomputed_windows"] == int(affected.sum()) > 0


def test_scorer_metric_scale_and_pa_do_not_hide_raw_error():
    o = observation()
    # Reference exactly equals raw in metres; estimator never sees this object.
    ref = ScoreReference(o.raw.copy(), np.ones(len(o.raw)), np.array([0, -1, 0]),
                         ((90, 150),), {})
    out = score_pose(o, ref, o.raw, np.full((len(o.raw), 17), .01),
                     np.zeros((len(o.raw), 17), bool), np.ones(len(o.raw)))
    assert out["mpjpe_mm"]["mean"] == pytest.approx(0)
    assert out["acceleration_error_mm_s2"]["mean"] == pytest.approx(0)
    moved = o.raw.copy()
    moved[:, 13, 2] += .001
    out = score_pose(o, ref, moved, np.full((len(o.raw), 17), .01),
                     np.zeros((len(o.raw), 17), bool), np.ones(len(o.raw)))
    assert out["per_joint_mm"]["left_wrist"]["mean"] == pytest.approx(1.)
    np.testing.assert_allclose(pa_error(o.raw * 2 + 10, o.raw), 0, atol=1e-10)


def test_withheld_warning_is_abstention_not_true_negative():
    from motion_contact.rule_proxies import score_warning_proxies
    o = observation()
    ref = ScoreReference(o.raw.copy(), np.ones(len(o.raw)), np.array([0, -1, 0]),
                         ((100, 150), (160, 210)), {})
    result = score_warning_proxies(o, ref, o.raw, np.ones((len(o.raw), 17), bool))
    assert result["abstained_reps"] == 2
    assert result["assessed_reps"] == 0
    assert all(row["assessed_reps"] == 0 for row in result["by_rule"].values())
    assert not result["human_error_labels"]
