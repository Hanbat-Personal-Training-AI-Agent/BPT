import argparse
import json
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from pose_feedback.body.motionagformer_adapter import (
    coco17_to_motionagformer_h36m17,
    normalize_motionagformer_sequence,
)
from pose_feedback.body.motionagformer_buffer import MotionAGFormerWindowBuilder


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare MotionAGFormer input windows from RTMPose JSONL.")
    parser.add_argument("--input-jsonl", default="assets/smoke/vedio_1_rtmpose_2d_keypoints.jsonl")
    parser.add_argument("--output-npz", default="assets/smoke/vedio_1_motionagformer_input_debug.npz")
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--window-size", type=int, default=243)
    parser.add_argument("--lookahead", type=int, nargs="+", default=[3, 5])
    return parser.parse_args()


def main():
    args = parse_args()
    rows = load_rows(Path(args.input_jsonl))
    if not rows:
        print({"input_jsonl": args.input_jsonl, "frames": 0, "reason": "no rows"})
        return 0

    raw_coco17, image_width, image_height, frame_numbers = rows_to_coco17(rows)
    converted, confidences = coco17_to_motionagformer_h36m17(raw_coco17)
    normalized_xy = normalize_motionagformer_sequence(converted, confidences, image_width, image_height)
    normalized = np.concatenate([normalized_xy, confidences[..., None]], axis=-1).astype("float32")

    builder = MotionAGFormerWindowBuilder(window_size=args.window_size)
    full_windows, full_indices = build_full_windows(builder, normalized)
    outputs = {
        "raw_coco17": raw_coco17.astype("float32"),
        "converted_h36m_2d": converted.astype("float32"),
        "normalized_h36m_2d": normalized.astype("float32"),
        "confidences": confidences.astype("float32"),
        "full_centered_windows": full_windows,
        "full_centered_frame_indices": frame_numbers[full_indices],
        "image_width": np.asarray([image_width], dtype="float32"),
        "image_height": np.asarray([image_height], dtype="float32"),
        "fps": np.asarray([args.fps], dtype="float32"),
    }
    latency = {
        "full": {
            "frames": builder.latency_frames("full"),
            "seconds": builder.latency_seconds(args.fps, "full"),
        },
    }
    for lookahead in args.lookahead:
        windows, indices = build_lookahead_windows(builder, normalized, lookahead)
        outputs[f"lookahead{lookahead}_windows"] = windows
        outputs[f"lookahead{lookahead}_frame_indices"] = frame_numbers[indices]
        latency[f"lookahead{lookahead}"] = {
            "frames": builder.latency_frames("lookahead", lookahead=lookahead),
            "seconds": builder.latency_seconds(args.fps, "lookahead", lookahead=lookahead),
        }

    output = Path(args.output_npz)
    output.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(output, **outputs)
    print(
        {
            "input_jsonl": args.input_jsonl,
            "frames": len(raw_coco17),
            "output_npz": str(output),
            "shapes": {key: value.shape for key, value in outputs.items() if hasattr(value, "shape")},
            "latency": latency,
        },
    )
    return 0


def load_rows(path):
    if not path.exists():
        raise FileNotFoundError(f"RTMPose JSONL not found: {path}")
    rows = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def rows_to_coco17(rows):
    valid = [row for row in rows if row.get("keypoints_coco17") is not None]
    if not valid:
        raise ValueError("No rows contain keypoints_coco17")
    first = valid[0]
    image_width = float(first["image_width"])
    image_height = float(first["image_height"])
    frame_numbers = []
    keypoints = []
    last = None
    for row in rows:
        if row.get("keypoints_coco17") is not None:
            last = np.asarray(row["keypoints_coco17"], dtype="float32")
        if last is None:
            continue
        frame_numbers.append(int(row["frame_idx"]))
        keypoints.append(last.copy())
    return np.stack(keypoints, axis=0), image_width, image_height, np.asarray(frame_numbers, dtype=int)


def build_full_windows(builder, sequence):
    windows = []
    indices = []
    for idx in range(len(sequence)):
        window, frame_indices = builder.build_full_centered(sequence, idx)
        windows.append(window)
        indices.append(frame_indices)
    return np.stack(windows).astype("float32"), np.stack(indices).astype(int)


def build_lookahead_windows(builder, sequence, lookahead):
    windows = []
    indices = []
    for idx in range(len(sequence)):
        window, frame_indices = builder.build_lookahead_padded(sequence, idx, lookahead)
        windows.append(window)
        indices.append(frame_indices)
    return np.stack(windows).astype("float32"), np.stack(indices).astype(int)


if __name__ == "__main__":
    raise SystemExit(main())
