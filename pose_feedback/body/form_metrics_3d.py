"""3D posture metrics per frame and per rep — the Python mirror of FormWarningTracker.measure3D + metrics2D
(ios/Runner/NativePose/Evaluators/FormWarnings.swift) for H36M17 poses (y down, root-relative, any unit).

Used to (1) pin Swift <-> Python parity (tests/fixtures/form_metrics_3d_cases.json) and (2) aggregate normal-rep
distributions on mocap / XS output as candidate evidence for the AI-PT thresholds (docs/results/lift_app.md).
Camera-view quantities (front view fraction) and ear / heel quantities are 2D-only and not computed here.
"""
import math

import numpy as np

UP = np.array([0.0, -1.0, 0.0])
SIDE = {"left": dict(shoulder=11, elbow=12, wrist=13, hip=4, knee=5, ankle=6),
        "right": dict(shoulder=14, elbow=15, wrist=16, hip=1, knee=2, ankle=3)}


def _angle(a, b, c):
    u, v = a - b, c - b
    if np.linalg.norm(u) <= 1e-8 or np.linalg.norm(v) <= 1e-8:
        return None
    return math.degrees(math.atan2(np.linalg.norm(np.cross(u, v)), float(np.dot(u, v))))


def signed_torso_angle(j, up=UP):
    forward = np.cross(j[4] - j[1], up)
    trunk = j[8] - j[0]
    if np.linalg.norm(forward) <= 1e-8 or np.linalg.norm(trunk) <= 1e-8:
        return None
    return math.degrees(math.atan2(float(np.dot(trunk, forward / np.linalg.norm(forward))), float(np.dot(trunk, up))))


def signed_line_deviation(point, a, b, up=UP):
    d = b - a
    length = np.linalg.norm(d)
    if length <= 1e-8:
        return None
    d_hat = d / length
    n = -up - d_hat * float(np.dot(d_hat, -up))
    if np.linalg.norm(n) < 0.3:
        return None
    return float(np.dot(point - a, n / np.linalg.norm(n))) / length


def frame_metrics(j, side="left", up=UP, two_d=None):
    """FormWarningTracker.measure3D for one H36M17 frame. two_d = {hipY, shoulderY, torsoLength} of the same frame
    in 2D (image y, absolute): XS output is pelvis-relative, so heights come from 2D (None = not available)."""
    j = np.asarray(j, dtype="float64")
    k = SIDE[side]
    s = {"elbow": _angle(j[k["shoulder"]], j[k["elbow"]], j[k["wrist"]]),
         "knee": _angle(j[k["hip"]], j[k["knee"]], j[k["ankle"]]),
         "hipAngle": _angle(j[k["shoulder"]], j[k["hip"]], j[k["knee"]]),
         "torso": signed_torso_angle(j, up),
         "hipDeviation": signed_line_deviation(j[0], j[8], (j[3] + j[6]) * 0.5, up),
         "headDeviation": signed_line_deviation(j[10], j[0], j[8], up),
         "torsoLength": None, "hipY": None, "shoulderY": None, "elbowBehind": None, "wristAhead": None,
         "kneeAnkleGapRatio": None}
    trunk = j[8] - j[0]
    tl = np.linalg.norm(trunk)
    for key in ("hipY", "shoulderY", "torsoLength"):
        s[key] = None if two_d is None else two_d.get(key)
    if tl > 1e-8:
        chest = np.cross(j[4] - j[1], trunk)
        if np.linalg.norm(chest) > 1e-8:
            s["elbowBehind"] = float(np.dot(j[k["elbow"]] - j[0], -chest / np.linalg.norm(chest))) / tl
    arm = np.linalg.norm(j[k["shoulder"]] - j[k["elbow"]]) + np.linalg.norm(j[k["elbow"]] - j[k["wrist"]])
    headward = trunk - up * float(np.dot(trunk, up))
    if arm > 1e-8 and np.linalg.norm(headward) > 1e-8:
        s["wristAhead"] = float(np.dot(j[k["wrist"]] - j[k["shoulder"]], headward / np.linalg.norm(headward))) / arm
    lr = j[4] - j[1]
    if np.linalg.norm(lr) > 1e-8:
        u = lr / np.linalg.norm(lr)
        gap = float(np.dot(j[6] - j[3], u))
        if abs(gap) > 1e-6:
            s["kneeAnkleGapRatio"] = float(np.dot(j[5] - j[2], u)) / gap
    return s


