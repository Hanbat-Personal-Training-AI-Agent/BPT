"""T2: push-up knee/leg depth-flip root cause and training-free fixes; T3: lookahead 3 vs 5 with the current defaults.

Fit3D mocap (Home only, aggregates only), original MotionAGFormer-XS on the app 2D (pose-replay RTMPose-m CSVs),
helpers from eval_lift_app_fit3d.py (same prep / cache / metrics / judge_py).

T2 (`t2`, push-up by default): XS L=5 + Pose3DConstraints() defaults (reflection off = "detect only"); flagged leg-frame
= knee theta < -30. Per flagged leg-frame and a matched random sample of unflagged leg-frames (same sequences, same
count): near/far leg, RTMPose hip/knee/ankle confidence, 2D knee-off-line ratio, depth-sign agreement with mocap of
knee / ankle / other-leg joints (camera z, pelvis-relative), knee offset-from-line depth sign, other-leg theta sign,
pelvis tilt sign. Fixes, all on the same constrained output: a = Pose3DConstraints(reflect_flipped_knee=True),
b = reflect only when the 2D leg is bent (off-line > k x 2D leg length) and/or the near leg, c = reflect only when the
knee offset depth sign disagrees with the median of the last N unflagged frames of that leg, d = like a, but when the
ankle depth (vs hip) also disagrees with its last-N median, mirror knee and ankle depth about the hip instead.
T3 (`t3`): L = 3 and 5, Pose3DConstraints(reflect_flipped_knee = squat), pose / angle / ROM errors, bad rate and
judge_py rule fires on normal reps with two_d heights from the app 2D (mocap reference with projected mocap 2D).

usage (Home, bpt-home):
  eval_lift_app_t2t3.py t2 --cpu --cache DIR --root ~/datasets/fit3d --replay ~/bpt-smpl/replay --run-dir RUN
  eval_lift_app_t2t3.py t3 --cpu --cache DIR --root ~/datasets/fit3d --replay ~/bpt-smpl/replay --run-dir RUN
"""
import argparse, json, os, sys
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eval_lift_app_fit3d as E  # noqa: E402
from eval_lift_app_fit3d import (ANG, EXERCISES, LEGS, ROM_KEYS, RULES_BY_EX, SIDES, angle_metrics, angles,  # noqa: E402
                                 apply_constraints, cat, finish, groups_of, knee_theta, load_model, load_seqs,
                                 pose_metrics, predict_rows, ref_angles, rep_records, rom_err, seq_key, st, vbin10)
from eval_3d_angles import interior  # noqa: E402

COCO_LEG = {'left': (11, 13, 15), 'right': (12, 14, 16)}
OTHER = {'left': 'right', 'right': 'left'}


def two_d(a, d):
    """Per-frame {hipY, shoulderY, torsoLength}: app 2D (near-side COCO px) and projected mocap (same frames)."""
    from pose_feedback.body.pose2d_data import project_fit3d
    side = {'L': 'left', 'R': 'right'}[d['side']]
    sh, hp = {'left': (5, 11), 'right': (6, 12)}[side]
    two = lambda S_, H_: [dict(hipY=float(b[1]), shoulderY=float(t[1]), torsoLength=float(np.hypot(*(t - b)))) for t, b in zip(S_, H_)]
    cam = json.load(open(f"{a.root}/train/{d['subj']}/camera_parameters/{d['cam']}/{d['ex']}.json"))
    Jp = d['J'][d['pick']]; hs, hh = {'left': (11, 4), 'right': (14, 1)}[side]
    return two(d['K'][:, sh, :2], d['K'][:, hp, :2]), two(project_fit3d(Jp[:, hs], cam), project_fit3d(Jp[:, hh], cam))


def reflect_knee(P, i, leg):
    h, k, an = LEGS[leg]
    line = P[i, an] - P[i, h]
    if np.linalg.norm(line) <= 1e-9: return
    u = line / np.linalg.norm(line); v = P[i, k] - P[i, h]
    P[i, k] = P[i, h] + 2 * u * float(v @ u) - v


def off_z(P, leg):
    h, k, an = LEGS[leg]
    v, ax = P[:, k] - P[:, h], P[:, an] - P[:, h]
    ax = ax / np.linalg.norm(ax, axis=-1, keepdims=True).clip(1e-9)
    return (v - ax * (v * ax).sum(-1, keepdims=True))[:, 2]


