"""Re-audit D-D-07 (original XS rows only): same code path as eval_3d_mediapipe.py run_fit3d (prep, mag_predict,
pose_metrics, angle_metrics, near side from the 2D confidence) on the app-path RTMPose-m COCO17 pose-replay CSVs that
are on Home (~/bpt-smpl/replay, made by an earlier track; provenance recorded in the manifest). Fine-tuned XS: weights
gone -> not run.

usage: dd07_repro.py --root ~/datasets/fit3d --replay ~/bpt-smpl/replay --out OUT.json
"""
import argparse, json, os, sys
from pathlib import Path
import numpy as np

sys.path[:0] = [str(Path(__file__).resolve().parents[2]), str(Path(__file__).resolve().parents[1])]
from eval_3d_angles import fit3d_jobs, near_side, view_and_side  # noqa: E402
from eval_3d_mediapipe import EXERCISES, TUNING, angle_metrics, angles, angles_from_2d, load_mag, mag_predict, pose_metrics  # noqa: E402
from finetune_motionagformer_fit3d import prep  # noqa: E402


def main():
    p = argparse.ArgumentParser(); p.add_argument('--root'); p.add_argument('--replay'); p.add_argument('--out')
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    a = p.parse_args()
    model, dev = load_mag(f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr', a.mag_repo)
    out = []
    for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(a.root, a.replay, None, list(EXERCISES)):
        d = prep(a.root, subj, ex, cam, J, R, T, csv); pick = d['pick']
        up_w = -R[1] / np.linalg.norm(R[1]); up_w = np.array([0, 0, 1.]) if abs(up_w[2]) > 0.8 else up_w
        up_c = R @ up_w; G = d['y'] * d['mm'][:, None, None] / 1000
        view, _ = view_and_side(J, R, T, up_w); side = near_side(d['K'])
        seg = [(int(np.searchsorted(pick, s)), int(np.searchsorted(pick, e))) for s, e in zip(ann, ann[1:])]
        ref = angles(G, side, up_c); ref['torso'] = ref['torso_g']
        P = mag_predict(model, dev, d['x']) * d['mm'][:, None, None] / 1000
        res = dict(subject=subj, exercise=ex, cam=cam, view_deg=round(view, 1), group='tuning' if subj in TUNING else 'heldout',
                   csv=os.path.basename(csv), mag_orig={**angle_metrics(angles(P, side, up_c), ref, seg), **pose_metrics(P, G)},
                   **{'2d': angle_metrics(angles_from_2d(d['K'], side), ref, seg)})
        out.append(res); print(subj, ex, cam, round(np.mean(res['mag_orig']['mpjpe'])), round(np.mean(res['mag_orig']['pa_mpjpe'])), flush=True)
    json.dump(out, open(a.out, 'w'))
    for grp in ('heldout', 'tuning'):
        rs = [r for r in out if r['group'] == grp]
        cat = lambda k: np.concatenate([r['mag_orig'][k] for r in rs])
        print(grp, len(rs), 'MPJPE', round(cat('mpjpe').mean(), 1), 'PA', round(cat('pa_mpjpe').mean(), 1), 'accel', round(cat('accel').mean(), 2))
        for ex in EXERCISES:
            for limb in ('knee', 'hip', 'elbow', 'torso', 'torso_g'):
                x = [v for r in rs if r['exercise'] == ex and 40 <= r['view_deg'] < 75 for v in r['mag_orig'][limb]['rep']]
                y = [v for r in rs if r['exercise'] == ex and 40 <= r['view_deg'] < 75 for v in r['2d'][limb]['rep']]
                if x: print(' ', grp, ex, limb, 'XS', round(float(np.median(x)), 1), '2D', round(float(np.median(y)), 1))


if __name__ == '__main__':
    main()
