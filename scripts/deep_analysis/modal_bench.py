"""GVHMR on Modal L4: speed, peak VRAM and cold start for gvhmr_eval.md §1-4 (app `bpt-gvhmr-bench`).

GVHMR (https://github.com/zju3dv/GVHMR, commit ee960bb): educational / research / non-profit use only, no
commercial use. SMPL-X / SMPL: non-commercial, no redistribution; they live only in the private Volume.
Only public CC BY clips are sent here (never Fit3D / Exercise3D).

    modal run modal_bench.py::download_weights        # once: GVHMR checkpoints from the HF mirror, sha256-checked
    modal volume put bpt-gvhmr ~/models/smplx/SMPLX_NEUTRAL.npz /body_models/smplx/SMPLX_NEUTRAL.npz
    modal volume put bpt-gvhmr ~/models/smpl/SMPL_NEUTRAL.pkl   /body_models/smpl/SMPL_NEUTRAL.pkl
    modal volume put bpt-gvhmr ~/bpt-smpl/smpl/smpl_neutral_h36m.npz /smpl_neutral_h36m.npz
    modal run modal_bench.py --clips ~/gvhmr/testvids/bench_30s.mp4,~/gvhmr/testvids/bench_60s.mp4
(run from scripts/deep_analysis/)
"""
import json, os, time
from pathlib import Path

import modal

_T_IMPORT = time.time()  # container start (module import) — cold start = client wall − in-container time
app = modal.App("bpt-gvhmr-bench")
vol = modal.Volume.from_name("bpt-gvhmr", create_if_missing=True)
GVHMR_COMMIT = "ee960bb6e2ea2d381aa97f08e9b71ef320b624b1"
# camenduru/GVHMR (Google Drive mirror of the official release), LFS sha256 checked on Home
CKPTS = {
    "gvhmr/gvhmr_siga24_release.ckpt": "4fae7da2",
    "hmr2/epoch=10-step=25000.ckpt": "2dcf7963",
    "vitpose/vitpose-h-multi-coco.pth": "50e33f40",
    "yolo/yolov8x.pt": "c4d5a3f0",
}
REQS = [  # GVHMR requirements.txt minus chumpy (does not build, unused by the demo path) and dev tools
    "timm==0.9.12", "lightning==2.3.0", "hydra-core==1.3", "hydra-zen", "hydra_colorlog", "rich", "numpy==1.23.5",
    "matplotlib", "setuptools>=68.0", "tensorboardX", "opencv-python-headless", "ffmpeg-python", "scikit-image",
    "termcolor", "einops", "imageio==2.34.1", "av==13.0.0", "joblib", "trimesh", "smplx", "wis3d", "pycolmap",
    "ultralytics==8.2.42", "cython", "lapx",
    "https://dl.fbaipublicfiles.com/pytorch3d/packaging/wheels/py310_cu121_pyt230/pytorch3d-0.7.6-cp310-cp310-linux_x86_64.whl",
]
image = (
    modal.Image.debian_slim(python_version="3.10")
    .apt_install("git", "ffmpeg", "libgl1", "libglib2.0-0", "build-essential")
    .pip_install("torch==2.3.0", "torchvision==0.18.0", index_url="https://download.pytorch.org/whl/cu121")
    .pip_install(*REQS)
    .pip_install("cython_bbox")
    .run_commands(f"git clone https://github.com/zju3dv/GVHMR /opt/GVHMR && git -C /opt/GVHMR checkout {GVHMR_COMMIT}",
                  "pip install -e /opt/GVHMR --no-deps",
                  "rm -rf /opt/GVHMR/inputs/checkpoints && mkdir -p /opt/GVHMR/inputs && ln -s /vol /opt/GVHMR/inputs/checkpoints")
    .env({"BPT_GVHMR_ROOT": "/opt/GVHMR", "BPT_SMPL_H36M_NPZ": "/vol/smpl_neutral_h36m.npz"})
    .add_local_python_source("gvhmr_runner")
)


@app.function(image=modal.Image.debian_slim().pip_install("huggingface_hub"), volumes={"/vol": vol}, timeout=30 * 60)
def download_weights():
    import hashlib
    from huggingface_hub import hf_hub_download
    out = {}
    for rel, sha in CKPTS.items():
        p = hf_hub_download("camenduru/GVHMR", rel, local_dir="/vol")
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for b in iter(lambda: f.read(1 << 24), b""): h.update(b)
        assert h.hexdigest().startswith(sha), (rel, h.hexdigest())
        out[rel] = os.path.getsize(p)
    vol.commit()
    return out


@app.function(image=image, gpu="L4", volumes={"/vol": vol}, timeout=15 * 60, scaledown_window=60, retries=0)
def bench(video: bytes, name: str):
    t0 = time.time()
    import gvhmr_runner as g
    src, out = Path("/tmp") / name, Path("/tmp/out") / name
    src.write_bytes(video)
    meta = g.run(src, out, half=False)
    t1 = time.time()
    return dict(meta=meta, container_age_s=round(t0 - _T_IMPORT, 2), in_container_s=round(t1 - t0, 2))


@app.local_entrypoint()
def main(clips: str):
    rows = []
    for i, c in enumerate(clips.split(",") * 2):  # each clip twice: the first call is cold, the rest warm
        p = Path(c).expanduser(); t = time.time()
        r = bench.remote(p.read_bytes(), p.name)
        r.update(clip=p.name, call=i, client_wall_s=round(time.time() - t, 2))
        rows.append(r); print(json.dumps(r), flush=True)
    Path("modal_bench.json").write_text(json.dumps(rows, indent=1))
