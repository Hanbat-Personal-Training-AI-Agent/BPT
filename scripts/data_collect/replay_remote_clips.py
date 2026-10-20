"""Run the app's pose path (pose-replay, RTMPose-m Halpe26 default (D-M-03), crop input, ready-pose off, no 3D) on clips
stored on Home, one clip at a time: copy a batch -> replay -> keep the JSON + per-frame side-view ratio summary -> delete
the video and the keypoint CSV (Mac disk is tight; data never leaves scratch).

usage: python3 -I replay_remote_clips.py <remote_dir> <names.txt> <out_dir> [batch=15]
  names.txt: clip stems, e.g. subject_001_squat_bad_side; exercise from the name (squat / push_up / back->row,
  or a 'stem<TAB>exercise' line). Env: POSE_REPLAY (binary), BPT_HEAVY (lock wrapper), HOST (default Home),
  POSE_MODELS (pose-replay --model names, comma-separated, default mhalpe26; each batch is copied once and run per model).
"""
import json, os, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from eval_side_videos import shoulder_ratios, pct  # noqa: E402

REPLAY = os.environ["POSE_REPLAY"]
HEAVY = os.environ.get("BPT_HEAVY")
HOST = os.environ.get("HOST", "Home")
FILE_EX = {"squat": "squat", "pushup": "pushup", "row": "barbell_row"}
MODELS = os.environ.get("POSE_MODELS", "mhalpe26").split(",")


def exercise_of(stem):
    return "pushup" if "push_up" in stem or "pushup" in stem else "row" if "_back_" in stem or "row" in stem else "squat"


def main(remote, names, out, batch=15):
    """Clips go in batches of one exercise: one pose-replay call (one lock hold, one model load) per batch."""
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    todo = []
    for line in open(names):
        if line.strip():
            stem, _, ex = line.strip().partition("\t")
            ex = ex or exercise_of(stem)
            if not all((out / f"{stem}_{FILE_EX[ex]}_{m}.json").exists() for m in MODELS):
                todo.append((stem, ex))
    for ex in FILE_EX:
        stems = [s for s, e in todo if e == ex]
        for i in range(0, len(stems), int(batch)):
            chunk = stems[i:i + int(batch)]
            mp4s = [out / f"{s}.mp4" for s in chunk]
            subprocess.run(["scp", "-q", *[f"{HOST}:{remote}/{s}.mp4" for s in chunk], str(out)], check=True)
            try:
                for model in MODELS:
                    subprocess.run([*([HEAVY] if HEAVY else []), REPLAY, "--exercise", ex, "--model", model, "--motion3d", "none",
                                    "--ready-pose", "off", "--output-dir", str(out), *map(str, mp4s)], check=True, stdout=subprocess.DEVNULL)
            finally:
                for m in mp4s:
                    m.unlink(missing_ok=True)
            for s in chunk:
                for model in MODELS:
                    js = out / f"{s}_{FILE_EX[ex]}_{model}.json"
                    csv_path = js.with_suffix(".csv")
                    r = shoulder_ratios(csv_path)
                    json.dump({"n": len(r), "p10": pct(r, .1), "p50": pct(r, .5), "p90": pct(r, .9),
                               "side_frac": sum(x <= 0.66 for x in r) / len(r) if r else None},
                              open(out / (f"{s}_ratio.json" if model == "mcoco17" else f"{s}_{model}_ratio.json"), "w"))
                    csv_path.unlink()
                    print(s, model, json.load(open(js))["session"]["rep_count"], flush=True)


if __name__ == "__main__":
    main(*sys.argv[1:])
