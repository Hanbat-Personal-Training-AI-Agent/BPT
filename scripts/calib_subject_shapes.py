"""Per-subject SMPL shape (β) and H36M bone lengths computed the way the product's calibration does it
(server/calibration_modal/fitting.py), on a local CPU. Evaluation only: nothing is uploaded anywhere.

  photos    a few standing frames per subject from several synchronized camera views, picked with the app's own
            RTMPose-m 2D (pose-replay CSV): shoulders, hips, knees, ankles confidence >= 0.5 (arms may hold a bar), both
            knees and hips >= 160 deg, trunk <= 15 deg from the image vertical, in at least two cameras at once for >= 10
            frames; the middle frame of the first and of the last such run (>= 2 s apart) of each sequence, every camera
            that sees the person standing at that instant. A sequence with no standing instant (bent-over rows that start
            in the bent position) falls back to frames with those joints confident (tag suffix "~any_pose"). At most
            --max-photos per subject, evenly spaced.
  per photo person box from the keypoints (fitting.person_box), the camera's own intrinsics (Fit3D frames are
            undistorted with its distortion model first), SAM 3D Body inference_type="body" -> MHR mesh.
  identity  MHR -> SMPL with MHR's converter, single_identity=True: one β for all photos of the subject (fitting.py 3).
  height    unknown for these subjects, so β stays the converter's (fitting.py step 5 needs the user's height). Only the
            segment proportions reach Pose3DConstraints (BoneLengthConstraint scales the targets per frame), so the
            missing height changes nothing there except through the proportions; segments_h<H> (β projected to
            H cm) measure how much that step would move them.
  out       <out>/subjects.json {subject: {beta, segments_cm (body.bone_lengths_cm, H36M), segments_h160/170/180,
            photos, timings}} + manifest.json, and what the app / pose-replay read: <out>/targets/<subject>.json
            ({"boneLengthData": {"segments": cm, "appDefinitionDiffers": [...]}}, = a calibration result, for
            BPT_BONE_TARGETS) and <out>/targets/byclip.json ({"byClip": {<sequence or subject prefix>: that}}, for
            pose-replay --bone-targets). Per-subject lengths are body measurements of real people (Fit3D, Exercise3D):
            they stay on this machine (device runs copy them over USB), never in git or reports (aggregates only).

The reprojection refinement (fitting.py step 4) is skipped: with refine_beta=False it moves pose / translation only,
so it cannot change β or the lengths.

usage (Home, conda bpt-sam3db):
  calib_subject_shapes.py fit3d --root ~/datasets/fit3d --replay ~/bpt-smpl/replay --subjects s03,...,s11 --out RUN
  calib_subject_shapes.py ex3d --videos ~/workspace/exercise3d-dataset/BPT/synced_video --csv ~/bpt-smpl/ex3dcsv \
      --labels ~/bpt-smpl/ex3d/exercise3d_labels --out RUN
"""
import argparse, ast, contextlib, glob, hashlib, json, os, pickle, socket, sys, time
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(REPO / 'server/calibration_modal'), str(REPO / 'scripts')]
import body  # noqa: E402  (the server's own β -> H36M -> length code)

# The user's person split (docs/decisions.md D-B-01; Exercise3D has no subject ids, SUBJECT_MAPPING_UNAVAILABLE).
EX3D_SUBJECTS = {'P1': ['squat_0000', 'squat_0001', 'squat_0003', 'barbellrow_0000', 'barbellrow_0002',
                        'pushup_0000', 'pushup_0001', 'pushup_0002', 'pushup_0003', 'pushup_0004'],
                 'P2': ['squat_0002', 'barbellrow_0003'], 'P3': ['barbellrow_0001']}
# Photos come from the standing exercises; push-ups (all P1) never stand and only take the subject's lengths.
EX3D_FILE = {'squat': 'squat', 'barbellrow': 'barbell_row'}
FIT3D_EXERCISES = ('squat', 'barbell_row')
REQUIRED = [5, 6, 11, 12, 13, 14, 15, 16]


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()


def read_csv(path):
    rows = [l.strip().split(',') for l in open(path)][1:]
    return np.array([[float(x) for x in r[4:4 + 51]] for r in rows]).reshape(len(rows), 17, 3)


def interior(a, b, c):
    u, v = a - b, c - b
    return np.degrees(np.arccos(np.clip((u * v).sum(-1) / (np.linalg.norm(u, axis=-1) * np.linalg.norm(v, axis=-1) + 1e-9), -1, 1)))


