"""Fit3D SMPL-X -> COCO17 label verification without trusting mocap joint centres (track fit3d-label-verify).

Label sources compared (all from the OFFICIAL per-frame Fit3D SMPL-X params, smplx library SMPLXLayer, rotation matrices,
per-frame betas + expression; projected with the official cameras incl. the Fit3D/H36M distortion model):
  gvhmr   GVHMR SmplxLiteCoco17 = smpl_coco17_J_regressor [17x6890] x smplx2smpl_sparse [6890x10475]
          (byte-identical to WHAM J_regressor_coco x smplx2smpl.pkl, checked in `audit`)
  native  SMPL-X joint set of the smplx library: body joint centres (hips 1/2, shoulders 16/17, ...) + face vertices
          nose 9120, eyes 9929/9448, ears 616/6 (the joint-centre style used by SMPL(-X)->COCO mappings in mmhuman3d-type code)
  h36m    WHAM/SPIN J_regressor_h36m [17x6890] x smplx2smpl (body 12 only, no face)
  mocap   Fit3D joints3d_25 (body 12 only)
RTMPose-m (app model) is a reference, never ground truth.

Subcommands (Home, conda bpt-mmpose; PYTHONPATH must include the smplx library, e.g. ~/flv/pylib):
  audit    numeric chain audit -> JSON: regressor identity / L-R sides in template space, numpy-LBS (old labels) vs smplx
           library, hand / expression sensitivity, gender, beta drift, distortion model size, video frame counts
  measure  per joint, every subject x exercise x camera: 3D segment-length CV, 3D acceleration, L/R axis consistency,
           in-frame rate, self-occlusion (z-buffer heuristic), 4-camera triangulation of the projected labels, RTMPose-m
           agreement + RTMPose 4-camera triangulation vs each source in 3D, body-frame offsets
  fitcheck mesh silhouette vs RTMDet-Ins person mask (IoU / precision / recall / boundary distance), sampled frames (GPU)
  sample   pick the manual-annotation frames, write crops + manifest.js (no coordinates) for the local annotation page,
           candidates.json (all sources in crop pixels) and overlay images. Everything Fit3D-derived stays out of git.
"""

import argparse
import json
import os

import cv2
import numpy as np
import torch

from check_fit3d_coco17_labels import CAMS, EXERCISES, FIT3D_COCO, SmplxCoco17, phase_frames, read_frames, body_frame_offset
from pose2d_ft_common import crop_box, load_model, predict
from pose_feedback.body.pose2d_data import COCO_NAMES, FLIP_PERM, apply_affine, box_to_center_scale, invert_affine, project_fit3d

GVHMR = os.path.expanduser('~/rtmft/ext/GVHMR/hmr4d/utils/body_model')
WHAM = os.path.expanduser('~/rtmft/ext/wham/body_models')
NATIVE = {0: 55, 1: 57, 2: 56, 3: 59, 4: 58, 5: 16, 6: 17, 7: 18, 8: 19, 9: 20, 10: 21, 11: 1, 12: 2, 13: 4, 14: 5, 15: 7, 16: 8}
# coco <- h36m by GEOMETRY: in J_regressor_h36m indices 1-3 sit on the SMPL left side (+x) although H36M names them right (audit)
H36M = {5: 11, 6: 14, 7: 12, 8: 15, 9: 13, 10: 16, 11: 1, 12: 4, 13: 2, 14: 5, 15: 3, 16: 6}
FACEV = {55: 9120, 56: 9929, 57: 9448, 58: 616, 59: 6}  # smplx lib extra joints 55-59 = these vertices
SMPLX_LR = {5: 16, 6: 17, 7: 18, 8: 19, 9: 20, 10: 21, 11: 1, 12: 2, 13: 4, 14: 5, 15: 7, 16: 8}  # coco <- SMPL-X joint
SOURCES = ('gvhmr', 'native', 'h36m', 'mocap')
SEGS = {'shoulder_w': (5, 6), 'hip_w': (11, 12), 'torso_l': (5, 11), 'torso_r': (6, 12), 'upper_arm_l': (5, 7),
        'upper_arm_r': (6, 8), 'forearm_l': (7, 9), 'forearm_r': (8, 10), 'thigh_l': (11, 13), 'thigh_r': (12, 14),
        'shin_l': (13, 15), 'shin_r': (14, 16), 'eye_eye': (1, 2), 'ear_ear': (3, 4), 'nose_leye': (0, 1), 'nose_reye': (0, 2)}
PAIRS = ((1, 2), (3, 4), (5, 6), (7, 8), (9, 10), (11, 12), (13, 14), (15, 16))


def jload(p):
    return json.load(open(p))


def regressors():
    import pickle
    s2s = torch.load(f'{GVHMR}/smplx2smpl_sparse.pt').to_dense().double().numpy()
    gv = torch.load(f'{GVHMR}/smpl_coco17_J_regressor.pt').double().numpy() @ s2s
    s2s_w = pickle.load(open(f'{WHAM}/smplx2smpl.pkl', 'rb'), encoding='latin1')['matrix']
    s2s_w = s2s_w.toarray() if hasattr(s2s_w, 'toarray') else np.asarray(s2s_w)
    wh = np.load(f'{WHAM}/J_regressor_coco.npy') @ s2s_w
    h36 = np.load(f'{WHAM}/J_regressor_h36m.npy') @ s2s
    return gv, wh, h36


