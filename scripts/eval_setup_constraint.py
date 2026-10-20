"""ai/setup-constraint studies on Fit3D (Home only; Fit3D never leaves Home, aggregates only in git).

Pre-registration: docs/results/setup_constraint_prereg.md (comparison rules fixed before validation results).
Reuses eval_lift_app_fit3d (Fit3D loading, app 2D -> XS input, mocap target in crop units, mm scale, metrics).

  gt-relations   E0  mocap: per-subject body dimensions (oracle) and how stable each candidate relation is per exercise
                     (feet / hands / hand-foot vectors, torso-frame wrists, world contact points), setup-phase ratios
usage: eval_setup_constraint.py gt-relations --root ~/datasets/fit3d --run-dir RUN [--subjects s03,s04,s05]
"""
import argparse, json, os, sys, time
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path[:0] = [str(REPO), str(HERE)]
from eval_3d_angles import load_joints  # noqa: E402
import eval_lift_app_fit3d as lf  # noqa: E402
from eval_lift_app_fit3d import CACHE, EXERCISES, load_seqs, predict_rows, seq_key, st, write_manifest  # noqa: E402

FPS50 = 50
# H36M17
PEL, RHIP, RKNE, RANK, LHIP, LKNE, LANK, SPI, THO, NEC, HEA, LSHO, LELB, LWRI, RSHO, RELB, RWRI = range(17)
RELATIONS = {  # name -> (a, b): vector P[b] - P[a]
    'feet': (RANK, LANK), 'hands': (RWRI, LWRI), 'hand_foot_r': (RANK, RWRI), 'hand_foot_l': (LANK, LWRI),
}


def torso_frame(P):
    """[N,3,3] rows = torso axes (x: right->left shoulder, y: pelvis->thorax orthogonalised, z = x cross y)."""
    x = P[:, LSHO] - P[:, RSHO]; x /= np.linalg.norm(x, axis=-1, keepdims=True).clip(1e-9)
    y = P[:, THO] - P[:, PEL]; y -= x * (x * y).sum(-1, keepdims=True); y /= np.linalg.norm(y, axis=-1, keepdims=True).clip(1e-9)
    return np.stack([x, y, np.cross(x, y)], 1)


def body_dims(P):
    """Per-frame body dimensions (same units as P): widths between joint centres and limb lengths (L/R mean)."""
    n = lambda a, b: np.linalg.norm(P[:, a] - P[:, b], axis=-1)
    return dict(hip_width=n(LHIP, RHIP), shoulder_width=n(LSHO, RSHO), thigh=(n(RHIP, RKNE) + n(LHIP, LKNE)) / 2,
                shin=(n(RKNE, RANK) + n(LKNE, LANK)) / 2, upper_arm=(n(RSHO, RELB) + n(LSHO, LELB)) / 2,
                forearm=(n(RELB, RWRI) + n(LELB, LWRI)) / 2, torso=n(PEL, THO))


def setup_ratios(P, ex, up):
    """Scale-free setup quantities per frame (any unit, any frame). up = unit up vector in P's frame."""
    d = body_dims(P); n = lambda a, b: np.linalg.norm(P[:, a] - P[:, b], axis=-1)
    r = dict(ankle_over_hip=n(LANK, RANK) / d['hip_width'], ankle_over_shoulder=n(LANK, RANK) / d['shoulder_width'])
    if ex in ('pushup', 'barbell_row'):
        r['wrist_over_shoulder'] = n(LWRI, RWRI) / d['shoulder_width']
    trunk = P[:, THO] - P[:, PEL]
    r['torso_incline_deg'] = np.degrees(np.arccos(np.clip((trunk @ up) / np.linalg.norm(trunk, axis=-1).clip(1e-9), -1, 1)))
    return r


def run_gt_relations(a):
    ann_all, recs, dims, inputs = {}, [], {}, []
    up = np.array([0., 0., 1.])  # Fit3D world: z up
    for subj in a.subjects:
        sd = f'{a.root}/train/{subj}'
        ann_all = json.load(open(f'{sd}/rep_ann.json')); inputs.append(f'{sd}/rep_ann.json')
        per = {}
        for ex in EXERCISES:
            P = load_joints(sd, ex)
            if P is None or ex not in ann_all: continue
            inputs.append(f'{sd}/joints3d_25/{ex}.json')
            ann = ann_all[ex]; s0, s1 = ann[0], ann[-1]
            for k, v in body_dims(P).items(): per.setdefault(k, []).append(v)
            rec = dict(subj=subj, exercise=ex, setup_frames=int(s0), set_frames=int(s1 - s0))
            vecs = {k: P[:, b] - P[:, a_] for k, (a_, b) in RELATIONS.items()}
            F = torso_frame(P)
            for side, w in (('l', LWRI), ('r', RWRI)):
                vecs[f'wrist_torso_{side}'] = np.einsum('nij,nj->ni', F, P[:, w] - P[:, THO])
            for nm, j in (('ankle_world_l', LANK), ('ankle_world_r', RANK), ('wrist_world_l', LWRI), ('wrist_world_r', RWRI)):
                vecs[nm] = P[:, j]
            ref_len = float(np.median(body_dims(P[s0:s1])['hip_width']))
            for k, v in vecs.items():
                setup = np.median(v[max(0, s0 - FPS50):s0], 0) if s0 >= 10 else v[s0]
                dev = np.linalg.norm(v[s0:s1] - setup, axis=-1) * 1000  # mm from the setup value during the set
                step = np.linalg.norm(np.diff(v[s0:s1], axis=0), axis=-1) * 1000 * FPS50  # mm/s
                reps = [np.linalg.norm(v[x:y] - np.median(v[x:y], 0), axis=-1).max() * 1000 for x, y in zip(ann, ann[1:])]
                rec[k] = dict(dev_p50=float(np.median(dev)), dev_p95=float(np.percentile(dev, 95)), dev_max=float(dev.max()),
                              speed_p95=float(np.percentile(step, 95)), within_rep_max_p50=float(np.median(reps)),
                              norm_mm=float(np.median(np.linalg.norm(v[s0:s1], axis=-1)) * 1000), hip_width_mm=ref_len * 1000)
            rr = setup_ratios(P, ex, up)
            rec['setup_ratios'] = {k: float(np.median(v[max(0, s0 - FPS50):s0])) for k, v in rr.items()}
            rec['set_ratios'] = {k: dict(p5=float(np.percentile(v[s0:s1], 5)), p50=float(np.median(v[s0:s1])), p95=float(np.percentile(v[s0:s1], 95)))
                                 for k, v in rr.items()}
            recs.append(rec)
        dims[subj] = {k: round(float(np.median(np.concatenate(v))) * 1000, 1) for k, v in per.items()}
        print(subj, dims[subj], flush=True)
    names = list(RELATIONS) + ['wrist_torso_l', 'wrist_torso_r', 'ankle_world_l', 'ankle_world_r', 'wrist_world_l', 'wrist_world_r']
    summ = dict(body_dims_mm=dims, groups={})
    md = ['**피험자별 체형(모캡 골격, mm, 관절 중심 기준 = oracle)**', '', '| 피험자 | ' + ' | '.join(dims[a.subjects[0]]) + ' |',
          '|---' * (1 + len(dims[a.subjects[0]])) + '|']
    md += [f'| {s} | ' + ' | '.join(f'{v:.0f}' for v in d.values()) + ' |' for s, d in dims.items()]
    md += ['', '**관계별 안정성 (세트 동안 셋업 값에서 벗어난 거리 mm: 중앙값 / p95 / 최대; 렙 안 최대 흔들림 중앙값; 속도 p95 mm/s; 피험자 중앙값)**', '',
           '| 운동 | 관계 | 영상 | 크기 mm | 벗어남 p50 | p95 | 최대 | 렙 안 최대 | 속도 p95 |', '|---' * 9 + '|']
    for ex in EXERCISES:
        rs = [r for r in recs if r['exercise'] == ex]
        if not rs: continue
        for k in names:
            g = {q: float(np.median([r[k][q] for r in rs])) for q in rs[0][k]}
            g['max_over_subjects'] = float(max(r[k]['dev_max'] for r in rs))
            summ['groups'][f'{ex}/{k}'] = g
            md.append(f"| {ex} | {k} | {len(rs)} | {g['norm_mm']:.0f} | {g['dev_p50']:.0f} | {g['dev_p95']:.0f} | {g['dev_max']:.0f} (전체 최대 {g['max_over_subjects']:.0f}) | "
                      f"{g['within_rep_max_p50']:.0f} | {g['speed_p95']:.0f} |")
    md += ['', '**셋업(첫 렙 전 1초) 비율 — 피험자별 (모캡)**', '', '| 운동 | 피험자 | ' + ' | '.join(['ankle/hip', 'ankle/shoulder', 'wrist/shoulder', 'torso°']) + ' |', '|---' * 6 + '|']
    for r in recs:
        q = r['setup_ratios']
        md.append(f"| {r['exercise']} | {r['subj']} | {q['ankle_over_hip']:.2f} | {q['ankle_over_shoulder']:.2f} | "
                  f"{q.get('wrist_over_shoulder', float('nan')):.2f} | {q['torso_incline_deg']:.0f} |")
    summ['records'] = recs
    out_j, out_m = Path(a.run_dir) / 'gt_relations.json', Path(a.run_dir) / 'gt_relations.md'
    json.dump(summ, open(out_j, 'w'), indent=1); out_m.write_text('\n'.join(md) + '\n'); print('\n'.join(md))
    write_manifest(a, inputs, [out_j, out_m])


