"""MotionAGFormer 2D input adapters.

MotionAGFormer is trained on Human3.6M-style 17-joint inputs. RTMPose emits
COCO17. The COCO->H36M mapping below is ported from
external/2DEstimatorEval/data/prepare_2d_estimation.py::coco2h36m.

The mapping is still approximate for arbitrary in-the-wild COCO detections:
torso/head joints are synthesized from COCO joints, and that mismatch can
degrade depth estimation.
"""

try:
    import numpy as np
except ModuleNotFoundError:  # pragma: no cover
    np = None


MOTIONAGFORMER_H36M17_NAMES = [
    "pelvis",
    "r_hip",
    "r_knee",
    "r_ankle",
    "l_hip",
    "l_knee",
    "l_ankle",
    "spine",
    "thorax",
    "neck",
    "head",
    "l_shoulder",
    "l_elbow",
    "l_wrist",
    "r_shoulder",
    "r_elbow",
    "r_wrist",
]

COCO = {
    "nose": 0,
    "left_eye": 1,
    "right_eye": 2,
    "left_ear": 3,
    "right_ear": 4,
    "left_shoulder": 5,
    "right_shoulder": 6,
    "left_elbow": 7,
    "right_elbow": 8,
    "left_wrist": 9,
    "right_wrist": 10,
    "left_hip": 11,
    "right_hip": 12,
    "left_knee": 13,
    "right_knee": 14,
    "left_ankle": 15,
    "right_ankle": 16,
}


def coco17_to_motionagformer_h36m17(coco17):
    """Convert COCO17 keypoints to MotionAGFormer H36M17 2D joints.

    Args:
        coco17: Array with shape (..., 17, 2) or (..., 17, 3).

    Returns:
        If input contains x/y only, returns converted joints with shape
        (..., 17, 2). If input contains confidence, returns
        (converted_2d, converted_confidence).
    """
    arr = _as_array(coco17)
    if arr.shape[-2] != 17 or arr.shape[-1] not in (2, 3):
        raise ValueError("coco17 must have shape (..., 17, 2) or (..., 17, 3)")
    converted = _coco2h36m_xy(arr[..., :2])
    if arr.shape[-1] == 2:
        return converted.astype("float32")
    confidence = _coco2h36m_conf(arr[..., 2])
    return converted.astype("float32"), confidence.astype("float32")


def normalize_motionagformer_2d(joints_2d, image_width, image_height):
    """Normalize image coordinates as MotionAGFormer/VideoPose3D expects.

    Source convention:
    common.camera.normalize_screen_coordinates(X, w, h):
        X / w * 2 - [1, h / w]
    """
    points = _as_2d_array(joints_2d)
    if image_width <= 0 or image_height <= 0:
        raise ValueError("image_width and image_height must be positive")
    offset = np.asarray([1.0, float(image_height) / float(image_width)], dtype="float32")
    return (points / float(image_width) * 2.0 - offset).astype("float32")


def denormalize_motionagformer_2d(normalized_2d, image_width, image_height):
    points = _as_2d_array(normalized_2d)
    if image_width <= 0 or image_height <= 0:
        raise ValueError("image_width and image_height must be positive")
    offset = np.asarray([1.0, float(image_height) / float(image_width)], dtype="float32")
    return ((points + offset) * float(image_width) / 2.0).astype("float32")


# 3D-input normalizations. All three are the same map, p -> (p - center) / side * 2, with a
# different square crop (docs/research/rtmpose_motionagformer_image_to_pose_pipeline.md §13):
#   "screen":      VideoPose3D normalize_screen_coordinates, side = W, image centre.
#                  On portrait video y spans +-H/W (~+-1.78) while H36M training is ~+-1.
#   "long_side":   side = max(W, H), image centre -> both axes within +-1.
#   "person_crop": side = person bbox * margin, held with hysteresis (PersonSquareCropTracker).
# 2D evaluators and calibration never see these values; this is the MotionAGFormer input only.
NORMALIZATION_SCREEN = "screen"
NORMALIZATION_LONG_SIDE = "long_side"
NORMALIZATION_PERSON_CROP = "person_crop"
NORMALIZATIONS = (NORMALIZATION_SCREEN, NORMALIZATION_LONG_SIDE, NORMALIZATION_PERSON_CROP)
# Measured in docs §13 (squat_03 + calibration dummies). Back to the old behaviour: NORMALIZATION_SCREEN.
DEFAULT_3D_NORMALIZATION = NORMALIZATION_PERSON_CROP


