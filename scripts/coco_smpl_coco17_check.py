"""Approach A of track fit3d-label-verify: test the SMPL -> COCO17 label definitions on HUMAN COCO keypoints (no Fit3D images).

Public SMPL fits of COCO persons, projected with their own (weak-perspective) camera, compared against the human COCO
keypoints of the same person:
  eft    EFT COCO2014-Val-ver10 (Joo et al., CC-BY-NC 4.0). EFT fitted SMPL to the COCO 2D keypoints using SPIN's joint map
         (shoulders/elbows/wrists/knees = SMPL joint centres, face = SMPL vertices 332/2800/6260/583/4071) but with COCO HIPS
         DISABLED and ankles reduced to a shin-orientation term (eftFitter.py). => hips are NOT circular; shoulders, face,
         elbows, wrists, knees are fitted to the 'native' definition (circular for native, NOT a test of it).
  dp     same persons re-fitted to DensePose-COCO surface correspondences ONLY (Guler et al., CC-BY-NC 4.0; no keypoint
         term at all), initialised from EFT, pose prior = L2 to the EFT pose with weight --lam (swept). Limbs are then an
         independent fit-quality control and every joint definition is tested on equal footing.
Definitions applied to the SMPL vertices (same matrices as the Fit3D chain, without the smplx2smpl step):
  gvhmr  GVHMR/WHAM J_regressor_coco [17x6890]
  native SMPL joint centres (hips 1/2, shoulders 16/17, ...) + face vertices (SPIN / smplx-lib 'smplh' vertex ids)
  h36m   WHAM/SPIN J_regressor_h36m (body 12, geometry-mapped L/R as in verify_fit3d_coco17.py)
Run on Home (conda bpt-mmpose, PYTHONPATH incl. the smplx library). Output = aggregate JSON only.
"""

import argparse
import hashlib
import json
import os
import sys
import time

import numpy as np
import torch

NAMES = ('nose', 'l_eye', 'r_eye', 'l_ear', 'r_ear', 'l_shoulder', 'r_shoulder', 'l_elbow', 'r_elbow', 'l_wrist', 'r_wrist',
         'l_hip', 'r_hip', 'l_knee', 'r_knee', 'l_ankle', 'r_ankle')
NATIVE_J = {5: 16, 6: 17, 7: 18, 8: 19, 9: 20, 10: 21, 11: 1, 12: 2, 13: 4, 14: 5, 15: 7, 16: 8}
FACE_V = {0: 332, 1: 2800, 2: 6260, 3: 583, 4: 4071}
H36M = {5: 11, 6: 14, 7: 12, 8: 15, 9: 13, 10: 16, 11: 1, 12: 4, 13: 2, 14: 5, 15: 3, 16: 6}
LIMBS = (7, 8, 9, 10, 13, 14, 15, 16)
GROUPS = {'face': (0, 1, 2, 3, 4), 'shoulder': (5, 6), 'elbow': (7, 8), 'wrist': (9, 10), 'hip': (11, 12), 'knee': (13, 14), 'ankle': (15, 16)}
EFT_FITTED = {'nose': 'native', 'eyes': 'native', 'ears': 'native', 'shoulder': 'native', 'elbow': 'native', 'wrist': 'native',
              'hip': 'NOT fitted', 'knee': 'native', 'ankle': 'orientation only'}


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


# ------------------------------------------------------------------------------------------------------ data
def load(a):
    eft = json.load(open(a.eft))['data']
    kp = {}
    for f in a.coco_kp:
        for x in json.load(open(f))['annotations']:
            kp[x['id']] = (np.array(x['keypoints'], float).reshape(17, 3), np.array(x['bbox'], float))
    dp = {}
    for f in a.densepose:
        for x in json.load(open(f))['annotations']:
            if 'dp_x' in x:
                dp[x['id']] = x
    return eft, kp, dp


