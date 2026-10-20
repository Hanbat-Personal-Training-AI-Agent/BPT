"""Held-out 2D accuracy of RTMPose candidates (track C).

PCK@a = share of keypoints whose prediction lies within a x (longer side of the person box) of the
reference. Reported per joint group. Reference per dataset:
  coco   COCO val2017 manual labels (subset), person-box crop (top-down, padding 1.25)
  ex3d   Exercise3D Sapiens2-5B 2D labels (pseudo labels, NOT ground truth), side cams (<=40 deg)
         and the rest; both the app's whole-frame stretch input and a person-box crop
  fit3d  Fit3D mocap joints projected with the camera (held-out subjects only); body-joint
         definitions differ from COCO (3D joint centres), so hips/shoulders carry a constant offset

usage: eval_pose2d.py --dataset coco|ex3d|fit3d --model VARIANT[:CHECKPOINT] [--name NAME] --out JSON
Fit3D frames stay on the Mac (licence); only aggregate numbers are written.
"""

import argparse
import glob
import json
import os
import urllib.request

import cv2
import numpy as np

from pose2d_ft_common import ROOT, crop_box, load_model, predict, stretch
from pose_feedback.body.pose2d_data import (
    INPUT_H, INPUT_W, apply_affine, bbox_from_points, box_to_center_scale, invert_affine, pck, project_fit3d,
)

SCRATCH = os.environ.get('BPT_C2D', '/private/tmp/bpt-c2d')
MAIN = ROOT if (ROOT / 'outputs/exercise3d_labels').exists() else ROOT.parents[2]  # worktree -> main checkout
EX3D_LABELS = os.environ.get('BPT_EX3D_LABELS', MAIN / 'outputs/exercise3d_labels')  # finetune3: Home paths via env
EX3D_VIDEOS = os.environ.get('BPT_EX3D_VIDEOS', MAIN / 'outputs/exercise3d_synced')
GT_JSON = os.environ.get('BPT_EX3D_GT', MAIN / 'outputs/rep_validation/gt.json')
EX3D_MODES = tuple(os.environ.get('BPT_EX3D_MODES', 'stretch,crop').split(','))
EX3D_HELD = {'squat_0002', 'barbellrow_0003', 'barbellrow_0001'}  # P2 / P3 (D-B-01); the rest is P1
LR_PAIRS = {'elbow': (7, 8), 'wrist': (9, 10), 'knee': (13, 14), 'ankle': (15, 16)}
SAPIENS_COCO17 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 62, 41, 9, 10, 11, 12, 13, 14]
SAPIENS_HALPE_FEET = [15, 18, 16, 19, 17, 20]  # l/r big toe, l/r small toe, l/r heel (Halpe 20..25 order)
GROUPS = {'face': [0, 1, 2, 3, 4], 'shoulder': [5, 6], 'elbow': [7, 8], 'wrist': [9, 10], 'hip': [11, 12],
          'knee': [13, 14], 'ankle': [15, 16], 'body12': list(range(5, 17)), 'limbs8': [7, 8, 9, 10, 13, 14, 15, 16]}
FIT3D_EXERCISES = ('squat', 'pushup', 'diamond_pushup', 'barbell_row', 'barbell_dead_row')  # the app's exercises + close variants
FIT3D_COCO = {5: 11, 6: 14, 7: 12, 8: 15, 9: 13, 10: 16, 11: 1, 12: 4, 13: 2, 14: 5, 15: 3, 16: 6}  # coco <- fit3d


def summarize(pred, gt, valid, box, extra=None):
    out = {'n_instances': int(len(pred))}
    for alpha in (0.05, 0.1):
        for g, idx in GROUPS.items():
            v = valid[:, idx]
            if v.any():
                out[f'pck{int(alpha * 100):02d}_{g}'] = round(pck(pred[:, idx], gt[:, idx], v, box, alpha), 4)
    d = np.linalg.norm(pred - gt, axis=-1) / box[:, None]
    out['mean_err_body12_pct_box'] = round(float(d[:, 5:][valid[:, 5:]].mean() * 100), 3)
    for g in ('elbow', 'wrist', 'hip', 'knee', 'ankle', 'shoulder', 'limbs8'):  # mean error per group (% box)
        v = valid[:, GROUPS[g]]
        if v.any():
            out[f'err_{g}_pct_box'] = round(float(d[:, GROUPS[g]][v].mean() * 100), 3)
    # left/right swap: both joints of a pair closer to the other side's reference than to their own
    sw = []
    for g, (l, r) in LR_PAIRS.items():
        ok = valid[:, l] & valid[:, r]
        cross = (np.linalg.norm(pred[:, l] - gt[:, r], axis=-1) < np.linalg.norm(pred[:, l] - gt[:, l], axis=-1)) & \
                (np.linalg.norm(pred[:, r] - gt[:, l], axis=-1) < np.linalg.norm(pred[:, r] - gt[:, r], axis=-1))
        anyc = (np.linalg.norm(pred[:, l] - gt[:, r], axis=-1) < np.linalg.norm(pred[:, l] - gt[:, l], axis=-1)) | \
               (np.linalg.norm(pred[:, r] - gt[:, l], axis=-1) < np.linalg.norm(pred[:, r] - gt[:, r], axis=-1))
        if ok.any():  # swap = both joints crossed; cross = at least one (collapse onto one side included)
            out[f'swap_{g}'] = round(float(cross[ok].mean()), 5); sw.append(cross[ok])
            out[f'cross_{g}'] = round(float(anyc[ok].mean()), 5)
    if sw:
        out['swap_limbs8'] = round(float(np.concatenate(sw).mean()), 5)
    if extra:
        out.update(extra)
    return out


