#!/usr/bin/env python
"""Training-free Home experiments; immutable raw caches, GT only in scoring.

All generated arrays/profile measurements stay on Home. RGB masks exist only
in decoder memory and are never viewed, exported, or written as images.
"""
import argparse
from dataclasses import replace
import hashlib
import json
import os
from pathlib import Path
import socket
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / "scripts")]
import numpy as np

from motion_contact.data import (EXERCISES, HELDOUT, TUNING, load_observations,
                                 load_predicted_profiles, load_score_reference, sha256)
from motion_contact.corruptions import (
    BLOCKS, LIMIT, check_cached_windows, corrupt_keypoints, damage_schedule, infer_changed_xs,
    infer_rgb_masks, observation_with_keypoints,
)

VARIANTS = ("A", "B", "C", "D", "E", "F", "G", "H", "HOLD")


def json_write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def source_hashes():
    files = [Path(__file__), *sorted(p for p in (ROOT / "scripts/motion_contact").glob("*.py") if not p.name.startswith(".")),
             ROOT / "pose_feedback/geometry/exercise_motion.py",
             ROOT / "pose_feedback/geometry/pose3d_constraints.py",
             ROOT / "pose_feedback/geometry/anatomical_limits.json",
             ROOT / "pose_feedback/body/form_metrics_3d.py",
             ROOT / "pose_feedback/body/motionagformer_adapter.py",
             ROOT / "scripts/eval_lift_app_fit3d.py",
             ROOT / "scripts/finetune_motionagformer_fit3d.py",
             ROOT / "docs/experiments/motion_contact_contract.md",
             ROOT / "docs/experiments/motion_contact_protocol.md"]
    return {str(p.relative_to(ROOT)): sha256(p) for p in files if p.exists()}


def selected(a):
    subjects, cameras, exercises = set(a.subjects.split(",")), set(a.cameras.split(",")), set(a.exercises.split(","))
    result = []
    for p in sorted(Path(a.cache).glob("*.npz")):
        subject, camera, exercise = p.stem.split("_", 2)
        if subject in subjects and exercise in exercises and ("all" in cameras or camera in cameras):
            result.append((p, Path(a.pose2d) / p.name))
    assert result, "No selected cached observations"
    return result


