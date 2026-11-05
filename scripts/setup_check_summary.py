"""Setup-constraint phone check (ai/setup-constraint builds): per run, adaptive-constraint and setup counts from the
judged-frame lines, next to the run summary and the app's perf log.

  conda run -n bpt-eval python -I scripts/setup_check_summary.py <summary.json> <perf_dir> <run_dir> [<run_dir> ...]

summary.json: analyze_device_video_runs.py over the same run dirs. perf_dir: the pulled perf_<exercise>_<time>.jsonl files;
each run is matched to the perf log that starts closest after its launch (manifest launched_at).
"""
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from device_perf_summary import summarize  # noqa: E402


def perf_for(launched_at, exercise, perf_dir):
    t0 = datetime.strptime(launched_at[:19], "%Y-%m-%dT%H:%M:%S")
    best = None
    for p in Path(perf_dir).glob(f"perf_{exercise}_*.jsonl"):
        t = datetime.strptime(p.stem.split("_", 2)[2], "%Y%m%d_%H%M%S")
        dt = (t - t0).total_seconds()
        if 0 <= dt < 120 and (best is None or dt < best[0]):
            best = (dt, p)
    return best[1] if best else None


def main(summary_path, perf_dir, *run_dirs):
    summary = {r["log"]: r for r in json.load(open(summary_path)) if "error" not in r}
    print("| run | env | 렙 | (a) 3D 경고 | 보낸 키(렙/세트) | 판정 FPS | 드롭 | 도착→판정 p50/p95 | lift3d p50/p95 (perf) | adaptive_filled / invalid / events 프레임 | setup_ready | 발열 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for d in run_dirs:
        manifest = json.load(open(Path(d) / "manifest.json"))
        for run in manifest["runs"]:
            log = Path(d) / run["log"]
            if not log.exists():
                continue
            rows = [json.loads(line) for line in open(log) if line.strip()]
            judged = [r for r in rows if r["type"] == "judged"]
            filled = sum(1 for r in judged if r.get("adaptive_filled"))
            invalid = sum(1 for r in judged if r.get("adaptive_invalid"))
            events = sum(1 for r in judged if r.get("adaptive_events"))
            ready = sum(1 for r in rows if r["type"] == "setup_ready")
            s = summary.get(log.name)
            exercise = next((r["exercise"] for r in rows if r["type"] == "camera_started"), "?")
            perf = perf_for(run["launched_at"], exercise, perf_dir) if run.get("launched_at") else None
            ps = summarize(perf) if perf else {}
            lift = f'{ps["lift3d"]["p50"]} / {ps["lift3d"]["p95"]}' if "lift3d" in ps else "–"
            env = ",".join(f"{k}={v}" for k, v in run["env"].items() if k in ("BPT_ADAPTIVE_3D",)) or "기본"
            e = s["item1_e2e"] if s else None
            p = s["item3_posture"] if s else {}
            print(f'| {log.stem.removeprefix("run_")} | {env} | {s["reps"]["app_last_rep"] if s else "?"} | '
                  f'{p.get("a_native_fired_3d")} | {p.get("b_sent_rep_scope")} / {p.get("b_sent_set_scope")} | '
                  f'{e["judged_fps"] if e else "?"} | {e["dropped"] if e else "?"} | '
                  f'{e["arrival_to_judgement_ms"]["p50"] if e else "?"} / {e["arrival_to_judgement_ms"]["p95"] if e else "?"} | {lift} | '
                  f'{filled} / {invalid} / {events} (/{len(judged)}) | {ready} | {s["device"]["thermal_start_end"] if s else "?"} |')


if __name__ == "__main__":
    main(*sys.argv[1:])