def off2d(K, leg):
    h, k, an = (K[:, j, :2] for j in COCO_LEG[leg])
    line = an - h; L = np.linalg.norm(line, axis=-1).clip(1e-6)
    dist = np.abs(line[:, 0] * (k - h)[:, 1] - line[:, 1] * (k - h)[:, 0]) / L
    return dist / (np.linalg.norm(k - h, axis=-1) + np.linalg.norm(an - k, axis=-1)).clip(1e-6)


def fixes(P0, Pa, K, flag, near_leg, N=10):
    """Variant outputs (metres, pelvis-relative). flag[leg] = bool [N]."""
    out = {'detect_only': P0, 'a_reflect': Pa}
    o2 = {leg: off2d(K, leg) for leg in SIDES}
    for name, cond in (('b_bent0.05', lambda leg: o2[leg] > 0.05), ('b_bent0.10', lambda leg: o2[leg] > 0.10),
                       ('b_near', lambda leg: np.full(len(P0), leg == near_leg)),
                       ('b_near_or_bent0.05', lambda leg: (leg == near_leg) | (o2[leg] > 0.05))):
        P = P0.copy()
        for leg in SIDES:
            for i in np.where(flag[leg] & cond(leg))[0]: reflect_knee(P, i, leg)
        out[name] = P
    for n in (N, 30):
        P = P0.copy()
        for leg in SIDES:
            oz = off_z(P0, leg); good = []
            for i in range(len(P0)):
                if not flag[leg][i]:
                    good.append(oz[i]); continue
                if len(good) >= 3 and np.sign(oz[i]) != np.sign(np.median(good[-n:])): reflect_knee(P, i, leg)
        out[f'c_temporal{n}'] = P
    P = P0.copy()
    for leg in SIDES:
        h, k, an = LEGS[leg]; az = P0[:, an, 2] - P0[:, h, 2]; good = []
        for i in range(len(P0)):
            if not flag[leg][i]:
                good.append(az[i]); continue
            if len(good) >= 3 and np.sign(az[i]) != np.sign(np.median(good[-N:])):
                for j in (k, an): P[i, j, 2] = 2 * P0[i, h, 2] - P0[i, j, 2]  # depth mirror about the hip (lengths kept)
            else:
                reflect_knee(P, i, leg)
    out['d_chain'] = P
    return out


