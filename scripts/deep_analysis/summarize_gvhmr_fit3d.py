"""Export only exercise-level aggregates from a Home-only Fit3D evaluation.

Raw joints, videos, per-subject profiles and per-rep metrics remain on Home.
The legacy evaluator/thresholds are frozen; this does not certify the live coaching catalog.
"""
import argparse
import importlib.util
import json
from pathlib import Path

import numpy as np


def summarize(rows, evaluator):
    variants = ['A2D', 'A', 'B', 'C', 'Bw', 'Cw', 'floor']
    summary = {'videos': len(rows), 'exercises': {}, 'decisionAgreement': {},
               'interpretation': {'B': 'monocular_default_intrinsics_no_gt_shape',
                                  'C': 'oracle_dataset_camera_intrinsics_no_gt_shape',
                                  'floor': 'oracle_gt_smplx_joint_definition_diagnostic',
                                  'viewSelection': 'GT-assisted camera selection frozen before results',
                                  'repAccuracy': 'net_count_proxy_not_temporally_matched_detection_accuracy',
                                  'decisionRules': 'frozen_20261020_legacy_not_current_team_catalog'}}
    for exercise in evaluator.EXERCISES:
        cohort = [r for r in rows if r['exercise'] == exercise]
        result = {'videos': len(cohort), 'framesInsideReps': sum(r['frames'] for r in cohort),
                  'referenceReps': sum(r['reps_truth'] for r in cohort),
                  'referenceCounterReps': sum(r['reps'].get('GT', 0) for r in cohort),
                  'referenceCounterNetAccuracy': evaluator.rep_acc(cohort, 'GT'), 'variants': {}}
        for variant in variants:
            available = [r for r in cohort if variant in r['angle_err']]
            if not available:
                continue
            angles = {key: float(np.mean([r['angle_err'][variant][key] for r in available]))
                      for key in ['knee', 'hip', 'elbow', 'torso']}
            errors = [float(np.mean(list(r['angle_err'][variant].values()))) for r in available]
            pa = [r['pa_mpjpe_mm'][variant] for r in available if variant in r['pa_mpjpe_mm']]
            result['variants'][variant] = {'videos': len(available), 'angleMaeDeg': angles,
                'fourAngleMeanDeg': float(np.mean(errors)), 'acrossVideoStdDeg': float(np.std(errors)),
                'paMpjpeMm': float(np.mean(pa)) if pa else None,
                'repNetCountAccuracy': evaluator.rep_acc(cohort, variant),
                'predictedReps': sum(r['reps'][variant] for r in available)}
        summary['exercises'][exercise] = result
    for key in evaluator.KEYS:
        summary['decisionAgreement'][key] = {v: {'agree': counts[0], 'total': counts[1],
                   'nearAgree': counts[2], 'nearTotal': counts[3]}
                   for v, counts in evaluator.decisions(rows, key).items()}
    gates = {}
    for variant in ['B', 'C']:
        per_ex = {}
        for exercise in ['squat', 'barbell_row', 'pushup']:
            methods = summary['exercises'][exercise]['variants']
            if not all(v in methods for v in ['A', variant]):
                per_ex[exercise] = {'status': 'missing_comparator'}
                continue
            counts = {v: np.zeros(4, dtype=int) for v in ['A', variant]}
            for key, (ex, _, _) in evaluator.KEYS.items():
                if ex != exercise:
                    continue
                decisions = evaluator.decisions(rows, key)
                for v in counts:
                    counts[v] += decisions.get(v, [0, 0, 0, 0])
            near = counts['A'][3] > 0
            idx = 2 if near else 0
            agreement = {v: float(c[idx]/c[idx+1]) if c[idx+1] else None for v, c in counts.items()}
            per_ex[exercise] = {'angleImproves': methods[variant]['fourAngleMeanDeg'] < methods['A']['fourAngleMeanDeg'],
                               'agreementScope': 'near_threshold' if near else 'all_reps',
                               'agreement': agreement,
                               'agreementNotWorse': (agreement[variant] >= agreement['A'])
                                if all(x is not None for x in agreement.values()) else None}
        gates[variant] = {'exercises': per_ex, 'criterion1Pass': all(
            r.get('angleImproves') and r.get('agreementNotWorse') for r in per_ex.values())}
    summary['preregisteredCriterion1'] = gates
    summary['acceptanceLimitations'] = ['L4_60s_latency_not_measured_here', 'L4_peak_vram_not_measured_here',
                                       'portrait_geometry_not_tested_by_square_fit3d',
                                       'rep_accuracy_uses_net_counts_not_event_matching',
                                       'historical_input_hashes_not_recorded_for_11_reused_pairs']
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--score', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--expected-videos', type=int, default=20)
    args = parser.parse_args()
    path = Path(__file__).with_name('eval_gvhmr_fit3d.py')
    spec = importlib.util.spec_from_file_location('frozen_evaluator', path)
    evaluator = importlib.util.module_from_spec(spec); spec.loader.exec_module(evaluator)
    rows = json.loads(args.score.read_text())
    if len(rows) != args.expected_videos:
        raise SystemExit(f'incomplete cohort: {len(rows)} != {args.expected_videos}')
    args.out.write_text(json.dumps(summarize(rows, evaluator), indent=2, allow_nan=False))
