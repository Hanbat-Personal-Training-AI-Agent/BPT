"""Lift-app studies on Fit3D mocap for the app's 3D path (RTMPose-m COCO17 crop 2D -> MotionAGFormer-XS).

Reuses eval_3d_angles / eval_3d_mediapipe / finetune_motionagformer_fit3d (Fit3D loading, H36M mapping, prep =
app 2D at 30 fps + person_crop input + mocap target in crop units + weak-perspective mm scale, pose_metrics,
angle_metrics, angles). Studies:
  lookahead   S1  output row / lookahead L: frame t from window [t+L-26, t+L] (edge-clamped), row 26-L
  gt-stats    S2a/b  mocap (all subjects, all exercises) signed knee theta, interior angles, bone lengths
  xs-knee     S2c + S3  XS output (L=5) theta / bones / ratios and the knee-hinge check vs mocap, axis rules
  hands       S4  MediaPipe Hand Landmarker on wrist crops of the Fit3D videos (saves wrist px per frame)
  wrist       S4  RTMPose vs MediaPipe wrist: 2D error, then XS 3D wrist/elbow error, gates
  coreml-dump / coreml-check   PyTorch vs Core ML (assets/coreml/motionagformer_xs.mlpackage) on real windows
S5: --constraint MODULE:FUNC applies FUNC(P [N,17,3] crop units, one sequence) to the selected XS output in
lookahead / xs-knee / wrist.

Each run writes <run-dir>/manifest.json (argv, code commit, sha256 of inputs and outputs) next to the aggregate
JSON / Markdown. Fit3D licence: user's own machines only, aggregates only (per-frame hand npz are deleted after).

usage (Home, bpt-home env, code synced to ~/bpt-runs/lift-app/_code/<sha>/):
  eval_lift_app_fit3d.py lookahead --root ~/datasets/fit3d --replay ~/bpt-smpl/replay --run-dir RUN
  eval_lift_app_fit3d.py gt-stats  --root ~/datasets/fit3d --run-dir RUN
  eval_lift_app_fit3d.py xs-knee   --root ... --replay ... --run-dir RUN
  eval_lift_app_fit3d.py hands     --root ... --replay ... --task hand_landmarker.task --run-dir RUN [--jobs 10]
  eval_lift_app_fit3d.py wrist     --root ... --replay ... --hands RUN_HANDS/hands --run-dir RUN
  eval_lift_app_fit3d.py coreml-dump --root ... --replay ... --run-dir RUN      (Home)
  eval_lift_app_fit3d.py coreml-check --dump DUMP.npz --mlpackage PKG --run-dir RUN   (Mac, bpt-coreml env)
"""
import argparse, glob, hashlib, importlib, json, os, socket, sys, time
from multiprocessing import Pool
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path[:0] = [str(REPO), str(HERE)]
from eval_3d_angles import FIT3D_TO_H36M, WINDOW, fit3d_jobs, interior, near_side, view_and_side  # noqa: E402
from eval_3d_mediapipe import BUCKETS, TUNING, angle_metrics, angles, pose_metrics  # noqa: E402
from pose_feedback.geometry.hinge_limit import LEGS, MIN_SIN_PARALLEL, knee_theta_deg  # noqa: E402

EXERCISES = ('squat', 'pushup', 'barbell_row')
H36M_PARENTS = [-1, 0, 1, 2, 0, 4, 5, 0, 7, 8, 9, 8, 11, 12, 8, 14, 15]
JN = ['pelvis', 'r_hip', 'r_knee', 'r_ankle', 'l_hip', 'l_knee', 'l_ankle', 'spine', 'thorax', 'neck', 'head',
      'l_shoulder', 'l_elbow', 'l_wrist', 'r_shoulder', 'r_elbow', 'r_wrist']
BONES = [(p, c) for c, p in enumerate(H36M_PARENTS) if p >= 0]
BONE_NAMES = [f'{JN[p]}-{JN[c]}' for p, c in BONES]
ANG = ('knee', 'hip', 'elbow', 'torso', 'torso_g')
SIDES = ('left', 'right')
COCO_WRIST, COCO_ELBOW = {'left': 9, 'right': 10}, {'left': 7, 'right': 8}
H_WRIST, H_ELBOW = {'left': 13, 'right': 16}, {'left': 12, 'right': 15}
HAND_MODES = ('c256', 'c015')  # 256 px fixed (Swift CameraPreviewOptions.handCropSize), 0.15 x person height


# ---------------------------------------------------------------- shared
def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()


def write_manifest(a, inputs, outputs, extra=None):
    code = REPO / 'CODE_SHA'
    commit = code.read_text().strip() if code.exists() else os.popen(f'git -C {REPO} rev-parse HEAD').read().strip()
    scripts = sorted(str(p) for p in list(REPO.glob('scripts/*.py')) + list(REPO.glob('pose_feedback/**/*.py')))
    m = dict(argv=sys.argv, python=sys.executable, host=socket.gethostname(), code_dir=str(REPO), git_commit=commit,
             finished=time.strftime('%Y-%m-%d %H:%M:%S'), extra=extra or {},
             inputs={p: sha256(p) for p in sorted(set(map(str, inputs))) if os.path.isfile(p)},
             code={p: sha256(p) for p in scripts},
             outputs={str(p): sha256(p) for p in outputs if os.path.isfile(p)})
    json.dump(m, open(Path(a.run_dir) / 'manifest.json', 'w'), indent=1)


def bucket(v):
    for lo, hi in BUCKETS:
        if lo <= v < hi: return f'{lo}-{90 if hi == 91 else hi}'


def load_constraint(spec):
    if not spec: return None
    mod, fn = spec.split(':')
    return getattr(importlib.import_module(mod), fn)


CACHE = {}  # set by main: dir for raw XS rows of the unmodified app input (Fit3D-derived, deleted after the runs)


def load_model(a):
    import torch
    from finetune_motionagformer_fit3d import load
    dev = 'cuda' if torch.cuda.is_available() and not a.cpu else 'cpu'
    if dev == 'cpu': torch.set_num_threads(8)  # 12 threads is 20x slower on Home (measured), 8 is the best
    return load(a.mag_repo, a.checkpoint, dev)[0].eval(), dev


def predict_rows(model, dev, x, Ls, key=None, batch=16):
    """Raw XS output for every frame t and lookahead L: window ending at t+L ([t+L-26, t+L] edge-clamped at both
    ends, exactly the app's lookahead_indices), row 26-L. One forward per window end serves every L. {L: [N,17,3]}."""
    import torch
    path = f"{CACHE['dir']}/{key}.npz" if key and CACHE.get('dir') else None
    if path and os.path.exists(path):
        z = np.load(path)
        if all(f'L{L}' in z for L in Ls): return {L: z[f'L{L}'].astype(float) for L in Ls}
    n = len(x); E = n + max(Ls); rows = [WINDOW - 1 - L for L in Ls]
    idx = np.clip(np.arange(E)[:, None] - (WINDOW - 1) + np.arange(WINDOW)[None], 0, n - 1)
    with torch.no_grad():
        out = np.concatenate([model(torch.from_numpy(x[idx[s:s + batch]]).to(dev))[:, rows].cpu().numpy()
                              for s in range(0, E, batch)]).astype(float)
    res = {L: out[np.arange(n) + L, k] for k, L in enumerate(Ls)}
    if path:
        os.makedirs(os.path.dirname(path), exist_ok=True); np.savez(path, **{f'L{L}': v for L, v in res.items()})
    return res