def run_spec(a):
    inputs = {}
    for cache, pose in selected(a):
        for path in (cache, pose):
            inputs[str(path)] = sha256(path)
        if a.scenario_dir:
            path = Path(a.scenario_dir) / cache.name
            inputs[str(path)] = sha256(path)
    for value in ([a.checkpoint, a.rtm_checkpoint, a.rtm_config] +
                  (a.profiles.split(",") if a.profiles else [])):
        if value and Path(value).is_file():
            inputs[str(Path(value))] = sha256(value)
    if a.profiles:
        for value in a.profiles.split(","):
            path = Path(value).parent / "manifest.json"
            inputs[str(path)] = sha256(path)
    return dict(schema=1, argv=sys.argv, host=socket.gethostname(), python=sys.executable,
                created=time.strftime("%Y-%m-%d %H:%M:%S %Z"), code=source_hashes(),
                configuration=vars(a), runtime_input_hashes=inputs,
                estimator_inputs="raw XS L5 + original image H36M2D/confidence + observed crop + optional predicted profile",
                gt_role="score only; not estimator, profile, anchor, phase, or corruption",
                first_usable_frame=21, calibration_frames=[21, 80], profile_activation=81, score_from=90,
                no_training=True, gpu_used=False,
                threads=int(os.environ.get("OMP_NUM_THREADS", "2")),
                thread_environment={k: os.environ.get(k) for k in
                                    ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS")})


def guard_run_directory(out, spec):
    out.mkdir(parents=True, exist_ok=True)
    path = out / "run_spec.json"
    if path.exists():
        prior = json.loads(path.read_text())
        assert prior["code"] == spec["code"], "Code/protocol changed: use a fresh run directory"
        assert prior.get("configuration") == spec.get("configuration"), "Arguments changed: use a fresh run directory"
        assert prior.get("runtime_input_hashes") == spec.get("runtime_input_hashes"), "Inputs changed: use a fresh run directory"
    else:
        json_write(path, spec)


def run_prepare(a):
    spec, records = run_spec(a), []
    profiles, profile_hashes = load_predicted_profiles(a.profiles.split(",")) if a.profiles else ({}, {})
    for cache, pose in selected(a):
        o = load_observations(cache, pose)
        records.append(dict(name=o.name, subject=o.subject, camera=o.camera, exercise=o.exercise,
                            split=o.split, frames=len(o.raw), predicted_profile_available=o.subject in profiles,
                            inputs=o.inputs))
    spec.update(sequences=records, profile_inputs=profile_hashes, gt_files_read=0,
                profile_source_note="Image-predicted SAM3DB/MHR/SMPL; shared-sequence calibration assumption is explicit")
    json_write(Path(a.out) / "input_inventory.json", spec)
    print(json.dumps(dict(sequences=len(records), frames=sum(x["frames"] for x in records),
                          subjects=sorted({x["subject"] for x in records}), predicted_profiles=len(profiles)), indent=2))


def run_benchmark(a):
    from motion_contact.runner import run_variant
    cache, pose = selected(a)[0]
    o = load_observations(cache, pose, limit=a.limit or LIMIT)
    assert o.subject in TUNING, "Timing pilot must use tuning subjects only"
    began = time.perf_counter()
    output = run_variant(o, "H")
    used = output["runtime_ms"][90:]
    result = dict(name=o.name, frames=len(o.raw), wall_seconds=time.perf_counter() - began,
                  estimator_p50_ms=float(np.nanmedian(used)), estimator_p95_ms=float(np.nanpercentile(used, 95)),
                  gt_files_read=0, code=source_hashes(), predictions_scored=False)
    json_write(Path(a.out) / "timing_pilot.json", result)
    print(json.dumps(result, indent=2))


def run_rgb(a):
    import torch
    from mmpose.apis import init_model
    torch.set_num_threads(2)
    torch.set_num_interop_threads(1)
    model = init_model(a.rtm_config, a.rtm_checkpoint, device="cpu")
    out = Path(a.out)
    guard_run_directory(out, run_spec(a))
    for cache, pose in selected(a):
        path = out / (cache.stem + ".npz")
        if path.exists() and path.with_suffix(".json").exists():
            continue
        o = load_observations(cache, pose)
        keypoints, damaged, report = infer_rgb_masks(o, model, a.dataset_root)
        np.savez_compressed(path, keypoints=keypoints.astype(np.float32), damage=damaged)
        report.update(name=o.name, inputs=o.inputs, model=sha256(a.rtm_checkpoint),
                      config=sha256(a.rtm_config), output_sha256=sha256(path))
        json_write(path.with_suffix(".json"), report)
        print(json.dumps({k: report[k] for k in ("name", "masked_rgb_frames", "seconds")}), flush=True)


def run_inference(a):
    import torch
    from finetune_motionagformer_fit3d import load
    from motion_contact.data import normalize_observations
    torch.set_num_threads(2)
    torch.set_num_interop_threads(1)
    model = load(a.mag_repo, a.checkpoint, "cpu")[0].eval()
    out = Path(a.out)
    guard_run_directory(out, run_spec(a))
    for cache, pose in selected(a):
        dest = out / (cache.stem + ".npz")
        if dest.exists() and dest.with_suffix(".json").exists():
            continue
        o = load_observations(cache, pose)
        parity = check_cached_windows(model, o)
        inputs = dict(o.inputs)
        if a.command == "infer-keypoints":
            keypoints, damage = corrupt_keypoints(o)
            scenario = "keypoint_damage_then_actual_XS"
        else:
            source = Path(a.scenario_dir) / (o.name + ".npz")
            with np.load(source) as z:
                keypoints, damage = z["keypoints"].astype(float), z["damage"].copy()
            inputs[str(source)] = sha256(source)
            scenario = "RGB_mask_then_actual_RTMPose_then_actual_XS"
        x, _ = normalize_observations(keypoints, o.image_size)
        raw, report = infer_changed_xs(model, x, o.normalized, o.raw, limit=a.limit or LIMIT)
        np.savez_compressed(dest, raw=raw.astype(np.float32), keypoints=keypoints.astype(np.float32), damage=damage)
        report.update(name=o.name, scenario=scenario, inputs=inputs, checkpoint_sha256=sha256(a.checkpoint),
                      output_sha256=sha256(dest), blocks=BLOCKS, evaluation_limit=a.limit or LIMIT,
                      no_output_3d_noise=True, gt_files_read=0, clean_cache_parity=parity)
        json_write(dest.with_suffix(".json"), report)
        print(json.dumps({k: report[k] for k in ("name", "scenario", "recomputed_windows", "seconds")}), flush=True)


def run_evaluation(a):
    from motion_contact.runner import run_variant
    from motion_contact.metrics import score_pose
    from motion_contact.rule_proxies import apply_existing_gates, score_warning_proxies
    assert a.freeze, "--freeze requires the frozen protocol's SHA256 before any evaluation"
    protocol = ROOT / "docs/experiments/motion_contact_protocol.md"
    assert sha256(protocol) == a.freeze, "Protocol changed since freezing"
    out = Path(a.out)
    guard_run_directory(out, run_spec(a))
    profiles, profile_hashes = load_predicted_profiles(a.profiles.split(",")) if a.profiles else ({}, {})
    records, all_inputs = [], dict(profile_hashes)
    for cache, pose in selected(a):
        result_path = out / "sequences" / (cache.stem + ".json")
        if result_path.exists():
            prior = json.loads(result_path.read_text())
            records.extend(prior["records"])
            all_inputs.update(prior["observation_inputs"])
            all_inputs.update(prior["score_inputs"])
            all_inputs.update(prior.get("scenario_inputs", {}))
            continue
        clean = load_observations(cache, pose)
        all_inputs.update(clean.inputs)
        damage = None
        scenario_inputs = {}
        if a.scenario_dir:
            source = Path(a.scenario_dir) / (clean.name + ".npz")
            with np.load(source) as z:
                o = observation_with_keypoints(clean, z["keypoints"].astype(float), z["raw"].astype(float),
                                               limit=a.limit or LIMIT)
                damage = z["damage"][:len(o.raw)]
            all_inputs[str(source)] = sha256(source)
            scenario_inputs[str(source)] = sha256(source)
        else:
            o = load_observations(cache, pose, limit=a.limit)
        sequence_outputs = []
        # Produce every estimator output before loading this sequence's GT.
        for variant in a.variants.split(","):
            modes = ("online", "rgb_smpl") if variant in ("E", "G", "H") and o.subject in profiles else ("online",)
            for mode in modes:
                label = variant + ("-SMPL" if mode == "rgb_smpl" else "-online" if variant in ("E", "G", "H") else "")
                result = run_variant(o, variant, profile_mode=mode, rgb_lengths=profiles.get(o.subject))
                app_pose, app_invalid, gate_timing = apply_existing_gates(
                    result["corrected"], result["invalid"], o.exercise, variant,
                    result["observation_passthrough"], result["expired_prediction_fallback"])
                result.update(app_pose=app_pose, app_invalid=app_invalid, gate_timing=gate_timing)
                target = out / "predictions_HOME_ONLY" / (o.name + "_" + label + ".npz")
                target.parent.mkdir(parents=True, exist_ok=True)
                np.savez_compressed(target, raw_model=o.raw, **{k: v for k, v in result.items() if isinstance(v, np.ndarray)})
                sequence_outputs.append((label, result, target))
        ref = load_score_reference(a.dataset_root, o)
        all_inputs.update(ref.inputs)
        sequence_records = []
        for label, result, target in sequence_outputs:
            # Convert clean cached outputs into the corrupted crop units solely
            # for the scorer's matched clean-quality recovery comparison.
            clean_matched = clean.raw[:len(o.raw)] * (clean.crops[:len(o.raw), 2] / o.crops[:, 2])[:, None, None]
            metrics = score_pose(o, ref, result["corrected"], result["uncertainty"], result["invalid"],
                                 result["runtime_ms"], damage=damage, clean_raw=clean_matched)
            metrics["legacy_warning_proxies"] = score_warning_proxies(o, ref, result["app_pose"], result["app_invalid"])
            metrics["existing_gate_cpu_ms"] = result["gate_timing"]
            record = dict(name=o.name, subject=o.subject, camera=o.camera, exercise=o.exercise,
                          split=o.split, variant=label, scenario="clean" if not a.scenario_dir else Path(a.scenario_dir).name,
                          metrics=metrics, diagnostics=result["diagnostics"], profile=result["profile_metadata"],
                          artifact_sha256=sha256(target))
            sequence_records.append(record)
            records.append(record)
        json_write(result_path, dict(records=sequence_records, observation_inputs=o.inputs,
                                     score_inputs=ref.inputs, scenario_inputs=scenario_inputs))
        json_write(out / "partial_results.json", dict(records=records, complete=False))
        print(o.name, len(sequence_records), "variants finished", flush=True)
    json_write(out / "results.json", dict(records=records, complete=True))
    manifest = run_spec(a)
    manifest.update(inputs=all_inputs, records=len(records), protocol_sha256=a.freeze,
                    outputs={str(out / "results.json"): sha256(out / "results.json")})
    json_write(out / "manifest.json", manifest)
    print("ALLDONE", len(records), out, flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=("prepare", "benchmark", "rgb-mask", "infer-keypoints", "infer-rgb-xs", "evaluate"))
    p.add_argument("--cache", required=True)
    p.add_argument("--pose2d", required=True)
    p.add_argument("--dataset-root", default=os.path.expanduser("~/datasets/fit3d"))
    p.add_argument("--subjects", default=",".join(TUNING + HELDOUT))
    p.add_argument("--cameras", default="all")
    p.add_argument("--exercises", default=",".join(EXERCISES))
    p.add_argument("--profiles", default="")
    p.add_argument("--out", required=True)
    p.add_argument("--limit", type=int)
    p.add_argument("--scenario-dir")
    p.add_argument("--variants", default=",".join(VARIANTS))
    p.add_argument("--freeze")
    p.add_argument("--mag-repo", default=os.path.expanduser("~/models/MotionAGFormer"))
    p.add_argument("--checkpoint", default=os.path.expanduser("~/models/MotionAGFormer/checkpoint/motionagformer-xs-h36m.pth.tr"))
    p.add_argument("--rtm-config")
    p.add_argument("--rtm-checkpoint")
    a = p.parse_args()
    Path(a.out).mkdir(parents=True, exist_ok=True)
    {"prepare": run_prepare, "benchmark": run_benchmark, "rgb-mask": run_rgb,
     "infer-keypoints": run_inference, "infer-rgb-xs": run_inference, "evaluate": run_evaluation}[a.command](a)


if __name__ == "__main__":
    main()
