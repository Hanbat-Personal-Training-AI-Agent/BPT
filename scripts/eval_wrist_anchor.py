"""Push-up wrist floor anchor (pose_feedback/geometry/wrist_anchor.py) - docs/results/setup_constraint_prereg.md section 8.

  tune      Fit3D tuning subjects: mocap wrist motion, app-2D flying / normal frames -> r, c, T by the section 8 rules
  validate  Fit3D held-out subjects: W1 flying, W2 wrist / elbow 2D + XS 3D error, W3 judge_py rule firing, W4 moves
  ex3d      Exercise3D 2D CSVs / device logs (no ground truth used): wrists > 1 forearm from the set reference, raw vs
            anchored
Fit3D runs on Home only (bpt-home); outputs are aggregates plus a manifest.
usage: python scripts/eval_wrist_anchor.py tune --root ~/datasets/fit3d --replay ~/bpt-smpl/replay --run-dir RUN
       python scripts/eval_wrist_anchor.py validate ... --params RUN_TUNE/wrist_params.json --run-dir RUN
       python scripts/eval_wrist_anchor.py ex3d --ex3d EX3D_DIR --csv-glob 'GLOB' [--devlogs LOGS] --params P --run-dir RUN
"""
import argparse, glob, json, os, sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / 'scripts')]
from pose_feedback.geometry.wrist_anchor import DEFAULTS, WristFloorAnchor  # noqa: E402

GRID_R, GRID_C, GRID_T = (0.3, 0.4, 0.5, 0.6, 0.8, 1.0), (0.1, 0.2, 0.3, 0.4, 0.5), (10, 15, 30, 45, 60)
H36M_OF = {9: (13, 12), 10: (16, 15)}  # COCO wrist -> (H36M wrist, H36M elbow)
ELBOW = {9: 7, 10: 8}
NEVER = 10 ** 9


def simulate(K, **params):
    """Anchored COCO17 2D for the whole sequence (the app runs it from the first push-up frame) + per-frame reports."""
    a = WristFloorAnchor(**params); out = K.copy(); reps = []
    for t in range(len(K)):
        out[t], r = a.update(K[t]); reps.append(r)
    return out, reps


def set_span(d):
    return d['seg'][0][0], d['seg'][-1][1]


def fit3d(a, subjects):
    import eval_lift_app_fit3d as lf
    from pose_feedback.body.pose2d_data import project_fit3d
    a.subjects, a.exercises = subjects, ['pushup']
    seqs = lf.load_seqs(a)
    for d in seqs:
        cam = json.load(open(f"{a.root}/train/{d['subj']}/camera_parameters/{d['cam']}/{d['ex']}.json"))
        J = d['J'][d['pick']]
        d['G2'] = project_fit3d(J.reshape(-1, 3), cam).reshape(len(J), -1, 2)
        lo, hi = set_span(d); d['lo'], d['hi'] = lo, hi
        d['f'] = {w: float(np.median(np.linalg.norm(d['G2'][lo:hi, hw] - d['G2'][lo:hi, he], axis=-1))) for w, (hw, he) in H36M_OF.items()}
        d['e'] = {w: np.linalg.norm(d['K'][:, w, :2] - d['G2'][:, hw], axis=-1) / d['f'][w] for w, (hw, _) in H36M_OF.items()}
    return seqs


def held_rates(seqs, **params):
    """Pooled over set frames of both wrists: held among flying (e > 1.0) and among normal (e <= 0.5)."""
    hf, nf, hn, nn = 0, 0, 0, 0
    for d in seqs:
        _, reps = simulate(d['K'], **params)
        for w in (9, 10):
            held = np.array([r[w] == 'held' for r in reps])[d['lo']:d['hi']]; e = d['e'][w][d['lo']:d['hi']]
            hf += int((held & (e > 1.0)).sum()); nf += int((e > 1.0).sum()); hn += int((held & (e <= 0.5)).sum()); nn += int((e <= 0.5).sum())
    return dict(held_flying=hf / max(nf, 1), held_normal=hn / max(nn, 1), flying=nf, normal=nn, J=hf / max(nf, 1) - hn / max(nn, 1))


def tight_runs(P, e, radius):
    """Longest sub-runs whose points stay within radius of their median: [(length, median e)] (greedy left to right)."""
    out, s = [], 0
    while s < len(P):
        t = s + 1
        while t < len(P) and np.linalg.norm(P[s:t + 1] - np.median(P[s:t + 1], axis=0), axis=1).max() <= radius:
            t += 1
        out.append((t - s, float(np.median(e[s:t])))); s = t
    return out