def _wrap(d):
    r = math.remainder(d, 360.0)
    return 180.0 if r == -180.0 else r


def _unwrap(a):
    out = []
    for v in a:
        out.append(out[-1] + _wrap(v - out[-1]) if out else v)
    return out


def rep_metrics(frames, exercise, is_first_rep=False, hips_first_window=8):
    """FormWarningTracker.metrics2D over the rep's 3D frame samples (dicts from frame_metrics), same names."""
    m = {}

    def put(name, value):
        if value is not None:
            m[name] = float(value)

    def vals(key, sub=None):
        return [f[key] for f in (frames if sub is None else sub) if f[key] is not None]

    def first(key):
        return next((f[key] for f in frames if f[key] is not None), None)

    put("elbow_min", min(vals("elbow"), default=None))
    put("elbow_max", max(vals("elbow"), default=None))
    put("knee_min", min(vals("knee"), default=None))
    put("knee_max", max(vals("knee"), default=None))
    put("hip_angle_max", max(vals("hipAngle"), default=None))
    torso = _unwrap(vals("torso"))
    put("torso_min", min(torso, default=None))
    put("torso_max", max(torso, default=None))
    put("torso_mean", _wrap(sum(torso) / len(torso)) if torso else None)
    put("hip_dev_min", min(vals("hipDeviation"), default=None))
    put("hip_dev_max", max(vals("hipDeviation"), default=None))
    h0 = first("headDeviation")
    if h0 is not None:
        put("head_dev_change_min", min(vals("headDeviation")) - h0)
        put("head_dev_change_max", max(vals("headDeviation")) - h0)
    put("elbow_behind_max", max(vals("elbowBehind"), default=None))

    def hips_first(b, window):
        bottom = frames[b]
        win = frames[b: b + window + 1]
        if bottom["torso"] is not None:
            rises = [_wrap(v - bottom["torso"]) for v in vals("torso", win)]
            if rises:
                put("hips_first_torso_rise", max(rises))
        ends = [f for f in win if f["hipY"] is not None and f["shoulderY"] is not None]
        if ends and bottom["hipY"] is not None and bottom["shoulderY"] is not None and bottom["torsoLength"] is not None:
            end = ends[-1]
            dt = end["frame"] - bottom["frame"]
            if dt > 0:
                put("hips_first_hip_rise_speed", (bottom["hipY"] - end["hipY"]) / bottom["torsoLength"] / dt)
                put("hips_first_shoulder_rise_speed", (bottom["shoulderY"] - end["shoulderY"]) / bottom["torsoLength"] / dt)

    if exercise == "pushup":
        tops = [f for f in frames if f["elbow"] is not None]
        if is_first_rep and tops:
            top = tops[0]
            for f in tops:
                if f["elbow"] > top["elbow"]:
                    top = f
            put("first_rep_top_wrist_ahead", top["wristAhead"])
    elif exercise == "squat":
        kmin = min(vals("knee"), default=None)
        b = next((i for i, f in enumerate(frames) if f["knee"] is not None and f["knee"] == kmin), None)
        if b is not None:
            put("torso_at_bottom", frames[b]["torso"])
            hips_first(b, hips_first_window)
        hmax = max(vals("hipY"), default=None)
        b = next((i for i, f in enumerate(frames) if f["hipY"] is not None and f["hipY"] == hmax), None)
        if b is not None:
            put("knee_ankle_gap_ratio_min", min(vals("kneeAnkleGapRatio", frames[b:]), default=None))
    return m


def sequence_rep_metrics(poses, intervals, exercise, side="left", up=UP, two_d=None):
    """Per-rep metrics for poses [N,17,3] and rep intervals [(start, end)] (inclusive frame indices); two_d = per-frame
    list of {hipY, shoulderY, torsoLength} from 2D or None."""
    out = []
    for r, (a, b) in enumerate(intervals):
        frames = []
        for t in range(a, b + 1):
            f = frame_metrics(poses[t], side, up, None if two_d is None else two_d[t])
            f["frame"] = t
            frames.append(f)
        out.append(rep_metrics(frames, exercise, is_first_rep=r == 0))
    return out
