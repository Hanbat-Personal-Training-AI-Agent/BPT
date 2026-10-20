"""Exercise3D person boxes for detector fine-tuning / evaluation (Mac or Home; local data only; never open frames with Read).

Box = min / max of the Exercise3D SMPL fit mesh (smpl_fit.npz: shared betas, per-frame pose, transl, metre scale; fitted
to the Sapiens2 triangulation, so pseudo labels, NOT ground truth) projected with that camera, clipped to the image —
the same body-surface definition as build_det_fit3d.py (SMPL-X mesh on Fit3D). SMPL model = the official pkl of the fit's
gender (read with stubs for chumpy / scipy.sparse, which are not needed for the arrays). P1 sequences for training,
--eval-only allows P2 / P3 (held out, D-F3-02). Writes <out>/<seq>_<cam>_<frame>.jpg + COCO-format <out>/<name>.json.
--check prints, per sequence, the median distance between the fit's SMPL joints and canonical_3d / scale (m) to verify
the frame / scale convention before any box is used. Note: the fit (Exercise3D-Dataset-Pipeline tools/fit_smpl_sequence.py)
minimises |joints * scale - canonical| and stores scale as "arbitrary_to_meters", so metres = canonical / scale; its
reported per_frame_joint_rmse_m multiplies by scale instead of dividing (about 1/scale^2 = ~18x too small).
QA per image: IoU between the mesh box and the tight box of the Sapiens2 keypoints (conf > 0.5).

usage: build_det_ex3d.py --labels DIR --videos DIR --gt gt.json --smpl DIR --out DIR --name ex3d_p1 [--seqs ...] [--stride 10]
"""
import argparse, ast, json, os, pickle, sys
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent), str(HERE)]
from xs_data import HELD_E3D, P1  # noqa: E402

PKL = {'male': 'basicmodel_m_lbs_10_207_0_v1.1.0.pkl', 'female': 'basicmodel_f_lbs_10_207_0_v1.1.0.pkl',
       'neutral': 'basicmodel_neutral_lbs_10_207_0_v1.1.0.pkl'}
SMPL_TO_CANON = {1: 'left_hip', 2: 'right_hip', 4: 'left_knee', 5: 'right_knee', 7: 'left_ankle', 8: 'right_ankle',
                 16: 'left_shoulder', 17: 'right_shoulder', 18: 'left_elbow', 19: 'right_elbow', 20: 'left_wrist', 21: 'right_wrist'}


class _Stub:
    def __init__(self, *a, **k): pass

    def __setstate__(self, state):
        self.__dict__.update(state if isinstance(state, dict) else {'_state': state})


class _Unpickler(pickle.Unpickler):
    def find_class(self, mod, name):
        return _Stub if mod.startswith(('chumpy', 'scipy')) else super().find_class(mod, name)


def load_smpl(path):
    d = _Unpickler(open(path, 'rb'), encoding='latin1').load()
    jr = d['J_regressor'].__dict__
    J = np.zeros(jr['_shape']); ip, ix, dv = jr['indptr'], jr['indices'], jr['data']
    for c in range(J.shape[1]):  # csc: column c holds rows ix[ip[c]:ip[c+1]]
        J[ix[ip[c]:ip[c + 1]], c] = dv[ip[c]:ip[c + 1]]
    sd = d['shapedirs'].__dict__['x'] if isinstance(d['shapedirs'], _Stub) else d['shapedirs']
    return dict(vt=np.asarray(d['v_template'], float), sd=np.asarray(sd, float)[:, :, :10], pd=np.asarray(d['posedirs'], float),
                w=np.asarray(d['weights'], float), Jr=J, parents=np.asarray(d['kintree_table'][0], np.int64))


def rodrigues(r):
    th = np.linalg.norm(r, axis=-1, keepdims=True).clip(1e-12)
    k = r / th; K = np.zeros(r.shape[:-1] + (3, 3))
    K[..., 0, 1], K[..., 0, 2], K[..., 1, 0], K[..., 1, 2], K[..., 2, 0], K[..., 2, 1] = -k[..., 2], k[..., 1], k[..., 2], -k[..., 0], -k[..., 1], k[..., 0]
    s, c = np.sin(th)[..., None], np.cos(th)[..., None]
    return np.eye(3) + s * K + (1 - c) * K @ K


def smpl_forward(m, betas, pose, transl):
    """standard SMPL LBS -> vertices [T,6890,3], joints [T,24,3] (metres, the fit's frame)."""
    T = len(pose)
    vs = m['vt'] + np.einsum('vck,k->vc', m['sd'], betas)
    J = m['Jr'] @ vs
    R = rodrigues(pose.reshape(T, 24, 3))
    pf = (R[:, 1:] - np.eye(3)).reshape(T, -1)
    v = vs + np.einsum('vck,tk->tvc', m['pd'], pf)
    G = np.zeros((T, 24, 4, 4)); G[:, :, 3, 3] = 1
    for j in range(24):
        q = m['parents'][j] if j else -1
        loc = np.zeros((T, 4, 4)); loc[:, :3, :3] = R[:, j]; loc[:, 3, 3] = 1
        loc[:, :3, 3] = J[j] - (J[q] if q >= 0 else 0)
        G[:, j] = loc if q < 0 else G[:, q] @ loc
    joints = G[:, :, :3, 3].copy()
    A = G.copy(); A[:, :, :3, 3] -= np.einsum('tjcd,jd->tjc', G[:, :, :3, :3], J)
    M = np.einsum('vj,tjcd->tvcd', m['w'], A)
    v = np.einsum('tvcd,tvd->tvc', M[..., :3, :3], v) + M[..., :3, 3]
    return v + transl[:, None], joints + transl[:, None]