# ---------------------------------------------------------------- occlusion engine (E2 / E4 / E5)
L5, WIN = 5, 27
COCO2H = {5: 11, 6: 14, 7: 12, 8: 15, 9: 13, 10: 16, 11: 4, 12: 1, 13: 5, 14: 2, 15: 6, 16: 3}
MIRROR = {5: 6, 6: 5, 7: 8, 8: 7, 9: 10, 10: 9, 11: 12, 12: 11, 13: 14, 14: 13, 15: 16, 16: 15}
BONE_REF = {9: 7, 10: 8, 7: 5, 8: 6, 15: 13, 16: 14, 13: 11, 14: 12, 5: 11, 6: 12}  # px scale of a damaged joint
GROUPS = {'wrist': {'L': [9], 'R': [10]}, 'ankle': {'L': [15], 'R': [16]}, 'knee': {'L': [13], 'R': [14]},
          'shoulder': {'L': [5], 'R': [6]}, 'arm': {'L': [7, 9], 'R': [8, 10]}, 'leg': {'L': [13, 15], 'R': [14, 16]}}
DURATIONS = {'short': 10, 'long': 60, 'vlong': 150}
CORRUPTIONS = ('keep', 'drift', 'mirror', 'freeze')
RECOVERY = 30


def rng_for(*keys):
    import zlib
    return np.random.default_rng(zlib.crc32('/'.join(map(str, keys)).encode()))


def set_range(d):
    """30 fps frames from the first rep start to the last rep end (rep_ann)."""
    return d['seg'][0][0], d['seg'][-1][1]


def schedule(lo, hi, length, rng, gap=45):
    """Non-overlapping episodes [s, s + length) in [lo, hi) with a recovery window and >= gap frames between them."""
    out, t = [], lo + int(rng.integers(0, gap))
    while t + length + RECOVERY <= hi:
        out.append((t, t + length))
        t += length + gap + int(rng.integers(0, gap))
    return out


def episodes_for(d, group, duration):
    """Deterministic (seeded by sequence and condition) episode list: (s, e, coco joints, corruption, side, near)."""
    rng = rng_for(seq_key(d), group, duration); lo, hi = set_range(d); out = []
    for s, e in schedule(lo, hi, DURATIONS[duration], rng):
        side = 'L' if rng.random() < 0.5 else 'R'
        out.append((s, e, GROUPS[group][side], CORRUPTIONS[int(rng.integers(0, len(CORRUPTIONS)))], side, side == d['side']))
    return out


def corrupt(K, episodes, rng):
    """Method 1: app 2D [N,17,3] (COCO px, confidence); each episode's joints get confidence U(0.05, 0.25) and a
    position model: keep (right place, low confidence), drift (random walk <= 0.6 bone), mirror (snapped to the other
    side's joint: left/right confusion), freeze (stuck at the last value before the episode)."""
    K2 = K.copy()
    for s, e, joints, model, *_ in episodes:
        n = e - s
        for j in joints:
            Lb = float(np.median(np.linalg.norm(K[:, j, :2] - K[:, BONE_REF[j], :2], axis=-1)))
            if model == 'keep':
                xy = K[s:e, j, :2]
            elif model == 'drift':
                off = np.cumsum(rng.normal(0, 0.03 * Lb, (n, 2)), 0)
                off *= np.minimum(1.0, 0.6 * Lb / np.maximum(np.linalg.norm(off, axis=-1, keepdims=True), 1e-9))
                xy = K[s:e, j, :2] + off
            elif model == 'mirror':
                xy = K[s:e, MIRROR[j], :2] + rng.normal(0, 0.05 * Lb, (n, 2))
            else:
                xy = np.repeat(K[max(s - 1, 0), j, :2][None], n, 0)
            K2[s:e, j, :2] = xy
            K2[s:e, j, 2] = rng.uniform(0.05, 0.25, n)
    return K2


def rows_partial(model, dev, x, changed, clean, batch=64):
    """XS rows (L=5) for input x where only frames `changed` differ from the clean input: windows touching a changed
    frame are recomputed, the rest reuse `clean`. Frame t = window [t+L-26, t+L] edge-clamped, row 26-L (the app)."""
    import torch
    n = len(x); need = np.zeros(n, bool)
    for c in np.flatnonzero(changed):
        need[max(0, c - L5):min(n, c - L5 + WIN)] = True
    t = np.flatnonzero(need); out = clean.copy()
    if len(t):
        idx = np.clip(t[:, None] + L5 - (WIN - 1) + np.arange(WIN)[None], 0, n - 1)
        with torch.no_grad():
            for s0 in range(0, len(t), batch):
                out[t[s0:s0 + batch]] = model(torch.from_numpy(x[idx[s0:s0 + batch]]).to(dev))[:, WIN - 1 - L5].cpu().numpy()
    return out, int(len(t))


def occl_path(a, d, cond):
    return f"{a.cache}/occl/{cond}/{seq_key(d)}.npz"


def run_occlude(a):
    """XS on the damaged 2D of every condition (group x duration) -> cache npz (rows, damaged K, unit, episodes)."""
    from finetune_motionagformer_fit3d import mag_input
    model, dev = load_model(a); seqs = load_seqs(a); t0, total = time.time(), 0
    d0 = seqs[0]; clean0 = predict_rows(model, dev, d0['x'], [5], seq_key(d0))[5]
    chk, _ = rows_partial(model, dev, d0['x'], np.ones(len(d0['x']), bool), clean0 * 0)
    assert np.allclose(chk, clean0, atol=1e-4), 'rows_partial != predict_rows'
    for cond in a.conditions:
        group, duration = cond.split('-')
        for d in seqs:
            out = occl_path(a, d, cond)
            if os.path.exists(out): continue
            clean = predict_rows(model, dev, d['x'], [5], seq_key(d))[5]
            eps = episodes_for(d, group, duration)
            Kc = corrupt(d['K'], eps, rng_for(seq_key(d), cond, 'damage'))
            xc, crops = mag_input(Kc)
            changed = np.abs(xc - d['x']).max((1, 2)) > 1e-7
            rows, nw = rows_partial(model, dev, xc, changed, clean); total += nw
            os.makedirs(os.path.dirname(out), exist_ok=True)
            np.savez(out + '.tmp.npz', rows=rows.astype(np.float32), K=Kc.astype(np.float32), x=xc, unit=(crops[:, 2] / 2).astype(np.float32),
                     episodes=json.dumps([[int(s), int(e), list(map(int, j)), m, sd, bool(nr)] for s, e, j, m, sd, nr in eps]))
            os.replace(out + '.tmp.npz', out)
        print(cond, f'{total} windows', f'{time.time() - t0:.0f}s', flush=True)
    write_manifest(a, [d['csv'] for d in seqs] + [a.checkpoint], [], dict(conditions=a.conditions, cache=a.cache, windows=total))


