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
