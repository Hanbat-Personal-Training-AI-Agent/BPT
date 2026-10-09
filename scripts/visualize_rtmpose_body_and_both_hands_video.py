import argparse
import json
import os
from pathlib import Path
import sys
import time


os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/bpt_mpl_cache")

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent
for path in (ROOT, SCRIPT_DIR):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

from compare_yolo26_rtmpose_full_body import legacy_openmmlab_checkpoint_load
from pose_feedback.body.body_adapter import coco_yolo_keypoints_to_body
from pose_feedback.body.coreml_motionagformer import (
    DEFAULT_MOTIONAGFORMER_COREML_PATH,
    CoreMLMotionAGFormerRunner,
)
from pose_feedback.body.live_motionagformer import (
    MOTIONAGFORMER_WINDOW_SIZE,
    motionagformer_frames_from_coco17,
    motionagformer_body_3d_debug,
    run_live_motionagformer_sequence,
)
from pose_feedback.body.motionagformer_buffer import MotionAGFormerWindowBuilder
from pose_feedback.body.motionagformer_wrist_source import build_motionagformer_input_2d
from pose_feedback.body.motionagformer_runner import MotionAGFormerRunner
from pose_feedback.body.rtmpose_runner import (
    RTMPoseNoPersonDetectedError,
    RTMPoseRunner,
)
from pose_feedback.body.visual_body_wrist_anchor import build_visual_body_2d
from pose_feedback.config import PUSHUP_SIDE_CONFIG
from pose_feedback.hand.hand_3d_overlay import build_hand_3d_overlay
from pose_feedback.hand.hand_crop_selector import HandCropSelector
from pose_feedback.hand.mediapipe_hand_landmarker_runner import (
    MediaPipeHandLandmarkerRunner,
)
from pose_feedback.hand.mediapipe_hand_runner import (
    MediaPipeHandsRuntimeError,
    MediaPipeHandsRunner,
)
from pose_feedback.hand.wrist_crop import (
    build_wrist_hand_crop,
    crop_metadata_from_box,
)
from pose_feedback.wrist.crop import CropBoxSmoother
from pose_feedback.wrist.estimator import WristEstimator
from pose_feedback.wrist.geometry import crop_to_image_coords
from visualize_rtmpose_body_and_both_hands import (
    draw_body,
    draw_side_hand,
    draw_text_summary,
    drawing_sizes,
)
from visualize_coreml_rtmpose_motionagformer_side_by_side import (
    load_coreml_motionagformer_npz,
    render_right_panel,
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="RTMPose-s body plus MediaPipe Hands video visualization smoke test.",
    )
    parser.add_argument("--video", default="assets/smoke/vedio_1.mp4")
    parser.add_argument(
        "--rtmpose-config",
        default="models/rtmpose/rtmpose-s_8xb256-420e_coco-256x192.py",
    )
    parser.add_argument(
        "--rtmpose-checkpoint",
        default="models/rtmpose/rtmpose-s_coco.pth",
    )
    parser.add_argument(
        "--output-video",
        default="assets/smoke/vedio_1_rtmpose_body_both_hands_overlay.mp4",
    )
    parser.add_argument(
        "--output-jsonl",
        default="assets/smoke/vedio_1_rtmpose_body_both_hands_log.jsonl",
    )
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--max-frames", type=int, default=300)
    parser.add_argument("--stride", type=int, default=1)
    parser.add_argument("--conf-threshold", type=float, default=0.3)
    parser.add_argument("--marker-scale", type=float, default=0.6)
    parser.add_argument(
        "--hand-crop-mode",
        choices=("wrist", "forward"),
        default="wrist",
        help="Use wrist-centered square crops by default; forward keeps the older elbow-to-wrist crop.",
    )
    parser.add_argument("--hand-crop-size", type=int, default=256)
    parser.add_argument("--wrist-conf-thr", type=float, default=0.3)
    parser.add_argument("--disable-hands", action="store_true")
    parser.add_argument("--draw-hand-crops", action="store_true")
    parser.add_argument(
        "--mediapipe-runtime",
        choices=("legacy", "tasks", "auto"),
        default="auto",
        help="legacy uses mp.solutions Hands; tasks uses MediaPipe Tasks HandLandmarker.",
    )
    parser.add_argument(
        "--hand-landmarker-task",
        default="assets/mediapipe/hand_landmarker.task",
        help="MediaPipe Tasks HandLandmarker .task path, used for --mediapipe-runtime tasks/auto.",
    )
    parser.add_argument(
        "--mediapipe-tasks-running-mode",
        choices=("image", "video"),
        default="video",
        help="MediaPipe Tasks running mode. Video mode uses side-specific tracking streams.",
    )
    parser.add_argument(
        "--mediapipe-tasks-delegate",
        choices=("cpu", "gpu"),
        default="cpu",
        help="MediaPipe Tasks inference delegate. CPU is the safe default on macOS.",
    )
    parser.add_argument(
        "--hand-sides",
        choices=("left", "right", "both"),
        default="both",
        help="Which hand crop streams to run. Useful to isolate per-side VIDEO-mode runners.",
    )
    parser.add_argument(
        "--debug-hand-timestamps",
        action="store_true",
        help="Print the first few VIDEO-mode timestamp_ms values per side for monotonicity checks.",
    )
    parser.add_argument(
        "--draw-3d-hands",
        action="store_true",
        help=(
            "Compatibility alias for --run-motionagformer --draw-3d-panel. "
            "Use the newer flags for profiling inference separately from rendering."
        ),
    )
    parser.add_argument(
        "--run-motionagformer",
        action="store_true",
        help="Run MotionAGFormer 3D lifting even when the Python 3D panel is not rendered.",
    )
    parser.add_argument(
        "--draw-3d-panel",
        action="store_true",
        help="Render the expensive Python 3D body/hand panel into the output video.",
    )
    parser.add_argument(
        "--hand-3d-mode",
        choices=("none", "local", "wrist-anchored"),
        default=None,
        help=(
            "3D hand attachment mode. Defaults to wrist-anchored when MotionAGFormer "
            "is running, otherwise none."
        ),
    )
    parser.add_argument("--hand-3d-scale", type=float, default=1.0)
    parser.add_argument(
        "--hand-3d-axis-map",
        default="x,y,z",
        help='Comma-separated MediaPipe hand world axis map before flips, e.g. "x,y,z" or "x,z,y".',
    )
    parser.add_argument("--hand-3d-flip-x", action="store_true")
    parser.add_argument("--hand-3d-flip-y", action="store_true")
    parser.add_argument("--hand-3d-flip-z", action="store_true")
    parser.add_argument(
        "--hide-body-wrist-limbs",
        action="store_true",
        help="Hide only body elbow-to-wrist skeleton lines in the 2D overlay.",
    )
    parser.add_argument(
        "--hide-body-keypoint-labels",
        action="store_true",
        help="Hide RTMPose body keypoint text labels in the 2D overlay.",
    )
    parser.add_argument(
        "--hide-body-skeleton",
        action="store_true",
        help="Hide all RTMPose body skeleton lines while keeping body points and hands.",
    )
    parser.add_argument(
        "--hide-hand-debug-vectors",
        action="store_true",
        help="Hide 2D hand debug arrows: elbow-to-RTMPose-wrist and RTMPose-wrist-to-middle-MCP.",
    )
    parser.add_argument(
        "--motionagformer-npz",
        default="assets/coreml_pipeline/npz/vedio_1_coreml_motionagformer_xs_3d.npz",
        help="Existing MotionAGFormer-XS 3D NPZ used only for 3D visualization panels.",
    )
    parser.add_argument(
        "--motionagformer-wrist-source",
        choices=("rtmpose", "mediapipe"),
        default="rtmpose",
        help=(
            "Experimental MotionAGFormer 2D input wrist source. The 2D overlay "
            "still draws raw RTMPose body keypoints."
        ),
    )
    parser.add_argument(
        "--body-wrist-2d-anchor",
        choices=("rtmpose", "mediapipe"),
        default="rtmpose",
        help=(
            "Visualization-only body skeleton wrist anchor. This does not affect "
            "MotionAGFormer input."
        ),
    )
    parser.add_argument(
        "--motionagformer-3d-source",
        choices=("auto", "live", "coreml", "npz"),
        default="auto",
        help="Use Core ML, live PyTorch MotionAGFormer, or replay an existing NPZ.",
    )
    parser.add_argument(
        "--motionagformer-coreml",
        default=DEFAULT_MOTIONAGFORMER_COREML_PATH,
        help="MotionAGFormer-XS Core ML .mlpackage path.",
    )
    parser.add_argument(
        "--motionagformer-coreml-compute-units",
        choices=("all", "cpu_only", "cpu_and_gpu", "cpu_and_ne"),
        default="all",
        help="Core ML compute units request. This does not verify ANE usage.",
    )
    parser.add_argument(
        "--motionagformer-config",
        default="external/MotionAGFormer/configs/h36m/MotionAGFormer-xsmall.yaml",
    )
    parser.add_argument(
        "--motionagformer-checkpoint",
        default="external/MotionAGFormer/checkpoint/motionagformer-xs-h36m.pth.tr",
    )
    parser.add_argument("--motionagformer-device", default="cpu")
    parser.add_argument("--motionagformer-lookahead", type=int, default=5)
    parser.add_argument("--view-preset", choices=("front", "side", "top", "stack"), default="stack")
    parser.add_argument("--axis-preset", choices=("raw", "user"), default="user")
    parser.add_argument("--profile-fps", action="store_true")
    parser.add_argument("--profile-warmup-frames", type=int, default=5)
    parser.add_argument(
        "--profile-output-json",
        default=None,
        help="Optional profiling JSON path. Defaults to <output-jsonl stem>_profile.json.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    if args.max_frames < 1:
        raise ValueError("--max-frames must be >= 1")
    if args.stride < 1:
        raise ValueError("--stride must be >= 1")
    profile_wall_start = time.perf_counter()
    records, video_meta, pass_status = process_video_pass(args)
    motionagformer_status = assign_motionagformer_3d(records, video_meta, args)
    hand_3d_counts = assign_hand_3d(records, args)
    render_status = render_and_write_outputs(records, video_meta, args)
    profile_total_wall_ms = elapsed_ms(profile_wall_start)

    if args.debug_hand_timestamps:
        for side in ("left", "right"):
            stamps = pass_status["ts_debug"][side]
            monotonic = all(b > a for a, b in zip(stamps, stamps[1:]))
            print(
                {
                    "debug_hand_timestamps_side": side,
                    "first_timestamps_ms": stamps,
                    "strictly_increasing": monotonic,
                },
            )

    summary = build_summary(
        args=args,
        video_meta=video_meta,
        pass_status=pass_status,
        motionagformer_status=motionagformer_status,
        hand_3d_counts=hand_3d_counts,
    )
    print(summary)
    if args.profile_fps:
        profile_report = build_profile_report(
            records=records,
            args=args,
            video_meta=video_meta,
            pass_status=pass_status,
            motionagformer_status=motionagformer_status,
            hand_3d_counts=hand_3d_counts,
            render_status=render_status,
            total_wall_ms=profile_total_wall_ms,
        )
        profile_path = profile_output_path(args)
        profile_path.parent.mkdir(parents=True, exist_ok=True)
        profile_path.write_text(
            json.dumps(profile_report, indent=2, sort_keys=True),
            encoding="utf-8",
        )
        print_profile_summary(profile_report, profile_path)
    return 0


def should_run_motionagformer(args):
    return bool(
        getattr(args, "run_motionagformer", False)
        or getattr(args, "draw_3d_panel", False)
        or getattr(args, "draw_3d_hands", False)
    )


def should_draw_3d_panel(args):
    return bool(
        getattr(args, "draw_3d_panel", False)
        or getattr(args, "draw_3d_hands", False)
    )


def effective_hand_3d_mode(args):
    mode = getattr(args, "hand_3d_mode", None)
    if mode is not None:
        return mode
    if should_run_motionagformer(args):
        return "wrist-anchored"
    return "none"


def process_video_pass(args):
    import cv2

    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened():
        print({"video_opened": False, "video": args.video})
        return [], {"fps": 30.0, "image_width": 0, "image_height": 0}, empty_pass_status("video_open_failed")

    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    if fps <= 1e-6:
        fps = 30.0
    image_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    image_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    rtmpose_load_start = time.perf_counter()
    rtmpose_runner, rtmpose_error = init_rtmpose(
        args.rtmpose_config,
        args.rtmpose_checkpoint,
        args.device,
    )
    rtmpose_load_ms = elapsed_ms(rtmpose_load_start)
    if rtmpose_error:
        print({"rtmpose_runtime": "unavailable", "reason": rtmpose_error})

    mediapipe_load_start = time.perf_counter()
    hand_runners, mediapipe_status = create_video_hand_runners(args)
    mediapipe_load_ms = elapsed_ms(mediapipe_load_start)
    config = PUSHUP_SIDE_CONFIG
    crop_selector = HandCropSelector()
    smoothers = {
        "left": CropBoxSmoother(alpha=config.crop_smoothing_alpha),
        "right": CropBoxSmoother(alpha=config.crop_smoothing_alpha),
    }
    estimators = {"left": WristEstimator(config), "right": WristEstimator(config)}
    wrist_source_counts = {
        side: {"rtmpose": 0, "mediapipe": 0, "fallback": 0}
        for side in ("left", "right")
    }
    body_wrist_2d_source_counts = {
        side: {"rtmpose": 0, "mediapipe": 0, "fallback": 0}
        for side in ("left", "right")
    }
    records = []
    status = {
        "mediapipe_status": mediapipe_status,
        "processed_frames": 0,
        "body_detected_count": 0,
        "left_hand_detected_count": 0,
        "right_hand_detected_count": 0,
        "motionagformer_wrist_source_counts": wrist_source_counts,
        "body_wrist_2d_source_counts": body_wrist_2d_source_counts,
        "model_load_ms": {
            "rtmpose": rtmpose_load_ms,
            "mediapipe_hand": mediapipe_load_ms,
        },
        "ts_debug": {"left": [], "right": []},
    }

    frame_idx = 0
    while status["processed_frames"] < args.max_frames:
        read_start = time.perf_counter()
        ok, frame = cap.read()
        read_ms = elapsed_ms(read_start)
        if not ok:
            break
        if frame_idx % args.stride != 0:
            frame_idx += 1
            continue

        profile_times = {}
        if args.profile_fps:
            profile_times["video_read_decode_ms"] = read_ms
        timestamp_sec = frame_idx / fps
        timestamp_ms = int(round(timestamp_sec * 1000.0))
        rtmpose_start = time.perf_counter()
        keypoints, body_error = predict_rtmpose(rtmpose_runner, frame)
        if args.profile_fps:
            profile_times["rtmpose_inference_ms"] = elapsed_ms(rtmpose_start)
        side_results = None
        motionagformer_input_2d = None
        motionagformer_wrist_debug = None
        visual_body_2d = None
        visual_body_wrist_debug = None
        if keypoints is not None:
            status["body_detected_count"] += 1
            body = coco_yolo_keypoints_to_body(
                keypoints,
                min_confidence=args.conf_threshold,
            )
            side_results = {}
            for side in ("left", "right"):
                side_results[side] = process_side(
                    side=side,
                    image=frame,
                    image_w=image_w,
                    image_h=image_h,
                    body=body,
                    crop_selector=crop_selector,
                    smoother=smoothers[side],
                    estimator=estimators[side],
                    hand_runner=None if hand_runners is None else hand_runners.get(side),
                    current_time_sec=timestamp_sec,
                    timestamp_ms=timestamp_ms,
                    hand_crop_mode=args.hand_crop_mode,
                    hand_crop_size=args.hand_crop_size,
                    wrist_conf_thr=args.wrist_conf_thr,
                    profile_enabled=args.profile_fps,
                )
            if args.profile_fps:
                add_side_profile_times(profile_times, side_results)
            if side_results["left"]["hand_result"] is not None:
                status["left_hand_detected_count"] += 1
            if side_results["right"]["hand_result"] is not None:
                status["right_hand_detected_count"] += 1
            if args.debug_hand_timestamps:
                for side in ("left", "right"):
                    side_result = side_results.get(side)
                    if (
                        hand_runners is not None
                        and side in hand_runners
                        and side_result is not None
                        and side_result.get("crop_box") is not None
                        and len(status["ts_debug"][side]) < 8
                    ):
                        status["ts_debug"][side].append(timestamp_ms)
            postprocess_start = time.perf_counter()
            mediapipe_wrists_px = mediapipe_wrists_from_side_results(side_results)
            motionagformer_input_2d, motionagformer_wrist_debug = build_motionagformer_input_2d(
                raw_body_2d=keypoints,
                mediapipe_wrists_px=mediapipe_wrists_px,
                wrist_source=args.motionagformer_wrist_source,
            )
            update_motionagformer_wrist_source_counts(
                wrist_source_counts,
                motionagformer_wrist_debug,
            )
            visual_body_2d, visual_body_wrist_debug = build_visual_body_2d(
                raw_body_2d=keypoints,
                mediapipe_wrists_px=mediapipe_wrists_px,
                body_wrist_anchor=args.body_wrist_2d_anchor,
            )
            update_wrist_source_counts(
                body_wrist_2d_source_counts,
                visual_body_wrist_debug,
            )
            if args.profile_fps:
                profile_times["body_postprocess_ms"] = elapsed_ms(postprocess_start)
        elif rtmpose_error and body_error is None:
            body_error = rtmpose_error

        records.append(
            {
                "frame_idx": frame_idx,
                "timestamp_sec": timestamp_sec,
                "body_detected": keypoints is not None,
                "keypoints": keypoints,
                "body_error": body_error,
                "side_results": side_results,
                "visual_body_2d": visual_body_2d,
                "visual_body_wrist_debug": visual_body_wrist_debug,
                "motionagformer_input_2d": motionagformer_input_2d,
                "motionagformer_wrist_debug": motionagformer_wrist_debug,
                "body_joints_3d": None,
                "hand_3d_by_side": make_empty_hand_3d(args),
                "motionagformer_3d_generation": "none",
                "motionagformer_3d_key_used": None,
                "motionagformer_coreml_model_path": None,
                "motionagformer_coreml_model_load_ms": None,
                "motionagformer_coreml_inference_ms": None,
                "profile_times_ms": profile_times,
            },
        )

        status["processed_frames"] += 1
        frame_idx += 1

    cap.release()
    close_hand_runners(hand_runners)
    return (
        records,
        {"fps": fps, "image_width": image_w, "image_height": image_h},
        status,
    )


def empty_pass_status(reason):
    return {
        "mediapipe_status": "not_started",
        "processed_frames": 0,
        "body_detected_count": 0,
        "left_hand_detected_count": 0,
        "right_hand_detected_count": 0,
        "motionagformer_wrist_source_counts": {
            side: {"rtmpose": 0, "mediapipe": 0, "fallback": 0}
            for side in ("left", "right")
        },
        "body_wrist_2d_source_counts": {
            side: {"rtmpose": 0, "mediapipe": 0, "fallback": 0}
            for side in ("left", "right")
        },
        "model_load_ms": {
            "rtmpose": None,
            "mediapipe_hand": None,
        },
        "ts_debug": {"left": [], "right": []},
        "reason": reason,
    }


def assign_motionagformer_3d(records, video_meta, args):
    if not should_run_motionagformer(args):
        return {"generation": "disabled", "key_used": None, "warning": None}

    if args.motionagformer_3d_source in ("auto", "coreml"):
        status = assign_coreml_motionagformer_3d(records, video_meta, args)
        if status["generation"] == "coreml":
            return status
        if args.motionagformer_3d_source == "coreml":
            return status
        print(
            {
                "motionagformer_3d": "coreml_unavailable_trying_live",
                "reason": status.get("warning"),
            },
        )

    if args.motionagformer_3d_source in ("auto", "live"):
        status = assign_live_motionagformer_3d(records, video_meta, args)
        if status["generation"] == "live_pytorch" or args.motionagformer_3d_source == "live":
            return status
        print(
            {
                "motionagformer_3d": "live_unavailable_using_npz",
                "reason": status.get("warning"),
            },
        )

    status = assign_npz_motionagformer_3d(records, args)
    if args.motionagformer_wrist_source == "mediapipe":
        warning = (
            "NPZ/replay 3D body was generated before this run; it cannot reflect "
            "--motionagformer-wrist-source mediapipe."
        )
        status["warning"] = warning
        print({"motionagformer_3d": "npz_replay_wrist_source_unaffected", "warning": warning})
    return status


def assign_coreml_motionagformer_3d(records, video_meta, args):
    valid_records = [record for record in records if record["motionagformer_input_2d"] is not None]
    if not valid_records:
        return {"generation": "unavailable", "key_used": None, "warning": "no valid 2D frames"}
    try:
        runner = CoreMLMotionAGFormerRunner(
            model_path=str(ROOT / args.motionagformer_coreml),
            compute_units=args.motionagformer_coreml_compute_units,
            window_size=MOTIONAGFORMER_WINDOW_SIZE,
        )
        pred_selected, inference_times = run_coreml_motionagformer_sequence(
            [record["motionagformer_input_2d"] for record in valid_records],
            runner=runner,
            image_width=video_meta["image_width"],
            image_height=video_meta["image_height"],
            lookahead=args.motionagformer_lookahead,
            window_size=MOTIONAGFORMER_WINDOW_SIZE,
        )
    except Exception as exc:
        return {
            "generation": "unavailable",
            "key_used": None,
            "warning": f"{type(exc).__name__}: {exc}",
            "model_path": args.motionagformer_coreml,
        }

    key_used = f"coreml_xs_lookahead{args.motionagformer_lookahead}"
    for record, joints, inference_ms in zip(valid_records, pred_selected, inference_times):
        record["body_joints_3d"] = joints
        record["motionagformer_3d_generation"] = "coreml"
        record["motionagformer_3d_key_used"] = key_used
        record["motionagformer_coreml_model_path"] = args.motionagformer_coreml
        record["motionagformer_coreml_model_load_ms"] = runner.load_ms
        record["motionagformer_coreml_inference_ms"] = inference_ms
        add_record_profile_time(record, "motionagformer_inference_ms", inference_ms)
        add_record_profile_time(record, "motionagformer_coreml_ms", inference_ms)
    return {
        "generation": "coreml",
        "key_used": key_used,
        "warning": None,
        "model_path": args.motionagformer_coreml,
        "model_load_ms": runner.load_ms,
        "coreml_compute_units_requested": args.motionagformer_coreml_compute_units,
        "inference_ms_mean": mean_or_none(inference_times),
        "inference_ms_median": median_or_none(inference_times),
        "frames_with_3d": int(len(pred_selected)),
    }


def run_coreml_motionagformer_sequence(
    coco17_sequence,
    runner,
    image_width,
    image_height,
    lookahead=5,
    window_size=MOTIONAGFORMER_WINDOW_SIZE,
):
    return run_timed_motionagformer_sequence(
        coco17_sequence=coco17_sequence,
        runner=runner,
        image_width=image_width,
        image_height=image_height,
        lookahead=lookahead,
        window_size=window_size,
    )


def run_timed_motionagformer_sequence(
    coco17_sequence,
    runner,
    image_width,
    image_height,
    lookahead=5,
    window_size=MOTIONAGFORMER_WINDOW_SIZE,
):
    import numpy as np

    normalized_frames = motionagformer_frames_from_coco17(coco17_sequence, image_width, image_height)
    builder = MotionAGFormerWindowBuilder(window_size=window_size)
    select_index = window_size - 1 - int(lookahead)
    pred_selected = []
    inference_times = []
    for index in range(len(normalized_frames)):
        window, _ = builder.build_lookahead_padded(
            normalized_frames,
            index,
            lookahead=int(lookahead),
        )
        inference_start = time.perf_counter()
        pred = runner.predict_3d(window.astype("float32"))
        inference_ms = elapsed_ms(inference_start)
        pred = np.asarray(pred, dtype="float32")
        pred_selected.append(pred[select_index])
        inference_times.append(float(getattr(runner, "last_inference_ms", inference_ms) or inference_ms))
    return np.stack(pred_selected).astype("float32"), inference_times


def assign_live_motionagformer_3d(records, video_meta, args):
    valid_records = [record for record in records if record["motionagformer_input_2d"] is not None]
    if not valid_records:
        return {"generation": "unavailable", "key_used": None, "warning": "no valid 2D frames"}
    try:
        load_start = time.perf_counter()
        runner = MotionAGFormerRunner(
            repo_dir=str(ROOT / "external/MotionAGFormer"),
            config_path=str(ROOT / args.motionagformer_config),
            checkpoint_path=str(ROOT / args.motionagformer_checkpoint),
            device=args.motionagformer_device,
            window_size=27,
        )
        load_ms = (time.perf_counter() - load_start) * 1000.0
        pred_selected, inference_times = run_timed_motionagformer_sequence(
            [record["motionagformer_input_2d"] for record in valid_records],
            runner=runner,
            image_width=video_meta["image_width"],
            image_height=video_meta["image_height"],
            lookahead=args.motionagformer_lookahead,
            window_size=27,
        )
    except Exception as exc:
        return {
            "generation": "unavailable",
            "key_used": None,
            "warning": f"{type(exc).__name__}: {exc}",
        }

    for record, joints in zip(valid_records, pred_selected):
        record["body_joints_3d"] = joints
        record["motionagformer_3d_generation"] = "live_pytorch"
        record["motionagformer_3d_key_used"] = f"live_pytorch_xs_lookahead{args.motionagformer_lookahead}"
    for record, inference_ms in zip(valid_records, inference_times):
        add_record_profile_time(record, "motionagformer_inference_ms", inference_ms)
        add_record_profile_time(record, "motionagformer_live_pytorch_ms", inference_ms)
    return {
        "generation": "live_pytorch",
        "key_used": f"live_pytorch_xs_lookahead{args.motionagformer_lookahead}",
        "warning": None,
        "model_load_ms": load_ms,
        "frames_with_3d": int(len(pred_selected)),
    }


def assign_npz_motionagformer_3d(records, args):
    by_frame, key_used = load_motionagformer_3d_by_frame(args)
    for record in records:
        replay_start = time.perf_counter()
        joints = by_frame.get(record["frame_idx"])
        replay_ms = elapsed_ms(replay_start)
        if joints is None:
            continue
        record["body_joints_3d"] = joints
        record["motionagformer_3d_generation"] = "npz_replay"
        record["motionagformer_3d_key_used"] = key_used
        add_record_profile_time(record, "motionagformer_inference_ms", replay_ms)
        add_record_profile_time(record, "motionagformer_npz_replay_ms", replay_ms)
    return {
        "generation": "npz_replay" if key_used is not None else "unavailable",
        "key_used": key_used,
        "warning": None,
        "frames_with_3d": sum(record["body_joints_3d"] is not None for record in records),
    }


def assign_hand_3d(records, args):
    counts = {"left": 0, "right": 0}
    if not should_run_motionagformer(args) or effective_hand_3d_mode(args) == "none":
        return counts
    for record in records:
        if record["side_results"] is None:
            record["hand_3d_by_side"] = make_empty_hand_3d(args)
            continue
        hand_3d_start = time.perf_counter()
        hand_3d_by_side = build_frame_hand_3d(
            side_results=record["side_results"],
            body_joints_3d=record["body_joints_3d"],
            args=args,
        )
        add_record_profile_time(record, "hand_3d_attach_ms", elapsed_ms(hand_3d_start))
        record["hand_3d_by_side"] = hand_3d_by_side
        for side in ("left", "right"):
            if hand_3d_by_side[side].get("available"):
                counts[side] += 1
    return counts


def render_and_write_outputs(records, video_meta, args):
    import cv2

    image_w = int(video_meta["image_width"])
    image_h = int(video_meta["image_height"])
    fps = float(video_meta["fps"])
    render_3d_views = should_draw_3d_panel(args)
    sizes = drawing_sizes(image_w, image_h, args.marker_scale)
    writer_open_start = time.perf_counter()
    writer = make_writer(args.output_video, fps, image_w * 2 if render_3d_views else image_w, image_h)
    writer_open_ms = elapsed_ms(writer_open_start)
    jsonl_path = Path(args.output_jsonl)
    jsonl_path.parent.mkdir(parents=True, exist_ok=True)

    render_status = {"video_writer_open_ms": writer_open_ms}
    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened():
        raise FileNotFoundError(f"Could not reopen video for rendering: {args.video}")
    records_by_frame = {record["frame_idx"]: record for record in records}
    with jsonl_path.open("w", encoding="utf-8") as log_file:
        frame_idx = 0
        while True:
            read_start = time.perf_counter()
            ok, frame = cap.read()
            read_ms = elapsed_ms(read_start)
            if not ok:
                break
            record = records_by_frame.get(frame_idx)
            if record is None:
                frame_idx += 1
                continue
            add_record_profile_time(record, "render_video_read_decode_ms", read_ms)
            overlay = frame.copy()
            overlay_start = time.perf_counter()
            if not record["body_detected"]:
                draw_body_failure(overlay, record.get("body_error"), sizes)
            else:
                draw_body(
                    overlay,
                    record["visual_body_2d"],
                    args.conf_threshold,
                    sizes,
                    hide_wrist_limbs=args.hide_body_wrist_limbs,
                    hide_keypoint_labels=args.hide_body_keypoint_labels,
                    hide_skeleton=args.hide_body_skeleton,
                )
                for side, color in (("left", (255, 255, 0)), ("right", (255, 0, 255))):
                    draw_side_hand(
                        overlay,
                        record["side_results"][side],
                        color,
                        sizes,
                        draw_crop=args.draw_hand_crops,
                        draw_debug_vectors=not args.hide_hand_debug_vectors,
                    )
                draw_text_summary(overlay, record["side_results"], sizes)
            add_record_profile_time(record, "overlay_2d_draw_ms", elapsed_ms(overlay_start))
            if render_3d_views:
                render_3d_start = time.perf_counter()
                output_frame = make_side_by_side_frame(
                    overlay=overlay,
                    body_joints_3d=record["body_joints_3d"],
                    hand_3d_by_side=record["hand_3d_by_side"],
                    frame_idx=record["frame_idx"],
                    image_w=image_w,
                    image_h=image_h,
                    args=args,
                    sizes=sizes,
                )
                add_record_profile_time(record, "render_3d_draw_ms", elapsed_ms(render_3d_start))
            else:
                output_frame = overlay
            writer_start = time.perf_counter()
            writer.write(output_frame)
            add_record_profile_time(record, "video_writer_ms", elapsed_ms(writer_start))
            jsonl_start = time.perf_counter()
            log_file.write(
                json.dumps(
                    frame_log(
                        frame_idx=record["frame_idx"],
                        timestamp_sec=record["timestamp_sec"],
                        body_detected=record["body_detected"],
                        image_width=image_w,
                        image_height=image_h,
                        side_results=record["side_results"],
                        hand_3d_by_side=record["hand_3d_by_side"],
                        visual_body_2d=record["visual_body_2d"],
                        visual_body_wrist_debug=record["visual_body_wrist_debug"],
                        motionagformer_input_2d=record["motionagformer_input_2d"],
                        motionagformer_wrist_debug=record["motionagformer_wrist_debug"],
                        body_joints_3d=record["body_joints_3d"],
                        motionagformer_3d_generation=record["motionagformer_3d_generation"],
                        motionagformer_3d_key_used=record["motionagformer_3d_key_used"],
                        motionagformer_coreml_model_path=record.get(
                            "motionagformer_coreml_model_path",
                        ),
                        motionagformer_coreml_model_load_ms=record.get(
                            "motionagformer_coreml_model_load_ms",
                        ),
                        motionagformer_coreml_inference_ms=record.get(
                            "motionagformer_coreml_inference_ms",
                        ),
                        args=args,
                    ),
                    sort_keys=True,
                )
                + "\n",
            )
            add_record_profile_time(record, "jsonl_logging_ms", elapsed_ms(jsonl_start))
            frame_idx += 1
    cap.release()
    writer.release()
    return render_status


def build_summary(args, video_meta, pass_status, motionagformer_status, hand_3d_counts):
    mediapipe_status = pass_status["mediapipe_status"]
    return {
        "video_opened": video_meta["image_width"] > 0 and video_meta["image_height"] > 0,
        "video": args.video,
        "mediapipe_runtime": mediapipe_status,
        "mediapipe_tasks_running_mode": (
            args.mediapipe_tasks_running_mode
            if mediapipe_status.startswith("tasks")
            else None
        ),
        "mediapipe_tasks_delegate": (
            args.mediapipe_tasks_delegate
            if mediapipe_status.startswith("tasks")
            else None
        ),
        "hand_sides": args.hand_sides,
        "hand_crop_mode": args.hand_crop_mode,
        "hand_crop_size": args.hand_crop_size,
        "wrist_conf_thr": args.wrist_conf_thr,
        "draw_3d_hands": args.draw_3d_hands,
        "run_motionagformer": should_run_motionagformer(args),
        "draw_3d_panel": should_draw_3d_panel(args),
        "hand_3d_mode": effective_hand_3d_mode(args),
        "hand_3d_scale": args.hand_3d_scale,
        "hide_body_wrist_limbs": bool(args.hide_body_wrist_limbs),
        "hide_body_keypoint_labels": bool(args.hide_body_keypoint_labels),
        "hide_body_skeleton": bool(args.hide_body_skeleton),
        "hide_hand_debug_vectors": bool(args.hide_hand_debug_vectors),
        "body_wrist_2d_anchor": args.body_wrist_2d_anchor,
        "body_wrist_2d_source_counts": pass_status["body_wrist_2d_source_counts"],
        "motionagformer_wrist_source": args.motionagformer_wrist_source,
        "motionagformer_wrist_source_counts": pass_status["motionagformer_wrist_source_counts"],
        "motionagformer_3d_source_requested": args.motionagformer_3d_source,
        "motionagformer_3d_generation": motionagformer_status.get("generation"),
        "motionagformer_3d_key_used": motionagformer_status.get("key_used"),
        "motionagformer_3d_warning": motionagformer_status.get("warning"),
        "motionagformer_coreml_model_path": motionagformer_status.get("model_path"),
        "motionagformer_coreml_model_load_ms": (
            motionagformer_status.get("model_load_ms")
            if motionagformer_status.get("generation") == "coreml"
            else None
        ),
        "motionagformer_coreml_inference_ms_mean": motionagformer_status.get(
            "inference_ms_mean",
        ),
        "motionagformer_coreml_inference_ms_median": motionagformer_status.get(
            "inference_ms_median",
        ),
        "motionagformer_coreml_compute_units_requested": motionagformer_status.get(
            "coreml_compute_units_requested",
        ),
        "motionagformer_live_model_load_ms": (
            motionagformer_status.get("model_load_ms")
            if motionagformer_status.get("generation") == "live_pytorch"
            else None
        ),
        "processed_frames": pass_status["processed_frames"],
        "body_detected_count": pass_status["body_detected_count"],
        "left_hand_detected_count": pass_status["left_hand_detected_count"],
        "right_hand_detected_count": pass_status["right_hand_detected_count"],
        "left_hand_3d_available_count": hand_3d_counts["left"],
        "right_hand_3d_available_count": hand_3d_counts["right"],
        "output_video": args.output_video,
        "output_jsonl": str(Path(args.output_jsonl)),
    }


def init_rtmpose(config_path, checkpoint_path, device):
    try:
        with legacy_openmmlab_checkpoint_load():
            return (
                RTMPoseRunner(
                    pose_config=config_path,
                    pose_checkpoint=checkpoint_path,
                    device=device,
                ),
                None,
            )
    except ImportError as exc:
        return None, f"runtime_import_error: {exc}"
    except Exception as exc:
        return None, f"{type(exc).__name__}: {exc}"


def predict_rtmpose(runner, frame):
    if runner is None:
        return None, None
    try:
        return runner.predict_keypoints(frame), None
    except RTMPoseNoPersonDetectedError as exc:
        return None, f"no_person_detected: {exc}"
    except Exception as exc:
        return None, f"{type(exc).__name__}: {exc}"


def load_motionagformer_3d_by_frame(args):
    if not should_run_motionagformer(args):
        return {}, None
    path = Path(args.motionagformer_npz)
    if not path.exists():
        print(
            {
                "motionagformer_3d": "unavailable",
                "reason": f"missing NPZ: {path}",
            },
        )
        return {}, None
    try:
        joints_3d, frame_indices, key_used = load_coreml_motionagformer_npz(path)
    except Exception as exc:
        print(
            {
                "motionagformer_3d": "failed",
                "reason": f"{type(exc).__name__}: {exc}",
            },
        )
        return {}, None
    return {
        int(frame_idx): joints_3d[index]
        for index, frame_idx in enumerate(frame_indices[: len(joints_3d)])
    }, key_used


def make_empty_hand_3d(args):
    mode = effective_hand_3d_mode(args) if should_run_motionagformer(args) else "none"
    return {
        side: {
            "available": False,
            "mode": mode,
            "world_landmarks": None,
            "local_landmarks": None,
            "draw_landmarks": None,
            "attached_landmarks": None,
            "body_wrist_index": None,
            "body_wrist_3d": None,
            "anchor_error": None,
            "anchor_matches_body_wrist": False,
            "skip_reason": "not_computed",
        }
        for side in ("left", "right")
    }


def build_frame_hand_3d(side_results, body_joints_3d, args):
    mode = effective_hand_3d_mode(args)
    return {
        side: build_hand_3d_overlay(
            hand_result=side_results[side]["hand_result"],
            body_joints_3d=body_joints_3d,
            side=side,
            mode=mode,
            scale=args.hand_3d_scale,
            axis_map=args.hand_3d_axis_map,
            flip_x=args.hand_3d_flip_x,
            flip_y=args.hand_3d_flip_y,
            flip_z=args.hand_3d_flip_z,
        )
        for side in ("left", "right")
    }


def mediapipe_wrists_from_side_results(side_results):
    wrists = {}
    for side in ("left", "right"):
        side_result = side_results.get(side) if side_results is not None else None
        hand_result = None if side_result is None else side_result.get("hand_result")
        if hand_result is None:
            continue
        wrist_px = hand_result.get("wrist_px")
        if wrist_px is not None:
            wrists[side] = wrist_px
    return wrists


def update_motionagformer_wrist_source_counts(counts, wrist_debug):
    update_wrist_source_counts(counts, wrist_debug)


def update_wrist_source_counts(counts, wrist_debug):
    if wrist_debug is None:
        return
    for side in ("left", "right"):
        source_used = wrist_debug.get(side, {}).get("source_used")
        if source_used in counts[side]:
            counts[side][source_used] += 1


def add_side_profile_times(profile_times, side_results):
    crop_combined = 0.0
    hand_combined = 0.0
    estimator_combined = 0.0
    for side in ("left", "right"):
        side_profile = side_results[side].get("profile_times_ms", {})
        crop_ms = side_profile.get("wrist_crop_build_ms")
        hand_ms = side_profile.get("mediapipe_hand_inference_ms")
        estimator_ms = side_profile.get("wrist_estimator_ms")
        if crop_ms is not None:
            profile_times[f"wrist_crop_build_{side}_ms"] = float(crop_ms)
            crop_combined += float(crop_ms)
        if hand_ms is not None:
            profile_times[f"mediapipe_hand_inference_{side}_ms"] = float(hand_ms)
            hand_combined += float(hand_ms)
        if estimator_ms is not None:
            estimator_combined += float(estimator_ms)
    profile_times["wrist_crop_build_combined_ms"] = crop_combined
    profile_times["mediapipe_hand_inference_combined_ms"] = hand_combined
    profile_times["wrist_estimator_combined_ms"] = estimator_combined


def add_record_profile_time(record, key, value):
    if value is None:
        return
    profile_times = record.setdefault("profile_times_ms", {})
    profile_times[key] = float(value)


def make_side_by_side_frame(
    overlay,
    body_joints_3d,
    hand_3d_by_side,
    frame_idx,
    image_w,
    image_h,
    args,
    sizes,
):
    import cv2
    import numpy as np

    if body_joints_3d is None:
        right = make_missing_3d_panel(image_w, image_h, frame_idx, sizes)
    else:
        right = render_right_panel(
            joints=body_joints_3d,
            window_idx=frame_idx,
            source_frame_idx=frame_idx,
            width=image_w,
            height=image_h,
            view_preset=args.view_preset,
            axis_preset=args.axis_preset,
            hand_3d=hand_3d_by_side,
        )
    if right.shape[:2] != overlay.shape[:2]:
        right = cv2.resize(right, (image_w, image_h), interpolation=cv2.INTER_AREA)
    return np.concatenate([overlay, right], axis=1)


def make_missing_3d_panel(image_w, image_h, frame_idx, sizes):
    import cv2
    import numpy as np

    panel = np.full((image_h, image_w, 3), 245, dtype=np.uint8)
    cv2.putText(
        panel,
        f"MotionAGFormer 3D unavailable | frame {frame_idx}",
        (16, 36),
        cv2.FONT_HERSHEY_SIMPLEX,
        sizes["font_scale"],
        (35, 35, 35),
        sizes["text_thickness"],
        cv2.LINE_AA,
    )
    return panel


def create_video_hand_runners(args):
    if args.disable_hands:
        return None, "disabled"
    if args.mediapipe_runtime in ("tasks", "auto"):
        try:
            return (
                create_tasks_hand_runners(
                    task_model_path=args.hand_landmarker_task,
                    running_mode=args.mediapipe_tasks_running_mode,
                    sides=selected_hand_sides(args),
                    delegate=args.mediapipe_tasks_delegate,
                ),
                f"tasks:{args.mediapipe_tasks_running_mode}",
            )
        except (ImportError, MediaPipeHandsRuntimeError) as exc:
            if args.mediapipe_runtime == "tasks":
                print({"mediapipe_runtime": "unavailable", "reason": str(exc)})
                return None, "unavailable"
            print({"mediapipe_runtime": "tasks_unavailable_using_legacy", "reason": str(exc)})
        except Exception as exc:
            if args.mediapipe_runtime == "tasks":
                print({"mediapipe_runtime": "failed", "reason": str(exc)})
                return None, "failed"
            print({"mediapipe_runtime": "tasks_failed_using_legacy", "reason": str(exc)})

    try:
        return (
            {
                side: MediaPipeHandsRunner(
                    static_image_mode=True,
                    max_num_hands=1,
                    min_detection_confidence=0.3,
                    min_tracking_confidence=0.3,
                    cpu_only=True,
                    input_color_format="BGR",
                )
                for side in selected_hand_sides(args)
            },
            "legacy",
        )
    except (ImportError, MediaPipeHandsRuntimeError) as exc:
        print({"mediapipe_runtime": "unavailable", "reason": str(exc)})
        return None, "unavailable"
    except Exception as exc:
        print({"mediapipe_runtime": "failed", "reason": str(exc)})
        return None, "failed"


def selected_hand_sides(args):
    if getattr(args, "hand_sides", "both") == "both":
        return ("left", "right")
    return (args.hand_sides,)


def create_tasks_hand_runners(
    task_model_path,
    running_mode,
    sides=("left", "right"),
    delegate="cpu",
):
    return {
        side: MediaPipeHandLandmarkerRunner(
            task_model_path=task_model_path,
            max_num_hands=1,
            min_detection_confidence=0.3,
            min_presence_confidence=0.3,
            min_tracking_confidence=0.3,
            input_color_format="BGR",
            running_mode=running_mode,
            delegate=delegate,
        )
        for side in sides
    }


def close_hand_runners(hand_runners):
    if not hand_runners:
        return
    seen = set()
    for runner in hand_runners.values():
        if runner is None:
            continue
        runner_id = id(runner)
        if runner_id in seen:
            continue
        seen.add(runner_id)
        runner.close()


def process_side(
    side,
    image,
    image_w,
    image_h,
    body,
    crop_selector,
    smoother,
    estimator,
    hand_runner,
    current_time_sec,
    timestamp_ms,
    hand_crop_mode,
    hand_crop_size,
    wrist_conf_thr,
    profile_enabled=False,
):
    side_body = body[side]
    profile_times = {}
    crop_start = time.perf_counter()
    crop_metadata = build_side_crop(
        side=side,
        image=image,
        image_w=image_w,
        image_h=image_h,
        side_body=side_body,
        crop_selector=crop_selector,
        smoother=smoother,
        hand_crop_mode=hand_crop_mode,
        hand_crop_size=hand_crop_size,
        wrist_conf_thr=wrist_conf_thr,
    )
    if profile_enabled:
        profile_times["wrist_crop_build_ms"] = elapsed_ms(crop_start)
    crop_box = None if crop_metadata is None else crop_metadata.crop_box

    hand_results = []
    hand_runtime_error = None
    if hand_runner is not None and crop_box is not None:
        try:
            hand_start = time.perf_counter()
            hand_results = run_hand_crop(
                hand_runner=hand_runner,
                image=image,
                crop_box=crop_box,
                timestamp_ms=timestamp_ms,
            )
            if profile_enabled:
                profile_times["mediapipe_hand_inference_ms"] = elapsed_ms(hand_start)
        except Exception as exc:
            hand_runtime_error = str(exc)
            if profile_enabled:
                profile_times["mediapipe_hand_inference_ms"] = elapsed_ms(hand_start)
    hand_result = hand_results[0] if hand_results else None

    estimator_start = time.perf_counter()
    estimate = estimator.estimate(
        elbow_px=side_body["elbow_px"],
        wrist_px=side_body["wrist_px"],
        elbow_conf=side_body["elbow_conf"],
        wrist_conf=side_body["wrist_conf"],
        shoulder_width_px=body["shoulder_width_px"],
        hand_landmarks=None if hand_result is None else hand_result["hand_landmarks"],
        hand_world_landmarks=None if hand_result is None else hand_result["hand_world_landmarks"],
        crop_box=crop_box,
        is_right_hand=side == "right",
        current_time_sec=current_time_sec,
    )
    if profile_enabled:
        profile_times["wrist_estimator_ms"] = elapsed_ms(estimator_start)
    return {
        "side": side,
        "side_body": side_body,
        "crop_box": crop_box,
        "crop_metadata": None if crop_metadata is None else crop_metadata.to_dict(),
        "crop_skip_reason": crop_skip_reason(side_body, crop_metadata, wrist_conf_thr),
        "hand_crop_mode": hand_crop_mode,
        "hand_result": hand_result,
        "hand_runtime_error": hand_runtime_error,
        "estimate": estimate,
        "profile_times_ms": profile_times,
    }


def run_hand_crop(hand_runner, image, crop_box, timestamp_ms):
    if getattr(hand_runner, "running_mode", None) == "video":
        return hand_runner.run_crop(image, crop_box, timestamp_ms=timestamp_ms)
    return hand_runner.run_crop(image, crop_box)


def build_side_crop(
    side,
    image,
    image_w,
    image_h,
    side_body,
    crop_selector,
    smoother,
    hand_crop_mode,
    hand_crop_size,
    wrist_conf_thr,
):
    if hand_crop_mode == "wrist":
        return build_wrist_hand_crop(
            frame_shape=image.shape,
            wrist_xy=side_body["wrist_px"],
            crop_size=hand_crop_size,
            side=side,
            confidence=side_body["wrist_conf"],
            confidence_threshold=wrist_conf_thr,
        )

    crop_box = crop_selector.select_crop(
        image_w=image_w,
        image_h=image_h,
        elbow_px=side_body["elbow_px"],
        wrist_px=side_body["wrist_px"],
        hand_bbox=None,
    )
    crop_box = smoother.update(crop_box)
    return crop_metadata_from_box(
        crop_box,
        frame_shape=image.shape,
        side=side,
        confidence=side_body["wrist_conf"],
    )


def crop_skip_reason(side_body, crop_metadata, wrist_conf_thr):
    if crop_metadata is not None:
        return None
    if side_body["wrist_conf"] < wrist_conf_thr:
        return "low_wrist_confidence"
    return "invalid_or_empty_crop"


def make_writer(path, fps, image_w, image_h):
    import cv2

    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(output), fourcc, fps, (image_w, image_h))
    if not writer.isOpened():
        raise RuntimeError(f"Could not open video writer: {output}")
    return writer


