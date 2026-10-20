"""Personalized exercise setup (reference): the ready pose measured against the user's own body. OFF by default.

ios/Runner/NativePose/Evaluators/ExerciseSetup.swift mirrors this; tests/fixtures/exercise_setup_cases.json pins both.
Evidence and limits: docs/results/setup_constraint_prereg.md section 6, docs/results/setup_constraint.md (E1).

The setup never says a pose is correct - SMPL beta does not define an optimal stance or grip. It
  1. measures scale-free items on the 3D (XS after constraints: H36M17, pelvis-relative, camera axes, any unit) for
     the chosen exercise / variant, each with an observation quality: 2D confidence of the joints it needs, and how
     much of a width lies along the camera depth axis (a width seen side-on is XS's depth guess, not a measurement);
  2. expresses them relative to the same frame's own hip / shoulder joint width (calibration SMPL widths in cm are
     only shown as a labelled reference, never used to claim a cm measurement);
  3. calls the setup ready when every required item has been measured with usable quality for `stable_frames`
     frames in a row and moved less than its tolerance over them (stillness, not correctness);
  4. compares with a reference only when the user saved one (personal "내 기준"), tolerance from measured
     repeatability - there is no built-in ideal band.
Joint widths are between joint centres (H36M hips / shoulders, ankles, wrists): not foot or bar-contact widths.
"""
import math

import numpy as np

from pose_feedback.body.form_metrics_3d import UP, signed_line_deviation

PELVIS, R_HIP, R_KNEE, R_ANKLE, L_HIP, L_KNEE, L_ANKLE, THORAX = 0, 1, 2, 3, 4, 5, 6, 8
L_SHOULDER, L_ELBOW, L_WRIST, R_SHOULDER, R_ELBOW, R_WRIST = 11, 12, 13, 14, 15, 16

# item -> (H36M joints it needs, required for "ready" in these exercises, tolerance kind)
ITEMS = {
    "feet_width": ((R_ANKLE, L_ANKLE, R_HIP, L_HIP), ("squat", "pushup", "barbell_row"), "ratio"),
    "feet_width_shoulder": ((R_ANKLE, L_ANKLE, R_SHOULDER, L_SHOULDER), (), "ratio"),
    "foot_symmetry": ((R_ANKLE, L_ANKLE, R_HIP, L_HIP), (), "ratio"),
    "foot_stagger": ((R_ANKLE, L_ANKLE, R_HIP, L_HIP, R_KNEE, L_KNEE), (), "ratio"),
    "shoulder_over_pelvis": ((R_SHOULDER, L_SHOULDER, R_HIP, L_HIP), (), "ratio"),
    "torso_incline": ((R_SHOULDER, L_SHOULDER, R_HIP, L_HIP), ("squat", "pushup", "barbell_row"), "deg"),
    "hand_width": ((R_WRIST, L_WRIST, R_SHOULDER, L_SHOULDER), ("pushup",), "ratio"),
    "wrist_ahead": ((R_WRIST, L_WRIST, R_SHOULDER, L_SHOULDER, R_ELBOW, L_ELBOW), (), "ratio"),
    "body_line": ((R_SHOULDER, L_SHOULDER, R_HIP, L_HIP, R_ANKLE, L_ANKLE), (), "ratio"),
    "grip_width": ((R_WRIST, L_WRIST, R_SHOULDER, L_SHOULDER), ("barbell_row",), "ratio"),
}
BY_EXERCISE = {
    "squat": ("feet_width", "feet_width_shoulder", "foot_symmetry", "foot_stagger", "shoulder_over_pelvis", "torso_incline"),
    "pushup": ("hand_width", "wrist_ahead", "feet_width", "body_line", "torso_incline"),
    "barbell_row": ("feet_width", "grip_width", "shoulder_over_pelvis", "torso_incline"),
}
# Width items: the vectors whose depth share decides "depth_estimated" (numerator, reference width).
WIDTH_VECTORS = {"feet_width": ((R_ANKLE, L_ANKLE), (R_HIP, L_HIP)), "feet_width_shoulder": ((R_ANKLE, L_ANKLE), (R_SHOULDER, L_SHOULDER)),
                 "hand_width": ((R_WRIST, L_WRIST), (R_SHOULDER, L_SHOULDER)), "grip_width": ((R_WRIST, L_WRIST), (R_SHOULDER, L_SHOULDER))}
