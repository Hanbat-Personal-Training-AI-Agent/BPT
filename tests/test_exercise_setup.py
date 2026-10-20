"""ExerciseSetup: scale-free items, stillness-based ready, personal-reference cues only, depth-share quality."""
import numpy as np

from pose_feedback.body.exercise_setup import ExerciseSetup, measure


def standing(feet=0.4, hip=0.2, z_feet=0.0):
    P = np.zeros((17, 3))
    P[1], P[4] = [-hip / 2, 0, 0], [hip / 2, 0, 0]
    P[2], P[5] = [-feet / 2, 0.45, 0], [feet / 2, 0.45, 0]
    P[3], P[6] = [-feet / 2, 0.9, -z_feet / 2], [feet / 2, 0.9, z_feet / 2]
    P[8] = [0, -0.5, 0]
    P[11], P[14] = [0.18, -0.5, 0], [-0.18, -0.5, 0]
    P[12], P[15] = [0.2, -0.2, 0], [-0.2, -0.2, 0]
    P[13], P[16] = [0.2, 0.05, 0], [-0.2, 0.05, 0]
    return P


def test_items_are_scale_free():
    a, b = measure(standing(), "squat"), measure(standing() * 3.7, "squat")
    assert abs(a["feet_width"] - 2.0) < 1e-9 and abs(a["torso_incline"]) < 1e-9
    for k in a:
        assert abs(a[k] - b[k]) < 1e-9


def test_ready_needs_stillness_and_never_judges_correctness():
    s = ExerciseSetup("squat")
    conf = np.full(17, 0.9)
    out = [s.update(standing(feet=0.4 + 0.1 * (t % 2)), conf) for t in range(40)]  # fidgeting feet (0.5 x hip width)
    assert out[-1]["phase"] == "holding" and out[-1]["moving"] and s.ready is None
    out = [s.update(standing(), conf) for _ in range(30)]
    assert out[-1]["phase"] == "ready" and abs(s.ready["feet_width"] - 2.0) < 1e-9
    assert all("cue" not in i for i in out[-1]["items"])  # no saved reference -> no adjustment cue at all


def test_low_confidence_feet_block_ready_and_reset_the_window():
    s = ExerciseSetup("squat")
    conf = np.full(17, 0.9)
    low = conf.copy(); low[6] = 0.1
    for t in range(29):
        s.update(standing(), conf)
    r = s.update(standing(), low)
    assert r["phase"] == "measuring" and s.ready is None
    assert [i["quality"] for i in r["items"] if i["key"] == "feet_width"] == ["missing"]


def test_personal_reference_cue_and_depth_share():
    s = ExerciseSetup("squat", reference={"feet_width": 2.6})
    r = s.update(standing(), np.full(17, 0.9))
    item = next(i for i in r["items"] if i["key"] == "feet_width")
    assert item["cue"] == "increase" and item["ref"] == 2.6
    side = ExerciseSetup("squat").update(standing(z_feet=0.6), np.full(17, 0.9))  # feet apart along the camera depth
    assert next(i for i in side["items"] if i["key"] == "feet_width")["quality"] == "depth_estimated"


def test_torso_lean_seen_head_on_is_only_an_estimate():
    P = standing()
    P[8] = [0, -0.1, -0.49]  # trunk pointing at the camera (push-up seen from the front)
    r = ExerciseSetup("squat").update(P, np.full(17, 0.9))
    assert next(i for i in r["items"] if i["key"] == "torso_incline")["quality"] == "depth_estimated"
