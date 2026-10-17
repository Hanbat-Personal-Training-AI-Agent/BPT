"""Reference clips with the exact label frames: decode the original from frame 0 (no seeking) and keep frames
[s-90, e+45] by frame index (trim=start_frame/end_frame), re-encode x264 crf 10. Original is CFR 30 (pts = k*512/15360
checked per file), so frame k <-> t = k/30. usage: make_ref.py <scriptdir> <labels_root> <rgb_dir> <out_dir> <ffmpeg> [w..]"""
import subprocess, sys, pathlib
sys.path.insert(0, sys.argv[1]); import eval_pushup_mmfit as e
labels, rgb, out, ff = sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4]), sys.argv[5]
only = set(sys.argv[6:]); out.mkdir(parents=True, exist_ok=True)
for cid, w, s, en, n in e.sets(labels):
    if w not in e.HELD_SESSIONS or (only and w not in only): continue
    mp4 = out / f"{cid}.mp4"
    if mp4.exists(): continue
    a = max(0, s - round(e.PRE * e.FPS)); b = en + round(e.POST * e.FPS)
    tmp = mp4.with_suffix(".part.mp4")
    subprocess.run([ff, "-v", "error", "-y", "-i", f"{rgb}/{w}_rgb.mp4", "-vf", f"trim=start_frame={a}:end_frame={b},setpts=PTS-STARTPTS",
                    "-an", "-c:v", "libx264", "-crf", "10", "-preset", "medium", "-pix_fmt", "yuv420p", "-r", "30", str(tmp)], check=True)
    tmp.rename(mp4); print("ref", cid, a, b, flush=True)
