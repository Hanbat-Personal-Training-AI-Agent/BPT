"""Visual + numeric check of a GVHMR result (gvhmr_runner.py) for depth collapse / tilt (the old portrait bug).

Sheet: per sampled frame, the upright 30 fps frame with the H36M-17 joints projected through GVHMR's K, and the
3D skeleton in GVHMR's gravity-aligned world seen from the front (x-y) and from the side (z-y).
Numbers: bone-length CV over frames (a collapsing body changes bone lengths), median depth extent of the body
in camera z vs its height, and torso tilt from world up on the most upright frames.
Only for videos that may be viewed (our test clips, CC BY public clips) — never Fit3D / Exercise3D frames.

usage (env bpt-gvhmr): python render_gvhmr_check.py VIDEO RESULT_NPZ OUT.png [--frames 6]
"""
import argparse, json, sys
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
BONES = [(0, 1), (1, 2), (2, 3), (0, 4), (4, 5), (5, 6), (0, 7), (7, 8), (8, 9), (9, 10),
         (8, 11), (11, 12), (12, 13), (8, 14), (14, 15), (15, 16)]
RIGHT = {1, 2, 3, 14, 15, 16}


def checks(z):
    C, W = z['h36m17_cam'].astype(float), z['h36m17_world'].astype(float)
    L = np.stack([np.linalg.norm(C[:, a] - C[:, b], axis=1) for a, b in BONES], 1)
    cv = L.std(0) / L.mean(0)
    height = np.linalg.norm(W[:, 10] - (W[:, 3] + W[:, 6]) / 2, axis=1)
    depth = C[..., 2].max(1) - C[..., 2].min(1)
    torso = W[:, 8] - W[:, 0]
    tilt = np.degrees(np.arccos(np.clip(torso[:, 1] / np.linalg.norm(torso, axis=1), -1, 1)))
    up = np.argsort(tilt)[:max(1, len(tilt) // 10)]
    return dict(bone_cv_median=float(np.median(cv)), bone_cv_max=float(cv.max()),
                depth_over_height_median=float(np.median(depth / height)),
                torso_tilt_upright10pct_deg=float(np.median(tilt[up])), torso_tilt_median_deg=float(np.median(tilt)),
                body_height_m_median=float(np.median(height)))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('video'); p.add_argument('result'); p.add_argument('out')
    p.add_argument('--frames', type=int, default=6)
    a = p.parse_args()
    import cv2, matplotlib
    matplotlib.use('Agg'); import matplotlib.pyplot as plt
    import gvhmr_runner as g
    z = np.load(a.result); C, W, K = z['h36m17_cam'], z['h36m17_world'], z['K']
    tmp = Path(a.out).with_suffix('.tmp.mp4')
    g.normalize_video(a.video, tmp)  # the same upright 30 fps frames GVHMR saw
    cap = cv2.VideoCapture(str(tmp)); cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 0); frames = []
    while True:
        ok, f = cap.read()
        if not ok: break
        frames.append(f[..., ::-1])
    tmp.unlink()
    n = min(len(frames), len(C)); idx = np.linspace(0, n - 1, a.frames).astype(int)
    fig, ax = plt.subplots(3, a.frames, figsize=(3 * a.frames, 9))
    lo, hi = W[:n].reshape(-1, 3).min(0), W[:n].reshape(-1, 3).max(0); mid = (lo + hi) / 2; r = (hi - lo).max() / 2 + 0.1
    for c, i in enumerate(idx):
        uv = (K @ C[i].T).T; uv = uv[:, :2] / uv[:, 2:]
        ax[0, c].imshow(frames[i]); ax[0, c].set_title(f'frame {i}'); ax[0, c].axis('off')
        for row, (u, v) in ((0, (uv[:, 0], uv[:, 1])), (1, (W[i, :, 0], W[i, :, 1])), (2, (W[i, :, 2], W[i, :, 1]))):
            for a_, b_ in BONES:
                ax[row, c].plot([u[a_], u[b_]], [v[a_], v[b_]], 'r-' if b_ in RIGHT else 'b-', lw=2)
        for row, (m0, m1) in ((1, (0, 1)), (2, (2, 1))):
            ax[row, c].set_xlim(mid[m0] - r, mid[m0] + r); ax[row, c].set_ylim(mid[m1] - r, mid[m1] + r)
            ax[row, c].set_aspect('equal'); ax[row, c].axhline(lo[1], color='gray', lw=0.5)
            ax[row, c].set_title(['', 'world front (x-y)', 'world side (z-y)'][row], fontsize=8)
    ck = checks(z)
    fig.suptitle(f"{Path(a.video).name}  " + json.dumps({k: round(v, 3) for k, v in ck.items()}), fontsize=8)
    fig.tight_layout(); fig.savefig(a.out, dpi=70)
    print(json.dumps(ck))


if __name__ == '__main__':
    main()
