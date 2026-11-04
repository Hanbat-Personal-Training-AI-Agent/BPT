#!/usr/bin/env python3
"""Import explicit, source-bound native fault decisions into a NEW local task.

This validates an existing export; it neither runs inference nor reconstructs
negative decisions from warning/event logs. See prediction_import_v1.md.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from independent_form_eval import (ContractError, IDENTITY, finite, keys, load,
                                   require, unchanged, validate_manifest,
                                   validate_rows, write_new)

CONTRACT = 'bpt-native-fault-decisions-v1'
RULE_SOURCE = 'ios/Runner/NativePose/Evaluators/FormWarnings.swift'
CHECKS = ('ruleEnabled', 'ruleEvaluated', 'requiredPhaseObserved', 'viewEligible',
          'referenceReady', 'finiteInputs')
EVIDENCE_FIELDS = ('state', 'reason', 'ruleId', 'decisionSemantic',
                   'exposureStartSeconds', 'exposureEndSeconds', 'checks',
                   'positiveEvidenceSufficient')


def file_sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def candidate_source(repo, candidate):
    # Resolve a full immutable commit, never HEAD, a branch or a caller's worktree.
    try:
        commit = subprocess.check_output(['git', '-C', str(repo), 'rev-parse',
            '--verify', candidate + '^{commit}'], stderr=subprocess.DEVNULL).decode().strip()
        require(commit == candidate, 'candidate must resolve to the exact frozen commit')
        return subprocess.check_output(['git', '-C', str(repo), 'show',
            candidate + ':' + RULE_SOURCE], stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as error:
        raise ContractError('frozen candidate rule source unavailable') from error


def convert(evidence, manifest, manifest_sha, rule_source_sha):
    keys(evidence, ('schemaVersion', 'contract', 'candidateCommit', 'manifestSha256',
         'protocolId', 'protocolSha256', 'boundaryManifestSha256', 'ruleSourceSha256',
         'observations'), 'evidence')
    require(type(evidence['schemaVersion']) is int and evidence['schemaVersion'] == 1,
            'unsupported evidence schemaVersion')
    require(evidence['contract'] == CONTRACT, 'unsupported rule contract; no rule-ID or semantic conversion')
    for field in ('candidateCommit', 'protocolId', 'protocolSha256', 'boundaryManifestSha256'):
        require(evidence[field] == manifest[field], f'evidence {field} mismatch')
    require(evidence['manifestSha256'] == manifest_sha, 'evidence manifest hash mismatch')
    require(evidence['ruleSourceSha256'] == rule_source_sha, 'frozen rule source hash mismatch')
    samples = validate_manifest(manifest)
    require(isinstance(evidence['observations'], list), 'evidence observations must be an array')
    observed = {}
    for row in evidence['observations']:
        keys(row, IDENTITY + EVIDENCE_FIELDS, 'evidence observation')
        sid = row['sampleId']
        require(isinstance(sid, str) and sid in samples, 'unexpected evidence sampleId')
        require(sid not in observed, 'duplicate evidence sampleId')
        require(all(type(row[k]) is type(samples[sid][k]) and row[k] == samples[sid][k]
                    for k in IDENTITY), 'evidence exact opportunity identity mismatch')
        require(row['ruleId'] == row['rule'], 'rule ID mapping forbidden')
        require(row['decisionSemantic'] == 'fault_presence', 'desired-match semantics cannot be converted')
        require(row['state'] in ('warning', 'no_warning', 'withheld'), 'evidence requires an explicit decision or gate')
        checks = row['checks']
        keys(checks, CHECKS, 'evaluation checks')
        require(all(type(value) is bool for value in checks.values()), 'evaluation checks must be explicit booleans')
        start, end = row['exposureStartSeconds'], row['exposureEndSeconds']
        require(finite(start) and finite(end) and 0 <= start < end, 'invalid evidence exposure clock')
        require(type(row['positiveEvidenceSufficient']) is bool,
                'positive evidence sufficiency must be explicit')
        if row['state'] == 'no_warning':
            require(all(checks.values()), 'negative decision lacks evaluated rule/phase/view/reference/finite input')
            require(start <= row['startSeconds'] and end >= row['endSeconds'], 'negative exposure omits part of the frozen window')
        elif row['state'] == 'warning':
            require(all(checks[k] for k in ('ruleEnabled', 'ruleEvaluated', 'finiteInputs')),
                    'positive decision lacks evaluated rule or finite relevant input')
            require(row['positiveEvidenceSufficient'], 'positive rule evidence sufficiency not attested')
            require(start >= row['startSeconds'] and end <= row['endSeconds'],
                    'positive witness must be contained in the frozen opportunity')
        # A withheld decision may reflect uncertainty beyond the six checks.
        # Its explicit local reason is required by the prediction validator.
        # Existing prediction validator checks reason codes and requires withheld reason.
        observed[sid] = {**samples[sid], 'state': row['state'], 'reason': row['reason']}
    predictions = {'schemaVersion': 1, 'manifestSha256': manifest_sha,
        'candidateCommit': manifest['candidateCommit'], 'observations': [observed.get(
            sid, {**sample, 'state': 'missing', 'reason': 'not_in_evidence'})
            for sid, sample in samples.items()]}
    validate_rows(predictions, manifest, manifest_sha, 'predictions')
    return predictions


def import_task(task_dir, evidence_path, protocol_path, boundary_path, clip_index_path,
                candidate_repo, output_dir):
    task, output = Path(task_dir), Path(output_dir)
    # Refuse replacement and aliases before opening the potentially large source clips.
    require(not output.exists() and not output.is_symlink(), 'output task already exists')
    paths = {'manifest': task/'manifest.json', 'labels': task/'labels.json',
             'predictions': task/'predictions.json', 'evidence': Path(evidence_path),
             'clipIndex': Path(clip_index_path)}
    loaded = {name: load(path) for name, path in paths.items()}
    manifest, manifest_sha = loaded['manifest']
    validate_manifest(manifest)
    validate_rows(loaded['labels'][0], manifest, manifest_sha, 'labels')
    base = validate_rows(loaded['predictions'][0], manifest, manifest_sha, 'predictions')
    require(all(row['state'] == 'missing' for row in base.values()),
            'base task contains predictions; refusing to replace prior decisions')
    protocol_sha, boundary_sha = file_sha(protocol_path), file_sha(boundary_path)
    require(protocol_sha == manifest['protocolSha256'], 'protocol file hash mismatch')
    require(boundary_sha == manifest['boundaryManifestSha256'], 'boundary manifest file hash mismatch')
    rule_source_sha = hashlib.sha256(candidate_source(candidate_repo, manifest['candidateCommit'])).hexdigest()
    predictions = convert(loaded['evidence'][0], manifest, manifest_sha, rule_source_sha)
    index = loaded['clipIndex'][0]
    require(isinstance(index, list), 'clip index must be an array')
    clips = {}
    for entry in index:
        require(isinstance(entry, dict) and isinstance(entry.get('localClipPath'), str)
                and isinstance(entry.get('clipSha256'), str), 'invalid clip index entry')
        digest = entry['clipSha256']
        require(digest not in clips, 'duplicate clip index hash')
        clips[digest] = Path(entry['localClipPath'])
    required_clips = {s['clipSha256'] for s in manifest['samples']}
    require(set(clips) == required_clips, 'clip index must match exact manifest source hashes')
    for digest, path in clips.items():
        require(file_sha(path) == digest, 'actual source clip bytes hash mismatch')
    preserved = {name: paths[name].read_bytes() for name in ('manifest', 'labels')}
    for name, raw in preserved.items():
        require(hashlib.sha256(raw).hexdigest() == loaded[name][1], 'task input changed before copy')
    snapshots = [(paths[name], digest) for name, (_, digest) in loaded.items()]
    snapshots += [(protocol_path, protocol_sha), (boundary_path, boundary_sha)]
    unchanged(snapshots)
    # Recheck the actual full clip bytes too; export declarations alone are insufficient.
    for digest, path in clips.items():
        require(file_sha(path) == digest, 'source clip bytes changed during import')
    states = {state: sum(row['state'] == state for row in predictions['observations'])
              for state in ('warning', 'no_warning', 'withheld', 'missing')}
    receipt = {'schemaVersion': 1, 'contract': CONTRACT,
        'candidateCommit': manifest['candidateCommit'], 'ruleSourceSha256': rule_source_sha,
        'inputSha256': {name: digest for name, (_, digest) in loaded.items()},
        'protocolSha256': protocol_sha, 'boundaryManifestSha256': boundary_sha,
        'sourceClipSha256': sorted(required_clips), 'predictionStates': states,
        'labelsPreserved': True, 'inferenceRun': False}
    # All validation occurs before exclusive creation. Copy manifest/labels byte-for-byte.
    output.mkdir(mode=0o700)
    for name in ('manifest', 'labels'):
        with (output / (name + '.json')).open('xb') as stream:
            stream.write(preserved[name])
    write_new(output/'predictions.json', predictions)
    write_new(output/'import_receipt.json', receipt)
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('task-dir', 'evidence', 'protocol', 'boundary-manifest', 'clip-index',
                 'candidate-repo', 'output-dir'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args(argv)
    try:
        result = import_task(args.task_dir, args.evidence, args.protocol, args.boundary_manifest,
                             args.clip_index, args.candidate_repo, args.output_dir)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (ContractError, OSError) as error:
        # No participant-bearing file paths or raw observations in console output.
        print(json.dumps({'status': 'rejected', 'errorType': type(error).__name__}), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
