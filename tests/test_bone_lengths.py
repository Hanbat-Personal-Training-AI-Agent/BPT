"""Bone-length constraint tests.

tests/fixtures/bone_length_cases.json is shared with the Swift tests
(ios/CalibrationEngineKit/Tests/CalibrationEngineKitTests/BoneLengthConstraintTests.swift).
Regenerate after an intentional change with:  python tests/test_bone_lengths.py
"""

import json
import math
import unittest
from pathlib import Path

import numpy as np

from pose_feedback.geometry.bone_lengths import (
    DEFAULT_SEGMENTS,
    H36M17_PARENTS,
    SEGMENT_NAMES,
    apply_bone_lengths,
    load_bone_length_targets,
)

FIXTURE = Path(__file__).parent / "fixtures" / "bone_length_cases.json"

# boneLengthData of outputs/calibration_fit/result_guided.json (server fit, 170 cm test height).
CALIBRATION_RESULT = {
    "result": {
        "userHeightCm": 170,
        "boneLengthData": {
            "unit": "cm",
            "skeleton": "h36m17",
            "pose": "rest",
            "segments": {
                "pelvis-right_hip": 14.63, "right_hip-right_knee": 43.62, "right_knee-right_ankle": 41.79,
                "pelvis-left_hip": 14.61, "left_hip-left_knee": 43.76, "left_knee-left_ankle": 41.06,
                "pelvis-spine": 24.25, "spine-thorax": 23.99, "thorax-neck": 11.41, "neck-head": 11.18,
                "thorax-left_shoulder": 14.39, "left_shoulder-left_elbow": 26.88, "left_elbow-left_wrist": 25.21,
                "thorax-right_shoulder": 14.91, "right_shoulder-right_elbow": 27.07,
                "right_elbow-right_wrist": 24.86, "shoulder_width": 28.43, "hip_width": 29.25,
            },
            "appDefinitionDiffers": [
                "pelvis-spine", "spine-thorax", "thorax-neck", "neck-head",
                "thorax-left_shoulder", "thorax-right_shoulder",
            ],
        },
    }
}
INVALID_VALUES = {
    "segments": {
        "right_hip-right_knee": None, "right_knee-right_ankle": "41.8", "left_hip-left_knee": 0,
        "left_knee-left_ankle": -3.0, "left_shoulder-left_elbow": True, "left_elbow-left_wrist": 25,
        "thorax-neck": 11.4, "shoulder_width": 28.4, "unknown-segment": 10.0,
    },
    "appDefinitionDiffers": ["thorax-neck"],
}
TARGETS = load_bone_length_targets(CALIBRATION_RESULT)


def _pose(scale=0.004, noise=0.0, seed=0, offset=(0.0, 0.0, 0.0)):
    """Random-direction skeleton: limb lengths = target * scale * (1 + noise_i), torso 0.1."""
    rng = np.random.default_rng(seed)
    j = np.zeros((17, 3))
    j[0] = offset
    for c in range(1, 17):
        d = rng.normal(size=3)
        d /= np.linalg.norm(d)
        target = TARGETS.get(SEGMENT_NAMES[c - 1])
        length = 0.1 if target is None else target * scale * (1.0 + noise * rng.uniform(-1, 1))
        j[c] = j[H36M17_PARENTS[c]] + d * length
    return j


def _cases():
    distorted = _pose(noise=0.3, seed=1)
    zero_shin = _pose(noise=0.2, seed=2)
    zero_shin[3] = zero_shin[2]
    return [
        # name, joints, targets, enabled, segments, blend
        ("proportional", _pose(seed=3, offset=(0.1, -0.2, 0.3)), TARGETS, True, DEFAULT_SEGMENTS, 1.0),
        ("distorted", distorted, TARGETS, True, DEFAULT_SEGMENTS, 1.0),
        ("distorted_blend_half", distorted, TARGETS, True, DEFAULT_SEGMENTS, 0.5),
        ("distorted_blend_zero", distorted, TARGETS, True, DEFAULT_SEGMENTS, 0.0),
        ("distorted_disabled", distorted, TARGETS, False, DEFAULT_SEGMENTS, 1.0),
        ("distorted_with_pelvis_hip", distorted, TARGETS, True,
         DEFAULT_SEGMENTS + ("pelvis-right_hip", "pelvis-left_hip"), 1.0),
        ("odd_segment_count", _pose(noise=0.4, seed=4), TARGETS, True, DEFAULT_SEGMENTS[:7], 1.0),
        ("missing_target_right_shin", _pose(noise=0.3, seed=5),
         {k: v for k, v in TARGETS.items() if k != "right_knee-right_ankle"}, True, DEFAULT_SEGMENTS, 1.0),
        ("degenerate_zero_right_shin", zero_shin, TARGETS, True, DEFAULT_SEGMENTS, 1.0),
        ("no_targets", _pose(noise=0.3, seed=6), {}, True, DEFAULT_SEGMENTS, 1.0),
    ]


def build_fixture():
    cases = []
    for name, j, targets, enabled, segments, blend in _cases():
        out, report = apply_bone_lengths(j, targets, enabled=enabled, segments=segments, blend=blend)
        cases.append({
            "name": name, "joints": j.tolist(), "targets_cm": targets, "enabled": enabled,
            "segments": list(segments), "blend": blend,
            "expected_joints": np.asarray(out, dtype="float64").tolist(), "expected_report": report,
        })
    loaders = [
        {"name": "calibration_result", "input": CALIBRATION_RESULT, "expected": TARGETS},
        {"name": "invalid_values", "input": INVALID_VALUES, "expected": load_bone_length_targets(INVALID_VALUES)},
    ]
    return {"apply": cases, "load": loaders}


