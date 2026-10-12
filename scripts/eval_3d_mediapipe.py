"""3D accuracy on Fit3D mocap: MediaPipe Pose world landmarks vs MotionAGFormer-XS vs the app's 2D angles (D-D-07).

Sources, all on the same frames (Fit3D 50 fps video picked down to the app's 30 fps):
  2d        app 2D: pose-replay CSV (RTMPose-m COCO17, crop input = the app default), image angles as in D-D.
  mp_<m>    MediaPipe Pose Landmarker lite/full/heavy, VIDEO mode on the whole frame, pose_world_landmarks
            (metres, origin = mid-hip, camera-aligned axes x right / y down / z away), mapped to H36M-17 (MP_H36M).
  mag_orig  MotionAGFormer-XS H36M weights on the app 2D (app window 27, lookahead 5), crop units -> metres with the
            mocap root depth (weak perspective, as finetune_motionagformer_fit3d.py) - an oracle scale MediaPipe lacks.
  mag_ft    same with Fit3D fine-tuned weights (trained on the tuning subjects s03-s05 only).
Metrics per video: MPJPE (root-aligned, all 17 joints), PA-MPJPE (per-frame similarity Procrustes), acceleration
error (jitter, mm/frame^2 at 30 fps), MediaPipe person-found rate, and the D-D angle errors per rep (extreme:
knee/hip/elbow min, torso max) and per frame for knee / hip / elbow / torso. torso = mid-hip->mid-shoulder vs
camera up (-y, what the app sees without gravity); torso_g = vs true gravity in the camera frame (a level-free IMU).
2D torso is vs image vertical for both. Angles use the app's near side (2D confidence), like D-D.
Exercise3D (`ex3d`): same angles against Sapiens-triangulated labels (NOT ground truth, relative comparison only).

Fit3D licence: run on the user's own machines only; inputs/outputs here are aggregates, never committed.

usage (Home, bpt-home):
  eval_3d_mediapipe.py mp-fit3d --root ~/datasets/fit3d --models DIR --subjects s03,... --out MPDIR [--jobs 6]
  eval_3d_mediapipe.py mp-ex3d  --videos DIR --gt gt.json --models DIR --out MPDIR [--max-view 75]
  eval_3d_mediapipe.py fit3d --root ~/datasets/fit3d --replay DIR --mp MPDIR --ft CKPT --subjects ... --out JSON
  eval_3d_mediapipe.py ex3d  --outputs DIR --replay DIR --mp MPDIR --ft CKPT --out JSON
  eval_3d_mediapipe.py offsets --root ~/datasets/fit3d --replay DIR --mp MPDIR --subjects ... --out JSON
  eval_3d_mediapipe.py table RESULT.json [...]
"""
import argparse, ast, glob, json, os, sys
from multiprocessing import Pool
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval_3d_angles import (APP_FPS, EX3D_NAMES, EXTREME, H36M, angles_2d, angles_3d, fit3d_jobs, incline,  # noqa: E402
                            near_side, read_csv, view_and_side)

MODELS = ('lite', 'full', 'heavy')
CAMS = ('50591643', '58860488', '60457274', '65906101')
EXERCISES = ('squat', 'pushup', 'barbell_row')
TUNING = {'s03', 's04', 's05'}
# BlazePose 33 -> H36M 17. -1 = built: pelvis = mid BlazePose hips (MediaPipe's own world origin), thorax = mid
# shoulders, spine = mid pelvis-thorax, head = mid ears (H36M head is the top of the head: ~10 cm higher). 9 = nose.
MP_H36M = [-1, 24, 26, 28, 23, 25, 27, -1, -1, 0, -1, 11, 13, 15, 12, 14, 16]
ANGLES = ('knee', 'hip', 'elbow', 'torso', 'torso_g')


def mp_to_h36m(W):
    J = W[:, [max(i, 0) for i in MP_H36M]].copy()
    J[:, 0] = (W[:, 23] + W[:, 24]) / 2
    J[:, 8] = (W[:, 11] + W[:, 12]) / 2
    J[:, 7] = (J[:, 0] + J[:, 8]) / 2
    J[:, 10] = (W[:, 7] + W[:, 8]) / 2
    return J


