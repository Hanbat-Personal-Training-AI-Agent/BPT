"""Fixed, observation-based stress schedules; no labels, GT, or image export."""
from dataclasses import replace
import time
from pathlib import Path

import numpy as np

from .data import normalize_observations

BLOCKS = ((100, 103), (130, 140), (170, 194), (215, 245))
LIMIT = 270


def target_joints(observations):
    """Choose the less confident side using the calibration prefix only."""
    k = observations.keypoints[21:81]
    if observations.exercise == "squat":
        coco = [15 if k[:, 15, 2].mean() < k[:, 16, 2].mean() else 16]
    else:
        left = k[:, 9, 2].mean() < k[:, 10, 2].mean()
        coco = [9 if left else 10]
        if observations.exercise == "pushup":
            coco.append(15 if left else 16)
    mapping = {9: 13, 10: 16, 15: 6, 16: 3}
    return coco, [mapping[j] for j in coco]


def damage_schedule(observations):
    _, h36m = target_joints(observations)
    mask = np.zeros((len(observations.raw), 17), bool)
    for start, end in BLOCKS:
        mask[start:end, h36m] = True
    return mask


def corrupt_keypoints(observations):
    """Low-confidence held detections plus one confident erroneous jump."""
    k = observations.keypoints.copy()
    joints, h36m = target_joints(observations)
    damage = damage_schedule(observations)
    for start, end in BLOCKS:
        k[start:end, joints, :2] = k[start - 1, joints, :2]
        k[start:end, joints, 2] = .05
    if len(k) > 255:
        height = observations.boxes[255, 3] - observations.boxes[255, 1]
        k[255, joints, 0] += .25 * height
        k[255, joints, 2] = .95
        damage[255, h36m] = True
    return k, damage


def observation_with_keypoints(observations, keypoints, raw=None, limit=None):
    x, crops = normalize_observations(keypoints, observations.image_size)
    n = min(limit or len(x), len(x))
    return replace(observations, keypoints=keypoints[:n], normalized=x[:n], crops=crops[:n],
                   raw=(observations.raw if raw is None else raw)[:n], pick=observations.pick[:n],
                   boxes=observations.boxes[:n])


def infer_changed_xs(model, x, original_x, original_raw, *, limit=LIMIT, batch=8):
    """Recompute every output window affected by changed REAL 2D input.

    Exact L5 windows use the full input past limit, avoiding tail-edge mismatch.
    Unchanged windows reuse the original immutable cache.
    """
    import torch
    n = min(limit, len(x))
    windows = np.clip(np.arange(n)[:, None] + 5 - 26 + np.arange(27)[None], 0, len(x) - 1)
    changed = np.any(x != original_x, axis=(1, 2))
    selected = np.flatnonzero(changed[windows].any(1))
    raw = original_raw.copy()
    began = time.perf_counter()
    with torch.inference_mode():
        for offset in range(0, len(selected), batch):
            rows = selected[offset:offset + batch]
            raw[rows] = model(torch.from_numpy(x[windows[rows]])).cpu().numpy()[:, 21]
    return raw, dict(recomputed_windows=len(selected), reused_windows=n - len(selected),
                     seconds=time.perf_counter() - began, output_row=21, lookahead=5)


def infer_rgb_masks(observations, model, dataset_root):
    """Mask RGB in memory on Home, run actual RTMPose on cached observed boxes.

    The clean detector boxes are fixed to isolate RTMPose robustness. This is
    not a detector-occlusion experiment. Never writes or displays an image.
    """
    import cv2
    from mmpose.apis import inference_topdown
    o = observations
    joints, _ = target_joints(o)
    k = o.keypoints.copy()
    damaged = damage_schedule(o)
    frames = np.flatnonzero(damaged.any(1))
    by_frame = {int(o.pick[t]): int(t) for t in frames}
    video = Path(dataset_root) / "train" / o.subject / "videos" / o.camera / (o.exercise + ".mp4")
    cap = cv2.VideoCapture(str(video))
    assert cap.isOpened(), video
    index, processed, began = 0, 0, time.perf_counter()
    try:
        while index <= max(by_frame):
            ok, image = cap.read()
            assert ok, (video, index)
            if index in by_frame:
                t = by_frame[index]
                # Placement is an experimental intervention from observed 2D;
                # it is not estimated from mocap or camera ground truth.
                box = o.boxes[t]
                radius = max(8, round(.08 * (box[3] - box[1])))
                for j in joints:
                    x, y = np.round(o.keypoints[t, j, :2]).astype(int)
                    x1, x2 = max(0, x - radius), min(image.shape[1], x + radius + 1)
                    y1, y2 = max(0, y - radius), min(image.shape[0], y + radius + 1)
                    image[y1:y2, x1:x2] = 127
                result = inference_topdown(model, image, bboxes=box[None], bbox_format="xyxy")[0].pred_instances
                k[t] = np.concatenate([result.keypoints[0], result.keypoint_scores[0, :, None]], 1)
                processed += 1
            index += 1
    finally:
        cap.release()
    return k, damaged, dict(masked_rgb_frames=processed, seconds=time.perf_counter() - began,
                            video=str(video), detector="original observed cached box; fixed",
                            mask="gray rectangle radius .08 observed box height, at observed target 2D",
                            images_saved=0)
