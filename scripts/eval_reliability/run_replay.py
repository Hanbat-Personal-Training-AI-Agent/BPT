"""Run pose-replay on a list of videos for both m models, keep every output (JSON, keypoint CSV, _crops.csv), write a
manifest, push the run dir to Home ~/bpt-runs/eval-reliability/<run_id>/. Videos are copied from Home in batches
(or used in place when local) and the Mac copies are deleted after the batch. Heavy work under lockf /tmp/bpt-heavy.lock.

usage: python3 -I run_replay.py <run_id> <list.tsv> [extra pose-replay args...]
  list.tsv lines: <video path (Home:path or local)>\t<exercise squat|pushup|row>[\t<crops csv for --crops-in, with {model}>]
env: REPLAY (binary), MODELS (default "mcoco17,halpe26"), RUNROOT (Mac scratch root), BATCH (default 12)
"""
import hashlib, json, os, pathlib, shlex, subprocess, sys, time

ROOT = pathlib.Path(os.environ.get("RUNROOT", "/private/tmp/claude-501/-Users-6-month-github-06-month-hanbat-repositories-BPT/d083b446-4e06-45ed-8204-8c6e9f22bd1c/scratchpad/evalrel/runs"))
REPLAY = os.environ.get("REPLAY", "/private/tmp/bpt-swiftpm-evalrel/release/pose-replay")
MODELS = {"mcoco17": ["--model", "mcoco17", "--model-path", os.path.expanduser("~/bpt-models/rtmpose_m_forward.mlpackage")],
          "halpe26": ["--model", "halpe26", "--model-path", os.path.expanduser("~/bpt-models/rtmpose_m_halpe26_forward.mlpackage")]}
REPO = "/Users/6_month/github/06-month/hanbat/repositories/BPT/.claude/worktrees/ai-eval-reliability"
FILE_EX = {"squat": "squat", "pushup": "pushup", "row": "barbell_row"}


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()


def pkg_sha(d):
    files = sorted(str(p.relative_to(d)) for p in pathlib.Path(d).rglob("*") if p.is_file())
    per = {f: sha(pathlib.Path(d) / f) for f in files}
    return {"files": per, "combined": hashlib.sha256(json.dumps(per, sort_keys=True).encode()).hexdigest()}


def main(run_id, listfile, *extra):
    out = ROOT / run_id; out.mkdir(parents=True, exist_ok=True); (out / "inputs").mkdir(exist_ok=True)
    models = os.environ.get("MODELS", "mcoco17,halpe26").split(",")
    items = [l.rstrip("\n").split("\t") for l in open(listfile) if l.strip()]
    man_p = out / "manifest.json"
    man = json.load(open(man_p)) if man_p.exists() else {
        "run_id": run_id, "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "argv": [sys.executable, *sys.argv],
        "git_commit": subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
        "git_dirty": subprocess.run(["git", "-C", REPO, "status", "--porcelain"], capture_output=True, text=True).stdout.strip() != "",
        "pose_replay": {"path": REPLAY, "sha256": sha(REPLAY)}, "runner_sha256": sha(__file__),
        "models": {m: {"args": MODELS[m], "mlpackage": pkg_sha(MODELS[m][3])} for m in models},
        "extra_args": list(extra), "inputs": {}, "commands": []}
    batch = int(os.environ.get("BATCH", "12"))
    groups = {}
    for it in items:
        groups.setdefault((it[1], it[2] if len(it) > 2 else ""), []).append(it[0])
    for (ex, crops), vids in groups.items():
        for i in range(0, len(vids), batch):
            chunk = vids[i:i + batch]
            stems = [pathlib.Path(v.split(":", 1)[-1]).stem for v in chunk]
            if all((out / f"{s}_{FILE_EX[ex]}_{m}.json").exists() for s in stems for m in models): continue
            remote = [v for v in chunk if v.startswith("Home:")]
            if remote: subprocess.run(["scp", "-q", *remote, str(out / "inputs")], check=True)
            local = [str(out / "inputs" / pathlib.Path(v[5:]).name) if v.startswith("Home:") else v for v in chunk]
            for v, l in zip(chunk, local): man["inputs"][pathlib.Path(l).stem] = {"source": v, "sha256": sha(l)}
            try:
                for m in models:
                    if crops:  # --crops-in takes one file: one call per video
                        for l, s in zip(local, stems):
                            cmd = ["lockf", "-k", "/tmp/bpt-heavy.lock", REPLAY, "--exercise", ex, *MODELS[m], "--motion3d", "none",
                                   "--ready-pose", "off", *extra, "--crops-in", crops.format(model=m, stem=s), "--output-dir", str(out), l]
                            man["commands"].append(shlex.join(cmd)); subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
                    else:
                        cmd = ["lockf", "-k", "/tmp/bpt-heavy.lock", REPLAY, "--exercise", ex, *MODELS[m], "--motion3d", "none",
                               "--ready-pose", "off", *extra, "--output-dir", str(out), *local]
                        man["commands"].append(shlex.join(cmd)); subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
            finally:
                for l, v in zip(local, chunk):
                    if v.startswith("Home:"): pathlib.Path(l).unlink(missing_ok=True)
            json.dump(man, open(man_p, "w"), indent=1)
            for s in stems:
                print(s, *[json.load(open(out / f"{s}_{FILE_EX[ex]}_{m}.json"))["session"]["rep_count"] for m in models], flush=True)
    man["outputs"] = {p.name: sha(p) for p in sorted(out.glob("*")) if p.is_file() and p.name != "manifest.json"}
    json.dump(man, open(man_p, "w"), indent=1)
    subprocess.run(["ssh", "Home", f"mkdir -p ~/bpt-runs/eval-reliability/{run_id}"], check=True)
    subprocess.run(["rsync", "-a", "--exclude", "inputs", f"{out}/", f"Home:bpt-runs/eval-reliability/{run_id}/"], check=True)
    print("RUN_DONE", run_id, flush=True)


if __name__ == "__main__":
    main(*sys.argv[1:])