# 임시값 until E1 (tuning subjects) replaces them: stillness tolerance over the window, by kind.
DEFAULTS = dict(reliable_conf=0.5, low_conf=0.3, depth_max=0.7, stable_frames=30, tol_ratio=0.10, tol_deg=5.0, tol_items=None)
# tol_items {item: tolerance} overrides the per-kind tolerance (E1: 2 x measured repeatability per item).


def _n(v):
    return float(np.linalg.norm(v))


def _unit(v):
    n = _n(v)
    return v / n if n > 1e-9 else None


def measure(P, exercise, up=UP):
    """{item: value or None} for the exercise's items. Ratios are scale-free; torso_incline in degrees."""
    P = np.asarray(P, dtype="float64")
    out = {}
    hipw, shw = _n(P[L_HIP] - P[R_HIP]), _n(P[L_SHOULDER] - P[R_SHOULDER])
    leg = (_n(P[R_HIP] - P[R_KNEE]) + _n(P[R_KNEE] - P[R_ANKLE]) + _n(P[L_HIP] - P[L_KNEE]) + _n(P[L_KNEE] - P[L_ANKLE])) / 2
    arm = (_n(P[R_SHOULDER] - P[R_ELBOW]) + _n(P[R_ELBOW] - P[R_WRIST]) + _n(P[L_SHOULDER] - P[L_ELBOW]) + _n(P[L_ELBOW] - P[L_WRIST])) / 2
    lr = _unit(P[L_HIP] - P[R_HIP])
    trunk = P[THORAX] - P[PELVIS]
    for key in BY_EXERCISE.get(exercise, ()):
        v = None
        if key == "feet_width" and hipw > 1e-9:
            v = _n(P[L_ANKLE] - P[R_ANKLE]) / hipw
        elif key == "feet_width_shoulder" and shw > 1e-9:
            v = _n(P[L_ANKLE] - P[R_ANKLE]) / shw
        elif key == "foot_symmetry" and lr is not None:
            mid = (P[L_HIP] + P[R_HIP]) / 2
            v = (float(np.dot(P[L_ANKLE] - mid, lr)) + float(np.dot(P[R_ANKLE] - mid, lr))) / hipw
        elif key == "foot_stagger" and lr is not None and leg > 1e-9:
            fwd = _unit(np.cross(P[L_HIP] - P[R_HIP], up))
            v = None if fwd is None else float(np.dot(P[L_ANKLE] - P[R_ANKLE], fwd)) / leg
        elif key == "shoulder_over_pelvis" and lr is not None:
            v = float(np.dot((P[L_SHOULDER] + P[R_SHOULDER]) / 2 - (P[L_HIP] + P[R_HIP]) / 2, lr)) / hipw
        elif key == "torso_incline" and _n(trunk) > 1e-9:
            v = math.degrees(math.acos(max(-1.0, min(1.0, float(np.dot(trunk, up)) / _n(trunk)))))
        elif key in ("hand_width", "grip_width") and shw > 1e-9:
            v = _n(P[L_WRIST] - P[R_WRIST]) / shw
        elif key == "wrist_ahead" and arm > 1e-9:
            head = _unit(trunk - np.asarray(up) * float(np.dot(trunk, up)))
            if head is not None:
                v = float(np.dot((P[L_WRIST] + P[R_WRIST]) / 2 - (P[L_SHOULDER] + P[R_SHOULDER]) / 2, head)) / arm
        elif key == "body_line":
            v = signed_line_deviation(P[PELVIS], P[THORAX], (P[R_ANKLE] + P[L_ANKLE]) / 2, up)
        out[key] = v if v is None or math.isfinite(v) else None
    return out


