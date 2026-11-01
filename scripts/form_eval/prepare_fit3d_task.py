#!/usr/bin/env python3
"""HOME-PRIVATE metadata/window adapter, no pose arrays/inference or form-label import.

Hashes existing video bytes and reads ffprobe metadata only. Never displays media.
The previously explored frozen20 is DEVELOPMENT ONLY, not a new holdout.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from independent_form_eval import PROTOCOL, RULES, ContractError, load, require, templates, write_new


def prepare(jobs_path, root, protocol_path, candidate, output_dir, expected_jobs=20, ffprobe="ffprobe"):
    jobs, boundary_hash = load(jobs_path)
    require(isinstance(jobs, list) and len(jobs) == expected_jobs, 'unexpected frozen job count')
    protocol_hash = hashlib.sha256(Path(protocol_path).read_bytes()).hexdigest()
    samples, review_index, groups, hashes, frame_rates = [], [], {}, {}, set()
    for index, job in enumerate(jobs, 1):
        exercise = job['exercise']
        require(exercise in RULES, 'unsupported job exercise')
        # Paths never leave this private adapter/output directory.
        clip = Path(root) / 'train' / job['subject'] / 'videos' / job['cam'] / (job['fit3d'] + '.mp4')
        require(clip.is_file(), 'existing source clip missing')
        probe = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-select_streams', 'v:0',
            '-show_entries', 'stream=r_frame_rate,avg_frame_rate,duration', '-of', 'json', str(clip)], stderr=subprocess.DEVNULL))
        stream = probe['streams'][0]
        for field in ('r_frame_rate', 'avg_frame_rate'):
            n, d = map(int, stream[field].split('/'))
            require(d > 0 and n / d == 50, 'source must retain verified dataset 50fps clock')
        duration = float(stream['duration'])
        frame_rates.add(50)
        hasher = hashlib.sha256()
        with clip.open('rb') as raw:
            for chunk in iter(lambda: raw.read(1024 * 1024), b''):
                hasher.update(chunk)
        digest = hasher.hexdigest()
        require(digest not in hashes, 'duplicate source clip bytes; review grouping before task generation')
        hashes[digest] = index
        groups.setdefault(job['subject'], f'g{len(groups) + 1:04d}')
        boundaries = job['reps']
        require(isinstance(boundaries, list) and len(boundaries) >= 2 and
                all(type(n) is int and n >= 0 for n in boundaries), 'invalid dataset boundary clock')
        for rep, (start, end) in enumerate(zip(boundaries, boundaries[1:]), 1):
            require(start < end and end / 50 <= duration + 0.04, 'boundary outside source clip')
            for rule in RULES[exercise]:
                samples.append({'sampleId': f'c{index:04d}.r{rep:04d}.{rule}', 'clipSha256': digest,
                    'exercise': exercise, 'rep': rep, 'rule': rule, 'side': 'none',
                    'startSeconds': start / 50, 'endSeconds': end / 50,
                    'timeUnit': 'seconds', 'labelUnit': 'per_rep_rule_binary_fault',
                    'split': 'development', 'splitGroup': groups[job['subject']],
                    'visibility': 'unknown', 'contactChange': 'unknown', 'windowCoverage': 'unknown'})
        review_index.append({'clipId': f'c{index:04d}', 'clipSha256': digest, 'localClipPath': str(clip),
                             'boundarySource': 'dataset_reference_intervals', 'sourceFrameRate': 50})
    manifest = {'schemaVersion': 1, 'protocolId': PROTOCOL, 'protocolSha256': protocol_hash,
        'candidateCommit': candidate, 'splitPlanId': 'existing20_explored_development_only',
        'dataKind': 'evaluation', 'boundarySource': 'dataset_reference_intervals',
        'boundaryManifestSha256': boundary_hash, 'samples': samples}
    # Validate every identity and generate only unknown/missing, before creating any output.
    manifest_bytes = (json.dumps(manifest, indent=2, allow_nan=False) + '\n').encode()
    manifest_hash = hashlib.sha256(manifest_bytes).hexdigest()
    labels, predictions = templates(manifest, manifest_hash)
    require(hashlib.sha256(Path(jobs_path).read_bytes()).hexdigest() == boundary_hash, 'boundary input changed')
    require(hashlib.sha256(Path(protocol_path).read_bytes()).hexdigest() == protocol_hash, 'protocol input changed')
    output = Path(output_dir)
    output.mkdir(mode=0o700)  # Exclusive private workspace; never overwrite prior annotations.
    with (output / 'manifest.json').open('xb') as f:
        f.write(manifest_bytes)
    write_new(output / 'labels.json', labels)
    write_new(output / 'predictions.json', predictions)
    write_new(output / 'review_index_PRIVATE.json', review_index)
    return {'clips': len(jobs), 'groups': len(groups), 'opportunities': len(samples),
            'physicalReps': len({(s['clipSha256'], s['rep']) for s in samples}),
            'unknownLabels': len(samples), 'missingPredictions': len(samples),
            'sourceFrameRates': sorted(frame_rates), 'holdoutOpportunities': 0,
            'boundarySource': manifest['boundarySource'], 'boundaryManifestSha256': boundary_hash,
            'manifestSha256': manifest_hash, 'protocolSha256': protocol_hash}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', required=True)
    parser.add_argument('--root', required=True)
    parser.add_argument('--protocol', required=True)
    parser.add_argument('--candidate-commit', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--ffprobe', default='ffprobe', help='existing local metadata tool only; no download')
    args = parser.parse_args()
    try:
        result = prepare(args.jobs, args.root, args.protocol, args.candidate_commit, args.output_dir, ffprobe=args.ffprobe)
        print(json.dumps(result, sort_keys=True))  # Counts/hashes only, no paths/identities/arrays.
    except (ContractError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        # Paths in subprocess exceptions may identify a clip: do not print exception payload.
        print(json.dumps({'status': 'blocked', 'errorType': type(error).__name__}))
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
