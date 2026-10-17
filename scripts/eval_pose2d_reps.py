"""Rep accuracy and feedback-event counts of a pose model through the app's evaluators (pose-replay).

Runs pose-replay (whole-frame input like the app, no 3D) on Exercise3D 13 sets x 3 cams plus the
no-motion regression videos (squat_03 truth 2, calibration dummies truth 0), then scores reps against
outputs/rep_validation/gt.json with analyze.py's matching (each app rep end credits the latest
uncredited truth trough at or before it; leftovers = missed / extra).
rep accuracy = (truth - missed) / (truth + extra).

BPT_HEAVY_SH=<heavy.sh> wraps each pose-replay call in the shared lock.
Also the standing "sway" synthesis (outputs/rep_validation/no_motion_synth.py, truth 0): this model's own keypoints of
4 standing stretches (squat_03 end/mid, dummy_01, Exercise3D squat_0002 cam1) looped 600 frames x 11 perturbations,
replayed through the squat and row evaluators.

usage: eval_pose2d_reps.py --binary PATH --name NAME --model coco17|halpe26|mcoco17 [--model-path MLPACKAGE] --out DIR
"""

import argparse
import collections
import csv
import concurrent.futures as cf
import glob
import json
import os
import subprocess

import numpy as np

from eval_pose2d import GT_JSON, MAIN
from pose_feedback.body.pose2d_data import match_reps as match

EXERCISE = {'squat': 'squat', 'pushup': 'pushup', 'barbellrow': 'row'}
DUMMIES = sorted(glob.glob(str(MAIN / 'outputs/calibration_dummy_videos/dummy_0*.mp4')))
SQUAT_03 = MAIN / 'assets/coreml_pipeline/videos/squat_03.mp4'
# Shared lock per video so other tracks' builds/tests interleave (BRIEF coordination protocol).
HEAVY = os.environ.get('BPT_HEAVY_SH')


def run(binary, model, model_path, exercise, video, out):
    os.makedirs(out, exist_ok=True)
    stem = os.path.basename(video)[:-4]
    cached = glob.glob(f'{out}/{stem}_*_{model}.json')
    if cached:
        return json.load(open(cached[0]))
    cmd = [binary, '--exercise', exercise, '--model', model, '--motion3d', 'none', '--output-dir', out, video]
    if model_path:
        cmd[1:1] = ['--model-path', model_path]
    if HEAVY:
        cmd = [HEAVY] + cmd
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    return json.load(open(glob.glob(f'{out}/{stem}_*_{model}.json')[0]))


SWAY_SRC = {'squat03_end': ('regression_squat', 'squat_03', 'squat', 380, 477), 'squat03_mid': ('regression_squat', 'squat_03', 'squat', 175, 215),
            'dummy01_front': ('regression_squat', 'dummy_01_male-3-sport', 'squat', 0, 40),
            'e3d_squat0002_cam1': ('squat_0002', 'cam1', 'squat', 0, 25)}
SWAY_CASES = [('none', 0)] + [('sway_x', a) for a in (0.05, 0.10)] + [('bob', a) for a in (0.03, 0.06, 0.10)] \
    + [('weight_shift', a) for a in (0.03, 0.06)] + [('jitter', a) for a in (0.01, 0.02)] + [('combo', 0.05)]


def perturb(X, kind, amp, rng):
    """Same as outputs/rep_validation/no_motion_synth.py: loop standing keypoints 600 frames @30 fps + one perturbation."""
    n = 600; idx = list(range(len(X))) + list(range(len(X) - 2, 0, -1))
    Y = np.array([X[idx[i % len(idx)]] for i in range(n)]).copy()
    P = Y[:, 4:].reshape(n, -1, 3)
    t = np.arange(n) / 30.0
    hip = (P[:, 11, :2] + P[:, 12, :2]) / 2; ank = (P[:, 15, :2] + P[:, 16, :2]) / 2
    leg = np.median(np.linalg.norm(hip - ank, axis=1)); H = np.median(np.abs(P[:, 0, 1] - ank[:, 1]))
    if kind == 'sway_x':
        P[:, :, 0] += amp * H * np.sin(2 * np.pi * 0.5 * t)[:, None]
    elif kind in ('bob', 'combo'):
        if kind == 'combo':
            P[:, :, 0] += 0.05 * H * np.sin(2 * np.pi * 0.5 * t)[:, None]
        d = amp * leg * (1 - np.cos(2 * np.pi * 0.7 * t)) / 2
        P[:, :13, 1] += d[:, None]; P[:, [13, 14], 1] += d[:, None] / 2
        if kind == 'combo':
            P[:, :, :2] += rng.normal(0, 0.01 * H, P[:, :, :2].shape)
    elif kind == 'weight_shift':
        d = amp * leg * np.sin(2 * np.pi * 0.4 * t)
        P[:, [11, 13], 1] += d[:, None]; P[:, [12, 14], 1] -= d[:, None]
        P[:, :, 0] += 0.5 * amp * H * np.sin(2 * np.pi * 0.4 * t)[:, None]
    elif kind == 'jitter':
        P[:, :, :2] += rng.normal(0, amp * H, P[:, :, :2].shape)
    Y[:, 4:] = P.reshape(n, -1); Y[:, 0] = np.arange(n); Y[:, 1] = t
    return Y


