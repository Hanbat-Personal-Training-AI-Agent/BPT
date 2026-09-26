import unittest

import numpy as np

from pose_feedback.body.motionagformer_wrist_source import (
    build_motionagformer_input_2d,
    reject_crossed_mediapipe_wrists,
)


class MotionAGFormerWristSourceTests(unittest.TestCase):
    def test_reject_crossed_mediapipe_wrists(self):
        raw = np.zeros((17, 3), dtype="float32")
        raw[9, :2] = [100.0, 100.0]  # left wrist
        raw[10, :2] = [200.0, 100.0]  # right wrist
        kept = reject_crossed_mediapipe_wrists(
            raw, {"left": [195.0, 102.0], "right": [205.0, 98.0]},
        )
        self.assertEqual(list(kept), ["right"])

    def test_raw_rtmpose_keypoints_are_not_mutated(self):
        raw = synthetic_coco()
        original = raw.copy()

        motion_input, _ = build_motionagformer_input_2d(
            raw,
            mediapipe_wrists_px={"left": [101.0, 202.0]},
            wrist_source="mediapipe",
        )

        np.testing.assert_allclose(raw, original)
        self.assertFalse(np.shares_memory(raw, motion_input))

    def test_rtmpose_mode_returns_unchanged_motionagformer_input(self):
        raw = synthetic_coco()

        motion_input, debug = build_motionagformer_input_2d(
            raw,
            mediapipe_wrists_px={"left": [101.0, 202.0], "right": [303.0, 404.0]},
            wrist_source="rtmpose",
        )

        np.testing.assert_allclose(motion_input, raw)
        self.assertEqual(debug["left"]["source_used"], "rtmpose")
        self.assertEqual(debug["right"]["source_used"], "rtmpose")

    def test_mediapipe_mode_replaces_left_wrist_only_when_left_exists(self):
        raw = synthetic_coco()

        motion_input, debug = build_motionagformer_input_2d(
            raw,
            mediapipe_wrists_px={"left": [101.0, 202.0]},
            wrist_source="mediapipe",
        )

        np.testing.assert_allclose(motion_input[9, :2], [101.0, 202.0])
        np.testing.assert_allclose(motion_input[10, :2], raw[10, :2])
        self.assertEqual(motion_input[9, 2], raw[9, 2])
        self.assertEqual(debug["left"]["source_used"], "mediapipe")
        self.assertEqual(debug["right"]["source_used"], "fallback")

    def test_mediapipe_mode_replaces_right_wrist_only_when_right_exists(self):
        raw = synthetic_coco()

        motion_input, debug = build_motionagformer_input_2d(
            raw,
            mediapipe_wrists_px={"right": [303.0, 404.0]},
            wrist_source="mediapipe",
        )

        np.testing.assert_allclose(motion_input[9, :2], raw[9, :2])
        np.testing.assert_allclose(motion_input[10, :2], [303.0, 404.0])
        self.assertEqual(motion_input[10, 2], raw[10, 2])
        self.assertEqual(debug["left"]["source_used"], "fallback")
        self.assertEqual(debug["right"]["source_used"], "mediapipe")

    def test_mediapipe_mode_falls_back_to_rtmpose_when_hand_missing(self):
        raw = synthetic_coco()

        motion_input, debug = build_motionagformer_input_2d(
            raw,
            mediapipe_wrists_px={},
            wrist_source="mediapipe",
        )

        np.testing.assert_allclose(motion_input, raw)
        self.assertEqual(debug["left"]["source_used"], "fallback")
        self.assertEqual(debug["right"]["source_used"], "fallback")

    def test_left_right_mapping_is_not_swapped(self):
        raw = synthetic_coco()

        motion_input, _ = build_motionagformer_input_2d(
            raw,
            mediapipe_wrists_px={
                "left": [111.0, 222.0],
                "right": [333.0, 444.0],
            },
            wrist_source="mediapipe",
        )

        np.testing.assert_allclose(motion_input[9, :2], [111.0, 222.0])
        np.testing.assert_allclose(motion_input[10, :2], [333.0, 444.0])


def synthetic_coco():
    coco = np.zeros((17, 3), dtype="float32")
    for idx in range(17):
        coco[idx] = [idx * 10.0, idx * 10.0 + 1.0, 0.5 + idx * 0.01]
    return coco


if __name__ == "__main__":
    unittest.main()
