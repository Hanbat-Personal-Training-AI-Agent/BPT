"""WristFloorAnchor: small moves kept and followed, jumps / low confidence held, a moved hand re-anchored."""
import numpy as np

from pose_feedback.geometry.wrist_anchor import WristFloorAnchor


def frame(lw=(300.0, 600.0), conf=0.9):
    """COCO17 px: left wrist at lw, its elbow 100 px above (forearm 100 px); right wrist / elbow fixed."""
    K = np.zeros((17, 3)); K[:, 2] = 0.9
    K[9, :2], K[7, :2] = lw, (lw[0], lw[1] - 100)
    K[10, :2], K[8, :2] = (500, 600), (500, 500)
    K[9, 2] = conf
    return K


def test_small_moves_kept_jumps_and_low_confidence_held_moved_hand_reanchored():
    a = WristFloorAnchor(radius=0.5, reanchor_frames=10, init_frames=5)
    for _ in range(5):
        a.update(frame())
    K, rep = a.update(frame((320, 600)))  # 0.2 forearm: a small slide, the observation stays
    assert rep[9] == "observed" and K[9, 0] == 320 and abs(a.state[9]["ref"][0] - 301.0) < 1e-9  # ref follows 5 %
    K, rep = a.update(frame((700, 200)))  # flies off: replaced by the floor reference, flagged
    assert rep[9] == "held" and abs(K[9, 0] - 301.0) < 1e-9 and K[9, 2] == 0.29
    K, rep = a.update(frame((310, 600), conf=0.1))  # not observed: held too
    assert rep[9] == "held" and K[9, 2] == 0.29
    reps = [a.update(frame((420, 600)))[1][9] for _ in range(10)]  # put down 1.2 forearm away and kept there
    assert reps[:9] == ["held"] * 9 and reps[9] == "reanchored" and abs(a.state[9]["ref"][0] - 420) < 1e-9
    assert a.update(frame((425, 600)))[1][9] == "observed" and a.state[10]["ref"] is not None
    b = WristFloorAnchor(init_frames=5)
    for t in range(5):
        Kb = frame((300 + 80 * (t % 2), 600))  # moving hands while getting down: no reference yet
        assert b.update(Kb)[1][9] == "none"
    assert b.state[9]["ref"] is None