def depth_share(P, key):
    """Largest |z| / |v| over the vectors a width item is made of (0 = in the image plane, 1 = along the depth)."""
    shares = [abs(float(P[b][2] - P[a][2])) / max(_n(P[b] - P[a]), 1e-9) for a, b in WIDTH_VECTORS.get(key, ())]
    return max(shares) if shares else 0.0


class ExerciseSetup:
    """Feed frames in time order; `update` returns the setup state of that frame (plain dict, Flutter payload)."""

    def __init__(self, exercise, reference=None, **params):
        self.exercise = exercise
        self.p = dict(DEFAULTS, **params)
        self.reference = dict(reference or {})  # user-saved {item: value}
        self.reset()

    def reset(self):
        self.window = []  # [(items, quality, pose px)] of the last stable_frames frames
        self.ready = None  # snapshot {item: median} once ready

    def quality(self, P, conf, key):
        c = min(float(conf[j]) for j in ITEMS[key][0])
        if c < self.p["low_conf"]:
            return "missing"
        if c < self.p["reliable_conf"]:
            return "low"
        return "depth_estimated" if depth_share(P, key) > self.p["depth_max"] else "good"

    def tolerance(self, key):
        if self.p["tol_items"] and key in self.p["tol_items"]:
            return self.p["tol_items"][key]
        return self.p["tol_deg"] if ITEMS[key][2] == "deg" else self.p["tol_ratio"]

    def seeds(self, relations):
        """At ready: {name: (median px vector, p90 deviation px)} of AdaptiveRelations-style (name, a, b) over the
        ready window - the stable relation the adaptive constraint starts from (variant F)."""
        out = {}
        for name, a, b in relations:
            V = np.stack([X[b] - X[a] for _, _, X in self.window])
            ref = np.median(V, 0)
            out[name] = (ref, float(np.percentile(np.linalg.norm(V - ref, axis=-1), 90)))
        return out

    def update(self, P, conf, usable=True, up=UP, unit=1.0):
        """P [17,3] crop units (None when this frame has no usable 3D), conf [17] H36M 2D confidences, unit = px per
        crop unit. Phases: unavailable (no usable 3D) -> measuring (a required item is not observed well) -> holding
        (all observed; `moving` when the window is full but an item moved more than its tolerance) -> ready."""
        keys = BY_EXERCISE.get(self.exercise, ())
        required = [k for k in keys if self.exercise in ITEMS[k][1]]
        if P is None or not usable:
            self.window = []
            return dict(phase="ready" if self.ready is not None else "unavailable", progress=0.0, moving=False, items=[])
        P = np.asarray(P, dtype="float64")
        values = measure(P, self.exercise, up)
        q = {k: self.quality(P, conf, k) if values.get(k) is not None else "missing" for k in keys}
        ok = ("good", "depth_estimated")
        if not all(q[k] in ok for k in required):
            self.window = []  # stillness is counted over frames in a row with every required item observed
        else:
            self.window.append((values, q, P * unit))
            if len(self.window) > self.p["stable_frames"]:
                self.window.pop(0)
        full = len(self.window) == self.p["stable_frames"]
        moving = full and not all(max(v[k] for v, _, _ in self.window) - min(v[k] for v, _, _ in self.window) <= self.tolerance(k)
                                  for k in required)
        if self.ready is None and full and required and not moving:
            self.ready = {k: float(np.median([v[k] for v, _, _ in self.window if v[k] is not None])) for k in keys
                          if any(v[k] is not None for v, _, _ in self.window)}
        items = []
        for k in keys:
            item = dict(key=k, value=values.get(k), quality=q[k], required=k in required, depth=round(depth_share(P, k), 3))
            ref = self.reference.get(k)
            if ref is not None and q[k] == "good" and values.get(k) is not None:
                d = values[k] - ref
                item["ref"] = ref
                item["cue"] = None if abs(d) <= self.tolerance(k) else ("increase" if d < 0 else "decrease")
            items.append(item)
        phase = "ready" if self.ready is not None else ("holding" if self.window else "measuring")
        return dict(phase=phase, progress=min(1.0, len(self.window) / self.p["stable_frames"]), moving=moving, items=items)
