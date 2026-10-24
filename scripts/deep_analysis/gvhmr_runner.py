"""GVHMR single-video runner: static camera (demo `-s`), per-stage time and peak VRAM, H36M-17 joints out.

Licences (read before using the output anywhere):
  - GVHMR code + weights (https://github.com/zju3dv/GVHMR, commit ee960bb, LICENSE): educational, research and
    non-profit use only; modifications must be open source; no commercial use. BPT uses it for the capstone only.
  - SMPL-X (https://smpl-x.is.tue.mpg.de) and SMPL (https://smpl.is.tue.mpg.de) body models: non-commercial,
    registration required, no redistribution. Never commit the model files; point GVHMR at a local copy.
  - J_regressor_h36m: SPIN data (BPT copy with the left/right legs fixed, server/calibration_modal/prepare_weights.py).

Same stages as tools/demo/demo.py with --static_cam: YOLOv8x track -> ViTPose-H COCO17 -> HMR2 ViT features ->
GVHMR network. Differences, all outside the network:
  - the input is first re-encoded to 30 fps (GVHMR assumes 30 fps), rotated by the phone's rotation metadata
    (neither OpenCV nor GVHMR's reader applies it), so portrait iPhone clips arrive upright;
  - crops go to the GPU batch by batch (demo puts the whole video's crops on the GPU);
  - half=True stores the ViTPose-H / HMR2 Linear weights in fp16 (computed in fp32, see `_half`) so they fit a
    3 GB GPU. Default: plain fp32 as upstream.

usage (env bpt-gvhmr):  python gvhmr_runner.py VIDEO OUT_DIR [--f-mm 26] [--half]
Writes OUT_DIR/result.npz (see `save`) and OUT_DIR/timing.json.
"""
import argparse, json, os, sys, threading, time
from pathlib import Path
import numpy as np

GVHMR_ROOT = Path(os.environ.get('BPT_GVHMR_ROOT', Path.home() / 'gvhmr/GVHMR'))
H36M_NPZ = Path(os.environ.get('BPT_SMPL_H36M_NPZ', Path.home() / 'bpt-smpl/smpl/smpl_neutral_h36m.npz'))
SMPL_PKL = Path(os.environ.get('BPT_SMPL_PKL', GVHMR_ROOT / 'inputs/checkpoints/body_models/smpl/SMPL_NEUTRAL.pkl'))
FPS = 30
# GVHMR static_conf_logits order (gvhmr_pipeline.py): L ankle, L foot, R ankle, R foot, L wrist, R wrist
CONTACT_NAMES = ['left_ankle', 'left_foot', 'right_ankle', 'right_foot', 'left_wrist', 'right_wrist']


class RunError(Exception):
    """Video rejected: `code` is the API error code (docs/deep_analysis/api.md)."""
    def __init__(self, code, msg):
        super().__init__(msg); self.code = code


def _imports():
    os.chdir(GVHMR_ROOT)  # GVHMR loads checkpoints and configs from relative paths
    sys.path.insert(0, str(GVHMR_ROOT))
    import torch  # noqa: F401


class VramPeak:
    """Peak device memory used (all processes) minus the level at start, sampled every 20 ms."""
    def __init__(self):
        import torch
        self.t = torch; free, total = torch.cuda.mem_get_info(); self.base = total - free; self.peak = self.base
        self.stop = False; self.th = threading.Thread(target=self._run, daemon=True); self.th.start()

    def _run(self):
        while not self.stop:
            free, total = self.t.cuda.mem_get_info(); self.peak = max(self.peak, total - free); time.sleep(0.02)

    def done(self):
        self.stop = True; self.th.join(); return (self.peak - self.base) / 2**20


