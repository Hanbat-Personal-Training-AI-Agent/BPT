"""Fine-tune MotionAGFormer-XS on Fit3D with the app's own 2D input (Mac-local only; Fit3D never leaves this Mac).

Input  : pose-replay CSV keypoints (RTMPose-s COCO17, the app's 2D path) sampled at the app's 30 fps, converted
         and person_crop-normalised exactly like the app (pose_feedback.body.live_motionagformer).
Target : Fit3D mocap joints (H36M order) in camera coordinates, root-relative, scaled into the same crop units
         as the input (weak perspective at the root depth: x_px = f * X / Z_root), y down.
MPJPE  : mean per-joint position error in mm (root-aligned), on the app's selected frame (lookahead 5) of
         every frame of the held-out subjects' sequences. Split by subject only.
Weights trained here are Fit3D-derived: non-commercial (capstone) use only.

usage: finetune_motionagformer_fit3d.py --root DIR --replay DIR --train s05 --test s03 --out CKPT [--epochs 15]
"""
import argparse, json, sys, time
from pathlib import Path
import numpy as np
import torch

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO)); sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval_3d_angles import APP_FPS, LOOKAHEAD, WINDOW, fit3d_jobs, read_csv  # noqa: E402
from pose_feedback.body.motionagformer_adapter import (  # noqa: E402
    PersonSquareCropTracker, coco17_to_motionagformer_h36m17, square_crop_normalize)

FLIP_L, FLIP_R = [1, 2, 3, 14, 15, 16], [4, 5, 6, 11, 12, 13]


def sequences(root, replay, subjects, exercises):
    out = []
    for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(root, replay, subjects, exercises):
        K = read_csv(csv); n = min(len(K), len(J))
        pick = np.round(np.arange(0, n, 50 / APP_FPS)).astype(int); pick = pick[pick < n]
        xy, conf = coco17_to_motionagformer_h36m17(K[pick])
        tr = PersonSquareCropTracker(); crops = []
        for f, c in zip(xy, conf): crops.append(tr.update(f, c) or (450., 450., 900.))
        x = np.stack([square_crop_normalize(f, c) for f, c in zip(xy, crops)])
        x = np.concatenate([x, conf[..., None]], -1).astype(np.float32)
        c = json.load(open(f'{root}/train/{subj}/camera_parameters/{cam}/{ex}.json'))
        fpx = float(np.mean(c['intrinsics_w_distortion']['f']))
        Xc = (J[pick] - T) @ R.T  # metres, camera frame, y down
        half = np.array([cr[2] for cr in crops]) / 2
        unit_m = half * Xc[:, 0, 2] / fpx  # metres per crop unit
        y = ((Xc - Xc[:, :1]) / unit_m[:, None, None]).astype(np.float32)
        out.append(dict(subj=subj, ex=ex, cam=cam, x=x, y=y, mm=(unit_m * 1000).astype(np.float32)))
    return out


def train_windows(seqs, stride):
    xs, ys = [], []
    for s in seqs:
        for i in range(0, len(s['x']) - WINDOW + 1, stride):
            xs.append(s['x'][i:i + WINDOW]); ys.append(s['y'][i:i + WINDOW])
    return torch.from_numpy(np.stack(xs)), torch.from_numpy(np.stack(ys))


def flip(t):
    t = t.clone(); t[..., 0] *= -1
    t[..., FLIP_L + FLIP_R, :] = t[..., FLIP_R + FLIP_L, :]
    return t


@torch.no_grad()
def app_predict(model, x, device, batch=512):
    """Per-frame selected output like the app (window [i+L-26, i+L] edge-clamped, row 26-L)."""
    n = len(x); idx = np.clip(np.arange(n)[:, None] + LOOKAHEAD - (WINDOW - 1) + np.arange(WINDOW)[None], 0, n - 1)
    out = []
    for s in range(0, n, batch):
        out.append(model(torch.from_numpy(x[idx[s:s + batch]]).to(device))[:, WINDOW - 1 - LOOKAHEAD].cpu().numpy())
    return np.concatenate(out)


