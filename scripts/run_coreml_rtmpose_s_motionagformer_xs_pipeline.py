"""Run macOS Python Core ML RTMPose-s -> MotionAGFormer-XS prototype.

Core ML scope:
* RTMPose-s neural-network forward only.
* MotionAGFormer-XS lifter.

Python scope:
* video decode/render
* full-image bbox and top-down affine preprocessing
* normalization
* SimCC decode and inverse affine
* COCO17 -> H36M17 conversion
* MotionAGFormer lookahead window construction
"""

import argparse
import csv
import json
import statistics
import sys
import time
from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from pose_feedback.body.motionagformer_adapter import (  # noqa: E402
    coco17_to_motionagformer_h36m17,
    normalize_motionagformer_2d,
)
from pose_feedback.body.motionagformer_buffer import MotionAGFormerWindowBuilder  # noqa: E402


RTMPOSE_INPUT_NAME = "input_image"
RTMPOSE_OUTPUT_X = "simcc_x"
RTMPOSE_OUTPUT_Y = "simcc_y"
MOTION_INPUT_NAME = "input_2d_sequence"
MOTION_OUTPUT_NAME = "pred_3d_sequence"
RTMPOSE_INPUT_SIZE = (192, 256)
MOTION_WINDOW_SIZE = 27
SIMCC_SPLIT_RATIO = 2.0
MEAN_RGB = np.asarray([123.675, 116.28, 103.53], dtype="float32")
STD_RGB = np.asarray([58.395, 57.12, 57.375], dtype="float32")

COCO17_NAMES = [
    "nose",
    "left_eye",
    "right_eye",
    "left_ear",
    "right_ear",
    "left_shoulder",
    "right_shoulder",
    "left_elbow",
    "right_elbow",
    "left_wrist",
    "right_wrist",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
]

COCO_SKELETON = [
    (5, 6),
    (5, 7),
    (7, 9),
    (6, 8),
    (8, 10),
    (5, 11),
    (6, 12),
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
    (0, 1),
    (0, 2),
    (1, 3),
    (2, 4),
]

H36M_SKELETON = [
    (0, 1),
    (1, 2),
    (2, 3),
    (0, 4),
    (4, 5),
    (5, 6),
    (0, 7),
    (7, 8),
    (8, 9),
    (9, 10),
    (8, 11),
    (11, 12),
    (12, 13),
    (8, 14),
    (14, 15),
    (15, 16),
]


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", default="assets/smoke/vedio_1.mp4")
    parser.add_argument("--rtmpose-coreml", default="assets/coreml/rtmpose_s_forward.mlpackage")
    parser.add_argument("--motionagformer-coreml", default="assets/coreml/motionagformer_xs.mlpackage")
    parser.add_argument("--output-jsonl", default="assets/coreml_pipeline/jsonl/vedio_1_coreml_rtmpose_s_2d.jsonl")
    parser.add_argument("--output-npz", default="assets/coreml_pipeline/npz/vedio_1_coreml_motionagformer_xs_3d.npz")
    parser.add_argument("--output-benchmark", default="assets/coreml_pipeline/logs/vedio_1_coreml_e2e_benchmark.json")
    parser.add_argument("--output-csv", default="assets/coreml_pipeline/csv/vedio_1_coreml_e2e_benchmark.csv")
    parser.add_argument("--output-video", default="assets/coreml_pipeline/videos/vedio_1_coreml_2d_3d_side_by_side.mp4")
    parser.add_argument("--max-frames", type=int, default=240)
    parser.add_argument("--lookahead", type=int, default=5)
    return parser.parse_args()


