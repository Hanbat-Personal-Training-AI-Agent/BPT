"""Independent synthetic criteria decisions; no labels, files, models or app state."""
import copy
import json
import math
import unittest
from scripts.coaching_criteria import evaluate, CATALOG


def request(aggregation='max',values=(80,90,100)):
    c=CATALOG['leftUpperArmDeg'].contract()
    identity={'metricId':c['metricId'],'metricVersion':c['version'],'definitionHash':c['definitionHash'],'unit':c['unit'],'coordinate':c['coordinate'],'aggregation':aggregation}
    scope={'sourceIdentity':{'inputSha256':'synthetic-input','sourceCommit':'synthetic-source','modelSha256':'synthetic-model','epoch':'set1','clockId':'clip-pts'},'selectedSide':'left','timeBasis':'source_pts_seconds','startPts':0,'endPts':.2,'phase':'descending','side':'left','view':'side','coverageComplete':True,'coverageEvidence':{'phaseStartObserved':True,'phaseEndObserved':True,'membershipSource':'synthetic-membership'},'expectedSourceIndices':list(range(len(values)))}
    samples=[{'sourceIndex':i,'pts':i*.1,'side':'left','phase':'descending','view':'side','available':True,'value':v,'rawValue':v} for i,v in enumerate(values)]
    o={**identity,'scope':scope,'samples':samples,'available':True,'blockingReasons':[], 'rawValue':values[-1],'correctedValue':values[-1], 'confidence':1.3,
       'support':{'requiredJointsSupported':True,'trackingObserved':True,'rawCorrectionChecked':True,'maximumCorrectionDifference':10}}
    p={**identity,'ruleId':'a','exercise':'pushup','variant':'floor','comparator':'gt','upper':95,'referenceKind':'engineering_candidate','predicateMeaning':'deviation','revision':'r1','source':'synthetic reviewed engineering fixture', 'availableAtPts':0,
       'applicability':{'phase':['descending'],'side':['left'],'view':['side']},'confirmation':{'kind':'engineering_review','at':'2026-11-02','reference':'synthetic test only','scope':{**identity,'ruleId':'a','exercise':'pushup','variant':'floor'}}}
    return {'evaluation':{'mode':'causal','asOfPts':.2},'exercise':'pushup','variant':'floor','observations':{'o':o},'profiles':{'p':p},'criterion':{'type':'atom','id':'a','observation':'o','profile':'p'}}


def decision(r):return evaluate(r)['criterion']
def combined(r,op):
    r=copy.deepcopy(r);r['criterion']={'type':'group','id':'g','op':op,'pairing':{'sidePolicy':'same_selected_side','temporal':'simultaneous'},'children':[r['criterion'],{'type':'atom','id':'b','observation':'missing'}]};return r


