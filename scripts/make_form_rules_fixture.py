"""Writes tests/fixtures/form_rules_cases.json: pose_feedback/feedback/form_rules.py judge() on random rep metrics with the
app defaults and with every rules-calib rule switched on, for ios FormRulePresetTests (Swift FormWarningTracker.judge).

  conda run -n bpt-eval python -I scripts/make_form_rules_fixture.py
"""
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pose_feedback.feedback.form_rules import judge, load_preset  # noqa: E402

# metric -> (low, high) for the random draws (wide enough to cross every threshold both ways).
RANGES = {
    "pushup": {"front_view_fraction": (0, 0.8), "hip_dev_max": (-0.1, 0.3), "hip_dev_min": (-0.4, 0.05),
               "elbow_min": (40, 130), "elbow_max": (130, 180), "head_dev_change_max": (0, 0.5),
               "head_dev_change_min": (-0.4, 0), "first_rep_top_wrist_ahead": (-0.6, 0.6),
               "upper_arm_incline_max": (-40, 30)},
    "squat": {"front_view_fraction": (0, 0.8), "hips_first_torso_rise": (0, 20), "hips_first_hip_rise_speed": (0, 0.05),
              "hips_first_shoulder_rise_speed": (0, 0.05), "knee_min": (40, 140), "knee_max": (150, 180),
              "hip_angle_max": (140, 180), "torso_at_bottom": (10, 70), "knee_ankle_gap_ratio_min": (0.4, 1.4),
              "thigh_incline_min": (-30, 50), "torso_minus_tibia_at_bottom": (-30, 40)},
    "barbell_row": {"front_view_fraction": (0, 0.8), "torso_min": (10, 60), "torso_max": (40, 110), "torso_mean": (10, 80),
                    "elbow_behind_max": (-0.3, 0.6), "head_dev_change_min": (-0.4, 0), "knee_min": (90, 170),
                    "knee_max": (150, 180), "pull_peak_wrist_trunk": (-0.3, 1.3), "pull_peak_asym": (0, 0.4),
                    "pull_peak_flare": (-10, 80), "pull_peak_forearm_tilt": (-60, 60), "elbow_min": (40, 170)},
}
# Every rules-calib rule on, mid-range thresholds; one old rule and one new rule switched off.
ALL_ON = {"pushUp.depthAbsUpperArmInclineDegrees": -5.0, "pushUp.lockoutAbsElbowDegrees": 155.0,
          "squat.depthAbsThighInclineDegrees": 10.0, "squat.torsoLeanOverTibiaDegrees": 8.0,
          "row.hingeShallowTorsoDegrees": 35.0, "row.kneesLockedDegrees": 172.0, "row.kneesBentDegrees": 115.0,
          "row.pullHighWristTrunk": 0.9, "row.pullLowWristTrunk": 0.1, "row.unevenPullRatio": 0.2,
          "row.elbowFlareDegrees": 45.0, "row.wristLeadDegrees": 30.0, "row.straightArmElbowDegrees": 130.0,
          "row.shortPullAbsBehind": 0.05, "pushUp.hipSagDeviation": 0.1, "squat.valgusKneeAnkleGapRatio": 0.7}
OFF = ["pushup_hip_pike", "squat_no_lockout", "row_wrist_lead"]


def main():
    rng = np.random.default_rng(7)
    defaults, _ = load_preset("app_default")
    cases = []
    for exercise, ranges in RANGES.items():
        for name, values, off in (("app_default", defaults, []), ("all_on", {**defaults, **ALL_ON}, OFF)):
            for _ in range(3):
                reps = []
                for _ in range(8):
                    m = {k: round(float(rng.uniform(lo, hi)), 6) for k, (lo, hi) in ranges.items() if rng.random() > 0.15}
                    reps.append(m)
                fired = judge(reps, exercise, values, set(off))
                cases.append({"exercise": exercise, "preset": name, "values": values, "off": off, "reps": reps,
                              "fired": fired})
    out = ROOT / "tests/fixtures/form_rules_cases.json"
    out.write_text(json.dumps(cases, separators=(",", ":")))
    n = sum(len(f) for c in cases for f in c["fired"])
    print("wrote", out, len(cases), "cases,", n, "fired keys")


if __name__ == "__main__":
    main()
