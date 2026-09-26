"""Run RTMDet-tiny (COCO) on a video and visualize the causal person crop.

Left: frame with raw person detections (gray), accepted top-1 box (green) and
the running-union crop fed to RTMPose (red). Right: that crop warped to the
RTMPose-s input size (192x256), padded with black outside the image.

Setup (bpt-ai env):
    mim download mmdet --config rtmdet_tiny_8xb32-300e_coco --dest models/rtmdet
"""
import argparse
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import torch
from mmdet.apis import inference_detector, init_detector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pose_feedback.body.person_crop_tracker import PersonCropTracker  # noqa: E402

MODEL_DIR = ROOT / "models" / "rtmdet"
POSE_INPUT_WH = (192, 256)


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--video", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--config", default=str(MODEL_DIR / "rtmdet_tiny_8xb32-300e_coco.py"))
    p.add_argument("--checkpoint", default=str(next(MODEL_DIR.glob("rtmdet_tiny_*.pth"), "")))
    p.add_argument("--device", default="cpu")
    p.add_argument("--score-thr", type=float, default=0.5)
    p.add_argument("--min-iou", type=float, default=0.5)
    p.add_argument("--save-dets", help="write per-frame person detections (x1,y1,x2,y2,score) as JSON")
    return p.parse_args()


def warp_crop(frame, crop):
    x1, y1, x2, y2 = crop
    w, h = POSE_INPUT_WH
    src = np.float32([[x1, y1], [x2, y1], [x1, y2]])
    dst = np.float32([[0, 0], [w, 0], [0, h]])
    return cv2.warpAffine(frame, cv2.getAffineTransform(src, dst), (w, h), borderValue=(0, 0, 0))


def main():
    args = parse_args()
    # Official OpenMMLab checkpoints are legacy pickles; PyTorch 2.6+ defaults to weights_only=True.
    original_load = torch.load
    torch.load = lambda *a, **k: original_load(*a, **{"weights_only": False, **k})
    try:
        model = init_detector(args.config, args.checkpoint, device=args.device)
    finally:
        torch.load = original_load

    cap = cv2.VideoCapture(args.video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    fw, fh = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    panel_w = fh * POSE_INPUT_WH[0] // POSE_INPUT_WH[1]
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(args.output, cv2.VideoWriter_fourcc(*"mp4v"), fps, (fw + panel_w, fh))

    tracker = PersonCropTracker(score_thr=args.score_thr, min_iou=args.min_iou)
    frames = accepted_count = 0
    all_dets = []
    infer_ms = 0.0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        t0 = time.perf_counter()
        pred = inference_detector(model, frame).pred_instances
        infer_ms += (time.perf_counter() - t0) * 1000
        keep = pred.labels == 0  # COCO class 0 = person
        dets = [(*b, s) for b, s in zip(pred.bboxes[keep].tolist(), pred.scores[keep].tolist()) if s >= 0.1]
        all_dets.append(dets)
        accepted, crop = tracker.update(dets)
        accepted_count += accepted is not None

        vis = frame.copy()
        for x1, y1, x2, y2, s in dets:
            cv2.rectangle(vis, (int(x1), int(y1)), (int(x2), int(y2)), (160, 160, 160), 1)
            cv2.putText(vis, f"{s:.2f}", (int(x1), int(y2) + 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (160, 160, 160), 1)
        if accepted is not None:
            x1, y1, x2, y2 = map(int, accepted)
            cv2.rectangle(vis, (x1, y1), (x2, y2), (0, 255, 0), 2)
        if crop is not None:
            x1, y1, x2, y2 = map(int, crop)
            cv2.rectangle(vis, (x1, y1), (x2, y2), (0, 0, 255), 2)
            panel = cv2.resize(warp_crop(frame, crop), (panel_w, fh))
        else:
            panel = np.zeros((fh, panel_w, 3), np.uint8)
        status = "accepted" if accepted is not None else "rejected"
        cv2.putText(vis, f"RTMDet-tiny  frame {frames}  thr {args.score_thr}  {status}", (10, 28),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
        cv2.putText(vis, "gray: raw  green: accepted  red: crop", (10, 56),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
        writer.write(np.hstack([vis, panel]))
        frames += 1

    cap.release()
    writer.release()
    if args.save_dets:
        Path(args.save_dets).write_text(json.dumps(all_dets))
    print(f"frames={frames} accepted_frames={accepted_count} final_crop={tuple(round(v) for v in tracker.crop())} "
          f"mean_infer_ms={infer_ms / max(frames, 1):.1f} output={args.output}")


if __name__ == "__main__":
    main()
