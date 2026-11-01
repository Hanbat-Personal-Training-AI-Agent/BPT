"""Home-local CPU-only joint-definition diagnostic. Never changes cached predictions.

Only aggregate numbers and hashes may leave Home. See the predeclared protocol.
"""
import argparse
from collections import defaultdict
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import time

import numpy as np

NATIVE = {'pelvis': 0, 'left_hip': 1, 'right_hip': 2,
          'left_knee': 4, 'right_knee': 5, 'left_ankle': 7, 'right_ankle': 8,
          'left_shoulder': 16, 'right_shoulder': 17, 'left_elbow': 18,
          'right_elbow': 19, 'left_wrist': 20, 'right_wrist': 21}
H36M = {'pelvis': 0, 'left_hip': 4, 'right_hip': 1, 'left_knee': 5,
        'right_knee': 2, 'left_ankle': 6, 'right_ankle': 3, 'left_shoulder': 11,
        'right_shoulder': 14, 'left_elbow': 12, 'right_elbow': 15,
        'left_wrist': 13, 'right_wrist': 16}
LIMBS = [k for k in NATIVE if k != 'pelvis']
PARAMS = ('global_orient', 'body_pose', 'betas', 'transl')


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda: f.read(2**20), b''):
            h.update(b)
    return h.hexdigest()


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def h36m_slots(joints):
    """Only anatomically defined slots; unused cranial/spine slots remain NaN."""
    out = np.full((len(joints), 17, 3), np.nan)
    for name, index in NATIVE.items():
        out[:, H36M[name]] = joints[:, index]
    return out


class NativeFK:
    def __init__(self, body_model):
        import torch
        from smplx.joint_names import JOINT_NAMES
        from smplx.lbs import batch_rigid_transform, batch_rodrigues
        self.t, self.model = torch, body_model
        self.rigid, self.rodrigues = batch_rigid_transform, batch_rodrigues
        for name, index in NATIVE.items():
            assert JOINT_NAMES[index] == name, (name, index)
        assert body_model.bm.joint_mapper is None
        assert torch.count_nonzero(body_model.bm.pose_mean[:66]) == 0
        self.parents = body_model.bm.parents[:22]
        assert all(int(self.parents[i]) < i for i in range(1, 22))

    def __call__(self, params, batch=32):
        out = []
        with self.t.inference_mode():
            for start in range(0, len(params['body_pose']), batch):
                p = {k: v[start:start+batch].cpu().float() for k, v in params.items()}
                rest = self.model.get_skeleton(p['betas'])
                aa = self.t.cat([p['global_orient'], p['body_pose']], -1)
                rotations = self.rodrigues(aa.reshape(-1, 3)).reshape(-1, 22, 3, 3)
                joints = self.rigid(rotations, rest, self.parents, dtype=rest.dtype)[0]
                out.append((joints + p['transl'][:, None]).numpy())
        result = np.concatenate(out)
        assert np.isfinite(result).all()
        return result


def summarize(values):
    x = np.asarray(values, float)
    assert np.isfinite(x).all()
    return dict(count=len(x), mean=float(x.mean()), min=float(x.min()),
                median=float(np.median(x)), max=float(x.max()))


class Pool:
    def __init__(self):
        self.data = defaultdict(list)

    def add(self, key, value):
        self.data[key].extend(np.asarray(value, float).reshape(-1).tolist())

    def paired(self, prefix, old, new, gt):
        old, new, gt = np.broadcast_arrays(old, new, gt)
        a, b = np.abs(old-gt), np.abs(new-gt)
        self.add(prefix+'/originalAbsError', a)
        self.add(prefix+'/nativeAbsError', b)
        self.add(prefix+'/pairedAbsErrorDelta', b-a)
        self.add(prefix+'/originalSignedError', old-gt)
        self.add(prefix+'/nativeSignedError', new-gt)
        self.add(prefix+'/improved', b < a-1e-9)
        self.add(prefix+'/worsened', b > a+1e-9)

    def result(self):
        return {k: summarize(v) for k, v in sorted(self.data.items()) if v}


def trace_metrics(x, gt):
    hi, lo = int(np.argmax(gt)), int(np.argmin(gt))
    return dict(min=float(x.min()), max=float(x.max()), range=float(np.ptp(x)),
                sustainedRange=float(np.percentile(x, 95)-np.percentile(x, 5)),
                atGtMax=float(x[hi]), atGtMin=float(x[lo]),
                atGtExtremeSignedRange=float(x[hi]-x[lo]),
                maxFrameAbsError=float(np.max(np.abs(x-gt))),
                maxTimingAbsSeconds=abs(int(np.argmax(x))-hi)/30.,
                minTimingAbsSeconds=abs(int(np.argmin(x))-lo)/30.)


