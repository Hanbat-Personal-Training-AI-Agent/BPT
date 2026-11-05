"""GVHMR speed / VRAM per stage (gvhmr_runner.run) on 30 s and 60 s clips, locally or on Modal.

Clips: our CC BY test clip looped to the length (not Fit3D — Fit3D never leaves the local machine).
  python bench_gvhmr.py make --src SIDE_SQUAT.mp4 --out-dir DIR           # DIR/bench_30s.mp4, DIR/bench_60s.mp4
  python bench_gvhmr.py run --videos DIR/bench_30s.mp4 DIR/bench_60s.mp4 --work DIR --out bench.json [--half] [--repeat 2]
On Modal the same `run` is called inside the L4 function (deep_analysis_modal.py::bench); cold start is
measured there from the client side.
"""
import argparse, json, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))


def make(src, out_dir, seconds=(30, 60), fps=30):
    import av, cv2
    cap = cv2.VideoCapture(str(src)); frames = []
    while True:
        ok, f = cap.read()
        if not ok: break
        frames.append(f)
    out_dir = Path(out_dir); out_dir.mkdir(parents=True, exist_ok=True)
    for s in seconds:
        o = av.open(str(out_dir / f'bench_{s}s.mp4'), 'w'); st = o.add_stream('libx264', rate=fps)
        st.height, st.width = frames[0].shape[:2]; st.pix_fmt = 'yuv420p'; st.options = {'crf': '17'}
        for i in range(s * fps):
            for p in st.encode(av.VideoFrame.from_ndarray(frames[i % len(frames)], format='bgr24')): o.mux(p)
        for p in st.encode(): o.mux(p)
        o.close()


def run(videos, work, half=False, repeat=1):
    import gvhmr_runner as g
    out = []
    for v in videos:
        for r in range(repeat):
            t = time.perf_counter()
            meta = g.run(v, Path(work) / f'{Path(v).stem}_{r}', half=half)
            meta.update(video=Path(v).name, repeat=r, wall_s=round(time.perf_counter() - t, 2))
            out.append(meta); print(json.dumps(meta), flush=True)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['make', 'run'])
    p.add_argument('--src'); p.add_argument('--out-dir'); p.add_argument('--videos', nargs='*')
    p.add_argument('--work'); p.add_argument('--out'); p.add_argument('--half', action='store_true')
    p.add_argument('--repeat', type=int, default=1)
    a = p.parse_args()
    if a.cmd == 'make': make(a.src, a.out_dir)
    else: json.dump(run(a.videos, a.work, a.half, a.repeat), open(a.out, 'w'), indent=1)


if __name__ == '__main__':
    main()