class CriteriaTests(unittest.TestCase):
    def test_supported_positive_and_zero_clock_confidence_not_probability(self):
        r=request();o=decision(r);self.assertEqual(o['state'],'positive_evidence');self.assertEqual(o['interpretation'],'candidate_predicate')
        self.assertEqual(o['observed']['confidence'],1.3);self.assertEqual(o['scope']['startPts'],0)
    def test_no_profile_preserves_all_metrics(self):
        r=request();r['profiles']={};v=evaluate(r)
        self.assertEqual(v['providedObservations'],r['observations']);self.assertIn('profile_required',v['criterion']['reasons'])
        self.assertNotIn('validated',v);self.assertNotIn('wholeFormNormal',v)
    def test_or_knownpositive_plus_unknown_preserved(self):
        d=decision(combined(request(),'OR'));self.assertEqual(d['state'],'positive_evidence');self.assertTrue(d['partialCoverage']);self.assertEqual(d['knownComponents'],['a'])
    def test_and_knownpositive_plus_unknown_withheld_component_retained(self):
        d=decision(combined(request(),'AND'));self.assertEqual(d['state'],'unknown');self.assertEqual(d['children'][0]['state'],'positive_evidence')
    def test_or_negative_unknown_not_negative(self):
        r=request(values=(10,20,30));self.assertEqual(decision(combined(r,'OR'))['state'],'unknown')
    def test_and_negative_component_retained_without_matching_other_scope(self):
        r=request(values=(10,20,30));d=decision(combined(r,'AND'));self.assertEqual(d['state'],'unknown');self.assertEqual(d['children'][0]['state'],'negative_evidence');self.assertTrue(d['partialCoverage'])
    def test_bool_not_number(self):
        r=request();r['profiles']['p']['upper']=True;self.assertIn('invalid_or_nonfinite_bounds',decision(r)['reasons'])
        r=request();r['observations']['o']['samples'][0]['value']=True;self.assertEqual(decision(r)['state'],'unknown')
    def test_nonfinite_rejected_before_decision(self):
        for x in [float('nan'),float('inf'),-float('inf')]:
            r=request();r['profiles']['p']['upper']=x
            with self.assertRaises(ValueError):evaluate(r)
    def test_reversed_bounds(self):
        r=request();r['profiles']['p'].update(comparator='inside',lower=110,upper=90);self.assertIn('invalid_or_nonfinite_bounds',decision(r)['reasons'])
    def test_duplicate_ids_samples_and_pts(self):
        r=combined(request(),'OR');r['criterion']['children'][1]['id']='a'
        with self.assertRaises(ValueError):evaluate(r)
        for field in ['sourceIndex','pts']:
            r=request();r['observations']['o']['samples'][1][field]=r['observations']['o']['samples'][0][field];self.assertEqual(decision(r)['state'],'unknown')
    def test_target_identity_mismatch_cannot_qualify(self):
        for field in ['metricVersion','definitionHash','unit','coordinate']:
            r=request();r['profiles']['p'][field]='other';self.assertEqual(decision(r)['state'],'unknown')
    def test_approved_boolean_cannot_replace_review_metadata(self):
        r=request();p=r['profiles']['p'];p['approved']=True;p.pop('confirmation');p['referenceKind']='explicit_target'
        self.assertEqual(decision(r)['state'],'unknown')
    def test_explicit_target_is_only_scoped_match(self):
        r=request();r['profiles']['p']['referenceKind']='explicit_target';d=decision(r)
        self.assertEqual(d['interpretation'],'scoped_target_predicate');self.assertNotIn('validated',d)
    def test_inside_outside_are_neutral_supplied_predicates_not_form_labels(self):
        r=request();p=r['profiles']['p'];p.update(referenceKind='explicit_target',comparator='inside',lower=70,upper=110,predicateMeaning='desired_match')
        self.assertEqual(decision(r)['state'],'positive_evidence');self.assertEqual(decision(r)['predicateMeaning'],'desired_match')
        p.update(comparator='outside',predicateMeaning='deviation');self.assertEqual(decision(r)['state'],'negative_evidence')
        p['upper']=95;self.assertEqual(decision(r)['state'],'positive_evidence');self.assertEqual(decision(r)['interpretation'],'scoped_target_predicate')
    def test_review_scope_and_profile_availability(self):
        r=request();r['profiles']['p']['confirmation']['scope']['variant']='kneeling';self.assertIn('review_scope_mismatch_or_missing',decision(r)['reasons'])
        r=request();r['profiles']['p']['availableAtPts']=.1;self.assertIn('future_or_unknown_profile_availability',decision(r)['reasons'])
    def test_unsupported_raw_correction_positive_never_survives_or(self):
        r=request();r['observations']['o']['samples'][2]['rawValue']=20
        d=decision(combined(r,'OR'));self.assertEqual(d['state'],'unknown');self.assertIn('raw_correction_disagreement',d['children'][0]['reasons'])
    def test_context_transition_blocks_combination_and_sustain(self):
        for key,new in [('side','right'),('phase','ascending'),('view','front')]:
            r=request();r['observations']['o']['samples'][1][key]=new;self.assertIn('context_transition_in_window',decision(r)['reasons'])
    def test_partial_max_known_exceedance_but_not_negative(self):
        r=request();r['observations']['o']['scope']['coverageComplete']=False;self.assertEqual(decision(r)['state'],'positive_evidence')
        r=request(values=(10,20,30));r['observations']['o']['scope']['coverageComplete']=False;self.assertEqual(decision(r)['state'],'unknown')
    def test_partial_min_and_rom_may_reverse_never_decide(self):
        for agg in ['min','rom','delta']:
            for upper in [1,200]:
                r=request(agg);r['profiles']['p']['upper']=upper;r['observations']['o']['scope']['coverageComplete']=False
                self.assertEqual(decision(r)['state'],'unknown')
    def test_complete_min_rom_and_delta(self):
        for agg,expected in [('min',80),('rom',20),('delta',20)]:
            r=request(agg);self.assertEqual(decision(r)['evaluatedValue'],expected)
    def test_expected_membership_not_scalar_coverage_claim(self):
        r=request('rom');r['observations']['o']['scope']['expectedSourceIndices']=[0,1,2,3];self.assertEqual(decision(r)['state'],'unknown')
    def test_sustain_uses_actual_pts_not_count_and_no_gap_bridge(self):
        r=request(values=(100,100,100));r['profiles']['p'].update(sustainSeconds=.15,maximumGapSeconds=.11)
        self.assertEqual(decision(r)['state'],'positive_evidence')
        r['observations']['o']['samples'][1]['available']=False;r['observations']['o']['scope']['coverageComplete']=False
        self.assertEqual(decision(r)['state'],'unknown')
        r=request(values=(100,100,100));r['profiles']['p'].update(sustainSeconds=.15,maximumGapSeconds=.05)
        self.assertEqual(decision(r)['supportedDurationSeconds'],0)
    def test_sustain_short_window_cannot_certify_negative(self):
        r=request(values=(100,100,100));r['profiles']['p'].update(sustainSeconds=.5,maximumGapSeconds=.11)
        self.assertEqual(decision(r)['state'],'unknown')
    def test_sustain_does_not_bridge_source_index_gap(self):
        r=request(values=(100,100,100));r['profiles']['p'].update(sustainSeconds=.15,maximumGapSeconds=.11)
        r['observations']['o']['samples'][1]['sourceIndex']=4;r['observations']['o']['samples'][2]['sourceIndex']=5
        self.assertEqual(decision(r)['state'],'unknown')
    def test_first3_relative_only_and_future_reference_forbidden(self):
        r=request();o=r['observations']['o'];p=r['profiles']['p'];p['referenceKind']='observed_first3';p['availableAtPts']=-1
        refs=[{**{k:o[k] for k in ['metricId','metricVersion','definitionHash','unit','coordinate','aggregation']},'id':str(i),'repIndex':i+1,'endPts':-3+i,'value':100,'available':True,'coverageComplete':True,'context':{k:o['scope'][k] for k in ['sourceIdentity','selectedSide','side','phase','view']}} for i in range(3)]
        p['references']=refs;d=decision(r);self.assertEqual(d['evaluatedValue'],0);self.assertEqual(d['interpretation'],'relative_change_predicate');self.assertEqual(d['state'],'negative_evidence')
        p['references'][2]['endPts']=0;self.assertEqual(decision(r)['state'],'unknown')
    def test_scope_mismatch_and_unknown_enums(self):
        r=request();r['observations']['o']['scope']['view']='unknown';self.assertEqual(decision(r)['state'],'unknown')
        r=request();r['profiles']['p']['referenceKind']='research_condition';self.assertEqual(decision(r)['state'],'unknown')
    def test_supported_max_positive_survives_other_missing_sample(self):
        r=request();r['observations']['o']['samples'][0].update(available=False,blockingReasons=['low_support'])
        d=decision(r);self.assertEqual(d['state'],'positive_evidence');self.assertTrue(d['partialCoverage']);self.assertIn('low_support',d['sampleEvidence'][0]['reasons'])
    def test_not_applicable_is_distinct_from_negative(self):
        r=request();r['exercise']='squat';self.assertEqual(decision(r)['state'],'not_applicable')
    def test_future_frame_and_missing_phase_span_evidence(self):
        r=request();r['evaluation']['asOfPts']=.1;self.assertIn('future_observation_window',decision(r)['reasons'])
        r=request('min');r['observations']['o']['scope'].pop('coverageEvidence');self.assertEqual(decision(r)['state'],'unknown')
    def test_strict_json_duplicate_and_constant_rejection(self):
        from scripts.coaching_criteria.json_contract import loads
        for text in ['{"x":1,"x":2}','{"x":NaN}','{"x":Infinity}']:
            with self.assertRaises(ValueError):loads(text)
    def test_arithmetic_overflow_is_unknown_not_infinite_evidence(self):
        r=request('rom',values=(-1e308,0,1e308));d=decision(r);self.assertEqual(d['state'],'unknown');self.assertIn('arithmetic_overflow',d['reasons'])
    def test_profile_fingerprint_decimal_and_unicode_parity(self):
        for number in [95.0, 1e-4, 1e-5, 1e15, 1e16, 1.2345678901234567e-4, 1e100]:
            r=request();r['profiles']['p']['upper']=number
            self.assertEqual(len(decision(r)['profileIntegrityHash']),64)
        r=request();r['profiles']['p']['source']='한글 😀 / é';self.assertEqual(len(decision(r)['profileIntegrityHash']),64)
    def test_confirmation_requires_strings(self):
        for field in ['kind','at','reference']:
            r=request();r['profiles']['p']['confirmation'][field]=True
            self.assertIn('confirmation_metadata_required',decision(r)['reasons'])
    def test_overflowing_sample_offset_cannot_prove_positive(self):
        r=request(values=(-1e308,0,1e308));p=r['profiles']['p'];p['referenceKind']='observed_first3'
        o=r['observations']['o'];o['scope'].update(startPts=10,endPts=10.2);r['evaluation']['asOfPts']=10.2
        for sample in o['samples']:sample['pts']+=10
        p['references']=[{**{k:o[k] for k in ['metricId','metricVersion','definitionHash','unit','coordinate','aggregation']},'id':f'r{i}','repIndex':i,'endPts':i,'value':-1e308,'available':True,'coverageComplete':True,'context':copy.deepcopy(o['scope'])} for i in [1,2,3]]
        d=decision(r);self.assertEqual(d['state'],'unknown');self.assertIn('arithmetic_overflow',d['reasons'])
    def test_tree_budgets(self):
        r=request();node=r['criterion']
        for i in range(18):node={'type':'group','id':str(i),'op':'OR','children':[node]}
        r['criterion']=node
        with self.assertRaises(ValueError):evaluate(r)
        r=request();r['criterion']={'type':'group','id':'root','op':'OR','children':[{'type':'atom','id':str(i),'observation':'missing'} for i in range(130)]}
        with self.assertRaises(ValueError):evaluate(r)
    def test_all_outputs_json_compatible(self):
        json.dumps(evaluate(combined(request(),'AND')),allow_nan=False)