class DPMap:
    """DensePose (I, U, V) -> SMPL vertex triple + barycentric weights (vectorised IUV2FBC of densepose_methods.py)."""

    def __init__(self, mat, flip_v=False):
        from scipy.io import loadmat
        m = loadmat(mat)
        self.fi = m['All_FaceIndices'].squeeze()
        self.faces = m['All_Faces'] - 1
        self.u, self.v = m['All_U_norm'].squeeze(), m['All_V_norm'].squeeze()
        self.vert = m['All_vertices'][0] - 1
        self.flip_v = flip_v

    def __call__(self, I, U, V):
        V = 1 - V if self.flip_v else V
        out_v, out_w = np.zeros((len(I), 3), int), np.zeros((len(I), 3))
        for part in np.unique(I):
            sel = np.where(I == part)[0]
            F = self.faces[self.fi == part]                    # [F,3] densepose vertex ids
            P0 = np.stack([self.u[F[:, 0]], self.v[F[:, 0]]], -1)
            e1 = np.stack([self.u[F[:, 1]], self.v[F[:, 1]]], -1) - P0
            e2 = np.stack([self.u[F[:, 2]], self.v[F[:, 2]]], -1) - P0
            det = e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]
            det = np.where(np.abs(det) < 1e-12, 1e-12, det)
            p = np.stack([U[sel], V[sel]], -1)[:, None] - P0[None]   # [N,F,2]
            b1 = (p[..., 0] * e2[:, 1] - p[..., 1] * e2[:, 0]) / det
            b2 = (e1[:, 0] * p[..., 1] - e1[:, 1] * p[..., 0]) / det
            b0 = 1 - b1 - b2
            inside = (b0 >= -1e-6) & (b1 >= -1e-6) & (b2 >= -1e-6)
            for n, i in enumerate(sel):
                hit = np.where(inside[n])[0]
                if len(hit):
                    f = hit[0]
                    out_v[i], out_w[i] = self.vert[F[f]], (b0[n, f], b1[n, f], b2[n, f])
                else:   # nearest UV vertex, as the original
                    uv = np.stack([self.u[F], self.v[F]], -1)        # [F,3,2]
                    d = np.linalg.norm(uv - np.array([U[i], V[i]]), axis=-1)
                    f, c = np.unravel_index(np.argmin(d), d.shape)
                    out_v[i], out_w[i] = self.vert[F[f, c]], np.eye(3)[0]
                    out_v[i, 1:] = out_v[i, 0]
        return out_v, out_w


# ----------------------------------------------------------------------------------------------------- model
class Smpl:
    def __init__(self, a, device):
        import smplx
        self.m = smplx.SMPLLayer(model_path=a.smpl, num_betas=10).to(device)
        self.dev = device
        self.coco = torch.tensor(np.load(f'{a.wham}/J_regressor_coco.npy'), dtype=torch.float32, device=device)
        self.h36m = torch.tensor(np.load(f'{a.wham}/J_regressor_h36m.npy'), dtype=torch.float32, device=device)

    def verts(self, go, bp, betas):
        o = self.m(global_orient=go, body_pose=bp, betas=betas)
        return o.vertices, o.joints

    def sources(self, V, J):
        B = V.shape[0]
        gv = torch.einsum('kv,bvc->bkc', self.coco, V)
        nat = torch.zeros(B, 17, 3, device=V.device)
        h = torch.full((B, 17, 3), float('nan'), device=V.device)
        hh = torch.einsum('kv,bvc->bkc', self.h36m, V)
        for c, j in NATIVE_J.items():
            nat[:, c] = J[:, j]
            h[:, c] = hh[:, H36M[c]]
        for c, v in FACE_V.items():
            nat[:, c] = V[:, v]
        return {'gvhmr': gv, 'native': nat, 'h36m': h}


def to_img(X, cam, center, bscale):
    """EFT weak perspective (imutils.convert_smpl_to_bbox, bAppTransFirst=False): n = s * X_xy + t; image = center + n * (bbox_scale*200)/2.
    Checked on 1500 EFT persons vs their fitted joints: this order leaves mean residual (-0.002, -0.003) of the box,
    s * (X + t) leaves (-0.003, -0.019)."""
    n = cam[:, None, :1] * X[..., :2] + cam[:, None, 1:]
    return center[:, None] + n * (bscale[:, None, None] * 100.0)