def mpjpe_mm(model, seqs, device):
    model.eval(); errs = {}
    for s in seqs:
        p = app_predict(model, s['x'], device); p = p - p[:, :1]
        e = np.linalg.norm(p - s['y'], axis=-1).mean(-1) * s['mm']
        errs.setdefault(s['ex'], []).append(e)
    per = {k: float(np.concatenate(v).mean()) for k, v in errs.items()}
    per['all'] = float(np.concatenate([np.concatenate(v) for v in errs.values()]).mean())
    return per


def load(mag_repo, ckpt, device):
    sys.path.insert(0, mag_repo)
    from utils.learning import load_model
    from utils.tools import get_config
    args = get_config(f'{mag_repo}/configs/h36m/MotionAGFormer-xsmall.yaml')
    m = load_model(args)
    st = torch.load(ckpt, map_location='cpu', weights_only=False); st = st.get('model', st.get('model_pos', st))
    m.load_state_dict({k.removeprefix('module.'): v for k, v in st.items()}, strict=True)
    return m.to(device), args


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', required=True); p.add_argument('--replay', required=True)
    p.add_argument('--train', required=True); p.add_argument('--test', required=True)
    p.add_argument('--exercises', default='squat,pushup,diamond_pushup,barbell_row,barbell_dead_row')
    p.add_argument('--mag-repo', default=str(REPO / 'external/MotionAGFormer'))
    p.add_argument('--checkpoint', default=None)
    p.add_argument('--epochs', type=int, default=15); p.add_argument('--lr', type=float, default=1e-4)
    p.add_argument('--batch', type=int, default=64); p.add_argument('--stride', type=int, default=3)
    p.add_argument('--out', required=True)
    a = p.parse_args()
    torch.manual_seed(0); np.random.seed(0)
    dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
    model, cfg = load(a.mag_repo, a.checkpoint or f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr', dev)
    from loss.pose3d import loss_mpjpe, n_mpjpe, loss_velocity  # after load() put the repo on sys.path
    ex = a.exercises.split(',')
    tr = sequences(a.root, a.replay, a.train.split(','), ex); te = sequences(a.root, a.replay, a.test.split(','), ex)
    X, Y = train_windows(tr, a.stride)
    print(f'train {len(tr)} seqs {len(X)} windows ({a.train}); test {len(te)} seqs ({a.test}); device {dev}', flush=True)
    log = {'base_test_mpjpe_mm': mpjpe_mm(model, te, dev), 'base_train_mpjpe_mm': mpjpe_mm(model, tr, dev), 'epochs': []}
    print('base', log['base_test_mpjpe_mm'], flush=True)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=cfg.weight_decay)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, a.epochs * ((len(X) + a.batch - 1) // a.batch))
    for ep in range(a.epochs):
        model.train(); perm = torch.randperm(len(X)); t0 = time.time(); tot = 0.
        for i in range(0, len(X), a.batch):
            b = perm[i:i + a.batch]; x, y = X[b], Y[b]
            f = torch.rand(len(b)) < 0.5
            x[f], y[f] = flip(x[f]), flip(y[f])
            x, y = x.to(dev), y.to(dev)
            pred = model(x)
            loss = loss_mpjpe(pred, y) + cfg.lambda_scale * n_mpjpe(pred, y) + cfg.lambda_3d_velocity * loss_velocity(pred, y)
            opt.zero_grad(); loss.backward(); opt.step(); sched.step(); tot += loss.item() * len(b)
        e = {'epoch': ep, 'loss': tot / len(X), 'train_mpjpe_mm': mpjpe_mm(model, tr, dev)['all'], 'sec': round(time.time() - t0)}
        log['epochs'].append(e); print(e, flush=True)
    log['final_test_mpjpe_mm'] = mpjpe_mm(model, te, dev); log['args'] = vars(a)
    print('final', log['final_test_mpjpe_mm'], flush=True)
    torch.save({'model': model.state_dict(), 'note': 'Fit3D-derived weights: non-commercial use only'}, a.out)
    json.dump(log, open(a.out + '.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