# ---------------------------------------------------------------- MediaPipe runs
def run_mp(job):
    """VIDEO mode over `video`, only frames in `pick` (None = all), timestamps at `fps`. Saves world [N,33,3]
    (NaN where no person), image landmarks [N,33,3] (x, y normalised, visibility)."""
    video, task, pick, fps, out = job
    if os.path.exists(out): return out
    import cv2, mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision
    lm = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=task), running_mode=vision.RunningMode.VIDEO))
    cap = cv2.VideoCapture(video); fps = fps or cap.get(cv2.CAP_PROP_FPS)
    want = None if pick is None else set(int(i) for i in pick)
    world, img, i, k = [], [], 0, 0
    while True:
        ok, fr = cap.read()
        if not ok: break
        if want is None or i in want:
            r = lm.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)),
                                    int(round(k * 1000 / fps)))
            if r.pose_world_landmarks:
                world.append([(p.x, p.y, p.z) for p in r.pose_world_landmarks[0]])
                img.append([(p.x, p.y, p.visibility) for p in r.pose_landmarks[0]])
            else:
                world.append(np.full((33, 3), np.nan)); img.append(np.full((33, 3), np.nan))
            k += 1
        i += 1
    lm.close()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    np.savez(out + '.tmp.npz', world=np.array(world, np.float32), img=np.array(img, np.float32))
    os.replace(out + '.tmp.npz', out)
    return out


def pick_frames(n50):
    return np.round(np.arange(0, n50, 50 / APP_FPS)).astype(int)


def mp_fit3d(a):
    import cv2
    jobs = []
    for subj in a.subjects:
        for cam in CAMS:
            for ex in a.exercises:
                v = f'{a.root}/train/{subj}/videos/{cam}/{ex}.mp4'
                if not os.path.exists(v): continue
                n = int(cv2.VideoCapture(v).get(cv2.CAP_PROP_FRAME_COUNT))
                for m in MODELS:
                    jobs.append((v, f'{a.models}/pose_landmarker_{m}.task', pick_frames(n), APP_FPS, f'{a.out}/{m}/{subj}/{cam}/{ex}.npz'))
    print(len(jobs), 'jobs', flush=True)
    with Pool(a.jobs) as p:
        for i, o in enumerate(p.imap_unordered(run_mp, jobs)): print(i, o, flush=True)


def mp_ex3d(a):
    gt = json.load(open(a.gt)); jobs = []
    for seq, g in gt.items():
        for cam, v in g['views'].items():
            if v['angle_deg'] > a.max_view: continue
            for m in MODELS:
                jobs.append((f"{a.videos}/{g['exercise']}/{seq}/{cam}.mp4", f'{a.models}/pose_landmarker_{m}.task', None, None,
                             f'{a.out}/{m}/{seq}/{cam}.npz'))
    print(len(jobs), 'jobs', flush=True)
    with Pool(a.jobs) as p:
        for i, o in enumerate(p.imap_unordered(run_mp, jobs)): print(i, o, flush=True)


# ---------------------------------------------------------------- metrics
def procrustes(P, G):
    """Per-frame similarity alignment of P onto G ([N,J,3]); rows with NaN stay NaN."""
    mp_, mg = P.mean(1, keepdims=True), G.mean(1, keepdims=True)
    X, Y = P - mp_, G - mg
    U, S, Vt = np.linalg.svd(np.nan_to_num(np.swapaxes(X, 1, 2) @ Y))
    d = np.sign(np.linalg.det(U @ Vt))
    U[:, :, -1] *= d[:, None]; S[:, -1] *= d
    R = U @ Vt
    s = S.sum(1) / (np.nan_to_num(X) ** 2).sum((1, 2)).clip(1e-12)
    return s[:, None, None] * X @ R + mg


