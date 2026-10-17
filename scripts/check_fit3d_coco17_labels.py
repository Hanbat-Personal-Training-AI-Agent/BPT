"""Verify Fit3D mocap -> COCO17 2D labels per joint before using them for training (track rtmpose-ft).

Labels: joints3d_25 projected into the original RGB videos with the official camera_parameters
(extrinsics + intrinsics_w_distortion, H36M/Fit3D distortion model, pose2d_data.project_fit3d).
COCO body joints 5-16 come from FIT3D_COCO; Fit3D has no eyes/ears and its head marker (9) is not COCO's nose,
so face joints have no label.

Per joint (all frames of each subject x exercise x camera):
  out_of_frame     share of projected points outside the image
  jitter_px        median / p99 |second difference| of the 2D track (50 fps)
  vs_model         RTMPose-m (app model) on the mocap-box crop, every --stride frame: median and p90
                   error / box, share > 0.10 (flags for visual inspection only; the model is NOT ground truth),
                   mean signed offset in the body frame (along pelvis->neck = "up", along l->r hip = "side", / torso)
  swap             frames where swapping the label's left/right reduces model error by half and the plain error > 0.10
  sync             model-vs-label wrist error at time shifts -3..3 frames (minimum at 0 = video and mocap in sync)
Contact sheets (rep top and bottom x 4 cameras, labels green, model red) are written per subject x exercise.
Fit3D images stay on this machine (licence).

usage: check_fit3d_coco17_labels.py --root ~/datasets/fit3d/train --subjects s03,s04 --out DIR [--stride 5]
"""

import argparse
import json
import os

import cv2
import numpy as np

from pose2d_ft_common import crop_box, load_model, predict
from pose_feedback.body.pose2d_data import (
    COCO_NAMES, FLIP_PERM, apply_affine, bbox_from_points, box_to_center_scale, invert_affine, project_fit3d,
)

EXERCISES = ('squat', 'pushup', 'diamond_pushup', 'barbell_row', 'barbell_dead_row')
CAMS = ('50591643', '58860488', '60457274', '65906101')
FIT3D_COCO = {5: 11, 6: 14, 7: 12, 8: 15, 9: 13, 10: 16, 11: 1, 12: 4, 13: 2, 14: 5, 15: 3, 16: 6}  # coco <- fit3d
BODY = list(range(5, 17))
EDGES = ((5, 7), (7, 9), (6, 8), (8, 10), (5, 6), (11, 12), (5, 11), (6, 12), (11, 13), (13, 15), (12, 14), (14, 16))


def coco_labels(J, camera):
    """J [T,25,3] -> [T,17,2] (face = nan)."""
    out = np.full((len(J), 17, 2), np.nan)
    p = project_fit3d(J.reshape(-1, 3), camera).reshape(len(J), 25, 2)
    for c, f in FIT3D_COCO.items():
        out[:, c] = p[:, f]
    return out


def phase_frames(J, ex, reps):
    """(top, bottom) frame per rep from rep_ann boundaries: top = boundary, bottom = extreme of the movement."""
    z = {'squat': -J[:, 0, 2], 'pushup': -J[:, 8, 2], 'diamond_pushup': -J[:, 8, 2]}.get(ex, J[:, [13, 16], 2].max(1))
    tops, bottoms = [], []
    for a, b in zip(reps[:-1], reps[1:]):
        tops.append(a)
        bottoms.append(a + int(np.argmax(z[a:b])))
    return tops, bottoms


def read_frames(path, want):
    cap, out, t = cv2.VideoCapture(path), {}, 0
    want = set(want)
    while want and t <= max(want):
        if not cap.grab():
            break
        if t in want:
            ok, fr = cap.retrieve()
            if ok:
                out[t] = fr
        t += 1
    cap.release()
    return out


def body_frame_offset(err, lab):
    """err [N,17,2] (pred - label) -> mean (up, side) components / torso length per joint."""
    hip_c, sh_c = lab[:, 11:13].mean(1), lab[:, 5:7].mean(1)
    up = sh_c - hip_c
    torso = np.linalg.norm(up, axis=1, keepdims=True) + 1e-6
    up = up / torso
    side = lab[:, 12] - lab[:, 11]
    side = side - (side * up).sum(1, keepdims=True) * up
    side = side / (np.linalg.norm(side, axis=1, keepdims=True) + 1e-6)
    u = (err * up[:, None]).sum(-1) / torso
    s = (err * side[:, None]).sum(-1) / torso
    return u, s


TAGS = {5: 'LS', 6: 'RS', 7: 'LE', 8: 'RE', 9: 'LW', 10: 'RW', 11: 'LH', 12: 'RH', 13: 'LK', 14: 'RK', 15: 'LA', 16: 'RA'}