class PairingTests(unittest.TestCase):
    def pair(self):
        r=request();r['observations']['o2']=copy.deepcopy(r['observations']['o']);r['profiles']['p2']=copy.deepcopy(r['profiles']['p'])
        r['profiles']['p2']['ruleId']='b';r['profiles']['p2']['confirmation']['scope']['ruleId']='b'
        r['criterion']={'type':'group','id':'g','op':'AND','pairing':{'sidePolicy':'same_selected_side','temporal':'simultaneous'},'children':[r['criterion'],{'type':'atom','id':'b','observation':'o2','profile':'p2'}]}
        return r
    def test_cross_clip_or_does_not_become_current_aggregate_warning(self):
        r=self.pair();r['criterion']['op']='OR';r['observations']['o2']['scope']['sourceIdentity']['inputSha256']='other'
        d=decision(r);self.assertEqual(d['state'],'unknown');self.assertEqual(d['children'][0]['state'],'positive_evidence');self.assertIn('conflicting_known_component_contexts',d['reasons'])
    def test_nested_summary_carries_actual_membership(self):
        r=self.pair();r['criterion']['pairing']['temporal']='same_window_summary';child=copy.deepcopy(r['criterion'])
        for node in child['children']:node['id']='nested-'+node['id'];r['profiles'][node['profile']]['ruleId']=node['id'];r['profiles'][node['profile']]['confirmation']['scope']['ruleId']=node['id']
        child['id']='nested';r['criterion']={'type':'group','id':'outer','op':'AND','pairing':{'sidePolicy':'same_selected_side','temporal':'same_window_summary'},'children':[child]}
        d=decision(r);self.assertEqual(d['state'],'positive_evidence');self.assertTrue(d['sampleMembership'])
        r['observations']['o2']['scope']['startPts']=-1;self.assertEqual(decision(r)['state'],'unknown')
    def test_nested_or_knownpositive_missing_can_support_outer_and(self):
        r=self.pair();left=r['criterion']['children'][0];r['criterion']['children'][0]={'type':'group','id':'inner','op':'OR','children':[left,{'type':'atom','id':'missing','observation':'absent'}]}
        d=decision(r);self.assertEqual(d['state'],'positive_evidence');self.assertTrue(d['partialCoverage'])
    def test_sustained_evidence_does_not_pair_isolated_earlier_blip(self):
        r=self.pair()
        for key,values in [('o',[100,0,100,100,100]),('o2',[100,0,0,0,0])]:
            o=r['observations'][key];o['scope']['endPts']=.4;o['scope']['expectedSourceIndices']=list(range(5))
            template=o['samples'][0]
            o['samples']=[{**template,'sourceIndex':i,'pts':i*.1,'value':v,'rawValue':v} for i,v in enumerate(values)]
        r['evaluation']['asOfPts']=.4;r['profiles']['p'].update(sustainSeconds=.15,maximumGapSeconds=.11)
        d=decision(r);self.assertEqual(d['children'][0]['state'],'positive_evidence');self.assertEqual(d['state'],'unknown')
        self.assertEqual([x['sourceIndex'] for x in d['children'][0]['supportedPositiveSamples']],[2,3,4])
        r['observations']['o2']['samples'][3].update(value=100,rawValue=100)
        self.assertEqual(decision(r)['state'],'positive_evidence')
    def test_nested_summary_or_cannot_become_simultaneous_sample(self):
        r=self.pair();o=r['observations']['o'];o['aggregation']='rom'
        p=r['profiles']['p'];p['aggregation']='rom';p['confirmation']['scope']['aggregation']='rom';p['upper']=10
        left=r['criterion']['children'][0]
        r['criterion']['children'][0]={'type':'group','id':'summary-or','op':'OR','children':[left,{'type':'atom','id':'missing','observation':'absent'}]}
        d=decision(r);self.assertEqual(d['children'][0]['state'],'positive_evidence');self.assertEqual(d['state'],'unknown')
        self.assertIn('summary_metric_requires_same_window_contract',d['reasons'])
        r['criterion']['pairing']['temporal']='same_window_summary';self.assertEqual(decision(r)['state'],'positive_evidence')
    def test_same_samples_positive_pair(self):
        self.assertEqual(decision(self.pair())['state'],'positive_evidence')
    def test_different_clip_same_pts_never_pairs(self):
        for key in ['inputSha256','sourceCommit','modelSha256','epoch','clockId']:
            r=self.pair();r['observations']['o2']['scope']['sourceIdentity'][key]='different'
            self.assertEqual(decision(r)['state'],'unknown')
    def test_different_positive_timestamps_not_simultaneous(self):
        r=self.pair();r['observations']['o']['samples'][0].update(value=100,rawValue=100);r['observations']['o']['samples'][2].update(value=80,rawValue=80)
        self.assertEqual(decision(r)['state'],'unknown')
        r['criterion']['pairing']['temporal']='same_window_summary';self.assertEqual(decision(r)['state'],'positive_evidence')
    def test_explicit_bilateral_pair_not_implicit_side_relaxation(self):
        r=self.pair();o=r['observations']['o2'];p=r['profiles']['p2'];spec=CATALOG['rightUpperArmDeg'].contract()
        for v in [o,p,p['confirmation']['scope']]:v.update(metricId=spec['metricId'],definitionHash=spec['definitionHash'])
        o['scope']['side']='right'
        for sample in o['samples']:sample['side']='right'
        p['applicability']['side']=['right']
        self.assertEqual(decision(r)['state'],'unknown')
        r['criterion']['pairing']['sidePolicy']='bilateral';self.assertEqual(decision(r)['state'],'positive_evidence')
    def test_sample_blocking_reason_cannot_qualify(self):
        r=self.pair();r['observations']['o2']['samples'][2]['blockingReasons']=['low_support']
        self.assertEqual(decision(r)['state'],'unknown')
    def test_summary_metrics_require_explicit_window_not_instant_pairing(self):
        r=self.pair()
        for o in r['observations'].values():o['aggregation']='rom'
        for p in r['profiles'].values():p['aggregation']='rom';p['confirmation']['scope']['aggregation']='rom';p['upper']=10
        self.assertEqual(decision(r)['state'],'unknown')
        r['criterion']['pairing']['temporal']='same_window_summary';self.assertEqual(decision(r)['state'],'positive_evidence')
    def test_mixed_meanings_remain_labelled_not_good_or_bad(self):
        r=self.pair();r['profiles']['p2']['predicateMeaning']='desired_match';d=decision(r)
        self.assertEqual(d['state'],'positive_evidence');self.assertEqual(set(d['predicateMeanings']),{'deviation','desired_match'});self.assertEqual(d['interpretation'],'compound_supplied_predicates_only')
    def test_malformed_profiles_scopes_samples_rejected_honestly(self):
        for bad in [[], 'bad', 1]:
            r=request();r['profiles']['p']=bad;self.assertEqual(decision(r)['state'],'unknown')
            r=request();r['observations']['o']['scope']=bad;self.assertEqual(decision(r)['state'],'unknown')
        r=request();r['observations']['o']['samples']=['bad'];self.assertEqual(decision(r)['state'],'unknown')

if __name__=='__main__':unittest.main()
