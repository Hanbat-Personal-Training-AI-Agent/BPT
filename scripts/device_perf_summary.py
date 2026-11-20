"""Summary of the app's per-second perf logs (BPT_PERF_LOG=1, Documents/workout_form_logs/perf_<exercise>_<time>.jsonl).

  conda run -n bpt-eval python -I scripts/device_perf_summary.py <perf.jsonl> [...]

Each line holds one second: per-stage {n, p50, p95, max} ms, pose_fps, judged_fps, dropped_frames, thermal. Whole-run
values here: p50 = n-weighted median of the per-second p50s, p95 = n-weighted median of the per-second p95s (the
per-frame samples are not kept, so these are approximations), max = max over seconds. Seconds with no processed frame
(before the clip starts, after it ends) are left out.
"""
import json
import sys
from collections import Counter
from pathlib import Path

STAGES = ("lift3d", "latency_input_to_judgement", "pose2d_hands", "evaluate")


def wmedian(pairs):
    pairs = sorted(pairs)
    total = sum(w for _, w in pairs)
    acc = 0
    for v, w in pairs:
        acc += w
        if acc >= total / 2:
            return round(v, 2)
    return None


def summarize(path):
    rows = [json.loads(line) for line in open(path) if line.strip()]
    rows = [r for r in rows if r.get("pose_fps", 0) > 0]
    out = {"log": Path(path).name, "seconds": len(rows),
           "pose_fps": round(sum(r["pose_fps"] for r in rows) / max(len(rows), 1), 2),
           "judged_fps": round(sum(r.get("judged_fps", 0) for r in rows) / max(len(rows), 1), 2),
           "dropped": sum(r.get("dropped_frames", 0) for r in rows),
           "thermal": dict(Counter(r.get("thermal") for r in rows))}
    for s in STAGES:
        st = [r[s] for r in rows if isinstance(r.get(s), dict) and r[s].get("n")]
        if st:
            out[s] = {"n": sum(x["n"] for x in st), "p50": wmedian([(x["p50"], x["n"]) for x in st]),
                      "p95": wmedian([(x["p95"], x["n"]) for x in st]), "max": max(x["max"] for x in st)}
    return out


def main(*paths):
    res = [summarize(p) for p in paths]
    print("| perf log | 초 | pose fps | judged fps | 드롭 | lift3d p50/p95/max ms | 입력→판정 p50/p95/max ms | 2D+손 p50/p95 ms | 발열 |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in res:
        f = lambda s: (f'{r[s]["p50"]} / {r[s]["p95"]} / {r[s]["max"]}' if s in r else "–")  # noqa: E731
        hands = f'{r["pose2d_hands"]["p50"]} / {r["pose2d_hands"]["p95"]}' if "pose2d_hands" in r else "–"
        print(f'| {r["log"]} | {r["seconds"]} | {r["pose_fps"]} | {r["judged_fps"]} | {r["dropped"]} | {f("lift3d")} | '
              f'{f("latency_input_to_judgement")} | {hands} | {r["thermal"]} |')
    return res


if __name__ == "__main__":
    main(*sys.argv[1:])
