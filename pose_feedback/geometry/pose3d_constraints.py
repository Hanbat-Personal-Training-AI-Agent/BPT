"""Anatomical constraints on the final MotionAGFormer-XS H36M17 output (reference).

ios/Runner/NativePose/PosePipeline/Pose3DConstraints.swift mirrors this; both are pinned by
tests/fixtures/pose3d_constraints_cases.json.

Order: XS output -> bone lengths (bone_lengths.apply_bone_lengths: calibration cm when present, else the
session running median lengths, L/R averaged, else population ratios) -> knee hyperextension
(hinge_limit) -> interior joint-angle limits (knee/elbow flexion, hip, shoulder, spine). No smoothing.
report["bad"] (an angle limit moved a joint more than bad_angle_deg, the knee depth flipped (theta < -30, detection
only), or - when bad_bone_fraction is set - a bone correction above it) is the "3D 불량" quality signal (LiveMotionAGFormer state bad_3d).
"""

import math
from collections import deque

import numpy as np

from pose_feedback.geometry.bone_lengths import H36M17_PARENTS, MIN_BONE_LENGTH, SEGMENT_NAMES, apply_bone_lengths
from pose_feedback.geometry.hinge_limit import clamp_knee_hyperextension, is_bad_3d, knee_theta_deg

# Relative segment lengths for the first session_min_frames frames (only ratios matter): Fit3D mocap, 8 subjects,
# upper arm / thigh 0.60-0.63, forearm / thigh 0.54-0.57, shin / thigh 0.95-1.06 (docs/results/lift_app.md S2).
PRIOR_LENGTHS = {
    "right_hip-right_knee": 1.0, "left_hip-left_knee": 1.0,
    "right_knee-right_ankle": 1.0, "left_knee-left_ankle": 1.0,
    "left_shoulder-left_elbow": 0.61, "right_shoulder-right_elbow": 0.61,
    "left_elbow-left_wrist": 0.55, "right_elbow-right_wrist": 0.55,
}

# (name, ref_from, ref_to, joint, child, min_deg, max_deg): angle between (ref_to - ref_from) and
# (child - joint). Fit3D mocap p0.1 / p99.9 over 47 exercises (lift_app.md S2; partly validation subjects). 제안값.
DEFAULT_ANGLE_LIMITS = (
    ("right_knee_flexion", 2, 1, 2, 3, 41.0, 180.0),
    ("left_knee_flexion", 5, 4, 5, 6, 41.0, 180.0),
    ("right_elbow_flexion", 15, 14, 15, 16, 22.0, 180.0),
    ("left_elbow_flexion", 12, 11, 12, 13, 22.0, 180.0),
    ("right_hip", 0, 8, 1, 2, 32.0, 180.0),
    ("left_hip", 0, 8, 4, 5, 32.0, 180.0),
    ("right_shoulder", 8, 0, 14, 15, 0.0, 172.0),
    ("left_shoulder", 8, 0, 11, 12, 0.0, 172.0),
    ("spine", 7, 0, 7, 8, 120.0, 180.0),
)

CHILDREN = [[c for c in range(17) if H36M17_PARENTS[c] == p] for p in range(17)]


def _mirror(name):
    return name.replace("left", "#").replace("right", "left").replace("#", "right")


def clamp_angle(j, limit):
    """In place. Rotates the subtree of `child` about `joint`; returns degrees moved or None (plane undefined)."""
    _, ref_from, ref_to, joint, child, lo, hi = limit
    a, b = j[ref_to] - j[ref_from], j[child] - j[joint]
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na <= 1e-9 or nb <= 1e-9:
        return None
    cross = np.cross(a, b)
    ncross = float(np.linalg.norm(cross))
    theta = math.degrees(math.atan2(ncross, float(np.dot(a, b))))
    target = min(max(theta, lo), hi)
    if target == theta:
        return 0.0
    if ncross / (na * nb) <= 0.05:
        return None
    axis = cross / ncross
    phi = math.radians(target - theta)
    pivot = j[joint].copy()
    stack = [child]
    while stack:
        k = stack.pop()
        v = j[k] - pivot
        j[k] = pivot + v * math.cos(phi) + np.cross(axis, v) * math.sin(phi) + axis * float(np.dot(axis, v)) * (1 - math.cos(phi))
        stack += CHILDREN[k]
    return abs(target - theta)


