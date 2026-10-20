"""finetune3 2D -> 3D effect, experiment A (same person box, 2D model only; Home, bpt-mmpose, GPU lock).

Boxes = lift-compare stage-1 npz (RTMDet-m person box per frame at the app's 30 fps picks of the 50 fps Fit3D video,
~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d/<subj>_<cam>_<exercise>.npz). Every RTMPose model (m COCO17 config,
original or fine-tuned state_dict) runs on the SAME boxes through the same batched top-down crop (mmpose convention,
padding 1.25, pose2d_ft_common.crop_box / predict) -> COCO17 px -> xs_data.real_seq_from (app COCO->H36M mapping +
person_crop) -> kind-R sequences npz per 2D model for xs_eval.py (mocap target, L=5 row). Fit3D stays on Home.

usage: rtm_lift_effect.py --pose2d DIR --subjects s07,s08,s09,s10,s11 --models tag=VARIANT[:CKPT],... --out-dir DIR
       (VARIANT = m_coco17 | m_halpe26; Halpe26 feeds XS its COCO-shared joints 0-16; --pose2d may also be a
        det_boxes_fit3d.py folder: same npz layout with pick / box)
"""
import argparse, json, os, sys
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent), str(HERE)]
from pose2d_ft_common import crop_box, load_model, predict  # noqa: E402
from pose_feedback.body.pose2d_data import apply_affine, box_to_center_scale, invert_affine  # noqa: E402
from xs_data import fit3d_seq, real_seq_from, save  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--pose2d', required=True); p.add_argument('--subjects', required=True)
    p.add_argument('--fit3d', default=os.path.expanduser('~/datasets/fit3d'))
    p.add_argument('--exercises', default='squat,pushup,barbell_row')
    p.add_argument('--models', required=True); p.add_argument('--out-dir', required=True)
    a = p.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)
    models = [(t, spec) for t, spec in (kv.split('=', 1) for kv in a.models.split(','))]
    nets = {t: load_model(spec.partition(':')[0] or 'm_coco17', spec.partition(':')[2] or None) for t, spec in models}
    seqs = {t: [] for t, _ in models}
    for s in a.subjects.split(','):
        for ex in a.exercises.split(','):
            d = fit3d_seq(a.fit3d, s, ex)
            if d is None:
                continue
            P, cams, ann = d
            for c in sorted(cams):
                f = f'{a.pose2d}/{s}_{c}_{ex}.npz'
                if not os.path.exists(f):
                    continue
                z = np.load(f); pick, box = z['pick'], z['box']
                cap = cv2.VideoCapture(f'{a.fit3d}/train/{s}/videos/{c}/{ex}.mp4')
                want, crops, back, i = set(pick.tolist()), [], [], 0
                while len(crops) < len(pick):
                    ok, img = cap.read()
                    if not ok:
                        break
                    if i in want:
                        k = len(crops)
                        cr, m = crop_box(cv2.cvtColor(img, cv2.COLOR_BGR2RGB), *box_to_center_scale(box[k]))
                        crops.append(cr); back.append(invert_affine(m))
                    i += 1
                cap.release()
                n = int(min(len(crops), np.searchsorted(pick, len(P))))  # frames with mocap
                pk, crops, back = pick[:n], crops[:n], back[:n]
                for t, _ in models:
                    kp, conf = predict(nets[t], crops)
                    K = np.concatenate([np.array([apply_affine(b, q) for b, q in zip(back, kp[:, :17])]), conf[:, :17, None]], -1)
                    seqs[t].append(real_seq_from(K, pk, s, ex, c, P, cams, ann))
                print(s, ex, c, n, flush=True)
    for t, _ in models:
        save(f'{a.out_dir}/R_expA_{t}.npz', seqs[t], a)


if __name__ == '__main__':
    main()
