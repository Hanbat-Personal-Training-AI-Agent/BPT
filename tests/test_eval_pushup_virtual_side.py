import numpy as np

from scripts import eval_pushup_virtual_side as ev


def test_virtual_camera_sees_a_side_body_upright():
    # Body lies along +x (head), camera 3 m to its left (-y) at 0.5 m: image x follows the head, y points down.
    up = np.array([0.0, 0.0, 1.0])
    C, target = np.array([0.0, -3.0, 0.5]), np.zeros(3)
    R = ev.look_at(C, target, up)
    cam = lambda X: (R @ (X - C))
    assert cam(target)[2] > 0 and abs(cam(target)[0]) < 1e-9
    assert cam(np.array([1.0, 0.0, 0.0]))[0] > 0  # head side -> image right
    assert cam(np.array([0.0, 0.0, 1.0]))[1] < cam(target)[1]  # higher point -> smaller image y


def test_match_credits_each_trough_once_and_counts_extras():
    credited, extra = ev.match([10, 40, 70], [5, 45, 47, 75, 200])
    assert sorted(credited) == [0, 1, 2]  # 45 -> trough 40; 47 finds nothing new; 75 -> 70
    assert extra == [2, 4]


def test_periodicity_counts_shoulder_dips():
    t = np.arange(300)
    sig = np.cos(2 * np.pi * t / 60)  # 5 dips
    assert len(ev.periodicity(sig)) == 5


def test_interp_nan_fills_gaps_and_zeroes_empty_columns():
    a = np.array([[0.0, np.nan], [np.nan, np.nan], [2.0, np.nan]])
    out = ev.interp_nan(a)
    assert out[1, 0] == 1.0 and (out[:, 1] == 0).all()
