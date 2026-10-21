"""Plot completed frozen aggregates; no inference, tuning or hidden filtering."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--aggregates", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    sources, groups = {}, {}
    for condition in ("clean96", "keypoint6", "rgb6"):
        for version, date in (("v3", "20261020"), ("v4", "20261021")):
            folder = args.aggregates / f"{date}-{version}-{condition}"
            aggregate = folder / "aggregate.json"
            data = json.loads(aggregate.read_text())
            assert data["complete"]
            spec = json.loads((folder / "run_spec.json").read_text())
            sources[f"{version}/{condition}"] = dict(
                aggregate_sha256=hashlib.sha256(aggregate.read_bytes()).hexdigest(),
                protocol_sha256=spec["configuration"]["freeze"],
                source_hashes=spec["code"],
                estimator_input_hashes=spec["runtime_input_hashes"],
                records=data["records"])
            for group in data["groups"]:
                if group["split"] == "heldout":
                    groups[(condition, version, group["exercise"], group["variant"])] = group
    selected = (("v3", "A", "Raw XS"), ("v3", "G-online", "G v3"),
                ("v4", "G-online", "G v4"), ("v4", "H-online", "H v4"))
    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    for (condition, version, exercise, variant), group in sorted(groups.items()):
        rows.append(dict(condition=condition, version=version, exercise=exercise,
                         variant=variant, streams=group["streams"],
                         mpjpe=group["means"]["mpjpe_mm"],
                         target_mpjpe=group["means"].get("categories_mm.artificially_occluded"),
                         motion_proxy=group["motion_preservation_proxy"],
                         invalid_fraction=group["abstention_fraction"],
                         after_gates=group["after_existing_gates_abstention"],
                         uncertainty_coverage=group["uncertainty_coordinate_95pct_coverage"],
                         fallback=group.get("expired_prediction_fallback_from90")))
    summary = dict(
        scope="Held-out descriptive pooled scores; v4 follows inspection of v3 failures.",
        baseline_reuse="A–F/HOLD are reused from v3; v4 recomputes G/H online and RGB-SMPL only.",
        limitations=["Damage sets contain one subject, six camera/exercise streams.",
                     "Artificial targets are intervention masks, not human visibility labels.",
                     "Movement suppression is a GT-only scoring proxy, not clinical false negatives.",
                     "Invalid outputs remain included in all-frame and target MPJPE.",
                     "Different validity masks must not be treated as matched accuracy gains."],
        generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        sources=sources, rows=rows)
    (args.out / "comparison.json").write_text(json.dumps(summary, indent=2) + "\n")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2, 2, figsize=(12, 8), constrained_layout=True)
    colors = ("#858d98", "#c45b4a", "#277da8", "#8461a8")
    for panel, conditions, metric in (
        (axes[0, 0], ("clean96", "keypoint6", "rgb6"), "all"),
        (axes[0, 1], ("keypoint6", "rgb6"), "target"),
        (axes[1, 0], ("keypoint6", "rgb6"), "suppressed"),
        (axes[1, 1], ("clean96", "keypoint6", "rgb6"), "invalid"),
    ):
        x = np.arange(len(conditions))
        for index, ((version, variant, label), color) in enumerate(zip(selected, colors)):
            values = []
            for condition in conditions:
                group = groups[(condition, version, "all", variant)]
                if metric in ("all", "target"):
                    key = "mpjpe_mm" if metric == "all" else "categories_mm.artificially_occluded"
                    value = group["means"][key]["mean"]
                elif metric == "suppressed":
                    value = 100 * group["motion_preservation_proxy"]["artificially_occluded"]["suppressed_fraction"]
                else:
                    value = 100 * group["abstention_fraction"]
                values.append(value)
            panel.bar(x + (index - 1.5) * .19, values, width=.18, label=label, color=color)
        panel.set_xticks(x, [{"clean96": "Clean (60 streams)", "keypoint6": "2D damage (6)",
                            "rgb6": "RGB mask (6)"}[c] for c in conditions])
        panel.spines[["top", "right"]].set_visible(False)
        panel.grid(axis="y", alpha=.2)
        panel.set_axisbelow(True)
        panel.set_ylim(bottom=0)
    axes[0, 0].set(title="All-joint error, including invalid outputs", ylabel="MPJPE (mm)")
    axes[0, 1].set(title="Error at imposed occlusion targets", ylabel="MPJPE (mm)")
    axes[1, 0].set(title="Suppressed displacement at moving targets", ylabel="Eligible windows (%)")
    axes[1, 1].set(title="Joints withheld by the estimator", ylabel="Joint-frames (%)")
    axes[0, 0].legend(ncol=2, fontsize=9)
    fig.suptitle("Frozen v3 and post-result v4 follow-up — accuracy, movement and assessment coverage", fontsize=12)
    fig.savefig(args.out / "comparison.png", dpi=180)
    fig.savefig(args.out / "comparison.svg")
    print(args.out)


if __name__ == "__main__":
    main()
