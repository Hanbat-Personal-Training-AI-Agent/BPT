"""eval-full: tables from fit3d_ablate.py records (Home). Aggregates only.

usage: summarize.py --runs RUN1,RUN2,... --compare A:B,... --out OUT   (A, B = run/var, e.g. C3_h26/Kstar)
Pooling (lift-refine definitions): MPJPE / PA / accel = mean over all frames of all videos; rep-extreme angle error =
median (p90) over all reps; invalid / impossible / knee flip = frame-weighted. Bootstrap: videos resampled with
replacement (2000, seed 0), the same videos for A and B (paired by subject, exercise, camera).
"""
import argparse, json
from collections import defaultdict

import numpy as np

ANG = ('knee', 'hip', 'elbow', 'torso_g')
EXS = ('squat', 'pushup', 'barbell_row')
NOISY6 = {'squat_no_lockout', 'valgus_if_front', 'pushup_no_lockout', 'pushup_hip_pike', 'pushup_shallow', 'pushup_head_up'}
RULES = {'squat': ['squat_hips_first', 'squat_shallow', 'squat_no_lockout', 'squat_lean_drift', 'squat_depth_fade', 'valgus_if_front'],
         'pushup': ['pushup_hip_sag', 'pushup_hip_pike', 'pushup_shallow', 'pushup_no_lockout', 'pushup_head_drop', 'pushup_head_up',
                    'pushup_hand_position', 'pushup_depth_fade'],
         'barbell_row': ['row_torso_swing', 'row_standing_up', 'row_short_pull', 'row_head_up']}


def stats(rs):
    n = sum(r['n'] for r in rs); na = sum(r['n_acc'] for r in rs); fr = sum(r['frames'] for r in rs)
    out = dict(videos=len(rs), mpjpe=sum(r['mpjpe'] for r in rs) / n, pa=sum(r['pa'] for r in rs) / n,
               accel=sum(r['accel'] for r in rs) / na,
               invalid=sum(r['invalid'] * r['frames'] for r in rs) / fr, impossible=sum(r['impossible'] * r['frames'] for r in rs) / fr,
               knee_flip=sum(r['knee_flip_raw'] * r['frames'] for r in rs) / fr)
    for g in ANG:
        v = np.concatenate([r['rep_err'][g] for r in rs]) if rs else np.zeros(0)
        v = v[np.isfinite(v)]
        out[g] = (float(np.median(v)), float(np.percentile(v, 90))) if len(v) else (np.nan, np.nan)
    reps = [f for r in rs for f in r['fired']]
    out['reps'] = len(reps)
    out['any_all'] = float(np.mean([bool(f) for f in reps])) if reps else np.nan
    out['any_6off'] = float(np.mean([bool(set(f) - NOISY6) for f in reps])) if reps else np.nan
    return out


def keyrates(rs):
    out = {}
    for ex in EXS:
        reps = [f for r in rs if r['exercise'] == ex for f in r['fired']]
        out[ex] = dict(reps=len(reps), **{k: float(np.mean([k in f for f in reps])) for k in RULES[ex]}) if reps else {}
    return out


def lr(rs):
    tot = defaultdict(lambda: [0, 0])
    for r in rs:
        for j, (c, n) in r['lr'].items(): tot[j][0] += c; tot[j][1] += n
    return {j: c / n for j, (c, n) in tot.items()}


def boot(A, B, n=2000, seed=0):
    key = lambda r: (r['subj'], r['exercise'], r['cam'])
    a, b = {key(r): r for r in A}, {key(r): r for r in B}
    ks = sorted(set(a) & set(b)); rng = np.random.default_rng(seed)
    diff = lambda idx: {m: (stats([a[ks[i]] for i in idx])[m] if m in ('mpjpe', 'pa') else stats([a[ks[i]] for i in idx])[m][0])
                        - (stats([b[ks[i]] for i in idx])[m] if m in ('mpjpe', 'pa') else stats([b[ks[i]] for i in idx])[m][0])
                        for m in ('mpjpe', 'pa', 'knee', 'elbow', 'torso_g')}
    point = diff(range(len(ks))); sims = [diff(rng.integers(0, len(ks), len(ks))) for _ in range(n)]
    return len(ks), {m: (point[m], float(np.percentile([s[m] for s in sims], 2.5)), float(np.percentile([s[m] for s in sims], 97.5))) for m in point}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--runs', required=True); p.add_argument('--compare', default=''); p.add_argument('--out', required=True)
    a = p.parse_args()
    by = {}
    for run in a.runs.split(','):
        J = json.load(open(f'{run}/records.json'))
        for r in J['records']: by.setdefault(f"{run}/{r['var']}", []).append(r)
    res = {}
    md = ['| run/var | 영상 | MPJPE | PA | 가속도 | 무릎 (p90) | 엉덩이 | 팔꿈치 | 몸통(중력) | 무효 관절 | 불가능 각 | 무릎 뒤집힘(원출력) | 스쿼트·푸시업·로우 MPJPE | 렙 | 오경보 R-all / R-6off |',
          '|---' * 15 + '|']
    for k, rs in by.items():
        s = stats(rs); s['by_ex'] = {ex: stats([r for r in rs if r['exercise'] == ex]) for ex in EXS}
        s['keys'] = keyrates(rs); s['lr'] = lr(rs); res[k] = s
        f = lambda t: f'{t[0]:.1f} ({t[1]:.0f})'
        md.append(f"| {k} | {s['videos']} | {s['mpjpe']:.1f} | {s['pa']:.1f} | {s['accel']:.2f} | {f(s['knee'])} | {f(s['hip'])} | {f(s['elbow'])} | "
                  f"{f(s['torso_g'])} | {s['invalid']:.2%} | {s['impossible']:.3%} | {s['knee_flip']:.2%} | "
                  + '·'.join(f"{s['by_ex'][ex]['mpjpe']:.1f}" for ex in EXS) + f" | {s['reps']} | {s['any_all']:.0%} / {s['any_6off']:.0%} |")
    md += ['', '| run/var | 운동 | 렙 | 키별 정상 렙 오경보(judge_py 현재 임계값) |', '|---|---|---|---|']
    for k, s in res.items():
        for ex in EXS:
            q = s['keys'][ex]
            if q: md.append(f"| {k} | {ex} | {q['reps']} | " + ', '.join(f"{n} {q[n]:.0%}" for n in RULES[ex]) + ' |')
    md += ['', '| run | 2D 한쪽 교차(무릎·발목·팔꿈치·손목) |', '|---|---|']
    for k, s in res.items():
        md.append(f"| {k} | " + ' · '.join(f"{j} {s['lr'][j]:.2%}" for j in ('knee', 'ankle', 'elbow', 'wrist')) + ' |')
    comp = {}
    if a.compare:
        md += ['', '| A − B | 영상 | MPJPE | PA | 무릎 렙극값 | 팔꿈치 | 몸통(중력) |', '|---|---|---|---|---|---|---|']
        for c in a.compare.split(','):
            A, B = c.split(':'); n, d = boot(by[A], by[B]); comp[c] = dict(videos=n, **d)
            md.append(f'| {A} − {B} | {n} | ' + ' | '.join(f'{d[m][0]:+.2f} [{d[m][1]:+.2f}, {d[m][2]:+.2f}]' for m in ('mpjpe', 'pa', 'knee', 'elbow', 'torso_g')) + ' |')
    json.dump(dict(results=res, compare=comp), open(f'{a.out}.json', 'w'), indent=1, default=float)
    open(f'{a.out}.md', 'w').write('\n'.join(md) + '\n'); print('\n'.join(md))


if __name__ == '__main__':
    main()