def run_t2(a):
    model, dev = load_model(a); seqs = load_seqs(a); rng = np.random.default_rng(0)
    feats, recs = [], []
    for d in seqs:
        raw = predict_rows(model, dev, d['x'], [3, 5], seq_key(d))[5]; mm = d['mm'][:, None, None] / 1000; G = d['G']; K = d['K']
        Qg, _ = apply_constraints(raw, {}); Qa, _ = apply_constraints(raw, dict(reflect_flipped_knee=True))
        P0, Pa = (Qg - Qg[:, :1]) * mm, (Qa - Qa[:, :1]) * mm
        near = {'L': 'left', 'R': 'right'}[d['side']]
        th = {leg: knee_theta(P0, leg)[0] for leg in SIDES}; thg = {leg: knee_theta(G, leg)[0] for leg in SIDES}
        flag = {leg: th[leg] < -30 for leg in SIDES}
        meta = dict(group=d['group'], exercise=d['ex'], vbin=vbin10(d['view']), subj=d['subj'], cam=d['cam'])
        sgn_bad = lambda x, g, eps: np.where(np.abs(g) > eps, (np.sign(x) != np.sign(g)).astype(float), np.nan)
        for leg in SIDES:
            h, k, an = LEGS[leg]; oh, ok_, oan = LEGS[OTHER[leg]]
            fl = np.where(flag[leg])[0]; nf = np.where(~flag[leg] & ~flag[OTHER[leg]])[0]
            ctrl = rng.choice(nf, size=min(len(fl), len(nf)), replace=False) if len(fl) and len(nf) else np.array([], int)
            o2 = off2d(K, leg); ch, ck, ca = COCO_LEG[leg]
            for kind, idx in (('flagged', fl), ('normal', ctrl)):
                if not len(idx): continue
                feats.append(dict(meta, kind=kind, n=len(idx), near=float(leg == near) * np.ones(len(idx)),
                                  conf_hip=K[idx, ch, 2], conf_knee=K[idx, ck, 2], conf_ankle=K[idx, ca, 2],
                                  conf_other_knee=K[idx, COCO_LEG[OTHER[leg]][1], 2], off2d=o2[idx],
                                  knee_z_wrong=sgn_bad(P0[idx, k, 2], G[idx, k, 2], 0.03), ankle_z_wrong=sgn_bad(P0[idx, an, 2], G[idx, an, 2], 0.03),
                                  knee_offz_wrong=sgn_bad(off_z(P0, leg)[idx], off_z(G, leg)[idx], 0.02),
                                  ankle_vs_hip_z_wrong=sgn_bad((P0[:, an, 2] - P0[:, h, 2])[idx], (G[:, an, 2] - G[:, h, 2])[idx], 0.03),
                                  other_knee_z_wrong=sgn_bad(P0[idx, ok_, 2], G[idx, ok_, 2], 0.03),
                                  other_theta_wrong=sgn_bad(th[OTHER[leg]][idx], thg[OTHER[leg]][idx], 10),
                                  pelvis_tilt_wrong=sgn_bad((P0[:, 4, 2] - P0[:, 1, 2])[idx], (G[:, 4, 2] - G[:, 1, 2])[idx], 0.02),
                                  knee_err_mm=np.linalg.norm(P0[idx, k] - G[idx, k], axis=-1) * 1000,
                                  knee_ang_err=np.abs(interior(P0[idx, h], P0[idx, k], P0[idx, an]) - interior(G[idx, h], G[idx, k], G[idx, an]))))
        ref = ref_angles(d)
        for v, P in fixes(P0, Pa, K, flag, near).items():
            kerr = {leg: np.linalg.norm(P[:, LEGS[leg][1]] - G[:, LEGS[leg][1]], axis=-1) * 1000 for leg in SIDES}
            k0 = {leg: np.linalg.norm(P0[:, LEGS[leg][1]] - G[:, LEGS[leg][1]], axis=-1) * 1000 for leg in SIDES}
            chg = {leg: np.linalg.norm(P[:, LEGS[leg][1]] - P0[:, LEGS[leg][1]], axis=-1) > 1e-6 for leg in SIDES}
            kang = lambda Q, leg: interior(*(Q[:, j] for j in LEGS[leg]))
            r = dict(meta, var=v, mpjpe=pose_metrics(P, G)['mpjpe'],
                     knee_err=np.concatenate([kerr[l] for l in SIDES]),
                     knee_err_flag=np.concatenate([kerr[l][flag[l]] for l in SIDES]),
                     knee_ang_err_flag=np.concatenate([np.abs(kang(P, l) - kang(G, l))[flag[l]] for l in SIDES]),
                     changed=np.concatenate([chg[l][flag[l]] for l in SIDES]),
                     correct=np.concatenate([(kerr[l] < k0[l])[chg[l]] for l in SIDES]),
                     bad=np.stack([knee_theta(P, l)[0] < -30 for l in SIDES], 1).any(1),
                     knee=angle_metrics(angles(P, d['side'], d['up_c']), ref, d['seg'])['knee'])
            recs.append(r)
        print(d['subj'], d['ex'], d['cam'], int(sum(f.sum() for f in flag.values())), flush=True)
    FK = ['near', 'conf_hip', 'conf_knee', 'conf_ankle', 'conf_other_knee', 'off2d', 'knee_z_wrong', 'ankle_z_wrong', 'knee_offz_wrong',
          'ankle_vs_hip_z_wrong', 'other_knee_z_wrong', 'other_theta_wrong', 'pelvis_tilt_wrong', 'knee_err_mm', 'knee_ang_err']
    summ, md = {'features': {}, 'fixes': {}}, []
    md += ['**2D 입력·깊이 상태: 걸린 다리×프레임(θ<−30) vs 같은 수의 정상 다리×프레임 (평균; *_wrong = 모캡과 깊이 부호 다름 비율, |모캡|>2–3 cm만)**', '',
           '| 묶음 | 시점 | 종류 | n | ' + ' | '.join(FK) + ' |', '|---' * (4 + len(FK)) + '|']
    for k, fs in groups_of(feats, ('group', 'vbin', 'kind')) + groups_of(feats, ('group', 'kind')):
        if 'all' in k: continue
        s = {q: float(np.nanmean(cat(fs, q))) if np.isfinite(cat(fs, q)).any() else None for q in FK}
        s['n'] = int(sum(f['n'] for f in fs)); summ['features']['/'.join(map(str, k))] = s
        vb, kind = (k[1], k[2]) if len(k) == 3 else ('all', k[1])
        md.append(f"| {k[0]} | {vb} | {kind} | {s['n']} | " + ' | '.join('-' if s[q] is None else f'{s[q]:.2f}' for q in FK) + ' |')
    md += ['', '**고치기 비교 (푸시업; 무릎 오차 mm, 각 오차 °; 바뀐 무릎 중 모캡에 가까워짐 = 반사 정확도; 남은 θ<−30 프레임 = bad)**', '',
           '| 묶음 | 시점 | 변형 | 영상 | MPJPE | 무릎 오차 전체 평균 | 걸린 다리 무릎 오차 평균 | 걸린 다리 무릎 각 오차 중앙값 | 걸린 중 바꿈 | 바꾼 것 중 가까워짐 | 남은 θ<−30 프레임 | 가까운 무릎 렙극값 / 프레임 |',
           '|---' * 12 + '|']
    for k, rs in groups_of(recs, ('group', 'vbin', 'var')) + groups_of(recs, ('group', 'var')):
        if 'all' in k: continue
        f = lambda q, kk='p50': q.get(kk, float('nan'))
        s = dict(videos=len(rs), mpjpe=st(cat(rs, 'mpjpe')), knee_err=st(cat(rs, 'knee_err')), knee_err_flag=st(cat(rs, 'knee_err_flag')),
                 knee_ang_err_flag=st(cat(rs, 'knee_ang_err_flag')), changed=float(cat(rs, 'changed').mean()) if len(cat(rs, 'changed')) else None,
                 correct=float(cat(rs, 'correct').mean()) if len(cat(rs, 'correct')) else None, n_changed=int(len(cat(rs, 'correct'))),
                 bad=float(cat(rs, 'bad').mean()), knee_rep=st(cat(rs, 'knee', 'rep')), knee_frame=st(cat(rs, 'knee', 'frame')))
        summ['fixes']['/'.join(map(str, k))] = s
        vb, v = (k[1], k[2]) if len(k) == 3 else ('all', k[1])
        chg = '-' if s['changed'] is None else f"{s['changed']:.0%}"
        cor = '-' if s['correct'] is None else f"{s['correct']:.0%}"
        md.append(f"| {k[0]} | {vb} | {v} | {s['videos']} | {s['mpjpe']['mean']:.1f} | {s['knee_err']['mean']:.1f} | "
                  f"{s['knee_err_flag'].get('mean', float('nan')):.0f} | {f(s['knee_ang_err_flag']):.1f} | {chg} | {cor} ({s['n_changed']}) | "
                  f"{s['bad']:.2%} | {f(s['knee_rep']):.1f} / {f(s['knee_frame']):.1f} |")
    finish(a, 't2', summ, md, [d['csv'] for d in seqs] + [a.checkpoint])