def lift(model, dev, x, L, constraint=None, key=None, raw=None):
    """App-equivalent 3D for every frame t: window [t+L-26, t+L] edge-clamped, output row 26-L, root-relative."""
    out = raw if raw is not None else predict_rows(model, dev, x, [L], key)[L]
    if constraint is not None: out = np.asarray(constraint(out), float)
    return out - out[:, :1]


def seq_key(d): return f"{d['subj']}_{d['cam']}_{d['ex']}"


def load_seqs(a):
    from finetune_motionagformer_fit3d import prep
    seqs = []
    for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(a.root, a.replay, a.subjects, a.exercises):
        d = prep(a.root, subj, ex, cam, J, R, T, csv); pick = d['pick']
        up_w = -R[1] / np.linalg.norm(R[1]); up_w = np.array([0, 0, 1.]) if abs(up_w[2]) > 0.8 else up_w
        view, _ = view_and_side(J, R, T, up_w)
        d.update(J=J, R=R, T=T, up_c=R @ up_w, view=view, bin=bucket(view), side=near_side(d['K']), csv=csv,
                 group='tuning' if subj in TUNING else 'heldout', G=d['y'] * d['mm'][:, None, None] / 1000,
                 seg=[(int(np.searchsorted(pick, s)), int(np.searchsorted(pick, e))) for s, e in zip(ann, ann[1:])])
        seqs.append(d)
    print(len(seqs), 'sequences', flush=True)
    return seqs


def ref_angles(d):
    r = angles(d['G'], d['side'], d['up_c']); r['torso'] = r['torso_g']  # truth torso is vs gravity
    return r


def st(x, ps=(50, 90)):
    x = np.asarray(x, float); x = x[np.isfinite(x)]
    if not len(x): return dict(n=0)
    return dict(n=int(len(x)), mean=round(float(x.mean()), 2), **{f'p{p}': round(float(np.percentile(x, p)), 2) for p in ps})


def groups_of(recs, keys=('group', 'exercise')):
    """Yield (key tuple, recs) for each key combination plus exercise='all'."""
    out = {}
    for r in recs:
        k = tuple(r[x] for x in keys); out.setdefault(k, []).append(r)
        if 'exercise' in keys:
            k2 = tuple('all' if x == 'exercise' else r[x] for x in keys); out.setdefault(k2, []).append(r)
    order = lambda v: (0, int(v), '') if isinstance(v, (int, np.integer)) else (1, 0, str(v))
    return sorted(out.items(), key=lambda kv: ((kv[0][0] != 'heldout'),) + tuple(order(v) for v in kv[0][1:]))


def cat(rs, *path):
    v = []
    for r in rs:
        x = r
        for p in path: x = x[p]
        v.append(np.asarray(x, float).ravel())
    return np.concatenate(v) if v else np.zeros(0)


# ---------------------------------------------------------------- knee theta (vectorised hinge_limit._knee_theta)
def knee_theta(P, leg):
    """P [N,17,3] -> theta deg [N] (NaN = degenerate, as hinge_limit), alignment |n_flex . a| [N]."""
    h, k, an = LEGS[leg]
    u, v, lr = P[:, k] - P[:, h], P[:, an] - P[:, k], P[:, 4] - P[:, 1]
    nu, nv, nl = (np.linalg.norm(z, axis=-1) for z in (u, v, lr))
    uh = u / nu[:, None].clip(1e-12)
    ax = lr - uh * (lr * uh).sum(-1, keepdims=True); na = np.linalg.norm(ax, axis=-1)
    ax = ax / na[:, None].clip(1e-12)
    perp = np.linalg.norm(v - ax * (v * ax).sum(-1, keepdims=True), axis=-1)
    bad = (nu < 1e-6) | (nv < 1e-6) | (nl < 1e-6) | (na < MIN_SIN_PARALLEL * nl) | (perp < MIN_SIN_PARALLEL * nv)
    c = np.cross(u, v)
    th = np.degrees(np.arctan2((c * ax).sum(-1), (u * v).sum(-1)))
    al = np.abs((c * ax).sum(-1)) / np.linalg.norm(c, axis=-1).clip(1e-12)
    th[bad] = np.nan; al[bad] = np.nan
    return th, al


def check_theta(P):
    """Self-check: vectorised theta == pose_feedback.geometry.hinge_limit.knee_theta_deg on a few frames."""
    for leg in SIDES:
        th = knee_theta(P[:40], leg)[0]
        ref = np.array([np.nan if (t := knee_theta_deg(p, leg)) is None else t for p in P[:40]])
        assert np.allclose(th, ref, equal_nan=True, atol=1e-6), (leg, th[:5], ref[:5])


def gt_angle_set(P):
    """Interior angles per side for knee / elbow / hip(trunk vs thigh) / shoulder(trunk-down vs upper arm), spine."""
    trunk = P[:, 8] - P[:, 0]
    vang = lambda a, b: np.degrees(np.arccos(np.clip((a * b).sum(-1) / (np.linalg.norm(a, axis=-1) * np.linalg.norm(b, axis=-1) + 1e-12), -1, 1)))
    out = {}
    for s, (hp, kn, an, sh, el, wr) in (('L', (4, 5, 6, 11, 12, 13)), ('R', (1, 2, 3, 14, 15, 16))):
        out[f'knee_{s}'] = interior(P[:, hp], P[:, kn], P[:, an])
        out[f'elbow_{s}'] = interior(P[:, sh], P[:, el], P[:, wr])
        out[f'hip_{s}'] = vang(trunk, P[:, kn] - P[:, hp])
        out[f'shoulder_{s}'] = vang(-trunk, P[:, el] - P[:, sh])
    out['spine'] = interior(P[:, 0], P[:, 7], P[:, 8])
    return out


def bone_len(P):
    return np.stack([np.linalg.norm(P[:, c] - P[:, p], axis=-1) for p, c in BONES], 1)  # [N,16]


def body_stats(P):
    """P [N,17,3] -> bone lengths [N,16] and named per-frame ratios (sided ones = mean of L and R)."""
    B = bone_len(P); i = {n: k for k, n in enumerate(BONE_NAMES)}
    m = lambda l, r: (B[:, i[l]] + B[:, i[r]]) / 2
    asym = lambda l, r: (B[:, i[l]] - B[:, i[r]]) / m(l, r)
    thigh, shin = m('l_hip-l_knee', 'r_hip-r_knee'), m('l_knee-l_ankle', 'r_knee-r_ankle')
    upper, fore = m('l_shoulder-l_elbow', 'r_shoulder-r_elbow'), m('l_elbow-l_wrist', 'r_elbow-r_wrist')
    return B, dict(shin_thigh=shin / thigh, forearm_upperarm=fore / upper, thigh_torso=thigh / np.linalg.norm(P[:, 8] - P[:, 0], axis=-1),
                   asym_thigh=asym('l_hip-l_knee', 'r_hip-r_knee'), asym_shin=asym('l_knee-l_ankle', 'r_knee-r_ankle'),
                   asym_upperarm=asym('l_shoulder-l_elbow', 'r_shoulder-r_elbow'), asym_forearm=asym('l_elbow-l_wrist', 'r_elbow-r_wrist'))


