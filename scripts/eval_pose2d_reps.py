"""Rep accuracy and feedback-event counts of a pose model through the app's evaluators (pose-replay).

Runs pose-replay (whole-frame input like the app, no 3D) on Exercise3D 13 sets x 3 cams plus the
no-motion regression videos (squat_03 truth 2, calibration dummies truth 0), then scores reps against
outputs/rep_validation/gt.json with analyze.py's matching (each app rep end credits the latest
uncredited truth trough at or before it; leftovers = missed / extra).
rep accuracy = (truth - missed) / (truth + extra).

BPT_HEAVY_SH=<heavy.sh> wraps each pose-replay call in the shared lock.
usage: eval_pose2d_reps.py --binary PATH --name NAME --model coco17|halpe26 [--model-path MLPACKAGE] --out DIR
"""

import argparse
import collections
import concurrent.futures as cf
import glob
import json
import os
import subprocess

from eval_pose2d import GT_JSON, MAIN

EXERCISE = {'squat': 'squat', 'pushup': 'pushup', 'barbellrow': 'row'}
DUMMIES = sorted(glob.glob(str(MAIN / 'outputs/calibration_dummy_videos/dummy_0*.mp4')))
SQUAT_03 = MAIN / 'assets/coreml_pipeline/videos/squat_03.mp4'
# Shared lock per video so other tracks' builds/tests interleave (BRIEF coordination protocol).
HEAVY = os.environ.get('BPT_HEAVY_SH')


def match(troughs, ends):
    credited, extra, last = {}, [], -1
    for i, e in enumerate(ends):
        cand = [k for k, t in enumerate(troughs) if t <= e + 5 and k > last]
        if cand:
            last = cand[-1]
            credited[last] = i
        else:
            extra.append(i)
    return credited, extra


def run(binary, model, model_path, exercise, video, out):
    os.makedirs(out, exist_ok=True)
    stem = os.path.basename(video)[:-4]
    cached = glob.glob(f'{out}/{stem}_*_{model}.json')
    if cached:
        return json.load(open(cached[0]))
    cmd = [binary, '--exercise', exercise, '--model', model, '--motion3d', 'none', '--output-dir', out, video]
    if model_path:
        cmd[1:1] = ['--model-path', model_path]
    if HEAVY:
        cmd = [HEAVY] + cmd
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    for f in glob.glob(f'{out}/{stem}_*.csv'):
        os.remove(f)
    return json.load(open(glob.glob(f'{out}/{stem}_*_{model}.json')[0]))


def events(res):
    c = collections.Counter()
    for e in res.get('events', []):
        c[e.get('key', '?')] += 1
    return c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--binary', required=True)
    ap.add_argument('--name', required=True)
    ap.add_argument('--model', default='coco17')
    ap.add_argument('--model-path')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    gt = json.load(open(GT_JSON))
    jobs = [(seq, cam) for seq in gt for cam in ('cam1', 'cam2', 'cam3')]

    def job(j):
        seq, cam = j
        g = gt[seq]
        video = str(MAIN / 'outputs/exercise3d_synced' / g['exercise'] / seq / f'{cam}.mp4')
        res = run(a.binary, a.model, a.model_path, EXERCISE[g['exercise']], video, f'{a.out}/{a.name}/{seq}')
        ends = [r['end_frame'] for r in res['reps']]
        credited, extra = match(g['rep_frames'], ends)
        return dict(seq=seq, cam=cam, exercise=g['exercise'], angle=g['views'][cam]['angle_deg'], truth=g['truth_reps'],
                    counted=len(ends), missed=g['truth_reps'] - len(credited), extra=len(extra), events=dict(events(res)),
                    warning_rep_counts=res['session'].get('warning_rep_counts', {}))

    def regression(j):
        exercise, video, truth = j
        res = run(a.binary, a.model, a.model_path, exercise, video, f'{a.out}/{a.name}/regression_{exercise}')
        return dict(video=os.path.basename(video), exercise=exercise, truth=truth, counted=len(res['reps']), events=dict(events(res)))

    with cf.ThreadPoolExecutor(3) as pool:
        rows = list(pool.map(job, jobs))
        reg = list(pool.map(regression, [('squat', str(SQUAT_03), 2)] + [(e, d, 0) for d in DUMMIES for e in ('squat', 'row')]))
    summary = {}
    for side in ('side40', 'other'):
        for ex in ('squat', 'pushup', 'barbellrow'):
            sel = [r for r in rows if r['exercise'] == ex and (round(r['angle']) <= 40) == (side == 'side40')]
            T, mi, xe = sum(r['truth'] for r in sel), sum(r['missed'] for r in sel), sum(r['extra'] for r in sel)
            ev = collections.Counter()
            for r in sel:
                ev.update(r['events'])
            summary[f'{side}/{ex}'] = dict(sets=len(sel), exact=sum(r['counted'] == r['truth'] for r in sel), truth=T,
                                           counted=sum(r['counted'] for r in sel), missed=mi, extra=xe,
                                           rep_accuracy=round((T - mi) / (T + xe), 4) if T else None, events=dict(ev))
    out = dict(name=a.name, model=a.model, model_path=a.model_path, summary=summary, regression=reg, rows=rows)
    json.dump(out, open(f'{a.out}/{a.name}.json', 'w'), indent=1)
    for k, v in summary.items():
        print(a.name, k, {x: v[x] for x in ('sets', 'exact', 'truth', 'counted', 'missed', 'extra', 'rep_accuracy')}, v['events'])
    for r in reg:
        print(a.name, 'regression', r)


if __name__ == '__main__':
    main()
