"""Body fit from the four calibration photos (runs in the GPU container).

1. Person box per photo from the manifest's RTMPose COCO-17 keypoints (no detector, no Sapiens2).
2. SAM 3D Body on each photo alone (box + the photo's intrinsics when known) -> MHR mesh.
3. MHR -> SMPL with MHR's official converter, one shared β across the four photos
   (convert_mhr2smpl(single_identity=True, is_tracking=False)).
4. Joint refinement: shared β + per-photo pose / orientation / translation against the 2D
   keypoints, reprojected with each photo's own camera. No masks, no silhouette loss (v1).
5. β projected onto the user's height (body.project_to_height), then poses refined with β fixed.
6. Result: β, rest-pose H36M joints and bone lengths, per-photo reprojection error, height error.

Coordinates: SAM 3D Body's vertices + pred_cam_t are in an OpenCV camera frame (x right, y down,
z forward, metres; see sam3d_body.py's keypoint projection), and the converter keeps that frame.
"""
import contextlib
import os
import sys
import time

import cv2
import numpy as np
import torch

import body
from worker import FitFailed, build_result

WEIGHTS = "/weights"
SAM3DB_DIR = f"{WEIGHTS}/sam-3d-body-dinov3"
SMPL_NPZ = f"{WEIGHTS}/smpl/smpl_neutral_h36m.npz"
MHR_CONVERSION = "/opt/MHR/tools/mhr_smpl_conversion"

# smplx SMPL joints 0-23, then extra vertices: 24 nose, 25 right eye, 26 left eye, 27 right ear, 28 left ear.
COCO_FROM_SMPL = [24, 26, 25, 28, 27, 16, 17, 18, 19, 20, 21, 1, 2, 4, 5, 7, 8]
# SMPL hip joints sit lower and further in than COCO's; trust them less.
COCO_WEIGHTS = np.array([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0.5, 0.5, 1, 1, 1, 1], dtype=np.float32)
MIN_CONFIDENCE = 0.3
REQUIRED = list(range(5, 17))  # shoulders .. ankles