def draw(img, lab, pred, tag, size=300):
    """Label = dots + tag text (left green, right cyan); model = crosses (left red, right magenta)."""
    box = bbox_from_points(lab[BODY])
    c = (box[:2] + box[2:]) / 2
    side = max(box[2] - box[0], box[3] - box[1]) * 1.4
    k = size / side
    m = np.array([[k, 0, size / 2 - k * c[0]], [0, k, size / 2 - k * c[1]]])
    tile = cv2.warpAffine(img, m, (size, size), borderValue=(40, 40, 40))
    L, P = apply_affine(m, lab[BODY]), apply_affine(m, pred[BODY])
    L = dict(zip(BODY, L)); P = dict(zip(BODY, P))
    for a, b in EDGES:
        cv2.line(tile, tuple(int(v) for v in L[a]), tuple(int(v) for v in L[b]), (0, 200, 0), 1)
    for j in BODY:
        left = j % 2 == 1
        col = (0, 255, 0) if left else (255, 255, 0)
        x, y = (int(v) for v in L[j])
        cv2.circle(tile, (x, y), 4, col, -1)
        if size > 300:
            cv2.putText(tile, TAGS[j], (x + 5, y - 4), cv2.FONT_HERSHEY_SIMPLEX, 0.4, col, 1)
        if not np.isfinite(P[j]).all():
            continue
        x, y = (int(v) for v in P[j])
        cv2.drawMarker(tile, (x, y), (0, 0, 255) if left else (255, 0, 255), cv2.MARKER_CROSS, 8, 2)
    cv2.putText(tile, tag, (4, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
    return tile


def render(a, model, spec):
    """spec subj:exercise:frame -> one sheet, 4 cameras, 480 px tiles."""
    subj, ex, t = spec.split(':')
    t = int(t)
    J = np.array(json.load(open(f'{a.root}/{subj}/joints3d_25/{ex}.json'))['joints3d_25'])
    tiles = []
    for cam in CAMS:
        camera = json.load(open(f'{a.root}/{subj}/camera_parameters/{cam}/{ex}.json'))
        lab = coco_labels(J[t:t + 1], camera)[0]
        fr = read_frames(f'{a.root}/{subj}/videos/{cam}/{ex}.mp4', [t])[t]
        cr, m = crop_box(cv2.cvtColor(fr, cv2.COLOR_BGR2RGB), *box_to_center_scale(bbox_from_points(lab[BODY])))
        q, _ = predict(model, [cr])
        tiles.append(draw(fr, lab, apply_affine(invert_affine(m), q[0][:17]), f'{subj} {ex} {cam} t{t}', 480))
    cv2.imwrite(f'{a.out}/render_{subj}_{ex}_{t}.jpg', np.vstack([np.hstack(tiles[:2]), np.hstack(tiles[2:])]),
                [cv2.IMWRITE_JPEG_QUALITY, 88])


def summarize(path):
    """Per-joint aggregate over every subject x exercise x camera of a check JSON (Fit3D or Exercise3D)."""
    rows = json.load(open(path))
    names = list(next(iter(rows.values()))['joints'])
    out = {}
    for j in names:
        v = [r['joints'][j] for r in rows.values()]
        get = lambda k: np.array([x[k] for x in v if x.get(k) is not None], float)
        agg = {k: round(float(np.median(get(k))), 4) for k in v[0] if isinstance(v[0][k], float) and len(get(k))}
        agg['model_far_max_video'] = round(float(get('model_far').max()), 3) if len(get('model_far')) else None
        if 'swap_frames' in v[0]:
            n = sum(r.get('n_model_frames', 0) for r in rows.values())
            agg['swap_frames_total'] = int(get('swap_frames').sum()); agg['swap_rate'] = round(float(get('swap_frames').sum()) / max(n, 1), 4)
        by_ex = {}
        for key, r in rows.items():
            ex = r.get('exercise') or key.split('/')[1]
            by_ex.setdefault(ex, []).append(r['joints'][j].get('model_err_med'))
        agg['model_err_med_by_exercise'] = {e: round(float(np.median([x for x in xs if x is not None])), 4) for e, xs in by_ex.items()}
        out[j] = agg
    if 'sync_wrist_ankle' in next(iter(rows.values())):
        best = [min(r['sync_wrist_ankle'], key=r['sync_wrist_ankle'].get) for r in rows.values()]
        out['_sync_best_shift_counts'] = {k: best.count(k) for k in sorted(set(best))}
    out['_videos'] = len(rows)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--subjects', default='')
    ap.add_argument('--out', required=True)
    ap.add_argument('--stride', type=int, default=5)
    ap.add_argument('--render', help='comma list subj:exercise:frame -> 4-camera close-up sheets only')
    ap.add_argument('--summary', help='check JSON -> per-joint aggregate (prints JSON, no model)')
    a = ap.parse_args()
    if a.summary:
        print(json.dumps(summarize(a.summary), indent=1))
        return
    os.makedirs(f'{a.out}/sheets', exist_ok=True)
    model = load_model('m_coco17')
    if a.render:
        for spec in a.render.split(','):
            render(a, model, spec)
        return
    rows = {}
    for subj in a.subjects.split(','):
        reps_all = json.load(open(f'{a.root}/{subj}/rep_ann.json'))
        for ex in EXERCISES:
            J = np.array(json.load(open(f'{a.root}/{subj}/joints3d_25/{ex}.json'))['joints3d_25'])
            tops, bottoms = phase_frames(J, ex, reps_all[ex])
            show = [tops[len(tops) // 2], bottoms[len(bottoms) // 2]]
            tiles = []
            for cam in CAMS:
                camera = json.load(open(f'{a.root}/{subj}/camera_parameters/{cam}/{ex}.json'))
                video = f'{a.root}/{subj}/videos/{cam}/{ex}.mp4'
                lab = coco_labels(J, camera)
                idx = list(range(0, len(J), a.stride))
                wide = sorted(set(idx) | {t + d for t in idx for d in (-3, -2, -1, 1, 2, 3) if 0 <= t + d < len(J)} | set(show))
                frames = read_frames(video, wide)
                H, W = next(iter(frames.values())).shape[:2]
                T = sorted(t for t in idx if t in frames)
                crops, backs = [], []
                for t in T:
                    cr, m = crop_box(cv2.cvtColor(frames[t], cv2.COLOR_BGR2RGB), *box_to_center_scale(bbox_from_points(lab[t, BODY])))
                    crops.append(cr); backs.append(invert_affine(m))
                kp, conf = predict(model, crops)
                pred = np.array([apply_affine(b, q[:17]) for b, q in zip(backs, kp)])
                L = lab[T]
                box = np.array([max(b[2] - b[0], b[3] - b[1]) for b in (bbox_from_points(l[BODY]) for l in L)])
                err = np.linalg.norm(pred - L, axis=-1) / box[:, None]
                sw = np.linalg.norm(pred - L[:, FLIP_PERM], axis=-1) / box[:, None]
                u, s = body_frame_offset(pred - L, L)
                # sync: wrist error vs shifted labels
                sync = {}
                for d in (-3, -2, -1, 0, 1, 2, 3):
                    ok = [i for i, t in enumerate(T) if 0 <= t + d < len(J)]
                    e = np.linalg.norm(pred[ok][:, [9, 10, 15, 16]] - lab[[T[i] + d for i in ok]][:, [9, 10, 15, 16]], axis=-1)
                    sync[d] = float(np.median(e / box[ok, None]))
                acc = np.linalg.norm(lab[2:] - 2 * lab[1:-1] + lab[:-2], axis=-1)
                oof = (lab[..., 0] < 0) | (lab[..., 0] >= W) | (lab[..., 1] < 0) | (lab[..., 1] >= H)
                key = f'{subj}/{ex}/{cam}'
                rows[key] = {'n_model_frames': len(T), 'n_frames': len(J), 'sync_wrist_ankle': sync, 'joints': {}}
                for j in BODY:
                    swapped = (sw[:, j] < 0.5 * err[:, j]) & (err[:, j] > 0.10)
                    rows[key]['joints'][COCO_NAMES[j]] = {
                        'out_of_frame': float(oof[:, j].mean()),
                        'jitter_px_med': float(np.median(acc[:, j])), 'jitter_px_p99': float(np.percentile(acc[:, j], 99)),
                        'model_err_med': float(np.median(err[:, j])), 'model_err_p90': float(np.percentile(err[:, j], 90)),
                        'model_far': float((err[:, j] > 0.10).mean()), 'model_conf_med': float(np.median(conf[:, j])),
                        'offset_up': float(np.mean(u[:, j])), 'offset_side': float(np.mean(s[:, j])),
                        'swap_frames': int(swapped.sum()), 'swap_examples': [int(T[i]) for i in np.where(swapped)[0][:5]],
                        'far_examples': [int(T[i]) for i in np.argsort(-err[:, j])[:3]],
                    }
                for t, ph in zip(show, ('top', 'bottom')):
                    fr = frames[t]
                    cr, m = crop_box(cv2.cvtColor(fr, cv2.COLOR_BGR2RGB), *box_to_center_scale(bbox_from_points(lab[t, BODY])))
                    q, _ = predict(model, [cr])
                    tiles.append((ph, draw(fr, lab[t], apply_affine(invert_affine(m), q[0][:17]), f'{subj} {ex} {cam[:4]} {ph} t{t}')))
                print(key, 'limb err med', round(float(np.median(err[:, [7, 8, 9, 10, 13, 14, 15, 16]])), 4),
                      'hip', round(float(np.median(err[:, [11, 12]])), 4), 'sync', {k: round(v, 4) for k, v in sync.items()}, flush=True)
            sheet = np.vstack([np.hstack([t for p, t in tiles if p == ph]) for ph in ('top', 'bottom')])
            cv2.imwrite(f'{a.out}/sheets/{subj}_{ex}.jpg', sheet, [cv2.IMWRITE_JPEG_QUALITY, 85])
        json.dump(rows, open(f'{a.out}/fit3d_label_check.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
