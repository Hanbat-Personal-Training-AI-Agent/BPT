"""finetune3 XS data: per-sequence MotionAGFormer-XS inputs/targets on the app's input path (Home only).

Every input goes through the app path: COCO17 keypoints (px) -> coco17_to_motionagformer_h36m17 -> person_crop
(PersonSquareCropTracker, D-12) -> [T,17,3] (x, y, conf), sampled at the app's 30 fps. Targets are root-relative
camera-frame H36M17 in the same crop units (weak perspective at the root depth), as scripts/finetune_motionagformer_fit3d.py.

Kinds
  R  Fit3D real cameras: app 2D = pose-replay RTMPose-m COCO17 crop CSVs (~/bpt-smpl/replay), target = mocap.
  V  Fit3D virtual cameras (side / oblique / front, 720x1280 portrait, iPhone-like f): 2D = mocap moved to the COCO17
     definition (per-part 3D offsets fitted on the TUNING subjects' real cameras, eval_pushup_virtual_side.fit_offsets
     generalised to 5 exercises) + a real RTMPose residual track (pool below, same exercise group, nearest view angle,
     random start, mirrored to the same facing), target = mocap in the virtual camera.
  E  Exercise3D P1 (user-approved 2026-10-20; labels = Sapiens2 triangulation, NOT ground truth): app 2D = reacquire
     e3d__cur CSVs, target = canonical_3d in that camera. Only the 8 limb joints (knees, ankles, elbows, wrists) are
     supervised (xs_train.py limb loss): hips / pelvis / shoulders differ in definition from mocap (D-C-09, lift_compare §4).
Residual pool: Fit3D tuning real cameras (app CSV - offset-corrected mocap projection) + Exercise3D P1 (app CSV -
  Sapiens2 2D, pooled per-joint mean removed), in crop units of the reference 2D, whole clips (temporal correlation,
  swaps and dropouts come along), RTMPose confidence kept.
Fit3D licence: user's own machines only, never in git; outputs here are Fit3D-derived (non-commercial).

usage (Home, bpt-home):
  xs_data.py offsets --fit3d ~/datasets/fit3d --replay ~/bpt-smpl/replay --out offsets.json
  xs_data.py pool    --fit3d ... --replay ... --offsets offsets.json --ex3d ~/bpt-smpl/ex3d --ex3d-csv DIR --out pool.npz
  xs_data.py build   --kinds R,V,E --subjects s03,s04,s05 ... --out seqs.npz
  xs_data.py vgrid   --subjects s07,...,s11 ... --out vgrid.npz      (fixed virtual cameras for evaluation)
"""
import argparse, ast, glob, gzip, json, os, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent), str(HERE)]
from eval_3d_angles import APP_FPS, EX3D_NAMES, FIT3D_TO_H36M, read_csv, view_and_side  # noqa: E402
from eval_pushup_virtual_side import (CAMS, FIT3D_COCO, PART, SAPIENS_COCO17, SWAP, body_basis, interp_nan,  # noqa: E402
                                      look_at, project_fit3d, unit)
from finetune_motionagformer_fit3d import mag_input  # noqa: E402
from pose_feedback.body.motionagformer_adapter import (PersonSquareCropTracker, coco17_to_motionagformer_h36m17,  # noqa: E402
                                                       square_crop_normalize)

APP_EX = ('squat', 'pushup', 'diamond_pushup', 'barbell_row', 'barbell_dead_row')
GROUP = {'squat': 'squat', 'pushup': 'pushup', 'diamond_pushup': 'pushup', 'barbell_row': 'row',
         'barbell_dead_row': 'row', 'deadlift': 'row', 'barbellrow': 'row'}
TUNING = ('s03', 's04', 's05')
P1 = ('squat_0000', 'squat_0001', 'squat_0003', 'barbellrow_0000', 'barbellrow_0002',
      'pushup_0000', 'pushup_0001', 'pushup_0002', 'pushup_0003', 'pushup_0004')  # D-B-01 person split (P1 = tuning)
HELD_E3D = ('squat_0002', 'barbellrow_0003', 'barbellrow_0001')  # P2, P2, P3: never trained on
EX3D_EXNAME = {'squat': 'squat', 'pushup': 'pushup', 'barbellrow': 'barbell_row'}
W, H, F = 720, 1280, 913.0  # iPhone 1x portrait (eval_pushup_virtual_side)
UP = np.array([0., 0., 1.])  # Fit3D world is z-up
H36M_SWAP = [0, 4, 5, 6, 1, 2, 3, 7, 8, 9, 10, 14, 15, 16, 11, 12, 13]
LIMBS = [2, 3, 5, 6, 12, 13, 15, 16]  # H36M knees, ankles, elbows, wrists
# Halpe26-only XS (C3, finetune3_plan.md §1.3): Halpe's own head / neck / hip, offsets fitted to these mocap joints (raw index)
HALPE_EXTRA = {17: (10, 'h_head'), 18: (8, 'h_neck'), 19: (0, 'h_hip')}
SAPIENS_NECK, SAPIENS_HIPS, SAPIENS_EYES = 69, (9, 10), (1, 2)


