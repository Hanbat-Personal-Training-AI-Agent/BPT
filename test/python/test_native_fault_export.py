"""Native-generated payloads plus explicitly adversarial contract mutations.

The temporary Git/binary/clip envelope is a unit-test envelope, never claimed as
real media execution. The checked-in frame/rule payload is emitted by Swift.
"""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/form_eval'))
import export_native_faults as ex
import import_predictions as imp
import independent_form_eval as ev

FIXTURE=Path(__file__).parent/'fixtures/native_fault_trace/native_pushup.jsonl'


def rows():
    return [json.loads(line) for line in FIXTURE.read_text().splitlines()]


def core_trace(exercise):
    path=FIXTURE.parent/('core_'+exercise+'.jsonl')
    trace=direct_trace([json.loads(line) for line in path.read_text().splitlines()])
    trace.exercise=exercise
    return trace


def direct_trace(records):
    trace=types.SimpleNamespace(exercise='pushup',failed_sources=set())
    trace.rows=records
    trace.frames={r['source']['frame']:r for r in records if r['type']=='frame'}
    trace.expected={s['sourceKey']:s for s in records[0]['expectedSourceManifest']}
    trace.reps={r['traceID']:r for r in records if r['type']=='rep'}
    trace.rep_sources=lambda rep:[trace.frames[f]['source'] for f in rep['frames2D']]
    trace.judges={j['traceID']:(r,j,source) for r in trace.reps.values()
                  for source,j in r['judgements'].items() if j}
    return trace


def decision(trace,rule,ordinal=0):
    rep=list(trace.reps.values())[ordinal]
    sources=trace.rep_sources(rep)
    sample={'sampleId':rule,'startSeconds':sources[0]['seconds'],'endSeconds':sources[-1]['seconds']}
    return ex.decision(trace,rep,rule,sample)


def rewrite(path,records):
    for index,row in enumerate(records):row['sequence']=index
    before=b''.join((json.dumps(r,sort_keys=True,separators=(',',':'))+'\n').encode() for r in records[:-1])
    footer=records[-1]
    footer.update(bytesBeforeFooter=len(before),recordsBeforeFooter=len(records)-1,
                  frameRecordsWritten=sum(r['type']=='frame' for r in records),
                  repRecordsWritten=sum(r['type']=='rep' for r in records))
    path.write_bytes(before+(json.dumps(footer,sort_keys=True,separators=(',',':'))+'\n').encode())


