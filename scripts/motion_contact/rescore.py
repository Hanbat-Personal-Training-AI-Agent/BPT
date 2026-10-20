"""Correct warning/recovery scoring from immutable saved outputs; no inference."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT), str(ROOT / "scripts")]
import numpy as np

from motion_contact.data import load_observations, load_score_reference, sha256
from motion_contact.corruptions import observation_with_keypoints
from motion_contact.metrics import score_recovery
from motion_contact.rule_proxies import score_warning_proxies
from motion_contact_eval import json_write, source_hashes


def option(argv, name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("original", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    original, out = args.original.resolve(), args.out.resolve()
    assert original != out, "Historical scores must not be overwritten"
    manifest_path, results_path = original / "manifest.json", original / "results.json"
    manifest, raw = json.loads(manifest_path.read_text()), json.loads(results_path.read_text())
    assert raw["complete"]
    expected = next(v for k, v in manifest["outputs"].items() if Path(k).name == "results.json")
    assert sha256(results_path) == expected
    # Verify the complete original input/source identity before reusing outputs.
    for path, expected in manifest["inputs"].items():
        assert sha256(path) == expected, ("changed original input", path)
    original_root = Path(manifest["argv"][0]).resolve().parents[1]
    for relative, expected in manifest["code"].items():
        assert sha256(original_root / relative) == expected, ("changed original source", relative)
    spec = dict(schema=1, action="scorer_only_correction_without_inference",
                original_manifest_sha256=sha256(manifest_path), original_results_sha256=sha256(results_path),
                original_argv=manifest["argv"], original_input_hashes=manifest["inputs"],
                code=source_hashes(), changed_fields=["legacy_warning_proxies", "recovery_to_original_quality_s"])
    out.mkdir(parents=True, exist_ok=True)
    spec_path = out / "run_spec.json"
    if spec_path.exists():
        assert json.loads(spec_path.read_text()) == spec, "Use a fresh scorer-correction directory"
    else:
        json_write(spec_path, spec)
    linked = out / "predictions_HOME_ONLY"
    if not linked.exists():
        linked.symlink_to(original / "predictions_HOME_ONLY", target_is_directory=True)
    assert linked.resolve() == (original / "predictions_HOME_ONLY").resolve()
    argv = manifest["argv"]
    cache, pose2d = Path(option(argv, "--cache")), Path(option(argv, "--pose2d"))
    scenario = option(argv, "--scenario-dir")
    limit = option(argv, "--limit")
    limit = int(limit) if limit else None
    dataset = option(argv, "--dataset-root", str(Path.home() / "datasets/fit3d"))
    grouped = defaultdict(list)
    for record in raw["records"]:
        grouped[record["name"]].append(record)
    complete = []
    for name, records in sorted(grouped.items()):
        destination = out / "sequences" / (name + ".json")
        if destination.exists():
            complete.extend(json.loads(destination.read_text())["records"])
            continue
        clean = load_observations(cache / (name + ".npz"), pose2d / (name + ".npz"))
        if scenario:
            with np.load(Path(scenario) / (name + ".npz")) as z:
                o = observation_with_keypoints(clean, z["keypoints"].astype(float), z["raw"].astype(float),
                                               limit=limit)
                damage = z["damage"][:len(o.raw)]
        else:
            o = load_observations(cache / (name + ".npz"), pose2d / (name + ".npz"), limit=limit)
            damage = np.zeros((len(o.raw), 17), bool)
        reference = load_score_reference(dataset, o)
        scale = reference.metres_per_crop_unit[:, None, None]
        clean_matched = clean.raw[:len(o.raw)] * (clean.crops[:len(o.raw), 2] / o.crops[:, 2])[:, None, None]
        baseline = (clean_matched - clean_matched[:, :1]) * scale
        baseline_error = np.linalg.norm(baseline - reference.joints_m, axis=-1) * 1000
        for record in records:
            path = linked / (name + "_" + record["variant"] + ".npz")
            assert sha256(path) == record["artifact_sha256"], ("changed prediction", path)
            with np.load(path) as z:
                pose = (z["corrected"] - z["corrected"][:, :1]) * scale
                error = np.linalg.norm(pose - reference.joints_m, axis=-1) * 1000
                record["metrics"]["legacy_warning_proxies"] = score_warning_proxies(
                    o, reference, z["app_pose"], z["app_invalid"])
                record["metrics"]["recovery_to_original_quality_s"] = score_recovery(
                    error, baseline_error, z["invalid"], damage, o.timestamps)
            record["scorer_correction"] = spec["changed_fields"]
        json_write(destination, dict(records=records))
        complete.extend(records)
        print(name, len(records), "saved predictions rescored", flush=True)
    json_write(out / "results.json", dict(complete=True, records=complete))
    json_write(out / "manifest.json", dict(spec, records=len(complete),
               outputs={str(out / "results.json"): sha256(out / "results.json")}))
    print("ALLDONE_SCORER_ONLY", len(complete), out, flush=True)


if __name__ == "__main__":
    main()