def main():
    args = parse_args()
    import coremltools as ct

    make_output_dirs(args)

    load_start = time.perf_counter()
    rtmpose_model = ct.models.MLModel(str(args.rtmpose_coreml), compute_units=ct.ComputeUnit.ALL)
    rtmpose_load_ms = elapsed_ms(load_start)
    load_start = time.perf_counter()
    motion_model = ct.models.MLModel(str(args.motionagformer_coreml), compute_units=ct.ComputeUnit.ALL)
    motion_load_ms = elapsed_ms(load_start)
    warmup_models(rtmpose_model, motion_model)

    (
        rows,
        coco17_2d,
        h36m17_2d,
        normalized_h36m17_2d,
        frame_indices,
        timestamps,
        stage_times,
        video_meta,
    ) = run_rtmpose_pass(args, rtmpose_model)

    pred_3d, pred_3d_selected, motion_indices = run_motionagformer_pass(
        args,
        motion_model,
        normalized_h36m17_2d,
        stage_times,
    )

    render_ms = render_side_by_side_video(
        args,
        rows,
        np.asarray(pred_3d_selected, dtype="float32"),
        video_meta,
    )
    stage_times["render_video_ms"] = render_ms

    save_jsonl(Path(args.output_jsonl), rows)
    save_npz(
        Path(args.output_npz),
        pred_3d,
        pred_3d_selected,
        coco17_2d,
        h36m17_2d,
        normalized_h36m17_2d,
        frame_indices,
        timestamps,
        args.lookahead,
        motion_indices,
    )
    benchmark = build_benchmark(
        args,
        stage_times,
        video_meta,
        rtmpose_load_ms,
        motion_load_ms,
        pred_3d_selected,
    )
    save_benchmark(Path(args.output_benchmark), Path(args.output_csv), benchmark)
    print(json.dumps(benchmark, indent=2, sort_keys=True))
    return 0


def make_output_dirs(args):
    for value in (
        args.output_jsonl,
        args.output_npz,
        args.output_benchmark,
        args.output_csv,
        args.output_video,
    ):
        if value:
            Path(value).parent.mkdir(parents=True, exist_ok=True)
    for folder in ("jsonl", "npz", "videos", "csv", "logs", "plots"):
        (ROOT / "assets/coreml_pipeline" / folder).mkdir(parents=True, exist_ok=True)


def warmup_models(rtmpose_model, motion_model):
    zeros_image = np.zeros((1, 3, 256, 192), dtype="float32")
    zeros_motion = np.zeros((1, MOTION_WINDOW_SIZE, 17, 3), dtype="float32")
    for _ in range(3):
        rtmpose_model.predict({RTMPOSE_INPUT_NAME: zeros_image})
        motion_model.predict({MOTION_INPUT_NAME: zeros_motion})


def run_rtmpose_pass(args, rtmpose_model):
    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened():
        raise FileNotFoundError(f"Could not open video: {args.video}")
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0) or 30.0
    image_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    image_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    rows = []
    coco17 = []
    h36m17 = []
    normalized = []
    frame_indices = []
    timestamps = []
    stage_times = new_stage_times()

    frame_index = 0
    while args.max_frames <= 0 or frame_index < args.max_frames:
        start = time.perf_counter()
        ok, frame = cap.read()
        if not ok:
            break
        stage_times["frame_decode_ms"].append(elapsed_ms(start))

        timestamp_sec = frame_index / fps
        start = time.perf_counter()
        input_tensor, warp_mat, inv_warp_mat = preprocess_rtmpose_full_image(frame)
        stage_times["rtmpose_preprocess_ms"].append(elapsed_ms(start))

        start = time.perf_counter()
        pred = rtmpose_model.predict({RTMPOSE_INPUT_NAME: input_tensor})
        stage_times["rtmpose_coreml_ms"].append(elapsed_ms(start))
        simcc_x = np.asarray(pred[RTMPOSE_OUTPUT_X], dtype="float32")
        simcc_y = np.asarray(pred[RTMPOSE_OUTPUT_Y], dtype="float32")

        start = time.perf_counter()
        keypoints_input, scores = decode_simcc(simcc_x, simcc_y)
        stage_times["simcc_decode_ms"].append(elapsed_ms(start))

        start = time.perf_counter()
        keypoints_image = apply_affine_to_points(keypoints_input[0], inv_warp_mat)
        coco = np.concatenate([keypoints_image, scores[0, :, None]], axis=-1).astype("float32")
        stage_times["inverse_affine_ms"].append(elapsed_ms(start))

        start = time.perf_counter()
        h36m_xy, h36m_conf = coco17_to_motionagformer_h36m17(coco)
        normalized_xy = normalize_motionagformer_2d(h36m_xy, image_w, image_h)
        normalized_frame = np.concatenate([normalized_xy, h36m_conf[:, None]], axis=-1).astype("float32")
        stage_times["coco_to_h36m_ms"].append(elapsed_ms(start))

        start = time.perf_counter()
        row = {
            "frame_index": frame_index,
            "frame_idx": frame_index,
            "timestamp_sec": float(timestamp_sec),
            "image_width": image_w,
            "image_height": image_h,
            "bbox_policy": "full_image",
            "coco17_keypoints": coco.tolist(),
            "keypoints_coco17": coco.tolist(),
            "rtmpose_raw_output_shapes": {
                RTMPOSE_OUTPUT_X: list(simcc_x.shape),
                RTMPOSE_OUTPUT_Y: list(simcc_y.shape),
            },
            "valid_2d": bool(np.any(coco[:, 2] > 0.0)),
        }
        rows.append(row)
        coco17.append(coco)
        h36m17.append(np.concatenate([h36m_xy, h36m_conf[:, None]], axis=-1).astype("float32"))
        normalized.append(normalized_frame)
        frame_indices.append(frame_index)
        timestamps.append(timestamp_sec)
        stage_times["postprocess_ms"].append(elapsed_ms(start))
        frame_index += 1

    cap.release()
    if not rows:
        raise RuntimeError("No frames processed")

    return (
        rows,
        np.stack(coco17).astype("float32"),
        np.stack(h36m17).astype("float32"),
        np.stack(normalized).astype("float32"),
        np.asarray(frame_indices, dtype=np.int32),
        np.asarray(timestamps, dtype="float32"),
        stage_times,
        {"fps": fps, "image_width": image_w, "image_height": image_h, "frames_processed": len(rows)},
    )


