"""Does knowing the user's body shape improve MotionAGFormer-XS 3D joint angles on unseen people? (D-D-08)

Per subject a "calibrated" bone-length table exactly like the calibration server: SMPL β (10) -> rest-pose mesh
-> J_regressor_h36m -> server/calibration_modal/body.bone_lengths_cm (16 H36M edges + shoulder/hip width, cm).
Fit3D ships SMPL-X (β varies per frame, SMPL-X model not here) and GHUM, not SMPL, so β is fitted per subject to
the subject's median mocap segment lengths (scipy least squares, small β prior). Calibration error is simulated
with independent per-segment log-normal noise σ = 3.75 % (mean |error| ≈ 3 %, decisions F4: held-out 2.83 %).

Variants (same data, same 10 epochs / batch 16 / AdamW 1e-4 cosine / flip as D-D-06/07):
  a  baseline fine-tune (MPJPE + 0.5 n-MPJPE + 20 velocity), retrained identically
  b  a + bone-length conditioning: FiLM on the joint embedding from log(L / mean L) (scale-free), zero-init
  c  a + per-module losses: joint angles (knee/elbow/hip both sides + torso direction, rad), bone-proportion
     consistency vs the subject's (noisy) calibrated lengths, acceleration (temporal smoothness)
  d  b + c
  e  (eval only) post-hoc: rescale each predicted bone to the calibrated proportions along its direction
2D input = the app's own RTMPose-m COCO17 keypoints from pose-replay on the real Fit3D videos (real model noise,
not GT 2D). Split by subject: train s03-s05, held-out s07-s11 (never used for choices).

Licence: Fit3D non-commercial, user's own Mac/Home only, aggregates only. SMPL non-commercial (decisions F5).
Weights trained here are Fit3D-derived: non-commercial capstone use only.

usage (Home, bpt-home):
  train_lifter_body_shape.py shapes --root ~/datasets/fit3d --smpl NPZ --ex3d DIR --out shapes.json
  train_lifter_body_shape.py train  --variant a --root ... --replay DIR --shapes shapes.json --out CKPT
  train_lifter_body_shape.py eval   --variant a --ckpt CKPT --root ... --replay DIR --shapes ... --ex3d DIR --out JSON
  train_lifter_body_shape.py table  RESULT.json ...
"""
import argparse, glob, json, os, pickle, sys, time
from pathlib import Path
import numpy as np

REPO = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(REPO), str(REPO / 'scripts'), str(REPO / 'server/calibration_modal')]
import body  # noqa: E402  (server/calibration_modal/body.py: the calibration server's own length table)
from eval_3d_angles import EX3D_NAMES, FIT3D_TO_H36M, load_joints, near_side, read_csv, view_and_side  # noqa: E402

TRAIN, HELDOUT = ['s03', 's04', 's05'], ['s07', 's08', 's09', 's10', 's11']
TRAIN_EX = ['squat', 'pushup', 'diamond_pushup', 'barbell_row', 'barbell_dead_row']
EVAL_EX = ['squat', 'pushup', 'barbell_row']
PAIRS = [(p, c) for c, p in enumerate(body.H36M_PARENTS) if p >= 0] + [(14, 11), (1, 4)]  # = bone_lengths_cm order
SEGS = list(body.bone_lengths_cm(np.random.rand(17, 3)).keys())
_sw = lambda j: {1: 4, 2: 5, 3: 6, 4: 1, 5: 2, 6: 3, 11: 14, 12: 15, 13: 16, 14: 11, 15: 12, 16: 13}.get(j, j)
FLIP_SEG = [next(k for k, q in enumerate(PAIRS) if {_sw(a), _sw(b)} == set(q)) for a, b in PAIRS]
SIGMA = 0.0375
TRIPLES = [(4, 5, 6), (1, 2, 3), (11, 12, 13), (14, 15, 16), (11, 4, 5), (14, 1, 2)]  # knee, elbow, hip L/R


def seg_len(J):
    return np.linalg.norm(J[..., [b for _, b in PAIRS], :] - J[..., [a for a, _ in PAIRS], :], axis=-1)