def rotmat_to_aa(R):
    from scipy.spatial.transform import Rotation
    return Rotation.from_matrix(R.reshape(-1, 3, 3)).as_rotvec().reshape(*R.shape[:-2], 3)


def aa_to_rotmat(aa):
    from smplx.lbs import batch_rodrigues
    return batch_rodrigues(aa.reshape(-1, 3)).reshape(*aa.shape[:-1], 3, 3)


# ------------------------------------------------------------------------------------------------------- fit
def fit_dp(body, init, pts, lam, iters, device, huber=0.02):
    """init: dict of tensors (aa [B,24,3], betas [B,10], cam [B,3], center [B,2], bscale [B]); pts: (vid [B,P,3], w [B,P,3],
    xy [B,P,2], mask [B,P]). DensePose-only reprojection (Huber, in bbox units) + lam * ||pose - pose_EFT||^2 + 1e-3 ||betas||^2."""
    aa = init['aa'].clone().requires_grad_(True)
    betas = init['betas'].clone().requires_grad_(True)
    cam = init['cam'].clone().requires_grad_(True)
    vid, w, xy, mask = pts
    opt = torch.optim.Adam([aa, betas, cam], lr=0.01)
    B = aa.shape[0]
    bidx = torch.arange(B, device=device)[:, None, None]
    for it in range(iters):
        R = aa_to_rotmat(aa)
        V, _ = body.verts(R[:, 0], R[:, 1:], betas)
        S = (V[bidx, vid] * w[..., None]).sum(2)           # [B,P,3]
        uv = to_img(S, cam, init['center'], init['bscale'])
        r = (uv - xy).norm(dim=-1) / (init['bscale'][:, None] * 200)
        data = torch.where(r < huber, 0.5 * r ** 2, huber * (r - 0.5 * huber))
        data = (data * mask).sum(1) / mask.sum(1).clamp(min=1)
        prior = ((aa[:, 1:] - init['aa'][:, 1:]) ** 2).mean((1, 2))
        loss = (data + lam * prior * 1e-3 + 1e-6 * (betas ** 2).sum(1)).sum()
        opt.zero_grad()
        loss.backward()
        opt.step()
    with torch.no_grad():
        R = aa_to_rotmat(aa)
        V, J = body.verts(R[:, 0], R[:, 1:], betas)
        S = (V[bidx, vid] * w[..., None]).sum(2)
        r = (to_img(S, cam, init['center'], init['bscale']) - xy).norm(dim=-1) / (init['bscale'][:, None] * 200)
        res = ((r * mask).sum(1) / mask.sum(1).clamp(min=1))
        pose_change = (aa[:, 1:] - init['aa'][:, 1:]).norm(dim=-1).mean(1)
    return V, J, cam.detach(), res, pose_change


def dp_points(dpmap, ann, P):
    I = np.array(ann['dp_I']).astype(int)
    U, Vv = np.array(ann['dp_U']), np.array(ann['dp_V'])
    x0, y0, w, h = ann['bbox']
    xy = np.stack([x0 + np.array(ann['dp_x']) / 256.0 * w, y0 + np.array(ann['dp_y']) / 256.0 * h], -1)
    vid, wt = dpmap(I, U, Vv)
    n = min(len(I), P)
    out = (np.zeros((P, 3), int), np.zeros((P, 3)), np.zeros((P, 2)), np.zeros(P))
    out[0][:n], out[1][:n], out[2][:n], out[3][:n] = vid[:n], wt[:n], xy[:n], 1
    return out


# --------------------------------------------------------------------------------------------------- metrics
def body_frame(err, ref):
    """err [N,17,2] (human - label), ref [N,17,2] label points that define the axes -> (up, side) per joint / torso length."""
    hip_c, sh_c = ref[:, 11:13].mean(1), ref[:, 5:7].mean(1)
    up = sh_c - hip_c
    torso = np.linalg.norm(up, axis=1, keepdims=True) + 1e-6
    up = up / torso
    side = ref[:, 12] - ref[:, 11]       # towards the person's right
    side = side - (side * up).sum(1, keepdims=True) * up
    side = side / (np.linalg.norm(side, axis=1, keepdims=True) + 1e-6)
    return (err * up[:, None]).sum(-1) / torso, (err * side[:, None]).sum(-1) / torso, torso[:, 0]


