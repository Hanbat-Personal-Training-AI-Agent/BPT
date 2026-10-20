#!/usr/bin/env python3
"""Synthetic post-XS behavior checks, separate from real RTMPose/XS experiments.

The generator's truth is scorer-only. Runtime receives noisy pose/image samples,
confidence, fixed-camera evidence, and a profile from its own first 60 samples.
These are adversarial engineering cases, not clinical or dataset accuracy.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pose_feedback.geometry.exercise_motion import EDGES, ExerciseMotionEstimator, VARIANTS

CASES = (
    "row_cv_short", "row_turn_visible_elbow", "row_turn_hidden_arm", "row_long",
    "pushup_support_root_motion", "squat_support_root_motion",
    "squat_reposition_visible", "squat_reposition_hidden",
    "row_single_confident_jump", "row_actual_torso_lean",
    "squat_actual_valgus", "pushup_actual_hip_sag",
)
SEEDS, N, START, FPS = (301, 302, 303), 210, 90, 30


def base_pose():
    return np.array([
        [0, 0, 0], [.08, .02, 0], [.10, .25, .01], [.12, .48, 0],
        [-.08, .02, 0], [-.10, .25, .01], [-.12, .48, 0],
        [0, -.2, 0], [0, -.4, 0], [0, -.45, 0], [0, -.52, 0],
        [-.20, -.36, 0], [-.35, -.15, 0], [-.45, .05, 0],
        [.20, -.36, 0], [.35, -.15, 0], [.45, .05, 0],
    ])


def leg(p):
    return np.mean([np.linalg.norm(p[a] - p[b]) + np.linalg.norm(p[b] - p[c])
                    for a, b, c in ((1, 2, 3), (4, 5, 6))])


def generate(name, seed):
    exercise = "barbell_row" if name.startswith("row") else name.split("_")[0]
    rng = np.random.default_rng(seed)
    t = np.arange(N)
    world = np.broadcast_to(base_pose(), (N, 17, 3)).copy()
    target = [13] if exercise in ("barbell_row", "pushup") else [3]
    damage = np.zeros((N, 17), bool)
    start, end = 96, 106
    ramp = np.clip((t - 96) / 9, 0, 1) * np.clip((165 - t) / 9, 0, 1)
    if name in ("row_cv_short", "row_long"):
        world[:, 13, 0] += .06 * t / FPS
        end = 141 if name == "row_long" else 106
        damage[start:end, 13] = True
    elif name.startswith("row_turn"):
        # Wrist reaches a smooth reversal while its neighbor is either seen or hidden.
        motion = .12 * np.sin((t - 100) * .06 + np.pi / 2)
        for j, fraction in ((13, 1), (12, .55), (16, 1), (15, .55)):
            world[:, j, 1] -= motion * fraction
        end = 120
        damage[90:end, [13, 16]] = True
        start = 90
        if name.endswith("hidden_arm"):
            damage[90:end, [12, 15]] = True
    elif name.endswith("support_root_motion"):
        root_y = .10 * np.sin((t - 70) * .045)
        world[:, :3, 1] += root_y[:, None]
        world[:, 4:6, 1] += root_y[:, None]
        world[:, 7:13, 1] += root_y[:, None]
        world[:, 14:16, 1] += root_y[:, None]
        damage[start:end, target] = True
    elif "reposition" in name:
        move = .13 * np.clip((t - 96) / 9, 0, 1)
        world[:, 3, 0] += move
        world[:, 2, 0] += move * .3
        if name.endswith("hidden"):
            damage[92:116, 3] = True
            start, end = 92, 116
    elif name == "row_actual_torso_lean":
        theta = np.radians(35 * ramp)
        for j in range(7, 17):
            y, z = base_pose()[j, 1:]
            world[:, j, 1] = y * np.cos(theta) - z * np.sin(theta)
            world[:, j, 2] = y * np.sin(theta) + z * np.cos(theta)
        target = [8, 11, 14]
    elif name == "squat_actual_valgus":
        world[:, 2, 0] -= .08 * ramp
        world[:, 5, 0] += .08 * ramp
        target = [2, 5]
    elif name == "pushup_actual_hip_sag":
        # Supine base rotated into an extended horizontal chain.
        p = base_pose().copy()
        p[:, 0], p[:, 1], p[:, 2] = p[:, 1].copy(), p[:, 2].copy(), p[:, 0].copy()
        world[:] = p
        world[:, [0, 1, 4], 1] += (.12 * ramp)[:, None]
        target = [0, 1, 4, 8]
    truth = world - world[:, :1]
    scale = leg(truth[0])
    raw = truth + rng.normal(0, .003 * scale, truth.shape)
    raw -= raw[:, :1]
    screen = np.concatenate([
        world[:, :, :2] + [.5, .55] + rng.normal(0, .001 * scale, (N, 17, 2)),
        np.full((N, 17, 1), .95),
    ], axis=-1)
    for j in range(17):
        hidden = np.flatnonzero(damage[:, j])
        if len(hidden):
            previous = hidden[0] - 1
            raw[hidden, j] = raw[previous, j] + [.22, -.18, .20]
            screen[hidden, j, :2] = screen[previous, j, :2]
            screen[hidden, j, 2] = .05
    if name == "row_single_confident_jump":
        raw[100, 13] += [.32, -.25, .25]
        screen[100, 13, :2] += [.32, -.25]
        damage[100, 13] = True
    return dict(name=name, exercise=exercise, raw=raw, screen=screen, truth=truth,
                world=world, damage=damage, target=target, scale=scale, start=start, end=end)


def runtime(sample, variant):
    raw, screen = sample["raw"], sample["screen"]
    observed = raw[21:81]
    lengths = {f"{a}-{b}": float(np.median(np.linalg.norm(observed[:, a] - observed[:, b], axis=-1)))
               for a, b in EDGES}
    denominator = np.mean([lengths["1-2"] + lengths["2-3"], lengths["4-5"] + lengths["5-6"]])
    profile = {k: v / denominator for k, v in lengths.items()}
    estimator = ExerciseMotionEstimator(sample["exercise"], variant)
    poses, invalid, states, uncertainty, phases = [], [], [], [], []
    for i in range(N):
        if i == 81:
            estimator.set_bone_profile(profile, .4)
        out = estimator.update(raw[i], screen[i], i / FPS, fixed_camera=True,
                               person_id="synthetic", grip_confirmed=False)
        poses.append(out["corrected"])
        invalid.append(out["invalid"])
        states.append([out["contacts"].get(str(j), "NONE") for j in range(17)])
        uncertainty.append(out["uncertainty"])
        phases.append(out["phase"])
    return np.array(poses), np.array(invalid), np.array(states), np.array(uncertainty), phases


def mean(x):
    return float(np.mean(x)) if np.size(x) else None


def first_run(mask, at, run=3):
    return next((i for i in range(at, len(mask) - run + 1) if mask[i:i + run].all()), None)


def posture_signal(p, name):
    if name == "row_actual_torso_lean":
        v = (p[:, 11] + p[:, 14] - p[:, 1] - p[:, 4]) / 2
        return np.degrees(np.arccos(np.clip(-v[:, 1] / np.linalg.norm(v, axis=1), -1, 1))), 20., [1, 4, 11, 14]
    if name == "squat_actual_valgus":
        ratio = np.abs(p[:, 2, 0] - p[:, 5, 0]) / np.maximum(np.abs(p[:, 3, 0] - p[:, 6, 0]), 1e-9)
        return 1 - ratio, .5, [2, 3, 5, 6]
    if name == "pushup_actual_hip_sag":
        return (p[:, 1, 1] + p[:, 4, 1]) / 2 - (p[:, 3, 1] + p[:, 6, 1] + p[:, 11, 1] + p[:, 14, 1]) / 4, .06, [1, 4, 3, 6, 11, 14]
    return None


def score(sample, output):
    p, invalid, states, uncertainty, phases = output
    gt, scale, damage, target = sample["truth"], sample["scale"], sample["damage"], sample["target"]
    error = np.linalg.norm(p - gt, axis=-1) / scale * 100
    raw_error = np.linalg.norm(sample["raw"] - gt, axis=-1) / scale * 100
    result = dict(target_error_leg_pct=mean(error[START:, target]),
                  occluded_error_leg_pct=mean(error[damage]),
                  target_abstention_fraction=mean(invalid[START:, target]),
                  hidden_abstention_fraction=mean(invalid[damage]),
                  hidden_uncertainty_leg_pct=mean(uncertainty[damage] / scale * 100),
                  hidden_joint_frames=int(damage.sum()))
    delta, delta_gt = p[5:] - p[:-5], gt[5:] - gt[:-5]
    distance = np.linalg.norm(delta_gt, axis=-1)
    eligible = (distance > .03 * scale) & (np.arange(N - 5)[:, None] >= START)
    projection = (delta * delta_gt).sum(-1) / np.maximum(distance**2, 1e-12)
    result["moving_eligible_joint_windows"] = int(eligible.sum())
    result["movement_suppressed_fraction"] = mean(projection[eligible] < .5)
    result["moving_projection_ratio"] = mean(projection[eligible])
    recoveries, censored = [], 0
    for j in range(17):
        for end in np.flatnonzero(damage[:-1, j] & ~damage[1:, j]) + 1:
            recovered = (~invalid[:, j]) & (error[:, j] <= np.maximum(2., raw_error[:, j] + 1.))
            hit = first_run(recovered, end)
            if hit is not None and hit - end <= 30:
                recoveries.append((hit - end) / FPS)
            else:
                censored += 1
    result["recovery_seconds"] = mean(recoveries)
    result["recovery_censored_after_1s"] = censored
    if "reposition" in sample["name"]:
        moving = np.flatnonzero(states[96:, 3] == "MOVING") + 96
        result["release_seconds_from_true_move"] = float((moving[0] - 96) / FPS) if len(moving) else None
        contact = np.flatnonzero(states[106:, 3] == "CONTACT") + 106
        result["reanchor_seconds_after_move_end"] = float((contact[0] - 105) / FPS) if len(contact) else None
        result["final_foot_error_leg_pct"] = mean(error[140:, 3])
    if "support_root_motion" in sample["name"]:
        j = target[0]
        support_screen = p[:, j, :2] + sample["world"][:, 0, :2]
        result["hidden_contact_xy_error_leg_pct"] = mean(np.linalg.norm(
            support_screen[damage[:, j]] - sample["world"][damage[:, j], j, :2], axis=-1) / scale * 100)
    if sample["name"] == "row_single_confident_jump":
        result["jump_error_leg_pct"] = float(error[100, 13])
        result["jump_invalid"] = bool(invalid[100, 13])
    signal = posture_signal(gt, sample["name"])
    if signal:
        truth_signal, threshold, joints = signal
        predicted = posture_signal(p, sample["name"])[0]
        bad = truth_signal > threshold
        assessed = ~invalid[:, joints].any(axis=1)
        result.update(
            posture_error_frames=int(bad.sum()), posture_assessed_error_frames=int((bad & assessed).sum()),
            posture_missed_error_frames=int((bad & assessed & (predicted <= threshold)).sum()),
            posture_abstained_error_frames=int((bad & ~assessed).sum()),
            posture_peak_ratio=float(np.max(predicted) / np.max(truth_signal)),
            posture_note="Synthetic geometric threshold; not a clinical rule or human-labelled error.")
    return result


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=False)
    manifest = dict(kind="synthetic_post_XS_behavior_not_dataset_accuracy", seeds=SEEDS,
                    cases=CASES, frames=N, fps=FPS, score_start=START,
                    generator_sha256=sha(__file__),
                    estimator_sha256=sha(ROOT / "pose_feedback/geometry/exercise_motion.py"),
                    gt_runtime_input=False, warning_labels="synthetic_geometry_only",
                    uncertainty_is_accuracy_guarantee=False)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    records = []
    for case in CASES:
        for seed in SEEDS:
            sample = generate(case, seed)
            for variant in VARIANTS:
                records.append(dict(case=case, seed=seed, variant=variant,
                                    metrics=score(sample, runtime(sample, variant))))
        print(case, "complete", flush=True)
        (out / "results.json").write_text(json.dumps(dict(manifest=manifest, records=records), indent=2) + "\n")


if __name__ == "__main__":
    main()
