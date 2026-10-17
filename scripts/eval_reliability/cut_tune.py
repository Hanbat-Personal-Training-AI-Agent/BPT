"""Cut the 47 D-T3-09 tuning push-up clips with eval_pushup_mmfit.cut() verbatim (Zenodo HTTP, Home ffmpeg 9.0.2).
usage: cut_tune.py <scriptdir> <labels_root> <out_dir>"""
import sys, pathlib, time
sys.path.insert(0, sys.argv[1]); import eval_pushup_mmfit as e
out = pathlib.Path(sys.argv[3]); out.mkdir(parents=True, exist_ok=True)
for cid, w, s, en, n in e.sets(sys.argv[2]):
    if w in e.HELD_SESSIONS: continue
    mp4 = out / f"{cid}.mp4"
    if not mp4.exists():
        t = time.time(); e.cut(cid, w, s, en, mp4); print("cut", cid, round(time.time() - t, 1), flush=True)
