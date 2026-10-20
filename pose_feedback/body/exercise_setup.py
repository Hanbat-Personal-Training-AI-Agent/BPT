"""Personalized exercise setup (reference): the ready pose measured against the user's own body. OFF by default.

ios/Runner/NativePose/Evaluators/ExerciseSetup.swift mirrors this; tests/fixtures/exercise_setup_cases.json pins both.
Evidence and limits: docs/results/setup_constraint_prereg.md section 6, docs/results/setup_constraint.md (E1).

The setup never says a pose is correct - SMPL beta does not define an optimal stance or grip. It
  1. measures scale-free items on the 3D (XS after constraints: H36M17, pelvis-relative, camera axes, any unit) for
     the chosen exercise / variant, each with an observation quality: 2D confidence of the joints it needs, and how
     much of a width lies along the camera depth axis (a width seen side-on is XS's depth guess, not a measurement);
  2. expresses them relative to the same frame's own hip / shoulder joint width (calibration SMPL widths in cm are
     only shown as a labelled reference, never used to claim a cm measurement);
  3. calls the setup ready when every required item this view can observe has been measured with usable quality for
     `stable_frames` frames in a row and the body was still over them (stillness, not correctness): with the frame's
     2D at hand the 2D joints the required items use (left-right midpoints, or the one seen joint of a pair; a pair
     with neither seen blocks) moved <= tol_2d x the 2D torso, and each item in the image plane in every frame moved
     less than its tolerance. A width along the camera depth (a side view) is XS's depth guess: its wobble is not the user moving and
     its far joint is often hidden, so with the 2D it neither blocks nor holds the setup - it is shown as an estimate
     (no number when its joints are not observed). Without 2D (offline callers) every required item must be usable and
     is held to its tolerance;
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
    # push-up feet: not required - from the side (the app's push-up view) the far hip / ankle are hidden (device
    # 2026-10-20 pushup_0003: far hip confidence median 0.40), so requiring them made ready impossible
    "feet_width": ((R_ANKLE, L_ANKLE, R_HIP, L_HIP), ("squat", "barbell_row"), "ratio"),
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
                 "hand_width": ((R_WRIST, L_WRIST), (R_SHOULDER, L_SHOULDER)), "grip_width": ((R_WRIST, L_WRIST), (R_SHOULDER, L_SHOULDER)),
                 # trunk lean seen head-on lies along the depth: E1b Exercise3D front views 15-34 deg off vs 1-4 deg from the side
                 "torso_incline": ((PELVIS, THORAX),),
                 # offsets measured along the hip line: from the side that line is the camera depth (device squat
                 # 2026-10-20: foot_symmetry -1.99 = XS's depth guess, the hip line 79-91 % along the depth)
                 "foot_symmetry": ((R_HIP, L_HIP),), "shoulder_over_pelvis": ((R_HIP, L_HIP),)}
# Foot items need the Halpe26 foot points (heels, big toes; RTMPose-m Halpe26 is being evaluated, NOT adopted - the app
# default COCO17 has none, then the feet are only seen through the ankles: foot_source "ankle"). 2D, display only.
#   heel_width: feet_width x (heel distance / ankle distance in the image) - heel-to-heel stance relative to the hips
#   toe_out:    big-toe distance / heel distance in the image (1 = parallel feet, > 1 = toes turned out)
#   heel_toe:   (heel y - big-toe y) / shin in the image, the side with the better foot points (heel lift: squat_heel_rise)
# widths need the feet line in the image plane (else depth_estimated), heel_toe needs a side-on sagittal plane.
FOOT_KEYS = {"squat": ("heel_width", "toe_out", "heel_toe"), "barbell_row": ("heel_width", "toe_out", "heel_toe")}
FOOT_POINTS = ("left_heel", "right_heel", "left_big_toe", "right_big_toe")
COCO_L_ANKLE, COCO_R_ANKLE, COCO_L_KNEE, COCO_R_KNEE = 15, 16, 13, 14
# left-right joint pairs (H36M -> COCO17) whose 2D midpoints hold the body still (ExerciseSetup.motion_2d)
PAIRS_2D = {(R_ANKLE, L_ANKLE): (16, 15), (R_KNEE, L_KNEE): (14, 13), (R_HIP, L_HIP): (12, 11),
            (R_SHOULDER, L_SHOULDER): (6, 5), (R_ELBOW, L_ELBOW): (8, 7), (R_WRIST, L_WRIST): (10, 9)}
# 임시값 until E1 (tuning subjects) replaces them: stillness tolerance over the window, by kind.
DEFAULTS = dict(reliable_conf=0.5, low_conf=0.3, depth_max=0.7, stable_frames=30, tol_ratio=0.10, tol_deg=5.0, tol_items=None,
                tol_2d=0.10)
# tol_items {item: tolerance} overrides the per-kind tolerance (E1: 2 x measured repeatability per item).
# tol_2d: largest 2D joint range over the window / 2D torso (임시값, same 10% as tol_ratio). Exercise3D app-path 2D,
# 15-frame windows: standing before the first squat p50 0.064, inside the first squat rep p50 0.336.


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
    if key == "foot_stagger":  # measured along the horizontal normal of the hip line: the depth when seen head-on
        # ponytail: exact only for a level hip line; use cross(hip line, up) if a tilted pelvis ever matters here
        return math.sqrt(max(0.0, 1.0 - depth_share(P, "foot_symmetry") ** 2))
    shares = [abs(float(P[b][2] - P[a][2])) / max(_n(P[b] - P[a]), 1e-9) for a, b in WIDTH_VECTORS.get(key, ())]
    return max(shares) if shares else 0.0


def measure_feet(feet, coco2d, feet_width):
    """{item: (value or None, min confidence of the points it uses)} from Halpe26 foot points (px, (x, y, c)) and
    the COCO17 2D of the same frame; feet_width = the 3D ankle ratio of this frame."""
    f = {k: np.asarray(feet[k], dtype="float64") for k in FOOT_POINTS}
    k2 = np.asarray(coco2d, dtype="float64")
    d2 = lambda a, b: float(np.hypot(*(a[:2] - b[:2])))
    ank = d2(k2[COCO_L_ANKLE], k2[COCO_R_ANKLE]); heel = d2(f["left_heel"], f["right_heel"]); toe = d2(f["left_big_toe"], f["right_big_toe"])
    out = {}
    c = min(f["left_heel"][2], f["right_heel"][2], k2[COCO_L_ANKLE][2], k2[COCO_R_ANKLE][2])
    out["heel_width"] = (feet_width * heel / ank if feet_width is not None and ank > 1e-6 else None, c)
    c = min(f["left_heel"][2], f["right_heel"][2], f["left_big_toe"][2], f["right_big_toe"][2])
    out["toe_out"] = (toe / heel if heel > 1e-6 else None, c)
    best = None
    for heel_k, toe_k, knee_j, ank_j in (("left_heel", "left_big_toe", COCO_L_KNEE, COCO_L_ANKLE), ("right_heel", "right_big_toe", COCO_R_KNEE, COCO_R_ANKLE)):
        shin = d2(k2[knee_j], k2[ank_j]); c = min(f[heel_k][2], f[toe_k][2])
        if shin > 1e-6 and (best is None or c > best[1]):
            best = ((f[heel_k][1] - f[toe_k][1]) / shin, c)
    out["heel_toe"] = best if best is not None else (None, 0.0)
    return out


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
        if key == "torso_incline":  # the trunk line is seen from either side (side view: the far shoulder / hip hidden)
            c = max(min(float(conf[R_SHOULDER]), float(conf[R_HIP])), min(float(conf[L_SHOULDER]), float(conf[L_HIP])))
        else:
            c = min(float(conf[j]) for j in ITEMS[key][0])
        if c < self.p["low_conf"]:
            return "missing"
        if c < self.p["reliable_conf"]:
            return "low"
        return "depth_estimated" if depth_share(P, key) > self.p["depth_max"] else "good"

    def tolerance(self, key):
        if self.p["tol_items"] and key in self.p["tol_items"]:
            return self.p["tol_items"][key]
        return self.p["tol_deg"] if key in ITEMS and ITEMS[key][2] == "deg" else self.p["tol_ratio"]

    def motion_2d(self, required):
        """Largest 2D range (px, x or y) over the window of the joints the required items use, / the 2D torso
        (mid-shoulders to mid-hips, median). Per left-right pair: the midpoint when both joints were seen (confidence
        >= low_conf) in every window frame (in a side view the two hips / ankles overlap and the 2D model trades them
        frame to frame - device squat 2026-10-20: one hip spans 0.13 torso while standing), else the one joint that was
        (the near side). None when a pair had neither (that body part may have moved unseen: a row pull with both
        wrists lost) or there is no torso - the setup then cannot be ready."""
        K = np.stack([e[3] for e in self.window])
        used = {j for k in required for j in ITEMS[k][0]}
        tracks = []
        for (ha, hb), (a, b) in PAIRS_2D.items():
            if ha not in used or hb not in used:
                continue
            seen_a, seen_b = (K[:, a, 2] >= self.p["low_conf"]).all(), (K[:, b, 2] >= self.p["low_conf"]).all()
            if seen_a and seen_b:
                tracks.append((K[:, a, :2] + K[:, b, :2]) / 2)
            elif seen_a or seen_b:
                tracks.append(K[:, a if seen_a else b, :2])
            else:
                return None
        torso = float(np.median(np.linalg.norm((K[:, 5, :2] + K[:, 6, :2] - K[:, 11, :2] - K[:, 12, :2]) / 2, axis=-1)))
        if not tracks or torso < 1e-6:
            return None
        return max(float(np.ptp(m, axis=0).max()) for m in tracks) / torso

    def seeds(self, relations):
        """At ready: {name: (median px vector, p90 deviation px)} of AdaptiveRelations-style (name, a, b) over the
        ready window - the stable relation the adaptive constraint starts from (variant F)."""
        out = {}
        for name, a, b in relations:
            V = np.stack([e[2][b] - e[2][a] for e in self.window])
            ref = np.median(V, 0)
            out[name] = (ref, float(np.percentile(np.linalg.norm(V - ref, axis=-1), 90)))
        return out

    def update(self, P, conf, usable=True, up=UP, unit=1.0, feet=None, coco2d=None):
        """P [17,3] crop units (None when this frame has no usable 3D), conf [17] H36M 2D confidences, unit = px per
        crop unit; feet = Halpe26 foot points {left_heel, right_heel, left_big_toe, right_big_toe: (x, y, c)} px and
        coco2d [17,3] px of the same frame, or None (COCO17 model: feet only through the ankles).
        Phases: unavailable (no usable 3D) -> measuring (a required item is not observed well) -> holding (all
        observed; `moving` when the window is full but an item moved more than its tolerance) -> ready."""
        foot_keys = FOOT_KEYS.get(self.exercise, ()) if feet is not None and coco2d is not None else ()
        keys = BY_EXERCISE.get(self.exercise, ()) + foot_keys
        required = [k for k in keys if k in ITEMS and self.exercise in ITEMS[k][1]]
        foot_source = "halpe26" if foot_keys else "ankle"
        if P is None or not usable:
            self.window = []
            return dict(phase="ready" if self.ready is not None else "unavailable", progress=0.0, moving=False, items=[],
                        foot_source=foot_source, motion_2d=None)
        P = np.asarray(P, dtype="float64")
        values = measure(P, self.exercise, up)
        q = {k: self.quality(P, conf, k) if values.get(k) is not None else "missing" for k in keys if k in ITEMS}
        if foot_keys:
            hips_side_on = abs(float(P[L_HIP][2] - P[R_HIP][2])) / max(_n(P[L_HIP] - P[R_HIP]), 1e-9)  # 1 = side-on
            for k, (v, c) in measure_feet(feet, coco2d, values.get("feet_width")).items():
                values[k] = v if v is None or math.isfinite(v) else None
                if values[k] is None or c < self.p["low_conf"]:
                    q[k] = "missing"
                elif c < self.p["reliable_conf"]:
                    q[k] = "low"
                elif k == "heel_toe":  # the heel lift is read in the sagittal plane: needs a side-on view
                    q[k] = "depth_estimated" if hips_side_on < 1 - self.p["depth_max"] else "good"
                else:  # widths in the image need the feet line in the image plane
                    q[k] = "depth_estimated" if depth_share(P, "feet_width") > self.p["depth_max"] else "good"
        ok = ("good", "depth_estimated")
        need = [k for k in required if coco2d is None or not (k in WIDTH_VECTORS and depth_share(P, k) > self.p["depth_max"])]
        if not need or not all(q[k] in ok for k in need):
            self.window = []  # stillness is counted over frames in a row with every required item observed
        else:
            self.window.append((values, q, P * unit, None if coco2d is None else np.asarray(coco2d, dtype="float64")))
            if len(self.window) > self.p["stable_frames"]:
                self.window.pop(0)
        full = len(self.window) == self.p["stable_frames"]
        two_d = full and all(e[3] is not None for e in self.window)
        motion = self.motion_2d(required) if two_d else None
        gate = [k for k in required if not two_d or all(e[1][k] == "good" for e in self.window)]
        moving = full and ((two_d and (motion is None or motion > self.p["tol_2d"]))
                           or not all(max(e[0][k] for e in self.window) - min(e[0][k] for e in self.window) <= self.tolerance(k)
                                      for k in gate))
        if self.ready is None and full and required and not moving:
            # the snapshot (saved as "내 기준" on request) keeps only items measured in the image plane in every frame:
            # a depth guess or a half-hidden joint is no reference to adjust against
            self.ready = {k: float(np.median([e[0][k] for e in self.window])) for k in keys
                          if all(e[1].get(k) == "good" for e in self.window)}
        items = []
        for k in keys:
            item = dict(key=k, value=values.get(k), quality=q[k], required=k in required,
                        depth=round(depth_share(P, "feet_width" if k in ("heel_width", "toe_out") else k), 3))
            ref = self.reference.get(k)
            if ref is not None and q[k] == "good" and values.get(k) is not None:
                d = values[k] - ref
                item["ref"] = ref
                item["cue"] = None if abs(d) <= self.tolerance(k) else ("increase" if d < 0 else "decrease")
            items.append(item)
        phase = "ready" if self.ready is not None else ("holding" if self.window else "measuring")
        return dict(phase=phase, progress=min(1.0, len(self.window) / self.p["stable_frames"]), moving=moving, items=items,
                    foot_source=foot_source, motion_2d=None if motion is None else round(motion, 4))