def run_t3(a):
    from pose_feedback.body.form_metrics_3d import UP
    model, dev = load_model(a); seqs = load_seqs(a)
    recs, reps = [], []
    for d in seqs:
        rows = predict_rows(model, dev, d['x'], [3, 5], seq_key(d)); mm = d['mm'][:, None, None] / 1000; ref = ref_angles(d)
        td_app, td_gt = two_d(a, d); side = {'L': 'left', 'R': 'right'}[d['side']]
        meta = dict(group=d['group'], exercise=d['ex'], subj=d['subj'], cam=d['cam'])
        reps += rep_records(d['G'], d['seg'], d['ex'], side, UP, dict(meta, src='gt'), td_gt)
        for L in (3, 5):
            Q, rp = apply_constraints(rows[L], dict(reflect_flipped_knee=d['ex'] == 'squat'))
            P = (Q - Q[:, :1]) * mm; A = angles(P, d['side'], d['up_c'])
            # a03ddd9: invalid joints -> NaN for the evaluators; frame state ok / partial_3d / bad_3d (all 17)
            inv = [r.get('invalid_joints', []) for r in rp]
            state = np.array([0 if not j else 2 if len(j) == 17 else 1 for j in inv])
            Pm = P.copy()
            for i, j in enumerate(inv):
                if j: Pm[i, j] = np.nan
            recs.append(dict(meta, L=L, bad=[r['bad'] for r in rp], partial=(state == 1).tolist(), bad17=(state == 2).tolist(),
                             **pose_metrics(P, d['G']), **angle_metrics(A, ref, d['seg']), rom=rom_err(A, ref, d['seg'])))
            rr = rep_records(Pm, d['seg'], d['ex'], side, UP, dict(meta, src=f'xs_L{L}'), td_app)
            for r, (s0, e0) in zip(rr, d['seg']):
                st_ = state[s0:e0 + 1]
                r['judge_old'] = bool((st_ == 0).mean() >= 0.5); r['judge_new'] = bool((st_ <= 1).mean() >= 0.5)
            reps += rr
        print(d['subj'], d['ex'], d['cam'], flush=True)
    f = lambda q, kk='p50': q.get(kk, float('nan'))
    summ = {'pose': {}, 'rules': {}}
    md = ['| 묶음 | 운동 | L | 지연 ms | 영상 | MPJPE | PA-MPJPE | 가속도 | ' + ' | '.join(f'{g} 렙극값 (p90) / 프레임' for g in ('knee', 'hip', 'elbow', 'torso_g'))
          + ' | ' + ' | '.join(f'ROM {g}' for g in ROM_KEYS) + ' | 무효 관절 있음 (partial+bad) | bad_3d(17) |', '|---' * 18 + '|']
    for k, rs in groups_of(recs, ('group', 'exercise', 'L')):
        s = dict(videos=len(rs), mpjpe=st(cat(rs, 'mpjpe')), pa=st(cat(rs, 'pa_mpjpe')), accel=st(cat(rs, 'accel')), bad=float(cat(rs, 'bad').mean()),
                 bad17=float(cat(rs, 'bad17').mean()),
                 **{g: dict(rep=st(cat(rs, g, 'rep')), frame=st(cat(rs, g, 'frame'))) for g in ANG}, rom={g: st(cat(rs, 'rom', g)) for g in ROM_KEYS})
        summ['pose']['/'.join(map(str, k))] = s
        md.append(f"| {k[0]} | {k[1]} | {k[2]} | {k[2] / 30 * 1000:.0f} | {s['videos']} | {s['mpjpe']['mean']:.1f} | {s['pa']['mean']:.1f} | {s['accel']['mean']:.2f} | "
                  + ' | '.join(f"{f(s[g]['rep']):.1f} ({f(s[g]['rep'], 'p90'):.0f}) / {f(s[g]['frame']):.1f}" for g in ('knee', 'hip', 'elbow', 'torso_g')) + ' | '
                  + ' | '.join(f"{f(s['rom'][g]):.1f}" for g in ROM_KEYS) + f" | {s['bad']:.2%} | {s['bad17']:.2%} |")
    md += ['', '**판정 가능 렙 비율 (렙 프레임의 ≥50%: 옛 규칙 = ok만, 새 규칙 = ok 또는 partial_3d)**', '', '| 묶음 | 운동 | L | 렙 | 옛 규칙 | 새 규칙 |', '|---' * 6 + '|']
    for grp in ('heldout', 'tuning'):
        for ex in list(EXERCISES) + ['all']:
            for L in (3, 5):
                rs = [r for r in reps if r['group'] == grp and r['src'] == f'xs_L{L}' and (ex == 'all' or r['exercise'] == ex)]
                if not rs: continue
                jo, jn = float(np.mean([r['judge_old'] for r in rs])), float(np.mean([r['judge_new'] for r in rs]))
                summ.setdefault('judgeable', {})[f'{grp}/{ex}/L{L}'] = dict(reps=len(rs), old=round(jo, 4), new=round(jn, 4))
                md.append(f'| {grp} | {ex} | {L} | {len(rs)} | {jo:.1%} | {jn:.1%} |')
    for ex in EXERCISES:
        md += ['', f'**{ex} 정상 렙 규칙 발화 (judge_py, sideView = 참, 카메라 위, 높이 = 2D, XS 무효 관절 = NaN → 그 지표만 빠짐)**', '',
               '| 묶음 | 소스 | 렙 | ' + ' | '.join(RULES_BY_EX[ex]) + ' |', '|---' * (3 + len(RULES_BY_EX[ex])) + '|']
        for grp in ('heldout', 'tuning'):
            for src in ('gt', 'xs_L3', 'xs_L5'):
                for sub in (('all', lambda r: True), ('judgeable_new', lambda r: r.get('judge_new', True))):
                    rs = [r for r in reps if r['exercise'] == ex and r['group'] == grp and r['src'] == src and sub[1](r)]
                    if not rs or (src == 'gt' and sub[0] != 'all'): continue
                    fr = {q: round(float(np.mean([q in r['fired'] for r in rs])), 4) for q in RULES_BY_EX[ex]}
                    summ['rules'][f'{ex}/{grp}/{src}/{sub[0]}'] = dict(reps=len(rs), **fr)
                    md.append(f"| {grp} | {src} ({sub[0]}) | {len(rs)} | " + ' | '.join(f'{fr[q]:.1%}' for q in RULES_BY_EX[ex]) + ' |')
    finish(a, 't3', summ, md, [d['csv'] for d in seqs] + [a.checkpoint])


