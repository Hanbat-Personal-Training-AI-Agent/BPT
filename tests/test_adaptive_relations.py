"""AdaptiveRelations: observed joints untouched, no constraint before setup, fill / re-anchor / expiry."""
import numpy as np

from pose_feedback.geometry.adaptive_relations import AdaptiveRelations, L_ANKLE, R_ANKLE


def pose(left_ankle_x=0.2, pelvis_drop=0.0):
    """Standing H36M17 in crop units: legs 0.9 long, ankles 0.4 apart; the pelvis moving changes every leg joint
    in pelvis-relative coordinates but not the ankle-ankle vector."""
    P = np.zeros((17, 3))
    P[1], P[4] = [-0.1, 0, 0], [0.1, 0, 0]
    P[2], P[5] = [-0.15, 0.45, 0], [0.15, 0.45, 0]
    P[3], P[6] = [-0.2, 0.9, 0], [left_ankle_x, 0.9, 0]
    P[8] = [0, -0.5, 0]
    P[[2, 3, 5, 6]] -= [0, pelvis_drop, 0]
    return P


def conf(low=()):
    c = np.full(17, 0.9)
    c[list(low)] = 0.1
    return c


def run(frames):
    m = AdaptiveRelations("squat")
    return m, [m.update(P, c, t) for t, (P, c) in enumerate(frames)]


def test_observed_frames_are_never_changed_and_setup_has_no_constraint():
    frames = [(pose(0.2 + 0.01 * np.sin(t)), conf()) for t in range(40)]
    m, out = run(frames)
    for (P, _), (Q, rep) in zip(frames, out):
        np.testing.assert_array_equal(P, Q)
    assert out[5][1]["relations"]["feet"]["state"] == "none"  # still collecting during setup
    assert m.state["feet"]["ref"] is not None


def test_occluded_ankle_follows_the_other_foot_while_the_pelvis_moves():
    frames = [(pose(), conf()) for _ in range(20)]
    frames += [(pose(left_ankle_x=0.6, pelvis_drop=0.2 * t / 10), conf(low=[L_ANKLE])) for t in range(10)]  # XS wrong
    _, out = run(frames)
    Q, rep = out[-1]
    truth = pose(pelvis_drop=0.2)
    # w = exp(-gap / decay_frames) = 0.80 after 10 frames: most, not all, of the XS error is removed
    assert np.linalg.norm(Q[L_ANKLE] - truth[L_ANKLE]) < 0.25 * np.linalg.norm(frames[-1][0][L_ANKLE] - truth[L_ANKLE])
    assert L_ANKLE in rep["filled"] and np.allclose(Q[R_ANKLE], frames[-1][0][R_ANKLE])


def test_real_observed_shift_is_accepted_not_snapped_back():
    frames = [(pose(), conf()) for _ in range(20)] + [(pose(left_ankle_x=0.32), conf()) for _ in range(10)]
    frames += [(pose(left_ankle_x=0.9), conf(low=[L_ANKLE])) for _ in range(3)]  # then a short occlusion
    m, out = run(frames)
    assert any(r["relations"]["feet"]["event"] == "reanchored" for _, r in out)
    x = out[-1][0][L_ANKLE][0]  # filled near the new place 0.32 (w = 0.94 after 3 frames), not the setup place 0.2
    assert abs(x - 0.32) < 0.05 and abs(x - 0.32) < abs(x - 0.2)
    for (P, _), (Q, _) in zip(frames[:30], out[:30]):
        np.testing.assert_array_equal(P, Q)


def test_long_occlusion_expires_and_marks_the_joint_invalid():
    frames = [(pose(), conf()) for _ in range(20)] + [(pose(left_ankle_x=0.6), conf(low=[L_ANKLE])) for _ in range(120)]
    _, out = run(frames)
    early, late = out[25], out[-1]
    assert L_ANKLE in early[1]["filled"] and L_ANKLE not in late[1]["filled"]
    assert L_ANKLE in late[1]["invalid"]
    np.testing.assert_array_equal(late[0], frames[-1][0])  # expired: XS kept, flagged instead of held


def test_real_knee_valgus_is_kept_while_an_ankle_is_occluded():
    """Spec section 10: a real posture error must not be erased. The knees cave in (observed) while the left ankle is
    occluded: knees stay exactly as observed and the valgus ratio follows the truth, not the setup stance."""
    from pose_feedback.body.form_metrics_3d import frame_metrics
    frames, truths = [], []
    for t in range(20):
        frames.append((pose(), conf())); truths.append(pose())
    for t in range(20):
        truth = pose()
        truth[[2, 5], 0] *= 1 - 0.6 * t / 19          # knees move inward: valgus
        xs = truth.copy(); xs[6] += [0.25, 0, 0.1]      # XS misplaces the occluded left ankle
        frames.append((xs, conf(low=[L_ANKLE]))); truths.append(truth)
    _, out = run(frames)
    for (P, _), (Q, _), G in zip(frames, out, truths):
        np.testing.assert_array_equal(Q[[2, 5]], P[[2, 5]])  # knees untouched
    ratio = lambda J: frame_metrics(J, "left")["kneeAnkleGapRatio"]
    # closer to the truth than XS (fill weight exp(-20/45) = 0.64 by the last frame: decays, never a hard hold)
    assert abs(ratio(out[-1][0]) - ratio(truths[-1])) < 0.6 * abs(ratio(frames[-1][0]) - ratio(truths[-1]))
    assert ratio(out[-1][0]) < 0.5 * ratio(out[19][0])  # the cave-in is still there after the fill