# ---------------------------------------------------------------- variants (A raw, B smoothing, B0 lock, C app constraints,
# D unconditional relation, E adaptive, F adaptive seeded by the setup window, EC = E after C = the app hook point)
def v_ema(P, alpha):
    """B: causal exponential smoothing of every joint (no extra latency, no confidence)."""
    out = P.copy()
    for t in range(1, len(P)):
        out[t] = alpha * P[t] + (1 - alpha) * out[t - 1]
    return out


def v_lock(P, conf, unit, thr):
    """B0 (negative control, never a candidate): a joint below thr is held at its last observed px position."""
    X = P * unit[:, None, None]; out = X.copy(); last = X[0].copy()
    for t in range(len(X)):
        ok = conf[t] >= thr; last[ok] = X[t][ok]; out[t][~ok] = last[~ok]
    return out / unit[:, None, None]


def v_hard(P, conf, unit, ex, params):
    """D: once a relation is established (same rule as E), it is enforced on every frame by moving both joints
    symmetrically - no confidence gating, no tracking, no re-anchoring."""
    from pose_feedback.geometry.adaptive_relations import AdaptiveRelations
    est = AdaptiveRelations(ex, **params); X = P * unit[:, None, None]; out = X.copy(); refs = {}
    for t in range(len(X)):
        est.update(P[t], conf[t], t, float(unit[t]))
        for name, a_, b in est.relations:
            if name not in refs and est.state[name]['ref'] is not None:
                refs[name] = est.state[name]['ref'].copy()
            if name in refs:
                corr = (refs[name] - (out[t, b] - out[t, a_])) / 2
                out[t, a_] -= corr; out[t, b] += corr
    return out / unit[:, None, None]


def setup_seed(P, conf, unit, ex, d, params, window=30):
    """F: relation references from the setup window (1 s before the first rep): median of the frames where both joints
    are observed, if >= window/2 such frames. -> {name: (ref_px, spread_px)}, seed frame."""
    from pose_feedback.geometry.adaptive_relations import DEFAULTS, RELATIONS
    thr = dict(DEFAULTS, **params)['reliable_conf']; f0 = d['seg'][0][0]; lo = max(0, f0 - window); out = {}
    for name, a_, b in RELATIONS.get(ex, ()):
        ok = [t for t in range(lo, f0) if conf[t][a_] >= thr and conf[t][b] >= thr]
        if len(ok) >= window // 2:
            V = np.stack([(P[t, b] - P[t, a_]) * unit[t] for t in ok]); ref = np.median(V, 0)
            out[name] = (ref, float(np.percentile(np.linalg.norm(V - ref, axis=-1), 90)))
    return out, f0


def v_adaptive(P, conf, unit, ex, params, seed=None):
    """E (seed None) / F (seed = (refs, frame): no online establishment, references from the setup window).
    -> (output crop units, invalid [N,17] bool, fill weight [N,17])."""
    from pose_feedback.geometry.adaptive_relations import AdaptiveRelations
    kw = dict(params)
    if seed is not None: kw['init_frames'] = 10 ** 9
    est = AdaptiveRelations(ex, **kw); out = P.copy(); inv = np.zeros(P.shape[:2], bool); W = np.zeros(P.shape[:2])
    for t in range(len(P)):
        if seed is not None and t == seed[1]:
            for name, (ref, spread) in seed[0].items(): est.seed_reference(name, ref, spread)
        out[t], rep = est.update(P[t], conf[t], t, float(unit[t]))
        inv[t, rep['invalid']] = True
        for j, f in rep['filled'].items(): W[t, j] = f['w']
    return out, inv, W


def v_constraints(P, ex):
    """C: the app's Pose3DConstraints defaults (bones, angle limits, knee flip detection; reflection on squat only)."""
    Q, reps = lf.apply_constraints(P, dict(reflect_flipped_knee=ex == 'squat'))
    inv = np.zeros(P.shape[:2], bool)
    for t, r in enumerate(reps): inv[t, r['invalid_joints']] = True
    return Q, inv


def all_variants(raw, conf, unit, d, params, ema_alpha, lock_thr, which):
    """{name: (Q crop units, invalid mask or None, fill weights or None)} for the selected variants."""
    ex, out = d['ex'], {}
    if 'A' in which: out['A'] = (raw, None, None)
    if 'B' in which: out['B'] = (v_ema(raw, ema_alpha), None, None)
    if 'B0' in which: out['B0'] = (v_lock(raw, conf, unit, lock_thr), None, None)
    if 'C' in which or 'EC' in which:
        C, invc = v_constraints(raw, ex); out['C'] = (C, invc, None)
    if 'D' in which: out['D'] = (v_hard(raw, conf, unit, ex, params), None, None)
    if 'E' in which: out['E'] = v_adaptive(raw, conf, unit, ex, params)
    if 'F' in which: out['F'] = v_adaptive(raw, conf, unit, ex, params, seed=setup_seed(raw, conf, unit, ex, d, params))
    if 'EC' in which:
        Q, inv, W = v_adaptive(out['C'][0], conf, unit, ex, params); out['EC'] = (Q, inv | out['C'][1], W)
    return out


# ---------------------------------------------------------------- metrics + evaluate
SIDE_H = {'L': dict(hip=4, knee=5, ankle=6, shoulder=11, elbow=12, wrist=13), 'R': dict(hip=1, knee=2, ankle=3, shoulder=14, elbow=15, wrist=16)}
LEG_GROUPS = ('ankle', 'knee', 'leg')


def limb_angle(P, side, group):
    from eval_3d_angles import interior
    k = SIDE_H[side]
    if group in LEG_GROUPS: return interior(P[:, k['hip']], P[:, k['knee']], P[:, k['ankle']])
    return interior(P[:, k['shoulder']], P[:, k['elbow']], P[:, k['wrist']])


def to_metres(Q, d):
    return (Q - Q[:, :1]) * d['mm'][:, None, None] / 1000


def episode_records(P, E, inv, W, d, eps, group, E_clean):
    G, Jw = d['G'], d['J'][d['pick']]; n = len(P); out = []
    for s, e, joints, model, side, near in eps:
        H = [COCO2H[j] for j in joints]
        a_p, a_g = limb_angle(P, side, group), limb_angle(G, side, group)
        stepP = np.linalg.norm(np.diff(P[:, H], axis=0), axis=-1) * 1000; stepG = np.linalg.norm(np.diff(G[:, H], axis=0), axis=-1) * 1000
        lo_j, hi_j = max(s - 1, 0), min(e + RECOVERY, n - 1)
        ev = E[:, H].mean(1); ec = E_clean[:, H].mean(1); rec_k = RECOVERY * 2
        for k in range(0, RECOVERY * 2):
            if e + k + 5 > n: break
            if (ev[e + k:e + k + 5] <= ec[e + k:e + k + 5] + 10).all(): rec_k = k; break
        out.append(dict(model=model, near=bool(near), err=float(ev[s:e].mean()), err_clean=float(ec[s:e].mean()),
                        err_rec=float(ev[e:e + RECOVERY].mean()), err_rec_clean=float(ec[e:e + RECOVERY].mean()),
                        moved=float(np.linalg.norm(Jw[s:e][:, H] - Jw[s][None, H], axis=-1).max() * 1000),
                        angle_err=float(np.nanmean(np.abs(a_p[s:e] - a_g[s:e]))),
                        jump=float(np.max(stepP[lo_j:hi_j] - stepG[lo_j:hi_j])) if hi_j > lo_j else 0.0, recovery_frames=int(rec_k),
                        filled=float((W[s:e][:, H] > 0.5).mean()) if W is not None else 0.0,
                        invalid=float(inv[s:e][:, H].mean()) if inv is not None else 0.0))
    return out


