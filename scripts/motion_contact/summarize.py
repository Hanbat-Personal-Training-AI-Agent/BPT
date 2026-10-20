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
        for key in ("reps", "assessed_reps", "abstained_reps"):
            rules[key] += w[key]
        for name, metrics in w["by_rule"].items():
            by_rule[name].update(metrics)
    result["legacy_warning_proxies"] = dict(rules, by_rule=dict(by_rule),
                                           human_incorrect_form_labels=False)
    diagnostics = Counter()
    contacts = Counter()
    transitions = Counter()
    runtimes = []
    for r in records:
        diagnostics.update(r["diagnostics"])
        path = run / "predictions_HOME_ONLY" / (r["name"] + "_" + r["variant"] + ".npz")
        with np.load(path) as z:
            runtime = z["runtime_ms"][90:]
            runtimes.append(runtime[np.isfinite(runtime)])
            states = z["contacts"][90:]
            contacts.update(states[states != ""].tolist())
            for a, b in zip(states[:-1], states[1:]):
                for old, new in zip(a, b):
                    if old and new and old != new:
                        transitions[old + "->" + new] += 1
    times = np.concatenate(runtimes) if runtimes else np.empty(0)
    result["runtime_ms"] = dict(n=len(times), p50=float(np.median(times)) if len(times) else None,
                                p95=float(np.percentile(times, 95)) if len(times) else None)
    result["diagnostics_since_frame21"] = dict(diagnostics)
    result["contact_joint_frames_from90"] = dict(contacts)
    result["contact_state_transitions_from90"] = dict(transitions)
    result["recovery_censored_events"] = sum(
        r["metrics"].get("recovery_to_original_quality_s", {}).get("censored_after_1s", 0)
        for r in records)
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