def image_square_crop(image_width, image_height, method):
    """(center_x, center_y, side) of the image-level crop for "screen" / "long_side"."""
    if image_width <= 0 or image_height <= 0:
        raise ValueError("image_width and image_height must be positive")
    if method == NORMALIZATION_SCREEN:
        side = float(image_width)
    elif method == NORMALIZATION_LONG_SIDE:
        side = float(max(image_width, image_height))
    else:
        raise ValueError(f"no image-level crop for {method!r}")
    return (image_width * 0.5, image_height * 0.5, side)


def square_crop_normalize(joints_2d, crop):
    cx, cy, side = crop
    points = _as_2d_array(joints_2d)
    return ((points - np.asarray([cx, cy], dtype="float32")) / float(side) * 2.0).astype("float32")


def square_crop_denormalize(normalized_2d, crop):
    cx, cy, side = crop
    points = _as_2d_array(normalized_2d)
    return (points * float(side) / 2.0 + np.asarray([cx, cy], dtype="float32")).astype("float32")


class PersonSquareCropTracker:
    """Square crop around the person, held still with hysteresis.

    Same idea as CalibrationFrameAnalyzer.updateCrop: the crop only moves when the person
    leaves it or its size leaves [min_ratio, max_ratio] x the fresh target, so keypoint
    jitter does not reach the normalized input. The band is wide on the large side because
    a squat shrinks the bbox to ~0.6x (squat_03) and the crop must not follow it (a fixed camera, as in
    H36M, sees the person get smaller). ios PersonSquareCropTracker mirrors this
    (tests/fixtures/motionagformer_normalization_cases.json).
    """

    def __init__(self, margin=2.0, min_confidence=0.3, min_ratio=0.8, max_ratio=2.0):
        self.margin = margin
        self.min_confidence = min_confidence
        self.min_ratio = min_ratio
        self.max_ratio = max_ratio
        self.crop = None

    def update(self, joints_2d, confidence):
        """Feed one frame; returns the crop (cx, cy, side) or None before the first valid frame."""
        pts = _as_2d_array(joints_2d)[np.asarray(confidence) >= self.min_confidence]
        if len(pts) < 2:
            return self.crop  # keep the last crop through dropouts
        x0, y0 = (float(v) for v in pts.min(axis=0))
        x1, y1 = (float(v) for v in pts.max(axis=0))
        if x1 - x0 <= 1.0 or y1 - y0 <= 1.0:
            return self.crop
        pad = 0.08 * (y1 - y0)  # keypoints stop at the eyes and ankles
        y0, y1 = y0 - pad, y1 + pad
        target = ((x0 + x1) * 0.5, (y0 + y1) * 0.5, max(x1 - x0, y1 - y0) * self.margin)
        if self.crop is not None:
            cx, cy, side = self.crop
            h = side * 0.5
            inside = cx - h <= x0 and x1 <= cx + h and cy - h <= y0 and y1 <= cy + h
            if inside and self.min_ratio * target[2] < side < self.max_ratio * target[2]:
                return self.crop
        self.crop = target
        return self.crop


def normalize_motionagformer_sequence(h36m_xy, h36m_conf, image_width, image_height,
                                      method=DEFAULT_3D_NORMALIZATION, tracker=None):
    """[N,17,2] pixel H36M17 -> [N,17,2] MotionAGFormer input, frames in time order."""
    xy = _as_2d_array(h36m_xy)
    if method == NORMALIZATION_PERSON_CROP:
        tracker = tracker or PersonSquareCropTracker()
        fallback = image_square_crop(image_width, image_height, NORMALIZATION_LONG_SIDE)
        out = [square_crop_normalize(f, tracker.update(f, c) or fallback) for f, c in zip(xy, h36m_conf)]
        return np.stack(out).astype("float32") if out else np.zeros((0, 17, 2), dtype="float32")
    return square_crop_normalize(xy, image_square_crop(image_width, image_height, method))


