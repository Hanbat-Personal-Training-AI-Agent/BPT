"""2D vs MotionAGFormer-3D joint angles against 3D reference, by camera view angle.

Question: on diagonal views, are knee / torso / elbow angles from the 3D lifter closer to the truth than the
2D image angles the app uses today?  Per frame (inside the rep window) and per rep (extreme: knee/elbow min,
torso max), for the near-side limb:
  2D  : interior angle in the image from pose-replay's CSV keypoints (exactly the app's 2D path);
        torso = near-side hip->shoulder vs image vertical.
  3D  : MotionAGFormer (PyTorch, same person_crop normalisation and 27-frame / lookahead-5 window as the app)
        on those keypoints; torso = mid-hip->mid-shoulder vs camera up (-y), as the app would see it.
  ref : Fit3D mocap joints3d_25 (ground truth) or Exercise3D canonical_3d (Sapiens triangulation, NOT ground
        truth); torso vs world up.
"Bad 3D" frames = knee hinge theta < -10 deg on either leg (pose_feedback/geometry/hinge_limit.py) and are
reported separately and excluded from the 3D error, like the app.

usage:
  eval_3d_angles.py fit3d --root DIR --replay DIR [--subjects s03,s05] [--checkpoint PTH] --out JSON
  eval_3d_angles.py ex3d  --out JSON [--checkpoint PTH]
"""
import argparse, glob, gzip, json, os, sys
from pathlib import Path
import numpy as np

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))
from pose_feedback.body.live_motionagformer import motionagformer_frames_from_coco17  # noqa: E402
from pose_feedback.geometry.hinge_limit import knee_theta_deg  # noqa: E402

