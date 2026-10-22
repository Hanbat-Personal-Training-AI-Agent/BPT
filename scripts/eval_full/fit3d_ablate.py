"""eval-full (docs/results/eval_full_prereg.md): Fit3D s07-s11 accuracy ablations of the BPT 3D pipeline. Home only.

Definitions are the lift-refine ones (eval_lift_refine.py constraints, code snapshot 195c0f4): the same Fit3D loader,
XS raw rows (predict_rows), Pose3DConstraints variants, pose/angle metrics and judge_py normal-rep false alarms.
Only the XS input can be swapped, as finetune3 t4_halpe.py does: experiment-A 2D of the same 30 fps picks
(RTMDet-m box + PyTorch RTMPose), mapped with the app mapping or the Halpe-own mapping (C3/C4).

One run = one (model, 2D source, mapping). XS runs once per lookahead; every constraint variant uses the same rows.
Output: per-video aggregates (records.json) - no frames, no keypoints leave the run folder.

usage (Home, bpt-home):
  fit3d_ablate.py --refine-code ~/bpt-runs/lift-refine/_code/195c0f4575d2 --adaptive adaptive_relations.py
                  --src base_h26|A_coco|A_halpe|h26ft|appcsv --mapping app|halpe --model TAG=CKPT
                  --variants raw,Ka,Kstar,... --shapes SUBJECTS.json --run-dir RUN [--threads 4]
"""
import argparse, importlib.util, json, os, sys, time

import numpy as np

SRC = {  # experiment-A 2D (same RTMDet boxes for all three finetune3 sources; A_* = lift-compare inference)
    'base_h26': ('~/bpt-runs/finetune3/c3-data/raw/base_h26', 'halpe'),
    'h26ft': ('~/bpt-runs/finetune3/c4-data/raw/h26ft', 'halpe'),
    'A_halpe': ('~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d', 'halpe'),
    'A_coco': ('~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d', 'coco'),
}
HALPE_OWN = ((19, 0), (18, 8), (17, 10))  # = t4_halpe.py / xs_data.to_h36m
NOISY6 = {'squat_no_lockout', 'valgus_if_front', 'pushup_no_lockout', 'pushup_hip_pike', 'pushup_shallow', 'pushup_head_up'}
# 2D L/R one-side crossing: (COCO left, COCO right, H36M left, H36M right)
LR = {'knee': (13, 14, 5, 2), 'ankle': (15, 16, 6, 3), 'elbow': (7, 8, 12, 15), 'wrist': (9, 10, 13, 16)}
ALL_VARIANTS = ('raw', 'Ka', 'Kstar', 'noclamp', 'nolimits', 'bone_none', 'bone_session', 'bone_prior', 'bone_oracle',
                'adapt', 'Ka_L3', 'Kstar_L3')
ADAPT = dict(reliable_conf=0.5, decay_frames=135.0, max_gap_frames=180)  # setup-constraint selection (E2, eval-heldout)


def to_h36m(K, mapping, coco17_to_h36m):
    xy, conf = coco17_to_h36m(K[:, :17])
    if mapping != 'halpe':
        return xy, conf
    xy, conf = xy.copy(), conf.copy()
    for h, j in HALPE_OWN:
        xy[:, j], conf[:, j] = K[:, h, :2], K[:, h, 2]
    xy[:, 7] = (xy[:, 0] + xy[:, 8]) / 2; conf[:, 7] = (conf[:, 0] + conf[:, 8]) / 2
    xy[:, 9] = (K[:, 0, :2] + xy[:, 8]) / 2; conf[:, 9] = (K[:, 0, 2] + conf[:, 8]) / 2
    return xy, conf