class Body:
    def __init__(self, model_dir, gender='neutral'):
        import smplx
        self.m = smplx.SMPLXLayer(model_path=f'{model_dir}/SMPLX_{gender.upper()}.npz', num_betas=10, num_expression_coeffs=10)
        self.gv, _, self.h36 = regressors()
        self.faces = self.m.faces.astype(np.int32)

    @torch.no_grad()
    def __call__(self, p, idx=None, hands=True, expression=True):
        """p = Fit3D smplx json dict -> (vertices [T,10475,3], smplx joints [T,127,3]) in world metres."""
        idx = np.arange(len(p['transl'])) if idx is None else np.asarray(idx)
        t = lambda k: torch.tensor(np.asarray(p[k], np.float32)[idx])
        eye = lambda n: torch.eye(3).expand(len(idx), n, 3, 3)
        out = self.m(global_orient=t('global_orient'), body_pose=t('body_pose'), betas=t('betas'), transl=t('transl'),
                     left_hand_pose=t('left_hand_pose') if hands else eye(15), right_hand_pose=t('right_hand_pose') if hands else eye(15),
                     jaw_pose=t('jaw_pose'), leye_pose=t('leye_pose'), reye_pose=t('reye_pose'),
                     expression=t('expression') if expression else torch.zeros(len(idx), 10))
        return out.vertices.double().numpy(), out.joints.double().numpy()

    def sources(self, V, Jx, mocap):
        """-> dict source -> [T,17,3] (nan where the source has no such joint)."""
        out = {'gvhmr': np.einsum('kv,tvc->tkc', self.gv, V)}
        out['native'] = Jx[:, [NATIVE[k] for k in range(17)]]
        h = np.einsum('kv,tvc->tkc', self.h36, V)
        out['h36m'] = np.full_like(out['gvhmr'], np.nan)
        out['mocap'] = np.full_like(out['gvhmr'], np.nan)
        for c in range(5, 17):
            out['h36m'][:, c] = h[:, H36M[c]]
            out['mocap'][:, c] = mocap[:, FIT3D_COCO[c]]
        return out


def proj(X, cam, model='h36m'):
    """[...,3] world -> [...,2] px. model: h36m (official Fit3D), opencv (Brown-Conrady), none (pinhole, same f/c)."""
    sh = X.shape[:-1]
    if model == 'h36m':
        return project_fit3d(X.reshape(-1, 3), cam).reshape(*sh, 2)
    R, T = np.asarray(cam['extrinsics']['R']), np.asarray(cam['extrinsics']['T']).reshape(3)
    i = cam['intrinsics_w_distortion']
    f, c, k, p = (np.asarray(i[n], float).reshape(-1) for n in 'fckp')
    xc = (X.reshape(-1, 3) - T) @ R.T
    x, y = xc[:, 0] / xc[:, 2], xc[:, 1] / xc[:, 2]
    if model == 'opencv':
        r2 = x * x + y * y
        rad = 1 + k[0] * r2 + k[1] * r2 ** 2 + k[2] * r2 ** 3
        x, y = x * rad + 2 * p[0] * x * y + p[1] * (r2 + 2 * x * x), y * rad + p[0] * (r2 + 2 * y * y) + 2 * p[1] * x * y
    return (np.stack([x, y], 1) * f + c).reshape(*sh, 2)


def cam_depth(X, cam):
    R, T = np.asarray(cam['extrinsics']['R']), np.asarray(cam['extrinsics']['T']).reshape(3)
    return ((X.reshape(-1, 3) - T) @ R.T)[:, 2].reshape(X.shape[:-1])


def undistort(uv, cam):
    """Inverse of the Fit3D/H36M distortion (fixed-point) -> normalised camera coords [N,2]."""
    i = cam['intrinsics_w_distortion']
    f, c, k, p = (np.asarray(i[n], float).reshape(-1) for n in 'fckp')
    xd = (np.asarray(uv, float) - c) / f
    x = xd.copy()
    for _ in range(30):
        r2 = (x ** 2).sum(1)
        rad = 1 + k[0] * r2 + k[1] * r2 ** 2 + k[2] * r2 ** 3
        tan = p[0] * x[:, 1] + p[1] * x[:, 0]
        x = (xd - np.outer(r2, [p[1], p[0]])) / (rad + tan)[:, None]
    return x


def triangulate(uvs, cams, w=None):
    """uvs [C,N,2] px, cams list, w [C,N] weights -> [N,3] (weighted DLT on undistorted coords)."""
    C, N = uvs.shape[:2]
    w = np.ones((C, N)) if w is None else w
    xs = [undistort(uvs[i], cams[i]) for i in range(C)]
    Ps = []
    for cam in cams:
        R, T = np.asarray(cam['extrinsics']['R']), np.asarray(cam['extrinsics']['T']).reshape(3, 1)
        Ps.append(np.hstack([R, -R @ T]))
    out = np.full((N, 3), np.nan)
    for n in range(N):
        A = []
        for i in range(C):
            if w[i, n] > 0 and np.isfinite(xs[i][n]).all():
                A += [w[i, n] * (xs[i][n, 0] * Ps[i][2] - Ps[i][0]), w[i, n] * (xs[i][n, 1] * Ps[i][2] - Ps[i][1])]
        if len(A) >= 4:
            v = np.linalg.svd(np.array(A))[2][-1]
            out[n] = v[:3] / v[3]
    return out