# ---------------------------------------------------------------- S1
def run_lookahead(a):
    model, dev = load_model(a); con = load_constraint(a.constraint); seqs = load_seqs(a)
    from finetune_motionagformer_fit3d import app_predict
    x0 = seqs[0]['x'][:120]; P5 = app_predict(model, x0, dev).astype(float)  # self-check vs the D-D-06/07 path
    assert np.allclose(lift(model, dev, x0, 5), P5 - P5[:, :1], atol=1e-4)
    recs = []
    for d in seqs:
        ref = ref_angles(d); rows = predict_rows(model, dev, d['x'], a.lookaheads, seq_key(d))
        for L in a.lookaheads:
            P = lift(model, dev, d['x'], L, con, raw=rows[L]) * d['mm'][:, None, None] / 1000
            th = np.stack([knee_theta(P, leg)[0] for leg in SIDES], 1)
            recs.append(dict(group=d['group'], exercise=d['ex'], bin=d['bin'], subj=d['subj'], cam=d['cam'], L=L,
                             bad=(th < -10).any(1).tolist(), **pose_metrics(P, d['G']),
                             **angle_metrics(angles(P, d['side'], d['up_c']), ref, d['seg'])))
        print(d['subj'], d['ex'], d['cam'], round(d['view']), flush=True)
    summ, md = {}, ['| 묶음 | 운동 | L | 지연 (ms) | 영상 | 프레임 | MPJPE | PA-MPJPE | 가속도 오차 | 3D 불량 | '
                    + ' | '.join(f'{k} 렙극값 (p90) / 프레임' for k in ANG) + ' |', '|---' * (10 + len(ANG)) + '|']
    for keys in (('group', 'exercise', 'L'), ('group', 'exercise', 'bin', 'L')):
        for k, rs in groups_of(recs, keys):
            s = dict(videos=len(rs), frames=int(len(cat(rs, 'mpjpe'))), mpjpe=st(cat(rs, 'mpjpe')), pa_mpjpe=st(cat(rs, 'pa_mpjpe')),
                     accel=st(cat(rs, 'accel')), bad3d=round(float(cat(rs, 'bad').mean()), 4),
                     **{g: dict(rep=st(cat(rs, g, 'rep')), frame=st(cat(rs, g, 'frame')), jitter=st(cat(rs, g, 'jitter'))) for g in ANG})
            summ['/'.join(map(str, k))] = s
            if len(keys) == 3:
                L = k[2]
                md.append(f"| {k[0]} | {k[1]} | {L} | {L / 30 * 1000:.0f} | {s['videos']} | {s['frames']} | {s['mpjpe']['mean']:.1f} | "
                          f"{s['pa_mpjpe']['mean']:.1f} | {s['accel']['mean']:.2f} | {s['bad3d']:.1%} | " +
                          ' | '.join(f"{s[g]['rep'].get('p50', float('nan')):.1f} ({s[g]['rep'].get('p90', float('nan')):.0f}) / "
                                     f"{s[g]['frame'].get('p50', float('nan')):.1f}" for g in ANG) + ' |')
    md += ['', '| 묶음 | 운동 | 시점 | L | 영상 | MPJPE | PA-MPJPE | 가속도 오차 |', '|---|---|---|---|---|---|---|---|']
    for key, s in summ.items():
        p = key.split('/')
        if len(p) == 4: md.append(f"| {p[0]} | {p[1]} | {p[2]} | {p[3]} | {s['videos']} | {s['mpjpe']['mean']:.1f} | {s['pa_mpjpe']['mean']:.1f} | {s['accel']['mean']:.2f} |")
    finish(a, 'lookahead', summ, md, [d['csv'] for d in seqs] + [a.checkpoint])


def finish(a, name, summ, md, inputs, extra=None):
    out_j, out_m = Path(a.run_dir) / f'{name}.json', Path(a.run_dir) / f'{name}.md'
    json.dump(summ, open(out_j, 'w'), indent=1); out_m.write_text('\n'.join(md) + '\n'); print('\n'.join(md))
    write_manifest(a, inputs, [out_j, out_m], extra)