def run_evaluate(a):
    from eval_3d_mediapipe import angle_metrics, angles, pose_metrics
    params = json.loads(a.params) if a.params else {}
    seqs = load_seqs(a); recs, inputs = [], []
    for d in seqs:
        clean = predict_rows(None, None, d['x'], [5], seq_key(d))[5]
        from finetune_motionagformer_fit3d import mag_input
        conf0, unit0 = d['x'][..., 2], mag_input(d['K'])[1][:, 2] / 2
        E_clean = np.linalg.norm(to_metres(clean, d) - d['G'], axis=-1) * 1000
        lo, hi = set_range(d); ref = lf.ref_angles(d)
        for cond in a.conditions:
            if cond == 'clean':
                raw, conf, unit, eps, group = clean, conf0, unit0, [], None
            else:
                z = np.load(occl_path(a, d, cond)); raw, conf, unit = z['rows'].astype(float), z['x'][..., 2], z['unit'].astype(float)
                eps = [tuple(e) for e in json.loads(str(z['episodes']))]; group = cond.split('-')[0]
            for v, (Q, inv, W) in all_variants(raw, conf, unit, d, params, a.ema_alpha, a.lock_thr, a.variants).items():
                P = to_metres(Q, d); E = np.linalg.norm(P - d['G'], axis=-1) * 1000; pm = pose_metrics(P[lo:hi], d['G'][lo:hi])
                r = dict(group=d['group'], exercise=d['ex'], subj=d['subj'], cam=d['cam'], bin=d['bin'], cond=cond, var=v,
                         mpjpe=float(E[lo:hi].mean()), pa=float(np.mean(pm['pa_mpjpe'])), accel=float(np.mean(pm['accel'])),
                         invalid=float(inv[lo:hi].mean()) if inv is not None else 0.0,
                         changed=float((np.abs(Q - raw).max(-1) > 1e-9)[lo:hi].mean()),
                         episodes=episode_records(P, E, inv, W, d, eps, group, E_clean) if eps else [])
                if cond == 'clean':
                    am = angle_metrics(angles(P, d['side'], d['up_c']), ref, d['seg'])
                    r['angles'] = {g: dict(rep=float(np.mean(am[g]['rep'])), frame=float(np.mean(am[g]['frame'])), jitter=float(np.mean(am[g]['jitter'])))
                                   for g in ('knee', 'hip', 'elbow', 'torso_g')}
                recs.append(r)
        inputs.append(d['csv']); print(seq_key(d), flush=True)
    summarize_eval(a, recs, inputs, params)


def boot_ci(x, n=2000, seed=0):
    x = np.asarray(x, float); x = x[np.isfinite(x)]
    if len(x) < 2: return [float('nan')] * 2
    rng = np.random.default_rng(seed); m = rng.choice(x, (n, len(x))).mean(1)
    return [float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))]


def summarize_eval(a, recs, inputs, params):
    summ = dict(params=params, ema_alpha=a.ema_alpha, lock_thr=a.lock_thr, groups={}, paired={})
    keyf = lambda r: (r['group'], r['cond'], r['exercise'])
    md = [f"params={json.dumps(params)} ema_alpha={a.ema_alpha} lock_thr={a.lock_thr}", '',
          '| 묶음 | 조건 | 운동 | 변형 | 영상 | MPJPE(세트) | PA | 가속도 | 무효 관절 | 바뀐 관절 | 가림 관절 오차 (깨끗한 입력 A) | 복구 30f 오차 | 복구 프레임 p50 | 사지 각 오차 | 점프 p95 | 채움 | 가림 중 무효 |',
          '|---' * 17 + '|']
    conds = list(dict.fromkeys(r['cond'] for r in recs)); vs = list(dict.fromkeys(r['var'] for r in recs))
    for grp in dict.fromkeys(r['group'] for r in recs):
        for cond in conds:
            for ex in list(EXERCISES) + ['all']:
                for v in vs:
                    rs = [r for r in recs if r['group'] == grp and r['cond'] == cond and r['var'] == v and (ex == 'all' or r['exercise'] == ex)]
                    if not rs: continue
                    ep = [e for r in rs for e in r['episodes']]
                    g = dict(videos=len(rs), mpjpe=float(np.mean([r['mpjpe'] for r in rs])), pa=float(np.mean([r['pa'] for r in rs])),
                             accel=float(np.mean([r['accel'] for r in rs])), invalid=float(np.mean([r['invalid'] for r in rs])),
                             changed=float(np.mean([r['changed'] for r in rs])), episodes=len(ep))
                    if ep:
                        g.update({k: float(np.mean([e[k] for e in ep])) for k in ('err', 'err_clean', 'err_rec', 'err_rec_clean', 'angle_err', 'filled', 'invalid')},
                                 recovery_p50=float(np.median([e['recovery_frames'] for e in ep])), jump_p95=float(np.percentile([e['jump'] for e in ep], 95)))
                        for m in CORRUPTIONS + ('near', 'far', 'moved', 'static'):
                            sel = [e for e in ep if (e['model'] == m) or (m == 'near' and e['near']) or (m == 'far' and not e['near'])
                                   or (m == 'moved' and e['moved'] > 50) or (m == 'static' and e['moved'] <= 50)]
                            if sel: g[f'err_{m}'] = float(np.mean([e['err'] for e in sel])); g[f'n_{m}'] = len(sel)
                    if 'angles' in rs[0]:
                        g['angles'] = {k: {q: float(np.mean([r['angles'][k][q] for r in rs])) for q in ('rep', 'frame', 'jitter')} for k in rs[0]['angles']}
                    summ['groups'][f'{grp}/{cond}/{ex}/{v}'] = g
                    f = lambda k, fmt='{:.1f}': fmt.format(g[k]) if k in g else '-'
                    md.append(f"| {grp} | {cond} | {ex} | {v} | {g['videos']} | {g['mpjpe']:.1f} | {g['pa']:.1f} | {g['accel']:.2f} | {g['invalid']:.1%} | {g['changed']:.1%} | "
                              f"{f('err')} ({f('err_clean')}) | {f('err_rec')} | {f('recovery_p50', '{:.0f}')} | {f('angle_err')} | {f('jump_p95')} | {f('filled', '{:.0%}')} | {f('invalid', '{:.0%}')} |")
            # paired per-video differences (bootstrap over videos) of the episode error / clean MPJPE
            for x, y in (('E', 'A'), ('E', 'B'), ('E', 'B0'), ('E', 'D'), ('F', 'E'), ('EC', 'C'), ('B', 'A'), ('C', 'A'), ('D', 'A')):
                key = lambda r: (r['subj'], r['cam'], r['exercise'])
                rx = {key(r): r for r in recs if r['group'] == grp and r['cond'] == cond and r['var'] == x}
                ry = {key(r): r for r in recs if r['group'] == grp and r['cond'] == cond and r['var'] == y}
                ks = sorted(set(rx) & set(ry))
                if not ks: continue
                q = 'episodes' if cond != 'clean' else None
                if q: dif = [np.mean([e['err'] for e in rx[k_]['episodes']]) - np.mean([e['err'] for e in ry[k_]['episodes']]) for k_ in ks if rx[k_]['episodes']]
                else: dif = [rx[k_]['mpjpe'] - ry[k_]['mpjpe'] for k_ in ks]
                summ['paired'][f'{grp}/{cond}/{x}-{y}'] = dict(n=len(dif), mean=float(np.mean(dif)) if dif else None, ci95=boot_ci(dif))
    md += ['', '**짝지은 차이 (영상 단위 평균, 부트스트랩 95% CI; 가림 조건 = 가림 관절 오차 mm, clean = 세트 MPJPE mm)**', '', '| 키 | n | 평균 | 95% CI |', '|---|---|---|---|']
    for k_, v in summ['paired'].items():
        md.append(f"| {k_} | {v['n']} | {v['mean']:.2f} | {v['ci95'][0]:.2f} – {v['ci95'][1]:.2f} |" if v['mean'] is not None else f'| {k_} | 0 | - | - |')
    out_j, out_m = Path(a.run_dir) / f'evaluate_{a.tag}.json', Path(a.run_dir) / f'evaluate_{a.tag}.md'
    json.dump(dict(summary=summ, records=recs), open(out_j, 'w')); out_m.write_text('\n'.join(md) + '\n')
    print('\n'.join(md[:3])); print(f'{len(recs)} records -> {out_m}')
    write_manifest(a, inputs + [a.checkpoint], [out_j, out_m], dict(conditions=a.conditions, variants=a.variants, params=params, cache=a.cache))


