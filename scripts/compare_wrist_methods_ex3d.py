"""Runs from a tree with ai/motion-contact-20261020 (3d00335) scripts/ + pose_feedback/ plus this branch's
pose_feedback/geometry/wrist_anchor.py (Home `_code/wristcmp_mc3d00335`).

Exercise3D push-ups, m Halpe26 app-path 2D (pose-replay CSVs, the planned app default): raw vs 2D floor anchor (W) vs
post-XS motion/contact G/H v4. No ground truth: a planted wrist stays put, so the set reference is the median observed
wrist (conf >= 0.5) over the set and 'flying' = > 1 forearm (median observed elbow-wrist) away. Overlay = what the screen
draws (A/G/H: observed 2D; W: anchored 2D); reproj = the 3D wrist re-projected to the image. Rules: lift-app judge_py
per GT rep window on the 3D each method outputs (estimator-invalid joints NaN)."""
import csv, json, sys
from dataclasses import replace
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parent
sys.path[:0] = [str(ROOT), str(ROOT / 'scripts')]
from motion_contact.data import Observations, normalize_observations
from motion_contact.runner import run_variant
from pose_feedback.geometry.wrist_anchor import WristFloorAnchor
from pose_feedback.body.motionagformer_adapter import square_crop_denormalize
from pose_feedback.body.form_metrics_3d import UP
import eval_lift_app_fit3d as lf
from eval_3d_angles import near_side
from finetune_motionagformer_fit3d import load
import torch; torch.set_num_threads(2)
CSVDIR, GT, OUT, PARAMS = Path(sys.argv[1]), json.load(open(sys.argv[2])), Path(sys.argv[3]), json.load(open(sys.argv[4]))
model = load(str(Path.home() / 'models/MotionAGFormer'), str(Path.home() / 'models/MotionAGFormer/checkpoint/motionagformer-xs-h36m.pth.tr'), 'cpu')[0].eval()

def xs(x):
    n = len(x); idx = np.clip(np.arange(n)[:, None] + 5 - 26 + np.arange(27)[None], 0, n - 1)
    with torch.inference_mode():
        return np.concatenate([model(torch.from_numpy(x[idx[s:s + 64]])).numpy()[:, 21] for s in range(0, n, 64)]).astype(float)

OUT.mkdir(parents=True, exist_ok=True); recs = []
for path in sorted(CSVDIR.glob('pushup_*_pushup_mhalpe26.csv')):
    seq = '_'.join(path.name.split('_')[:2]); g = GT[seq]
    rows = list(csv.DictReader(open(path)))
    K = np.array([[[float(r[f'j{j}_{q}']) for q in 'xyc'] for j in range(17)] for r in rows]); rep = np.array([int(r['rep']) for r in rows]); n = len(K)
    size = tuple(json.load(open(path.with_suffix('.json')))['image_size'])
    on = int(np.argmax(rep >= 1)) if (rep >= 1).any() else n
    rf = g['rep_frames']; half = int(np.median(np.diff(rf)) / 2); lo, hi = max(21, rf[0] - half), min(n, rf[-1] + half)
    seg = [(max(0, f - half), min(n - 1, f + half)) for f in rf if f + half < n]
    a = WristFloorAnchor(**PARAMS); Kw = K.copy(); held = np.zeros((n, 2), bool)
    for t in range(n):
        Kw[t], st = a.update(K[t], active=t >= on); held[t] = [st[9] == 'held', st[10] == 'held']
    x, crops = normalize_observations(K, size); xw, crops_w = normalize_observations(Kw, size)
    raw = xs(x); raw_w = xs(xw) if (xw != x).any() else raw
    pick = np.round(np.arange(n) * 50 / 30).astype(int)
    o = Observations(path.stem, seq, path.name.split('_')[2], 'pushup', raw, K, x, crops, pick, np.zeros((n, 4)), size, {})
    methods = {'A': (raw, x, crops, None, K), 'W': (raw_w, xw, crops_w, None, Kw)}
    for v in ('G', 'H'):
        r = run_variant(o, v); methods[v] = (r['corrected'], x, crops, r['invalid'], K)
    rec = dict(name=path.stem, held=float(held[lo:hi].mean()), active_from=on)
    side = {'L': 'left', 'R': 'right'}[near_side(K)]
    for m, (P, xx, cc, inv, K2) in methods.items():
        rp = np.stack([square_crop_denormalize(P[t, :, :2] - P[t, :1, :2] + xx[t, :1, :2], cc[t]) for t in range(n)])
        r_ = {}
        for w, (hw, e) in {9: (13, 7), 10: (16, 8)}.items():
            good = K[lo:hi, w, 2] >= .5; fe = good & (K[lo:hi, e, 2] >= .5)
            if good.sum() < 10 or fe.sum() < 10: continue
            ref = np.median(K[lo:hi][good, w, :2], 0); f = np.median(np.linalg.norm(K[lo:hi, w, :2] - K[lo:hi, e, :2], axis=-1)[fe])
            d2 = np.linalg.norm(K2[lo:hi, w, :2] - ref, axis=-1) / f; d3 = np.linalg.norm(rp[lo:hi, hw] - ref, axis=-1) / f
            r_[f'overlay_fly_{w}'] = float((d2 > 1).mean()); r_[f'overlay_max_{w}'] = float(d2.max())
            r_[f'reproj_fly_{w}'] = float((d3 > 1).mean()); r_[f'reproj_max_{w}'] = float(d3.max())
        Pr = P - P[:, :1]
        if inv is not None: Pr = Pr.copy(); Pr[inv] = np.nan
        sh, hp = {'left': (5, 11), 'right': (6, 12)}[side]
        two = [dict(hipY=float(K2[t, hp, 1]), shoulderY=float(K2[t, sh, 1]), torsoLength=float(np.hypot(*(K2[t, sh, :2] - K2[t, hp, :2])))) for t in range(n)]
        r_['fired'] = [sorted(z['fired']) for z in lf.rep_records(Pr, seg, 'pushup', side, UP, {}, two)]
        rec[m] = r_
    recs.append(rec); print(path.stem, 'held', round(rec['held'], 3), {m: {k: round(v, 3) for k, v in rec[m].items() if 'fly' in k} for m in methods}, flush=True)
json.dump(dict(params=PARAMS, recs=recs), open(OUT / 'compare_ex3d.json', 'w'), indent=1)
md = ['| 방법 | 화면 손목 > 1 아래팔 | 화면 최대(아래팔) | 3D 재투영 > 1 | 재투영 최대 | 규칙 발동이 A와 다른 렙 |', '|---|---|---|---|---|---|']
nrep = sum(len(r['A']['fired']) for r in recs)
for m in ('A', 'W', 'G', 'H'):
    vals = lambda k: [r[m][k_] for r in recs for k_ in r[m] if k_.startswith(k)]
    diff = sum(a != b for r in recs for a, b in zip(r['A']['fired'], r[m]['fired']))
    md.append(f"| {m} | {np.mean(vals('overlay_fly')):.2%} | {max(vals('overlay_max')):.2f} | {np.mean(vals('reproj_fly')):.2%} | {max(vals('reproj_max')):.2f} | {diff}/{nrep} |")
md.append(f"\n클립 {len(recs)}개(손목 {len(vals('overlay_fly'))}개), W held {np.mean([r['held'] for r in recs]):.2%}")
(OUT / 'compare_ex3d.md').write_text('\n'.join(md) + '\n'); print('\n'.join(md))
