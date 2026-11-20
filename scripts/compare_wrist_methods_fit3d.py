"""Runs from a tree with ai/motion-contact-20261020 (3d00335) scripts/ + pose_feedback/ plus this branch's
pose_feedback/geometry/wrist_anchor.py (Home `_code/wristcmp_mc3d00335`).

Push-up wrist: 2D floor anchor (ai/setup-constraint WristFloorAnchor v2) vs post-XS motion/contact estimator G/H v4
(ai/motion-contact-20261020 3d00335), SAME inputs and scorer: Fit3D held-out s07-s11 push-ups, Halpe26 experiment-A 2D
+ raw XS L5 cache (the motion-contact protocol inputs). GT only for scoring. Aggregates only leave Home.

Per stream (frames >= 90, the motion-contact score start; 'set' = GT rep segments):
  overlay 2D wrist (what the screen draws): A/G/H = observed 2D, W = anchored 2D -> error vs projected mocap, flying > 1 forearm
  3D wrist / elbow error mm (oracle metric scale, root-relative), and the 3D wrist re-projected to the image (flying)
  judge_py push-up rule firing per rep (lift-app rep_records, same 3D the scorer sees, estimator-invalid joints NaN)
"""
import json, sys, time
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parent
sys.path[:0] = [str(ROOT), str(ROOT / 'scripts')]
from motion_contact.data import load_observations, load_score_reference, HELDOUT
from motion_contact.corruptions import observation_with_keypoints, infer_changed_xs
from motion_contact.runner import run_variant
from pose_feedback.geometry.wrist_anchor import WristFloorAnchor
from pose_feedback.body.pose2d_data import project_fit3d
from pose_feedback.body.motionagformer_adapter import square_crop_denormalize
from pose_feedback.body.form_metrics_3d import UP
import eval_lift_app_fit3d as lf
from eval_3d_angles import near_side
from finetune_motionagformer_fit3d import load

