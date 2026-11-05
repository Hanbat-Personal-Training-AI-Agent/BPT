"""Method 2 occlusion (Home, bpt-mmpose env): paint a joint region of the real Fit3D frames and rerun RTMPose-m COCO17.

For each chosen video and episode (group in wrist / ankle / knee, 60 frames at 30 fps): every frame of the episode gets a
filled grey disc at the mocap joint's projection, radius = 0.6 x the projected bone (forearm / shin / thigh). RTMPose-m
COCO17 (mmpose, same checkpoint and config as lift-compare A-pose2d) runs top-down on the SAME RTMDet box that A-pose2d
used for that frame, so the only change against the clean A-pose2d keypoints is the paint. Episodes are seeded like
eval_setup_constraint.episodes_for (crc32 of video + group). Fit3D never leaves Home; outputs stay in the run folder.

usage: eval_setup_rgb_occlusion.py --root ~/datasets/fit3d --pose2d A-pose2d-20261019/pose2d --out RUN/rgb \
           --coco-cfg CFG --coco-ckpt CKPT --videos s07_50591643_squat,... [--groups wrist,ankle,knee] [--per-video 2]
"""
import argparse, hashlib, json, os, socket, sys, time, zlib
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [os.path.dirname(HERE), HERE]
FIT3D_TO_H36M = [0, 4, 5, 6, 1, 2, 3, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
# group -> per side (H36M joint painted, H36M parent for the radius, COCO index damaged)
GROUPS = {'wrist': {'L': (13, 12, 9), 'R': (16, 15, 10)}, 'ankle': {'L': (6, 5, 15), 'R': (3, 2, 16)},
          'knee': {'L': (5, 4, 13), 'R': (2, 1, 14)}}
LENGTH, GAP = 60, 60


def project(points, cam):
    from pose_feedback.body.pose2d_data import project_fit3d
    return project_fit3d(points, cam)


def episodes(key, group, lo, hi, per_video):
    rng = np.random.default_rng(zlib.crc32(f'{key}/{group}/rgb'.encode())); out, t = [], lo + int(rng.integers(0, GAP))
    while t + LENGTH + 30 <= hi and len(out) < per_video:
        out.append((t, t + LENGTH, 'L' if rng.random() < 0.5 else 'R')); t += LENGTH + GAP + int(rng.integers(0, GAP))
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', required=True); p.add_argument('--pose2d', required=True); p.add_argument('--out', required=True)
    p.add_argument('--coco-cfg', required=True); p.add_argument('--coco-ckpt', required=True)
    p.add_argument('--videos', type=lambda s: s.split(','), required=True)
    p.add_argument('--groups', type=lambda s: s.split(','), default=list(GROUPS)); p.add_argument('--per-video', type=int, default=2)
    a = p.parse_args()
    import cv2
    from mmpose.apis import init_model, inference_topdown
    model = init_model(a.coco_cfg, a.coco_ckpt, device='cpu')
    os.makedirs(a.out, exist_ok=True)
    for key in a.videos:
        out = f'{a.out}/{key}.npz'
        if os.path.exists(out): continue
        subj, cam, ex = key.split('_', 2)
        z = np.load(f'{a.pose2d}/{key}.npz'); pick, boxes = z['pick'], z['box']
        J = np.array(json.load(open(f'{a.root}/train/{subj}/joints3d_25/{ex}.json'))['joints3d_25'], float)[:, FIT3D_TO_H36M]
        camj = json.load(open(f'{a.root}/train/{subj}/camera_parameters/{cam}/{ex}.json'))
        ann = json.load(open(f'{a.root}/train/{subj}/rep_ann.json'))[ex]
        lo, hi = int(np.searchsorted(pick, ann[0])), int(np.searchsorted(pick, ann[-1]))
        jobs = {}  # 30 fps index -> [(painted H36M joint, parent)]
        eps = []
        for g in a.groups:
            for s, e, side in episodes(key, g, lo, hi, a.per_video):
                hj, par, coco = GROUPS[g][side]; eps.append(dict(group=g, s=s, e=e, side=side, coco=coco, h36m=hj))
                for t in range(s, e): jobs.setdefault(t, []).append((hj, par))
        want = {int(pick[t]): t for t in jobs}
        cap = cv2.VideoCapture(f'{a.root}/train/{subj}/videos/{cam}/{ex}.mp4'); f, res = 0, {}
        while want:
            ok, img = cap.read()
            if not ok: break
            t = want.pop(f, None); f += 1
            if t is None: continue
            for hj, par in jobs[t]:
                c, q = project(J[pick[t]][[hj, par]], camj)
                cv2.circle(img, (int(round(c[0])), int(round(c[1]))), int(round(0.6 * np.linalg.norm(c - q))), (128, 128, 128), -1)
            r = inference_topdown(model, img, bboxes=boxes[t][None], bbox_format='xyxy')[0].pred_instances
            res[t] = np.concatenate([r.keypoints[0], r.keypoint_scores[0][:, None]], 1)
        frames = np.array(sorted(res)); kp = np.stack([res[t] for t in frames]).astype(np.float32) if len(frames) else np.zeros((0, 17, 3), np.float32)
        np.savez(out + '.tmp.npz', frames=frames, coco=kp, episodes=json.dumps(eps)); os.replace(out + '.tmp.npz', out)
        print(key, len(eps), 'episodes', len(frames), 'frames', flush=True)
    sha = lambda f: hashlib.sha256(open(f, 'rb').read()).hexdigest()
    outs = sorted(str(q) for q in __import__('pathlib').Path(a.out).glob('*.npz'))
    json.dump(dict(argv=sys.argv, python=sys.executable, host=socket.gethostname(), finished=time.strftime('%Y-%m-%d %H:%M:%S'),
                   code={__file__: sha(__file__)}, checkpoint={a.coco_ckpt: sha(a.coco_ckpt)}, config={a.coco_cfg: sha(a.coco_cfg)},
                   pose2d={f'{a.pose2d}/{k}.npz': sha(f'{a.pose2d}/{k}.npz') for k in a.videos},
                   outputs={o: sha(o) for o in outs}, note='Fit3D-derived per-frame 2D: delete after the rgb-eval run'),
              open(os.path.join(os.path.dirname(a.out.rstrip('/')), 'manifest.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
