"""finetune3 XS training on xs_data.py sequences — the D-D-06 recipe (scripts/finetune_motionagformer_fit3d.py):
original H36M XS weights, 10 epochs, AdamW 1e-4 (weight decay from the XS config) cosine per step, batch 16, random
left/right flip, loss = MPJPE + lambda_scale * N-MPJPE + lambda_3d_velocity * velocity (XS config values) on the
27-frame window, for kinds R and V. Kind E (Exercise3D, pseudo labels) only gets the limb loss: MPJPE of the 8 limb
joints after removing their own centroid (no hips / pelvis / shoulders: different definitions), weight --w-e,
frames without valid limb labels masked. Output weights are Fit3D-derived (and Sapiens2-derived with E): non-commercial.

usage (Home, bpt-home, under flock ~/.bpt-gpu.lock):
  xs_train.py --data train.npz [more.npz] --out xs.pth [--w-e 0.5] [--epochs 10]
"""
import argparse, json, sys, time
from pathlib import Path
import numpy as np
import torch

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent)]
from eval_3d_angles import WINDOW  # noqa: E402
from finetune_motionagformer_fit3d import flip, load  # noqa: E402

LIMBS = [2, 3, 5, 6, 12, 13, 15, 16]


def load_seqs(paths):
    seqs = []
    for p in paths:
        z = np.load(p)
        for i, m in enumerate(json.loads(str(z['meta']))):
            m = dict(m, x=z[f'x{i}'], y=z[f'y{i}'], mm=z[f'mm{i}'])
            if f'f{i}' in z.files:
                m['fmask'] = z[f'f{i}']
            seqs.append(m)
    return seqs


def windows(seqs, strides):
    X, Y, M, E = [], [], [], []
    for s in seqs:
        for i in range(0, len(s['x']) - WINDOW + 1, strides[s['kind']]):
            m = s['fmask'][i:i + WINDOW] if 'fmask' in s else np.ones(WINDOW, bool)
            if s['kind'] == 'E' and m.sum() < WINDOW // 2:
                continue
            X.append(s['x'][i:i + WINDOW]); Y.append(s['y'][i:i + WINDOW]); M.append(m); E.append(s['kind'] == 'E')
    return (torch.from_numpy(np.stack(X)), torch.from_numpy(np.stack(Y)), torch.from_numpy(np.stack(M)),
            torch.tensor(E))


def limb_loss(pred, y, m):
    p, t = pred[:, :, LIMBS], y[:, :, LIMBS]
    e = torch.norm((p - p.mean(2, keepdim=True)) - (t - t.mean(2, keepdim=True)), dim=-1).mean(-1)
    return (e * m).sum() / m.sum().clamp(min=1)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--data', nargs='+', required=True); p.add_argument('--out', required=True)
    p.add_argument('--mag-repo', default=str(Path('~/models/MotionAGFormer').expanduser()))
    p.add_argument('--epochs', type=int, default=10); p.add_argument('--lr', type=float, default=1e-4)
    p.add_argument('--batch', type=int, default=16); p.add_argument('--w-e', type=float, default=0.5)
    p.add_argument('--stride', default='R=3,V=3,E=3'); p.add_argument('--seed', type=int, default=0)
    a = p.parse_args()
    torch.manual_seed(a.seed); np.random.seed(a.seed)
    dev = 'cuda' if torch.cuda.is_available() else 'cpu'
    model, cfg = load(a.mag_repo, f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr', dev)
    from loss.pose3d import loss_mpjpe, loss_velocity, n_mpjpe  # on sys.path after load()
    seqs = load_seqs(a.data)
    strides = {k: int(v) for k, v in (kv.split('=') for kv in a.stride.split(','))}
    X, Y, M, E = windows(seqs, strides)
    kinds = {}
    for s in seqs:
        kinds[s['kind']] = kinds.get(s['kind'], 0) + 1
    print(f'{len(seqs)} seqs {kinds}, {len(X)} windows ({int(E.sum())} E), device {dev}', flush=True)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=cfg.weight_decay)
    nb = (len(X) + a.batch - 1) // a.batch
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, a.epochs * nb)
    log = dict(args=vars(a), windows=len(X), windows_e=int(E.sum()), seqs=kinds, epochs=[])
    for ep in range(a.epochs):
        model.train(); perm = torch.randperm(len(X)); t0 = time.time(); tot = te = 0.
        for i in range(0, len(X), a.batch):
            b = perm[i:i + a.batch]
            x, y, m, e = X[b].clone(), Y[b].clone(), M[b], E[b]
            f = torch.rand(len(b)) < 0.5
            x[f], y[f] = flip(x[f]), flip(y[f])
            x, y, m, e = x.to(dev), y.to(dev), m.to(dev), e.to(dev)
            pred = model(x)
            loss = torch.zeros((), device=dev)
            if (~e).any():
                pf, yf = pred[~e], y[~e]
                lf = loss_mpjpe(pf, yf) + cfg.lambda_scale * n_mpjpe(pf, yf) + cfg.lambda_3d_velocity * loss_velocity(pf, yf)
                loss = loss + lf * (~e).sum() / len(b)
            if e.any():
                le = limb_loss(pred[e], y[e], m[e].float())
                loss = loss + a.w_e * le * e.sum() / len(b); te += le.item() * int(e.sum())
            opt.zero_grad(); loss.backward(); opt.step(); sched.step(); tot += loss.item() * len(b)
        r = dict(epoch=ep, loss=tot / len(X), limb_loss_e=te / max(1, int(E.sum())), sec=round(time.time() - t0))
        log['epochs'].append(r); print(r, flush=True)
    torch.save({'model': model.state_dict(), 'note': 'finetune3 XS: Fit3D-derived (+Exercise3D/Sapiens2-derived if E) '
                'weights, NON-COMMERCIAL use only', 'args': vars(a)}, a.out)
    json.dump(log, open(a.out + '.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
