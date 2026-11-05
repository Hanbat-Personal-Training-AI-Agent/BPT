import importlib.util
from pathlib import Path
import sys
import unittest

import numpy as np

HELPER = Path(__file__).resolve().parents[1]/'ablate_smplx_joint_centers.py'
spec = importlib.util.spec_from_file_location('joint_center_ablation', HELPER)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class NumericTests(unittest.TestCase):
    def test_named_bilateral_mapping_and_unused_slots(self):
        j = np.arange(2*22*3).reshape(2, 22, 3)
        h = m.h36m_slots(j)
        for name in m.NATIVE:
            np.testing.assert_array_equal(h[:, m.H36M[name]], j[:, m.NATIVE[name]])
        self.assertTrue(np.isnan(h[:, [7, 8, 9, 10]]).all())
        self.assertEqual(m.NATIVE['left_elbow'], 18)
        self.assertEqual(m.NATIVE['right_ankle'], 8)

    def test_phase_range_and_paired_errors(self):
        gt = np.array([0., 10., 20., 10., 0.])
        x = gt*.5+3
        q = m.trace_metrics(x, gt)
        self.assertEqual(q['range'], 10.)
        self.assertEqual(q['atGtExtremeSignedRange'], 10.)
        self.assertEqual(q['maxTimingAbsSeconds'], 0.)
        p = m.Pool(); p.paired('test', [10, 2], [4, 3], [0, 0])
        r = p.result()
        self.assertEqual(r['test/pairedAbsErrorDelta']['mean'], -2.5)
        self.assertEqual(r['test/improved']['mean'], .5)
        self.assertEqual(r['test/worsened']['mean'], .5)

    def test_frozen_reconstruction_rejects_changed_metric(self):
        a = [{'knee_min': 30., 'missing': np.nan}]
        self.assertEqual(m.assert_metrics(a, a), (2, 0.))
        with self.assertRaises(AssertionError):
            m.assert_metrics(a, [{'knee_min': 31., 'missing': np.nan}])


@unittest.skipUnless((Path.home()/'gvhmr/GVHMR').is_dir(), 'licensed Home-local body model required')
class RealBodyModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import torch
        torch.set_num_threads(2)
        root = Path.home()/'gvhmr/GVHMR'
        sys.path.insert(0, str(root))
        from hmr4d.utils.smplx_utils import make_smplx
        cls.t = torch
        cls.model = make_smplx('supermotion').cpu()
        cls.fk = m.NativeFK(cls.model)

    def params(self):
        t = self.t
        body = t.linspace(-.25, .3, 126).reshape(2, 63)
        return dict(body_pose=body, betas=t.zeros(2, 10), global_orient=t.zeros(2, 3), transl=t.zeros(2, 3))

    def test_full_standard_lbs_parity_and_batch_invariance(self):
        p = self.params(); p['betas'][1, 0] = 1.25
        with self.t.inference_mode():
            full = self.model(**p).joints[:, :22].numpy()
        np.testing.assert_allclose(self.fk(p, 1), full, rtol=0, atol=2e-6)
        np.testing.assert_allclose(self.fk(p, 1), self.fk(p, 2), rtol=0, atol=1e-6)

    def test_rigid_motion_and_shape_dependency(self):
        p = self.params(); original = self.fk(p)
        shifted = dict(p); shifted['transl'] = self.t.tensor([[1., -2., 3.]]).expand(2, -1)
        np.testing.assert_allclose(self.fk(shifted), original+np.array([1., -2., 3.]), atol=1e-6)
        rotated = dict(p); rotated['global_orient'] = self.t.tensor([[0., 0., np.pi/2]]).float().expand(2, -1)
        R = np.array([[0., -1., 0.], [1., 0., 0.], [0., 0., 1.]])
        expected = (original-original[:, :1]) @ R.T+original[:, :1]
        np.testing.assert_allclose(self.fk(rotated), expected, rtol=0, atol=1e-6)
        shaped = dict(p); shaped['betas'] = self.t.ones(2, 10)
        a = original[:, 4]-original[:, 1]
        b = self.fk(shaped)[:, 4]-self.fk(shaped)[:, 1]
        self.assertGreater(float(np.max(abs(np.linalg.norm(a, axis=-1)-np.linalg.norm(b, axis=-1)))), 1e-5)


if __name__ == '__main__':
    unittest.main()