def pose_metrics(P, G):
    """P, G root-relative metres [N,17,3] (P may have NaN rows). Per-frame MPJPE, PA-MPJPE (mm), accel error."""
    ok = ~np.isnan(P).any((1, 2))
    e = np.linalg.norm(P - G, axis=-1).mean(-1) * 1000
    pa = np.linalg.norm(procrustes(P, G) - G, axis=-1).mean(-1) * 1000
    acc = lambda X: X[2:] - 2 * X[1:-1] + X[:-2]
    okA = ok[2:] & ok[1:-1] & ok[:-2]
    ae = (np.linalg.norm(acc(P) - acc(G), axis=-1).mean(-1) * 1000)[okA]
    return dict(mpjpe=e[ok].tolist(), pa_mpjpe=pa[ok].tolist(), accel=ae.tolist(), found=float(ok.mean()))


def angle_metrics(A, ref, segments):
    """A, ref: {angle: [N]}. Rep-extreme error per rep, frame error and angle jitter (|d2 A - d2 ref|) inside reps."""
    inside = np.zeros(len(ref['knee']), bool)
    for s, e in segments: inside[s:e + 1] = True
    out = {}
    for k in ANGLES:
        a, r, ext = A[k], ref[k], EXTREME[k.split('_')[0]]
        reps = [abs(ext(a[s:e + 1]) - ext(r[s:e + 1])) for s, e in segments if not np.isnan(a[s:e + 1]).all()]
        d2 = lambda x: x[2:] - 2 * x[1:-1] + x[:-2]
        j = np.abs(d2(a) - d2(r))[inside[1:-1]]
        f = np.abs(a - r)[inside]
        out[k] = dict(rep=reps, frame=f[~np.isnan(f)].tolist(), jitter=j[~np.isnan(j)].tolist())
    return out


def angles(P, side, up):
    """H36M-ordered 3D [N,17,3] in the camera frame -> knee/hip/elbow/torso(cam -y)/torso_g(true up `up`)."""
    out = angles_3d(P, np.array([0., -1, 0]), side)
    out['torso_g'] = incline((P[:, 11] + P[:, 14]) / 2 - (P[:, 1] + P[:, 4]) / 2, up)
    return out


def angles_from_2d(K, side):
    out = angles_2d(K, side); out['torso_g'] = out['torso']
    return out


def load_mag(ckpt, mag_repo):
    import torch
    from finetune_motionagformer_fit3d import load
    dev = 'cuda' if torch.cuda.is_available() else 'cpu'
    return load(mag_repo, ckpt, dev)[0], dev


def mag_predict(model, dev, x):
    from finetune_motionagformer_fit3d import app_predict
    P = app_predict(model, x, dev).astype(float)
    return P - P[:, :1]


def load_mp(path, n):
    W = np.load(path)['world'][:n].astype(float)
    return mp_to_h36m(W) - mp_to_h36m(W)[:, :1]


def run_fit3d(a):
    from finetune_motionagformer_fit3d import prep
    mags = {'mag_orig': load_mag(a.orig, a.mag_repo), 'mag_ft': load_mag(a.ft, a.mag_repo)} if a.ft else \
        {'mag_orig': load_mag(a.orig, a.mag_repo)}
    out = []
    for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(a.root, a.replay, a.subjects, a.exercises):
        d = prep(a.root, subj, ex, cam, J, R, T, csv); pick, n = d['pick'], len(d['pick'])
        up_w = -R[1] / np.linalg.norm(R[1]); up_w = np.array([0, 0, 1.]) if abs(up_w[2]) > 0.8 else up_w
        up_c = R @ up_w  # gravity "up" in the camera frame (y down)
        G = d['y'] * d['mm'][:, None, None] / 1000  # metres, camera frame, root-relative
        view, _ = view_and_side(J, R, T, up_w); side = near_side(d['K'])
        seg = [(int(np.searchsorted(pick, s)), int(np.searchsorted(pick, e))) for s, e in zip(ann, ann[1:])]
        ref = angles(G, side, up_c); ref['torso'] = ref['torso_g']  # the truth's torso is always vs gravity
        res = dict(source='fit3d', subject=subj, exercise=ex, cam=cam, view_deg=round(view, 1), side=side,
                   group='tuning' if subj in TUNING else 'heldout', frames=n,
                   cam_pitch_deg=round(float(np.degrees(np.arcsin(np.clip(R[2] @ up_w, -1, 1)))), 1))
        res['2d'] = angle_metrics(angles_from_2d(d['K'], side), ref, seg)
        for name, (model, dev) in mags.items():
            P = mag_predict(model, dev, d['x']) * d['mm'][:, None, None] / 1000
            res[name] = {**angle_metrics(angles(P, side, up_c), ref, seg), **pose_metrics(P, G)}
        for m in MODELS:
            P = load_mp(f'{a.mp}/{m}/{subj}/{cam}/{ex}.npz', n)
            P[:, :, 2] *= a.mp_zsign
            res[f'mp_{m}'] = {**angle_metrics(angles(P, side, up_c), ref, seg), **pose_metrics(P, G)}
        print(subj, ex, cam, f'view={view:.0f}', {s: (round(np.mean(res[s]['mpjpe'])), round(np.mean(res[s]['pa_mpjpe'])))
                                                  for s in res if isinstance(res[s], dict) and 'mpjpe' in res[s]}, flush=True)
        out.append(res)
    json.dump(out, open(a.out, 'w'))