def _length(j, c):
    return float(np.linalg.norm(j[c] - j[H36M17_PARENTS[c]]))


def _angle(a, b):
    # atan2 form: acos loses ~1e-6 deg to rounding near 0.
    return math.degrees(math.atan2(float(np.linalg.norm(np.cross(a, b))), float(np.dot(a, b))))


class BoneLengthTests(unittest.TestCase):
    def setUp(self):
        self.cases = {c[0]: c for c in _cases()}

    def run_case(self, name):
        _, j, targets, enabled, segments, blend = self.cases[name]
        return j, apply_bone_lengths(j, targets, enabled=enabled, segments=segments, blend=blend)

    def test_loader(self):
        self.assertEqual(set(TARGETS), set(SEGMENT_NAMES) - set(
            CALIBRATION_RESULT["result"]["boneLengthData"]["appDefinitionDiffers"]))
        self.assertEqual(TARGETS["right_hip-right_knee"], 43.62)
        self.assertEqual(load_bone_length_targets(INVALID_VALUES), {"left_elbow-left_wrist": 25.0})
        self.assertEqual(load_bone_length_targets(CALIBRATION_RESULT["result"]["boneLengthData"]), TARGETS)

    def test_constrained_lengths_directions_and_rest(self):
        for name in ("proportional", "distorted", "distorted_with_pelvis_hip", "odd_segment_count",
                     "missing_target_right_shin", "degenerate_zero_right_shin"):
            _, j, targets, _, segments, _ = self.cases[name]
            out, report = apply_bone_lengths(j, targets, segments=segments)
            s = report["scale"]
            ratios = sorted(_length(j, c) / targets[n] for c, n in enumerate(SEGMENT_NAMES, 1)
                            if n in segments and n in targets and _length(j, c) >= 1e-6)
            self.assertAlmostEqual(s, float(np.median(ratios)), places=12, msg=name)
            np.testing.assert_array_equal(out[0], j[0])
            for c, n in enumerate(SEGMENT_NAMES, 1):
                seg = report["segments"][n]
                if seg["constrained"]:
                    self.assertAlmostEqual(_length(out, c), targets[n] * s, delta=1e-6, msg=f"{name} {n}")
                else:
                    self.assertAlmostEqual(_length(out, c), _length(j, c), delta=1e-12, msg=f"{name} {n}")
                if not seg["degenerate"]:
                    p = H36M17_PARENTS[c]
                    self.assertLess(_angle(out[c] - out[p], j[c] - j[p]), 1e-6, f"{name} {n}")
            if name == "proportional":
                np.testing.assert_allclose(out, j, atol=1e-12)
                self.assertAlmostEqual(s, 0.004, places=12)

    def test_blend(self):
        j, (out, report) = self.run_case("distorted_blend_half")
        _, (hard, _) = self.run_case("distorted")
        for c, n in enumerate(SEGMENT_NAMES, 1):
            if n in DEFAULT_SEGMENTS:
                self.assertAlmostEqual(_length(out, c), 0.5 * (_length(j, c) + _length(hard, c)), places=12)
        j, (out, _) = self.run_case("distorted_blend_zero")
        np.testing.assert_allclose(out, j, atol=1e-12)

    def test_disabled_and_no_targets_return_input(self):
        for name in ("distorted_disabled", "no_targets"):
            j, (out, report) = self.run_case(name)
            self.assertIs(out, j)
            self.assertIsNone(report["scale"])
            self.assertFalse(any(s["constrained"] for s in report["segments"].values()))

    def test_degenerate_flagged_and_untouched(self):
        j, (out, report) = self.run_case("degenerate_zero_right_shin")
        seg = report["segments"]["right_knee-right_ankle"]
        self.assertTrue(seg["degenerate"])
        self.assertFalse(seg["constrained"])
        np.testing.assert_allclose(out[3], out[2], atol=0)  # still zero length, moved with the knee
        self.assertTrue(report["segments"]["left_knee-left_ankle"]["constrained"])

    def test_invalid_config(self):
        with self.assertRaises(ValueError):
            apply_bone_lengths(np.zeros((17, 3)), TARGETS, segments=("pelvis-nose",))
        with self.assertRaises(ValueError):
            apply_bone_lengths(np.zeros((17, 3)), TARGETS, blend=1.5)

    def test_shared_fixture_matches(self):
        stored = json.loads(FIXTURE.read_text())
        fresh = build_fixture()
        self.assertEqual(stored["load"], fresh["load"])
        self.assertEqual([c["name"] for c in stored["apply"]], [c["name"] for c in fresh["apply"]])
        for s, f in zip(stored["apply"], fresh["apply"]):
            np.testing.assert_allclose(s["joints"], f["joints"], atol=1e-12)
            np.testing.assert_allclose(s["expected_joints"], f["expected_joints"], atol=1e-12)
            self.assertEqual(s["expected_report"]["scale"] is None, f["expected_report"]["scale"] is None)


if __name__ == "__main__":
    FIXTURE.parent.mkdir(exist_ok=True)
    FIXTURE.write_text(json.dumps(build_fixture(), indent=1) + "\n")
    print(f"wrote {FIXTURE}")
