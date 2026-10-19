"""lift-compare tables from lift_eval.py JSON (aggregates only). Rule: docs/results/lift_compare_plan.md section 5.

usage: table.py RESULT.json [--group heldout] [--boot 2000] > tables.md
"""
import argparse, json
import numpy as np

H36M_NAMES = ['pelvis', 'r_hip', 'r_knee', 'r_ankle', 'l_hip', 'l_knee', 'l_ankle', 'spine', 'thorax', 'neck', 'head',
              'l_sh', 'l_el', 'l_wr', 'r_sh', 'r_el', 'r_wr']
LIMB = {'squat': ('knee', 'hip', 'torso_g'), 'pushup': ('elbow', 'hip', 'torso_g'), 'barbell_row': ('elbow', 'hip', 'torso_g')}
ALL_ANG = ('knee', 'hip', 'elbow', 'torso_g')
THR = {'mpjpe': 2, 'pa': 2, 'accel': 0.5, 'ang': 1}
VIEWS = [('측면 ≤40°', 0, 40), ('사선 40–75°', 40, 75), ('정면 ≥75°', 75, 181)]


def pooled(rows, key, metric):
    n = np.array([r['frames'] for r in rows]); v = np.array([r['m3d'][key][metric] for r in rows])
    return float((n * v).sum() / n.sum())


def reps(rows, key, ang, kind='rep'):
    return np.concatenate([r['m3d'][key]['ang'][ang][kind] for r in rows]) if rows else np.array([])


def boot_diff(rows, a, b, fn, B, seed=0):
    """fn(rows, key) -> scalar. Cluster bootstrap over subjects of fn(.., b) - fn(.., a)."""
    subs = sorted({r['subject'] for r in rows}); by = {s: [r for r in rows if r['subject'] == s] for s in subs}
    rng = np.random.default_rng(seed); est = fn(rows, b) - fn(rows, a); bs = []
    for _ in range(B):
        rr = [r for s in rng.choice(subs, len(subs)) for r in by[s]]
        bs.append(fn(rr, b) - fn(rr, a))
    lo, hi = np.percentile(bs, [2.5, 97.5])
    per = [fn(by[s], b) - fn(by[s], a) for s in subs]
    return est, lo, hi, per


def verdict(est, lo, hi, thr):
    if lo > 0 and est >= thr: return '**나빠짐**'
    if hi < 0 and -est >= thr: return '**좋아짐**'
    return '구별 불가'


def fmt_rep(x): return f'{np.median(x):.1f} ({np.percentile(x, 90):.1f})' if len(x) else '-'


