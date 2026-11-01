"""Readout-only CPU ablation on Home caches; exports aggregates, never arrays/IDs.

The PRIMARY GT side never follows the candidate side. A separate matched-side
diagnostic is explicitly a changed target, not fixed-target improvement.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import sys

import numpy as np

from ablate_smplx_joint_centers import Pool, assert_metrics, module, sha, trace_metrics

SIDE_JOINTS = {'L': [3, 5, 7, 9, 11, 13, 15], 'R': [4, 6, 8, 10, 12, 14, 16]}
ANGLE_JOINTS = {'L': {'knee': [11, 13, 15], 'hip': [5, 11, 13], 'elbow': [5, 7, 9]},
                'R': {'knee': [12, 14, 16], 'hip': [6, 12, 14], 'elbow': [6, 8, 10]}}


def own_side(keypoints):
    k = np.asarray(keypoints)
    if k.ndim != 3 or k.shape[1:] != (17, 3) or not np.isfinite(k).all():
        raise ValueError('expected finite COCO17 keypoints and confidence')
    means = {s: float(k[:, ids, 2].mean()) for s, ids in SIDE_JOINTS.items()}
    return max('LR', key=lambda s: means[s]), abs(means['L']-means['R'])


def noisy_inputs(joints, keypoints, scenario, rng):
    if scenario == 'retained':
        return joints, keypoints
    if scenario == 'jointNoise10mm':
        return joints + rng.normal(0, .01, joints.shape), keypoints
    if scenario == 'confidenceNoise005':
        k = keypoints.copy()
        k[:, :, 2] = np.clip(k[:, :, 2]+rng.normal(0, .05, k[:, :, 2].shape), 0, 1)
        return joints, k
    raise ValueError('unknown fixed scenario')


def decision_counts(gt, pred, threshold, mask):
    g, p, mask = np.asarray(gt), np.asarray(pred), np.asarray(mask)
    mask = mask & np.isfinite(g) & np.isfinite(p)
    return dict(count=int(mask.sum()), agree=int(((g > threshold) == (p > threshold))[mask].sum()),
                falsePositive=int((mask & (g <= threshold) & (p > threshold)).sum()),
                falseNegative=int((mask & (g > threshold) & (p <= threshold)).sum()))


def side_errors(original, candidate, fixed_gt, matched_gt):
    """Keep the fixed-target and changed-target contracts explicit and separate."""
    return (np.abs(np.asarray(original)-fixed_gt), np.abs(np.asarray(candidate)-fixed_gt),
            np.abs(np.asarray(candidate)-matched_gt))


def run(args):
    args.run, args.root, args.output, args.protocol = [p.resolve() for p in (args.run, args.root, args.output, args.protocol)]
    sys.path.insert(0, str(args.run/'code/deep_analysis'))
    ev = module(args.run/'code/deep_analysis/eval_gvhmr_fit3d.py', 'own_side_frozen_eval')
    e = ev.ev()
    jobs = json.loads((args.run/'jobs.json').read_text())
    rows = json.loads((args.run/'score_full_private.json').read_text())
    assert len(jobs) == len(rows) == 20
    scores = {(r['subject'], r['exercise'], r['cam']): r for r in rows}
    sources = {args.run/'jobs.json', args.run/'score_full_private.json',
               args.run/'code/deep_analysis/eval_gvhmr_fit3d.py', args.run/'code/eval_3d_angles.py'}
    for j in jobs:
        sd = args.root/'train'/j['subject']; d = args.run/'work'/ev.tag(j)
        base = sd/'joints3d_25'/j['fit3d']
        sources.add(base.with_suffix('.npy') if base.with_suffix('.npy').exists() else base.with_suffix('.json'))
        sources.update([sd/'rep_ann.json', sd/'camera_parameters'/j['cam']/(j['fit3d']+'.json')])
        sources.update(d/v/'result.npz' for v in ('B', 'C'))
        sources.update(p for p in (d/'A.npz', d/'floor.npz') if p.exists())
    before = {p: sha(p) for p in sources}
    args.output.with_name('input_hashes_private.json').write_text(json.dumps({str(p): h for p, h in sorted(before.items())}, indent=2)+'\n')
    pool = Pool(); counts = defaultdict(int); decisions = defaultdict(lambda: defaultdict(int))
    rng = np.random.default_rng(20261102); checked = 0; worst = 0.
    for ordinal, j in enumerate(jobs):
        ex = j['exercise']; d = args.run/'work'/ev.tag(j)
        saved = scores[(j['subject'], ex, j['cam'])]
        G = e.load_joints(str(args.root/'train'/j['subject']), j['fit3d'])
        R, _, _ = ev.load_cam(args.root, j['subject'], j['cam'], j['fit3d'])
        pick = ev.pick_frames(len(G)); G = G[pick]; up = ev.world_up(R)
        P, confidence = {}, {}; K = None
        for v in ('B', 'C'):
            with np.load(d/v/'result.npz', allow_pickle=False) as z:
                P[v], P[v+'w'] = z['h36m17_cam'].astype(float), z['h36m17_world'].astype(float)
                confidence[v] = z['vitpose_coco17'].astype(float)
                counts['resultFilesWithStoredTrackingMask'] += int('tracked_mask' in z)
        for v, filename in (('A', 'A.npz'), ('floor', 'floor.npz')):
            if (d/filename).exists():
                with np.load(d/filename, allow_pickle=False) as z:
                    P[v] = z['P'].astype(float)
                    if v == 'A': K = z['K']
        n = min([len(G)]+[len(p) for p in P.values()]+([len(K)] if K is not None else []))
        G = G[:n]; P = {v: p[:n] for v, p in P.items()}
        conf = {v: c[:n] for v, c in confidence.items()}
        old_side = e.near_side(K[:n]) if K is not None else j['side_gt']
        assert old_side == saved['side']
        segs = [(int(np.searchsorted(pick, s)), min(int(np.searchsorted(pick, t)), n-1))
                for s, t in zip(j['reps'], j['reps'][1:]) if int(np.searchsorted(pick, s)) < n-1]
        inside = np.zeros(n, bool)
        for s, t in segs: inside[s:t+1] = True
        gt = {s: e.angles_3d(G, up, s) for s in ('L', 'R')}
        angles = {'GT': gt[old_side]}
        for v, p in P.items():
            pu = up if v == 'floor' else (np.array([0, 1., 0]) if v.endswith('w') else np.array([0, -1., 0]))
            angles[v] = e.angles_3d(p, pu, old_side)
        if K is not None: angles['A2D'] = e.angles_2d(K[:n], old_side)
        metrics = {v: ev.rep_metrics(a, segs) for v, a in angles.items()}
        for v, m in metrics.items():
            c, w = assert_metrics(m, saved['rep_metrics'][v]); checked += c; worst = max(worst, w)
        failed = np.zeros(len(segs), bool)
        failure_key = {'barbell_row': 'row_torso_swing', 'pushup': 'pushup_no_lockout'}.get(ex)
        if failure_key:
            _, fn, thr = ev.KEYS[failure_key]; gv = np.array(fn(metrics['GT']), float)
            for v in ('B', 'C'):
                pv = np.array(fn(metrics[v]), float)
                failed |= np.isfinite(gv) & (abs(gv-thr) <= ev.BOUNDARY) & ((gv > thr) != (pv > thr))
        counts[ex+'/videos'] += 1; counts[ex+'/reps'] += len(segs)
        counts[ex+'/framesInsideReps'] += int(inside.sum())
        counts[ex+'/originalFailureUnionReps'] += int(failed.sum())
        for v in ('B', 'C'):
            for scenario in ('retained', 'jointNoise10mm', 'confidenceNoise005'):
                p, k = noisy_inputs(P[v], conf[v], scenario, rng)
                side, gap = own_side(k)
                assert side == e.near_side(k)
                prefix = '/'.join([scenario, ex, v])
                counts[prefix+'/videos'] += 1
                counts[prefix+'/changedSideVideos'] += int(side != old_side)
                counts[prefix+'/changedSideReps'] += len(segs)*int(side != old_side)
                counts[prefix+'/selectedLeftVideos'] += int(side == 'L')
                pool.add(prefix+'/selectorConfidenceGap', gap)
                oa = e.angles_3d(p, np.array([0, -1., 0]), old_side)
                na = e.angles_3d(p, np.array([0, -1., 0]), side)
                # Side-independent torso is an exact numerical negative control.
                np.testing.assert_array_equal(oa['torso'], na['torso'])
                om, nm = ev.rep_metrics(oa, segs), ev.rep_metrics(na, segs)
                for angle in ('knee', 'hip', 'elbow', 'torso'):
                    key = prefix+'/'+angle
                    pool.paired(key+'/fixedGt/frameDegrees', oa[angle][inside], na[angle][inside], gt[old_side][angle][inside])
                    old_error, new_error, matched_error = side_errors(oa[angle][inside], na[angle][inside],
                                                                    gt[old_side][angle][inside], gt[side][angle][inside])
                    pool.paired(key+'/fixedGt/videoMaeDegrees', np.mean(old_error), np.mean(new_error), 0.)
                    pool.add(key+'/changedTargetDiagnostic/newSideAgainstNewGtVideoMae',
                             np.mean(matched_error))
                    if scenario != 'retained': continue
                    for s in ('L', 'R'):
                        bilateral = e.angles_3d(p, np.array([0, -1., 0]), s)
                        pool.add(prefix+'/immutableBilateral/'+s+'/'+angle+'/videoMaeDegrees',
                                 np.mean(abs(bilateral[angle][inside]-gt[s][angle][inside])))
                    for ri, (s, t) in enumerate(segs):
                        sl = slice(s, t+1)
                        trace = [trace_metrics(a[angle][sl], gt[old_side][angle][sl]) for a in (gt[old_side], oa, na)]
                        jointids = [5, 6, 11, 12] if angle == 'torso' else ANGLE_JOINTS[side][angle]
                        support_group = 'lowRelevantSupport' if k[sl][:, jointids, 2].min() < .35 else 'highRelevantSupport'
                        cohorts = ['allReps', 'originalFailureUnion' if failed[ri] else 'otherReps', support_group,
                                   'smallSelectorGap' if gap < .05 else 'largeSelectorGap']
                        for group in cohorts:
                            for field in ('min', 'max', 'range', 'sustainedRange', 'maxFrameAbsError', 'maxTimingAbsSeconds'):
                                target = 0. if field in ('maxFrameAbsError', 'maxTimingAbsSeconds') else trace[0][field]
                                pool.paired(key+'/fixedGt/'+group+'/'+field, trace[1][field], trace[2][field], target)
                for decision, (exercise, fn, threshold) in ev.KEYS.items():
                    if exercise != ex: continue
                    gvals = np.array(fn(metrics['GT']), float)
                    for readout, m in (('original', om), ('ownDetector', nm)):
                        vals = np.array(fn(m), float)
                        for group, mask in [('all', np.ones(len(segs), bool)),
                                            ('boundary', abs(gvals-threshold) <= ev.BOUNDARY),
                                            ('originalFailureUnion', failed), ('otherReps', ~failed)]:
                            dest = decisions[prefix+'/'+decision+'/'+readout+'/'+group]
                            for name, value in decision_counts(gvals, vals, threshold, mask).items(): dest[name] += value
                if ex == 'pushup' and scenario == 'retained':
                    peaks = [np.array([m['elbow_max'] for m in ms]) for ms in (metrics['GT'], om, nm)]
                    for ri in range(len(segs)):
                        cohort = 'originalFailureUnion' if failed[ri] else 'otherReps'
                        for group in ('allReps', cohort):
                            current = [a[ri] for a in peaks]
                            reference = [max(a[:ri+1]) for a in peaks]
                            for name, vals in [('currentMax', current), ('runningReferenceMax', reference),
                                               ('deficit', np.asarray(reference)-current)]:
                                pool.paired(prefix+'/reference/'+group+'/'+name, vals[1], vals[2], vals[0])
            print('scored', ordinal+1, v, flush=True)
    assert checked == 4632
    unchanged = all(sha(p) == h for p, h in before.items()); assert unchanged
    result = dict(purpose='reused20_own_detector_side_diagnostic_no_adoption',
                  counts=dict(counts), frozenScoreValuesChecked=checked, maximumFrozenScoreDelta=worst,
                  inputFileCount=len(before), allInputHashesUnchanged=unchanged,
                  inputCohortSha256=hashlib.sha256(''.join(sorted(before.values())).encode()).hexdigest(),
                  scoreSha256=sha(args.run/'score_full_private.json'), helperSha256=sha(__file__),
                  protocolSha256=sha(args.protocol), numericHelperSha256=sha(Path(__file__).with_name('ablate_smplx_joint_centers.py')),
                  distributions=pool.result(), decisions=dict(decisions),
                  caveats=['primary_gt_side_is_fixed', 'matched_new_side_gt_is_different_target',
                           'confidence_strata_are_not_noise_labels', 'synthetic_perturbations_are_not_real_validation',
                           'no_expert_form_labels_no_adoption_claim'])
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print(json.dumps({k: result[k] for k in ('counts', 'frozenScoreValuesChecked', 'maximumFrozenScoreDelta', 'allInputHashesUnchanged')}))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--run', type=Path, required=True); p.add_argument('--root', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True); p.add_argument('--protocol', type=Path, required=True)
    run(p.parse_args())