def run_tune(a):
    import eval_lift_app_fit3d as lf
    seqs = fit3d(a, ['s03', 's04', 's05'])
    motion = []
    for d in seqs:
        for w, (hw, _) in H36M_OF.items():
            G = d['G2'][d['lo']:d['hi'], hw]; ref = np.median(G[:15], axis=0)
            motion.append(float(np.percentile(np.linalg.norm(G - ref, axis=-1) / d['f'][w], 99)))
    need_r = max(motion)
    grid = {f'r{r}_c0.3': held_rates(seqs, radius=r, conf=0.3, reanchor_frames=60) for r in GRID_R}
    ok = [r for r in GRID_R if r >= need_r] or [GRID_R[-1]]
    r_sel = max(ok, key=lambda r: (round(grid[f'r{r}_c0.3']['J'], 6), r))
    for c in GRID_C:
        grid.setdefault(f'r{r_sel}_c{c}', held_rates(seqs, radius=r_sel, conf=c, reanchor_frames=60))
    c_sel = max(GRID_C, key=lambda c: (round(grid[f'r{r_sel}_c{c}']['J'], 6), -c))
    runs = []  # tight out-of-radius observed runs with no re-anchoring
    for d in seqs:
        _, reps = simulate(d['K'], radius=r_sel, conf=c_sel, reanchor_frames=NEVER)
        for w in (9, 10):
            out_seen = np.array([r[w] == 'held' for r in reps]) & (d['K'][:, w, 2] >= c_sel)
            out_seen[:d['lo']] = False; out_seen[d['hi']:] = False
            idx = np.flatnonzero(out_seen)
            for grp in np.split(idx, np.flatnonzero(np.diff(idx) > 1) + 1) if len(idx) else []:
                runs += tight_runs(d['K'][grp, w, :2], d['e'][w][grp], r_sel * d['f'][w] / 2)
    fly = [n for n, me in runs if me > 1.0]
    frac = {T: (sum(n >= T for n in fly) / len(fly) if fly else 0.0) for T in GRID_T}
    t_sel = next((T for T in GRID_T if frac[T] <= 0.01), 60)
    params = dict(DEFAULTS, radius=r_sel, conf=c_sel, reanchor_frames=t_sel)
    res = dict(videos=len(seqs), wrist_motion_p99_max=need_r, wrist_motion_p99=motion, grid=grid, r=r_sel, c=c_sel,
               flying_runs=len(fly), runs=len(runs), run_frac_ge_T=frac, T=t_sel, params=params)
    out = Path(a.run_dir)
    json.dump(res, open(out / 'wrist_tune.json', 'w'), indent=1); json.dump(params, open(out / 'wrist_params.json', 'w'), indent=1)
    md = [f'조정 {len(seqs)}영상(s03–s05 푸시업, 카메라 4대). 정답 손목 이동 p99 최댓값 {need_r:.3f} 아래팔',
          '', '| r × 아래팔 | c | 날아감 중 held | 정상 중 held | J |', '|---|---|---|---|---|']
    md += [f"| {k.split('_')[0][1:]} | {k.split('_')[1][1:]} | {v['held_flying']:.1%} | {v['held_normal']:.1%} | {v['J']:.3f} |" for k, v in grid.items()]
    md += ['', f'날아감 프레임 {grid[f"r{r_sel}_c{c_sel}"]["flying"]}, 정상 {grid[f"r{r_sel}_c{c_sel}"]["normal"]}. '
           f'날아감 구간 {len(fly)}개 중 T 이상 이어진 비율: ' + ', '.join(f'{T}: {v:.1%}' for T, v in frac.items()),
           f'**선택: r = {r_sel}, c = {c_sel}, T = {t_sel}**']
    (out / 'wrist_tune.md').write_text('\n'.join(md) + '\n'); print('\n'.join(md))
    lf.write_manifest(a, [d['csv'] for d in seqs], [out / 'wrist_tune.json', out / 'wrist_params.json', out / 'wrist_tune.md'],
                      dict(rules='docs/results/setup_constraint_prereg.md section 8'))


def boot(x, n=2000, seed=0):
    x = np.asarray(x, float); rng = np.random.default_rng(seed)
    m = rng.choice(x, (n, len(x))).mean(1)
    return float(x.mean()), float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))


