"""COCO train2017 person crops in the Fit3D crop format (labels.npz) for replay during fine-tuning,
so the model keeps COCO's keypoint definitions (Fit3D-only fine-tuning moved hips/ankles to joint
centres and dropped COCO val PCK).

usage: build_coco_pose2d_crops.py --ann person_keypoints_train2017.json --out DIR/coco [--n 6000]
Images are fetched one by one from images.cocodataset.org and only the 320 px crop is kept.
"""

import argparse
import os
import urllib.request

import cv2
import numpy as np

from build_fit3d_pose2d_crops import SIDE
from pose_feedback.body.pose2d_data import apply_affine, box_to_center_scale


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ann', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--n', type=int, default=6000)
    a = ap.parse_args()
    import json
    ann = json.load(open(a.ann))
    imgs = {i['id']: i for i in ann['images']}
    rng = np.random.default_rng(0)
    people = [p for p in ann['annotations'] if p['num_keypoints'] >= 8 and p['area'] >= 64 * 64 and not p['iscrowd']]
    people = [people[i] for i in rng.choice(len(people), min(a.n, len(people)), replace=False)]
    os.makedirs(a.out, exist_ok=True)
    names, kps, vis = [], [], []
    for p in people:
        info = imgs[p['image_id']]
        try:
            data = urllib.request.urlopen(info['coco_url'], timeout=30).read()
        except Exception as e:  # skip unreachable images, keep going
            print('skip', info['file_name'], e)
            continue
        im = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
        x, y, w, h = p['bbox']
        c, _ = box_to_center_scale([x, y, x + w, y + h])
        k = SIDE / (max(w, h) * 1.6)
        lm = np.array([[k, 0, SIDE / 2 - k * c[0]], [0, k, SIDE / 2 - k * c[1]]])
        crop = cv2.warpAffine(im, lm, (SIDE, SIDE), flags=cv2.INTER_AREA)
        name = f"{p['id']}.jpg"
        cv2.imwrite(f'{a.out}/{name}', crop, [cv2.IMWRITE_JPEG_QUALITY, 90])
        kp = np.array(p['keypoints'], float).reshape(17, 3)
        names.append(name); kps.append(apply_affine(lm, kp[:, :2])); vis.append(kp[:, 2] > 0)
    kps, vis = np.array(kps, np.float32), np.array(vis, np.float32)
    # pseudo == ground truth here, so --face/--hips-shoulders pseudo use COCO's own labels
    np.savez(f'{a.out}/labels.npz', names=np.array(names), keypoints=kps, pseudo=kps, pseudo_conf=vis, weights=vis)
    print('saved', len(names))


if __name__ == '__main__':
    main()
