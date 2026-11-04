"""Person boxes on Fit3D videos with any RTMDet checkpoint, in the lift-compare stage-1 rule and npz layout (Home, GPU lock):
at the app's 30 fps picks of the 50 fps video, persons with score >= 0.2, the box with the largest score x area; a frame
without one keeps the previous box (has_det False). Output <out>/<subj>_<cam>_<exercise>.npz {pick, box, has_det, wh} feeds
rtm_lift_effect.py --pose2d (new det -> 2D -> XS, D-F3-06 E3). Fit3D stays on Home.

usage: det_boxes_fit3d.py --ckpt CKPT [--cfg CFG] --subjects s07,... --out DIR [--exercises squat,pushup,barbell_row]
"""
import argparse, glob, os

import cv2
import numpy as np
from mmdet.apis import inference_detector, init_detector

CFG = os.path.expanduser('~/miniconda3/envs/bpt-mmpose/lib/python3.10/site-packages/mmdet/.mim/configs/rtmdet/rtmdet_m_8xb32-300e_coco.py')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--ckpt', required=True); p.add_argument('--cfg', default=CFG)
    p.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d')); p.add_argument('--subjects', required=True)
    p.add_argument('--exercises', default='squat,pushup,barbell_row'); p.add_argument('--out', required=True)
    a = p.parse_args()
    det = init_detector(a.cfg, a.ckpt, device='cuda:0')
    os.makedirs(a.out, exist_ok=True)
    for s in a.subjects.split(','):
        for v in sorted(glob.glob(f'{a.root}/train/{s}/videos/*/*.mp4')):
            cam, ex = v.split('/')[-2], os.path.basename(v)[:-4]
            out = f'{a.out}/{s}_{cam}_{ex}.npz'
            if ex not in a.exercises.split(',') or os.path.exists(out):
                continue
            cap = cv2.VideoCapture(v); n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            want = set(np.round(np.arange(0, n, 50 / 30)).astype(int).tolist())
            pick, boxes, has, prev, i, wh = [], [], [], None, 0, None
            while True:
                ok, img = cap.read()
                if not ok:
                    break
                wh = (img.shape[1], img.shape[0])
                if i in want:
                    r = inference_detector(det, img).pred_instances
                    keep = (r.labels == 0) & (r.scores >= 0.2)
                    b, sc = r.bboxes[keep].cpu().numpy(), r.scores[keep].cpu().numpy()
                    if len(b):
                        prev = b[np.argmax(sc * (b[:, 2] - b[:, 0]) * (b[:, 3] - b[:, 1]))]; has.append(True)
                    else:
                        has.append(False)
                    boxes.append(prev if prev is not None else np.array([0, 0, img.shape[1], img.shape[0]], float)); pick.append(i)
                i += 1
            np.savez(out + '.tmp.npz', pick=np.array(pick), box=np.array(boxes, np.float32), has_det=np.array(has), wh=np.array(wh))
            os.replace(out + '.tmp.npz', out)
            print(s, cam, ex, len(pick), 'nodet', len(has) - sum(has), flush=True)


if __name__ == '__main__':
    main()