def draw_body_failure(image, reason, sizes):
    import cv2

    x1, y1, x2, y2 = 8, 8, min(image.shape[1] - 8, 520), 78
    roi = image[y1:y2, x1:x2]
    black = roi.copy()
    black[:] = (0, 0, 0)
    cv2.addWeighted(black, 0.68, roi, 0.32, 0, dst=roi)
    cv2.putText(
        image,
        "body_detected: False",
        (x1 + 8, y1 + 26),
        cv2.FONT_HERSHEY_SIMPLEX,
        sizes["font_scale"],
        (255, 255, 255),
        sizes["text_thickness"],
        cv2.LINE_AA,
    )
    cv2.putText(
        image,
        str(reason or "no result")[:90],
        (x1 + 8, y1 + 52),
        cv2.FONT_HERSHEY_SIMPLEX,
        sizes["font_scale"],
        (180, 180, 255),
        sizes["text_thickness"],
        cv2.LINE_AA,
    )


def frame_log(
    frame_idx,
    timestamp_sec,
    body_detected,
    image_width,
    image_height,
    side_results,
    hand_3d_by_side,
    visual_body_2d,
    visual_body_wrist_debug,
    motionagformer_input_2d,
    motionagformer_wrist_debug,
    body_joints_3d,
    motionagformer_3d_generation,
    motionagformer_3d_key_used,
    motionagformer_coreml_model_path,
    motionagformer_coreml_model_load_ms,
    motionagformer_coreml_inference_ms,
    args,
):
    run_motionagformer = should_run_motionagformer(args)
    draw_3d_panel = should_draw_3d_panel(args)
    hand_3d_mode = effective_hand_3d_mode(args) if run_motionagformer else "none"
    row = {
        "frame_idx": frame_idx,
        "timestamp_sec": timestamp_sec,
        "body_detected": body_detected,
        "image_width": int(image_width),
        "image_height": int(image_height),
        "mediapipe_tasks_running_mode": (
            args.mediapipe_tasks_running_mode
            if args.mediapipe_runtime in ("tasks", "auto")
            else None
        ),
        "run_motionagformer": run_motionagformer,
        "draw_3d_panel": draw_3d_panel,
        "hand_3d_mode": hand_3d_mode,
        "hand_3d_scale": args.hand_3d_scale,
        "hand_3d_axis_map": args.hand_3d_axis_map,
        "hand_3d_flip_x": bool(args.hand_3d_flip_x),
        "hand_3d_flip_y": bool(args.hand_3d_flip_y),
        "hand_3d_flip_z": bool(args.hand_3d_flip_z),
        "hide_body_wrist_limb_overlay": bool(args.hide_body_wrist_limbs),
        "hide_body_keypoint_labels": bool(args.hide_body_keypoint_labels),
        "hide_body_skeleton": bool(args.hide_body_skeleton),
        "hide_hand_debug_vectors": bool(args.hide_hand_debug_vectors),
        "body_wrist_2d_anchor": args.body_wrist_2d_anchor,
        "visual_body_2d": None if visual_body_2d is None else visual_body_2d.tolist(),
        "motionagformer_wrist_source": args.motionagformer_wrist_source,
        "motionagformer_3d_generation": motionagformer_3d_generation,
        "motionagformer_3d_key_used": motionagformer_3d_key_used,
        "motionagformer_coreml_model_path": motionagformer_coreml_model_path,
        "motionagformer_coreml_model_load_ms": motionagformer_coreml_model_load_ms,
        "motionagformer_coreml_inference_ms": motionagformer_coreml_inference_ms,
        "motionagformer_body_3d": None if body_joints_3d is None else body_joints_3d.tolist(),
        "motionagformer_input_2d": (
            None if motionagformer_input_2d is None else motionagformer_input_2d.tolist()
        ),
        "left": side_log(None if side_results is None else side_results["left"]),
        "right": side_log(None if side_results is None else side_results["right"]),
    }
    for side in ("left", "right"):
        row.update(
            prefixed_hand_landmark_log(
                side,
                None if side_results is None else side_results[side],
            ),
        )
        row.update(prefixed_hand_3d_log(side, hand_3d_by_side.get(side)))
        row.update(prefixed_visual_body_wrist_log(side, visual_body_wrist_debug))
        row.update(prefixed_motionagformer_wrist_log(side, motionagformer_wrist_debug))
        row.update(prefixed_motionagformer_3d_log(side, body_joints_3d))
    return row


