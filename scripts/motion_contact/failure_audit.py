"""Read-only failure decomposition from frozen saved predictions; no inference.

The output contains aggregate errors and aggregate run descriptions, never
poses, photographs, body profiles, or per-frame arrays.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import sys

import numpy as np


def option(argv, name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


def describe(values):
    x = np.asarray(values, float).ravel()
    finite = x[np.isfinite(x)]
    return dict(n=int(x.size), finite_n=int(finite.size),
                mean=float(finite.mean()) if finite.size else None,
                p50=float(np.median(finite)) if finite.size else None,
                p95=float(np.percentile(finite, 95)) if finite.size else None,
                p99=float(np.percentile(finite, 99)) if finite.size else None,
                maximum=float(finite.max()) if finite.size else None)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--code-root", type=Path, required=True)
    parser.add_argument("--runs", type=Path, nargs="+", required=True)
    parser.add_argument("--baseline-runs", type=Path, nargs="+", help="Optional matching frozen A runs, one per --runs")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    sys.path[:0] = [str(args.code_root), str(args.code_root / "scripts")]
    from motion_contact.data import JOINTS, load_observations, load_score_reference, sha256
    from motion_contact.corruptions import observation_with_keypoints

    output = dict(schema=1, action="saved_prediction_failure_decomposition_no_inference",
                  analysis_sha256=sha256(__file__), runs={},
                  definitions={
                      "age": "seconds since last trusted exact-pass observation; proxy, NOT last accepted measurement",
                      "high_confidence_nontrusted": "confidence>=0.45 and not observation_passthrough; adaptive innovation rejected",
                      "contribution": "sum(variant error - raw A error) over group / ALL scored joint-frames, in mm",
                      "gt_role": "offline error scoring only; no parameter selection or estimator update",
                  })
    assert not args.out.exists(), "Use a fresh aggregate output path"
    if args.baseline_runs:
        assert len(args.baseline_runs) == len(args.runs)
    for run_index, run in enumerate(args.runs):
        manifest_path, result_path = run / "manifest.json", run / "results.json"
        manifest, results = json.loads(manifest_path.read_text()), json.loads(result_path.read_text())
        assert results["complete"]
        assert sha256(result_path) == next(v for k, v in manifest["outputs"].items()
                                           if Path(k).name == "results.json")
        for path, expected in manifest["inputs"].items():
            assert sha256(path) == expected, path
        source = Path(manifest["argv"][0]).resolve().parents[1]
        assert args.code_root.resolve() == source, "Scoring import source must match frozen run"
        for relative, expected in manifest["code"].items():
            assert sha256(source / relative) == expected, relative
        baseline_run = args.baseline_runs[run_index] if args.baseline_runs else run
        baseline_manifest_path = baseline_run / "manifest.json"
        baseline_result_path = baseline_run / "results.json"
        baseline_manifest = json.loads(baseline_manifest_path.read_text())
        baseline_results = json.loads(baseline_result_path.read_text())
        assert baseline_results["complete"]
        assert sha256(baseline_result_path) == next(v for k, v in baseline_manifest["outputs"].items()
                                                    if Path(k).name == "results.json")
        assert baseline_manifest["inputs"] == manifest["inputs"], "Baseline input identity differs"
        assert baseline_manifest["runtime_input_hashes"] == manifest["runtime_input_hashes"]
        baseline_source = Path(baseline_manifest["argv"][0]).resolve().parents[1]
        for relative, expected in baseline_manifest["code"].items():
            assert sha256(baseline_source / relative) == expected, relative
        baseline_records = {r["name"]: r for r in baseline_results["records"]
                            if r["split"] == "heldout" and r["variant"] == "A"}
        argv = manifest["argv"]
        cache, pose = Path(option(argv, "--cache")), Path(option(argv, "--pose2d"))
        scenario = option(argv, "--scenario-dir")
        limit = int(option(argv, "--limit")) if "--limit" in argv else None
        dataset = option(argv, "--dataset-root", str(Path.home() / "datasets/fit3d"))
        records = {(r["name"], r["variant"]): r for r in results["records"] if r["split"] == "heldout"}
        pooled, run_descriptions = defaultdict(lambda: defaultdict(list)), defaultdict(list)
        checks = defaultdict(lambda: dict(root_max=0., raw_model_difference_max=0., trusted_difference_max=0.))
        for name in sorted({n for n, _ in records}):
            clean = load_observations(cache / (name + ".npz"), pose / (name + ".npz"))
            if scenario:
                with np.load(Path(scenario) / (name + ".npz")) as z:
                    o = observation_with_keypoints(clean, z["keypoints"].astype(float),
                                                   z["raw"].astype(float), limit=limit)
                    damage = z["damage"][:len(o.raw)]
            else:
                o = clean
                damage = np.zeros((len(o.raw), 17), bool)
            ref = load_score_reference(dataset, o)
            scale = ref.metres_per_crop_unit[:, None, None]
            arrays = {}
            for variant in ("A", "G-online", "H-online"):
                path = (baseline_run if variant == "A" else run) / "predictions_HOME_ONLY" / (name + "_" + variant + ".npz")
                record = baseline_records[name] if variant == "A" else records[(name, variant)]
                assert sha256(path) == record["artifact_sha256"], path
                with np.load(path) as z:
                    arrays[variant] = {k: z[k].copy() for k in
                        ("corrected", "raw_model", "invalid", "used_prediction", "observation_passthrough")}
            a = arrays["A"]["corrected"]
            assert a.shape == o.raw.shape
            assert np.array_equal(arrays["A"]["raw_model"], o.raw), "Baseline frame/input alignment differs"
            baseline = np.linalg.norm((a - a[:, :1]) * scale - ref.joints_m, axis=-1) * 1000
            for variant in ("G-online", "H-online"):
                z = arrays[variant]
                corrected, trusted = z["corrected"], z["observation_passthrough"]
                error = np.linalg.norm((corrected - corrected[:, :1]) * scale - ref.joints_m, axis=-1) * 1000
                conf = o.normalized[:, :, 2]
                age = np.full(error.shape, np.inf)
                last = np.full(17, -np.inf)
                for t in range(21, len(error)):
                    last[trusted[t]] = o.timestamps[t]
                    age[t] = o.timestamps[t] - last
                scored = np.broadcast_to(np.arange(len(error))[:, None] >= 90, error.shape)
                groups = {
                    "all": scored,
                    "trusted_exact_pass": scored & trusted,
                    "nontrusted": scored & ~trusted,
                    "high_confidence_nontrusted": scored & (conf >= .45) & ~trusted,
                    "medium_confidence_nontrusted": scored & (conf >= .30) & (conf < .45) & ~trusted,
                    "low_confidence_nontrusted": scored & (conf < .30) & ~trusted,
                    "valid_same_mask": scored & ~z["invalid"],
                    "invalid_same_mask": scored & z["invalid"],
                    "used_prediction": scored & z["used_prediction"],
                    "artificial_target": scored & damage,
                }
                for lo, hi in ((0, .35), (.35, .5), (.5, 1), (1, 2), (2, np.inf)):
                    groups[f"nontrusted_age_{lo}_{hi}_s"] = scored & ~trusted & (age >= lo) & (age < hi)
                for j, joint in enumerate(JOINTS):
                    mask = np.zeros_like(scored)
                    mask[90:, j] = True
                    groups["joint_" + joint] = mask
                for group, mask in groups.items():
                    key = variant + "/" + group
                    pooled[key]["raw_error"].append(baseline[mask])
                    pooled[key]["error"].append(error[mask])
                    pooled[key]["delta"].append((error - baseline)[mask])
                    pooled[key]["age"].append(age[mask])
                c = checks[variant]
                c["root_max"] = max(c["root_max"], float(np.max(np.abs(corrected[90:, 0]))))
                c["raw_model_difference_max"] = max(c["raw_model_difference_max"],
                                                     float(np.max(np.abs(z["raw_model"] - o.raw))))
                c["trusted_difference_max"] = max(c["trusted_difference_max"],
                                                   float(np.max(np.abs(corrected[trusted] - a[trusted]))))
                # Consecutive high-confidence rejected observations; aggregate
                # summaries remain on Home and contain no body coordinates.
                rejected = (conf >= .45) & ~trusted
                for j in range(17):
                    edges = np.diff(np.r_[False, rejected[:, j], False].astype(int))
                    for start, stop in zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)):
                        start = max(int(start), 90)
                        if stop <= start:
                            continue
                        section = slice(start, stop)
                        image_factor = o.crops[:, 2] / (2 * o.image_size[1])
                        canonical = corrected * image_factor[:, None, None]
                        steps = np.diff(canonical[section, j], axis=0)
                        dt = np.diff(o.timestamps[section])
                        speed = np.linalg.norm(steps, axis=-1) / dt if len(dt) else []
                        run_descriptions[variant].append(dict(
                            sequence=name, joint=JOINTS[j], frames=int(stop-start),
                            duration_s=float(o.timestamps[stop-1]-o.timestamps[start]),
                            raw_error_mm=describe(baseline[section, j]),
                            predicted_error_mm=describe(error[section, j]),
                            drift_speed_image_heights_s=describe(speed),
                            mean_delta_mm=float((error-baseline)[section, j].mean()),
                            last_trusted_age_at_end_s=float(age[stop-1, j]) if np.isfinite(age[stop-1, j]) else None,
                        ))
            print(run.name, name, flush=True)
        summary = {}
        for key, values in pooled.items():
            v = {field: np.concatenate(parts) for field, parts in values.items()}
            variant = key.split("/")[0]
            all_count = sum(len(x) for x in pooled[variant + "/all"]["error"])
            summary[key] = dict(raw_error_mm=describe(v["raw_error"]), error_mm=describe(v["error"]),
                                paired_delta_mm=describe(v["delta"]),
                                contribution_to_all_delta_mm=float(np.sum(v["delta"]) / all_count),
                                age_since_trusted_s=describe(v["age"]))
        output["runs"][run.name] = dict(
            manifest_sha256=sha256(manifest_path), results_sha256=sha256(result_path),
            baseline_run=str(baseline_run), baseline_manifest_sha256=sha256(baseline_manifest_path),
            baseline_results_sha256=sha256(baseline_result_path),
            held_sequences=len({n for n, _ in records}), checks=checks, groups=summary,
            longest_high_confidence_rejection_runs={
                v: sorted(items, key=lambda x: x["frames"], reverse=True)[:15]
                for v, items in run_descriptions.items()},
            largest_error_high_confidence_rejection_runs={
                v: sorted(items, key=lambda x: x["predicted_error_mm"]["maximum"], reverse=True)[:15]
                for v, items in run_descriptions.items()})
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, indent=2, allow_nan=False) + "\n")


if __name__ == "__main__":
    main()
