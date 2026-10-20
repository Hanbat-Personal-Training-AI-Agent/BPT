"""GVHMR vs the live path on Fit3D (local only — Fit3D is non-commercial, no redistribution: nothing here leaves
the machine except the aggregate numbers that `score` prints).

  A  : live path = app RTMPose-m COCO17 2D (pose-replay CSV, Core ML on Mac) -> MotionAGFormer-XS (H36M ckpt, the
       app's 27-frame / lookahead-5 window), via scripts/eval_3d_angles.py unchanged. A2D = the app's own 2D angles.
  B  : GVHMR, static camera (demo -s), default intrinsics (focal = image diagonal).
  C  : GVHMR, static camera, f_mm from the Fit3D camera's intrinsics (full-frame equivalent, diagonal rule as
       GVHMR's create_camera_sensor).
  GT : Fit3D mocap joints3d_25 -> H36M-17 (eval_3d_angles.FIT3D_TO_H36M).
Input camera: per subject x exercise the Fit3D camera closest to a side view (eval_3d_angles.view_and_side).
Frames: 50 fps -> 30 fps by the evaluator's pick (round(arange(0, n, 50/30))), the same frames for A, B, C, GT.

  python eval_gvhmr_fit3d.py jobs  --root ~/datasets/fit3d --replay ~/bpt-smpl/replay --out jobs.json   (any env)
  python eval_gvhmr_fit3d.py gvhmr --root ~/datasets/fit3d --jobs jobs.json --work DIR [--half]          (bpt-gvhmr)
  python eval_gvhmr_fit3d.py lift  --root ~/datasets/fit3d --jobs jobs.json --work DIR                   (bpt-home)
  python eval_gvhmr_fit3d.py floor --root ~/datasets/fit3d --jobs jobs.json --work DIR                   (bpt-gvhmr)
  python eval_gvhmr_fit3d.py score --root ~/datasets/fit3d --jobs jobs.json --work DIR --out score.json  (any env)
"""
import argparse, json, os, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
SUBJECTS = ['s07', 's08', 's09', 's10', 's11']  # Fit3D held-out split used by every BPT track
# BPT exercise -> Fit3D action (names that match; barbell_dead_row / diamond_pushup are other movements)
EXERCISES = {'squat': 'squat', 'barbell_row': 'barbell_row', 'pushup': 'pushup', 'deadlift': 'deadlift'}
FIT3D_FPS, APP_FPS = 50, 30
DIAG_FF = (24 ** 2 + 36 ** 2) ** 0.5
VARIANTS = ['A2D', 'A', 'B', 'C']


def ev():
    import eval_3d_angles as e  # scripts/ (on sys.path in __main__)
    return e


def pick_frames(n):
    p = np.round(np.arange(0, n, FIT3D_FPS / APP_FPS)).astype(int)
    return p[p < n]


def load_cam(root, s, cam, ex):
    c = json.load(open(f'{root}/train/{s}/camera_parameters/{cam}/{ex}.json'))
    return np.array(c['extrinsics']['R']), np.array(c['extrinsics']['T']).reshape(3), c


def world_up(R):
    up = -R[1] / np.linalg.norm(R[1])
    return np.array([0, 0, 1.]) if abs(up[2]) > 0.8 else up  # same rule as eval_3d_angles.run_fit3d


def cmd_jobs(a):
    e = ev(); jobs = []
    for s in SUBJECTS:
        ann = json.load(open(f'{a.root}/train/{s}/rep_ann.json'))
        for bpt, ex in EXERCISES.items():
            J = e.load_joints(f'{a.root}/train/{s}', ex)
            if J is None or ex not in ann: continue
            views = []
            for cam in sorted(os.listdir(f'{a.root}/train/{s}/camera_parameters')):
                R, T, c = load_cam(a.root, s, cam, ex)
                ang, side = e.view_and_side(J, R, T, world_up(R))
                views.append((ang, cam, side, c))
            ang, cam, side, c = min(views)
            f = np.mean(c['intrinsics_wo_distortion']['f'])
            csv = sorted(Path(a.replay).glob(f'{s}/{cam}/{ex}_*coco17.csv')) if a.replay else []
            jobs.append(dict(subject=s, exercise=bpt, fit3d=ex, cam=cam, view_deg=round(ang, 1), side_gt=side,
                             f_px=round(f, 1), f_mm=round(f * DIAG_FF / (900 * 2 ** 0.5), 2), reps=ann[ex],
                             replay=str(csv[0]) if csv else None, all_views={v[1]: round(v[0], 1) for v in views}))
            print(jobs[-1]['subject'], bpt, cam, jobs[-1]['view_deg'], jobs[-1]['f_mm'], bool(csv), flush=True)
    json.dump(jobs, open(a.out, 'w'), indent=1)