def assert_metrics(actual, saved):
    count, worst = 0, 0.
    assert len(actual) == len(saved)
    for a, b in zip(actual, saved):
        assert a.keys() == b.keys()
        for k in a:
            assert np.isclose(a[k], b[k], rtol=0, atol=1e-8, equal_nan=True), k
            if np.isfinite(a[k]):
                worst = max(worst, float(abs(a[k]-b[k])))
            count += 1
    return count, worst


def run(args):
    # GVHMR's import helper changes cwd for its checkpoint paths.
    for key in ('run', 'root', 'protocol', 'output', 'validation'):
        setattr(args, key, getattr(args, key).resolve())
    import torch
    torch.set_num_threads(2)
    torch.set_num_interop_threads(1)
    started = time.monotonic()
    runroot = args.run.resolve()
    sys.path.insert(0, str(runroot/'code/deep_analysis'))
    ev = module(runroot/'code/deep_analysis/eval_gvhmr_fit3d.py', 'joint_ablation_frozen_eval')
    e = ev.ev()
    import gvhmr_runner as g
    g._imports()
    original_model = g.H36M(device='cpu')
    native = NativeFK(original_model.smplx)
    jobs = json.loads((runroot/'jobs.json').read_text())
    scores = json.loads((runroot/'score_full_private.json').read_text())
    assert len(jobs) == len(scores) == 20
    score = {(r['subject'], r['exercise'], r['cam']): r for r in scores}
    sources = {p for p in (runroot/'jobs.json', runroot/'score_full_private.json',
                           runroot/'code/deep_analysis/eval_gvhmr_fit3d.py',
                           runroot/'code/eval_3d_angles.py',
                           runroot/'code/deep_analysis/gvhmr_runner.py')}
    for j in jobs:
        sd = args.root/'train'/j['subject']
        sources.update([sd/'rep_ann.json', sd/'camera_parameters'/j['cam']/(j['fit3d']+'.json')])
        base = sd/'joints3d_25'/j['fit3d']
        sources.add(base.with_suffix('.npy') if base.with_suffix('.npy').exists() else base.with_suffix('.json'))
        d = runroot/'work'/ev.tag(j)
        sources.update(d/v/'result.npz' for v in ('B', 'C'))
        sources.update(p for p in (d/'A.npz', d/'floor.npz') if p.exists())
    hashes_before = {p: sha(p) for p in sources}
    private_manifest = args.output.with_name('input_hashes_private.json')
    private_manifest.write_text(json.dumps({str(p): h for p, h in sorted(hashes_before.items())}, indent=2)+'\n')
    # First pass: validate every result and coordinate system before scoring any alternative.
    validation = dict(coordinateChecks=0, nativeMaxDifferenceMeters=0., surfaceMaxDifferenceMeters=0.)
    for ordinal, j in enumerate(jobs):
        for v in ('B', 'C'):
            with np.load(runroot/'work'/ev.tag(j)/v/'result.npz', allow_pickle=False) as z:
                for coord, field in (('incam', 'h36m17_cam'), ('global', 'h36m17_world')):
                    n = len(z[field]); pick = np.unique([0, n//2, n-1])
                    p = {k: torch.from_numpy(z[f'smplx_{coord}_{k}'][pick]) for k in PARAMS}
                    with torch.inference_mode():
                        standard = original_model.smplx(**p)
                        fast = native(p)
                        nd = float(np.max(np.abs(fast-standard.joints[:, :22].numpy())))
                        verts = torch.stack([original_model.x2s @ x for x in standard.vertices])
                        surface = torch.einsum('jv,bvc->bjc', original_model.reg, verts).numpy()
                        sd = float(np.max(np.abs(surface-z[field][pick])))
                    assert nd <= 1e-4 and sd <= 1e-4, (nd, sd)
                    validation['nativeMaxDifferenceMeters'] = max(validation['nativeMaxDifferenceMeters'], nd)
                    validation['surfaceMaxDifferenceMeters'] = max(validation['surfaceMaxDifferenceMeters'], sd)
                    validation['coordinateChecks'] += 1
        print('parity', ordinal+1, '/20', flush=True)
    validation.update(toleranceMeters=1e-4, framesPerCheck=3, passed=True)
    args.validation.write_text(json.dumps(validation, indent=2)+'\n')
    pool = Pool(); counts = defaultdict(int); checks = worst = 0
    decisions = defaultdict(lambda: defaultdict(int))
    for ordinal, j in enumerate(jobs):
        ex = j['exercise']; d = runroot/'work'/ev.tag(j)
        saved = score[(j['subject'], ex, j['cam'])]
        G = e.load_joints(str(args.root/'train'/j['subject']), j['fit3d'])
        R, T, _ = ev.load_cam(args.root, j['subject'], j['cam'], j['fit3d'])
        pick = ev.pick_frames(len(G)); G = G[pick]; up = ev.world_up(R)
        P = {}; K = None
        for v in ('B', 'C'):
            with np.load(d/v/'result.npz', allow_pickle=False) as z:
                P[v] = z['h36m17_cam'].astype(float)
                P[v+'w'] = z['h36m17_world'].astype(float)
                p = {k: torch.from_numpy(z[f'smplx_incam_{k}']) for k in PARAMS}
                P[v+'native'] = h36m_slots(native(p, args.batch))
        for v, filename in (('A', 'A.npz'), ('floor', 'floor.npz')):
            if (d/filename).exists():
                with np.load(d/filename, allow_pickle=False) as z:
                    P[v] = z['P'].astype(float)
                    if v == 'A': K = z['K']
        n = min([len(G)]+[len(p) for p in P.values()]+([len(K)] if K is not None else []))
        G = G[:n]; P = {v: p[:n] for v, p in P.items()}
        side = e.near_side(K[:n]) if K is not None else j['side_gt']
        assert side == saved['side']
        segs = [(int(np.searchsorted(pick, s)), min(int(np.searchsorted(pick, t)), n-1))
                for s, t in zip(j['reps'], j['reps'][1:]) if int(np.searchsorted(pick, s)) < n-1]
        inside = np.zeros(n, bool)
        for s, t in segs: inside[s:t+1] = True
        angles = {'GT': e.angles_3d(G, up, side)}
        for v, p in P.items():
            pu = up if v == 'floor' else (np.array([0, 1., 0]) if v.endswith('w') else np.array([0, -1., 0]))
            angles[v] = e.angles_3d(p, pu, side)
        if K is not None: angles['A2D'] = e.angles_2d(K[:n], side)
        metrics = {v: ev.rep_metrics(a, segs) for v, a in angles.items()}
        for v, m in metrics.items():
            if v.endswith('native'): continue
            c, w = assert_metrics(m, saved['rep_metrics'][v]); checks += c; worst = max(worst, w)
        # Frozen cohort union uses original outputs only, never native results.
        key = {'barbell_row': 'row_torso_swing', 'pushup': 'pushup_no_lockout'}.get(ex)
        failed = np.zeros(len(segs), bool)
        if key:
            _, fn, thr = ev.KEYS[key]
            gv = np.array(fn(metrics['GT']), float)
            for v in ('B', 'C'):
                pv = np.array(fn(metrics[v]), float)
                failed |= np.isfinite(gv) & (abs(gv-thr) <= ev.BOUNDARY) & ((gv > thr) != (pv > thr))
        counts[ex+'/videos'] += 1
        counts[ex+'/reps'] += len(segs)
        counts[ex+'/failedUnionReps'] += int(failed.sum())
        counts[ex+'/uniqueFramesInsideReps'] += int(inside.sum())
        Gcam = (G-G[:, :1]) @ R.T
        for v in ('B', 'C'):
            old, new = P[v], P[v+'native']
            for name in LIMBS:
                idx = H36M[name]
                a = np.linalg.norm((old-old[:, :1])[:, idx]-Gcam[:, idx], axis=-1)*1000
                b = np.linalg.norm((new-new[:, :1])[:, idx]-Gcam[:, idx], axis=-1)*1000
                pool.paired(ex+'/'+v+'/coordinateMm/'+name, a[inside], b[inside], 0.)
                pool.paired(ex+'/'+v+'/coordinateMm/all12', a[inside], b[inside], 0.)
                pool.add(ex+'/'+v+'/nativeMinusSurfaceRootRelativeMm/'+name,
                         np.linalg.norm((new-new[:, :1])[:, idx]-(old-old[:, :1])[:, idx], axis=-1)[inside]*1000)
            for label in ('selected', 'L', 'R'):
                use_side = side if label == 'selected' else label
                ga = e.angles_3d(G, up, use_side)
                oa = e.angles_3d(old, np.array([0, -1., 0]), use_side)
                na = e.angles_3d(new, np.array([0, -1., 0]), use_side)
                for angle in ('knee', 'hip', 'elbow', 'torso'):
                    prefix = ex+'/'+v+'/'+label+'/'+angle
                    pool.paired(prefix+'/frameDegrees', oa[angle][inside], na[angle][inside], ga[angle][inside])
                    pool.paired(prefix+'/videoMaeDegrees', np.mean(abs(oa[angle][inside]-ga[angle][inside])),
                                np.mean(abs(na[angle][inside]-ga[angle][inside])), 0.)
                    for ri, (s, t) in enumerate(segs):
                        sl = slice(s, t+1)
                        ts = [trace_metrics(a[angle][sl], ga[angle][sl]) for a in (ga, oa, na)]
                        cohort = 'originalFailureUnion' if failed[ri] else 'otherReps'
                        for group in ('allReps', cohort):
                            for metric in ts[0]:
                                # Timing and maximum frame errors have zero as their target.
                                target = 0. if metric.endswith('Seconds') or metric == 'maxFrameAbsError' else ts[0][metric]
                                pool.paired(prefix+'/'+group+'/'+metric, ts[1][metric], ts[2][metric], target)
            for decision, (exercise, fn, thr) in ev.KEYS.items():
                if exercise != ex: continue
                gv = np.asarray(fn(metrics['GT']), float)
                for suffix in ('', 'native'):
                    pv = np.asarray(fn(metrics[v+suffix]), float)
                    eligible = np.isfinite(gv) & np.isfinite(pv)
                    for group, mask in [('all', eligible), ('boundary', eligible & (abs(gv-thr) <= ev.BOUNDARY)),
                                        ('originalFailureUnion', eligible & failed), ('otherReps', eligible & ~failed)]:
                        k = '/'.join([decision, v+suffix, group]); dest = decisions[k]
                        dest['count'] += int(mask.sum()); dest['agree'] += int(((gv > thr) == (pv > thr))[mask].sum())
                        dest['falsePositive'] += int((mask & (gv <= thr) & (pv > thr)).sum())
                        dest['falseNegative'] += int((mask & (gv > thr) & (pv <= thr)).sum())
                        if mask.any() and suffix == '':
                            pool.paired(k+'/decisionValue', np.asarray(fn(metrics[v]))[mask],
                                        np.asarray(fn(metrics[v+'native']))[mask], gv[mask])
            # Selected-side current/reference peaks and differential error, same cohort/complement.
            if ex == 'pushup':
                peaks = {k: np.array([m['elbow_max'] for m in metrics[k]]) for k in ('GT', v, v+'native')}
                for ri in range(len(segs)):
                    cohort = 'originalFailureUnion' if failed[ri] else 'otherReps'
                    for group in ('allReps', cohort):
                        prefix = ex+'/'+v+'/selectedReference/'+group
                        cur = [peaks[k][ri] for k in ('GT', v, v+'native')]
                        ref = [np.max(peaks[k][:ri+1]) for k in ('GT', v, v+'native')]
                        for name, vals in [('currentMax', cur), ('runningReferenceMax', ref),
                                           ('deficit', np.asarray(ref)-np.asarray(cur))]:
                            pool.paired(prefix+'/'+name, vals[1], vals[2], vals[0])
                        gtref = int(np.argmax(peaks['GT'][:ri+1]))
                        for k in (v, v+'native'):
                            pool.add(prefix+'/'+k+'/referenceMatchesGt', int(np.argmax(peaks[k][:ri+1])) == gtref)
        print('scored', ordinal+1, '/20', flush=True)
    unchanged = all(sha(p) == h for p, h in hashes_before.items())
    assert unchanged
    import inspect
    import smplx.lbs
    import smplx.joint_names
    implementation = [Path(inspect.getfile(type(native.model))), Path(inspect.getfile(smplx.lbs)),
                      Path(inspect.getfile(smplx.joint_names))]
    model_path = g.GVHMR_ROOT/'inputs/checkpoints/body_models/smplx/SMPLX_NEUTRAL.npz'
    result = dict(purpose='reused20_joint_definition_diagnostic_no_adoption',
                  counts=dict(counts), mapping=NATIVE, validation=validation,
                  frozenScoreValuesChecked=checks, maximumFrozenScoreDelta=worst,
                  inputFileCount=len(hashes_before), allInputHashesUnchanged=unchanged,
                  inputCohortSha256=hashlib.sha256(''.join(sorted(hashes_before.values())).encode()).hexdigest(),
                  scoreSha256=sha(runroot/'score_full_private.json'), jobsSha256=sha(runroot/'jobs.json'),
                  helperSha256=sha(__file__), protocolSha256=sha(args.protocol),
                  implementationHashes={p.name: sha(p) for p in implementation}, modelSha256=sha(model_path),
                  distributions=pool.result(), decisions=dict(decisions),
                  elapsedSeconds=time.monotonic()-started, cpuThreads=2, batch=args.batch)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print(json.dumps({k: result[k] for k in ('counts', 'validation', 'frozenScoreValuesChecked',
                                           'maximumFrozenScoreDelta', 'allInputHashesUnchanged', 'elapsedSeconds')}))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--run', type=Path, required=True)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--protocol', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--validation', type=Path, required=True)
    p.add_argument('--batch', type=int, default=32)
    args = p.parse_args()
    assert 1 <= args.batch <= 64
    run(args)