def zbuffer(V, cam, H, W, s=0.25):
    uv = proj(V, cam) * s
    z = cam_depth(V, cam)
    h, w = int(H * s), int(W * s)
    u, v = np.round(uv[:, 0]).astype(int), np.round(uv[:, 1]).astype(int)
    ok = (u >= 0) & (u < w) & (v >= 0) & (v < h)
    zb = np.full((h, w), np.inf, np.float32)
    np.minimum.at(zb, (v[ok], u[ok]), z[ok].astype(np.float32))
    return cv2.erode(zb, np.ones((3, 3), np.uint8)), s   # min-filter closes splat holes


def occluded(X17, zb, s, cam, margin=0.12):
    """ponytail: vertex-splat z-buffer + fixed 12 cm margin (joint points sit inside the body); a heuristic, not a renderer."""
    uv = proj(X17, cam) * s
    z = cam_depth(X17, cam)
    out = np.zeros(len(X17), bool)
    for j, ((u, v), d) in enumerate(zip(uv, z)):
        if not np.isfinite([u, v, d]).all():
            continue
        u, v = int(round(u)), int(round(v))
        if 0 <= v < zb.shape[0] and 0 <= u < zb.shape[1]:
            out[j] = zb[v, u] < d - margin
    return out


def silhouette(V, faces, cam, H, W):
    uv = np.round(proj(V, cam)).astype(np.int32)
    m = np.zeros((H, W), np.uint8)
    cv2.fillPoly(m, list(uv[faces]), 1)
    return m


def mesh_box(V2):
    x0, y0 = V2.min(0)
    x1, y1 = V2.max(0)
    return np.array([x0, y0, x1, y1])


