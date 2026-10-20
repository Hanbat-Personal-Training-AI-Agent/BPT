#!/usr/bin/env python
"""Scorer-only confidence audit of completed clean held-out XS outputs.

Run on Home. Export aggregate JSON only, never images or per-frame arrays.
No model, confidence threshold, estimator, or acceptance criterion is fitted.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import sys


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def option(argv, name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--code-root", type=Path, required=True)
    parser.add_argument("--completed-run", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists(), "Preserve previous audit; choose a fresh output"
    code = args.code_root.resolve()
    sys.path[:0] = [str(code), str(code / "scripts")]
    import numpy as np
    from motion_contact.data import HELDOUT, load_observations, load_score_reference

    run = args.completed_run.resolve()
    manifest_path, results_path = run / "manifest.json", run / "results.json"
    manifest = json.loads(manifest_path.read_text())
    results = json.loads(results_path.read_text())
    assert results["complete"], "Audit only completed inference/evaluation"
    expected = next(v for k, v in manifest["outputs"].items()
                    if Path(k).name == "results.json")
    assert digest(results_path) == expected
    argv = manifest["argv"]
    assert not option(argv, "--scenario-dir"), "This audit concerns clean input"
    assert not option(argv, "--limit"), "Use the full clean evaluation"
    names = sorted({r["name"] for r in results["records"]
                    if r["split"] == "heldout" and r["variant"] == "A"})
    assert len(names) == 60, f"Expected all 60 held-out streams, got {len(names)}"
    cache, pose2d = Path(option(argv, "--cache")), Path(option(argv, "--pose2d"))
    dataset = option(argv, "--dataset-root", str(Path.home() / "datasets/fit3d"))
    groups = {
        "all_nonroot_joints": tuple(range(1, 17)),
        "wrists": (13, 16),
        "elbows": (12, 15),
        "ankles": (3, 6),
    }
    # .30 and .45 are frozen runtime boundaries. Remaining bins and 100/200 mm
    # tails are descriptive displays, not a search for replacement thresholds.
    bins = [
        ("below_0.30", -np.inf, .30),
        ("0.30_to_0.45", .30, .45),
        ("0.45_to_0.60", .45, .60),
        ("0.60_to_0.80", .60, .80),
        ("at_least_0.80", .80, np.inf),
        ("at_least_0.45_frozen_reliable_threshold", .45, np.inf),
        ("all_scores", -np.inf, np.inf),
    ]
    buckets, inputs, stream_counts = defaultdict(list), {}, defaultdict(int)
    counts = dict(nonfinite_3d_error=0, nonfinite_confidence=0,
                  confidence_outside_0_1=0, nonroot_joint_frames=0)
    for name in names:
        o = load_observations(cache / (name + ".npz"), pose2d / (name + ".npz"))
        assert o.subject in HELDOUT
        # The raw XS cache is already produced, immutable, and present in the
        # completed run. GT enters only now, inside this offline scorer.
        ref = load_score_reference(dataset, o)
        for path, value in {**o.inputs, **ref.inputs}.items():
            assert manifest["inputs"][path] == value, ("Changed input", path)
            inputs[path] = value
        pose_m = (o.raw - o.raw[:, :1]) * ref.metres_per_crop_unit[:, None, None]
        error = np.linalg.norm(pose_m - ref.joints_m, axis=-1)[90:] * 1000
        confidence = o.normalized[90:, :, 2]
        counts["nonroot_joint_frames"] += int(error[:, 1:].size)
        counts["nonfinite_3d_error"] += int((~np.isfinite(error[:, 1:])).sum())
        counts["nonfinite_confidence"] += int((~np.isfinite(confidence[:, 1:])).sum())
        counts["confidence_outside_0_1"] += int(
            ((confidence[:, 1:] < 0) | (confidence[:, 1:] > 1)).sum())
        for exercise in ("all", o.exercise):
            stream_counts[exercise] += 1
            for group, joints in groups.items():
                e, c = error[:, joints].ravel(), confidence[:, joints].ravel()
                valid = np.isfinite(e) & np.isfinite(c)
                for label, low, high in bins:
                    selected = valid & (c >= low) & (c < high)
                    buckets[(exercise, group, label)].append(
                        np.column_stack((e[selected], c[selected])))
        print(name, "scored", flush=True)

    rows = []
    for (exercise, group, label), chunks in sorted(buckets.items()):
        values = np.concatenate(chunks)
        e, c = values[:, 0], values[:, 1]
        n = len(e)
        rows.append(dict(
            exercise=exercise, joint_group=group, confidence_bin=label,
            streams=stream_counts[exercise], joint_frames=n,
            mean_confidence=float(c.mean()) if n else None,
            mean_error_mm=float(e.mean()) if n else None,
            median_error_mm=float(np.median(e)) if n else None,
            p95_error_mm=float(np.percentile(e, 95)) if n else None,
            above_100mm_count=int((e > 100).sum()),
            above_200mm_count=int((e > 200).sum()),
            above_100mm_fraction=float((e > 100).mean()) if n else None,
            above_200mm_fraction=float((e > 200).mean()) if n else None))
    output = dict(
        complete=True, source_run=str(run), streams=len(names), score_from=90,
        source_manifest_sha256=digest(manifest_path),
        source_results_sha256=digest(results_path),
        source_hashes={
            str(Path(__file__).resolve()): digest(__file__),
            **{str(code / p): digest(code / p) for p in (
                "scripts/motion_contact/data.py",
                "pose_feedback/body/motionagformer_adapter.py")},
        },
        input_hashes=inputs, counts=counts, groups=rows,
        no_inference=True, no_training=True, gt_role="offline scoring only",
        units="root-relative Euclidean joint error in mm; same GT-only unit conversion as main scorer",
        limitations=[
            "RTMPose SimCC confidence concerns 2D localization, not calibrated 3D correctness.",
            "The >=.45 row includes no estimator temporal-consistency gate.",
            "Head/torso/hip centre confidences include the existing H36M mapping of 2D joints.",
            "Frame counts are temporally correlated; they are not independent subjects.",
            "100/200 mm tails are descriptive, not clinical or adoption thresholds.",
            "Fit3D environment only; high score can coexist with lifting/model bias.",
        ])
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, indent=2, allow_nan=False) + "\n")
    print(args.out, flush=True)


if __name__ == "__main__":
    main()
