import unittest

from pose_feedback.body.person_crop_tracker import PersonCropTracker


class PersonCropTrackerTests(unittest.TestCase):
    def test_low_score_jump_and_union(self):
        t = PersonCropTracker(score_thr=0.5, padding=1.0, aspect_wh=0.5)
        t.update([(0, 0, 10, 20, 0.9), (50, 50, 60, 60, 0.4)])  # low-score box ignored
        self.assertEqual(t.union, (0, 0, 10, 20))
        acc, _ = t.update([(100, 100, 110, 120, 0.9)])  # one-frame jump rejected
        self.assertIsNone(acc)
        self.assertEqual(t.union, (0, 0, 10, 20))
        t.update([(0, 0, 10, 20, 0.9)])  # back, but IoU with the jump frame fails
        t.update([(0, 5, 12, 20, 0.9)])  # consistent again: accepted and grows union
        self.assertEqual(t.union, (0, 0, 12, 20))
        x1, y1, x2, y2 = t.crop()
        self.assertAlmostEqual((x2 - x1) / (y2 - y1), 0.5)
        self.assertLessEqual(x1, 0)
        self.assertGreaterEqual(x2, 12)

    def test_reset(self):
        t = PersonCropTracker()
        t.update([(0, 0, 10, 20, 0.9)])
        t.reset()
        self.assertIsNone(t.crop())


if __name__ == "__main__":
    unittest.main()