def strata(J3, ref2d):
    """J3 SMPL joints in fit-camera coords [N,24,3] (weak persp: z = depth axis). side: hip axis mostly along depth;
    horiz: 2D torso within 30 deg of image horizontal (lying / prone proxy, COCO has no gravity)."""
    hip = J3[:, 1] - J3[:, 2]
    hip = hip / (np.linalg.norm(hip, axis=1, keepdims=True) + 1e-9)
    side = np.abs(hip[:, 2]) > 0.7
    t = ref2d[:, 5:7].mean(1) - ref2d[:, 11:13].mean(1)
    horiz = np.abs(t[:, 1]) < np.tan(np.radians(30)) * np.abs(t[:, 0])
    return {'side': side, 'horiz': horiz, 'other': ~side & ~horiz}


def metrics(S2, human, box_long, ref, mask_sel, vis_min=2):
    """S2 dict source -> [N,17,2]; human [N,17,3]; -> per source per joint stats over persons in mask_sel."""
    out = {}
    hv = human[..., 2] >= vis_min
    for s, X in S2.items():
        err = human[..., :2] - X
        e = np.linalg.norm(err, axis=-1) / box_long[:, None]
        u, sd, _ = body_frame(err, ref)
        o = {}
        for k in range(17):
            m = mask_sel & hv[:, k] & np.isfinite(e[:, k])
            if m.sum() < 10:
                continue
            o[NAMES[k]] = {'n': int(m.sum()), 'err_med': round(float(np.median(e[m, k])), 4), 'err_p90': round(float(np.percentile(e[m, k], 90)), 4),
                           'pck05': round(float((e[m, k] < 0.05).mean()), 3), 'pck10': round(float((e[m, k] < 0.10).mean()), 3),
                           'up_mean': round(float(np.mean(u[m, k])), 4), 'up_med': round(float(np.median(u[m, k])), 4),
                           'side_mean': round(float(np.mean(sd[m, k])), 4), 'up_sd': round(float(np.std(u[m, k])), 4)}
        out[s] = o
    return out


def offset_test(S2, human, box_long, ref, sel, ids, vis_min=2):
    """Fixed per-joint (up, side) offset in body axes estimated on even annIds, applied to odd ones: error before / after."""
    out = {}
    hv = human[..., 2] >= vis_min
    tr, te = sel & (ids % 2 == 0), sel & (ids % 2 == 1)
    hip_c, sh_c = ref[:, 11:13].mean(1), ref[:, 5:7].mean(1)
    up = sh_c - hip_c
    torso = np.linalg.norm(up, axis=1, keepdims=True) + 1e-6
    up = up / torso
    side = ref[:, 12] - ref[:, 11]
    side = side - (side * up).sum(1, keepdims=True) * up
    side = side / (np.linalg.norm(side, axis=1, keepdims=True) + 1e-6)
    for s, X in S2.items():
        err = human[..., :2] - X
        u, sd, _ = body_frame(err, ref)
        o = {}
        for k in range(17):
            a, b = tr & hv[:, k] & np.isfinite(u[:, k]), te & hv[:, k] & np.isfinite(u[:, k])
            if a.sum() < 20 or b.sum() < 20:
                continue
            du, ds = float(np.median(u[a, k])), float(np.median(sd[a, k]))
            Xc = X[:, k] + (du * up + ds * side) * torso
            e0 = np.linalg.norm(err[b, k], axis=-1) / box_long[b]
            e1 = np.linalg.norm(human[b, k, :2] - Xc[b], axis=-1) / box_long[b]
            o[NAMES[k]] = {'offset_up': round(du, 4), 'offset_side': round(ds, 4), 'n_test': int(b.sum()),
                           'err_med_before': round(float(np.median(e0)), 4), 'err_med_after': round(float(np.median(e1)), 4),
                           'pck05_before': round(float((e0 < 0.05).mean()), 3), 'pck05_after': round(float((e1 < 0.05).mean()), 3)}
        out[s] = o
    return out


