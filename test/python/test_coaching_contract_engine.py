"""Synthetic contract arithmetic tests, never measured posture accuracy."""
import copy
import math
import unittest
from scripts.coaching_contract.contract import SCHEMA, digest, loads
from scripts.coaching_contract.engine import evaluate, compare


def sample(angles=(60, 60, 60, 90), exercise='pushup'):
    frames, reps = [], []
    chain = (14, 15, 16) if exercise == 'pushup' else (1, 2, 3)
    for i, degrees in enumerate(angles):
        joints = [None] * 51
        points = [(1,0,0), (0,0,0), (math.cos(math.radians(degrees)), math.sin(math.radians(degrees)),0)]
        for joint, point in zip(chain, points):
            joints[joint*3:joint*3+3] = point
        frames.append({'id': i, 'time': {'seconds': i+0.5}, 'side': 'right', 'phase': 'bottom',
                       'view_eligible': True, 'joints': joints, 'uncertainty_known': True,
                       'chain_support': {'elbow': True, 'knee': True}})
        reps.append({'id': i+1, 'ordinal': i+1, 'frame_ids': [i], 'span_complete': True,
                     'original_interval': {'start': i, 'end': i, 'closure': 'closed', 'unit':'native_frame_index'},
                     'runtime': {'state': 'missing'}, 'delivery': {'state':'missing'}})
    return {'schema': SCHEMA, 'exercise': exercise, 'criterion_scope':'relative_drift',
            'reference_kind':'observed_first3', 'target_profile':None,
            'first3_reference_identity':{'origin':'observed_set_start','set_id':'fixture','observation_sha256':'a'*64,'first3_rep_ids':[1,2,3]},
            'clip':{'observation_sha256':'a'*64,'media_sha256':None},
            'source':{'joint_definition':'BPT_H36M17','coordinate_frame':'camera_x_right_y_down_z_away_pelvis_relative','pose_units':'h36m17_xs_model_space_no_metric_guarantee',
                      'layer_role':'assessment','side_policy':'actual_per_frame'},
            'clock':{'id':'synthetic_fixture'}, 'frames':frames,'reps':reps}