def perm20(n):
    """left/right swap of COCO17 (+ the midline Halpe points 17-19 kept)."""
    return list(SWAP) + list(range(17, n))


def to_h36m(K, mapping='app'):
    """keypoints [N,K>=17,3] px -> H36M17 2D + confidence. app = coco17_to_motionagformer_h36m17 on joints 0-16 (the app's
    Swift coco17ToH36M17); halpe = the same, then pelvis <- Halpe 19 hip, thorax <- 18 neck, head <- 17 head and spine / neck
    rebuilt from them like the app builds them (C3 mapping chosen by halpe_mapping_check.py)."""
    xy, conf = coco17_to_motionagformer_h36m17(K[:, :17])
    if mapping != 'halpe':
        return xy, conf
    xy, conf = xy.copy(), conf.copy()
    for h, j in ((19, 0), (18, 8), (17, 10)):
        xy[:, j], conf[:, j] = K[:, h, :2], K[:, h, 2]
    xy[:, 7] = (xy[:, 0] + xy[:, 8]) / 2; conf[:, 7] = (conf[:, 0] + conf[:, 8]) / 2
    xy[:, 9] = (K[:, 0, :2] + xy[:, 8]) / 2; conf[:, 9] = (K[:, 0, 2] + conf[:, 8]) / 2
    return xy, conf


def mag_in(K, w=900., h=900., mapping='app'):
    """mag_input with a choice of H36M mapping (identical to mag_input for mapping='app')."""
    if mapping != 'halpe':
        return mag_input(K[:, :17], w, h)
    xy, conf = to_h36m(K, mapping)
    tr = PersonSquareCropTracker(); crops = []
    for f, c in zip(xy, conf): crops.append(tr.update(f, c) or (w / 2, h / 2, max(w, h)))
    x = np.stack([square_crop_normalize(f, c) for f, c in zip(xy, crops)])
    return np.concatenate([x, conf[..., None]], -1).astype(np.float32), np.array(crops)


# ---------------------------------------------------------------- Fit3D helpers
def fit3d_seq(root, s, ex):
    """mocap joints3d_25 [T,25,3] (50 fps, metres, world z-up), cameras {cam: json}, rep_ann list or None."""
    f = f'{root}/train/{s}/joints3d_25/{ex}.json'
    if not os.path.exists(f):
        return None
    P = np.array(json.load(open(f))['joints3d_25'], float)
    cams = {c: json.load(open(f'{root}/train/{s}/camera_parameters/{c}/{ex}.json')) for c in CAMS}
    return P, cams, json.load(open(f'{root}/train/{s}/rep_ann.json')).get(ex)


def pick30(n):
    p = np.round(np.arange(0, n, 50 / APP_FPS)).astype(int)
    return p[p < n]


def coco_points(P, offsets):
    """mocap [T,25,3] -> COCO17-definition 3D points [T,17,3] (+ Halpe 17-19 -> [T,20,3] when the offsets have them);
    face points synthesised (eval_pushup_virtual_side.synth)."""
    K = np.zeros((len(P), 20 if 'h_hip' in offsets else 17, 3))
    if 'h_hip' in offsets:
        for j, (fj, part) in HALPE_EXTRA.items():
            K[:, j] = P[:, fj] + body_basis(P, j) @ offsets[part]
    for j, fj in FIT3D_COCO.items():
        K[:, j] = P[:, fj] + body_basis(P, j) @ offsets[PART[j]]
    lr = unit((P[:, 14] - P[:, 11]) + (P[:, 4] - P[:, 1]))
    for eye, ear, sgn in ((1, 3, -1), (2, 4, 1)):
        K[:, eye] = 0.7 * P[:, 9] + 0.3 * P[:, 10] + sgn * 0.03 * lr
        K[:, ear] = 0.5 * (P[:, 9] + P[:, 10]) + sgn * 0.07 * lr
    return K


def app_csv(replay, s, cam, ex):
    g = glob.glob(f'{replay}/{s}/{cam}/{ex}_*coco17.csv')
    return g[0] if g else None


def target(Xc, crops, f):
    """camera-frame joints [T,17,3] (y down) -> root-relative crop units, and metres per crop unit (mm scale)."""
    unit_m = crops[:, 2] / 2 * Xc[:, 0, 2] / f
    return ((Xc - Xc[:, :1]) / unit_m[:, None, None]).astype(np.float32), (unit_m * 1000).astype(np.float32)


def ref_crops(K2, w, h):
    """person crops of reference 2D (all joints confident) — the scale residuals are expressed in."""
    return mag_input(np.concatenate([K2, np.ones(K2.shape[:2] + (1,))], -1), w, h)[1]


