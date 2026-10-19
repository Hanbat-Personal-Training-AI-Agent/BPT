"""Live MotionAGFormer sequence helpers for Python diagnostics."""

try:
    import numpy as np
except ModuleNotFoundError:  # pragma: no cover
    np = None

from pose_feedback.body.motionagformer_adapter import (
    DEFAULT_3D_NORMALIZATION,
    coco17_to_motionagformer_h36m17,
    normalize_motionagformer_sequence,
)
from pose_feedback.body.motionagformer_buffer import MotionAGFormerWindowBuilder


MOTIONAGFORMER_WINDOW_SIZE = 27
MOTIONAGFORMER_WRIST_ELBOW_INDICES = {
    "left": {"elbow": 12, "wrist": 13},
    "right": {"elbow": 15, "wrist": 16},
}


def motionagformer_frames_from_coco17(coco17_sequence, image_width, image_height,
                                      normalization=DEFAULT_3D_NORMALIZATION):
    """Convert COCO17 frames (time order) to normalized MotionAGFormer [N, 17, 3]."""
    h36m_xy, h36m_conf = coco17_to_motionagformer_h36m17(np.stack(coco17_sequence))
    normalized_xy = normalize_motionagformer_sequence(h36m_xy, h36m_conf, image_width, image_height, normalization)
    return np.concatenate([normalized_xy, h36m_conf[..., None]], axis=-1).astype("float32")


def run_live_motionagformer_sequence(
    coco17_sequence,
    runner,
    image_width,
    image_height,
    lookahead=5,
    window_size=MOTIONAGFORMER_WINDOW_SIZE,
    normalization=DEFAULT_3D_NORMALIZATION,
):
    """Run MotionAGFormer over a selected COCO17 sequence.

    Returns:
        pred_3d_selected: [N, 17, 3]
        pred_3d_windows: [N, T, 17, 3]
        motion_indices: [N, T]
        normalized_frames: [N, 17, 3]
    """
    if np is None:  # pragma: no cover
        raise ImportError("numpy is required for live MotionAGFormer helpers")
    if not coco17_sequence:
        empty_selected = np.zeros((0, 17, 3), dtype="float32")
        empty_windows = np.zeros((0, window_size, 17, 3), dtype="float32")
        empty_indices = np.zeros((0, window_size), dtype="int32")
        empty_norm = np.zeros((0, 17, 3), dtype="float32")
        return empty_selected, empty_windows, empty_indices, empty_norm

    normalized_frames = motionagformer_frames_from_coco17(coco17_sequence, image_width, image_height, normalization)
    builder = MotionAGFormerWindowBuilder(window_size=window_size)
    select_index = window_size - 1 - int(lookahead)
    pred_windows = []
    pred_selected = []
    motion_indices = []
    for index in range(len(normalized_frames)):
        window, indices = builder.build_lookahead_padded(
            normalized_frames,
            index,
            lookahead=int(lookahead),
        )
        pred = runner.predict_3d(window.astype("float32"))
        pred = np.asarray(pred, dtype="float32")
        pred_windows.append(pred)
        pred_selected.append(pred[select_index])
        motion_indices.append(indices)
    return (
        np.stack(pred_selected).astype("float32"),
        np.stack(pred_windows).astype("float32"),
        np.stack(motion_indices).astype("int32"),
        normalized_frames,
    )


def motionagformer_body_3d_debug(joints_3d):
    """Return wrist/elbow coordinates and elbow-wrist lengths for JSONL debug."""
    if joints_3d is None:
        return {side: _empty_side_debug() for side in ("left", "right")}
    joints = np.asarray(joints_3d, dtype="float32")
    if joints.shape != (17, 3):
        return {side: _empty_side_debug() for side in ("left", "right")}
    debug = {}
    for side, indices in MOTIONAGFORMER_WRIST_ELBOW_INDICES.items():
        elbow = joints[indices["elbow"]]
        wrist = joints[indices["wrist"]]
        debug[side] = {
            "elbow_3d": _xyz_list(elbow),
            "wrist_3d": _xyz_list(wrist),
            "elbow_wrist_length_3d": float(np.linalg.norm(wrist - elbow)),
        }
    return debug


def _empty_side_debug():
    return {
        "elbow_3d": None,
        "wrist_3d": None,
        "elbow_wrist_length_3d": None,
    }


def _xyz_list(value):
    return [float(value[0]), float(value[1]), float(value[2])]