# ---------------------------------------------------------------- foot shifts (semi-synthetic; user 2026-10-20)
SHIFT_CASES = {  # amp m, ramp frames (30 fps), occluded while shifting (+15 f), between reps
    'grad2': dict(amp=0.02, ramp=30, occl=False, step=False), 'grad5': dict(amp=0.05, ramp=60, occl=False, step=False),
    'step': dict(amp=0.08, ramp=9, occl=False, step=True),
    'occ_grad5': dict(amp=0.05, ramp=60, occl=True, step=False), 'occ_step': dict(amp=0.08, ramp=9, occl=True, step=True),
}
SHIFT_TAIL, SHIFT_OCC_EXTRA = 90, 15


def shift_plan(d, case):
    """Seeded: which foot ('L' / 'R'), start frame, ramp, damage model. None when the set is too short."""
    c = SHIFT_CASES[case]; rng = rng_for(seq_key(d), 'shift', case); lo, hi = set_range(d); n = len(d['x'])
    side = 'L' if rng.random() < 0.5 else 'R'
    if c['step']:
        cands = [e for _, e in d['seg'][1:-1] if e + c['ramp'] + SHIFT_TAIL < n]
        if not cands: return None
        start = int(cands[int(rng.integers(0, len(cands)))])
    else:
        if hi - c['ramp'] - SHIFT_TAIL <= lo + 30: return None
        start = int(rng.integers(lo + 30, hi - c['ramp'] - SHIFT_TAIL))
    return dict(side=side, start=start, ramp=c['ramp'], amp=c['amp'], occl=c['occl'], model=('keep', 'drift', 'freeze')[int(rng.integers(0, 3))])


def apply_shift(d, plan, a):
    """Moves one ankle (and its knee by half) outward in the world, horizontally; returns damaged K, G and the
    camera-frame shift of the ankle per frame (m)."""
    from pose_feedback.body.pose2d_data import project_fit3d
    cam = json.load(open(f"{a.root}/train/{d['subj']}/camera_parameters/{d['cam']}/{d['ex']}.json"))
    Jp = d['J'][d['pick']]; n = len(Jp); t = np.arange(n)
    lr = Jp[plan['start'], LHIP] - Jp[plan['start'], RHIP]; lr[2] = 0; lr /= np.linalg.norm(lr)
    ank, kne, cank, ckne = (LANK, LKNE, 15, 13) if plan['side'] == 'L' else (RANK, RKNE, 16, 14)
    outward = lr if plan['side'] == 'L' else -lr
    delta = plan['amp'] * np.clip((t - plan['start']) / plan['ramp'], 0, 1)[:, None] * outward[None]  # world m
    K = d['K'].copy(); G = d['G'].copy(); R = d['R']
    for j, cj, f in ((ank, cank, 1.0), (kne, ckne, 0.5)):
        moved = t >= plan['start']
        K[moved, cj, :2] += project_fit3d(Jp[moved, j] + f * delta[moved], cam) - project_fit3d(Jp[moved, j], cam)
        G[:, j] += f * delta @ R.T
    if plan['occl']:
        s0, e0 = plan['start'], min(n, plan['start'] + plan['ramp'] + SHIFT_OCC_EXTRA)
        K = corrupt(K, [(s0, e0, [cank], plan['model'])], rng_for(seq_key(d), 'shift-damage'))
    return K, G, delta @ R.T


def run_foot_shift(a):
    """XS on the shifted input of every case (cache), then variants on clean vs shifted input (paired)."""
    from finetune_motionagformer_fit3d import mag_input
    params = json.loads(a.params) if a.params else {}
    model = dev = None; seqs = load_seqs(a); recs, inputs = [], []
    for d in seqs:
        clean = predict_rows(None, None, d['x'], [5], seq_key(d))[5]
        conf0, unit0 = d['x'][..., 2], mag_input(d['K'])[1][:, 2] / 2
        base = all_variants(clean, conf0, unit0, d, params, a.ema_alpha, a.lock_thr, a.variants)
        mm = d['mm'][:, None] / 1000
        for case in a.cases:
            plan = shift_plan(d, case)
            if plan is None: continue
            path = f"{a.cache}/shift/{case}/{seq_key(d)}.npz"
            K, G, dcam = apply_shift(d, plan, a)
            if os.path.exists(path):
                z = np.load(path); rows, xs, unit = z['rows'].astype(float), z['x'], z['unit'].astype(float)
            else:
                if model is None: model, dev = load_model(a)
                xs, crops = mag_input(K); unit = crops[:, 2] / 2
                rows, _ = rows_partial(model, dev, xs, np.abs(xs - d['x']).max((1, 2)) > 1e-7, clean)
                os.makedirs(os.path.dirname(path), exist_ok=True); np.savez(path, rows=rows.astype(np.float32), x=xs, unit=unit.astype(np.float32))
            sh = all_variants(rows, xs[..., 2], unit, d, params, a.ema_alpha, a.lock_thr, a.variants)
            ank = LANK if plan['side'] == 'L' else RANK
            sign = 1.0 if plan['side'] == 'L' else -1.0  # v = left - right ankle
            dv_true = sign * dcam
            end = plan['start'] + plan['ramp']; occ_end = end + SHIFT_OCC_EXTRA
            W = dict(ramp=(plan['start'], end), W1=(end, occ_end), W2=(occ_end + 5, occ_end + 65))
            vec = lambda Q: (Q[:, LANK] - Q[:, RANK]) * mm
            dvA = vec(sh['A'][0]) - vec(base['A'][0])
            for v in sh:
                dv = vec(sh[v][0]) - vec(base[v][0])
                P = to_metres(sh[v][0], d); err = np.linalg.norm(P[:, ank] - G[:, ank], axis=-1) * 1000
                r = dict(group=d['group'], exercise=d['ex'], subj=d['subj'], cam=d['cam'], case=case, var=v, side=plan['side'],
                         near=plan['side'] == d['side'], model=plan['model'] if plan['occl'] else None)
                for w, (x0, x1) in W.items():
                    x1 = min(x1, len(dv))
                    if x1 - x0 < 3: continue
                    tt = slice(x0, x1)
                    r[f'supp_true_{w}'] = float(1 - (dv[tt] * dv_true[tt]).sum(-1).mean() / (dv_true[tt] ** 2).sum(-1).mean())
                    den = (dvA[tt] ** 2).sum(-1).mean()
                    r[f'supp_A_{w}'] = float(1 - (dv[tt] * dvA[tt]).sum(-1).mean() / den) if den > 1e-10 else None
                    r[f'ank_err_{w}'] = float(err[tt].mean())
                recs.append(r)
        inputs.append(d['csv']); print(seq_key(d), flush=True)
    summ, md = {}, ['억제율 = 1 − (Δv_변형·Δv)/|Δv|²: 1 = 이동을 완전히 지움, 0 = 그대로 따라감. 참 = 실제 이동 기준, A = XS 원출력이 본 이동 기준.', '',
                    '| 묶음 | 케이스 | 운동 | 변형 | n | 억제(참) 이동 중 / W1 / W2 | 억제(A 대비) 이동 중 / W1 / W2 | 발목 오차 W1 / W2 mm |', '|---' * 8 + '|']
    f = lambda rs, k: (lambda x: f'{np.mean(x):.2f}' if x else '-')([r[k] for r in rs if r.get(k) is not None])
    for grp in dict.fromkeys(r['group'] for r in recs):
        for case in a.cases:
            for ex in list(EXERCISES) + ['all']:
                for v in dict.fromkeys(r['var'] for r in recs):
                    rs = [r for r in recs if r['group'] == grp and r['case'] == case and r['var'] == v and (ex == 'all' or r['exercise'] == ex)]
                    if not rs: continue
                    g = {k: float(np.mean([r[k] for r in rs if r.get(k) is not None])) for k in rs[0] if k.startswith(('supp', 'ank')) and any(r.get(k) is not None for r in rs)}
                    summ[f'{grp}/{case}/{ex}/{v}'] = dict(n=len(rs), **g)
                    md.append(f"| {grp} | {case} | {ex} | {v} | {len(rs)} | {f(rs, 'supp_true_ramp')} / {f(rs, 'supp_true_W1')} / {f(rs, 'supp_true_W2')} | "
                              f"{f(rs, 'supp_A_ramp')} / {f(rs, 'supp_A_W1')} / {f(rs, 'supp_A_W2')} | {f(rs, 'ank_err_W1')} / {f(rs, 'ank_err_W2')} |")
    out_j, out_m = Path(a.run_dir) / f'foot_shift_{a.tag}.json', Path(a.run_dir) / f'foot_shift_{a.tag}.md'
    json.dump(dict(summary=summ, records=recs, params=params), open(out_j, 'w')); out_m.write_text('\n'.join(md) + '\n')
    print(f'{len(recs)} records -> {out_m}')
    write_manifest(a, inputs + [a.checkpoint], [out_j, out_m], dict(cases=a.cases, params=params, variants=a.variants, cache=a.cache))


