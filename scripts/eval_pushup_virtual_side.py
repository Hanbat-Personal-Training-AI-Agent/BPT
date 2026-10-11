"""Held-out side-view push-up rep accuracy from Fit3D mocap projected into virtual side cameras
(synthetic projection, no detector). Track T3 / D-T3-08.

Three steps, data never leaves the machine it is on (Fit3D licence: local only, aggregates only):
  noise   (Mac)  Exercise3D side push-ups (<=45 deg): RTMPose-m COCO17 keypoints vs Sapiens2 2D pseudo labels
                 -> per-frame residual (torso-length units, head = +x, camera-near side in the "left" slots)
                 and RTMPose confidence. Each clip is kept as a whole sequence (temporal correlation,
                 left/right swaps and cross-joint correlation come along); the pooled mean is removed.
  synth   (Home) 1. COCO17 definition offsets: Fit3D joints3d_25 are joint centres, COCO shoulders/hips sit
                    elsewhere (D-C-02). Fit one 3D offset per body part (body frame: torso axis, outward,
                    anterior; L/R mirrored) by least squares between RTMPose-m on the real videos of the
                    TUNING subjects (s03-s05, 4 cams) and the camera projection of the mocap.
                 2. Every subject: mocap 50 -> 30 fps, offsets applied, projected into virtual pinhole
                    cameras 720x1280 (f 913 px = iPhone 1x 16:9 portrait, short-side FOV 43 deg) placed
                    DIST m from the body centre at HEIGHT m above the floor, on the body's left and right,
                    rotated ANGLE deg from the pure side toward the head. Variants: clean (conf 0.9) and
                    noise seeds (an Exercise3D residual clip of the nearest view angle, random start).
                 3. Truth: rep_ann boundaries (reps = len-1) + 3D shoulder-height troughs in the window.
  score   (Mac)  pose-replay --keypoints-csv on every CSV, rep accuracy per subject x angle x variant.

usage:
  eval_pushup_virtual_side.py noise --cache DIR --out pool.npz
  eval_pushup_virtual_side.py synth --fit3d ~/datasets/fit3d/train --rtm DIR --pool pool.npz --out DIR
  eval_pushup_virtual_side.py score --synth DIR --pose-replay BIN --out results.json
Rep accuracy = (truth - missed) / (truth + extra), same as outputs/rep_validation (three-ex run_eval.py).
"""
import argparse
import collections
import csv
import glob
import json
import os
import subprocess
import tempfile

import numpy as np

SAPIENS_COCO17 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 62, 41, 9, 10, 11, 12, 13, 14]
SWAP = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15]  # COCO17 left <-> right
LEFT, RIGHT = [5, 7, 9, 11, 13, 15], [6, 8, 10, 12, 14, 16]
# COCO17 <- Fit3D joints3d_25 (11 is on the same side as hip 1; D-C-02 / eval_pose2d.FIT3D_COCO), nose <- 9
FIT3D_COCO = {0: 9, 5: 11, 6: 14, 7: 12, 8: 15, 9: 13, 10: 16, 11: 1, 12: 4, 13: 2, 14: 5, 15: 3, 16: 6}
PART = {0: 'nose', 5: 'shoulder', 6: 'shoulder', 7: 'elbow', 8: 'elbow', 9: 'wrist', 10: 'wrist',
        11: 'hip', 12: 'hip', 13: 'knee', 14: 'knee', 15: 'ankle', 16: 'ankle'}
TUNING = ('s03', 's04', 's05')
HELD = ('s07', 's08', 's09', 's10', 's11')
CAMS = ('50591643', '58860488', '60457274', '65906101')
W, H, F = 720, 1280, 913.0
ANGLES = (0, 20, 40)
SEEDS = 3
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_kp_csv(path):
    rows = list(csv.reader(open(path)))[1:]
    return np.array([[float(x or 0) for x in r[4:4 + 51]] for r in rows]).reshape(-1, 17, 3)


def interp_nan(a):
    """[T, ...] linear interpolation over NaN in time per column; all-NaN columns -> 0."""
    flat = a.reshape(len(a), -1).copy()
    t = np.arange(len(a))
    for k in range(flat.shape[1]):
        ok = ~np.isnan(flat[:, k])
        flat[:, k] = np.interp(t, t[ok], flat[ok, k]) if ok.sum() > 0.1 * len(a) else 0.0
    return flat.reshape(a.shape)