def coco(model, limit=500):
    ann = json.load(open(f'{SCRATCH}/person_keypoints_val2017.json'))
    imgs = {i['id']: i for i in ann['images']}
    people = sorted((a for a in ann['annotations'] if a['num_keypoints'] >= 8 and a['area'] >= 64 * 64 and not a['iscrowd']),
                    key=lambda a: a['id'])[:limit]
    crops, gts, valid, boxes, ms = [], [], [], [], []
    os.makedirs(f'{SCRATCH}/coco_val', exist_ok=True)
    for a in people:
        name = imgs[a['image_id']]['file_name']
        path = f'{SCRATCH}/coco_val/{name}'
        if not os.path.exists(path):
            urllib.request.urlretrieve(f'http://images.cocodataset.org/val2017/{name}', path)
        im = cv2.cvtColor(cv2.imread(path), cv2.COLOR_BGR2RGB)
        x, y, w, h = a['bbox']
        c, s = box_to_center_scale([x, y, x + w, y + h])
        cr, m = crop_box(im, c, s)
        k = np.array(a['keypoints'], float).reshape(17, 3)
        crops.append(cr); ms.append(m); gts.append(k[:, :2]); valid.append(k[:, 2] > 0); boxes.append(max(w, h))
    kp, conf = predict(model, crops)
    pred = np.array([apply_affine(invert_affine(m), p) for m, p in zip(ms, kp[:, :17])])
    return summarize(pred, np.array(gts), np.array(valid), np.array(boxes), conf_stats(conf[:, :17]))


def conf_stats(conf):
    return {'conf_p10': round(float(np.percentile(conf, 10)), 3), 'conf_p50': round(float(np.median(conf)), 3)}


def read_frames(path, indices):
    """Sequential grab (seeking re-decodes from the last keyframe every time, ~10x slower)."""
    cap = cv2.VideoCapture(str(path))
    want, out, t = set(indices), {}, 0
    while want and t <= max(want):
        if not cap.grab():
            break
        if t in want:
            ok, fr = cap.retrieve()
            if ok:
                out[t] = cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)
        t += 1
    cap.release()
    return out


def ex3d(model, stride=15):
    gt = json.load(open(GT_JSON))
    rows = {}
    for seq, g in sorted(gt.items()):
        for cam, view in g['views'].items():
            lab = np.load(EX3D_LABELS / seq / 'view' / f'{cam}_pose_2d.npz')
            video = EX3D_VIDEOS / g['exercise'] / seq / f'{cam}.mp4'
            idx = [int(t) for t in range(0, len(lab['frame_index']), stride) if lab['target_present'][t]]
            frames = read_frames(video, [int(lab['frame_index'][t]) for t in idx])
            for mode in EX3D_MODES:
                crops, back, gts, valid, boxes, feet = [], [], [], [], [], []
                for t in idx:
                    fr = frames.get(int(lab['frame_index'][t]))
                    if fr is None:
                        continue
                    # labels are in pixels of a 1280-long-side copy (Sapiens run on 720x1280): similarity fit
                    # to app keypoints over all 39 videos gives scale 1.40-1.56 around 1920/1280 = 1.5, offset ~0
                    lab_scale = max(fr.shape[:2]) / 1280.0
                    k = lab['keypoints_xy'][t][SAPIENS_COCO17] * lab_scale
                    v = lab['valid_mask'][t][SAPIENS_COCO17] & (lab['confidence'][t][SAPIENS_COCO17] > 0.5)
                    box = bbox_from_points(k[5:], v[5:])
                    if mode == 'stretch':
                        h, w = fr.shape[:2]
                        crops.append(stretch(fr))
                        back.append(np.array([[w / INPUT_W, 0, 0], [0, h / INPUT_H, 0]]))
                    else:
                        cr, m = crop_box(fr, *box_to_center_scale(box))
                        crops.append(cr); back.append(invert_affine(m))
                    gts.append(k); valid.append(v); boxes.append(max(box[2] - box[0], box[3] - box[1]))
                    feet.append(lab['keypoints_xy'][t][SAPIENS_HALPE_FEET] * lab_scale)
                kp, conf = predict(model, crops)
                full = np.array([apply_affine(b, p) for b, p in zip(back, kp)])
                extra = conf_stats(conf[:, :17])
                if full.shape[1] == 26:  # Halpe26 heels/toes vs Sapiens feet
                    fe = np.array(feet)
                    d = np.linalg.norm(full[:, 20:] - fe, axis=-1) / np.array(boxes)[:, None]
                    extra['pck05_heel'] = round(float((d[:, 4:] < 0.05).mean()), 4)
                    extra['pck05_toes'] = round(float((d[:, :4] < 0.05).mean()), 4)
                rows[f'{seq}/{cam}/{mode}'] = dict(summarize(full[:, :17], np.array(gts), np.array(valid), np.array(boxes), extra),
                                                   exercise=g['exercise'], angle=view['angle_deg'], mode=mode,
                                                   split='heldout' if seq in EX3D_HELD else 'P1')
    agg = {}
    for mode in EX3D_MODES:
        for side in ('side40', 'other'):
            sel = [r for r in rows.values() if r['mode'] == mode and (round(r['angle']) <= 40) == (side == 'side40')]
            for ex in ('all', 'squat', 'pushup', 'barbellrow'):
                for split in ('all', 'heldout', 'P1'):
                    s = [r for r in sel if (ex == 'all' or r['exercise'] == ex) and (split == 'all' or r['split'] == split)]
                    if s:
                        agg[f'{mode}/{side}/{ex}' + ('' if split == 'all' else f'/{split}')] = weighted(s)
    return {'aggregate': agg, 'per_video': rows}


