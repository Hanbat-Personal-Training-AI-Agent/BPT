"""Modal wiring for the calibration server (app `bpt-calibration`).

    modal deploy modal_app.py                      # from server/calibration_modal/
    modal run modal_app.py::download_weights       # once: SAM 3D Body checkpoint into bpt-weights

Secrets (never in code): `bpt-r2` (R2_ENDPOINT_URL, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY),
`bpt-jwt` (JWT_SECRET = the backend's base64 jwt.secret), `bpt-hf` (HF_TOKEN with SAM 3D Body access).
Volume `bpt-weights`: /smpl/smpl_neutral_h36m.npz (prepare_weights.py) and /sam-3d-body-dinov3/.
"""
import os
from pathlib import Path

import modal

app = modal.App("bpt-calibration")
secrets = [modal.Secret.from_name("bpt-r2"), modal.Secret.from_name("bpt-jwt")]
weights = modal.Volume.from_name("bpt-weights", create_if_missing=True)
SOURCES = ("body", "checks", "service", "storage", "worker", "deep_analysis", "deep_metrics", "deep_worker")

image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install("fastapi[standard]==0.143.0", "boto3==1.43.110", "pyjwt==2.15.1", "pillow==12.3.0", "numpy==2.5.3")
    .add_local_python_source(*SOURCES)
)

SAM3DB_COMMIT = "b5c765a0d89d789985e186d396315e7590887b94"
MHR_COMMIT = "d96fafa33bbf018647c70c3525e91f53e79d2a14"
fit_image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("git", "libgl1", "libglib2.0-0")
    .pip_install("torch==2.8.0", "torchvision==0.23.0")
    .pip_install(
        # sam-3d-body INSTALL.md, minus training- and visualisation-only packages
        "pytorch-lightning", "opencv-python-headless", "yacs", "scikit-image", "einops", "timm", "dill", "roma",
        "omegaconf", "trimesh", "braceexpand", "huggingface_hub",
        # DINOv3 backbone code (torch.hub) requirements
        "termcolor", "ftfy", "regex", "submitit", "torchmetrics",
        # MHR -> SMPL converter
        "pymomentum-cpu==0.1.114.post0", "smplx==0.1.28", "scikit-learn", "tqdm",
        "boto3==1.43.110", "pyjwt==2.15.1", "pillow==12.3.0",
    )
    .run_commands(
        f"git clone https://github.com/facebookresearch/sam-3d-body /opt/sam-3d-body"
        f" && git -C /opt/sam-3d-body checkout {SAM3DB_COMMIT}",
        f"git clone https://github.com/facebookresearch/MHR /opt/MHR && git -C /opt/MHR checkout {MHR_COMMIT}",
        # MHR from the pinned commit (the PyPI wheel lags), editable so MHR.from_files finds /opt/MHR/assets.
        "pip install -e /opt/MHR",
        "cd /opt/MHR && python -m mhr.download_assets",
        # The DINOv3 backbone code comes through torch.hub; fetch it at build, not on every cold start.
        "python -c \"import torch; torch.hub.load('facebookresearch/dinov3', 'dinov3_vith16plus', "
        "source='github', pretrained=False, trust_repo=True)\"",
    )
    .add_local_python_source(*SOURCES, "fitting")
)


# Idle seconds a fitting container stays up (Modal's default is 60). Long enough that a container
# warmed when the capture screen opens (~65 s cold start) is still there when the upload lands.
SCALEDOWN_SECONDS = 180

# Inside the container this file is /root/modal_app.py: .parent never fails where parents[2] raises.
REPO = Path(__file__).resolve().parent.parent.parent
# scripts/deep_analysis/modal_bench.py와 같은 고정 버전. 빌드/배포 시에만 설치한다.
deep_weights = modal.Volume.from_name("bpt-gvhmr", create_if_missing=True)
deep_image = (
    modal.Image.debian_slim(python_version="3.10")
    .apt_install("git", "ffmpeg", "libgl1", "libglib2.0-0", "build-essential", "fonts-noto-cjk")
    .pip_install("torch==2.3.0", "torchvision==0.18.0", index_url="https://download.pytorch.org/whl/cu121")
    .pip_install(
        "timm==0.9.12", "lightning==2.3.0", "hydra-core==1.3", "hydra-zen", "hydra_colorlog", "rich",
        "numpy==1.23.5", "matplotlib", "setuptools>=68.0", "tensorboardX", "opencv-python-headless==4.11.0.86",
        "ffmpeg-python", "scikit-image", "termcolor", "einops", "imageio==2.34.1", "av==13.0.0", "joblib",
        "trimesh", "smplx", "wis3d", "pycolmap", "ultralytics==8.2.42", "cython", "lapx", "boto3", "pyjwt", "pillow", "fastapi",
        "https://dl.fbaipublicfiles.com/pytorch3d/packaging/wheels/py310_cu121_pyt230/pytorch3d-0.7.6-cp310-cp310-linux_x86_64.whl",
    )
    .pip_install("cython_bbox")
    .run_commands(
        "git clone https://github.com/zju3dv/GVHMR /opt/GVHMR && git -C /opt/GVHMR checkout ee960bb6e2ea2d381aa97f08e9b71ef320b624b1",
        "pip install -e /opt/GVHMR --no-deps",
        "rm -rf /opt/GVHMR/inputs/checkpoints && mkdir -p /opt/GVHMR/inputs && ln -s /vol /opt/GVHMR/inputs/checkpoints",
    )
    .env({"BPT_GVHMR_ROOT": "/opt/GVHMR", "BPT_SMPL_H36M_NPZ": "/vol/smpl_neutral_h36m.npz"})
    .add_local_file(REPO / "scripts/deep_analysis/gvhmr_runner.py",
                    "/root/gvhmr_runner.py", copy=True)
    .add_local_file(Path(__file__).with_name("deep_rules.csv"), "/root/deep_rules.csv", copy=True)
    .add_local_python_source("checks", "storage", "deep_analysis", "deep_metrics", "deep_worker")
)

