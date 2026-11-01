#!/usr/bin/env python3
"""Local, stdlib-only per-rep/rule evaluation. Never generates ground-truth labels."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys

PROTOCOL = 'bpt-independent-form-v1'
RULES = {
    'squat': ('squat_hips_first', 'squat_shallow', 'squat_no_lockout', 'squat_lean_drift',
              'squat_depth_fade', 'squat_knee_valgus', 'squat_heel_rise'),
    'pushup': ('pushup_hip_sag', 'pushup_hip_pike', 'pushup_shallow', 'pushup_no_lockout',
               'pushup_head_drop', 'pushup_head_up', 'pushup_hand_position', 'pushup_depth_fade'),
    'barbell_row': ('row_torso_swing', 'row_standing_up', 'row_short_pull', 'row_head_up', 'row_shrug'),
    'bench_press': ('bench_hips_up', 'bench_shallow', 'bench_no_lockout'),
    'deadlift': ('deadlift_hips_first', 'deadlift_no_lockout', 'deadlift_lean_back'),
}
IDENTITY = ('sampleId', 'clipSha256', 'exercise', 'rep', 'rule', 'side', 'startSeconds',
            'endSeconds', 'timeUnit', 'labelUnit', 'split', 'splitGroup', 'visibility',
            'contactChange', 'windowCoverage')
LABEL_FIELDS = ('label', 'sourceType', 'observerId', 'adjudicatorId', 'protocolId')
PRED_FIELDS = ('state', 'reason')
STATES = ('warning', 'no_warning', 'withheld', 'missing')
HEX64 = re.compile(r'[0-9a-f]{64}\Z')
COMMIT = re.compile(r'[0-9a-f]{40}\Z')
ID = re.compile(r'[A-Za-z0-9_.:-]{1,100}\Z')


class ContractError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ContractError(message)


def keys(obj, fields, where):
    require(isinstance(obj, dict) and set(obj) == set(fields), f'{where}: missing/unknown fields')


def ident(value, name):
    require(isinstance(value, str) and ID.fullmatch(value), f'invalid {name}')


def sha(value, name):
    require(isinstance(value, str) and HEX64.fullmatch(value), f'invalid {name}')


def integer(value):
    return type(value) is int and value >= 1


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def load(path):
    raw = Path(path).read_bytes()
    # Reject duplicate JSON keys instead of accepting a different last value.
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f'duplicate JSON key: {key}')
            result[key] = value
        return result
    try:
        value = json.loads(raw, object_pairs_hook=unique,
                           parse_constant=lambda token: (_ for _ in ()).throw(ContractError(f'nonfinite JSON: {token}')))
    except (ValueError, UnicodeError) as error:
        raise ContractError(f'{path}: {error}') from error
    return value, hashlib.sha256(raw).hexdigest()


def validate_manifest(manifest):
    keys(manifest, ('schemaVersion', 'protocolId', 'protocolSha256', 'candidateCommit',
                    'splitPlanId', 'dataKind', 'boundarySource', 'boundaryManifestSha256', 'samples'), 'manifest')
    require(type(manifest['schemaVersion']) is int and manifest['schemaVersion'] == 1, 'unsupported schemaVersion')
    require(manifest['protocolId'] == PROTOCOL, 'unsupported protocol')
    sha(manifest['protocolSha256'], 'protocolSha256')
    require(isinstance(manifest['candidateCommit'], str) and COMMIT.fullmatch(manifest['candidateCommit']), 'invalid candidateCommit')
    ident(manifest['splitPlanId'], 'splitPlanId')
    require(manifest['dataKind'] in ('evaluation', 'synthetic_fixture'), 'invalid dataKind')
    require(manifest['boundarySource'] in ('human_windows', 'ai_windows', 'dataset_reference_intervals', 'synthetic'), 'invalid boundarySource')
    sha(manifest['boundaryManifestSha256'], 'boundaryManifestSha256')
    samples = manifest['samples']
    require(isinstance(samples, list) and samples, 'manifest needs sample opportunities')
    ids, opportunities, clips, groups, windows = {}, set(), {}, {}, {}
    for sample in samples:
        keys(sample, IDENTITY, 'sample')
        ident(sample['sampleId'], 'sampleId')
        sha(sample['clipSha256'], 'clipSha256')
        require(isinstance(sample['exercise'], str) and sample['exercise'] in RULES and sample['rule'] in RULES[sample['exercise']], 'unknown exercise/rule pair')
        require(integer(sample['rep']), 'rep must be a positive integer')
        require(sample['side'] in ('none', 'left', 'right', 'both'), 'invalid side')
        require(finite(sample['startSeconds']) and finite(sample['endSeconds'])
                and 0 <= sample['startSeconds'] < sample['endSeconds'], 'invalid time window')
        require(sample['timeUnit'] == 'seconds' and sample['labelUnit'] == 'per_rep_rule_binary_fault', 'unit mismatch')
        require(sample['split'] in ('development', 'holdout'), 'invalid split')
        ident(sample['splitGroup'], 'splitGroup')
        require(sample['visibility'] in ('adequate', 'occluded', 'out_of_view', 'unknown'), 'invalid visibility')
        require(sample['contactChange'] in ('yes', 'no', 'unknown'), 'invalid contactChange')
        require(sample['windowCoverage'] in ('full_rep', 'partial_rep', 'unknown'), 'invalid windowCoverage')
        sid = sample['sampleId']
        require(sid not in ids, f'duplicate sampleId: {sid}')
        opportunity = tuple(sample[k] for k in ('clipSha256', 'rep', 'rule', 'side'))
        require(opportunity not in opportunities, f'duplicate opportunity: {sid}')
        opportunities.add(opportunity)
        clip = sample['clipSha256']
        group = sample['splitGroup']
        clip_scope = (sample['exercise'], sample['split'], group)
        require(clip not in clips or clips[clip] == clip_scope, 'cross-clip exercise/split/group mismatch')
        require(group not in groups or groups[group] == sample['split'], 'splitGroup crosses split')
        clips[clip], groups[group] = clip_scope, sample['split']
        rep = (clip, sample['rep'])
        window = tuple(sample[k] for k in ('startSeconds', 'endSeconds', 'windowCoverage'))
        require(rep not in windows or windows[rep] == window, 'rep time/window mismatch between rules')
        windows[rep] = window
        ids[sid] = sample
    for clip in clips:
        ordered = sorted((rep, value) for (digest, rep), value in windows.items() if digest == clip)
        for (_, before), (_, after) in zip(ordered, ordered[1:]):
            require(before[1] <= after[0], 'rep windows overlap or rep order disagrees with time')
    return ids


def validate_rows(document, manifest, digest, kind):
    row_key = 'annotations' if kind == 'labels' else 'observations'
    fields = ('schemaVersion', 'manifestSha256', row_key) if kind == 'labels' else (
        'schemaVersion', 'manifestSha256', 'candidateCommit', row_key)
    keys(document, fields, kind)
    require(type(document['schemaVersion']) is int and document['schemaVersion'] == 1, 'unsupported row schemaVersion')
    require(document['manifestSha256'] == digest, f'{kind}: manifest hash mismatch')
    if kind != 'labels':
        require(document['candidateCommit'] == manifest['candidateCommit'], 'candidate mismatch')
    samples = validate_manifest(manifest)
    require(isinstance(document[row_key], list), f'{kind}: rows must be an array')
    indexed = {}
    for row in document[row_key]:
        keys(row, IDENTITY + (LABEL_FIELDS if kind == 'labels' else PRED_FIELDS), kind)
        sid = row['sampleId']
        require(isinstance(sid, str) and sid in samples, f'{kind}: unexpected sampleId')
        require(sid not in indexed, f'{kind}: duplicate sampleId {sid}')
        require(all(type(row[k]) is type(samples[sid][k]) and row[k] == samples[sid][k] for k in IDENTITY),
                f'{kind}: identity/hash/side/unit/time mismatch for {sid}')
        if kind == 'labels':
            require(row['label'] in ('positive', 'negative', 'unknown'), 'invalid label')
            require(row['protocolId'] == manifest['protocolId'], 'label protocol mismatch')
            require(row['sourceType'] in ('unreviewed', 'human_adjudicated'), 'AI/GT proxy labels are not expert labels')
            if row['label'] != 'unknown':
                require(row['sourceType'] == 'human_adjudicated', 'binary labels require human adjudication')
            if row['sourceType'] == 'human_adjudicated':
                ident(row['observerId'], 'observerId')
                ident(row['adjudicatorId'], 'adjudicatorId')
                require(row['observerId'] != row['adjudicatorId'], 'independent adjudicator required')
            else:
                require(row['observerId'] is None and row['adjudicatorId'] is None, 'unreviewed observer fields must stay null')
        else:
            require(row['state'] in STATES, 'invalid prediction state')
            require(row['reason'] is None or isinstance(row['reason'], str) and ID.fullmatch(row['reason']), 'reason must be a local nonidentifying code')
            if row['state'] in ('withheld', 'missing'):
                require(row['reason'] is not None, 'withheld/missing requires an explicit reason code')
        indexed[sid] = row
    require(set(indexed) == set(samples), f'{kind}: missing rows; represent unknown/missing explicitly')
    return indexed


def templates(manifest, digest):
    validate_manifest(manifest)
    annotations, observations = [], []
    for sample in manifest['samples']:
        annotations.append({**sample, 'label': 'unknown', 'sourceType': 'unreviewed',
                            'observerId': None, 'adjudicatorId': None, 'protocolId': manifest['protocolId']})
        observations.append({**sample, 'state': 'missing', 'reason': 'not_imported'})
    return ({'schemaVersion': 1, 'manifestSha256': digest, 'annotations': annotations},
            {'schemaVersion': 1, 'manifestSha256': digest, 'candidateCommit': manifest['candidateCommit'],
             'observations': observations})


def ratio(numerator, denominator):
    return {'numerator': numerator, 'denominator': denominator,
            'value': numerator / denominator if denominator else None}


def metrics(samples, labels, predictions):
    adjudicated = [s for s in samples if labels[s['sampleId']]['label'] != 'unknown']
    counts = {'TP': 0, 'FP': 0, 'FN': 0, 'TN': 0}
    withheld = {'positive': 0, 'negative': 0}
    missing = {'positive': 0, 'negative': 0}
    positive = 0
    states = dict.fromkeys(STATES, 0)
    for sample in samples:
        sid = sample['sampleId']
        states[predictions[sid]['state']] += 1
    for sample in adjudicated:
        sid = sample['sampleId']
        label, state = labels[sid]['label'], predictions[sid]['state']
        positive += label == 'positive'
        if state in ('withheld', 'missing'):
            (withheld if state == 'withheld' else missing)[label] += 1
        else:
            cell = ('TP' if label == 'positive' else 'FP') if state == 'warning' else (
                'FN' if label == 'positive' else 'TN')
            counts[cell] += 1
    selected = sum(counts.values())
    n = len(adjudicated)
    strict_fn = counts['FN'] + withheld['positive'] + missing['positive']
    return {
        'opportunities': len(samples), 'physicalReps': len({(s['clipSha256'], s['rep']) for s in samples}),
        'adjudicated': n, 'unknownLabels': len(samples) - n, 'predictionStatesAllRows': states,
        'selectiveConfusion': counts,
        'withheldAdjudicated': withheld, 'missingAdjudicated': missing,
        'strictFNIncludingMisses': strict_fn,
        'strictRecall': ratio(counts['TP'], positive),
        'selectiveRecall': ratio(counts['TP'], counts['TP'] + counts['FN']),
        'selectiveSpecificity': ratio(counts['TN'], counts['TN'] + counts['FP']),
        'selectiveAccuracy': ratio(counts['TP'] + counts['TN'], selected),
        'precision': ratio(counts['TP'], counts['TP'] + counts['FP']),
        'decisionCoverage': ratio(selected, n),
        'correctCoverage': ratio(counts['TP'] + counts['TN'], n),
        # Abstained negatives are unresolved, never silently counted as true negatives.
        'unresolvedNegative': withheld['negative'] + missing['negative'],
    }


def evaluate(manifest, digest, labels, predictions):
    label_rows = validate_rows(labels, manifest, digest, 'labels')
    pred_rows = validate_rows(predictions, manifest, digest, 'predictions')
    samples = manifest['samples']
    by = {}
    for field in ('split', 'exercise', 'rule', 'side', 'visibility', 'contactChange', 'windowCoverage'):
        by[field] = {value: metrics([s for s in samples if s[field] == value], label_rows, pred_rows)
                     for value in sorted({s[field] for s in samples})}
    return {'schemaVersion': 1, 'protocolId': manifest['protocolId'],
            'protocolSha256': manifest['protocolSha256'], 'candidateCommit': manifest['candidateCommit'],
            'splitPlanId': manifest['splitPlanId'], 'dataKind': manifest['dataKind'],
            'boundarySource': manifest['boundarySource'], 'boundaryManifestSha256': manifest['boundaryManifestSha256'],
            'unit': 'per_rep_rule_binary_fault', 'overall': metrics(samples, label_rows, pred_rows),
            'by': by}


def write_new(path, value):
    # Exclusive creation also rejects existing files, symlinks and input/output aliases.
    with Path(path).open('x', encoding='utf-8') as output:
        json.dump(value, output, indent=2, allow_nan=False)
        output.write('\n')


def unchanged(paths_and_hashes):
    for path, digest in paths_and_hashes:
        require(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, f'input changed during run: {path}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    template = sub.add_parser('template')
    template.add_argument('--manifest', required=True)
    template.add_argument('--output-dir', required=True)
    score = sub.add_parser('score')
    score.add_argument('--manifest', required=True)
    score.add_argument('--labels', required=True)
    score.add_argument('--predictions', required=True)
    score.add_argument('--output', required=True)
    for command in (template, score):
        command.add_argument('--protocol', required=True)
        command.add_argument('--boundary-manifest', required=True)
    args = parser.parse_args(argv)
    try:
        manifest, digest = load(args.manifest)
        protocol_hash = hashlib.sha256(Path(args.protocol).read_bytes()).hexdigest()
        boundary_hash = hashlib.sha256(Path(args.boundary_manifest).read_bytes()).hexdigest()
        require(manifest.get('protocolSha256') == protocol_hash, 'protocol file hash mismatch')
        require(manifest.get('boundaryManifestSha256') == boundary_hash, 'boundary manifest file hash mismatch')
        provenance = [(args.protocol, protocol_hash), (args.boundary_manifest, boundary_hash)]
        if args.command == 'template':
            labels, predictions = templates(manifest, digest)
            unchanged([(args.manifest, digest)] + provenance)
            os.mkdir(args.output_dir, 0o700)  # Refuse to overwrite any existing annotation workspace.
            write_new(Path(args.output_dir) / 'labels.json', labels)
            write_new(Path(args.output_dir) / 'predictions.json', predictions)
        else:
            labels, lh = load(args.labels)
            predictions, ph = load(args.predictions)
            result = evaluate(manifest, digest, labels, predictions)
            result['inputSha256'] = {'manifest': digest, 'labels': lh, 'predictions': ph, 'protocol': protocol_hash, 'boundaryManifest': boundary_hash}
            unchanged([(args.manifest, digest), (args.labels, lh), (args.predictions, ph)] + provenance)
            write_new(args.output, result)
        return 0
    except (ContractError, OSError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
