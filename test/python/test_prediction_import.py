import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/form_eval'))
import independent_form_eval as ev
import import_predictions as importer
from test_independent_form_eval import manifest


def exported(m, digest='e'*64):
    return {'schemaVersion': 1, 'contract': importer.CONTRACT,
        'candidateCommit': m['candidateCommit'], 'manifestSha256': digest,
        'protocolId': m['protocolId'], 'protocolSha256': m['protocolSha256'],
        'boundaryManifestSha256': m['boundaryManifestSha256'], 'ruleSourceSha256': 'f'*64,
        'observations': [{**s, 'state': 'no_warning', 'reason': None, 'ruleId': s['rule'],
            'decisionSemantic': 'fault_presence', 'positiveEvidenceSufficient': True, 'exposureStartSeconds': s['startSeconds'],
            'exposureEndSeconds': s['endSeconds'], 'checks': dict.fromkeys(importer.CHECKS, True)}
            for s in m['samples']]}


class PredictionImportTests(unittest.TestCase):
    def test_partial_evidence_keeps_denominator_and_missing_distinct_from_withheld(self):
        m = manifest(3); evidence = exported(m)
        evidence['observations'].pop()
        evidence['observations'][0]['state'] = 'warning'
        evidence['observations'][1].update(state='withheld', reason='phase_unobserved')
        evidence['observations'][1]['checks']['requiredPhaseObserved'] = False
        result = importer.convert(evidence, m, 'e'*64, 'f'*64)
        self.assertEqual([r['state'] for r in result['observations']], ['warning','withheld','missing'])
        self.assertEqual(result['observations'][2]['reason'], 'not_in_evidence')
        labels, _ = ev.templates(m, 'e'*64)
        metrics = ev.evaluate(m, 'e'*64, labels, result)['overall']
        self.assertEqual(metrics['opportunities'], 3)
        self.assertEqual(metrics['adjudicated'], 0)

    def test_duplicate_unknown_or_changed_identity_rejected(self):
        m = manifest(2)
        mutations = [lambda e:e['observations'].append(copy.deepcopy(e['observations'][0])),
                     lambda e:e['observations'][0].update(sampleId='unknown')]
        for field, value in [('clipSha256','0'*64), ('rep',True), ('rule','pushup_shallow'),
                             ('side','left'), ('endSeconds',1.0), ('split','development'),
                             ('visibility','adequate'), ('windowCoverage','full_rep')]:
            mutations.append(lambda e, f=field, v=value:e['observations'][0].update({f:v}))
        for mutate in mutations:
            e = exported(m); mutate(e)
            with self.assertRaises(ev.ContractError): importer.convert(e,m,'e'*64,'f'*64)

    def test_every_provenance_binding_required(self):
        m = manifest(1)
        for field in ('candidateCommit','manifestSha256','protocolId','protocolSha256',
                      'boundaryManifestSha256','ruleSourceSha256','contract'):
            e = exported(m); e[field] = 'unrelated'
            with self.subTest(field=field), self.assertRaises(ev.ContractError):
                importer.convert(e,m,'e'*64,'f'*64)

    def test_no_silence_disabled_rule_missing_phase_or_partial_window_as_negative(self):
        m = manifest(1)
        for check in importer.CHECKS:
            for state in (('warning','no_warning') if check in ('ruleEnabled','ruleEvaluated','finiteInputs') else ('no_warning',)):
                e = exported(m); e['observations'][0]['state'] = state
                e['observations'][0]['checks'][check] = False
                with self.subTest(check=check,state=state), self.assertRaises(ev.ContractError):
                    importer.convert(e,m,'e'*64,'f'*64)
        for field, value in [('exposureStartSeconds',.1), ('exposureEndSeconds',.9),
                             ('exposureEndSeconds',float('nan')), ('state','missing'),
                             ('decisionSemantic','desired_match'), ('ruleId','pushup.depth'),
                             ('reason','participant name')]:
            e = exported(m); e['observations'][0][field] = value
            with self.subTest(field=field), self.assertRaises(ev.ContractError):
                importer.convert(e,m,'e'*64,'f'*64)
        e = exported(m); del e['observations'][0]['checks']['ruleEvaluated']
        with self.assertRaises(ev.ContractError): importer.convert(e,m,'e'*64,'f'*64)

    def test_partial_positive_requires_explicit_rule_sufficiency(self):
        m = manifest(1); e = exported(m); row = e['observations'][0]
        row.update(state='warning', exposureEndSeconds=.5)
        for key in ('requiredPhaseObserved','viewEligible','referenceReady'):
            row['checks'][key] = False
        self.assertEqual(importer.convert(e,m,'e'*64,'f'*64)['observations'][0]['state'],'warning')
        row['positiveEvidenceSufficient'] = False
        with self.assertRaises(ev.ContractError): importer.convert(e,m,'e'*64,'f'*64)
        row['positiveEvidenceSufficient'] = True
        for start, end in ((3,4), (0,1.1)):
            row['exposureStartSeconds'],row['exposureEndSeconds'] = start,end
            with self.assertRaises(ev.ContractError): importer.convert(e,m,'e'*64,'f'*64)

    def test_gate_or_uncertainty_requires_explicit_local_reason(self):
        m = manifest(1); e = exported(m)
        e['observations'][0].update(state='withheld',reason='high_uncertainty')
        self.assertEqual(importer.convert(e,m,'e'*64,'f'*64)['observations'][0]['state'],'withheld')
        e['observations'][0]['reason'] = None
        with self.assertRaises(ev.ContractError): importer.convert(e,m,'e'*64,'f'*64)

    def fixture(self, d):
        task = d/'source-task'; task.mkdir()
        protocol, boundary, clip = d/'protocol.md', d/'boundaries.json', d/'clip.bin'
        protocol.write_text('synthetic protocol'); boundary.write_text('[]'); clip.write_bytes(b'synthetic clip bytes')
        m = manifest(4)
        m['protocolSha256'] = importer.file_sha(protocol)
        m['boundaryManifestSha256'] = importer.file_sha(boundary)
        for row in m['samples']: row['clipSha256'] = importer.file_sha(clip)
        ev.write_new(task/'manifest.json',m); _, digest = ev.load(task/'manifest.json')
        labels,predictions = ev.templates(m,digest)
        ev.write_new(task/'labels.json',labels); ev.write_new(task/'predictions.json',predictions)
        source = b'synthetic frozen rule source'
        evidence = exported(m,digest)
        evidence['ruleSourceSha256'] = hashlib.sha256(source).hexdigest()
        evidence['observations'][0]['state'] = 'warning'
        evidence['observations'][1].update(state='withheld',reason='reference_not_ready')
        evidence['observations'][1]['checks']['referenceReady'] = False
        evidence['observations'].pop()
        ev.write_new(d/'evidence.json', evidence)
        ev.write_new(d/'index.json',[{'clipSha256':importer.file_sha(clip),'localClipPath':str(clip)}])
        args = (task,d/'evidence.json',protocol,boundary,d/'index.json',ROOT,d/'imported')
        return args,source,clip

    def test_offline_roundtrip_preserves_bytes_and_refuses_existing_output_and_decisions(self):
        with tempfile.TemporaryDirectory() as directory:
            d=Path(directory); args,source,clip = self.fixture(d)
            before={p:p.read_bytes() for p in d.rglob('*') if p.is_file()}
            with patch.object(importer,'candidate_source',return_value=source):
                receipt=importer.import_task(*args)
                with self.assertRaises(ev.ContractError): importer.import_task(*args)
            self.assertEqual(receipt['predictionStates'],{'warning':1,'no_warning':1,'withheld':1,'missing':1})
            self.assertEqual(before,{p:p.read_bytes() for p in before})
            for name in ('manifest.json','labels.json'):
                self.assertEqual((d/'source-task'/name).read_bytes(),(d/'imported'/name).read_bytes())
            shared=['--manifest',str(d/'imported/manifest.json'),'--protocol',str(args[2]),
                    '--boundary-manifest',str(args[3]),'--labels',str(d/'imported/labels.json'),
                    '--predictions',str(d/'imported/predictions.json'),'--output',str(d/'score.json')]
            self.assertEqual(ev.main(['score',*shared]),0)
            report,_=ev.load(d/'score.json')
            self.assertEqual(report['overall']['predictionStatesAllRows'],receipt['predictionStates'])
            self.assertEqual(report['overall']['unknownLabels'],4)
            predictions,_=ev.load(d/'source-task/predictions.json')
            predictions['observations'][0].update(state='warning',reason=None)
            (d/'source-task/predictions.json').write_text(json.dumps(predictions))
            args=(*args[:-1],d/'replacement')
            with patch.object(importer,'candidate_source',return_value=source), self.assertRaises(ev.ContractError):
                importer.import_task(*args)
            self.assertFalse((d/'replacement').exists())

    def test_clip_hash_mismatch_and_changed_inputs_fail_before_output(self):
        for change in ('clip','index','changed_snapshot'):
            with tempfile.TemporaryDirectory() as directory:
                d=Path(directory); args,source,clip=self.fixture(d)
                if change=='clip': clip.write_bytes(b'changed')
                if change=='index': (d/'index.json').write_text('[]')
                def changed(_): raise ev.ContractError('input changed')
                with patch.object(importer,'candidate_source',return_value=source):
                    if change=='changed_snapshot':
                        with patch.object(importer,'unchanged',side_effect=changed), self.assertRaises(ev.ContractError):
                            importer.import_task(*args)
                    else:
                        with self.assertRaises(ev.ContractError): importer.import_task(*args)
                self.assertFalse((d/'imported').exists())

    def test_real_frozen_candidate_source_and_nonexistent_candidate(self):
        import subprocess
        candidate=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD']).decode().strip()
        self.assertIn(b'FormWarningTracker',importer.candidate_source(ROOT,candidate))
        with self.assertRaises(ev.ContractError): importer.candidate_source(ROOT,'0'*40)


if __name__ == '__main__': unittest.main()