# ---------------------------------------------------------------- S2a/b
def run_gt_stats(a):
    from eval_3d_angles import load_joints
    per_ex, bones, inputs = {}, {}, []
    for sd in sorted(glob.glob(f'{a.root}/train/s*')):
        subj = os.path.basename(sd)
        if subj not in a.subjects: continue
        for jf in sorted(glob.glob(f'{sd}/joints3d_25/*.json')):
            ex = Path(jf).stem; P = load_joints(sd, ex); inputs.append(jf)
            if per_ex == {}: check_theta(P)
            th = np.concatenate([knee_theta(P, leg)[0] for leg in SIDES])
            e = per_ex.setdefault(ex, dict(theta=[], ang={}))
            e['theta'].append(th)
            for k, v in gt_angle_set(P).items(): e['ang'].setdefault(k.split('_')[0], []).append(v)
            B, r = body_stats(P * 1000)
            b = bones.setdefault(subj, dict(mean=[], cv=[], ratio={}))
            b['mean'].append(B.mean(0)); b['cv'].append(B.std(0) / B.mean(0))
            for k, v in r.items(): b['ratio'].setdefault(k, []).append(v)
        print(subj, flush=True)
    PS = (0.1, 1, 5, 50, 95, 99, 99.9)
    pct = lambda x: {f'p{p}': round(float(np.nanpercentile(x, p)), 2) for p in PS}
    summ = dict(theta={}, interior={}, bones={})
    allx = lambda key: [v for ex, e in per_ex.items() for v in (e['theta'] if key == 'theta' else e['ang'][key])]
    for ex in list(EXERCISES) + ['all_main', 'all']:
        src = {x: per_ex[x] for x in (EXERCISES if ex == 'all_main' else per_ex if ex == 'all' else [ex])}
        th = np.concatenate([v for e in src.values() for v in e['theta']])
        summ['theta'][ex] = dict(frames_legs=int(np.isfinite(th).sum()), degenerate=round(float(np.isnan(th).mean()), 4),
                                 below_m10=round(float((th < -10).mean()), 5), below_m5=round(float((th < -5).mean()), 5), **pct(th))
        summ['interior'][ex] = {k: pct(np.concatenate([v for e in src.values() for v in e['ang'][k]]))
                                for k in ('knee', 'elbow', 'hip', 'shoulder', 'spine')}
    for subj, b in bones.items():
        summ['bones'][subj] = dict(sequences=len(b['mean']), mean_mm=dict(zip(BONE_NAMES, np.round(np.mean(b['mean'], 0), 1).tolist())),
                                   cv_within_seq_median=dict(zip(BONE_NAMES, np.round(np.median(b['cv'], 0), 4).tolist())),
                                   ratio={k: st(np.concatenate(v), (5, 50, 95)) for k, v in b['ratio'].items()})
    md = ['**θ (부호 있는 무릎 경첩각, °, 프레임×다리)**', '', '| 운동 | 프레임×다리 | 퇴화 | θ<−10° | θ<−5° | ' + ' | '.join(f'p{p}' for p in PS) + ' |',
          '|---' * (5 + len(PS)) + '|']
    for ex, s in summ['theta'].items():
        md.append(f"| {ex} | {s['frames_legs']} | {s['degenerate']:.2%} | {s['below_m10']:.3%} | {s['below_m5']:.3%} | " + ' | '.join(f"{s[f'p{p}']:.1f}" for p in PS) + ' |')
    md += ['', '**내부각 (°, 0–180)**', '', '| 운동 | 관절 | ' + ' | '.join(f'p{p}' for p in PS) + ' |', '|---' * (2 + len(PS)) + '|']
    for ex, s in summ['interior'].items():
        for k, v in s.items(): md.append(f'| {ex} | {k} | ' + ' | '.join(f"{v[f'p{p}']:.1f}" for p in PS) + ' |')
    md += ['', '**뼈 길이 (mm, 피험자별 평균) / 시퀀스 안 CV 중앙값**', '', '| 뼈 | ' + ' | '.join(bones) + ' |', '|---' * (1 + len(bones)) + '|']
    for bn in BONE_NAMES:
        md.append(f'| {bn} | ' + ' | '.join(f"{summ['bones'][s]['mean_mm'][bn]:.0f} ({summ['bones'][s]['cv_within_seq_median'][bn]:.1%})" for s in bones) + ' |')
    md += ['', '**비율 (피험자별 프레임 중앙값 [p5–p95])**', '', '| 비율 | ' + ' | '.join(bones) + ' |', '|---' * (1 + len(bones)) + '|']
    for k in summ['bones'][next(iter(bones))]['ratio']:
        md.append(f'| {k} | ' + ' | '.join(f"{summ['bones'][s]['ratio'][k]['p50']:.3f} [{summ['bones'][s]['ratio'][k]['p5']:.3f}–{summ['bones'][s]['ratio'][k]['p95']:.3f}]" for s in bones) + ' |')
    finish(a, 'gt_stats', summ, md, inputs)


# ---------------------------------------------------------------- S2c + S3
RULES = {  # name -> f(theta, align) flag; theta / align are per leg-frame
    'cur θ<−10': lambda t, al, thr: t < -10,
    'θ<−15': lambda t, al, thr: t < -15,
    'θ<−20': lambda t, al, thr: t < -20,
    'θ<−30': lambda t, al, thr: t < -30,
    'θ<GT조정p0.1': lambda t, al, thr: t < thr,
    '|n·a|≥0.5 & θ<−10': lambda t, al, thr: (al >= 0.5) & (t < -10),
    '|n·a|≥0.7 & θ<−10': lambda t, al, thr: (al >= 0.7) & (t < -10),
    '|n·a|≥0.7 & θ<−20': lambda t, al, thr: (al >= 0.7) & (t < -20),
}


