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


def relation_record(subj, ex, P, ann, fps, up):
    """Stability of each candidate relation over one set: distance from the setup value (1 s before the first rep),
    within-rep wobble, speed; plus the setup ratios. P world [N,17,3] metres (or mm-equivalent / 1000)."""
    s0, s1 = int(ann[0]), int(ann[-1])
    rec = dict(subj=subj, exercise=ex, setup_frames=s0, set_frames=s1 - s0)
    vecs = {k: P[:, b] - P[:, a_] for k, (a_, b) in RELATIONS.items()}
    F = torso_frame(P)
    for side, w in (('l', LWRI), ('r', RWRI)):
        vecs[f'wrist_torso_{side}'] = np.einsum('nij,nj->ni', F, P[:, w] - P[:, THO])
    for nm, j in (('ankle_world_l', LANK), ('ankle_world_r', RANK), ('wrist_world_l', LWRI), ('wrist_world_r', RWRI)):
        vecs[nm] = P[:, j]
    ref_len = float(np.median(body_dims(P[s0:s1])['hip_width']))
    for k, v in vecs.items():
        setup = np.median(v[max(0, s0 - fps):s0], 0) if s0 >= 10 else v[s0]
        dev = np.linalg.norm(v[s0:s1] - setup, axis=-1) * 1000  # mm from the setup value during the set
        step = np.linalg.norm(np.diff(v[s0:s1], axis=0), axis=-1) * 1000 * fps  # mm/s
        reps = [np.linalg.norm(v[x:y] - np.median(v[x:y], 0), axis=-1).max() * 1000 for x, y in zip(ann, ann[1:]) if y > x]
        rec[k] = dict(dev_p50=float(np.median(dev)), dev_p95=float(np.percentile(dev, 95)), dev_max=float(dev.max()),
                      speed_p95=float(np.percentile(step, 95)), within_rep_max_p50=float(np.median(reps)),
                      norm_mm=float(np.median(np.linalg.norm(v[s0:s1], axis=-1)) * 1000), hip_width_mm=ref_len * 1000)
    rr = setup_ratios(P, ex, up)
    rec['setup_ratios'] = {k: float(np.median(v[max(0, s0 - fps):s0])) for k, v in rr.items()}
    rec['set_ratios'] = {k: dict(p5=float(np.percentile(v[s0:s1], 5)), p50=float(np.median(v[s0:s1])), p95=float(np.percentile(v[s0:s1], 95)))
                         for k, v in rr.items()}
    return rec


def run_gt_relations(a):
    recs, dims, inputs = [], {}, []
    if getattr(a, 'dataset', 'fit3d') == 'ex3d':
        seen = set()
        for d in load_ex3d_seqs(a):
            if d['subj'] in seen or len(d['seg']) < 2: continue  # world pseudo-GT is the same for every camera of a clip
            seen.add(d['subj']); ann = [d['seg'][0][0]] + [e for _, e in d['seg']]
            recs.append(relation_record(d['subj'], d['ex'], d['J'], ann, 30, d['R'].T @ d['up_c']))
            dims[d['subj']] = {k: round(float(np.median(v)) * 1000, 1) for k, v in body_dims(d['J']).items()}
            inputs.append(d['csv'])
        head = '**클립별 체형(Exercise3D 의사 정답, mm 환산 = 다리 850 mm 가정)**'
    else:
        up = np.array([0., 0., 1.])  # Fit3D world: z up
        for subj in a.subjects:
            sd = f'{a.root}/train/{subj}'
            ann_all = json.load(open(f'{sd}/rep_ann.json')); inputs.append(f'{sd}/rep_ann.json')
            per = {}
            for ex in EXERCISES:
                P = load_joints(sd, ex)
                if P is None or ex not in ann_all: continue
                inputs.append(f'{sd}/joints3d_25/{ex}.json')
                for k, v in body_dims(P).items(): per.setdefault(k, []).append(v)
                recs.append(relation_record(subj, ex, P, ann_all[ex], FPS50, up))
            dims[subj] = {k: round(float(np.median(np.concatenate(v))) * 1000, 1) for k, v in per.items()}
            print(subj, dims[subj], flush=True)
        head = '**피험자별 체형(모캡 골격, mm, 관절 중심 기준 = oracle)**'
    names = list(RELATIONS) + ['wrist_torso_l', 'wrist_torso_r', 'ankle_world_l', 'ankle_world_r', 'wrist_world_l', 'wrist_world_r']
    summ = dict(body_dims_mm=dims, groups={})
    first = next(iter(dims.values()))
    md = [head, '', '| 피험자 | ' + ' | '.join(first) + ' |', '|---' * (1 + len(first)) + '|']
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
    md += ['', '**셋업(첫 렙 전 1초) 비율**', '', '| 운동 | 피험자 | ' + ' | '.join(['ankle/hip', 'ankle/shoulder', 'wrist/shoulder', 'torso°']) + ' |', '|---' * 6 + '|']
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
MAX_EPISODES = {'short': 3, 'long': 2, 'vlong': 1}  # per video and condition (Home CPU budget, prereg change log)
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
    sched = schedule(lo, hi, DURATIONS[duration], rng)
    keep = sorted(rng.choice(len(sched), min(len(sched), MAX_EPISODES[duration]), replace=False)) if sched else []
    for s, e in [sched[i] for i in keep]:
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


def _forward(model, dev, xb):
    """[B,27,17,3] numpy -> [B,27,17,3] numpy. dev None: `model` is a plain numpy function (tests)."""
    if dev is None:
        return np.asarray(model(xb))
    import torch
    with torch.no_grad():
        return model(torch.from_numpy(xb).to(dev)).cpu().numpy()


def rows_partial(model, dev, x, changed, clean, batch=256):
    """XS rows (L=5) for input x where only frames `changed` differ from the clean input: windows touching a changed
    frame are recomputed, the rest reuse `clean`. Frame t = window [t+L-26, t+L] edge-clamped, row 26-L (the app)."""
    n = len(x); need = np.zeros(n, bool)
    for c in np.flatnonzero(changed):
        need[max(0, c - L5):min(n, c - L5 + WIN)] = True
    t = np.flatnonzero(need); out = clean.copy()
    if len(t):
        idx = np.clip(t[:, None] + L5 - (WIN - 1) + np.arange(WIN)[None], 0, n - 1)
        for s0 in range(0, len(t), batch):
            out[t[s0:s0 + batch]] = _forward(model, dev, x[idx[s0:s0 + batch]])[:, WIN - 1 - L5]
    return out, int(len(t))


def rows_at(model, dev, x, frames, batch=256):
    """XS rows (L=5, the app's window) for the listed output frames only -> {frame: [17,3]}."""
    n = len(x); t = np.asarray(sorted(frames)); out = {}
    idx = np.clip(t[:, None] + L5 - (WIN - 1) + np.arange(WIN)[None], 0, n - 1)
    for s0 in range(0, len(t), batch):
        r = _forward(model, dev, x[idx[s0:s0 + batch]])[:, WIN - 1 - L5]
        out.update({int(f): v.astype(float) for f, v in zip(t[s0:s0 + batch], r)})
    return out


def occl_path(a, d, cond):
    return f"{a.cache}/occl/{cond}/{seq_key(d)}.npz"


def run_occlude(a):
    """XS on the damaged 2D of every condition (group x duration) -> cache npz (rows, damaged K, unit, episodes)."""
    from finetune_motionagformer_fit3d import mag_input
    model, dev = load_model(a); seqs = load_any(a); t0, total = time.time(), 0
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