def side_log(side_result):
    if side_result is None:
        return {
            "crop_box": None,
            "crop_metadata": None,
            "crop_skip_reason": None,
            "hand_crop_mode": None,
            "hand_detected": False,
            "bend_angle_2d": None,
            "bend_state": None,
        }
    estimate = side_result["estimate"]
    return {
        "crop_box": (
            None
            if side_result["crop_box"] is None
            else tuple(int(value) for value in side_result["crop_box"])
        ),
        "crop_metadata": side_result.get("crop_metadata"),
        "crop_skip_reason": side_result.get("crop_skip_reason"),
        "hand_crop_mode": side_result.get("hand_crop_mode"),
        "hand_detected": side_result["hand_result"] is not None,
        "wrist_confidence": float(side_result["side_body"]["wrist_conf"]),
        "bend_angle_2d": estimate["bend_angle_2d"],
        "bend_state": estimate["bend_state"],
    }


def prefixed_hand_landmark_log(side, side_result):
    prefix = f"{side}_"
    empty = {
        f"{prefix}hand_landmarks_px": None,
        f"{prefix}hand_landmarks_normalized": None,
        f"{prefix}hand_world_landmarks": None,
        f"{prefix}mediapipe_wrist_px": None,
        f"{prefix}mediapipe_middle_mcp_px": None,
        f"{prefix}mediapipe_index_mcp_px": None,
        f"{prefix}mediapipe_pinky_mcp_px": None,
    }
    if side_result is None or side_result["hand_result"] is None:
        return empty

    hand_result = side_result["hand_result"]
    hand_landmarks = hand_result.get("hand_landmarks")
    hand_world_landmarks = hand_result.get("hand_world_landmarks")
    crop_box = hand_result.get("crop_box") or side_result["crop_box"]
    if hand_landmarks is None or crop_box is None:
        return empty

    px_landmarks = hand_landmarks_to_image_px(hand_landmarks, crop_box)
    normalized_landmarks = hand_landmarks_to_xyz(hand_landmarks)
    world_landmarks = (
        None
        if hand_world_landmarks is None
        else hand_landmarks_to_xyz(hand_world_landmarks)
    )
    return {
        f"{prefix}hand_landmarks_px": px_landmarks,
        f"{prefix}hand_landmarks_normalized": normalized_landmarks,
        f"{prefix}hand_world_landmarks": world_landmarks,
        f"{prefix}mediapipe_wrist_px": landmark_at(px_landmarks, 0),
        f"{prefix}mediapipe_middle_mcp_px": landmark_at(px_landmarks, 9),
        f"{prefix}mediapipe_index_mcp_px": landmark_at(px_landmarks, 5),
        f"{prefix}mediapipe_pinky_mcp_px": landmark_at(px_landmarks, 17),
    }


