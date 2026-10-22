"""finetune3 T4-Halpe (plan §1.4): the lift-app T4 evaluation (eval_lift_app_t2t3.py t4, a03ddd9: mocap, rep segments,
judge_py rules, Pose3DConstraints L=5) with only the XS input swapped: instead of the app replay CSV, the experiment-A
Halpe26 2D of the same 30 fps picked frames (rtm_lift_effect --save-raw), mapped to H36M with `--mapping app` (the app's
coco17ToH36M17 on joints 0-16) or `halpe` (pelvis <- 19, thorax <- 18, head <- 17, as xs_data.to_h36m). The crop, the
mm-per-crop-unit scale and the 2D heights used by the rules follow the swapped 2D. Sequences whose raw picks do not match
the replay picks are skipped and counted. One mapping per run; merge runs by tag afterwards.

usage (Home, bpt-home): t4_halpe.py --lift-code DIR --raw RAWDIR --mapping halpe|app --models tag=ckpt,... --run-dir RUN
                        [--root ~/datasets/fit3d --replay ~/bpt-smpl/replay --subjects s07,...]
"""
import argparse, json, os, sys

import numpy as np

HALPE_OWN = ((19, 0), (18, 8), (17, 10))  # Halpe hip -> pelvis, neck -> thorax, head -> head (C3 mapping)


def to_h36m(K, mapping, coco17_to_h36m):
    """Same as finetune3/xs_data.to_h36m (kept here so only the lift-app code is imported)."""
    xy, conf = coco17_to_h36m(K[:, :17])
    if mapping != 'halpe':
        return xy, conf
    xy, conf = xy.copy(), conf.copy()
    for h, j in HALPE_OWN:
        xy[:, j], conf[:, j] = K[:, h, :2], K[:, h, 2]
    xy[:, 7] = (xy[:, 0] + xy[:, 8]) / 2; conf[:, 7] = (conf[:, 0] + conf[:, 8]) / 2
    xy[:, 9] = (K[:, 0, :2] + xy[:, 8]) / 2; conf[:, 9] = (K[:, 0, 2] + conf[:, 8]) / 2
    return xy, conf


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--lift-code', required=True); p.add_argument('--raw', required=True)
    p.add_argument('--mapping', choices=['app', 'halpe'], required=True)
    p.add_argument('--models', required=True); p.add_argument('--run-dir', required=True)
    p.add_argument('--root', default=os.path.expanduser('~/datasets/fit3d'))
    p.add_argument('--replay', default=os.path.expanduser('~/bpt-smpl/replay'))
    p.add_argument('--subjects', default='s07,s08,s09,s10,s11')
    a = p.parse_args(); argv = list(sys.argv)
    sys.path.insert(0, a.lift_code)
    import eval_lift_app_t2t3 as T
    import eval_lift_app_fit3d as E
    from eval_3d_angles import near_side
    from finetune_motionagformer_fit3d import PersonSquareCropTracker, coco17_to_motionagformer_h36m17, square_crop_normalize

    orig_load = E.load_seqs
    skipped = []

    def load_seqs(args):
        out = []
        for d in orig_load(args):
            f = f"{a.raw}/{d['subj']}_{d['cam']}_{d['ex']}.npz"
            if not os.path.exists(f):
                skipped.append((d['subj'], d['ex'], d['cam'], 'no raw')); continue
            z = np.load(f); pk, K = z['pick'], z['halpe']
            m = min(len(pk), len(d['pick']))
            if m < 0.95 * len(d['pick']) or not np.array_equal(pk[:m], d['pick'][:m]):
                skipped.append((d['subj'], d['ex'], d['cam'], 'pick mismatch')); continue
            for k in ('x', 'y', 'mm', 'pick', 'K', 'G'):
                d[k] = d[k][:m]
            d['seg'] = [(s, e) for s, e in d['seg'] if e < m]
            K = K[:m]
            xy, conf = to_h36m(K, a.mapping, coco17_to_motionagformer_h36m17)
            tr, crops = PersonSquareCropTracker(), []
            for q, c in zip(xy, conf):
                crops.append(tr.update(q, c) or (450., 450., 900.))
            crops = np.array(crops)
            d['x'] = np.concatenate([np.stack([square_crop_normalize(q, c) for q, c in zip(xy, crops)]), conf[..., None]], -1).astype(np.float32)
            cam = json.load(open(f"{a.root}/train/{d['subj']}/camera_parameters/{d['cam']}/{d['ex']}.json"))
            fpx = float(np.mean(cam['intrinsics_w_distortion']['f']))
            Xc = (d['J'][d['pick']] - d['T']) @ d['R'].T
            d['mm'] = (crops[:, 2] / 2 * Xc[:, 0, 2] / fpx * 1000).astype(np.float32)
            d['K'] = K[:, :17]; d['side'] = near_side(d['K']); d['csv'] = f
            out.append(d)
        print(len(out), 'sequences on swapped 2D;', len(skipped), 'skipped', skipped, flush=True)
        return out

    T.load_seqs = load_seqs
    os.makedirs(a.run_dir, exist_ok=True)
    sys.argv = [sys.argv[0], 't4', '--root', a.root, '--replay', a.replay, '--subjects', a.subjects,
                '--models', a.models, '--run-dir', a.run_dir]
    T.main()
    json.dump(dict(argv=argv, mapping=a.mapping, raw=a.raw, lift_code=a.lift_code, skipped=skipped), open(f'{a.run_dir}/t4_halpe_input.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
