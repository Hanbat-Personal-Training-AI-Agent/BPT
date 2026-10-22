"""Collect and summarize the user's own trial sessions (real camera, trial build with logs on: ai/trial-*).

  conda run -n bpt-eval python -I scripts/trial_logs.py pull <out_dir> [--since YYYYMMDD_HHMMSS]
  conda run -n bpt-eval python -I scripts/trial_logs.py summary <out_dir>

pull copies the app's Documents/workout_form_logs (form logs <exercise>_<time>.jsonl and perf logs
perf_<exercise>_<time>.jsonl) from the phone with devicectl; --since keeps only sessions at or after that time.
summary prints one row per session: reps, judged-from (3d / 3d_unavailable / 2d), 3D state frames, warnings per key,
side view; and from the matching perf log (same exercise, start within 120 s): FPS, drops, input→judgement p50/p95,
lift3d, thermal and battery start→end. No video or image is ever stored or read here.
"""
import argparse
import json
import subprocess
import sys
import tempfile
from collections import Counter
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from device_perf_summary import summarize  # noqa: E402

DEVICE = "00008150-0011745A26F8401C"
BUNDLE = "com.bpt.liftdev"


def pull(out, since):
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        r = subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", DEVICE, "--domain-type",
                            "appDataContainer", "--domain-identifier", BUNDLE, "--source", "Documents/workout_form_logs",
                            "--destination", str(Path(tmp) / "logs")], capture_output=True, text=True, timeout=900)
        if r.returncode != 0:
            sys.exit(r.stderr[-800:])
        n = 0
        for p in Path(tmp, "logs").rglob("*.jsonl"):
            if since and p.stem.rsplit("_", 2)[-2] + "_" + p.stem.rsplit("_", 1)[-1] < since:
                continue
            (out / p.name).write_bytes(p.read_bytes())
            n += 1
    print(f"pulled {n} files into {out}")


def stamp(path):
    return datetime.strptime("_".join(path.stem.rsplit("_", 2)[-2:]), "%Y%m%d_%H%M%S")


def summary(out):
    perf = sorted(out.glob("perf_*.jsonl"))
    print("| 세션 | 운동 | 렙 | 판정 원천 | 3D 프레임(불량) | 경고(렙 수) | 옆면 | FPS | 드롭 | 입력→판정 p50/p95 | lift3d p50 | 발열 | 배터리 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for p in sorted(out.glob("*.jsonl")):
        if p.name.startswith("perf_"):
            continue
        rows = [json.loads(line) for line in open(p) if line.strip()]
        reps = [r for r in rows if not r.get("session")]
        sess = next((r for r in rows if r.get("session")), {})
        src = Counter(r.get("form_source") for r in reps)
        warn = Counter(k for r in reps for k in (r.get("warnings") or []))
        ex = sess.get("exercise") or p.stem.rsplit("_", 2)[0]
        t0 = stamp(p)
        match = [q for q in perf if q.stem.split("_", 2)[1].lower() == ex.lower() and 0 <= (stamp(q) - t0).total_seconds() < 120]
        ps = summarize(match[0]) if match else {}
        lat = ps.get("latency_input_to_judgement", {})
        battery = None
        if match:
            lines = [json.loads(line) for line in open(match[0]) if line.strip()]
            bats = [x.get("battery") for x in lines if x.get("battery") is not None]
            battery = f"{bats[0]}→{bats[-1]}" if bats else None
        print(f'| {p.stem} | {ex} | {sess.get("reps", len(reps))} | {dict(src)} | {sess.get("frames_3d")} ({sess.get("bad_3d_frames")}) | '
              f'{dict(warn) or "–"} | {sess.get("side_view")} | {ps.get("pose_fps", "–")} | {ps.get("dropped", "–")} | '
              f'{lat.get("p50", "–")}/{lat.get("p95", "–")} | {(ps.get("lift3d") or {}).get("p50", "–")} | {ps.get("thermal", "–")} | {battery or "–"} |')


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("pull")
    a.add_argument("out")
    a.add_argument("--since", default="")
    b = sub.add_parser("summary")
    b.add_argument("out")
    args = ap.parse_args()
    if args.cmd == "pull":
        pull(Path(args.out), args.since)
    else:
        summary(Path(args.out))


if __name__ == "__main__":
    main()
