"""Rep counting from a 2D vs a 3D joint-angle signal, same simple counter for both (squat: near knee, push-up and
row: near elbow; 9-frame mean, normalised to the clip's p5..p95, Schmitt trigger 0.35/0.65, a rep = a dip).
This compares the signals, not the app's state machines (pose-replay counts are reported next to them).
Truth: Fit3D rep_ann boundaries, Exercise3D gt.json truth_reps.

usage: count_reps_3d_vs_2d.py fit3d --root DIR --replay DIR --out JSON
       count_reps_3d_vs_2d.py ex3d --ex3d-replay DIR --out JSON
"""
import argparse, json, os, sys
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval_3d_angles import (APP_FPS, REPO, angles_2d, angles_3d, fit3d_jobs, lift, load_lifter,  # noqa: E402
                            near_side, read_csv, view_and_side)

LIMB = {'squat': 'knee', 'pushup': 'elbow', 'diamond_pushup': 'elbow', 'barbell_row': 'elbow',
        'barbell_dead_row': 'elbow', 'barbellrow': 'elbow'}


def count(sig, lo=0.35, hi=0.65, k=9):
    """Dips of the normalised signal: below lo after having been above hi (same rule as the truth counters)."""
    sig = np.asarray(sig, float)
    good = np.isfinite(sig)
    if good.sum() < k: return 0
    sig = np.interp(np.arange(len(sig)), np.where(good)[0], sig[good])
    sig = np.convolve(np.pad(sig, k // 2, mode='edge'), np.ones(k) / k, mode='valid')
    p5, p95 = np.percentile(sig, [5, 95])
    if p95 - p5 < 1e-6: return 0
    n = (sig - p5) / (p95 - p5); reps, armed, low = 0, n[0] > hi, False
    for v in n:
        if v > hi:
            if low: reps += 1
            armed, low = True, False
        elif v < lo and armed: low = True
    return reps + (1 if low and n[-1] > 0.5 else 0)


def app_reps(csv):
    j = Path(str(csv)[:-4] + '.json')
    return json.load(open(j))['session']['rep_count'] if j.exists() else None


def one(K, w, h, runner, ex):
    side = near_side(K); P = lift(K, w, h, runner); limb = LIMB[ex]
    return count(angles_2d(K, side)[limb]), count(angles_3d(P, np.array([0, -1., 0]), side)[limb])


def main():
    p = argparse.ArgumentParser()
    p.add_argument('source', choices=['fit3d', 'ex3d'])
    p.add_argument('--root'); p.add_argument('--replay'); p.add_argument('--ex3d-replay')
    p.add_argument('--outputs', default=str(REPO / 'outputs'))
    p.add_argument('--mag-repo', default=str(REPO / 'external/MotionAGFormer'))
    p.add_argument('--out', required=True)
    a = p.parse_args()
    runner = load_lifter(f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr', a.mag_repo)
    out = []
    if a.source == 'fit3d':
        for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(a.root, a.replay, None,
                                                         ['squat', 'pushup', 'barbell_row']):
            K = read_csv(csv); n = min(len(K), len(J))
            pick = np.round(np.arange(0, n, 50 / APP_FPS)).astype(int); pick = pick[pick < n]
            up = -R[1] / np.linalg.norm(R[1]); up = np.array([0, 0, 1.]) if abs(up[2]) > 0.8 else up
            view = view_and_side(J, R, T, up)[0]
            r2, r3 = one(K[pick], 900, 900, runner, ex)
            out.append(dict(source='fit3d', subject=subj, exercise=ex, cam=cam, view_deg=round(view, 1),
                            truth=len(ann) - 1, reps_2d=r2, reps_3d=r3, app_reps=app_reps(csv)))
            print(out[-1], flush=True)
    else:
        O = Path(a.outputs); gt = json.load(open(O / 'rep_validation/gt.json'))
        exname = {'squat': 'squat', 'pushup': 'pushup', 'barbellrow': 'barbell_row'}
        for seq, g in gt.items():
            for cam, v in g['views'].items():
                csv = Path(a.ex3d_replay) / seq / f'{cam}_{exname[g["exercise"]]}_coco17.csv'
                if not csv.exists(): continue
                w, h = json.load(open(str(csv)[:-4] + '.json'))['image_size']
                r2, r3 = one(read_csv(csv), w, h, runner, g['exercise'])
                out.append(dict(source='ex3d', subject=seq, exercise=g['exercise'], cam=cam, view_deg=v['angle_deg'],
                                truth=g['truth_reps'], reps_2d=r2, reps_3d=r3, app_reps=app_reps(csv)))
                print(out[-1], flush=True)
    json.dump(out, open(a.out, 'w'), indent=1)


if __name__ == '__main__':
    main()