def run_xs_knee(a):
    model, dev = load_model(a); con = load_constraint(a.constraint); seqs = load_seqs(a)
    check_theta(seqs[0]['G'])
    recs = []
    for d in seqs:
        P = lift(model, dev, d['x'], 5, con, key=seq_key(d)) * d['mm'][:, None, None] / 1000; G = d['G']
        r = dict(group=d['group'], exercise=d['ex'], bin=d['bin'], subj=d['subj'], cam=d['cam'], legs={})
        for leg in SIDES:
            h, k, an = LEGS[leg]
            tx, ax_ = knee_theta(P, leg); tg, ag = knee_theta(G, leg)
            dz = lambda Q: Q[:, k, 2] - (Q[:, h, 2] + Q[:, an, 2]) / 2  # knee depth vs hip-ankle line (camera z)
            r['legs'][leg] = dict(tx=tx, ax=ax_, tg=tg, ag=ag, err=np.abs(interior(P[:, h], P[:, k], P[:, an]) - interior(G[:, h], G[:, k], G[:, an])),
                                  dzx=dz(P), dzg=dz(G))
        nk = {'L': 'left', 'R': 'right'}[d['side']]
        r['near_err'] = r['legs'][nk]['err']
        r['bx'], r['rx'] = body_stats(P * 1000); r['bg'], r['rg'] = body_stats(G * 1000)
        recs.append(r)
    leg = lambda rs, key: np.concatenate([r['legs'][s][key] for r in rs for s in SIDES])
    tun = [r for r in recs if r['group'] == 'tuning']
    thr = float(np.nanpercentile(leg(tun, 'tg'), 0.1)) if tun else -10.0
    summ = dict(gt_tuning_theta_p01=round(thr, 2), groups={})
    md_a = ['**XS(L=5) θ 분포·3D 불량 vs 정답 같은 프레임 (°)**', '',
            '| 묶음 | 운동 | 시점 | 영상 | 프레임 | XS θ p1 / p5 / p50 | 정답 θ p0.1 / p1 / p50 | XS θ<−10 다리 | XS 3D 불량 프레임 | 정답 θ<−10 | XS 정강이/허벅지 p5–p50–p95 | 정답 | XS 아래팔/위팔 | 정답 | XS 허벅지/몸통 | 정답 | XS 뼈 CV(시퀀스 안, 다리 4뼈 중앙값) | 정답 |',
            '|---' * 18 + '|']
    md_b = ['**3D 불량(XS θ<−10) 원인 분해 (다리×프레임 단위)**', '',
            '| 묶음 | 운동 | 걸린 다리 | 정답도 θ<−10 | 각도 크기 맞음(오차≤20°) | 오차>20° | 무릎 깊이 부호 반대(|Δz정답|>2cm 중) | 정렬 |n·a| XS 걸린 중앙값 / 정답 전체 중앙값 / XS 전체 | 정답 θ 걸린 프레임 중앙값 |',
            '|---' * 10 + '|']
    md_c = ['**규칙별: 정답에서 걸림(오경보), XS에서 걸림, 무릎 오차>20° 기준 정밀도/재현율 (다리×프레임)**', '',
            '| 묶음 | 운동 | 규칙 | 정답 걸림 | XS 걸림 | 정밀도 | 재현율 | 오차>20° 다리 | XS 걸림 중 오차≤20° |', '|---' * 9 + '|']
    LEGB = [n for n in BONE_NAMES if n[2:5] in ('hip', 'kne')]
    for k, rs in groups_of(recs, ('group', 'exercise', 'bin')) + groups_of(recs, ('group', 'exercise')):
        key = '/'.join(map(str, k)); tx, tg, ax_, ag, err = (leg(rs, z) for z in ('tx', 'tg', 'ax', 'ag', 'err'))
        dzx, dzg = leg(rs, 'dzx'), leg(rs, 'dzg')
        fl = tx < -10; big = err > 20
        badf = np.concatenate([(np.stack([r['legs'][s]['tx'] for s in SIDES], 1) < -10).any(1) for r in rs])
        cvb = lambda b: float(np.median([np.median((r[b].std(0) / r[b].mean(0))[[BONE_NAMES.index(n) for n in LEGB]]) for r in rs]))
        ratio = lambda rk, name: st(np.concatenate([r[rk][name] for r in rs]), (5, 50, 95))
        s = dict(videos=len(rs), frames=int(len(badf)), xs_theta=st(tx, (1, 5, 50)), gt_theta=st(tg, (0.1, 1, 50)),
                 xs_below_m10_legs=round(float(fl.mean()), 4), xs_bad3d_frames=round(float(badf.mean()), 4),
                 gt_below_m10_legs=round(float((tg < -10).mean()), 5),
                 ratios={n: dict(xs=ratio('rx', n), gt=ratio('rg', n)) for n in ('shin_thigh', 'forearm_upperarm', 'thigh_torso')},
                 bone_cv_leg=dict(xs=round(cvb('bx'), 4), gt=round(cvb('bg'), 4)),
                 bone_cv_all=dict(xs=dict(zip(BONE_NAMES, np.round(np.median([r['bx'].std(0) / r['bx'].mean(0) for r in rs], 0), 4).tolist())),
                                  gt=dict(zip(BONE_NAMES, np.round(np.median([r['bg'].std(0) / r['bg'].mean(0) for r in rs], 0), 4).tolist()))))
        deep = np.abs(dzg) > 0.02
        s['cause'] = dict(flagged=int(fl.sum()), gt_also=int((fl & (tg < -10)).sum()), mag_ok=int((fl & ~big).sum()), big_err=int((fl & big).sum()),
                          depth_sign_flip=int((fl & deep & (np.sign(dzx) != np.sign(dzg))).sum()), flagged_deep=int((fl & deep).sum()),
                          align_flagged=st(ax_[fl]), align_gt=st(ag), align_xs=st(ax_), gt_theta_flagged=st(tg[fl]))
        s['rules'] = {}
        for name, f in RULES.items():
            fx, fg = f(tx, ax_, thr), f(tg, ag, thr)
            s['rules'][name] = dict(gt_fire=round(float(fg.mean()), 5), xs_fire=round(float(fx.mean()), 4),
                                    precision=round(float((fx & big).sum() / max(fx.sum(), 1)), 3), recall=round(float((fx & big).sum() / max(big.sum(), 1)), 3),
                                    big=int(big.sum()), fp_xs=int((fx & ~big).sum()))
        # D-D-03-comparable frame level: any leg flagged vs near-side knee error > 20
        ne = np.concatenate([r['near_err'] for r in rs]); bg_ = ne > 20
        s['dd03_frame'] = dict(flag_rate=round(float(badf.mean()), 4), recall=round(float((badf & bg_).sum() / max(bg_.sum(), 1)), 3),
                               precision=round(float((badf & bg_).sum() / max(badf.sum(), 1)), 3), big=int(bg_.sum()))
        summ['groups'][key] = s
        R = s['ratios']; rf = lambda q: f"{q['p5']:.2f}–{q['p50']:.2f}–{q['p95']:.2f}"
        bn = k[2] if len(k) == 3 else 'all'
        md_a.append(f"| {k[0]} | {k[1]} | {bn} | {s['videos']} | {s['frames']} | {s['xs_theta']['p1']:.1f} / {s['xs_theta']['p5']:.1f} / {s['xs_theta']['p50']:.1f} | "
                    f"{s['gt_theta']['p0.1']:.1f} / {s['gt_theta']['p1']:.1f} / {s['gt_theta']['p50']:.1f} | {s['xs_below_m10_legs']:.1%} | {s['xs_bad3d_frames']:.1%} | "
                    f"{s['gt_below_m10_legs']:.2%} | {rf(R['shin_thigh']['xs'])} | {rf(R['shin_thigh']['gt'])} | {rf(R['forearm_upperarm']['xs'])} | "
                    f"{rf(R['forearm_upperarm']['gt'])} | {rf(R['thigh_torso']['xs'])} | {rf(R['thigh_torso']['gt'])} | {s['bone_cv_leg']['xs']:.1%} | {s['bone_cv_leg']['gt']:.1%} |")
        if len(k) == 2:
            c = s['cause']; n = max(c['flagged'], 1)
            md_b.append(f"| {k[0]} | {k[1]} | {c['flagged']} | {c['gt_also'] / n:.1%} | {c['mag_ok'] / n:.1%} | {c['big_err'] / n:.1%} | "
                        f"{c['depth_sign_flip'] / max(c['flagged_deep'], 1):.1%} ({c['flagged_deep']}) | {c['align_flagged'].get('p50', float('nan')):.2f} / "
                        f"{c['align_gt']['p50']:.2f} / {c['align_xs']['p50']:.2f} | {c['gt_theta_flagged'].get('p50', float('nan')):.1f} |")
            for name, v in s['rules'].items():
                md_c.append(f"| {k[0]} | {k[1]} | {name} | {v['gt_fire']:.3%} | {v['xs_fire']:.2%} | {v['precision']:.2f} | {v['recall']:.2f} | {v['big']} | {v['fp_xs']} |")
            md_c.append(f"| {k[0]} | {k[1]} | (D-D-03 방식: 프레임, 아무 다리 vs 가까운 무릎 오차>20°) | - | {s['dd03_frame']['flag_rate']:.2%} | "
                        f"{s['dd03_frame']['precision']:.2f} | {s['dd03_frame']['recall']:.2f} | {s['dd03_frame']['big']} | - |")
    finish(a, 'xs_knee', summ, md_a + [''] + md_b + [''] + md_c + ['', f'GT 조정 피험자 θ p0.1 = {thr:.2f}°'],
           [d['csv'] for d in seqs] + [a.checkpoint])


# ---------------------------------------------------------------- S5 constraints
def gt_limits(path, src='all'):
    """Angle limits for Pose3DConstraints from gt_stats.json interior p0.1 (mins) / shoulder p99.9 (max)."""
    s = json.load(open(path))['interior'][src]; lo = lambda k: round(s[k]['p0.1'], 1)
    return (("right_knee_flexion", 2, 1, 2, 3, lo('knee'), 180.0), ("left_knee_flexion", 5, 4, 5, 6, lo('knee'), 180.0),
            ("right_elbow_flexion", 15, 14, 15, 16, lo('elbow'), 180.0), ("left_elbow_flexion", 12, 11, 12, 13, lo('elbow'), 180.0),
            ("right_hip", 0, 8, 1, 2, lo('hip'), 180.0), ("left_hip", 0, 8, 4, 5, lo('hip'), 180.0),
            ("spine", 7, 0, 7, 8, lo('spine'), 180.0),
            ("right_shoulder", 8, 0, 14, 15, 0.0, round(s['shoulder']['p99.9'], 1)),
            ("left_shoulder", 8, 0, 11, 12, 0.0, round(s['shoulder']['p99.9'], 1)))


