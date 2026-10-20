import numpy as np
import pytest

from pose_feedback.geometry.exercise_motion import ContactState, ExerciseMotionEstimator, VARIANTS


def pose():
    return np.array([
        [0, 0, 0], [.08, .02, 0], [.10, .25, .01], [.12, .48, 0],
        [-.08, .02, 0], [-.10, .25, .01], [-.12, .48, 0],
        [0, -.2, 0], [0, -.4, 0], [0, -.45, 0], [0, -.52, 0],
        [-.20, -.36, 0], [-.35, -.15, 0], [-.45, .05, 0],
        [.20, -.36, 0], [.35, -.15, 0], [.45, .05, 0],
    ], dtype=float)


def screen(p):
    return np.column_stack([p[:, :2] + [.5, .55], np.ones(17)])


def warm(m, p=None, n=30, fixed=True):
    p = pose() if p is None else p
    for t in range(n):
        result = m.update(p, screen(p), t / 30, fixed_camera=fixed)
    return result


def test_a_keeps_exact_raw_without_mutating_input():
    p = pose()
    s = screen(p)
    r = ExerciseMotionEstimator("squat", "A").update(p, s, 0)
    np.testing.assert_array_equal(r["raw"], p)
    np.testing.assert_array_equal(r["corrected"], p)
    r["corrected"][0] += 1
    np.testing.assert_array_equal(p, pose())
    np.testing.assert_array_equal(r["raw"], p)


@pytest.mark.parametrize("variant", ["G", "H"])
def test_confirmed_observed_motion_is_exact_and_never_smoothed(variant):
    m = ExerciseMotionEstimator("barbell_row", variant)
    # Ordinary sustained movement, including a direction reversal. It is below
    # the jump gate and fully observed, so every output must be exactly current.
    for t in range(100):
        p = pose()
        p[[8, 11, 12, 13, 14, 15, 16], 2] += .1 * np.sin(t / 9)
        p[[2, 5], 0] += .04 * np.sin(t / 8)
        r = m.update(p, screen(p), t / 30, fixed_camera=True)
        np.testing.assert_array_equal(r["corrected"], p)
        np.testing.assert_array_equal(r["correction_magnitude"], np.zeros(17))
        assert r["diagnostics"]["observation_passthrough"] == list(range(17))
        assert not r["used_prediction"].any()


@pytest.mark.parametrize("variant", ["G", "H"])
def test_recovered_observation_releases_prediction_without_blending(variant):
    m = ExerciseMotionEstimator("barbell_row", variant)
    warm(m)
    p = pose()
    s = screen(p)
    s[13, 2] = .05
    p[13] += [.3, .2, .1]
    hidden = m.update(p, s, 1., fixed_camera=True)
    assert hidden["used_prediction"][13]
    actual = pose()
    actual[13, 0] += .02
    recovered = m.update(actual, screen(actual), 31 / 30, fixed_camera=True)
    np.testing.assert_array_equal(recovered["corrected"][13], actual[13])
    assert recovered["correction_magnitude"][13] == 0
    assert not recovered["used_prediction"][13]


def test_cv_continues_motion_and_is_better_than_hold_on_constant_velocity():
    cv = ExerciseMotionEstimator("barbell_row", "C")
    hold = ExerciseMotionEstimator("barbell_row", "HOLD")
    for t in range(40):
        truth = pose()
        truth[13, 0] += .09 * t / 30
        observed = truth.copy()
        s = screen(truth)
        if t >= 30:
            observed[13] = pose()[13] + [.8, -.5, .4]
            s[13, 2] = .1
        a = cv.update(observed, s, t / 30)
        b = hold.update(observed, s, t / 30)
    assert np.linalg.norm(a["corrected"][13] - truth[13]) < 1e-8
    assert np.linalg.norm(b["corrected"][13] - truth[13]) > .02
    assert a["used_prediction"][13] and a["invalid"][13]


def test_expired_prediction_is_invalid_and_uncertainty_grows():
    m = ExerciseMotionEstimator("barbell_row", "D")
    warm(m)
    p, s = pose(), screen(pose())
    s[13, 2] = .1
    first = m.update(p, s, 1.)
    for t in range(31, 60):
        last = m.update(p, s, t / 30)
    assert last["uncertainty"][13] > first["uncertainty"][13]
    assert last["invalid"][13]
    assert last["roles"][13] == "uncertain_joint"


def test_image_contact_does_not_pin_root_relative_ankle():
    m = ExerciseMotionEstimator("squat", "F")
    warm(m)
    p, s = pose(), screen(pose())
    # Person root moves down; feet remain in the same image coordinates.
    p[:, 1] -= .12
    p[0] = 0
    s[0, 1] += .12
    r = m.update(p, s, 1., fixed_camera=True)
    np.testing.assert_allclose(r["corrected"][3], p[3])
    np.testing.assert_allclose(r["corrected"][6], p[6])
    assert r["contacts"]["3"] == "CONTACT"


def test_contact_rejects_one_high_confidence_jump_but_releases_real_move():
    c = ContactState()
    for t in range(8):
        c.update(np.array([.2, .3]), True, t / 30, .5, True)
    old = c.anchor.copy()
    c.update(np.array([.4, .3]), True, 8 / 30, .5, True)
    np.testing.assert_array_equal(c.anchor, old)
    c.update(np.array([.2, .3]), True, 9 / 30, .5, True)
    for t in range(10, 13):
        c.update(np.array([.4, .3]), True, t / 30, .5, True)
    assert c.state == "MOVING"
    assert c.anchor is None
    for t in range(13, 18):
        c.update(np.array([.4, .3]), True, t / 30, .5, True)
    assert c.state == "CONTACT"
    np.testing.assert_allclose(c.anchor, [.4, .3])