class LiveMotionAGFormer:
    """Past-frames-only MotionAGFormer, the reference for ios MotionAGFormerLive.swift
    (tests/fixtures/live3d_parity.json pins both).

    push() takes one COCO17 frame (pixels, [17,3]) and returns the frames that became ready, oldest
    first, as dicts {frame, payload, state, filled, row, raw, pose3d, constraints}. Frame t uses the
    window [t + L - 26, t + L] (output row 26 - L), so it comes out L frames late with its own payload.
    cadence k runs one inference per k frames and reads k consecutive rows. flush() emits the last
    frames with the window clamped at the newest frame (= run_live_motionagformer_sequence at the end).
    States: warming_up (< 27 real frames since reset), tracking_lost (< min_joints joints at
    min_confidence; reset_after_lost such frames in a row clear the window), bad_3d (constraints), ok.
    """

    WINDOW = MOTIONAGFORMER_WINDOW_SIZE

    def __init__(self, predict, lookahead=5, cadence=1, min_joints=6, min_confidence=0.3,
                 reset_after_lost=15, constraints=None):
        from pose_feedback.body.motionagformer_adapter import PersonSquareCropTracker  # noqa: F401
        from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints

        assert 0 <= lookahead < self.WINDOW and cadence >= 1 and lookahead + cadence <= self.WINDOW
        self.predict = predict  # [27,17,3] float32 -> [27,17,3]
        self.lookahead, self.cadence = int(lookahead), int(cadence)
        self.min_joints, self.min_confidence, self.reset_after_lost = min_joints, min_confidence, reset_after_lost
        self.constraints = constraints if constraints is not None else Pose3DConstraints()
        self.inferences = 0
        self.reset()

    def reset(self):
        from pose_feedback.body.motionagformer_adapter import PersonSquareCropTracker

        self.tracker = PersonSquareCropTracker()
        self.entries = []  # (frame, payload, input [17,3], valid)
        self.pending = 0
        self.real = 0
        self.lost_run = 0

    def _normalize(self, coco17, w, h):
        from pose_feedback.body.motionagformer_adapter import (
            NORMALIZATION_LONG_SIDE, image_square_crop, square_crop_normalize)

        xy, conf = coco17_to_motionagformer_h36m17(np.asarray(coco17, dtype="float64")[None])
        crop = self.tracker.update(xy[0], conf[0]) or image_square_crop(w, h, NORMALIZATION_LONG_SIDE)
        return np.concatenate([square_crop_normalize(xy[0], crop), conf[0][:, None]], axis=-1).astype("float32")

    def push(self, frame, coco17, image_width, image_height, payload=None):
        coco17 = np.asarray(coco17, dtype="float64")
        valid = coco17.shape == (17, 3) and int((coco17[:, 2] >= self.min_confidence).sum()) >= self.min_joints
        out = []
        if valid:
            self.lost_run = 0
        else:
            self.lost_run += 1
            if self.lost_run >= self.reset_after_lost or not self.entries:
                if self.entries:
                    out += self.flush()
                out.append(self._frame(frame, payload, "tracking_lost", 0))
                return out
        self.entries.append((frame, payload, self._normalize(coco17, image_width, image_height), valid))
        self.pending += 1
        self.real += 1
        if len(self.entries) > self.WINDOW:
            self.entries.pop(0)
        ready = self.pending - self.lookahead
        if ready <= 0:
            return out
        if self.real < self.WINDOW:
            out += self._emit_without_3d(ready)
        elif ready >= self.cadence:
            out += self._emit_window(len(self.entries) - 1, ready, 0)
        return out

    def flush(self):
        out = []
        if self.real < self.WINDOW:
            out = self._emit_without_3d(self.pending)
        else:
            while self.pending > 0:
                p = len(self.entries) - self.pending
                shortfall = p + self.lookahead - (len(self.entries) - 1)
                if shortfall <= 0:
                    out += self._emit_window(p + self.lookahead, 1, 0)
                else:
                    out += self._emit_window(len(self.entries) - 1, 1, shortfall)
        self.reset()
        return out

    @staticmethod
    def _frame(frame, payload, state, filled, row=None, raw=None, pose3d=None, constraints=None):
        return {"frame": frame, "payload": payload, "state": state, "filled": filled, "row": row,
                "raw": raw, "pose3d": pose3d, "constraints": constraints}

    def _emit_without_3d(self, count):
        start = len(self.entries) - self.pending
        out = [self._frame(f, pl, "warming_up" if v else "tracking_lost", self.real)
               for f, pl, _, v in self.entries[start:start + count]]
        self.pending -= count
        return out

    def _emit_window(self, end, count, extra):
        w = self.WINDOW
        window = np.stack([self.entries[min(max(end + extra - (w - 1) + t, 0), end)][2] for t in range(w)])
        pred = np.asarray(self.predict(window.astype("float32")), dtype="float64").reshape(w, 17, 3)
        self.inferences += 1
        start = len(self.entries) - self.pending
        out = []
        for p in range(start, start + count):
            f, pl, _, valid = self.entries[p]
            row = (w - 1) - (end + extra - p)
            raw = pred[row].copy()
            if not valid:
                out.append(self._frame(f, pl, "tracking_lost", self.real, row, raw))
                continue
            fixed, report = self.constraints.apply(raw)
            out.append(self._frame(f, pl, "bad_3d" if report["bad"] else "ok", min(self.real, w), row, raw, fixed, report))
        self.pending -= count
        return out
