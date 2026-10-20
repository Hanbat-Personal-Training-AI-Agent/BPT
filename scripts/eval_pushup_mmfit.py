"""Held-out push-up rep-count eval on public MM-Fit (CC BY 4.0) side-view video.

Data (not in repo): labels from https://s3.eu-west-2.amazonaws.com/vradu.uk/mm-fit.zip
(mm-fit/wXX/wXX_labels.csv: start_frame,end_frame,reps,exercise @30 fps), video from
https://zenodo.org/records/7672767 (wXX_rgb.mp4). Clips are cut per push-up set with
PRE s before start_frame and POST s after end_frame (see cut()).

Labels without the 1.7 GB zip: python3 -I scripts/fetch_zip_members.py <zip url> <outdir> "labels[.]csv$"
usage: python3 -I scripts/eval_pushup_mmfit.py <labels_root> <clips_dir> <out_dir> <results.json> [--cut] [--run]
Labels are set-level counts only, so missed/extra come from |counted - truth|.
acc = sum(truth - missed) / sum(truth + extra)  (project rep metric).
"""
import csv, json, os, pathlib, subprocess, sys

PRE, POST, FPS = 3.0, 1.5, 30
# D-T3-09 person split (fixed before any fix was measured): sessions of people never in the authors' train split.
HELD_SESSIONS = {"w00", "w05", "w12", "w13", "w19", "w20"}
ZENODO = "https://zenodo.org/api/records/7672767/files/{w}_rgb.mp4/content"
HEAVY = os.environ.get("BPT_HEAVY", "")  # optional lock wrapper (scratchpad/shared/heavy.sh)
MODEL = os.environ.get("POSE_MODEL", "mhalpe26")  # pose-replay --model (app workout default, D-M-03)
REPLAY = os.environ.get("POSE_REPLAY", "/private/tmp/bpt-swiftpm-pushup-heldout/release/pose-replay")


def sets(labels_root):
    for lab in sorted(pathlib.Path(labels_root).glob("*/*_labels.csv")):
        w = lab.name.split("_")[0]
        rows = [r for r in csv.reader(open(lab)) if r and r[3] == "pushups"]
        for k, (s, e, n, _) in enumerate(rows, 1):
            yield f"{w}_s{k}", w, int(s), int(e), int(n)


def cut(clip_id, w, s, e, out):
    ss = max(0.0, s / FPS - PRE)
    for attempt in range(4):  # Zenodo sometimes drops ranged streams early
        tmp = out.with_suffix(".part.mp4")
        r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-reconnect", "1", "-reconnect_on_network_error", "1",
                            "-reconnect_delay_max", "5", "-ss", str(ss), "-i", ZENODO.format(w=w),
                    "-t", str((e - s) / FPS + PRE + POST), "-an", "-c:v", "libx264", "-crf", "23",
                    "-preset", "veryfast", "-pix_fmt", "yuv420p", str(tmp)])
        if r.returncode == 0:
            return tmp.rename(out)
    raise RuntimeError(f"cut failed: {clip_id}")


def score(rows):
    t = sum(r["truth"] for r in rows)
    m = sum(r["missed"] for r in rows)
    x = sum(r["extra"] for r in rows)
    return {"clips": len(rows), "truth": t, "missed": m, "extra": x,
            "acc": round((t - m) / (t + x), 4) if t + x else None,
            "exact": sum(r["counted"] == r["truth"] for r in rows)}


def main(labels_root, clips, outdir, results, *flags):
    clips, outdir = pathlib.Path(clips), pathlib.Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    rows = []
    for cid, w, s, e, n in sets(labels_root):
        mp4 = clips / f"{cid}.mp4"
        if "--cut" in flags and not mp4.exists():
            cut(cid, w, s, e, mp4)
        js = outdir / f"{cid}_pushup_{MODEL}.json"
        if "--run" in flags and not js.exists():
            subprocess.run([*([HEAVY] if HEAVY else []), REPLAY, "--exercise", "pushup", "--model", MODEL, "--motion3d", "none",
                            "--output-dir", str(outdir), str(mp4)], check=True,
                           env={"BPT_LOCK": os.environ.get("BPT_LOCK", "heavy"), "PATH": "/usr/bin:/bin"},
                           stdout=subprocess.DEVNULL)
        sess = json.load(open(js))["session"]
        c = sess["rep_count"]
        rows.append({"clip": cid, "workout": w, "split": "held" if w in HELD_SESSIONS else "tune", "label_start_frame": s, "label_end_frame": e,
                     "clip_offset_frames": round(min(PRE * FPS, s)),
                     "truth": n, "counted": c, "missed": max(0, n - c), "extra": max(0, c - n),
                     "rep_end_frames": sess["rep_end_frames"]})
    by_split = {sp: score([r for r in rows if r["split"] == sp]) for sp in ("tune", "held")}
    json.dump({"rows": rows, "total": score(rows), **by_split}, open(results, "w"), indent=1)
    print(json.dumps({"total": score(rows), **by_split}))


if __name__ == "__main__":
    assert score([{"truth": 10, "counted": 9, "missed": 1, "extra": 0},
                  {"truth": 10, "counted": 11, "missed": 0, "extra": 1}])["acc"] == round(19 / 21, 4)
    main(*sys.argv[1:])
