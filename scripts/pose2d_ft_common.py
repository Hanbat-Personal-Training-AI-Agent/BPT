"""Torch/cv2 side of track C (fine-tune + eval). Pure maths lives in pose_feedback/body/pose2d_data.py."""

import os
import sys
from pathlib import Path

import cv2
import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'scripts'))

from pose_feedback.body.pose2d_data import INPUT_H, INPUT_W, crop_affine, decode_simcc  # noqa: E402

MEAN = np.array([123.675, 116.28, 103.53], np.float32)
STD = np.array([58.395, 57.12, 57.375], np.float32)
DEVICE = 'cuda' if torch.cuda.is_available() else 'mps' if torch.backends.mps.is_available() else 'cpu'


def load_model(variant='coco17', checkpoint=None, device=DEVICE):
    """mmpose RTMPose (variant names from rtmpose_s_coreml_common.VARIANTS), optional fine-tuned state_dict."""
    os.environ['BPT_RTMPOSE_VARIANT'] = variant
    import importlib
    import rtmpose_s_coreml_common as common
    common = importlib.reload(common)
    model = common.load_rtmpose_model(device='cpu')
    if checkpoint:
        state = torch.load(checkpoint, map_location='cpu', weights_only=False)
        model.load_state_dict(state.get('state_dict', state))
    return model.to(device).eval()


def forward(model, batch):
    """batch float [B,3,256,192] normalised -> (simcc_x [B,K,384], simcc_y [B,K,512])."""
    return model.head(model.extract_feat(batch))


def to_tensor(crops_rgb):
    """list of uint8 RGB [256,192,3] -> normalised [B,3,256,192]."""
    x = (np.stack(crops_rgb).astype(np.float32) - MEAN) / STD
    return torch.from_numpy(x.transpose(0, 3, 1, 2).copy())


def warp(image_rgb, matrix):
    return cv2.warpAffine(image_rgb, matrix, (INPUT_W, INPUT_H), flags=cv2.INTER_LINEAR)


def stretch(image_rgb):
    """The app's current camera path: whole frame resized to 192x256 ignoring aspect."""
    return cv2.resize(image_rgb, (INPUT_W, INPUT_H), interpolation=cv2.INTER_LINEAR)


@torch.no_grad()
def predict(model, crops_rgb, batch=64, device=DEVICE):
    """-> keypoints [N,K,2] in input pixels, confidence [N,K] (app decode)."""
    kps, confs = [], []
    for i in range(0, len(crops_rgb), batch):
        sx, sy = forward(model, to_tensor(crops_rgb[i:i + batch]).to(device))
        sx, sy = sx.float().cpu().numpy(), sy.float().cpu().numpy()
        for a, b in zip(sx, sy):
            k, c = decode_simcc(a, b)
            kps.append(k)
            confs.append(c)
    return np.array(kps), np.array(confs)


def crop_box(image_rgb, center, scale):
    m = crop_affine(center, scale)
    return warp(image_rgb, m), m