def prefixed_hand_3d_log(side, hand_3d):
    prefix = f"{side}_"
    if not hand_3d:
        return {
            f"{prefix}hand_3d_available": False,
            f"{prefix}hand_3d_skip_reason": "not_computed",
            f"{prefix}hand_3d_local_landmarks": None,
            f"{prefix}attached_hand_3d_landmarks": None,
            f"{prefix}body_wrist_3d": None,
            f"{prefix}hand_3d_anchor_error": None,
            f"{prefix}hand_3d_anchor_matches_body_wrist": False,
        }
    return {
        f"{prefix}hand_3d_available": bool(hand_3d.get("available")),
        f"{prefix}hand_3d_skip_reason": hand_3d.get("skip_reason"),
        f"{prefix}hand_3d_local_landmarks": hand_3d.get("local_landmarks"),
        f"{prefix}attached_hand_3d_landmarks": hand_3d.get("attached_landmarks"),
        f"{prefix}body_wrist_3d": hand_3d.get("body_wrist_3d"),
        f"{prefix}hand_3d_anchor_error": hand_3d.get("anchor_error"),
        f"{prefix}hand_3d_anchor_matches_body_wrist": bool(
            hand_3d.get("anchor_matches_body_wrist"),
        ),
    }


def prefixed_visual_body_wrist_log(side, wrist_debug):
    prefix = f"{side}_"
    side_debug = None if wrist_debug is None else wrist_debug.get(side)
    if side_debug is None:
        return {
            f"{prefix}body_wrist_2d_source_used": None,
            f"{prefix}visual_body_wrist_px": None,
        }
    return {
        f"{prefix}body_wrist_2d_source_used": side_debug.get("source_used"),
        f"{prefix}visual_body_wrist_px": side_debug.get("visual_body_wrist_px"),
    }


