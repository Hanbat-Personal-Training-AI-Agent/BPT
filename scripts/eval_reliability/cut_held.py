"""Cut the 18 D-T3-09 held-out push-up clips with eval_pushup_mmfit.cut() verbatim (script copy from git 1a8a3c4 = HEAD).
usage: cut_held.py <eval_pushup_mmfit.py dir> <labels_root> <out_dir> [<local rgb dir>]
With a local rgb dir: the ZENODO url template is replaced by that file and the three HTTP-only -reconnect* options
(rejected by ffmpeg for local files) are dropped; every other ffmpeg argument is unchanged."""
import sys, pathlib, time, subprocess
sys.path.insert(0, sys.argv[1]); import eval_pushup_mmfit as e
out = pathlib.Path(sys.argv[3]); out.mkdir(parents=True, exist_ok=True)
if len(sys.argv) > 4:
    e.ZENODO = sys.argv[4] + "/{w}_rgb.mp4"
    _run = subprocess.run
    def run(cmd, *a, **k):
        c, i = [], 0
        while i < len(cmd):
            if cmd[i] in ("-reconnect", "-reconnect_on_network_error", "-reconnect_delay_max"): i += 2; continue
            c.append(cmd[i]); i += 1
        return _run(c, *a, **k)
    e.subprocess.run = run
for cid, w, s, en, n in e.sets(sys.argv[2]):
    if w not in e.HELD_SESSIONS: continue
    mp4 = out / f"{cid}.mp4"
    if not mp4.exists():
        t = time.time(); e.cut(cid, w, s, en, mp4); print("cut", cid, round(time.time() - t, 1), flush=True)
