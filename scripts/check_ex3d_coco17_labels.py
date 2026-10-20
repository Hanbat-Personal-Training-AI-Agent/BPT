"""Exercise3D SMPL fit -> COCO17 2D (PSEUDO-GT, Sapiens2-derived, status REVIEW) and its per-joint check (track rtmpose-ft).

Mesh: outputs/exercise3d_labels/<seq>/smpl_fit/smpl_fit.npz (SMPL v1.1.0, gender from metadata) -> 6890 vertices
-> COCO17 with the published vertex regressor J_regressor_coco.npy (WHAM body_models, identical to GVHMR
smpl_coco17_J_regressor.pt). Projected with geometry/metadata.json camera_geometry (pinhole, working frame
720x1280, scaled to the video). NOT ground truth: the fit was made to Sapiens2 triangulated joints with COCO hips/
shoulders pinned to SMPL joint centres, so it is for evaluation only (D-C-01), never training.

Per joint: error vs the Sapiens2 2D view labels and vs the triangulated canonical COCO joints reprojected,
RTMPose-m disagreement (flag only), jitter, out-of-frame, left/right swap flags. Contact sheets per seq (top/bottom x cams).

usage: check_ex3d_coco17_labels.py --smpl-dir DIR(smpl_<gender>.npz, J_regressor_coco.npy) --out DIR [--stride 5]
"""

import argparse
import json
import os

import cv2
import numpy as np

from check_fit3d_coco17_labels import BODY, body_frame_offset, draw, read_frames
from eval_pose2d import EX3D_LABELS, EX3D_VIDEOS, GT_JSON, SAPIENS_COCO17
from pose2d_ft_common import crop_box, load_model, predict
from pose_feedback.body.pose2d_data import COCO_NAMES, FLIP_PERM, apply_affine, bbox_from_points, box_to_center_scale, invert_affine

CANON_COCO17 = list(range(17))  # canonical_joint_names starts with the COCO17 order


def rodrigues(r):
    """[N,3] axis-angle -> [N,3,3]."""
    th = np.linalg.norm(r, axis=1, keepdims=True) + 1e-12
    k = r / th
    K = np.zeros((len(r), 3, 3))
    K[:, 0, 1], K[:, 0, 2], K[:, 1, 2] = -k[:, 2], k[:, 1], -k[:, 0]
    K = K - K.transpose(0, 2, 1)
    s, c = np.sin(th)[:, :, None], np.cos(th)[:, :, None]
    return np.eye(3) + s * K + (1 - c) * K @ K


def smpl_vertices(model, betas, pose, transl):
    """SMPL LBS: betas [10], pose [T,72], transl [T,3] -> [T,6890,3]."""
    v_shaped = model['v_template'] + model['shapedirs'] @ betas
    J = model['J_regressor'] @ v_shaped
    parents = model['kintree'][0]
    out = []
    for p, t in zip(pose, transl):
        R = rodrigues(p.reshape(24, 3))
        v = v_shaped + model['posedirs'] @ (R[1:] - np.eye(3)).ravel()
        G = np.zeros((24, 4, 4))
        G[0, :3, :3], G[0, :3, 3], G[0, 3, 3] = R[0], J[0], 1
        for i in range(1, 24):
            L = np.eye(4); L[:3, :3] = R[i]; L[:3, 3] = J[i] - J[parents[i]]
            G[i] = G[parents[i]] @ L
        G[:, :3, 3] -= np.einsum('jab,jb->ja', G[:, :3, :3], J)
        Tv = np.einsum('vj,jab->vab', model['weights'], G)
        out.append(np.einsum('vab,vb->va', Tv[:, :3, :3], v) + Tv[:, :3, 3] + t)
    return np.array(out)