def prefixed_motionagformer_wrist_log(side, wrist_debug):
    prefix = f"{side}_"
    side_debug = None if wrist_debug is None else wrist_debug.get(side)
    if side_debug is None:
        return {
            f"{prefix}motionagformer_wrist_source_used": None,
            f"{prefix}rtmpose_wrist_px": None,
            f"{prefix}mediapipe_wrist_px": None,
            f"{prefix}motionagformer_input_wrist_px": None,
        }
    return {
        f"{prefix}motionagformer_wrist_source_used": side_debug.get("source_used"),
        f"{prefix}rtmpose_wrist_px": side_debug.get("rtmpose_wrist_px"),
        f"{prefix}mediapipe_wrist_px": side_debug.get("mediapipe_wrist_px"),
        f"{prefix}motionagformer_input_wrist_px": side_debug.get(
            "motionagformer_input_wrist_px",
        ),
    }


def prefixed_motionagformer_3d_log(side, body_joints_3d):
    prefix = f"{side}_"
    debug = motionagformer_body_3d_debug(body_joints_3d).get(side, {})
    return {
        f"{prefix}motionagformer_wrist_3d": debug.get("wrist_3d"),
        f"{prefix}motionagformer_elbow_3d": debug.get("elbow_3d"),
        f"{prefix}motionagformer_elbow_wrist_length_3d": debug.get(
            "elbow_wrist_length_3d",
        ),
    }


