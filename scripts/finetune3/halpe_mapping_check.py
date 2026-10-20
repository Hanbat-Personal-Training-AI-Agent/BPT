"""Halpe26 -> H36M input mapping for the Halpe26-only XS (C3), decided BEFORE training on the TUNING subjects (Home only).

Two mappings of the synthesised H36M joints:
  app    the app's current one (coco17_to_motionagformer_h36m17 on Halpe joints 0-16): pelvis = mid hips, thorax = mid
         shoulders, head = mid eyes (spine = mid(pelvis, thorax), neck/nose = mid(nose, thorax))
  halpe  Halpe's own points: pelvis <- 19 hip, thorax <- 18 neck, head <- 17 head (spine / neck-nose rebuilt the same way)
For each joint, the mapped 2D point of the original RTMPose-m Halpe26 (lift-compare stage 1, same RTMDet box) is compared
with the projected mocap H36M joint: distance in torso lengths (projected mocap thorax-pelvis), median and p90, the signed
offset along the torso axis, and the spread (median absolute deviation of the residual around its per-video median).
Pre-registered choice (finetune3_plan.md §1.3): per joint (pelvis, thorax, head) the mapping with the smaller median
distance wins. Aggregates only.

usage: halpe_mapping_check.py --pose2d DIR --subjects s03,s04,s05 --out OUT.json
"""
import argparse, glob, json, os, sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent), str(HERE)]
from eval_3d_angles import FIT3D_TO_H36M  # noqa: E402
from pose_feedback.body.motionagformer_adapter import coco17_to_motionagformer_h36m17  # noqa: E402
from pose_feedback.body.pose2d_data import project_fit3d  # noqa: E402

JOINTS = {'pelvis': 0, 'thorax': 8, 'head': 10}
HALPE = {'pelvis': 19, 'thorax': 18, 'head': 17}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--pose2d', default=os.path.expanduser('~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d'))
    p.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d'))
    p.add_argument('--subjects', default='s03,s04,s05'); p.add_argument('--out', required=True)
    a = p.parse_args()
    acc = {m: {j: dict(d=[], along=[], spread=[]) for j in JOINTS} for m in ('app', 'halpe')}
    for s in a.subjects.split(','):
        for f in sorted(glob.glob(f'{a.pose2d}/{s}_*_*.npz')):
            cam, ex = os.path.basename(f)[len(s) + 1:-4].split('_', 1)
            z = np.load(f); pk, H = z['pick'], z['halpe']
            J = np.array(json.load(open(f'{a.root}/train/{s}/joints3d_25/{ex}.json'))['joints3d_25'])
            keep = pk < len(J); pk, H = pk[keep], H[keep]
            camj = json.load(open(f'{a.root}/train/{s}/camera_parameters/{cam}/{ex}.json'))
            G = project_fit3d(J[pk][:, FIT3D_TO_H36M].reshape(-1, 3), camj).reshape(len(pk), 17, 2)
            torso = np.linalg.norm(G[:, 8] - G[:, 0], axis=-1)
            ax = (G[:, 8] - G[:, 0]) / torso[:, None]  # pelvis -> thorax (up the trunk)
            app, _ = coco17_to_motionagformer_h36m17(H[:, :17])
            for m in ('app', 'halpe'):
                for name, j in JOINTS.items():
                    q = app[:, j] if m == 'app' else H[:, HALPE[name], :2]
                    r = (q - G[:, j]) / torso[:, None]
                    acc[m][name]['d'].append(np.linalg.norm(r, axis=-1))
                    acc[m][name]['along'].append(np.sum(r * ax, -1))
                    acc[m][name]['spread'].append(np.linalg.norm(r - np.median(r, 0), axis=-1))
    out = {}
    for m, js in acc.items():
        for name, v in js.items():
            d = np.concatenate(v['d'])
            out.setdefault(name, {})[m] = dict(dist_median=float(np.median(d)), dist_p90=float(np.percentile(d, 90)),
                                              along_median=float(np.median(np.concatenate(v['along']))),
                                              spread_median=float(np.median(np.concatenate(v['spread']))))
    choice = {name: ('halpe' if r['halpe']['dist_median'] < r['app']['dist_median'] else 'app') for name, r in out.items()}
    json.dump(dict(subjects=a.subjects, per_joint=out, choice=choice), open(a.out, 'w'), indent=1)
    print(json.dumps(dict(per_joint=out, choice=choice), indent=1))


if __name__ == '__main__':
    main()