def normalize_video(src, dst, max_seconds=None):
    """Re-encode to upright 30 fps H.264 by nearest-time frame pick. Returns (n_frames, w, h, src_fps, rotation)."""
    import cv2, av
    cap = cv2.VideoCapture(str(src))
    # iPhone portrait = landscape pixels + a display rotation. OpenCV 4.11 reports it but does not apply it,
    # and GVHMR's own readers ignore it (the person would arrive lying on the side), so rotate here.
    cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 0)
    deg = int(round(cap.get(cv2.CAP_PROP_ORIENTATION_META) or 0))
    rot = {90: cv2.ROTATE_90_CLOCKWISE, 180: cv2.ROTATE_180, 270: cv2.ROTATE_90_COUNTERCLOCKWISE,
           -90: cv2.ROTATE_90_COUNTERCLOCKWISE}.get(deg)
    fps = cap.get(cv2.CAP_PROP_FPS) or FPS
    n_src = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if n_src <= 0: raise RunError('video_unreadable', f'cannot read frames from {src}')
    if max_seconds and n_src / fps > max_seconds:
        raise RunError('video_too_long', f'{n_src / fps:.1f} s > {max_seconds} s')
    pick = set(np.round(np.arange(0, n_src, fps / FPS)).astype(int).tolist())
    out = av.open(str(dst), 'w'); st = None; i = n = 0
    while True:
        ok, f = cap.read()
        if not ok: break
        if i in pick:
            if rot is not None: f = cv2.rotate(f, rot)
            if st is None:
                h, w = f.shape[:2]; st = out.add_stream('libx264', rate=FPS)
                st.width, st.height, st.pix_fmt = w - w % 2, h - h % 2, 'yuv420p'; st.options = {'crf': '17'}
            fr = av.VideoFrame.from_ndarray(f[:st.height, :st.width], format='bgr24')
            for p in st.encode(fr): out.mux(p)
            n += 1
        i += 1
    if st is not None:
        for p in st.encode(): out.mux(p)
    out.close(); cap.release()
    if n == 0: raise RunError('video_unreadable', f'no frames decoded from {src}')
    return n, st.width, st.height, fps, deg


def phone_f_mm(path):
    """35 mm-equivalent focal length from iPhone QuickTime metadata, or None (most re-encoded clips drop it)."""
    import av
    with av.open(str(path)) as c:
        for md in [c.metadata] + [s.metadata for s in c.streams]:
            for k, v in md.items():
                if 'focal_length.35mm_equivalent' in k:
                    try: return float(v)
                    except ValueError: pass
    return None


def track(video, n):
    """Longest YOLOv8x track (as the demo), plus how many other people are tracked for >= 30 % of the video."""
    import torch
    from hmr4d.utils.preproc import Tracker
    from hmr4d.utils.geo.hmr_cam import get_bbx_xys_from_xyxy
    from hmr4d.utils.seq_utils import frame_id_to_mask, rearrange_by_mask, get_frame_id_list_from_mask, \
        linear_interpolate_frame_ids
    from hmr4d.utils.net_utils import moving_average_smooth
    tr = Tracker(); hist = tr.track(str(video))
    ids, boxes, order = tr.sort_track_length(hist, str(video))
    if not order: raise RunError('no_person', 'no person detected')
    frames = torch.tensor(ids[order[0]])
    if len(frames) < 0.5 * n: raise RunError('no_person', f'person visible in {len(frames)}/{n} frames (< 50 %)')
    others = sum(len(ids[k]) >= 0.3 * n for k in order[1:])
    mask = frame_id_to_mask(frames, n)
    xyxy = rearrange_by_mask(torch.tensor(boxes[order[0]]), mask)
    xyxy = linear_interpolate_frame_ids(xyxy, get_frame_id_list_from_mask(~mask))
    xyxy = moving_average_smooth(moving_average_smooth(xyxy, window_size=5, dim=0), window_size=5, dim=0)
    del tr; torch.cuda.empty_cache()
    return xyxy.float(), get_bbx_xys_from_xyxy(xyxy, base_enlarge=1.2).float(), others, len(frames)


def _half(module, half):
    """Store nn.Linear weights in fp16 (ViT-H is ~99 % Linear) and upcast each one to fp32 just for its own call:
    fits a 3 GB GPU and still computes in fp32 (Pascal GPUs run fp16 math at 1/64 speed). Only the weight
    rounding to fp16 differs from the full fp32 run."""
    import torch
    if not half: return module

    def up(m, _):
        m.weight.data = m.weight.data.float()

    def down(m, _, __):
        m.weight.data = m.weight.data.half()

    for m in module.modules():
        if isinstance(m, torch.nn.Linear):
            m.weight.data = m.weight.data.half()
            m.register_forward_pre_hook(up); m.register_forward_hook(down)
    return module