class Pose3DConstraints:
    def __init__(self, enabled=True, bone_lengths=True, calibration_targets_cm=None, knee_correction=False,
                 knee_limit_deg=30.0, angle_limits=DEFAULT_ANGLE_LIMITS, bad_angle_deg=20.0, bad_bone_fraction=None,
                 reflect_flipped_knee=False,
                 session_min_frames=30, session_window_frames=300, prior_lengths=None):
        self.enabled = enabled
        self.bone_lengths = bone_lengths
        self.calibration_targets_cm = calibration_targets_cm
        self.knee_correction = knee_correction
        self.knee_limit_deg = knee_limit_deg
        self.reflect_flipped_knee = reflect_flipped_knee
        self.angle_limits = angle_limits
        self.bad_angle_deg = bad_angle_deg
        self.bad_bone_fraction = bad_bone_fraction
        self.session_min_frames = session_min_frames
        self.prior_lengths = dict(prior_lengths or PRIOR_LENGTHS)
        self.history = {name: deque(maxlen=session_window_frames) for name in self.prior_lengths}

    def session_targets(self):
        if min(len(v) for v in self.history.values()) < self.session_min_frames:
            return None
        med = {name: float(_median(list(v))) for name, v in self.history.items()}
        return {name: (med[name] + med.get(_mirror(name), med[name])) / 2 for name in med}

    def _record(self, j):
        for c in range(1, 17):
            name = SEGMENT_NAMES[c - 1]
            if name not in self.history:
                continue
            length = float(np.linalg.norm(j[c] - j[H36M17_PARENTS[c]]))
            if length > MIN_BONE_LENGTH:
                self.history[name].append(length)

    def apply(self, joints_3d):
        """Return (joints [17,3] float64, report dict)."""
        j = np.asarray(joints_3d, dtype="float64").copy()
        report = {"bone_max_correction": 0.0, "bone_source": "none", "knee_hyperextended": False,
                  "knee_correction_deg": 0.0, "knees_reflected": 0, "angle_corrections": {}, "bad": False}
        if not self.enabled:
            return j, report
        if self.bone_lengths:
            if self.calibration_targets_cm:
                targets, report["bone_source"] = self.calibration_targets_cm, "calibration"
            else:
                session = self.session_targets()
                targets, report["bone_source"] = (session, "session") if session else (self.prior_lengths, "prior")
            self._record(j)
            out, bones = apply_bone_lengths(j, targets)
            j = np.asarray(out, dtype="float64").copy()
            corr = [abs(s["output"] - s["observed"]) / max(s["observed"], MIN_BONE_LENGTH)
                    for s in bones["segments"].values() if s["constrained"]]
            report["bone_max_correction"] = max(corr) if corr else 0.0
        if self.reflect_flipped_knee:
            # Knee depth flip (lift_app.md S3): reflect the knee across the hip-ankle line (interior angle, lengths kept).
            for leg, (hip, knee, ankle) in (("right", (1, 2, 3)), ("left", (4, 5, 6))):
                theta = knee_theta_deg(j, leg)
                if theta is None or theta >= -self.knee_limit_deg:
                    continue
                line = j[ankle] - j[hip]
                if np.linalg.norm(line) <= 1e-9:
                    continue
                a = line / np.linalg.norm(line)
                v = j[knee] - j[hip]
                j[knee] = j[hip] + 2 * a * float(np.dot(v, a)) - v
                report["knees_reflected"] += 1
        out, hinge = clamp_knee_hyperextension(j, limit_deg=self.knee_limit_deg, enabled=self.knee_correction)
        j = np.asarray(out, dtype="float64").copy()
        report["knee_hyperextended"] = is_bad_3d(hinge)
        report["knee_correction_deg"] = max(hinge[leg]["correction_deg"] for leg in hinge)
        for limit in self.angle_limits:
            moved = clamp_angle(j, limit)
            if moved:
                report["angle_corrections"][limit[0]] = moved
        max_angle = max([report["knee_correction_deg"]] + list(report["angle_corrections"].values()))
        report["bad"] = bool(max_angle > self.bad_angle_deg
                             or (self.bad_bone_fraction is not None and report["bone_max_correction"] > self.bad_bone_fraction)
                             or (report["knee_hyperextended"] and not self.knee_correction))
        return j, report


def _median(values):
    v = sorted(values)
    n = len(v)
    return v[n // 2] if n % 2 else 0.5 * (v[n // 2 - 1] + v[n // 2])
