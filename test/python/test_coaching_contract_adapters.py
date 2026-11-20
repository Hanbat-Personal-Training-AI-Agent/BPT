"""Adapter provenance/receipt tests. Public fixtures contain no real capture data."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from scripts.coaching_contract.adapters import native, deep_report, file_sha
from scripts.coaching_contract.contract import digest
from scripts.coaching_contract.engine import evaluate
from scripts.coaching_contract.replay import run
from test_coaching_contract_engine import sample


class AdapterTests(unittest.TestCase):
    def test_native_retains_actual_histories_layers_not_runtime_inference(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'public.jsonl'
            header={'model_hashes':{'public_fixture':'a'*64},'units_3d':'h36m17_xs_model_space_no_metric_guarantee','provenance':'synthetic_test'}
            p.write_text(json.dumps(header)+'\n'); sha=file_sha(p)
            frames=[]
            for f in sample()['frames']:
                x={'frame':f['id'],'source_index':f['id'],'source_time_value':int(f['time']['seconds']*1000),
                   'source_time_scale':1000,'source_pts':f['time']['seconds'],'side':f['side'],'phase':f['phase'],
                   'side_view':f['view_eligible'],'assessment_3d':f['joints'],'invalid':[],
                   'confidence_h36m':[1.2]*17,'assessment_state':'ok','raw_state':'ok',
                   'raw_3d':f['joints'],'constrained_3d':f['joints'],'adapted_3d':f['joints'],
                   'row':21,'filled':27,'flush_tail':False,'rotation':0,'front_camera':False,
                   'source_mirrored':False,'judgement_up':[0,-1,0],'source_gravity_available':False}
                frames.append(x)
            reps=[{'rep':i+1,'start_frame':i,'end_frame':i,'side':'right','form_source':'3d'} for i in range(4)]
            epoch={'start':{'exercise':'pushUp','set':1,'time_basis':'sample_pts_seconds'},'frames':frames,'reps':reps,'end':{'flush_complete':True}}
            with patch('scripts.coaching_contract.adapters.load_terminal',return_value=({0:epoch},False,sha)):
                s=native(p,sha)[0]
            self.assertEqual(s['frames'][0]['confidence_h36m'][0],1.2)
            self.assertEqual(s['frames'][0]['layer_hashes']['raw_3d'],digest(frames[0]['raw_3d']))
            self.assertIsNone(s['clip']['media_sha256'])
            self.assertEqual(s['first3_reference_identity']['first3_rep_ids'],[1,2,3])
            r=evaluate(s)['reps'][-1]
            self.assertEqual(r['qualified_shadow']['state'],'warning')
            self.assertEqual(r['runtime']['state'],'missing');self.assertEqual(r['delivery']['state'],'missing')
            with self.assertRaisesRegex(ValueError,'sha256_mismatch'):native(p,'0'*64)

    def fixture_deep(self, root, exercise='barbell-row', evaluated=None, warnings=None):
        report={'exerciseId':exercise,'fps':30,'reps':[{'repIndex':1,'startMs':123,'endMs':456,
                    'evaluatedKeys':evaluated,'serverWarnings':warnings,'metricValidity':{},'faults':[]}]}
        evidence={'inputVideoSha256':'a'*64,'pinnedNativeManifestCanonicalSha256':'b'*64,
                  'actualImportedSourceSha256':{'worker':'c'*64},'nativeManifestRetimed':False}
        rp,ep,vp=(Path(root)/n for n in ('worker.json','evidence.json','proof.json'))
        rp.write_text(json.dumps(report));ep.write_text(json.dumps(evidence))
        proof={'status':'verified_actual_isolated_report_not_authenticated_API',
               'artifactSha256':{'worker_report.json':file_sha(rp),'evidence.json':file_sha(ep)},
               'inputVideoSha256':'a'*64,'serviceManifestSha256':'b'*64}
        vp.write_text(json.dumps(proof))
        return rp,ep,vp

    def test_worker_row_stays_unsupported_preserves_non_target_warnings(self):
        with tempfile.TemporaryDirectory() as tmp:
            rp,ep,vp=self.fixture_deep(tmp,warnings=['symmetry'])
            s=deep_report(rp,file_sha(rp),ep,vp);r=evaluate(s)['reps'][0]
            self.assertEqual(r['qualified_shadow']['reasons'],['unsupported_exercise'])
            self.assertEqual(r['runtime']['server_warnings'],['symmetry'])
            self.assertEqual(r['runtime']['state'],'missing')
            self.assertEqual(r['original_interval'],{'start':123,'end':456,'unit':'video_ms','closure':'half_open'})
            self.assertEqual(s['frames'],[])

    def test_worker_only_explicit_evaluated_key_can_be_negative(self):
        with tempfile.TemporaryDirectory() as tmp:
            rp,ep,vp=self.fixture_deep(tmp,'pushup',[],[])
            r=deep_report(rp,file_sha(rp),ep,vp)['reps'][0]
            self.assertEqual(r['runtime']['state'],'withheld')
            rp,ep,vp=self.fixture_deep(tmp,'pushup',['pushup_shallow'],[])
            self.assertEqual(deep_report(rp,file_sha(rp),ep,vp)['reps'][0]['runtime']['state'],'no_warning')
            rp,ep,vp=self.fixture_deep(tmp,'pushup',['pushup_shallow'],['pushup_shallow'])
            self.assertEqual(deep_report(rp,file_sha(rp),ep,vp)['reps'][0]['runtime']['state'],'warning')

    def test_worker_tampered_evidence_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            rp,ep,vp=self.fixture_deep(tmp)
            ep.write_text(ep.read_text()+' ')
            with self.assertRaisesRegex(ValueError,'evidence_binding'):deep_report(rp,file_sha(rp),ep,vp)

    def test_cli_creates_private_immutable_output_and_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'fixture';p.write_text('public');sha=file_sha(p)
            s=sample();s['source']['kind']='synthetic_fixture'
            a=argparse.Namespace(output=str(Path(tmp)/'out'),native=[(str(p),sha)],deep_report=None)
            with patch('scripts.coaching_contract.replay.native',return_value=[s]):r=run(a)
            self.assertTrue(r['input_files_unchanged']);self.assertFalse((Path(a.output)/'INCOMPLETE').exists())
            self.assertEqual((Path(a.output).stat().st_mode & 0o777),0o700)
            self.assertEqual(((Path(a.output)/'aggregate.json').stat().st_mode & 0o777),0o600)
            with self.assertRaises(FileExistsError):run(a)
            self.assertEqual(file_sha(p),sha)

    def test_cli_failure_retains_incomplete_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'fixture';p.write_text('public')
            a=argparse.Namespace(output=str(Path(tmp)/'out'),native=[(str(p),'0'*64)],deep_report=None)
            with self.assertRaises(ValueError):run(a)
            self.assertTrue((Path(a.output)/'INCOMPLETE').exists())
            self.assertTrue((Path(a.output)/'input-receipt.json').exists())
            self.assertEqual(json.loads((Path(a.output)/'failure.json').read_text())['status'],'incomplete')

    @unittest.skipUnless(os.environ.get('BPT_COACHING_REAL_ROOT'),'private read-only captures opt-in')
    def test_actual_capture_strict_reader_and_immutable_three_inputs(self):
        root=Path(os.environ['BPT_COACHING_REAL_ROOT'])
        pins={'squat':'c783990a63bb3aa05afd30bd122b3c9b2e513a53a3e7430a86dddc4e83db5039',
              'pushup':'508cf87e31740b20e17b6b44775b3ab28cdc9fc94fbbcd5af69acfa031dbe3fa',
              'barbellrow':'20f8daf37800599513bdafba20e0e4b312a66cbf593fca68aad031143bf8921a'}
        for exercise,sha in pins.items():
            p=root/exercise/'terminal-original.jsonl';streams=native(p,sha)
            self.assertEqual(len(streams),1);r=evaluate(streams[0]);self.assertEqual(len(r['reps']),10)
            self.assertTrue(all(x['runtime']['state']=='missing' and x['delivery']['state']=='missing' for x in r['reps']))
            self.assertEqual(file_sha(p),sha)

    def test_cli_cross_source_comparison_keeps_missing_counterpart_scope(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'fixture';p.write_text('public');sha=file_sha(p)
            a=sample();a['source']['kind']='native_fixture';b=copy.deepcopy(a);b['source']['kind']='deep_fixture'
            args=argparse.Namespace(output=str(Path(tmp)/'out'),native=[(str(p),sha)],deep_report=None)
            with patch('scripts.coaching_contract.replay.native',return_value=[a,b]):r=run(args)
            self.assertEqual(r['comparisons'][0]['states'],{'withheld':4})
            self.assertFalse(r['comparisons'][0]['semantic_parity_asserted'])
            self.assertTrue((Path(args.output)/'comparison-00-01.json').exists())

    @unittest.skipUnless(os.environ.get('BPT_COACHING_WORKER_ROOT'),'private verified worker opt-in')
    def test_actual_worker_row_is_not_repurposed_as_supported_rule(self):
        root=Path(os.environ['BPT_COACHING_WORKER_ROOT'])
        sha='f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa'
        s=deep_report(root/'worker_report.json',sha,root/'evidence.json',root/'verification-summary.json')
        r=evaluate(s)
        self.assertEqual(len(r['reps']),10)
        self.assertTrue(all(x['qualified_shadow']['reasons']==['unsupported_exercise'] for x in r['reps']))
        self.assertEqual(sum(len(x['runtime']['original_faults']) for x in r['reps']),10)
        self.assertEqual(file_sha(root/'worker_report.json'),sha)
