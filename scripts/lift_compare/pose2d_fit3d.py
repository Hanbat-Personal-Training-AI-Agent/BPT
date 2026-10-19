"""lift-compare stage 1 (Home, bpt-mmpose, GPU): experiment A 2D on Fit3D.

Per video, at the app's 30 fps picks of the 50 fps original: RTMDet-m person box (per frame, label person, score >= 0.2,
largest score x area; a frame with no box keeps the previous one and is flagged), then RTMPose-m COCO17 and
RTMPose-m Halpe26 top-down on that SAME box (mmpose inference_topdown, xyxy). Fit3D never leaves Home; outputs stay
in the run folder (licence: aggregates only in git).

usage: pose2d_fit3d.py --root ~/datasets/fit3d --out RUN/pose2d --subjects s03,... [--exercises squat,pushup,barbell_row]
"""
import argparse, glob, os, sys
import numpy as np

APP_FPS = 30
CFG_DET = os.path.expanduser('~/miniconda3/envs/bpt-mmpose/lib/python3.10/site-packages/mmdet/.mim/configs/rtmdet/rtmdet_m_8xb32-300e_coco.py')


def pick_frames(n50):
    return np.round(np.arange(0, n50, 50 / APP_FPS)).astype(int)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', required=True); p.add_argument('--out', required=True)
    p.add_argument('--subjects', type=lambda s: s.split(','), required=True)
    p.add_argument('--exercises', type=lambda s: s.split(','), default=['squat', 'pushup', 'barbell_row'])
    p.add_argument('--det-ckpt', required=True)
    p.add_argument('--coco-cfg', required=True); p.add_argument('--coco-ckpt', required=True)
    p.add_argument('--halpe-cfg', required=True); p.add_argument('--halpe-ckpt', required=True)
    a = p.parse_args()
    import cv2
    from mmdet.apis import init_detector, inference_detector
    from mmpose.apis import init_model, inference_topdown
    from mmpose.utils import adapt_mmdet_pipeline
    det = init_detector(CFG_DET, a.det_ckpt, device='cuda:0'); det.cfg = adapt_mmdet_pipeline(det.cfg)
    poses = {'coco': init_model(a.coco_cfg, a.coco_ckpt, device='cuda:0'),
             'halpe': init_model(a.halpe_cfg, a.halpe_ckpt, device='cuda:0')}
    for subj in a.subjects:
        for v in sorted(glob.glob(f'{a.root}/train/{subj}/videos/*/*.mp4')):
            cam, ex = v.split('/')[-2], os.path.basename(v)[:-4]
            if ex not in a.exercises: continue
            out = f'{a.out}/{subj}_{cam}_{ex}.npz'
            if os.path.exists(out): continue
            cap = cv2.VideoCapture(v); n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            want = set(pick_frames(n).tolist()); pick, boxes, has, kp = [], [], [], {k: [] for k in poses}
            prev, i = None, 0
            while True:
                ok, img = cap.read()
                if not ok: break
                wh = (img.shape[1], img.shape[0])
                if i in want:
                    r = inference_detector(det, img).pred_instances
                    keep = (r.labels == 0) & (r.scores >= 0.2)
                    b, s = r.bboxes[keep].cpu().numpy(), r.scores[keep].cpu().numpy()
                    if len(b):
                        prev = b[np.argmax(s * (b[:, 2] - b[:, 0]) * (b[:, 3] - b[:, 1]))]; has.append(True)
                    else:
                        has.append(False)
                    box = prev if prev is not None else np.array([0, 0, img.shape[1], img.shape[0]], float)
                    boxes.append(box); pick.append(i)
                    for k, m in poses.items():
                        res = inference_topdown(m, img, bboxes=box[None], bbox_format='xyxy')[0].pred_instances
                        kp[k].append(np.concatenate([res.keypoints[0], res.keypoint_scores[0][:, None]], 1))
                i += 1
            os.makedirs(a.out, exist_ok=True)
            np.savez(out + '.tmp.npz', pick=np.array(pick), box=np.array(boxes, np.float32), has_det=np.array(has),
                     coco=np.array(kp['coco'], np.float32), halpe=np.array(kp['halpe'], np.float32),
                     wh=np.array(wh))
            os.replace(out + '.tmp.npz', out)
            print(subj, cam, ex, len(pick), f'nodet={len(has) - sum(has)}', flush=True)


if __name__ == '__main__':
    main()