def apply_constraints(P, kw):
    """One Pose3DConstraints per sequence (stateful session median), frames in time order."""
    from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints
    c = Pose3DConstraints(**kw); out, reps = [], []
    for p in P:
        q, r = c.apply(p); out.append(q); reps.append(r)
    return np.stack(out), reps


def fire_stats(reps, names):
    f = lambda pred: [bool(pred(r)) for r in reps]
    return dict(bone_gt5=f(lambda r: r['bone_max_correction'] > 0.05), bone_gt30=f(lambda r: r['bone_max_correction'] > 0.30),
                knee_hyper=f(lambda r: r['knee_hyperextended']), bad=f(lambda r: r['bad']),
                any_angle=f(lambda r: len(r['angle_corrections']) > 0),
                **{f'ang_{n}': f(lambda r, n=n: n in r['angle_corrections']) for n in names})


def run_constraints(a):
    from pose_feedback.geometry.pose3d_constraints import DEFAULT_ANGLE_LIMITS
    model, dev = load_model(a); seqs = load_seqs(a)
    variants = {'a_raw': None, 'b_bones': dict(angle_limits=()), 'c_angles': dict(bone_lengths=False), 'd_all': {},
                'e_all_knee': dict(knee_correction=True)}
    if a.gt_limits: variants['f_all_gtlim'] = dict(angle_limits=gt_limits(a.gt_limits))
    recs = []
    for d in seqs:
        raw = predict_rows(model, dev, d['x'], [5], seq_key(d))[5]; ref = ref_angles(d); mm = d['mm'][:, None, None] / 1000
        for v, kw in variants.items():
            r = dict(group=d['group'], exercise=d['ex'], bin=d['bin'], subj=d['subj'], cam=d['cam'], var=v)
            if kw is None:
                Q = raw
            else:
                Q, reps = apply_constraints(raw, kw)
                names = [l[0] for l in kw.get('angle_limits', DEFAULT_ANGLE_LIMITS)]
                r['fire_xs'] = fire_stats(reps, names)
                r['fire_gt'] = fire_stats(apply_constraints(d['y'].astype(float), kw)[1], names)
            P = (Q - Q[:, :1]) * mm
            r.update(**pose_metrics(P, d['G']), **angle_metrics(angles(P, d['side'], d['up_c']), ref, d['seg']))
            recs.append(r)
        print(d['subj'], d['ex'], d['cam'], flush=True)
    summ = {}
    md = ['| 묶음 | 운동 | 변형 | 영상 | MPJPE | PA-MPJPE | 가속도 오차 | ' + ' | '.join(f'{g} 렙극값 (p90) / 프레임 / 떨림' for g in ANG) + ' |',
          '|---' * (7 + len(ANG)) + '|']
    md2 = ['| 묶음 | 운동 | 변형 | 대상 | 뼈 보정>5% | 뼈>30% | 무릎 과신전 | 각도 제한 하나라도 | bad | 제한별 |', '|---' * 10 + '|']
    for k, rs in groups_of(recs, ('group', 'exercise', 'var')):
        s = dict(videos=len(rs), mpjpe=st(cat(rs, 'mpjpe')), pa_mpjpe=st(cat(rs, 'pa_mpjpe')), accel=st(cat(rs, 'accel')),
                 **{g: dict(rep=st(cat(rs, g, 'rep')), frame=st(cat(rs, g, 'frame')), jitter=st(cat(rs, g, 'jitter'))) for g in ANG})
        f = lambda q, kk='p50': q.get(kk, float('nan'))
        md.append(f"| {k[0]} | {k[1]} | {k[2]} | {s['videos']} | {s['mpjpe']['mean']:.1f} | {s['pa_mpjpe']['mean']:.1f} | {s['accel']['mean']:.2f} | " +
                  ' | '.join(f"{f(s[g]['rep']):.1f} ({f(s[g]['rep'], 'p90'):.0f}) / {f(s[g]['frame']):.1f} / {f(s[g]['jitter']):.2f}" for g in ANG) + ' |')
        if 'fire_xs' in rs[0]:
            for who in ('fire_xs', 'fire_gt'):
                fr = {q: round(float(cat(rs, who, q).mean()), 4) for q in rs[0][who]}; s[who] = fr
                angs = ', '.join(f"{q[4:]} {v:.1%}" for q, v in fr.items() if q.startswith('ang_') and v > 0) or '-'
                md2.append(f"| {k[0]} | {k[1]} | {k[2]} | {'XS' if who == 'fire_xs' else '정답'} | {fr['bone_gt5']:.1%} | {fr['bone_gt30']:.1%} | "
                           f"{fr['knee_hyper']:.1%} | {fr['any_angle']:.1%} | {fr['bad']:.1%} | {angs} |")
        summ['/'.join(k)] = s
    lim = {'default': [list(l) for l in DEFAULT_ANGLE_LIMITS], 'gt': [list(l) for l in gt_limits(a.gt_limits)] if a.gt_limits else None}
    finish(a, 'constraints', dict(limits=lim, groups=summ), md + [''] + md2 + ['', f'limits: {json.dumps(lim)}'],
           [d['csv'] for d in seqs] + [a.checkpoint] + ([a.gt_limits] if a.gt_limits else []))


# ---------------------------------------------------------------- S4 hands
def hand_job(job):
    video, K, task, out = job
    if os.path.exists(out): return out
    import cv2, mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision
    mk = lambda: vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=task), running_mode=vision.RunningMode.VIDEO, num_hands=1,
        min_hand_detection_confidence=0.5, min_hand_presence_confidence=0.5, min_tracking_confidence=0.5))  # = Swift runner
    lms = {(m, s): mk() for m in HAND_MODES for s in SIDES}
    res = {m: np.full((len(K), 2, 4), np.nan, np.float32) for m in HAND_MODES}  # x, y (frame px), handedness score, crop side
    n50 = int(cv2.VideoCapture(video).get(cv2.CAP_PROP_FRAME_COUNT))
    pick = np.round(np.arange(0, n50, 50 / 30)).astype(int)
    want = {int(f): i for i, f in enumerate(pick) if i < len(K)}
    cap = cv2.VideoCapture(video); f = 0
    while True:
        ok, fr = cap.read()
        if not ok: break
        i = want.get(f); f += 1
        if i is None: continue
        rgb = cv2.cvtColor(fr, cv2.COLOR_BGR2RGB); H, W = rgb.shape[:2]
        for m in HAND_MODES:
            size = 256.0 if m == 'c256' else 0.15 * float(K[i, :, 1].max() - K[i, :, 1].min())  # A-path person height
            size = int(round(min(size, W, H)))
            for si, s in enumerate(SIDES):
                wx, wy, wc = K[i, COCO_WRIST[s]]
                if wc < 0.3 or size < 8: continue  # HandCropBuilder.defaultWristConfidenceThreshold
                x0 = int(round(min(max(wx - size / 2, 0), W - size))); y0 = int(round(min(max(wy - size / 2, 0), H - size)))
                crop = np.ascontiguousarray(rgb[y0:y0 + size, x0:x0 + size])
                r = lms[(m, s)].detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=crop), int(round(i * 1000 / 30)))
                if r.hand_landmarks:
                    p = r.hand_landmarks[0][0]
                    res[m][i, si] = (x0 + p.x * crop.shape[1], y0 + p.y * crop.shape[0], r.handedness[0][0].score, size)
                else:
                    res[m][i, si, 3] = size
    for lm in lms.values(): lm.close()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    np.savez(out + '.tmp.npz', **res); os.replace(out + '.tmp.npz', out)
    return out