# ---------------------------------------------------------------- noise (Mac)
def noise(args):
    root = REPO if os.path.exists(f'{REPO}/outputs/exercise3d_labels') else os.path.dirname(os.path.dirname(os.path.dirname(REPO)))
    gt = json.load(open(f'{root}/outputs/rep_validation/gt.json'))
    clips, stats = [], []
    for seq, g in sorted(gt.items()):
        if g['exercise'] != 'pushup':
            continue
        for cam, v in sorted(g['views'].items()):
            if v['angle_deg'] > 45:
                continue
            kp = read_kp_csv(f'{args.cache}/{seq}/{cam}_mcoco17.csv')
            lab = np.load(f'{root}/outputs/exercise3d_labels/{seq}/view/{cam}_pose_2d.npz')
            n = min(len(kp), len(lab['frame_index']))
            kp = kp[:n]
            xy = lab['keypoints_xy'][:n][:, SAPIENS_COCO17] * 1.5  # labels are on a 1280-long-side copy (eval_pose2d)
            ok = lab['valid_mask'][:n][:, SAPIENS_COCO17] & (lab['confidence'][:n][:, SAPIENS_COCO17] > 0.5) & lab['target_present'][:n, None]
            near_left = kp[:, LEFT, 2].mean() >= kp[:, RIGHT, 2].mean()
            perm = list(range(17)) if near_left else SWAP
            sh, hp = xy[:, 5:7].mean(1), xy[:, 11:13].mean(1)
            torso = np.median(np.linalg.norm(sh - hp, axis=1)[ok[:, 5:7].all(1) & ok[:, 11:13].all(1)])
            head = np.sign(np.median(sh[:, 0] - hp[:, 0]))
            res = (kp[:, :, :2] - xy) / torso
            res[~ok] = np.nan
            res[:, :, 0] *= head
            res, conf = interp_nan(res[:, perm]), kp[:, perm, 2]
            clips.append(dict(name=f'{seq}/{cam}', angle=v['angle_deg'], res=res, conf=conf))
            stats.append((f'{seq}/{cam}', v['angle_deg'], 'L' if near_left else 'R', round(float(torso), 1), int(head), n))
    mean = np.mean(np.concatenate([c['res'] for c in clips]), axis=0)
    for c in clips:
        c['res'] = c['res'] - mean
    allr, allc = np.concatenate([c['res'] for c in clips]), np.concatenate([c['conf'] for c in clips])
    print('clips (seq/cam, angle, near, torso px, head dir, frames):', *stats, sep='\n  ')
    print('removed mean (torso units, near-side slots):', np.round(mean, 3).tolist())
    print('|resid| p50/p90 per joint (torso units, near=left slots):')
    e = np.linalg.norm(allr, axis=2)
    print('  p50', np.round(np.median(e, 0), 3).tolist())
    print('  p90', np.round(np.percentile(e, 90, 0), 3).tolist())
    print('  conf p50', np.round(np.median(allc, 0), 2).tolist())
    np.savez(args.out, names=[c['name'] for c in clips], angles=[c['angle'] for c in clips],
             **{f'res{i}': c['res'] for i, c in enumerate(clips)}, **{f'conf{i}': c['conf'] for i, c in enumerate(clips)})


# ---------------------------------------------------------------- synth (Home)
def project_fit3d(points, camera):  # same as pose_feedback.body.pose2d_data.project_fit3d (kept local: runs on Home)
    R = np.asarray(camera['extrinsics']['R'], float)
    T = np.asarray(camera['extrinsics']['T'], float).reshape(3)
    i = camera['intrinsics_w_distortion']
    f, c = np.asarray(i['f'], float).reshape(2), np.asarray(i['c'], float).reshape(2)
    k, p = np.asarray(i['k'], float).reshape(3), np.asarray(i['p'], float).reshape(2)
    xy = (np.asarray(points, float) - T) @ R.T
    xy = xy[:, :2] / xy[:, 2:3]
    r2 = (xy ** 2).sum(1)
    xy = xy * (1 + k[0] * r2 + k[1] * r2 ** 2 + k[2] * r2 ** 3 + p[0] * xy[:, 1] + p[1] * xy[:, 0])[:, None] + np.outer(r2, [p[1], p[0]])
    return xy * f + c