# ----------------------------------------------------------------------------------------------------------- audit
def audit(a):
    out = {}
    gv, wh, h36 = regressors()
    m = np.load(f'{a.smplx}/SMPLX_NEUTRAL.npz', allow_pickle=True)
    vt = m['v_template']
    out['smplx_npz'] = {'shapedirs': list(m['shapedirs'].shape), 'posedirs': list(m['posedirs'].shape),
                        'version_txt': open(f'{a.smplx}/version.txt').read().strip()}
    out['regressor'] = {'gvhmr_vs_wham_max_abs': float(np.abs(gv - wh).max()),
                        'vertices_per_joint': {COCO_NAMES[k]: int((np.abs(gv[k]) > 0).sum()) for k in range(17)},
                        'rows_sum': [round(float(x), 4) for x in gv.sum(1)], 'negative_weights': int((gv < 0).sum())}
    # left/right in template space: SMPL-X left side is +x. left joints must be x > 0.
    Jr = m['J_regressor'] @ vt
    sides = {}
    for name, X in (('gvhmr', gv @ vt), ('native_joints', np.array([Jr[NATIVE[k]] if NATIVE[k] < 55 else vt[FACEV[NATIVE[k]]] for k in range(17)])),
                    ('h36m', np.array([(h36 @ vt)[H36M[k]] if k in H36M else [np.nan] * 3 for k in range(17)]))):
        sides[name] = {COCO_NAMES[k]: round(float(X[k, 0]), 4) for k in range(17)}
    out['template_x_m (left must be > 0)'] = sides
    # old numpy 132-vertex LBS (labels of D-C-09) vs smplx library
    body = Body(a.smplx)
    p = jload(f'{a.root}/s03/smplx/squat.json')
    idx = np.arange(0, len(p['transl']), max(1, len(p['transl']) // 40))
    V, Jx = body(p, idx)
    lib = np.einsum('kv,tvc->tkc', body.gv, V)
    out['smplx_face_joint_is_vertex_max_m'] = float(max(np.abs(Jx[:, j] - V[:, v]).max() for j, v in FACEV.items()))
    old = SmplxCoco17(a.smplx, GVHMR)
    tmp = f'/tmp/flv_{os.getpid()}.json'
    json.dump({k: np.asarray(v)[idx].tolist() for k, v in p.items()}, open(tmp, 'w'))
    oldC = old(tmp)
    os.remove(tmp)
    out['numpy_lbs_vs_smplx_lib_mm'] = {'max': float(np.abs(oldC - lib).max() * 1000), 'median': float(np.median(np.linalg.norm(oldC - lib, axis=-1)) * 1000)}
    Vh, _ = body(p, idx, hands=False)
    Ve, _ = body(p, idx, expression=False)
    dh = np.linalg.norm(np.einsum('kv,tvc->tkc', body.gv, Vh) - lib, axis=-1) * 1000
    de = np.linalg.norm(np.einsum('kv,tvc->tkc', body.gv, Ve) - lib, axis=-1) * 1000
    out['hand_pose_identity_shift_mm_max'] = {COCO_NAMES[k]: round(float(dh[:, k].max()), 2) for k in range(17)}
    out['expression_zero_shift_mm_max'] = {COCO_NAMES[k]: round(float(de[:, k].max()), 2) for k in range(17)}
    # gender, betas, frames, distortion, extrinsics
    bodies = {g: Body(a.smplx, g) for g in ('neutral', 'male', 'female')}
    out['gender_limb_mm'] = {}
    out['betas'] = {}
    out['frames'] = {}
    out['distortion_px'] = {}
    out['intrinsics_wo_vs_w'] = []
    limbs = [7, 8, 9, 10, 13, 14, 15, 16]
    for subj in a.subjects.split(','):
        res = {g: [] for g in bodies}
        lr = []
        bstd = []
        for ex in EXERCISES:
            p = jload(f'{a.root}/{subj}/smplx/{ex}.json')
            J = np.array(jload(f'{a.root}/{subj}/joints3d_25/{ex}.json')['joints3d_25'])
            b = np.array(p['betas'])
            bstd.append(float(b.std(0).max()))
            idx = np.arange(0, len(J), 20)
            for g, bd in bodies.items():
                _, Jx = bd(p, idx)
                d = [np.linalg.norm(Jx[:, SMPLX_LR[c]] - J[idx, FIT3D_COCO[c]], axis=-1) for c in limbs]
                res[g].append(float(np.median(d)) * 1000)
                if g == 'neutral':   # mocap L/R naming vs SMPL-X: distance to same-side vs opposite-side joint
                    for c in limbs:
                        o = c + 1 if c % 2 else c - 1
                        lr.append(float(np.median(np.linalg.norm(Jx[:, SMPLX_LR[c]] - J[idx, FIT3D_COCO[c]], axis=-1) <
                                                    np.linalg.norm(Jx[:, SMPLX_LR[c]] - J[idx, FIT3D_COCO[o]], axis=-1))))
            for cam in CAMS:
                camera = jload(f'{a.root}/{subj}/camera_parameters/{cam}/{ex}.json')
                cap = cv2.VideoCapture(f'{a.root}/{subj}/videos/{cam}/{ex}.mp4')
                n, fps, W, H = (cap.get(x) for x in (cv2.CAP_PROP_FRAME_COUNT, cv2.CAP_PROP_FPS, cv2.CAP_PROP_FRAME_WIDTH, cv2.CAP_PROP_FRAME_HEIGHT))
                cap.release()
                out['frames'][f'{subj}/{ex}/{cam}'] = [int(n), len(J), round(fps, 2), int(W), int(H)]
                X = bodies['neutral'].sources(*bodies['neutral'](p, idx), J[idx])['gvhmr']
                hp = proj(X, camera)
                out['distortion_px'][f'{subj}/{ex}/{cam}'] = [float(np.abs(hp - proj(X, camera, 'opencv')).max()),
                                                             float(np.linalg.norm(hp - proj(X, camera, 'none'), axis=-1).max())]
                i = camera['intrinsics_w_distortion']; o = camera['intrinsics_wo_distortion']
                out['intrinsics_wo_vs_w'].append(float(np.abs(np.r_[np.ravel(i['f']), np.ravel(i['c'])] - np.r_[np.ravel(o['f']), np.ravel(o['c'])]).max()))
        out['gender_limb_mm'][subj] = {g: round(float(np.median(v)), 1) for g, v in res.items()}
        out['betas'][subj] = {'max_std_over_frames': round(max(bstd), 4)}
        out['mocap_lr_same_side_closer_frac_min'] = min(out.get('mocap_lr_same_side_closer_frac_min', 1.0), min(lr))
        print(subj, out['gender_limb_mm'][subj], flush=True)
    d = np.array(list(out['distortion_px'].values()))
    out['distortion_summary'] = {'h36m_vs_opencv_max_px': float(d[:, 0].max()), 'h36m_vs_opencv_med_px': float(np.median(d[:, 0])),
                                 'distortion_effect_max_px': float(d[:, 1].max()), 'distortion_effect_med_px': float(np.median(d[:, 1]))}
    fr = np.array([v[:2] for v in out['frames'].values()])
    out['frames_summary'] = {'videos': len(fr), 'video_minus_label_frames': {str(k): int(v) for k, v in zip(*np.unique(fr[:, 0] - fr[:, 1], return_counts=True))},
                             'fps': sorted({v[2] for v in out['frames'].values()}), 'sizes': sorted({f'{v[3]}x{v[4]}' for v in out['frames'].values()})}
    out['intrinsics_wo_vs_w'] = float(max(out['intrinsics_wo_vs_w']))
    json.dump(out, open(a.out, 'w'), indent=1)


# --------------------------------------------------------------------------------------------------------- measure
def measure(a):
    body = Body(a.smplx)
    model = load_model('m_coco17')
    rows = {}
    if os.path.exists(a.out):
        rows = jload(a.out)
    for subj in a.subjects.split(','):
        for ex in EXERCISES:
            key = f'{subj}/{ex}'
            if key in rows:
                continue
            p = jload(f'{a.root}/{subj}/smplx/{ex}.json')
            J = np.array(jload(f'{a.root}/{subj}/joints3d_25/{ex}.json')['joints3d_25'])
            idx = np.arange(0, len(J), a.stride)
            V, Jx = body(p, idx)
            S = body.sources(V, Jx, J[idx])
            r = {'n': len(idx), 'src': {}}
            # 3D: segment CV, acceleration (consecutive sampled frames), L/R axis vs mocap pelvis / shoulder axis
            ax_lo = J[idx, FIT3D_COCO[11]] - J[idx, FIT3D_COCO[12]]
            ax_up = J[idx, FIT3D_COCO[5]] - J[idx, FIT3D_COCO[6]]
            for s, X in S.items():
                seg = {}
                for name, (i, j) in SEGS.items():
                    L = np.linalg.norm(X[:, i] - X[:, j], axis=-1)
                    if np.isfinite(L).all():
                        seg[name] = [float(L.mean()), float(L.std() / L.mean())]
                acc = np.linalg.norm(X[2:] - 2 * X[1:-1] + X[:-2], axis=-1) * 1000 / a.stride ** 2
                lr = {}
                for i, j in PAIRS:
                    d = X[:, i] - X[:, j]
                    if np.isfinite(d).all():
                        lr[COCO_NAMES[i]] = float(((d * (ax_lo if i >= 11 else ax_up)).sum(1) < 0).mean())
                r['src'][s] = {'seg': seg, 'acc_p99_mm': [float(np.nanpercentile(acc[:, k], 99)) if np.isfinite(acc[:, k]).any() else None for k in range(17)],
                               'lr_wrong_frac': lr}
            # per camera
            frames_all, cams = {}, []
            per_cam = {}
            for cam in CAMS:
                camera = jload(f'{a.root}/{subj}/camera_parameters/{cam}/{ex}.json')
                cams.append(camera)
                rt = set(idx[::a.model_every].tolist())
                frames = read_frames(f'{a.root}/{subj}/videos/{cam}/{ex}.mp4', sorted(rt))
                H, W = next(iter(frames.values())).shape[:2]
                pc = {'in_frame': {}, 'occluded': {}}
                P = {s: proj(X, camera) for s, X in S.items()}
                for s in SOURCES:
                    x = P[s]
                    ok = (x[..., 0] >= 0) & (x[..., 0] < W) & (x[..., 1] >= 0) & (x[..., 1] < H)
                    pc['in_frame'][s] = [float(ok[:, k].mean()) if np.isfinite(x[:, k]).all() else None for k in range(17)]
                occ = {s: [] for s in SOURCES}
                boxes = []
                for n, t in enumerate(idx):
                    zb, sc = zbuffer(V[n], camera, H, W)
                    for s in SOURCES:
                        occ[s].append(occluded(S[s][n], zb, sc, camera))
                    boxes.append(mesh_box(proj(V[n], camera)))
                boxes = np.array(boxes)
                for s in SOURCES:
                    o = np.array(occ[s])
                    pc['occluded'][s] = [float(o[:, k].mean()) if np.isfinite(S[s][:, k]).all() else None for k in range(17)]
                # RTMPose-m on the mesh-box crop
                T = [n for n, t in enumerate(idx) if t in frames]
                crops, backs = [], []
                for n in T:
                    cr, mm = crop_box(cv2.cvtColor(frames[idx[n]], cv2.COLOR_BGR2RGB), *box_to_center_scale(boxes[n]))
                    crops.append(cr); backs.append(invert_affine(mm))
                kp, conf = predict(model, crops)
                pred = np.array([apply_affine(b, q[:17]) for b, q in zip(backs, kp)])
                blong = np.maximum(boxes[T, 2] - boxes[T, 0], boxes[T, 3] - boxes[T, 1])
                pc['rtm'] = {}
                for s in SOURCES:
                    L = P[s][T]
                    e = np.linalg.norm(pred - L, axis=-1) / blong[:, None]
                    sw = np.linalg.norm(pred - L[:, FLIP_PERM], axis=-1) / blong[:, None]
                    ref = P['gvhmr'][T]   # body frame from the gvhmr labels for every source (same axes)
                    u, sd = body_frame_offset(pred - L, ref)
                    pc['rtm'][s] = {'err_med': [float(np.median(e[:, k])) if np.isfinite(e[:, k]).all() else None for k in range(17)],
                                    'pck05': [float((e[:, k] < 0.05).mean()) if np.isfinite(e[:, k]).all() else None for k in range(17)],
                                    'pck10': [float((e[:, k] < 0.10).mean()) if np.isfinite(e[:, k]).all() else None for k in range(17)],
                                    'up': [float(np.mean(u[:, k])) if np.isfinite(u[:, k]).all() else None for k in range(17)],
                                    'side': [float(np.mean(sd[:, k])) if np.isfinite(sd[:, k]).all() else None for k in range(17)],
                                    'swap': [float(((sw[:, k] < 0.5 * e[:, k]) & (e[:, k] > 0.10)).mean()) if np.isfinite(e[:, k]).all() else None for k in range(17)]}
                per_cam[cam] = pc
                frames_all[cam] = (T, pred, conf)
            r['cams'] = per_cam
            # 4-camera triangulation: projected labels (chain self-consistency) and RTMPose (image-based 3D reference)
            reproj = []
            n0 = len(idx) // 2
            X = S['gvhmr'][n0]
            uvs = np.array([proj(X, c) for c in cams])
            Xt = triangulate(uvs, cams)
            reproj = float(np.abs(np.array([proj(Xt, c) for c in cams]) - uvs).max())
            Tc = sorted(set.intersection(*[set(v[0]) for v in frames_all.values()]))
            tri_err = {s: [] for s in SOURCES}
            tri_res = []
            for n in Tc:
                uv = np.array([frames_all[c][1][frames_all[c][0].index(n)] for c in CAMS])
                w = np.array([frames_all[c][2][frames_all[c][0].index(n)][:17] for c in CAMS])
                w = np.where(w > 0.3, w, 0)
                Xr = triangulate(uv, cams, w)
                rp = np.array([proj(Xr, c) for c in cams])
                tri_res.append(np.where(w > 0, np.linalg.norm(rp - uv, axis=-1), np.nan))
                for s in SOURCES:
                    tri_err[s].append(np.linalg.norm(Xr - S[s][n], axis=-1) * 1000)
            r['label_triangulation_reproj_px_max'] = reproj
            r['rtm_tri_reproj_px_med'] = [float(np.nanmedian(np.array(tri_res)[:, :, k])) for k in range(17)]
            r['rtm_tri_vs_src_mm_med'] = {s: [float(np.nanmedian(np.array(v)[:, k])) if np.isfinite(np.array(v)[:, k]).any() else None for k in range(17)] for s, v in tri_err.items()}
            rows[key] = r
            print(key, 'rtm-tri vs gvhmr mm', [round(x) for x in r['rtm_tri_vs_src_mm_med']['gvhmr']], flush=True)
            json.dump(rows, open(a.out, 'w'))


def med(xs):
    xs = [x for x in xs if x is not None and np.isfinite(x)]
    return round(float(np.median(xs)), 4) if xs else None


def summarize(path):
    rows = jload(path)
    out = {}
    for s in SOURCES:
        o = {}
        for k in range(17):
            j = COCO_NAMES[k]
            cams = [c for r in rows.values() for c in r['cams'].values()]
            o[j] = {'rtm_err_med': med([c['rtm'][s]['err_med'][k] for c in cams]),
                    'rtm_pck05': med([c['rtm'][s]['pck05'][k] for c in cams]),
                    'rtm_pck10': med([c['rtm'][s]['pck10'][k] for c in cams]),
                    'rtm_up': med([c['rtm'][s]['up'][k] for c in cams]), 'rtm_side': med([c['rtm'][s]['side'][k] for c in cams]),
                    'rtm_swap_max': max([c['rtm'][s]['swap'][k] or 0 for c in cams]),
                    'occluded': med([c['occluded'][s][k] for c in cams]), 'in_frame_min': min([c['in_frame'][s][k] if c['in_frame'][s][k] is not None else 1 for c in cams]),
                    'rtm_tri_vs_src_mm': med([r['rtm_tri_vs_src_mm_med'][s][k] for r in rows.values()]),
                    'acc_p99_mm': med([r['src'][s]['acc_p99_mm'][k] for r in rows.values()])}
            o[j]['lr_wrong_frac_max'] = max([r['src'][s]['lr_wrong_frac'].get(j, 0) for r in rows.values()]) if j in rows[next(iter(rows))]['src'][s]['lr_wrong_frac'] else None
        segs = {}
        for name in SEGS:
            v = [r['src'][s]['seg'][name] for r in rows.values() if name in r['src'][s]['seg']]
            if v:
                segs[name] = {'cv_med': round(float(np.median([x[1] for x in v])), 4), 'cv_max': round(float(np.max([x[1] for x in v])), 4),
                              'len_mm_med': round(float(np.median([x[0] for x in v])) * 1000, 1)}
        out[s] = {'joints': o, 'segments': segs}
    out['rtm_tri_reproj_px_med'] = {COCO_NAMES[k]: med([r['rtm_tri_reproj_px_med'][k] for r in rows.values()]) for k in range(17)}
    out['label_triangulation_reproj_px_max'] = max(r['label_triangulation_reproj_px_max'] for r in rows.values())
    out['_sequences'] = len(rows)
    return out


# -------------------------------------------------------------------------------------------------------- fitcheck
def fitcheck(a):
    from mmdet.apis import inference_detector, init_detector
    import mmdet
    cfg = os.path.join(os.path.dirname(mmdet.__file__), '.mim/configs/rtmdet/rtmdet-ins_m_8xb32-300e_coco.py')
    det = init_detector(cfg, a.seg, device='cuda' if torch.cuda.is_available() else 'cpu')
    body = Body(a.smplx)
    rows = {}
    for subj in a.subjects.split(','):
        reps = jload(f'{a.root}/{subj}/rep_ann.json')
        for ex in EXERCISES:
            p = jload(f'{a.root}/{subj}/smplx/{ex}.json')
            J = np.array(jload(f'{a.root}/{subj}/joints3d_25/{ex}.json')['joints3d_25'])
            tops, bottoms = phase_frames(J, ex, reps[ex])
            ts = [tops[len(tops) // 2], bottoms[len(bottoms) // 2]]
            V, _ = body(p, ts)
            for cam in CAMS:
                camera = jload(f'{a.root}/{subj}/camera_parameters/{cam}/{ex}.json')
                frames = read_frames(f'{a.root}/{subj}/videos/{cam}/{ex}.mp4', ts)
                for n, t in enumerate(ts):
                    img = frames[t]
                    H, W = img.shape[:2]
                    sil = silhouette(V[n], body.faces, camera, H, W).astype(bool)
                    res = inference_detector(det, img).pred_instances
                    keep = (res.labels == 0) & (res.scores > 0.3)
                    if not keep.any():
                        rows[f'{subj}/{ex}/{cam}/{t}'] = None
                        continue
                    k = int(torch.argmax(torch.where(keep, res.scores, torch.zeros_like(res.scores))))
                    msk = res.masks[k].cpu().numpy().astype(bool)
                    inter, uni = (sil & msk).sum(), (sil | msk).sum()
                    x0, y0, x1, y1 = mesh_box(proj(V[n], camera))
                    blong = max(x1 - x0, y1 - y0)
                    # boundary distance: mesh contour pixels -> nearest mask contour pixel, / box
                    em = cv2.Canny(msk.astype(np.uint8) * 255, 50, 150) == 0
                    dt = cv2.distanceTransform(em.astype(np.uint8), cv2.DIST_L2, 3)
                    es = cv2.Canny(sil.astype(np.uint8) * 255, 50, 150) > 0
                    rows[f'{subj}/{ex}/{cam}/{t}'] = {'iou': float(inter / uni), 'precision': float(inter / sil.sum()), 'recall': float(inter / msk.sum()),
                                                     'boundary_med': float(np.median(dt[es]) / blong), 'boundary_p90': float(np.percentile(dt[es], 90) / blong),
                                                     'score': float(res.scores[k])}
            print(subj, ex, [round(v['iou'], 3) for kk, v in rows.items() if v and kk.startswith(f'{subj}/{ex}/')], flush=True)
    vals = [v for v in rows.values() if v]
    summ = {k: {'med': round(float(np.median([v[k] for v in vals])), 4), 'p10': round(float(np.percentile([v[k] for v in vals], 10)), 4),
                'min': round(float(np.min([v[k] for v in vals])), 4)} for k in ('iou', 'precision', 'recall', 'boundary_med', 'boundary_p90')}
    by_ex = {ex: round(float(np.median([v['iou'] for kk, v in rows.items() if v and f'/{ex}/' in kk])), 4) for ex in EXERCISES}
    json.dump({'summary': summ, 'iou_by_exercise': by_ex, 'n': len(vals), 'no_mask': sum(v is None for v in rows.values()), 'rows': rows}, open(a.out, 'w'), indent=1)


# ---------------------------------------------------------------------------------------------------------- sample
PLAN = (('squat', 'top'), ('pushup', 'bottom'), ('barbell_row', 'bottom'), ('squat', 'bottom'), ('pushup', 'top'))
EXTRA = ('diamond_pushup', 'barbell_dead_row')
COL_L, COL_R = (0, 220, 0), (255, 200, 0)   # BGR: left green, right cyan-ish


def sample_plan(subjects, seed=0):
    rng = np.random.default_rng(seed)
    out = []
    for r in range(len(PLAN) + 1):
        for i, subj in enumerate(subjects):
            ex, ph = PLAN[r] if r < len(PLAN) else (EXTRA[i % 2], ('top', 'bottom')[i // 2 % 2])
            out.append((subj, ex, ph, CAMS[(i + r) % 4], float(rng.random())))
    return out


def sample(a):
    subjects = a.subjects.split(',')
    plan = sample_plan(subjects)[:a.n]
    body = Body(a.smplx)
    model = load_model('m_coco17')
    os.makedirs(f'{a.out}/frames', exist_ok=True)
    os.makedirs(f'{a.overlays}', exist_ok=True)
    cand, manifest = {}, []
    for k, (subj, ex, ph, cam, u) in enumerate(plan):
        reps = jload(f'{a.root}/{subj}/rep_ann.json')[ex]
        J = np.array(jload(f'{a.root}/{subj}/joints3d_25/{ex}.json')['joints3d_25'])
        tops, bottoms = phase_frames(J, ex, reps)
        lst = tops if ph == 'top' else bottoms
        t = int(lst[int(u * len(lst))])
        p = jload(f'{a.root}/{subj}/smplx/{ex}.json')
        V, Jx = body(p, [t])
        S = {s: X[0] for s, X in body.sources(V, Jx, J[[t]]).items()}
        camera = jload(f'{a.root}/{subj}/camera_parameters/{cam}/{ex}.json')
        img = read_frames(f'{a.root}/{subj}/videos/{cam}/{ex}.mp4', [t])[t]
        H, W = img.shape[:2]
        box = mesh_box(proj(V[0], camera))
        blong = float(max(box[2] - box[0], box[3] - box[1]))
        c = (box[:2] + box[2:]) / 2
        side = blong * 1.25
        sc = a.size / side
        aff = np.array([[sc, 0, a.size / 2 - sc * c[0]], [0, sc, a.size / 2 - sc * c[1]]])
        crop = cv2.warpAffine(img, aff, (a.size, a.size), flags=cv2.INTER_LINEAR, borderValue=(40, 40, 40))
        fid = f'f{k:02d}'
        cv2.imwrite(f'{a.out}/frames/{fid}.jpg', crop, [cv2.IMWRITE_JPEG_QUALITY, 92])
        cr, mm = crop_box(cv2.cvtColor(img, cv2.COLOR_BGR2RGB), *box_to_center_scale(box))
        q, cf = predict(model, [cr])
        rtm = apply_affine(invert_affine(mm), q[0][:17])
        zb, s4 = zbuffer(V[0], camera, H, W)
        src2d = {s: apply_affine(aff, proj(X, camera)) for s, X in S.items()}
        src2d['rtmpose_m'] = apply_affine(aff, rtm)
        cand[fid] = {'subject': subj, 'exercise': ex, 'phase': ph, 'camera': cam, 'frame': t, 'scale': sc, 'box_long_px': blong,
                     'crop_size': a.size, 'sources': {s: [[None, None] if not np.isfinite(v).all() else [round(float(v[0]), 2), round(float(v[1]), 2)] for v in X] for s, X in src2d.items()},
                     'rtmpose_conf': [round(float(x), 3) for x in cf[0][:17]],
                     'occluded_gvhmr_zbuffer': occluded(S['gvhmr'], zb, s4, camera).tolist()}
        manifest.append({'id': fid, 'img': f'frames/{fid}.jpg', 'note': f'{ex} ({ph})'})
        draw_overlay(crop, src2d, f'{fid} {subj} {ex} {ph} cam{cam[:4]} t{t}', f'{a.overlays}/{fid}.jpg')
        print(fid, subj, ex, ph, cam, t, flush=True)
    # repeats: re-click the same image without the earlier clicks (repeatability), placed after frame 20 and at the end
    reps_ids = [m['id'] for m in manifest[1:len(manifest):max(1, len(manifest) // a.repeats)]][:a.repeats]
    order = manifest[:20] + [{'id': i + 'r', 'img': f'frames/{i}.jpg', 'note': '반복(재클릭)', 'repeat_of': i} for i in reps_ids[:2]] + \
        manifest[20:] + [{'id': i + 'r', 'img': f'frames/{i}.jpg', 'note': '반복(재클릭)', 'repeat_of': i} for i in reps_ids[2:]]
    json.dump(cand, open(f'{a.out}/candidates.json', 'w'))
    open(f'{a.out}/manifest.js', 'w').write('window.MANIFEST = ' + json.dumps(order, ensure_ascii=False) + ';\n')


TAGS = ('N', 'LEy', 'REy', 'LEa', 'REa', 'LS', 'RS', 'LE', 'RE', 'LW', 'RW', 'LH', 'RH', 'LK', 'RK', 'LA', 'RA')


def draw_overlay(crop, src2d, title, path):
    """Two panels: left = gvhmr label (dot) vs RTMPose-m (+); right = mocap (ring) and SMPL-X native (square) vs label (dot)."""
    panels = []
    for kind in ('rtm', 'alt'):
        im = crop.copy()
        for k in range(17):
            col = COL_L if k % 2 == 1 else COL_R
            if k == 0:
                col = (0, 160, 255)
            lab = src2d['gvhmr'][k]
            cv2.circle(im, (int(lab[0]), int(lab[1])), 5, col, -1)
            cv2.putText(im, TAGS[k], (int(lab[0]) + 6, int(lab[1]) - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.42, col, 1)
            if kind == 'rtm':
                q = src2d['rtmpose_m'][k]
                cv2.drawMarker(im, (int(q[0]), int(q[1])), (0, 0, 255) if k % 2 else (255, 0, 255), cv2.MARKER_CROSS, 14, 2)
            else:
                q = src2d['mocap'][k]
                if np.isfinite(q).all():
                    cv2.circle(im, (int(q[0]), int(q[1])), 8, (255, 255, 255), 2)
                q = src2d['native'][k]
                cv2.drawMarker(im, (int(q[0]), int(q[1])), (0, 255, 255), cv2.MARKER_SQUARE, 10, 2)
        legend = '● label(SMPL-X GVHMR)  + RTMPose-m' if kind == 'rtm' else '● label  ○ mocap  □ SMPL-X joint centre'
        cv2.putText(im, title, (6, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        cv2.putText(im, legend.replace('●', 'dot').replace('○', 'ring').replace('□', 'square'), (6, im.shape[0] - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        panels.append(im)
    cv2.imwrite(path, np.hstack(panels), [cv2.IMWRITE_JPEG_QUALITY, 88])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=('audit', 'measure', 'summary', 'fitcheck', 'sample'))
    ap.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d/train'))
    ap.add_argument('--smplx', default=os.path.expanduser('~/models/smplx'))
    ap.add_argument('--subjects', default='s03,s04,s05,s07,s08,s09,s10,s11')
    ap.add_argument('--out', required=True)
    ap.add_argument('--stride', type=int, default=5)
    ap.add_argument('--model-every', type=int, default=2, help='measure: RTMPose on every n-th sampled frame')
    ap.add_argument('--seg', default=os.path.expanduser('~/models/flv/rtmdet-ins_m_8xb32-300e_coco_20221123_001039-6eba602e.pth'))
    ap.add_argument('--n', type=int, default=40)
    ap.add_argument('--repeats', type=int, default=5)
    ap.add_argument('--size', type=int, default=800)
    ap.add_argument('--overlays', default='')
    a = ap.parse_args()
    if a.cmd == 'summary':
        print(json.dumps(summarize(a.out), indent=1))
    else:
        globals()[a.cmd](a)


if __name__ == '__main__':
    main()
