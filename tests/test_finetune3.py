"""finetune3 helpers (synthetic data only; no Fit3D / Exercise3D). Skipped where torch / cv2 are missing (bpt-eval)."""
import json
import math

import numpy as np
import pytest

torch = pytest.importorskip('torch')
pytest.importorskip('cv2')

from scripts.finetune3 import build_det_ex3d as bde  # noqa: E402
from scripts.finetune3 import det_finetune as det  # noqa: E402
from scripts.finetune3 import xs_data as xd  # noqa: E402
from scripts.finetune3 import xs_train as xt  # noqa: E402


def test_target_is_weak_perspective_crop_units():
    # 17 joints ~3 m in front of a pinhole camera (y down): target x/y == projected offset from the root / (side / 2)
    rng = np.random.default_rng(0)
    X = np.array([0.0, 0.0, 3.0]) + rng.normal(0, 0.3, (1, 17, 3)) * [1, 1, 0.01]
    f, side = 1000.0, 600.0
    y, mm = xd.target(X, np.array([[0.0, 0.0, side]]), f)
    uv = X[..., :2] / X[..., 2:3] * f
    assert np.allclose(y[0, :, :2], (uv[0] - uv[0, :1]) / (side / 2), atol=2e-3)
    assert abs(mm[0] - side / 2 * X[0, 0, 2] / f * 1000) < 1e-2


def _pool(tmp_path, ref, res):
    meta = [dict(name='c0', group='squat', angle=10.0, source='ex3d')]
    np.savez(tmp_path / 'p.npz', meta=json.dumps(meta), res0=res, conf0=np.full(res.shape[:2], 0.8), ref0=ref)
    return xd.Pool(tmp_path / 'p.npz')


def test_pool_mirrors_a_clip_seen_from_the_other_side(tmp_path):
    ref = np.zeros((17, 2)); ref[xd.H36M_SWAP[1:4]] = [0.3, 0.0]  # left leg on the right of the image
    res = np.zeros((5, 17, 2)); res[:, 13] = [0.1, 0.0]  # error on the left knee (COCO 13), pointing +x
    p = _pool(tmp_path, ref, res)
    mirrored = ref.copy(); mirrored[:, 0] *= -1; mirrored = mirrored[xd.H36M_SWAP]
    r, c, name = p.noise(np.random.default_rng(0), 'squat', 10.0, 5, mirrored)
    assert np.allclose(r[:, 14], [-0.1, 0.0]) and np.allclose(r[:, 13], 0)  # moved to the right knee, x flipped
    r2, _, _ = p.noise(np.random.default_rng(0), 'squat', 10.0, 5, ref)
    assert np.allclose(r2[:, 13], [0.1, 0.0])  # same side: unchanged


def _standing_mocap():
    # standing mocap-like body (Fit3D joints3d_25 layout), facing +y: a camera on the right (side=+1, az 0) sees view ~0
    P = np.zeros((60, 25, 3))
    P[:, 0] = [0, 0, 1.0]; P[:, 1] = [-0.1, 0, 0.95]; P[:, 4] = [0.1, 0, 0.95]
    P[:, 2] = [-0.1, 0, 0.5]; P[:, 5] = [0.1, 0, 0.5]; P[:, 3] = [-0.1, 0, 0.08]; P[:, 6] = [0.1, 0, 0.08]
    P[:, 7] = [0, 0, 1.2]; P[:, 8] = [0, 0, 1.45]; P[:, 9] = [0, 0.08, 1.6]; P[:, 10] = [0, 0, 1.72]
    P[:, 11] = [-0.2, 0, 1.45]; P[:, 14] = [0.2, 0, 1.45]; P[:, 12] = [-0.25, 0, 1.15]; P[:, 15] = [0.25, 0, 1.15]
    P[:, 13] = [-0.25, 0.05, 0.9]; P[:, 16] = [0.25, 0.05, 0.9]
    return P