def tag(j):
    return f"{j['subject']}_{j['exercise']}_{j['cam']}"


def cmd_gvhmr(a):
    """B then C per job. The runner's 30 fps pick of a 50 fps video is exactly pick_frames; C reuses B's
    preprocessing (same frames, only the intrinsics differ), so C's timing covers network + postprocess only."""
    import gvhmr_runner as g
    for j in json.load(open(a.jobs)):
        d = Path(a.work) / tag(j)
        if (d / 'C' / 'result.npz').exists(): continue
        src = f"{a.root}/train/{j['subject']}/videos/{j['cam']}/{j['fit3d']}.mp4"
        meta = g.run(src, d / 'B', f_mm=None, half=a.half, keep_video=True)
        print(tag(j), 'B', meta['timing_s'], meta['vram_peak_mib'], flush=True)
        (d / 'C').mkdir(exist_ok=True); os.replace(d / 'B' / 'preproc.pt', d / 'C' / 'preproc.pt')
        (d / 'B' / 'input_30fps.mp4').unlink()
        meta = g.run(src, d / 'C', f_mm=j['f_mm'], half=a.half)
        print(tag(j), 'C', meta['timing_s'], flush=True)


def cmd_lift(a):
    e = ev()
    runner = e.load_lifter(a.checkpoint, a.mag_repo)
    for j in json.load(open(a.jobs)):
        d = Path(a.work) / tag(j); out = d / 'A.npz'
        if out.exists() or not j['replay']: continue
        d.mkdir(parents=True, exist_ok=True)
        K = e.read_csv(j['replay']); pick = pick_frames(len(K)); K = K[pick]
        np.savez_compressed(out, P=e.lift(K, 900, 900, runner), K=K)
        print(tag(j), 'A', len(K), flush=True)


class SmplxH36M:
    """Fit3D official SMPL-X params (rotation matrices) -> SMPL-X vertices -> smplx2smpl -> J_regressor_h36m.
    Same numpy LBS as scripts/check_fit3d_coco17_labels.py (ai/rtmpose-ft) with the H36M regressor; only the
    vertices the regressor touches are skinned."""

    def __init__(self, model_dir, x2s, h36m_npz, gender='neutral'):
        import torch
        m = np.load(f'{model_dir}/SMPLX_{gender.upper()}.npz', allow_pickle=True)
        W = np.load(h36m_npz)['J_regressor_h36m'] @ torch.load(x2s).to_dense().double().numpy()  # (17, 10475)
        self.vid = np.where(np.abs(W).sum(0) > 0)[0]; self.W = W[:, self.vid]
        sd = m['shapedirs'].astype(np.float64)
        self.vt, self.sd, self.ed = m['v_template'][self.vid].astype(np.float64), sd[self.vid, :, :10], sd[self.vid, :, 300:310]
        self.pd = m['posedirs'][self.vid].astype(np.float64); self.lw = m['weights'][self.vid].astype(np.float64)
        Jr = m['J_regressor'].astype(np.float64)
        self.Jt, self.Js, self.Je = Jr @ m['v_template'], np.einsum('jv,vck->jck', Jr, sd[:, :, :10]), np.einsum('jv,vck->jck', Jr, sd[:, :, 300:310])
        self.parents = m['kintree_table'][0].astype(np.int64); self.parents[0] = -1  # stored as uint32 max

    def __call__(self, path):
        p = {k: np.array(v, np.float64) for k, v in json.load(open(path)).items()}
        R = np.concatenate([p['global_orient'], p['body_pose'], p['jaw_pose'], p['leye_pose'], p['reye_pose'],
                            p['left_hand_pose'], p['right_hand_pose']], 1)
        b, e = p['betas'], p['expression']
        J = self.Jt + np.einsum('tk,jck->tjc', b, self.Js) + np.einsum('tk,jck->tjc', e, self.Je)
        T = len(R); G = np.zeros((T, 55, 4, 4)); G[:, :, 3, 3] = 1
        for j, q in enumerate(self.parents):
            loc = np.zeros((T, 4, 4)); loc[:, :3, :3] = R[:, j]; loc[:, 3, 3] = 1
            loc[:, :3, 3] = J[:, j] - (J[:, q] if q >= 0 else 0)
            G[:, j] = loc if q < 0 else G[:, q] @ loc
        A = G.copy(); A[:, :, :3, 3] -= np.einsum('tjcd,tjd->tjc', G[:, :, :3, :3], J)
        pf = (R[:, 1:] - np.eye(3)).reshape(T, -1)
        v = self.vt + np.einsum('tk,vck->tvc', b, self.sd) + np.einsum('tk,vck->tvc', e, self.ed) + np.einsum('tk,vck->tvc', pf, self.pd)
        M = np.einsum('vj,tjcd->tvcd', self.lw, A)
        v = np.einsum('tvcd,tvd->tvc', M[..., :3, :3], v) + M[..., :3, 3] + p['transl'][:, None]
        return np.einsum('kv,tvc->tkc', self.W, v)