def run_hands(a):
    from eval_3d_angles import read_csv
    jobs, inputs = [], [a.task]
    for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(a.root, a.replay, a.subjects, a.exercises):
        K = read_csv(csv); n = min(len(K), len(J)); pick = np.round(np.arange(0, n, 50 / 30)).astype(int); pick = pick[pick < n]
        jobs.append((f'{a.root}/train/{subj}/videos/{cam}/{ex}.mp4', K[pick], a.task, f'{a.run_dir}/hands/{subj}/{cam}/{ex}.npz'))
        inputs.append(csv)
    print(len(jobs), 'videos', flush=True)
    with Pool(a.jobs) as p:
        for i, o in enumerate(p.imap_unordered(hand_job, jobs)): print(i, o, flush=True)
    write_manifest(a, inputs, [], dict(note='hands/*.npz are Fit3D-derived per-frame wrist px: delete after the wrist run',
                                       videos={j[0]: os.path.getsize(j[0]) for j in jobs}))


def gate_ok(var, K, side, w):
    if var == 'mp': return True
    wr, el = K[COCO_WRIST[side]], K[COCO_ELBOW[side]]
    if var.startswith('d'): return np.linalg.norm(w - wr[:2]) < float(var[1:]) * np.linalg.norm(el[:2] - wr[:2])
    if var.startswith('c'): return wr[2] < float(var[1:])
    raise ValueError(var)


def run_wrist(a):
    from finetune_motionagformer_fit3d import mag_input
    from pose_feedback.body.pose2d_data import project_fit3d
    from pose_feedback.body.motionagformer_wrist_source import build_motionagformer_input_2d, reject_crossed_mediapipe_wrists
    model, dev = load_model(a); con = load_constraint(a.constraint); seqs = load_seqs(a)
    variants = ['rtm', 'mp'] + a.gates
    recs, inputs = [], [a.checkpoint]
    for d in seqs:
        hp = f"{a.hands}/{d['subj']}/{d['cam']}/{d['ex']}.npz"
        if not os.path.exists(hp): continue
        Hd = np.load(hp); inputs += [d['csv']]
        K, n = d['K'], len(d['K'])
        cam = json.load(open(f"{a.root}/train/{d['subj']}/camera_parameters/{d['cam']}/{d['ex']}.json"))
        Jp = d['J'][d['pick']]
        g2 = {j: project_fit3d(Jp[:, j], cam) for j in (12, 13, 15, 16)}
        fore = {s: np.median(np.linalg.norm(g2[H_ELBOW[s]] - g2[H_WRIST[s]], axis=-1)) for s in SIDES}
        _, crops0 = mag_input(K); ratio = d['mm'] / 1000 / (crops0[:, 2] / 2)  # (Z_root / f) per frame
        ref = ref_angles(d); G = d['G']
        for m in HAND_MODES:
            hw = Hd[m]
            for var in variants:
                Kp = K.copy(); rep = np.zeros((n, 2), bool); crossed = 0
                if var != 'rtm':
                    for i in range(n):
                        found = {s: hw[i, si, :2] for si, s in enumerate(SIDES) if np.isfinite(hw[i, si, 0])}
                        kept = reject_crossed_mediapipe_wrists(K[i], found); crossed += len(found) - len(kept)
                        kept = {s: w for s, w in kept.items() if gate_ok(var, K[i], s, w)}
                        Kp[i], _ = build_motionagformer_input_2d(K[i], kept, 'mediapipe')
                        rep[i] = [s in kept for s in SIDES]
                e2 = {s: np.linalg.norm(Kp[:, COCO_WRIST[s], :2] - g2[H_WRIST[s]], axis=-1) for s in SIDES}
                e2r = {s: np.linalg.norm(K[:, COCO_WRIST[s], :2] - g2[H_WRIST[s]], axis=-1) for s in SIDES}
                r = dict(group=d['group'], exercise=d['ex'], bin=d['bin'], subj=d['subj'], cam=d['cam'], mode=m, var=var,
                         crop_made=np.isfinite(hw[:, :, 3]).mean(), detected=np.isfinite(hw[:, :, 0]).mean(), replaced=rep.mean(), crossed=crossed,
                         w2d_px=np.concatenate([e2[s] for s in SIDES]), w2d_fore=np.concatenate([e2[s] / fore[s] for s in SIDES]),
                         w2d_px_rep=np.concatenate([e2[s][rep[:, si]] for si, s in enumerate(SIDES)]),
                         w2d_px_rep_rtm=np.concatenate([e2r[s][rep[:, si]] for si, s in enumerate(SIDES)]),
                         wrist3d=[], elbow3d=[], wrist_acc=[], elbow_ang=[], mpjpe=[], elbow_near=dict(rep=[], frame=[]))
                # 3D only where asked (XS on Home CPU is ~35 windows/s); 'rtm' = the cached app-input rows
                if var in a.vars_3d and (m in a.modes_3d or var == 'rtm'):
                    x, crops = mag_input(Kp)
                    P = lift(model, dev, x, 5, con, key=seq_key(d) if var == 'rtm' else None) * (crops[:, 2] / 2 * ratio)[:, None, None]
                    acc = lambda X: X[2:] - 2 * X[1:-1] + X[:-2]
                    r.update(wrist3d=np.linalg.norm(P[:, [13, 16]] - G[:, [13, 16]], axis=-1).ravel() * 1000,
                             elbow3d=np.linalg.norm(P[:, [12, 15]] - G[:, [12, 15]], axis=-1).ravel() * 1000,
                             wrist_acc=np.linalg.norm(acc(P[:, [13, 16]]) - acc(G[:, [13, 16]]), axis=-1).ravel() * 1000,
                             elbow_ang=np.concatenate([np.abs(interior(P[:, s], P[:, e], P[:, w]) - interior(G[:, s], G[:, e], G[:, w]))
                                                       for s, e, w in ((11, 12, 13), (14, 15, 16))]),
                             mpjpe=pose_metrics(P, G)['mpjpe'],
                             elbow_near=angle_metrics(angles(P, d['side'], d['up_c']), ref, d['seg'])['elbow'])
                recs.append(r)
        print(d['subj'], d['ex'], d['cam'], flush=True)
    summ = {}
    md = ['| 묶음 | 운동 | crop | 변형 | 영상 | crop 만듦 | 손 찾음 | 교체 | 반대손 거름 | 손목 2D 오차 px 중앙값 (p90) | ÷아래팔 | 교체 프레임 MP / RTM px | '
          '손목 3D mm | 팔꿈치 3D mm | 팔꿈치각 프레임 ° (p90) | 가까운 팔꿈치 렙극값 ° | 손목 가속도 오차 | MPJPE |', '|---' * 18 + '|']
    for k, rs in groups_of(recs, ('group', 'exercise', 'mode', 'var')):
        s = dict(videos=len(rs), crop_made=round(float(np.mean([r['crop_made'] for r in rs])), 4),
                 detected=round(float(np.mean([r['detected'] for r in rs])), 4), replaced=round(float(np.mean([r['replaced'] for r in rs])), 4),
                 crossed=int(sum(r['crossed'] for r in rs)),
                 **{q: st(cat(rs, q)) for q in ('w2d_px', 'w2d_fore', 'w2d_px_rep', 'w2d_px_rep_rtm', 'wrist3d', 'elbow3d', 'wrist_acc', 'elbow_ang', 'mpjpe')},
                 elbow_rep=st(cat(rs, 'elbow_near', 'rep')), elbow_frame_near=st(cat(rs, 'elbow_near', 'frame')))
        summ['/'.join(k)] = s
        f = lambda q, kk='p50': s[q].get(kk, float('nan'))
        md.append(f"| {k[0]} | {k[1]} | {k[2]} | {k[3]} | {s['videos']} | {s['crop_made']:.1%} | {s['detected']:.1%} | {s['replaced']:.1%} | {s['crossed']} | "
                  f"{f('w2d_px'):.1f} ({f('w2d_px', 'p90'):.0f}) | {f('w2d_fore'):.2f} | {f('w2d_px_rep'):.1f} / {f('w2d_px_rep_rtm'):.1f} | "
                  f"{f('wrist3d', 'mean'):.1f} | {f('elbow3d', 'mean'):.1f} | {f('elbow_ang'):.1f} ({f('elbow_ang', 'p90'):.0f}) | "
                  f"{f('elbow_rep'):.1f} | {f('wrist_acc', 'mean'):.2f} | {f('mpjpe', 'mean'):.1f} |")
    finish(a, 'wrist', summ, md, inputs + [a.task] if a.task else inputs)