def hand_landmarks_to_image_px(hand_landmarks, crop_box):
    x1, y1, x2, y2 = crop_box
    points = []
    for landmark in hand_landmarks.landmark:
        point = crop_to_image_coords(landmark, x1, y1, x2, y2)
        points.append([float(point[0]), float(point[1])])
    return points


def hand_landmarks_to_xyz(landmarks):
    return [
        [
            float(landmark.x),
            float(landmark.y),
            float(getattr(landmark, "z", 0.0)),
        ]
        for landmark in landmarks.landmark
    ]


def landmark_at(points, index):
    if points is None or len(points) <= index:
        return None
    return [float(points[index][0]), float(points[index][1])]


PROFILE_TOTAL_COMPONENTS = (
    "video_read_decode_ms",
    "rtmpose_inference_ms",
    "body_postprocess_ms",
    "wrist_crop_build_combined_ms",
    "mediapipe_hand_inference_combined_ms",
    "wrist_estimator_combined_ms",
    "motionagformer_inference_ms",
    "hand_3d_attach_ms",
    "render_video_read_decode_ms",
    "overlay_2d_draw_ms",
    "render_3d_draw_ms",
    "video_writer_ms",
    "jsonl_logging_ms",
)

PROFILE_STAGE_ORDER = (
    "video_read_decode_ms",
    "rtmpose_inference_ms",
    "body_postprocess_ms",
    "wrist_crop_build_left_ms",
    "wrist_crop_build_right_ms",
    "wrist_crop_build_combined_ms",
    "mediapipe_hand_inference_left_ms",
    "mediapipe_hand_inference_right_ms",
    "mediapipe_hand_inference_combined_ms",
    "wrist_estimator_combined_ms",
    "motionagformer_inference_ms",
    "motionagformer_live_pytorch_ms",
    "motionagformer_coreml_ms",
    "motionagformer_npz_replay_ms",
    "hand_3d_attach_ms",
    "render_video_read_decode_ms",
    "overlay_2d_draw_ms",
    "render_3d_draw_ms",
    "video_writer_ms",
    "jsonl_logging_ms",
    "total_per_frame_ms",
)


