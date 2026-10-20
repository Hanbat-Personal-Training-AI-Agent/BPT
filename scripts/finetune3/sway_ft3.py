"""No-motion (fake rep) test for 2D candidates — the reacquire track's sway.py (itself outputs/rep_validation/no_motion_synth.py,
generator unchanged) with sources, models, binary and output folder as arguments. Standing keypoints of 4 clips (each model's
own keypoints from its pose-replay run, kept CSVs) are looped ping-pong to 600 frames @30 fps, 11 perturbations (none, sideways
sway, knee bob, weight shift, jitter, combo), replayed with pose-replay --keypoints-csv; truth = 0 reps. Mac, bpt-eval.

usage: sway_ft3.py --kp-keep DIR --models mcoco17b,ft2d --exercises squat,row --replay BIN --out DIR
"""
import argparse, csv, itertools, json, os, subprocess

import numpy as np

SRC = {  # name -> (csv with the model placeholder, frame range) — same clips and ranges as sway.py
    'squat03_end': ('squat_03_squat_{m}.csv', 380, 477),
    'squat03_mid': ('squat_03_squat_{m}.csv', 175, 215),
    'dummy01_front': ('v2_dummy_01_male-3-sport_squat_{m}.csv', 0, 40),
    'e3d_squat0002_cam1': ('squat_0002_cam1_squat_{m}.csv', 0, 25),
}
CASES = [('none', 0)] + [('sway_x', a) for a in (0.05, 0.10)] + [('bob', a) for a in (0.03, 0.06, 0.10)] \
    + [('weight_shift', a) for a in (0.03, 0.06)] + [('jitter', a) for a in (0.01, 0.02)] + [('combo', 0.05)]


def load(path, a, b):
    rows = list(csv.reader(open(path)))
    return rows[0], np.array([[0, float(r[1]), 0, 0] + [float(x or 0) for x in r[4:]] for r in rows[1 + a:1 + b]])


def perturb(X, kind, amp, rng):  # sway.py, unchanged
    n = 600; idx = list(range(len(X))) + list(range(len(X) - 2, 0, -1))
    Y = np.array([X[idx[i % len(idx)]] for i in range(n)]).copy()
    P = Y[:, 4:].reshape(n, -1, 3)
    t = np.arange(n) / 30.0
    hip = (P[:, 11, :2] + P[:, 12, :2]) / 2; ank = (P[:, 15, :2] + P[:, 16, :2]) / 2
    leg = np.median(np.linalg.norm(hip - ank, axis=1)); H = np.median(np.abs(P[:, 0, 1] - ank[:, 1]))
    if kind == 'sway_x':
        P[:, :, 0] += amp * H * np.sin(2 * np.pi * 0.5 * t)[:, None]
    elif kind == 'bob':
        d = amp * leg * (1 - np.cos(2 * np.pi * 0.7 * t)) / 2
        upper = [i for i in range(P.shape[1]) if i < 13]
        P[:, upper, 1] += d[:, None]
        P[:, [13, 14], 1] += d[:, None] / 2
    elif kind == 'weight_shift':
        d = amp * leg * np.sin(2 * np.pi * 0.4 * t)
        P[:, [11, 13], 1] += d[:, None]; P[:, [12, 14], 1] -= d[:, None]
        P[:, :, 0] += 0.5 * amp * H * np.sin(2 * np.pi * 0.4 * t)[:, None]
    elif kind == 'jitter':
        P[:, :, :2] += rng.normal(0, amp * H, P[:, :, :2].shape)
    elif kind == 'combo':
        P[:, :, 0] += 0.05 * H * np.sin(2 * np.pi * 0.5 * t)[:, None]
        d = amp * leg * (1 - np.cos(2 * np.pi * 0.7 * t)) / 2
        P[:, :13, 1] += d[:, None]; P[:, [13, 14], 1] += d[:, None] / 2
        P[:, :, :2] += rng.normal(0, 0.01 * H, P[:, :, :2].shape)
    Y[:, 4:] = P.reshape(n, -1); Y[:, 0] = np.arange(n); Y[:, 1] = t
    return Y


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--kp-keep', required=True); p.add_argument('--models', required=True)
    p.add_argument('--exercises', default='squat,row'); p.add_argument('--replay', required=True); p.add_argument('--out', required=True)
    a = p.parse_args()
    out, exs = [], a.exercises.split(',')
    for (name, (spec, s0, s1)), m, (kind, amp) in itertools.product(SRC.items(), a.models.split(','), CASES):
        head, X = load(os.path.join(a.kp_keep, spec.format(m=m)), s0, s1)
        Y = perturb(X, kind, amp, np.random.default_rng(0))
        tag = f'{name}_{kind}{amp}_{m}'; path = f'{a.out}/csv/{tag}.csv'; os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as f:
            f.write(','.join(head) + '\n')
            for r in Y:
                f.write(','.join(['%d' % r[0], '%.4f' % r[1], 'x', '0'] + ['%.3f' % v for v in r[4:]]) + '\n')
        row = dict(src=name, kind=kind, amp=amp, model=m)
        for ex in exs:
            d = f'{a.out}/out/{ex}'; os.makedirs(d, exist_ok=True)
            subprocess.run(['lockf', '-k', '/tmp/bpt-heavy.lock', a.replay, '--exercise', ex, '--model', 'mcoco17', '--motion3d', 'none',
                            '--keypoints-csv', path, '--output-dir', d, f'/x/{tag}.mp4'], stdout=subprocess.DEVNULL, check=True)
            exn = {'squat': 'squat', 'row': 'barbell_row'}[ex]
            row[ex] = json.load(open(f'{d}/{tag}_{exn}_mcoco17.json'))['session']['rep_count']
        out.append(row); print(row, flush=True)
    json.dump(out, open(f'{a.out}/result.json', 'w'), indent=1)
    print('SUM', {m: {ex: sum(r[ex] for r in out if r['model'] == m) for ex in exs} for m in a.models.split(',')}, len(out))


if __name__ == '__main__':
    main()