# ---------------------------------------------------------------- Core ML parity
def run_coreml_dump(a):
    model, dev = load_model(a); seqs = load_seqs(a)
    import torch
    xs, mm = [], []
    for d in seqs[:: max(1, len(seqs) // 6)][:6]:  # 6 sequences, 16 windows each, spread over the sequence
        n = len(d['x'])
        for e in np.linspace(WINDOW, n - 1, 16).astype(int):
            xs.append(d['x'][e - WINDOW + 1:e + 1]); mm.append(d['mm'][e])
    X = np.stack(xs).astype(np.float32)
    with torch.no_grad(): Y = model(torch.from_numpy(X).to(dev)).cpu().numpy()
    out = Path(a.run_dir) / 'coreml_dump.npz'; np.savez(out, x=X, y=Y, mm=np.array(mm, np.float32))
    write_manifest(a, [d['csv'] for d in seqs[:: max(1, len(seqs) // 6)][:6]] + [a.checkpoint], [out],
                   dict(note='windows of Fit3D-derived 2D input: delete after coreml-check'))


def run_coreml_check(a):
    import coremltools as ct
    z = np.load(a.dump); X, Y, mm = z['x'], z['y'], z['mm']
    res = {}
    for cu in ('ALL', 'CPU_ONLY'):
        m = ct.models.MLModel(a.mlpackage, compute_units=getattr(ct.ComputeUnit, cu))
        C = np.stack([np.asarray(m.predict({'input_2d_sequence': x[None]})['pred_3d_sequence'])[0] for x in X])
        dd = np.abs(C - Y); row = dd[:, WINDOW - 1 - 5]
        res[cu] = dict(windows=len(X), max_abs_all_rows=float(dd.max()), max_abs_row21=float(row.max()), mean_abs=float(dd.mean()),
                       max_mm_row21=float((row * mm[:, None, None]).max()),
                       mpjpe_mm_row21=float((np.linalg.norm((C - C[:, :, :1]) - (Y - Y[:, :, :1]), axis=-1)[:, WINDOW - 1 - 5].mean(1) * mm).mean()))
    print(json.dumps(res, indent=1))
    out = Path(a.run_dir) / 'coreml_check.json'; json.dump(res, open(out, 'w'), indent=1)
    write_manifest(a, [a.dump, *glob.glob(f'{a.mlpackage}/**/*', recursive=True)], [out])


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['lookahead', 'gt-stats', 'xs-knee', 'constraints', 'hands', 'wrist', 'coreml-dump', 'coreml-check'])
    p.add_argument('--gt-limits', default=None, help='gt_stats.json (tuning subjects) -> extra variant f with p0.1/p99.9 limits')
    p.add_argument('--root'); p.add_argument('--replay'); p.add_argument('--run-dir', required=True)
    p.add_argument('--subjects', type=lambda s: s.split(','), default=['s03', 's04', 's05', 's07', 's08', 's09', 's10', 's11'])
    p.add_argument('--exercises', type=lambda s: s.split(','), default=list(EXERCISES))
    p.add_argument('--lookaheads', type=lambda s: [int(v) for v in s.split(',')], default=[0, 1, 2, 3, 5, 8, 13])
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    p.add_argument('--checkpoint', default=None); p.add_argument('--cpu', action='store_true')
    p.add_argument('--constraint', default=None, help='MODULE:FUNC, P [N,17,3] crop units -> same (S5)')
    p.add_argument('--task'); p.add_argument('--hands'); p.add_argument('--jobs', type=int, default=10)
    p.add_argument('--gates', type=lambda s: s.split(','), default=['d0.25', 'd0.5', 'd1.0', 'c0.5', 'c0.7'])
    p.add_argument('--dump'); p.add_argument('--mlpackage')
    p.add_argument('--vars-3d', type=lambda s: s.split(','), default=[], help='wrist variants that also get the XS 3D pass')
    p.add_argument('--modes-3d', type=lambda s: s.split(','), default=list(HAND_MODES))
    p.add_argument('--cache', default=None, help='dir for raw XS rows of the app input, shared by lookahead/xs-knee/constraints')
    a = p.parse_args()
    CACHE['dir'] = a.cache
    a.checkpoint = a.checkpoint or f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr'
    os.makedirs(a.run_dir, exist_ok=True)
    {'lookahead': run_lookahead, 'gt-stats': run_gt_stats, 'xs-knee': run_xs_knee, 'constraints': run_constraints, 'hands': run_hands, 'wrist': run_wrist,
     'coreml-dump': run_coreml_dump, 'coreml-check': run_coreml_check}[a.cmd](a)


if __name__ == '__main__':
    main()