def standing(K):
    """[N] bool: the person stands straight in this camera (app 2D, image y down)."""
    ok = (K[:, REQUIRED, 2] >= 0.5).all(1)
    knees = np.minimum(interior(K[:, 11, :2], K[:, 13, :2], K[:, 15, :2]), interior(K[:, 12, :2], K[:, 14, :2], K[:, 16, :2]))
    hips = np.minimum(interior(K[:, 5, :2], K[:, 11, :2], K[:, 13, :2]), interior(K[:, 6, :2], K[:, 12, :2], K[:, 14, :2]))
    trunk = (K[:, 5, :2] + K[:, 6, :2]) / 2 - (K[:, 11, :2] + K[:, 12, :2]) / 2
    tilt = np.degrees(np.arctan2(np.abs(trunk[:, 0]), -trunk[:, 1]))
    return ok & (knees >= 160) & (hips >= 160) & (tilt <= 15)


def confident(K):
    return (K[:, REQUIRED, 2] >= 0.5).all(1)


def pick_instants(Ks, fps):
    """[(t, cams, fallback)] from the per-camera standing masks (>= 2 cameras at once), else confident frames."""
    for test, fallback in ((standing, False), (confident, True)):
        n = min(len(k) for k in Ks.values())
        masks = {cam: test(k[:n]) for cam, k in Ks.items()}
        ts = instants(np.sum(list(masks.values()), 0) >= 2, fps)
        if ts: return [(t, [c for c in Ks if masks[c][t]], fallback) for t in ts]
    return []


