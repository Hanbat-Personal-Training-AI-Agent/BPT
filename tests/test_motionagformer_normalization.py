"""MotionAGFormer 3D-input normalization tests.

tests/fixtures/motionagformer_normalization_cases.json is shared with the Swift tests
(ios/CalibrationEngineKit/Tests/CalibrationEngineKitTests/MotionAGFormerNormalizationTests.swift).
Regenerate after an intentional change with:  python tests/test_motionagformer_normalization.py
"""

import json
import unittest
from pathlib import Path

import numpy as np

from pose_feedback.body.motionagformer_adapter import (
    DEFAULT_3D_NORMALIZATION,
    NORMALIZATION_LONG_SIDE,
    NORMALIZATION_PERSON_CROP,
    NORMALIZATION_SCREEN,
    PersonSquareCropTracker,
    image_square_crop,
    normalize_motionagformer_2d,
    normalize_motionagformer_sequence,
    square_crop_denormalize,
    square_crop_normalize,
)

FIXTURE = Path(__file__).parent / "fixtures" / "motionagformer_normalization_cases.json"


def _person(cx, foot_y, height, conf=0.9, noise=0.0, seed=0):
    """H36M17 pixel frame: a standing stick figure `height` px from eyes to ankles."""
    rel = np.asarray([
        [0, 0.50], [-0.06, 0.50], [-0.06, 0.75], [-0.06, 1.0], [0.06, 0.50], [0.06, 0.75], [0.06, 1.0],
        [0, 0.35], [0, 0.20], [0, 0.12], [0, 0.0], [0.10, 0.20], [0.14, 0.35], [0.15, 0.48],
        [-0.10, 0.20], [-0.14, 0.35], [-0.15, 0.48],
    ])
    xy = np.stack([cx + rel[:, 0] * height, foot_y - height + rel[:, 1] * height], axis=-1)
    xy += np.random.default_rng(seed).normal(0.0, noise, xy.shape)
    return xy.astype("float32"), np.full(17, conf, dtype="float32")


def _track():
    """Stand still (jitter) -> squat to 0.6x -> dropout -> walk out of the crop -> step closer."""
    frames = [_person(360, 1100, 900, noise=3.0, seed=i) for i in range(5)]
    frames += [_person(360, 1100, h) for h in (800, 700, 600, 540, 700, 900)]
    frames.append(_person(360, 1100, 900, conf=0.1))  # every joint below min confidence
    frames.append(_person(1360, 1100, 900))
    frames.append(_person(1360, 1250, 1300))
    return frames


def build_fixture():
    image_cases = []
    points = np.asarray([[0, 0], [720, 1280], [360, 640], [100, 1200]], dtype="float32")
    for w, h in ((720, 1280), (1280, 720), (1080, 1080)):
        image_cases.append({
            "width": w, "height": h, "points": points.tolist(),
            "screen": square_crop_normalize(points, image_square_crop(w, h, NORMALIZATION_SCREEN)).tolist(),
            "long_side": square_crop_normalize(points, image_square_crop(w, h, NORMALIZATION_LONG_SIDE)).tolist(),
        })
    tracker = PersonSquareCropTracker()
    track = []
    w, h = 720, 1280
    for xy, conf in _track():
        crop = tracker.update(xy, conf)
        track.append({"joints": np.concatenate([xy, conf[:, None]], axis=-1).tolist(),
                      "crop": list(crop), "normalized": square_crop_normalize(xy, crop).tolist()})
    return {"image_cases": image_cases, "track": {"width": w, "height": h, "frames": track}}