def limb_anchor(S2, human, ref):
    """Per person 2D translation + isotropic scale that maps the reference label's visible limbs onto the human limbs
    (least squares, >= 4 limbs), applied to every source. Removes global fit error (position / size) using the 8 limb points
    only, so shoulder / hip / face offsets that remain are definition offsets relative to the limbs. Limb errors after this
    are fitted, not independent."""
    vis = human[:, LIMBS, 2] >= 2
    out = {s: np.full_like(X, np.nan) for s, X in S2.items()}
    ok = vis.sum(1) >= 4
    for n in np.where(ok)[0]:
        x, h = ref[n, LIMBS][vis[n]], human[n, LIMBS, :2][vis[n]]
        xm, hm = x.mean(0), h.mean(0)
        k = ((h - hm) * (x - xm)).sum() / max(((x - xm) ** 2).sum(), 1e-9)
        for s, X in S2.items():
            out[s][n] = hm + k * (X[n] - xm)
    return out, ok


def evaluate(S2, J3, human, bbox, ids, limb_thr):
    box_long = np.maximum(bbox[:, 2], bbox[:, 3])
    ref = S2['gvhmr']
    st = strata(J3, ref)
    # fit-quality control: median gvhmr limb error over visible limbs (needs >= 4)
    e = np.linalg.norm(human[..., :2] - ref, axis=-1) / box_long[:, None]
    lv = human[:, LIMBS, 2] >= 2
    le = np.where(lv, e[:, LIMBS], np.nan)
    limb_med = np.nanmedian(np.where(lv.sum(1, keepdims=True) >= 4, le, np.nan), axis=1)
    good = np.isfinite(limb_med) & (limb_med < limb_thr)
    allm = np.ones(len(ids), bool)
    res = {'n_persons': len(ids), 'n_limb_ok': int(good.sum()), 'limb_thr': limb_thr,
           'strata_n': {k: int(v.sum()) for k, v in st.items()}, 'strata_n_limb_ok': {k: int((v & good).sum()) for k, v in st.items()}}
    res['all'] = metrics(S2, human, box_long, ref, allm)
    res['limb_ok'] = metrics(S2, human, box_long, ref, good)
    for k, v in st.items():
        res[f'limb_ok_{k}'] = metrics(S2, human, box_long, ref, good & v)
    occl = np.concatenate([human[..., :2], (human[..., 2:] == 1) * 2.0], -1)   # COCO v=1 (labelled, not visible) only
    res['occluded_v1_limb_ok'] = metrics(S2, occl, box_long, ref, good)
    res['offset_limb_ok'] = offset_test(S2, human, box_long, ref, good, ids)
    A, aok = limb_anchor(S2, human, ref)
    res['anchored_all'] = metrics(A, human, box_long, A['gvhmr'], aok)
    for k, v in st.items():
        res[f'anchored_{k}'] = metrics(A, human, box_long, A['gvhmr'], aok & v)
    res['offset_anchored'] = offset_test(A, human, box_long, A['gvhmr'], aok, ids)
    return res


