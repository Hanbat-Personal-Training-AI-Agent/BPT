"""Knee hyperextension clamp tests.

tests/fixtures/knee_hinge_limit_cases.json is shared with the Swift tests
(ios/CalibrationEngineKit/Tests/CalibrationEngineKitTests/KneeHingeLimitTests.swift).
Regenerate after an intentional change with:  python tests/test_hinge_limit.py
"""

import json
import math
import unittest
from pathlib import Path

import numpy as np

from pose_feedback.geometry.hinge_limit import clamp_knee_hyperextension, is_bad_3d, knee_theta_deg

FIXTURE = Path(__file__).parent / "fixtures" / "knee_hinge_limit_cases.json"
THIGH, SHIN = 0.45, 0.40


def _rot(axis, deg):
    axis = np.asarray(axis, dtype="float64") / np.linalg.norm(axis)
    x, y, z = axis
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    k = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    return np.eye(3) * c + s * k + (1 - c) * np.outer(axis, axis)


def _pose(right=(0.0, 0.0), left=(0.0, 0.0), r_ext_rot=0.0, r_abd=0.0):
    """Body frame: x = subject's left, y = up, z = forward (right-handed).

    Each leg is (hip flexion alpha, knee flexion beta) in degrees; beta < 0 is
    hyperextension. r_ext_rot spins the right thigh about its own axis (rotates
    the knee hinge), r_abd abducts the whole right leg about the forward axis.
    """
    j = np.zeros((17, 3))
    j[1], j[4] = [-0.1, 0, 0], [0.1, 0, 0]
    for (hip, knee, ankle), (alpha, beta), side in (((1, 2, 3), right, "r"), ((4, 5, 6), left, "l")):
        a, b = math.radians(alpha), math.radians(alpha - beta)
        u = THIGH * np.array([0, -math.cos(a), math.sin(a)])
        v = SHIN * np.array([0, -math.cos(b), math.sin(b)])
        if side == "r":
            spin = _rot(u, -r_ext_rot)  # about the thigh: knee hinge turns outward
            v = spin @ v
            abd = _rot([0, 0, 1], -r_abd)  # right leg out to the subject's right
            u, v = abd @ u, abd @ v
        j[knee] = j[hip] + u
        j[ankle] = j[knee] + v
    j[7], j[8], j[9], j[10] = [0, 0.25, 0], [0, 0.5, 0], [0, 0.6, 0], [0, 0.75, 0]
    j[11], j[12], j[13] = [0.18, 0.48, 0], [0.2, 0.2, 0], [0.2, 0.0, 0.05]
    j[14], j[15], j[16] = [-0.18, 0.48, 0], [-0.2, 0.2, 0], [-0.2, 0.0, 0.05]
    return j


def _cases():
    rng_rot = _rot([0.3, -1.0, 0.5], 73.0)  # arbitrary proper rotation
    straight = _pose()
    return [
        ("standing", _pose((0, 5), (0, 3)), 10.0, True),
        ("squat_bottom", _pose((95, 125), (95, 125)), 10.0, True),
        ("hyperextension_15", _pose((0, -15), (0, 5)), 10.0, True),
        ("hyperextension_30_both", _pose((10, -30), (10, -30)), 10.0, True),
        ("hyperextension_30_rotated_translated", _pose((0, -30), (0, 0)) @ rng_rot.T + [0.3, -2.0, 1.5], 10.0, True),
        ("external_rotation_45_flexion_60", _pose((20, 60), (0, 0), r_ext_rot=45), 10.0, True),
        ("abduction_30_flexion_40", _pose((0, 40), (0, 0), r_abd=30), 10.0, True),
        ("abduction_30_hyperextension_25", _pose((0, -25), (0, 0), r_abd=30), 10.0, True),
        ("straight", straight, 10.0, True),
        ("at_limit_9_9", _pose((0, -9.9), (0, -9.9)), 10.0, True),
        ("hyperextension_15_limit_20", _pose((0, -15), (0, -25)), 20.0, True),
        ("hyperextension_30_disabled", _pose((0, -30), (0, -30)), 10.0, False),
        ("degenerate_zero_thigh", _zero_thigh(), 10.0, True),
        ("degenerate_thigh_along_pelvis", _thigh_along_pelvis(), 10.0, True),
    ]


def _zero_thigh():
    j = _pose((0, -30), (0, -30))
    j[2] = j[1]
    return j


def _thigh_along_pelvis():
    j = _pose((0, -30), (0, -30))
    j[2] = j[1] + [-THIGH, 0, 0]
    j[3] = j[2] + [0, -SHIN, 0]
    return j


def _report_json(report):
    return {leg: dict(r) for leg, r in report.items()}


def build_fixture():
    out = []
    for name, joints, limit, enabled in _cases():
        result, report = clamp_knee_hyperextension(joints, limit_deg=limit, enabled=enabled)
        out.append({
            "name": name, "limit_deg": limit, "enabled": enabled,
            "joints": np.asarray(joints).tolist(),
            "expected_joints": np.asarray(result).tolist(),
            "expected_report": _report_json(report),
        })
    return out