WINDOW, LOOKAHEAD, APP_FPS = 27, 5, 30
# Fit3D joints3d_25 -> H36M17: Fit3D 1-3 is the LEFT leg (same side as shoulder 11), H36M 1-3 is the right.
FIT3D_TO_H36M = [0, 4, 5, 6, 1, 2, 3, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
# limb -> (H36M a, b, c) per side, (COCO a, b, c) per side
H36M = {'knee': {'L': (4, 5, 6), 'R': (1, 2, 3)}, 'elbow': {'L': (11, 12, 13), 'R': (14, 15, 16)}}
COCO = {'knee': {'L': (11, 13, 15), 'R': (12, 14, 16)}, 'elbow': {'L': (5, 7, 9), 'R': (6, 8, 10)}}
COCO_SH, COCO_HIP = {'L': 5, 'R': 6}, {'L': 11, 'R': 12}
SIDE_JOINTS = {'L': [3, 5, 7, 9, 11, 13, 15], 'R': [4, 6, 8, 10, 12, 14, 16]}  # ear..ankle, FormWarnings.sideScore
EX3D_NAMES = ['pelvis_center', 'right_hip', 'right_knee', 'right_ankle', 'left_hip', 'left_knee', 'left_ankle',
              None, 'shoulder_center', 'nose', None, 'left_shoulder', 'left_elbow', 'left_wrist',
              'right_shoulder', 'right_elbow', 'right_wrist']
EXTREME = {'knee': np.nanmin, 'elbow': np.nanmin, 'torso': np.nanmax}


def interior(a, b, c):
    u, v = a - b, c - b
    cos = np.sum(u * v, -1) / (np.linalg.norm(u, axis=-1) * np.linalg.norm(v, axis=-1) + 1e-9)
    return np.degrees(np.arccos(np.clip(cos, -1, 1)))


def incline(vec, up):
    """Unsigned angle of vec from `up`, deg."""
    return np.degrees(np.arccos(np.clip(vec @ up / (np.linalg.norm(vec, axis=-1) + 1e-9), -1, 1)))


def near_side(K):
    """The app's near side: the side whose ear..ankle keypoints have the higher mean 2D confidence."""
    return max('LR', key=lambda s: K[:, SIDE_JOINTS[s], 2].mean())


def angles_3d(J, up, side):
    out = {k: interior(*(J[:, i] for i in H36M[k][side])) for k in H36M}
    out['torso'] = incline((J[:, 11] + J[:, 14]) / 2 - (J[:, 1] + J[:, 4]) / 2, up)
    return out


def angles_2d(K, side):
    out = {k: interior(*(K[:, i, :2] for i in COCO[k][side])) for k in COCO}
    t = K[:, COCO_SH[side], :2] - K[:, COCO_HIP[side], :2]
    out['torso'] = np.degrees(np.arctan2(np.abs(t[:, 0]), -t[:, 1]))
    return out


def load_lifter(checkpoint, mag_repo):
    from pose_feedback.body.motionagformer_runner import MotionAGFormerRunner
    return MotionAGFormerRunner(repo_dir=mag_repo, config_path=f'{mag_repo}/configs/h36m/MotionAGFormer-xsmall.yaml',
                                checkpoint_path=checkpoint)  # auto: mps on Mac


def lift(coco, w, h, runner, batch=256):
    """App-equivalent selected3D for every frame: window [i+L-26, i+L] edge-clamped, output row 26-L."""
    frames = motionagformer_frames_from_coco17(list(coco), w, h)
    n = len(frames); t = np.arange(WINDOW)
    idx = np.clip(np.arange(n)[:, None] + LOOKAHEAD - (WINDOW - 1) + t[None], 0, n - 1)
    out = []
    for s in range(0, n, batch):
        out.append(runner.predict_3d(frames[idx[s:s + batch]])[:, WINDOW - 1 - LOOKAHEAD])
    return np.concatenate(out).astype(float)


def bad3d(P):
    return np.array([any((th := knee_theta_deg(p, leg)) is not None and th < -10 for leg in ('left', 'right')) for p in P])


def read_csv(path):
    op = gzip.open if str(path).endswith('.gz') else open
    with op(path, 'rt') as f:
        head = f.readline().strip().split(',')
        rows = np.array([[float(x) for x in l.strip().split(',')[4:4 + 51]] for l in f])
    assert head[4] == 'j0_x'
    return rows.reshape(len(rows), 17, 3)


def evaluate(coco, ref, ref_up, side, w, h, runner, segments, cam_up=np.array([0., -1, 0])):
    """coco [N,17,3] app 2D, ref [N,17,3] H36M-ordered reference. segments: [(s,e)] rep frame ranges."""
    P = lift(coco, w, h, runner)
    bad = bad3d(P)
    a2, a3, ar = angles_2d(coco, side), angles_3d(P, cam_up, side), angles_3d(ref, ref_up, side)
    inside = np.zeros(len(coco), bool)
    for s, e in segments: inside[s:e + 1] = True
    res = {'frames': int(inside.sum()), 'bad3d_frames': int((bad & inside).sum()),
           # knee hinge check: flagged mask and the 3D knee error on every frame (flagged ones included), and how
           # many reference frames are themselves hyperextended past the limit (true hyperextension, ~0 expected)
           'bad_mask': bad[inside].tolist(), 'ref_bad_frames': int((bad3d(ref) & inside).sum())}
    for k in ar:
        e2 = np.abs(a2[k] - ar[k])[inside]; e3 = np.abs(a3[k] - ar[k])[inside & ~bad]
        r2, r3 = [], []
        for s, e in segments:
            g = EXTREME[k](ar[k][s:e + 1])
            r2.append(abs(EXTREME[k](a2[k][s:e + 1]) - g))
            ok = ~bad[s:e + 1]
            if ok.any(): r3.append(abs(EXTREME[k](a3[k][s:e + 1][ok]) - g))
        res[k] = {'frame_err_2d': e2.tolist(), 'frame_err_3d': e3.tolist(), 'rep_err_2d': r2, 'rep_err_3d': r3,
                  'frame_err_3d_all': np.abs(a3[k] - ar[k])[inside].tolist(),
                  'ref_range': float(np.ptp(ar[k][inside]))}
    return res


def fit3d_jobs(root, replay, subjects, exercises):
    for sd in sorted(glob.glob(f'{root}/train/s*')):
        subj = os.path.basename(sd)
        if subjects and subj not in subjects: continue
        ann = json.load(open(f'{sd}/rep_ann.json'))
        for ex in exercises:
            if not os.path.exists(f'{sd}/joints3d_25/{ex}.npy') or ex not in ann: continue
            J = np.load(f'{sd}/joints3d_25/{ex}.npy').astype(float)[:, FIT3D_TO_H36M]
            for cp in sorted(glob.glob(f'{sd}/camera_parameters/*/{ex}.json')):
                cam = cp.split('/')[-2]
                csv = glob.glob(f'{replay}/{subj}/{cam}/{ex}_*_coco17.csv')
                if not csv: continue
                c = json.load(open(cp)); R = np.array(c['extrinsics']['R']); T = np.array(c['extrinsics']['T']).reshape(3)
                yield subj, ex, cam, J, R, T, ann[ex], csv[0]


def view_and_side(J, R, T, up):
    """Horizontal angle between camera->pelvis ray and body left-right line (0 side, 90 front/back), near side."""
    lr = ((J[:, 14] - J[:, 11]) + (J[:, 1] - J[:, 4])) / 2  # L -> R
    lr -= np.outer(lr @ up, up)
    ray = J[:, 0] - T; ray -= np.outer(ray @ up, up)
    cos = np.sum(ray * lr, 1) / (np.linalg.norm(ray, axis=1) * np.linalg.norm(lr, axis=1))
    ang = float(np.median(np.degrees(np.arccos(np.clip(np.abs(cos), 0, 1)))))
    return ang, ('L' if np.median(cos) > 0 else 'R')  # ray along L->R: the left side is seen first


def run_fit3d(a, runner):
    out = []
    for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(a.root, a.replay, a.subjects, a.exercises):
        K = read_csv(csv); n = min(len(K), len(J))
        pick = np.round(np.arange(0, n, 50 / APP_FPS)).astype(int); pick = pick[pick < n]  # 50 fps -> app 30 fps
        up = -R[1] / np.linalg.norm(R[1])  # camera up in world; world z-up for Fit3D
        up = np.array([0, 0, 1.]) if abs(up[2]) > 0.8 else up
        ang, _ = view_and_side(J, R, T, up); side = near_side(K)
        seg = [(int(np.searchsorted(pick, s)), int(np.searchsorted(pick, e))) for s, e in zip(ann, ann[1:])]
        r = evaluate(K[pick], J[pick], up, side, 900, 900, runner, seg)
        r.update(source='fit3d', subject=subj, exercise=ex, cam=cam, view_deg=round(ang, 1), side=side,
                 cam_pitch_deg=round(float(np.degrees(np.arcsin(np.clip(R[2] @ up, -1, 1)))), 1))
        print(subj, ex, cam, f'view={ang:.0f}', f"bad3d={r['bad3d_frames']}/{r['frames']}",
              {k: (round(float(np.median(r[k]['frame_err_2d'])), 1), round(float(np.median(r[k]['frame_err_3d'] or [np.nan])), 1))
               for k in ('knee', 'torso', 'elbow')}, flush=True)
        out.append(r)
    return out


def run_ex3d(a, runner):
    import ast
    O = Path(a.outputs); L = O / 'exercise3d_labels'
    gt = json.load(open(O / 'rep_validation/gt.json'))
    exname = {'squat': 'squat', 'pushup': 'pushup', 'barbellrow': 'barbell_row'}
    out = []
    for seq, g in gt.items():
        z = np.load(L / seq / 'geometry/canonical_3d.npz'); names = list(z['joint_names']); P = z['keypoints_3d'].astype(float)
        J = np.stack([P[:, names.index(n)] if n else np.full((len(P), 3), np.nan) for n in EX3D_NAMES], 1)
        m = json.load(open(L / seq / 'geometry/metadata.json')); cg = m['camera_geometry']
        cg = ast.literal_eval(cg) if isinstance(cg, str) else cg
        Rs = {c: np.array(v['extrinsic_world_to_camera'])[:, :3] for c, v in cg.items()}
        up = -np.mean([R[1] for R in Rs.values()], axis=0); up /= np.linalg.norm(up)
        rf = g['rep_frames']; half = int(np.median(np.diff(rf)) / 2) if len(rf) > 1 else 15
        seg = [(max(0, r - half), min(len(J) - 1, r + half)) for r in rf]
        for cam, v in g['views'].items():
            csv = Path(a.ex3d_replay or O / 'rep_validation/replay') / seq / f'{cam}_{exname[g["exercise"]]}_coco17.csv'
            csv = csv if csv.exists() else Path(f'{csv}.gz')
            if not csv.exists(): continue
            K = read_csv(csv); n = min(len(K), len(J))
            w, h = (int(x) for x in os.popen(f'ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 '
                                            f'{O}/exercise3d_synced/{g["exercise"]}/{seq}/{cam}.mp4').read().strip().split(','))
            side = near_side(K)
            r = evaluate(K[:n], J[:n], up, side, w, h, runner, seg)
            r.update(source='ex3d', subject=seq, exercise=g['exercise'], cam=cam, view_deg=v['angle_deg'], side=side)
            print(seq, cam, f"view={v['angle_deg']:.0f}", f"bad3d={r['bad3d_frames']}/{r['frames']}",
                  {k: (round(float(np.median(r[k]['frame_err_2d'])), 1), round(float(np.median(r[k]['frame_err_3d'] or [np.nan])), 1))
                   for k in ('knee', 'torso', 'elbow')}, flush=True)
            out.append(r)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument('source', choices=['fit3d', 'ex3d'])
    p.add_argument('--root'); p.add_argument('--replay')
    p.add_argument('--subjects', type=lambda s: s.split(','), default=None)
    p.add_argument('--exercises', type=lambda s: s.split(','), default=['squat', 'pushup', 'barbell_row'])
    p.add_argument('--mag-repo', default=str(REPO / 'external/MotionAGFormer'))
    p.add_argument('--checkpoint', default=None)
    p.add_argument('--ex3d-replay', default=None, help='pose-replay output dir per sequence (default outputs/rep_validation/replay)')
    p.add_argument('--outputs', default=str(REPO / 'outputs'), help='Exercise3D labels + rep_validation replays')
    p.add_argument('--out', required=True)
    a = p.parse_args()
    runner = load_lifter(a.checkpoint or f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr', a.mag_repo)
    res = run_fit3d(a, runner) if a.source == 'fit3d' else run_ex3d(a, runner)
    json.dump(res, open(a.out, 'w'))


if __name__ == '__main__':
    main()
