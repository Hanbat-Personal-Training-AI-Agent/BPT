"""Summarize completed Home-only runs without exporting per-frame data."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

import numpy as np


def statistic_leaves(value, prefix=""):
    if isinstance(value, dict):
        if "n" in value and "mean" in value:
            yield prefix, value
        else:
            for key, child in value.items():
                yield from statistic_leaves(child, prefix + "." + key if prefix else key)


def aggregate(records, run):
    weighted, counts = defaultdict(float), Counter()
    for record in records:
        for path, stat in statistic_leaves(record["metrics"]):
            if stat["n"] and stat["mean"] is not None:
                weighted[path] += stat["mean"] * stat["n"]
                counts[path] += stat["n"]
    means = {key: dict(n=counts[key], mean=weighted[key] / counts[key]) for key in counts}
    jf = sum(r["metrics"]["joint_frames"] for r in records)
    result = dict(streams=len(records), joint_frames=jf, means=means,
                  abstention_fraction=sum(r["metrics"]["abstention_fraction"] *
                                          r["metrics"]["joint_frames"] for r in records) / jf)
    result["motion_preservation_proxy"] = {}
    for name in ("all", "artificially_occluded", "assessable"):
        items = [r["metrics"]["motion_preservation_proxy"]["groups"][name] for r in records]
        n = sum(x["eligible_joint_frames"] for x in items)
        result["motion_preservation_proxy"][name] = dict(
            eligible_joint_frames=n,
            suppressed_fraction=sum((x["suppressed_fraction"] or 0) * x["eligible_joint_frames"]
                                    for x in items) / n if n else None)
    stationary = [r["metrics"]["motion_preservation_proxy"] for r in records]
    n = sum(x["gt_stationary_joint_frames"] for x in stationary)
    result["stationary_motion_proxy"] = dict(
        eligible_joint_frames=n, false_movement_fraction=
        sum((x["false_movement_fraction"] or 0) * x["gt_stationary_joint_frames"]
            for x in stationary) / n if n else None)
    rules = Counter()
    by_rule = defaultdict(Counter)
    for r in records:
        w = r["metrics"]["legacy_warning_proxies"]
        for key in ("reps", "assessed_reps", "abstained_reps", "assessed_rule_reps",
                    "abstained_rule_reps", "history_warmup_rule_reps", "not_applicable_rule_reps"):
            rules[key] += w.get(key, 0)
        for name, metrics in w["by_rule"].items():
            by_rule[name].update(metrics)
    result["legacy_warning_proxies"] = dict(rules, by_rule=dict(by_rule),
                                           human_incorrect_form_labels=False)
    calibration = [(r["metrics"]["uncertainty_calibration"],
                    r["metrics"]["uncertainty_calibration"]["radial_error_over_sigma"]["n"])
                   for r in records]
    n = sum(count for value, count in calibration if value["coordinate_95pct_coverage"] is not None)
    result["uncertainty_coordinate_95pct_coverage"] = dict(
        joint_frames=n, coordinate_count=3 * n,
        fraction=sum(value["coordinate_95pct_coverage"] * count for value, count in calibration
                     if value["coordinate_95pct_coverage"] is not None) / n if n else None)
    result["constraint_diagnostics_from21"] = {
        key: sum(r["metrics"]["existing_gate_cpu_ms"].get(key, 0) for r in records)
        for key in ("constraint_proposed_joint_frames", "restored_trusted_joint_frames",
                    "restored_expired_fallback_joint_frames",
                    "constraint_applied_joint_frames")}
    diagnostics = Counter()
    contacts = Counter()
    transitions = Counter()
    runtimes = []
    passthrough_frames = 0
    passthrough_error = app_passthrough_error = 0.
    expired_frames = expired_invalid_frames = 0
    expired_error = app_expired_error = 0.
    app_invalid_frames = app_joint_frames = 0
    for r in records:
        diagnostics.update(r["diagnostics"])
        path = run / "predictions_HOME_ONLY" / (r["name"] + "_" + r["variant"] + ".npz")
        with np.load(path) as z:
            app_invalid_frames += int(z["app_invalid"][90:].sum())
            app_joint_frames += int(z["app_invalid"][90:].size)
            runtime = z["runtime_ms"][90:]
            runtimes.append(runtime[np.isfinite(runtime)])
            states = z["contacts"][90:]
            contacts.update(states[states != ""].tolist())
            for a, b in zip(states[:-1], states[1:]):
                for old, new in zip(a, b):
                    if old and new and old != new:
                        transitions[old + "->" + new] += 1
            if "observation_passthrough" in z:
                trusted = z["observation_passthrough"].copy()
                trusted[:90] = False
                passthrough_frames += int(trusted.sum())
                if trusted.any():
                    raw = z["raw_model"] - z["raw_model"][:, :1]
                    passthrough_error = max(passthrough_error, float(
                        np.max(np.abs(z["corrected"][trusted] - raw[trusted]))))
                    app_passthrough_error = max(app_passthrough_error, float(
                        np.max(np.abs(z["app_pose"][trusted] - raw[trusted]))))
            if "expired_prediction_fallback" in z:
                expired = z["expired_prediction_fallback"].copy()
                expired[:90] = False
                expired_frames += int(expired.sum())
                expired_invalid_frames += int((expired & z["app_invalid"]).sum())
                if expired.any():
                    raw = z["raw_model"] - z["raw_model"][:, :1]
                    expired_error = max(expired_error, float(
                        np.max(np.abs(z["corrected"][expired] - raw[expired]))))
                    app_expired_error = max(app_expired_error, float(
                        np.max(np.abs(z["app_pose"][expired] - raw[expired]))))
    times = np.concatenate(runtimes) if runtimes else np.empty(0)
    result["runtime_ms"] = dict(n=len(times), p50=float(np.median(times)) if len(times) else None,
                                p95=float(np.percentile(times, 95)) if len(times) else None)
    result["diagnostics_since_frame21"] = dict(diagnostics)
    result["expired_prediction_fallback_from90"] = dict(
        joint_frames=expired_frames, invalid_joint_frames=expired_invalid_frames,
        maximum_raw_difference=expired_error, maximum_app_raw_difference=app_expired_error,
        interpretation="Untrusted raw fallback, not successful prediction or observation recovery")
    result["contact_joint_frames_from90"] = dict(contacts)
    result["contact_state_transitions_from90"] = dict(transitions)
    result["after_existing_gates_abstention"] = dict(
        invalid_joint_frames=app_invalid_frames, joint_frames=app_joint_frames,
        fraction=app_invalid_frames / app_joint_frames if app_joint_frames else None)
    result["trusted_observation_passthrough_from90"] = dict(
        joint_frames=passthrough_frames, maximum_absolute_crop_unit_error=passthrough_error,
        after_existing_gates_maximum_absolute_crop_unit_error=app_passthrough_error)
    result["recovery_censored_events"] = sum(
        r["metrics"].get("recovery_to_original_quality_s", {}).get("censored_after_1s", 0)
        for r in records)
    result["recovery_events"] = {
        key: sum(r["metrics"].get("recovery_to_original_quality_s", {}).get(key, 0) for r in records)
        for key in ("eligible_events", "recovered_events", "full_1s_unrecovered_events",
                    "limited_followup_events", "clip_end_censored_events", "next_damage_censored_events")}
    followup = [e["available_followup_s"] for r in records
                for e in r["metrics"].get("recovery_to_original_quality_s", {}).get("events", [])]
    result["recovery_available_followup_s"] = dict(
        n=len(followup), mean=float(np.mean(followup)) if followup else None,
        minimum=float(np.min(followup)) if followup else None,
        maximum=float(np.max(followup)) if followup else None)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    raw = json.loads((args.run / "results.json").read_text())
    assert raw["complete"], "Partial runs must not be presented as completed evaluation"
    buckets = defaultdict(list)
    for record in raw["records"]:
        for exercise in ("all", record["exercise"]):
            buckets[(record["split"], exercise, record["variant"])].append(record)
    output = dict(
        run=str(args.run), complete=True, records=len(raw["records"]),
        aggregation="Joint/frame/count weighted means; runtime quantiles pooled from Home-only arrays.",
        limitations=["GT-rule FP/FN are proxies without human incorrect-form labels.",
                     "RGB-SMPL calibration includes evaluated sequences; secondary assumption only.",
                     "Contact states are inferred; no manual real contact/relocation labels.",
                     "No clinical, product-readiness, or model-adoption conclusion."],
        groups=[dict(split=split, exercise=exercise, variant=variant,
                     **aggregate(records, args.run))
                for (split, exercise, variant), records in sorted(buckets.items())])
    destination = args.out or args.run / "aggregate.json"
    destination.write_text(json.dumps(output, indent=2, allow_nan=False) + "\n")
    print(destination)


if __name__ == "__main__":
    main()