def episode_records(P, E, inv, W, d, eps, group, E_clean, P_clean=None):
    G, Jw = d['G'], d['J'][d['pick']]; n = len(P); out = []
    for s, e, joints, model, side, near in eps:
        H = [COCO2H[j] for j in joints]
        a_p, a_g = limb_angle(P, side, group), limb_angle(G, side, group)
        a_c = limb_angle(P_clean, side, group) if P_clean is not None else a_p
        stepP = np.linalg.norm(np.diff(P[:, H], axis=0), axis=-1) * 1000; stepG = np.linalg.norm(np.diff(G[:, H], axis=0), axis=-1) * 1000
        lo_j, hi_j = max(s - 1, 0), min(e + RECOVERY, n - 1)
        ev = E[:, H].mean(1); ec = E_clean[:, H].mean(1); rec_k = RECOVERY * 2
        for k in range(0, RECOVERY * 2):
            if e + k + 5 > n: break
            if (ev[e + k:e + k + 5] <= ec[e + k:e + k + 5] + 10).all(): rec_k = k; break
        out.append(dict(model=model, near=bool(near), err=float(ev[s:e].mean()), err_clean=float(ec[s:e].mean()),
                        err_rec=float(ev[e:e + RECOVERY].mean()), err_rec_clean=float(ec[e:e + RECOVERY].mean()),
                        moved=float(np.linalg.norm(Jw[s:e][:, H] - Jw[s][None, H], axis=-1).max() * 1000),
                        angle_err=float(np.nanmean(np.abs(a_p[s:e] - a_g[s:e]))), angle_err_clean=float(np.nanmean(np.abs(a_c[s:e] - a_g[s:e]))),
                        dev_clean=float(np.linalg.norm(P[s:e][:, H] - P_clean[s:e][:, H], axis=-1).mean() * 1000) if P_clean is not None else float('nan'),
                        dev_clean_rec=float(np.linalg.norm(P[e:e + RECOVERY][:, H] - P_clean[e:e + RECOVERY][:, H], axis=-1).mean() * 1000) if P_clean is not None else float('nan'),
                        angle_dev_clean=float(np.nanmean(np.abs(a_p[s:e] - a_c[s:e]))),
                        jump=float(np.max(stepP[lo_j:hi_j] - stepG[lo_j:hi_j])) if hi_j > lo_j else 0.0, recovery_frames=int(rec_k),
                        filled=float((W[s:e][:, H] > 0.5).mean()) if W is not None else 0.0,
                        invalid=float(inv[s:e][:, H].mean()) if inv is not None else 0.0))
    return out


def run_evaluate(a):
    from eval_3d_mediapipe import angle_metrics, angles, pose_metrics
    params = json.loads(a.params) if a.params else {}
    seqs = load_any(a); recs, inputs = [], []
    for d in seqs:
        clean = predict_rows(None, None, d['x'], [5], seq_key(d))[5]
        from finetune_motionagformer_fit3d import mag_input
        conf0, unit0 = d['x'][..., 2], mag_input(d['K'])[1][:, 2] / 2
        P_clean = to_metres(clean, d); E_clean = np.linalg.norm(P_clean - d['G'], axis=-1) * 1000
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
                         episodes=episode_records(P, E, inv, W, d, eps, group, E_clean, P_clean) if eps else [])
                if a.rules and v in a.rules_variants:
                    r['reps'] = rule_reps(P, inv, d, z['K'] if cond != 'clean' else d['K'])
                if cond == 'clean':
                    A_ = angles(P, d['side'], d['up_c']); am = angle_metrics(A_, ref, d['seg'])
                    r['angles'] = {g: dict(rep=float(np.mean(am[g]['rep'])), frame=float(np.mean(am[g]['frame'])), jitter=float(np.mean(am[g]['jitter'])),
                                           lag=lag_frames(A_[g][lo:hi], ref[g][lo:hi]))
                                   for g in ('knee', 'hip', 'elbow', 'torso_g')}
                recs.append(r)
        inputs.append(d['csv']); print(seq_key(d), flush=True)
    summarize_eval(a, recs, inputs, params)


def rule_reps(P, inv, d, K):
    """E5: per rep the fired app rules (lift-app judge_py, camera up = app default) and the metric keys that could be
    computed, on the 3D the evaluators would get (invalid joints NaN). Heights from the same frame's 2D (0dda987)."""
    from pose_feedback.body.form_metrics_3d import UP
    side = {'L': 'left', 'R': 'right'}[d['side']]; sh, hp = {'left': (5, 11), 'right': (6, 12)}[side]
    two = [dict(hipY=float(K[t, hp, 1]), shoulderY=float(K[t, sh, 1]), torsoLength=float(np.hypot(*(K[t, sh, :2] - K[t, hp, :2]))))
           for t in range(len(K))]
    Pm = P.copy()
    if inv is not None: Pm[inv] = np.nan
    out = lf.rep_records(Pm, d['seg'], d['ex'], side, UP, {}, two)
    return [dict(fired=sorted(r['fired']), keys=sorted(r['m'])) for r in out]


def lag_frames(a, r, max_lag=10):
    """Delay of trajectory a behind r in frames (argmax of the normalised cross-correlation, -10..10; > 0 = late)."""
    a, r = np.asarray(a, float), np.asarray(r, float); ok = np.isfinite(a) & np.isfinite(r)
    if ok.sum() < 3 * max_lag: return float('nan')
    a, r = (a - np.nanmean(a[ok])) * ok, (r - np.nanmean(r[ok])) * ok
    a, r = np.nan_to_num(a), np.nan_to_num(r); n = len(a)
    c = [float(np.dot(a[k:], r[:n - k]) if k >= 0 else np.dot(a[:n + k], r[-k:])) for k in range(-max_lag, max_lag + 1)]
    return float(np.argmax(c) - max_lag)


def boot_ci(x, n=2000, seed=0):
    x = np.asarray(x, float); x = x[np.isfinite(x)]
    if len(x) < 2: return [float('nan')] * 2
    rng = np.random.default_rng(seed); m = rng.choice(x, (n, len(x))).mean(1)
    return [float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))]


