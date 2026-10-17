"""Approach B of fit3d-label-verify: consensus of independent COCO-trained top-down models on Fit3D frames.

Numbers only, Home only. Frames, per-frame coordinates and predictions stay in the run dir (never git, never uploaded).
Consensus is NOT ground truth: it measures the COCO-definition convention as learned from human COCO labels, and it can
fail on occluded / prone poses.

  frames  pick frames (40 manual-candidate frames + stratified 3 per subject x exercise x camera), write frames/*.jpg,
          labels.npz (gvhmr / native / h36m / mocap 2D, mesh box, z-buffer occlusion of gvhmr points, view flags)
  infer   --model NAME: one COCO model on all frames -> preds_NAME.npz (keypoints [N,17,2] px, scores [N,17])
  report  consensus, leave-one-out inter-model floor, per-source error / PCK / body-axis bias, verdicts, offset test
Run (Home): PYTHONPATH=~/flv/pylib:~/flv/repo python fit3d_coco17_consensus.py <cmd> --run ~/bpt-runs/fit3d-label-verify/<id>
"""

import argparse
import glob
import json
import os

import cv2
import numpy as np
import torch

from check_fit3d_coco17_labels import CAMS, EXERCISES, FIT3D_COCO, body_frame_offset, read_frames
from pose_feedback.body.pose2d_data import COCO_NAMES, apply_affine, box_to_center_scale, invert_affine
from verify_fit3d_coco17 import SOURCES, Body, jload, mesh_box, occluded, proj, zbuffer

CFG = os.path.join(os.path.dirname(__import__('mmpose').__file__), '.mim/configs/body_2d_keypoint')
CK = os.path.expanduser('~/models/coco_pose_consensus')
MODELS = {  # name -> (config, checkpoint); all trained on human COCO train2017 keypoints (rtmpose_l: AIC+COCO pretrain)
    'vitpose_h': ('topdown_heatmap/coco/td-hm_ViTPose-huge_8xb64-210e_coco-256x192.py', 'td-hm_ViTPose-huge_8xb64-210e_coco-256x192-e32adcd4_20230314.pth'),
    'hrnet_w48_dark': ('topdown_heatmap/coco/td-hm_hrnet-w48_dark-8xb32-210e_coco-384x288.py', 'td-hm_hrnet-w48_dark-8xb32-210e_coco-384x288-39c3c381_20220916.pth'),
    'res152_dark': ('topdown_heatmap/coco/td-hm_res152_dark-8xb32-210e_coco-384x288.py', 'td-hm_res152_dark-8xb32-210e_coco-384x288-329f8454_20221031.pth'),
    'rtmpose_l': ('rtmpose/coco/rtmpose-l_8xb256-420e_coco-256x192.py', 'rtmpose-l_simcc-coco_pt-aic-coco_420e-256x192-1352a4d2_20230127.pth'),
}
SUBJECTS = ('s03', 's04', 's05', 's07', 's08', 's09', 's10', 's11')
CONF = 0.3
LIMBS = (7, 8, 9, 10, 13, 14, 15, 16)


# ---------------------------------------------------------------------------------------------------------- frames
def frame_plan(a):
    cand = jload(a.candidates)
    plan = {}   # (subj, ex, cam) -> {frame: tag}
    for fid in sorted(cand):
        c = cand[fid]
        plan.setdefault((c['subject'], c['exercise'], c['camera']), {})[int(c['frame'])] = fid
    rng = np.random.default_rng(a.seed)
    for subj in SUBJECTS:
        for ex in EXERCISES:
            n = len(jload(f'{a.root}/{subj}/joints3d_25/{ex}.json')['joints3d_25'])
            for cam in CAMS:
                for t in sorted(rng.choice(n, a.per_video, replace=False).tolist()):
                    plan.setdefault((subj, ex, cam), {}).setdefault(int(t), 'strat')
    return plan