def preprocess_rtmpose_full_image(frame_bgr):
    image_h, image_w = frame_bgr.shape[:2]
    bbox = np.asarray([0.0, 0.0, float(image_w), float(image_h)], dtype="float32")
    center = (bbox[2:] + bbox[:2]) * 0.5
    scale = (bbox[2:] - bbox[:2]) * 1.25
    scale = fix_aspect_ratio(scale, RTMPOSE_INPUT_SIZE[0] / RTMPOSE_INPUT_SIZE[1])
    warp_mat = get_warp_matrix(center, scale, 0.0, RTMPOSE_INPUT_SIZE, inv=False)
    inv_warp_mat = get_warp_matrix(center, scale, 0.0, RTMPOSE_INPUT_SIZE, inv=True)
    warped = cv2.warpAffine(frame_bgr, warp_mat, RTMPOSE_INPUT_SIZE, flags=cv2.INTER_LINEAR)
    rgb = cv2.cvtColor(warped, cv2.COLOR_BGR2RGB).astype("float32")
    normalized = (rgb - MEAN_RGB) / STD_RGB
    tensor = normalized.transpose(2, 0, 1)[None, ...].astype("float32")
    return tensor, warp_mat, inv_warp_mat


def fix_aspect_ratio(scale, aspect_ratio):
    w, h = float(scale[0]), float(scale[1])
    if w > h * aspect_ratio:
        return np.asarray([w, w / aspect_ratio], dtype="float32")
    return np.asarray([h * aspect_ratio, h], dtype="float32")


def get_warp_matrix(center, scale, rot, output_size, inv=False):
    src_w, _ = scale[:2]
    dst_w, dst_h = output_size[:2]
    rot_rad = np.deg2rad(rot)
    src_dir = rotate_point(np.asarray([src_w * -0.5, 0.0], dtype="float32"), rot_rad)
    dst_dir = np.asarray([dst_w * -0.5, 0.0], dtype="float32")
    src = np.zeros((3, 2), dtype="float32")
    src[0, :] = center
    src[1, :] = center + src_dir
    src[2, :] = get_3rd_point(src[0, :], src[1, :])
    dst = np.zeros((3, 2), dtype="float32")
    dst[0, :] = [dst_w * 0.5, dst_h * 0.5]
    dst[1, :] = np.asarray([dst_w * 0.5, dst_h * 0.5], dtype="float32") + dst_dir
    dst[2, :] = get_3rd_point(dst[0, :], dst[1, :])
    if inv:
        return cv2.getAffineTransform(np.float32(dst), np.float32(src))
    return cv2.getAffineTransform(np.float32(src), np.float32(dst))


def rotate_point(point, angle_rad):
    sn, cs = np.sin(angle_rad), np.cos(angle_rad)
    return np.asarray([point[0] * cs - point[1] * sn, point[0] * sn + point[1] * cs], dtype="float32")


