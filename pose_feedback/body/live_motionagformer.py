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