def cmd_floor(a):
    """GT SMPL-X through the same H36M conversion, so the conversion + joint-definition gap is measured."""
    import gvhmr_runner as g
    conv = SmplxH36M(a.smplx, g.GVHMR_ROOT / 'hmr4d/utils/body_model/smplx2smpl_sparse.pt', g.H36M_NPZ)
    for j in json.load(open(a.jobs)):
        out = Path(a.work) / tag(j) / 'floor.npz'
        if out.exists(): continue
        out.parent.mkdir(parents=True, exist_ok=True)
        P = conv(f"{a.root}/train/{j['subject']}/smplx/{j['fit3d']}.json")
        np.savez_compressed(out, P=P[pick_frames(len(P))]); print(tag(j), 'floor', flush=True)


# ---------------------------------------------------------------- scoring
def pa_mpjpe(P, G):
    """Per-frame Procrustes (rotation + scale + translation) of P onto G, mean joint error (G units)."""
    out = []
    for p, q in zip(P, G):
        p0, q0 = p - p.mean(0), q - q.mean(0)
        U, S, Vt = np.linalg.svd(p0.T @ q0)
        d = np.sign(np.linalg.det(U @ Vt)); D = np.diag([1, 1, d])
        Rm = U @ D @ Vt; s = (S * np.diag(D)).sum() / (p0 ** 2).sum()
        out.append(np.linalg.norm(s * p0 @ Rm - q0, axis=1).mean())
    return np.array(out)


def rep_metrics(ang, segs):
    """Per-rep values the Swift rules use (FormWarnings.swift), from one angle set."""
    r = []
    for s, e in segs:
        sl = slice(s, e + 1)
        r.append(dict(knee_min=np.nanmin(ang['knee'][sl]), knee_max=np.nanmax(ang['knee'][sl]),
                      elbow_min=np.nanmin(ang['elbow'][sl]), elbow_max=np.nanmax(ang['elbow'][sl]),
                      hip_max=np.nanmax(ang['hip'][sl]), torso_range=np.ptp(ang['torso'][sl])))
    return r


# key -> (exercise, decision value from the rep list, threshold) — thresholds as in FormWarnings.swift
def _over_baseline(name):
    return lambda reps: [r[name] - np.median([q[name] for q in reps[:3]]) if i >= 3 else np.nan for i, r in enumerate(reps)]


def _below_set_max(name):
    return lambda reps: [max(q[name] for q in reps[:i + 1]) - r[name] for i, r in enumerate(reps)]


KEYS = {
    'row_torso_swing': ('barbell_row', lambda reps: [r['torso_range'] for r in reps], 39.9),  # Exercise3D p99
    'squat_shallow': ('squat', _over_baseline('knee_min'), 15.0),
    'squat_no_lockout': ('squat', _below_set_max('knee_max'), 10.0),
    'pushup_shallow': ('pushup', _over_baseline('elbow_min'), 15.0),
    'pushup_no_lockout': ('pushup', _below_set_max('elbow_max'), 10.0),
}
BOUNDARY = 5.0