def instants(mask, fps, min_run=10, min_gap_s=2.0):
    """Middle frame of the first and the last run of >= min_run True frames (the last only if >= min_gap_s later)."""
    runs, start = [], None
    for i, v in enumerate(list(mask) + [False]):
        if v and start is None: start = i
        if not v and start is not None:
            if i - start >= min_run: runs.append((start + i - 1) // 2)
            start = None
    if not runs: return []
    return [runs[0]] + ([runs[-1]] if runs[-1] - runs[0] >= min_gap_s * fps else [])


# ---------------------------------------------------------------- photo sources
def fit3d_photos(a, subj):
    """[(image RGB, keypoints [17,3] in that image, intrinsics (fx, fy, cx, cy), tag)] for one Fit3D subject."""
    import cv2
    photos = []
    for ex in FIT3D_EXERCISES:
        cams = sorted(os.path.basename(p) for p in glob.glob(f'{a.root}/train/{subj}/videos/*'))
        Ks = {}
        for cam in cams:
            csv = glob.glob(f'{a.replay}/{subj}/{cam}/{ex}_*coco17.csv')
            if csv: Ks[cam] = read_csv(csv[0])
        if len(Ks) < 2: continue
        for t, cams, fallback in pick_instants(Ks, fps=50):
            for cam in cams:
                K = Ks[cam]
                c = json.load(open(f'{a.root}/train/{subj}/camera_parameters/{cam}/{ex}.json'))
                w, wo = c['intrinsics_w_distortion'], c['intrinsics_wo_distortion']
                Kd = np.array([[w['f'][0][0], 0, w['c'][0][0]], [0, w['f'][0][1], w['c'][0][1]], [0, 0, 1]])
                Ku = np.array([[wo['f'][0], 0, wo['c'][0]], [0, wo['f'][1], wo['c'][1]], [0, 0, 1]])
                dist = np.array([w['k'][0][0], w['k'][0][1], w['p'][0][0], w['p'][0][1], w['k'][0][2]])
                cap = cv2.VideoCapture(f'{a.root}/train/{subj}/videos/{cam}/{ex}.mp4')
                cap.set(cv2.CAP_PROP_POS_FRAMES, int(t)); ok, frame = cap.read(); cap.release()
                if not ok: continue
                img = cv2.cvtColor(cv2.undistort(frame, Kd, dist, newCameraMatrix=Ku), cv2.COLOR_BGR2RGB)
                kp = K[t].copy()
                kp[:, :2] = cv2.undistortPoints(kp[:, None, :2].astype(np.float64), Kd, dist, P=Ku)[:, 0]
                photos.append((img, kp, (Ku[0, 0], Ku[1, 1], Ku[0, 2], Ku[1, 2]), f'{ex}/{cam}/{t}' + ('~any_pose' if fallback else '')))
    return photos


def ex3d_photos(a, seqs):
    import cv2
    photos = []
    for seq in seqs:
        ex = seq.split('_')[0]
        meta = json.load(open(f'{a.labels}/{seq}/geometry/metadata.json'))
        cg = meta['camera_geometry']; cg = ast.literal_eval(cg) if isinstance(cg, str) else cg
        Ks = {cam: read_csv(f'{a.csv}/{seq}/{cam}_{EX3D_FILE[ex]}_mcoco17.csv') for cam in ('cam1', 'cam2', 'cam3')}
        for t, cams, fallback in pick_instants(Ks, fps=30):
            for cam in cams:
                K = Ks[cam]
                cap = cv2.VideoCapture(f'{a.videos}/{ex}/{seq}/{cam}.mp4')
                cap.set(cv2.CAP_PROP_POS_FRAMES, int(t)); ok, frame = cap.read(); cap.release()
                if not ok: continue
                H, W = frame.shape[:2]
                M = np.array(cg[cam]['intrinsic_working_frame']); wh, ww = cg[cam]['working_frame_hw']
                s = W / ww  # working frame -> this video (same aspect)
                photos.append((cv2.cvtColor(frame, cv2.COLOR_BGR2RGB), K[t], (M[0, 0] * s, M[1, 1] * s, M[0, 2] * s, M[1, 2] * s),
                               f'{seq}/{cam}/{t}' + ('~any_pose' if fallback else '')))
    return photos


# ---------------------------------------------------------------- the server's steps, on CPU
class Calibrator:
    def __init__(self, a):
        os.environ['MOMENTUM_ENABLED'] = '0'  # as fitting.py: TorchScript MHR from the checkpoint
        import torch
        if not torch.cuda.is_available():
            # ponytail: sam-3d-body's get_ray_condition calls .cuda() unconditionally; CPU-only runs need a no-op.
            torch.Tensor.cuda = lambda self, *args, **kwargs: self
        torch.set_num_threads(a.threads)
        sys.path.insert(0, a.sam3db_src)
        from sam_3d_body import SAM3DBodyEstimator, load_sam_3d_body
        import smplx
        self.torch, self.a = torch, a
        model, cfg = load_sam_3d_body(f'{a.weights}/model.ckpt', device='cpu', mhr_path=f'{a.weights}/assets/mhr_model.pt')
        self.estimator = SAM3DBodyEstimator(sam_3d_body_model=model, model_cfg=cfg, human_detector=None,
                                            human_segmentor=None, fov_estimator=None)
        arrays = dict(np.load(a.smpl))
        self.v_template, self.shapedirs, self.reg = arrays['v_template'], arrays['shapedirs'], arrays['J_regressor_h36m']
        self.pkl = Path(a.out) / 'tmp_smpl_neutral.pkl'  # licensed model, deleted at the end
        with open(self.pkl, 'wb') as fh:
            pickle.dump({k: v for k, v in arrays.items() if k != 'J_regressor_h36m'}, fh)
        self.smpl = smplx.SMPL(model_path=str(self.pkl), num_betas=10)
        sys.path.insert(0, a.conversion)
        from conversion import Conversion
        from fitting import MhrTopology  # the server's stand-in for mhr.MHR (faces only)
        self.converter = Conversion(mhr_model=MhrTopology(self.estimator.faces), smpl_model=self.smpl, method='pytorch')

    def __call__(self, photos):
        from fitting import person_box
        t0, meshes, info = time.perf_counter(), [], []
        for img, kp, (fx, fy, cx, cy), tag in photos:
            h, w = img.shape[:2]
            cam = self.torch.tensor([[[fx, 0, cx], [0, fy, cy], [0, 0, 1]]], dtype=self.torch.float32)
            out = self.estimator.process_one_image(img, bboxes=person_box(kp.astype(np.float32), w, h)[None], cam_int=cam,
                                                   inference_type='body')
            if len(out) != 1:
                info.append(dict(photo=tag, found=False)); continue
            meshes.append(100.0 * (out[0]['pred_vertices'] + out[0]['pred_cam_t'][None]))  # cm, as the converter expects
            info.append(dict(photo=tag, found=True, mhr_height_m=round(float(np.ptp(out[0]['pred_vertices'][:, 1])), 3)))
        t1 = time.perf_counter()
        with contextlib.chdir(self.a.conversion):
            conv = self.converter.convert_mhr2smpl(mhr_vertices=np.stack(meshes), single_identity=True, is_tracking=False,
                                                   return_smpl_parameters=True)
        beta = np.asarray(conv.result_parameters['betas'].detach().cpu() if self.torch.is_tensor(conv.result_parameters['betas'])
                          else conv.result_parameters['betas'], float)[0]
        res = dict(beta=beta.tolist(), photos=info, segments_cm=self.lengths(beta),
                   mhr_to_smpl_error_cm=None if conv.result_errors is None else round(100 * float(np.mean(conv.result_errors)), 3),
                   timing_s=dict(sam3d_body=round(t1 - t0, 1), mhr_to_smpl=round(time.perf_counter() - t1, 1)))
        for H in (160, 170, 180):
            res[f'segments_h{H}'] = self.lengths(body.project_to_height(self.v_template, self.shapedirs, beta, H / 100))
        return res

    def lengths(self, beta):
        return body.bone_lengths_cm(body.h36m_joints(body.shaped_vertices(self.v_template, self.shapedirs, beta), self.reg))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('source', choices=['fit3d', 'ex3d'])
    p.add_argument('--root'); p.add_argument('--replay'); p.add_argument('--subjects', type=lambda s: s.split(','))
    p.add_argument('--videos'); p.add_argument('--csv'); p.add_argument('--labels')
    p.add_argument('--out', required=True); p.add_argument('--threads', type=int, default=10)
    p.add_argument('--max-photos', type=int, default=12)
    p.add_argument('--weights', default=os.path.expanduser('~/models/sam-3d-body-dinov3'))
    p.add_argument('--sam3db-src', default=os.path.expanduser('~/models/src/sam-3d-body'))
    p.add_argument('--conversion', default=os.path.expanduser('~/models/src/MHR/tools/mhr_smpl_conversion'))
    p.add_argument('--smpl', default=os.path.expanduser('~/bpt-smpl/smpl/smpl_neutral_h36m.npz'))
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    jobs = ({s: (lambda s=s: fit3d_photos(a, s)) for s in a.subjects} if a.source == 'fit3d'
            else {s: (lambda q=q: ex3d_photos(a, [x for x in q if not x.startswith('pushup')]))
                  for s, q in EX3D_SUBJECTS.items() if not a.subjects or s in a.subjects})
    cal, out = Calibrator(a), {}
    targets_dir = Path(a.out) / 'targets'; targets_dir.mkdir(exist_ok=True)
    try:
        for subj, photos in jobs.items():
            ph = photos()
            if len(ph) > a.max_photos:  # evenly spaced over the sequences / instants / cameras
                ph = [ph[int(i)] for i in np.linspace(0, len(ph) - 1, a.max_photos).round()]
            print(subj, len(ph), 'photos', [p[3] for p in ph], flush=True)
            if ph: out[subj] = cal(ph)
            json.dump(out, open(Path(a.out) / 'subjects.json', 'w'), indent=1)
            if subj in out:
                seg = out[subj]['segments_cm']
                doc = {'boneLengthData': {'segments': seg, 'appDefinitionDiffers': [k for k in seg if body.app_definition_differs(k)]},
                       'subject': subj, 'source': 'calib_subject_shapes.py (SAM 3D Body -> MHR->SMPL single identity, no height)'}
                json.dump(doc, open(targets_dir / f'{subj}.json', 'w'), indent=1)
                keys = EX3D_SUBJECTS[subj] if a.source == 'ex3d' else [subj]
                by = json.load(open(targets_dir / 'byclip.json'))['byClip'] if (targets_dir / 'byclip.json').exists() else {}
                by.update({k: doc for k in keys})
                json.dump({'byClip': by}, open(targets_dir / 'byclip.json', 'w'), indent=1)
    finally:
        cal.pkl.unlink(missing_ok=True)
    weights = [f'{a.weights}/model.ckpt', f'{a.weights}/assets/mhr_model.pt', f'{a.weights}/model_config.yaml', a.smpl]
    weights += sorted(glob.glob(f'{a.conversion}/assets/*'))
    code = [str(REPO / 'scripts/calib_subject_shapes.py'), str(REPO / 'server/calibration_modal/body.py'),
            str(REPO / 'server/calibration_modal/fitting.py')]
    git = lambda d: os.popen(f'git -C {d} rev-parse HEAD 2>/dev/null').read().strip()
    json.dump(dict(argv=sys.argv, python=sys.executable, host=socket.gethostname(), finished=time.strftime('%Y-%m-%d %H:%M:%S'),
                   code_commit=(REPO / 'CODE_SHA').read_text().strip() if (REPO / 'CODE_SHA').exists() else git(REPO),
                   sam3d_body_commit=git(a.sam3db_src), mhr_commit=git(Path(a.conversion).parents[1]),
                   photos={s: [i['photo'] for i in r['photos']] for s, r in out.items()},
                   inputs={w: sha256(w) for w in weights if os.path.isfile(w)}, code={c: sha256(c) for c in code},
                   outputs={str(Path(a.out) / 'subjects.json'): sha256(Path(a.out) / 'subjects.json')},
                   note='per-subject lengths are personal body measurements: keep on Home, report aggregates only'),
              open(Path(a.out) / 'manifest.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