def run_ex3d(a):
    from finetune_motionagformer_fit3d import mag_input
    mags = {'mag_orig': load_mag(a.orig, a.mag_repo), 'mag_ft': load_mag(a.ft, a.mag_repo)}
    O = Path(a.outputs); gt = json.load(open(O / 'rep_validation/gt.json')); out = []
    exname = {'squat': 'squat', 'pushup': 'pushup', 'barbellrow': 'barbell_row'}
    for seq, g in gt.items():
        z = np.load(O / 'exercise3d_labels' / seq / 'geometry/canonical_3d.npz'); names = list(z['joint_names'])
        Pw = z['keypoints_3d'].astype(float)
        J = np.stack([Pw[:, names.index(nm)] if nm else np.full((len(Pw), 3), np.nan) for nm in EX3D_NAMES], 1)
        cg = json.load(open(O / 'exercise3d_labels' / seq / 'geometry/metadata.json'))['camera_geometry']
        cg = ast.literal_eval(cg) if isinstance(cg, str) else cg
        Rs = {c: np.array(v['extrinsic_world_to_camera'])[:, :3] for c, v in cg.items()}
        up_w = -np.mean([R[1] for R in Rs.values()], axis=0); up_w /= np.linalg.norm(up_w)
        rf = g['rep_frames']; half = int(np.median(np.diff(rf)) / 2) if len(rf) > 1 else 15
        for cam, v in g['views'].items():
            if v['angle_deg'] > a.max_view: continue
            K = read_csv(f'{a.replay}/{seq}/{cam}_mcoco17.csv')
            w, h = json.load(open(O / 'rep_validation/replay' / seq / f'{cam}_{exname[g["exercise"]]}_coco17.json'))['image_size']
            n = min(len(K), len(J)); K = K[:n]; R = Rs[cam]; up_c = R @ up_w
            G = J[:n] @ R.T
            G[:, 7], G[:, 10] = (G[:, 0] + G[:, 8]) / 2, G[:, 9]  # Ex3D has no spine / head top (unused by angles)
            seg = [(max(0, r - half), min(n - 1, r + half)) for r in rf if r < n]
            side = near_side(K); ref = angles(G - G[:, :1], side, up_c); ref['torso'] = ref['torso_g']
            res = dict(source='ex3d', subject=seq, exercise=g['exercise'], cam=cam, view_deg=v['angle_deg'], side=side,
                       group='heldout' if seq in {'squat_0002', 'barbellrow_0001', 'barbellrow_0003'} else 'tuning', frames=n)
            res['2d'] = angle_metrics(angles_from_2d(K, side), ref, seg)
            x, _ = mag_input(K, w, h)
            for name, (model, dev) in mags.items():
                res[name] = angle_metrics(angles(mag_predict(model, dev, x), side, up_c), ref, seg)
            for m in MODELS:
                P = load_mp(f'{a.mp}/{m}/{seq}/{cam}.npz', n); P[:, :, 2] *= a.mp_zsign
                res[f'mp_{m}'] = {**angle_metrics(angles(P, side, up_c), ref, seg), 'found': float((~np.isnan(P).any((1, 2))).mean())}
            print(seq, cam, round(v['angle_deg']), flush=True)
            out.append(res)
    json.dump(out, open(a.out, 'w'))


