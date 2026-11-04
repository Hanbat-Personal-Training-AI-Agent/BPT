"""CPU-only temporal evaluation of saved Fit3D predictions; see frozen protocol.

Private output contains event data/identifiers and MUST remain beside the private
source data. Public output contains exercise-level aggregates and anonymous hashes.
No model invocation or alteration of existing files occurs.
"""
import argparse
from collections import defaultdict
from fractions import Fraction
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import numpy as np


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def events(sig, lo=.35, hi=.65, k=9):
    """Instrument count() without changing its signal or branch decisions.

    Return (start index, end index, terminal partial). The last high sample before
    entering the low state anchors the interval. The completion sample is its end.
    """
    sig = np.asarray(sig, float)
    good = np.isfinite(sig)
    if good.sum() < k:
        return []
    sig = np.interp(np.arange(len(sig)), np.where(good)[0], sig[good])
    sig = np.convolve(np.pad(sig, k // 2, mode='edge'), np.ones(k) / k, mode='valid')
    p5, p95 = np.percentile(sig, [5, 95])
    if p95 - p5 < 1e-6:
        return []
    n = (sig - p5) / (p95 - p5)
    armed, low, start, out = n[0] > hi, False, 0, []
    for i, v in enumerate(n):
        if v > hi:
            if low:
                out.append((start, i, False))
            armed, low, start = True, False, i
        elif v < lo and armed:
            low = True
    if low and n[-1] > .5:
        out.append((start, len(n) - 1, True))
    return out


def iou(a, b):
    intersection = max(0, min(a[1], b[1]) - max(a[0], b[0]))
    union = max(a[1], b[1]) - min(a[0], b[0])
    return Fraction(int(intersection), int(union)) if union else Fraction(0)


def matching(pred, ref, threshold=Fraction(1, 2)):
    """Exact max-cardinality, max-IoU, min-endpoint-L1 bipartite matching.

    Successive shortest augmenting paths on residual unit-capacity graph. Cost
    tuples compare lexicographically, using exact rational IoU. Bellman-Ford
    handles negative/reverse edges. Stable insertion/relaxation order resolves
    tied optima deterministically; augmentation permits reassignment of old pairs.
    """
    for interval in [*pred, *ref]:
        if len(interval) != 2 or interval[0] >= interval[1]:
            raise ValueError('intervals must have positive duration')
    n, m = len(pred), len(ref)
    sink = n + m + 1
    graph = [[] for _ in range(sink + 1)]
    zero = (Fraction(0), 0)

    def edge(a, b, cost):
        f = [b, len(graph[b]), 1, cost]
        r = [a, len(graph[a]), 0, tuple(-x for x in cost)]
        graph[a].append(f)
        graph[b].append(r)
        return f

    for p in range(n):
        edge(0, p + 1, zero)
    links = []
    for p, a in enumerate(pred):
        for r, b in enumerate(ref):
            score = iou(a, b)
            if score >= threshold:
                links.append((p, r, edge(p + 1, n + 1 + r,
                    (-score, abs(a[0] - b[0]) + abs(a[1] - b[1])))))
    for r in range(m):
        edge(n + 1 + r, sink, zero)
    while True:
        distance, parent = [None] * len(graph), [None] * len(graph)
        distance[0] = zero
        for _ in range(len(graph) - 1):
            changed = False
            for a, edges in enumerate(graph):
                if distance[a] is None:
                    continue
                for k, e in enumerate(edges):
                    if not e[2]:
                        continue
                    candidate = tuple(x + y for x, y in zip(distance[a], e[3]))
                    if distance[e[0]] is None or candidate < distance[e[0]]:
                        distance[e[0]], parent[e[0]] = candidate, (a, k)
                        changed = True
            if not changed:
                break
        if parent[sink] is None:
            break
        b = sink
        while b != 0:
            a, k = parent[b]
            e = graph[a][k]
            e[2] -= 1
            graph[b][e[1]][2] += 1
            b = a
    return [(p, r) for p, r, e in links if not e[2]]


def scoreable_events(pred_all, censored):
    """Return observable intervals and their indices in the full emitted list."""
    indices = [i for i, p in enumerate(pred_all)
               if not any(iou(p, r) > 0 for r in censored)]
    return [pred_all[i] for i in indices], indices


def stats(values):
    a = np.asarray(values, float)
    if not len(a):
        return {'n': 0, 'mean': None, 'median': None, 'p95': None}
    return dict(n=len(a), mean=float(a.mean()), median=float(np.median(a)),
                p95=float(np.percentile(a, 95)))


def summarize(rows):
    """Pool event counts and matched-only boundary samples over videos."""
    out = {}
    for ex in sorted({r['exercise'] for r in rows} | {'all'}):
        selected = [r for r in rows if ex == 'all' or r['exercise'] == ex]
        for variant in sorted({v for r in selected for v in r['variants']}):
            vr = [r['variants'][variant] for r in selected if variant in r['variants']]
            for threshold in ('0.25', '0.50', '0.75'):
                rr = [r['scores'][threshold] for r in vr]
                sums = {k: sum(r[k] for r in rr) for k in ('reference', 'predicted', 'matched', 'missed', 'extra')}
                t, p, tp = sums['reference'], sums['predicted'], sums['matched']
                sums.update(videos=len(vr), precision=tp / p if p else None,
                            recall=tp / t if t else None, f1=2 * tp / (t + p) if t + p else None,
                            event_accuracy=tp / (t + sums['extra']) if t + sums['extra'] else None)
                legacy_t = sum(r['all_reference'] for r in vr)
                legacy_miss = sum(max(0, r['all_reference'] - r['raw_count']) for r in vr)
                legacy_extra = sum(max(0, r['raw_count'] - r['all_reference']) for r in vr)
                sums['legacy_net_count_proxy'] = ((legacy_t - legacy_miss) / (legacy_t + legacy_extra)
                                                   if legacy_t + legacy_extra else None)
                for key in ('start_signed_s', 'end_signed_s', 'start_abs_s', 'end_abs_s', 'iou'):
                    sums[key] = stats([x for r in rr for x in r[key]])
                for key in ('terminal_partial', 'outside_annotation_span', 'censored_prediction', 'censored_reference',
                            'finite_samples', 'interpolated_samples', 'all_reference', 'raw_count'):
                    sums[key] = sum(r[key] for r in vr)
                out[f'{ex}/{variant}/iou{threshold}'] = sums
    return out


def run(args):
    run_dir, root = args.run.resolve(), args.root.resolve()
    sys.path.insert(0, str(run_dir / 'code'))
    ev = load_module(run_dir / 'code/deep_analysis/eval_gvhmr_fit3d.py', 'frozen_temporal_eval')
    e = ev.ev()
    counter = load_module(run_dir / 'code/count_reps_3d_vs_2d.py', 'frozen_temporal_count')
    jobs_path, score_path = run_dir / 'jobs.json', run_dir / 'score_full_private.json'
    jobs, scores = json.loads(jobs_path.read_text()), json.loads(score_path.read_text())
    score_by_key = {(r['subject'], r['exercise'], r['cam']): r for r in scores}
    paths = {jobs_path, score_path, Path(__file__).resolve(), args.protocol.resolve(),
             run_dir / 'code/deep_analysis/eval_gvhmr_fit3d.py', run_dir / 'code/eval_3d_angles.py',
             run_dir / 'code/count_reps_3d_vs_2d.py'}
    for j in jobs:
        sd, d = root / 'train' / j['subject'], run_dir / 'work' / ev.tag(j)
        jp = sd / 'joints3d_25' / j['fit3d']
        paths.update([sd / 'rep_ann.json', sd / 'camera_parameters' / j['cam'] / (j['fit3d'] + '.json'),
                      jp.with_suffix('.npy') if jp.with_suffix('.npy').exists() else jp.with_suffix('.json')])
        paths.update(d / v / 'result.npz' for v in ('B', 'C'))
        if (d / 'A.npz').exists():
            paths.add(d / 'A.npz')
    before = {str(p): sha(p) for p in sorted(paths)}
    rows = []
    for j in jobs:
        ex, d = j['exercise'], run_dir / 'work' / ev.tag(j)
        source_ann = json.loads((root / 'train' / j['subject'] / 'rep_ann.json').read_text())[j['fit3d']]
        if source_ann != j['reps']:
            raise ValueError('jobs annotation differs from source')
        G = e.load_joints(str(root / 'train' / j['subject']), j['fit3d'])
        boundaries = np.asarray(j['reps'])
        if (boundaries.ndim != 1 or len(boundaries) < 2 or not np.isfinite(boundaries).all()
                or not (boundaries == boundaries.astype(int)).all() or not (np.diff(boundaries) > 0).all()
                or boundaries[0] < 0 or boundaries[-1] >= len(G)):
            raise ValueError('invalid source-frame annotation boundaries')
        pick = ev.pick_frames(len(G))
        P, K = {}, None
        for v in ('B', 'C'):
            with np.load(d / v / 'result.npz', allow_pickle=False) as z:
                P[v] = z['h36m17_cam'].astype(float)
        if (d / 'A.npz').exists():
            with np.load(d / 'A.npz', allow_pickle=False) as z:
                P['A'], K = z['P'], z['K']
        n = min([len(pick)] + [len(p) for p in P.values()] + ([len(K)] if K is not None else []))
        if n < 2:
            raise ValueError('insufficient common prefix')
        side = e.near_side(K[:n]) if K is not None else j['side_gt']
        R, _, _ = ev.load_cam(root, j['subject'], j['cam'], j['fit3d'])
        angles = {'mocap_control': e.angles_3d(G[pick[:n]], ev.world_up(R), side)}
        angles.update({v: e.angles_3d(p[:n], np.array([0., -1, 0]), side) for v, p in P.items()})
        if K is not None:
            angles['A2D'] = e.angles_2d(K[:n], side)
        all_ref = list(zip(boundaries[:-1].tolist(), boundaries[1:].tolist()))
        reference = [r for r in all_ref if r[0] >= pick[0] and r[1] <= pick[n - 1]]
        censored = [r for r in all_ref if r not in reference]
        row = dict(subject=j['subject'], exercise=ex, cam=j['cam'], source_frames=len(G),
                   expected_samples=len(pick), observed_samples=n, annotation_matches=True, variants={})
        old = score_by_key[(j['subject'], ex, j['cam'])]
        if side != old['side']:
            raise ValueError('frozen selected side changed')
        limb = 'hip' if ex == 'deadlift' else counter.LIMB[j['fit3d']]
        for v, a in angles.items():
            signal = a[limb]
            raw = events(signal)
            expected_count = int(counter.count(signal))
            if len(raw) != expected_count or expected_count != old['reps']['GT' if v == 'mocap_control' else v]:
                raise ValueError('counter or saved score parity failed')
            pred_all = [(int(pick[s]), int(pick[t])) for s, t, _ in raw]
            pred, original_indices = scoreable_events(pred_all, censored)
            vr = dict(raw_count=len(raw), all_reference=len(all_ref), terminal_partial=sum(x[2] for x in raw),
                      outside_annotation_span=int(sum(p[1] <= boundaries[0] or p[0] >= boundaries[-1] for p in pred_all)),
                      finite_samples=int(np.isfinite(signal).sum()),
                      interpolated_samples=int((~np.isfinite(signal)).sum()),
                      censored_reference=len(censored), censored_prediction=len(pred_all) - len(pred),
                      events=pred_all, scored_events=pred, scored_event_original_indices=original_indices,
                      pair_index_convention='pairs index scored_events and reference',
                      reference=reference, scores={})
            for label, threshold in [('0.25', Fraction(1, 4)), ('0.50', Fraction(1, 2)), ('0.75', Fraction(3, 4))]:
                pairs = matching(pred, reference, threshold)
                start = [(pred[p][0] - reference[r][0]) / 50 for p, r in pairs]
                end = [(pred[p][1] - reference[r][1]) / 50 for p, r in pairs]
                vr['scores'][label] = dict(reference=len(reference), predicted=len(pred), matched=len(pairs),
                    missed=len(reference) - len(pairs), extra=len(pred) - len(pairs), pairs=pairs,
                    start_signed_s=start, end_signed_s=end, start_abs_s=list(map(abs, start)),
                    end_abs_s=list(map(abs, end)), iou=[float(iou(pred[p], reference[r])) for p, r in pairs])
            row['variants'][v] = vr
        rows.append(row)
    after = {p: sha(p) for p in before}
    if before != after:
        raise ValueError('source/input hash changed during evaluation')
    private = {'rows': rows, 'source_hashes': before}
    public = dict(schema_version=2, comparison='dataset-reference temporal agreement',
                  clock='source frame / 50; half-open intervals', primary_iou=0.5,
                  code_sha256={p.name: before[str(p)] for p in paths if p.suffix == '.py'},
                  protocol_sha256=sha(args.protocol), source_hashes_unchanged=True,
                  source_manifest_sha256=hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest(),
                  anonymous_input_sha256=sorted(before.values()),
                  runtime=dict(python=sys.version.split()[0], numpy=np.__version__),
                  coverage=dict(jobs=len(jobs), evaluated=len(rows), annotation_checks_passed=len(rows),
                    source_frames=sum(r['source_frames'] for r in rows),
                    expected_samples=sum(r['expected_samples'] for r in rows),
                    observed_samples=sum(r['observed_samples'] for r in rows),
                    missing_A_jobs=sum('A' not in r['variants'] for r in rows),
                    counter_parity_checks=sum(len(r['variants']) for r in rows)),
                  metrics=summarize(rows))
    # Serialize first so type/nonfinite failures cannot create partial JSON.
    private_json = json.dumps(private, indent=2, allow_nan=False)
    public_json = json.dumps(public, indent=2, allow_nan=False)
    # Exclusive writes prevent overwriting even a previous evaluation result.
    with args.private_out.open('x') as f:
        f.write(private_json + '\n')
    with args.out.open('x') as f:
        f.write(public_json + '\n')
    print(json.dumps(public, allow_nan=False))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('run', 'root', 'out', 'private-out', 'protocol'):
        p.add_argument('--' + name, type=Path, required=True)
    run(p.parse_args())


if __name__ == '__main__':
    main()
