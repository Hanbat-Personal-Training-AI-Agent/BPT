"""Before/after table of device video-as-camera runs (summaries from analyze_device_video_runs.py), per clip.

  conda run -n bpt-eval python -I scripts/compare_device_runs.py <before.json>[,<more.json>] <after.json>[,<more.json>]

Every run of a clip is listed (run-to-run spread is the noise floor), then the per-clip mean of each side.
"""
import json
import statistics
import sys
from collections import defaultdict

FIELDS = (("처리 FPS", lambda e, d: e["processed_fps"]), ("드롭", lambda e, d: e["dropped"]),
          ("도착→판정 p50", lambda e, d: e["arrival_to_judgement_ms"]["p50"]),
          ("도착→판정 p95", lambda e, d: e["arrival_to_judgement_ms"]["p95"]),
          ("도착→Flutter p50", lambda e, d: e["arrival_to_flutter_reply_ms_onPoseUpdate"]["p50"]),
          ("도착→Flutter p95", lambda e, d: e["arrival_to_flutter_reply_ms_onPoseUpdate"]["p95"]),
          ("CPU p50 %", lambda e, d: d["cpu_pct_p50"]))


def load(spec):
    rows = []
    for path in spec.split(","):
        rows += [r for r in json.load(open(path)) if "error" not in r]
    return rows


def main(before, after):
    sides = {"before": load(before), "after": load(after)}
    clips = sorted({r["clip"] for rs in sides.values() for r in rs})
    print("| clip | 빌드 | 실행 | " + " | ".join(f for f, _ in FIELDS) + " |")
    print("|---|---|---|" + "---|" * len(FIELDS))
    for clip in clips:
        for side, rs in sides.items():
            runs = [r for r in rs if r["clip"] == clip]
            vals = defaultdict(list)
            for r in runs:
                cells = [get(r["item1_e2e"], r["device"]) for _, get in FIELDS]
                for (f, _), v in zip(FIELDS, cells):
                    vals[f].append(v)
                print(f'| {clip.removesuffix(".mp4")} | {side} | {r["log"]} | ' + " | ".join(str(v) for v in cells) + " |")
            if len(runs) > 1:
                print(f'| {clip.removesuffix(".mp4")} | {side} | 평균({len(runs)}) | '
                      + " | ".join(str(round(statistics.mean(vals[f]), 1)) for f, _ in FIELDS) + " |")


if __name__ == "__main__":
    main(*sys.argv[1:])
