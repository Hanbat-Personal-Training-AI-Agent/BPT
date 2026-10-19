"""Experiment A box check, two definitions (post-hoc sensitivity; the pre-registered rule is `raw`):
  raw     mocap limbs + shoulders + hips (12 points, projected) inside the RTMDet box itself
  padded  the same points inside the region RTMPose actually sees (mmpose top-down: box scaled x1.25, then widened to
          the 192x256 aspect) - i.e. no joint is cut off from the model input
Per video: frame fractions, and the median / min margin (px) of the worst point outside the raw box.

usage: box_check.py --root ~/datasets/fit3d --pose2d DIR --out box.json
"""
import argparse, glob, json, os, sys
from pathlib import Path
import numpy as np

sys.path[:0] = [str(Path(__file__).resolve().parents[2]), str(Path(__file__).resolve().parents[1])]
from eval_3d_angles import load_joints  # noqa: E402
from pose_feedback.body.pose2d_data import project_fit3d  # noqa: E402

BODY = [1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16]


def inside(P, b):
    return ((P[..., 0] >= b[:, None, 0]) & (P[..., 0] <= b[:, None, 2]) & (P[..., 1] >= b[:, None, 1]) & (P[..., 1] <= b[:, None, 3])).all(1)


def padded(b, k=1.25, aspect=192 / 256):
    c = (b[:, :2] + b[:, 2:]) / 2; w, h = (b[:, 2] - b[:, 0]) * k, (b[:, 3] - b[:, 1]) * k
    w2 = np.where(w > aspect * h, w, h * aspect); h2 = np.where(w > aspect * h, w / aspect, h)
    return np.stack([c[:, 0] - w2 / 2, c[:, 1] - h2 / 2, c[:, 0] + w2 / 2, c[:, 1] + h2 / 2], 1)


def main():
    p = argparse.ArgumentParser(); p.add_argument('--root'); p.add_argument('--pose2d'); p.add_argument('--out'); a = p.parse_args()
    out = {}
    for f in sorted(glob.glob(f'{a.pose2d}/*.npz')):
        name = os.path.basename(f)[:-4]; subj, cam, ex = name.split('_', 2); d = np.load(f)
        J = load_joints(f'{a.root}/train/{subj}', ex); keep = d['pick'] < len(J); pick = d['pick'][keep]; b = d['box'][keep]
        c = json.load(open(f'{a.root}/train/{subj}/camera_parameters/{cam}/{ex}.json'))
        G2 = project_fit3d(J[pick].reshape(-1, 3), c).reshape(len(pick), 17, 2)[:, BODY]
        over = np.maximum.reduce([b[:, None, 0] - G2[..., 0], G2[..., 0] - b[:, None, 2], b[:, None, 1] - G2[..., 1], G2[..., 1] - b[:, None, 3]]).max(1)
        out[name] = dict(raw=float(inside(G2, b).mean()), padded=float(inside(G2, padded(b)).mean()),
                         nodet=float(1 - d['has_det'][keep].mean()), worst_out_px_med=float(np.median(np.maximum(over, 0))),
                         worst_out_px_p99=float(np.percentile(np.maximum(over, 0), 99)))
    json.dump(out, open(a.out, 'w'), indent=0)
    r = np.array([v['raw'] for v in out.values()]); q = np.array([v['padded'] for v in out.values()])
    print(len(out), 'raw>=0.99', int((r >= 0.99).sum()), 'padded>=0.99', int((q >= 0.99).sum()),
          'worst_out_p99 median px', round(float(np.median([v['worst_out_px_p99'] for v in out.values()])), 1))


if __name__ == '__main__':
    main()