def test_contact_expires_without_observation():
    c = ContactState()
    for t in range(8):
        c.update(np.array([.2, .3]), True, t / 30, .5, True)
    c.update(np.array([9., 9.]), False, .3, .5, True)
    assert c.state == "OCCLUDED"
    np.testing.assert_allclose(c.anchor, [.2, .3])
    c.update(np.array([9., 9.]), False, .8, .5, True)
    assert c.state == "UNINITIALIZED" and c.anchor is None


def test_low_confidence_leg_cannot_make_a_bad_wrist_jump_trusted():
    m = ExerciseMotionEstimator("pushup", "G")
    warm(m)
    p = pose()
    s = screen(p)
    # Camera sees no actual wrist move, but the lifter produces a gross jump.
    p[13, 0] += 1
    p[3] = [0, 100, 0]
    s[3, 2] = 0
    result = m.update(p, s, 1., fixed_camera=True)
    assert result["diagnostics"]["scale"] < 1
    assert 13 in result["diagnostics"]["rejected_joints"]
    assert 13 not in result["diagnostics"]["observation_passthrough"]
    assert result["invalid"][13]


@pytest.mark.parametrize("state,count", [("UNINITIALIZED", 7), ("REACQUIRE", 4)])
def test_contact_candidates_expire_even_before_an_anchor_exists(state, count):
    c = ContactState()
    c.state = state
    point = np.array([.2, .4])
    for i in range(count):
        c.update(point, True, i / 30, 1., True)
    assert c.anchor is None
    for i in range(count, count + 61):
        c.update(point, False, i / 30, 1., True)
    c.update(point, True, (count + 61) / 30, 1., True)
    assert c.state == "UNINITIALIZED"
    assert c.anchor is None
    assert len(c.history) == 1


def test_no_fixed_camera_no_contact_and_no_unverified_grip():
    m = ExerciseMotionEstimator("barbell_row", "G")
    r = warm(m, fixed=False)
    assert set(r["contacts"].values()) == {"UNINITIALIZED"}
    assert r["diagnostics"]["grip_used"] is False
    assert r["roles"][13] == "dynamic_joint"


def test_kinematics_never_normalizes_reliable_form():
    d = ExerciseMotionEstimator("squat", "D")
    e = ExerciseMotionEstimator("squat", "E", {"1-2": .1, "2-3": .1}, .9)
    for t in range(40):
        p = pose()
        p[2, 0] -= .15 * min(t / 30, 1)
        p[8, 0] += .10 * min(t / 30, 1)
        a = d.update(p, screen(p), t / 30)
        b = e.update(p, screen(p), t / 30)
        np.testing.assert_allclose(a["corrected"], b["corrected"])
        assert b["diagnostics"]["bone_corrected"] == []


def test_low_confidence_jump_does_not_pollute_adaptive_prediction():
    m = ExerciseMotionEstimator("barbell_row", "G")
    warm(m)
    raw = pose()
    raw[13] += [.8, -.6, .3]
    s = screen(pose())
    s[13, 2] = .05
    r = m.update(raw, s, 1.)
    assert np.linalg.norm(r["corrected"][13] - pose()[13]) < .01
    np.testing.assert_array_equal(r["raw"], raw)
    assert r["invalid"][13]


def test_person_and_time_reset_remove_old_contact():
    m = ExerciseMotionEstimator("pushup", "G")
    warm(m)
    assert m.contacts[13].anchor is not None
    r = m.update(pose(), screen(pose()), 1., fixed_camera=True, person_id=1)
    assert r["contacts"]["13"] == "UNINITIALIZED"
    warm(m)
    r = m.update(pose(), screen(pose()), .1, fixed_camera=True)
    assert r["contacts"]["13"] == "UNINITIALIZED"


@pytest.mark.parametrize("variant", VARIANTS)
def test_prefix_invariance_no_future_frames(variant):
    def run(length):
        m = ExerciseMotionEstimator("barbell_row", variant)
        result = []
        for t in range(length):
            p = pose()
            p[13, 1] += .04 * np.sin(t / 8)
            s = screen(p)
            if 16 <= t <= 20:
                s[13, 2] = .1
            result.append(m.update(p, s, t / 30, fixed_camera=True)["corrected"])
        return result
    np.testing.assert_array_equal(run(25), run(60)[:25])


def test_missing_initial_observation_is_not_a_zero_pose_measurement():
    p = pose()
    p[13] = np.nan
    s = screen(pose())
    s[13, 2] = 0
    m = ExerciseMotionEstimator("barbell_row", "G")
    r = m.update(p, s, 0)
    assert np.isnan(r["corrected"][13]).all()
    assert r["invalid"][13]
    assert r["roles"][13] == "uncertain_joint"


def test_visible_elbow_reversal_can_damp_hidden_wrist_without_future_phase():
    m = ExerciseMotionEstimator("barbell_row", "H")
    phases = []
    for t in range(40):
        p = pose()
        offset = .006 * (t if t <= 25 else 50 - t)
        p[[12, 13, 15, 16], 1] -= offset
        s = screen(p)
        if t >= 20:
            s[[13, 16], 2] = .1
        result = m.update(p, s, t / 30)
        phases.append(result["phase"])
    assert "transition" in phases[26:29]
    assert result["invalid"][13]


def test_person_change_removes_other_person_calibration():
    m = ExerciseMotionEstimator("squat", "E")
    m.set_bone_profile({"1-2": .5}, .7)
    m.update(pose(), screen(pose()), 0, person_id="one")
    r = m.update(pose(), screen(pose()), 1 / 30, person_id="two")
    assert not r["diagnostics"]["calibration_used"]
    with pytest.raises(ValueError):
        m.set_bone_profile({"1-2": float("nan")}, .7)
