"""Modal wiring for the calibration server (app `bpt-calibration`).

    modal deploy modal_app.py                      # from server/calibration_modal/
    modal run modal_app.py::download_weights       # once: SAM 3D Body checkpoint into bpt-weights

Secrets (never in code): `bpt-r2` (R2_ENDPOINT_URL, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY),
`bpt-jwt` (JWT_SECRET = the backend's base64 jwt.secret), `bpt-hf` (HF_TOKEN with SAM 3D Body access).
Volume `bpt-weights`: /smpl/smpl_neutral_h36m.npz (prepare_weights.py) and /sam-3d-body-dinov3/.
"""
import os

import modal

app = modal.App("bpt-calibration")
secrets = [modal.Secret.from_name("bpt-r2"), modal.Secret.from_name("bpt-jwt")]
weights = modal.Volume.from_name("bpt-weights", create_if_missing=True)
SOURCES = ("body", "checks", "service", "storage", "worker")

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


@app.function(image=fit_image, gpu="L4", volumes={"/weights": weights}, secrets=secrets[:1],
              timeout=15 * 60, min_containers=0)
def fit_body(job):
    import fitting
    import storage
    import worker

    global _fitter
    if "_fitter" not in globals():  # models load once per container
        _fitter = fitting.Fitter()
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
    )
