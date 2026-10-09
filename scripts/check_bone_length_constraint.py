"""Measure the bone-length constraint on MotionAGFormer npz output.

Usage:
  python scripts/check_bone_length_constraint.py --calibration result.json clip1.npz [clip2.npz ...]

npz files come from scripts/run_coreml_rtmpose_s_motionagformer_xs_pipeline.py
(`pred_3d_selected`, [N,17,3]). Prints, per clip and limb segment: length CV across frames
before/after, mean |correction| (model units and % of the observed length), the clip-median
observed/target ratio relative to the clip scale, and left/right asymmetry before/after.
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pose_feedback.geometry.bone_lengths import (  # noqa: E402
    DEFAULT_SEGMENTS,
    H36M17_PARENTS,
    SEGMENT_NAMES,
    apply_bone_lengths,
    load_bone_length_targets,
)

PAIRS = [
    ("thigh", "left_hip-left_knee", "right_hip-right_knee"),
    ("shin", "left_knee-left_ankle", "right_knee-right_ankle"),
    ("upper_arm", "left_shoulder-left_elbow", "right_shoulder-right_elbow"),
    ("forearm", "left_elbow-left_wrist", "right_elbow-right_wrist"),
]


def lengths(poses):
    return {n: np.linalg.norm(poses[:, c] - poses[:, H36M17_PARENTS[c]], axis=-1) for c, n in enumerate(SEGMENT_NAMES, 1)}


def cv(x):
    return float(np.std(x) / np.mean(x))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--calibration", required=True)
    ap.add_argument("npz", nargs="+")
    args = ap.parse_args()
    targets = load_bone_length_targets(json.loads(Path(args.calibration).read_text()))

    for path in args.npz:
        poses = np.load(path)["pred_3d_selected"].astype("float64")
        outs, scales = [], []
        for p in poses:
            o, r = apply_bone_lengths(p, targets)
            outs.append(o)
            scales.append(r["scale"])
        outs = np.asarray(outs)
        scales = np.asarray(scales, dtype="float64")
        before, after = lengths(poses), lengths(outs)
        clip_scale = float(np.median(scales))
        print(f"\n## {Path(path).stem}  frames={len(poses)}  scale median={clip_scale:.5f} CV={cv(scales):.3f}")
        print("| segment | CV before | CV after | mean |corr| | mean |corr| % | median obs/(target*s) |")
        print("|---|---|---|---|---|---|")
        for n in DEFAULT_SEGMENTS:
            corr = np.abs(after[n] - before[n])
            rel = np.median(before[n] / (targets[n] * scales))
            print(f"| {n} | {cv(before[n]):.3f} | {cv(after[n]):.3f} | {corr.mean():.4f} | "
                  f"{100 * np.mean(corr / before[n]):.1f}% | {rel:.3f} |")
        print("| pair | L/R asym before | L/R asym after |")
        print("|---|---|---|")
        for label, left, right in PAIRS:
            def asym(d):
                return 100 * np.mean(np.abs(d[left] - d[right]) / (0.5 * (d[left] + d[right])))
            print(f"| {label} | {asym(before):.1f}% | {asym(after):.1f}% |")


if __name__ == "__main__":
    main()