def build_profile_report(
    records,
    args,
    video_meta,
    pass_status,
    motionagformer_status,
    hand_3d_counts,
    render_status,
    total_wall_ms,
):
    rows = profile_rows(records)
    warmup = max(0, min(int(args.profile_warmup_frames), len(rows)))
    measured_rows = rows[warmup:]
    total_frames = len(rows)
    measured_frames = len(measured_rows)
    total_stage_ms = sum(row["total_per_frame_ms"] for row in rows)
    measured_stage_ms = sum(row["total_per_frame_ms"] for row in measured_rows)
    model_load_ms = {
        "rtmpose": pass_status.get("model_load_ms", {}).get("rtmpose"),
        "mediapipe_hand": pass_status.get("model_load_ms", {}).get("mediapipe_hand"),
        "motionagformer_pytorch": (
            motionagformer_status.get("model_load_ms")
            if motionagformer_status.get("generation") == "live_pytorch"
            else None
        ),
        "motionagformer_coreml": (
            motionagformer_status.get("model_load_ms")
            if motionagformer_status.get("generation") == "coreml"
            else None
        ),
        "video_writer_open": render_status.get("video_writer_open_ms"),
    }
    return {
        "video": args.video,
        "output_video": args.output_video,
        "output_jsonl": str(Path(args.output_jsonl)),
        "source_fps": float(video_meta.get("fps", 0.0)),
        "processed_frames": int(pass_status["processed_frames"]),
        "run_motionagformer": should_run_motionagformer(args),
        "draw_3d_panel": should_draw_3d_panel(args),
        "hand_3d_mode": effective_hand_3d_mode(args) if should_run_motionagformer(args) else "none",
        "profile_warmup_frames": warmup,
        "measured_frames_excluding_warmup": measured_frames,
        "total_wall_clock_ms": float(total_wall_ms),
        "overall_fps_wall_clock": fps_from_ms(total_wall_ms, total_frames),
        "overall_fps_stage_sum": fps_from_ms(total_stage_ms, total_frames),
        "fps_excluding_warmup_stage_sum": fps_from_ms(measured_stage_ms, measured_frames),
        "model_load_ms": model_load_ms,
        "motionagformer_3d_generation": motionagformer_status.get("generation"),
        "motionagformer_3d_key_used": motionagformer_status.get("key_used"),
        "motionagformer_3d_warning": motionagformer_status.get("warning"),
        "body_detected_count": pass_status["body_detected_count"],
        "left_hand_detected_count": pass_status["left_hand_detected_count"],
        "right_hand_detected_count": pass_status["right_hand_detected_count"],
        "left_hand_3d_available_count": hand_3d_counts["left"],
        "right_hand_3d_available_count": hand_3d_counts["right"],
        "body_wrist_2d_anchor": args.body_wrist_2d_anchor,
        "body_wrist_2d_source_counts": pass_status["body_wrist_2d_source_counts"],
        "motionagformer_wrist_source": args.motionagformer_wrist_source,
        "motionagformer_wrist_source_counts": pass_status["motionagformer_wrist_source_counts"],
        "hand_3d_anchor_invariant": hand_anchor_invariant(records),
        "stages_all_frames": profile_stage_stats(rows),
        "stages_excluding_warmup": profile_stage_stats(measured_rows),
        "main_bottleneck_excluding_warmup": main_bottleneck(profile_stage_stats(measured_rows)),
        "rendering_vs_inference_excluding_warmup": rendering_vs_inference(measured_rows),
        "ane_verified": False,
    }