# ---------------------------------------------------------------- E1 setup measurement accuracy
SETUP_WINDOW = 30
WIDTH_ITEMS = ('feet_width', 'feet_width_shoulder', 'hand_width', 'grip_width')


def item_series(P, ex, up):
    from pose_feedback.body.exercise_setup import measure
    rows = [measure(p, ex, up) for p in P]
    return {k: np.array([np.nan if r.get(k) is None else r[k] for r in rows]) for k in rows[0]}


def run_setup_measure(a):
    """E1: setup items from XS (A raw, C constrained) vs mocap over the setup window; 2D pixel ratio; oracle-body
    transfer; repeatability; rep-top drift (false cues against the session's own setup value); cm via oracle widths."""
    from pose_feedback.body.exercise_setup import depth_share
    from pose_feedback.body.form_metrics_3d import UP
    seqs = load_seqs(a); recs, inputs = [], []
    for d in seqs:
        ex = d['ex']; f0 = d['seg'][0][0]; w = slice(max(0, f0 - SETUP_WINDOW), f0)
        if f0 < SETUP_WINDOW // 2: continue
        raw = predict_rows(None, None, d['x'], [5], seq_key(d))[5]
        C, _ = v_constraints(raw, ex)
        G = d['G']; Jw = d['J'][d['pick']]
        dims = body_dims(Jw); hipw_cm, shw_cm, thigh_cm = (float(np.median(dims[k])) * 100 for k in ('hip_width', 'shoulder_width', 'thigh'))
        srcs = {'xs_raw': item_series(raw, ex, UP), 'xs_c': item_series(C, ex, UP), 'gt': item_series(G, ex, d['up_c'])}
        K = d['K']; px = lambda i, j: np.linalg.norm(K[:, i, :2] - K[:, j, :2], axis=-1)
        two = {'feet_width': px(15, 16) / px(11, 12), 'feet_width_shoulder': px(15, 16) / px(5, 6), 'hand_width': px(9, 10) / px(5, 6), 'grip_width': px(9, 10) / px(5, 6)}
        thigh_xs = (np.linalg.norm(raw[:, RHIP] - raw[:, RKNE], axis=-1) + np.linalg.norm(raw[:, LHIP] - raw[:, LKNE], axis=-1)) / 2
        transfer = np.linalg.norm(raw[:, LANK] - raw[:, RANK], axis=-1) / (thigh_xs * hipw_cm / thigh_cm)
        tops = [s_ for s_, _ in d['seg']]
        rec = dict(group=d['group'], exercise=ex, subj=d['subj'], cam=d['cam'], view=float(d['view']), bin=d['bin'], items={})
        for k in srcs['gt']:
            g = float(np.nanmedian(srcs['gt'][k][w]))
            r = dict(gt=g, depth=float(np.median([depth_share(p, k) for p in G[w]])))
            for src in ('xs_raw', 'xs_c'):
                v = srcs[src][k]
                r[src] = float(np.nanmedian(v[w])); r[f'{src}_sd'] = float(np.nanstd(v[w]))
                r[f'{src}_tops'] = [float(v[t]) for t in tops if np.isfinite(v[t])]
            r['gt_tops'] = [float(srcs['gt'][k][t]) for t in tops]
            if k in two: r['2d'] = float(np.nanmedian(two[k][w]))
            if k == 'feet_width':
                r['transfer'] = float(np.nanmedian(transfer[w]))
                gt_cm = float(np.median(np.linalg.norm(G[w, LANK] - G[w, RANK], axis=-1))) * 100
                r['cm'] = dict(gt=gt_cm, xs=r['xs_raw'] * hipw_cm, transfer=r['transfer'] * hipw_cm)
            if k in ('hand_width', 'grip_width'):
                gt_cm = float(np.median(np.linalg.norm(G[w, LWRI] - G[w, RWRI], axis=-1))) * 100
                r['cm'] = dict(gt=gt_cm, xs=r['xs_raw'] * shw_cm)
            rec['items'][k] = r
        recs.append(rec); inputs.append(d['csv']); print(seq_key(d), flush=True)
    # tolerance per item = 2 x median within-window SD of xs_raw on tuning subjects (prereg section 6)
    tol = {}
    for k in sorted({k for r in recs for k in r['items']}):
        sds = [r['items'][k]['xs_raw_sd'] for r in recs if r['group'] == 'tuning' and k in r['items'] and np.isfinite(r['items'][k]['xs_raw_sd'])]
        if sds: tol[k] = 2 * float(np.median(sds))
    summ = dict(tolerance=tol, groups={})
    md = ['허용폭(조정 피험자, 2 × 셋업 창 안 표준편차 중앙값): ' + ', '.join(f'{k} {v:.3f}' for k, v in tol.items()), '',
          '| 묶음 | 운동 | 항목 | 시점 | n | 모캡 중앙값 | XS 오차 |중앙값| (p90) | XS+제약 | 2D 오차 | 체형 전이 오차 | 창 안 SD | 렙 꼭대기 오경보(같은 영상) | 다른 카메라 오경보 | cm 오차 XS / 전이 (모캡 cm 중앙값) |',
          '|---' * 15 + '|']
    for grp in ('tuning', 'heldout'):
        for ex in EXERCISES:
            items = sorted({k for r in recs if r['exercise'] == ex for k in r['items']})
            for k in items:
                for b in ['all'] + sorted({r['bin'] for r in recs}):
                    rs = [r for r in recs if r['group'] == grp and r['exercise'] == ex and k in r['items'] and (b == 'all' or r['bin'] == b)]
                    if not rs: continue
                    it = [r['items'][k] for r in rs]
                    e = np.array([abs(i['xs_raw'] - i['gt']) for i in it]); ec = np.array([abs(i['xs_c'] - i['gt']) for i in it])
                    e2 = np.array([abs(i['2d'] - i['gt']) for i in it if '2d' in i]); et = np.array([abs(i['transfer'] - i['gt']) for i in it if 'transfer' in i])
                    t_ = tol.get(k, float('nan'))
                    fc = [abs(x - i['xs_raw']) > t_ for i in it for x in i['xs_raw_tops'][1:]]
                    xc = []
                    if b == 'all':
                        for subj in {r['subj'] for r in rs}:
                            vals = [r['items'][k]['xs_raw'] for r in rs if r['subj'] == subj]
                            xc += [abs(u - v) > t_ for i_, u in enumerate(vals) for v in vals[i_ + 1:]]
                    cm = [i['cm'] for i in it if 'cm' in i]
                    g = dict(n=len(rs), gt_median=float(np.median([i['gt'] for i in it])), xs_abs_err_p50=float(np.median(e)), xs_abs_err_p90=float(np.percentile(e, 90)),
                             xs_c_abs_err_p50=float(np.median(ec)), err_2d_p50=float(np.median(e2)) if len(e2) else None, transfer_err_p50=float(np.median(et)) if len(et) else None,
                             sd_p50=float(np.median([i['xs_raw_sd'] for i in it])), false_cue_reptops=float(np.mean(fc)) if fc else None,
                             false_cue_cross_cam=float(np.mean(xc)) if xc else None, depth_p50=float(np.median([i['depth'] for i in it])))
                    if cm:
                        g['cm_err_xs_p50'] = float(np.median([abs(c['xs'] - c['gt']) for c in cm])); g['cm_gt_p50'] = float(np.median([c['gt'] for c in cm]))
                        if 'transfer' in cm[0]: g['cm_err_transfer_p50'] = float(np.median([abs(c['transfer'] - c['gt']) for c in cm]))
                    summ['groups'][f'{grp}/{ex}/{k}/{b}'] = g
                    fmt = lambda v, f_='{:.2f}': '-' if v is None else f_.format(v)
                    md.append(f"| {grp} | {ex} | {k} | {b} | {g['n']} | {g['gt_median']:.2f} | {g['xs_abs_err_p50']:.2f} ({g['xs_abs_err_p90']:.2f}) | {g['xs_c_abs_err_p50']:.2f} | "
                              f"{fmt(g['err_2d_p50'])} | {fmt(g['transfer_err_p50'])} | {g['sd_p50']:.3f} | {fmt(g['false_cue_reptops'], '{:.0%}')} | {fmt(g['false_cue_cross_cam'], '{:.0%}')} | "
                              f"{fmt(g.get('cm_err_xs_p50'), '{:.1f}')} / {fmt(g.get('cm_err_transfer_p50'), '{:.1f}')} ({fmt(g.get('cm_gt_p50'), '{:.0f}')}) |")
    out_j, out_m = Path(a.run_dir) / 'setup_measure.json', Path(a.run_dir) / 'setup_measure.md'
    json.dump(dict(summary=summ, records=recs), open(out_j, 'w')); out_m.write_text('\n'.join(md) + '\n'); print('\n'.join(md[:2]))
    write_manifest(a, inputs + [a.checkpoint], [out_j, out_m])