# ----------------------------------------------------------------------------------------------------------- main
def run(a):
    t0 = time.time()
    device = 'cuda' if (a.device == 'cuda' and torch.cuda.is_available()) else 'cpu'
    eft, kp, dp = load(a)
    body = Smpl(a, device)
    eft = [x for x in eft if x['annotId'] in kp]
    if a.limit:
        eft = eft[:a.limit]
    ids = np.array([x['annotId'] for x in eft])
    pose = np.array([x['parm_pose'] for x in eft], np.float32)        # [N,24,3,3]
    betas = np.array([x['parm_shape'] for x in eft], np.float32)
    cam = np.array([x['parm_cam'] for x in eft], np.float32)
    center = np.array([x['bbox_center'] for x in eft], np.float32)
    bscale = np.array([x['bbox_scale'] for x in eft], np.float32)
    human = np.array([kp[i][0] for i in ids])
    bbox = np.array([kp[i][1] for i in ids])
    T = lambda z: torch.tensor(z, device=device)
    out = {'inputs': {'eft': [a.eft, sha(a.eft)], 'coco_kp': [[f, sha(f)] for f in a.coco_kp], 'densepose': [[f, sha(f)] for f in a.densepose],
                      'uv': [a.uv, sha(a.uv)], 'smpl': [a.smpl, sha(a.smpl)], 'wham_regressors': {f: sha(f'{a.wham}/{f}') for f in ('J_regressor_coco.npy', 'J_regressor_h36m.npy')}},
           'eft_fitted_definition': EFT_FITTED}

    # ---- A1: EFT as released
    S2, J3 = {s: [] for s in ('gvhmr', 'native', 'h36m')}, []
    with torch.no_grad():
        for i in range(0, len(ids), 512):
            sl = slice(i, i + 512)
            V, J = body.verts(T(pose[sl, 0]), T(pose[sl, 1:]), T(betas[sl]))
            for s, X in body.sources(V, J).items():
                S2[s].append(to_img(X, T(cam[sl]), T(center[sl]), T(bscale[sl])).cpu().numpy())
            J3.append(J[:, :24].cpu().numpy())
    S2 = {s: np.concatenate(v) for s, v in S2.items()}
    J3 = np.concatenate(J3)
    # projection sanity: EFT's own gt_keypoint_2d (image px) vs COCO human keypoints
    g = np.array([x['gt_keypoint_2d'] for x in eft])[:, 25 + 7, :2]      # GT 'Right Elbow'
    hv = human[:, 8, 2] > 0
    out['check_eft_gt_vs_coco_relbow_px_med'] = float(np.median(np.linalg.norm(g[hv] - human[hv, 8, :2], axis=-1)))
    out['eft'] = evaluate(S2, J3, human, bbox, ids, a.limb_thr)
    print('eft done', round(time.time() - t0), flush=True)

    # ---- A2: DensePose-only refit
    sel = np.array([i in dp for i in ids])
    out['dp_overlap'] = int(sel.sum())
    if sel.any() and not a.skip_dp:
        idx = np.where(sel)[0]
        best = None
        for flip in (False, True):   # V convention check on the EFT init: smaller residual wins
            dpm = DPMap(a.uv, flip)
            pts = [dp_points(dpm, dp[ids[i]], a.max_pts) for i in idx[:200]]
            P = [T(np.stack([p[k] for p in pts])) for k in range(4)]
            with torch.no_grad():
                sl = idx[:200]
                V, _ = body.verts(T(pose[sl, 0]), T(pose[sl, 1:]), T(betas[sl]))
                bi = torch.arange(len(sl), device=device)[:, None, None]
                Sx = (V[bi, P[0].long()] * P[1].float()[..., None]).sum(2)
                r = (to_img(Sx, T(cam[sl]), T(center[sl]), T(bscale[sl])) - P[2].float()).norm(dim=-1) / (T(bscale[sl])[:, None] * 200)
                res = float(((r * P[3]).sum(1) / P[3].sum(1)).median())
            out[f'dp_init_residual_flipV={flip}'] = res
            if best is None or res < best[0]:
                best = (res, flip)
        dpm = DPMap(a.uv, best[1])
        out['dp_flipV'] = best[1]
        pts = [dp_points(dpm, dp[ids[i]], a.max_pts) for i in idx]
        out['dp_points_per_person_med'] = float(np.median([p[3].sum() for p in pts]))
        aa = rotmat_to_aa(pose[idx]).astype(np.float32)
        for lam in a.lams:
            S2d, J3d, resid, pchg = {s: [] for s in ('gvhmr', 'native', 'h36m')}, [], [], []
            for b in range(0, len(idx), a.batch):
                bi = idx[b:b + a.batch]
                pp = pts[b:b + a.batch]
                P = (T(np.stack([p[0] for p in pp])).long(), T(np.stack([p[1] for p in pp]).astype(np.float32)),
                     T(np.stack([p[2] for p in pp]).astype(np.float32)), T(np.stack([p[3] for p in pp]).astype(np.float32)))
                init = {'aa': T(aa[b:b + a.batch]), 'betas': T(betas[bi]), 'cam': T(cam[bi]), 'center': T(center[bi]), 'bscale': T(bscale[bi])}
                V, J, c, r, pc = fit_dp(body, init, P, lam, a.iters, device)
                with torch.no_grad():
                    for s, X in body.sources(V, J).items():
                        S2d[s].append(to_img(X, c, init['center'], init['bscale']).cpu().numpy())
                J3d.append(J[:, :24].detach().cpu().numpy())
                resid.append(r.cpu().numpy())
                pchg.append(pc.cpu().numpy())
            S2d = {s: np.concatenate(v) for s, v in S2d.items()}
            r = np.concatenate(resid)
            ev = evaluate(S2d, np.concatenate(J3d), human[idx], bbox[idx], ids[idx], a.limb_thr)
            ev['dp_residual_med'] = float(np.median(r))
            ev['pose_change_rad_med'] = float(np.median(np.concatenate(pchg)))
            out[f'dp_lam{lam}'] = ev
            print('dp lam', lam, 'resid', round(float(np.median(r)), 4), round(time.time() - t0), flush=True)
            json.dump(out, open(a.out, 'w'), indent=1)
        # EFT (as released) on the same persons, for a like-for-like comparison
        out['eft_on_dp_persons'] = evaluate({s: X[idx] for s, X in S2.items()}, J3[idx], human[idx], bbox[idx], ids[idx], a.limb_thr)
    out['seconds'] = round(time.time() - t0)
    json.dump(out, open(a.out, 'w'), indent=1)