def profile_rows(records):
    rows = []
    for record in records:
        times = dict(record.get("profile_times_ms") or {})
        times["total_per_frame_ms"] = sum(
            float(times.get(key, 0.0))
            for key in PROFILE_TOTAL_COMPONENTS
        )
        rows.append(times)
    return rows


def profile_stage_stats(rows):
    stats = {}
    for key in PROFILE_STAGE_ORDER:
        values = [float(row[key]) for row in rows if key in row and row[key] is not None]
        if values:
            stats[key] = summarize_values(values)
    return stats


def summarize_values(values):
    sorted_values = sorted(float(value) for value in values)
    total = sum(sorted_values)
    mean = total / len(sorted_values)
    return {
        "count": len(sorted_values),
        "total_ms": total,
        "mean_ms": mean,
        "median_ms": percentile(sorted_values, 50),
        "p95_ms": percentile(sorted_values, 95),
        "max_ms": sorted_values[-1],
        "fps_from_mean_ms": None if mean <= 1e-12 else 1000.0 / mean,
    }


def percentile(sorted_values, pct):
    if not sorted_values:
        return None
    if len(sorted_values) == 1:
        return sorted_values[0]
    rank = (len(sorted_values) - 1) * (pct / 100.0)
    lo = int(rank)
    hi = min(lo + 1, len(sorted_values) - 1)
    weight = rank - lo
    return sorted_values[lo] * (1.0 - weight) + sorted_values[hi] * weight


def fps_from_ms(total_ms, frame_count):
    if frame_count <= 0 or total_ms <= 1e-12:
        return None
    return 1000.0 * frame_count / total_ms


def hand_anchor_invariant(records, tolerance=1e-6):
    errors = []
    checked = 0
    for record in records:
        hand_3d_by_side = record.get("hand_3d_by_side") or {}
        for side in ("left", "right"):
            hand_3d = hand_3d_by_side.get(side) or {}
            error = hand_3d.get("anchor_error")
            if error is None:
                continue
            checked += 1
            errors.append(float(error))
    worst = max(errors) if errors else None
    return {
        "checked_count": checked,
        "worst_anchor_error": worst,
        "all_within_tolerance": bool(errors) and worst <= tolerance,
        "tolerance": tolerance,
    }


def main_bottleneck(stage_stats):
    candidates = {
        key: value
        for key, value in stage_stats.items()
        if key != "total_per_frame_ms"
    }
    if not candidates:
        return None
    key = max(candidates, key=lambda name: candidates[name]["mean_ms"])
    return {
        "stage": key,
        "mean_ms": candidates[key]["mean_ms"],
        "p95_ms": candidates[key]["p95_ms"],
    }


def rendering_vs_inference(rows):
    inference_keys = (
        "rtmpose_inference_ms",
        "mediapipe_hand_inference_combined_ms",
        "motionagformer_inference_ms",
    )
    rendering_keys = (
        "overlay_2d_draw_ms",
        "render_3d_draw_ms",
        "video_writer_ms",
        "jsonl_logging_ms",
    )
    inference_ms = sum(sum(float(row.get(key, 0.0)) for key in inference_keys) for row in rows)
    rendering_ms = sum(sum(float(row.get(key, 0.0)) for key in rendering_keys) for row in rows)
    return {
        "inference_total_ms": inference_ms,
        "rendering_total_ms": rendering_ms,
        "rendering_over_inference_ratio": (
            None if inference_ms <= 1e-12 else rendering_ms / inference_ms
        ),
        "rendering_dominates_inference": rendering_ms > inference_ms,
    }


def profile_output_path(args):
    if args.profile_output_json:
        return Path(args.profile_output_json)
    if args.output_jsonl:
        path = Path(args.output_jsonl)
        return path.with_name(f"{path.stem}_profile.json")
    path = Path(args.output_video)
    return path.with_name(f"{path.stem}_profile.json")


def print_profile_summary(report, profile_path):
    print(
        {
            "profile_output_json": str(profile_path),
            "overall_fps_wall_clock": report["overall_fps_wall_clock"],
            "fps_excluding_warmup_stage_sum": report["fps_excluding_warmup_stage_sum"],
            "main_bottleneck_excluding_warmup": report["main_bottleneck_excluding_warmup"],
            "rendering_vs_inference_excluding_warmup": report["rendering_vs_inference_excluding_warmup"],
        },
    )
    print("profile stages excluding warmup:")
    for key, value in report["stages_excluding_warmup"].items():
        print(
            f"  {key}: count={value['count']} mean={value['mean_ms']:.3f} "
            f"median={value['median_ms']:.3f} p95={value['p95_ms']:.3f} "
            f"max={value['max_ms']:.3f}",
        )


def elapsed_ms(start):
    return (time.perf_counter() - start) * 1000.0


def mean_or_none(values):
    valid = [float(value) for value in values if value is not None]
    if not valid:
        return None
    return sum(valid) / len(valid)


def median_or_none(values):
    valid = sorted(float(value) for value in values if value is not None)
    if not valid:
        return None
    middle = len(valid) // 2
    if len(valid) % 2:
        return valid[middle]
    return (valid[middle - 1] + valid[middle]) / 2.0


if __name__ == "__main__":
    raise SystemExit(main())