def summarize_eval(a, recs, inputs, params):
    summ = dict(params=params, ema_alpha=a.ema_alpha, lock_thr=a.lock_thr, groups={}, paired={})
    keyf = lambda r: (r['group'], r['cond'], r['exercise'])
    md = [f"params={json.dumps(params)} ema_alpha={a.ema_alpha} lock_thr={a.lock_thr}", '',
          '| 묶음 | 조건 | 운동 | 변형 | 영상 | MPJPE(세트) | PA | 가속도 | 무효 관절 | 바뀐 관절 | 가림 관절 오차 (깨끗한 입력 A) | 복구 30f 오차 | 복구 프레임 p50 | 사지 각 오차 (깨끗한 A) | 점프 p95 | 채움 | 가림 중 무효 | 깨끗한 A와의 거리 가림 / 복구 mm | 사지 각 거리 ° |',
          '|---' * 19 + '|']
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
                        g.update({k: float(np.mean([e[k] for e in ep])) for k in ('err', 'err_clean', 'err_rec', 'err_rec_clean', 'angle_err', 'angle_err_clean', 'filled', 'invalid', 'dev_clean', 'dev_clean_rec', 'angle_dev_clean')},
                                 recovery_p50=float(np.median([e['recovery_frames'] for e in ep])), jump_p95=float(np.percentile([e['jump'] for e in ep], 95)))
                        for m in CORRUPTIONS + ('near', 'far', 'moved', 'static'):
                            sel = [e for e in ep if (e['model'] == m) or (m == 'near' and e['near']) or (m == 'far' and not e['near'])
                                   or (m == 'moved' and e['moved'] > 50) or (m == 'static' and e['moved'] <= 50)]
                            if sel: g[f'err_{m}'] = float(np.mean([e['err'] for e in sel])); g[f'n_{m}'] = len(sel)
                    if 'angles' in rs[0]:
                        g['angles'] = {k: {q: float(np.nanmean([r['angles'][k].get(q, np.nan) for r in rs])) for q in ('rep', 'frame', 'jitter', 'lag')} for k in rs[0]['angles']}
                    summ['groups'][f'{grp}/{cond}/{ex}/{v}'] = g
                    f = lambda k, fmt='{:.1f}': fmt.format(g[k]) if k in g else '-'
                    md.append(f"| {grp} | {cond} | {ex} | {v} | {g['videos']} | {g['mpjpe']:.1f} | {g['pa']:.1f} | {g['accel']:.2f} | {g['invalid']:.1%} | {g['changed']:.1%} | "
                              f"{f('err')} ({f('err_clean')}) | {f('err_rec')} | {f('recovery_p50', '{:.0f}')} | {f('angle_err')} ({f('angle_err_clean')}) | {f('jump_p95')} | {f('filled', '{:.0%}')} | {f('invalid', '{:.0%}')} | "
                              f"{f('dev_clean')} / {f('dev_clean_rec')} | {f('angle_dev_clean')} |")
            # paired per-video differences (bootstrap over videos) of the episode error / clean MPJPE
            for x, y in (('E', 'A'), ('E', 'B'), ('E', 'B0'), ('E', 'D'), ('F', 'E'), ('EC', 'C'), ('B', 'A'), ('C', 'A'), ('D', 'A')):
                key = lambda r: (r['subj'], r['cam'], r['exercise'])
                rx = {key(r): r for r in recs if r['group'] == grp and r['cond'] == cond and r['var'] == x}
                ry = {key(r): r for r in recs if r['group'] == grp and r['cond'] == cond and r['var'] == y}
                ks = sorted(set(rx) & set(ry))
                if not ks: continue
                if cond != 'clean':
                    for m in ('err', 'dev_clean'):
                        dif = [np.mean([e[m] for e in rx[k_]['episodes']]) - np.mean([e[m] for e in ry[k_]['episodes']]) for k_ in ks if rx[k_]['episodes']]
                        summ['paired'][f'{grp}/{cond}/{x}-{y}' + ('' if m == 'err' else '/dev')] = dict(n=len(dif), mean=float(np.mean(dif)) if dif else None, ci95=boot_ci(dif))
                else:
                    dif = [rx[k_]['mpjpe'] - ry[k_]['mpjpe'] for k_ in ks]
                    summ['paired'][f'{grp}/{cond}/{x}-{y}'] = dict(n=len(dif), mean=float(np.mean(dif)) if dif else None, ci95=boot_ci(dif))
    md += ['', '**짝지은 차이 (영상 단위 평균, 부트스트랩 95% CI; 가림 조건 = 가림 관절 오차 mm, /dev = 깨끗한 입력 A와의 거리 mm(정답 없이), clean = 세트 MPJPE mm)**', '', '| 키 | n | 평균 | 95% CI |', '|---|---|---|---|']
    for k_, v in summ['paired'].items():
        md.append(f"| {k_} | {v['n']} | {v['mean']:.2f} | {v['ci95'][0]:.2f} – {v['ci95'][1]:.2f} |" if v['mean'] is not None else f'| {k_} | 0 | - | - |')
    if any('reps' in r for r in recs):
        md += ['', '**E5 정상 렙 규칙 발동률 (lift-app judge_py, 카메라 위 = 앱 기본; 판정 가능 = 그 규칙의 지표가 계산된 렙)**', '',
               '| 묶음 | 조건 | 운동 | 변형 | 렙 | 규칙별 발동률 | 지표 계산 비율(elbow_min / knee_min / hip_dev_min / torso_mean) |', '|---' * 7 + '|']
        for grp in dict.fromkeys(r['group'] for r in recs):
            for cond in conds:
                for ex in EXERCISES:
                    for v in vs:
                        rs = [r for r in recs if r['group'] == grp and r['cond'] == cond and r['var'] == v and r['exercise'] == ex and 'reps' in r]
                        reps = [x for r in rs for x in r['reps']]
                        if not reps: continue
                        fire = {k: float(np.mean([k in x['fired'] for x in reps])) for k in lf.RULES_BY_EX[ex]}
                        valid = {k: float(np.mean([k in x['keys'] for x in reps])) for k in ('elbow_min', 'knee_min', 'hip_dev_min', 'torso_mean')}
                        summ['groups'].setdefault(f'{grp}/{cond}/{ex}/{v}', {})['rules'] = dict(reps=len(reps), fire=fire, valid=valid)
                        md.append(f"| {grp} | {cond} | {ex} | {v} | {len(reps)} | " + ', '.join(f'{k.split("_", 1)[1]} {x:.0%}' for k, x in fire.items()) +
                                  ' | ' + ' / '.join(f'{x:.0%}' for x in valid.values()) + ' |')
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
    if 'project' in d:
        proj = d['project']
    else:
        from pose_feedback.body.pose2d_data import project_fit3d
        cam = json.load(open(f"{a.root}/train/{d['subj']}/camera_parameters/{d['cam']}/{d['ex']}.json"))
        proj = lambda P_: project_fit3d(P_, cam)
    Jp = d['J'][d['pick']]; n = len(Jp); t = np.arange(n)
    lr = Jp[plan['start'], LHIP] - Jp[plan['start'], RHIP]
    up = np.array([0., 0., 1.]) if 'project' not in d else d['R'].T @ d['up_c']  # world up (Fit3D z; Ex3D from the cameras)
    lr = lr - up * float(lr @ up); lr /= np.linalg.norm(lr)
    ank, kne, cank, ckne = (LANK, LKNE, 15, 13) if plan['side'] == 'L' else (RANK, RKNE, 16, 14)
    outward = lr if plan['side'] == 'L' else -lr
    delta = plan['amp'] * np.clip((t - plan['start']) / plan['ramp'], 0, 1)[:, None] * outward[None]  # world m
    K = d['K'].copy(); G = d['G'].copy(); R = d['R']
    for j, cj, f in ((ank, cank, 1.0), (kne, ckne, 0.5)):
        moved = t >= plan['start']
        K[moved, cj, :2] += proj(Jp[moved, j] + f * delta[moved]) - proj(Jp[moved, j])
        G[:, j] += f * delta @ R.T
    if plan['occl']:
        s0, e0 = plan['start'], min(n, plan['start'] + plan['ramp'] + SHIFT_OCC_EXTRA)
        K = corrupt(K, [(s0, e0, [cank], plan['model'])], rng_for(seq_key(d), 'shift-damage'))
    return K, G, delta @ R.T


