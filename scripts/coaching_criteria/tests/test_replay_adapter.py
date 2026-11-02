import copy
import unittest
from scripts.coaching_criteria.replay_adapter import frame_request, PINNED
from scripts.coaching_criteria import evaluate

class ReplayAdapterTests(unittest.TestCase):
    def frame(self):
        return {'source':{'source_pts':0,'source_index':0,'epoch':1,'time_basis':'sample_pts_seconds'},
                'context':{'exercise':'pushup','phase':'descending','side':'left','side_view':True,'flush_tail':False,'gravitySynchronized':False},
                'metrics':{'leftUpperArmDeg':{**copy.deepcopy(PINNED['leftUpperArmDeg']),'value':100,'rawValue':95,'available':True,'reasons':[],'qualifiers':[]}}}
    def test_actual_schema_bridge_preserves_original_and_no_profile(self):
        frame=self.frame();r=frame_request(frame,'input');result=evaluate(r);o=result['providedObservations']['leftUpperArmDeg']
        self.assertEqual(o['originalReplayMetric'],frame['metrics']['leftUpperArmDeg']);self.assertTrue(o['sourceBindingExact'])
        self.assertEqual(o['correctedValue'],100);self.assertIn('profile_required',result['criterion']['children'][0]['reasons'])
    def test_definition_mismatch_not_aliased(self):
        frame=self.frame();frame['metrics']['leftUpperArmDeg']['coordinateSpace']='research_anatomical_shoulder_angle'
        o=frame_request(frame,'input')['observations']['leftUpperArmDeg'];self.assertFalse(o['sourceBindingExact']);self.assertIn('replay_definition_mismatch',o['blockingReasons'])
    def test_unknown_metric_kept_not_deleted(self):
        frame=self.frame();frame['metrics']['unknownProxy']=frame['metrics'].pop('leftUpperArmDeg');r=evaluate(frame_request(frame,'input'))
        self.assertIn('unknownProxy',r['providedObservations']);self.assertIn('unknown_metric_definition',r['criterion']['children'][0]['reasons'])

if __name__=='__main__':unittest.main()