class Fitter:
    """Models load once per container."""

    def __init__(self, device="cuda"):
        # Any value disables sam-3d-body's pymomentum MHR (it segfaults loading the FBX rig with
        # pymomentum-cpu 0.1.114); it then uses the TorchScript MHR shipped with the checkpoint.
        os.environ["MOMENTUM_ENABLED"] = "0"
        sys.path.insert(0, "/opt/sam-3d-body")
        from sam_3d_body import SAM3DBodyEstimator, load_sam_3d_body
        import smplx

        self.device = device
        model, cfg = load_sam_3d_body(f"{SAM3DB_DIR}/model.ckpt", device=device,
                                      mhr_path=f"{SAM3DB_DIR}/assets/mhr_model.pt")
        self.estimator = SAM3DBodyEstimator(sam_3d_body_model=model, model_cfg=cfg, human_detector=None,
                                            human_segmentor=None, fov_estimator=None)
        arrays = dict(np.load(SMPL_NPZ))
        self.v_template, self.shapedirs = arrays["v_template"], arrays["shapedirs"]
        self.j_regressor_h36m = arrays["J_regressor_h36m"]
        pkl = "/tmp/smpl_neutral.pkl"  # smplx reads SMPL from a chumpy-free pickle
        if not os.path.exists(pkl):
            import pickle
            with open(pkl, "wb") as fh:
                pickle.dump({k: v for k, v in arrays.items() if k != "J_regressor_h36m"}, fh)
        self.smpl = smplx.SMPL(model_path=pkl, num_betas=10).to(device)
        self.converter = None  # built lazily: it reads ./assets relative to its folder

    def _conversion(self):
        """MHR's converter; call it inside contextlib.chdir(MHR_CONVERSION), it reads ./assets lazily."""
        if self.converter is None:
            sys.path.insert(0, MHR_CONVERSION)
            from conversion import Conversion
            self.converter = Conversion(mhr_model=MhrTopology(self.estimator.faces),
                                        smpl_model=self.smpl, method="pytorch")
        return self.converter

    def __call__(self, manifest, photos):
        timing, started = {}, time.perf_counter()
        torch.cuda.reset_peak_memory_stats()
        views = manifest["views"]
        images, keypoints, cameras = {}, {}, {}
        for view in views:
            label = view["label"]
            image = cv2.imdecode(np.frombuffer(photos[label], np.uint8), cv2.IMREAD_COLOR)
            images[label] = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            kp = np.asarray(view["keypoints"], dtype=np.float32)
            if (kp[REQUIRED, 2] >= MIN_CONFIDENCE).sum() < 8:
                raise FitFailed("low_keypoint_confidence")
            keypoints[label] = kp
            cameras[label] = view.get("intrinsics", manifest.get("intrinsics"))

        # 2. SAM 3D Body per photo
        sam_outputs, focal = {}, {}
        for label, image in images.items():
            h, w = image.shape[:2]
            cam = cameras[label]
            known = cam and cam.get("fx", 0) > 0
            cam_int = None
            if known:
                cam_int = torch.tensor([[[cam["fx"], 0, cam["cx"]], [0, cam["fy"], cam["cy"]], [0, 0, 1]]],
                                       dtype=torch.float32)
            out = self.estimator.process_one_image(image, bboxes=person_box(keypoints[label], w, h)[None],
                                                   cam_int=cam_int, inference_type="body")
            if len(out) != 1:
                raise FitFailed("person_not_found")
            sam_outputs[label] = out[0]
            focal[label] = (cam["fx"], cam["fy"], cam["cx"], cam["cy"]) if known else (
                float(out[0]["focal_length"]), float(out[0]["focal_length"]), w / 2, h / 2)
        timing["sam3d_body_s"] = time.perf_counter() - started

        # 3. MHR -> SMPL, one shared identity
        t = time.perf_counter()
        labels = [v["label"] for v in views]
        mhr_vertices = np.stack([100.0 * (sam_outputs[l]["pred_vertices"] + sam_outputs[l]["pred_cam_t"][None])
                                 for l in labels])  # cm, as the converter expects
        with contextlib.chdir(MHR_CONVERSION):
            converted = self._conversion().convert_mhr2smpl(mhr_vertices=mhr_vertices, single_identity=True,
                                                            is_tracking=False, return_smpl_parameters=True)
        init = {k: torch.as_tensor(np.asarray(v.detach().cpu() if torch.is_tensor(v) else v),
                                   dtype=torch.float32, device=self.device)
                for k, v in converted.result_parameters.items()}
        timing["mhr_to_smpl_s"] = time.perf_counter() - t

        # 4-5. refine against the 2D keypoints, put the height in, refine poses again
        t = time.perf_counter()
        target = torch.tensor(np.stack([keypoints[l] for l in labels]), device=self.device)
        K = torch.tensor([[[f[0], 0, f[2]], [0, f[1], f[3]], [0, 0, 1]] for f in (focal[l] for l in labels)],
                         dtype=torch.float32, device=self.device)
        scale = torch.tensor([box_height(keypoints[l]) for l in labels], device=self.device)
        betas = init["betas"][:1].clone().requires_grad_(True)
        orient = init["global_orient"].clone().requires_grad_(True)
        pose = init["body_pose"].clone().requires_grad_(True)
        transl = init["transl"].clone().requires_grad_(True)
        pose0 = init["body_pose"].clone()

        def loss_fn(beta):
            out = self.smpl(betas=beta.expand(len(labels), -1), global_orient=orient, body_pose=pose, transl=transl)
            uv = project(out.joints[:, COCO_FROM_SMPL], K)
            w = target[..., 2] * (target[..., 2] >= MIN_CONFIDENCE) * torch.as_tensor(COCO_WEIGHTS, device=self.device)
            err = ((uv - target[..., :2]).norm(dim=-1) / scale[:, None])
            data = (w * torch.nn.functional.huber_loss(err, torch.zeros_like(err), delta=0.05, reduction="none")).sum()
            return data + 1e-3 * ((pose - pose0) ** 2).sum() + 1e-3 * (beta ** 2).sum(), uv

        optimise([betas, orient, pose, transl], lambda: loss_fn(betas)[0], steps=300)
        beta_h = body.project_to_height(self.v_template, self.shapedirs, betas.detach().cpu().numpy()[0],
                                        manifest["userHeightCm"] / 100)
        fixed = torch.tensor(beta_h[None], dtype=torch.float32, device=self.device)
        optimise([orient, pose, transl], lambda: loss_fn(fixed)[0], steps=200)
        timing["refine_s"] = time.perf_counter() - t

        with torch.no_grad():
            _, uv = loss_fn(fixed)
        if not torch.isfinite(uv).all():
            raise FitFailed("fit_diverged")
        reprojection = {}
        for i, label in enumerate(labels):
            ok = target[i, :, 2] >= MIN_CONFIDENCE
            reprojection[label] = round(float((uv[i, ok] - target[i, ok, :2]).norm(dim=-1).mean()), 2)
            if reprojection[label] > 0.15 * float(scale[i]):
                raise FitFailed("fit_diverged")

        rest = body.shaped_vertices(self.v_template, self.shapedirs, beta_h)
        per_view = {label: {"body_pose": pose[i].tolist(), "global_orient": orient[i].tolist(),
                            "transl": transl[i].tolist(),
                            "focalUsed": {"fx": focal[label][0], "fy": focal[label][1],
                                          "cx": focal[label][2], "cy": focal[label][3]},
                            # the converter compares SMPL and mapped MHR vertices in metres
                            "mhrToSmplVertexErrorCm": round(100 * float(np.asarray(converted.result_errors)[i].mean()), 3)
                            if converted.result_errors is not None else None}
                    for i, label in enumerate(labels)}
        timing["total_s"] = time.perf_counter() - started
        result = build_result(manifest, beta=beta_h, joints=body.h36m_joints(rest, self.j_regressor_h36m),
                              mesh_height_m=body.height_m(rest), reprojection_px=reprojection, per_view=per_view)
        result["debug"]["timing"] = {k: round(v, 2) for k, v in timing.items()}
        result["debug"]["gpu"] = {"name": torch.cuda.get_device_name(),
                                  "peakAllocatedGiB": round(torch.cuda.max_memory_allocated() / 2**30, 2)}
        result["debug"]["betaBeforeHeight"] = betas.detach().cpu().numpy()[0].tolist()
        return result