class KneeHingeLimitTests(unittest.TestCase):
    def setUp(self):
        self.cases = {name: (j, lim, en) for name, j, lim, en in _cases()}

    def run_case(self, name):
        j, lim, en = self.cases[name]
        return j, clamp_knee_hyperextension(j, limit_deg=lim, enabled=en)

    def assert_corrected_to_limit(self, joints, out, leg, limit):
        hip, knee, ankle = {"right": (1, 2, 3), "left": (4, 5, 6)}[leg]
        self.assertAlmostEqual(knee_theta_deg(out, leg), -limit, delta=1e-4)
        self.assertAlmostEqual(np.linalg.norm(out[ankle] - out[knee]), np.linalg.norm(joints[ankle] - joints[knee]), places=12)

    def test_theta_sign_and_values(self):
        expected = {
            "standing": (5, 3), "squat_bottom": (125, 125), "straight": (0, 0),
            "hyperextension_15": (-15, 5), "hyperextension_30_both": (-30, -30),
            "hyperextension_30_rotated_translated": (-30, 0),
            "abduction_30_flexion_40": (40, 0), "abduction_30_hyperextension_25": (-25, 0),
            # hinge turned 45 deg away from the pelvis axis: magnitude shrinks, sign holds
            "external_rotation_45_flexion_60": (math.degrees(math.atan2(math.sin(math.radians(60)) * math.cos(math.radians(45)), math.cos(math.radians(60)))), 0),
        }
        for name, (r, l) in expected.items():
            j = self.cases[name][0]
            self.assertAlmostEqual(knee_theta_deg(j, "right"), r, places=9, msg=name)
            self.assertAlmostEqual(knee_theta_deg(j, "left"), l, places=9, msg=name)

    def test_in_range_returns_input_unchanged(self):
        for name in ("standing", "squat_bottom", "straight", "external_rotation_45_flexion_60",
                     "abduction_30_flexion_40", "at_limit_9_9", "hyperextension_30_disabled"):
            j, (out, report) = self.run_case(name)
            self.assertIs(out, j, name)
            self.assertFalse(report["right"]["corrected"] or report["left"]["corrected"], name)
        f32 = self.cases["standing"][0].astype("float32")
        self.assertIs(clamp_knee_hyperextension(f32)[0], f32)

    def test_hyperextension_clamped_to_limit(self):
        for name, legs in (("hyperextension_15", ["right"]), ("hyperextension_30_both", ["right", "left"]),
                           ("hyperextension_30_rotated_translated", ["right"]),
                           ("abduction_30_hyperextension_25", ["right"]),
                           ("hyperextension_15_limit_20", ["left"])):
            j, (out, report) = self.run_case(name)
            limit = self.cases[name][1]
            for leg in ("right", "left"):
                self.assertEqual(report[leg]["corrected"], leg in legs, name)
            changed = [i for i in range(17) if not np.array_equal(out[i], j[i])]
            self.assertEqual(changed, sorted({"right": 3, "left": 6}[leg] for leg in legs), name)
            for leg in legs:
                self.assert_corrected_to_limit(j, out, leg, limit)
                self.assertAlmostEqual(report[leg]["correction_deg"], -limit - report[leg]["theta_deg"], places=12)
        self.assertAlmostEqual(self.run_case("hyperextension_15")[1][1]["right"]["correction_deg"], 5.0, places=9)

    def test_bad_3d_detected_even_when_correction_disabled(self):
        bad = {"hyperextension_15", "hyperextension_30_both", "hyperextension_30_rotated_translated",
               "abduction_30_hyperextension_25", "hyperextension_15_limit_20", "hyperextension_30_disabled",
               "degenerate_zero_thigh", "degenerate_thigh_along_pelvis"}  # degenerate cases: the left leg is -30
        for name in self.cases:
            _, (_, report) = self.run_case(name)
            self.assertEqual(is_bad_3d(report), name in bad, name)
        _, (out, report) = self.run_case("hyperextension_30_disabled")
        self.assertTrue(report["right"]["hyperextended"] and not report["right"]["corrected"])
        self.assertFalse(self.run_case("at_limit_9_9")[1][1]["right"]["hyperextended"])
        self.assertFalse(self.run_case("degenerate_zero_thigh")[1][1]["right"]["hyperextended"])

    def test_degenerate_frames_untouched_and_flagged(self):
        for name, leg in (("degenerate_zero_thigh", "right"), ("degenerate_thigh_along_pelvis", "right")):
            j, (out, report) = self.run_case(name)
            self.assertTrue(report[leg]["degenerate"], name)
            self.assertIsNone(report[leg]["theta_deg"])
            self.assertFalse(report[leg]["corrected"])
            self.assertTrue(np.array_equal(out[[1, 2, 3]], j[[1, 2, 3]]))
            self.assertTrue(report["left"]["corrected"])  # the healthy leg is still handled

    def test_shared_fixture_matches(self):
        stored = json.loads(FIXTURE.read_text())
        fresh = build_fixture()
        self.assertEqual([c["name"] for c in stored], [c["name"] for c in fresh])
        for s, f in zip(stored, fresh):
            np.testing.assert_allclose(s["joints"], f["joints"], atol=1e-12)
            np.testing.assert_allclose(s["expected_joints"], f["expected_joints"], atol=1e-12)
            for leg in ("right", "left"):
                sr, fr = s["expected_report"][leg], f["expected_report"][leg]
                self.assertEqual((sr["corrected"], sr["degenerate"], sr["hyperextended"]),
                                 (fr["corrected"], fr["degenerate"], fr["hyperextended"]))
                for key in ("theta_deg", "correction_deg"):
                    if sr[key] is None:
                        self.assertIsNone(fr[key])
                    else:
                        self.assertAlmostEqual(sr[key], fr[key], places=9)


if __name__ == "__main__":
    FIXTURE.parent.mkdir(exist_ok=True)
    FIXTURE.write_text(json.dumps(build_fixture(), indent=1) + "\n")
    print(f"wrote {FIXTURE}")