# ---------------------------------------------------------------- body shape
def fit_beta(target_cm, mask, smpl, lam=1e-3):
    """SMPL β whose rest-pose H36M segment lengths match target_cm[mask] (relative error), and the server table."""
    from scipy.optimize import least_squares
    R = smpl['J_regressor_h36m']
    A0, D = R @ smpl['v_template'], np.einsum('jv,vcb->jcb', R, smpl['shapedirs'][:, :, :10])
    res = lambda b: np.concatenate([((seg_len(A0 + D @ b) * 100 - target_cm) / target_cm)[mask], np.sqrt(lam) * b])
    beta = least_squares(res, np.zeros(10)).x
    J = body.h36m_joints(body.shaped_vertices(smpl['v_template'], smpl['shapedirs'], beta), R)
    cal = np.array(list(body.bone_lengths_cm(J).values()))
    return beta, cal, float(np.mean(np.abs(cal - target_cm)[mask] / target_cm[mask]) * 100)


def cmd_shapes(a):
    smpl = dict(np.load(a.smpl)); out = {}
    for sd in sorted(glob.glob(f'{a.root}/train/s*')):
        L = np.concatenate([seg_len(J) for ex in TRAIN_EX if (J := load_joints(sd, ex)) is not None]) * 100
        target = np.median(L, 0)
        beta, cal, err = fit_beta(target, np.ones(len(SEGS), bool), smpl)
        out[os.path.basename(sd)] = dict(beta=beta.tolist(), calibrated_cm=cal.tolist(), mocap_cm=target.tolist(), fit_err_pct=err)
        print(os.path.basename(sd), f'fit {err:.2f}%', flush=True)
    if a.ex3d:  # Exercise3D labels (Sapiens triangulation): only the segments whose joints exist
        have = [i for i, n in enumerate(EX3D_NAMES) if n and i != 9]  # Ex3D "neck" slot is the nose
        mask = np.array([a_ in have and b_ in have for a_, b_ in PAIRS])
        for seq in sorted(json.load(open(f'{a.ex3d}/gt.json'))):
            J = ex3d_joints(a.ex3d, seq)[0]
            target = np.nan_to_num(np.nanmedian(seg_len(J), 0) * 100, nan=1.)
            beta, cal, err = fit_beta(target, mask, smpl)
            out[seq] = dict(beta=beta.tolist(), calibrated_cm=cal.tolist(), fit_err_pct=err)
            print(seq, f'fit {err:.2f}%', flush=True)
    json.dump(out, open(a.out, 'w'), indent=1)


def noisy(cal, rng):
    return np.asarray(cal) * np.exp(rng.normal(0, SIGMA, len(cal))) if rng is not None else np.asarray(cal)


def cond(L):
    L = np.asarray(L, np.float32); return np.log(L / L.mean(-1, keepdims=True))