def get_3rd_point(a, b):
    direction = a - b
    return b + np.asarray([-direction[1], direction[0]], dtype="float32")


def decode_simcc(simcc_x, simcc_y):
    n, k, _ = simcc_x.shape
    x_flat = simcc_x.reshape(n * k, -1)
    y_flat = simcc_y.reshape(n * k, -1)
    x_locs = np.argmax(x_flat, axis=1)
    y_locs = np.argmax(y_flat, axis=1)
    max_x = np.max(x_flat, axis=1)
    max_y = np.max(y_flat, axis=1)
    scores = np.minimum(max_x, max_y).astype("float32")
    locs = np.stack([x_locs, y_locs], axis=-1).astype("float32")
    locs[scores <= 0.0] = -1.0
    locs = (locs / SIMCC_SPLIT_RATIO).reshape(n, k, 2).astype("float32")
    return locs, scores.reshape(n, k).astype("float32")


def apply_affine_to_points(points, matrix):
    ones = np.ones((points.shape[0], 1), dtype="float32")
    homogeneous = np.concatenate([points.astype("float32"), ones], axis=1)
    return (homogeneous @ matrix.T).astype("float32")


def run_motionagformer_pass(args, motion_model, normalized_h36m17_2d, stage_times):
    builder = MotionAGFormerWindowBuilder(window_size=MOTION_WINDOW_SIZE)
    pred_3d = []
    pred_3d_selected = []
    motion_indices = []
    select_index = MOTION_WINDOW_SIZE - 1 - int(args.lookahead)
    for idx in range(len(normalized_h36m17_2d)):
        start = time.perf_counter()
        window, indices = builder.build_lookahead_padded(normalized_h36m17_2d, idx, args.lookahead)
        input_tensor = window[None, ...].astype("float32")
        stage_times["motionagformer_preprocess_ms"].append(elapsed_ms(start))

        start = time.perf_counter()
        pred = motion_model.predict({MOTION_INPUT_NAME: input_tensor})
        stage_times["motionagformer_coreml_ms"].append(elapsed_ms(start))
        output = np.asarray(pred[MOTION_OUTPUT_NAME], dtype="float32")
        pred_3d.append(output[0])
        pred_3d_selected.append(output[0, select_index])
        motion_indices.append(indices)
    return (
        np.stack(pred_3d).astype("float32"),
        np.stack(pred_3d_selected).astype("float32"),
        np.stack(motion_indices).astype(np.int32),
    )