def unit(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def body_basis(P, joint):
    """[T,3,3] columns: torso axis (hip->shoulder), outward (toward the joint's side; nose: subject's right), anterior."""
    e1 = unit((P[:, 11] + P[:, 14]) / 2 - (P[:, 1] + P[:, 4]) / 2)
    lr = (P[:, 14] - P[:, 11]) + (P[:, 4] - P[:, 1])  # left -> right
    lr = unit(lr - (lr * e1).sum(1, keepdims=True) * e1)
    e3 = np.cross(e1, lr)
    out = -lr if joint in LEFT else lr
    return np.stack([e1, out, e3], axis=2)


def load_subject(root, s):
    P = np.array(json.load(open(f'{root}/{s}/joints3d_25/pushup.json'))['joints3d_25'], float)
    cams = {c: json.load(open(f'{root}/{s}/camera_parameters/{c}/pushup.json')) for c in CAMS}
    up = unit(-np.mean([np.asarray(c['extrinsics']['R'], float)[1] for c in cams.values()], axis=0))
    return P, cams, up, json.load(open(f'{root}/{s}/rep_ann.json'))['pushup']


def fit_offsets(root, rtm_dir):
    obs = collections.defaultdict(lambda: ([], []))  # part -> (J rows [2,3], residual [2])
    for s in TUNING:
        P, cams, up, ann = load_subject(root, s)
        for c in CAMS:
            kp = read_kp_csv(f'{rtm_dir}/rtm_{s}_{c}.csv')
            n = min(len(kp), len(P))
            fr = np.arange(ann[0], min(ann[-1] + 1, n))
            for j, fj in FIT3D_COCO.items():
                X, B = P[fr, fj], body_basis(P[fr], j)
                x0 = project_fit3d(X, cams[c])
                Jc = np.stack([(project_fit3d(X + 0.01 * B[:, :, k], cams[c]) - x0) / 0.01 for k in range(3)], axis=2)
                good = kp[fr, j, 2] >= 0.5
                obs[PART[j]][0].append(Jc[good])
                obs[PART[j]][1].append(kp[fr, j, :2][good] - x0[good])
    offsets, report = {}, {}
    for part, (Js, rs) in obs.items():
        J, r = np.concatenate(Js).reshape(-1, 3), np.concatenate(rs).reshape(-1)
        keep = np.ones(len(r), bool)
        for _ in range(3):  # trimmed least squares (RTMPose left/right swaps and misses)
            d = np.linalg.lstsq(J[keep], r[keep], rcond=None)[0]
            e = np.abs(r - J @ d)
            keep = e < 3 * np.median(e[keep])
        offsets[part] = d
        before = np.median(np.hypot(*r.reshape(-1, 2).T))
        after = np.median(np.hypot(*(r - J @ d).reshape(-1, 2).T))
        report[part] = dict(offset_m=np.round(d, 3).tolist(), obs=int(len(r) // 2), med_err_px_before=round(float(before), 1),
                            med_err_px_after=round(float(after), 1))
    return offsets, report


def periodicity(sig, lo=0.35, hi=0.65):  # three-ex fit3d_gt.count (shoulder height troughs)
    p5, p95 = np.percentile(sig, [5, 95])
    n = (sig - p5) / (p95 - p5)
    reps, armed, start = [], n[0] > hi, None
    for i, v in enumerate(n):
        if v > hi:
            if not armed and start is not None:
                reps.append(int(start + np.argmin(n[start:i])))
            armed, start = True, None
        elif v < lo and armed:
            armed, start = False, i
    if start is not None and n[-1] > 0.5:
        reps.append(int(start + np.argmin(n[start:])))
    return reps


def look_at(C, target, up):
    z = unit(target - C)
    x = unit(np.cross(z, up))
    return np.stack([x, np.cross(z, x), z])  # rows; X_cam = R (X - C), y down


def synth(args):
    offsets, report = fit_offsets(args.fit3d, args.rtm)
    print(json.dumps(report, indent=1))
    pool = np.load(args.pool)
    pangles = np.asarray(pool['angles'])
    os.makedirs(args.out, exist_ok=True)
    gt, meta = {}, dict(offsets=report, height_m=args.height, dist_m=args.dist, f_px=F, size=[W, H], angles=ANGLES, seeds=SEEDS,
                        pool=[str(x) for x in pool['names']])
    rng = np.random.default_rng(0)
    for s in TUNING + HELD:
        P50, cams, up, ann = load_subject(args.fit3d, s)
        t50 = np.arange(len(P50)) / 50.0
        t30 = np.arange(0, t50[-1], 1 / 30.0)
        P = np.stack([np.stack([np.interp(t30, t50, P50[:, j, k]) for k in range(3)], 1) for j in range(25)], 1)
        a, b = int(round(ann[0] * 0.6)), int(round(ann[-1] * 0.6))
        K = np.zeros((len(P), 17, 3))
        for j, fj in FIT3D_COCO.items():
            K[:, j] = P[:, fj] + body_basis(P, j) @ offsets[PART[j]]
        lr = unit(((P[:, 14] - P[:, 11]) + (P[:, 4] - P[:, 1])))
        for eye, ear, sgn in ((1, 3, -1), (2, 4, 1)):  # face points only feed the side/confidence gates
            K[:, eye] = 0.7 * P[:, 9] + 0.3 * P[:, 10] + sgn * 0.03 * lr
            K[:, ear] = 0.5 * (P[:, 9] + P[:, 10]) + sgn * 0.07 * lr
        win = slice(a, b + 1)
        height = lambda X: X @ up
        floor = np.percentile(np.minimum(height(P[:, 3]), height(P[:, 6])), 1) - 0.05  # ankle centre ~5 cm above floor
        centre = ((P[win, 1] + P[win, 4] + P[win, 11] + P[win, 14]) / 4).mean(0)
        horiz = lambda v: unit(v - (v @ up) * up)
        head = horiz(((P[win, 11] + P[win, 14]) / 2 - (P[win, 3] + P[win, 6]) / 2).mean(0))
        right = horiz(lr[win].mean(0))
        sh = (P[:, 11] + P[:, 14]) / 2 @ up
        gt[s] = dict(truth=len(ann) - 1, window=[a, b], troughs=[a + r for r in periodicity(np.convolve(np.pad(sh[a:b + 1], 4, mode='edge'), np.ones(9) / 9, mode='valid'))],
                     frames=len(P), split='tune' if s in TUNING else 'held')
        for side, sdir in (('L', -right), ('R', right)):
            for ang in ANGLES:
                th = np.radians(ang)
                d = np.cos(th) * sdir + np.sin(th) * head
                C = centre - (centre @ up) * up + up * (floor + args.height) + args.dist * d
                R = look_at(C, centre, up)
                xc = (K.reshape(-1, 3) - C) @ R.T
                uv = (xc[:, :2] / xc[:, 2:3] * F + [W / 2, H / 2]).reshape(-1, 17, 2)
                torso = np.median(np.linalg.norm(uv[win, 5:7].mean(1) - uv[win, 11:13].mean(1), axis=1))
                hsign = np.sign(np.median(uv[win, 5:7].mean(1)[:, 0] - uv[win, 11:13].mean(1)[:, 0]))
                # check the view angle with the three-ex definition (horizontal ray vs left-right axis)
                ray = horiz(centre - C)
                gt[s].setdefault('angle_check', {})[f'{side}{ang}'] = round(float(np.degrees(np.arccos(min(1.0, abs(ray @ right))))), 1)
                gt[s].setdefault('in_frame', {})[f'{side}{ang}'] = round(float(((uv[win, 5:] >= 0) & (uv[win, 5:] < [W, H])).all(2).mean()), 3)
                variants = [('clean', uv, np.full((len(P), 17), 0.9))]
                near = np.argsort(np.abs(pangles - ang), kind='stable')[:SEEDS]
                for seed, ci in enumerate(near):
                    res, conf = pool[f'res{ci}'], pool[f'conf{ci}']
                    idx = (rng.integers(len(res)) + np.arange(len(P))) % len(res)
                    r, c = res[idx].copy(), conf[idx].copy()
                    r[:, :, 0] *= hsign
                    if side == 'R':
                        r, c = r[:, SWAP], c[:, SWAP]
                    variants.append((f'noise{seed}', uv + r * torso, c))
                for name, xy, c in variants:
                    with open(f'{args.out}/{s}_{side}{ang}_{name}.csv', 'w') as fh:
                        fh.write('frame,time,status,rep,' + ','.join(f'j{j}_{q}' for j in range(17) for q in 'xyc') + '\n')
                        for i in range(len(P)):
                            fh.write(f'{i},{i / 30:.4f},,,' + ','.join(f'{xy[i, j, 0]:.2f},{xy[i, j, 1]:.2f},{c[i, j]:.4f}' for j in range(17)) + '\n')
    json.dump(dict(meta, gt=gt), open(f'{args.out}/gt.json', 'w'), indent=1)
    print({s: (g['truth'], len(g['troughs']), g['angle_check'], min(g['in_frame'].values())) for s, g in gt.items()})


# ---------------------------------------------------------------- score (Mac)
def match(troughs, ends):  # three-ex run_eval.match: a rep end credits the latest unclaimed trough at or before it (+5 frames)
    credited, extra, last = {}, [], -1
    for i, e in enumerate(ends):
        cand = [k for k, t in enumerate(troughs) if t <= e + 5 and k > last]
        if cand:
            last = cand[-1]
            credited[last] = i
        else:
            extra.append(i)
    return credited, extra


def acc(rows):
    t, mi, ex = (sum(r[k] for r in rows) for k in ('truth', 'missed', 'extra'))
    return (t - mi) / (t + ex) if t + ex else float('nan')


def score(args):
    meta = json.load(open(f'{args.synth}/gt.json'))
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for path in sorted(glob.glob(f'{args.synth}/s*.csv')):
            name = os.path.basename(path)[:-4]
            s, view, variant = name.split('_')
            subprocess.run([args.pose_replay, '--exercise', 'pushup', '--motion3d', 'none', '--keypoints-csv', path,
                            '--output-dir', tmp, f'/x/{name}.mp4'], stdout=subprocess.DEVNULL, check=True)
            out = glob.glob(f'{tmp}/{name}_pushup_*.json')[0]
            j = json.load(open(out))
            for f in glob.glob(f'{tmp}/{name}_*'):
                os.remove(f)
            g = meta['gt'][s]
            ends = j['session']['rep_end_frames']
            cr, ex = match(g['troughs'], ends)
            a, b = g['window']
            rows.append(dict(subject=s, split=g['split'], side=view[0], angle=int(view[1:]), variant=variant,
                             truth=g['truth'], troughs=len(g['troughs']), counted=len(ends), missed=len(g['troughs']) - len(cr),
                             extra=len(ex), extra_in_window=sum(1 for i in ex if a - 10 <= ends[i] <= b + 15),
                             ends=ends, events=collections.Counter(e['key'] for e in j['events'])))
    json.dump(dict(meta=meta, rows=rows), open(args.out, 'w'), indent=1)
    print_tables(rows)


def print_tables(rows):
    def cell(rs):  # all reps | set window only (extras while getting down / standing up ignored)
        t, mi, ex, exw = (sum(r[k] for r in rs) for k in ('truth', 'missed', 'extra', 'extra_in_window'))
        return f'{acc(rs):.1%} / {(t - mi) / (t + exw):.1%} (−{mi} +{ex}, 구간안 +{exw})'
    for variant in ('clean', 'noise'):
        rs = [r for r in rows if r['variant'].startswith(variant)]
        print(f'\n### {variant}  rep accuracy all / set-window only (−missed +extra, +extra inside the set window)')
        print('| subject | split | ' + ' | '.join(f'{a}°' for a in ANGLES) + ' | all |')
        print('|---|---|' + '---|' * (len(ANGLES) + 1))
        for s in TUNING + HELD:
            sr = [r for r in rs if r['subject'] == s]
            if sr:
                print(f'| {s} | {sr[0]["split"]} | ' + ' | '.join(cell([r for r in sr if r['angle'] == a]) for a in ANGLES) + f' | {cell(sr)} |')
        for split in ('tune', 'held'):
            sr = [r for r in rs if r['split'] == split]
            print(f'| **{split}** | | ' + ' | '.join(cell([r for r in sr if r['angle'] == a]) for a in ANGLES) + f' | **{cell(sr)}** |')
    ev = collections.Counter()
    for r in rows:
        ev.update(r['events'])
    print('\nevents:', dict(ev))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('noise'); p.add_argument('--cache', required=True); p.add_argument('--out', required=True)
    p = sub.add_parser('synth'); p.add_argument('--fit3d', required=True); p.add_argument('--rtm', required=True)
    p.add_argument('--pool', required=True); p.add_argument('--out', required=True)
    p.add_argument('--height', type=float, default=0.5); p.add_argument('--dist', type=float, default=3.5)
    p = sub.add_parser('score'); p.add_argument('--synth', required=True); p.add_argument('--pose-replay', required=True)
    p.add_argument('--out', required=True)
    a = ap.parse_args()
    {'noise': noise, 'synth': synth, 'score': score}[a.cmd](a)