# ---------------------------------------------------------------- E4 quality signals
LIMB_PARENT = {2: 1, 3: 2, 5: 4, 6: 5, 12: 11, 13: 12, 15: 14, 16: 15, 11: 8, 14: 8}


def auc(score, label):
    """ROC AUC (Mann-Whitney, ties averaged): P(score of a positive > score of a negative)."""
    from scipy.stats import rankdata
    score, label = np.asarray(score, float), np.asarray(label, bool)
    ok = np.isfinite(score); score, label = score[ok], label[ok]
    npos, nneg = label.sum(), (~label).sum()
    if npos == 0 or nneg == 0: return None
    r = rankdata(score)
    return float((r[label].sum() - npos * (npos + 1) / 2) / (npos * nneg))


def run_signals(a):
    from finetune_motionagformer_fit3d import mag_input
    seqs = load_seqs(a); feats = {k: [] for k in ('conf', 'temporal', 'reproj', 'bone')}; err, jt, cond_of, inputs = [], [], [], []
    J = sorted(LIMB_PARENT)
    for d in seqs:
        clean = predict_rows(None, None, d['x'], [5], seq_key(d))[5]
        for cond in a.conditions:
            if cond == 'clean':
                raw, x, unit = clean, d['x'], mag_input(d['K'])[1][:, 2] / 2
            else:
                z = np.load(occl_path(a, d, cond)); raw, x, unit = z['rows'].astype(float), z['x'], z['unit'].astype(float)
            lo, hi = set_range(d); X = raw * unit[:, None, None]
            E = np.linalg.norm(to_metres(raw, d) - d['G'], axis=-1) * 1000
            leg = np.median(np.linalg.norm(X[:, 1] - X[:, 2], axis=-1) + np.linalg.norm(X[:, 2] - X[:, 3], axis=-1))
            acc = np.zeros_like(X[..., 0]); acc[2:] = np.linalg.norm(X[2:] - 2 * X[1:-1] + X[:-2], axis=-1) / leg
            rp = np.linalg.norm((raw[:, :, :2] - raw[:, :1, :2]) - (x[:, :, :2] - x[:, :1, :2]), axis=-1)
            bone = np.zeros_like(E)
            for j, p_ in LIMB_PARENT.items():
                Lj = np.linalg.norm(raw[:, j] - raw[:, p_], axis=-1); bone[:, j] = np.abs(Lj - np.median(Lj)) / np.median(Lj)
            sl = slice(lo, hi)
            feats['conf'].append(-x[sl][:, J, 2].ravel()); feats['temporal'].append(acc[sl][:, J].ravel())
            feats['reproj'].append(rp[sl][:, J].ravel()); feats['bone'].append(bone[sl][:, J].ravel())
            err.append(E[sl][:, J].ravel()); jt.append(np.tile(J, hi - lo)); cond_of.append(np.full((hi - lo) * len(J), cond))
        inputs.append(d['csv']); print(seq_key(d), flush=True)
    F = {k: np.concatenate(v) for k, v in feats.items()}; err = np.concatenate(err); jt = np.concatenate(jt); cond_of = np.concatenate(cond_of)
    groups = {'all': np.ones_like(err, bool), 'ankle': np.isin(jt, [3, 6]), 'knee': np.isin(jt, [2, 5]), 'wrist': np.isin(jt, [13, 16]),
              'elbow': np.isin(jt, [12, 15]), 'shoulder': np.isin(jt, [11, 14]), 'clean': cond_of == 'clean', 'occluded': cond_of != 'clean'}
    summ, md = {}, ['| 표적 | 묶음 | 관절-프레임 | 양성 비율 | AUC 신뢰도 | 시간 잔차 | 재투영 불일치 | 뼈 길이 편차 |', '|---' * 8 + '|']
    for thr in (100, 150):
        for gname, m in groups.items():
            lab = err[m] > thr
            s_ = {k: auc(F[k][m], lab) for k in F}
            summ[f'{thr}/{gname}'] = dict(n=int(m.sum()), pos=float(lab.mean()), **s_)
            fa = lambda v: '-' if v is None else f'{v:.3f}'
            md.append(f"| >{thr} mm | {gname} | {int(m.sum())} | {lab.mean():.1%} | " + ' | '.join(fa(s_[k]) for k in ('conf', 'temporal', 'reproj', 'bone')) + ' |')
    out_j, out_m = Path(a.run_dir) / f'signals_{a.tag}.json', Path(a.run_dir) / f'signals_{a.tag}.md'
    json.dump(summ, open(out_j, 'w'), indent=1); out_m.write_text('\n'.join(md) + '\n'); print('\n'.join(md))
    write_manifest(a, inputs + [a.checkpoint], [out_j, out_m], dict(conditions=a.conditions, cache=a.cache))


# ---------------------------------------------------------------- tuning (tuning subjects only, prereg section 2)
_TUNE = {}