def sway(binary, model, out):
    """Standing keypoints + perturbations -> squat and row rep counts (truth 0)."""
    rows = []
    for name, (sub, stem, ex, a, b) in SWAY_SRC.items():
        rows_csv = list(csv.reader(open(glob.glob(f'{out}/{sub}/{stem}_{ex}_{model}.csv')[0])))
        head = rows_csv[0]
        X = np.array([[0, float(r[1]), 0, 0] + [float(x or 0) for x in r[4:]] for r in rows_csv[1 + a:1 + b]])
        for kind, amp in SWAY_CASES:
            Y = perturb(X, kind, amp, np.random.default_rng(0))
            tag = f'{name}_{kind}{amp}'
            p = f'{out}/sway/{tag}.csv'; os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, 'w') as f:
                f.write(','.join(head) + '\n')
                for r in Y:
                    f.write(','.join(['%d' % r[0], '%.4f' % r[1], 'x', '0'] + ['%.3f' % v for v in r[4:]]) + '\n')
            row = dict(src=name, kind=kind, amp=amp)
            for e, en in (('squat', 'squat'), ('row', 'barbell_row')):
                subprocess.run([binary, '--exercise', e, '--model', model, '--motion3d', 'none', '--keypoints-csv', p,
                                '--output-dir', f'{out}/sway', f'/x/{tag}.mp4'], stdout=subprocess.DEVNULL, check=True)
                row[e] = json.load(open(f'{out}/sway/{tag}_{en}_{model}.json'))['session']['rep_count']
            rows.append(row)
    return rows


def events(res):
    c = collections.Counter()
    for e in res.get('events', []):
        c[e.get('key', '?')] += 1
    return c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--binary', required=True)
    ap.add_argument('--name', required=True)
    ap.add_argument('--model', default='coco17')
    ap.add_argument('--model-path')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    gt = json.load(open(GT_JSON))
    jobs = [(seq, cam) for seq in gt for cam in ('cam1', 'cam2', 'cam3')]

    def job(j):
        seq, cam = j
        g = gt[seq]
        video = str(MAIN / 'outputs/exercise3d_synced' / g['exercise'] / seq / f'{cam}.mp4')
        res = run(a.binary, a.model, a.model_path, EXERCISE[g['exercise']], video, f'{a.out}/{a.name}/{seq}')
        ends = [r['end_frame'] for r in res['reps']]
        credited, extra = match(g['rep_frames'], ends)
        return dict(seq=seq, cam=cam, exercise=g['exercise'], angle=g['views'][cam]['angle_deg'], truth=g['truth_reps'],
                    counted=len(ends), missed=g['truth_reps'] - len(credited), extra=len(extra), events=dict(events(res)),
                    warning_rep_counts=res['session'].get('warning_rep_counts', {}))

    def regression(j):
        exercise, video, truth = j
        res = run(a.binary, a.model, a.model_path, exercise, video, f'{a.out}/{a.name}/regression_{exercise}')
        return dict(video=os.path.basename(video), exercise=exercise, truth=truth, counted=len(res['reps']), events=dict(events(res)))

    with cf.ThreadPoolExecutor(3) as pool:
        rows = list(pool.map(job, jobs))
        reg = list(pool.map(regression, [('squat', str(SQUAT_03), 2)] + [(e, d, 0) for d in DUMMIES for e in ('squat', 'row')]))
    summary = {}
    for side in ('side40', 'other'):
        for ex in ('squat', 'pushup', 'barbellrow'):
            sel = [r for r in rows if r['exercise'] == ex and (round(r['angle']) <= 40) == (side == 'side40')]
            T, mi, xe = sum(r['truth'] for r in sel), sum(r['missed'] for r in sel), sum(r['extra'] for r in sel)
            ev = collections.Counter()
            for r in sel:
                ev.update(r['events'])
            summary[f'{side}/{ex}'] = dict(sets=len(sel), exact=sum(r['counted'] == r['truth'] for r in sel), truth=T,
                                           counted=sum(r['counted'] for r in sel), missed=mi, extra=xe,
                                           rep_accuracy=round((T - mi) / (T + xe), 4) if T else None, events=dict(ev))
    sw = sway(a.binary, a.model, f'{a.out}/{a.name}')
    out = dict(name=a.name, model=a.model, model_path=a.model_path, summary=summary, regression=reg, rows=rows, sway=sw,
               sway_false_reps={e: sum(r[e] for r in sw) for e in ('squat', 'row')})
    json.dump(out, open(f'{a.out}/{a.name}.json', 'w'), indent=1)
    for k, v in summary.items():
        print(a.name, k, {x: v[x] for x in ('sets', 'exact', 'truth', 'counted', 'missed', 'extra', 'rep_accuracy')}, v['events'])
    for r in reg:
        print(a.name, 'regression', r)
    print(a.name, 'sway false reps', out['sway_false_reps'], 'cases', len(sw))


if __name__ == '__main__':
    main()
