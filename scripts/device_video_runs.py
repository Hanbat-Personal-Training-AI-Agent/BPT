"""Exercise3D-as-camera runs of the real Runner app on the iPhone (ai/lift-app video-as-camera mode).

  conda run -n bpt-eval python -I scripts/device_video_runs.py push   <clips_dir> [names...]
  conda run -n bpt-eval python -I scripts/device_video_runs.py run    <clips_dir> <out_dir> [--clips a,b,...] [--env K=V ...]
                                                                     [--tag TAG] [--loops N] [--timeout-pad S]
                                                                     [--reps-from-gt GT.json]
  conda run -n bpt-eval python -I scripts/device_video_runs.py pull   <out_dir>

push copies clips into the app's Documents/e3d_clips (never into git or the bundle). run launches com.bpt.liftdev once
per clip with BPT_CAMERA_VIDEO=e3d_clips/<clip>.mp4 + BPT_AUTOSTART_WORKOUT=<exercise> (+ --env extras), waits for the
run log's video_end (polling the device), pulls Documents/video_runs and workout_form_logs into <out_dir>, and writes
<out_dir>/manifest.json (clip sha256, env, app binary hashes, commands). Heavy: wrap in lockf -k /tmp/bpt-heavy.lock.
--no-pull (phone on Wi-Fi, where CoreDevice file copies stall): launch, wait the clip length + --wait-pad, go on; the
logs stay in the app's Documents/video_runs and are pulled later over USB (`pull`).
--reps-from-gt sets BPT_AUTOSTART_REPS to the clip's truth reps (Exercise3D pseudo labels), so Flutter's workout screen
reaches its rep target and sends endSet (3D tail flush, set-scope keys, onSetEnd) like a real set.
Exercise3D frames are never opened here; only the app's logs are read.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEVICE = os.environ.get("BPT_DEVICE_UDID", "00008150-0011745A26F8401C")
BUNDLE = os.environ.get("BPT_APP_BUNDLE", "com.bpt.liftdev")
EXERCISE = {"squat": "squat", "pushup": "pushup", "barbellrow": "barbell-row"}


def sh(cmd, check=True, timeout=300):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}")
    return r


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def devicectl(*args, timeout=300, retries=12):
    """devicectl with retries (the phone locks / drops off Wi-Fi)."""
    last = None
    for attempt in range(retries):
        r = sh(["xcrun", "devicectl", *args], check=False, timeout=timeout)
        if r.returncode == 0:
            return r
        last = r
        msg = (r.stdout + r.stderr)[-400:].replace("\n", " ")
        print(f"  devicectl retry {attempt + 1}: {msg}", flush=True)
        time.sleep(20)
    raise RuntimeError(f"devicectl failed: {' '.join(args)}\n{last.stdout[-1500:]}\n{last.stderr[-1500:]}")


def copy_to(local, remote):
    devicectl("device", "copy", "to", "--device", DEVICE, "--domain-type", "appDataContainer",
              "--domain-identifier", BUNDLE, "--source", str(local), "--destination", remote, timeout=600)


def copy_from(remote, local):
    r = sh(["xcrun", "devicectl", "device", "copy", "from", "--device", DEVICE, "--domain-type", "appDataContainer",
            "--domain-identifier", BUNDLE, "--source", remote, "--destination", str(local)], check=False, timeout=300)
    return r.returncode == 0


def push(a):
    clips = sorted(Path(a.clips_dir).glob("*.mp4"))
    if a.names:
        clips = [c for c in clips if c.stem in set(a.names)]
    for c in clips:
        print("push", c.name, flush=True)
        copy_to(c, f"Documents/e3d_clips/{c.name}")


def launch(env):
    devicectl("device", "process", "launch", "--device", DEVICE, "--terminate-existing",
              "--environment-variables", json.dumps(env), BUNDLE, timeout=120)


def pull_log(dest, tag):
    """The one run log of this launch (fixed name run_<tag>.jsonl)."""
    dest.mkdir(parents=True, exist_ok=True)
    target = dest / f"run_{tag}.jsonl"
    with tempfile.TemporaryDirectory() as tmp:
        if copy_from(f"Documents/video_runs/run_{tag}.jsonl", Path(tmp) / target.name):
            got = next((p for p in Path(tmp).rglob("*.jsonl")), None)
            if got:
                shutil.copy2(got, target)
    return target if target.exists() else None


def pull_runs(dest):
    """Every run log and perf log (end of a batch)."""
    dest.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for remote, pattern in (("Documents/video_runs", "*.jsonl"), ("Documents/workout_form_logs", "perf_*.jsonl")):
            if copy_from(remote, Path(tmp) / Path(remote).name):
                for f in (Path(tmp) / Path(remote).name).rglob(pattern):
                    shutil.copy2(f, dest / f.name)


def run(a):
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    clips = sorted(Path(a.clips_dir).glob("*.mp4"))
    if a.clips:
        want = a.clips.split(",")
        clips = [c for c in clips if c.stem in want]
    extra = dict(kv.split("=", 1) for kv in a.env)
    gt = json.load(open(a.reps_from_gt)) if a.reps_from_gt else None
    runs = []
    for c in clips:
        exercise = EXERCISE[c.stem.split("_")[0]]
        tag = f"{a.tag}_{c.stem}"
        env = {"BPT_CAMERA_VIDEO": f"e3d_clips/{c.name}", "BPT_AUTOSTART_WORKOUT": exercise, "BPT_PERF_LOG": "1",
               "BPT_RUN_TAG": tag, **({"BPT_CAMERA_VIDEO_LOOPS": str(a.loops)} if a.loops > 1 else {}),
               **({"BPT_AUTOSTART_REPS": str(gt[c.stem.rsplit("_", 1)[0]]["truth_reps"])} if gt else {}), **extra}
        frames = int(sh(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=nb_frames",
                         "-of", "csv=p=0", str(c)]).stdout.strip() or 0)
        expected = frames / 30 * a.loops
        print(f"== {tag} exercise={exercise} frames={frames} expected={expected:.0f}s", flush=True)
        started = time.time()
        launch(env)
        if a.no_pull:
            time.sleep(expected + a.wait_pad)
            runs.append({"clip": c.name, "clip_sha256": sha256(c), "exercise": exercise, "env": env, "frames": frames,
                         "log": f"run_{tag}.jsonl", "log_sha256": None, "ended": None,
                         "pulled": False, "wall_s": round(time.time() - started, 1)})
            print(f"   launched, waited {time.time() - started:.0f}s (log stays on the phone)", flush=True)
            continue
        deadline = started + expected + a.timeout_pad
        time.sleep(max(5, expected * 0.9))
        log, ended = None, False
        while time.time() < deadline:
            log = pull_log(out, tag)
            if log and any('"session_end"' in line for line in open(log)):
                ended = True
                break
            time.sleep(10)
        time.sleep(3)
        log = pull_log(out, tag) or log
        runs.append({"clip": c.name, "clip_sha256": sha256(c), "exercise": exercise, "env": env, "frames": frames,
                     "log": log.name if log else None, "log_sha256": sha256(log) if log else None,
                     "ended": ended, "wall_s": round(time.time() - started, 1)})
        print(f"   log={log.name if log else None} ended={ended}", flush=True)
    if a.pull_all:  # every run log + perf log on the phone: big over Wi-Fi
        pull_runs(out / "all_logs")
    manifest = {"created": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "argv": sys.argv, "device": DEVICE, "bundle": BUNDLE,
                "app": a.app_hashes and json.load(open(a.app_hashes)), "runs": runs,
                "git_commit": sh(["git", "rev-parse", "HEAD"]).stdout.strip()}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("push")
    p.add_argument("clips_dir")
    p.add_argument("names", nargs="*")
    r = sub.add_parser("run")
    r.add_argument("clips_dir")
    r.add_argument("out_dir")
    r.add_argument("--clips", default="")
    r.add_argument("--env", nargs="*", default=[])
    r.add_argument("--tag", default="v")
    r.add_argument("--loops", type=int, default=1)
    r.add_argument("--timeout-pad", type=float, default=90)
    r.add_argument("--app-hashes", default="")
    r.add_argument("--reps-from-gt", default="")
    r.add_argument("--pull-all", action="store_true")
    r.add_argument("--no-pull", action="store_true")
    r.add_argument("--wait-pad", type=float, default=12)
    q = sub.add_parser("pull")
    q.add_argument("out_dir")
    a = ap.parse_args()
    {"push": push, "run": run, "pull": lambda a: pull_runs(Path(a.out_dir))}[a.cmd](a)  # noqa: E501


if __name__ == "__main__":
    main()
