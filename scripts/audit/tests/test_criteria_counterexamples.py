"""Independent synthetic counterexamples against frozen production geometry.
No media, inference, device, annotation or approved-correct reference is used.
"""
import copy
import sys
import unittest
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'server/calibration_modal'))
import deep_metrics as dm


def fixture(exercise='squat', count=4):
    n=count*30
    j=np.zeros((n,17,3))
    for hip,x in [(1,-.2),(4,.2)]:
        j[:,hip]=[x,1,0];j[:,hip+1]=[x,.5,0]
        a=np.deg2rad(np.tile(np.r_[np.linspace(10,60,16),np.linspace(60,10,15)[1:]],count))
        j[:,hip+2]=np.stack([np.full(n,x),.5-.5*np.cos(a),.5*np.sin(a)],axis=1)
    for shoulder,x in [(11,.2),(14,-.2)]:
        j[:,shoulder]=[x,1.5,0];j[:,shoulder+1]=[x,1.25,.1]
        a=np.deg2rad(np.tile(np.r_[np.linspace(10,60,16),np.linspace(60,10,15)[1:]],count))
        j[:,shoulder+2]=j[:,shoulder+1]+np.stack([np.zeros(n),-.25*np.cos(a),.25*np.sin(a)],axis=1)
    m={'exerciseId':exercise,'reps':[{'repIndex':i+1,'startMs':1000*i,'endMs':1000*(i+1),'side':'left','onDeviceWarnings':[]} for i in range(count)]}
    return j,m


def evaluate(j,m,**kw):
    return dm.metrics(j,30,m,joint_confidence=kw.pop('joint_confidence',np.full((len(j),17),.9)),tracked_mask=kw.pop('tracked_mask',np.ones(len(j),bool)),**kw)


class ProductionCounterexamples(unittest.TestCase):
    def test_first_three_same_bad_depth_is_relative_not_correctness(self):
        for exercise in ['squat','pushup','barbell-row']:
            with self.subTest(exercise=exercise):
                j,m=fixture(exercise);r=evaluate(j,m)
                for rep in r['reps'][:3]:
                    self.assertEqual(rep['metricValidity']['depthDriftDeg']['assessment'],'withheld')
                    self.assertIn('requires_baseline_reps',rep['metricValidity']['depthDriftDeg']['reasons'])
                self.assertEqual(r['reps'][3]['fatigueDrift']['depthDriftDeg'],0)
                # Equal relative depth despite deliberately limited excursion provides no approved form label.
                self.assertNotIn('approvedCorrect',r['reps'][3])

    def test_interval_is_start_inclusive_end_exclusive(self):
        j,m=fixture();a=evaluate(j,m)['reps'][0]['anglesDeg']['knee']
        # Collapsed sample exactly at end=1000ms belongs to rep2, not rep1.
        j[30,5]=j[30,4];r=evaluate(j,m)
        self.assertEqual(r['reps'][0]['anglesDeg']['knee'],a)
        self.assertIsNone(r['reps'][1]['anglesDeg']['knee']['min'])
        j,m=fixture();j[0,5]=j[0,4]
        self.assertIsNone(evaluate(j,m)['reps'][0]['anglesDeg']['knee']['min'])

    def test_fractional_boundary_uses_ceil_without_host_clock(self):
        j,m=fixture();m['reps']=m['reps'][:1];m['reps'][0].update(startMs=1,endMs=1001)
        j[0,5]=j[0,4]
        self.assertIsNotNone(evaluate(j,m)['reps'][0]['anglesDeg']['knee']['min'])
        j[30,5]=j[30,4]
        self.assertIsNone(evaluate(j,m)['reps'][0]['anglesDeg']['knee']['min'])

    def test_selected_side_not_majority_or_confidence_fallback(self):
        j,m=fixture();j[:,2]=j[:,1]  # right leg invalid; declared left remains usable
        r=evaluate(j,m);self.assertIsNotNone(r['reps'][0]['depthAngleDeg'])
        for rep in m['reps']:rep['side']='right'
        self.assertIsNone(evaluate(j,m)['reps'][0]['depthAngleDeg'])

    def test_missing_primary_preserves_known_other_joint(self):
        j,m=fixture();j[10,5]=j[10,4];r=evaluate(j,m)['reps'][0]
        self.assertIsNone(r['romDeg']);self.assertEqual(r['metricValidity']['romDeg']['assessment'],'withheld')
        self.assertIsNotNone(r['anglesDeg']['elbow']['min'])
        self.assertEqual(r['metricValidity']['elbow']['assessment'],'available')
        self.assertIsNone(r['anglesDeg']['elbow']['top'])  # primary-selected phase unavailable

    def test_zero_valid_trunk_is_distinct_from_missing(self):
        j,m=fixture();r=evaluate(j,m)['reps'][0]
        self.assertEqual(r['anglesDeg']['torso']['min'],0)
        self.assertEqual(r['metricValidity']['trunkStdDeg']['assessment'],'available')
        j[:,11]=(j[:,1]+j[:,4])/2;j[:,14]=j[:,11]
        r=evaluate(j,m)['reps'][0]
        self.assertIsNone(r['anglesDeg']['torso']['min'])
        self.assertEqual(r['metricValidity']['trunkStdDeg']['assessment'],'withheld')

    def test_future_rep_cannot_change_prior_numeric_metrics(self):
        j,m=fixture(count=5);before=evaluate(j,m)['reps'][:4]
        j[120:,6]+=[0,0,5];after=evaluate(j,m)['reps'][:4]
        self.assertEqual(before,after)

    def test_mirror_preserves_angles_but_not_anatomical_labels_implicitly(self):
        j,m=fixture();a=evaluate(j,m);j[:,:,0]*=-1;b=evaluate(j,m)
        self.assertEqual([x['anglesDeg'] for x in a['reps']],[x['anglesDeg'] for x in b['reps']])
        # Reflection alone is not a left/right relabel operation.
        self.assertEqual(b['reps'][0]['side'],'left')

    def test_rotation_requires_declared_gravity_frame(self):
        j,m=fixture();a=evaluate(j,m)['reps'][0]
        rotated=j[:,:,[0,2,1]].copy();rotated[:,:,1]*=-1;b=evaluate(rotated,m)['reps'][0]
        self.assertEqual(a['anglesDeg']['knee'],b['anglesDeg']['knee'])
        self.assertNotEqual(a['anglesDeg']['torso']['min'],b['anglesDeg']['torso']['min'])

    def test_root_relative_cannot_establish_world_vertical_motion(self):
        j,m=fixture();delta=np.linspace(0,.5,len(j));j[:,:,1]+=delta[:,None]
        a=evaluate(j,m)['reps'][0];root=j-(j[:,1:2]+j[:,4:5])/2;b=evaluate(root,m)['reps'][0]
        self.assertGreater(a['depthMeters'],0);self.assertEqual(b['depthMeters'],0)
        self.assertEqual(a['anglesDeg'],b['anglesDeg'])

if __name__=='__main__':unittest.main()
