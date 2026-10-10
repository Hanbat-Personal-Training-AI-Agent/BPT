"""Numpy-only helpers for 2D pose fine-tuning / evaluation (track C).

- Fit3D camera projection (H36M-style radial + tangential distortion).
- Top-down crop affine (RTMPose 192x256 input, bbox padded 1.25, fixed 3:4 aspect) and its inverse.
- SimCC Gaussian targets (split ratio 2.0) and argmax decode identical to the app's SimCCDecoder.
- PCK (percent of keypoints within alpha * person-box size).

Fit3D-derived data is licence-restricted (non-commercial, never uploaded): these helpers only
compute; callers keep crops on the Mac and delete them afterwards.
"""

import numpy as np

INPUT_W, INPUT_H = 192, 256
SPLIT_RATIO = 2.0
SIGMA = (4.9, 5.66)  # RTMPose-s/m codec sigma (x, y) in SimCC bins

# Fit3D joints3d_25 -> COCO17 body joints (index into the 25). Face points 1-4 (eyes, ears)
# have no Fit3D counterpart; nose is FIT3D_NOSE but measured as a head-centre marker, not
# the nose tip, so it is treated like the other face points (see FACE_JOINTS).
COCO_NAMES = ('nose', 'l_eye', 'r_eye', 'l_ear', 'r_ear', 'l_sh', 'r_sh', 'l_el', 'r_el', 'l_wr', 'r_wr',
              'l_hip', 'r_hip', 'l_kn', 'r_kn', 'l_an', 'r_an')
FACE_JOINTS = (0, 1, 2, 3, 4)
FLIP_PAIRS = ((1, 2), (3, 4), (5, 6), (7, 8), (9, 10), (11, 12), (13, 14), (15, 16))
FLIP_PERM = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15]


def project_fit3d(points, camera):
    """points [N,3] world (m) -> [N,2] pixels, with Fit3D/H36M camera json (X_cam = R (X - T))."""
    R = np.asarray(camera['extrinsics']['R'], float)
    T = np.asarray(camera['extrinsics']['T'], float).reshape(3)
    intr = camera['intrinsics_w_distortion']
    f = np.asarray(intr['f'], float).reshape(2)
    c = np.asarray(intr['c'], float).reshape(2)
    k = np.asarray(intr['k'], float).reshape(3)
    p = np.asarray(intr['p'], float).reshape(2)
    xc = (np.asarray(points, float) - T) @ R.T
    xy = xc[:, :2] / xc[:, 2:3]
    r2 = (xy ** 2).sum(1)
    radial = 1 + k[0] * r2 + k[1] * r2 ** 2 + k[2] * r2 ** 3
    tan = p[0] * xy[:, 1] + p[1] * xy[:, 0]
    xy = xy * (radial + tan)[:, None] + np.outer(r2, [p[1], p[0]])
    return xy * f + c


def bbox_from_points(points, valid=None):
    """Tight [x0, y0, x1, y1] around valid points."""
    pts = np.asarray(points, float)
    if valid is not None:
        pts = pts[np.asarray(valid, bool)]
    return np.array([pts[:, 0].min(), pts[:, 1].min(), pts[:, 0].max(), pts[:, 1].max()])


def box_to_center_scale(box, padding=1.25):
    """[x0,y0,x1,y1] -> centre, (w, h) widened to the 3:4 input aspect and padded (mmpose convention)."""
    x0, y0, x1, y1 = box
    center = np.array([(x0 + x1) / 2, (y0 + y1) / 2])
    w, h = (x1 - x0) * padding, (y1 - y0) * padding
    aspect = INPUT_W / INPUT_H
    if w > h * aspect:
        h = w / aspect
    else:
        w = h * aspect
    return center, np.array([w, h])


def crop_affine(center, scale, rotation_deg=0.0):
    """2x3 matrix mapping image pixels to the 192x256 input (rotation about the centre)."""
    a = np.deg2rad(rotation_deg)
    s = INPUT_W / scale[0]
    cos, sin = np.cos(a) * s, np.sin(a) * s
    # input = S R (x - c) + input_centre
    m = np.array([[cos, -sin, 0.0], [sin, cos, 0.0]])
    m[:, 2] = np.array([INPUT_W / 2, INPUT_H / 2]) - m[:, :2] @ center
    return m


def apply_affine(m, points):
    pts = np.asarray(points, float)
    return pts @ m[:, :2].T + m[:, 2]


def invert_affine(m):
    a = np.linalg.inv(m[:, :2])
    return np.hstack([a, (-a @ m[:, 2])[:, None]])


def simcc_targets(keypoints, weights):
    """keypoints [K,2] in input pixels -> (tx [K,384], ty [K,512], w [K]). Joints outside the
    input get weight 0 (mmpose SimCCLabel behaviour)."""
    kp = np.asarray(keypoints, float)
    w = np.asarray(weights, float).copy()
    xs = np.arange(int(INPUT_W * SPLIT_RATIO))
    ys = np.arange(int(INPUT_H * SPLIT_RATIO))
    mu = kp * SPLIT_RATIO
    outside = (kp[:, 0] < 0) | (kp[:, 0] >= INPUT_W) | (kp[:, 1] < 0) | (kp[:, 1] >= INPUT_H)
    w[outside] = 0
    tx = np.exp(-((xs[None] - mu[:, :1]) ** 2) / (2 * SIGMA[0] ** 2))
    ty = np.exp(-((ys[None] - mu[:, 1:]) ** 2) / (2 * SIGMA[1] ** 2))
    return tx.astype(np.float32), ty.astype(np.float32), w.astype(np.float32)


def decode_simcc(simcc_x, simcc_y):
    """[K,384],[K,512] -> keypoints [K,2] in input pixels and confidence = min(max x, max y),
    exactly like ios SimCCDecoder (argmax / split ratio, raw logits as confidence)."""
    sx, sy = np.asarray(simcc_x), np.asarray(simcc_y)
    ix, iy = sx.argmax(-1), sy.argmax(-1)
    conf = np.minimum(sx.max(-1), sy.max(-1))
    return np.stack([ix, iy], -1) / SPLIT_RATIO, conf


def pck(pred, gt, valid, box_size, alpha=0.05):
    """Fraction of valid joints with |pred - gt| < alpha * box_size. pred/gt [N,K,2], valid [N,K],
    box_size [N] (max side of the person box in the same pixels)."""
    d = np.linalg.norm(np.asarray(pred, float) - np.asarray(gt, float), axis=-1)
    ok = d < alpha * np.asarray(box_size, float)[:, None]
    v = np.asarray(valid, bool)
    return float(ok[v].mean()) if v.any() else float('nan')


def flip_keypoints(keypoints, width, pairs=FLIP_PAIRS):
    """Horizontal flip of [K,2] (or [K,...]) keypoints inside an image of `width`, swapping L/R."""
    kp = np.array(keypoints, float, copy=True)
    kp[:, 0] = width - 1 - kp[:, 0]
    for a, b in pairs:
        kp[[a, b]] = kp[[b, a]]
    return kp