# ---------------------------------------------------------------- model
def build(a, variant, dev):
    import torch, torch.nn as nn
    from finetune_motionagformer_fit3d import load

    class Lifter(nn.Module):
        """MotionAGFormer-XS; with film=True a zero-initialised FiLM on the joint embedding from the bone vector."""
        def __init__(self, base, film):
            super().__init__(); self.base = base
            self.film = nn.Sequential(nn.Linear(len(SEGS), 64), nn.GELU(), nn.Linear(64, 2 * base.pos_embed.shape[-1])) if film else None
            if film: nn.init.zeros_(self.film[2].weight); nn.init.zeros_(self.film[2].bias)

        def forward(self, x, c=None):
            m = self.base; h = m.joints_embed(x) + m.pos_embed
            if self.film is not None:
                g, b = self.film(c).chunk(2, -1); h = h * (1 + g[:, None, None]) + b[:, None, None]
            for layer in m.layers: h = layer(h)
            return m.head(m.rep_logit(m.norm(h)))

    base, cfg = load(a.mag_repo, f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr', 'cpu')
    return Lifter(base, variant in 'bd').to(dev), cfg


def sequences(a, subjects, exercises):
    """App-2D input / mocap target per video (finetune_motionagformer_fit3d.prep), cached on Home."""
    from finetune_motionagformer_fit3d import sequences as seqs
    path = f'{a.cache}/seqs_{"_".join(subjects)}_{"_".join(exercises)}.pkl'
    if os.path.exists(path): return pickle.load(open(path, 'rb'))
    s = seqs(a.root, a.replay, subjects, exercises); os.makedirs(a.cache, exist_ok=True); pickle.dump(s, open(path, 'wb'))
    return s


def losses(pred, y, Lcal, torch):
    """Per-module losses (variant c/d): joint angles (rad), bone proportions vs calibration, acceleration."""
    def ang(u, v): return torch.atan2(torch.sqrt((torch.cross(u, v, dim=-1) ** 2).sum(-1) + 1e-12), (u * v).sum(-1))
    def angles(P): return torch.stack([ang(P[..., i, :] - P[..., j, :], P[..., k, :] - P[..., j, :]) for i, j, k in TRIPLES], -1)
    torso = lambda P: (P[..., 11, :] + P[..., 14, :]) / 2 - (P[..., 1, :] + P[..., 4, :]) / 2
    la = (angles(pred) - angles(y)).abs().mean() + ang(torso(pred), torso(y)).mean()
    A, B = [a for a, _ in PAIRS], [b for _, b in PAIRS]
    L = torch.sqrt(((pred[..., B, :] - pred[..., A, :]) ** 2).sum(-1) + 1e-12)
    p, q = L / L.sum(-1, keepdim=True), Lcal / Lcal.sum(-1, keepdim=True)
    lb = (p / q[:, None] - 1).abs().mean()
    acc = lambda P: P[:, 2:] - 2 * P[:, 1:-1] + P[:, :-2]
    lacc = torch.norm(acc(pred) - acc(y), dim=-1).mean()
    return la, lb, lacc


def cmd_train(a):
    import torch
    from eval_3d_angles import WINDOW
    from finetune_motionagformer_fit3d import flip
    torch.manual_seed(0); np.random.seed(0); rng = np.random.default_rng(0)
    dev = 'cuda' if torch.cuda.is_available() else 'cpu'
    model, cfg = build(a, a.variant, dev)
    from loss.pose3d import loss_mpjpe, n_mpjpe, loss_velocity
    shapes = json.load(open(a.shapes)); seqs = sequences(a, TRAIN, TRAIN_EX)
    xs, ys, ss = [], [], []
    for s in seqs:
        for i in range(0, len(s['x']) - WINDOW + 1, a.stride):
            xs.append(s['x'][i:i + WINDOW]); ys.append(s['y'][i:i + WINDOW]); ss.append(s['subj'])
    X, Y = torch.from_numpy(np.stack(xs)), torch.from_numpy(np.stack(ys)); CAL = [shapes[s]['calibrated_cm'] for s in ss]
    print(f'variant {a.variant}: {len(seqs)} seqs {len(X)} windows, device {dev}', flush=True)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=cfg.weight_decay)
    steps = a.epochs * ((len(X) + a.batch - 1) // a.batch)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, steps)
    log = {'variant': a.variant, 'epochs': [], 'args': vars(a)}
    for ep in range(a.epochs):
        model.train(); perm = torch.randperm(len(X)); t0 = time.time(); tot = np.zeros(4)
        for i in range(0, len(X), a.batch):
            b = perm[i:i + a.batch]; x, y = X[b].clone(), Y[b].clone()
            L = np.stack([noisy(CAL[j], rng) for j in b.tolist()]).astype(np.float32)
            f = torch.rand(len(b)) < 0.5
            x[f], y[f] = flip(x[f]), flip(y[f]); L[f.numpy()] = L[f.numpy()][:, FLIP_SEG]
            x, y, Lt = x.to(dev), y.to(dev), torch.from_numpy(L).to(dev)
            pred = model(x, torch.from_numpy(cond(L)).to(dev))
            loss = loss_mpjpe(pred, y) + cfg.lambda_scale * n_mpjpe(pred, y) + cfg.lambda_3d_velocity * loss_velocity(pred, y)
            terms = [loss.item(), 0, 0, 0]
            if a.variant in 'cd':
                la, lb, lacc = losses(pred, y, Lt, torch)
                loss = loss + a.w_angle * la + a.w_bone * lb + a.w_acc * lacc
                terms[1:] = [a.w_angle * la.item(), a.w_bone * lb.item(), a.w_acc * lacc.item()]
            opt.zero_grad(); loss.backward(); opt.step(); sched.step(); tot += np.array(terms) * len(b)
        e = dict(epoch=ep, base=tot[0] / len(X), angle=tot[1] / len(X), bone=tot[2] / len(X), acc=tot[3] / len(X), sec=round(time.time() - t0))
        log['epochs'].append(e); print(e, flush=True)
    torch.save({'model': model.state_dict(), 'variant': a.variant,
                'note': 'Fit3D-derived weights: non-commercial (capstone) use only; SMPL-derived conditioning'}, a.out)
    json.dump(log, open(a.out + '.json', 'w'), indent=1)


# ---------------------------------------------------------------- eval
def project(P, L):
    """Post-hoc bone projection: each predicted bone keeps its direction, gets the calibrated length (same
    proportions, scaled per frame to the prediction's own total length). P [N,17,3] root-relative."""
    s = seg_len(P)[:, :16].sum(-1) / np.sum(L[:16]); Q = np.zeros_like(P)
    for k, (p, c) in enumerate(PAIRS[:16]):  # parents come before children
        d = P[:, c] - P[:, p]; d /= np.linalg.norm(d, axis=-1, keepdims=True) + 1e-9
        Q[:, c] = Q[:, p] + d * (L[k] * s)[:, None]
    return Q


def predict(model, x, L, dev, batch=512):
    """Per-frame selected output like the app (window [i+L-26, i+L] edge-clamped, row 26-L)."""
    import torch
    from eval_3d_angles import LOOKAHEAD, WINDOW
    n = len(x); idx = np.clip(np.arange(n)[:, None] + LOOKAHEAD - (WINDOW - 1) + np.arange(WINDOW)[None], 0, n - 1)
    c = torch.from_numpy(cond(L)[None]).to(dev); out = []
    with torch.no_grad():
        for s in range(0, n, batch):
            xb = torch.from_numpy(x[idx[s:s + batch]]).to(dev)
            out.append(model(xb, c.expand(len(xb), -1))[:, WINDOW - 1 - LOOKAHEAD].cpu().numpy())
    P = np.concatenate(out).astype(float); return P - P[:, :1]


def ex3d_joints(root, seq):
    import ast
    z = np.load(f'{root}/exercise3d_labels/{seq}/geometry/canonical_3d.npz'); names = list(z['joint_names'])
    Pw = z['keypoints_3d'].astype(float)
    J = np.stack([Pw[:, names.index(nm)] if nm else np.full((len(Pw), 3), np.nan) for nm in EX3D_NAMES], 1)
    cg = json.load(open(f'{root}/exercise3d_labels/{seq}/geometry/metadata.json'))['camera_geometry']
    cg = ast.literal_eval(cg) if isinstance(cg, str) else cg
    return J, {c: np.array(v['extrinsic_world_to_camera'])[:, :3] for c, v in cg.items()}


def cmd_eval(a):
    import torch
    from eval_3d_mediapipe import angle_metrics, angles, pose_metrics
    from finetune_motionagformer_fit3d import mag_input
    dev = 'cuda' if torch.cuda.is_available() else 'cpu'
    model, _ = build(a, a.variant, dev)
    model.load_state_dict(torch.load(a.ckpt, map_location='cpu', weights_only=False)['model']); model.eval()
    shapes = json.load(open(a.shapes))
    v, uses_c, out = a.variant, a.variant in 'bd', []

    def run(res, x, cal, G, side, up, seg, mm, with_pose=True):
        """Tags: <v> (noisy calibration, 3 fixed draws pooled; a/c ignore it), <v>_oracle (exact calibration),
        e_<v> / e_<v>_oracle (post-hoc bone projection on top)."""
        def lifted(L):
            P = predict(model, x, L, dev)
            return P * mm[:, None, None] / 1000 if mm is not None else P

        def pooled(tag, preds):
            r = {}
            for P in preds:
                m = {**angle_metrics(angles(P, side, up), res['_ref'], seg), **(pose_metrics(P, G) if with_pose else {})}
                for k, val in m.items():
                    if isinstance(val, dict):
                        for kk, vv in val.items(): r.setdefault(k, {}).setdefault(kk, []).extend(vv)
                    elif isinstance(val, list): r.setdefault(k, []).extend(val)
                    else: r[k] = val
            res[tag] = r
        oracle = np.asarray(cal)
        draws = [noisy(cal, np.random.default_rng([k, sum(map(ord, res['subject']))])) for k in range(3)]
        P0 = lifted(oracle)
        noisy_preds = [lifted(L) for L in draws] if uses_c else [P0] * 3
        pooled(v, noisy_preds if uses_c else [P0])
        if uses_c: pooled(v + '_oracle', [P0])
        pooled('e_' + v, [project(P, L) for P, L in zip(noisy_preds, draws)])
        pooled('e_' + v + '_oracle', [project(P0, oracle)])

    from finetune_motionagformer_fit3d import prep
    from eval_3d_angles import fit3d_jobs
    for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(a.root, a.replay, HELDOUT, EVAL_EX):
        d = prep(a.root, subj, ex, cam, J, R, T, csv); pick = d['pick']
        up_w = -R[1] / np.linalg.norm(R[1]); up_w = np.array([0, 0, 1.]) if abs(up_w[2]) > 0.8 else up_w
        up_c = R @ up_w; G = d['y'] * d['mm'][:, None, None] / 1000
        view, _ = view_and_side(J, R, T, up_w); side = near_side(d['K'])
        seg = [(int(np.searchsorted(pick, s)), int(np.searchsorted(pick, e))) for s, e in zip(ann, ann[1:])]
        ref = angles(G, side, up_c); ref['torso'] = ref['torso_g']
        res = dict(source='fit3d', subject=subj, exercise=ex, cam=cam, view_deg=round(view, 1), _ref=ref)
        run(res, d['x'], shapes[subj]['calibrated_cm'], G, side, up_c, seg, d['mm'])
        res.pop('_ref'); out.append(res); print(subj, ex, cam, round(float(np.mean(res[a.variant]['mpjpe']))), flush=True)
    if a.ex3d:  # relative check only (labels are not ground truth)
        gt = json.load(open(f'{a.ex3d}/gt.json')); exname = {'squat': 'squat', 'pushup': 'pushup', 'barbellrow': 'barbell_row'}
        for seq, g in gt.items():
            J, Rs = ex3d_joints(a.ex3d, seq)
            up_w = -np.mean([R[1] for R in Rs.values()], axis=0); up_w /= np.linalg.norm(up_w)
            rf = g['rep_frames']; half = int(np.median(np.diff(rf)) / 2) if len(rf) > 1 else 15
            for cam, v in g['views'].items():
                csv = f'{a.ex3d}/ex3dcsv/{seq}/{cam}_{exname[g["exercise"]]}_mcoco17.csv'
                if v['angle_deg'] > 75 or not os.path.exists(csv): continue
                K = read_csv(csv); meta = glob.glob(f'{a.ex3d}/replay_meta/{seq}/{cam}_*_coco17.json')[0]
                w, h = json.load(open(meta))['image_size']
                n = min(len(K), len(J)); K = K[:n]; R = Rs[cam]; up_c = R @ up_w
                G = J[:n] @ R.T; G[:, 7], G[:, 10] = (G[:, 0] + G[:, 8]) / 2, G[:, 9]; G = G - G[:, :1]
                seg = [(max(0, r - half), min(n - 1, r + half)) for r in rf if r < n]
                side = near_side(K); ref = angles(G, side, up_c); ref['torso'] = ref['torso_g']
                res = dict(source='ex3d', subject=seq, exercise=g['exercise'], cam=cam, view_deg=v['angle_deg'], _ref=ref)
                run(res, mag_input(K, w, h)[0], shapes[seq]['calibrated_cm'], G, side, up_c, seg, None, with_pose=False)
                res.pop('_ref'); out.append(res); print(seq, cam, round(v['angle_deg']), flush=True)
    json.dump(out, open(a.out, 'w'))


# ---------------------------------------------------------------- table
CELLS = [('squat', 'knee'), ('squat', 'hip'), ('squat', 'torso_g'), ('pushup', 'hip'), ('pushup', 'elbow'),
         ('barbell_row', 'torso_g'), ('barbell_row', 'elbow')]
EX3D_EX = {'barbellrow': 'barbell_row'}


def cell(rows, tag, ex, limb):
    v = np.concatenate([r[tag][limb]['rep'] for r in rows if tag in r and EX3D_EX.get(r['exercise'], r['exercise']) == ex] or [[]])
    if not len(v): return '-'
    m, p = np.median(v), np.percentile(v, 90)
    return f'{"**" if m <= 5 and p <= 10 else ""}{m:.1f} ({p:.0f}){"**" if m <= 5 and p <= 10 else ""}'


def cmd_table(a):
    rows = [r for f in a.files for r in json.load(open(f))]
    tags = list(dict.fromkeys(k for r in rows for k, v in r.items() if isinstance(v, dict)))
    head = ' | '.join(f'{ex.split("_")[-1]} {limb}' for ex, limb in CELLS)
    for title, sel, pose in (('Fit3D held-out s07-s11 (diagonal 56-75 deg)', lambda r: r['source'] == 'fit3d', True),
                             ('Exercise3D side <=40 deg (labels not GT, relative)', lambda r: r['source'] == 'ex3d' and r['view_deg'] <= 40, False),
                             ('Exercise3D diagonal 40-75 deg (relative)', lambda r: r['source'] == 'ex3d' and r['view_deg'] > 40, False)):
        rs = [r for r in rows if sel(r)]
        if not rs: continue
        print(f'\n### {title} ({len(rs)} videos)\n')
        print(f'| variant | {"MPJPE | PA-MPJPE | accel | " if pose else ""}{head} |')
        print('|---|' + '---|' * (len(CELLS) + (3 if pose else 0)))
        for t in tags:
            sub = [r for r in rs if t in r]
            if not sub: continue
            pm = ''
            if pose and 'mpjpe' in sub[0][t]:
                cat = lambda k: np.concatenate([r[t][k] for r in sub])
                pm = f"{cat('mpjpe').mean():.1f} | {cat('pa_mpjpe').mean():.1f} | {cat('accel').mean():.2f} | "
            print(f'| {t} | {pm}' + ' | '.join(cell(sub, t, ex, limb) for ex, limb in CELLS) + ' |')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['shapes', 'train', 'eval', 'table']); p.add_argument('files', nargs='*')
    p.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d')); p.add_argument('--replay')
    p.add_argument('--smpl'); p.add_argument('--ex3d'); p.add_argument('--shapes'); p.add_argument('--ckpt')
    p.add_argument('--variant', default='a', choices=list('abcd'))
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    p.add_argument('--cache', default=os.path.expanduser('~/bpt-smpl/cache'))
    p.add_argument('--epochs', type=int, default=10); p.add_argument('--batch', type=int, default=16)
    p.add_argument('--stride', type=int, default=3); p.add_argument('--lr', type=float, default=1e-4)
    p.add_argument('--w-angle', type=float, default=0.1); p.add_argument('--w-bone', type=float, default=0.1)
    p.add_argument('--w-acc', type=float, default=10.0)
    p.add_argument('--out')
    a = p.parse_args()
    {'shapes': cmd_shapes, 'train': cmd_train, 'eval': cmd_eval, 'table': cmd_table}[a.cmd](a)


if __name__ == '__main__':
    main()