def motionagformer_angles(joints_3d):
    """Return elbow/knee angles for MotionAGFormer's H36M17 order."""
    from pose_feedback.geometry.angles_3d import angle_3d

    joints = _as_array(joints_3d)
    if joints.shape[-2:] != (17, 3):
        raise ValueError("joints_3d must have shape (..., 17, 3)")
    return {
        "left_elbow": angle_3d(joints[11], joints[12], joints[13]),
        "right_elbow": angle_3d(joints[14], joints[15], joints[16]),
        "left_knee": angle_3d(joints[4], joints[5], joints[6]),
        "right_knee": angle_3d(joints[1], joints[2], joints[3]),
    }


def _coco2h36m_xy(keypoints):
    new_keypoints = np.zeros_like(keypoints)
    new_keypoints[..., 0, :] = (keypoints[..., 11, :] + keypoints[..., 12, :]) * 0.5
    new_keypoints[..., 1, :] = keypoints[..., 12, :]
    new_keypoints[..., 2, :] = keypoints[..., 14, :]
    new_keypoints[..., 3, :] = keypoints[..., 16, :]
    new_keypoints[..., 4, :] = keypoints[..., 11, :]
    new_keypoints[..., 5, :] = keypoints[..., 13, :]
    new_keypoints[..., 6, :] = keypoints[..., 15, :]
    new_keypoints[..., 8, :] = (keypoints[..., 5, :] + keypoints[..., 6, :]) * 0.5
    new_keypoints[..., 7, :] = (new_keypoints[..., 0, :] + new_keypoints[..., 8, :]) * 0.5
    new_keypoints[..., 9, :] = (keypoints[..., 0, :] + new_keypoints[..., 8, :]) * 0.5
    new_keypoints[..., 10, :] = (keypoints[..., 1, :] + keypoints[..., 2, :]) * 0.5
    new_keypoints[..., 11, :] = keypoints[..., 5, :]
    new_keypoints[..., 12, :] = keypoints[..., 7, :]
    new_keypoints[..., 13, :] = keypoints[..., 9, :]
    new_keypoints[..., 14, :] = keypoints[..., 6, :]
    new_keypoints[..., 15, :] = keypoints[..., 8, :]
    new_keypoints[..., 16, :] = keypoints[..., 10, :]
    return new_keypoints


def _coco2h36m_conf(confidence):
    conf = np.asarray(confidence, dtype="float32")
    new_conf = np.zeros(conf.shape[:-1] + (17,), dtype="float32")
    new_conf[..., 0] = (conf[..., 11] + conf[..., 12]) * 0.5
    new_conf[..., 1] = conf[..., 12]
    new_conf[..., 2] = conf[..., 14]
    new_conf[..., 3] = conf[..., 16]
    new_conf[..., 4] = conf[..., 11]
    new_conf[..., 5] = conf[..., 13]
    new_conf[..., 6] = conf[..., 15]
    new_conf[..., 8] = (conf[..., 5] + conf[..., 6]) * 0.5
    new_conf[..., 7] = (new_conf[..., 0] + new_conf[..., 8]) * 0.5
    new_conf[..., 9] = (conf[..., 0] + new_conf[..., 8]) * 0.5
    new_conf[..., 10] = (conf[..., 1] + conf[..., 2]) * 0.5
    new_conf[..., 11] = conf[..., 5]
    new_conf[..., 12] = conf[..., 7]
    new_conf[..., 13] = conf[..., 9]
    new_conf[..., 14] = conf[..., 6]
    new_conf[..., 15] = conf[..., 8]
    new_conf[..., 16] = conf[..., 10]
    return new_conf


def _as_array(values):
    if np is None:  # pragma: no cover
        raise ImportError("numpy is required for MotionAGFormer adapters")
    return np.asarray(values, dtype="float32")


def _as_2d_array(values):
    arr = _as_array(values)
    if arr.shape[-1] != 2:
        raise ValueError("joints_2d must have last dimension 2")
    return arr
