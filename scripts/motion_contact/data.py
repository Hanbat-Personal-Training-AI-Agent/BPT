"""Read existing observations without reading Fit3D labels.

Only ``load_score_reference`` accesses mocap, camera extrinsics, or rep labels.
Personal calibration tables remain on Home; manifests contain their file hashes.
"""
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path

import numpy as np

from pose_feedback.body.motionagformer_adapter import (
    PersonSquareCropTracker, coco17_to_motionagformer_h36m17, square_crop_normalize,
)

PARENTS = (-1, 0, 1, 2, 0, 4, 5, 0, 7, 8, 9, 8, 11, 12, 8, 14, 15)
JOINTS = ("pelvis", "right_hip", "right_knee", "right_ankle",
          "left_hip", "left_knee", "left_ankle", "spine", "thorax", "neck",
          "head", "left_shoulder", "left_elbow", "left_wrist",
          "right_shoulder", "right_elbow", "right_wrist")
BONES = tuple((p, j) for j, p in enumerate(PARENTS) if p >= 0)
FIT3D_TO_H36M = (0, 4, 5, 6, 1, 2, 3, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
TUNING = ("s03", "s04", "s05")
HELDOUT = ("s07", "s08", "s09", "s10", "s11")
EXERCISES = ("squat", "pushup", "barbell_row")


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def normalize_observations(keypoints, image_size):
    """The cached XS producer's exact observed crop/mapping; no GT scale."""
    xy, conf = coco17_to_motionagformer_h36m17(keypoints[:, :17])
    tracker = PersonSquareCropTracker()
    width, height = image_size
    crops = np.asarray([tracker.update(f, c) or (width / 2, height / 2, max(width, height))
                        for f, c in zip(xy, conf)], dtype=float)
    normalized = np.stack([square_crop_normalize(f, c) for f, c in zip(xy, crops)])
    return np.concatenate([normalized, conf[..., None]], -1).astype(np.float32), crops


@dataclass
class Observations:
    name: str
    subject: str
    camera: str
    exercise: str
    raw: np.ndarray
    keypoints: np.ndarray
    normalized: np.ndarray
    crops: np.ndarray
    pick: np.ndarray
    boxes: np.ndarray
    image_size: tuple
    inputs: dict

    @property
    def timestamps(self):
        return self.pick / 50.0

    @property
    def split(self):
        return "tuning" if self.subject in TUNING else "heldout"


def load_observations(cache_file, pose2d_file, limit=None):
    cache_file, pose2d_file = Path(cache_file), Path(pose2d_file)
    subject, camera, exercise = cache_file.stem.split("_", 2)
    assert subject in TUNING + HELDOUT and exercise in EXERCISES
    with np.load(cache_file) as z:
        raw = z["L5"].astype(float)
    with np.load(pose2d_file) as z:
        keypoints = z["halpe"].astype(float)
        pick, boxes = z["pick"].copy(), z["box"].astype(float)
        image_size = tuple(z["wh"].astype(int))
    # The original raw producer used the common CSV/label length before
    # replacing 2D with Halpe. The video-derived Halpe NPZ has 0–3 extra trailing
    # frames on these 96 streams. Its exact 30fps prefix is the cached input.
    n_raw = len(raw)
    assert raw.shape == (n_raw, 17, 3) and n_raw <= len(keypoints), (cache_file, raw.shape, keypoints.shape)
    assert len(keypoints) - n_raw <= 3, (cache_file, "unexpected producer alignment")
    keypoints, pick, boxes = keypoints[:n_raw], pick[:n_raw], boxes[:n_raw]
    assert np.array_equal(pick, np.round(np.arange(n_raw) * 50 / 30).astype(int)), cache_file
    assert np.all(np.diff(pick) > 0)
    normalized, crops = normalize_observations(keypoints, image_size)
    n = min(len(raw), limit) if limit else len(raw)
    return Observations(cache_file.stem, subject, camera, exercise, raw[:n],
                        keypoints[:n], normalized[:n], crops[:n], pick[:n],
                        boxes[:n], image_size,
                        {str(p): sha256(p) for p in (cache_file, pose2d_file)})


def load_predicted_profiles(paths):
    """Accept image-predicted calibration only, rejecting old mocap-fitted shapes.

    The source is an independent calibration session in the experimental sense:
    photos were selected from observed detections over the original sequence,
    not restricted to the evaluation stream's initial frames.
    """
    profiles, hashes = {}, {}
    for path in map(Path, paths):
        manifest_path = path.parent / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        assert manifest.get("code_commit") == "195c0f4575d2739906c437fad3e1d925b554b760", manifest_path
        expected = next(v for k, v in manifest["outputs"].items() if Path(k).name == path.name)
        assert sha256(path) == expected, path
        data = json.loads(path.read_text())
        for subject, profile in data.items():
            assert "segments_cm" in profile and "photos" in profile, (subject, "not RGB calibration")
            assert "mocap_cm" not in profile and "calibrated_cm" not in profile, "GT-derived profile prohibited"
            values = []
            for p, c in BONES:
                values.append(float(profile["segments_cm"][f"{JOINTS[p]}-{JOINTS[c]}"]) / 100.0)
            values = np.asarray(values)
            assert np.isfinite(values).all() and (values > 0).all()
            profiles[subject] = values
        hashes[str(path)] = sha256(path)
        hashes[str(manifest_path)] = sha256(manifest_path)
    return profiles, hashes


@dataclass
class ScoreReference:
    joints_m: np.ndarray
    metres_per_crop_unit: np.ndarray
    up_camera: np.ndarray
    rep_segments: tuple
    inputs: dict


def load_score_reference(dataset_root, observations):
    """GT is read only after the estimator has produced its output.

    GT pelvis depth is allowed solely for offline metric unit conversion. The
    estimator never receives this object, its scale, its gravity, or its reps.
    """
    o = observations
    root = Path(dataset_root) / "train" / o.subject
    joint_path = root / "joints3d_25" / (o.exercise + ".json")
    joints = np.asarray(json.loads(joint_path.read_text())["joints3d_25"], float)
    joints = joints[o.pick][:, FIT3D_TO_H36M]
    camera_path = root / "camera_parameters" / o.camera / (o.exercise + ".json")
    camera = json.loads(camera_path.read_text())
    rotation = np.asarray(camera["extrinsics"]["R"], float)
    translation = np.asarray(camera["extrinsics"]["T"], float).reshape(3)
    camera_joints = (joints - translation) @ rotation.T
    focal = np.mean(camera["intrinsics_w_distortion"]["f"])
    metric_scale = o.crops[:, 2] / 2 * camera_joints[:, 0, 2] / focal
    ann_path = root / "rep_ann.json"
    ann = json.loads(ann_path.read_text())[o.exercise]
    segments = tuple((int(np.searchsorted(o.pick, s)), min(len(o.pick) - 1, int(np.searchsorted(o.pick, e))))
                     for s, e in zip(ann, ann[1:]) if s <= o.pick[-1])
    return ScoreReference(camera_joints - camera_joints[:, :1], metric_scale,
                          rotation @ np.array([0., 0., 1.]), segments,
                          {str(p): sha256(p) for p in (joint_path, camera_path, ann_path)})
