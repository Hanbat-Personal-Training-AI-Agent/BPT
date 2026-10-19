"""Exercise3D table [E3D, pseudo-GT, unverified, not independent]: per acquisition config (expA / cur / lb / s15 / det),
view (side <=40, oblique 40-75, front >=75) and input, P-MPJPE (% torso) and rep-extreme angle error median (p90);
paired ha - coco difference with a cluster bootstrap over sequences (only 13 sequences -> wide CIs).

usage: ex3d_table.py ex3d.json [ex3d_ftd.json] > table.md
"""
import json, sys
import numpy as np

LIMB = {'squat': ('knee', 'hip', 'torso_g'), 'pushup': ('elbow', 'hip', 'torso_g'), 'barbell_row': ('elbow', 'hip', 'torso_g')}
VIEWS = [('측면 ≤40°', 0, 40), ('사선 40–75°', 40, 75), ('정면 ≥75°', 75, 181)]


def fmt(x): return f'{np.median(x):.1f} ({np.percentile(x, 90):.1f})' if len(x) else '-'


def main():
    R = json.load(open(sys.argv[1])); P = print
    for extra in sys.argv[2:]:  # merge other lifters' results (same cfg / seq / cam)
        idx = {(r['cfg'], r['seq'], r['cam']): r for r in R}
        for e in json.load(open(extra)): idx[(e['cfg'], e['seq'], e['cam'])]['m3d'].update(e['m3d'])
    for norm in ('crop', 'screen'):
        P(f'### 정규화 {norm}, 원래 XS, raw\n')
        P('| 설정 | 시점 | 영상 | 입력 | P-MPJPE (% 몸통) | ' + ' | '.join(f'{g} 렙 극값' for g in ('knee', 'hip', 'elbow', 'torso_g')) + ' |')
        P('|---|---|---|---|---|---|---|---|---|')
        for cfg in dict.fromkeys(r['cfg'] for r in R):
            for vn, lo, hi in VIEWS:
                rs = [r for r in R if r['cfg'] == cfg and lo <= r['view_deg'] < hi]
                if not rs: continue
                for k in [k for k in rs[0]['m3d'] if k.endswith(f'|{norm}|raw')]:
                    i = k.rsplit('|', 2)[0]
                    if any(k not in r['m3d'] for r in rs): continue
                    pa = np.mean([r['m3d'][k]['pa'] for r in rs])
                    cells = [fmt(np.concatenate([r['m3d'][k]['ang'][g]['rep'] for r in rs if g in LIMB[r['exercise']]] or [[]])) for g in ('knee', 'hip', 'elbow', 'torso_g')]
                    P(f'| {cfg} | {vn} | {len(rs)} | {i} | {pa:.1f} | ' + ' | '.join(cells) + ' |')
        P('')
        P(f'#### 쌍 차이 ha − coco (정규화 {norm}): P-MPJPE %p, 95% 시퀀스 묶음 부트스트랩\n')
        P('| 설정 | 시점 | 차이 | 95% CI |'); P('|---|---|---|---|')
        rng = np.random.default_rng(0)
        for cfg in dict.fromkeys(r['cfg'] for r in R):
            for vn, lo, hi in VIEWS:
                rs = [r for r in R if r['cfg'] == cfg and lo <= r['view_deg'] < hi]
                if not rs: continue
                if any(f'ha|{norm}|raw' not in r['m3d'] for r in rs): continue
                seqs = sorted({r['seq'] for r in rs}); by = {s: [r['m3d'][f'ha|{norm}|raw']['pa'] - r['m3d'][f'coco|{norm}|raw']['pa'] for r in rs if r['seq'] == s] for s in seqs}
                est = np.mean([v for s in seqs for v in by[s]])
                bs = [np.mean([v for s in rng.choice(seqs, len(seqs)) for v in by[s]]) for _ in range(2000)]
                P(f'| {cfg} | {vn} | {est:+.2f} | [{np.percentile(bs, 2.5):+.2f}, {np.percentile(bs, 97.5):+.2f}] |')
        P('')


if __name__ == '__main__':
    main()
