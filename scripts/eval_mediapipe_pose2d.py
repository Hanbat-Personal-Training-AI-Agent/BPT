"""MediaPipe Pose Landmarker vs the track C 2D metric (PCK@0.05 body12 on Exercise3D side views, D-C-07).

Same frames and reference as `eval_pose2d.py --dataset ex3d` (every 15th labelled frame, Sapiens2-5B pseudo labels,
side cams <= 40 deg, box = longer side of the label box), in two steps (pack imports eval_pose2d, so torch;
eval needs mediapipe: bpt-ft on the Mac or bpt-home on Home):
  pack  (Mac, bpt-ft)    eval_mediapipe_pose2d.py pack OUT.npz      frames at 720x1280 (the label pixels) + labels
  eval  (bpt-ft|bpt-home) eval_mediapipe_pose2d.py eval OUT.npz --model pose_landmarker_full.task --out res.json
  rtmpose (bpt-coreml)    eval_mediapipe_pose2d.py rtmpose OUT.npz --model rtmpose_m_forward.mlpackage --out res.json
eval runs IMAGE mode twice: on the whole frame (MediaPipe's own person detector, like the app would) and on the
label-box crop (the same oracle crop RTMPose gets in eval_pose2d's "crop" rows). A missed person counts as wrong.
rtmpose runs the app's Core ML RTMPose on that label-box crop of the same packed frames (reference row).
"""

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'scripts'))
from pose_feedback.body.pose2d_data import bbox_from_points, box_to_center_scale, crop_affine, pck  # noqa: E402

BLAZEPOSE_COCO17 = [0, 2, 5, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]  # same map as MediaPipeBench.swift
BODY12 = list(range(5, 17))
CROP_SCALE = 2  # crop rendered at 384x512 (2x RTMPose's 192x256) so MediaPipe's 256x256 input is not upsampled


def pack(out):
    from eval_pose2d import EX3D_LABELS, EX3D_VIDEOS, GT_JSON, SAPIENS_COCO17, read_frames
    gt = json.load(open(GT_JSON))
    data = {k: [] for k in ('jpg', 'gt', 'valid', 'box', 'video', 'exercise')}
    for seq, g in sorted(gt.items()):
        for cam, view in g['views'].items():
            if round(view['angle_deg']) > 40:
                continue
            lab = np.load(EX3D_LABELS / seq / 'view' / f'{cam}_pose_2d.npz')
            idx = [t for t in range(0, len(lab['frame_index']), 15) if lab['target_present'][t]]
            frames = read_frames(EX3D_VIDEOS / g['exercise'] / seq / f'{cam}.mp4', [int(lab['frame_index'][t]) for t in idx])
            for t in idx:
                fr = frames.get(int(lab['frame_index'][t]))
                if fr is None:
                    continue
                s = 1280.0 / max(fr.shape[:2])  # labels are in pixels of the 1280-long-side copy
                fr = cv2.resize(fr, (round(fr.shape[1] * s), round(fr.shape[0] * s)), interpolation=cv2.INTER_AREA)
                k = lab['keypoints_xy'][t][SAPIENS_COCO17]
                v = lab['valid_mask'][t][SAPIENS_COCO17] & (lab['confidence'][t][SAPIENS_COCO17] > 0.5)
                data['jpg'].append(np.frombuffer(cv2.imencode('.jpg', cv2.cvtColor(fr, cv2.COLOR_RGB2BGR),
                                                              [cv2.IMWRITE_JPEG_QUALITY, 92])[1], np.uint8))
                data['gt'].append(k); data['valid'].append(v); data['box'].append(bbox_from_points(k[5:], v[5:]))
                data['video'].append(f'{seq}/{cam}'); data['exercise'].append(g['exercise'])
    jpg = np.empty(len(data['jpg']), object)
    jpg[:] = data['jpg']
    np.savez(out, **{k: np.array(v) for k, v in data.items() if k != 'jpg'}, jpg=jpg)
    print(out, len(jpg), 'frames from', len(set(data['video'])), 'videos')


def to_coco17(landmarks, back):
    """33 normalized BlazePose landmarks (in the image MediaPipe saw) -> COCO-17 frame pixels via the 2x3 `back`."""
    p = np.array([[landmarks[i].x, landmarks[i].y, 1.0] for i in BLAZEPOSE_COCO17])
    return p @ back.T


