"""Experimental wrist-source selection for MotionAGFormer 2D inputs."""

try:
    import numpy as np
except ModuleNotFoundError:  # pragma: no cover
    np = None


COCO_WRIST_INDEX = {
    "left": 9,
    "right": 10,
}


def build_motionagformer_input_2d(
    raw_body_2d,
    mediapipe_wrists_px=None,
    wrist_source="rtmpose",
):
    """Return a MotionAGFormer input copy plus per-side wrist-source debug.

    Args:
        raw_body_2d: RTMPose COCO17 keypoints with shape [17, 2] or [17, 3].
        mediapipe_wrists_px: Optional dict, side -> [x, y] in original frame px.
        wrist_source: "rtmpose" keeps the raw copy unchanged; "mediapipe"
            replaces only available wrist x/y coordinates in the copy.

    The input array is never mutated. Confidence values, when present, stay from
    RTMPose because MediaPipe Tasks does not provide a direct replacement score
    in the current pipeline schema.
    """
    if np is None:  # pragma: no cover
        raise ImportError("numpy is required for MotionAGFormer wrist source selection")
    if wrist_source not in ("rtmpose", "mediapipe"):
        raise ValueError('wrist_source must be "rtmpose" or "mediapipe"')

    raw = np.asarray(raw_body_2d, dtype="float32")
    if raw.shape != (17, 2) and raw.shape != (17, 3):
        raise ValueError(f"raw_body_2d must have shape [17, 2] or [17, 3], got {raw.shape}")

    motionagformer_input = raw.copy()
    mediapipe_wrists_px = mediapipe_wrists_px or {}
    debug = {
        "motionagformer_wrist_source": wrist_source,
        "raw_keypoints_mutated": False,
        "left": _side_debug(raw, motionagformer_input, "left", None, "rtmpose"),
        "right": _side_debug(raw, motionagformer_input, "right", None, "rtmpose"),
    }

    if wrist_source == "rtmpose":
        return motionagformer_input, debug

    for side, wrist_index in COCO_WRIST_INDEX.items():
        mp_wrist = _as_wrist_xy(mediapipe_wrists_px.get(side))
        if mp_wrist is None:
            debug[side] = _side_debug(raw, motionagformer_input, side, None, "fallback")
            continue
        motionagformer_input[wrist_index, :2] = mp_wrist
        debug[side] = _side_debug(raw, motionagformer_input, side, mp_wrist, "mediapipe")

    return motionagformer_input, debug


def reject_crossed_mediapipe_wrists(raw_body_2d, mediapipe_wrists_px):
    """Drop MediaPipe wrists that sit closer to the opposite RTMPose wrist.

    A wrist-centred hand crop can contain both hands (or only the other hand
    when this one is occluded); MediaPipe then returns the wrong hand.
    """
    raw = np.asarray(raw_body_2d, dtype="float32")
    kept = {}
    for side, wrist in (mediapipe_wrists_px or {}).items():
        xy = _as_wrist_xy(wrist)
        if xy is None:
            continue
        other = "right" if side == "left" else "left"
        own_d = np.linalg.norm(xy - raw[COCO_WRIST_INDEX[side], :2])
        other_d = np.linalg.norm(xy - raw[COCO_WRIST_INDEX[other], :2])
        if own_d <= other_d:
            kept[side] = wrist
    return kept


def _side_debug(raw, motionagformer_input, side, mediapipe_wrist, source_used):
    wrist_index = COCO_WRIST_INDEX[side]
    return {
        "source_used": source_used,
        "rtmpose_wrist_px": _xy_list(raw[wrist_index, :2]),
        "mediapipe_wrist_px": None if mediapipe_wrist is None else _xy_list(mediapipe_wrist),
        "motionagformer_input_wrist_px": _xy_list(motionagformer_input[wrist_index, :2]),
        "wrist_index": wrist_index,
    }


def _as_wrist_xy(value):
    if value is None:
        return None
    arr = np.asarray(value, dtype="float32")
    if arr.shape[0] < 2:
        return None
    return arr[:2].astype("float32")


def _xy_list(value):
    return [float(value[0]), float(value[1])]


COCO_ELBOW_INDEX = {"left": 7, "right": 8}
# Fit3D validation (docs/results/lift_app.md S4): MediaPipe wrists were further from the mocap wrist than RTMPose on
# every exercise and crop size; |MP - RTM| < 0.25 x forearm was the least harmful gate (3D neutral). 제안값.
DEFAULT_MAX_SHIFT_FOREARM = 0.25


def gate_mediapipe_wrists(raw_body_2d, mediapipe_wrists_px, max_shift_forearm=DEFAULT_MAX_SHIFT_FOREARM):
    """Keep a MediaPipe wrist only when it is within max_shift_forearm x the RTMPose forearm of the RTMPose wrist
    (None = no gate). Run after reject_crossed_mediapipe_wrists. ios MotionAGFormerWristSource mirrors it."""
    if max_shift_forearm is None:
        return dict(mediapipe_wrists_px or {})
    raw = np.asarray(raw_body_2d, dtype="float64")
    kept = {}
    for side, wrist in (mediapipe_wrists_px or {}).items():
        xy = _as_wrist_xy(wrist)
        if xy is None:
            continue
        w, e = raw[COCO_WRIST_INDEX[side], :2], raw[COCO_ELBOW_INDEX[side], :2]
        if np.linalg.norm(xy - w) < max_shift_forearm * np.linalg.norm(w - e):
            kept[side] = wrist
    return kept


# Both 256 px wrist crops hold both hands when the wrists are close; with the far hand hidden MediaPipe (numHands = 1)
# returns the near hand in both crops (Exercise3D barbellrow_0000 cam2, 2026-10-20 device run). 제안값.
SAME_HAND_IOU = 0.5


def same_hand(landmarks_a, landmarks_b, iou=SAME_HAND_IOU):
    """Two detections ([21, 2+] landmarks, frame px) are one hand: IoU of their landmark boxes > iou.
    ios MotionAGFormerWristSource.sameHand mirrors it."""
    if landmarks_a is None or landmarks_b is None:
        return False
    a, b = np.asarray(landmarks_a, dtype="float64")[:, :2], np.asarray(landmarks_b, dtype="float64")[:, :2]
    (ax0, ay0), (ax1, ay1) = a.min(0), a.max(0)
    (bx0, by0), (bx1, by1) = b.min(0), b.max(0)
    w, h = min(ax1, bx1) - max(ax0, bx0), min(ay1, by1) - max(ay0, by0)
    if w <= 0 or h <= 0:
        return False
    inter = w * h
    union = (ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter
    return union > 0 and inter / union > iou


def dedupe_same_hand(mediapipe_wrists_px, is_same_hand):
    """Both crops returned the same hand: which side it belongs to is unknown, so neither detection is used (the
    RTMPose wrists stay). Run before reject_crossed_mediapipe_wrists."""
    wrists = dict(mediapipe_wrists_px or {})
    if is_same_hand and "left" in wrists and "right" in wrists:
        return {}
    return wrists
