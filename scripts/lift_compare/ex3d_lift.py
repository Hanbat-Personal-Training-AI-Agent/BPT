"""lift-compare on Exercise3D: [E3D, pseudo-GT, unverified, not independent] - relative comparison only.

2D CSVs already made by earlier tracks (no new 2D runs):
  expA  ~/bpt-runs/eval-reliability/ex3d_held_expA_rtmdet  (same RTMDet box, held-out P2/P3, Mac pose-replay --crops-in)
  cur / lb / s15 / det  ~/bpt-runs/reacquire/e3d__<cfg>    (app path, Mac pose-replay, D-T3-20 acquisition configs)
Each: <seq>_<cam>_<exercise>_{mcoco17,halpe26}.csv[.gz]. Lifter inputs coco / ha / hb as lift_eval.py, crop and screen
normalisation, original XS, raw output. Scored against Exercise3D canonical_3d (Sapiens triangulation): rep-extreme
angle errors (near side from gt.json), P-MPJPE on the 13 joints Exercise3D has (pelvis, hips, knees, ankles, shoulder
centre as thorax, shoulders, elbows, wrists) in % of the label torso length (canonical_3d is not metric) -> no MPJPE.

usage: ex3d_lift.py --labels ~/bpt-smpl/ex3d --runs expA=DIR,cur=DIR,... --out OUT.json
"""
import argparse, ast, glob, gzip, json, os, sys
from pathlib import Path
import numpy as np

sys.path[:0] = [str(Path(__file__).resolve().parents[2]), str(Path(__file__).resolve().parents[1]), str(Path(__file__).resolve().parent)]
from eval_3d_angles import EX3D_NAMES  # noqa: E402
from eval_3d_mediapipe import angles, procrustes  # noqa: E402
from finetune_motionagformer_fit3d import app_predict, load  # noqa: E402
from lift_eval import FiLMLifter, ang_metrics, h36m_inputs, normalise  # noqa: E402

EXNAME = {'squat': 'squat', 'pushup': 'pushup', 'barbellrow': 'barbell_row'}
HELD = {'squat_0002', 'barbellrow_0001', 'barbellrow_0003'}
PA_JOINTS = [0, 1, 2, 3, 4, 5, 6, 8, 11, 12, 13, 14, 15, 16]


def read(path):
    op = gzip.open if path.endswith('.gz') else open
    with op(path, 'rt') as f:
        head = f.readline().strip().split(','); i0 = head.index('j0_x')
        rows = np.array([[float(x) for x in l.strip().split(',')[i0:]] for l in f])
    return rows.reshape(len(rows), -1, 3)


def find(d, stem):
    for s in ('.csv', '.csv.gz'):
        if os.path.exists(d + '/' + stem + s): return d + '/' + stem + s


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--labels', required=True); p.add_argument('--runs', required=True); p.add_argument('--out', required=True)
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    p.add_argument('--ftd', default=None); p.add_argument('--shapes', default=None)
    p.add_argument('--only-ftd', action='store_true', help='run only the D-D-08 d lifter (crop)')
    a = p.parse_args()
    import torch
    dev = 'cuda' if torch.cuda.is_available() else 'cpu'
    model = load(a.mag_repo, f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr', dev)[0].eval()
    lifters = {} if a.only_ftd else {'orig': (lambda X, seq: app_predict(model, X, dev), ('crop', 'screen'))}
    if a.ftd:
        ftd, shapes = FiLMLifter.make(a.mag_repo, a.ftd, dev), json.load(open(a.shapes))
        lifters['ftd'] = (lambda X, seq: FiLMLifter.predict(ftd, X, shapes[seq]['calibrated_cm'], dev), ('crop',))
    gt = json.load(open(f'{a.labels}/gt.json')); L = f'{a.labels}/exercise3d_labels'; out = []
    for cfg, d in (x.split('=') for x in a.runs.split(',')):
        for seq, g in gt.items():
            if g['exercise'] not in EXNAME: continue
            z = np.load(f'{L}/{seq}/geometry/canonical_3d.npz'); names = list(z['joint_names']); Pw = z['keypoints_3d'].astype(float)
            J = np.stack([Pw[:, names.index(nm)] if nm else np.full((len(Pw), 3), np.nan) for nm in EX3D_NAMES], 1)
            cg = json.load(open(f'{L}/{seq}/geometry/metadata.json'))['camera_geometry']
            cg = ast.literal_eval(cg) if isinstance(cg, str) else cg
            Rs = {c: np.array(v['extrinsic_world_to_camera'])[:, :3] for c, v in cg.items()}
            up_w = -np.mean([R[1] for R in Rs.values()], axis=0); up_w /= np.linalg.norm(up_w)
            rf = g['rep_frames']; half = int(np.median(np.diff(rf)) / 2) if len(rf) > 1 else 15
            for cam, v in g['views'].items():
                stem = f"{seq}_{cam}_{EXNAME[g['exercise']]}"
                fc, fh = find(d, stem + '_mcoco17'), find(d, stem + '_halpe26')
                if not fc or not fh: continue
                Kc, Kh = read(fc), read(fh)
                w, h = json.load(open(glob.glob(f'{d}/{stem}_mcoco17.json')[0]))['image_size']
                n = min(len(Kc), len(Kh), len(J)); R = Rs[cam]; up_c = R @ up_w
                G = J[:n] @ R.T; G = G - G[:, :1]
                torso = float(np.nanmedian(np.linalg.norm(G[:, 8] - G[:, 0], axis=-1)))  # canonical_3d is not metric
                seg = [(max(0, r - half), min(n - 1, r + half)) for r in rf if r < n]
                side = 'L' if v['near_side'] == 'left' else 'R'
                ref = angles(G, side, up_c); ref['torso'] = ref['torso_g']
                res = dict(cfg=cfg, seq=seq, exercise=EXNAME[g['exercise']], cam=cam, view_deg=v['angle_deg'], frames=n,
                           group='heldout' if seq in HELD else 'tuning', m3d={})
                inp = h36m_inputs({'coco': Kc[:n, :17], 'halpe': Kh[:n]}, None)
                for key, (xy, cf) in inp.items():
                    for norm in ('crop', 'screen'):
                      x, _ = normalise(xy, cf, norm, w, h)
                      X = np.concatenate([x, cf[..., None]], -1).astype(np.float32)
                      for lname, (fn, norms) in lifters.items():
                        if norm not in norms: continue
                        P = fn(X, seq).astype(float); P = P - P[:, :1]
                        pa = np.linalg.norm(procrustes(P[:, PA_JOINTS], G[:, PA_JOINTS]) - G[:, PA_JOINTS], axis=-1).mean(-1) / torso * 100
                        res['m3d'][f'{key}|{norm}|raw' if lname == 'orig' else f'{lname}|{key}|{norm}|raw'] = dict(pa=float(np.nanmean(pa)), ang=ang_metrics(angles(P, side, up_c), ref, seg))
                print(cfg, stem, round(v['angle_deg']), {k: round(r['pa']) for k, r in res['m3d'].items() if '|crop' in k}, flush=True)
                out.append(res)
    json.dump(out, open(a.out, 'w'))


if __name__ == '__main__':
    main()
