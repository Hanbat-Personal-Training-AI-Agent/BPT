import numpy as np

from scripts import eval_3d_angles as ev


def test_interior_and_torso_angles():
    a, b, c = np.array([[0., 1]]), np.array([[0., 0]]), np.array([[1., 0]])
    assert np.allclose(ev.interior(a, b, c), 90)
    K = np.zeros((1, 17, 3))
    K[0, 5, :2] = (10, 0); K[0, 11, :2] = (0, 10)  # left shoulder up-right of the left hip: 45 deg lean
    assert np.allclose(ev.angles_2d(K, 'L')['torso'], 45)
    J = np.zeros((1, 17, 3)); J[0, 11] = J[0, 14] = (0, 0, 1)  # mid-shoulder straight above mid-hip
    assert np.allclose(ev.angles_3d(J, np.array([0, 0, 1.]), 'L')['torso'], 0, atol=0.01)


def test_fit3d_leg_swap_and_view():
    # Fit3D: index 1 (hip) is on the shoulder-11 (left) side; H36M index 4 is the left hip.
    assert ev.FIT3D_TO_H36M[4] == 1 and ev.FIT3D_TO_H36M[1] == 4 and ev.FIT3D_TO_H36M[11] == 11
    # Subject faces +x, z up: left = +y. Camera on +y looks at the left side -> view 0 deg, near side L.
    J = np.zeros((5, 17, 3)); J[:, 4] = J[:, 11] = (0, .2, 1); J[:, 1] = J[:, 14] = (0, -.2, 1)
    ang, side = ev.view_and_side(J, None, np.array([0, 5., 1]), np.array([0, 0, 1.]))
    assert ang < 1 and side == 'L'
    ang, _ = ev.view_and_side(J, None, np.array([5., 0, 1]), np.array([0, 0, 1.]))
    assert ang > 89


def test_lift_uses_app_window():
    class Echo:  # returns the window's frame index in every joint, so the selected row is visible
        def predict_3d(self, w):
            return w[..., :1].repeat(3, -1)
    coco = np.zeros((40, 17, 3)); coco[..., 2] = 1
    coco[:, :, 0] = np.arange(40)[:, None] * 10 + 100; coco[:, :, 1] = 300 + np.arange(17)[None] * 10
    frames = ev.motionagformer_frames_from_coco17(list(coco), 640, 480)
    out = ev.lift(coco, 640, 480, Echo())
    # Selected row 21 of window [i-21, i+5] is frame i itself (output delayed by the 5-frame lookahead).
    assert np.allclose(out[:, 0, 0], frames[:, 0, 0])


def test_near_side_is_higher_confidence_side():
    K = np.zeros((3, 17, 3)); K[:, ev.SIDE_JOINTS['R'], 2] = .9; K[:, ev.SIDE_JOINTS['L'], 2] = .4
    assert ev.near_side(K) == 'R'