# 팀 코칭 카탈로그가 들어오면 이미지에 같은 계약으로 포함한다.
catalog = REPO / "docs/coaching/fault_catalog.csv"
if catalog.is_file():
    deep_image = deep_image.add_local_file(catalog, "/docs/coaching/fault_catalog.csv", copy=True)


@app.function(image=deep_image, gpu="L4", volumes={"/vol": deep_weights}, secrets=secrets[:1],
              timeout=15 * 60, min_containers=0, scaledown_window=60, retries=0)
def deep_analysis_job(job):
    import deep_worker
    import storage

    bucket = storage.Bucket.from_env()
    state = storage.BucketState(bucket)
    required = ["gvhmr/gvhmr_siga24_release.ckpt", "hmr2/epoch=10-step=25000.ckpt",
                "vitpose/vitpose-h-multi-coco.pth", "yolo/yolov8x.pt", "smpl_neutral_h36m.npz",
                "body_models/smplx/SMPLX_NEUTRAL.npz", "body_models/smpl/SMPL_NEUTRAL.pkl"]
    if any(not (Path("/vol") / name).is_file() for name in required):
        state.put(f"deep-job:{job['jobId']}", job | {"status": "failed", "error": "weights_missing"})
        return
    return deep_worker.run(job, bucket, state)


@app.function(image=fit_image, gpu="L4", volumes={"/weights": weights}, secrets=secrets[:1],
              timeout=15 * 60, min_containers=0, scaledown_window=SCALEDOWN_SECONDS, retries=0)
def fit_body(job):
    import fitting
    import storage
    import worker

    global _fitter
    if "_fitter" not in globals():  # models load once per container
        _fitter = fitting.Fitter()
    if job.get("warmup"):  # POST /v1/calibrations/warmup: the models are loaded, nothing else to do
        return {"warm": True}
    bucket = storage.Bucket.from_env()
    return worker.run(job, bucket, storage.BucketState(bucket), _fitter)


@app.function(image=modal.Image.debian_slim(python_version="3.12").pip_install("huggingface_hub"), volumes={"/weights": weights},
              secrets=[modal.Secret.from_name("bpt-hf")], timeout=30 * 60)
def download_weights(repo: str = "facebook/sam-3d-body-dinov3"):
    from huggingface_hub import snapshot_download

    target = "/weights/" + repo.split("/")[1]
    snapshot_download(repo, local_dir=target, token=os.environ["HF_TOKEN"],
                      allow_patterns=["model.ckpt", "model_config.yaml", "assets/mhr_model.pt"])
    weights.commit()
    return {os.path.relpath(os.path.join(d, f), target): os.path.getsize(os.path.join(d, f))
            for d, _, files in os.walk(target) for f in files if ".cache" not in d}


@app.function(image=image, secrets=secrets)
@modal.concurrent(max_inputs=50)
@modal.asgi_app()
def api():
    import service
    import storage

    bucket = storage.Bucket.from_env()
    return service.create_app(
        bucket=bucket,
        state=storage.BucketState(bucket),
        spawn=fit_body.spawn,
        jwt_secret=os.environ["JWT_SECRET"],
        call_failure=call_failure,
        warm=lambda: fit_body.spawn({"warmup": True}),
        deep_spawn=deep_analysis_job.spawn,
    )


def call_failure(call_id):
    """Error code for a fit_body call that ended without the worker writing it down, else None."""
    try:
        modal.FunctionCall.from_id(call_id).get(timeout=0)
    except modal.exception.FunctionTimeoutError:
        return "timeout"
    except (TimeoutError, modal.exception.TimeoutError):  # builtin TimeoutError: still queued or running
        return None
    except Exception:  # the worker raised (it already wrote its code) or its container died
        return "internal_error"
    return None