def run_validate(a):
    import eval_lift_app_fit3d as lf
    import eval_setup_constraint as E
    from finetune_motionagformer_fit3d import mag_input
    params = json.load(open(a.params)); r_, T_ = params['radius'], params['reanchor_frames']
    lf.CACHE['dir'] = a.cache
    seqs = fit3d(a, ['s07', 's08', 's09', 's10', 's11'])
    model, dev = E.load_model(a)
    recs, rules = [], {'raw': {}, 'anchor': {}}
    for d in seqs:
        lo, hi = d['lo'], d['hi']; K = d['K']
        A, reps = simulate(K, **params)
        rec = dict(key=lf.seq_key(d), view=d['view'])
        for w, (hw, he) in H36M_OF.items():
            ea = np.linalg.norm(A[:, w, :2] - d['G2'][:, hw], axis=-1) / d['f'][w]
            rec[f'fly_raw_{w}'] = float((d['e'][w][lo:hi] > 1.0).mean()); rec[f'fly_anchor_{w}'] = float((ea[lo:hi] > 1.0).mean())
            rec[f'err2d_raw_{w}'] = float(np.mean(d['e'][w][lo:hi] * d['f'][w])); rec[f'err2d_anchor_{w}'] = float(np.mean(ea[lo:hi] * d['f'][w]))
            rec[f'held_{w}'] = float(np.mean([rp[w] == 'held' for rp in reps[lo:hi]]))
            rec[f'elbow2d_{w}'] = float(np.mean(np.linalg.norm(K[lo:hi, ELBOW[w], :2] - d['G2'][lo:hi, he], axis=-1)))
        clean = lf.predict_rows(model, dev, d['x'], [5], lf.seq_key(d))[5]
        _, crops0 = mag_input(K); xa, crops = mag_input(A)
        changed = np.abs(xa - d['x']).max((1, 2)) > 0
        rows, n_re = E.rows_partial(model, dev, xa.astype(np.float32), changed, clean)
        # a held wrist (confidence 0.29) can leave the person crop, so the anchored input may have another crop side:
        # XS output is in crop units, d['mm'] belongs to the original crops - rescale before converting to mm
        rows = rows * (crops[:, 2] / crops0[:, 2])[:, None, None]
        rec['crop_changed'] = float((np.abs(crops - crops0).max(1) > 1e-6).mean())
        for tag, P in (('raw', clean), ('anchor', rows)):
            Em = np.linalg.norm(E.to_metres(P, d) - d['G'], axis=-1)[lo:hi] * 1000
            rec[f'err3d_{tag}_wrist'] = float(Em[:, [13, 16]].mean()); rec[f'err3d_{tag}_elbow'] = float(Em[:, [12, 15]].mean())
            Q, inv = E.v_constraints(P, 'pushup')
            for rr in E.rule_reps(Q, inv, d, K if tag == 'raw' else A):
                for k in rr['keys']:
                    c = rules[tag].setdefault(k, [0, 0]); c[1] += 1; c[0] += k in rr['fired']
        rec['recomputed_windows'] = n_re
        # W4 moved hand (left wrist): 1.5 r forearm over 10 frames at mid-set, stays; then a 0.5 r slide over 60 frames
        mid = (lo + hi) // 2; f = d['f'][9]; step = np.zeros((len(K), 2)); step[mid:mid + 10, 0] = np.linspace(0, 1.5 * r_ * f, 10); step[mid + 10:, 0] = 1.5 * r_ * f
        Km = K.copy(); Km[:, 9, :2] += step
        _, rm = simulate(Km, **params)
        ev = [t for t in range(mid, len(K)) if rm[t][9] == 'reanchored']
        rec['w4_reanchor_delay'] = (ev[0] - (mid + 10)) if ev else None
        slide = np.zeros((len(K), 2)); s0 = max(lo, mid - 90); slide[s0:s0 + 60, 0] = np.linspace(0, 0.5 * r_ * f, 60); slide[s0 + 60:, 0] = 0.5 * r_ * f
        Ks = K.copy(); Ks[:, 9, :2] += slide
        _, rs = simulate(Ks, **params)
        rec['w4_slide_extra_held'] = int(sum(rs[t][9] == 'held' for t in range(s0, s0 + 90)) - sum(reps[t][9] == 'held' for t in range(s0, s0 + 90)))
        recs.append(rec); print(rec['key'], {k: round(v, 3) if isinstance(v, float) else v for k, v in rec.items() if k != 'key'}, flush=True)
    summ = {}
    for name, f_ in (('W1 fly (anchor - raw)', lambda r: (r['fly_anchor_9'] + r['fly_anchor_10'] - r['fly_raw_9'] - r['fly_raw_10']) / 2),
                     ('wrist 2D px (anchor - raw)', lambda r: (r['err2d_anchor_9'] + r['err2d_anchor_10'] - r['err2d_raw_9'] - r['err2d_raw_10']) / 2),
                     ('wrist 3D mm (anchor - raw)', lambda r: r['err3d_anchor_wrist'] - r['err3d_raw_wrist']),
                     ('elbow 3D mm (anchor - raw)', lambda r: r['err3d_anchor_elbow'] - r['err3d_raw_elbow'])):
        summ[name] = boot([f_(r) for r in recs])
    base = {'wrist 2D px (anchor - raw)': np.mean([(r['err2d_raw_9'] + r['err2d_raw_10']) / 2 for r in recs]),
            'wrist 3D mm (anchor - raw)': np.mean([r['err3d_raw_wrist'] for r in recs]), 'elbow 3D mm (anchor - raw)': np.mean([r['err3d_raw_elbow'] for r in recs])}
    rate = {tag: {k: v[0] / v[1] for k, v in rules[tag].items() if v[1]} for tag in rules}
    dr = {k: rate['anchor'].get(k, 0) - rate['raw'][k] for k in rate['raw']}
    w4 = [r['w4_reanchor_delay'] for r in recs]
    verdict = dict(
        W1=summ['W1 fly (anchor - raw)'][2] < 0,
        W2=all(summ[k][2] <= 0.02 * base[k] for k in base),
        W3=max((abs(v) for v in dr.values()), default=0) <= 0.02,
        W4=all(x is not None and x <= T_ for x in w4) and all(r['w4_slide_extra_held'] <= 0 for r in recs))
    out = Path(a.run_dir)
    json.dump(dict(params=params, recs=recs, summary=summ, base=base, rule_rate=rate, rule_diff=dr, verdict=verdict), open(out / 'wrist_validate.json', 'w'), indent=1)
    md = [f'검증 {len(recs)}영상(s07–s11 푸시업, 카메라 4대), 매개변수 {json.dumps(params)}', '',
          '| 항목 | 평균 차이 | 95% CI | 기준값(raw) |', '|---|---|---|---|']
    md += [f'| {k} | {m:+.4f} | {l:+.4f} – {h:+.4f} | {base.get(k, float("nan")):.2f} |' for k, (m, l, h) in summ.items()]
    md += ['', f"날아감 비율 raw {np.mean([(r['fly_raw_9'] + r['fly_raw_10']) / 2 for r in recs]):.2%} → anchor {np.mean([(r['fly_anchor_9'] + r['fly_anchor_10']) / 2 for r in recs]):.2%}, "
           f"held {np.mean([(r['held_9'] + r['held_10']) / 2 for r in recs]):.2%}",
           f'규칙 발동률 차이 최대 {max((abs(v) for v in dr.values()), default=0):.1%}p: ' + ', '.join(f'{k} {rate["raw"][k]:.0%}→{rate["anchor"].get(k, 0):.0%}' for k in sorted(dr, key=lambda k: -abs(dr[k]))[:6]),
           f'W4 다시 잡기 지연(이동 끝 뒤 프레임): {w4}; 미끄럼 중 늘어난 held 최대 {max(r["w4_slide_extra_held"] for r in recs)}',
           f'**판정(제안): {verdict}**']
    (out / 'wrist_validate.md').write_text('\n'.join(md) + '\n'); print('\n'.join(md))
    lf.write_manifest(a, [d['csv'] for d in seqs] + [a.params, a.checkpoint], [out / 'wrist_validate.json', out / 'wrist_validate.md'],
                      dict(rules='docs/results/setup_constraint_prereg.md section 8', cache=a.cache))