def run_offsets(a):
    """Definition offsets of MediaPipe's hips/shoulders vs Fit3D mocap: after a similarity fit on the limb joints only
    (knees, ankles, elbows, wrists), the residual of each hip / shoulder / pelvis / thorax in the mocap body frame
    (x = lateral to the body's right, y = up the trunk, z = forward), plus hip / shoulder width ratios."""
    from finetune_motionagformer_fit3d import prep
    limbs = [2, 3, 5, 6, 12, 13, 15, 16]
    rows = {}
    for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(a.root, a.replay, a.subjects, a.exercises):
        d = prep(a.root, subj, ex, cam, J, R, T, csv); n = len(d['pick'])
        G = d['y'] * d['mm'][:, None, None] / 1000
        for m in MODELS:
            P = load_mp(f'{a.mp}/{m}/{subj}/{cam}/{ex}.npz', n); P[:, :, 2] *= a.mp_zsign
            ok = ~np.isnan(P).any((1, 2)); P, g = P[ok], G[ok]
            mp_, mg = P[:, limbs].mean(1, keepdims=True), g[:, limbs].mean(1, keepdims=True)
            X, Y = P[:, limbs] - mp_, g[:, limbs] - mg
            U, S, Vt = np.linalg.svd(np.swapaxes(X, 1, 2) @ Y); dd = np.sign(np.linalg.det(U @ Vt))
            U[:, :, -1] *= dd[:, None]; S[:, -1] *= dd
            Q = (S.sum(1) / (X ** 2).sum((1, 2)))[:, None, None] * (P - mp_) @ (U @ Vt) + mg
            lat = g[:, 1] - g[:, 4]; lat /= np.linalg.norm(lat, axis=-1, keepdims=True)
            upv = g[:, 8] - g[:, 0]; upv -= (upv * lat).sum(-1, keepdims=True) * lat; upv /= np.linalg.norm(upv, axis=-1, keepdims=True)
            fwd = np.cross(lat, upv)  # sign only matters for the forward column; checked below via the nose
            fwd *= np.sign(np.nanmedian(((g[:, 9] - g[:, 8]) * fwd).sum(-1)))
            B = np.stack([lat, upv, fwd], -1)  # [N,3,3] columns
            r = rows.setdefault(m, {}).setdefault('tuning' if subj in TUNING else 'heldout', {})
            for name, j in (('pelvis', 0), ('r_hip', 1), ('l_hip', 4), ('thorax', 8), ('l_shoulder', 11), ('r_shoulder', 14), ('head', 10)):
                r.setdefault(name, []).append(np.einsum('nk,nkc->nc', Q[:, j] - g[:, j], B) * 1000)
            r.setdefault('hip_width_ratio', []).append(np.linalg.norm(Q[:, 1] - Q[:, 4], axis=-1) / np.linalg.norm(g[:, 1] - g[:, 4], axis=-1))
            r.setdefault('shoulder_width_ratio', []).append(np.linalg.norm(Q[:, 11] - Q[:, 14], axis=-1) / np.linalg.norm(g[:, 11] - g[:, 14], axis=-1))
            r.setdefault('trunk_len_ratio', []).append(np.linalg.norm(Q[:, 8] - Q[:, 0], axis=-1) / np.linalg.norm(g[:, 8] - g[:, 0], axis=-1))
        print(subj, ex, cam, flush=True)
    summ = {m: {grp: {k: np.round(np.median(np.concatenate(v), 0), 3).tolist() for k, v in r.items()} for grp, r in g.items()}
            for m, g in rows.items()}
    json.dump(summ, open(a.out, 'w'), indent=1); print(json.dumps(summ, indent=1))


# ---------------------------------------------------------------- tables
SOURCES = ['2d', 'mp_lite', 'mp_full', 'mp_heavy', 'mag_orig', 'mag_ft']
LIMBS = {'squat': ['knee', 'hip', 'torso', 'torso_g'], 'pushup': ['elbow', 'hip', 'torso', 'torso_g'],
         'barbell_row': ['elbow', 'hip', 'torso', 'torso_g'], 'barbellrow': ['elbow', 'hip', 'torso', 'torso_g']}
BUCKETS = [(0, 40), (40, 75), (75, 91)]


