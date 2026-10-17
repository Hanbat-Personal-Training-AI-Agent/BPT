"""Temporal alignment of a cut clip against the original video, numeric (64x36 gray thumbnails, no viewing).
For clip frame k the expected original frame is a+k (a = s-90). Reports per-clip: clip frame count, expected count,
best offset d in [-6, 6] per frame (argmin MSE vs original a+k+d), the share of frames at each d, and frames
whose best match is ambiguous (min MSE not < 0.8 x second best). usage: clip_align.py <scriptdir> <labels> <rgb> <clips_dir> <ffmpeg> <out.json> [w..]"""
import json, subprocess, sys, pathlib
import numpy as np
sys.path.insert(0, sys.argv[1]); import eval_pushup_mmfit as e
labels, rgb, clips, ff, outp = sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4]), sys.argv[5], sys.argv[6]
only = set(sys.argv[7:]); W, H, D = 64, 36, 6
def frames(cmd):
    raw = subprocess.run(cmd + ["-vf_placeholder"], capture_output=True).stdout if False else subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, H, W).astype(np.float32)
res = {}
try: res = json.load(open(outp))
except Exception: pass
for cid, w, s, en, n in e.sets(labels):
    if w not in e.HELD_SESSIONS or (only and w not in only): continue
    clip = clips / f"{cid}.mp4"
    if not clip.exists(): continue
    a = max(0, s - 90); b = en + 45
    lo = max(0, a - D)
    orig = frames([ff, "-v", "error", "-i", f"{rgb}/{w}_rgb.mp4", "-vf", f"trim=start_frame={lo}:end_frame={b + D + 1},scale={W}:{H},format=gray", "-f", "rawvideo", "-"])
    cf = frames([ff, "-v", "error", "-i", str(clip), "-vf", f"scale={W}:{H},format=gray", "-f", "rawvideo", "-"])
    best, amb = [], 0
    for k in range(len(cf)):
        cand = [(float(((cf[k] - orig[a + k + d - lo]) ** 2).mean()), d) for d in range(-D, D + 1) if 0 <= a + k + d - lo < len(orig)]
        cand.sort(); best.append(cand[0][1])
        if len(cand) > 1 and not cand[0][0] < 0.8 * cand[1][0]: amb += 1
    best = np.array(best); vals, cnt = np.unique(best, return_counts=True)
    pts = subprocess.run([ff.replace("ffmpeg", "ffprobe"), "-v", "error", "-select_streams", "v", "-show_entries", "packet=pts", "-of", "csv=p=0", str(clip)], capture_output=True, text=True).stdout.split()
    res[cid] = dict(clip_frames=len(cf), expected=b - a + 1, offset_share={int(v): int(c) for v, c in zip(vals, cnt)}, ambiguous=amb,
                    median_offset=int(np.median(best)), first10=best[:10].tolist(), last10=best[-10:].tolist(), packets=len(pts))
    print(cid, res[cid]["clip_frames"], res[cid]["expected"], res[cid]["offset_share"], "amb", amb, flush=True)
    json.dump(res, open(outp, "w"), indent=1)