def run_ex3d(a):
    """No ground truth: a push-up wrist stays on the floor, so the set reference is the median observed wrist (conf >=
    0.5) over the set and the forearm the median observed elbow-wrist; 'flying' = more than 1 forearm away."""
    sys.path.insert(0, str(ROOT / 'scripts'))
    from eval_3d_angles import read_csv
    params = json.load(open(a.params)) if a.params else dict(DEFAULTS)
    gt = json.load(open(f'{a.ex3d}/gt.json')); rows = []

    def measure(name, K, span, extra=None):
        A, reps = simulate(K, **params); lo, hi = span; rec = dict(name=name, **(extra or {}))
        for w in (9, 10):
            good = K[lo:hi, w, 2] >= 0.5; fe = good & (K[lo:hi, ELBOW[w], 2] >= 0.5)
            if good.sum() < 10 or fe.sum() < 10: continue
            ref = np.median(K[lo:hi][good, w, :2], axis=0); f = np.median(np.linalg.norm(K[lo:hi, w, :2] - K[lo:hi, ELBOW[w], :2], axis=-1)[fe])
            for tag, X in (('raw', K), ('anchor', A)):
                dd = np.linalg.norm(X[lo:hi, w, :2] - ref, axis=-1) / f
                rec[f'{tag}_{w}'] = dict(gt05=float((dd > 0.5).mean()), gt10=float((dd > 1.0).mean()), max=float(dd.max()))
            rec[f'held_{w}'] = float(np.mean([r[w] == 'held' for r in reps[lo:hi]]))
        rows.append(rec)
        print(name, {k: v for k, v in rec.items() if k != 'name'}, flush=True)

    for csv in sorted(glob.glob(a.csv_glob)):
        pc = Path(csv); seq = pc.parent.name if pc.parent.name in gt else '_'.join(pc.name.split('_')[:2])
        name = pc.name if pc.name.startswith(seq) else f'{seq}_{pc.name}'
        if seq not in gt or 'pushup' not in seq: continue
        rf = gt[seq]['rep_frames']; half = int(np.median(np.diff(rf)) / 2)
        if name.endswith('_halpe26.csv'):
            R = [l.rstrip('\n').split(',') for l in open(csv)][1:]
            K = np.array([[float(x) for x in r[4:4 + 26 * 3]] for r in R]).reshape(len(R), 26, 3)[:, :17]
        else:
            K = read_csv(csv)
        measure(name, K, (max(0, rf[0] - half), min(len(K), rf[-1] + half)), dict(src='csv'))
    for log in sorted(glob.glob(a.devlogs)) if a.devlogs else []:
        J = [json.loads(l) for l in open(log) if l.strip()]
        jud = [d for d in J if d['type'] == 'judged']; reps = [d for d in J if d['type'] == 'rep']
        if not reps: continue
        K = np.array([np.array(d['kp'], float).reshape(17, 3) for d in jud]); X = K.copy()
        for t, d in enumerate(jud):  # the XS / overlay input: MediaPipe wrists where they replaced RTMPose
            for side, c, flag in (('left', 9, d['wrists'][0]), ('right', 10, d['wrists'][1])):
                h = d.get('hands', {}).get(side)
                if flag and h is not None: X[t, c, :2] = h
        measure(Path(log).name, X, (reps[0]['start_frame'], reps[-1]['end_frame'] + 1), dict(src='device'))
    out = Path(a.run_dir); json.dump(dict(params=params, rows=rows), open(out / 'wrist_ex3d.json', 'w'), indent=1)
    md = ['| 입력 | 손목 | > 0.5 아래팔 raw → anchor | > 1.0 raw → anchor | 최대 raw → anchor | held |', '|---|---|---|---|---|---|']
    for r in rows:
        for w in (9, 10):
            if f'raw_{w}' in r:
                md.append(f"| {r['name']} | {'L' if w == 9 else 'R'} | {r[f'raw_{w}']['gt05']:.1%} → {r[f'anchor_{w}']['gt05']:.1%} | "
                          f"{r[f'raw_{w}']['gt10']:.1%} → {r[f'anchor_{w}']['gt10']:.1%} | {r[f'raw_{w}']['max']:.2f} → {r[f'anchor_{w}']['max']:.2f} | {r[f'held_{w}']:.1%} |")
    (out / 'wrist_ex3d.md').write_text('\n'.join(md) + '\n'); print('\n'.join(md))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['tune', 'validate', 'ex3d'])
    p.add_argument('--root'); p.add_argument('--replay'); p.add_argument('--run-dir', required=True); p.add_argument('--params')
    p.add_argument('--ex3d'); p.add_argument('--csv-glob'); p.add_argument('--devlogs')
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer')); p.add_argument('--checkpoint')
    p.add_argument('--threads', type=int, default=4); p.add_argument('--device', choices=['cpu', 'mps'], default='cpu')
    p.add_argument('--cache', default=os.path.expanduser('~/bpt-runs/setup-constraint/_cache_xs'))
    a = p.parse_args()
    a.checkpoint = a.checkpoint or f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr'
    os.makedirs(a.run_dir, exist_ok=True)
    {'tune': run_tune, 'validate': run_validate, 'ex3d': run_ex3d}[a.cmd](a)


if __name__ == '__main__':
    main()
