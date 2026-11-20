"""One isolated CPU-allocation benchmark of an already-consented completed job.

Uses Modal invocation options; never changes the deployed Function's defaults.
Only the exact previously verified calibration-video hash is eligible. No account
enumeration, fresh upload, credentials, body parameters, or video bytes are returned.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import uuid
from pathlib import Path

import modal

ROOT = Path(__file__).resolve().parents[2] if modal.is_local() else Path('/root')
if modal.is_local():
    sys.path.insert(0, str(ROOT / 'server/calibration_modal'))
app = modal.App('bpt-deep-cpu-benchmark-20261026')
image = (modal.Image.debian_slim(python_version='3.12')
         .pip_install('boto3==1.43.110').add_local_python_source('storage'))


@app.function(image=image, cpu=.25, memory=256, timeout=1000, retries=0,
              secrets=[modal.Secret.from_name('bpt-r2')])
def benchmark(source_job: str, expected_video_sha: str, expected_shape_job: str, inspect_only: bool = False):
    import storage
    bucket = storage.Bucket.from_env()
    state = storage.BucketState(bucket)
    source = state.get('deep-job:' + source_job)
    if not source or source.get('status') != 'done':
        raise ValueError('source_job_not_done')
    if source.get('manifest', {}).get('testPurpose') != 'transport_only_calibration_clip_synthetic_intervals':
        raise ValueError('source_is_not_authorized_transport_fixture')
    if source.get('shape', {}).get('calibrationJobId') != expected_shape_job:
        raise ValueError('unexpected_calibration_source')
    if hashlib.sha256(bucket.get(source['prefix'] + 'video.mp4')).hexdigest() != expected_video_sha:
        raise ValueError('unexpected_source_video')
    job_id = 'job-' + uuid.uuid5(uuid.NAMESPACE_URL, 'bpt-cpu4-20261026:' + source_job).hex
    key = 'deep-job:' + job_id
    previous = state.get(key)
    if inspect_only and (not previous or previous.get('status') != 'done'):
        raise ValueError('read_only_inspection_requires_completed_benchmark')
    if previous and previous.get('status') != 'done':
        raise ValueError('benchmark_already_submitted_no_automatic_retry')
    if previous is None:
        job = {k: source[k] for k in ('userId', 'sessionId', 'sizes', 'prefix', 'manifest', 'shape', 'type')}
        job.update(jobId=job_id, queuedAt=time.time(), status='queued', progressRate=0, attempt=0)
        if not state.put(key, job, skip_if_exists=True):
            raise ValueError('benchmark_concurrent_submission')
        function = modal.Function.from_name('bpt-calibration', 'deep_analysis_job').with_options(cpu=4)
        function.remote(job)
    completed = state.get(key)
    if completed.get('status') != 'done':
        return {'result': 'failed', 'worker_error': completed.get('error')}
    report = completed['report']
    old_report = source['report']
    numeric_diffs, changed_paths = [], []

    def compare(a, b, path):
        if type(a) in (int, float) and type(b) in (int, float):
            numeric_diffs.append({'path': path, 'absolute_difference': abs(a - b)})
        elif isinstance(a, dict) and isinstance(b, dict) and a.keys() == b.keys():
            for k in a:
                compare(a[k], b[k], path + '.' + k)
        elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
            for i, (x, y) in enumerate(zip(a, b)):
                compare(x, y, path + '.' + str(i))
        elif a != b:
            changed_paths.append(path)

    # Rounded clinical/biomechanical validity is not established by numerical parity.
    for section in ('reps', 'faults', 'timeline', 'summary', 'consistency', 'bodyShape', 'rules'):
        compare(report[section], old_report[section], section)
    groups = {
        'anglesDeg_degrees': [x for x in numeric_diffs if '.anglesDeg.' in x['path']],
        'extrema_frame_indices': [x for x in numeric_diffs if x['path'].endswith(('.topFrame', '.bottomFrame'))],
        'extrema_seconds': [x for x in numeric_diffs if x['path'].endswith(('.topTime', '.bottomTime'))],
    }
    return {
        'result': 'completed', 'requested_cpu_cores': 4, 'deployed_defaults_changed': False,
        'read_only_inspection': inspect_only,
        'source_video_sha256': expected_video_sha, 'exercise_accuracy_evaluation': False,
        'worker_timing': completed.get('workerTiming'), 'runner_elapsed_seconds': report.get('runnerElapsedSeconds'),
        'runner_stage_seconds': report['timingSeconds'], 'processing_seconds': report.get('processingTimingSeconds'),
        'resource_usage': report.get('resourceUsage'), 'runtime': report.get('runtime'),
        'numeric_values_compared': len(numeric_diffs),
        'numeric_max_absolute_difference': max((x['absolute_difference'] for x in numeric_diffs), default=0),
        'numeric_changed_count': sum(x['absolute_difference'] > 0 for x in numeric_diffs),
        'numeric_largest_differences': sorted((x for x in numeric_diffs if x['absolute_difference'] > 0),
                                              key=lambda x: x['absolute_difference'], reverse=True)[:25],
        'numerically_identical': not any(x['absolute_difference'] > 0 for x in numeric_diffs) and not changed_paths,
        'unit_specific_differences': {name: {
            'compared': len(values), 'changed': sum(x['absolute_difference'] > 0 for x in values),
            'max_absolute_difference': max((x['absolute_difference'] for x in values), default=0),
        } for name, values in groups.items()},
        'faults_identical': report['faults'] == old_report['faults'],
        'metric_validity_identical': [r.get('metricValidity') for r in report['reps']]
                                   == [r.get('metricValidity') for r in old_report['reps']],
        'non_numeric_changed_paths': changed_paths,
    }


@app.local_entrypoint()
def main(evidence: str, report: str, output: str, inspect_only: bool = False):
    target = Path(output)
    if target.exists():
        raise ValueError('preserve_existing_benchmark_evidence')
    e = json.loads(Path(evidence).read_text())
    r = json.loads(Path(report).read_text())
    if e.get('result') != 'passed' or e.get('exercise_quality_evaluation') is not False:
        raise ValueError('source_transport_smoke_not_verified')
    started = time.monotonic()
    result = benchmark.remote(e['job_id'], e['source_sha256'], r['bodyShape']['calibrationJobId'], inspect_only)
    result['coordinator_elapsed_seconds'] = round(time.monotonic() - started, 3)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps({k: result.get(k) for k in ('result', 'runner_elapsed_seconds', 'numeric_max_absolute_difference')}))
