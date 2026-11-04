"""Fit3D person boxes for detector fine-tuning / box AP (Home only; never upload; never open the frames with Read).

Box = min / max of the official per-frame SMPL-X mesh (Fit3D smplx/<exercise>.json, SMPL-X neutral model, numpy LBS
as scripts/check_fit3d_coco17_labels.SmplxCoco17 but on every --vstep-th vertex) projected with the distorted camera,
clipped to the image: the body-surface box (no clothes / hair). Frames every --stride (50 fps), all exercises unless
--exercises. Writes <out>/<subject>/<exercise>_<cam>_<frame>.jpg and a COCO-format <out>/<subject>.json (category 1
= person), so mmdet can train / evaluate. Labels are Fit3D-derived (non-commercial); the SMPL-X model is non-commercial.

usage: build_det_fit3d.py --root ~/datasets/fit3d/train --smplx ~/models/smplx --subjects s03,s04 --out DIR [--jobs 6]
"""
import argparse, glob, json, os, sys
from multiprocessing import Pool
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent), str(HERE)]
from pose_feedback.body.pose2d_data import project_fit3d  # noqa: E402


class SmplxMesh:
    """SMPL-X vertices (world, m) from the official Fit3D params — check_fit3d_coco17_labels.SmplxCoco17 without the
    COCO regressor, on a vertex subset."""

    def __init__(self, model_dir, vstep=2, gender='neutral'):
        m = np.load(f'{model_dir}/SMPLX_{gender.upper()}.npz', allow_pickle=True)
        vid = np.arange(0, len(m['v_template']), vstep)
        sd = m['shapedirs'].astype(np.float64)
        self.vt, self.sd, self.ed = m['v_template'][vid].astype(np.float64), sd[vid, :, :10], sd[vid, :, 300:310]
        self.pd = m['posedirs'][vid].astype(np.float64)
        self.lw = m['weights'][vid].astype(np.float64)
        Jr = m['J_regressor'].astype(np.float64)
        self.Jt, self.Js, self.Je = Jr @ m['v_template'], np.einsum('jv,vck->jck', Jr, sd[:, :, :10]), np.einsum('jv,vck->jck', Jr, sd[:, :, 300:310])
        self.parents = m['kintree_table'][0].astype(np.int64); self.parents[0] = -1

    def __call__(self, path, frames):
        p = {k: np.array(v, np.float64)[frames] for k, v in json.load(open(path)).items()}
        R = np.concatenate([p['global_orient'], p['body_pose'], p['jaw_pose'], p['leye_pose'], p['reye_pose'],
                            p['left_hand_pose'], p['right_hand_pose']], 1)
        b, e = p['betas'], p['expression']
        J = self.Jt + np.einsum('tk,jck->tjc', b, self.Js) + np.einsum('tk,jck->tjc', e, self.Je)
        T = len(R)
        G = np.zeros((T, 55, 4, 4)); G[:, :, 3, 3] = 1
        for j, q in enumerate(self.parents):
            local = np.zeros((T, 4, 4)); local[:, :3, :3] = R[:, j]; local[:, 3, 3] = 1
            local[:, :3, 3] = J[:, j] - (J[:, q] if q >= 0 else 0)
            G[:, j] = local if q < 0 else G[:, q] @ local
        A = G.copy()
        A[:, :, :3, 3] -= np.einsum('tjcd,tjd->tjc', G[:, :, :3, :3], J)
        pf = (R[:, 1:] - np.eye(3)).reshape(T, -1)
        v = self.vt + np.einsum('tk,vck->tvc', b, self.sd) + np.einsum('tk,vck->tvc', e, self.ed) + np.einsum('tk,vck->tvc', pf, self.pd)
        M = np.einsum('vj,tjcd->tvcd', self.lw, A)
        return np.einsum('tvcd,tvd->tvc', M[..., :3, :3], v) + M[..., :3, 3] + p['transl'][:, None]


def one_video(job):
    root, smplx, subj, ex, cam, stride, out = job
    n = len(json.load(open(f'{root}/{subj}/smplx/{ex}.json'))['transl'])
    frames = list(range(0, n, stride))
    V = SmplxMesh(smplx)(f'{root}/{subj}/smplx/{ex}.json', frames)
    camera = json.load(open(f'{root}/{subj}/camera_parameters/{cam}/{ex}.json'))
    cap = cv2.VideoCapture(f'{root}/{subj}/videos/{cam}/{ex}.mp4')
    W, H = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    recs, want, t = [], dict(zip(frames, range(len(frames)))), 0
    while want:
        ok, fr = cap.read()
        if not ok:
            break
        if t in want:
            uv = project_fit3d(V[want.pop(t)], camera)
            x0, y0 = np.clip(uv.min(0), 0, [W - 1, H - 1]); x1, y1 = np.clip(uv.max(0), 0, [W - 1, H - 1])
            vis = float(((uv >= 0) & (uv < [W, H])).all(1).mean())
            name = f'{subj}/{ex}_{cam}_{t:05d}.jpg'
            cv2.imwrite(f'{out}/{name}', fr, [cv2.IMWRITE_JPEG_QUALITY, 90])
            recs.append(dict(file_name=name, width=W, height=H, bbox=[float(x0), float(y0), float(x1 - x0), float(y1 - y0)],
                             vis=vis, exercise=ex, cam=cam, frame=t))
        t += 1
    cap.release()
    return recs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True); ap.add_argument('--smplx', required=True)
    ap.add_argument('--subjects', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--stride', type=int, default=25); ap.add_argument('--exercises', default='')
    ap.add_argument('--jobs', type=int, default=6)
    a = ap.parse_args()
    for subj in a.subjects.split(','):
        os.makedirs(f'{a.out}/{subj}', exist_ok=True)
        jobs = []
        for v in sorted(glob.glob(f'{a.root}/{subj}/videos/*/*.mp4')):
            cam, ex = v.split('/')[-2], os.path.basename(v)[:-4]
            if (a.exercises and ex not in a.exercises.split(',')) or not os.path.exists(f'{a.root}/{subj}/smplx/{ex}.json'):
                continue
            jobs.append((a.root, a.smplx, subj, ex, cam, a.stride, a.out))
        with Pool(a.jobs) as pool:
            recs = [r for rs in pool.map(one_video, jobs) for r in rs]
        images, anns = [], []
        for i, r in enumerate(recs):
            images.append(dict(id=i + 1, file_name=r['file_name'], width=r['width'], height=r['height'], exercise=r['exercise'],
                               cam=r['cam'], frame=r['frame']))
            x, y, w, h = r['bbox']
            anns.append(dict(id=i + 1, image_id=i + 1, category_id=1, bbox=[x, y, w, h], area=w * h, iscrowd=0, vis=r['vis']))
        json.dump(dict(images=images, annotations=anns, categories=[dict(id=1, name='person')]), open(f'{a.out}/{subj}.json', 'w'))
        print(subj, len(images), 'images', flush=True)


if __name__ == '__main__':
    main()
