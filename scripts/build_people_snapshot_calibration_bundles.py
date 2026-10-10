"""Calibration bundles (manifest.json + 4 photos) from People Snapshot, for checking the body fit.

    python scripts/build_people_snapshot_calibration_bundles.py --root <people_snapshot_public> --out <dir>

Per subject: four frames whose body yaw (from the dataset's reconstructed_poses) is nearest to
0, +60, 180, -60 degrees from the first frame, the dataset's camera (camera.pkl), its OpenPose
COCO-18 keypoints mapped to COCO-17, and `reference.json`: the subject's consensus mesh height and
vertices (SMPL topology, dataset fit with clothing offsets; a reference, NOT ground truth).

People Snapshot (Alldieck et al., CVPR 2018) has no licence file in the mirror we use; keep the
bundles local / in the eval container, never in git (outputs/calibration_dummy_videos/README.txt).
"""
import argparse
import json
import pickle
from pathlib import Path

import cv2
import h5py
import numpy as np

OPENPOSE18_TO_COCO17 = [0, 15, 14, 17, 16, 5, 2, 6, 3, 7, 4, 11, 8, 12, 9, 13, 10]
VIEWS = (("front", 0), ("rightfront", 60), ("back", 180), ("leftfront", -60))


def rodrigues(axis_angle):
    return cv2.Rodrigues(np.asarray(axis_angle, dtype=np.float64))[0]


def yaw_deg(pose):
    """Body yaw about the camera's vertical axis, from the root rotation (SMPL forward = +z)."""
    forward = rodrigues(pose[:3]) @ np.array([0.0, 0.0, 1.0])
    return np.degrees(np.arctan2(forward[0], forward[2]))


def pick_frames(poses):
    yaws = np.array([yaw_deg(p) for p in poses])
    rel = (yaws - yaws[0] + 180) % 360 - 180
    picks = {}
    for label, target in VIEWS:
        diff = np.abs((rel - target + 180) % 360 - 180)
        picks[label] = (int(diff.argmin()), float(rel[diff.argmin()]))
    return picks


def build(subject_dir, out_dir):
    name = subject_dir.name
    cam = pickle.load(open(subject_dir / "camera.pkl", "rb"), encoding="latin1")
    poses = h5py.File(subject_dir / "reconstructed_poses.hdf5")["pose"][:]
    keypoints = h5py.File(subject_dir / "keypoints.hdf5")["keypoints"][:].reshape(-1, 18, 3)
    picks = pick_frames(poses[: len(keypoints)])
    video = cv2.VideoCapture(str(subject_dir / f"{name}.mp4"))
    frames = {}
    for label, (index, _) in picks.items():
        video.set(cv2.CAP_PROP_POS_FRAMES, index)
        ok, frame = video.read()
        assert ok, (name, index)
        frames[label] = frame
    h, w = next(iter(frames.values())).shape[:2]
    intrinsics = {"fx": float(cam["camera_f"][0]), "fy": float(cam["camera_f"][1]),
                  "cx": float(cam["camera_c"][0]), "cy": float(cam["camera_c"][1]), "source": "attachment"}
    vertices = np.array([l.split()[1:4] for l in open(subject_dir / "consensus.obj") if l.startswith("v ")], float)
    height_cm = round(float(vertices[:, 1].max() - vertices[:, 1].min()) * 100, 1)
    views = []
    for label, yaw in VIEWS:
        kp = keypoints[picks[label][0]][OPENPOSE18_TO_COCO17]
        views.append({"label": label, "file": f"view_{label}.jpg", "nominalYawDeg": yaw,
                      "measuredYawDeg": round(picks[label][1], 1), "frame": picks[label][0],
                      "keypoints": [[float(x), float(y), float(c)] for x, y, c in kp],
                      "imageWidth": w, "imageHeight": h, "intrinsics": intrinsics})
    target = out_dir / name
    target.mkdir(parents=True, exist_ok=True)
    for label, frame in frames.items():
        cv2.imwrite(str(target / f"view_{label}.jpg"), frame, [cv2.IMWRITE_JPEG_QUALITY, 92])
    manifest = {"schemaVersion": 1, "isComplete": True, "sessionId": name, "userHeightCm": height_cm,
                "imageWidth": w, "imageHeight": h, "keypointFormat": "coco17_pixel_unmirrored",
                "perViewCameraMetadata": True, "intrinsics": intrinsics, "views": views,
                "source": "people_snapshot (OpenPose keypoints, not the app's RTMPose)"}
    (target / "manifest.json").write_text(json.dumps(manifest))
    (target / "reference.json").write_text(json.dumps(
        {"heightCm": height_cm, "vertices": np.round(vertices, 5).tolist(),
         "gender": "female" if name.startswith("female") else "male"}))
    return name, height_cm, {k: v[1] for k, v in picks.items()}


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--root", required=True, type=Path)
    args.add_argument("--out", required=True, type=Path)
    opts = args.parse_args()
    for subject in sorted(p for p in opts.root.iterdir() if (p / "consensus.obj").exists()):
        name, height, yaws = build(subject, opts.out)
        print(f"{name}: {height} cm, yaws {', '.join(f'{k} {v:+.0f}' for k, v in yaws.items())}")


if __name__ == "__main__":
    main()
