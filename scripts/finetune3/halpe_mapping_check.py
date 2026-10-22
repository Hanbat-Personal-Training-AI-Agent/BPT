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
Also (plan §1.4, report only) the same statistics per frame view bucket: horizontal angle between the camera->pelvis ray
and the body left-right line per frame (eval_3d_angles.view_and_side without the median; 0 side, 90 front), side <= 40,
oblique 40-75, front >= 75, with frame counts.

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
BUCKETS = ('side<=40', 'oblique40-75', 'front>=75')


def frame_views(J, R, T):
    """per-frame view angle (deg) like eval_3d_angles.view_and_side (world up = -R[1], z-up fallback)."""
    up = -R[1] / np.linalg.norm(R[1]); up = np.array([0, 0, 1.]) if abs(up[2]) > 0.8 else up
    lr = ((J[:, 14] - J[:, 11]) + (J[:, 1] - J[:, 4])) / 2; lr -= np.outer(lr @ up, up)
    ray = J[:, 0] - T; ray -= np.outer(ray @ up, up)
    cos = np.sum(ray * lr, 1) / (np.linalg.norm(ray, axis=1) * np.linalg.norm(lr, axis=1))
    return np.degrees(np.arccos(np.clip(np.abs(cos), 0, 1)))


def bucket_of(v):
    return np.where(v <= 40, 0, np.where(v < 75, 1, 2))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--pose2d', default=os.path.expanduser('~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d'))
    p.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d'))
    p.add_argument('--subjects', default='s03,s04,s05'); p.add_argument('--out', required=True)
    a = p.parse_args()
    acc = {m: {j: dict(d=[], along=[], spread=[]) for j in JOINTS} for m in ('app', 'halpe')}
    bk, exs = [], []
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
            Rc = np.array(camj['extrinsics']['R']); Tc = np.array(camj['extrinsics']['T']).reshape(3)
            bk.append(bucket_of(frame_views(J[pk], Rc, Tc))); exs += [ex] * len(pk)
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
    bk = np.concatenate(bk); per_view = {}
    for b, bname in enumerate(BUCKETS):
        sel = bk == b
        per_view[bname] = dict(frames=int(sel.sum()), frames_by_exercise={e: int(np.sum(sel & (np.array(exs) == e))) for e in sorted(set(exs))})
        if sel.sum() == 0: continue
        for m, js in acc.items():
            for name, v in js.items():
                d, al = np.concatenate(v['d'])[sel], np.concatenate(v['along'])[sel]
                per_view[bname].setdefault(name, {})[m] = dict(dist_median=float(np.median(d)), dist_p90=float(np.percentile(d, 90)),
                                                               along_median=float(np.median(al)))
    choice = {name: ('halpe' if r['halpe']['dist_median'] < r['app']['dist_median'] else 'app') for name, r in out.items()}
    json.dump(dict(subjects=a.subjects, pose2d=a.pose2d, per_joint=out, choice=choice, per_view=per_view), open(a.out, 'w'), indent=1)
    print(json.dumps(dict(per_joint=out, choice=choice, per_view=per_view), indent=1))


if __name__ == '__main__':
    main()
