"""Summarize fixed synthetic engineering cases; no parameter selection."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--v1", required=True)
    parser.add_argument("--v2", "--candidate", dest="v2", required=True)
    parser.add_argument("--candidate-label", choices=("v2", "v3", "v4"), default="v2")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    inputs, summaries, posture = {}, {}, {}
    candidate = args.candidate_label
    for version, folder in (("v1", args.v1), (candidate, args.v2)):
        path = Path(folder) / "results.json"
        data = json.loads(path.read_text())
        records = data["records"]
        assert len(records) == 12 * 3 * 9
        inputs[version] = dict(results_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                               manifest=data["manifest"])
        summaries[version] = {}
        for case in sorted({r["case"] for r in records}):
            summaries[version][case] = {}
            for variant in ("A", "B", "C", "D", "E", "F", "G", "H", "HOLD"):
                rows = [r["metrics"] for r in records if r["case"] == case and r["variant"] == variant]
                keys = sorted(set().union(*(r.keys() for r in rows)))
                values = {}
                for key in keys:
                    numeric = [r[key] for r in rows if isinstance(r.get(key), (int, float))]
                    if len(numeric) == 3:
                        values[key] = dict(mean=float(np.mean(numeric)),
                                           min=float(min(numeric)), max=float(max(numeric)))
                    elif not numeric:
                        values[key] = None
                    else:
                        values[key] = dict(observed=len(numeric), mean=float(np.mean(numeric)))
                summaries[version][case][variant] = values
        posture[version] = {}
        for variant in ("A", "B", "C", "D", "E", "F", "G", "H", "HOLD"):
            rows = [r["metrics"] for r in records if "actual_" in r["case"] and r["variant"] == variant]
            posture[version][variant] = {
                key: sum(r[key] for r in rows) for key in (
                    "posture_error_frames", "posture_assessed_error_frames",
                    "posture_missed_error_frames", "posture_abstained_error_frames")}
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    summary = dict(kind="synthetic_post_XS_not_dataset_or_clinical_accuracy",
                   inputs=inputs, case_means_and_seed_ranges=summaries,
                   synthetic_posture_totals=posture)
    (out / "motion_contact_stress_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 2, figsize=(13, 4.4), constrained_layout=True)
    cases = ("row_cv_short", "row_long", "row_turn_visible_elbow", "row_turn_hidden_arm")
    labels = ("Straight, 0.33 s", "Straight, 1.50 s", "Turn, elbow visible", "Turn, arm hidden")
    for k, (variant, color) in enumerate(zip(("C", "D", "G", "H", "HOLD"),
                                            ("#599bd6", "#9297a0", "#159b88", "#d56b49", "#8067a3"))):
        means = [summaries[candidate][c][variant]["occluded_error_leg_pct"]["mean"] for c in cases]
        name = {"C": "CV", "D": "Kalman", "G": f"G {candidate}", "H": f"H {candidate}", "HOLD": "Hold"}[variant]
        axes[0].bar(np.arange(4) + (k - 2) * .15, means, width=.145, color=color, label=name)
    axes[0].set_xticks(np.arange(4), labels, rotation=15, ha="right")
    axes[0].set_ylabel("Hidden-joint error / reference leg length (%)")
    axes[0].set_ylim(bottom=0)
    axes[0].set_title("Hidden output error, including uncertain fallback")
    axes[0].legend(ncol=3, fontsize=8)
    selections = (("v1", "B"), ("v1", "D"), ("v1", "G"), ("v1", "H"), (candidate, "G"), (candidate, "H"))
    missed = [posture[v][a]["posture_missed_error_frames"] for v, a in selections]
    withheld = [posture[v][a]["posture_abstained_error_frames"] for v, a in selections]
    axes[1].bar(np.arange(6), missed, color="#d56b49", label="Missed, while assessed")
    axes[1].bar(np.arange(6), withheld, bottom=missed, color="#9297a0", label="Withheld")
    axes[1].set_xticks(np.arange(6), ("EMA", "Kalman", "G v1", "H v1", f"G {candidate}", f"H {candidate}"))
    axes[1].set_ylabel("Frames, out of 534 synthetic error frames")
    axes[1].set_title("Trusted observations preserve visible form changes")
    axes[1].legend(fontsize=8)
    for ax in axes:
        ax.spines[["top", "right"]].set_visible(False)
        ax.grid(axis="y", alpha=.2)
        ax.set_axisbelow(True)
    fig.suptitle("Synthetic behavior stress: 3 fixed noise seeds; no real-image accuracy claim", fontsize=11)
    fig.savefig(out / "motion_contact_stress.png", dpi=180)
    fig.savefig(out / "motion_contact_stress.svg")


if __name__ == "__main__":
    main()
