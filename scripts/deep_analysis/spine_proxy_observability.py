"""Home-only evaluation of a three-joint bend proxy, never a lumbar-curvature classifier.

Only exercise aggregates leave Home. GT is used for evaluation, never model input.
"""
import argparse
import json
import sys
from pathlib import Path
import numpy as np


def bend_proxy(joints):
    a = joints[:, 0] - joints[:, 7]
    b = joints[:, 8] - joints[:, 7]
    denominator = np.linalg.norm(a, axis=-1) * np.linalg.norm(b, axis=-1)
    result = np.full(len(joints), np.nan)
    valid = denominator > 1e-10
    result[valid] = 180 - np.degrees(np.arccos(np.clip(
        np.sum(a[valid] * b[valid], axis=-1) / denominator[valid], -1, 1)))
    return result


def trunk_tilt(joints, up):
    v = (joints[:, 11] + joints[:, 14] - joints[:, 1] - joints[:, 4]) / 2
    norm = np.linalg.norm(v, axis=-1)
    result = np.full(len(joints), np.nan)
    valid = norm > 1e-10
    result[valid] = np.degrees(np.arccos(np.clip((v[valid] @ up) / norm[valid], -1, 1)))
    return result


def stats(values):
    values = np.asarray(values); values = values[np.isfinite(values)]
    if not len(values):
        return None
    return {'count': len(values), 'meanDeg': float(values.mean()), 'stdDeg': float(values.std()),
            'minDeg': float(values.min()), 'maxDeg': float(values.max()),
            'p05Deg': float(np.percentile(values, 5)), 'p95Deg': float(np.percentile(values, 95))}


def correlation(pred, reference):
    ok = np.isfinite(pred) & np.isfinite(reference)
    p, g = pred[ok], reference[ok]
    # Numerical constancy guard, NOT a clinical cutoff or an accepted normal range.
    if len(g) < 3 or g.std() < .001 or p.std() < 1e-9:
        return None
    return float(np.corrcoef(p, g)[0, 1])


def synthetic_examples():
    j = np.zeros((3, 17, 3))
    j[:, 7] = [0, 1, 0]; j[:, 8] = [0, 2, 0]
    theta = np.radians(60)
    rotation = np.array([[1, 0, 0], [0, np.cos(theta), -np.sin(theta)], [0, np.sin(theta), np.cos(theta)]])
    j[1] = j[1] @ rotation.T
    j[2, 8] = j[2, 7] + [0, np.cos(np.radians(30)), np.sin(np.radians(30))]
    for k in range(3):
        j[k, 1] = j[k, 4] = j[k, 0]
        j[k, 11] = j[k, 14] = j[k, 8]
    return {name: {'proxyDeg': float(bend_proxy(j)[i]), 'wholeTrunkTiltDeg': float(trunk_tilt(j, np.array([0., 1, 0]))[i])}
            for i, name in enumerate(['straight_upright', 'rigid_tilt_60deg', 'upper_segment_bend_30deg'])}


def evaluate(run, require_complete):
    sys.path.insert(0, str(run/'code/deep_analysis'))
    sys.path.insert(0, str(run/'code'))
    import eval_gvhmr_fit3d as evaluation
    e = evaluation.ev()
    root = Path.home()/'datasets/fit3d'
    grouped = {}
    jobs = json.loads((run/'jobs.json').read_text())
    for job in jobs:
        directory = run/'work'/evaluation.tag(job)
        gt = e.load_joints(str(root/'train'/job['subject']), job['fit3d'])
        indices = evaluation.pick_frames(len(gt)); gt = gt[indices]
        R, _, _ = evaluation.load_cam(root, job['subject'], job['cam'], job['fit3d'])
        up = evaluation.world_up(R)
        inside = np.zeros(len(gt), dtype=bool)
        for start, end in zip(job['reps'], job['reps'][1:]):
            lo, hi = np.searchsorted(indices, [start, end]); inside[lo:min(hi+1,len(gt))] = True
        predictions = {}
        for name, path, key, vertical in [
            ('XS_legacy', directory/'A.npz', 'P', [0,-1,0]),
            ('GVHMR_B', directory/'B/result.npz', 'h36m17_world', [0,1,0]),
            ('GVHMR_C_oracle_intrinsics', directory/'C/result.npz', 'h36m17_world', [0,1,0]),
            ('floor_oracle_neutral_smplx', directory/'floor.npz', 'P', up)]:
            if not path.exists():
                if require_complete and name.startswith('GVHMR'):
                    raise ValueError('incomplete GVHMR cohort')
                continue
            with np.load(path, allow_pickle=False) as z:
                pred = z[key]
                n = min(len(pred),len(gt)); selected = inside[:n]
                predictions[name] = (bend_proxy(pred[:n])[selected], trunk_tilt(pred[:n], np.array(vertical))[selected],
                                     bend_proxy(gt[:n])[selected], trunk_tilt(gt[:n],up)[selected])
        grouped.setdefault(job['exercise'], []).append((bend_proxy(gt)[inside], trunk_tilt(gt,up)[inside], predictions))
    result = {'definition': '180-angle(pelvis0,spine7,thorax8), unsigned 3-joint proxy, not lumbar curvature',
              'correlationGuardReferenceStdDeg': .001, 'syntheticExamples': synthetic_examples(),
              'C3': {'assessed': False, 'reason': 'no_matching_fit3d_per_frame_cache_found'}, 'exercises': {}}
    for exercise, clips in grouped.items():
        ref = np.concatenate([c[0] for c in clips]); tilt = np.concatenate([c[1] for c in clips])
        stds = np.array([np.nanstd(c[0]) for c in clips])
        result['exercises'][exercise] = row = {'videos': len(clips), 'referenceProxy': stats(ref),
            'referenceWholeTrunkTilt': stats(tilt),
            'withinVideoReferenceStdDeg': {'min':float(stds.min()),'median':float(np.median(stds)),'max':float(stds.max())},
            'referenceNumericallyConstantVideos': int((stds<.001).sum()),
            'referenceStdBelowOneDegreeVideos': int((stds<1).sum()), 'variants': {}}
        for name in sorted({name for c in clips for name in c[2]}):
            sets = [c[2][name] for c in clips if name in c[2]]
            p,t,g,gt = [np.concatenate([s[i] for s in sets]) for i in range(4)]
            correlations = [v for s in sets if (v:=correlation(s[0],s[2])) is not None]
            row['variants'][name] = {'videos':len(sets),'proxy':stats(p),
                'proxyMaeDeg':float(np.nanmean(np.abs(p-g))),
                'wholeTrunkTiltMaeDeg':float(np.nanmean(np.abs(t-gt))),
                'withinVideoCorrelationCount':len(correlations),
                'medianWithinVideoCorrelation':float(np.median(correlations)) if correlations else None}
    return result


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--run',type=Path,required=True);parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--require-complete-gvhmr',action='store_true')
    args=parser.parse_args()
    args.out.write_text(json.dumps(evaluate(args.run,args.require_complete_gvhmr),indent=2,allow_nan=False))