def med(x): return f'{np.median(x):.1f}' if len(x) else '-'


def table(rows):
    srcs = [s for s in SOURCES if any(s in r for r in rows)]
    lines = []
    if any('mpjpe' in r.get('mp_full', {}) for r in rows):
        lines += ['| 묶음 | 소스 | MPJPE (mm) | PA-MPJPE (mm) | 가속도 오차 (mm/프레임²) | 사람 찾음 |', '|---|---|---|---|---|---|']
        for grp in ('heldout', 'tuning'):
            for s in srcs[1:]:
                rs = [r[s] for r in rows if r['group'] == grp and s in r]
                if not rs: continue
                cat = lambda k: np.concatenate([x[k] for x in rs])
                lines.append(f"| {grp} | {s} | {cat('mpjpe').mean():.0f} | {cat('pa_mpjpe').mean():.0f} | {cat('accel').mean():.1f} | "
                             f"{np.mean([x['found'] for x in rs]):.1%} |")
        lines.append('')
        lines += ['| 묶음 | 운동 | MPJPE (mm) ' + ' | '.join(srcs[1:]) + ' |', '|---|---|' + '---|' * (len(srcs) - 1)]
        for grp in ('heldout', 'tuning'):
            for ex in dict.fromkeys(r['exercise'] for r in rows):
                rs = [r for r in rows if r['group'] == grp and r['exercise'] == ex]
                if rs: lines.append(f'| {grp} | {ex} | ' + ' | '.join(f"{np.concatenate([r[s]['mpjpe'] for r in rs]).mean():.0f} / "
                                                                    f"{np.concatenate([r[s]['pa_mpjpe'] for r in rs]).mean():.0f}" for s in srcs[1:]) + ' |')
        lines.append('')
    for kind, key in (('렙 극값 오차 중앙값 (°)', 'rep'), ('프레임 오차 중앙값 (°)', 'frame'), ('각도 떨림 |Δ²θ−Δ²θ정답| 중앙값 (°/프레임²)', 'jitter')):
        lines += [f'**{kind}**', '', '| 묶음 | 운동 | 각도 | 시점 | 영상 | ' + ' | '.join(srcs) + ' |', '|---|---|---|---|---|' + '---|' * len(srcs)]
        for grp in ('heldout', 'tuning'):
            for ex in dict.fromkeys(r['exercise'] for r in rows):
                for limb in LIMBS[ex]:
                    for lo, hi in BUCKETS:
                        rs = [r for r in rows if r['group'] == grp and r['exercise'] == ex and lo <= r['view_deg'] < hi]
                        if not rs: continue
                        vals = [med(np.concatenate([r[s][limb][key] for r in rs])) for s in srcs]
                        lines.append(f"| {grp} | {ex} | {limb} | {lo}–{90 if hi == 91 else hi}° | {len(rs)} | " + ' | '.join(vals) + ' |')
        lines.append('')
    return '\n'.join(lines)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['mp-fit3d', 'mp-ex3d', 'fit3d', 'ex3d', 'offsets', 'table'])
    p.add_argument('files', nargs='*')
    p.add_argument('--root'); p.add_argument('--replay'); p.add_argument('--mp'); p.add_argument('--models')
    p.add_argument('--videos'); p.add_argument('--gt'); p.add_argument('--outputs')
    p.add_argument('--subjects', type=lambda s: s.split(','), default=None)
    p.add_argument('--exercises', type=lambda s: s.split(','), default=list(EXERCISES))
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    p.add_argument('--orig', default=None); p.add_argument('--ft', default=None)
    p.add_argument('--mp-zsign', type=float, default=1.0)
    p.add_argument('--max-view', type=float, default=75); p.add_argument('--jobs', type=int, default=6)
    p.add_argument('--out')
    a = p.parse_args()
    a.orig = a.orig or f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr'
    if a.cmd == 'table':
        print(table([r for f in a.files for r in json.load(open(f))])); return
    {'mp-fit3d': mp_fit3d, 'mp-ex3d': mp_ex3d, 'fit3d': run_fit3d, 'ex3d': run_ex3d, 'offsets': run_offsets}[a.cmd](a)


if __name__ == '__main__':
    main()