def run_foot_shift(a):
    """XS on the shifted input of every case (cache), then variants on clean vs shifted input (paired)."""
    from finetune_motionagformer_fit3d import mag_input
    params = json.loads(a.params) if a.params else {}
    model = dev = None; seqs = load_any(a); recs, inputs = [], []
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
                chg = np.abs(xs - d['x']).max((1, 2)) > 1e-7
                chg[plan['start'] + plan['ramp'] + SHIFT_OCC_EXTRA + 70:] = False  # frames after W2 are never scored (CPU)
                rows, _ = rows_partial(model, dev, xs, chg, clean)
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
        sam = None  # non-oracle body: lift-refine SAM 3D Body -> SMPL targets (calibration-result shape), when given
        if a.shapes and os.path.exists(f"{a.shapes}/targets/{d['subj']}.json"):
            sg = json.load(open(f"{a.shapes}/targets/{d['subj']}.json"))['boneLengthData']['segments']; inputs.append(f"{a.shapes}/targets/{d['subj']}.json")
            th_s = (sg['right_hip-right_knee'] + sg['left_hip-left_knee']) / 2
            sam = np.linalg.norm(raw[:, LANK] - raw[:, RANK], axis=-1) / (thigh_xs * sg['hip_width'] / th_s)
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
                if sam is not None: r['transfer_sam'] = float(np.nanmedian(sam[w]))
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
          '| 묶음 | 운동 | 항목 | 시점 | n | 모캡 중앙값 | XS 오차 |중앙값| (p90) | XS+제약 | 2D 오차 | 체형 전이 오차 oracle / SAM 3D Body | 창 안 SD | 렙 꼭대기 오경보(같은 영상) | 다른 카메라 오경보 | cm 오차 XS / 전이 (모캡 cm 중앙값) |',
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
                    es = np.array([abs(i['transfer_sam'] - i['gt']) for i in it if 'transfer_sam' in i])
                    t_ = tol.get(k, float('nan'))
                    fc = [abs(x - i['xs_raw']) > t_ for i in it for x in i['xs_raw_tops'][1:]]
                    xc = []
                    if b == 'all':
                        for subj in {r['subj'] for r in rs}:
                            vals = [r['items'][k]['xs_raw'] for r in rs if r['subj'] == subj]
                            xc += [abs(u - v) > t_ for i_, u in enumerate(vals) for v in vals[i_ + 1:]]
                    cm = [i['cm'] for i in it if 'cm' in i]
                    g = dict(n=len(rs), gt_median=float(np.median([i['gt'] for i in it])), xs_abs_err_p50=float(np.median(e)), xs_abs_err_p90=float(np.percentile(e, 90)),
                             xs_c_abs_err_p50=float(np.median(ec)), err_2d_p50=float(np.median(e2)) if len(e2) else None, transfer_err_p50=float(np.median(et)) if len(et) else None, transfer_sam_err_p50=float(np.median(es)) if len(es) else None,
                             sd_p50=float(np.median([i['xs_raw_sd'] for i in it])), false_cue_reptops=float(np.mean(fc)) if fc else None,
                             false_cue_cross_cam=float(np.mean(xc)) if xc else None, depth_p50=float(np.median([i['depth'] for i in it])))
                    if cm:
                        g['cm_err_xs_p50'] = float(np.median([abs(c['xs'] - c['gt']) for c in cm])); g['cm_gt_p50'] = float(np.median([c['gt'] for c in cm]))
                        if 'transfer' in cm[0]: g['cm_err_transfer_p50'] = float(np.median([abs(c['transfer'] - c['gt']) for c in cm]))
                    summ['groups'][f'{grp}/{ex}/{k}/{b}'] = g
                    fmt = lambda v, f_='{:.2f}': '-' if v is None else f_.format(v)
                    md.append(f"| {grp} | {ex} | {k} | {b} | {g['n']} | {g['gt_median']:.2f} | {g['xs_abs_err_p50']:.2f} ({g['xs_abs_err_p90']:.2f}) | {g['xs_c_abs_err_p50']:.2f} | "
                              f"{fmt(g['err_2d_p50'])} | {fmt(g['transfer_err_p50'])} / {fmt(g['transfer_sam_err_p50'])} | {g['sd_p50']:.3f} | {fmt(g['false_cue_reptops'], '{:.0%}')} | {fmt(g['false_cue_cross_cam'], '{:.0%}')} | "
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
    seqs = load_any(a); feats = {k: [] for k in ('conf', 'temporal', 'reproj', 'bone')}; err, jt, cond_of, inputs = [], [], [], []
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
    seqs = load_any(a); conds = [c for c in a.conditions if c != 'clean']; occl = {}; S = []
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


# ---------------------------------------------------------------- method 2: RGB occlusion (masks from eval_setup_rgb_occlusion.py)
def run_rgb_eval(a):
    """Same mmpose RTMPose-m 2D with and without the painted joint (same RTMDet box) -> XS -> variants. The clean
    reference here is the unpainted mmpose 2D (A-pose2d), not the app CSV, so the paint is the only difference."""
    from finetune_motionagformer_fit3d import mag_input
    from pose_feedback.body.pose2d_data import project_fit3d
    params = json.loads(a.params) if a.params else {}
    model, dev = load_model(a); seqs = {seq_key(d): d for d in load_seqs(a)}; recs, inputs, twod = [], [], []
    for path in sorted(Path(a.rgb).glob('*.npz')):
        key = path.stem; subj, cam, ex = key.split('_', 2); d0 = seqs.get(f'{subj}_{cam}_{ex}')
        if d0 is None: continue
        A = np.load(f'{a.pose2d}/{key}.npz'); Ap = A['pick']; idx = np.searchsorted(Ap, d0['pick'])
        assert (Ap[np.minimum(idx, len(Ap) - 1)] == d0['pick']).all(), key
        Kmm = A['coco'][idx].astype(float)
        x, crops = mag_input(Kmm); _, crops0 = mag_input(d0['K'])
        d = dict(d0, K=Kmm, x=x, mm=d0['mm'] * crops[:, 2] / crops0[:, 2])
        ck = f"{a.cache}/rgb/{key}_clean.npz"
        if os.path.exists(ck): clean = np.load(ck)['rows'].astype(float)
        else:
            clean, _ = rows_partial(model, dev, x, np.ones(len(x), bool), np.zeros((len(x), 17, 3)))
            os.makedirs(os.path.dirname(ck), exist_ok=True); np.savez(ck, rows=clean.astype(np.float32))
        z = np.load(path); fr, kp = z['frames'], z['coco']; eps_j = json.loads(str(z['episodes']))
        Km = Kmm.copy(); Km[fr] = kp
        xm, cm = mag_input(Km); rows, nw = rows_partial(model, dev, xm, np.abs(xm - x).max((1, 2)) > 1e-7, clean)
        camj = json.load(open(f'{a.root}/train/{subj}/camera_parameters/{cam}/{ex}.json')); Jp = d0['J'][d0['pick']]
        P_clean = to_metres(clean, d); E_clean = np.linalg.norm(P_clean - d['G'], axis=-1) * 1000
        for g in dict.fromkeys(e['group'] for e in eps_j):
            eps = [(e['s'], e['e'], [e['coco']], 'rgb', e['side'], e['side'] == d['side']) for e in eps_j if e['group'] == g]
            for s_, e_, joints, *_ in eps:
                j = joints[0]; gt2 = project_fit3d(Jp[s_:e_, COCO2H[j]], camj)
                twod.append(dict(group=g, conf_clean=float(Kmm[s_:e_, j, 2].mean()), conf_mask=float(Km[s_:e_, j, 2].mean()),
                                 px_clean=float(np.linalg.norm(Kmm[s_:e_, j, :2] - gt2, axis=-1).mean()),
                                 px_mask=float(np.linalg.norm(Km[s_:e_, j, :2] - gt2, axis=-1).mean())))
            for v, (Q, inv, W) in all_variants(rows, xm[..., 2], cm[:, 2] / 2, d, params, a.ema_alpha, a.lock_thr, a.variants).items():
                P = to_metres(Q, d); E = np.linalg.norm(P - d['G'], axis=-1) * 1000; lo, hi = set_range(d)
                recs.append(dict(group=d['group'], exercise=ex, subj=subj, cam=cam, bin=d['bin'], cond=f'rgb-{g}', var=v,
                                 mpjpe=float(E[lo:hi].mean()), pa=float('nan'), accel=float('nan'),
                                 invalid=float(inv[lo:hi].mean()) if inv is not None else 0.0,
                                 changed=float((np.abs(Q - rows).max(-1) > 1e-9)[lo:hi].mean()),
                                 episodes=episode_records(P, E, inv, W, d, eps, g, E_clean, P_clean)))
        inputs += [str(path), f'{a.pose2d}/{key}.npz']; print(key, nw, flush=True)
    md2 = ['**RTMPose가 칠한 관절에 보인 반응 (같은 박스, 모캡 투영 대비 px)**', '', '| 묶음 | 가림 | 신뢰도 깨끗 → 칠함 | 2D 오차 px 깨끗 → 칠함 |', '|---|---|---|---|']
    for g in dict.fromkeys(t['group'] for t in twod):
        ts = [t for t in twod if t['group'] == g]
        md2.append(f"| {g} | {len(ts)} | {np.mean([t['conf_clean'] for t in ts]):.2f} → {np.mean([t['conf_mask'] for t in ts]):.2f} | "
                   f"{np.mean([t['px_clean'] for t in ts]):.1f} → {np.mean([t['px_mask'] for t in ts]):.1f} |")
    a.tag = f'rgb_{a.tag}'
    Path(a.run_dir).mkdir(parents=True, exist_ok=True); (Path(a.run_dir) / 'rgb_2d.md').write_text('\n'.join(md2) + '\n'); print('\n'.join(md2))
    summarize_eval(a, recs, inputs, params)


# ---------------------------------------------------------------- E1b setup items on Exercise3D side / front views (Mac OK: not Fit3D)
EX3D_HELDOUT = {'squat_0002', 'barbellrow_0001', 'barbellrow_0003'}  # P2 / P3 (docs/decisions.md person split)


def run_setup_ex3d(a):
    """Setup items from the app 2D (RTMPose-m CSV) -> XS (L=5) vs Exercise3D canonical_3d (Sapiens triangulation =
    PSEUDO ground truth, not truth), per camera view (side <= 40 deg, diagonal 40-75, front > 75). Also the pseudo-GT
    foot geometry (heels / big toes): how far the ankle-centre distance is from the heel / toe distances."""
    from pose_feedback.body.exercise_setup import depth_share
    from pose_feedback.body.form_metrics_3d import UP
    model, dev = load_model(a); recs, inputs = [], [f'{a.ex3d}/gt.json']
    gt = json.load(open(f'{a.ex3d}/gt.json'))
    for d in load_ex3d_seqs(a):
        seq, ex = d['subj'], d['ex']; n = len(d['x'])
        z = np.load(f'{a.ex3d}/labels/{seq}/geometry/canonical_3d.npz'); names = list(z['joint_names']); Pw = z['keypoints_3d'][:n].astype(float)
        foot = {k: Pw[:, names.index(k)] for k in ('left_heel', 'right_heel', 'left_big_toe', 'right_big_toe')}
        rf = gt[seq]['rep_frames']; half = int(np.median(np.diff(rf)) / 2) if len(rf) > 1 else 15
        w1 = rf[0] - half; w0 = max(0, w1 - SETUP_WINDOW)
        if w1 - w0 < SETUP_WINDOW // 2: continue
        w = slice(w0, w1)
        R_ = rows_at(model, dev, d['x'], range(w0, w1)); P = np.full((n, 17, 3), np.nan)
        for f_, v_ in R_.items(): P[f_] = v_
        P[:w0] = P[w0]; P[w1:] = P[w1 - 1]  # only the setup window is scored; the rest is filler for item_series
        G = d['G']; xs, gs = item_series(P, ex, UP), item_series(G, ex, d['up_c'])
        ank = np.linalg.norm(Pw[:, names.index('left_ankle')] - Pw[:, names.index('right_ankle')], axis=-1)
        heel = np.linalg.norm(foot['left_heel'] - foot['right_heel'], axis=-1); toe = np.linalg.norm(foot['left_big_toe'] - foot['right_big_toe'], axis=-1)
        rec = dict(seq=seq, exercise=ex, cam=d['cam'], view=d['view'], vbin=d['bin'], group=d['group'], align_px=d['align_px'], items={})
        for k in gs:
            rec['items'][k] = dict(gt=float(np.nanmedian(gs[k][w])), xs=float(np.nanmedian(xs[k][w])), xs_sd=float(np.nanstd(xs[k][w])),
                                   depth=float(np.nanmedian([depth_share(q, k) for q in G[w]])))
        rec['foot'] = dict(heel_over_ankle=float(np.nanmedian(heel[w] / ank[w])), toe_over_ankle=float(np.nanmedian(toe[w] / ank[w])))
        recs.append(rec); inputs.append(d['csv']); print(seq, d['cam'], flush=True)
    md = ['Exercise3D = Sapiens 삼각측량 **의사 정답**(정답 아님). 묶음 = P1(조정) / P2·P3(검증). 셋업 창 = 첫 렙 저점 − 렙 간격/2 앞 1초.', '',
          '| 묶음 | 운동 | 항목 | 시점 | 영상 | 의사 정답 중앙값 | XS 오차 |중앙값| (최대) | 창 안 SD | 깊이 비율 중앙값 |', '|---' * 9 + '|']
    summ = {}
    for grp in ('tuning', 'heldout'):
        for ex in EXERCISES:
            for k in sorted({k for r in recs if r['exercise'] == ex for k in r['items']}):
                for vb in ('side', 'diag', 'front'):
                    rs = [r for r in recs if r['group'] == grp and r['exercise'] == ex and r['vbin'] == vb and k in r['items']]
                    if not rs: continue
                    it = [r['items'][k] for r in rs]; e = [abs(i['xs'] - i['gt']) for i in it if np.isfinite(i['xs']) and np.isfinite(i['gt'])]
                    if not e: continue
                    gsum = dict(n=len(rs), gt=float(np.median([i['gt'] for i in it])), err_p50=float(np.median(e)), err_max=float(np.max(e)),
                                sd=float(np.median([i['xs_sd'] for i in it])), depth=float(np.median([i['depth'] for i in it])))
                    summ[f'{grp}/{ex}/{k}/{vb}'] = gsum
                    md.append(f"| {grp} | {ex} | {k} | {vb} | {gsum['n']} | {gsum['gt']:.2f} | {gsum['err_p50']:.2f} ({gsum['err_max']:.2f}) | {gsum['sd']:.3f} | {gsum['depth']:.2f} |")
    fo = [r['foot'] for r in recs]
    md += ['', f"의사 정답 발 형상(셋업 창, 클립×카메라 중복 제외 전 {len(fo)}개): 뒤꿈치 간 / 발목 간 중앙값 {np.median([x['heel_over_ankle'] for x in fo]):.2f}, "
           f"엄지발가락 간 / 발목 간 중앙값 {np.median([x['toe_over_ankle'] for x in fo]):.2f} (범위 {np.min([x['toe_over_ankle'] for x in fo]):.2f}–{np.max([x['toe_over_ankle'] for x in fo]):.2f})"]
    out_j, out_m = Path(a.run_dir) / 'setup_ex3d.json', Path(a.run_dir) / 'setup_ex3d.md'
    json.dump(dict(summary=summ, records=recs), open(out_j, 'w')); out_m.write_text('\n'.join(md) + '\n'); print('\n'.join(md))
    write_manifest(a, inputs + [a.checkpoint], [out_j, out_m], dict(device=dev))


# ---------------------------------------------------------------- Exercise3D sequences in the Fit3D record shape (Mac OK)
EX3D_LEG_MM = 850.0  # Ex3D world units are an arbitrary gauge: lengths are reported as mm-equivalent for a 850 mm leg


def load_ex3d_seqs(a):
    """Exercise3D app CSV (RTMPose-m) + canonical_3d PSEUDO ground truth, per sequence x camera, as the dicts the
    Fit3D studies use (x, K, G, mm, seg, side, up_c, J, pick, R, group, bin, view, csv, project). Lengths are
    mm-equivalent (pseudo-GT leg length scaled to EX3D_LEG_MM) - relation-stability / suppression checks only."""
    import ast
    from eval_3d_angles import EX3D_NAMES, read_csv
    from finetune_motionagformer_fit3d import mag_input
    gt = json.load(open(f'{a.ex3d}/gt.json')); exname = {'squat': 'squat', 'pushup': 'pushup', 'barbellrow': 'barbell_row'}; out = []
    for seq, g in gt.items():
        ex = exname.get(g['exercise'])
        if ex is None or ex not in a.exercises: continue
        z = np.load(f'{a.ex3d}/labels/{seq}/geometry/canonical_3d.npz'); names = list(z['joint_names']); Pw = z['keypoints_3d'].astype(float)
        Jw = np.stack([Pw[:, names.index(nm)] if nm else np.full((len(Pw), 3), np.nan) for nm in EX3D_NAMES], 1)
        Jw[:, 7], Jw[:, 10] = (Jw[:, 0] + Jw[:, 8]) / 2, Jw[:, 9]
        bad = np.isnan(Jw).any((1, 2))
        if bad.any():  # barbellrow_0003: 64 label frames NaN -> linear interpolation (recorded in the report)
            t_ = np.arange(len(Jw))
            for j in range(17):
                for c in range(3): Jw[bad, j, c] = np.interp(t_[bad], t_[~bad], Jw[~bad, j, c])
        leg = np.nanmedian(np.linalg.norm(Jw[:, 1] - Jw[:, 2], axis=-1) + np.linalg.norm(Jw[:, 2] - Jw[:, 3], axis=-1))
        k_mm = EX3D_LEG_MM / leg  # units -> mm-equivalent
        cg = json.load(open(f'{a.ex3d}/labels/{seq}/geometry/metadata.json'))['camera_geometry']; cg = ast.literal_eval(cg) if isinstance(cg, str) else cg
        up_w = -np.mean([np.array(v['extrinsic_world_to_camera'])[1, :3] for v in cg.values()], axis=0); up_w /= np.linalg.norm(up_w)
        rf = g['rep_frames']; half = int(np.median(np.diff(rf)) / 2) if len(rf) > 1 else 15
        views = g['views'].items()
        if getattr(a, 'ex3d_view', 'all') == 'side1':  # one camera per clip: the most side-on (CPU budget)
            views = [min(views, key=lambda kv: kv[1]['angle_deg'])]
        for cam, v in views:
            hits = sorted(Path(f'{a.ex3d}/csv/{seq}').glob(f'{cam}_*_mcoco17.csv'))
            if cam not in cg or not hits: continue
            csv = str(hits[0]); K = read_csv(csv); n = min(len(K), len(Jw)); K = K[:n]; x, crops = mag_input(K)
            E = np.array(cg[cam]['extrinsic_world_to_camera'], float); R, T = E[:, :3], E[:, 3]; Kin = np.array(cg[cam]['intrinsic_working_frame'], float)
            # alignment audit: projected pseudo-GT vs the app 2D (ankles, wrists, hips). The CSV pixels are in the source
            # video resolution, the label intrinsics in the 720 x 1280 working frame -> one scale (spread ratio, median).
            pg = lambda P_: (lambda c: (c[:, :, :2] / c[:, :, 2:3]) @ Kin[:2, :2].T + Kin[:2, 2])(P_ @ R.T + T)
            proj2 = pg(Jw[:n][:, [3, 6, 13, 16, 1, 4]]); k2 = K[:, [16, 15, 9, 10, 12, 11], :2]
            spread = lambda q: np.linalg.norm(q - q.mean(1, keepdims=True), axis=-1).mean(1)
            px_scale = float(np.median(spread(k2) / spread(proj2)))
            proj2 = proj2 * px_scale
            off = {o: float(np.nanmedian(np.linalg.norm(proj2[max(0, o):n + min(0, o)] - k2[max(0, -o):n - max(0, o)], axis=-1))) for o in range(-3, 4)}
            if min(off, key=off.get) != 0: print('WARN offset', seq, cam, {k_: round(v_, 1) for k_, v_ in off.items()}, flush=True)
            Xc = Jw[:n] @ R.T + T
            unit = crops[:, 2] / 2 * Xc[:, 0, 2] / (Kin[0, 0] * px_scale)  # pseudo-GT units per crop unit (weak perspective at the root)
            d = dict(subj=seq, ex=ex, cam=cam, x=x, K=K, pick=np.arange(n), csv=csv, R=R, J=Jw[:n] * k_mm / 1000,
                     G=(Xc - Xc[:, :1]) * k_mm / 1000, mm=(unit * k_mm).astype(np.float32), up_c=R @ up_w,
                     seg=[(max(0, r - half), min(n - 1, r + half)) for r in rf if r + half < n], side='L' if v['near_side'] == 'left' else 'R',
                     view=float(v['angle_deg']), group='heldout' if seq in EX3D_HELDOUT else 'tuning',
                     project=lambda P_, R=R, T=T, Kin=Kin, k=k_mm, sc=px_scale: sc * ((lambda c: (c[:, :2] / c[:, 2:3]) @ Kin[:2, :2].T + Kin[:2, 2])((P_ * 1000 / k) @ R.T + T)))
            d['bin'] = 'side' if d['view'] <= 40 else 'diag' if d['view'] <= 75 else 'front'
            d['align_px'] = off[0]; d['label_nan_frames'] = int(bad.sum()); d['px_scale'] = px_scale
            out.append(d)
    print(len(out), 'Exercise3D sequences (pseudo-GT)', flush=True)
    return out


def load_any(a):
    seqs = load_ex3d_seqs(a) if getattr(a, 'dataset', 'fit3d') == 'ex3d' else load_seqs(a)
    if getattr(a, 'cams', None):  # Home CPU budget: e.g. 2 of the 4 Fit3D cameras for the tuning grid
        seqs = [d for d in seqs if d['cam'] in a.cams]
    return seqs


# ---------------------------------------------------------------- prereg verdicts (section 5) from saved results
def run_verdicts(a):
    """R1-R6 of docs/results/setup_constraint_prereg.md from an evaluate JSON (+ foot_shift JSON). No new compute."""
    ev = json.load(open(a.eval_json)); recs = ev['records']; grp = a.group
    occl = [c for c in dict.fromkeys(r['cond'] for r in recs) if c != 'clean']
    key = lambda r: (r['subj'], r['cam'], r['exercise'], r['cond'])
    by = {}
    for r in recs:
        if r['group'] == grp: by.setdefault(r['var'], {})[key(r)] = r
    def paired(x, y, metric='err', conds=occl):
        ks = [k for k in by.get(x, {}) if k in by.get(y, {}) and k[3] in conds and by[x][k]['episodes']]
        per = {}
        for k in ks:  # per video: mean over its episodes of every condition
            v = k[:3]; per.setdefault(v, [[], []])
            per[v][0] += [e[metric] for e in by[x][k]['episodes']]; per[v][1] += [e[metric] for e in by[y][k]['episodes']]
        d = [np.mean(p[0]) - np.mean(p[1]) for p in per.values()]
        base = [np.mean(p[1]) for p in per.values()]
        return dict(n=len(d), mean=float(np.mean(d)) if d else None, ci95=boot_ci(d), rel=float(np.mean(d) / np.mean(base)) if d else None)
    out, md = {}, [f'**사전등록 판정 ({grp}, {Path(a.eval_json).name})** — 규칙은 제안(미승인)', '']
    r1 = paired('E', 'A'); ok1 = r1['ci95'][1] < 0 and r1['rel'] <= -0.05
    out['R1'] = dict(E_minus_A=r1, pass_=bool(ok1))
    md.append(f"- R1 가림 이득(E − A, 가림 관절 오차): {r1['mean']:+.2f} mm (CI {r1['ci95'][0]:+.2f} – {r1['ci95'][1]:+.2f}, 상대 {r1['rel']:+.1%}, 영상 {r1['n']}) → {'통과' if ok1 else '실패'}")
    for x, y in (('EC', 'C'), ('E', 'B'), ('E', 'B0'), ('E', 'D'), ('F', 'E'), ('B', 'A'), ('C', 'A'), ('D', 'A'), ('B0', 'A')):
        q = paired(x, y); out[f'{x}-{y}'] = q
        md.append(f"  - {x} − {y}: {q['mean']:+.2f} mm (CI {q['ci95'][0]:+.2f} – {q['ci95'][1]:+.2f}, 상대 {q['rel']:+.1%})" if q['mean'] is not None else f'  - {x} − {y}: -')
    cl = lambda v: [r for k, r in by.get(v, {}).items() if k[3] == 'clean']
    if cl('E') and cl('A'):
        dm = float(np.mean([r['mpjpe'] for r in cl('E')]) - np.mean([r['mpjpe'] for r in cl('A')]))
        da = float(np.mean([r['accel'] for r in cl('E')]) / np.mean([r['accel'] for r in cl('A')]) - 1)
        ok2 = dm <= 0.5 and da <= 0.03; out['R2'] = dict(mpjpe_delta=dm, accel_rel=da, pass_=bool(ok2))
        md.append(f"- R2 깨끗한 입력(E − A): MPJPE {dm:+.2f} mm, 가속도 {da:+.1%} → {'통과' if ok2 else '실패'}")
    if a.shift_json:
        fs = json.load(open(a.shift_json))['summary']
        g = lambda case, v, w: fs.get(f'{grp}/{case}/all/{v}', {}).get(f'supp_A_{w}')
        obs = [g(c, 'E', 'W2') for c in ('grad2', 'grad5', 'step')]; obs_r = [g(c, 'E', 'ramp') for c in ('grad2', 'grad5', 'step')]
        o = [x for x in obs + obs_r if x is not None]
        ok3a = bool(o) and max(o) <= 0.05
        occ = {c: {w: (g(c, 'E', w), g(c, 'B0', w)) for w in ('W1', 'W2')} for c in ('occ_grad5', 'occ_step')}
        ok3b = all(v[0] is not None and v[1] is not None and v[0] < v[1] for c in occ.values() for v in c.values()) and \
            all(c['W2'][0] is not None and c['W2'][0] <= 0.10 for c in occ.values())
        out['R3'] = dict(observed=o, occluded=occ, pass_=bool(ok3a and ok3b))
        md.append(f"- R3 실제 움직임 보존: 관측된 이동 E 억제율(A 대비) 최대 {max(o) if o else float('nan'):.1%}; 가림 중 이동 " +
                  ', '.join(f"{c} W1 {v['W1'][0]:.0%}(B0 {v['W1'][1]:.0%}) W2 {v['W2'][0]:.0%}(B0 {v['W2'][1]:.0%})" for c, v in occ.items() if None not in v['W1'] + v['W2']) +
                  f" → {'통과' if ok3a and ok3b else '실패'}")
    r4 = paired('E', 'B')
    angle_ok = None
    if cl('E') and cl('B'):
        ae = np.mean([np.mean([r['angles'][g_]['rep'] for g_ in r['angles']]) for r in cl('E')]); ab = np.mean([np.mean([r['angles'][g_]['rep'] for g_ in r['angles']]) for r in cl('B')])
        angle_ok = bool(ae <= ab)
    ok4 = r4['ci95'][1] < 0 and bool(angle_ok)
    out['R4'] = dict(E_minus_B=r4, clean_rep_angle_E_le_B=angle_ok, pass_=bool(ok4))
    md.append(f"- R4 평활 대비: E − B {r4['mean']:+.2f} mm (CI {r4['ci95'][0]:+.2f} – {r4['ci95'][1]:+.2f}), 깨끗한 입력 렙 극값 각도 E ≤ B: {angle_ok} → {'통과' if ok4 else '실패'}")
    rules = {}
    for r in recs:
        if r['group'] == grp and 'reps' in r and r['var'] in ('C', 'EC'):
            for x in r['reps']:
                rules.setdefault((r['cond'], r['exercise'], r['var']), []).append(x)
    worst = 0.0; rows = []
    for (cond, ex, v), reps in rules.items():
        if v != 'EC' or (cond, ex, 'C') not in rules: continue
        for k in lf.RULES_BY_EX[ex]:
            fe = np.mean([k in x['fired'] for x in reps]); fc = np.mean([k in x['fired'] for x in rules[(cond, ex, 'C')]])
            worst = max(worst, abs(fe - fc)); rows.append((cond, ex, k, fc, fe))
    if rows:
        ok5 = worst <= 0.03; out['R5'] = dict(max_abs_diff=float(worst), pass_=bool(ok5))
        md.append(f"- R5 자세 평가 무해(정상 렙 규칙 발동, |EC − C| 최대): {worst:.1%} → {'통과' if ok5 else '실패'}")
        for cond, ex, k, fc, fe in sorted(rows, key=lambda r: -abs(r[4] - r[3]))[:6]:
            md.append(f"  - {cond} {ex} {k}: C {fc:.1%} → EC {fe:.1%}")
    r6 = paired('F', 'E'); ok6 = r6['ci95'][1] < 0 if r6['mean'] is not None else False
    out['R6'] = dict(F_minus_E=r6, pass_=bool(ok6))
    md.append(f"- R6 셋업 초기화(F − E): {r6['mean']:+.2f} mm (CI {r6['ci95'][0]:+.2f} – {r6['ci95'][1]:+.2f}) → {'이득' if ok6 else '이득 없음'}")
    out_j, out_m = Path(a.run_dir) / f'verdicts_{grp}.json', Path(a.run_dir) / f'verdicts_{grp}.md'
    json.dump(out, open(out_j, 'w'), indent=1); out_m.write_text('\n'.join(md) + '\n'); print('\n'.join(md))
    write_manifest(a, [a.eval_json] + ([a.shift_json] if a.shift_json else []), [out_j, out_m])


# ---------------------------------------------------------------- E0b: how stable are the relations in the XS output itself
def run_xs_relations(a):
    """Clean input: for every relation of the exercise, the spread of v = P[b] - P[a] over the set in XS (A raw) vs
    the truth, and the error of v itself (mm). A relation can only help when XS's own v is steadier / closer than XS's
    joint under occlusion; this measures the first part."""
    from pose_feedback.geometry.adaptive_relations import RELATIONS as AR
    seqs = load_any(a); recs, inputs = [], []
    for d in seqs:
        raw = predict_rows(None, None, d['x'], [5], seq_key(d))[5]; lo, hi = set_range(d)
        P, G = to_metres(raw, d), d['G']; conf = d['x'][..., 2]
        for name, j0, j1 in AR.get(d['ex'], ()):
            ok = (conf[lo:hi, j0] >= 0.5) & (conf[lo:hi, j1] >= 0.5)
            vp, vg = (P[lo:hi, j1] - P[lo:hi, j0])[ok], (G[lo:hi, j1] - G[lo:hi, j0])[ok]
            if len(vp) < 10: continue
            spread = lambda v: float(np.median(np.linalg.norm(v - np.median(v, 0), axis=-1)) * 1000)
            recs.append(dict(group=d['group'], exercise=d['ex'], rel=name, observed=float(ok.mean()), spread_xs=spread(vp), spread_gt=spread(vg),
                             err_v=float(np.median(np.linalg.norm(vp - vg, axis=-1)) * 1000),
                             err_joint=float(np.median(np.linalg.norm(P[lo:hi, j1][ok] - G[lo:hi, j1][ok], axis=-1)) * 1000)))
        inputs.append(d['csv'])
    md = ['| 묶음 | 운동 | 관계 | 영상 | 두 관절 관측 비율 | v 퍼짐 XS / 정답 (mm, 중앙값) | v 오차 (mm) | 관절 b 자체 오차 (mm) |', '|---' * 8 + '|']
    summ = {}
    for grp in dict.fromkeys(r['group'] for r in recs):
        for ex in EXERCISES:
            for name in dict.fromkeys(r['rel'] for r in recs if r['exercise'] == ex):
                rs = [r for r in recs if r['group'] == grp and r['exercise'] == ex and r['rel'] == name]
                if not rs: continue
                g = {k: float(np.median([r[k] for r in rs])) for k in ('observed', 'spread_xs', 'spread_gt', 'err_v', 'err_joint')}
                summ[f'{grp}/{ex}/{name}'] = dict(n=len(rs), **g)
                md.append(f"| {grp} | {ex} | {name} | {len(rs)} | {g['observed']:.0%} | {g['spread_xs']:.0f} / {g['spread_gt']:.0f} | {g['err_v']:.0f} | {g['err_joint']:.0f} |")
    out_j, out_m = Path(a.run_dir) / 'xs_relations.json', Path(a.run_dir) / 'xs_relations.md'
    json.dump(dict(summary=summ, records=recs), open(out_j, 'w'), indent=1); out_m.write_text('\n'.join(md) + '\n'); print('\n'.join(md))
    write_manifest(a, inputs + [a.checkpoint], [out_j, out_m])


def load_model(a):
    import torch
    from finetune_motionagformer_fit3d import load
    torch.set_num_threads(a.threads)  # Home is shared: 4-6 threads beat 8 under load (measured 2026-10-20)
    dev = 'mps' if a.device == 'mps' and torch.backends.mps.is_available() else 'cpu'
    return load(a.mag_repo, a.checkpoint, dev)[0].eval(), dev


def run_cache_clean(a):
    """Raw XS rows (L=5) of the unmodified app input for every sequence -> CACHE (Fit3D-derived: delete after)."""
    model, dev = load_model(a); seqs = load_any(a); t0 = time.time()
    for i, d in enumerate(seqs):
        predict_rows(model, dev, d['x'], [5], seq_key(d))
        print(i, seq_key(d), len(d['x']), f'{time.time() - t0:.0f}s', flush=True)
    write_manifest(a, [d['csv'] for d in seqs] + [a.checkpoint], [], dict(cache=a.cache))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['gt-relations', 'cache-clean', 'occlude', 'evaluate', 'foot-shift', 'setup-measure', 'signals', 'tune', 'rgb-eval', 'setup-ex3d', 'verdicts', 'xs-relations'])
    p.add_argument('--eval-json'); p.add_argument('--shift-json'); p.add_argument('--group', default='heldout')
    p.add_argument('--shapes', default=None, help='lift-refine shapes run dir (targets/<subject>.json), non-oracle body for E1')
    p.add_argument('--ex3d', help='dir with gt.json, csv/<seq>/<cam>_<ex>_mcoco17.csv, labels/<seq>/geometry')
    p.add_argument('--dataset', choices=['fit3d', 'ex3d'], default='fit3d'); p.add_argument('--device', choices=['cpu', 'mps'], default='cpu')
    p.add_argument('--ex3d-view', choices=['all', 'side1'], default='all')
    p.add_argument('--cams', type=lambda s: s.split(','), default=None, help='Fit3D camera ids to keep (default all 4)')
    p.add_argument('--rgb', help='dir of eval_setup_rgb_occlusion.py outputs'); p.add_argument('--pose2d', help='lift-compare A-pose2d pose2d dir')
    p.add_argument('--jobs', type=int, default=4)
    p.add_argument('--cases', type=lambda s: s.split(','), default=list(SHIFT_CASES))
    p.add_argument('--variants', type=lambda s: s.split(','), default=['A', 'B', 'B0', 'C', 'D', 'E', 'F', 'EC'])
    p.add_argument('--params', default='', help='JSON overrides of adaptive_relations.DEFAULTS (E / F / EC / D)')
    p.add_argument('--ema-alpha', type=float, default=0.5); p.add_argument('--lock-thr', type=float, default=0.5)
    p.add_argument('--tag', default='run')
    p.add_argument('--rules', action='store_true', help='E5: rule firing / metric validity per rep')
    p.add_argument('--rules-variants', type=lambda s: s.split(','), default=['A', 'B', 'C', 'E', 'EC'])
    # 10 conditions (Home CPU budget): the relations act on ankles / wrists only, so knee / shoulder / multi-joint get 'long'
    p.add_argument('--conditions', type=lambda s: s.split(','), default=[f'{g}-{u}' for g in ('wrist', 'ankle') for u in DURATIONS]
                   + ['knee-long', 'shoulder-long', 'arm-long', 'leg-long'])
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
     'signals': run_signals, 'tune': run_tune, 'rgb-eval': run_rgb_eval, 'setup-ex3d': run_setup_ex3d, 'verdicts': run_verdicts, 'xs-relations': run_xs_relations}[a.cmd](a)


if __name__ == '__main__':
    main()