class MhrTopology:
    """Stands in for mhr.MHR in Conversion: MHR -> SMPL from vertices reads only the mesh faces
    (conversion.py _compute_target_vertices), and loading the real MHR needs pymomentum (see above).
    """

    def __init__(self, faces):
        self.character = type("Character", (), {"mesh": type("Mesh", (), {"faces": np.asarray(faces)})})

    def to(self, device):
        return self


def person_box(kp, width, height):
    """xyxy around the confident keypoints, padded; the head and feet extend past their joints."""
    ok = kp[:, 2] >= MIN_CONFIDENCE
    x0, y0 = kp[ok, :2].min(0)
    x1, y1 = kp[ok, :2].max(0)
    h = y1 - y0
    box = np.array([x0 - 0.15 * h, y0 - 0.2 * h, x1 + 0.15 * h, y1 + 0.1 * h], dtype=np.float32)
    return np.clip(box, 0, [width - 1, height - 1, width - 1, height - 1]).astype(np.float32)


def box_height(kp):
    ok = kp[:, 2] >= MIN_CONFIDENCE
    return float(kp[ok, 1].max() - kp[ok, 1].min())


def project(points, K):
    """OpenCV pinhole: (B, N, 3) camera-frame points -> (B, N, 2) pixels."""
    p = torch.einsum("bij,bnj->bni", K, points)
    return p[..., :2] / p[..., 2:].clamp(min=1e-6)


def optimise(params, closure, steps):
    opt = torch.optim.Adam(params, lr=0.01)
    for _ in range(steps):
        opt.zero_grad()
        loss = closure()
        loss.backward()
        opt.step()
