"""Fit3D foot keypoints for Halpe26 (D-F3-05): SMPL-X foot vertices vs the original RTMPose-m Halpe26 (Home only).

Halpe26 feet = 20 / 21 big toe, 22 / 23 small toe, 24 / 25 heel (left / right), the OpenPose foot definition. Fit3D has
no foot labels, but its official per-frame SMPL-X fits do: the smplx library's OpenPose foot vertices (left 5770 big toe,
5780 small toe, 8846 heel; right 8463, 8474, 8635). `check` verifies the ids on the template (toe = front-most, heel =
back-most, big toe medial of small toe) and then, per point type on the TUNING subjects' experiment-A frames (lift-compare
stage 1: same RTMDet box, PyTorch m Halpe26), compares the projected vertex with the model: distance / box long side
(median, p90), left/right swap, and the signed offset along the foot axis (heel -> big toe) and across it (D-C-09 style:
label definition vs the model, not accuracy). Aggregates only.

usage: foot_labels.py check --root ~/datasets/fit3d --smplx ~/models/smplx --pose2d DIR --subjects s03,s04,s05 --out OUT.json
"""
import argparse, glob, json, os, sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent), str(HERE)]
from build_det_fit3d import SmplxMesh  # noqa: E402
from pose_feedback.body.pose2d_data import project_fit3d  # noqa: E402

FOOT_VERTS = [5770, 8463, 5780, 8474, 8846, 8635]  # Halpe 20..25: L/R big toe, L/R small toe, L/R heel
NAMES = ['l_big_toe', 'r_big_toe', 'l_small_toe', 'r_small_toe', 'l_heel', 'r_heel']
TYPES = {'big_toe': (0, 1), 'small_toe': (2, 3), 'heel': (4, 5)}


class FootMesh(SmplxMesh):
    def __init__(self, model_dir):
        super().__init__(model_dir, vstep=1)
        keep = np.array(FOOT_VERTS)
        self.vt, self.sd, self.ed, self.pd, self.lw = self.vt[keep], self.sd[keep], self.ed[keep], self.pd[keep], self.lw[keep]


def template_check(model_dir):
    """rest-pose sanity of the ids: SMPL-X y up, z forward, x = subject's left."""
    v = np.load(f'{model_dir}/SMPLX_NEUTRAL.npz', allow_pickle=True)['v_template']
    f = v[FOOT_VERTS]
    out = dict(zip(NAMES, np.round(f, 3).tolist()))
    ok = dict(toes_in_front_of_heel=bool(f[0, 2] > f[4, 2] and f[1, 2] > f[5, 2] and f[2, 2] > f[4, 2]),
              big_toe_medial=bool(abs(f[0, 0]) < abs(f[2, 0]) and abs(f[1, 0]) < abs(f[3, 0])),
              left_is_plus_x=bool(f[0, 0] > 0 and f[1, 0] < 0),
              near_floor=bool(np.all(f[:, 1] < v[:, 1].min() + 0.06)))
    return out, ok


def check(a):
    tmpl, ok = template_check(a.smplx)
    mesh = FootMesh(a.smplx)
    rows = []
    for s in a.subjects.split(','):
        for f in sorted(glob.glob(f'{a.pose2d}/{s}_*_*.npz')):
            cam, ex = os.path.basename(f)[len(s) + 1:-4].split('_', 1)
            z = np.load(f); pk, box, H = z['pick'], z['box'], z['halpe']
            sj = f'{a.root}/train/{s}/smplx/{ex}.json'
            if not os.path.exists(sj):
                continue
            keep = pk < len(json.load(open(sj))['transl'])  # frames with an SMPL-X fit
            pk, box, H = pk[keep], box[keep], H[keep]
            V = mesh(sj, pk)  # [T,6,3]
            camj = json.load(open(f'{a.root}/train/{s}/camera_parameters/{cam}/{ex}.json'))
            uv = project_fit3d(V.reshape(-1, 3), camj).reshape(len(pk), 6, 2)
            pred, conf = H[:, 20:26, :2], H[:, 20:26, 2]
            side = np.maximum(box[:, 2] - box[:, 0], box[:, 3] - box[:, 1])[:, None]
            d = np.linalg.norm(pred - uv, axis=-1) / side
            # foot axis per side from the labels: heel -> big toe
            res = dict(subject=s, exercise=ex, cam=cam, frames=int(len(pk)))
            for side_i, (bt, st, he) in enumerate(((0, 2, 4), (1, 3, 5))):
                ax = uv[:, bt] - uv[:, he]; L = np.linalg.norm(ax, axis=-1, keepdims=True).clip(1e-6); ax = ax / L
                nrm = np.stack([-ax[:, 1], ax[:, 0]], -1)
                for j in (bt, st, he):
                    off = pred[:, j] - uv[:, j]
                    res.setdefault('along', {})[NAMES[j]] = float(np.median(np.sum(off * ax, -1) / side[:, 0]))
                    res.setdefault('across', {})[NAMES[j]] = float(np.median(np.sum(off * nrm, -1) / side[:, 0]))
            res['dist'] = {NAMES[j]: d[:, j].tolist() for j in range(6)}
            res['conf'] = {NAMES[j]: float(np.median(conf[:, j])) for j in range(6)}
            for t, (l, r) in TYPES.items():
                sw = (np.linalg.norm(pred[:, l] - uv[:, r], axis=-1) < np.linalg.norm(pred[:, l] - uv[:, l], axis=-1)) & \
                     (np.linalg.norm(pred[:, r] - uv[:, l], axis=-1) < np.linalg.norm(pred[:, r] - uv[:, r], axis=-1))
                res.setdefault('swap', {})[t] = float(sw.mean())
            rows.append(res)
            print(s, ex, cam, {t: round(float(np.median(np.concatenate([res['dist'][NAMES[l]], res['dist'][NAMES[r]]]))), 4)
                               for t, (l, r) in TYPES.items()}, flush=True)
    summ = {}
    for t, (l, r) in TYPES.items():
        dd = np.concatenate([np.concatenate([x['dist'][NAMES[l]], x['dist'][NAMES[r]]]) for x in rows])
        summ[t] = dict(dist_median=float(np.median(dd)), dist_p90=float(np.percentile(dd, 90)), pck05=float((dd < 0.05).mean()),
                       swap=float(np.mean([x['swap'][t] for x in rows])),
                       along_median=float(np.median([x['along'][NAMES[k]] for x in rows for k in (l, r)])),
                       across_median=float(np.median([np.abs(x['across'][NAMES[k]]) for x in rows for k in (l, r)])),
                       conf_median=float(np.median([x['conf'][NAMES[k]] for x in rows for k in (l, r)])))
    json.dump(dict(template=tmpl, template_ok=ok, summary=summ, videos=[{k: v for k, v in x.items() if k != 'dist'} for x in rows]),
              open(a.out, 'w'), indent=1)
    print(json.dumps(dict(template_ok=ok, summary=summ), indent=1))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['check'])
    p.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d')); p.add_argument('--smplx', default=os.path.expanduser('~/models/smplx'))
    p.add_argument('--pose2d', default=os.path.expanduser('~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d'))
    p.add_argument('--subjects', default='s03,s04,s05'); p.add_argument('--out', required=True)
    a = p.parse_args()
    check(a)


if __name__ == '__main__':
    main()