CACHE, POSE2D, FIT3D, OUT = map(Path, sys.argv[1:5])
PARAMS = json.load(open(sys.argv[5]))
import torch; torch.set_num_threads(2)
model = load(str(Path.home() / 'models/MotionAGFormer'), str(Path.home() / 'models/MotionAGFormer/checkpoint/motionagformer-xs-h36m.pth.tr'), 'cpu')[0].eval()
H36 = {9: (13, 12), 10: (16, 15)}; ELB = {9: 7, 10: 8}
F2H = [0, 4, 5, 6, 1, 2, 3, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
OUT.mkdir(parents=True, exist_ok=True); recs = []
for cache in sorted(CACHE.glob('*_pushup.npz')):
    subj = cache.stem.split('_')[0]
    if subj not in HELDOUT: continue
    t0 = time.time()
    o = load_observations(cache, POSE2D / cache.name); ref = load_score_reference(FIT3D, o); n = len(o.raw)
    cam = json.load(open(FIT3D / 'train' / subj / 'camera_parameters' / o.camera / 'pushup.json'))
    Jw = np.asarray(json.load(open(FIT3D / 'train' / subj / 'joints3d_25' / 'pushup.json'))['joints3d_25'], float)[o.pick][:, F2H]
    G2 = project_fit3d(Jw.reshape(-1, 3), cam).reshape(n, 17, 2)
    seg = ref.rep_segments; lo, hi = max(90, seg[0][0]), seg[-1][1]
    fore = {w: float(np.median(np.linalg.norm(G2[lo:hi, hw] - G2[lo:hi, he], axis=-1))) for w, (hw, he) in H36.items()}
    # W: anchor the observed 2D (wrists only change), active once rep 1 is counted (end of the first GT rep)
    a = WristFloorAnchor(**PARAMS); K = o.keypoints.copy(); held = np.zeros((n, 2), bool)
    for t in range(n):
        k2, st = a.update(o.keypoints[t, :17], active=t >= seg[0][1]); K[t, :17] = k2
        held[t] = [st[9] == 'held', st[10] == 'held']
    ow = observation_with_keypoints(o, K)
    raw_w, info = infer_changed_xs(model, ow.normalized, o.normalized, o.raw, limit=n)
    ref_w = load_score_reference(FIT3D, ow)
    methods = {'A': (o, ref, o.raw, None, o.keypoints), 'W': (ow, ref_w, raw_w, None, K)}
    for v in ('G', 'H'):
        r = run_variant(o, v); methods[v] = (o, ref, r['corrected'], r['invalid'], o.keypoints)
    rec = dict(name=o.name, recomputed_windows=info['recomputed_windows'], held=float(held[lo:hi].mean()))
    side = near_side(o.keypoints[:, :17])
    for m, (ob, rf, P, inv, K2) in methods.items():
        Pm = (P - P[:, :1]) * rf.metres_per_crop_unit[:, None, None]
        err = np.linalg.norm(Pm - rf.joints_m, axis=-1)[lo:hi] * 1000
        rp = np.stack([square_crop_denormalize(P[t, :, :2] - P[t, :1, :2] + ob.normalized[t, :1, :2], ob.crops[t]) for t in range(n)])
        r_ = dict(wrist3d=float(err[:, [13, 16]].mean()), elbow3d=float(err[:, [12, 15]].mean()), all3d=float(err.mean()))
        for w, (hw, he) in H36.items():
            e2 = np.linalg.norm(K2[lo:hi, w, :2] - G2[lo:hi, hw], axis=-1)
            e3 = np.linalg.norm(rp[lo:hi, hw] - G2[lo:hi, hw], axis=-1)
            r_[f'overlay_px_{w}'] = float(e2.mean()); r_[f'overlay_fly_{w}'] = float((e2 > fore[w]).mean())
            r_[f'reproj_px_{w}'] = float(e3.mean()); r_[f'reproj_fly_{w}'] = float((e3 > fore[w]).mean())
            r_[f'elbow_px_{w}'] = float(np.linalg.norm(K2[lo:hi, ELB[w], :2] - G2[lo:hi, he], axis=-1).mean())
        Pr = P - P[:, :1]
        if inv is not None: Pr = Pr.copy(); Pr[inv] = np.nan
        sh, hp = {'L': (5, 11), 'R': (6, 12)}[side]
        two = [dict(hipY=float(K2[t, hp, 1]), shoulderY=float(K2[t, sh, 1]), torsoLength=float(np.hypot(*(K2[t, sh, :2] - K2[t, hp, :2])))) for t in range(n)]
        reps = lf.rep_records(Pr, list(seg), 'pushup', {'L': 'left', 'R': 'right'}[side], UP, {}, two)
        r_['fired'] = [sorted(x['fired']) for x in reps]
        rec[m] = r_
    recs.append(rec); print(o.name, f'{time.time() - t0:.0f}s', {m: (round(rec[m]['wrist3d'], 1), round((rec[m]['overlay_fly_9'] + rec[m]['overlay_fly_10']) / 2, 4)) for m in methods}, flush=True)
json.dump(dict(params=PARAMS, recs=recs), open(OUT / 'compare.json', 'w'), indent=1)
M = ('A', 'W', 'G', 'H'); md = ['| 방법 | 화면 손목 날아감 | 화면 손목 오차 px | 3D 재투영 날아감 | 손목 3D mm | 팔꿈치 3D mm | 전체 3D mm | 규칙 발동 다른 렙 (A 대비) |', '|---|---|---|---|---|---|---|---|']
nrep = sum(len(r['A']['fired']) for r in recs)
for m in M:
    g = lambda k: np.mean([(r[m][f'{k}_9'] + r[m][f'{k}_10']) / 2 for r in recs])
    diff = sum(a != b for r in recs for a, b in zip(r['A']['fired'], r[m]['fired']))
    md.append(f"| {m} | {g('overlay_fly'):.2%} | {g('overlay_px'):.2f} | {g('reproj_fly'):.2%} | {np.mean([r[m]['wrist3d'] for r in recs]):.1f} | {np.mean([r[m]['elbow3d'] for r in recs]):.1f} | {np.mean([r[m]['all3d'] for r in recs]):.1f} | {diff}/{nrep} |")
md.append(f"\n영상 {len(recs)}개, W held {np.mean([r['held'] for r in recs]):.2%}, W XS 재계산 창 {sum(r['recomputed_windows'] for r in recs)}")
(OUT / 'compare.md').write_text('\n'.join(md) + '\n'); print('\n'.join(md))
