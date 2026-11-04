"""Post-result mocap phase/dwell diagnosis, explicitly no acceptance rescore."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import sys

import numpy as np

from eval_temporal_repetitions import events, iou, load_module, sha, stats


def normalized(signal):
    signal = np.asarray(signal, float)
    good = np.isfinite(signal)
    signal = np.interp(np.arange(len(signal)), np.where(good)[0], signal[good])
    smooth = np.convolve(np.pad(signal, 4, mode='edge'), np.ones(9) / 9, mode='valid')
    a, b = np.percentile(smooth, [5, 95])
    if b - a < 1e-6:
        raise ValueError('flat control signal')
    return (smooth - a) / (b - a)


def run(args):
    sys.path.insert(0, str(args.run / 'code'))
    ev = load_module(args.run / 'code/deep_analysis/eval_gvhmr_fit3d.py', 'phase_ev')
    e = ev.ev()
    old = json.loads((args.run / 'score_full_private.json').read_text())
    sides = {(r['subject'], r['exercise'], r['cam']): r['side'] for r in old}
    jobs = json.loads((args.run / 'jobs.json').read_text())
    pool, counts = defaultdict(lambda: defaultdict(list)), defaultdict(lambda: defaultdict(int))
    hashes = {str(p): sha(p) for p in [Path(__file__), args.protocol,
              args.run / 'jobs.json', args.run / 'score_full_private.json',
              args.run / 'code/deep_analysis/eval_gvhmr_fit3d.py',
              args.run / 'code/eval_3d_angles.py', Path(__file__).with_name('eval_temporal_repetitions.py')]}
    for j in jobs:
        ex = j['exercise']
        jp = args.root / 'train' / j['subject'] / 'joints3d_25' / j['fit3d']
        jp = jp.with_suffix('.npy') if jp.with_suffix('.npy').exists() else jp.with_suffix('.json')
        hashes[str(jp)] = sha(jp)
        cp = args.root / 'train' / j['subject'] / 'camera_parameters' / j['cam'] / (j['fit3d'] + '.json')
        hashes[str(cp)] = sha(cp)
        G = e.load_joints(str(args.root / 'train' / j['subject']), j['fit3d'])
        pick = ev.pick_frames(len(G))
        R, _, _ = ev.load_cam(args.root, j['subject'], j['cam'], j['fit3d'])
        side = sides[(j['subject'], ex, j['cam'])]
        limb = 'hip' if ex == 'deadlift' else ('knee' if ex == 'squat' else 'elbow')
        signal = e.angles_3d(G[pick], ev.world_up(R), side)[limb]
        norm = normalized(signal)
        emitted = events(signal)
        pred = [(int(pick[a]), int(pick[b])) for a, b, _ in emitted]
        for a, b, _ in emitted:
            left, right = a, b
            while left > 0 and norm[left - 1] > .65:
                left -= 1
            while right + 1 < len(norm) and norm[right + 1] > .65:
                right += 1
            pool[ex]['event_duration_s'].append((pick[b] - pick[a]) / 50)
            pool[ex]['omitted_high_before_s'].append((pick[a] - pick[left]) / 50)
            pool[ex]['omitted_high_after_s'].append((pick[right] - pick[b]) / 50)
            pool[ex]['high_expanded_duration_s'].append((pick[right] - pick[left]) / 50)
        for start, end in zip(j['reps'], j['reps'][1:]):
            a, b = np.searchsorted(pick, [start, end])
            values = norm[a:b + 1]
            counts[ex]['references'] += 1
            for label, value in [('start', norm[a]), ('end', norm[b])]:
                state = 'high' if value > .65 else ('low' if value < .35 else 'middle')
                counts[ex][label + '_' + state] += 1
                pool[ex][label + '_normalized'].append(float(value))
            low = values < .35
            runs = int(low[0]) + int((low[1:] & ~low[:-1]).sum())
            counts[ex]['low_runs_' + str(runs)] += 1
            pool[ex]['minimum_relative_position'].append(float(np.argmin(values) / max(1, len(values) - 1)))
            pool[ex]['reference_duration_s'].append((end - start) / 50)
            pool[ex]['high_sample_fraction'].append(float((values > .65).mean()))
            p = max(pred, key=lambda p: iou(p, (start, end)))
            pool[ex]['best_excursion_iou'].append(float(iou(p, (start, end))))
            pool[ex]['best_excursion_duration_ratio'].append((p[1] - p[0]) / (end - start))
            pool[ex]['best_excursion_start_shift_s'].append((p[0] - start) / 50)
            pool[ex]['best_excursion_end_shift_s'].append((p[1] - end) / 50)
    if any(sha(Path(p)) != h for p, h in hashes.items()):
        raise ValueError('input changed')
    output = dict(purpose='post-result phase/dwell diagnostic, no rescore',
                  source_sha256=sorted(hashes.values()), protocol_sha256=sha(args.protocol),
                  counts=dict(counts), metrics={ex: {k: stats(v) for k, v in metrics.items()} for ex, metrics in pool.items()})
    with args.out.open('x') as f:
        json.dump(output, f, indent=2, allow_nan=False)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('run', 'root', 'protocol', 'out'):
        p.add_argument('--' + name, required=True, type=Path)
    run(p.parse_args())
