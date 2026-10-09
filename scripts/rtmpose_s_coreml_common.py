"""Shared RTMPose-s forward-only helpers for Core ML feasibility scripts."""

from contextlib import contextmanager
import os
from pathlib import Path

import numpy as np
import torch


ROOT = Path(__file__).resolve().parents[1]
# Same RTMPose-s network, two checkpoints. Pick with BPT_RTMPOSE_VARIANT=coco17|halpe26
# (default coco17). Halpe26 = COCO17 order for 0-16, then head, neck, hip, toes, heels.
VARIANTS = {
    "coco17": (
        "rtmpose-s_8xb256-420e_coco-256x192.py",
        "rtmpose-s_coco.pth",
        "rtmpose_s",
    ),
    "halpe26": (
        "rtmpose-s_8xb1024-700e_body8-halpe26-256x192.py",
        "rtmpose-s_simcc-body7_pt-body7-halpe26_700e-256x192-7f134165_20230605.pth",
        "rtmpose_s_halpe26",
    ),
}
VARIANT = os.environ.get("BPT_RTMPOSE_VARIANT", "coco17")
_config_name, _checkpoint_name, _stem = VARIANTS[VARIANT]
CONFIG_PATH = ROOT / "models/rtmpose" / _config_name
CHECKPOINT_PATH = ROOT / "models/rtmpose" / _checkpoint_name
VIDEO_PATH = ROOT / "assets/smoke/vedio_1.mp4"
COREML_DIR = ROOT / "assets/coreml"
# Trace and mlpackage are per variant so a cached trace never leaks into the other model.
TRACE_PATH = COREML_DIR / f"{_stem}_forward_trace.pt"
FORWARD_INPUT_NPY = COREML_DIR / "rtmpose_s_forward_input.npy"
COREML_MODEL_PATH = COREML_DIR / f"{_stem}_forward.mlpackage"
INPUT_NAME = "input_image"
OUTPUT_NAMES = ("simcc_x", "simcc_y")
INPUT_SIZE_WH = (192, 256)
INPUT_SHAPE = (1, 3, 256, 192)


class RTMPoseForwardOnly(torch.nn.Module):
    """Wrap MMPose TopdownPoseEstimator as a one-tensor neural forward.

    The wrapper excludes image loading, bbox/crop/affine preprocessing,
    normalization, SimCC decode, and inverse coordinate mapping.
    """

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_image):
        features = self.model.extract_feat(input_image)
        return self.model.head(features)


def setup_runtime_environment():
    os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/bpt_mplconfig")
    os.environ.setdefault("XDG_CACHE_HOME", "/private/tmp/bpt_xdg_cache")
    Path(os.environ["MPLCONFIGDIR"]).mkdir(parents=True, exist_ok=True)
    Path(os.environ["XDG_CACHE_HOME"]).mkdir(parents=True, exist_ok=True)


@contextmanager
def legacy_torch_load():
    original_load = torch.load

    def load_with_legacy_default(*args, **kwargs):
        kwargs.setdefault("weights_only", False)
        return original_load(*args, **kwargs)

    torch.load = load_with_legacy_default
    try:
        yield
    finally:
        torch.load = original_load


def load_rtmpose_model(device="cpu"):
    setup_runtime_environment()
    from mmpose.apis import init_model

    with legacy_torch_load():
        model = init_model(str(CONFIG_PATH), str(CHECKPOINT_PATH), device=device)
    model.eval()
    return model


def read_first_video_frame(video_path=VIDEO_PATH):
    import cv2

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Could not open video: {video_path}")
    ok, frame = cap.read()
    cap.release()
    if not ok or frame is None:
        raise RuntimeError(f"Could not read first frame from: {video_path}")
    return frame


def prepare_input_tensor_from_frame(frame_bgr):
    import cv2

    width, height = INPUT_SIZE_WH
    resized = cv2.resize(frame_bgr, (width, height), interpolation=cv2.INTER_LINEAR)
    rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB).astype("float32")
    mean = np.asarray([123.675, 116.28, 103.53], dtype="float32")
    std = np.asarray([58.395, 57.12, 57.375], dtype="float32")
    normalized = (rgb - mean) / std
    return normalized.transpose(2, 0, 1)[None, ...].astype("float32")


def load_or_create_forward_input():
    if FORWARD_INPUT_NPY.exists():
        tensor = np.load(FORWARD_INPUT_NPY).astype("float32")
    else:
        tensor = prepare_input_tensor_from_frame(read_first_video_frame())
    if tuple(tensor.shape) != INPUT_SHAPE:
        raise ValueError(f"Expected input shape {INPUT_SHAPE}, got {tensor.shape}")
    return tensor


def save_forward_input(tensor):
    COREML_DIR.mkdir(parents=True, exist_ok=True)
    np.save(FORWARD_INPUT_NPY, np.asarray(tensor, dtype="float32"))


def forward_output_dict(outputs):
    if isinstance(outputs, torch.Tensor):
        outputs = (outputs,)
    if not isinstance(outputs, (tuple, list)):
        raise TypeError(f"Unsupported output type: {type(outputs)!r}")
    names = OUTPUT_NAMES if len(outputs) == 2 else tuple(f"raw_output_{i}" for i in range(len(outputs)))
    return {name: output for name, output in zip(names, outputs)}


def numpy_output_dict(outputs):
    result = {}
    for name, value in forward_output_dict(outputs).items():
        detach = getattr(value, "detach", None)
        if detach is not None:
            value = detach().cpu().numpy()
        result[name] = np.asarray(value, dtype="float32")
    return result


def shape_dict(values):
    return {name: list(value.shape) for name, value in values.items()}


def stats_dict(values):
    return {
        name: {
            "min": float(value.min()),
            "max": float(value.max()),
            "mean": float(value.mean()),
        }
        for name, value in values.items()
    }


def trace_forward_model(model, input_tensor):
    wrapper = RTMPoseForwardOnly(model).eval()
    tensor = torch.from_numpy(np.asarray(input_tensor, dtype="float32"))
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, tensor, check_trace=False)
    return traced