def frames(a):
    os.makedirs(f'{a.run}/frames', exist_ok=True)
    body = Body(a.smplx)
    plan = frame_plan(a)
    rec = {k: [] for k in ('key', 'tag', 'subject', 'exercise', 'camera', 'frame', 'box', 'occ', 'prone', 'side', 'torso_cos_up', 'hip_cos_view')}
    lab = []
    up_check = {}
    for (subj, ex, cam), want in sorted(plan.items()):
        ts = sorted(want)
        p = jload(f'{a.root}/{subj}/smplx/{ex}.json')
        J = np.array(jload(f'{a.root}/{subj}/joints3d_25/{ex}.json')['joints3d_25'])
        V, Jx = body(p, ts)
        S = body.sources(V, Jx, J[ts])
        camera = jload(f'{a.root}/{subj}/camera_parameters/{cam}/{ex}.json')
        imgs = read_frames(f'{a.root}/{subj}/videos/{cam}/{ex}.mp4', ts)
        R = np.asarray(camera['extrinsics']['R'])
        for n, t in enumerate(ts):
            if t not in imgs:
                print('missing frame', subj, ex, cam, t, flush=True)
                continue
            img = imgs[t]
            H, W = img.shape[:2]
            key = f'{subj}_{ex}_{cam}_{t:05d}'
            cv2.imwrite(f'{a.run}/frames/{key}.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 95])
            zb, sc = zbuffer(V[n], camera, H, W)
            M = J[t]
            hip_c, sh_c = (M[FIT3D_COCO[11]] + M[FIT3D_COCO[12]]) / 2, (M[FIT3D_COCO[5]] + M[FIT3D_COCO[6]]) / 2
            torso = (sh_c - hip_c) / np.linalg.norm(sh_c - hip_c)
            hip_lr = M[FIT3D_COCO[11]] - M[FIT3D_COCO[12]]
            hip_lr /= np.linalg.norm(hip_lr)
            up_check.setdefault(ex, []).append(torso.tolist())
            cos_up = float(abs(torso[a.up_axis]))
            cos_view = float(abs(hip_lr @ R[2]))   # R[2] = camera optical axis in world
            rec['key'].append(key); rec['tag'].append(want[t]); rec['subject'].append(subj); rec['exercise'].append(ex)
            rec['camera'].append(cam); rec['frame'].append(t); rec['box'].append(mesh_box(proj(V[n], camera)))
            rec['occ'].append(occluded(S['gvhmr'][n], zb, sc, camera)); rec['prone'].append(cos_up < 0.5)  # < 30 deg from horizontal
            rec['side'].append(cos_view > 0.7); rec['torso_cos_up'].append(cos_up); rec['hip_cos_view'].append(cos_view)
            lab.append(np.stack([proj(S[s][n], camera) for s in SOURCES]))
        print(subj, ex, cam, len(ts), flush=True)
    np.savez(f'{a.run}/labels.npz', labels=np.array(lab), sources=np.array(SOURCES), **{k: np.array(v) for k, v in rec.items()})
    # up-axis check: mean |torso component| per world axis per exercise (standing exercises should peak on the up axis)
    json.dump({ex: np.abs(np.array(v)).mean(0).round(3).tolist() for ex, v in up_check.items()}, open(f'{a.run}/up_axis_check.json', 'w'), indent=1)


# ----------------------------------------------------------------------------------------------------------- infer
def half_backbone(model):
    """ponytail: fp16 backbone only (3 GB GPU), head stays fp32; checked against fp32 on CPU with --check."""
    bb = model.backbone.half()
    fwd = bb.forward
    bb.forward = lambda x: tuple(t.float() for t in fwd(x.half()))
    return model


def infer(a):
    L = np.load(f'{a.run}/labels.npz')
    keys, boxes = L['key'], L['box']
    out = f'{a.run}/preds_{a.model}.npz'
    if a.model == 'rtmpose_m_app':   # the app model, reference only (same pipeline as verify_fit3d_coco17 measure)
        from pose2d_ft_common import crop_box, load_model, predict
        model = load_model('m_coco17')
        kp, sc = [], []
        for k, b in zip(keys, boxes):
            img = cv2.cvtColor(cv2.imread(f'{a.run}/frames/{k}.jpg'), cv2.COLOR_BGR2RGB)
            cr, mm = crop_box(img, *box_to_center_scale(b))
            q, c = predict(model, [cr])
            kp.append(apply_affine(invert_affine(mm), q[0][:17])); sc.append(c[0][:17])
        np.savez(out, keypoints=np.array(kp), scores=np.array(sc))
        return
    from mmpose.apis import inference_topdown, init_model
    cfg, ck = MODELS[a.model]
    half = a.model == 'vitpose_h'
    model = init_model(f'{CFG}/{cfg}', f'{CK}/{ck}', device='cpu')
    ref = None
    if a.check:   # fp32 CPU reference on the first frames
        ref = [inference_topdown(model, f'{a.run}/frames/{k}.jpg', b[None], 'xyxy')[0].pred_instances.keypoints[0] for k, b in zip(keys[:a.check], boxes[:a.check])]
    if half:
        half_backbone(model)
    model = model.cuda()
    kp, sc = [], []
    for k, b in zip(keys, boxes):
        r = inference_topdown(model, f'{a.run}/frames/{k}.jpg', b[None], 'xyxy')[0].pred_instances
        kp.append(r.keypoints[0]); sc.append(r.keypoint_scores[0])
    kp = np.array(kp)
    extra = {}
    if ref is not None:
        d = np.linalg.norm(kp[:a.check] - np.array(ref), axis=-1) / np.maximum(boxes[:a.check, 2] - boxes[:a.check, 0], boxes[:a.check, 3] - boxes[:a.check, 1])[:, None]
        extra['check_vs_fp32_cpu_max_box'] = d.max()
        print('max |gpu - fp32 cpu| / box', d.max(), flush=True)
    np.savez(out, keypoints=kp, scores=np.array(sc), **extra)


# ---------------------------------------------------------------------------------------------------------- report
def cons(P, C, ok_min):
    """P [M,N,17,2], C [M,N,17] -> coordinate median over models with conf > CONF (nan if < ok_min valid)."""
    Q = np.where((C > CONF)[..., None], P, np.nan)
    n = np.isfinite(Q[..., 0]).sum(0)
    with np.errstate(all='ignore'), __import__('warnings').catch_warnings():
        __import__('warnings').simplefilter('ignore')
        m = np.nanmedian(Q, 0)
    m[n < ok_min] = np.nan
    return m


def stats(X, ref, blong, mask):
    """X, ref [N,17,2] px; mask [N] -> per joint dict of err / pck / bias (ref - X in ref body frame, torso units)."""
    e = np.linalg.norm(X - ref, axis=-1) / blong[:, None]
    u, s = body_frame_offset(ref - X, ref)
    out = []
    for k in range(17):
        v = mask & np.isfinite(e[:, k])
        if v.sum() < 5:
            out.append(None)
            continue
        uk, sk = u[v, k], s[v, k]
        out.append({'n': int(v.sum()), 'err_med': float(np.median(e[v, k])), 'err_p90': float(np.percentile(e[v, k], 90)),
                    'pck05': float((e[v, k] < 0.05).mean()), 'pck10': float((e[v, k] < 0.10).mean()),
                    'up': float(np.nanmean(uk)), 'side': float(np.nanmean(sk))})
    return out


def report(a):
    L = np.load(f'{a.run}/labels.npz')
    lab, box = L['labels'], L['box']
    blong = np.maximum(box[:, 2] - box[:, 0], box[:, 3] - box[:, 1])
    names = list(MODELS)
    P = np.stack([np.load(f'{a.run}/preds_{m}.npz')['keypoints'] for m in names])
    C = np.stack([np.load(f'{a.run}/preds_{m}.npz')['scores'] for m in names])
    app = np.load(f'{a.run}/preds_rtmpose_m_app.npz')['keypoints']
    full = cons(P, C, 3)
    loo = [cons(np.delete(P, m, 0), np.delete(C, m, 0), 2) for m in range(len(names))]
    srcs = {s: lab[:, i] for i, s in enumerate(L['sources'])}
    srcs['rtmpose_m_app'] = app
    prone, side = L['prone'].astype(bool), L['side'].astype(bool)
    splits = {'all': np.ones(len(lab), bool), 'prone': prone, 'side_view': side, 'other': ~prone & ~side,
              'candidates40': L['tag'] != 'strat'}
    res = {'n_frames': int(len(lab)), 'box_long_px_median': float(np.median(blong)), 'models': names, 'split_n': {k: int(v.sum()) for k, v in splits.items()}, 'splits': {}}
    for sp, mask in splits.items():
        r = {'floor': {}, 'vs_full': {}, 'vs_loo': {}, 'agree05': [], 'verdict': {}}
        for m, nm in enumerate(names):   # model m held out vs consensus of the others, only where m itself is confident
            Xm = np.where((C[m] > CONF)[..., None], P[m], np.nan)
            r['floor'][nm] = stats(Xm, loo[m], blong, mask)
        e_all = np.linalg.norm(P - full[None], axis=-1) / blong[None, :, None]
        okc = (C > CONF) & np.isfinite(e_all)
        for k in range(17):
            v = mask & np.isfinite(full[:, k, 0])
            r['agree05'].append(float(np.mean([np.all(e_all[okc[:, n, k], n, k] < 0.05) for n in np.where(v)[0]])) if v.any() else None)
        for s, X in srcs.items():
            r['vs_full'][s] = stats(X, full, blong, mask)
            per = [stats(X, loo[m], blong, mask & (C[m] > CONF).any(1)) for m in range(len(names))]
            agg = []
            for k in range(17):   # same held-out protocol as the floor, averaged over the 4 leave-one-out consensuses
                ps = [p[k] for p in per if p[k] is not None]
                agg.append({q: float(np.mean([p[q] for p in ps])) for q in ('err_med', 'up', 'side', 'pck05')} if ps else None)
            r['vs_loo'][s] = agg
            vd = []
            for k in range(17):
                fl = [r['floor'][nm][k] for nm in names if r['floor'][nm][k] is not None]
                x = agg[k]
                if x is None or len(fl) < 2:
                    vd.append(None)
                    continue
                ok = x['err_med'] <= max(f['err_med'] for f in fl) and abs(x['up']) <= max(abs(f['up']) for f in fl) and \
                    abs(x['side']) <= max(abs(f['side']) for f in fl)
                vd.append('consistent' if ok else 'outside')
            r['verdict'][s] = vd
            # looser second test: the source's own limb joints (elbow/wrist/knee/ankle, two-source verified in D-C-09) set the
            # label-noise level; a joint passes if its err and |bias| are no worse than the worst limb joint of the same source
            lim = [agg[k] for k in LIMBS if agg[k] is not None]
            r.setdefault('limb_control', {})[s] = [None if agg[k] is None or not lim else
                                                  ('consistent' if agg[k]['err_med'] <= max(x['err_med'] for x in lim) and
                                                   abs(agg[k]['up']) <= max(abs(x['up']) for x in lim) and
                                                   abs(agg[k]['side']) <= max(abs(x['side']) for x in lim) else 'outside') for k in range(17)]
        res['splits'][sp] = r
    # offset test (measurement only): mean (up, side) gvhmr->consensus offset in the LABEL's own body frame, estimated on
    # s03,s04,s05,s07 and applied to s08-s11
    tr = np.isin(L['subject'], ['s03', 's04', 's05', 's07'])
    res['offset_test'] = {}
    for s in ('gvhmr', 'native'):
        X = srcs[s]
        hip_c, sh_c = X[:, 11:13].mean(1), X[:, 5:7].mean(1)
        upv = sh_c - hip_c
        tl = np.linalg.norm(upv, axis=1, keepdims=True)
        upv = upv / tl
        sdv = X[:, 12] - X[:, 11]
        sdv = sdv - (sdv * upv).sum(1, keepdims=True) * upv
        sdv /= np.linalg.norm(sdv, axis=1, keepdims=True)
        u, sd = body_frame_offset(full - X, X)
        o = {}
        for k in (0, 1, 2, 3, 4, 5, 6, 11, 12):
            v = np.isfinite(u[:, k])
            mu, ms = float(np.nanmean(u[tr & v, k])), float(np.nanmean(sd[tr & v, k]))
            Xc = X[:, k] + (mu * upv + ms * sdv) * tl
            te = ~tr & v
            e0 = np.linalg.norm(X[te, k] - full[te, k], axis=-1) / blong[te]
            e1 = np.linalg.norm(Xc[te] - full[te, k], axis=-1) / blong[te]
            o[COCO_NAMES[k]] = {'offset_up': mu, 'offset_side': ms, 'test_n': int(te.sum()),
                                'test_err_med_before': float(np.median(e0)), 'test_err_med_after': float(np.median(e1)),
                                'test_pck05_before': float((e0 < 0.05).mean()), 'test_pck05_after': float((e1 < 0.05).mean()),
                                'offset_up_by_split_train': {sp: float(np.nanmean(u[tr & v & m, k])) for sp, m in splits.items() if (tr & v & m).sum() > 5}}
        res['offset_test'][s] = o
    json.dump(res, open(f'{a.run}/report.json', 'w'), indent=1)
    print(markdown(res))


def markdown(res):
    f = lambda x, d=3: '–' if x is None else f'{x:.{d}f}'
    out = []
    out.append('✓ = within inter-model spread (strict); L = no worse than the same source\'s worst limb joint (limb control); '
               'up/side = (consensus - source) in consensus body axes, torso units; + up = source sits below consensus')
    for sp in ('all', 'prone', 'side_view', 'other', 'candidates40'):
        r = res['splits'][sp]
        out.append(f'\n### {sp} (n={res["split_n"][sp]})\n')
        out.append('| joint | floor err med (min–max over models) | floor |up| max | floor |side| max | agree@0.05 | ' +
                   ' | '.join(f'{s} err/pck05/up/side' for s in r['vs_loo']) + ' |')
        out.append('|' + '---|' * (5 + len(r['vs_loo'])))
        for k in range(17):
            fl = [r['floor'][m][k] for m in r['floor'] if r['floor'][m][k] is not None]
            if not fl:
                continue
            cells = []
            for s, agg in r['vs_loo'].items():
                x = agg[k]
                cells.append('–' if x is None else f'{f(x["err_med"])}/{f(x["pck05"], 2)}/{x["up"]:+.3f}/{x["side"]:+.3f} {"✓" if r["verdict"][s][k] == "consistent" else "✗"}{"L" if r["limb_control"][s][k] == "consistent" else ""}')
            out.append(f'| {COCO_NAMES[k]} | {f(min(x["err_med"] for x in fl))}–{f(max(x["err_med"] for x in fl))} | '
                       f'{f(max(abs(x["up"]) for x in fl))} | {f(max(abs(x["side"]) for x in fl))} | {f(r["agree05"][k], 2)} | ' + ' | '.join(cells) + ' |')
    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=('frames', 'infer', 'report'))
    ap.add_argument('--run', required=True)
    ap.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d/train'))
    ap.add_argument('--smplx', default=os.path.expanduser('~/models/smplx'))
    ap.add_argument('--candidates', default=os.path.expanduser('~/flv/out/annot/candidates.json'))
    ap.add_argument('--seed', type=int, default=20261018)
    ap.add_argument('--per-video', type=int, default=3)
    ap.add_argument('--up-axis', type=int, default=2, help='world up axis of Fit3D (checked in up_axis_check.json)')
    ap.add_argument('--model', choices=tuple(MODELS) + ('rtmpose_m_app',))
    ap.add_argument('--check', type=int, default=0, help='infer: compare first N frames with a fp32 CPU run')
    a = ap.parse_args()
    globals()[a.cmd](a)


if __name__ == '__main__':
    main()
