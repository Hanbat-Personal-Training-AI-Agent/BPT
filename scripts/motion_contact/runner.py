"""Estimator boundary and causal profile preparation, with no GT imports."""
import time

import numpy as np

from pose_feedback.body.motionagformer_adapter import coco17_to_motionagformer_h36m17
from pose_feedback.geometry.exercise_motion import ExerciseMotionEstimator
from .data import BONES

FIRST_USABLE, CALIBRATION_END, SCORE_START = 21, 81, 90


def profile_ratios(lengths):
    lengths = np.asarray(lengths, float)
    by_edge = dict(zip(BONES, lengths))
    legs = [by_edge[(1, 2)] + by_edge[(2, 3)], by_edge[(4, 5)] + by_edge[(5, 6)]]
    finite = [x for x in legs if np.isfinite(x) and x > 1e-6]
    if not finite:
        return {}
    scale = np.median(finite)
    return {f"{a}-{b}": float(v / scale) for (a, b), v in by_edge.items()
            if np.isfinite(v) and v > 0}


def online_profile(raw_image_units, confidence):
    """Lengths only; never record an initial pose as the correct exercise form."""
    p, conf = raw_image_units[FIRST_USABLE:CALIBRATION_END], confidence[FIRST_USABLE:CALIBRATION_END]
    lengths = []
    for a, b in BONES:
        good = (conf[:, a] >= .45) & (conf[:, b] >= .45) & np.isfinite(p[:, [a, b]]).all(axis=(1, 2))
        values = np.linalg.norm(p[:, a] - p[:, b], axis=-1)[good]
        lengths.append(np.median(values) if len(values) >= 30 else np.nan)
    return profile_ratios(lengths)


def run_variant(observations, variant, *, profile_mode="online", rgb_lengths=None):
    o = observations
    n = len(o.raw)
    factor = o.crops[:, 2] / (2 * o.image_size[1])
    raw_centered = o.raw - o.raw[:, :1]
    raw = raw_centered * factor[:, None, None]
    xy, conf = coco17_to_motionagformer_h36m17(o.keypoints[:, :17])
    screen = np.concatenate([xy / o.image_size[1], conf[..., None]], -1)
    if profile_mode == "online":
        profile, confidence = online_profile(raw, conf), .4
    elif profile_mode == "rgb_smpl":
        assert rgb_lengths is not None
        profile, confidence = profile_ratios(rgb_lengths), .7
    else:
        profile, confidence = {}, 0.
    estimator = ExerciseMotionEstimator(o.exercise, variant=variant)
    corrected = raw_centered.copy()
    uncertainty = np.full((n, 17), np.nan)
    invalid = np.ones((n, 17), bool)
    used_prediction = np.zeros((n, 17), bool)
    observation_passthrough = np.zeros((n, 17), bool)
    corrections = np.zeros((n, 17))
    contacts = np.full((n, 17), "", dtype="U16")
    roles = np.full((n, 17), "unavailable", dtype="U32")
    phases = np.full(n, "unknown", dtype="U16")
    runtime_ms = np.full(n, np.nan)
    counts = dict(contact_corrections=0, bone_corrections=0, rejected_joint_frames=0,
                  calibration_used_frames=0, grip_used_frames=0)
    for t in range(FIRST_USABLE, n):
        # Initial calibration uses only completed past/current emitted outputs.
        # Set it at 81 after rows21..80; no padded XS rows or future target.
        if t == CALIBRATION_END:
            estimator.set_bone_profile(profile, confidence)
        began = time.perf_counter_ns()
        out = estimator.update(raw[t], screen[t], o.timestamps[t], fixed_camera=True,
                               camera_motion=False, person_id=o.subject, phase=None, grip_confirmed=False)
        runtime_ms[t] = (time.perf_counter_ns() - began) / 1e6
        corrected[t] = out["corrected"] / factor[t]
        uncertainty[t] = out["uncertainty"] / factor[t]
        invalid[t] = out["invalid"]
        used_prediction[t] = out["used_prediction"]
        corrections[t] = out["correction_magnitude"] / factor[t]
        roles[t] = out["roles"]
        phases[t] = out["phase"]
        for j, state in out["contacts"].items():
            contacts[t, int(j)] = state
        d = out["diagnostics"]
        observation_passthrough[t, d.get("observation_passthrough", [])] = True
        counts["contact_corrections"] += len(d["contact_corrected"])
        counts["bone_corrections"] += len(d["bone_corrected"])
        counts["rejected_joint_frames"] += len(d["rejected_joints"])
        counts["calibration_used_frames"] += int(d["calibration_used"])
        counts["grip_used_frames"] += int(d["grip_used"])
    return dict(corrected=corrected, uncertainty=uncertainty, invalid=invalid,
                used_prediction=used_prediction, correction_magnitude=corrections,
                observation_passthrough=observation_passthrough,
                contacts=contacts, roles=roles, phases=phases, runtime_ms=runtime_ms,
                diagnostics=counts, profile_metadata=dict(
                    source_type="online_observation_lengths" if profile_mode == "online" else "rgb_smpl_calibration",
                    calibration_confidence=confidence, available_bones=len(profile),
                    first_usable_frame=FIRST_USABLE,
                    calibration_frames=[FIRST_USABLE, CALIBRATION_END - 1] if profile_mode == "online" else None,
                    profile_activation_frame=CALIBRATION_END,
                    uses_evaluation_sequence=True, uses_gt=False,
                    independent_calibration_assumption=profile_mode == "rgb_smpl"))
