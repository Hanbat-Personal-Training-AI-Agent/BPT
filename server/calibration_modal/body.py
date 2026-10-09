"""SMPL shape helpers that need no fitting: height of a shape, putting the user's height into β,
H36M joints and the bone length table.

Arrays come from the SMPL model file (v_template (6890, 3), shapedirs (6890, 3, ≥10)); the model
itself is licensed and never stored in this repository.
"""
import numpy as np

# docs/research/rtmpose_motionagformer_image_to_pose_pipeline.md §12 (MotionAGFormer order).
H36M_JOINTS = ("pelvis", "right_hip", "right_knee", "right_ankle", "left_hip", "left_knee", "left_ankle",
               "spine", "thorax", "neck", "head", "left_shoulder", "left_elbow", "left_wrist",
               "right_shoulder", "right_elbow", "right_wrist")
H36M_PARENTS = (-1, 0, 1, 2, 0, 4, 5, 0, 7, 8, 9, 8, 11, 12, 8, 14, 15)
# The app builds these from COCO averages (§12), so lengths touching them mean something else there.
APP_SYNTHESIZED = {"spine", "thorax", "neck", "head"}


def shaped_vertices(v_template, shapedirs, beta):
    """Rest-pose (T-pose) vertices of shape β, in metres."""
    return v_template + shapedirs[:, :, : len(beta)] @ np.asarray(beta, dtype=float)


def height_m(vertices):
    """Standing height of a rest-pose mesh: top of the head to the sole (SMPL y is up)."""
    return float(vertices[:, 1].max() - vertices[:, 1].min())


def height_gradient(v_template, shapedirs, beta):
    """(g, h0) so that height(β') ≈ h0 + gᵀβ' near β, using the current top and bottom vertices."""
    beta = np.asarray(beta, dtype=float)
    v = shaped_vertices(v_template, shapedirs, beta)
    top, bottom = v[:, 1].argmax(), v[:, 1].argmin()
    g = shapedirs[top, 1, : len(beta)] - shapedirs[bottom, 1, : len(beta)]
    return g, height_m(v) - g @ beta


def project_to_height(v_template, shapedirs, beta, height, iterations=4):
    """β_H = β̄ + g·(H − h₀ − gᵀβ̄)/(gᵀg): the closest β (Euclidean) on the height-H hyperplane.

    SMPL height is linear in β only while the top and bottom vertices stay the same, and they
    change with β; re-linearising at the result a few times removes the ~1 cm that one step misses.
    Each step moves along g only, so the result is still the projection onto the final hyperplane.
    """
    beta = np.asarray(beta, dtype=float).copy()
    for _ in range(iterations):
        g, h0 = height_gradient(v_template, shapedirs, beta)
        beta = beta + g * (height - h0 - g @ beta) / (g @ g)
    return beta


def h36m_joints(vertices, j_regressor_h36m):
    """(17, 3) joints from a (17, 6890) regressor such as J_regressor_h36m."""
    return np.asarray(j_regressor_h36m) @ vertices


def bone_lengths_cm(joints):
    """16 parent-child segments of the H36M skeleton plus shoulder and hip width, in centimetres."""
    joints = np.asarray(joints, dtype=float)
    segments = {}
    for child, parent in enumerate(H36M_PARENTS):
        if parent >= 0:
            segments[f"{H36M_JOINTS[parent]}-{H36M_JOINTS[child]}"] = joints[child] - joints[parent]
    segments["shoulder_width"] = joints[H36M_JOINTS.index("left_shoulder")] - joints[H36M_JOINTS.index("right_shoulder")]
    segments["hip_width"] = joints[H36M_JOINTS.index("left_hip")] - joints[H36M_JOINTS.index("right_hip")]
    return {name: round(float(np.linalg.norm(d)) * 100, 2) for name, d in segments.items()}


def app_definition_differs(segment):
    return any(part in APP_SYNTHESIZED for part in segment.split("-"))
