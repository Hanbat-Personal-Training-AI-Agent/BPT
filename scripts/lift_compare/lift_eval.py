"""lift-compare stage 3 (Home, bpt-home, GPU): 2D -> MotionAGFormer-XS -> 3D on Fit3D, scored against the mocap.

Inputs per video: stage-1 npz (same RTMDet box, RTMPose-m COCO17 + Halpe26), stage-2 npz (MediaPipe wrists).
Lifter inputs (H36M17 2D + confidence):
  coco     COCO17 -> coco17_to_motionagformer_h36m17 (the app mapping)
  ha       Halpe26 joints 0-16 -> same mapping (variant a, primary pipeline B)
  hb       ha, then pelvis <- Halpe 19 Hip, thorax <- 18 Neck, head <- 17 Head, spine / 9 rebuilt (variant b)
  coco_mp, ha_mp   the above with MediaPipe Hand wrists (stage 2)
  gt2d     projected mocap H36M17, confidence 1 (oracle reference: lifter error alone)
Normalisation: crop = app person_crop (PersonSquareCropTracker), screen = MotionAGFormer H36M training (X/w*2-[1,h/w]).
Constraints: raw; con_app = ai/lift-app Pose3DConstraints (ed67a6e defaults); con_fit3d = same class with limits /
prior lengths from Fit3D tuning subjects s03-s05 (priors.json). Applied per frame in XS output units, in time order.
Units -> metres with the mocap root depth (weak perspective; same oracle for every variant).
Metric definitions: docs/results/lift_compare_plan.md section 4.

usage: lift_eval.py --root ~/datasets/fit3d --pose2d DIR --mpwrist DIR --priors priors.json --out OUT.json [--subjects ...]
"""
import argparse, glob, json, os, sys
from pathlib import Path
import numpy as np

sys.path[:0] = [str(Path(__file__).resolve().parents[2]), str(Path(__file__).resolve().parents[1])]
from eval_3d_angles import APP_FPS, view_and_side, load_joints  # noqa: E402
from eval_3d_mediapipe import EXTREME, angles, pose_metrics, procrustes  # noqa: E402
from finetune_motionagformer_fit3d import app_predict, load  # noqa: E402
from pose_feedback.body.motionagformer_adapter import (PersonSquareCropTracker, coco17_to_motionagformer_h36m17,  # noqa: E402
                                                       normalize_motionagformer_2d, square_crop_normalize)
from pose_feedback.body.pose2d_data import project_fit3d  # noqa: E402

TUNING = {'s03', 's04', 's05'}
COCO2H = {5: 11, 6: 14, 7: 12, 8: 15, 9: 13, 10: 16, 11: 4, 12: 1, 13: 5, 14: 2, 15: 6, 16: 3}  # COCO idx -> H36M idx
SEGS = {'thigh': [(1, 2), (4, 5)], 'shin': [(2, 3), (5, 6)], 'upper_arm': [(11, 12), (14, 15)], 'forearm': [(12, 13), (15, 16)],
        'shoulder_w': [(11, 14)], 'hip_w': [(1, 4)], 'torso': [(0, 8)]}
ANG = ('knee', 'hip', 'elbow', 'torso', 'torso_g')


class FiLMLifter:
    """D-D-08 variant d (ai/smpl-train scripts/train_lifter_body_shape.py `build`, copied): MotionAGFormer-XS with a
    zero-initialised FiLM on the joint embedding from log(L / mean L) of the subject's 18 calibrated bone lengths."""
    @staticmethod
    def make(mag_repo, ckpt, dev):
        import torch, torch.nn as nn

        class Lifter(nn.Module):
            def __init__(self, base):
                super().__init__(); self.base = base
                self.film = nn.Sequential(nn.Linear(18, 64), nn.GELU(), nn.Linear(64, 2 * base.pos_embed.shape[-1]))

            def forward(self, x, c):
                m = self.base; h = m.joints_embed(x) + m.pos_embed
                g, b = self.film(c).chunk(2, -1); h = h * (1 + g[:, None, None]) + b[:, None, None]
                for layer in m.layers: h = layer(h)
                return m.head(m.rep_logit(m.norm(h)))
        base, _ = load(mag_repo, f'{mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr', 'cpu')
        m = Lifter(base); m.load_state_dict(torch.load(ckpt, map_location='cpu', weights_only=False)['model']); return m.to(dev).eval()

    @staticmethod
    def predict(model, x, cal_cm, dev, batch=512):
        import torch
        from eval_3d_angles import LOOKAHEAD, WINDOW
        L = np.asarray(cal_cm, np.float32); c = torch.from_numpy(np.log(L / L.mean())[None]).to(dev)
        n = len(x); idx = np.clip(np.arange(n)[:, None] + LOOKAHEAD - (WINDOW - 1) + np.arange(WINDOW)[None], 0, n - 1); out = []
        with torch.no_grad():
            for s in range(0, n, batch):
                xb = torch.from_numpy(x[idx[s:s + batch]]).to(dev)
                out.append(model(xb, c.expand(len(xb), -1))[:, WINDOW - 1 - LOOKAHEAD].cpu().numpy())
        return np.concatenate(out)


