#!/usr/bin/env python3
"""Read-only Home-private cache contract audit. No arrays, models, media or report adapter.

NPZ headers are inspected without numpy/pickle. Per-file identities/hashes stay in a
new private receipt; stdout is aggregate only. Absence is never replaced by zeros,
tracking masks, empty on-device warnings or ground-truth-derived app metadata.
"""
import argparse
import ast
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import struct
import zipfile


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def header(archive, key):
    with archive.open(key + '.npy') as source:
        if source.read(6) != b'\x93NUMPY': raise ValueError('invalid numpy header')
        version = source.read(2)
        width = 2 if version[0] == 1 else 4 if version[0] in (2, 3) else 0
        if not width: raise ValueError('unsupported numpy header')
        length = int.from_bytes(source.read(width), 'little')
        if not 0 < length <= 1024 * 1024: raise ValueError('invalid numpy header length')
        data = ast.literal_eval(source.read(length).decode('utf-8' if version[0] == 3 else 'latin1'))
        return {'shape': list(data['shape']), 'dtype': data['descr']}


def audit(base, receipt, expected_jobs_sha):
    base, receipt = Path(base), Path(receipt)
    jobs_path = base / 'jobs.json'
    if digest(jobs_path) != expected_jobs_sha: raise ValueError('job manifest changed')
    jobs = json.loads(jobs_path.read_text())
    if not isinstance(jobs, list) or len(jobs) != 20: raise ValueError('expected frozen20')
    files = {jobs_path: digest(jobs_path)}
    records, schemas, missing, dimensions = [], Counter(), Counter(), Counter()
    for job in jobs:
        tag = '_'.join(job[k] for k in ('subject', 'exercise', 'cam'))
        for variant in ('B', 'C'):
            directory = base / 'work' / tag / variant
            result, timing = directory / 'result.npz', directory / 'timing.json'
            files[result], files[timing] = digest(result), digest(timing)
            meta = json.loads(timing.read_text())
            with zipfile.ZipFile(result) as archive:
                keys = sorted(Path(name).stem for name in archive.namelist())
                schemas[tuple(keys)] += 1
                shapes = {key: header(archive, key) for key in ('h36m17_world', 'vitpose_coco17') if key in keys}
                for key in ('h36m17_world', 'vitpose_coco17', 'tracked_mask'):
                    if key not in keys: missing[key] += 1
                if 'tracked_mask' in keys: shapes['tracked_mask'] = header(archive, 'tracked_mask')
            world = shapes.get('h36m17_world', {}).get('shape')
            support = shapes.get('vitpose_coco17', {}).get('shape')
            dimensions['world_T_17_3'] += bool(world and len(world) == 3 and world[1:] == [17, 3])
            dimensions['vitpose_T_17_3'] += bool(support and len(support) == 3 and support[1:] == [17, 3])
            dimensions['matching_world_vitpose_frames'] += bool(world and support and world[0] == support[0])
            dimensions['matching_metadata_frames'] += bool(world and world[0] == meta.get('frames'))
            dimensions['runtime_fps_30'] += meta.get('fps') == 30
            dimensions['source_fps_50'] += meta.get('src_fps') == 50
            dimensions['person_frame_ratio_available'] += (
                type(meta.get('person_frames')) in (int, float) and type(meta.get('frames')) in (int, float)
                and 0 <= meta['person_frames'] <= meta['frames'] and meta['frames'] > 0)
            records.append({'privateRelativePath': str(directory.relative_to(base)), 'headers': shapes,
                            'metadataKeys': sorted(meta), 'variant': variant})
    candidates, json_count, weak, nested = [], 0, 0, 0
    for path in base.rglob('*.json'):
        if 'code' in path.relative_to(base).parts: continue
        try: data = json.loads(path.read_text())
        except (ValueError, OSError): continue
        json_count += 1
        if isinstance(data, dict):
            if data.get('schemaVersion') == 1 and data.get('timebase') == 'video_ms' and isinstance(data.get('reps'), list):
                candidates.append(str(path.relative_to(base)))
            weak += isinstance(data.get('reps'), list) and data.get('exerciseId') is not None
            nested += isinstance(data.get('manifest'), dict)
    # This tool audits only. Even a future candidate needs verified correspondence to
    # its source clip, timestamps and real native observations before a service replay.
    file_records = [{'privateRelativePath': str(p.relative_to(base)), 'sha256': sha} for p, sha in sorted(files.items())]
    for path, before in files.items():
        if digest(path) != before: raise ValueError('input changed while auditing')
    commitment = hashlib.sha256(json.dumps(file_records, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    private = {'files': file_records, 'records': records, 'serviceManifestCandidates': candidates}
    with receipt.open('x', encoding='utf-8') as output:
        os.chmod(receipt, 0o600)
        json.dump(private, output, indent=2)
        output.write('\n')
    return {'purpose': 'saved_cache_contract_audit_not_service_replay_or_accuracy',
        'status': 'service_replay_not_executed', 'jobs': len(jobs), 'resultFiles': len(records),
        'inputFilesHashedAndRechecked': len(files), 'inputsUnchanged': True,
        'inputSetSha256': commitment, 'jobsSha256': files[jobs_path],
        'headerChecks': dict(dimensions), 'missingArrays': dict(missing),
        'npzSchemaCounts': [{'keys': list(keys), 'count': count} for keys, count in schemas.items()],
        'nonCodeJsonFilesInspected': json_count, 'videoMsManifestCandidates': len(candidates),
        'exerciseRepsObjects': weak, 'nestedManifestObjects': nested,
        'researchBoundarySource': 'dataset_reference_intervals_50fps_with_side_gt_not_native_manifest',
        'beforeReportsExecuted': 0, 'afterReportsExecuted': 0,
        'fullyValidContentParity': None, 'actualPartialNullCount': None,
        'wholeJobRejectionCount': None, 'withheldMetricCount': None,
        'blocker': 'no_saved_native_video_ms_manifest_or_observed_side_warning_correspondence'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--private-receipt', required=True)
    parser.add_argument('--expected-jobs-sha', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(audit(args.base, args.private_receipt, args.expected_jobs_sha), indent=2))
        return 0
    except Exception as error:
        # Do not expose private per-video paths via errors.
        print(json.dumps({'status': 'audit_blocked', 'errorType': type(error).__name__}))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
