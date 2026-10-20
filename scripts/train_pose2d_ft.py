"""Fine-tune RTMPose (COCO17, 256x192 SimCC) on Fit3D crops from build_fit3d_pose2d_crops.py (track C, rtmpose-ft).

Fit3D data stays on the user's own machines (Mac MPS or Home CUDA), never cloud. Loss = mmpose KLDiscretLoss (beta 10,
label softmax, target weights); aug = scale 0.75-1.25, rotation +-30 deg (p 0.6), shift, flip, colour; BatchNorm statistics frozen.
Face joints 0-4: --face pseudo (current model's prediction, weight 1 where its confidence > 0.5)
or --face zero (weight 0). --hips-shoulders pseudo keeps COCO's hip/shoulder definition (Fit3D's are
joint centres, ~5% of the box away) by training those on the current model's prediction too. Selection: lowest body-12 error on --val subjects.

rtmpose-ft (D-C-08) options:
  --fit3d-joints limbs   Fit3D supervision only on the joints verified for COCO (elbows, wrists, knees, ankles);
                         face/shoulders/hips weight 0 (docs/results/rtmpose_ft_label_check.md).
  --coco DIR --coco-ratio R   mix COCO train2017 crops (build_coco_pose2d_crops.py) so that R of every epoch is COCO,
                         redrawn each epoch; --coco-val N of them are held back for selection (COCO body-12 PCK).
  --aug app              app-like crop (RTMPoseCropTracker: keypoint box, 3:4, hysteresis up to 1.35x, off-centre),
                         small rotation, plus motion blur, low light + sensor noise, JPEG compression.
  Selection: best Fit3D --val limbs PCK@0.05 among epochs whose COCO-holdout body-12 PCK is >= epoch 0 - 0.005.

finetune3 (D-F3-01/02) options:
  --extra DIR/NAME,...   more crop sets (labels.npz, e.g. Exercise3D P1 Sapiens2 labels) trained on all 17 joints
                         with their own weights (pseudo = label).
  --freeze-backbone      train the head only (backbone frozen, BN frozen as always).
  --distill W            add W x KL(student || original model) on the COCO crops (teacher = the starting weights,
                         frozen), on top of the COCO labels — keeps COCO behaviour close to the original.

usage: train_pose2d_ft.py --data DIR --train s03,s04 --val s05 --face pseudo|zero --out CKPT
       [--fit3d-joints limbs] [--coco DIR --coco-ratio 0.5] [--aug app] [--variant m_coco17]
"""

import argparse
import json
import os
import time

import cv2
import numpy as np
import torch
import torch.nn.functional as F

from pose2d_ft_common import DEVICE, MEAN, STD, forward, load_model
from pose_feedback.body.pose2d_data import (
    INPUT_H, INPUT_W, apply_affine, bbox_from_points, box_to_center_scale, crop_affine, decode_simcc, FLIP_PERM, flip_keypoints,
    simcc_targets,
)

FACE_CONF = 0.5


HIPS_SHOULDERS = [5, 6, 11, 12]
LIMBS = [7, 8, 9, 10, 13, 14, 15, 16]


def load_split(data, subjects, face, hips_shoulders='fit3d', joints='body12'):
    items = []
    for s in subjects:
        d = np.load(f'{data}/{s}/labels.npz')
        kp = d['keypoints'].copy()
        w = np.ones((len(kp), 17), np.float32)
        kp[:, :5] = d['pseudo'][:, :5]
        w[:, :5] = (d['pseudo_conf'][:, :5] > FACE_CONF) if face == 'pseudo' else 0
        if hips_shoulders == 'pseudo':
            kp[:, HIPS_SHOULDERS] = d['pseudo'][:, HIPS_SHOULDERS]
            w[:, HIPS_SHOULDERS] = d['pseudo_conf'][:, HIPS_SHOULDERS] > FACE_CONF
        if joints == 'limbs':
            keep = np.zeros(17, np.float32); keep[LIMBS] = 1
            w *= keep
        if 'weights' in d:  # COCO replay: only labelled joints
            w *= d['weights']
        items += [(f'{data}/{s}/{n}', k, ww) for n, k, ww in zip(d['names'], kp, w)]
    return items