def render_side_by_side_video(args, rows, pred_3d_selected, video_meta):
    if not args.output_video:
        return [0.0 for _ in rows]
    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened():
        raise FileNotFoundError(f"Could not open video for rendering: {args.video}")
    output_w, output_h = 1080, 960
    panel_w = output_w // 2
    fps = float(video_meta["fps"])
    writer = cv2.VideoWriter(
        str(args.output_video),
        cv2.VideoWriter_fourcc(*"mp4v"),
        fps,
        (output_w, output_h),
    )
    if not writer.isOpened():
        raise RuntimeError(f"Could not open video writer: {args.output_video}")

    times = []
    for idx, row in enumerate(rows):
        ok, frame = cap.read()
        if not ok:
            break
        start = time.perf_counter()
        left = cv2.resize(frame, (panel_w, output_h), interpolation=cv2.INTER_AREA)
        scale_x = panel_w / float(video_meta["image_width"])
        scale_y = output_h / float(video_meta["image_height"])
        keypoints = np.asarray(row["coco17_keypoints"], dtype="float32").copy()
        keypoints[:, 0] *= scale_x
        keypoints[:, 1] *= scale_y
        draw_coco_skeleton(left, keypoints)
        cv2.putText(left, "RTMPose-s CoreML 2D", (16, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)

        right = np.full((output_h, panel_w, 3), 245, dtype=np.uint8)
        draw_3d_views(right, pred_3d_selected[idx])
        cv2.putText(right, "MotionAGFormer-XS CoreML 3D", (16, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (20, 20, 20), 2)
        writer.write(np.concatenate([left, right], axis=1))
        times.append(elapsed_ms(start))

    cap.release()
    writer.release()
    if len(times) < len(rows):
        times.extend([0.0] * (len(rows) - len(times)))
    return times


def draw_coco_skeleton(image, keypoints):
    for a, b in COCO_SKELETON:
        conf = min(float(keypoints[a, 2]), float(keypoints[b, 2]))
        color = color_for_conf(conf)
        cv2.line(image, point(keypoints[a]), point(keypoints[b]), color, 2, cv2.LINE_AA)
    for idx, kp in enumerate(keypoints):
        color = color_for_conf(float(kp[2]))
        cv2.circle(image, point(kp), 4, color, -1, cv2.LINE_AA)
        if idx in (5, 6, 7, 8, 9, 10, 11, 12):
            cv2.putText(image, f"{idx}:{kp[2]:.2f}", (point(kp)[0] + 5, point(kp)[1] - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.35, color, 1)


def color_for_conf(conf):
    if conf >= 0.7:
        return (40, 220, 80)
    if conf >= 0.4:
        return (40, 180, 255)
    return (120, 120, 120)


def point(row):
    return int(round(float(row[0]))), int(round(float(row[1])))


def draw_3d_views(panel, joints):
    views = [
        ("front x/y", (0, 1), (0, 0, panel.shape[1], panel.shape[0] // 3)),
        ("side z/y", (2, 1), (0, panel.shape[0] // 3, panel.shape[1], 2 * panel.shape[0] // 3)),
        ("top x/z", (0, 2), (0, 2 * panel.shape[0] // 3, panel.shape[1], panel.shape[0])),
    ]
    for label, axes, rect in views:
        draw_3d_projection(panel, joints, axes, rect, label)


def draw_3d_projection(panel, joints, axes, rect, label):
    x1, y1, x2, y2 = rect
    cv2.rectangle(panel, (x1, y1), (x2 - 1, y2 - 1), (215, 215, 215), 1)
    pts = np.asarray(joints[:, axes], dtype="float32")
    pts = pts - pts.mean(axis=0, keepdims=True)
    span = float(np.max(np.abs(pts))) or 1.0
    scale = 0.42 * min(x2 - x1, y2 - y1) / span
    center = np.asarray([(x1 + x2) * 0.5, (y1 + y2) * 0.5], dtype="float32")
    draw = pts * np.asarray([scale, -scale], dtype="float32") + center
    for a, b in H36M_SKELETON:
        cv2.line(panel, point(draw[a]), point(draw[b]), (50, 90, 180), 2, cv2.LINE_AA)
    for p in draw:
        cv2.circle(panel, point(p), 3, (20, 20, 20), -1, cv2.LINE_AA)
    cv2.putText(panel, label, (x1 + 12, y1 + 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (45, 45, 45), 1)


def new_stage_times():
    return {
        "frame_decode_ms": [],
        "rtmpose_preprocess_ms": [],
        "rtmpose_coreml_ms": [],
        "simcc_decode_ms": [],
        "inverse_affine_ms": [],
        "coco_to_h36m_ms": [],
        "motionagformer_preprocess_ms": [],
        "motionagformer_coreml_ms": [],
        "postprocess_ms": [],
        "render_video_ms": [],
    }


def build_benchmark(args, stage_times, video_meta, rtmpose_load_ms, motion_load_ms, pred_3d_selected):
    no_render = sum_stage_times(stage_times, include_render=False)
    with_render = no_render + np.asarray(stage_times["render_video_ms"], dtype="float32")
    frames_processed = int(video_meta["frames_processed"])
    latency = {
        "total_no_render": summarize(no_render),
        "rtmpose_coreml": summarize(stage_times["rtmpose_coreml_ms"]),
        "motionagformer_coreml": summarize(stage_times["motionagformer_coreml_ms"]),
        "rtmpose_preprocess": summarize(stage_times["rtmpose_preprocess_ms"]),
        "simcc_decode": summarize(stage_times["simcc_decode_ms"]),
        "motionagformer_preprocess": summarize(stage_times["motionagformer_preprocess_ms"]),
        "inverse_affine": summarize(stage_times["inverse_affine_ms"]),
        "coco_to_h36m": summarize(stage_times["coco_to_h36m_ms"]),
        "postprocess": summarize(stage_times["postprocess_ms"]),
        "render_video": summarize(stage_times["render_video_ms"]),
        "total_with_render": summarize(with_render),
    }
    fps_no_render = 1000.0 / latency["total_no_render"]["mean"] if latency["total_no_render"]["mean"] > 0 else 0.0
    fps_with_render = 1000.0 / latency["total_with_render"]["mean"] if latency["total_with_render"]["mean"] > 0 else None
    return {
        "video": args.video,
        "frames_processed": frames_processed,
        "frames_with_3d": int(len(pred_3d_selected)),
        "bbox_policy": "full_image",
        "lookahead": int(args.lookahead),
        "latency_frames": int(args.lookahead),
        "model_load_ms": {
            "rtmpose": float(rtmpose_load_ms),
            "motionagformer_xs": float(motion_load_ms),
        },
        "latency_ms": latency,
        "fps_no_render": float(fps_no_render),
        "fps_with_render": None if fps_with_render is None else float(fps_with_render),
        "realtime_30fps_no_render": bool(fps_no_render >= 30.0),
        "realtime_20fps_no_render": bool(fps_no_render >= 20.0),
        "ane_verified": False,
        "rtmpose_raw_output_shapes": {
            RTMPOSE_OUTPUT_X: [1, 17, 384],
            RTMPOSE_OUTPUT_Y: [1, 17, 512],
        },
        "motionagformer_input_shape": [1, MOTION_WINDOW_SIZE, 17, 3],
        "motionagformer_output_shape": [1, MOTION_WINDOW_SIZE, 17, 3],
        "selected_3d_shape": list(np.asarray(pred_3d_selected).shape),
    }


def sum_stage_times(stage_times, include_render):
    keys = [
        "frame_decode_ms",
        "rtmpose_preprocess_ms",
        "rtmpose_coreml_ms",
        "simcc_decode_ms",
        "inverse_affine_ms",
        "coco_to_h36m_ms",
        "motionagformer_preprocess_ms",
        "motionagformer_coreml_ms",
        "postprocess_ms",
    ]
    if include_render:
        keys.append("render_video_ms")
    total = None
    for key in keys:
        values = np.asarray(stage_times[key], dtype="float32")
        total = values if total is None else total + values
    return total


def summarize(values):
    arr = np.asarray(values, dtype="float32")
    if arr.size == 0:
        return {"mean": None, "median": None, "p90": None, "p95": None, "min": None, "max": None}
    return {
        "mean": float(np.mean(arr)),
        "median": float(np.median(arr)),
        "p90": float(np.percentile(arr, 90)),
        "p95": float(np.percentile(arr, 95)),
        "min": float(np.min(arr)),
        "max": float(np.max(arr)),
    }


def save_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, sort_keys=True) + "\n")


def save_npz(path, pred_3d, pred_3d_selected, coco17_2d, h36m17_2d, normalized_h36m17_2d, frame_indices, timestamps, lookahead, motion_indices):
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        path,
        pred_3d=np.asarray(pred_3d, dtype="float32"),
        pred_3d_selected=np.asarray(pred_3d_selected, dtype="float32"),
        coco17_2d=np.asarray(coco17_2d, dtype="float32"),
        h36m17_2d=np.asarray(h36m17_2d, dtype="float32"),
        normalized_h36m17_2d=np.asarray(normalized_h36m17_2d, dtype="float32"),
        frame_indices=np.asarray(frame_indices, dtype=np.int32),
        timestamps_sec=np.asarray(timestamps, dtype="float32"),
        motionagformer_window_indices=np.asarray(motion_indices, dtype=np.int32),
        latency_frames=np.asarray([lookahead], dtype=np.int32),
        model=np.asarray(["MotionAGFormer-XS CoreML"]),
        source_2d=np.asarray(["RTMPose-s CoreML"]),
    )


def save_benchmark(json_path, csv_path, benchmark):
    json_path.parent.mkdir(parents=True, exist_ok=True)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(benchmark, indent=2, sort_keys=True), encoding="utf-8")
    with csv_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=["stage", "mean", "median", "p90", "p95", "min", "max"])
        writer.writeheader()
        for stage, stats in benchmark["latency_ms"].items():
            writer.writerow({"stage": stage, **stats})


def elapsed_ms(start):
    return (time.perf_counter() - start) * 1000.0


if __name__ == "__main__":
    raise SystemExit(main())