def test_virtual_side_camera_geometry():
    P = _standing_mocap()
    offs = {k: np.zeros(3) for k in ('nose', 'shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle')}
    cam = dict(side=1.0, az=0.0, front=1.0, height=1.0, dist=3.0, f=913.0)
    v = xd.virtual_seq(P, offs, None, np.random.default_rng(0), 'squat', cam, 'sX/squat/g0', noisy=False)
    assert v['view'] < 1.0 and v['side'] == 'R' and v['inframe'] == 1.0
    assert v['y'][0, 0].tolist() == [0.0, 0.0, 0.0]
    assert v['y'][0, 10, 1] < v['y'][0, 3, 1]  # head above the ankle (y down)
    assert abs(v["y"][0, 11, 2] - v["y"][0, 14, 2]) > 0.1  # left / right shoulders differ in depth seen from the side


def test_virtual_mapping_comparison_keeps_identical_noisy_2d(monkeypatch):
    P = _standing_mocap()
    offs = {k: np.zeros(3) for k in ('nose', 'shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle',
                                    'h_head', 'h_neck', 'h_hip')}
    # Ensure the two mappings produce different crop extents.
    offs['h_head'] = np.array([0.3, 0.0, 0.0])
    cam = dict(side=1.0, az=20.0, front=1.0, height=1.0, dist=3.0, f=913.0)
    refposes, observed = [], []

    class FixedPool:
        def noise(self, rng, group, angle, n, refpose):
            refposes.append(refpose.copy())
            return np.full((n, 20, 2), 0.02), np.full((n, 20), 0.8), 'synthetic'

    mag_in = xd.mag_in

    def capture(K, *args):
        if np.allclose(K[..., 2], 0.8):
            observed.append(K.copy())
        return mag_in(K, *args)

    monkeypatch.setattr(xd, 'mag_in', capture)
    for mapping in ('halpe', 'app'):
        monkeypatch.setattr(xd, 'V_MAPPING', mapping)
        xd.virtual_seq(P, offs, FixedPool(), np.random.default_rng(0), 'squat', cam, 'sX/squat/g0')
    assert len(observed) == 2
    assert np.allclose(observed[0], observed[1])
    assert np.allclose(refposes[0], refposes[1])


def test_limb_loss_ignores_translation_and_masks():
    y = torch.randn(2, 27, 17, 3)
    assert xt.limb_loss(y + 5.0, y, torch.ones(2, 27)).item() < 1e-5
    p = y.clone(); p[:, :, 2] += 1.0  # move one knee
    full = xt.limb_loss(p, y, torch.ones(2, 27)).item()
    assert full > 0.05 and xt.limb_loss(p, y, torch.zeros(2, 27)).item() == 0.0


def test_rodrigues_and_iou():
    assert np.allclose(bde.rodrigues(np.zeros((1, 3)))[0], np.eye(3))
    Rz = bde.rodrigues(np.array([[0, 0, math.pi / 2]]))[0]
    assert np.allclose(Rz @ [1, 0, 0], [0, 1, 0], atol=1e-9)
    assert det.iou([0, 0, 2, 2], [1, 0, 3, 2]) == pytest.approx(1 / 3)


def test_halpe_mapping_uses_halpe_pelvis_neck_head():
    K = np.random.default_rng(0).uniform(0, 100, (3, 26, 3))
    app, _ = xd.to_h36m(K, 'app')
    hm, conf = xd.to_h36m(K, 'halpe')
    assert np.allclose(hm[:, 0], K[:, 19, :2]) and np.allclose(hm[:, 8], K[:, 18, :2]) and np.allclose(hm[:, 10], K[:, 17, :2])
    assert np.allclose(hm[:, 7], (K[:, 19, :2] + K[:, 18, :2]) / 2) and np.allclose(hm[:, 9], (K[:, 0, :2] + K[:, 18, :2]) / 2)
    assert np.allclose(np.delete(hm, [0, 7, 8, 9, 10], 1), np.delete(app, [0, 7, 8, 9, 10], 1))  # limbs unchanged
    assert np.allclose(conf[:, 0], K[:, 19, 2])
    x_app, _ = xd.mag_in(K[:, :17], 100, 100, 'app')
    x_ref, _ = xd.mag_input(K[:, :17], 100, 100)
    assert np.allclose(x_app, x_ref)  # mapping='app' is exactly the app path