def vitpose(video, bbx_xys, half):
    """Same as hmr4d VitPoseExtractor.extract (flip test, mmpose UDP decode), crops moved per batch."""
    import torch
    from hmr4d.utils.preproc.vitpose import get_batch, flip_heatmap_coco17, keypoints_from_heatmaps, build_model
    pose = _half(build_model('ViTPose_huge_coco_256x192', 'inputs/checkpoints/vitpose/vitpose-h-multi-coco.pth'), half)
    pose.cuda().eval()
    imgs, bbx = get_batch(str(video), bbx_xys, img_ds=0.5)
    out = []
    with torch.no_grad():
        for j in range(0, len(imgs), 16):
            b = imgs[j:j + 16, :, :, 32:224].cuda()
            hm, hf = pose(torch.cat([b, b.flip(3)])).chunk(2)
            hm = ((hm + flip_heatmap_coco17(hf)) * 0.5).cpu().numpy()
            xs = bbx[j:j + 16]
            scale = (torch.cat((xs[:, [2]] * 24 / 32, xs[:, [2]]), 1) / 200).numpy()
            p, c = keypoints_from_heatmaps(heatmaps=hm, center=xs[:, :2].numpy(), scale=scale, use_udp=True)
            out.append(torch.from_numpy(np.concatenate((p, c), -1)))
    del pose; torch.cuda.empty_cache()
    return torch.cat(out).float()


def features(video, bbx_xys, half):
    """Same as hmr4d Extractor.extract_video_features, crops moved per batch."""
    import torch
    from hmr4d.network.hmr2 import load_hmr2
    from hmr4d.utils.preproc.vitfeat_extractor import get_batch
    m = _half(load_hmr2().eval(), half).cuda()
    imgs, _ = get_batch(str(video), bbx_xys, img_ds=0.5)
    out = []
    with torch.no_grad():
        for j in range(0, len(imgs), 16):
            out.append(m({'img': imgs[j:j + 16].cuda()}).float().cpu())
    del m; torch.cuda.empty_cache()
    return torch.cat(out)


def network(n, w, h, bbx_xys, kp2d, feats, f_mm):
    import torch, hydra
    from hydra import initialize_config_module, compose
    from hmr4d.configs import register_store_gvhmr
    from hmr4d.model.gvhmr.gvhmr_pl_demo import DemoPL  # noqa: F401  registers model/gvhmr/gvhmr_pl_demo
    from hmr4d.utils.geo.hmr_cam import estimate_K, create_camera_sensor
    from hmr4d.utils.geo_transform import compute_cam_angvel
    from hmr4d.utils.net_utils import detach_to_cpu
    with initialize_config_module(version_base='1.3', config_module='hmr4d.configs'):
        register_store_gvhmr()
        cfg = compose(config_name='demo', overrides=['video_name=bpt', 'static_cam=True', 'verbose=False',
                                                     'use_dpvo=False'] + ([f'f_mm={f_mm}'] if f_mm else []))
    K = (create_camera_sensor(w, h, f_mm)[2] if f_mm else estimate_K(w, h)).repeat(n, 1, 1)
    data = {'length': torch.tensor(n), 'bbx_xys': bbx_xys, 'kp2d': kp2d, 'K_fullimg': K,
            'cam_angvel': compute_cam_angvel(torch.eye(3).repeat(n, 1, 1)), 'f_imgseq': feats}
    model = hydra.utils.instantiate(cfg.model, _recursive_=False)
    model.load_pretrained_model(cfg.ckpt_path)
    model = model.eval().cuda()
    pred = detach_to_cpu(model.predict(data, static_cam=True))
    del model; torch.cuda.empty_cache()
    return pred, K[0].numpy()