class EngineTests(unittest.TestCase):
    def test_first_three_bad_not_absolute_correct(self):
        out = evaluate(sample((60,60,60,60)))
        self.assertEqual(out['reps'][3]['qualified_shadow']['state'], 'no_warning')
        self.assertEqual(out['absolute_normality'], 'not_assessed')
        self.assertEqual(out['reference_correctness'], 'not_established')
        self.assertFalse(out['target_used'])
        self.assertEqual([r['qualified_shadow']['state'] for r in out['reps'][:3]], ['withheld']*3)

    def test_causal_exact_first3_both_rules(self):
        for exercise in ('pushup','squat'):
            s = sample(exercise=exercise)
            old = evaluate(s)['reps'][3]
            self.assertEqual(old['reference_ids'], [1,2,3])
            self.assertAlmostEqual(old['common_scalar']['value_deg'],30)
            self.assertEqual(old['qualified_shadow']['state'],'warning')
            extended = sample((60,60,60,90,160), exercise)
            self.assertEqual(old, evaluate(extended)['reps'][3])

    def test_unrelated_missing_does_not_erase_positive(self):
        s = sample()
        # Almost all unrelated joints are missing by construction.
        self.assertEqual(evaluate(s)['reps'][3]['qualified_shadow']['state'], 'warning')

    def test_required_gap_preserves_observed_positive_and_runtime(self):
        s = sample()
        f = copy.deepcopy(s['frames'][-1]);f['id']=4;f['time']['seconds']=4.5;f['joints']=None
        s['frames'].append(f);s['reps'][-1]['frame_ids'].append(4);s['reps'][-1]['original_interval']['end']=4
        s['reps'][-1]['runtime']={'state':'warning','key':'pushup_shallow'}
        r=evaluate(s)['reps'][-1]
        self.assertEqual(r['qualified_shadow']['state'],'withheld')
        self.assertTrue(r['common_scalar']['observed_subset_predicate'])
        self.assertEqual(r['runtime']['state'],'warning')

    def test_silence_not_negative(self):
        r=evaluate(sample())['reps'][-1]
        self.assertEqual(r['runtime']['state'],'missing')
        self.assertEqual(r['delivery']['state'],'missing')

    def test_view_side_phase_support_uncertainty_missing(self):
        for field, value, reason in [('side',None,'side_missing'),('view_eligible',None,'view_missing'),
                                      ('view_eligible',False,'view_ineligible'),('phase',None,'phase_history_missing_or_unknown'),
                                      ('uncertainty_known',None,'uncertainty_provenance_missing')]:
            s=sample();s['frames'][-1][field]=value
            r=evaluate(s)['reps'][-1]
            self.assertIn(reason,r['qualified_shadow']['reasons'])
            self.assertEqual(r['qualified_shadow']['state'],'withheld')
        s=sample();s['frames'][0]['chain_support']['elbow']=None
        self.assertIn('reference:required_chain_support_missing',evaluate(s)['reps'][-1]['qualified_shadow']['reasons'])

    def test_fixed_side_is_not_observed_history(self):
        s=sample();s['source']['side_policy']='fixed_manifest_policy'
        r=evaluate(s)['reps'][-1]
        self.assertTrue(r['common_scalar']['observed_subset_predicate'])
        self.assertIn('actual_side_history_missing',r['qualified_shadow']['reasons'])

    def test_overlap_reference_withheld(self):
        s=sample();s['reps'][0]['frame_ids']=[0,3];s['reps'][0]['span_complete']=False;s['reps'][0]['original_interval']['end']=3
        self.assertIn('reference_not_strictly_past',evaluate(s)['reps'][-1]['qualified_shadow']['reasons'])

    def test_source_comparison_never_parity(self):
        a=sample();b=sample();b['source']['coordinate_frame']='world'
        r=compare(evaluate(a),evaluate(b))
        self.assertFalse(r['same_source_provenance']);self.assertFalse(r['same_pose_asserted'])
        self.assertFalse(r['ground_truth']);self.assertFalse(r['semantic_parity_asserted'])
        self.assertIn('media_identity_missing',r['reps'][-1]['reasons'])
        self.assertEqual(r['reps'][-1]['descriptive_delta_deg'],0)
        b['clip']['media_sha256']='b'*64;a['clip']['media_sha256']='a'*64
        self.assertIn('different_media_bytes',compare(evaluate(a),evaluate(b))['reps'][-1]['reasons'])
        a['clip']['media_sha256']='b'*64;b['clock']={'id':'other'}
        self.assertIn('clock_mapping_unverified',compare(evaluate(a),evaluate(b))['reps'][-1]['reasons'])

    def test_closed_halfopen_preserved_not_silently_joined(self):
        a=sample();b=copy.deepcopy(a);b['clock']['frame_seconds_to_video_ms']=1000;b['reps'][-1]['original_interval'].update(closure='half_open',unit='video_ms',start=3000,end=4000)
        r=compare(evaluate(a),evaluate(b))['reps'][-1]
        self.assertIn('original_interval_mismatch',r['reasons'])
        self.assertEqual(r['left']['original_interval']['closure'],'closed')

    def test_profile_preserved_unused(self):
        s=sample();s['target_profile']={'id':'review-later','revision':'r1','source_provenance':'fixture','review_status':'unreviewed'}
        r=evaluate(s)
        self.assertEqual(r['target_profile'],s['target_profile']);self.assertFalse(r['target_used'])
        s['criterion_scope']='explicit_target'
        with self.assertRaisesRegex(ValueError,'scope_not_implemented'):evaluate(s)

    def test_structure_rejects_ambiguity(self):
        with self.assertRaisesRegex(ValueError,'duplicate_json_key'):loads('{"a":1,"a":2}')
        for mutate in (lambda s:s['frames'][0].update(id=True),
                       lambda s:s['frames'][0]['time'].update(seconds=float('nan')),
                       lambda s:s['frames'].append(s['frames'][-1]),
                       lambda s:s['reps'].append(s['reps'][-1])):
            s=sample();mutate(s)
            with self.assertRaises(ValueError):evaluate(s)
        self.assertEqual(digest(sample()),digest(sample()))

    def test_unsupported_not_negative(self):
        s=sample();s['exercise']='barbell-row'
        r=evaluate(s)
        self.assertEqual(len(r['reps']),4)
        self.assertTrue(all(x['qualified_shadow']=={'state':'withheld','reasons':['unsupported_exercise']} for x in r['reps']))

    def test_side_change_and_mixed_side_withhold_keep_scalar(self):
        s=sample(); f=s['frames'][-1]
        f['side']='left';f['joints'][33:42]=f['joints'][42:51]
        r=evaluate(s)['reps'][-1]
        self.assertIn('reference_current_side_mismatch',r['qualified_shadow']['reasons'])
        self.assertTrue(r['common_scalar']['observed_subset_predicate'])
        f=copy.deepcopy(f);f['id']=4;f['time']['seconds']=4.5;f['side']='right'
        s['frames'].append(f);s['reps'][-1]['frame_ids'].append(4);s['reps'][-1]['original_interval']['end']=4
        self.assertIn('mixed_actual_sides',evaluate(s)['reps'][-1]['qualified_shadow']['reasons'])

    def test_reference_ordinals_not_assumed_first3(self):
        s=sample()
        for r in s['reps']: r['ordinal']+=4
        self.assertIn('first3_reference_identity_unverified',evaluate(s)['reps'][-1]['qualified_shadow']['reasons'])

    def test_huge_finite_geometry_no_overflow_false_zero(self):
        from scripts.coaching_contract.engine import angle
        points=[None]*51
        for i,p in zip((14,15,16),((1e308,0,0),(-1e308,0,0),(0,1e308,0))): points[i*3:i*3+3]=p
        self.assertAlmostEqual(angle(points,(14,15,16)),45)

    def test_interval_selection_integrity(self):
        s=sample();s['reps'][0]['frame_ids']=[1]
        with self.assertRaisesRegex(ValueError,'outside_original'):evaluate(s)
        s=sample();s['reps'][0]['original_interval']['end']=1
        with self.assertRaisesRegex(ValueError,'incomplete_selection'):evaluate(s)
        s=sample();s['reps'][0]['original_interval'].update(unit='video_ms',closure='half_open',start=0,end=1000)
        with self.assertRaisesRegex(ValueError,'mapping_missing'):evaluate(s)

    def test_unknown_phase_and_coordinate_not_qualified(self):
        for v in ('','unknown'):
            s=sample();s['frames'][-1]['phase']=v
            self.assertIn('phase_history_missing_or_unknown',evaluate(s)['reps'][-1]['qualified_shadow']['reasons'])
        s=sample();s['source']['coordinate_frame']='arbitrary'
        self.assertIn('coordinate_or_units_missing',evaluate(s)['reps'][-1]['qualified_shadow']['reasons'])

    def test_reference_identity_requires_bound_capture_set(self):
        s=sample();s.pop('first3_reference_identity')
        self.assertIn('first3_reference_identity_unverified',evaluate(s)['reps'][-1]['qualified_shadow']['reasons'])
        s=sample();s['first3_reference_identity']['observation_sha256']='b'*64
        self.assertIn('first3_reference_identity_unverified',evaluate(s)['reps'][-1]['qualified_shadow']['reasons'])

    def test_wrong_phase_does_not_certify_depth_measurement(self):
        s=sample();s['frames'][-1]['phase']='top'
        r=evaluate(s)['reps'][-1]
        self.assertIn('bottom_phase_not_observed',r['qualified_shadow']['reasons'])
        self.assertTrue(r['common_scalar']['observed_subset_predicate'])

    def test_invalid_chain_explicit_mask_overrides_finite_coords(self):
        s=sample();s['frames'][-1]['invalid_joints']=[15]
        self.assertIsNone(evaluate(s)['reps'][-1]['observation']['minimum_deg'])

    def test_right_only_known_positive_preserved(self):
        a=evaluate(sample());b=evaluate(sample((60,60,60,90,100)))
        r=compare(a,b)['reps'][-1]
        self.assertEqual(r['id'],5);self.assertIsNone(r['left'])
        self.assertEqual(r['right']['qualified_shadow']['state'],'warning')
        self.assertIn('counterpart_missing',r['reasons'])
