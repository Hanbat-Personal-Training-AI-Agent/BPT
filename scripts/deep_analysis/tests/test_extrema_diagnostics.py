"""Small numeric contracts for diagnostic arithmetic, not media/model evidence."""
import importlib.util
from pathlib import Path
import unittest
import numpy as np

spec=importlib.util.spec_from_file_location('diagnostics',Path(__file__).resolve().parents[1]/'diagnose_gvhmr_extrema.py')
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)


class ExtremaDiagnosticsTests(unittest.TestCase):
    def test_single_spike_and_sustained_plateau_have_distinct_support(self):
        spike=np.zeros(31);spike[15]=20
        plateau=np.zeros(31);plateau[10:21]=20
        a,b=d.series_stats(spike),d.series_stats(plateau)
        self.assertAlmostEqual(a['maxSupport2degSeconds'],1/30)
        self.assertAlmostEqual(b['maxSupport2degSeconds'],11/30)
        self.assertEqual(a['rangeDropSingleMax'],0)
        self.assertEqual(b['rangeDropSingleMax'],20)
        self.assertEqual(a['maxMinusNeighborMedian'],20)
        # argmax picks the plateau's first frame: three neighbors per side.
        self.assertEqual(b['maxMinusNeighborMedian'],10)

    def test_matched_extreme_compression_and_time_shift_are_separate(self):
        g=np.sin(np.linspace(0,2*np.pi,121))
        x=.5*g+30
        a=d.compare_series(x,g)
        self.assertAlmostEqual(a['ownRangeError'],-1)
        self.assertAlmostEqual(a['atGtExtremeRangeError'],-1)
        self.assertEqual(a['maxTimingAbsSeconds'],0)
        delayed=np.r_[np.repeat(g[0],5),g[:-5]]
        b=d.compare_series(delayed,g)
        self.assertEqual(b['bestLagFrames'],5)
        self.assertLess(b['bestLagCenteredNormalizedRms'],1e-10)

    def test_endpoint_effect_and_nonfinite_guard(self):
        x=np.zeros(31);x[-1]=30
        a=d.series_stats(x)
        self.assertEqual(a['maxWithin3FramesOfEndpoint'],1)
        self.assertEqual(a['disjointEndRange'],0)
        x[3]=np.nan
        with self.assertRaises(ValueError):d.series_stats(x)


if __name__=='__main__':unittest.main()
