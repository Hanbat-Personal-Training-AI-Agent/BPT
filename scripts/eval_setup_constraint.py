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
    p.add_argument('cmd', choices=['gt-relations', 'cache-clean', 'occlude', 'evaluate'])
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
    {'gt-relations': run_gt_relations, 'cache-clean': run_cache_clean, 'occlude': run_occlude, 'evaluate': run_evaluate}[a.cmd](a)


if __name__ == '__main__':
    main()