class H36M:
    """SMPL-X params -> SMPL vertices (GVHMR smplx2smpl_sparse, a fixed vertex map) -> J_regressor_h36m (17).

    beta (10, the calibration server's SMPL β from the body scan) = pose only: GVHMR's per-frame betas are
    dropped and its global_orient / body_pose drive GVHMR's own SMPL-X with the SMPL-X β whose rest mesh (mapped to
    SMPL topology) best matches the user's SMPL rest mesh (linear least squares, translation free). Staying in
    SMPL-X keeps the skeleton GVHMR's rotations were predicted for; driving SMPL with them instead moved the
    elbow angle by ~4° on Exercise3D P2 (docs/results/deep_analysis_app.md). The pelvis stays where GVHMR put it,
    scaled by user height / GVHMR body height about the camera (world) origin, so the bigger or smaller body still
    projects onto the same image (monocular depth scales with body size)."""
    def __init__(self, device='cuda', beta=None):
        import torch
        from hmr4d.utils.smplx_utils import make_smplx
        self.t = torch; self.dev = device
        self.smplx = make_smplx('supermotion').to(device)
        self.x2s = torch.load(GVHMR_ROOT / 'hmr4d/utils/body_model/smplx2smpl_sparse.pt').to(device)
        self.reg = torch.from_numpy(np.load(H36M_NPZ)['J_regressor_h36m']).float().to(device)
        self.beta = None if beta is None else self.smplx_beta(beta)

    def smplx_beta(self, beta):
        import smplx
        t = self.t
        with t.no_grad():
            target = smplx.SMPL(model_path=str(SMPL_PKL), num_betas=10)(
                betas=t.tensor([beta], dtype=t.float32)).vertices[0].to(self.dev)        # (6890, 3) rest pose
            bm = self.smplx.bm; n = bm.shapedirs.shape[-1]
            vt = self.x2s @ bm.v_template
            dirs = t.stack([self.x2s @ bm.shapedirs[:, :, i] for i in range(n)], -1)    # (6890, 3, n)
            dirs = dirs - dirs.mean(0); rhs = (target - target.mean(0)) - (vt - vt.mean(0))
            sol = t.linalg.lstsq(dirs.reshape(-1, n).cpu(), rhs.reshape(-1, 1).cpu()).solution
        return sol.T.to(self.dev)                                                        # (1, n)

    def _height(self, betas):
        rest = {'betas': betas, 'global_orient': self.t.zeros(1, 3, device=self.dev),
                'body_pose': self.t.zeros(1, 63, device=self.dev), 'transl': self.t.zeros(1, 3, device=self.dev)}
        v = self.x2s @ self.smplx(**rest).vertices[0]
        return float(v[:, 1].max() - v[:, 1].min())

    def _joints(self, params, batch):
        out = []
        n = len(params['body_pose'])
        for s in range(0, n, batch):
            p = {k: v[s:s + batch].to(self.dev) for k, v in params.items()}
            v = self.smplx(**p).vertices                                   # (B, 10475, 3)
            v = self.t.stack([self.x2s @ x for x in v])                    # (B, 6890, 3) SMPL topology
            out.append(self.t.einsum('jv,bvc->bjc', self.reg, v).cpu())    # (B, 17, 3)
        return self.t.cat(out).numpy().astype(np.float32)

    def __call__(self, params, batch=512, fixed=True):
        with self.t.no_grad():
            own = self._joints(params, batch)
            if not fixed or self.beta is None: return own
            j = self._joints(params | {'betas': self.beta.cpu().expand(len(own), -1)}, batch)
            ratio = self._height(self.beta) / self._height(params['betas'].mean(0, keepdim=True).to(self.dev))
        return j - j[:, :1] + own[:, :1] * ratio


def save(path, pred, K, xyxy, kp2d, j_cam, j_world, meta, j_world_own=None):
    """result.npz: h36m17_cam (N,17,3) metres, OpenCV camera (x right, y down, z forward), order = BPT H36M-17
    (0 pelvis, 1-3 right leg, 4-6 left leg, 7 spine, 8 thorax, 9 neck/nose, 10 head, 11-13 left arm,
    14-16 right arm); h36m17_world (N,17,3) metres, GVHMR gravity-aligned world (y up, starts facing +z);
    smplx_{incam,global}_{global_orient,body_pose,betas,transl} axis-angle (GVHMR SMPL-X, 10 betas — NOT the
    calibration server's SMPL beta); with a calibrated beta, h36m17_* use that body shape (H36M class, meta
    body_shape='calibration') and h36m17_world_gvhmr_beta keeps GVHMR's own-shape joints; contact_prob (N,6) sigmoid(static_conf_logits), order CONTACT_NAMES;
    vitpose_coco17 (N,17,3) px + conf; bbx_xyxy (N,4); K (3,3) the intrinsics GVHMR used."""
    import torch
    z = dict(h36m17_cam=j_cam, h36m17_world=j_world, K=K, bbx_xyxy=xyxy.numpy(), vitpose_coco17=kp2d.numpy())
    if j_world_own is not None: z['h36m17_world_gvhmr_beta'] = j_world_own
    for frame in ('incam', 'global'):
        for k, v in pred[f'smpl_params_{frame}'].items(): z[f'smplx_{frame}_{k}'] = v.numpy()
    logits = pred['net_outputs'].get('static_conf_logits')
    if logits is not None: z['contact_prob'] = torch.sigmoid(logits[0]).numpy()
    np.savez_compressed(path, **z, meta=json.dumps(meta))


