"""Experiment B (full app pipeline after 2D): the same app 2D keypoint CSVs replayed through pose-replay with
2D-only judging vs the lift-app 3D path (MotionAGFormerLive + constraints + 3D posture judgement), plus 3D variants.

  conda run -n bpt-eval python -I scripts/lift_app_e2e.py run <in_dir> <out_dir> [--modes 2d,3d,3d_raw,3d_c2] [--xs PATH]
  conda run -n bpt-eval python -I scripts/lift_app_e2e.py summary <out_dir> <out.json>

<in_dir> holds pose-replay outputs `<stem>_<exercise>_mcoco17.{csv,json}` (the JSON gives the image size). Each mode
replays every CSV with --keypoints-dir (no RTMPose, so 2D is identical across modes) into <out_dir>/<mode>/.
Modes: 2d = --motion3d none (old judging); 3d = XS lookahead 5, constraints on, posture from 3D; 3d_raw = constraints
off; 3d_c2 = cadence 2. Heavy: wrap in `lockf -k /tmp/bpt-heavy.lock`. Writes <out_dir>/manifest.json (sha256 + argv).
summary: per mode and exercise, rep counts (must match 2d: counting is 2D), 3D frame states, reps by form_source,
warnings_2d vs warnings_3d agreement, fired-key counts.
"""
import argparse
import hashlib
import json
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXERCISES = {"squat": "squat", "pushup": "pushup", "barbell_row": "row"}
MODES = {
    "2d": ["--motion3d", "none"],
    "3d": [],
    "3d_raw": ["--constraints", "off"],
    "3d_c2": ["--cadence", "2"],
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def tree_sha(path):
    p = Path(path)
    return {str(f.relative_to(p)): sha256(f) for f in sorted(p.rglob("*")) if f.is_file()} if p.is_dir() else sha256(p)


def run(a):
    binary = ROOT / "ios/CalibrationEngineKit/.build/release/pose-replay"
    subprocess.run(["swift", "build", "-c", "release", "--product", "pose-replay", "--package-path",
                    str(ROOT / "ios/CalibrationEngineKit")], check=True)
    in_dir, out_dir = Path(a.in_dir), Path(a.out_dir)
    stems = defaultdict(list)
    for csv in sorted(in_dir.glob("*_mcoco17.csv")):
        if csv.name.endswith("_3d.csv") or csv.name.endswith("_crops.csv"):
            continue
        for ex in EXERCISES:
            suffix = f"_{ex}_mcoco17.csv"
            if csv.name.endswith(suffix):
                stems[ex].append(csv.name[: -len(suffix)])
    commands = []
    for mode in a.modes.split(","):
        (out_dir / mode).mkdir(parents=True, exist_ok=True)
        for ex, names in stems.items():
            cmd = [str(binary), "--exercise", EXERCISES[ex], "--model", "mcoco17", "--keypoints-dir", str(in_dir),
                   "--output-dir", str(out_dir / mode)] + MODES[mode]
            if mode != "2d":
                cmd += ["--motion3d", a.xs]
            cmd += [f"{n}.mp4" for n in names]
            t0 = time.time()
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
            commands.append({"mode": mode, "exercise": ex, "clips": len(names), "seconds": round(time.time() - t0, 1),
                             "argv": cmd[:12] + ["..."]})
            print(mode, ex, len(names), f"{time.time() - t0:.0f}s", flush=True)
    git = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    dirty = bool(subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain", "--untracked-files=no"],
                                capture_output=True, text=True).stdout.strip())
    manifest = {
        "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "argv": sys.argv, "git_commit": git, "git_dirty": dirty,
        "pose_replay_sha256": sha256(binary), "xs_mlpackage": {"path": a.xs, "sha256": tree_sha(a.xs)},
        "inputs": {"dir": str(in_dir), "csv_sha256": {p.name: sha256(p) for p in sorted(in_dir.glob("*_mcoco17.csv"))}},
        "commands": commands,
        "outputs": {mode: {p.name: sha256(p) for p in sorted((out_dir / mode).glob("*.json"))} for mode in a.modes.split(",")},
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1))


def summary(a):
    out_dir = Path(a.out_dir)
    base = {p.name: json.load(open(p)) for p in (out_dir / "2d").glob("*.json") if p.name != "manifest.json"}
    result = {}
    for mode_dir in sorted(p for p in out_dir.iterdir() if p.is_dir()):
        per_ex = defaultdict(lambda: {"clips": 0, "reps": 0, "rep_count_differs_from_2d": 0, "states_3d": Counter(),
                                      "form_source": Counter(), "fired_3d": Counter(), "fired_2d": Counter(),
                                      "reps_both": 0, "reps_same_keys": 0, "ms_3d_per_frame_mac": []})
        for p in sorted(mode_dir.glob("*.json")):
            j = json.load(open(p))
            s = per_ex[j["exercise"]]
            s["clips"] += 1
            s["reps"] += j["session"]["rep_count"]
            if p.name in base and base[p.name]["session"]["rep_count"] != j["session"]["rep_count"]:
                s["rep_count_differs_from_2d"] += 1
            s["states_3d"].update(j["session"].get("states_3d", {}))
            if j.get("ms_3d_per_frame_mac"):
                s["ms_3d_per_frame_mac"].append(j["ms_3d_per_frame_mac"])
            for r in j["reps"]:
                s["form_source"][r.get("form_source", "2d")] += 1
                w2 = r.get("warnings_2d", r["warnings"])
                s["fired_2d"].update(w2)
                w3 = r.get("warnings_3d")
                if w3 is not None:
                    s["fired_3d"].update(w3)
                    s["reps_both"] += 1
                    s["reps_same_keys"] += set(w3) == set(w2)
        result[mode_dir.name] = {ex: {k: (dict(v) if isinstance(v, Counter) else
                                          (round(sum(v) / len(v), 3) if k == "ms_3d_per_frame_mac" and v else v))
                                      for k, v in s.items()} for ex, s in per_ex.items()}
    Path(a.out).write_text(json.dumps(result, indent=1, ensure_ascii=False))
    print(json.dumps(result, indent=1, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("in_dir")
    r.add_argument("out_dir")
    r.add_argument("--modes", default="2d,3d,3d_raw,3d_c2")
    r.add_argument("--xs", default=str(ROOT / "assets/coreml/motionagformer_xs.mlpackage"))
    s = sub.add_parser("summary")
    s.add_argument("out_dir")
    s.add_argument("out")
    a = ap.parse_args()
    run(a) if a.cmd == "run" else summary(a)


if __name__ == "__main__":
    main()