# ---------------------------------------------------------------- T4 Fit3D fine-tuned XS (NON-COMMERCIAL) vs original
# S7 candidate thresholds = 1% exceedance values of normal ORIGINAL-XS reps (validation, cam up, eval_lift_app S7 rerun
# 20261020-s7-rep-metrics-0dda987). Candidates only; circular for the original XS on the same reps (~1% by construction).
CAND = {
    'pushup_hip_pike': ('hip_dev_min', '<', -0.328), 'pushup_hip_sag': ('hip_dev_max', '>', 0.099),
    'pushup_head_up': ('head_dev_change_min', '<', -0.275), 'pushup_head_drop': ('head_dev_change_max', '>', 0.261),
    'pushup_hand_position': ('first_rep_top_wrist_ahead', 'out', (-0.325, 0.451)),
    'pushup_shallow': ('q_over_base_elbow_min', '>', 2.6), 'pushup_no_lockout': ('q_below_setmax_elbow_max', '>', 13.1),
    'squat_shallow': ('q_over_base_knee_min', '>', 8.5),
    'squat_no_lockout': (('q_below_setmax_knee_max', 'q_below_setmax_hip_angle_max'), 'any>', (19.6, 13.3)),
    'squat_hips_first': ('hips_first_torso_rise', 'hf', 8.6), 'valgus_if_front': ('knee_ankle_gap_ratio_min', '<', 0.675),
    'row_torso_swing': ('torso_range', '>', 38.2), 'row_standing_up': ('q_standing_up', '>', 2.9),
    'row_short_pull': ('q_short_pull', '>', 0.099), 'row_head_up': ('head_dev_change_min', '<', -0.15),
}