def selftest():
    # body_frame: a point shifted exactly one torso up must read up=+1, side=0
    ref = np.zeros((1, 17, 2))
    ref[0, 11], ref[0, 12], ref[0, 5], ref[0, 6] = (-1, 0), (1, 0), (-1, -2), (1, -2)
    err = np.zeros((1, 17, 2))
    err[0, 0] = (0, -2)
    u, s, t = body_frame(err, ref)
    assert abs(u[0, 0] - 1) < 1e-5 and abs(s[0, 0]) < 1e-5 and abs(t[0] - 2) < 1e-5
    err[0, 0] = (2, 0)   # towards r_hip = person's right
    u, s, _ = body_frame(err, ref)
    assert abs(s[0, 0] - 1) < 1e-5 and abs(u[0, 0]) < 1e-5
    print('selftest ok')


def main():
    ap = argparse.ArgumentParser()
    H = os.path.expanduser
    ap.add_argument('--eft', default=H('~/datasets/eft/COCO2014-Val-ver10.json'))
    ap.add_argument('--coco-kp', nargs='+', default=[H('~/datasets/coco/annotations/person_keypoints_val2017.json'), H('~/datasets/coco/annotations/person_keypoints_train2017.json')])
    ap.add_argument('--densepose', nargs='+', default=[H('~/datasets/densepose/densepose_coco_2014_minival.json'), H('~/datasets/densepose/densepose_coco_2014_valminusminival.json')])
    ap.add_argument('--uv', default=H('~/datasets/densepose/uv/UV_Processed.mat'))
    ap.add_argument('--smpl', default=H('~/models/smpl/SMPL_NEUTRAL.pkl'))
    ap.add_argument('--wham', default=H('~/rtmft/ext/wham/body_models'))
    ap.add_argument('--lams', type=float, nargs='+', default=[100.0, 10.0, 1.0])
    ap.add_argument('--iters', type=int, default=300)
    ap.add_argument('--batch', type=int, default=256)
    ap.add_argument('--max-pts', type=int, default=200)
    ap.add_argument('--limb-thr', type=float, default=0.05)
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--skip-dp', action='store_true')
    ap.add_argument('--device', default='cpu')
    ap.add_argument('--out', default='')
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    run(a)


if __name__ == '__main__':
    sys.exit(main())
