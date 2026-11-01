import importlib.util
from pathlib import Path
import unittest
import numpy as np

spec = importlib.util.spec_from_file_location('spine', Path(__file__).resolve().parents[1]/'spine_proxy_observability.py')
spine = importlib.util.module_from_spec(spec); spec.loader.exec_module(spine)


class ProxyTests(unittest.TestCase):
    def test_rigid_tilt_is_not_internal_bend(self):
        cases = spine.synthetic_examples()
        self.assertAlmostEqual(cases['rigid_tilt_60deg']['proxyDeg'], 0, places=5)
        self.assertAlmostEqual(cases['rigid_tilt_60deg']['wholeTrunkTiltDeg'], 60, places=5)
        self.assertAlmostEqual(cases['upper_segment_bend_30deg']['proxyDeg'], 30, places=5)
        self.assertAlmostEqual(cases['upper_segment_bend_30deg']['wholeTrunkTiltDeg'], 15, places=5)

    def test_degenerate_and_constant_signals_do_not_claim_observability(self):
        joints = np.zeros((4, 17, 3))
        self.assertIsNone(spine.stats(spine.bend_proxy(joints)))
        self.assertIsNone(spine.stats(spine.trunk_tilt(joints, np.array([0,1,0]))))
        self.assertIsNone(spine.correlation(np.arange(10), np.zeros(10)))


if __name__ == '__main__':
    unittest.main()
