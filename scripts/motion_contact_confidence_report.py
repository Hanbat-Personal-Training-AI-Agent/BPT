#!/usr/bin/env python
"""Render aggregate confidence audit; no per-frame inputs or model inference."""
import argparse
import hashlib
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("audit", type=Path)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    data = json.loads(a.audit.read_text())
    assert data["complete"] and data["streams"] == 60
    a.out.mkdir(parents=True, exist_ok=True)
    bins = ["below_0.30", "0.30_to_0.45", "0.45_to_0.60",
            "0.60_to_0.80", "at_least_0.80"]
    labels = ["< 0.30", "0.30–0.45", "0.45–0.60", "0.60–0.80", "≥ 0.80"]
    groups = [("all_nonroot_joints", "All joints except pelvis"),
              ("wrists", "Wrists")]
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                         "axes.spines.top": False, "axes.spines.right": False})
    fig, axes = plt.subplots(2, 2, figsize=(11.5, 7), sharex="col",
                             gridspec_kw={"height_ratios": [2.5, 1.2]})
    for col, (group, title) in enumerate(groups):
        table = {r["confidence_bin"]: r for r in data["groups"]
                 if r["exercise"] == "all" and r["joint_group"] == group}
        rows = [table[b] for b in bins]
        x = np.arange(len(bins))
        mean = [np.nan if r["mean_error_mm"] is None else r["mean_error_mm"] for r in rows]
        p95 = [np.nan if r["p95_error_mm"] is None else r["p95_error_mm"] for r in rows]
        axes[0, col].plot(x, mean, "o-", color="#2166ac", label="Mean joint error")
        axes[0, col].plot(x, p95, "s--", color="#b35806", label="95th percentile error")
        axes[0, col].set_title(title, loc="left", fontweight="bold")
        axes[0, col].set_ylabel("Root-relative 3D error (mm)")
        axes[0, col].set_ylim(bottom=0)
        axes[0, col].grid(axis="y", alpha=.2)
        axes[0, col].axvline(1.5, color="#777", linewidth=1, linestyle="--", alpha=.5)
        axes[0, col].legend(frameon=False, fontsize=9)
        counts = [r["joint_frames"] for r in rows]
        axes[1, col].bar(x, counts, color=["#a9b4bf"] * 2 + ["#80aacf"] * 3)
        axes[1, col].set_ylabel("Joint-frames")
        axes[1, col].set_ylim(0, max(counts) * 1.2 if max(counts) else 1)
        for pos, count in zip(x, counts):
            axes[1, col].annotate(f"{count:,}", (pos, count), xytext=(0, 4),
                                  textcoords="offset points", ha="center", fontsize=8)
        axes[1, col].set_xticks(x, labels)
        axes[1, col].set_xlabel("Mapped RTMPose 2D confidence")
        axes[1, col].ticklabel_format(axis="y", style="sci", scilimits=(0, 0))
        axes[1, col].axvline(1.5, color="#777", linewidth=1, linestyle="--", alpha=.5)
    fig.suptitle("2D confidence does not certify 3D correctness",
                 x=.08, y=.97, ha="left", fontsize=16, fontweight="bold")
    fig.text(.08, .92, "Original XS + Halpe26 · 60 held-out Fit3D streams · frames 90 onward",
             color="#555", fontsize=11)
    fig.text(.08, .035,
             "Dashed boundary: fixed confidence threshold 0.45; temporal consistency is not applied here.\n"
             "P95 describes the error distribution, not a confidence interval. Samples are temporally correlated.",
             color="#555", fontsize=9)
    fig.subplots_adjust(top=.85, bottom=.15, left=.08, right=.98, hspace=.25, wspace=.30)
    for ext in ("png", "svg"):
        fig.savefig(a.out / f"motion_contact_confidence.{ext}", dpi=170)
    plt.close(fig)
    provenance = dict(
        input_sha256=hashlib.sha256(a.audit.read_bytes()).hexdigest(),
        report_source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        outputs={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in a.out.glob("motion_contact_confidence.*")})
    (a.out / "figure_manifest.json").write_text(json.dumps(provenance, indent=2) + "\n")


if __name__ == "__main__":
    main()