def run(video, out_dir, f_mm=None, half=False, max_seconds=None, keep_video=False, beta=None):
    """beta: the user's calibrated SMPL β (10) -> h36m17_* use it (pose-only GVHMR); None -> GVHMR's own β."""
    _imports()
    import torch
    out_dir = Path(out_dir); out_dir.mkdir(parents=True, exist_ok=True)
    T, V = {}, {}

    def stage(name, fn, *a):
        torch.cuda.synchronize(); vp = VramPeak(); t = time.perf_counter()
        print(f"[stage] {name}", flush=True); r = fn(*a)
        torch.cuda.synchronize(); T[name] = round(time.perf_counter() - t, 3); V[name] = round(vp.done(), 1)
        return r

    vid, cache = out_dir / 'input_30fps.mp4', out_dir / 'preproc.pt'
    if cache.exists():  # debugging re-runs only: timings of the cached stages are not measured
        c = torch.load(cache); n, w, h, src_fps, deg, xyxy, bbx_xys, others, seen, kp2d, feats = c
    else:
        n, w, h, src_fps, deg = stage('normalize', normalize_video, video, vid, max_seconds)
        if n < 30: raise RunError('video_too_short', f'{n} frames at 30 fps (< 1 s)')
        xyxy, bbx_xys, others, seen = stage('track', track, vid, n)
        kp2d = stage('vitpose', vitpose, vid, bbx_xys, half)
        feats = stage('features', features, vid, bbx_xys, half)
        torch.save((n, w, h, src_fps, deg, xyxy, bbx_xys, others, seen, kp2d, feats), cache)
    pred, K = stage('network', network, n, w, h, bbx_xys, kp2d, feats, f_mm)

    def post():
        j = H36M(beta=beta); jc = j(pred['smpl_params_incam']); jw = j(pred['smpl_params_global'])
        own = j(pred['smpl_params_global'], fixed=False) if beta is not None else None
        del j; torch.cuda.empty_cache(); return jc, jw, own
    j_cam, j_world, j_world_own = stage('postprocess', post)
    meta = dict(frames=n, width=w, height=h, src_fps=src_fps, rotation_deg=deg, fps=FPS, f_mm=f_mm, half=half, other_people=others,
                person_frames=seen, gpu=torch.cuda.get_device_name(), timing_s=T, vram_peak_mib=V,
                body_shape='calibration' if beta is not None else 'gvhmr', gvhmr_commit='ee960bb', regressor='smplx2smpl_sparse + J_regressor_h36m (BPT L/R-fixed)')
    save(out_dir / 'result.npz', pred, K, xyxy, kp2d, j_cam, j_world, meta, j_world_own)
    json.dump(meta, open(out_dir / 'timing.json', 'w'), indent=1)
    if not keep_video:
        vid.unlink(missing_ok=True); cache.unlink()
    return meta


def main():
    p = argparse.ArgumentParser()
    p.add_argument('video'); p.add_argument('out_dir')
    p.add_argument('--f-mm', default=None, help="full-frame equivalent focal length (mm), or 'auto' = phone metadata")
    p.add_argument('--half', action='store_true', help='fp16-stored ViTPose-H / HMR2 Linear weights (3 GB GPU)')
    p.add_argument('--keep-video', action='store_true')
    p.add_argument('--beta', help='JSON list of 10 calibrated SMPL betas (pose-only GVHMR)')
    a = p.parse_args()
    f_mm = phone_f_mm(a.video) if a.f_mm == 'auto' else (float(a.f_mm) if a.f_mm else None)
    try:
        print(json.dumps(run(Path(a.video).resolve(), Path(a.out_dir).resolve(), f_mm, a.half,
                             keep_video=a.keep_video, beta=json.loads(a.beta) if a.beta else None), indent=1))
    except RunError as e:
        print(json.dumps({'error': e.code, 'message': str(e)})); sys.exit(2)


if __name__ == '__main__':
    main()
