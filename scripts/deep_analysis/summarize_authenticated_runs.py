"""Export aggregate transport/runtime evidence without account IDs, URLs or poses."""
from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path


def summarize(root: Path, runs: list[str], cpu_inspection: Path | None = None) -> dict:
    inputs = json.loads((root / 'input_manifest.json').read_text())
    by_hash = {row['sha256']: row for row in inputs['inputs']}
    instances = {}
    rows = []
    for name in runs:
        evidence = json.loads((root / name / 'evidence.json').read_text())
        report = json.loads((root / name / 'report.json').read_text())
        if evidence.get('result') != 'passed' or not all(evidence['checks'].values()):
            raise ValueError('incomplete_or_failed_run:' + name)
        source = by_hash[evidence['source_sha256']]
        duration = float(source['video']['duration'])
        resources = report.get('resourceUsage', {})
        peak = resources.get('deviceUsedPeakMiB')
        worker = (evidence.get('worker_timing') or {}).get('seconds', {})
        runtime = report.get('runtime', {})
        instance = runtime.get('instanceId')
        if instance:
            instances.setdefault(instance, 'process_' + str(len(instances) + 1))
        runner_seconds = report.get('runnerElapsedSeconds')
        reasons = collections.Counter(reason for rep in report['reps']
                                      for value in rep['metricValidity'].values()
                                      for reason in value['reasons'])
        row = {
            'run': name, 'deployment': evidence['deployment'], 'started_at': evidence['started_at'],
            'input_sha256': evidence['source_sha256'], 'input_bytes': source['bytes'],
            'input_seconds': duration, 'input_frames': int(source['video']['nb_frames']),
            'authenticated_checks_passed': len(evidence['checks']),
            'client_verification_seconds': evidence['elapsed_seconds'],
            'runner_stage_seconds': report['timingSeconds'],
            'runner_stage_sum_seconds': round(sum(report['timingSeconds'].values()), 3),
            'runner_elapsed_seconds': runner_seconds,
            'processing_seconds': report.get('processingTimingSeconds'),
            'worker_seconds': worker or None,
            'worker_scope': (evidence.get('worker_timing') or {}).get('scope'),
            'sampled_device_peak_mib': peak,
            'sample_interval_ms': resources.get('samplingIntervalMs'),
            'worker_process': instances.get(instance, 'not_recorded'),
            'job_ordinal_in_process': runtime.get('jobOrdinal'),
            'first_job_in_process': runtime.get('firstJobInProcess'),
            'metric_assessments': evidence['metric_assessments'],
            'metric_withholding_reasons': dict(sorted(reasons.items())),
            'calibration_shape_used': report['bodyShape']['source'] == 'calibration',
            'exercise_accuracy_evaluation': False,
        }
        row['performance_gates'] = {
            '60s_worker_le_180_seconds': None if duration < 59.9 or not worker else worker['total'] <= 180,
            '60s_runner_le_180_seconds': None if duration < 59.9 or runner_seconds is None else runner_seconds <= 180,
            'sampled_peak_le_22_decimal_gb': None if peak is None else peak * 2**20 <= 22_000_000_000,
        }
        rows.append(row)
    result = {
        'purpose': 'authenticated_transport_and_runtime_only',
        'inputs': inputs['preparation'],
        'notes': [
            'The same consented calibration clip is repeated for runtime tests; no real exercise labels are supplied.',
            'Client time includes login, upload, polling and contract checks/downloads; it is not GPU time.',
            'Worker time excludes container startup, queue wait and the final state commit; see the recorded scope.',
            'Process identity proves reuse only, not platform cold/warm startup or retained model weights.',
            'VRAM is sampled device-wide used memory every 20 ms; brief unsampled peaks remain possible.',
            '22 GB is conservatively interpreted as 22,000,000,000 bytes; raw MiB is retained.',
            'Available metric support is not proof of correct 3D pose or correct coaching.',
        ],
        'runs': rows,
    }
    if cpu_inspection is not None:
        benchmark = json.loads(cpu_inspection.read_text())
        if benchmark.get('result') != 'completed' or benchmark.get('read_only_inspection') is not True:
            raise ValueError('cpu_benchmark_requires_completed_read_only_inspection')
        baseline = next(r for r in rows if r['input_sha256'] == benchmark['source_video_sha256'])
        keys = ('requested_cpu_cores', 'deployed_defaults_changed', 'source_video_sha256',
                'exercise_accuracy_evaluation', 'worker_timing', 'runner_elapsed_seconds',
                'runner_stage_seconds', 'processing_seconds', 'resource_usage', 'numeric_values_compared',
                'numeric_changed_count', 'unit_specific_differences', 'numerically_identical',
                'non_numeric_changed_paths', 'faults_identical', 'metric_validity_identical')
        comparison = {key: benchmark[key] for key in keys}
        comparison['baseline_run'] = baseline['run']
        baseline_report = json.loads((root / baseline['run'] / 'report.json').read_text())
        benchmark_instance = benchmark.get('runtime', {}).get('instanceId')
        baseline_instance = baseline_report.get('runtime', {}).get('instanceId')
        comparison['process_reused_from_baseline'] = (benchmark_instance == baseline_instance
                                                    if benchmark_instance and baseline_instance else None)
        comparison['n_per_condition'] = 1
        comparison['performance_gates'] = {
            '60s_worker_le_180_seconds': benchmark['worker_timing']['seconds']['total'] <= 180,
            '60s_runner_le_180_seconds': benchmark['runner_elapsed_seconds'] <= 180,
            'sampled_peak_le_22_decimal_gb': benchmark['resource_usage']['deviceUsedPeakMiB'] * 2**20 <= 22_000_000_000,
        }
        comparison['notes'] = [
            'Invocation-only cpu=4 override; no deployed default changes and no new source video upload.',
            'A different worker process and one run per condition do not establish a causal CPU-allocation effect.',
            'Full faults/metricValidity equality includes numerical evidence/support, not only categorical decisions.',
            'Nonidentical report values are not an exercise-accuracy evaluation; the fixture contains synthetic rep intervals.',
        ]
        result['cpu_allocation_diagnostic'] = comparison
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--runs', nargs='+', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu-inspection', type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('refusing to overwrite existing evidence')
    result = summarize(args.root, args.runs, args.cpu_inspection)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'runs': len(result['runs']), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
