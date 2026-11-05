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
import prepare_fit3d_task as adapter


def manifest(n=9):
    return {'schemaVersion': 1, 'protocolId': ev.PROTOCOL, 'protocolSha256': 'a' * 64,
            'candidateCommit': 'c' * 40, 'splitPlanId': 'synthetic_prespecified', 'dataKind': 'synthetic_fixture',
            'boundarySource': 'synthetic', 'boundaryManifestSha256': 'b' * 64,
            'samples': [{'sampleId': f's{i}', 'clipSha256': 'd' * 64, 'exercise': 'pushup', 'rep': i+1,
                'rule': 'pushup_no_lockout', 'side': 'none', 'startSeconds': i*2, 'endSeconds': i*2+1,
                'timeUnit': 'seconds', 'labelUnit': 'per_rep_rule_binary_fault', 'split': 'holdout',
                'splitGroup': 'synthetic_group', 'visibility': 'unknown', 'contactChange': 'unknown',
                'windowCoverage': 'unknown'} for i in range(n)]}


def binary(row, label):
    row.update(label=label, sourceType='human_adjudicated', observerId='synthetic_observer',
               adjudicatorId='synthetic_adjudicator')


class EvalTests(unittest.TestCase):
    def test_unknown_templates_never_invent_form_evidence(self):
        m = manifest()
        labels, predictions = ev.templates(m, 'e'*64)
        report = ev.evaluate(m, 'e'*64, labels, predictions)['overall']
        self.assertEqual((report['adjudicated'], report['unknownLabels']), (0, 9))
        self.assertEqual(report['predictionStatesAllRows']['missing'], 9)
        for field in ('strictRecall', 'selectiveAccuracy', 'correctCoverage', 'decisionCoverage'):
            self.assertEqual(report[field]['denominator'], 0)
            self.assertIsNone(report[field]['value'])
        self.assertTrue(all(r['observerId'] is None and r['sourceType'] == 'unreviewed' for r in labels['annotations']))

    def test_synthetic_math_counts_withheld_and_missing_positives_as_strict_misses(self):
        m = manifest()
        labels, predictions = ev.templates(m, 'e'*64)
        for i in range(8):
            binary(labels['annotations'][i], 'positive' if i < 4 else 'negative')
        for row, state in zip(predictions['observations'],
                              ['warning', 'no_warning', 'withheld', 'missing', 'warning', 'no_warning', 'withheld', 'missing', 'warning']):
            row.update(state=state, reason='synthetic_gate' if state in ('withheld', 'missing') else None)
        output = ev.evaluate(m, 'e'*64, labels, predictions)
        r = output['overall']
        self.assertEqual(r['selectiveConfusion'], {'TP':1, 'FP':1, 'FN':1, 'TN':1})
        self.assertEqual(r['strictFNIncludingMisses'], 3)
        self.assertEqual(r['unresolvedNegative'], 2)
        self.assertEqual(r['strictRecall'], {'numerator':1,'denominator':4,'value':0.25})
        self.assertEqual(r['selectiveAccuracy']['value'], 0.5)
        self.assertEqual(r['decisionCoverage']['value'], 0.5)
        self.assertEqual(r['correctCoverage']['value'], 0.25)
        self.assertEqual((r['unknownLabels'], r['physicalReps']), (1, 9))
        self.assertEqual(output['by']['split']['holdout'], r)
        self.assertEqual(output['dataKind'], 'synthetic_fixture')

    def test_no_selected_decisions_is_not_perfect_accuracy(self):
        m = manifest(1)
        labels, predictions = ev.templates(m, 'e'*64)
        binary(labels['annotations'][0], 'positive')
        r = ev.evaluate(m, 'e'*64, labels, predictions)['overall']
        self.assertEqual(r['strictFNIncludingMisses'], 1)
        self.assertEqual(r['strictRecall']['value'], 0)
        self.assertIsNone(r['selectiveAccuracy']['value'])
        self.assertEqual(r['correctCoverage']['denominator'], 1)

    def test_incomplete_or_duplicate_rows_fail_instead_of_disappearing(self):
        m = manifest(2)
        for kind in ('labels', 'predictions'):
            key = 'annotations' if kind == 'labels' else 'observations'
            for mutation in ('missing', 'duplicate', 'unexpected'):
                labels, predictions = ev.templates(m, 'e'*64)
                document = labels if kind == 'labels' else predictions
                if mutation == 'missing': document[key].pop()
                elif mutation == 'duplicate': document[key].append(copy.deepcopy(document[key][0]))
                else: document[key][0]['sampleId'] = 'other'
                with self.subTest(kind=kind, mutation=mutation), self.assertRaises(ev.ContractError):
                    ev.evaluate(m, 'e'*64, labels, predictions)

    def test_identity_mismatches_fail(self):
        m = manifest(1)
        for field, value in [('clipSha256','0'*64), ('side','left'), ('timeUnit','milliseconds'),
                             ('labelUnit','degrees'), ('endSeconds',999), ('rep',2),
                             ('rule','pushup_shallow'), ('split','development'), ('visibility','adequate')]:
            for doc_index, key in [(0,'annotations'), (1,'observations')]:
                docs = ev.templates(m, 'e'*64)
                docs[doc_index][key][0][field] = value
                with self.subTest(field=field, doc=key), self.assertRaises(ev.ContractError):
                    ev.evaluate(m, 'e'*64, *docs)

    def test_unknown_rules_duplicate_opportunities_and_invalid_clocks_fail(self):
        mutations = [lambda s:s.update(rule='imagined_rule'), lambda s:s.update(rep=True),
                     lambda s:s.update(endSeconds=float('nan')), lambda s:s.update(startSeconds=-1),
                     lambda s:s.update(timeUnit='frames'), lambda s:s.update(endSeconds=0)]
        for mutation in mutations:
            m = manifest(1); mutation(m['samples'][0])
            with self.assertRaises(ev.ContractError): ev.validate_manifest(m)
        m = manifest(1); m['samples'].append({**m['samples'][0], 'sampleId':'other'})
        with self.assertRaises(ev.ContractError): ev.validate_manifest(m)
        m = manifest(2); m['samples'][1]['startSeconds'] = 0
        with self.assertRaises(ev.ContractError): ev.validate_manifest(m)

    def test_clip_or_participant_group_cannot_cross_splits(self):
        for new_clip in (False, True):
            m = manifest(2)
            m['samples'][1]['split'] = 'development'
            if new_clip: m['samples'][1]['clipSha256'] = '0'*64
            with self.assertRaises(ev.ContractError): ev.validate_manifest(m)

    def test_human_binary_requires_attested_independent_observers_not_ai_or_gt(self):
        m = manifest(1)
        for source in ('unreviewed', 'ai_proxy', 'dataset_author', 'gt_angle_proxy'):
            labels, predictions = ev.templates(m, 'e'*64)
            labels['annotations'][0].update(label='positive', sourceType=source)
            with self.assertRaises(ev.ContractError): ev.evaluate(m, 'e'*64, labels, predictions)
        labels, predictions = ev.templates(m, 'e'*64)
        binary(labels['annotations'][0], 'positive')
        labels['annotations'][0]['adjudicatorId'] = 'synthetic_observer'
        with self.assertRaises(ev.ContractError): ev.evaluate(m, 'e'*64, labels, predictions)

    def test_hash_candidate_protocol_and_unknown_fields_fail(self):
        for field in ('manifestSha256', 'candidateCommit'):
            m = manifest(1); labels, predictions = ev.templates(m, 'e'*64)
            predictions[field] = '0'*64
            with self.assertRaises(ev.ContractError): ev.evaluate(m, 'e'*64, labels, predictions)
        m = manifest(1); labels, predictions = ev.templates(m, 'e'*64)
        labels['annotations'][0]['protocolId'] = 'other'
        with self.assertRaises(ev.ContractError): ev.evaluate(m, 'e'*64, labels, predictions)
        labels, predictions = ev.templates(m, 'e'*64)
        predictions['observations'][0]['angleFromGT'] = 140
        with self.assertRaises(ev.ContractError): ev.evaluate(m, 'e'*64, labels, predictions)

    def test_distinct_rules_same_rep_do_not_inflate_physical_rep_count(self):
        m = manifest(1)
        m['samples'].append({**m['samples'][0], 'sampleId':'other', 'rule':'pushup_shallow'})
        labels, predictions = ev.templates(m, 'e'*64)
        r = ev.evaluate(m, 'e'*64, labels, predictions)['overall']
        self.assertEqual((r['opportunities'], r['physicalReps']), (2, 1))

    def test_cli_end_to_end_inputs_unchanged_and_existing_outputs_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            protocol, boundaries = d/'protocol.md', d/'boundaries.json'
            protocol.write_text('synthetic protocol'); boundaries.write_text('[]')
            m = manifest(2)
            m['protocolSha256'] = hashlib.sha256(protocol.read_bytes()).hexdigest()
            m['boundaryManifestSha256'] = hashlib.sha256(boundaries.read_bytes()).hexdigest()
            path = d/'manifest.json'; path.write_text(json.dumps(m))
            before = path.read_bytes()
            shared = ['--manifest',str(path),'--protocol',str(protocol),'--boundary-manifest',str(boundaries)]
            task = d/'new-task'
            self.assertEqual(ev.main(['template',*shared,'--output-dir',str(task)]), 0)
            self.assertEqual(ev.main(['template',*shared,'--output-dir',str(task)]), 2)
            output = d/'result.json'
            args = ['score',*shared,'--labels',str(task/'labels.json'),'--predictions',str(task/'predictions.json'),'--output',str(output)]
            self.assertEqual(ev.main(args), 0)
            report = output.read_bytes()
            self.assertEqual(ev.main(args), 2)
            self.assertEqual((output.read_bytes(),path.read_bytes()),(report,before))
            protocol.write_text('changed')
            self.assertEqual(ev.main(['template',*shared,'--output-dir',str(d/'other')]), 2)

    def test_duplicate_json_keys_nonfinite_and_changed_snapshot_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)/'input.json'
            for content in ('{"a":1,"a":2}', '{"a":NaN}'):
                p.write_text(content)
                with self.assertRaises(ev.ContractError): ev.load(p)
            p.write_text('{}'); _, digest = ev.load(p); p.write_text('[]')
            with self.assertRaises(ev.ContractError): ev.unchanged([(p,digest)])

    def test_rule_catalog_matches_native_fault_event_ids(self):
        native = (ROOT/'ios/Runner/NativePose/Evaluators/FormWarnings.swift').read_text()
        ids = set(ev.RULES['squat'] + ev.RULES['pushup'] + ev.RULES['barbell_row'] + ev.RULES['bench_press'] + ev.RULES['deadlift'])
        fired = set(__import__('re').findall(r'fire\("([a-z_]+)"', native))
        self.assertEqual(ids, fired - {'setup_side_view'})  # setup eligibility is not a per-rep form fault.

    def test_schema_declares_the_same_identity_and_catalog_contract(self):
        schema = json.loads((ROOT/'scripts/form_eval/input.schema.json').read_text())
        identity = schema['$defs']['identity']
        self.assertEqual(set(identity['required']), set(ev.IDENTITY))
        self.assertEqual(set(identity['properties']), set(ev.IDENTITY))
        self.assertEqual(set(identity['properties']['rule']['enum']), {r for values in ev.RULES.values() for r in values})
        self.assertEqual(set(schema['$defs']['annotation']['allOf'][1]['required']), set(ev.LABEL_FIELDS))
        self.assertEqual(set(schema['$defs']['observation']['allOf'][1]['required']), set(ev.PRED_FIELDS))

    def test_private_adapter_keeps_50fps_boundaries_unknown_and_development_only(self):
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            jobs = []
            for i in range(2):
                clip = d/'train'/f's{i}'/'videos'/'cam'/'pushup.mp4'
                clip.parent.mkdir(parents=True); clip.write_bytes(f'synthetic_clip_{i}'.encode())
                jobs.append({'subject':f's{i}', 'cam':'cam', 'fit3d':'pushup', 'exercise':'pushup', 'reps':[10,30,50]})
            jobs_path = d/'jobs.json'; jobs_path.write_text(json.dumps(jobs))
            protocol = d/'protocol.md'; protocol.write_text('synthetic protocol')
            probe = json.dumps({'streams':[{'r_frame_rate':'50/1','avg_frame_rate':'50/1','duration':'3'}]}).encode()
            with patch.object(adapter.subprocess,'check_output',return_value=probe):
                result = adapter.prepare(jobs_path,d,protocol,'c'*40,d/'task',expected_jobs=2)
            self.assertEqual((result['clips'],result['physicalReps'],result['opportunities']),(2,4,32))
            self.assertEqual(result['holdoutOpportunities'],0)
            m,_ = ev.load(d/'task/manifest.json')
            self.assertEqual((m['samples'][0]['startSeconds'],m['samples'][0]['endSeconds']),(0.2,0.6))
            labels,_ = ev.load(d/'task/labels.json')
            self.assertTrue(all(r['label']=='unknown' for r in labels['annotations']))
            self.assertTrue((d/'task/review_index_PRIVATE.json').exists())
            with patch.object(adapter.subprocess,'check_output',return_value=probe), self.assertRaises(FileExistsError):
                adapter.prepare(jobs_path,d,protocol,'c'*40,d/'task',expected_jobs=2)


if __name__ == '__main__':
    unittest.main()
