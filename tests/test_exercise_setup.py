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


def feet_and_coco(P, toe_out=1.0, heel_lift=0.0, conf=0.9):
    """Halpe26 foot points + COCO17 2D consistent with `standing()` seen from the front (x right, y down, px = x 200)."""
    px = lambda v: np.array([v[0] * 200 + 360, v[1] * 200 + 640])
    coco = np.zeros((17, 3)); coco[:, 2] = conf
    for c, h in ((15, 6), (16, 3), (13, 5), (14, 2), (11, 4), (12, 1)):
        coco[c, :2] = px(P[h])
    feet = {}
    for side, h in (("left", 6), ("right", 3)):
        a = px(P[h]); sgn = 1 if side == "left" else -1
        feet[f"{side}_heel"] = (a[0], a[1] + 10 - heel_lift, conf)
        feet[f"{side}_big_toe"] = (a[0] + sgn * (toe_out - 1) * 40, a[1] + 12, conf)
    return feet, coco


def test_foot_items_only_with_halpe26_feet_and_ankle_fallback():
    P = standing()
    plain = ExerciseSetup("squat").update(P, np.full(17, 0.9))
    assert plain["foot_source"] == "ankle" and not any(i["key"] in ("heel_width", "toe_out", "heel_toe") for i in plain["items"])
    feet, coco = feet_and_coco(P, toe_out=1.5)
    r = ExerciseSetup("squat").update(P, np.full(17, 0.9), feet=feet, coco2d=coco)
    it = {i["key"]: i for i in r["items"]}
    assert r["foot_source"] == "halpe26"
    assert abs(it["heel_width"]["value"] - it["feet_width"]["value"]) < 1e-9  # heels right under the ankles
    assert it["toe_out"]["value"] > 1.1 and it["toe_out"]["quality"] == "good"
    assert it["heel_toe"]["quality"] == "depth_estimated"  # a front view cannot read the heel lift
    low_feet, coco = feet_and_coco(P, conf=0.2)
    r = ExerciseSetup("squat").update(P, np.full(17, 0.9), feet=low_feet, coco2d=coco)
    assert {i["key"]: i["quality"] for i in r["items"]}["toe_out"] == "missing"


def side(P, wobble=0.0):
    """standing() turned side-on (the body's left-right axis along the camera depth); wobble = XS's depth guess of the
    left ankle moving frame to frame."""
    Q = P.copy()
    Q[:, 0], Q[:, 2] = -P[:, 2], P[:, 0]
    Q[6, 2] += wobble
    return Q


def coco_of(P, conf=0.9, drop=0.0):
    """COCO17 2D (px = 200 x crop units, y down) of an H36M pose; drop = the whole body lower in the image (px)."""
    k = np.zeros((17, 3)); k[:, 2] = conf
    for c, h in ((5, 11), (6, 14), (7, 12), (8, 15), (9, 13), (10, 16), (11, 4), (12, 1), (13, 5), (14, 2), (15, 6), (16, 3)):
        k[c, :2] = [P[h][0] * 200 + 360, P[h][1] * 200 + 640 + drop]
    return k


def test_side_view_widths_are_held_still_by_the_2d_not_by_xs_depth():
    conf = np.full(17, 0.9)
    frames = [side(standing(), wobble=0.04 * (t % 3 - 1)) for t in range(40)]  # feet_width wobbles 0.4 x hip width
    s = ExerciseSetup("squat")
    out = [s.update(P, conf, coco2d=coco_of(P)) for P in frames]
    q = {i["key"]: i["quality"] for i in out[-1]["items"]}
    assert q["feet_width"] == q["foot_symmetry"] == q["shoulder_over_pelvis"] == "depth_estimated"
    assert q["torso_incline"] == q["foot_stagger"] == "good"
    assert out[29]["phase"] == "ready" and out[29]["motion_2d"] == 0.0  # 30 frames, 2D still
    assert "feet_width" not in s.ready and "torso_incline" in s.ready  # a depth guess is never saved as a reference
    old = ExerciseSetup("squat")  # no 2D: every required item is held to its tolerance, the depth wobble blocks
    assert all(old.update(P, conf)["phase"] != "ready" for P in frames)
    sink = ExerciseSetup("squat")  # 3D unchanged (pelvis-relative) but the body sinks 3 px a frame in the image
    out = [sink.update(frames[0], conf, coco2d=coco_of(frames[0], drop=3.0 * t)) for t in range(40)]
    assert out[-1]["moving"] and sink.ready is None
    hidden, out = ExerciseSetup("squat"), []  # far ankle half hidden for 5 frames: a side-on width cannot block it
    for t, P in enumerate(frames):
        c, k = conf.copy(), coco_of(P)
        if 10 <= t < 15:
            c[6] = k[15, 2] = 0.4
        out.append(hidden.update(P, c, coco2d=k))
    assert out[12]["phase"] == "holding" and out[29]["phase"] == "ready"
    assert next(i for i in out[12]["items"] if i["key"] == "feet_width")["quality"] == "low"
    far = conf.copy(); far[[4, 11]] = 0.4  # far hip / shoulder hidden: the trunk is still seen from the near side
    r = ExerciseSetup("squat").update(frames[0], far, coco2d=coco_of(frames[0]))
    assert {i["key"]: i["quality"] for i in r["items"]}["torso_incline"] == "good"
    assert not any(i["required"] for i in ExerciseSetup("pushup").update(standing(), conf)["items"] if i["key"] == "feet_width")
