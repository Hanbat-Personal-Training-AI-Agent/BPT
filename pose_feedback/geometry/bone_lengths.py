"""Bone-length constraint for MotionAGFormer H36M17 3D output (`selected3D`).

Reference implementation; ios/Runner/NativePose/PosePipeline/BoneLengthConstraint.swift
mirrors it and both are pinned by tests/fixtures/bone_length_cases.json.

Targets come from the body calibration result (boneLengthData.segments, cm, rest-pose SMPL
via J_regressor_h36m). MotionAGFormer output is root-relative and in normalized screen
units (not metric), so only proportions are used: per frame,
  s = median(observed / target) over the constrained segments,
and each constrained segment is set to target * s (blended with the observed length by
`blend`). Walking the kinematic tree from the pelvis, every child keeps its direction from
its parent and its whole subtree moves with it; unconstrained segments keep their observed
length. The pelvis never moves.

Order once the 3D path is wired: selected3D -> this -> knee hinge clamp.
"""

import math

try:
    import numpy as np
except ModuleNotFoundError:  # pragma: no cover
    np = None


# H36M17 order as produced by pose_feedback/body/motionagformer_adapter.py::_coco2h36m_xy.
H36M17_JOINTS = [
    "pelvis", "right_hip", "right_knee", "right_ankle", "left_hip", "left_knee", "left_ankle",
    "spine", "thorax", "neck", "head",
    "left_shoulder", "left_elbow", "left_wrist", "right_shoulder", "right_elbow", "right_wrist",
]
H36M17_PARENTS = [-1, 0, 1, 2, 0, 4, 5, 0, 7, 8, 9, 8, 11, 12, 8, 14, 15]
# SEGMENT_NAMES[child - 1] is the "<parent>-<child>" key used by boneLengthData.segments.
SEGMENT_NAMES = [f"{H36M17_JOINTS[H36M17_PARENTS[c]]}-{H36M17_JOINTS[c]}" for c in range(1, 17)]

# Limbs only. Torso/head joints are synthesized from COCO averages in the app (not comparable),
# and pelvis-hip is left out because the app pelvis is the midpoint of COCO hip keypoints
# (surface landmarks), not the SMPL hip joint centers the calibration measured.
DEFAULT_SEGMENTS = (
    "right_hip-right_knee", "right_knee-right_ankle",
    "left_hip-left_knee", "left_knee-left_ankle",
    "left_shoulder-left_elbow", "left_elbow-left_wrist",
    "right_shoulder-right_elbow", "right_elbow-right_wrist",
)
MIN_BONE_LENGTH = 1e-6  # model units; MotionAGFormer-XS bones are ~0.1-0.5


def load_bone_length_targets(data):
    """Turn a calibration result (or its boneLengthData) into {segment: cm}.

    Accepts the status response ({"result": ...}), the result itself, or boneLengthData.
    Drops appDefinitionDiffers segments, names that are not H36M17 parent-child segments
    (e.g. shoulder_width), and values that are missing, non-numeric, non-finite or <= 0.
    """
    for key in ("result", "boneLengthData"):
        if isinstance(data.get(key), dict):
            data = data[key]
    segments = data.get("segments")
    if not isinstance(segments, dict):
        return {}
    skip = set(data.get("appDefinitionDiffers") or [])
    targets = {}
    for name in SEGMENT_NAMES:
        value = segments.get(name)
        if name in skip or isinstance(value, bool) or not isinstance(value, (int, float)):
            continue
        if math.isfinite(value) and value > 0:
            targets[name] = float(value)
    return targets


def apply_bone_lengths(joints_3d, targets_cm, enabled=True, segments=DEFAULT_SEGMENTS, blend=1.0):
    """Return (joints, report) for one H36M17 [17,3] frame.

    report = {"scale": float | None, "segments": {name: {
        "observed": float, "output": float, "target_cm": float | None,
        "constrained": bool, "degenerate": bool}}}
    `scale` is model units per cm (None when no constrained segment was usable, in which
    case the input is returned unchanged). Disabled -> input returned as is (same object).
    """
    if np is None:  # pragma: no cover
        raise ImportError("numpy is required for the bone length constraint")
    unknown = set(segments) - set(SEGMENT_NAMES)
    if unknown:
        raise ValueError(f"unknown segments: {sorted(unknown)}")
    if not 0.0 <= blend <= 1.0:
        raise ValueError("blend must be in [0, 1]")
    j = np.asarray(joints_3d, dtype="float64")
    if j.shape != (17, 3):
        raise ValueError("joints_3d must have shape (17, 3)")

    observed = [0.0] + [float(np.linalg.norm(j[c] - j[H36M17_PARENTS[c]])) for c in range(1, 17)]
    use = [False] * 17
    ratios = []
    report = {"scale": None, "segments": {}}
    for c, name in enumerate(SEGMENT_NAMES, start=1):
        target = targets_cm.get(name)
        degenerate = observed[c] < MIN_BONE_LENGTH
        use[c] = enabled and name in segments and target is not None and not degenerate
        if use[c]:
            ratios.append(observed[c] / target)
        report["segments"][name] = {
            "observed": observed[c], "output": observed[c], "target_cm": target,
            "constrained": False, "degenerate": degenerate,
        }
    if not ratios:
        return joints_3d, report

    scale = _median(ratios)
    report["scale"] = scale
    out = j.copy()
    for c in range(1, 17):
        p = H36M17_PARENTS[c]
        d = j[c] - j[p]
        if use[c]:
            name = SEGMENT_NAMES[c - 1]
            length = observed[c] + blend * (targets_cm[name] * scale - observed[c])
            d = d / observed[c] * length
            report["segments"][name]["constrained"] = True
            report["segments"][name]["output"] = length
        out[c] = out[p] + d
    return out, report


def _median(values):
    v = sorted(values)
    n = len(v)
    return v[n // 2] if n % 2 else 0.5 * (v[n // 2 - 1] + v[n // 2])