def h36m_inputs(d, mp):
    co, ha = coco17_to_motionagformer_h36m17(d['coco']), coco17_to_motionagformer_h36m17(d['halpe'][:, :17])
    H = d['halpe']
    hb_xy, hb_c = ha[0].copy(), ha[1].copy()
    for dst, src in ((0, 19), (8, 18), (10, 17)): hb_xy[:, dst], hb_c[:, dst] = H[:, src, :2], H[:, src, 2]
    hb_xy[:, 7] = (hb_xy[:, 0] + hb_xy[:, 8]) / 2; hb_c[:, 7] = (hb_c[:, 0] + hb_c[:, 8]) / 2
    hb_xy[:, 9] = (H[:, 0, :2] + hb_xy[:, 8]) / 2; hb_c[:, 9] = (H[:, 0, 2] + hb_c[:, 8]) / 2
    out = {'coco': co, 'ha': ha, 'hb': (hb_xy, hb_c)}
    if mp is not None:
        out['coco_mp'] = coco17_to_motionagformer_h36m17(mp['coco_in'])
        out['ha_mp'] = coco17_to_motionagformer_h36m17(mp['halpe_in'])
    return out


def normalise(xy, conf, norm, w, h):
    if norm == 'screen':
        return normalize_motionagformer_2d(xy, w, h), np.full(len(xy), w / 2.)
    tr = PersonSquareCropTracker(); crops = []
    for f, c in zip(xy, conf): crops.append(tr.update(f, c) or (w / 2, h / 2, max(w, h)))
    crops = np.array(crops)
    return np.stack([square_crop_normalize(f, c) for f, c in zip(xy, crops)]), crops[:, 2] / 2  # px per unit


def constrain(P, kind, priors):
    if kind == 'raw': return P
    from pose_feedback.geometry.pose3d_constraints import DEFAULT_ANGLE_LIMITS, Pose3DConstraints
    if kind == 'con_app':
        c = Pose3DConstraints()
    else:
        A, B = priors['angles']['tuning']['all'], priors['bones']['prior_lengths']['tuning']
        lim = tuple((n, rf, rt, j, ch, A[n]['p0.1'], A[n]['p99.9']) for n, rf, rt, j, ch, _, _ in DEFAULT_ANGLE_LIMITS)
        pl = {}
        for s in ('right', 'left'):
            pl[f'{s}_hip-{s}_knee'] = 1.0; pl[f'{s}_knee-{s}_ankle'] = B['shin']
            pl[f'{s}_shoulder-{s}_elbow'] = B['upper_arm']; pl[f'{s}_elbow-{s}_wrist'] = B['forearm']
        c = Pose3DConstraints(angle_limits=lim, prior_lengths=pl)
    out, bad = [], []
    for p in P:
        q, r = c.apply(p); out.append(q); bad.append(r['bad'])
    return np.array(out), float(np.mean(bad))


def ang_metrics(A, ref, seg):
    inside = np.zeros(len(ref['knee']), bool)
    for s, e in seg: inside[s:e + 1] = True
    d2 = lambda x: x[2:] - 2 * x[1:-1] + x[:-2]
    out = {}
    for k in ANG:
        a, r, ext = A[k], ref[k], EXTREME[k.split('_')[0]]
        rep = [float(abs(ext(a[s:e + 1]) - ext(r[s:e + 1]))) for s, e in seg]
        rom = [float(abs(np.ptp(a[s:e + 1]) - np.ptp(r[s:e + 1]))) for s, e in seg]
        f = np.abs(a - r)[inside]; j = np.abs(d2(a) - d2(r))[inside[1:-1]]
        out[k] = dict(rep=rep, rom=rom, frame_med=float(np.median(f)), frame_mean=float(f.mean()), jitter_med=float(np.median(j)))
    return out