def main():
    p = argparse.ArgumentParser(); p.add_argument('json'); p.add_argument('--group', default='heldout')
    p.add_argument('--boot', type=int, default=2000); p.add_argument('--norms', default='crop,screen')
    a = p.parse_args()
    allrows = json.load(open(a.json)); rows = [r for r in allrows if r['group'] == a.group]
    bad = [r for r in rows if r['box_ok'] < 0.99 or r['nodet'] > 0.01]
    rows = [r for r in rows if r not in bad]
    P = print
    P(f"## 묶음 {a.group}: 영상 {len(rows)}개 (상자 검증 탈락 {len(bad)}: {[(r['subject'], r['cam'], r['exercise'], round(r['box_ok'], 3)) for r in bad]})")
    P(f"피험자 {sorted({r['subject'] for r in rows})}, 시점각 범위 {min(r['view_deg'] for r in rows)}–{max(r['view_deg'] for r in rows)}°, "
      f"시점 분포 {[(n, sum(lo <= r['view_deg'] < hi for r in rows)) for n, lo, hi in VIEWS]}\n")
    keys = list(rows[0]['m3d'])
    for norm in a.norms.split(','):
        for con in ('raw', 'con_app', 'con_fit3d'):
            ks = [k for k in keys if k.split('|')[1] == norm and k.split('|')[2] == con]
            P(f'### 3D 전체 — 정규화 {norm}, {con}\n')
            P('| 입력 | MPJPE | P-MPJPE | 가속도 오차 | ' + ' | '.join(f'{g} 렙 극값 중앙 (p90)' for g in ALL_ANG) + ' | ' + ' | '.join(f'{g} ROM' for g in ALL_ANG) + (' | 3D 불량 비율' if con != 'raw' else '') + ' |')
            P('|---|---|---|---|' + '---|' * (2 * len(ALL_ANG)) + ('---|' if con != 'raw' else ''))
            for k in ks:
                angrows = lambda g: [r for r in rows if g in LIMB[r['exercise']]]
                P(f"| {k.split('|')[0]} | {pooled(rows, k, 'mpjpe'):.1f} | {pooled(rows, k, 'pa'):.1f} | {pooled(rows, k, 'accel'):.2f} | "
                  + ' | '.join(fmt_rep(reps(angrows(g), k, g)) for g in ALL_ANG) + ' | '
                  + ' | '.join(fmt_rep(reps(angrows(g), k, g, 'rom')) for g in ALL_ANG)
                  + (f" | {np.mean([r['m3d'][k]['bad_rate'] for r in rows]):.3f}" if con != 'raw' else '') + ' |')
            P('')
        # paired comparisons vs coco (raw)
        P(f'### 쌍 비교 (정규화 {norm}, raw): 차이 = 변형 − coco, 95% 피험자 묶음 부트스트랩 CI, 피험자별 차이\n')
        P('| 변형 | 지표 | 차이 | 95% CI | 판정 | 피험자별 |'); P('|---|---|---|---|---|---|')
        base = f'coco|{norm}|raw'
        for v in ('ha', 'hb', 'coco_mp', 'ha_mp'):
            k = f'{v}|{norm}|raw'
            if k not in keys: continue
            b0 = base if v != 'ha_mp' else f'ha|{norm}|raw'
            for met in ('mpjpe', 'pa', 'accel'):
                est, lo, hi, per = boot_diff(rows, b0, k, lambda rr, kk: pooled(rr, kk, met), a.boot)
                P(f"| {v} vs {b0.split('|')[0]} | {met} | {est:+.2f} | [{lo:+.2f}, {hi:+.2f}] | {verdict(est, lo, hi, THR[met])} | {' '.join(f'{x:+.1f}' for x in per)} |")
            for g in ALL_ANG:
                rr0 = [r for r in rows if g in LIMB[r['exercise']]]
                est, lo, hi, per = boot_diff(rr0, b0, k, lambda rr, kk: float(np.mean(reps(rr, kk, g))), a.boot)
                P(f"| {v} vs {b0.split('|')[0]} | {g} 렙 극값 평균 | {est:+.2f} | [{lo:+.2f}, {hi:+.2f}] | {verdict(est, lo, hi, THR['ang'])} | {' '.join(f'{x:+.1f}' for x in per)} |")
        P('')
        # by exercise and view
        P(f'### 운동·시점별 (정규화 {norm}, raw): MPJPE / P-MPJPE, 각도 렙 극값 중앙(p90)\n')
        inps = [k.split('|')[0] for k in keys if k.endswith(f'|{norm}|raw')]
        P('| 운동 | 시점 | 영상 | ' + ' | '.join(inps) + ' |'); P('|---|---|---|' + '---|' * len(inps))
        for ex in LIMB:
            for vn, lo, hi in VIEWS:
                rs = [r for r in rows if r['exercise'] == ex and lo <= r['view_deg'] < hi]
                if not rs: continue
                cells = []
                for i in inps:
                    k = f'{i}|{norm}|raw'
                    cells.append(f"{pooled(rs, k, 'mpjpe'):.0f} / {pooled(rs, k, 'pa'):.0f}; " + ', '.join(f'{g} {fmt_rep(reps(rs, k, g))}' for g in LIMB[ex]))
                P(f'| {ex} | {vn} | {len(rs)} | ' + ' | '.join(cells) + ' |')
        P('')
        P(f'### 관절별 3D 위치 오차 (mm, 정규화 {norm}, raw, 루트 기준 / P-정렬 후)\n')
        P('| 입력 | ' + ' | '.join(H36M_NAMES[1:]) + ' |'); P('|---|' + '---|' * 16)
        for i in inps:
            k = f'{i}|{norm}|raw'; n = np.array([r['frames'] for r in rows])
            j = (n[:, None] * np.array([r['m3d'][k]['joint'] for r in rows])).sum(0) / n.sum()
            jp = (n[:, None] * np.array([r['m3d'][k]['joint_pa'] for r in rows])).sum(0) / n.sum()
            P(f'| {i} | ' + ' | '.join(f'{x:.0f}/{y:.0f}' for x, y in zip(j[1:], jp[1:])) + ' |')
        P('')
        P(f'### 손목 묶음 (정규화 {norm}, raw): 3D 손목·팔꿈치 오차(mm), 팔꿈치 렙 극값·ROM, 손목 가속도 오차\n')
        P('| 운동 | 입력 | 손목 L/R | 팔꿈치 L/R | 팔꿈치 렙 극값 | 팔꿈치 ROM | 손목 가속도 L/R | MediaPipe 교체율 L/R |'); P('|---|---|---|---|---|---|---|---|')
        for ex in LIMB:
            rs = [r for r in rows if r['exercise'] == ex]; n = np.array([r['frames'] for r in rs])
            for i in ('coco', 'coco_mp', 'ha', 'ha_mp'):
                k = f'{i}|{norm}|raw'
                if k not in keys: continue
                j = (n[:, None] * np.array([r['m3d'][k]['joint'] for r in rs])).sum(0) / n.sum()
                ja = (n[:, None] * np.array([r['m3d'][k]['joint_accel'] for r in rs])).sum(0) / n.sum()
                repl = np.mean([r['mp_replaced']['coco' if i.startswith('coco') else 'halpe'] for r in rs], 0) if i.endswith('_mp') else None
                P(f"| {ex} | {i} | {j[13]:.0f}/{j[16]:.0f} | {j[12]:.0f}/{j[15]:.0f} | {fmt_rep(reps(rs, k, 'elbow'))} | {fmt_rep(reps(rs, k, 'elbow', 'rom'))} | "
                  f"{ja[13]:.2f}/{ja[16]:.2f} | {'-' if repl is None else f'{repl[0]:.2f}/{repl[1]:.2f}'} |")
        P('')
    # 2D
    P('### 2D (투영 모캡 대비, H36M17로 옮긴 입력): 오차 ÷ 사람 상자 긴 변, PCK@0.05, 떨림(px/프레임²), 끊김(신뢰도<0.3)\n')
    J2 = [('팔꿈치', (12, 15)), ('손목', (13, 16)), ('무릎', (2, 5)), ('발목', (3, 6)), ('어깨(근사)', (11, 14))]
    m2 = list(rows[0]['m2d'])
    P('| 입력 | ' + ' | '.join(f'{n} 오차 / PCK / 떨림 / 끊김' for n, _ in J2) + ' | 엉덩이 위 치우침(몸통 길이) | 골반·흉곽 위 치우침 |'); P('|---|' + '---|' * (len(J2) + 2))
    for m in m2:
        def avg(f, idx): return float(np.mean([np.mean([r['m2d'][m][f][i] for i in idx]) for r in rows]))
        P(f'| {m} | ' + ' | '.join(f"{avg('err', ix):.4f} / {avg('pck', ix):.3f} / {avg('jitter_px', ix):.2f} / {avg('drop', ix):.3f}" for _, ix in J2)
          + f" | {avg('up_off', (1, 4)):+.3f} | {avg('up_off', (0,)):+.3f} / {avg('up_off', (8,)):+.3f} |")
    P('')
    P('### 입력 분포: 신뢰도 중앙값 (p10), 2D 뼈 길이 비(입력 ÷ 투영 모캡) 중앙값\n')
    segs = list(rows[0]['m2d']['coco']['bone_ratio'])
    P('| 입력 | 팔다리 신뢰도 | 엉덩이 신뢰도 | 골반 신뢰도 | 흉곽 신뢰도 | ' + ' | '.join(segs) + ' |'); P('|---|---|---|---|---|' + '---|' * len(segs))
    for m in m2:
        c = lambda f, idx: float(np.mean([np.mean([r['m2d'][m][f][i] for i in idx]) for r in rows]))
        limbs = (2, 3, 5, 6, 12, 13, 15, 16)
        P(f"| {m} | {c('conf_med', limbs):.3f} ({c('conf_p10', limbs):.3f}) | {c('conf_med', (1, 4)):.3f} ({c('conf_p10', (1, 4)):.3f}) | "
          f"{c('conf_med', (0,)):.3f} | {c('conf_med', (8,)):.3f} | " + ' | '.join(f"{np.median([r['m2d'][m]['bone_ratio'][s] for r in rows]):.3f}" for s in segs) + ' |')
    P('')
    P('### XS 입력 공간에서 사람 키(정규화 후 y 범위 중앙값)\n')
    sk = list(rows[0]['scale_in']); P('| 입력|정규화 | 값 |'); P('|---|---|')
    for k in sk: P(f"| {k} | {np.median([r['scale_in'][k] for r in rows]):.3f} |")
    P('')
    P('### Halpe26 고유 관절 vs 모캡 (오차 ÷ 상자, 위 치우침 ÷ 몸통 길이)\n')
    P('| 관절 | 오차 | 위 치우침 |'); P('|---|---|---|')
    for n in rows[0]['halpe_extra']:
        P(f"| {n} | {np.mean([r['halpe_extra'][n]['err'] for r in rows]):.4f} | {np.median([r['halpe_extra'][n]['up_off'] for r in rows]):+.3f} |")


if __name__ == '__main__':
    main()
