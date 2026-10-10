import numpy as np

from pose_feedback.body.pose2d_data import (
    FLIP_PERM, INPUT_H, INPUT_W, apply_affine, box_to_center_scale, crop_affine, decode_simcc, flip_keypoints,
    invert_affine, pck, project_fit3d, simcc_targets,
)


def camera(k=(0, 0, 0), p=(0, 0)):
    return {'extrinsics': {'R': np.eye(3).tolist(), 'T': [[0, 0, -5]]},
            'intrinsics_w_distortion': {'f': [[1000, 1000]], 'c': [[450, 450]], 'k': [list(k)], 'p': [list(p)]}}


def test_project_pinhole_and_camera_centre():
    # X_cam = R (X - T): camera at T=(0,0,-5) looking down +z sees the origin 5 m ahead, on the principal point
    pts = project_fit3d(np.array([[0, 0, 0], [0.5, -0.25, 0]]), camera())
    assert np.allclose(pts, [[450, 450], [550, 400]])


def test_project_radial_distortion_pushes_points_out():
    plain = project_fit3d(np.array([[1.0, 0, 0]]), camera())
    barrel = project_fit3d(np.array([[1.0, 0, 0]]), camera(k=(0.1, 0, 0)))
    assert barrel[0, 0] > plain[0, 0] and np.isclose(barrel[0, 1], 450)


def test_center_scale_keeps_3_by_4_aspect_and_padding():
    c, s = box_to_center_scale([0, 0, 30, 100])
    assert np.allclose(c, [15, 50]) and np.isclose(s[1], 125) and np.isclose(s[0] / s[1], INPUT_W / INPUT_H)


def test_crop_affine_maps_box_centre_to_input_centre_and_inverts():
    c, s = box_to_center_scale([100, 50, 220, 410])
    for rot in (0.0, 25.0):
        m = crop_affine(c, s, rot)
        assert np.allclose(apply_affine(m, c[None]), [[INPUT_W / 2, INPUT_H / 2]])
        pts = np.array([[120.0, 60.0], [200.0, 400.0]])
        assert np.allclose(apply_affine(invert_affine(m), apply_affine(m, pts)), pts)
    # without rotation the padded box height fills the 256 input exactly
    top = apply_affine(crop_affine(c, s), np.array([[c[0], c[1] - s[1] / 2]]))
    assert np.allclose(top, [[INPUT_W / 2, 0]])


def test_simcc_target_peak_decodes_back_and_outside_joint_gets_zero_weight():
    kp = np.array([[50.5, 100.0], [10.0, 300.0]])  # second joint below the 256 input
    tx, ty, w = simcc_targets(kp, [1, 1])
    assert tx.shape == (2, 384) and ty.shape == (2, 512)
    dec, conf = decode_simcc(tx, ty)
    assert np.allclose(dec[0], kp[0]) and np.isclose(conf[0], 1.0)
    assert list(w) == [1, 0]


def test_decode_uses_min_of_axis_peaks_as_confidence_like_app():
    sx, sy = np.zeros((1, 384)), np.zeros((1, 512))
    sx[0, 10], sy[0, 20] = 0.8, 0.3
    k, c = decode_simcc(sx, sy)
    assert np.allclose(k, [[5, 10]]) and np.isclose(c[0], 0.3)


def test_flip_swaps_left_right_and_mirrors_x():
    kp = np.arange(34, dtype=float).reshape(17, 2)
    f = flip_keypoints(kp, 100)
    assert np.allclose(f[5], [100 - 1 - kp[6, 0], kp[6, 1]])
    assert FLIP_PERM[5] == 6 and FLIP_PERM[0] == 0
    assert np.allclose(flip_keypoints(f, 100), kp)


def test_pck_counts_only_valid_joints_within_alpha_box():
    gt = np.zeros((1, 3, 2))
    pred = np.array([[[4, 0], [6, 0], [100, 0]]], float)
    assert pck(pred, gt, [[True, True, False]], [100], 0.05) == 0.5