def evaluate(packed, model, out):
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision
    d = np.load(packed, allow_pickle=True)
    landmarker = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=model), running_mode=vision.RunningMode.IMAGE, num_poses=1))
    preds = {'frame': [], 'crop': []}
    for jpg, box in zip(d['jpg'], d['box']):
        rgb = cv2.cvtColor(cv2.imdecode(jpg, cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
        h, w = rgb.shape[:2]
        m = crop_affine(*box_to_center_scale(box)) * CROP_SCALE
        cw, ch = 192 * CROP_SCALE, 256 * CROP_SCALE
        crop = cv2.warpAffine(rgb, m, (cw, ch), flags=cv2.INTER_LINEAR)
        inv = cv2.invertAffineTransform(m)
        for mode, image, back in (('frame', rgb, np.array([[w, 0, 0], [0, h, 0]], float)),
                                  ('crop', crop, inv @ np.diag([cw, ch, 1.0]))):
            r = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(image)))
            preds[mode].append(to_coco17(r.pose_landmarks[0], back) if r.pose_landmarks else np.full((17, 2), 1e9))
    score(d, preds, model, out)


def rtmpose(packed, model, out):
    import coremltools as ct
    from pose_feedback.body.pose2d_data import apply_affine, decode_simcc, invert_affine
    d = np.load(packed, allow_pickle=True)
    net = ct.models.MLModel(model)
    mean, std = np.array([123.675, 116.28, 103.53], np.float32), np.array([58.395, 57.12, 57.375], np.float32)
    preds = []
    for jpg, box in zip(d['jpg'], d['box']):
        rgb = cv2.cvtColor(cv2.imdecode(jpg, cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
        m = crop_affine(*box_to_center_scale(box))
        x = (cv2.warpAffine(rgb, m, (192, 256), flags=cv2.INTER_LINEAR).astype(np.float32) - mean) / std
        o = net.predict({'input_image': x.transpose(2, 0, 1)[None]})
        k, _ = decode_simcc(o['simcc_x'][0], o['simcc_y'][0])
        preds.append(apply_affine(invert_affine(m), k[:17]))
    score(d, {'crop': preds}, model, out)


def score(d, preds, model, out):
    res = {'model': Path(model).stem, 'n_frames': int(len(d['gt'])), 'n_videos': int(len(set(d['video'])))}
    size = np.max(d['box'][:, 2:] - d['box'][:, :2], axis=1)
    for mode, p in preds.items():
        p = np.array(p)
        for ex in ('all', 'squat', 'pushup', 'barbellrow'):
            sel = np.ones(len(p), bool) if ex == 'all' else d['exercise'] == ex
            res[f'{mode}/{ex}'] = {'n': int(sel.sum()), 'detected': round(float((p[sel, 0, 0] < 1e8).mean()), 4),
                                   'pck05_body12': round(pck(p[sel][:, BODY12], d['gt'][sel][:, BODY12],
                                                             d['valid'][sel][:, BODY12], size[sel]), 4)}
    json.dump(res, open(out, 'w'), indent=1)
    print(json.dumps(res))


def _check():
    """Mapping self-check: identity landmarks through the frame transform land on COCO joints in pixels."""
    class L:
        def __init__(self, i): self.x, self.y = i / 100, i / 200
    k = to_coco17([L(i) for i in range(33)], np.array([[720, 0, 0], [0, 1280, 0]], float))
    assert np.allclose(k[5], [11 / 100 * 720, 11 / 200 * 1280]) and np.allclose(k[16], [28 / 100 * 720, 28 / 200 * 1280])


if __name__ == '__main__':
    _check()
    ap = argparse.ArgumentParser()
    ap.add_argument('step', choices=('pack', 'eval', 'rtmpose'))
    ap.add_argument('packed')
    ap.add_argument('--model')
    ap.add_argument('--out')
    a = ap.parse_args()
    {'pack': lambda: pack(a.packed), 'eval': lambda: evaluate(a.packed, a.model, a.out),
     'rtmpose': lambda: rtmpose(a.packed, a.model, a.out)}[a.step]()