def lr_cross(K17, Jpx):
    """fraction of frames where the predicted left (right) joint is closer to the opposite projected mocap joint."""
    out = {}
    for name, (cl, cr, hl, hr) in LR.items():
        pl, pr, gl, gr = K17[:, cl, :2], K17[:, cr, :2], Jpx[:, hl], Jpx[:, hr]
        d = lambda a, b: np.linalg.norm(a - b, axis=-1)
        out[name] = [int(((d(pl, gr) < d(pl, gl)) | (d(pr, gl) < d(pr, gr))).sum()), len(K17)]
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--refine-code', required=True); p.add_argument('--adaptive', required=True)
    p.add_argument('--src', required=True, choices=list(SRC) + ['appcsv']); p.add_argument('--mapping', choices=['app', 'halpe'], required=True)
    p.add_argument('--model', required=True); p.add_argument('--variants', default=','.join(ALL_VARIANTS))
    p.add_argument('--shapes', required=True); p.add_argument('--run-dir', required=True)
    p.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d')); p.add_argument('--replay', default=os.path.expanduser('~/bpt-smpl/replay'))
    p.add_argument('--subjects', default='s07,s08,s09,s10,s11'); p.add_argument('--threads', type=int, default=4)
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    a = p.parse_args(); argv = list(sys.argv)
    variants = a.variants.split(','); assert set(variants) <= set(ALL_VARIANTS), variants
    tag, ckpt = a.model.split('=', 1); ckpt = os.path.expanduser(ckpt)
    rc = os.path.expanduser(a.refine_code); sys.path[:0] = [rc, f'{rc}/scripts']
    import torch
    torch.set_num_threads(a.threads)
    import eval_lift_app_fit3d as E
    from eval_lift_app_fit3d import (ANG, angle_metrics, angles, apply_constraints, knee_theta, predict_rows, ref_angles,
                                     rep_records, seq_key)
    from eval_lift_app_t2t3 import two_d
    from eval_3d_angles import near_side
    from eval_lift_refine import impossible, mocap_targets
    from finetune_motionagformer_fit3d import PersonSquareCropTracker, coco17_to_motionagformer_h36m17, load, square_crop_normalize
    from pose_feedback.body.form_metrics_3d import UP
    from pose_feedback.body.pose2d_data import project_fit3d
    spec = importlib.util.spec_from_file_location('adaptive_relations', os.path.expanduser(a.adaptive))
    AR = importlib.util.module_from_spec(spec); spec.loader.exec_module(AR)

    ea = argparse.Namespace(root=a.root, replay=a.replay, subjects=a.subjects.split(','), exercises=list(E.EXERCISES))
    seqs, skipped = [], []
    for d in E.load_seqs(ea):
        cam = json.load(open(f"{a.root}/train/{d['subj']}/camera_parameters/{d['cam']}/{d['ex']}.json"))
        if a.src != 'appcsv':
            rdir, key = SRC[a.src]
            f = f"{os.path.expanduser(rdir)}/{d['subj']}_{d['cam']}_{d['ex']}.npz"
            if not os.path.exists(f): skipped.append((d['subj'], d['ex'], d['cam'], 'no raw')); continue
            z = np.load(f); pk, K = z['pick'], z[key]
            m = min(len(pk), len(d['pick']))
            if m < 0.95 * len(d['pick']) or not np.array_equal(pk[:m], d['pick'][:m]):
                skipped.append((d['subj'], d['ex'], d['cam'], 'pick mismatch')); continue
            for k in ('x', 'y', 'mm', 'pick', 'K', 'G'): d[k] = d[k][:m]
            d['seg'] = [(s, e) for s, e in d['seg'] if e < m]
            K = K[:m]
            if a.mapping == 'halpe' and K.shape[1] < 26: raise SystemExit('halpe mapping needs 26 points')
            xy, conf = to_h36m(K, a.mapping, coco17_to_motionagformer_h36m17)
            tr, crops = PersonSquareCropTracker(), []
            for q, c in zip(xy, conf): crops.append(tr.update(q, c) or (450., 450., 900.))
            crops = np.array(crops)
            d['x'] = np.concatenate([np.stack([square_crop_normalize(q, c) for q, c in zip(xy, crops)]), conf[..., None]], -1).astype(np.float32)
            fpx = float(np.mean(cam['intrinsics_w_distortion']['f']))
            Xc = (d['J'][d['pick']] - d['T']) @ d['R'].T
            d['mm'] = (crops[:, 2] / 2 * Xc[:, 0, 2] / fpx * 1000).astype(np.float32)
            d['K'] = K[:, :17]; d['side'] = near_side(d['K']); d['unit'] = crops[:, 2] / 2
        else:
            assert a.mapping == 'app'
            d['unit'] = None
        d['lr'] = lr_cross(d['K'], project_fit3d(d['J'][d['pick']].reshape(-1, 3), cam).reshape(len(d['pick']), 17, 2))
        seqs.append(d)
    print(len(seqs), 'sequences;', len(skipped), 'skipped', skipped, flush=True)
    if a.src == 'appcsv' and 'adapt' in variants: variants.remove('adapt')

    model = load(a.mag_repo, ckpt, 'cpu')[0].eval()
    shapes = json.load(open(os.path.expanduser(a.shapes)))
    recs, t0 = [], time.time()
    for d in seqs:
        Ls = [5] + ([3] if any(v.endswith('_L3') for v in variants) else [])
        rows = predict_rows(model, 'cpu', d['x'], Ls, None)
        mm = d['mm'][:, None, None] / 1000; ref = ref_angles(d); side = {'L': 'left', 'R': 'right'}[d['side']]; G = d['G']
        td_app, _ = two_d(ea, d); sq = d['ex'] == 'squat'
        cal = shapes[d['subj']]['segments_cm']
        Ka = dict(knee_clamp_deg=None, reflect_flipped_knee=sq)
        Ks = dict(reflect_flipped_knee=sq, calibration_targets_cm=cal)
        kw = {'raw': None, 'Ka': Ka, 'Kstar': Ks, 'noclamp': dict(Ka, calibration_targets_cm=cal),
              'nolimits': dict(Ks, angle_limits=()), 'bone_none': dict(reflect_flipped_knee=sq, bone_lengths=False),
              'bone_session': dict(reflect_flipped_knee=sq), 'bone_prior': dict(reflect_flipped_knee=sq, session_min_frames=10 ** 9),
              'bone_oracle': dict(reflect_flipped_knee=sq, calibration_targets_cm=mocap_targets(G)), 'adapt': Ks,
              'Ka_L3': Ka, 'Kstar_L3': Ks}
        raw5 = rows[5]
        flip = {L: float(np.mean([np.nan_to_num(knee_theta(rows[L], leg)[0], nan=0.) < -30 for leg in ('left', 'right')])) for L in rows}
        meta = dict(subj=d['subj'], exercise=d['ex'], cam=d['cam'], model=tag, src=a.src, mapping=a.mapping, frames=len(raw5),
                    lr=d['lr'])
        for v in variants:
            L = 3 if v.endswith('_L3') else 5; raw = rows[L]
            if kw[v] is None:
                Q, inv = raw, [[] for _ in raw]
            else:
                Q, rp = apply_constraints(raw, kw[v]); inv = [list(r['invalid_joints']) for r in rp]
            if v == 'adapt':
                est = AR.AdaptiveRelations(d['ex'], **ADAPT); conf = d['x'][..., 2]; Q = Q.copy()
                for t in range(len(Q)):
                    Q[t], r = est.update(Q[t], conf[t], t, float(d['unit'][t]))
                    inv[t] = sorted(set(inv[t]) | set(int(j) for j in r['invalid']))
            P = (Q - Q[:, :1]) * mm
            Pm = P.copy()
            for i, j in enumerate(inv):
                if j: Pm[i, j] = np.nan
            pm = E.pose_metrics(P, G)
            am = angle_metrics(angles(P, d['side'], d['up_c']), ref, d['seg'])
            reps = rep_records(Pm, d['seg'], d['ex'], side, UP, dict(var=v), td_app)
            recs.append(dict(meta, var=v, L=L, mpjpe=float(np.sum(pm['mpjpe'])), pa=float(np.sum(pm['pa_mpjpe'])), n=len(pm['mpjpe']),
                             accel=float(np.sum(pm['accel'])), n_acc=len(pm['accel']),
                             rep_err={g: [float(x) for x in am[g]['rep']] for g in ANG},
                             invalid=float(np.mean([bool(j) for j in inv])), impossible=float(np.mean(impossible(P))),
                             knee_flip_raw=flip[L], fired=[sorted(r['fired']) for r in reps]))
        print(d['subj'], d['ex'], d['cam'], f'{time.time() - t0:.0f}s', flush=True)
    os.makedirs(a.run_dir, exist_ok=True)
    json.dump(dict(argv=argv, skipped=skipped, adapt=ADAPT, noisy6=sorted(NOISY6), records=recs),
              open(f'{a.run_dir}/records.json', 'w'))
    print('done', len(recs), 'records', flush=True)


if __name__ == '__main__':
    main()
