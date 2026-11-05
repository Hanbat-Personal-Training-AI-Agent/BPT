import unittest
import numpy as np
from .metrics import measure,supported,rolling_range

class ExactGeometryTests(unittest.TestCase):
 def test_thorax_hip_definition_and_scale_translation_invariance(self):
  rng=np.random.default_rng(17582);j=rng.normal(size=(32,17,3));a=measure(j);b=measure(j*7+np.array([3,2,-9]))
  for name in a:np.testing.assert_allclose(a[name],b[name],rtol=0,atol=1e-10,equal_nan=True)
  changed=j.copy();changed[:,11]+=20
  np.testing.assert_array_equal(a['leftHipDeg'],measure(changed)['leftHipDeg'])
 def test_missing_other_wrist_does_not_erase_known_leg(self):
  values=measure(np.random.default_rng(7).normal(size=(4,17,3)));score=np.ones((4,17));score[:,16]=np.nan
  support=supported(values,score,np.zeros((4,17),bool),.5)
  self.assertTrue(support['leftKneeDeg'].all());self.assertFalse(support['rightElbowDeg'].any())
 def test_rolling_window_never_bridges_missing_support(self):
  t=np.arange(10)*.1;v=np.arange(10)*10.;support=np.ones(10,bool);support[5]=False
  _,valid=rolling_range(v,t,support,seconds=.2)
  self.assertTrue(valid[3]);self.assertFalse(valid[5]);self.assertFalse(valid[6]);self.assertTrue(valid[9])
 def test_nonfinite_initial_timestamp_cannot_fake_complete_zero_range(self):
  value,valid=rolling_range([1.],[np.nan],seconds=.2)
  self.assertFalse(valid[0]);self.assertTrue(np.isnan(value[0]))
 def test_camera_torso_circular_crossing_not_358_range(self):
  value,valid=rolling_range([179,-179,-178],[0,.1,.2],seconds=.2)
  self.assertTrue(valid[-1]);self.assertAlmostEqual(value[-1],3)

if __name__=='__main__':unittest.main()