def weighted(rows):
    keys = sorted({k for r in rows for k in r if k.startswith(('pck', 'mean_err', 'conf', 'err_', 'swap_'))})
    n = np.array([r['n_instances'] for r in rows], float)
    return {'n_instances': int(n.sum()), **{k: round(float(np.average([r.get(k, np.nan) for r in rows], weights=n)), 4) for k in keys}}


def fit3d(model, subjects, stride=10):
    root = os.environ.get('BPT_FIT3D', '/private/tmp/claude-501/-Users-6-month-github-06-month-hanbat-repositories-BPT/'
                          'd083b446-4e06-45ed-8204-8c6e9f22bd1c/scratchpad/d3/fit3d/train')
    rows = {}
    for subj in subjects:
        for video in sorted(glob.glob(f'{root}/{subj}/videos/*/*.mp4')):
            cam, ex = video.split('/')[-2], os.path.basename(video)[:-4]
            if ex not in FIT3D_EXERCISES:
                continue
            jf, cf = f'{root}/{subj}/joints3d_25/{ex}', f'{root}/{subj}/camera_parameters/{cam}/{ex}.json'
            jf = next((f for f in (jf + '.npy', jf + '.json') if os.path.exists(f)), None)  # Mac copy .npy, original .json
            if not (jf and os.path.exists(cf)):
                continue
            J = np.load(jf) if jf.endswith('.npy') else np.array(json.load(open(jf))['joints3d_25'])
            camera = json.load(open(cf))
            idx = list(range(0, len(J), stride))
            frames = read_frames(video, idx)
            crops, back, gts, boxes = [], [], [], []
            for t in idx:
                if t not in frames:
                    continue
                p = project_fit3d(J[t], camera)
                k = np.zeros((17, 2)); k[list(FIT3D_COCO)] = p[list(FIT3D_COCO.values())]
                box = bbox_from_points(p)
                cr, m = crop_box(frames[t], *box_to_center_scale(box))
                crops.append(cr); back.append(invert_affine(m)); gts.append(k); boxes.append(max(box[2] - box[0], box[3] - box[1]))
            kp, conf = predict(model, crops)
            full = np.array([apply_affine(b, q) for b, q in zip(back, kp[:, :17])])
            valid = np.zeros((len(gts), 17), bool); valid[:, 5:] = True
            rows[f'{subj}/{ex}/{cam}'] = dict(summarize(full, np.array(gts), valid, np.array(boxes), conf_stats(conf[:, 5:17])), exercise=ex)
    return {'aggregate': {'all': weighted(list(rows.values()))}, 'per_video': rows}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dataset', required=True, choices=('coco', 'ex3d', 'fit3d'))
    ap.add_argument('--model', required=True)
    ap.add_argument('--name')
    ap.add_argument('--subjects', default='s09,s10,s11')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    variant, _, ckpt = a.model.partition(':')
    model = load_model(variant, ckpt or None)
    res = {'coco': lambda: coco(model), 'ex3d': lambda: ex3d(model),
           'fit3d': lambda: fit3d(model, a.subjects.split(','))}[a.dataset]()
    res = {'model': a.name or a.model, 'dataset': a.dataset, **(res if 'aggregate' in res else {'aggregate': {'all': res}})}
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump(res, open(a.out, 'w'), indent=1)
    for k, v in res['aggregate'].items():
        print(a.name or a.model, a.dataset, k, {x: v[x] for x in v if x in ('n_instances', 'pck05_body12', 'pck05_limbs8', 'pck05_hip', 'pck05_face', 'pck10_body12', 'pck05_heel', 'mean_err_body12_pct_box', 'conf_p10')})


if __name__ == '__main__':
    main()