def judge_cand(m, ex):
    out = set()
    for rule, (q, op, t) in CAND.items():
        if rule not in RULES_BY_EX[ex]: continue
        if op == 'any>':
            fire = any(qq in m and m[qq] > tt for qq, tt in zip(q, t))
        elif q not in m:
            continue
        elif op == '<': fire = m[q] < t
        elif op == '>': fire = m[q] > t
        elif op == 'out': fire = m[q] < t[0] or m[q] > t[1]
        else: fire = m[q] > t and m.get('hips_first_hip_rise_speed', -1) > m.get('hips_first_shoulder_rise_speed', 0)
        if fire: out.add(rule)
    return out


def run_t4(a):
    import torch
    from finetune_motionagformer_fit3d import load
    from pose_feedback.body.form_metrics_3d import UP
    seqs = load_seqs(a); models = [kv.split('=', 1) for kv in a.models.split(',')]
    dev = 'cuda' if torch.cuda.is_available() and not a.cpu else 'cpu'
    recs, reps = [], []
    for d in seqs:
        td_app, td_gt = two_d(a, d); side = {'L': 'left', 'R': 'right'}[d['side']]
        meta = dict(group=d['group'], exercise=d['ex'], subj=d['subj'], cam=d['cam'])
        for r in rep_records(d['G'], d['seg'], d['ex'], side, UP, dict(meta, model='mocap'), td_gt):
            r['cand'] = judge_cand(r['m'], d['ex']); r['judge_old'] = r['judge_new'] = True; reps.append(r)
    for tag, ck in models:
        model = load(a.mag_repo, ck, dev)[0].eval()
        for d in seqs:
            if d['subj'] in a.exclude.get(tag, ()): continue
            raw = predict_rows(model, dev, d['x'], [5], None, batch=256 if dev == 'cuda' else 16)[5]
            mm = d['mm'][:, None, None] / 1000; ref = ref_angles(d); side = {'L': 'left', 'R': 'right'}[d['side']]
            td_app, _ = two_d(a, d)
            Q, rp = apply_constraints(raw, dict(reflect_flipped_knee=d['ex'] == 'squat'))
            P = (Q - Q[:, :1]) * mm; A = angles(P, d['side'], d['up_c']); Praw = (raw - raw[:, :1]) * mm
            inv = [r.get('invalid_joints', []) for r in rp]
            state = np.array([0 if not j else 2 if len(j) == 17 else 1 for j in inv])
            Pm = P.copy()
            for i, j in enumerate(inv):
                if j: Pm[i, j] = np.nan
            meta = dict(group=d['group'], exercise=d['ex'], subj=d['subj'], cam=d['cam'], model=tag)
            recs.append(dict(meta, flip=np.concatenate([knee_theta(Praw, l)[0] < -30 for l in SIDES]),
                             partial=(state == 1), bad17=(state == 2), **pose_metrics(P, d['G']), **angle_metrics(A, ref, d['seg'])))
            for r, (s0, e0) in zip(rep_records(Pm, d['seg'], d['ex'], side, UP, meta, td_app), d['seg']):
                st_ = state[s0:e0 + 1]
                r['judge_old'] = bool((st_ == 0).mean() >= 0.5); r['judge_new'] = bool((st_ <= 1).mean() >= 0.5)
                r['cand'] = judge_cand(r['m'], d['ex']); reps.append(r)
            print(tag, d['subj'], d['ex'], d['cam'], flush=True)
        del model
    f = lambda q, kk='p50': q.get(kk, float('nan'))
    tags = [t for t, _ in models]
    summ = {'pose': {}, 'rules': {}, 'quant': {}, 'cand': {k: list(v) for k, v in CAND.items()}}
    md = ['Fit3D 유래·비상업(NON-COMMERCIAL) 가중치 포함. L=5, Pose3DConstraints() 기본값(a03ddd9: 스쿼트만 무릎 반사, 지표별 무효화). '
          '검증 s07–s11 (두 미세조정 모두 학습에 안 씀).', '',
          '| 묶음 | 운동 | 모델 | 영상 | MPJPE | PA-MPJPE | 가속도 | knee 렙극값 (p90) | hip | elbow | torso_g | 무릎 뒤집힘(θ<−30 다리×프레임) | 무효 관절 프레임 (partial) | bad_3d(17) | 판정 불가 렙 옛 / 새 |',
          '|---' * 15 + '|']
    for k, rs in groups_of(recs, ('group', 'exercise', 'model')):
        rr = [r for r in reps if r.get('model') == k[2] and r['group'] == k[0] and (k[1] == 'all' or r['exercise'] == k[1])]
        s = dict(videos=len(rs), mpjpe=st(cat(rs, 'mpjpe')), pa=st(cat(rs, 'pa_mpjpe')), accel=st(cat(rs, 'accel')),
                 flip=float(cat(rs, 'flip').mean()), partial=float(cat(rs, 'partial').mean()), bad17=float(cat(rs, 'bad17').mean()),
                 unj_old=float(np.mean([not r['judge_old'] for r in rr])) if rr else None, unj_new=float(np.mean([not r['judge_new'] for r in rr])) if rr else None,
                 **{g: st(cat(rs, g, 'rep')) for g in ANG})
        summ['pose']['/'.join(k)] = s
        md.append(f"| {k[0]} | {k[1]} | {k[2]} | {s['videos']} | {s['mpjpe']['mean']:.1f} | {s['pa']['mean']:.1f} | {s['accel']['mean']:.2f} | "
                  f"{f(s['knee']):.1f} ({f(s['knee'], 'p90'):.0f}) | {f(s['hip']):.1f} | {f(s['elbow']):.1f} | {f(s['torso_g']):.1f} | {s['flip']:.2%} | "
                  f"{s['partial']:.2%} | {s['bad17']:.2%} | {s['unj_old']:.1%} / {s['unj_new']:.1%} |")
    for ex in EXERCISES:
        rules = RULES_BY_EX[ex]
        md += ['', f'**{ex} 정상 렙 오경보: 현재 앱 임계값 (judge_py) / S7 후보 임계값 (원래 XS 1% 초과값)**', '',
               '| 묶음 | 모델 | 렙 | ' + ' | '.join(rules) + ' |', '|---' * (3 + len(rules)) + '|']
        for grp in ('heldout', 'tuning'):
            for tag in ['mocap'] + tags:
                rs = [r for r in reps if r['exercise'] == ex and r['group'] == grp and r.get('model') == tag and r['judge_new']]
                if not rs: continue
                cur = {q: float(np.mean([q in r['fired'] for r in rs])) for q in rules}
                cd = {q: float(np.mean([q in r['cand'] for r in rs])) for q in rules if q in CAND}
                summ['rules'][f'{ex}/{grp}/{tag}'] = dict(reps=len(rs), current=cur, candidate=cd)
                md.append(f"| {grp} | {tag} | {len(rs)} | " + ' | '.join(f"{cur[q]:.0%} / {'-' if q not in cd else f'{cd[q]:.0%}'}" for q in rules) + ' |')
        qs = sorted({v[0] if isinstance(v[0], str) else x for k, v in CAND.items() if k in rules for x in ([v[0]] if isinstance(v[0], str) else v[0])})
        md += ['', f'**{ex} 규칙 양 p1 / p99 (정상 렙, 모델별)**', '', '| 묶음 | 모델 | ' + ' | '.join(qs) + ' |', '|---' * (2 + len(qs)) + '|']
        for grp in ('heldout', 'tuning'):
            for tag in ['mocap'] + tags:
                rs = [r for r in reps if r['exercise'] == ex and r['group'] == grp and r.get('model') == tag and r['judge_new']]
                if not rs: continue
                cells = []
                for q in qs:
                    v = np.array([r['m'][q] for r in rs if q in r['m']], float)
                    pq = (float(np.percentile(v, 1)), float(np.percentile(v, 99))) if len(v) else None
                    summ['quant'][f'{ex}/{grp}/{tag}/{q}'] = dict(n=int(len(v)), p1=pq and pq[0], p99=pq and pq[1])
                    cells.append('-' if pq is None else f'{pq[0]:.3g} / {pq[1]:.3g}')
                md.append(f"| {grp} | {tag} | " + ' | '.join(cells) + ' |')
    finish(a, 't4', summ, md, [d['csv'] for d in seqs] + [ck for _, ck in models])


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['t2', 't3', 't4'])
    p.add_argument('--root', required=True); p.add_argument('--replay', required=True); p.add_argument('--run-dir', required=True)
    p.add_argument('--subjects', type=lambda s: s.split(','), default=['s03', 's04', 's05', 's07', 's08', 's09', 's10', 's11'])
    p.add_argument('--exercises', type=lambda s: s.split(','), default=None)
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    p.add_argument('--checkpoint', default=None); p.add_argument('--cpu', action='store_true'); p.add_argument('--cache', default=None)
    p.add_argument('--models', default=None, help='t4: tag=ckpt,... (Fit3D fine-tuned = NON-COMMERCIAL)')
    p.add_argument('--exclude', type=json.loads, default={}, help='t4: {tag: [training subjects to skip]}')
    a = p.parse_args()
    a.exercises = a.exercises or (['pushup'] if a.cmd == 't2' else list(EXERCISES))
    a.checkpoint = a.checkpoint or f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr'
    E.CACHE['dir'] = a.cache; os.makedirs(a.run_dir, exist_ok=True)
    {'t2': run_t2, 't3': run_t3, 't4': run_t4}[a.cmd](a)


if __name__ == '__main__':
    main()
