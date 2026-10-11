"""Tables from eval_3d_angles.py JSON: median / p90 absolute angle error (deg), 2D vs 3D, by view-angle bucket.
usage: summarize_3d_angles.py RESULT.json [RESULT2.json ...]"""
import json, sys
import numpy as np

BUCKETS = [(0, 20), (20, 40), (40, 60), (60, 75), (75, 91)]
LIMB = {'squat': ['knee', 'torso'], 'pushup': ['elbow', 'torso'], 'barbellrow': ['torso', 'elbow'],
        'barbell_row': ['torso', 'elbow'], 'diamond_pushup': ['elbow', 'torso'], 'barbell_dead_row': ['torso', 'elbow']}


def q(a):
    return f'{np.median(a):.1f} / {np.percentile(a, 90):.1f}' if len(a) else '-'


def table(rows, kind):
    out = [f'| 운동 | 각도 | 시점 | 영상 수 | 2D {kind} 중앙/p90 | 3D {kind} 중앙/p90 | 3D 불량 프레임 |', '|---|---|---|---|---|---|---|']
    for ex in dict.fromkeys(r['exercise'] for r in rows):
        for limb in LIMB.get(ex, ['knee', 'torso']):
            for lo, hi in BUCKETS:
                rs = [r for r in rows if r['exercise'] == ex and lo <= r['view_deg'] < hi]
                if not rs: continue
                k2, k3 = ('frame_err_2d', 'frame_err_3d') if kind == '프레임' else ('rep_err_2d', 'rep_err_3d')
                e2 = np.concatenate([r[limb][k2] for r in rs]); e3 = np.concatenate([r[limb][k3] for r in rs])
                bad = sum(r['bad3d_frames'] for r in rs) / max(1, sum(r['frames'] for r in rs))
                out.append(f'| {ex} | {limb} | {lo}–{hi - 1 if hi == 91 else hi}° | {len(rs)} | {q(e2)} | {q(e3)} | {bad:.1%} |')
    return '\n'.join(out)


if __name__ == '__main__':
    rows = [r for f in sys.argv[1:] for r in json.load(open(f))]
    print(table(rows, '프레임')); print(); print(table(rows, '렙 극값'))
