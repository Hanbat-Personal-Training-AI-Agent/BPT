import importlib.util
from pathlib import Path

import numpy as np

spec = importlib.util.spec_from_file_location(
    "psb", Path(__file__).resolve().parents[1] / "scripts/build_people_snapshot_calibration_bundles.py")
psb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(psb)


def test_frames_nearest_to_each_view_yaw_are_picked():
    # A subject turning in place: root yaw 0..359 degrees about the vertical (y) axis, with a 180° x flip
    # like People Snapshot's camera-facing root.
    yaws = np.arange(0, 360, 7.0)
    poses = np.zeros((len(yaws), 72))
    for i, y in enumerate(np.radians(yaws)):
        poses[i, :3] = [0, y, 0]
    picks = psb.pick_frames(poses)
    for label, target in psb.VIEWS:
        assert abs((picks[label][1] - target + 180) % 360 - 180) <= 3.5, (label, picks[label])


def test_rodrigues_matches_a_quarter_turn():
    R = psb.rodrigues([0, np.pi / 2, 0])
    assert np.allclose(R @ [0, 0, 1], [1, 0, 0])
    assert np.allclose(psb.rodrigues([0, 0, 0]), np.eye(3))


def test_openpose_to_coco_keeps_sides():
    # COCO 5 = left shoulder = OpenPose 5; COCO 6 = right shoulder = OpenPose 2; COCO 16 right ankle = OpenPose 10.
    assert psb.OPENPOSE18_TO_COCO17[5] == 5 and psb.OPENPOSE18_TO_COCO17[6] == 2
    assert psb.OPENPOSE18_TO_COCO17[16] == 10 and len(set(psb.OPENPOSE18_TO_COCO17)) == 17