def iou_xyxy(a, b):
    x0, y0, x1, y1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    i = max(0.0, x1 - x0) * max(0.0, y1 - y0)
    return float(i / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i + 1e-9))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--labels', required=True); ap.add_argument('--videos', required=True); ap.add_argument('--gt', required=True)
    ap.add_argument('--smpl', required=True); ap.add_argument('--out', required=True); ap.add_argument('--name', required=True)
    ap.add_argument('--seqs', default=','.join(P1)); ap.add_argument('--stride', type=int, default=10)
    ap.add_argument('--eval-only', action='store_true'); ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    gt = json.load(open(a.gt)); os.makedirs(a.out, exist_ok=True)
    images, anns, models, report = [], [], {}, {}
    for seq in a.seqs.split(','):
        assert a.eval_only or seq not in HELD_E3D, f'{seq} is held out (P2/P3): evaluation only'
        L = f'{a.labels}/{seq}'
        fit = np.load(f'{L}/smpl_fit/smpl_fit.npz'); meta = json.load(open(f'{L}/smpl_fit/metadata.json'))
        gender = meta.get('gender', 'neutral')
        m = models.setdefault(gender, load_smpl(f'{a.smpl}/{PKL[gender]}'))
        fr = np.arange(0, len(fit['frame_index']), a.stride)
        pose = np.concatenate([fit['global_orient'][fr], fit['body_pose'][fr]], 1)
        V, Jt = smpl_forward(m, fit['betas'][0], pose, fit['transl'][fr])
        s = float(fit['scale_arbitrary_to_meters'])
        z = np.load(f'{L}/geometry/canonical_3d.npz'); names = list(z['joint_names'])
        C = z['keypoints_3d'][fr].astype(float) / s  # metres = canonical / scale (see docstring)
        err = [np.nanmedian(np.linalg.norm(Jt[:, j] - C[:, names.index(n)], axis=-1)) for j, n in SMPL_TO_CANON.items()]
        report[seq] = dict(gender=gender, joint_err_m_median=round(float(np.median(err)), 3), frames=int(len(fr)))
        if a.check:
            print(seq, report[seq], flush=True); continue
        cg = json.load(open(f'{L}/geometry/metadata.json'))['camera_geometry']
        cg = ast.literal_eval(cg) if isinstance(cg, str) else cg
        ex = gt[seq]['exercise']
        for cam in ('cam1', 'cam2', 'cam3'):
            E = np.array(cg[cam]['extrinsic_world_to_camera']); K = np.array(cg[cam]['intrinsic_working_frame'])
            lab = np.load(f'{L}/view/{cam}_pose_2d.npz')  # Sapiens2 2D (QA only: IoU of its keypoint box vs the mesh box)
            cap = cv2.VideoCapture(f'{a.videos}/{ex}/{seq}/{cam}.mp4')
            Wv, Hv = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            k = max(Wv, Hv) / 1280.0  # working frame -> video px
            Xc = (V * s) @ E[:, :3].T + E[:, 3]  # metres -> the gauge's arbitrary units (x scale), camera frame
            uv = (Xc[..., :2] / Xc[..., 2:3]) @ K[:2, :2].T + K[:2, 2]
            uv *= k
            want, t = dict(zip(fr.tolist(), range(len(fr)))), 0
            while want:
                ok, img = cap.read()
                if not ok:
                    break
                if t in want:
                    i = want.pop(t); p = uv[i]
                    x0, y0 = np.clip(p.min(0), 0, [Wv - 1, Hv - 1]); x1, y1 = np.clip(p.max(0), 0, [Wv - 1, Hv - 1])
                    kv = lab['valid_mask'][t] & (lab['confidence'][t] > 0.5)
                    q = lab['keypoints_xy'][t][kv] * k
                    kiou = iou_xyxy([x0, y0, x1, y1], [*q.min(0), *q.max(0)]) if len(q) >= 8 else None
                    name = f'{seq}_{cam}_{t:05d}.jpg'
                    cv2.imwrite(f'{a.out}/{name}', img, [cv2.IMWRITE_JPEG_QUALITY, 90])
                    iid = len(images) + 1
                    images.append(dict(id=iid, file_name=name, width=Wv, height=Hv, seq=seq, cam=cam, frame=t))
                    anns.append(dict(id=iid, image_id=iid, category_id=1, bbox=[float(x0), float(y0), float(x1 - x0), float(y1 - y0)],
                                     area=float((x1 - x0) * (y1 - y0)), iscrowd=0,
                                     vis=float(((p >= 0) & (p < [Wv, Hv])).all(1).mean()), sapiens_box_iou=kiou))
                t += 1
            cap.release()
        ious = [x['sapiens_box_iou'] for x in anns if x['sapiens_box_iou'] is not None and images[x['image_id'] - 1]['seq'] == seq]
        report[seq]['mesh_vs_sapiens_box_iou_median'] = round(float(np.median(ious)), 3) if ious else None
        print(seq, report[seq], len(images), flush=True)
    if not a.check:
        json.dump(dict(images=images, annotations=anns, categories=[dict(id=1, name='person')], report=report),
                  open(f'{a.out}/{a.name}.json', 'w'))


if __name__ == '__main__':
    main()
