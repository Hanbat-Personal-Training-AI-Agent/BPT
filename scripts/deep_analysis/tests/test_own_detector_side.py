import importlib.util
from pathlib import Path
import sys
import unittest

import numpy as np

DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DIRECTORY))
spec = importlib.util.spec_from_file_location('own_detector_side', DIRECTORY/'ablate_own_detector_side.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


class OwnSideTests(unittest.TestCase):
    def test_selector_uses_only_own_confidence_and_deterministic_tie(self):
        k = np.zeros((7, 17, 3)); k[:, :, 2] = .8
        self.assertEqual(m.own_side(k), ('L', 0.))
        k[:, m.SIDE_JOINTS['R'], 2] = .9
        self.assertEqual(m.own_side(k)[0], 'R')
        before = m.own_side(k)
        k[:, :, :2] = -123456
        self.assertEqual(m.own_side(k), before)
        k[0, 0, 0] = np.nan
        with self.assertRaises(ValueError): m.own_side(k)

    def test_changing_gt_side_cannot_hide_fixed_target_regression(self):
        # Each side is recovered perfectly, but changing sides changes the target.
        old, fixed_new, matched_new = m.side_errors([60., 60.], [30., 30.], [60., 60.], [30., 30.])
        np.testing.assert_array_equal(old, [0., 0.])
        np.testing.assert_array_equal(fixed_new, [30., 30.])
        np.testing.assert_array_equal(matched_new, [0., 0.])
        changed_gt = m.side_errors([60.], [30.], [60.], [100.])
        self.assertEqual(changed_gt[1][0], 30.)

    def test_noise_is_seeded_and_does_not_mutate_source(self):
        j = np.ones((100, 17, 3)); k = j*.8
        for scenario in ('retained', 'jointNoise10mm', 'confidenceNoise005'):
            a = m.noisy_inputs(j, k, scenario, np.random.default_rng(20261102))
            b = m.noisy_inputs(j, k, scenario, np.random.default_rng(20261102))
            for x, y in zip(a, b): np.testing.assert_array_equal(x, y)
        np.testing.assert_array_equal(j, 1.)
        np.testing.assert_array_equal(k, .8)
        _, noisy = m.noisy_inputs(j, k, 'confidenceNoise005', np.random.default_rng(20261102))
        self.assertTrue((noisy[:, :, 2] >= 0).all() and (noisy[:, :, 2] <= 1).all())

    def test_strict_threshold_and_nonfinite_denominators(self):
        result = m.decision_counts([10., 11., 9., np.nan], [11., 10., 9., 11.], 10., [True]*4)
        self.assertEqual(result, dict(count=3, agree=1, falsePositive=1, falseNegative=1))


if __name__ == '__main__': unittest.main()
