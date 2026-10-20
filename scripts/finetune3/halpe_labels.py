"""Halpe26 training labels for the existing 2D crops (D-F3-05): same images (symlinks), 26 keypoints, new labels.npz.

  fit3d  c2d/fit3d/<s> (build_fit3d_pose2d_crops.py, COCO17 body from the mocap) + feet = the official SMPL-X fit's
         OpenPose foot vertices (foot_labels.py, definition verified on the tuning subjects), mapped with the same crop
         affine the builder used (recomputed from the mocap and checked against the stored COCO joints).
  ex3d   c2d/ex3d_p1 (build_ex3d_pose2d_crops.py, Sapiens2 COCO17) + feet = Sapiens2 big toe / small toe / heel
         (pseudo labels), weight = Sapiens validity; Halpe 17-19 (head, neck, hip) weight 0 for both.
Fit3D-derived output stays on Home (non-commercial); Exercise3D output is Sapiens2-derived.

usage: halpe_labels.py fit3d --src c2d/fit3d --dst c2d/fit3d26 --subjects s03,s04,s05 [--root ... --smplx ...]
       halpe_labels.py ex3d  --src c2d/ex3d_p1 --dst c2d/ex3d26/ex3d_p1 --ex3d ~/bpt-smpl/ex3d --videos DIR
"""
import argparse, glob, json, os, sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent), str(HERE)]
from build_fit3d_pose2d_crops import SIDE  # noqa: E402
from eval_pose2d import FIT3D_COCO, SAPIENS_HALPE_FEET  # noqa: E402
from eval_pushup_virtual_side import SAPIENS_COCO17  # noqa: E402
from foot_labels import FootMesh  # noqa: E402
from pose_feedback.body.pose2d_data import apply_affine, bbox_from_points, box_to_center_scale, project_fit3d  # noqa: E402


def loose_affine(box):
    c, _ = box_to_center_scale(box)
    k = SIDE / (max(box[2] - box[0], box[3] - box[1]) * 1.6)
    return np.array([[k, 0, SIDE / 2 - k * c[0]], [0, k, SIDE / 2 - k * c[1]]])


def link_images(src, dst, names):
    os.makedirs(dst, exist_ok=True)
    for n in names:
        if not os.path.exists(f'{dst}/{n}'):
            os.symlink(os.path.abspath(f'{src}/{n}'), f'{dst}/{n}')


def fit3d(a):
    mesh = FootMesh(a.smplx)
    for s in a.subjects.split(','):
        d = np.load(f'{a.src}/{s}/labels.npz'); names = [str(n) for n in d['names']]
        kp26 = np.zeros((len(names), 26, 2), np.float32); kp26[:, :17] = d['keypoints']
        w26 = np.zeros((len(names), 26), np.float32); w26[:, 5:17] = 1  # limbs selected by --fit3d-joints in training
        by_video = {}
        for i, n in enumerate(names):
            ex, cam, t = n[:-4].rsplit('_', 2)
            by_video.setdefault((ex, cam), []).append((i, int(t)))
        worst = 0.0
        for (ex, cam), items in sorted(by_video.items()):
            J = np.array(json.load(open(f'{a.root}/train/{s}/joints3d_25/{ex}.json'))['joints3d_25'])
            camj = json.load(open(f'{a.root}/train/{s}/camera_parameters/{cam}/{ex}.json'))
            frames = np.array([t for _, t in items])
            nf = len(json.load(open(f'{a.root}/train/{s}/smplx/{ex}.json'))['transl'])
            V = mesh(f'{a.root}/train/{s}/smplx/{ex}.json', np.minimum(frames, nf - 1))
            for (i, t), v in zip(items, V):
                p = project_fit3d(J[t], camj)
                lm = loose_affine(bbox_from_points(p))
                body = np.zeros((17, 2)); body[list(FIT3D_COCO)] = p[list(FIT3D_COCO.values())]
                worst = max(worst, float(np.abs(apply_affine(lm, body)[5:] - d['keypoints'][i][5:]).max()))
                kp26[i, 20:26] = apply_affine(lm, project_fit3d(v, camj))
                w26[i, 20:26] = 1 if t < nf else 0
        assert worst < 0.05, f'{s}: recomputed crop affine does not reproduce the stored joints ({worst:.3f} px)'
        out = f'{a.dst}/{s}'; link_images(f'{a.src}/{s}', out, names)
        np.savez(f'{out}/labels.npz', names=d['names'], keypoints=kp26, pseudo=np.concatenate([d['pseudo'], np.zeros((len(names), 9, 2), np.float32)], 1),
                 pseudo_conf=np.concatenate([d['pseudo_conf'], np.zeros((len(names), 9), np.float32)], 1), weights=w26)
        print(s, len(names), 'crops; affine check max', round(worst, 4), 'px; feet weight', float(w26[:, 20:].mean()), flush=True)


def ex3d(a):
    import cv2
    d = np.load(f'{a.src}/labels.npz'); names = [str(n) for n in d['names']]
    kp26 = np.zeros((len(names), 26, 2), np.float32); kp26[:, :17] = d['keypoints']
    w26 = np.zeros((len(names), 26), np.float32); w26[:, :17] = d['weights']
    cache = {}
    for i, n in enumerate(names):
        seq, cam, t = n[:-4].rsplit('_', 2); t = int(t)
        if (seq, cam) not in cache:
            lab = np.load(f'{a.ex3d}/exercise3d_labels/{seq}/view/{cam}_pose_2d.npz')
            ex = json.load(open(f'{a.ex3d}/gt.json'))[seq]['exercise']
            cap = cv2.VideoCapture(f'{a.videos}/{ex}/{seq}/{cam}.mp4')
            k = max(cap.get(cv2.CAP_PROP_FRAME_WIDTH), cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) / 1280.0; cap.release()
            ok = lab['valid_mask'] & (lab['confidence'] > 0.5) & lab['target_present'][:, None]
            cache[(seq, cam)] = (lab['keypoints_xy'] * k, ok)
        xy, ok = cache[(seq, cam)]
        lm = loose_affine(bbox_from_points(xy[t][SAPIENS_COCO17], ok[t][SAPIENS_COCO17]))
        assert np.allclose(apply_affine(lm, np.nan_to_num(xy[t][SAPIENS_COCO17])), d['keypoints'][i], atol=0.05), n
        kp26[i, 20:26] = apply_affine(lm, np.nan_to_num(xy[t][SAPIENS_HALPE_FEET]))
        w26[i, 20:26] = ok[t][SAPIENS_HALPE_FEET]
    link_images(a.src, a.dst, names)
    np.savez(f'{a.dst}/labels.npz', names=d['names'], keypoints=kp26, pseudo=kp26, pseudo_conf=w26, weights=w26)
    print(len(names), 'crops; feet weight', float(w26[:, 20:].mean()))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['fit3d', 'ex3d'])
    p.add_argument('--src', required=True); p.add_argument('--dst', required=True); p.add_argument('--subjects', default='s03,s04,s05')
    p.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d')); p.add_argument('--smplx', default=os.path.expanduser('~/models/smplx'))
    p.add_argument('--ex3d', default=os.path.expanduser('~/bpt-smpl/ex3d'))
    p.add_argument('--videos', default=os.path.expanduser('~/workspace/exercise3d-dataset/BPT/synced_video'))
    a = p.parse_args()
    {'fit3d': fit3d, 'ex3d': ex3d}[a.cmd](a)


if __name__ == '__main__':
    main()