def project(X, cam, sx, sy):
    E, K = np.array(cam['extrinsic_world_to_camera']), np.array(cam['intrinsic_working_frame'])
    xc = X @ E[:, :3].T + E[:, 3]
    uv = xc @ K.T
    return np.stack([uv[..., 0] / uv[..., 2] * sx, uv[..., 1] / uv[..., 2] * sy], -1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--smpl-dir', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--stride', type=int, default=5)
    a = ap.parse_args()
    os.makedirs(f'{a.out}/sheets', exist_ok=True)
    reg = np.load(f'{a.smpl_dir}/J_regressor_coco.npy')
    model = load_model('m_coco17')
    gt = json.load(open(GT_JSON))
    rows = {}
    for seq, g in sorted(gt.items()):
        lab_dir = EX3D_LABELS / seq
        meta = json.load(open(lab_dir / 'smpl_fit/metadata.json'))
        fit = np.load(lab_dir / 'smpl_fit/smpl_fit.npz')
        smpl = dict(np.load(f"{a.smpl_dir}/smpl_{meta.get('gender', 'neutral')}.npz"))
        pose = np.concatenate([fit['global_orient'], fit['body_pose']], 1)
        V = smpl_vertices(smpl, fit['betas'][0], pose, fit['transl'])
        coco_m = np.einsum('jv,tvc->tjc', reg, V)
        joints_m = np.einsum('jv,tvc->tjc', smpl['J_regressor'], V)
        canon = np.load(lab_dir / 'geometry/canonical_3d.npz')
        cams = json.load(open(lab_dir / 'geometry/metadata.json'))['camera_geometry']
        # metres <-> canonical arbitrary units: choose the direction that matches the fit's pelvis
        sc = float(fit['scale_arbitrary_to_meters'])
        pel = canon['keypoints_3d'][:, 24]
        k = min((sc, 1 / sc), key=lambda s: np.nanmedian(np.linalg.norm(joints_m[:, 0] * s - pel, axis=1)))
        coco_w = coco_m * k
        fit_rmse = float(np.nanmedian(np.linalg.norm(joints_m[:, 0] * k - pel, axis=1)) / k)
        tiles = []
        for cam, view in g['views'].items():
            vid = EX3D_VIDEOS / g['exercise'] / seq / f'{cam}.mp4'
            cap = cv2.VideoCapture(str(vid)); W, H = cap.get(3), cap.get(4); cap.release()
            wh = cams[cam]['working_frame_hw']
            sx, sy = W / wh[1], H / wh[0]
            lab = project(coco_w, cams[cam], sx, sy)
            can2d = project(canon['keypoints_3d'][:, CANON_COCO17], cams[cam], sx, sy)
            sap = np.load(lab_dir / 'view' / f'{cam}_pose_2d.npz')
            sap_xy = sap['keypoints_xy'][:, SAPIENS_COCO17] * (max(W, H) / 1280.0)
            sap_ok = sap['valid_mask'][:, SAPIENS_COCO17] & (sap['confidence'][:, SAPIENS_COCO17] > 0.5)
            n = min(len(lab), len(sap_xy))
            idx = [t for t in range(0, n, a.stride) if sap['target_present'][t]]
            # top/bottom by image-space hip height of this camera (y down): bottom = lowest hips
            y = lab[:n, 11:13, 1].mean(1)
            show = [int(np.argmin(y[:n])), int(np.argmax(y[:n]))]
            frames = read_frames(str(vid), sorted(set(idx) | set(show)))
            T = [t for t in idx if t in frames]
            crops, backs = [], []
            for t in T:
                cr, m = crop_box(cv2.cvtColor(frames[t], cv2.COLOR_BGR2RGB), *box_to_center_scale(bbox_from_points(lab[t, BODY])))
                crops.append(cr); backs.append(invert_affine(m))
            kp, conf = predict(model, crops)
            pred = np.array([apply_affine(b, q[:17]) for b, q in zip(backs, kp)])
            L = lab[T]
            box = np.array([max(b[2] - b[0], b[3] - b[1]) for b in (bbox_from_points(l[BODY]) for l in L)])
            err = np.linalg.norm(pred - L, axis=-1) / box[:, None]
            e_sap = np.linalg.norm(sap_xy[T] - L, axis=-1) / box[:, None]
            e_can = np.linalg.norm(can2d[T] - L, axis=-1) / box[:, None]
            sw = np.linalg.norm(pred - L[:, FLIP_PERM], axis=-1) / box[:, None]
            u, s = body_frame_offset(sap_xy[T] - L, L)
            acc = np.linalg.norm(lab[2:] - 2 * lab[1:-1] + lab[:-2], axis=-1)
            oof = (lab[..., 0] < 0) | (lab[..., 0] >= W) | (lab[..., 1] < 0) | (lab[..., 1] >= H)
            key = f'{seq}/{cam}'
            rows[key] = {'exercise': g['exercise'], 'angle': view['angle_deg'], 'fit_pelvis_err_m': fit_rmse, 'n_model_frames': len(T), 'joints': {}}
            for j in range(17):
                ok = sap_ok[T, j]
                rows[key]['joints'][COCO_NAMES[j]] = {
                    'vs_sapiens2d_med': float(np.median(e_sap[ok, j])) if ok.any() else None,
                    'vs_sapiens2d_p90': float(np.percentile(e_sap[ok, j], 90)) if ok.any() else None,
                    'vs_sapiens_pck05': float((e_sap[ok, j] < 0.05).mean()) if ok.any() else None,
                    'vs_canonical_med': float(np.nanmedian(e_can[:, j])),
                    'sapiens_minus_label_up': float(np.mean(u[ok, j])) if ok.any() else None,
                    'sapiens_minus_label_side': float(np.mean(s[ok, j])) if ok.any() else None,
                    'model_err_med': float(np.median(err[:, j])), 'model_far': float((err[:, j] > 0.10).mean()),
                    'swap_frames': int(((sw[:, j] < 0.5 * err[:, j]) & (err[:, j] > 0.10)).sum()),
                    'jitter_px_med': float(np.median(acc[:, j])), 'jitter_px_p99': float(np.percentile(acc[:, j], 99)),
                    'out_of_frame': float(oof[:, j].mean()),
                }
            for t, ph in zip(show, ('top', 'bottom')):
                fr = frames[t]
                tiles.append((ph, draw(fr, lab[t], sap_xy[t], f'{seq} {cam} {ph} t{t} (x=Sapiens)')))
            print(key, 'vs sapiens med body', round(float(np.nanmedian(e_sap[:, 5:])), 4), 'hip', round(float(np.median(e_sap[:, 11:13])), 4),
                  'model hip', round(float(np.median(err[:, 11:13])), 4), flush=True)
        sheet = np.vstack([np.hstack([t for p, t in tiles if p == ph]) for ph in ('top', 'bottom')])
        cv2.imwrite(f'{a.out}/sheets/{seq}.jpg', sheet, [cv2.IMWRITE_JPEG_QUALITY, 85])
    json.dump(rows, open(f'{a.out}/ex3d_label_check.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
