"""Fit3D -> 2D training crops for RTMPose fine-tuning (track C). Mac only; never upload the output.

Per sampled frame: a loose square crop around the projected joints (box padded 1.6, longer side
resized to 320 px, JPEG) + COCO17 keypoints in crop pixels. Body joints 5-16 come from Fit3D mocap
(projected with the distorted camera model). All 17 joints are also stored as pseudo labels from the
current app model (RTMPose-s COCO17) on the standard 1.25 crop, with confidence: face joints 0-4 have
no Fit3D counterpart, and hips/shoulders are Fit3D joint centres (a different definition from COCO's).

--no-pseudo skips the pseudo labels (rtmpose-ft trains only the verified Fit3D joints, D-C-08).

usage: build_fit3d_pose2d_crops.py --subjects s03,s04 --out DIR [--stride 5] [--no-pseudo]
"""

import argparse
import glob
import json
import os

import cv2
import numpy as np

from pose2d_ft_common import crop_box, load_model, predict
from pose_feedback.body.pose2d_data import (
    apply_affine, bbox_from_points, box_to_center_scale, invert_affine, project_fit3d,
)
from eval_pose2d import FIT3D_COCO

EXERCISES = ('squat', 'pushup', 'diamond_pushup', 'barbell_row', 'barbell_dead_row')
SIDE = 320


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=os.environ.get('BPT_FIT3D'))
    ap.add_argument('--subjects', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--stride', type=int, default=5)
    ap.add_argument('--no-pseudo', action='store_true')
    a = ap.parse_args()
    model = None if a.no_pseudo else load_model('coco17')
    for subj in a.subjects.split(','):
        out = f'{a.out}/{subj}'
        if os.path.exists(f'{out}/labels.npz'):
            continue
        os.makedirs(out, exist_ok=True)
        names, kps, pseudo, pseudo_conf = [], [], [], []
        for video in sorted(glob.glob(f'{a.root}/{subj}/videos/*/*.mp4')):
            cam, ex = video.split('/')[-2], os.path.basename(video)[:-4]
            jf, cf = f'{a.root}/{subj}/joints3d_25/{ex}', f'{a.root}/{subj}/camera_parameters/{cam}/{ex}.json'
            jf = next((f for f in (jf + '.npy', jf + '.json') if os.path.exists(f)), None)
            if ex not in EXERCISES or not (jf and os.path.exists(cf)):
                continue
            J = np.load(jf) if jf.endswith('.npy') else np.array(json.load(open(jf))['joints3d_25'])
            camera = json.load(open(cf))
            cap = cv2.VideoCapture(video)
            std_crops, std_back, loose = [], [], []
            for t in range(len(J)):
                ok, fr = cap.read()
                if not ok:
                    break
                if t % a.stride:
                    continue
                rgb = cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)
                p = project_fit3d(J[t], camera)
                box = bbox_from_points(p)
                c, s = box_to_center_scale(box)
                cr, m = crop_box(rgb, c, s)
                std_crops.append(cr); std_back.append(invert_affine(m))
                side = max(box[2] - box[0], box[3] - box[1]) * 1.6
                k = SIDE / side
                lm = np.array([[k, 0, SIDE / 2 - k * c[0]], [0, k, SIDE / 2 - k * c[1]]])
                img = cv2.warpAffine(rgb, lm, (SIDE, SIDE), flags=cv2.INTER_AREA, borderValue=(0, 0, 0))
                name = f'{ex}_{cam}_{t:05d}.jpg'
                cv2.imwrite(f'{out}/{name}', cv2.cvtColor(img, cv2.COLOR_RGB2BGR), [cv2.IMWRITE_JPEG_QUALITY, 90])
                body = np.zeros((17, 2))
                body[list(FIT3D_COCO)] = p[list(FIT3D_COCO.values())]
                names.append(name); kps.append(apply_affine(lm, body)); loose.append(lm)
            cap.release()
            if not std_crops:
                continue
            if model is None:
                pseudo += [np.zeros((17, 2))] * len(std_crops); pseudo_conf += [np.zeros(17)] * len(std_crops)
            else:
                pk, pc = predict(model, std_crops)
                for b, q, cf_, lm in zip(std_back, pk, pc, loose):
                    pseudo.append(apply_affine(lm, apply_affine(b, q))); pseudo_conf.append(cf_)
            print(subj, ex, cam, len(std_crops), flush=True)
        np.savez(f'{out}/labels.npz', names=np.array(names), keypoints=np.array(kps, np.float32),
                 pseudo=np.array(pseudo, np.float32), pseudo_conf=np.array(pseudo_conf, np.float32))


if __name__ == '__main__':
    main()
