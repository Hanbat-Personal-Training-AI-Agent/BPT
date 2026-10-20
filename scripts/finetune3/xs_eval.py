"""finetune3 XS evaluation on xs_data.py sequences for several lifters (same app path: L=5 selected row, window
[t+L-26, t+L] edge-clamped, person_crop input already in the sequences).

  R / V  Fit3D mocap = verified 3D. MPJPE, PA-MPJPE, accel error (mm; crop units -> metres with the mocap root depth),
         angles knee / hip / elbow / torso_g (true up): rep-extreme error per rep (rep_ann), frame error, jitter.
         Near side from geometry. V = synthetic 2D (virtual camera + real RTMPose residual track) — not the app's real
         2D; 'clean' rows have no 2D noise (lifter-only error).
  E      Exercise3D canonical_3d = Sapiens2 triangulation, NOT ground truth, not metric: limb-relative error and
         PA-MPJPE on the 14 labelled joints in % of the label torso; same angles (hip / torso_g carry the Sapiens hip
         definition). Relative comparison only — and not independent for a lifter trained on Exercise3D labels.

usage: xs_eval.py --data A.npz [B.npz ...] --models tag=ckpt,... --out OUT.json [--cpu]
       xs_eval.py --table OUT.json [--by kind,noise,bucket,group]   (markdown to stdout)
"""
import argparse, json, sys
from pathlib import Path
import numpy as np
import torch

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent), str(HERE)]
from eval_3d_mediapipe import angle_metrics, angles, pose_metrics, procrustes  # noqa: E402
from finetune_motionagformer_fit3d import app_predict, load  # noqa: E402
from xs_train import LIMBS, load_seqs  # noqa: E402

PA14 = [0, 1, 2, 3, 4, 5, 6, 8, 11, 12, 13, 14, 15, 16]
ANG = ('knee', 'hip', 'elbow', 'torso_g')


def bucket(v):
    return 'side<=40' if v <= 40 else 'oblique40-75' if v < 75 else 'front>=75'


def score(s, P):
    P = P - P[:, :1]
    side, up = s['side'], np.array(s['up_c'])
    seg = [tuple(x) for x in s['seg']]
    r = dict(name=s['name'], kind=s['kind'], subject=s.get('subject'), exercise=s.get('exercise'), group=s['group'],
             view=s['view'], bucket=bucket(s['view']), noise=s.get('noise', 'real'), split=s.get('split'), src=s.get('src', 'app'))
    if s['kind'] in ('R', 'V'):
        k = s['mm'][:, None, None] / 1000.0
        pm = pose_metrics(P * k, s['y'] * k)
        r.update(mpjpe=float(np.mean(pm['mpjpe'])), pa=float(np.mean(pm['pa_mpjpe'])), accel=float(np.mean(pm['accel'])))
        A, ref = angles(P * k, side, up), angles(s['y'] * k, side, up)
    else:
        G, ok = s['y'], s['fmask']
        torso = float(np.median(np.linalg.norm(G[ok, 8] - G[ok, 0], axis=-1)))
        c = lambda X: X[:, LIMBS] - X[:, LIMBS].mean(1, keepdims=True)
        r.update(limb=float(np.linalg.norm(c(P) - c(G), axis=-1).mean(-1)[ok].mean() / torso * 100),
                 pa=float(np.linalg.norm(procrustes(P[:, PA14], G[:, PA14]) - G[:, PA14], axis=-1).mean(-1)[ok].mean() / torso * 100))
        A, ref = angles(P, side, up), angles(G, side, up)
    am = angle_metrics(A, ref, seg) if seg else {}
    for a in ANG:
        if a in am:
            r[f'{a}_rep'] = am[a]['rep']; r[f'{a}_frame'] = float(np.median(am[a]['frame'])) if am[a]['frame'] else None
    return r


def table(path, by):
    d = json.load(open(path))
    keyf = lambda r: tuple('noisy' if k == 'noise' and r['kind'] == 'V' and r['noise'] != 'clean' else
                           ('-' if k == 'noise' and r['kind'] != 'V' else str(r.get(k))) for k in by)
    keys = sorted({keyf(r) for rows in d['rows'].values() for r in rows})
    med = lambda v: f'{np.median(v):.1f} ({np.percentile(v, 90):.0f})' if v else '-'
    print('| ' + ' | '.join(by) + ' | model | n | MPJPE / PA (mm; E: limb% / PA%) | accel | ' + ' | '.join(f'{a} rep (p90)' for a in ANG) + ' |')
    print('|' + '---|' * (len(by) + 4 + len(ANG)))
    for k in keys:
        for tag, rows in d['rows'].items():
            rs = [r for r in rows if keyf(r) == k]
            if not rs:
                continue
            e = rs[0]['kind'] == 'E'
            pos = (f"{np.mean([r['limb'] for r in rs]):.1f} / {np.mean([r['pa'] for r in rs]):.1f}" if e else
                   f"{np.mean([r['mpjpe'] for r in rs]):.1f} / {np.mean([r['pa'] for r in rs]):.1f}")
            acc = '-' if e else f"{np.mean([r['accel'] for r in rs]):.2f}"
            angs = [med([x for r in rs for x in r.get(f'{a}_rep', [])]) for a in ANG]
            print('| ' + ' | '.join(k) + f' | {tag} | {len(rs)} | {pos} | {acc} | ' + ' | '.join(angs) + ' |')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--table'); p.add_argument('--by', default='kind,noise,bucket,group')
    p.add_argument('--data', nargs='+'); p.add_argument('--models')
    p.add_argument('--mag-repo', default=str(Path('~/models/MotionAGFormer').expanduser()))
    p.add_argument('--out'); p.add_argument('--cpu', action='store_true')
    a = p.parse_args()
    if a.table:
        return table(a.table, a.by.split(','))
    dev = 'cpu' if a.cpu or not torch.cuda.is_available() else 'cuda'
    seqs = []
    for path in a.data:  # 2D source of E sequences = the CSV layout of the file (E built from Halpe26 CSVs: *_h26.npz)
        for q in load_seqs([path]):
            if q['kind'] == 'E' and 'src' not in q:
                q['src'] = 'app_halpe26' if path.endswith('_h26.npz') else 'app_coco17'
            seqs.append(q)
    out = {}
    for tag, ck in (kv.split('=', 1) for kv in a.models.split(',')):
        model = load(a.mag_repo, ck, dev)[0].eval()
        out[tag] = [score(s, app_predict(model, s['x'], dev).astype(float)) for s in seqs]
        print(tag, len(out[tag]), 'seqs', flush=True)
    json.dump(dict(models=dict(kv.split('=', 1) for kv in a.models.split(',')), data=a.data, rows=out), open(a.out, 'w'))


if __name__ == '__main__':
    main()