class NormalizationTests(unittest.TestCase):
    def test_default_is_person_crop(self):
        self.assertEqual(DEFAULT_3D_NORMALIZATION, NORMALIZATION_PERSON_CROP)

    def test_screen_matches_videopose3d_formula(self):
        pts = np.asarray([[0, 0], [720, 1280], [100, 1200]], dtype="float32")
        got = square_crop_normalize(pts, image_square_crop(720, 1280, NORMALIZATION_SCREEN))
        np.testing.assert_allclose(got, normalize_motionagformer_2d(pts, 720, 1280), atol=1e-6)
        np.testing.assert_allclose(got[1], [1.0, 1280 / 720], atol=1e-6)

    def test_long_side_formula_portrait_and_landscape(self):
        pts = np.asarray([[0, 0], [720, 1280], [360, 640]], dtype="float32")
        got = square_crop_normalize(pts, image_square_crop(720, 1280, NORMALIZATION_LONG_SIDE))
        # x/H*2 - W/H, y/H*2 - 1
        np.testing.assert_allclose(got, pts / 1280 * 2 - [720 / 1280, 1.0], atol=1e-6)
        np.testing.assert_allclose(got[1], [0.5625, 1.0], atol=1e-6)
        land = square_crop_normalize(np.asarray([[1280, 720]], dtype="float32"),
                                     image_square_crop(1280, 720, NORMALIZATION_LONG_SIDE))
        np.testing.assert_allclose(land[0], [1.0, 0.5625], atol=1e-6)

    def test_square_crop_round_trip(self):
        pts = np.random.default_rng(1).uniform(-200, 1500, (5, 17, 2)).astype("float32")
        crop = (321.5, 702.25, 1830.0)
        back = square_crop_denormalize(square_crop_normalize(pts, crop), crop)
        np.testing.assert_allclose(back, pts, atol=1e-3)

    def test_tracker_holds_through_jitter_and_squat_and_dropout(self):
        tracker = PersonSquareCropTracker()
        crops = [tracker.update(xy, c) for xy, c in _track()]
        first = crops[0]
        self.assertAlmostEqual(first[2], 900 * 1.16 * 2.0, delta=30)  # eyes-ankles + 8% pads, margin 2
        # jitter (0-4), squat down to 0.6x and back up (5-10), dropout (11): same crop object
        for i in range(12):
            self.assertIs(crops[i], first, i)
        self.assertIsNot(crops[12], first)  # walked out of the crop -> re-centred
        self.assertAlmostEqual(crops[12][0], 1360, delta=1)
        self.assertIsNot(crops[13], crops[12])  # 1.44x taller -> re-crop
        self.assertGreater(crops[13][2], crops[12][2])
        # the whole sequence path uses the same tracker
        xy = np.stack([f[0] for f in _track()])
        conf = np.stack([f[1] for f in _track()])
        got = normalize_motionagformer_sequence(xy, conf, 720, 1280, NORMALIZATION_PERSON_CROP)
        for i, crop in enumerate(crops):
            np.testing.assert_allclose(got[i], square_crop_normalize(xy[i], crop), atol=1e-6)

    def test_tracker_recrops_on_strong_shrink_and_none_before_first_valid(self):
        tracker = PersonSquareCropTracker()
        self.assertIsNone(tracker.update(*_person(360, 1100, 900, conf=0.1)))
        big = tracker.update(*_person(360, 1100, 900))
        small = tracker.update(*_person(360, 1100, 400))  # 0.44x: beyond the 2.0 band
        self.assertLess(small[2], big[2])

    def test_person_crop_sequence_falls_back_to_long_side_before_first_crop(self):
        xy, conf = _person(360, 1100, 900, conf=0.1)
        got = normalize_motionagformer_sequence(xy[None], conf[None], 720, 1280, NORMALIZATION_PERSON_CROP)
        want = square_crop_normalize(xy, image_square_crop(720, 1280, NORMALIZATION_LONG_SIDE))
        np.testing.assert_allclose(got[0], want, atol=1e-6)

    def test_shared_fixture_matches(self):
        stored = json.loads(FIXTURE.read_text())
        fresh = build_fixture()
        for s, f in zip(stored["image_cases"], fresh["image_cases"]):
            np.testing.assert_allclose(s["screen"], f["screen"], atol=1e-6)
            np.testing.assert_allclose(s["long_side"], f["long_side"], atol=1e-6)
        for s, f in zip(stored["track"]["frames"], fresh["track"]["frames"]):
            np.testing.assert_allclose(s["crop"], f["crop"], atol=1e-6)
            np.testing.assert_allclose(s["normalized"], f["normalized"], atol=1e-6)


if __name__ == "__main__":
    FIXTURE.parent.mkdir(exist_ok=True)
    FIXTURE.write_text(json.dumps(build_fixture(), indent=1) + "\n")