# ---------------------------------------------------------------- offsets
def offsets(a):
    if a.halpe:
        return offsets_halpe(a)
    obs = {}
    for s in TUNING:
        for ex in APP_EX:
            d = fit3d_seq(a.fit3d, s, ex)
            if d is None:
                continue
            P, cams, ann = d
            for c in CAMS:
                csv = app_csv(a.replay, s, c, ex)
                if not csv:
                    continue
                kp = read_csv(csv)
                n = min(len(kp), len(P))
                fr = np.arange(0, n, 5)  # every 5th 50 fps frame
                for j, fj in FIT3D_COCO.items():
                    X, B = P[fr, fj], body_basis(P[fr], j)
                    x0 = project_fit3d(X, cams[c])
                    Jc = np.stack([(project_fit3d(X + 0.01 * B[:, :, k], cams[c]) - x0) / 0.01 for k in range(3)], axis=2)
                    good = kp[fr, j, 2] >= 0.5
                    o = obs.setdefault(PART[j], ([], []))
                    o[0].append(Jc[good]); o[1].append(kp[fr, j, :2][good] - x0[good])
    out, report = {}, {}
    for part, (Js, rs) in obs.items():
        J, r = np.concatenate(Js).reshape(-1, 3), np.concatenate(rs).reshape(-1)
        keep = np.ones(len(r), bool)
        for _ in range(3):  # trimmed least squares (swaps, misses)
            d = np.linalg.lstsq(J[keep], r[keep], rcond=None)[0]
            e = np.abs(r - J @ d)
            keep = e < 3 * np.median(e[keep])
        out[part] = d.tolist()
        report[part] = dict(offset_m=np.round(d, 3).tolist(), obs=int(len(r) // 2),
                            med_err_px_before=round(float(np.median(np.hypot(*r.reshape(-1, 2).T))), 1),
                            med_err_px_after=round(float(np.median(np.hypot(*(r - J @ d).reshape(-1, 2).T))), 1))
    json.dump(dict(offsets=out, report=report, subjects=TUNING, exercises=APP_EX), open(a.out, 'w'), indent=1)
    print(json.dumps(report, indent=1))


def fit_parts(obs):
    out, report = {}, {}
    for part, (Js, rs) in obs.items():
        J, r = np.concatenate(Js).reshape(-1, 3), np.concatenate(rs).reshape(-1)
        keep = np.ones(len(r), bool)
        for _ in range(3):  # trimmed least squares (swaps, misses)
            d = np.linalg.lstsq(J[keep], r[keep], rcond=None)[0]
            e = np.abs(r - J @ d)
            keep = e < 3 * np.median(e[keep])
        out[part] = d.tolist()
        report[part] = dict(offset_m=np.round(d, 3).tolist(), obs=int(len(r) // 2),
                            med_err_px_before=round(float(np.median(np.hypot(*r.reshape(-1, 2).T))), 1),
                            med_err_px_after=round(float(np.median(np.hypot(*(r - J @ d).reshape(-1, 2).T))), 1))
    return out, report


def offsets_halpe(a):
    """COCO17 parts + Halpe head / neck / hip offsets from a Halpe26 model's experiment-A 2D (lift-compare stage-1 layout,
    `--pose2d`: pick, halpe [n,26,3]) on the TUNING subjects' real cameras."""
    obs = {}
    for s in TUNING:
        for ex in ('squat', 'pushup', 'barbell_row'):
            d = fit3d_seq(a.fit3d, s, ex)
            if d is None:
                continue
            P, cams, ann = d
            for c in CAMS:
                f = f'{a.pose2d}/{s}_{c}_{ex}.npz'
                if not os.path.exists(f):
                    continue
                z = np.load(f); pk = z['pick']; keep = pk < len(P); pk = pk[keep][::3]; kp = z['halpe'][keep][::3]
                parts = {**{j: (fj, PART[j]) for j, fj in FIT3D_COCO.items()}, **HALPE_EXTRA}
                for j, (fj, part) in parts.items():
                    X, B = P[pk, fj], body_basis(P[pk], j)
                    x0 = project_fit3d(X, cams[c])
                    Jc = np.stack([(project_fit3d(X + 0.01 * B[:, :, k], cams[c]) - x0) / 0.01 for k in range(3)], axis=2)
                    good = kp[:, j, 2] >= 0.5
                    o = obs.setdefault(part, ([], []))
                    o[0].append(Jc[good]); o[1].append(kp[:, j, :2][good] - x0[good])
    out, report = fit_parts(obs)
    json.dump(dict(offsets=out, report=report, subjects=TUNING, source=a.pose2d, model='halpe26'), open(a.out, 'w'), indent=1)
    print(json.dumps(report, indent=1))


def load_offsets(path):
    return {k: np.array(v) for k, v in json.load(open(path))['offsets'].items()}


# ---------------------------------------------------------------- residual pool
def clip_entry(K, ref2, w, h, name, group, angle, source, mapping='app'):
    """K app [T,J,3] px, ref2 [T,J,2] px (NaN = unknown) -> residual in crop units of the reference."""
    ref = np.nan_to_num(interp_nan(ref2.copy()))
    crops = mag_in(np.concatenate([ref, np.ones(ref.shape[:2] + (1,))], -1), w, h, mapping)[1]
    res = (K[:, :, :2] - ref2) / crops[:, 2:3, None]
    res = interp_nan(res)
    xy = to_h36m(np.concatenate([ref, np.ones(ref.shape[:2] + (1,))], -1), mapping)[0]
    norm = (xy - crops[:, None, :2]) / crops[:, None, 2:3] * 2  # mean reference pose for mirroring
    return dict(name=name, group=group, angle=float(angle), source=source, res=res.astype(np.float32),
                conf=K[:, :, 2].astype(np.float32), refpose=norm.mean(0).astype(np.float32))


def pool(a):
    if a.halpe:
        return pool_halpe(a)
    offs, clips = load_offsets(a.offsets), []
    for s in a.pool_subjects.split(','):
        for ex in APP_EX:
            d = fit3d_seq(a.fit3d, s, ex)
            if d is None:
                continue
            P, cams, ann = d
            for c in CAMS:
                csv = app_csv(a.replay, s, c, ex)
                if not csv:
                    continue
                kp = read_csv(csv); n = min(len(kp), len(P)); pk = pick30(n)
                K3 = coco_points(P[pk], offs)
                ref2 = project_fit3d(K3.reshape(-1, 3), cams[c]).reshape(-1, 17, 2)
                R = np.array(cams[c]['extrinsics']['R']); T = np.array(cams[c]['extrinsics']['T']).reshape(3)
                ang, _ = view_and_side(P[pk][:, FIT3D_TO_H36M], R, T, UP)
                clips.append(clip_entry(kp[pk], ref2, 900, 900, f'{s}/{ex}/{c}', GROUP[ex], ang, 'fit3d'))
    gt = json.load(open(f'{a.ex3d}/gt.json'))
    e3d = []
    for seq in P1:
        g = gt[seq]
        for cam, v in g['views'].items():
            stem = f'{a.ex3d_csv}/{seq}_{cam}_{EX3D_EXNAME[g["exercise"]]}_mcoco17'
            csv = stem + '.csv' if os.path.exists(stem + '.csv') else stem + '.csv.gz'
            w, h = json.load(open(stem + '.json'))['image_size']
            kp = read_csv(csv)
            lab = np.load(f'{a.ex3d}/exercise3d_labels/{seq}/view/{cam}_pose_2d.npz')
            n = min(len(kp), len(lab['frame_index']))
            xy = lab['keypoints_xy'][:n][:, SAPIENS_COCO17] * (max(w, h) / 1280.0)  # labels live on the 1280-long-side working frame
            ok = lab['valid_mask'][:n][:, SAPIENS_COCO17] & (lab['confidence'][:n][:, SAPIENS_COCO17] > 0.5) & lab['target_present'][:n, None]
            xy[~ok] = np.nan
            e3d.append(clip_entry(kp[:n], xy, w, h, f'{seq}/{cam}', GROUP[g['exercise']], v['angle_deg'], 'ex3d'))
    mean = np.nanmean(np.concatenate([c['res'] for c in e3d]), axis=0)  # RTMPose vs Sapiens2 definition bias
    for c in e3d:
        c['res'] = (c['res'] - mean).astype(np.float32)
    clips += e3d
    np.savez_compressed(a.out, meta=json.dumps([{k: c[k] for k in ('name', 'group', 'angle', 'source')} for c in clips]),
                        ex3d_mean=mean, **{f'res{i}': c['res'] for i, c in enumerate(clips)},
                        **{f'conf{i}': c['conf'] for i, c in enumerate(clips)}, **{f'ref{i}': c['refpose'] for i, c in enumerate(clips)})
    e = np.concatenate([np.linalg.norm(c['res'], axis=-1) for c in clips])
    print(len(clips), 'clips;', 'res |.| p50/p90 per joint (crop units):', np.round(np.median(e, 0), 3).tolist(),
          np.round(np.percentile(e, 90, 0), 3).tolist())


def pool_halpe(a):
    """20-point (COCO17 + Halpe head / neck / hip) residual pool from a Halpe26 model: Fit3D tuning experiment-A 2D
    (--pose2d) vs the offset-corrected mocap, and Exercise3D P1 app-path Halpe26 CSVs (--ex3d-csv) vs Sapiens2 (neck =
    Sapiens neck, hip = mid Sapiens hips, head has no Sapiens counterpart: the eyes' residual stands in)."""
    offs, clips = load_offsets(a.offsets), []
    for s in a.pool_subjects.split(','):
        for ex in ('squat', 'pushup', 'barbell_row'):
            d = fit3d_seq(a.fit3d, s, ex)
            if d is None:
                continue
            P, cams, ann = d
            for c in CAMS:
                f = f'{a.pose2d}/{s}_{c}_{ex}.npz'
                if not os.path.exists(f):
                    continue
                z = np.load(f); pk = z['pick']; keep = pk < len(P); pk = pk[keep]; kp = z['halpe'][keep][:, :20]
                ref2 = project_fit3d(coco_points(P[pk], offs).reshape(-1, 3), cams[c]).reshape(-1, 20, 2)
                R = np.array(cams[c]['extrinsics']['R']); T = np.array(cams[c]['extrinsics']['T']).reshape(3)
                ang, _ = view_and_side(P[pk][:, FIT3D_TO_H36M], R, T, UP)
                clips.append(clip_entry(kp, ref2, 900, 900, f'{s}/{ex}/{c}', GROUP[ex], ang, 'fit3d', 'halpe'))
    gt = json.load(open(f'{a.ex3d}/gt.json'))
    e3d = []
    for seq in P1:
        g = gt[seq]
        for cam, v in g['views'].items():
            stem = f'{a.ex3d_csv}/{seq}_{cam}_{EX3D_EXNAME[g["exercise"]]}_{a.e_model}'
            csv = stem + '.csv' if os.path.exists(stem + '.csv') else stem + '.csv.gz'
            w, h = json.load(open(stem + '.json'))['image_size']
            kp = read_csv_n(csv, 26)[:, :20]
            lab = np.load(f'{a.ex3d}/exercise3d_labels/{seq}/view/{cam}_pose_2d.npz')
            n = min(len(kp), len(lab['frame_index']))
            ok = lab['valid_mask'][:n] & (lab['confidence'][:n] > 0.5) & lab['target_present'][:n, None]
            L = np.where(ok[..., None], lab['keypoints_xy'][:n] * (max(w, h) / 1280.0), np.nan)
            xy = np.full((n, 20, 2), np.nan)
            xy[:, :17] = L[:, SAPIENS_COCO17]; xy[:, 18] = L[:, SAPIENS_NECK]; xy[:, 19] = L[:, list(SAPIENS_HIPS)].mean(1)
            ce = clip_entry(kp[:n], xy, w, h, f'{seq}/{cam}', GROUP[g['exercise']], v['angle_deg'], 'ex3d', 'halpe')
            ce['res'][:, 17] = ce['res'][:, list(SAPIENS_EYES)].mean(1)  # head: no Sapiens label, eyes stand in
            e3d.append(ce)
    mean = np.nanmean(np.concatenate([c['res'] for c in e3d]), axis=0)
    for c in e3d:
        c['res'] = (c['res'] - mean).astype(np.float32)
    clips += e3d
    np.savez_compressed(a.out, meta=json.dumps([{k: c[k] for k in ('name', 'group', 'angle', 'source')} for c in clips]),
                        ex3d_mean=mean, **{f'res{i}': c['res'] for i, c in enumerate(clips)},
                        **{f'conf{i}': c['conf'] for i, c in enumerate(clips)}, **{f'ref{i}': c['refpose'] for i, c in enumerate(clips)})
    e = np.concatenate([np.linalg.norm(c['res'], axis=-1) for c in clips])
    print(len(clips), 'clips (halpe);', 'res |.| p50 per joint:', np.round(np.median(e, 0), 3).tolist())


def read_csv_n(path, k):
    """pose-replay keypoint CSV with k joints -> [T,k,3] (read_csv keeps 17)."""
    op = gzip.open if str(path).endswith('.gz') else open
    with op(path, 'rt') as f:
        head = f.readline().strip().split(',')
        rows = np.array([[float(x or 'nan') for x in l.strip().split(',')[4:4 + 3 * k]] for l in f])
    assert head[4] == 'j0_x'
    return np.nan_to_num(rows.reshape(len(rows), k, 3))


class Pool:
    def __init__(self, path):
        z = np.load(path)
        self.meta = json.loads(str(z['meta']))
        self.res = [z[f'res{i}'] for i in range(len(self.meta))]
        self.conf = [z[f'conf{i}'] for i in range(len(self.meta))]
        self.ref = [z[f'ref{i}'] for i in range(len(self.meta))]

    def noise(self, rng, group, angle, n, refpose, k=3):
        """residual [n,17,2] crop units + conf [n,17]: same group, one of the k nearest view angles, random start,
        mirrored (x -> -x, left <-> right) when that matches the target's mean pose better."""
        cand = [i for i, m in enumerate(self.meta) if m['group'] == group]
        cand = sorted(cand, key=lambda i: abs(self.meta[i]['angle'] - angle))[:k]
        i = cand[rng.integers(len(cand))]
        idx = (rng.integers(len(self.res[i])) + np.arange(n)) % len(self.res[i])
        r, c, ref = self.res[i][idx].copy(), self.conf[i][idx].copy(), self.ref[i]
        mref = ref.copy(); mref[:, 0] *= -1; mref = mref[H36M_SWAP]
        if np.linalg.norm(mref - refpose) < np.linalg.norm(ref - refpose):
            pm = perm20(r.shape[1]); r, c = r[:, pm], c[:, pm]; r[:, :, 0] *= -1
        return r, c, self.meta[i]['name']


# ---------------------------------------------------------------- sequences
def real_seq(root, replay, s, ex, c, P, cams, ann=None):
    csv = app_csv(replay, s, c, ex)
    if not csv:
        return None
    K = read_csv(csv); n = min(len(K), len(P)); pk = pick30(n)
    return real_seq_from(K[pk], pk, s, ex, c, P, cams, ann)


def real_seq_from(K30, pk, s, ex, c, P, cams, ann=None, w=900, h=900, mapping='app'):
    """R sequence from keypoints (COCO17, or Halpe26 with mapping='halpe') at the picked 30 fps frames pk (50 fps indices)."""
    x, crops = mag_in(K30, w, h, mapping)
    cam = cams[c]; R = np.array(cam['extrinsics']['R']); T = np.array(cam['extrinsics']['T']).reshape(3)
    Xc = (P[pk][:, FIT3D_TO_H36M] - T) @ R.T
    y, mm = target(Xc, crops, float(np.mean(cam['intrinsics_w_distortion']['f'])))
    ang, side = view_and_side(P[pk][:, FIT3D_TO_H36M], R, T, UP)
    return dict(kind='R', name=f'{s}/{ex}/{c}', subject=s, exercise=ex, cam=c, src='app', group=GROUP[ex], x=x, y=y, mm=mm,
                view=ang, side=side, up_c=(R @ UP).tolist(), seg=segments(ann, pk))


def segments(ann, pk):
    """rep_ann boundaries (50 fps frames) -> rep (start, end) at the picked 30 fps frames."""
    if not ann:
        return []
    return [(int(np.searchsorted(pk, a)), int(min(np.searchsorted(pk, b), len(pk) - 1))) for a, b in zip(ann, ann[1:])]


def body_dirs(P):
    """horizontal right (L->R) and 'front' (anterior + head direction; head for prone poses) of a [T,25,3] sequence."""
    horiz = lambda v: unit(v - (v @ UP)[..., None] * UP)
    lr = unit((P[:, 14] - P[:, 11]) + (P[:, 4] - P[:, 1]))
    e1 = unit((P[:, 11] + P[:, 14]) / 2 - (P[:, 1] + P[:, 4]) / 2)
    ant = np.cross(e1, lr)
    ant *= np.sign(np.sum((P[:, 9] - P[:, 8]) * ant, -1).mean())  # the nose is anterior of the thorax
    return horiz(lr.mean(0)), horiz((ant + e1).mean(0))


V_MAPPING = None  # build/vgrid --v-mapping: force the H36M mapping of virtual 2D (default: halpe when the offsets have Halpe points)


def virtual_seq(P, offs, pool_, rng, group, cam, name, noisy=True, ann=None):
    source_mapping = 'halpe' if 'h_hip' in offs else 'app'
    mapping = V_MAPPING or source_mapping
    """cam = dict(side=+-1, az deg from the pure side toward +-front, height m, dist m, f px)."""
    pk = pick30(len(P)); Pk = P[pk]
    right, front = body_dirs(Pk)
    centre = ((Pk[:, 1] + Pk[:, 4] + Pk[:, 11] + Pk[:, 14]) / 4).mean(0)
    floor = np.percentile(np.minimum(Pk[:, 3] @ UP, Pk[:, 6] @ UP), 1) - 0.05
    th = np.radians(cam['az'])
    d = unit(np.cos(th) * cam['side'] * right + np.sin(th) * cam['front'] * front)
    C = centre - (centre @ UP) * UP + UP * (floor + cam['height']) + cam['dist'] * d
    Rm = look_at(C, centre, UP)
    K3 = coco_points(Pk, offs)
    xc = (K3.reshape(-1, 3) - C) @ Rm.T
    uv = (xc[:, :2] / xc[:, 2:3] * cam['f'] + [W / 2, H / 2]).reshape(-1, K3.shape[1], 2)
    inframe = float(((uv[:, 5:] >= 0) & (uv[:, 5:] < [W, H])).all(2).all(1).mean())
    J = Pk[:, FIT3D_TO_H36M]
    ray = centre - C; ray -= (ray @ UP) * UP
    view = float(np.degrees(np.arccos(min(1.0, abs(unit(ray) @ right)))))
    clean = np.concatenate([uv, np.full(uv.shape[:2] + (1,), 0.9)], -1)
    xcl, crops = mag_in(clean, W, H, mapping)
    src = 'clean'
    if noisy:
        # Residuals are measured in the source mapping's crop units. An evaluation-only mapping
        # override must not change their pixel scale or mirror choice: both models see the same 2D.
        noise_ref, noise_crops = (xcl, crops) if mapping == source_mapping else mag_in(clean, W, H, source_mapping)
        r, c, src = pool_.noise(rng, group, view, len(uv), noise_ref[..., :2].mean(0))
        K = np.concatenate([uv + r * noise_crops[:, 2:3, None], c[..., None]], -1)
        x, crops = mag_in(K, W, H, mapping)
    else:
        x = xcl
    y, mm = target((J - C) @ Rm.T, crops, cam['f'])
    side = view_and_side(J, None, C, UP)[1]
    sub, ex = name.split('/')[:2]
    return dict(kind='V', name=name, subject=sub, exercise=ex, group=group, x=x, y=y, mm=mm, view=view, side=side, src=f'v_{mapping}',
                inframe=inframe, noise=src, cam=cam, up_c=(Rm @ UP).tolist(), seg=segments(ann, pk))


def random_cam(rng):
    return dict(side=float(rng.choice([-1, 1])), az=float(rng.uniform(0, 90)), front=float(rng.choice([-1, 1])),
                height=float(rng.uniform(0.3, 1.6)), dist=float(rng.uniform(2.2, 4.5)), f=float(F * rng.uniform(0.85, 1.25)))


def ex3d_seq(ex3d, ex3d_csv, seq, cam, model='mcoco17', mapping='app'):
    """model = the pose-replay keypoint layout suffix of the CSV (mcoco17, or halpe26: its first 17 joints are COCO17)."""
    gt = json.load(open(f'{ex3d}/gt.json'))[seq]
    L = f'{ex3d}/exercise3d_labels/{seq}'
    z = np.load(f'{L}/geometry/canonical_3d.npz'); names = list(z['joint_names'])
    Pw, ok = z['keypoints_3d'].astype(float), z['valid_mask']
    J = np.stack([Pw[:, names.index(nm)] if nm else np.full((len(Pw), 3), np.nan) for nm in EX3D_NAMES], 1)
    okj = np.stack([ok[:, names.index(nm)] if nm else np.zeros(len(Pw), bool) for nm in EX3D_NAMES], 1)
    cg = json.load(open(f'{L}/geometry/metadata.json'))['camera_geometry']
    cg = ast.literal_eval(cg) if isinstance(cg, str) else cg
    E = np.array(cg[cam]['extrinsic_world_to_camera']); Kint = np.array(cg[cam]['intrinsic_working_frame'])
    stem = f'{ex3d_csv}/{seq}_{cam}_{EX3D_EXNAME[gt["exercise"]]}_{model}'
    csv = stem + '.csv' if os.path.exists(stem + '.csv') else stem + '.csv.gz'
    w, h = json.load(open(stem + '.json'))['image_size']
    K = read_csv_n(csv, 26) if mapping == 'halpe' else read_csv(csv); n = min(len(K), len(J))  # read_csv keeps 17 joints
    x, crops = mag_in(K[:n], w, h, mapping)
    Xc = J[:n] @ E[:, :3].T + E[:, 3]
    f = float(Kint[0, 0] + Kint[1, 1]) / 2 * (max(w, h) / 1280.0)  # working frame -> video px
    y, mm = target(np.nan_to_num(Xc), crops, f)
    fmask = okj[:n][:, LIMBS].all(1) & okj[:n, 0] & np.isfinite(Xc[:, LIMBS + [0]]).all((1, 2))
    Rs = [np.array(v['extrinsic_world_to_camera'])[:, :3] for v in cg.values()]
    up_w = -np.mean([R[1] for R in Rs], axis=0); up_w /= np.linalg.norm(up_w)
    rf = gt['rep_frames']; half = int(np.median(np.diff(rf)) / 2) if len(rf) > 1 else 15
    seg = [(max(0, r - half), min(n - 1, r + half)) for r in rf if r < n]
    v = gt['views'][cam]
    return dict(kind='E', name=f'{seq}/{cam}', subject=seq, exercise=EX3D_EXNAME[gt['exercise']], group=GROUP[gt['exercise']],
                x=x, y=y, mm=mm, view=float(v['angle_deg']), side='L' if v['near_side'] == 'left' else 'R',
                up_c=(E[:, :3] @ up_w).tolist(), seg=seg, fmask=fmask, split='heldout' if seq in HELD_E3D else 'P1')


def save(out, seqs, args):
    meta = [{k: v for k, v in s.items() if k not in ('x', 'y', 'mm', 'fmask')} for s in seqs]
    arrs = {}
    for i, s in enumerate(seqs):
        arrs[f'x{i}'], arrs[f'y{i}'], arrs[f'mm{i}'] = s['x'], s['y'], s['mm']
        if 'fmask' in s:
            arrs[f'f{i}'] = s['fmask']
    np.savez_compressed(out, meta=json.dumps(meta), args=json.dumps(vars(args)), **arrs)
    by = {}
    for s in seqs:
        by.setdefault(s['kind'], [0, 0]); by[s['kind']][0] += 1; by[s['kind']][1] += len(s['x'])
    print(out, {k: f'{v[0]} seqs / {v[1]} frames' for k, v in by.items()})


def build(a):
    rng = np.random.default_rng(a.seed)
    kinds, seqs = a.kinds.split(','), []
    offs = load_offsets(a.offsets) if 'V' in kinds else None
    pool_ = Pool(a.pool) if 'V' in kinds else None
    for s in a.subjects.split(',') if a.subjects else []:
        for ex in a.exercises.split(','):
            d = fit3d_seq(a.fit3d, s, ex)
            if d is None:
                continue
            P, cams, _ = d
            if 'R' in kinds and ex in APP_EX:
                for c in CAMS:
                    r = real_seq(a.fit3d, a.replay, s, ex, c, P, cams, d[2])
                    if r: seqs.append(r)
            if 'V' in kinds:
                for k in range(a.vcams):
                    for _ in range(20):  # keep the body in frame
                        cam = random_cam(rng)
                        v = virtual_seq(P, offs, pool_, rng, GROUP[ex], cam, f'{s}/{ex}/v{k}', ann=d[2])
                        if v['inframe'] >= 0.98: break
                    seqs.append(v)
    if 'A' in kinds:  # lift-compare stage-1 2D: same RTMDet box, RTMPose-m COCO17 and m Halpe26 (COCO-shared joints 0-16)
        for s in a.subjects.split(','):
            for ex in ('squat', 'pushup', 'barbell_row'):
                d = fit3d_seq(a.fit3d, s, ex)
                if d is None:
                    continue
                P, cams, ann = d
                for c in CAMS:
                    f = f'{a.pose2d}/{s}_{c}_{ex}.npz'
                    if not os.path.exists(f):
                        continue
                    z = np.load(f); pk = z['pick']; n = int(np.searchsorted(pk, len(P)))
                    for src in a.a_sources.split(','):
                        hm = a.mapping == 'halpe' and src == 'halpe'
                        r = real_seq_from(z[src][:n] if hm else z[src][:n, :17], pk[:n], s, ex, c, P, cams, ann, mapping=a.mapping if hm else 'app')
                        r['src'] = a.a_tag + src + ('_hmap' if hm else ''); r['name'] += '/' + r['src']
                        seqs.append(r)
    if 'E' in kinds:
        for seq in a.ex3d_seqs.split(','):
            assert a.eval_only or seq not in HELD_E3D, f'{seq} is held out (P2/P3): evaluation only'
            for cam in ('cam1', 'cam2', 'cam3'):
                q = ex3d_seq(a.ex3d, a.ex3d_csv, seq, cam, a.e_model, a.mapping)
                q['src'] = f'app_{a.e_model}' + ('_hmap' if a.mapping == 'halpe' else ''); seqs.append(q)
    save(a.out, seqs, a)


def vgrid(a):
    """fixed evaluation cameras: side L/R x az 0/20/40/60 toward the front, + front and back (az 90), h 0.8 m, d 3.0 m,
    f 913; each clean and with noise seed 0."""
    rng = np.random.default_rng(1234)
    offs, pool_ = load_offsets(a.offsets), Pool(a.pool)
    cams = [dict(side=sd, az=az, front=1.0) for sd in (-1.0, 1.0) for az in (0.0, 20.0, 40.0, 60.0)]
    cams += [dict(side=1.0, az=90.0, front=1.0), dict(side=1.0, az=90.0, front=-1.0)]
    seqs = []
    for s in a.subjects.split(','):
        for ex in a.exercises.split(','):
            d = fit3d_seq(a.fit3d, s, ex)
            if d is None:
                continue
            for ci, cam in enumerate(cams):
                cam = dict(cam, height=0.8, dist=3.0, f=F)
                for noisy in ((True,) if a.noisy_only else (False, True)):
                    v = virtual_seq(d[0], offs, pool_, rng, GROUP[ex], cam, f'{s}/{ex}/g{ci}', noisy=noisy, ann=d[2])
                    v['grid'] = ci
                    seqs.append(v)
    save(a.out, seqs, a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=['offsets', 'pool', 'build', 'vgrid'])
    ap.add_argument('--fit3d', default=os.path.expanduser('~/datasets/fit3d'))
    ap.add_argument('--replay', default=os.path.expanduser('~/bpt-smpl/replay'))
    ap.add_argument('--ex3d', default=os.path.expanduser('~/bpt-smpl/ex3d'))
    ap.add_argument('--ex3d-csv', default=os.path.expanduser('~/bpt-runs/reacquire/e3d__cur'))
    ap.add_argument('--offsets'); ap.add_argument('--pool')
    ap.add_argument('--kinds', default='R'); ap.add_argument('--subjects', default='')
    ap.add_argument('--exercises', default=','.join(APP_EX + ('deadlift',)))
    ap.add_argument('--ex3d-seqs', default=','.join(P1))
    ap.add_argument('--vcams', type=int, default=4); ap.add_argument('--seed', type=int, default=0)
    ap.add_argument('--e-model', default='mcoco17', help='build --kinds E: CSV layout suffix (mcoco17 | halpe26)')
    ap.add_argument('--mapping', default='app', help='app | halpe: H36M input mapping for Halpe26 2D (C3, plan §1.3)')
    ap.add_argument('--halpe', action='store_true', help='offsets / pool: fit from a Halpe26 model (--pose2d, --ex3d-csv)')
    ap.add_argument('--a-tag', default='A', help='build --kinds A: src prefix')
    ap.add_argument('--noisy-only', action='store_true', help='vgrid: only the noisy variant (clean skipped)')
    ap.add_argument('--v-mapping', default=None, help='app | halpe: force the mapping of virtual 2D (same 2D, other mapping)')
    ap.add_argument('--pose2d', default=os.path.expanduser('~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d'))
    ap.add_argument('--a-sources', default='coco,halpe', help='build --kinds A: stage-1 keypoint arrays to use')
    ap.add_argument('--pool-subjects', default=','.join(TUNING), help='pool: Fit3D subjects whose real-camera residuals go in')
    ap.add_argument('--eval-only', action='store_true', help='allow Exercise3D held-out (P2/P3) sequences: evaluation sets only')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    global V_MAPPING
    V_MAPPING = a.v_mapping
    {'offsets': offsets, 'pool': pool, 'build': build, 'vgrid': vgrid}[a.cmd](a)


if __name__ == '__main__':
    main()