class NativePayloadTests(unittest.TestCase):
    def test_actual_native_fixture_has_honest_missing_phases_and_baselines(self):
        trace=direct_trace(rows());states=[]
        for ordinal in range(4):
            for rule in ex.CORE['pushup']:
                states.append(decision(trace,rule,ordinal)[0]['state'])
        self.assertEqual(states.count('no_warning'),17)
        self.assertEqual(states.count('withheld'),15)
        self.assertEqual(states.count('warning'),0)
        row,audit=decision(trace,'pushup_no_lockout')
        self.assertEqual(audit['disposition'],'required_phase_not_observed_top')

    def test_delivery_quiet_key_still_evaluates(self):
        row,audit=decision(direct_trace(rows()),'pushup_hip_pike')
        self.assertFalse(audit['deliveryEnabled'])
        self.assertEqual(row['state'],'no_warning')

    def test_missing_global_source_does_not_erase_unrelated_rep(self):
        records=rows();records=[r for r in records if r.get('source',{}).get('frame')!=11]
        row,_=decision(direct_trace(records),'pushup_hip_sag')
        self.assertEqual(row['state'],'no_warning')

    def test_gap_inside_negative_scope_withholds(self):
        trace=direct_trace(rows());del trace.frames[1]
        # Boundary sources survive; the gap cannot be bridged by endpoints.
        trace.rep_sources=lambda rep:[trace.frames[f]['source'] for f in (rep['startFrame'],rep['endFrame'])]
        row,audit=decision(trace,'pushup_hip_sag')
        self.assertEqual(row['state'],'withheld')
        self.assertEqual(audit['disposition'],'missing_source_frame')

    def test_unobserved_joint_and_unknown_view_never_negative(self):
        for mutate in ('joint','view','source'):
            trace=direct_trace(rows());sample=trace.frames[1]['sample2D']
            if mutate=='joint':sample['inputSupport']['jointEvidence'][11]['finiteCoordinates']=False
            if mutate=='view':sample['frontView']=None
            if mutate=='source':list(trace.reps.values())[0]['formSource']='3d_unavailable'
            with self.subTest(mutate=mutate):
                self.assertEqual(decision(trace,'pushup_hip_sag')[0]['state'],'withheld')

    def test_initial_inherited_facing_is_not_proven_by_finite_after(self):
        trace=direct_trace(rows())
        trace.frames[0]['sample2D']['inputSupport']['facing']['before']=1
        # Hand position needs top, so test its actual selector lineage directly.
        rep=list(trace.reps.values())[0];judge=rep['judgements']['2d']
        support=ex.Support(trace,rep,judge,'2d','pushup_hand_position')
        with self.assertRaisesRegex(ex.Unproven,'inherited_or_broken_facing_history'):
            support.metric('first_rep_top_wrist_ahead')

    def test_offered_missing_history_cannot_be_negative_max(self):
        trace=direct_trace(rows());rep=list(trace.reps.values())[1];judge=rep['judgements']['2d']
        # Mutation mimics compactMap's dangerous absent-metric row.
        del judge['history'][0]['metrics']['elbow_max']
        op=next(r for r in judge['rules'] if r['rule']=='pushup_no_lockout')['operands'][0]
        op['referenceEntries'][0]['value']=None
        # Native completeReference must be false for missing history.
        op['completeReference']=False
        support=ex.Support(trace,rep,judge,'2d','pushup_no_lockout')
        with self.assertRaisesRegex(ex.Unproven,'incomplete_reference'):
            support.references(op,False)

    def test_historical_view_is_checked_independently(self):
        trace=direct_trace(rows());rep=list(trace.reps.values())[3];judge=rep['judgements']['2d']
        first=list(trace.reps.values())[0]
        first['judgements']['2d']['view']['actualSideView']=False
        row,audit=decision(trace,'pushup_shallow',3)
        self.assertEqual(row['state'],'withheld')
        self.assertEqual(audit['disposition'],'wrong_native_view_branch')

    def test_trend_duplicate_positions_are_not_repaired(self):
        trace=direct_trace(rows());rep=list(trace.reps.values())[0];judge=rep['judgements']['2d']
        op=next(r for r in judge['rules'] if r['rule']=='pushup_depth_fade')['operands'][0]
        self.assertEqual([e['index'] for e in op['referenceEntries']],[0,0])
        with self.assertRaisesRegex(ex.Unproven,'incomplete_trend_reference'):
            ex.Support(trace,rep,judge,'2d','pushup_depth_fade').references(op,False)

    def test_failed_negative_sentinel_is_not_an_evaluated_frame(self):
        source=copy.deepcopy(rows()[0]['expectedSourceManifest'][0]);source['frame']=-1
        ex.validate_source(source,allow_failed_sentinel=True)
        with self.assertRaises(ev.ContractError):ex.validate_source(source)
        source['frame']=-7
        with self.assertRaises(ev.ContractError):ex.validate_source(source,allow_failed_sentinel=True)

    def test_all_twenty_catalogue_ids_are_processed_from_native_three_exercise_fixtures(self):
        seen=set();positive=set()
        for exercise,rules in ex.CORE.items():
            trace=core_trace(exercise)
            for ordinal in range(len(trace.reps)):
                for rule in rules:
                    row,audit=decision(trace,rule,ordinal);seen.add(rule)
                    self.assertNotIn('unsupported',audit['disposition'])
                    if row['state']=='warning':positive.add(rule)
        self.assertEqual(len(seen),20)
        self.assertTrue({'pushup_hip_sag','pushup_shallow','pushup_no_lockout','squat_hips_first',
                         'squat_no_lockout','row_torso_swing','row_shrug'}<=positive)

    def test_all_twenty_native_default_threshold_positive_paths_are_supported(self):
        positive=set()
        for case,exercise in (('pushup_side','pushup'),('squat_side','squat'),
                              ('squat_front','squat'),('row_side','barbell_row')):
            records=[json.loads(line) for line in (FIXTURE.parent/('coverage_v2_'+case+'.jsonl')).read_text().splitlines()]
            trace=direct_trace(records);trace.exercise=exercise
            for index,rep in enumerate(trace.reps.values()):
                for rule in ex.CORE[exercise]:
                    row,audit=decision(trace,rule,index)
                    native=next(r for r in rep['judgements']['2d']['rules'] if r['rule']==rule)
                    if native['condition'] is True:
                        with self.subTest(case=case,rep=index,rule=rule):
                            self.assertEqual(row['state'],'warning',audit['disposition'])
                        positive.add(rule)
        self.assertEqual(positive,set().union(*map(set,ex.CORE.values())))

    def test_pointwise_positive_survives_unrelated_missing_quantity_but_negative_does_not(self):
        trace=core_trace('pushup')
        del trace.frames[2]['sample2D']['measurements']['hipDeviation']
        positive,_=decision(trace,'pushup_hip_sag')
        negative,_=decision(trace,'pushup_hip_pike')
        self.assertEqual(positive['state'],'warning')
        self.assertEqual(negative['state'],'withheld')
        self.assertLessEqual(positive['exposureEndSeconds'],0.02)

    def test_one_trustworthy_tied_extremum_suffices_for_pointwise_positive(self):
        trace=core_trace('pushup');rep=list(trace.reps.values())[0]
        support=rep['judgements']['2d']['metricSupport']['hip_dev_max']
        # Adversarial redundant-tie lineage: frame0 remains the actual native
        # maximum witness; a second allegedly tied frame is untrustworthy.
        support['selectedFrames'].append(2)
        trace.frames[2]['sample2D']['inputSupport']['jointEvidence'][11]['finiteCoordinates']=False
        row,audit=decision(trace,'pushup_hip_sag')
        self.assertEqual(row['state'],'warning')
        self.assertEqual(audit['metricChecks'][0]['provenSelectedFrames'],[0])

    def test_shallow_positive_needs_whole_current_minimum_search(self):
        trace=core_trace('pushup')
        self.assertEqual(decision(trace,'pushup_shallow',1)[0]['state'],'warning')
        del trace.frames[6]['sample2D']['measurements']['elbow']
        self.assertEqual(decision(trace,'pushup_shallow',1)[0]['state'],'withheld')

    def test_native_or_short_circuit_needs_only_supported_true_branch(self):
        trace=core_trace('squat');rep=list(trace.reps.values())[0]
        rule=next(r for r in rep['judgements']['2d']['rules'] if r['rule']=='squat_no_lockout')
        self.assertEqual(len(rule['operands']),1)
        self.assertEqual(decision(trace,'squat_no_lockout')[0]['state'],'warning')
        # The unused hip branch can be unavailable without erasing knee proof.
        for frame in rep['frames2D']:trace.frames[frame]['sample2D']['measurements'].pop('hipAngle',None)
        self.assertEqual(decision(trace,'squat_no_lockout')[0]['state'],'warning')

    def test_failed_or_branch_has_no_witness_side_effects(self):
        trace=core_trace('squat');rep=list(trace.reps.values())[0];judge=rep['judgements']['2d']
        row=copy.deepcopy(next(r for r in judge['rules'] if r['rule']=='squat_no_lockout'))
        row['operands']=[{'metric':'knee_max','operation':'below_set_max','result':True},
                         {'metric':'hip_angle_max','operation':'below_set_max','result':True}]
        support=ex.Support(trace,rep,judge,'2d','squat_no_lockout')
        def branch(operand,positive):
            if operand['metric']=='knee_max':
                support.witness.add(0);support.reference_ids.append('failed');support.metric_checks.append({'failed':True})
                raise ex.Unproven('unsupported first branch')
            support.witness.add(3)
        with patch.object(support,'operand',side_effect=branch),patch.object(support,'view'):
            support.evaluate(row,True)
        self.assertEqual(support.witness,{3});self.assertEqual(support.reference_ids,[]);self.assertEqual(support.metric_checks,[])

    def test_partial_3d_uses_serialized_raw_value(self):
        trace=core_trace('pushup');rep=list(trace.reps.values())[0]
        sample=copy.deepcopy(trace.frames[0]['sample2D']);sample['state3D']='partial_3d'
        trace.frames[0]['sample3D']=sample;rep['frames3D']=[0]
        support=ex.Support(trace,rep,rep['judgements']['2d'],'3d','pushup_hip_sag')
        self.assertIs(support.sample(0),sample)

    def test_crossing_positive_witness_is_rejected_not_clipped(self):
        trace=core_trace('pushup');rep=list(trace.reps.values())[0]
        with self.assertRaisesRegex(ev.ContractError,'outside exact frozen'):
            ex.decision(trace,rep,'pushup_hip_sag',{'sampleId':'bad','startSeconds':0.02,'endSeconds':0.06})

    def test_facing_bad_establishment_then_valid_confirmation_recovers(self):
        trace=core_trace('barbell_row');rep=list(trace.reps.values())[0]
        support=ex.Support(trace,rep,rep['judgements']['2d'],'2d','row_torso_swing')
        # Frame1 establishes; frame0 legitimately has no face observation.
        trace.frames[1]['sample2D']['inputSupport']['jointEvidence'][0]['finiteCoordinates']=False
        with self.assertRaisesRegex(ex.Unproven,'trustworthy'):
            support.facing(1)
        support.facing(2)  # finite native confirm re-establishes the same sign

    def test_facing_reset_starts_new_witnessed_segment(self):
        trace=core_trace('barbell_row');rep=list(trace.reps.values())[1]
        # Explicit adversarial event mutation tests reset handling, not geometry.
        trace.rows.append({'type':'reset','sequence':trace.frames[4]['sequence']-0.5})
        inputs=trace.frames[4]['sample2D']['inputSupport'];facing=inputs['facing'];observation=inputs['facingObservation']
        facing['before']=None;observation['before']=None;observation['updateKind']='establish'
        support=ex.Support(trace,rep,rep['judgements']['2d'],'2d','row_torso_swing')
        support.facing(4)

    def test_bad_facing_flip_stays_unproven_until_finite_confirmation(self):
        trace=core_trace('barbell_row');rep=list(trace.reps.values())[0]
        # Keep actual establish at1. Explicit mutation models the native
        # candidate/flip state branch, with an unobserved final face joint.
        for frame,kind,before,after,run_before,run_after in ((2,'candidate',1,1,0,1),(3,'flip',1,-1,1,0)):
            data=trace.frames[frame]['sample2D']['inputSupport']
            data['facing'].update(before=before,after=after,candidateRunBefore=run_before,candidateRun=run_after)
            data['facingObservation'].update(seen=-1,updateKind=kind,before=before,after=after,
                                             candidateRunBefore=run_before,candidateRunAfter=run_after)
        trace.frames[3]['sample2D']['inputSupport']['jointEvidence'][0]['finiteCoordinates']=False
        support=ex.Support(trace,rep,rep['judgements']['2d'],'2d','row_torso_swing')
        with self.assertRaisesRegex(ex.Unproven,'trustworthy'):support.facing(3)
        trace.frames[3]['sample2D']['inputSupport']['jointEvidence'][0]['finiteCoordinates']=True
        support.facing(3)


class EnvelopeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.repo=self.root/'repo';self.repo.mkdir()
        def git(*args):return subprocess.check_output(['git','-C',str(self.repo),*args],stderr=subprocess.DEVNULL).decode().strip()
        self.git=git;git('init','-q');git('config','user.email','fixture@example.invalid');git('config','user.name','Synthetic envelope')
        self.sources={}
        # Real repository rule bytes are used; the envelope only exercises identity.
        for name in ('FormWarnings.swift','PushUpEvaluator.swift'):
            path='ios/Runner/NativePose/Evaluators/'+name
            output=self.repo/path;output.parent.mkdir(parents=True,exist_ok=True)
            output.write_bytes((ROOT/path).read_bytes());self.sources[path]=ex.file_sha(output)
        path='ios/Runner/NativePose/Evaluators/FormFaultEvidence.swift'
        output=self.repo/path;output.write_text('// UNIT TEST envelope instrumentation identity, not an executed binary\n')
        self.sources[path]=ex.file_sha(output)
        git('add','.');git('commit','-qm','Explicit unit-test provenance envelope');self.candidate=git('rev-parse','HEAD')
        self.clip=self.root/'synthetic.bin';self.clip.write_bytes(b'UNIT TEST, NOT VIDEO')
        self.binary=self.root/'synthetic-executable.bin';self.binary.write_bytes(b'UNIT TEST, NOT EXECUTABLE')
        self.protocol=ROOT/'docs/evaluation/independent_form_protocol_v1.md'
        self.records=rows()
        self.records[0]['binding']={'candidateId':self.candidate,'exercise':'pushup','clipId':'unit_test',
            'taskBinding':'unbound_native_windows','executionScope':'headless_original_video_native_evaluator',
            'sourceSHA256':ex.file_sha(self.clip),'executableSHA256':ex.file_sha(self.binary),
            'runtimeSourceSHA256':self.sources,
            'modelArtifactSHA256':{str(self.binary):ex.file_sha(self.binary)},
            'buildManifest':{'contract':'bpt-pose-replay-build-v1','candidateId':self.candidate,
                'sourceStableAcrossBuild':True,'executableSHA256':ex.file_sha(self.binary),'sourceSHA256':self.sources}}
        self.trace=self.root/'test-envelope.jsonl';rewrite(self.trace,self.records)
        self.receipt=self.root/'receipt.json'
        self.receipt.write_bytes(ex.dumps({'contract':'bpt-pose-replay-receipt-v1','runID':'fixture',
            'tracePath':str(self.trace),'traceSHA256':ex.file_sha(self.trace),'candidateId':self.candidate,
            'sourceSHA256Before':ex.file_sha(self.clip),'sourceSHA256After':ex.file_sha(self.clip),
            'modelArtifactSHA256Before':{str(self.binary):ex.file_sha(self.binary)},
            'modelArtifactSHA256After':{str(self.binary):ex.file_sha(self.binary)},'artifactsStable':True,
            'lifterActive':False,'formSource3D':False,'modelDigestAlgorithm':'sha256-relative-path-nul-file-sha256-lf-v1'}))
        self.bundle=self.root/'bundle.json';self.bundle.write_bytes(ex.dumps({'schemaVersion':1,'traces':[
            {'tracePath':str(self.trace),'clipPath':str(self.clip),'executablePath':str(self.binary),'receiptPath':str(self.receipt)}]}))

    def test_prepare_export_import_roundtrip_preserves_all_inputs(self):
        paths=[self.trace,self.clip,self.binary,self.bundle,self.protocol,self.receipt]
        before={p:p.read_bytes() for p in paths}
        task=self.root/'task';out=self.root/'export';imported=self.root/'imported'
        receipt=ex.prepare(self.bundle,self.repo,self.protocol,task)
        self.assertEqual((receipt['nativeReps'],receipt['opportunities']),(4,32))
        before.update({p:p.read_bytes() for p in task.iterdir()})
        result=ex.export(task,self.repo,self.protocol,out)
        self.assertEqual(result['states'],{'no_warning':17,'withheld':15})
        self.assertEqual(result['evidenceSHA256'],ex.file_sha(out/'evidence.json'))
        self.assertEqual(ev.load(out/'export_audit.json')[0]['evidenceSHA256'],ex.file_sha(out/'evidence.json'))
        imp.import_task(task,out/'evidence.json',self.protocol,task/'boundary_manifest.json',
                        task/'clip_index_PRIVATE.json',self.repo,imported)
        manifest,sha=ev.load(imported/'manifest.json');labels,_=ev.load(imported/'labels.json');predictions,_=ev.load(imported/'predictions.json')
        score=ev.evaluate(manifest,sha,labels,predictions)['overall']
        self.assertEqual(score['unknownLabels'],32);self.assertEqual(score['adjudicated'],0)
        self.assertIsNone(score['selectiveAccuracy']['value'])
        self.assertTrue(all(p.read_bytes()==raw for p,raw in before.items()))

    def test_overwrite_and_task_subset_are_rejected(self):
        task=self.root/'task';ex.prepare(self.bundle,self.repo,self.protocol,task)
        with self.assertRaisesRegex(ev.ContractError,'already exists'):ex.prepare(self.bundle,self.repo,self.protocol,task)
        ex.export(task,self.repo,self.protocol,self.root/'export')
        with self.assertRaisesRegex(ev.ContractError,'already exists'):ex.export(task,self.repo,self.protocol,self.root/'export')
        m,_=ev.load(task/'manifest.json');m['samples'].pop();(task/'manifest.json').write_bytes(ex.dumps(m))
        with self.assertRaisesRegex(ev.ContractError,'complete native-derived'):ex.export(task,self.repo,self.protocol,self.root/'new')

    def test_full_bytes_candidate_and_runtime_hash_mismatch_rejected(self):
        for key in ('clip','binary','candidate','source'):
            saved=copy.deepcopy(self.records)
            if key=='clip':self.records[0]['binding']['sourceSHA256']='0'*64
            if key=='binary':self.records[0]['binding']['executableSHA256']='0'*64
            if key=='candidate':self.records[0]['binding']['candidateId']='0'*40
            if key=='source':self.records[0]['binding']['runtimeSourceSHA256'][next(iter(self.sources))]='0'*64
            rewrite(self.trace,self.records)
            with self.subTest(key=key),self.assertRaises(ev.ContractError):ex.read_bundle(self.bundle,self.repo)
            self.records=saved

    def test_duplicate_sequence_source_or_unclosed_writer_rejected(self):
        for key in ('sequence','source','footer','truncated'):
            records=copy.deepcopy(self.records)
            if key=='source':records.insert(2,copy.deepcopy(records[1]))
            if key=='footer':records[-1]['writerComplete']=False
            rewrite(self.trace,records)
            if key=='sequence':
                records[1]['sequence']=99
                self.trace.write_text('\n'.join(json.dumps(r) for r in records)+'\n')
            if key=='truncated':self.trace.write_bytes(self.trace.read_bytes()[:-1])
            with self.subTest(key=key),self.assertRaises(ev.ContractError):ex.read_bundle(self.bundle,self.repo)

    def test_closed_failed_frame_is_accounted_without_erasing_other_reps(self):
        frame=next(r for r in self.records if r['type']=='frame' and r['source']['frame']==11)
        frame.update(observation='invalid_coco17_count',sample2D=None,sample3D=None)
        self.records[-1].update(failedSourcesCount=1,sourceCoverageComplete=False)
        rewrite(self.trace,self.records)
        receipt,_=ex.load(self.receipt);receipt['traceSHA256']=ex.file_sha(self.trace)
        self.receipt.write_bytes(ex.dumps(receipt))
        traces,_=ex.read_bundle(self.bundle,self.repo)
        self.assertEqual(traces[0].failed_sources,{'fixture/source/11'})
        self.assertEqual(decision(traces[0],'pushup_hip_sag')[0]['state'],'no_warning')
        self.assertEqual(decision(traces[0],'pushup_hip_sag',3)[0]['state'],'withheld')

    def test_execution_receipt_and_model_bytes_are_required(self):
        receipt,_=ex.load(self.receipt)
        for field in ('traceSHA256','sourceSHA256After','modelArtifactSHA256After','artifactsStable'):
            changed=copy.deepcopy(receipt);changed[field]=None
            self.receipt.write_bytes(ex.dumps(changed))
            with self.subTest(field=field),self.assertRaises(ev.ContractError):ex.read_bundle(self.bundle,self.repo)
        self.receipt.write_bytes(ex.dumps(receipt))
        self.binary.write_bytes(b'changed bytes')
        with self.assertRaises(ev.ContractError):ex.read_bundle(self.bundle,self.repo)


if __name__=='__main__':unittest.main()
