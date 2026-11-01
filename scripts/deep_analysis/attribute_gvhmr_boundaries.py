"""Home-only CPU score attribution; exports aggregate counts/errors, never identities.

Consumes frozen evaluator per-rep scores only. It does not change thresholds,
models, predictions, preregistered acceptance, or use GT as inference input.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np

VARIANTS = ('A2D', 'A', 'B', 'C', 'Bw', 'Cw', 'floor')


def distribution(values):
    a = np.asarray(values, dtype=float)
    a = a[np.isfinite(a)]
    return {'count': int(len(a)), 'min': float(a.min()) if len(a) else None,
            'median': float(np.median(a)) if len(a) else None,
            'max': float(a.max()) if len(a) else None,
            'meanAbsolute': float(np.abs(a).mean()) if len(a) else None}


def attribute(rows, evaluator):
    result = {'purpose': 'aggregate_legacy_boundary_failure_attribution_not_acceptance_rescore',
              'boundaryDegrees': evaluator.BOUNDARY, 'videos': len(rows), 'metrics': {}}
    for key, (exercise, fn, threshold) in evaluator.KEYS.items():
        cohort = [r for r in rows if r['exercise'] == exercise]
        metric = {'exercise': exercise, 'thresholdDegrees': threshold,
                  'operator': 'value_strictly_greater_than_threshold', 'variants': {}}
        for variant in VARIANTS:
            truths, predictions, baseline = [], [], []
            reference_errors, current_errors = [], []
            for row in cohort:
                reps = row['rep_metrics']
                if variant not in reps:
                    continue
                g = np.array(fn(reps['GT']), dtype=float)
                p = np.array(fn(reps[variant]), dtype=float)
                a = np.array(fn(reps['A']), dtype=float) if 'A' in reps else np.full_like(g, np.nan)
                if g.shape != p.shape or g.shape != a.shape:
                    raise ValueError('unaligned score lengths')
                near = np.isfinite(g) & np.isfinite(p) & (np.abs(g - threshold) <= evaluator.BOUNDARY)
                truths.extend(g[near]); predictions.extend(p[near]); baseline.extend(a[near])
                if key.endswith('no_lockout'):
                    field = 'knee_max' if exercise == 'squat' else 'elbow_max'
                    gc = np.asarray([r[field] for r in reps['GT']], dtype=float)
                    pc = np.asarray([r[field] for r in reps[variant]], dtype=float)
                    wrong = near & ((g > threshold) != (p > threshold))
                    reference_errors.extend((np.maximum.accumulate(pc) - np.maximum.accumulate(gc))[wrong])
                    current_errors.extend((pc - gc)[wrong])
            g, p, a = (np.array(v, dtype=float) for v in (truths, predictions, baseline))
            mismatch = (g > threshold) != (p > threshold)
            finite_a = np.isfinite(a)
            metric['variants'][variant] = {
                'nearTotal': len(g), 'nearAgree': int((~mismatch).sum()),
                'falsePositiveVsAngleThreshold': int(((g <= threshold) & (p > threshold)).sum()),
                'falseNegativeVsAngleThreshold': int(((g > threshold) & (p <= threshold)).sum()),
                'baselineCorrectVariantWrong': int((finite_a & ((a > threshold) == (g > threshold)) & mismatch).sum()),
                'baselineWrongVariantCorrect': int((finite_a & ((a > threshold) != (g > threshold)) & ~mismatch).sum()),
                'truthSignedMarginDegrees': distribution(g - threshold),
                'predictionSignedMarginDegrees': distribution(p - threshold),
                'signedPredictionErrorDegrees': distribution(p - g),
                'disagreementTruthSignedMarginDegrees': distribution((g - threshold)[mismatch]),
                'disagreementPredictionSignedMarginDegrees': distribution((p - threshold)[mismatch]),
                'disagreementSignedPredictionErrorDegrees': distribution((p - g)[mismatch]),
            }
            if key.endswith('no_lockout'):
                metric['variants'][variant]['disagreementDeficitComponents'] = {
                    'identity': 'deficit_error_equals_running_set_max_error_minus_current_rep_max_error',
                    'runningSetMaxErrorDegrees': distribution(reference_errors),
                    'currentRepMaxErrorDegrees': distribution(current_errors)}
        sensitivity = {}
        for camera, world in [('B', 'Bw'), ('C', 'Cw')]:
            decision_changed = total = 0
            errors_delta = []
            for row in cohort:
                reps = row['rep_metrics']
                if camera not in reps or world not in reps:
                    continue
                g, c, w = [np.asarray(fn(reps[v]), dtype=float) for v in ('GT', camera, world)]
                if not (g.shape == c.shape == w.shape):
                    raise ValueError('unaligned world diagnostic lengths')
                near = np.isfinite(g) & np.isfinite(c) & np.isfinite(w) & (np.abs(g-threshold) <= evaluator.BOUNDARY)
                total += int(near.sum())
                decision_changed += int(((c > threshold) != (w > threshold))[near].sum())
                errors_delta.extend((np.abs(w-g) - np.abs(c-g))[near])
            sensitivity[f'{camera}_to_{world}'] = {'nearTotal': total, 'decisionChanged': decision_changed,
                'worldMinusCameraAbsoluteErrorDegrees': distribution(errors_delta)}
        metric['separateWorldUpDiagnostic'] = sensitivity
        result['metrics'][key] = metric
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--score', type=Path, required=True)
    p.add_argument('--evaluator', type=Path, default=Path(__file__).with_name('eval_gvhmr_fit3d.py'))
    p.add_argument('--expected-videos', type=int, default=20)
    args = p.parse_args()
    spec = importlib.util.spec_from_file_location('frozen_evaluator', args.evaluator)
    evaluator = importlib.util.module_from_spec(spec); spec.loader.exec_module(evaluator)
    rows = json.loads(args.score.read_text())
    if len(rows) != args.expected_videos:
        raise SystemExit('incomplete cohort')
    output = attribute(rows, evaluator)
    output['evaluatorSha256'] = hashlib.sha256(args.evaluator.read_bytes()).hexdigest()
    output['scoreSha256'] = hashlib.sha256(args.score.read_bytes()).hexdigest()
    print(json.dumps(output, indent=2, allow_nan=False))
