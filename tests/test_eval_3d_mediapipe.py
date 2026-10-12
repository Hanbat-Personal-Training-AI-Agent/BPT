import numpy as np

from scripts import eval_3d_mediapipe as ev


def test_procrustes_undoes_a_similarity_transform():
    rng = np.random.default_rng(0)
    G = rng.normal(size=(4, 17, 3))
    a = 0.7
    R = np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]])
    P = 1.3 * G @ R + 0.5
    assert np.allclose(ev.procrustes(P, G), G, atol=1e-9)
    P[1] = np.nan  # a frame with no person stays NaN, others unaffected
    out = ev.procrustes(P, G)
    assert np.isnan(out[1]).all() and np.allclose(out[[0, 2, 3]], G[[0, 2, 3]], atol=1e-9)


def test_blazepose_to_h36m_builds_pelvis_thorax_and_keeps_sides():
    W = np.zeros((1, 33, 3))
    W[0, 23], W[0, 24] = [-1, 0, 0], [1, 0, 0]  # BlazePose left / right hip
    W[0, 11], W[0, 12] = [-1, -2, 0], [1, -2, 0]  # left / right shoulder
    J = ev.mp_to_h36m(W)
    assert np.allclose(J[0, 0], 0) and np.allclose(J[0, 8], [0, -2, 0]) and np.allclose(J[0, 7], [0, -1, 0])
    assert J[0, 1, 0] == 1 and J[0, 4, 0] == -1  # H36M 1 = right hip, 4 = left hip
    assert J[0, 14, 0] == 1 and J[0, 11, 0] == -1  # H36M 14 = right shoulder, 11 = left


def test_rep_extreme_error_uses_min_for_joints_and_max_for_torso():
    ref = {k: np.full(10, 100.0) for k in ev.ANGLES}
    ref['knee'][3] = 60.0
    A = {k: v.copy() for k, v in ref.items()}
    A['knee'][3], A['knee'][4] = 100.0, 70.0  # bottom found one frame late and 10 deg shallow
    A['torso'][5] = 110.0
    m = ev.angle_metrics(A, ref, [(0, 9)])
    assert m['knee']['rep'] == [10.0] and m['torso']['rep'] == [10.0] and m['hip']['rep'] == [0.0]
