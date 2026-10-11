"""Compare two app perf logs (recording OFF vs ON) → markdown table.

The app writes one JSON line per second when launched with BPT_PERF_LOG=1
(Documents/workout_form_logs/perf_<exercise>_<time>.jsonl; WorkoutSessionBridge.swift):
{"t", "pose_fps", "dropped_frames", "thermal", "battery", "recording"}.
Procedure: docs/research/set_recording_perf.md.

    python scripts/compare_perf_logs.py OFF.jsonl ON.jsonl [--skip-seconds 10]
"""
import argparse
import json
import statistics
import sys

FPS_DROP_LIMIT = 0.10  # recording stays off (flag) when ON loses more than 10 % of OFF's pose FPS


def load(path, skip_seconds=0):
    with open(path, encoding="utf-8") as f:
        rows = [json.loads(line) for line in f if line.strip()]
    return rows[skip_seconds:]


def summarize(rows):
    fps = [r["pose_fps"] for r in rows]
    battery = [r["battery"] for r in rows if r.get("battery") is not None]
    hot = sum(r["thermal"] in ("serious", "critical") for r in rows)
    return {
        "seconds": len(rows),
        "fps_mean": statistics.fmean(fps) if fps else 0.0,
        "fps_p10": sorted(fps)[len(fps) // 10] if fps else 0.0,
        "dropped_per_s": sum(r["dropped_frames"] for r in rows) / max(len(rows), 1),
        "hot_pct": 100 * hot / max(len(rows), 1),
        "thermal_last": rows[-1]["thermal"] if rows else "-",
        "battery_used_pct": 100 * (battery[0] - battery[-1]) if len(battery) > 1 else None,
        "recording_pct": 100 * sum(bool(r.get("recording")) for r in rows) / max(len(rows), 1),
    }


def report(off, on):
    a, b = summarize(off), summarize(on)
    drop = (a["fps_mean"] - b["fps_mean"]) / a["fps_mean"] if a["fps_mean"] else 0.0
    def f(v, spec=".1f"):
        return "-" if v is None else format(v, spec) if isinstance(v, float) else str(v)
    lines = [
        "| 항목 | 녹화 OFF | 녹화 ON |",
        "| --- | --- | --- |",
        f"| 기록 시간(초) | {a['seconds']} | {b['seconds']} |",
        f"| 녹화 켜진 비율(%) | {f(a['recording_pct'])} | {f(b['recording_pct'])} |",
        f"| 포즈 FPS 평균 | {f(a['fps_mean'])} | {f(b['fps_mean'])} |",
        f"| 포즈 FPS 하위 10% | {f(a['fps_p10'])} | {f(b['fps_p10'])} |",
        f"| 버린 프레임/초 | {f(a['dropped_per_s'], '.2f')} | {f(b['dropped_per_s'], '.2f')} |",
        f"| 발열 serious 이상(%) | {f(a['hot_pct'])} | {f(b['hot_pct'])} |",
        f"| 마지막 발열 상태 | {a['thermal_last']} | {b['thermal_last']} |",
        f"| 배터리 사용(%p) | {f(a['battery_used_pct'])} | {f(b['battery_used_pct'])} |",
        "",
        f"FPS 감소: {100 * drop:.1f}% → "
        + ("녹화 기본 OFF 유지 (10% 초과)" if drop > FPS_DROP_LIMIT else "10% 이내: 녹화 기본 ON 가능"),
    ]
    return "\n".join(lines), drop


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("off")
    p.add_argument("on")
    p.add_argument("--skip-seconds", type=int, default=10, help="warm-up seconds dropped from each log")
    args = p.parse_args(argv)
    table, _ = report(load(args.off, args.skip_seconds), load(args.on, args.skip_seconds))
    print(table)


if __name__ == "__main__":
    sys.exit(main())
