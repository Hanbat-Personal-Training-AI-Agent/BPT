"""Benchmark RTMPose-s Core ML forward-only prediction latency on macOS."""

import csv
import json
import statistics
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from rtmpose_s_coreml_common import COREML_MODEL_PATH, INPUT_NAME, load_or_create_forward_input  # noqa: E402


# Optional argv[1]: another .mlpackage to benchmark (e.g. the COCO17 one shipped in the app).
MODEL_PATH = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else COREML_MODEL_PATH
OUTPUT_JSON = ROOT / f"assets/coreml/{MODEL_PATH.stem}_benchmark_macos.json"
OUTPUT_CSV = ROOT / f"assets/coreml/{MODEL_PATH.stem}_benchmark_macos.csv"
WARMUP = 10
ITERATIONS = 100


def main():
    import coremltools as ct

    input_tensor = load_or_create_forward_input()
    load_start = time.perf_counter()
    model = ct.models.MLModel(str(MODEL_PATH), compute_units=ct.ComputeUnit.ALL)
    model_load_ms = elapsed_ms(load_start)

    first_start = time.perf_counter()
    model.predict({INPUT_NAME: input_tensor})
    first_prediction_ms = elapsed_ms(first_start)

    for _ in range(WARMUP):
        model.predict({INPUT_NAME: input_tensor})

    times = []
    for _ in range(ITERATIONS):
        start = time.perf_counter()
        model.predict({INPUT_NAME: input_tensor})
        times.append(elapsed_ms(start))

    stats = summarize_times(times)
    result = {
        "coreml_model_path": str(MODEL_PATH.relative_to(ROOT)),
        "input_shape": list(input_tensor.shape),
        "model_load_ms": float(model_load_ms),
        "first_prediction_ms": float(first_prediction_ms),
        "warmup_count": WARMUP,
        "iteration_count": ITERATIONS,
        "precision": model.user_defined_metadata.get("precision", "unknown"),
        "export_scope": model.user_defined_metadata.get("export_scope", "unknown"),
        "compute_units_requested": "ALL",
        "ane_verified": False,
        **stats,
    }
    OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_JSON.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    write_csv(result)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def elapsed_ms(start):
    return (time.perf_counter() - start) * 1000.0


def summarize_times(times):
    sorted_times = sorted(times)
    mean_ms = statistics.mean(times)
    return {
        "mean_ms": float(mean_ms),
        "median_ms": float(statistics.median(times)),
        "p90_ms": float(percentile(sorted_times, 90)),
        "p95_ms": float(percentile(sorted_times, 95)),
        "min_ms": float(min(times)),
        "max_ms": float(max(times)),
        "fps": float(1000.0 / mean_ms if mean_ms > 0 else 0.0),
    }


def percentile(sorted_values, value):
    index = (len(sorted_values) - 1) * value / 100.0
    lower = int(index)
    upper = min(lower + 1, len(sorted_values) - 1)
    weight = index - lower
    return sorted_values[lower] * (1.0 - weight) + sorted_values[upper] * weight


def write_csv(result):
    fieldnames = [
        "coreml_model_path",
        "input_shape",
        "model_load_ms",
        "first_prediction_ms",
        "warmup_count",
        "iteration_count",
        "mean_ms",
        "median_ms",
        "p90_ms",
        "p95_ms",
        "min_ms",
        "max_ms",
        "fps",
        "precision",
        "export_scope",
        "compute_units_requested",
        "ane_verified",
    ]
    row = dict(result)
    row["input_shape"] = json.dumps(row["input_shape"])
    with OUTPUT_CSV.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerow({key: row.get(key) for key in fieldnames})


if __name__ == "__main__":
    raise SystemExit(main())
