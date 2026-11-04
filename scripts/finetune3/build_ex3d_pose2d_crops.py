"""Exercise3D P1 -> 2D training crops in the build_fit3d_pose2d_crops.py format (labels.npz), Home only.

Labels = Sapiens2-5B COCO17 subset (pseudo labels, NOT ground truth; user-approved for training 2026-10-20, D-F3-02),
scaled from the 1280-long-side working frame to the video; weight 1 where valid, confidence > 0.5 and the target is
present. Only P1 sequences (D-B-01 person split); P2 / P3 are refused. Frames every --stride, loose square crop
(keypoint box x 1.6, 320 px), keypoints in crop pixels. Never upload the output; never open the images with Read.

usage: build_ex3d_pose2d_crops.py --ex3d ~/bpt-smpl/ex3d --videos ~/workspace/exercise3d-dataset/BPT/synced_video --out DIR
"""
import argparse, json, os, sys
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent), str(HERE)]
from build_fit3d_pose2d_crops import SIDE  # noqa: E402
from eval_pushup_virtual_side import SAPIENS_COCO17  # noqa: E402
from pose_feedback.body.pose2d_data import apply_affine, bbox_from_points, box_to_center_scale  # noqa: E402
from xs_data import HELD_E3D, P1  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ex3d', required=True); ap.add_argument('--videos', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--seqs', default=','.join(P1)); ap.add_argument('--stride', type=int, default=3)
    a = ap.parse_args()
    gt = json.load(open(f'{a.ex3d}/gt.json'))
    out = f'{a.out}/ex3d_p1'
    os.makedirs(out, exist_ok=True)
    names, kps, wts = [], [], []
    for seq in a.seqs.split(','):
        assert seq not in HELD_E3D, f'{seq} is held out (P2/P3)'
        ex = gt[seq]['exercise']
        for cam in ('cam1', 'cam2', 'cam3'):
            lab = np.load(f'{a.ex3d}/exercise3d_labels/{seq}/view/{cam}_pose_2d.npz')
            cap = cv2.VideoCapture(f'{a.videos}/{ex}/{seq}/{cam}.mp4')
            w, h = cap.get(cv2.CAP_PROP_FRAME_WIDTH), cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
            xy = lab['keypoints_xy'][:, SAPIENS_COCO17] * (max(w, h) / 1280.0)
            ok = lab['valid_mask'][:, SAPIENS_COCO17] & (lab['confidence'][:, SAPIENS_COCO17] > 0.5) & lab['target_present'][:, None]
            n = 0
            for t in range(len(xy)):
                good, fr = cap.read()
                if not good:
                    break
                if t % a.stride or ok[t, 5:].sum() < 8:
                    continue
                box = bbox_from_points(xy[t], ok[t])
                c, _ = box_to_center_scale(box)
                k = SIDE / (max(box[2] - box[0], box[3] - box[1]) * 1.6)
                lm = np.array([[k, 0, SIDE / 2 - k * c[0]], [0, k, SIDE / 2 - k * c[1]]])
                img = cv2.warpAffine(fr, lm, (SIDE, SIDE), flags=cv2.INTER_AREA, borderValue=(0, 0, 0))
                name = f'{seq}_{cam}_{t:05d}.jpg'
                cv2.imwrite(f'{out}/{name}', img, [cv2.IMWRITE_JPEG_QUALITY, 90])
                names.append(name); kps.append(apply_affine(lm, np.nan_to_num(xy[t]))); wts.append(ok[t])
                n += 1
            cap.release()
            print(seq, cam, n, flush=True)
    kps, wts = np.array(kps, np.float32), np.array(wts, np.float32)
    # pseudo = the label itself so that train_pose2d_ft --face pseudo / --hips-shoulders pseudo keep these joints
    np.savez(f'{out}/labels.npz', names=np.array(names), keypoints=kps, pseudo=kps, pseudo_conf=wts, weights=wts)
    print('saved', len(names))


if __name__ == '__main__':
    main()
