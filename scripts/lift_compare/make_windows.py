"""Parity windows for Core ML checks: XS inputs (person_crop, app mapping) from Exercise3D app-path m COCO17 CSVs
(no Fit3D data). Every 15th frame window of each video, 27 frames edge-clamped like the app (lookahead 5).

usage: make_windows.py --csv-dir ~/bpt-runs/reacquire/e3d__cur --out windows.npz [--max 400]
"""
import argparse, glob, gzip, json, sys
from pathlib import Path
import numpy as np

sys.path[:0] = [str(Path(__file__).resolve().parents[2]), str(Path(__file__).resolve().parents[1]), str(Path(__file__).resolve().parent)]
from ex3d_lift import read  # noqa: E402
from finetune_motionagformer_fit3d import mag_input  # noqa: E402


def main():
    p = argparse.ArgumentParser(); p.add_argument('--csv-dir'); p.add_argument('--out'); p.add_argument('--max', type=int, default=400)
    a = p.parse_args(); W = []
    for f in sorted(glob.glob(f'{a.csv_dir}/*_mcoco17.csv*')):
        if f.endswith('_crops.csv') or f.endswith('_crops.csv.gz'): continue
        stem = f.split('/')[-1].split('_mcoco17')[0]
        w, h = json.load(open(f'{a.csv_dir}/{stem}_mcoco17.json'))['image_size']
        K = read(f)[:, :17]; x, _ = mag_input(K, w, h); n = len(x)
        for i in range(0, n, 15):
            idx = np.clip(np.arange(i + 5 - 26, i + 6), 0, n - 1); W.append(x[idx])
    W = np.array(W, np.float32)[np.random.default_rng(0).permutation(len(W))[:a.max]]
    np.savez(a.out, x=W); print(W.shape)


if __name__ == '__main__':
    main()