def _tune_one(params):
    """Pooled episode error of E with `params` over every cached condition of the tuning sequences + clean change."""
    seqs, conds = _TUNE['seqs'], _TUNE['conds']; ep, clean_d = [], []
    for d, clean, conf0, unit0 in seqs:
        Q, _, _ = v_adaptive(clean, conf0, unit0, d['ex'], params); lo, hi = set_range(d)
        E0 = np.linalg.norm(to_metres(clean, d) - d['G'], axis=-1) * 1000; E1 = np.linalg.norm(to_metres(Q, d) - d['G'], axis=-1) * 1000
        clean_d.append(float(E1[lo:hi].mean() - E0[lo:hi].mean()))
        for cond in conds:
            z = _TUNE['occl'][(seq_key(d), cond)]
            Q, inv, W = v_adaptive(z['rows'], z['conf'], z['unit'], d['ex'], params)
            P = to_metres(Q, d); E = np.linalg.norm(P - d['G'], axis=-1) * 1000
            for s_, e_, joints, *_ in z['eps']:
                ep.append(float(E[s_:e_][:, [COCO2H[j] for j in joints]].mean()))
    return dict(params=params, ep_err=float(np.mean(ep)), clean_delta=float(np.mean(clean_d)), n_ep=len(ep))


def run_tune(a):
    import itertools
    from multiprocessing import Pool
    from finetune_motionagformer_fit3d import mag_input
    seqs = load_seqs(a); conds = [c for c in a.conditions if c != 'clean']; occl = {}; S = []
    for d in seqs:
        assert d['group'] == 'tuning', 'tune runs on tuning subjects only'
        clean = predict_rows(None, None, d['x'], [5], seq_key(d))[5]
        S.append((d, clean, d['x'][..., 2], mag_input(d['K'])[1][:, 2] / 2))
        for cond in conds:
            z = np.load(occl_path(a, d, cond))
            occl[(seq_key(d), cond)] = dict(rows=z['rows'].astype(float), conf=z['x'][..., 2], unit=z['unit'].astype(float),
                                            eps=[tuple(e) for e in json.loads(str(z['episodes']))])
    _TUNE.update(seqs=S, conds=conds, occl=occl)
    balls = [None, (0.08, 0.002), (0.15, 0.002)]
    grid = [dict(reliable_conf=c, decay_frames=dc, max_gap_frames=g, **({} if b is None else dict(ball_base=b[0], ball_growth=b[1])))
            for c, dc, g, b in itertools.product((0.4, 0.5, 0.6), (15.0, 45.0, 135.0), (45, 90, 180), balls)]
    with Pool(a.jobs) as pool:
        res = pool.map(_tune_one, grid)
    # baselines on the same episodes: A (no change), B per alpha, B0 per threshold
    base = {}
    for name, fn in [('A', lambda d, r, c, u: r)] + [(f'B{al}', lambda d, r, c, u, al=al: v_ema(r, al)) for al in (0.3, 0.5, 0.7)] + \
            [(f'B0_{th}', lambda d, r, c, u, th=th: v_lock(r, c, u, th)) for th in (0.4, 0.5, 0.6)]:
        ep = []
        for d, clean, conf0, unit0 in S:
            for cond in conds:
                z = occl[(seq_key(d), cond)]; P = to_metres(fn(d, z['rows'], z['conf'], z['unit']), d)
                E = np.linalg.norm(P - d['G'], axis=-1) * 1000
                ep += [float(E[s_:e_][:, [COCO2H[j] for j in joints]].mean()) for s_, e_, joints, *_ in z['eps']]
        base[name] = float(np.mean(ep))
    ok = [r for r in res if r['clean_delta'] <= 0.5]
    best = min(ok, key=lambda r: r['ep_err']) if ok else None
    md = [f"조정 피험자 {sorted({d['subj'] for d, *_ in S})}, 조건 {len(conds)}개, 가림 {res[0]['n_ep']}개. 기준선: " + ', '.join(f'{k} {v:.1f}' for k, v in base.items()),
          f"선택(깨끗한 입력 변화 ≤ +0.5 mm 중 가림 관절 오차 최소): {json.dumps(best['params']) if best else '없음'}", '',
          '| reliable_conf | decay | max_gap | ball | 가림 관절 오차 | 깨끗한 입력 MPJPE 변화 |', '|---|---|---|---|---|---|']
    for r in sorted(res, key=lambda r: r['ep_err']):
        q = r['params']
        md.append(f"| {q['reliable_conf']} | {q['decay_frames']:.0f} | {q['max_gap_frames']} | {q.get('ball_base', '-')} | {r['ep_err']:.2f} | {r['clean_delta']:+.3f} |")
    out_j, out_m = Path(a.run_dir) / 'tune.json', Path(a.run_dir) / 'tune.md'
    json.dump(dict(results=res, baselines=base, best=best), open(out_j, 'w'), indent=1); out_m.write_text('\n'.join(md) + '\n'); print('\n'.join(md[:12]))
    write_manifest(a, [d['csv'] for d, *_ in S] + [a.checkpoint], [out_j, out_m], dict(conditions=conds, cache=a.cache))


def load_model(a):
    import torch
    from finetune_motionagformer_fit3d import load
    torch.set_num_threads(a.threads)  # Home is shared: 4-6 threads beat 8 under load (measured 2026-10-20)
    return load(a.mag_repo, a.checkpoint, 'cpu')[0].eval(), 'cpu'


def run_cache_clean(a):
    """Raw XS rows (L=5) of the unmodified app input for every sequence -> CACHE (Fit3D-derived: delete after)."""
    model, dev = load_model(a); seqs = load_seqs(a); t0 = time.time()
    for i, d in enumerate(seqs):
        predict_rows(model, dev, d['x'], [5], seq_key(d))
        print(i, seq_key(d), len(d['x']), f'{time.time() - t0:.0f}s', flush=True)
    write_manifest(a, [d['csv'] for d in seqs] + [a.checkpoint], [], dict(cache=a.cache))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['gt-relations', 'cache-clean', 'occlude', 'evaluate', 'foot-shift', 'setup-measure', 'signals', 'tune'])
    p.add_argument('--jobs', type=int, default=4)
    p.add_argument('--cases', type=lambda s: s.split(','), default=list(SHIFT_CASES))
    p.add_argument('--variants', type=lambda s: s.split(','), default=['A', 'B', 'B0', 'C', 'D', 'E', 'F', 'EC'])
    p.add_argument('--params', default='', help='JSON overrides of adaptive_relations.DEFAULTS (E / F / EC / D)')
    p.add_argument('--ema-alpha', type=float, default=0.5); p.add_argument('--lock-thr', type=float, default=0.5)
    p.add_argument('--tag', default='run')
    p.add_argument('--conditions', type=lambda s: s.split(','), default=[f'{g}-{u}' for g in GROUPS for u in DURATIONS])
    p.add_argument('--root'); p.add_argument('--replay'); p.add_argument('--run-dir', required=True)
    p.add_argument('--subjects', type=lambda s: s.split(','), default=['s03', 's04', 's05'])
    p.add_argument('--exercises', type=lambda s: s.split(','), default=list(EXERCISES))
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    p.add_argument('--checkpoint', default=None)
    p.add_argument('--threads', type=int, default=4)
    p.add_argument('--cache', default=os.path.expanduser('~/bpt-runs/setup-constraint/_cache_xs'),
                   help='raw XS rows of the clean app input (Fit3D-derived, delete after the runs)')
    a = p.parse_args()
    a.checkpoint = a.checkpoint or f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr'
    CACHE['dir'] = a.cache
    os.makedirs(a.run_dir, exist_ok=True)
    {'gt-relations': run_gt_relations, 'cache-clean': run_cache_clean, 'occlude': run_occlude, 'evaluate': run_evaluate, 'foot-shift': run_foot_shift, 'setup-measure': run_setup_measure,
     'signals': run_signals, 'tune': run_tune}[a.cmd](a)


if __name__ == '__main__':
    main()
