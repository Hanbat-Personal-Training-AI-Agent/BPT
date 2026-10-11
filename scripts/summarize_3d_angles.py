"""Tables from eval_3d_angles.py JSON: median / p90 absolute angle error (deg), 2D vs 3D, by view-angle bucket,
per subject group (tuning vs held-out), and the knee-hinge "bad 3D" check.
usage: summarize_3d_angles.py RESULT.json [RESULT2.json ...]"""
import json, sys
import numpy as np

BUCKETS = [(0, 20), (20, 40), (40, 60), (60, 75), (75, 91)]
LIMB = {'squat': ['knee', 'torso'], 'pushup': ['elbow', 'torso'], 'barbellrow': ['torso', 'elbow'],
        'barbell_row': ['torso', 'elbow'], 'diamond_pushup': ['elbow', 'torso'], 'barbell_dead_row': ['torso', 'elbow']}
# Exercise3D has no subject ids; split by person as in docs/decisions.md D-B-01 (P1 = tuning, P2/P3 = held-out).
EX3D_HELD_OUT = {'squat_0002', 'barbellrow_0001', 'barbellrow_0003'}
BIG_ERR = 20  # deg: a 3D knee this far off is "bad 3D" for the hinge check


def group(r):
    if r['source'] == 'ex3d':
        return '검증(P2·P3)' if r['subject'] in EX3D_HELD_OUT else '튜닝(P1)'
    return f"Fit3D {r['subject']}"


def q(a):
    return f'{np.median(a):.1f} / {np.percentile(a, 90):.1f}' if len(a) else '-'


def table(rows, kind):
    k2, k3 = ('frame_err_2d', 'frame_err_3d') if kind == '프레임' else ('rep_err_2d', 'rep_err_3d')
    out = [f'| 묶음 | 운동 | 각도 | 시점 | 영상 수 | 2D {kind} 오차 중앙/p90 | 3D {kind} 오차 중앙/p90 |', '|---|---|---|---|---|---|---|']
    for g in sorted(dict.fromkeys(group(r) for r in rows)):
        for ex in dict.fromkeys(r['exercise'] for r in rows):
            for limb in LIMB.get(ex, ['knee', 'torso']):
                for lo, hi in BUCKETS:
                    rs = [r for r in rows if group(r) == g and r['exercise'] == ex and lo <= r['view_deg'] < hi]
                    if not rs: continue
                    e2 = np.concatenate([r[limb][k2] for r in rs]); e3 = np.concatenate([r[limb][k3] for r in rs])
                    out.append(f'| {g} | {ex} | {limb} | {lo}–{90 if hi == 91 else hi}° | {len(rs)} | {q(e2)} | {q(e3)} |')
    return '\n'.join(out)


def hinge(rows):
    out = [f'| 묶음 | 운동 | 프레임 | 3D 불량 비율 | 3D 무릎 오차>{BIG_ERR}° 중 잡은 비율 | 잡은 프레임 중 실제 오차>{BIG_ERR}° | 정답 자체 과신전 프레임 |',
           '|---|---|---|---|---|---|---|']
    for g in sorted(dict.fromkeys(group(r) for r in rows)):
        for ex in dict.fromkeys(r['exercise'] for r in rows):
            rs = [r for r in rows if group(r) == g and r['exercise'] == ex and 'bad_mask' in r]
            if not rs: continue
            bad = np.concatenate([np.array(r['bad_mask'], bool) for r in rs])
            err = np.concatenate([np.array(r['knee']['frame_err_3d_all']) for r in rs])
            big = err > BIG_ERR
            rec = f'{(bad & big).sum() / big.sum():.0%} ({big.sum()})' if big.any() else '-'
            prec = f'{(bad & big).sum() / bad.sum():.0%}' if bad.any() else '-'
            out.append(f"| {g} | {ex} | {len(bad)} | {bad.mean():.1%} | {rec} | {prec} | {sum(r['ref_bad_frames'] for r in rs)} |")
    return '\n'.join(out)


if __name__ == '__main__':
    rows = [r for f in sys.argv[1:] for r in json.load(open(f))]
    print(table(rows, '프레임')); print(); print(table(rows, '렙 극값')); print(); print(hinge(rows))