def cmd_score(a):
    e = ev(); res = []
    for j in json.load(open(a.jobs)):
        d = Path(a.work) / tag(j)
        if not (d / 'B' / 'result.npz').exists(): continue
        G = e.load_joints(f"{a.root}/train/{j['subject']}", j['fit3d']); R, T, _ = load_cam(a.root, j['subject'], j['cam'], j['fit3d'])
        up = world_up(R); pick50 = pick_frames(len(G)); G = G[pick50]
        P, K = {}, None
        for v in ('B', 'C'):
            z = np.load(d / v / 'result.npz'); P[v] = z['h36m17_cam'].astype(float)
            P[v + 'w'] = z['h36m17_world'].astype(float)
        if (d / 'A.npz').exists():
            z = np.load(d / 'A.npz'); P['A'] = z['P']; K = z['K']
        F = np.load(d / 'floor.npz')['P'] if (d / 'floor.npz').exists() else None
        n = min([len(G)] + [len(x) for x in P.values()] + ([len(K)] if K is not None else []))
        G = G[:n]; P = {k: v[:n] for k, v in P.items()}
        side = e.near_side(K[:n]) if K is not None else j['side_gt']
        segs = [(int(np.searchsorted(pick50, s)), int(np.searchsorted(pick50, t))) for s, t in zip(j['reps'], j['reps'][1:])]
        segs = [(s, min(t, n - 1)) for s, t in segs if s < n - 1]
        inside = np.zeros(n, bool)
        for s, t in segs: inside[s:t + 1] = True
        cam_up = np.array([0, -1., 0])
        ang = {'GT': e.angles_3d(G, up, side)}
        for k in ('A', 'B', 'C'):
            if k in P: ang[k] = e.angles_3d(P[k], cam_up, side)
        for k in ('Bw', 'Cw'):
            ang[k] = e.angles_3d(P[k], np.array([0, 1., 0]), side)  # GVHMR gravity-aligned world, y up
        if K is not None: ang['A2D'] = e.angles_2d(K[:n], side)
        if F is not None: ang['floor'] = e.angles_3d(F[:n], up, side)
        r = dict(subject=j['subject'], exercise=j['exercise'], cam=j['cam'], view_deg=j['view_deg'], side=side,
                 frames=int(inside.sum()), reps_truth=len(j['reps']) - 1, angle_err={}, pa_mpjpe_mm={}, reps={}, rep_metrics={})
        for k, A_ in ang.items():
            if k == 'GT': continue
            r['angle_err'][k] = {q: float(np.nanmean(np.abs(A_[q] - ang['GT'][q])[inside])) for q in ('knee', 'hip', 'elbow', 'torso')}
        for k in ('A', 'B', 'C'):
            if k in P: r['pa_mpjpe_mm'][k] = float(pa_mpjpe(P[k][inside], G[inside]).mean() * 1000)
        if F is not None:
            r['pa_mpjpe_mm']['floor'] = float(pa_mpjpe(F[:n][inside], G[inside]).mean() * 1000)
            r['mpjpe_floor_mm'] = float(np.linalg.norm(F[:n] - G, axis=-1)[inside].mean() * 1000)
            r['floor_joint_mm'] = (np.linalg.norm(F[:n] - G, axis=-1)[inside].mean(0) * 1000).round(1).tolist()
        import count_reps_3d_vs_2d as c
        limb = 'hip' if j['exercise'] == 'deadlift' else c.LIMB[j['fit3d']]
        for k, A_ in ang.items():
            r['reps'][k] = int(c.count(A_[limb]))
            r['rep_metrics'][k] = [{q: float(v) for q, v in m.items()} for m in rep_metrics(A_, segs)]
        res.append(r); print(tag(j), {k: round(v['knee'], 1) for k, v in r['angle_err'].items()}, r['reps'], flush=True)
    json.dump(res, open(a.out, 'w'), indent=1)
    report(res)


