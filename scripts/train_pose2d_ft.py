"""Fine-tune RTMPose (COCO17, 256x192 SimCC) on Fit3D crops from build_fit3d_pose2d_crops.py (track C).

Mac (MPS) only: Fit3D data must not leave this machine. Loss = mmpose KLDiscretLoss (beta 10,
label softmax, target weights); aug = scale 0.75-1.25, rotation +-30 deg (p 0.6), shift, flip, colour; BatchNorm statistics frozen.
Face joints 0-4: --face pseudo (current model's prediction, weight 1 where its confidence > 0.5)
or --face zero (weight 0). Selection: lowest body-12 error on --val subjects.

usage: train_pose2d_ft.py --data DIR --train s03,s04 --val s08 --face pseudo|zero --out CKPT
"""

import argparse
import os
import time

import cv2
import numpy as np
import torch
import torch.nn.functional as F

from pose2d_ft_common import DEVICE, forward, load_model, to_tensor
from pose_feedback.body.pose2d_data import (
    INPUT_H, INPUT_W, apply_affine, bbox_from_points, box_to_center_scale, crop_affine, decode_simcc, FLIP_PERM, flip_keypoints,
    simcc_targets,
)

FACE_CONF = 0.5


def load_split(data, subjects, face):
    items = []
    for s in subjects:
        d = np.load(f'{data}/{s}/labels.npz')
        kp = d['keypoints'].copy()
        w = np.ones((len(kp), 17), np.float32)
        kp[:, :5] = d['face']
        w[:, :5] = (d['face_conf'] > FACE_CONF) if face == 'pseudo' else 0
        items += [(f'{data}/{s}/{n}', k, ww) for n, k, ww in zip(d['names'], kp, w)]
    return items


def sample(item, rng, train):
    path, kp, w = item
    img = cv2.cvtColor(cv2.imread(path), cv2.COLOR_BGR2RGB)
    box = bbox_from_points(kp, w > 0)
    c, s = box_to_center_scale(box)
    rot = 0.0
    if train:
        if rng.random() < 0.5:
            img = img[:, ::-1].copy()
            kp = flip_keypoints(kp, img.shape[1]); w = w[FLIP_PERM]
            c = np.array([img.shape[1] - 1 - c[0], c[1]])
        s = s * rng.uniform(0.75, 1.25)
        c = c + rng.uniform(-0.1, 0.1, 2) * s
        if rng.random() < 0.6:
            rot = rng.uniform(-30, 30)
    m = crop_affine(c, s, rot)
    crop = cv2.warpAffine(img, m, (INPUT_W, INPUT_H), flags=cv2.INTER_LINEAR)
    if train:
        crop = np.clip(crop.astype(np.float32) * rng.uniform(0.7, 1.3) + rng.uniform(-25, 25), 0, 255).astype(np.uint8)
    return crop, apply_affine(m, kp), w


def kl_loss(pred, target, weight, beta=10.0):
    log_pt = F.log_softmax(pred * beta, -1)
    tgt = F.softmax(target * beta, -1)
    loss = (tgt * (torch.log(tgt + 1e-12) - log_pt)).mean(-1)  # mean over bins, like mmpose
    return (loss * weight).mean()


def batches(items, bs, rng, train):
    order = rng.permutation(len(items)) if train else np.arange(len(items))
    for i in range(0, len(order), bs):
        crops, tx, ty, ws, kps = [], [], [], [], []
        for j in order[i:i + bs]:
            crop, kp, w = sample(items[j], rng, train)
            a, b, ww = simcc_targets(kp, w)
            crops.append(crop); tx.append(a); ty.append(b); ws.append(ww); kps.append(kp)
        yield to_tensor(crops), torch.from_numpy(np.stack(tx)), torch.from_numpy(np.stack(ty)), torch.from_numpy(np.stack(ws)), np.stack(kps)


@torch.no_grad()
def validate(model, items):
    model.eval()
    errs = []
    rng = np.random.default_rng(0)
    for x, _, _, w, kp in batches(items, 64, rng, False):
        sx, sy = forward(model, x.to(DEVICE))
        for a, b, k, ww in zip(sx.float().cpu().numpy(), sy.float().cpu().numpy(), kp, w.numpy()):
            p, _ = decode_simcc(a, b)
            box = bbox_from_points(k[5:])
            size = max(box[2] - box[0], box[3] - box[1])
            errs.append(np.linalg.norm(p[5:] - k[5:], axis=-1)[ww[5:] > 0] / size)
    e = np.concatenate(errs)
    return float(e.mean()), float((e < 0.05).mean())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--train', required=True)
    ap.add_argument('--val', required=True)
    ap.add_argument('--face', choices=('pseudo', 'zero'), default='pseudo')
    ap.add_argument('--variant', default='coco17')
    ap.add_argument('--epochs', type=int, default=8)
    ap.add_argument('--lr', type=float, default=1e-4)
    ap.add_argument('--bs', type=int, default=48)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    torch.manual_seed(0)
    rng = np.random.default_rng(0)
    train = load_split(a.data, a.train.split(','), a.face)
    val = load_split(a.data, a.val.split(','), a.face)[::3]
    model = load_model(a.variant)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=0.05)
    steps = a.epochs * ((len(train) + a.bs - 1) // a.bs)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, a.lr, total_steps=steps, pct_start=0.05)
    best = validate(model, val)
    print(f'train {len(train)} val {len(val)} epoch 0 val err {best[0]:.4f} pck05 {best[1]:.4f}', flush=True)
    torch.save(model.state_dict(), a.out)
    t0 = time.time()
    for ep in range(1, a.epochs + 1):
        model.train()
        # Frozen BN statistics: 10 train-mode batches of Fit3D alone moved val error 0.046 -> 0.067 (running stats drift).
        for mod in model.modules():
            if isinstance(mod, torch.nn.modules.batchnorm._BatchNorm):
                mod.eval()
        tot = 0.0
        for i, (x, tx, ty, w, _) in enumerate(batches(train, a.bs, rng, True)):
            sx, sy = forward(model, x.to(DEVICE))
            w = w.to(DEVICE)
            loss = kl_loss(sx, tx.to(DEVICE), w) + kl_loss(sy, ty.to(DEVICE), w)
            opt.zero_grad(); loss.backward(); opt.step(); sched.step()
            tot += loss.item()
        err = validate(model, val)
        print(f'epoch {ep} loss {tot / (i + 1):.5f} val err {err[0]:.4f} pck05 {err[1]:.4f} {time.time() - t0:.0f}s', flush=True)
        if err[0] < best[0]:
            best = err
            torch.save(model.state_dict(), a.out)
    print('best', best, flush=True)


if __name__ == '__main__':
    main()