def degrade(crop, rng):
    """App conditions: motion blur, low light (gamma + sensor noise), JPEG compression; each p=0.3."""
    if rng.random() < 0.3:
        k = int(rng.integers(5, 16))
        ker = np.zeros((k, k), np.float32)
        ker[k // 2] = 1
        ker = cv2.warpAffine(ker, cv2.getRotationMatrix2D((k / 2 - 0.5, k / 2 - 0.5), rng.uniform(0, 180), 1.0), (k, k))
        crop = cv2.filter2D(crop, -1, ker / max(ker.sum(), 1e-6))
    if rng.random() < 0.3:
        x = (crop.astype(np.float32) / 255) ** rng.uniform(1.5, 3.0) * 255 * rng.uniform(0.5, 1.0)
        crop = np.clip(x + rng.normal(0, rng.uniform(2, 10), x.shape), 0, 255).astype(np.uint8)
    if rng.random() < 0.3:
        ok, buf = cv2.imencode('.jpg', crop, [cv2.IMWRITE_JPEG_QUALITY, int(rng.integers(15, 60))])
        crop = cv2.imdecode(buf, cv2.IMREAD_UNCHANGED)
    return crop


def sample(item, rng, train, aug='mmpose'):
    path, kp, w = item
    img = cv2.cvtColor(cv2.imread(path), cv2.COLOR_BGR2RGB)
    box = bbox_from_points(kp, w > 0)
    if aug == 'app':  # RTMPoseCropTracker: keypoint bounds + 8% height, 12.5% margin per side, 3:4
        box = box + np.array([0, -0.08, 0, 0.08]) * (box[3] - box[1])
    c, s = box_to_center_scale(box)
    rot = 0.0
    if train:
        if rng.random() < 0.5:
            img = img[:, ::-1].copy()
            kp = flip_keypoints(kp, img.shape[1]); w = w[FLIP_PERM]
            c = np.array([img.shape[1] - 1 - c[0], c[1]])
        if aug == 'app':  # hysteresis keeps a crop up to 1.35x the target, person anywhere inside
            k = rng.uniform(0.95, 1.4)
            c = c + rng.uniform(-0.5, 0.5, 2) * (k - 1) * s + rng.uniform(-0.03, 0.03, 2) * s
            s = s * k
            if rng.random() < 0.3:
                rot = rng.uniform(-15, 15)
        else:
            s = s * rng.uniform(0.75, 1.25)
            c = c + rng.uniform(-0.1, 0.1, 2) * s
            if rng.random() < 0.6:
                rot = rng.uniform(-30, 30)
    m = crop_affine(c, s, rot)
    crop = cv2.warpAffine(img, m, (INPUT_W, INPUT_H), flags=cv2.INTER_LINEAR)
    if train:
        crop = np.clip(crop.astype(np.float32) * rng.uniform(0.7, 1.3) + rng.uniform(-25, 25), 0, 255).astype(np.uint8)
        if aug == 'app':
            crop = degrade(crop, rng)
    return crop, apply_affine(m, kp), w


def kl_loss(pred, target, weight, beta=10.0):
    log_pt = F.log_softmax(pred * beta, -1)
    tgt = F.softmax(target * beta, -1)
    loss = (tgt * (torch.log(tgt + 1e-12) - log_pt)).mean(-1)  # mean over bins, like mmpose
    return (loss * weight).mean()


class Crops(torch.utils.data.Dataset):
    def __init__(self, items, train, aug, seed):
        self.items, self.train, self.aug, self.seed = items, train, aug, seed

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        rng = np.random.default_rng((self.seed, i)) if self.train else np.random.default_rng(0)
        crop, kp, w = sample(self.items[i], rng, self.train, self.aug)
        a, b, ww = simcc_targets(kp, w)
        x = (crop.astype(np.float32) - MEAN) / STD
        return torch.from_numpy(x.transpose(2, 0, 1).copy()), torch.from_numpy(a), torch.from_numpy(b), torch.from_numpy(ww), kp


def batches(items, bs, rng, train, aug='mmpose', workers=0, coco_prefix=None):
    order = rng.permutation(len(items)) if train else np.arange(len(items))
    ordered = [items[j] for j in order]
    ds = Crops(ordered, train, aug, int(rng.integers(1 << 30)))
    for b, (x, tx, ty, w, kp) in enumerate(torch.utils.data.DataLoader(ds, batch_size=bs, num_workers=workers, shuffle=False)):
        if coco_prefix is None:
            yield x, tx, ty, w, kp.numpy()
        else:
            src = torch.tensor([it[0].startswith(coco_prefix) for it in ordered[b * bs:(b + 1) * bs]])
            yield x, tx, ty, w, kp.numpy(), src


@torch.no_grad()
def validate(model, items, workers=0):
    """-> (mean error / box, PCK@0.05) over the body joints that carry weight."""
    model.eval()
    errs = []
    rng = np.random.default_rng(0)
    for x, _, _, w, kp in batches(items, 64, rng, False, workers=workers):
        sx, sy = forward(model, x.to(DEVICE))
        for a, b, k, ww in zip(sx.float().cpu().numpy(), sy.float().cpu().numpy(), kp, w.numpy()):
            p, _ = decode_simcc(a, b)
            box = bbox_from_points(k[5:], ww[5:] > 0) if (ww[5:] > 0).sum() >= 2 else bbox_from_points(k[5:])
            size = max(box[2] - box[0], box[3] - box[1], 1.0)
            errs.append(np.linalg.norm(p[5:] - k[5:], axis=-1)[ww[5:] > 0] / size)
    e = np.concatenate(errs)
    return float(e.mean()), float((e < 0.05).mean())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--train', required=True)
    ap.add_argument('--val', required=True)
    ap.add_argument('--face', choices=('pseudo', 'zero'), default='pseudo')
    ap.add_argument('--hips-shoulders', choices=('fit3d', 'pseudo'), default='fit3d')
    ap.add_argument('--fit3d-joints', choices=('body12', 'limbs'), default='body12')
    ap.add_argument('--coco')
    ap.add_argument('--coco-ratio', type=float, default=0.5)
    ap.add_argument('--coco-val', type=int, default=1500)
    ap.add_argument('--aug', choices=('mmpose', 'app'), default='mmpose')
    ap.add_argument('--variant', default='coco17')
    ap.add_argument('--extra', default='')
    ap.add_argument('--freeze-backbone', action='store_true')
    ap.add_argument('--distill', type=float, default=0.0)
    ap.add_argument('--epochs', type=int, default=8)
    ap.add_argument('--lr', type=float, default=1e-4)
    ap.add_argument('--bs', type=int, default=48)
    ap.add_argument('--workers', type=int, default=0)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    torch.manual_seed(0)
    rng = np.random.default_rng(0)
    train = load_split(a.data, a.train.split(','), a.face, a.hips_shoulders, a.fit3d_joints)
    for ex in filter(None, a.extra.split(',')):
        train += load_split(os.path.dirname(ex), [os.path.basename(ex)], 'pseudo', 'pseudo', 'body12')
    val = load_split(a.data, a.val.split(','), a.face, a.hips_shoulders, a.fit3d_joints)[::3]
    coco, coco_val = [], []
    if a.coco:
        c = load_split(os.path.dirname(a.coco), [os.path.basename(a.coco)], 'pseudo', 'pseudo')
        perm = np.random.default_rng(1).permutation(len(c))
        coco_val, coco = [c[i] for i in perm[:a.coco_val]], [c[i] for i in perm[a.coco_val:]]
    n_coco = int(len(train) * a.coco_ratio / (1 - a.coco_ratio)) if coco else 0
    model = load_model(a.variant)
    teacher = None
    if a.distill > 0:
        teacher = load_model(a.variant).eval()
        for q in teacher.parameters():
            q.requires_grad_(False)
    if a.freeze_backbone:
        for q in model.backbone.parameters():
            q.requires_grad_(False)
    opt = torch.optim.AdamW([q for q in model.parameters() if q.requires_grad], lr=a.lr, weight_decay=0.05)
    steps = a.epochs * ((len(train) + n_coco + a.bs - 1) // a.bs)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, a.lr, total_steps=steps, pct_start=0.05)

    def evaluate():
        f = validate(model, val, a.workers)
        c = validate(model, coco_val, a.workers) if coco_val else (float('nan'), float('nan'))
        return dict(fit3d_err=f[0], fit3d_pck05=f[1], coco_err=c[0], coco_pck05=c[1])

    log = [dict(epoch=0, **evaluate())]
    floor = log[0]['coco_pck05'] - 0.005
    best = log[0]
    print(f'train fit3d {len(train)} + coco {n_coco}/epoch (pool {len(coco)}), val {len(val)} / coco {len(coco_val)}', log[0], flush=True)
    torch.save(model.state_dict(), a.out)
    t0 = time.time()
    for ep in range(1, a.epochs + 1):
        model.train()
        # Frozen BN statistics: 10 train-mode batches of Fit3D alone moved val error 0.046 -> 0.067 (running stats drift).
        for mod in model.modules():
            if isinstance(mod, torch.nn.modules.batchnorm._BatchNorm):
                mod.eval()
        items = train + [coco[i] for i in rng.choice(len(coco), n_coco, replace=False)] if n_coco else train
        tot = 0.0
        coco_prefix = os.path.dirname(coco[0][0]) if (teacher is not None and coco) else None
        for i, (x, tx, ty, w, _, *src) in enumerate(batches(items, a.bs, rng, True, a.aug, a.workers, coco_prefix)):
            x = x.to(DEVICE)
            sx, sy = forward(model, x)
            w = w.to(DEVICE)
            loss = kl_loss(sx, tx.to(DEVICE), w) + kl_loss(sy, ty.to(DEVICE), w)
            if teacher is not None and src and src[0].any():
                c = src[0].to(DEVICE)
                with torch.no_grad():
                    gx, gy = forward(teacher, x[c])
                ones = torch.ones(gx.shape[:2], device=DEVICE)
                loss = loss + a.distill * (kl_loss(sx[c], gx, ones) + kl_loss(sy[c], gy, ones)) * c.float().mean()
            opt.zero_grad(); loss.backward(); opt.step(); sched.step()
            tot += loss.item()
        r = dict(epoch=ep, loss=tot / (i + 1), sec=round(time.time() - t0), **evaluate())
        log.append(r)
        print(r, flush=True)
        if r['fit3d_pck05'] > best['fit3d_pck05'] and not r['coco_pck05'] < floor:
            best = r
            torch.save(model.state_dict(), a.out)
    json.dump(dict(args=vars(a), log=log, best=best), open(a.out + '.json', 'w'), indent=1)
    print('best', best, flush=True)


if __name__ == '__main__':
    main()
