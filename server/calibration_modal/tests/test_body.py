import json
import os
from pathlib import Path

import numpy as np
import pytest

import body
import worker
from conftest import manifest_dict

# Plain-array SMPL neutral (see prepare_weights.py); the model is licensed, so the test is optional.
SMPL_NPZ = os.environ.get("SMPL_NPZ")


def linear_model():
    """A toy body whose height is exactly 1.6 + gᵀβ: top vertex y = 1.6 + gᵀβ, bottom fixed at 0."""
    rng = np.random.default_rng(1)
    v_template = np.array([[0.0, 1.6, 0.0], [0.0, 0.0, 0.0], [0.1, 0.8, 0.0]])
    shapedirs = np.zeros((3, 3, 10))
    shapedirs[0, 1] = rng.normal(0, 0.05, 10)
    return v_template, shapedirs


def test_projection_hits_the_height_and_moves_only_along_g():
    v_template, shapedirs = linear_model()
    start = np.full(10, 0.3)
    beta = body.project_to_height(v_template, shapedirs, start, 1.82)
    assert body.height_m(body.shaped_vertices(v_template, shapedirs, beta)) == pytest.approx(1.82, abs=1e-9)
    g = shapedirs[0, 1]
    moved = beta - start
    assert np.allclose(moved, g * (moved @ g) / (g @ g))  # orthogonal projection: no other change


def test_projection_formula_matches_the_spec_in_one_step():
    v_template, shapedirs = linear_model()
    start = np.linspace(-1, 1, 10)
    g, h0 = shapedirs[0, 1], 1.6
    expected = start + g * (1.7 - h0 - g @ start) / (g @ g)
    assert np.allclose(body.project_to_height(v_template, shapedirs, start, 1.7, iterations=1), expected)


@pytest.mark.skipif(not SMPL_NPZ, reason="set SMPL_NPZ to a plain-array SMPL neutral model")
def test_real_smpl_heights_within_a_millimetre():
    model = np.load(SMPL_NPZ)
    v_template, shapedirs = model["v_template"], model["shapedirs"][:, :, :10]
    rng = np.random.default_rng(0)
    for _ in range(50):
        start = rng.normal(0, 1.0, 10)
        target = rng.uniform(1.45, 2.0)
        beta = body.project_to_height(v_template, shapedirs, start, target)
        assert body.height_m(body.shaped_vertices(v_template, shapedirs, beta)) == pytest.approx(target, abs=1e-3)


def joints_t_pose():
    """H36M joints of a simple T-pose skeleton in metres."""
    j = np.zeros((17, 3))
    named = {"pelvis": (0, 0.9), "right_hip": (-0.1, 0.9), "right_knee": (-0.1, 0.5), "right_ankle": (-0.1, 0.1),
             "left_hip": (0.1, 0.9), "left_knee": (0.1, 0.5), "left_ankle": (0.1, 0.1), "spine": (0, 1.15),
             "thorax": (0, 1.4), "neck": (0, 1.5), "head": (0, 1.65), "left_shoulder": (0.2, 1.4),
             "left_elbow": (0.5, 1.4), "left_wrist": (0.75, 1.4), "right_shoulder": (-0.2, 1.4),
             "right_elbow": (-0.5, 1.4), "right_wrist": (-0.75, 1.4)}
    for name, (x, y) in named.items():
        j[body.H36M_JOINTS.index(name)] = (x, y, 0)
    return j


def test_bone_lengths_cover_the_skeleton_and_widths():
    lengths = body.bone_lengths_cm(joints_t_pose())
    assert len(lengths) == 18
    assert lengths["right_knee-right_ankle"] == 40.0
    assert lengths["left_shoulder-left_elbow"] == 30.0
    assert lengths["shoulder_width"] == 40.0 and lengths["hip_width"] == 20.0
    flagged = {name for name in lengths if body.app_definition_differs(name)}
    assert flagged == {"pelvis-spine", "spine-thorax", "thorax-neck", "neck-head",
                       "thorax-left_shoulder", "thorax-right_shoulder"}


def test_result_schema_keeps_debug_apart():
    m = manifest_dict()
    result = worker.build_result(
        m, beta=np.arange(10) / 10, joints=joints_t_pose(), mesh_height_m=1.718,
        reprojection_px={"front": 3.2},
        per_view={"front": {"body_pose": [0.0] * 69, "global_orient": [0.0] * 3, "transl": [0.0] * 3}})
    json.dumps(result)  # plain JSON
    assert result["smplBeta"][3] == pytest.approx(0.3)
    assert set(result["boneLengthData"]["segments"]) >= {"shoulder_width", "hip_width"}
    assert "thorax-neck" in result["boneLengthData"]["appDefinitionDiffers"]
    assert result["quality"]["heightErrorCm"] == pytest.approx(171.8 - 172.0)
    assert result["quality"]["perView"]["front"] == {"reprojectionErrorPx": 3.2}
    assert result["quality"]["perView"]["back"] == {"reprojectionErrorPx": None}
    front = result["debug"]["per_view"]["front"]
    assert len(front["body_pose"]) == 69 and front["camera"]["fx"] == 70.0
    assert not any(k in result for k in ("body_pose", "global_orient", "transl", "per_view"))


def test_stub_result_has_the_schema_and_no_body():
    result = worker.stub_fit(manifest_dict(), {})
    assert result["stub"] is True and result["smplBeta"] is None and result["boneLengthData"] is None
    assert set(result["debug"]["per_view"]) == {"front", "rightfront", "back", "leftfront"}