def rep_acc(rows, k):
    """BPT rep accuracy: (truth - missed) / (truth + extra), summed over videos."""
    t = sum(r['reps_truth'] for r in rows if k in r['reps'])
    if not t: return None
    miss = sum(max(0, r['reps_truth'] - r['reps'][k]) for r in rows if k in r['reps'])
    extra = sum(max(0, r['reps'][k] - r['reps_truth']) for r in rows if k in r['reps'])
    return (t - miss) / (t + extra)


def decisions(rows, key):
    """Per rep: GT decision vs each variant's, all reps and reps whose GT value is within BOUNDARY of the threshold."""
    ex, fn, thr = KEYS[key]; out = {}
    for r in rows:
        if r['exercise'] != ex: continue
        g = np.array(fn(r['rep_metrics']['GT']), float)
        for k, m in r['rep_metrics'].items():
            if k == 'GT': continue
            p = np.array(fn(m), float); ok = np.isfinite(g) & np.isfinite(p)
            near = ok & (np.abs(g - thr) <= BOUNDARY)
            o = out.setdefault(k, [0, 0, 0, 0])
            o[0] += int(((g > thr) == (p > thr))[ok].sum()); o[1] += int(ok.sum())
            o[2] += int(((g > thr) == (p > thr))[near].sum()); o[3] += int(near.sum())
    return out


def report(res):
    exs = list(EXERCISES)
    cols = ['A2D', 'A', 'B', 'C', 'Bw', 'Cw', 'floor']
    print('\n## joint-angle mean abs error (deg), frames inside reps')
    for ex in exs:
        rows = [r for r in res if r['exercise'] == ex]
        if not rows: continue
        for q in ('knee', 'hip', 'elbow', 'torso'):
            vals = []
            for k in cols:
                v = [r['angle_err'][k][q] for r in rows if k in r['angle_err']]
                vals.append(f'{np.mean(v):.1f}' if v else '-')
            print(f'| {ex} | {q} | ' + ' | '.join(vals) + ' |')
    print('\n## PA-MPJPE (mm)')
    for ex in exs:
        rows = [r for r in res if r['exercise'] == ex]
        if rows: print(f'| {ex} | ' + ' | '.join(f"{np.mean([r['pa_mpjpe_mm'][k] for r in rows if k in r['pa_mpjpe_mm']]):.1f}"
                                         if any(k in r['pa_mpjpe_mm'] for r in rows) else '-' for k in ('A', 'B', 'C', 'floor')) + ' |')
    print('\n## rep accuracy (simple counter, count_reps_3d_vs_2d.count)')
    for ex in exs:
        rows = [r for r in res if r['exercise'] == ex]
        if rows: print(f'| {ex} | ' + ' | '.join('-' if rep_acc(rows, k) is None else f'{100 * rep_acc(rows, k):.1f}%' for k in ['GT'] + cols[:6]) + ' |')
    print('\n## decision agreement with GT: all reps / reps within ±5 of threshold')
    for key in KEYS:
        d = decisions(res, key)
        print(f'| {key} | ' + ' | '.join(f'{d[k][0]}/{d[k][1]} ; {d[k][2]}/{d[k][3]}' if k in d else '-' for k in cols[:6]) + ' |')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['jobs', 'gvhmr', 'lift', 'floor', 'score'])
    p.add_argument('--root', default=str(Path.home() / 'datasets/fit3d'))
    p.add_argument('--replay', default=str(Path.home() / 'bpt-smpl/replay'))
    p.add_argument('--jobs'); p.add_argument('--work'); p.add_argument('--out')
    p.add_argument('--half', action='store_true')
    p.add_argument('--smplx', default=str(Path.home() / 'models/smplx'))
    p.add_argument('--mag-repo', default=str(Path.home() / 'models/MotionAGFormer'))
    p.add_argument('--checkpoint', default=str(Path.home() / 'models/MotionAGFormer/checkpoint/motionagformer-xs-h36m.pth.tr'))
    a = p.parse_args()
    {'jobs': cmd_jobs, 'gvhmr': cmd_gvhmr, 'lift': cmd_lift, 'floor': cmd_floor, 'score': cmd_score}[a.cmd](a)


if __name__ == '__main__':
    sys.path.insert(0, str(HERE.parent))  # scripts/: eval_3d_angles, count_reps_3d_vs_2d
    sys.path.insert(0, str(HERE))
    main()