def metrics3d(P, G, side, up_c, seg):
    m = pose_metrics(P, G)
    pj = np.linalg.norm(P - G, axis=-1).mean(0) * 1000
    paj = np.linalg.norm(procrustes(P, G) - G, axis=-1).mean(0) * 1000
    acc = lambda X: X[2:] - 2 * X[1:-1] + X[:-2]
    accj = (np.linalg.norm(acc(P) - acc(G), axis=-1).mean(0) * 1000)
    ref = angles(G, side, up_c); ref['torso'] = ref['torso_g']
    return dict(mpjpe=float(np.mean(m['mpjpe'])), pa=float(np.mean(m['pa_mpjpe'])), accel=float(np.mean(m['accel'])),
                joint=pj.round(2).tolist(), joint_pa=paj.round(2).tolist(), joint_accel=accj.round(3).tolist(),
                ang=ang_metrics(angles(P, side, up_c), ref, seg))


def metrics2d(K, conf, G2, scale):
    """K [N,17,2] H36M-mapped input, G2 projected mocap H36M17. Joint stats in H36M order."""
    e = np.linalg.norm(K - G2, axis=-1) / scale[:, None]
    acc = lambda X: X[2:] - 2 * X[1:-1] + X[:-2]
    jit = np.linalg.norm(acc(K) - acc(G2), axis=-1)
    up = G2[:, 8] - G2[:, 0]; tl = np.linalg.norm(up, axis=-1); up = up / tl[:, None]
    off = ((K - G2) * up[:, None]).sum(-1) / tl[:, None]  # + = input above the mocap joint, in torso lengths
    br = {}
    for n, ps in SEGS.items():
        r = np.mean([np.linalg.norm(K[:, a] - K[:, b], axis=-1) / np.linalg.norm(G2[:, a] - G2[:, b], axis=-1) for a, b in ps], 0)
        br[n] = float(np.median(r))
    return dict(err=e.mean(0).round(4).tolist(), pck=(e < 0.05).mean(0).round(4).tolist(), jitter_px=jit.mean(0).round(3).tolist(),
                up_off=np.median(off, 0).round(4).tolist(), drop=(conf < 0.3).mean(0).round(4).tolist(),
                conf_med=np.median(conf, 0).round(3).tolist(), conf_p10=np.percentile(conf, 10, axis=0).round(3).tolist(), bone_ratio=br)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', required=True); p.add_argument('--pose2d', required=True); p.add_argument('--mpwrist', required=True)
    p.add_argument('--priors', required=True); p.add_argument('--out', required=True)
    p.add_argument('--subjects', type=lambda s: s.split(','), default=None)
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    p.add_argument('--ckpt', default=None)
    p.add_argument('--ftd', default=None, help='D-D-08 d.pth (Fit3D fine-tuned XS with bone-length FiLM)')
    p.add_argument('--shapes', default=None, help='shapes.json with per-subject calibrated_cm (SMPL beta fit, D-D-08)')
    a = p.parse_args()
    import torch
    dev = 'cuda' if torch.cuda.is_available() else 'cpu'
    model = load(a.mag_repo, a.ckpt or f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr', dev)[0].eval()
    lifters = {'orig': (lambda X, subj: app_predict(model, X, dev), ('crop', 'screen'))}
    if a.ftd:
        ftd, shapes = FiLMLifter.make(a.mag_repo, a.ftd, dev), json.load(open(a.shapes))
        lifters['ftd'] = (lambda X, subj: FiLMLifter.predict(ftd, X, shapes[subj]['calibrated_cm'], dev), ('crop',))
    priors = json.load(open(a.priors)); results = []
    for f in sorted(glob.glob(f'{a.pose2d}/*.npz')):
        name = os.path.basename(f)[:-4]; subj, cam, ex = name.split('_', 2)
        if a.subjects and subj not in a.subjects: continue
        d = dict(np.load(f)); mpf = f'{a.mpwrist}/{name}.npz'; mp = dict(np.load(mpf)) if os.path.exists(mpf) else None
        sd = f'{a.root}/train/{subj}'
        Jw = load_joints(sd, ex); ann = json.load(open(f'{sd}/rep_ann.json'))[ex]
        c = json.load(open(f'{sd}/camera_parameters/{cam}/{ex}.json'))
        R = np.array(c['extrinsics']['R']); T = np.array(c['extrinsics']['T']).reshape(3)
        fpx = float(np.mean(c['intrinsics_w_distortion']['f']))
        keep = d['pick'] < len(Jw); pick = d['pick'][keep]
        for k in ('box', 'has_det', 'coco', 'halpe'): d[k] = d[k][keep]
        if mp:
            for k in ('coco_in', 'halpe_in'): mp[k] = mp[k][keep]
            for k in ('coco_replaced', 'halpe_replaced'): mp[k] = mp[k][keep]
        w, h = (int(x) for x in d['wh'])
        J = Jw[pick]; Xc = (J - T) @ R.T; G = Xc - Xc[:, :1]; zroot = Xc[:, 0, 2]
        G2 = project_fit3d(J.reshape(-1, 3), c).reshape(len(J), 17, 2)
        up_w = np.array([0, 0, 1.]); up_c = R @ up_w
        view, side = view_and_side(Jw, R, T, up_w)
        seg = [(int(np.searchsorted(pick, s)), int(np.searchsorted(pick, e))) for s, e in zip(ann, ann[1:])]
        g2 = G2 - G2.min(1, keepdims=True); scale = np.maximum(g2[..., 0].max(1), g2[..., 1].max(1))
        # box verification: mocap limbs + shoulders + hips inside the RTMDet box
        body = [1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16]; b = d['box']
        inside = ((G2[:, body, 0] >= b[:, None, 0]) & (G2[:, body, 0] <= b[:, None, 2]) & (G2[:, body, 1] >= b[:, None, 1]) & (G2[:, body, 1] <= b[:, None, 3])).all(1)
        res = dict(subject=subj, exercise=ex, cam=cam, group='tuning' if subj in TUNING else 'heldout', view_deg=round(float(view), 1),
                   side=side, frames=int(len(pick)), reps=len(seg), box_ok=float(inside.mean()), nodet=float(1 - d['has_det'].mean()),
                   mp_replaced={k: mp[f'{k}_replaced'].mean(0).round(3).tolist() for k in ('coco', 'halpe')} if mp else None, m2d={}, m3d={}, scale_in={})
        inp = h36m_inputs(d, mp); inp['gt2d'] = (G2.astype(np.float32), np.ones(G2.shape[:2], np.float32))
        H = d['halpe']
        res['halpe_extra'] = {n: dict(err=float((np.linalg.norm(H[:, s, :2] - G2[:, t], axis=-1) / scale).mean()),
                                      up_off=float(np.median((((H[:, s, :2] - G2[:, t]) * ((G2[:, 8] - G2[:, 0]) / np.linalg.norm(G2[:, 8] - G2[:, 0], axis=-1, keepdims=True))).sum(-1))
                                                             / np.linalg.norm(G2[:, 8] - G2[:, 0], axis=-1))))
                              for n, s, t in (('hip19_vs_pelvis', 19, 0), ('neck18_vs_thorax', 18, 8), ('head17_vs_head', 17, 10))}
        for key, (xy, cf) in inp.items():
            if key != 'gt2d': res['m2d'][key] = metrics2d(xy, cf, G2, scale)
            for norm in ('crop', 'screen'):
              x, px = normalise(xy, cf, norm, w, h)
              ys = x[..., 1]; res['scale_in'][f'{key}|{norm}'] = float(np.median(ys.max(1) - ys.min(1)))
              X = np.concatenate([x, cf[..., None]], -1).astype(np.float32)
              unit_m = px * zroot / fpx
              for lname, (fn, norms) in lifters.items():
                if norm not in norms: continue
                Praw = fn(X, subj).astype(float); Praw = Praw - Praw[:, :1]
                for con in ('raw', 'con_app', 'con_fit3d'):
                    if con == 'raw': Pu, badr = Praw, None
                    else: Pu, badr = constrain(Praw, con, priors)
                    P = Pu * unit_m[:, None, None]
                    r = metrics3d(P, G, side, up_c, seg)
                    if badr is not None: r['bad_rate'] = badr
                    res['m3d'][f'{lname}|{key}|{norm}|{con}'] = r
        print(name, f'view={view:.0f}', f"box_ok={res['box_ok']:.3f}",
              {k: (round(v['mpjpe']), round(v['pa'])) for k, v in res['m3d'].items() if k.endswith('|raw') and '|crop' in k}, flush=True)
        results.append(res)
    json.dump(results, open(a.out, 'w'))


if __name__ == '__main__':
    main()
