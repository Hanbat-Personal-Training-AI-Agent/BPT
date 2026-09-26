"""Compare the full pose pipeline with and without the RTMDet person-crop front-end.

A (no detector): full image bbox -> RTMPose-s -> ...
B (detector):    PersonCropTracker crop from RTMDet-tiny detections -> RTMPose-s -> ...
Shared tail: COCO17->H36M17 -> 27-frame lookahead window -> MotionAGFormer-XS.
With --with-hands, before that: wrist crop (side = --hand-crop-ratio x person height) -> MediaPipe
Hand (VIDEO mode, per side) -> drop MediaPipe wrists closer to the opposite
RTMPose wrist -> replace COCO wrists -> COCO17->H36M17 -> 27-frame lookahead
window -> MotionAGFormer-XS. Person height is the RTMDet union box height in B
and the RTMPose keypoint extent in A (and in B before the first detection). RTMPose-s and MotionAGFormer-XS run as Core ML.

Detections come from (bpt-ai env, needs mmdet):
    python scripts/visualize_rtmdet_tiny_person_video.py --video V --output O --save-dets D.json
Run this script in the base env (needs coremltools + mediapipe). No ground truth
is used; metrics are confidence, temporal jitter and 3D bone-length consistency.
"""
import argparse
import json
import sys
from types import SimpleNamespace
from pathlib import Path

import coremltools as ct
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / "scripts")]
import run_coreml_rtmpose_s_motionagformer_xs_pipeline as P  # noqa: E402
import visualize_rtmpose_body_and_both_hands_video as V  # noqa: E402
from pose_feedback.body.motionagformer_adapter import (  # noqa: E402
    coco17_to_motionagformer_h36m17,
    normalize_motionagformer_2d,
)
from pose_feedback.body.motionagformer_buffer import MotionAGFormerWindowBuilder  # noqa: E402
from pose_feedback.body.motionagformer_wrist_source import (  # noqa: E402
    build_motionagformer_input_2d,
    reject_crossed_mediapipe_wrists,
)
from pose_feedback.body.person_crop_tracker import PersonCropTracker  # noqa: E402

BODY = list(range(5, 17))  # COCO shoulders..ankles
WRISTS = [9, 10]
COLOR_A = (0, 140, 255)  # orange: full image
COLOR_B = (255, 200, 0)  # cyan: person crop


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--video", required=True)
    p.add_argument("--dets-json", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--rtmpose-coreml", default="ios/Runner/NativePose/Models/rtmpose_s_forward.mlpackage")
    p.add_argument("--motionagformer-coreml", default="assets/coreml/motionagformer_xs.mlpackage")
    p.add_argument("--with-hands", action="store_true",
                   help="insert the MediaPipe Hand wrist-replacement stage (off by default)")
    p.add_argument("--hand-landmarker-task", default="ios/Runner/NativePose/Models/hand_landmarker.task")
    p.add_argument("--hand-crop-ratio", type=float, default=0.15,
                   help="hand crop side / person height; hand length is ~0.11 of body height")
    p.add_argument("--lookahead", type=int, default=5)
    p.add_argument("--score-thr", type=float, default=0.5)
    p.add_argument("--min-iou", type=float, default=0.5)
    return p.parse_args()


def run_rtmpose(model, frame, center, scale):
    w, h = P.RTMPOSE_INPUT_SIZE
    warp = P.get_warp_matrix(center, scale, 0.0, P.RTMPOSE_INPUT_SIZE)
    inv = P.get_warp_matrix(center, scale, 0.0, P.RTMPOSE_INPUT_SIZE, inv=True)
    rgb = cv2.cvtColor(cv2.warpAffine(frame, warp, (w, h), flags=cv2.INTER_LINEAR), cv2.COLOR_BGR2RGB)
    tensor = ((rgb.astype("float32") - P.MEAN_RGB) / P.STD_RGB).transpose(2, 0, 1)[None]
    pred = model.predict({P.RTMPOSE_INPUT_NAME: tensor})
    locs, scores = P.decode_simcc(np.asarray(pred[P.RTMPOSE_OUTPUT_X]), np.asarray(pred[P.RTMPOSE_OUTPUT_Y]))
    return np.concatenate([P.apply_affine_to_points(locs[0], inv), scores[0, :, None]], axis=-1)


def keypoint_height(coco):
    return float(coco[:, 1].max() - coco[:, 1].min())


def run_hand_stage(frames, coco_seq, person_heights, fps, task_path, crop_ratio):
    """Wrist crop -> MediaPipe Hand -> MotionAGFormer input with MediaPipe wrists."""
    runners, status = V.create_video_hand_runners(SimpleNamespace(
        disable_hands=False, mediapipe_runtime="tasks", hand_landmarker_task=task_path,
        mediapipe_tasks_running_mode="video", mediapipe_tasks_delegate="cpu", hand_sides="both",
    ))
    if runners is None:
        raise RuntimeError(f"MediaPipe Hand unavailable: {status}")
    config = V.PUSHUP_SIDE_CONFIG
    crop_selector = V.HandCropSelector()
    smoothers = {s: V.CropBoxSmoother(alpha=config.crop_smoothing_alpha) for s in ("left", "right")}
    estimators = {s: V.WristEstimator(config) for s in ("left", "right")}
    motion_in, hand_boxes, replaced, crossed = [], [], [], 0
    try:
        for i, (frame, coco, person_h) in enumerate(zip(frames, coco_seq, person_heights)):
            ih, iw = frame.shape[:2]
            body = V.coco_yolo_keypoints_to_body(coco, min_confidence=0.3)
            side_results = {
                side: V.process_side(
                    side=side, image=frame, image_w=iw, image_h=ih, body=body,
                    crop_selector=crop_selector, smoother=smoothers[side], estimator=estimators[side],
                    hand_runner=runners.get(side), current_time_sec=i / fps,
                    timestamp_ms=int(round(i * 1000.0 / fps)), hand_crop_mode="wrist",
                    hand_crop_size=max(1, round(crop_ratio * person_h)), wrist_conf_thr=0.3,
                )
                for side in ("left", "right")
            }
            found = V.mediapipe_wrists_from_side_results(side_results)
            wrists = reject_crossed_mediapipe_wrists(coco, found)
            crossed += len(found) - len(wrists)
            inp, _ = build_motionagformer_input_2d(coco, mediapipe_wrists_px=wrists, wrist_source="mediapipe")
            motion_in.append(inp)
            hand_boxes.append([r["crop_box"] for r in side_results.values() if r["crop_box"] is not None])
            replaced.append([side in wrists for side in ("left", "right")])
    finally:
        V.close_hand_runners(runners)
    return np.stack(motion_in), hand_boxes, np.array(replaced), crossed


def run_motion(model, coco_seq, image_w, image_h, lookahead):
    norm = []
    for coco in coco_seq:
        xy, conf = coco17_to_motionagformer_h36m17(coco)
        norm.append(np.concatenate([normalize_motionagformer_2d(xy, image_w, image_h), conf[:, None]], axis=-1))
    norm = np.stack(norm).astype("float32")
    builder = MotionAGFormerWindowBuilder(window_size=P.MOTION_WINDOW_SIZE)
    select = P.MOTION_WINDOW_SIZE - 1 - lookahead
    out = []
    for i in range(len(norm)):
        window, _ = builder.build_lookahead_padded(norm, i, lookahead)
        pred = model.predict({P.MOTION_INPUT_NAME: window[None].astype("float32")})
        out.append(np.asarray(pred[P.MOTION_OUTPUT_NAME])[0, select])
    return np.stack(out)


def accel(x):
    return float(np.linalg.norm(x[2:] - 2 * x[1:-1] + x[:-2], axis=-1).mean())


def metrics(coco, pred3d, replaced, crossed):
    acc2d = accel(coco[:, BODY, :2])
    rel = pred3d - pred3d[:, :1]
    acc3d = np.linalg.norm(rel[2:] - 2 * rel[1:-1] + rel[:-2], axis=-1).mean()
    bones = np.stack([np.linalg.norm(pred3d[:, a] - pred3d[:, b], axis=-1) for a, b in P.H36M_SKELETON], axis=1)
    return {
        "mean_body_conf_2d": float(coco[:, BODY, 2].mean()),
        "low_conf_joint_ratio_2d(<0.4)": float((coco[:, BODY, 2] < 0.4).mean()),
        "mediapipe_wrist_replaced_ratio(left,right)": replaced.mean(0).round(3).tolist(),
        "mediapipe_wrong_hand_rejected": crossed,
        "jitter_2d_accel_px": acc2d,
        "jitter_2d_wrist_accel_px": accel(coco[:, WRISTS, :2]),
        "jitter_3d_accel": float(acc3d),
        "bone_length_cv_3d": float((bones.std(0) / bones.mean(0)).mean()),
    }


def draw_2d(img, coco, color):
    # Drawn regardless of confidence so a low-confidence baseline stays visible.
    for a, b in P.COCO_SKELETON:
        cv2.line(img, P.point(coco[a]), P.point(coco[b]), color, 2, cv2.LINE_AA)
    for kp in coco:
        cv2.circle(img, P.point(kp), 3, color, -1, cv2.LINE_AA)


def draw_3d_overlay(panel, a3d, b3d):
    h, w = panel.shape[:2]
    views = [("front x/y", (0, 1)), ("side z/y", (2, 1)), ("top x/z", (0, 2))]
    cw = w // len(views)
    for vi, (label, axes) in enumerate(views):
        x0 = vi * cw
        cv2.rectangle(panel, (x0, 0), (x0 + cw - 1, h - 1), (200, 200, 200), 1)
        pa, pb = (j[:, axes] - j[:1, axes] for j in (a3d, b3d))  # pelvis-centred
        span = float(max(np.abs(pa).max(), np.abs(pb).max())) or 1.0
        s = 0.42 * min(cw, h) / span
        c = np.array([x0 + cw / 2, h / 2])
        for pts, color in ((pa, COLOR_A), (pb, COLOR_B)):
            d = pts * np.array([s, -s]) + c
            for a, b in P.H36M_SKELETON:
                cv2.line(panel, P.point(d[a]), P.point(d[b]), color, 2, cv2.LINE_AA)
        cv2.putText(panel, label, (x0 + 8, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (60, 60, 60), 1)


def main():
    args = parse_args()
    dets = json.loads(Path(args.dets_json).read_text())
    rtm = ct.models.MLModel(args.rtmpose_coreml)
    motion = ct.models.MLModel(args.motionagformer_coreml)
    aspect = P.RTMPOSE_INPUT_SIZE[0] / P.RTMPOSE_INPUT_SIZE[1]
    tracker = PersonCropTracker(score_thr=args.score_thr, min_iou=args.min_iou, aspect_wh=aspect)

    cap = cv2.VideoCapture(args.video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frames, coco_a, coco_b, crops, heights_b = [], [], [], [], []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        ih, iw = frame.shape[:2]
        full_scale = P.fix_aspect_ratio(np.array([iw, ih], "float32") * 1.25, aspect)  # same as app/full-image path
        coco_a.append(run_rtmpose(rtm, frame, np.array([iw / 2, ih / 2], "float32"), full_scale))
        _, crop = tracker.update(dets[len(frames)])
        crops.append(crop)
        heights_b.append(None if tracker.union is None else tracker.union[3] - tracker.union[1])
        if crop is None:  # no person yet: fall back to full image
            coco_b.append(coco_a[-1])
        else:
            x1, y1, x2, y2 = crop  # tracker already padded and fixed the aspect ratio
            coco_b.append(run_rtmpose(rtm, frame, np.array([(x1 + x2) / 2, (y1 + y2) / 2], "float32"),
                                      np.array([x2 - x1, y2 - y1], "float32")))
        frames.append(frame)
    cap.release()
    coco_a, coco_b = np.stack(coco_a), np.stack(coco_b)
    ih, iw = frames[0].shape[:2]
    # 2D shown/measured below is the MotionAGFormer input, i.e. after wrist replacement.
    heights_a = [keypoint_height(c) for c in coco_a]
    heights_b = [h if h is not None else keypoint_height(c) for h, c in zip(heights_b, coco_b)]
    if args.with_hands:
        coco_a, hand_a, rep_a, crossed_a = run_hand_stage(
            frames, coco_a, heights_a, fps, args.hand_landmarker_task, args.hand_crop_ratio)
        coco_b, hand_b, rep_b, crossed_b = run_hand_stage(
            frames, coco_b, heights_b, fps, args.hand_landmarker_task, args.hand_crop_ratio)
    else:
        hand_a = hand_b = [[] for _ in frames]
        rep_a = rep_b = np.zeros((len(frames), 2), bool)
        crossed_a = crossed_b = 0
    a3d = run_motion(motion, coco_a, iw, ih, args.lookahead)
    b3d = run_motion(motion, coco_b, iw, ih, args.lookahead)

    ra, rb = a3d - a3d[:, :1], b3d - b3d[:, :1]
    summary = {
        "frames": len(frames),
        "hand_crop_ratio": args.hand_crop_ratio,
        "A_no_detector": metrics(coco_a, a3d, rep_a, crossed_a),
        "B_rtmdet_person_crop": metrics(coco_b, b3d, rep_b, crossed_b),
        "A_vs_B_2d_mean_px": float(np.linalg.norm(coco_a[:, BODY, :2] - coco_b[:, BODY, :2], axis=-1).mean()),
        "A_vs_B_3d_mpjpe_pelvis_rel": float(np.linalg.norm(ra - rb, axis=-1).mean()),
    }
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.with_suffix(".json").write_text(json.dumps(summary, indent=2))
    np.savez(out.with_suffix(".npz"), coco_a=coco_a, coco_b=coco_b, pred3d_a=a3d, pred3d_b=b3d)

    half = 540
    size = (half * 2, half + 360)
    writer = cv2.VideoWriter(str(out), cv2.VideoWriter_fourcc(*"mp4v"), fps, size)
    sx = half / iw
    for i, frame in enumerate(frames):
        left, right = frame.copy(), frame.copy()
        draw_2d(left, coco_a[i], COLOR_A)
        draw_2d(right, coco_b[i], COLOR_B)
        for img, boxes in ((left, hand_a[i]), (right, hand_b[i])):
            for x1, y1, x2, y2 in boxes:
                cv2.rectangle(img, (int(x1), int(y1)), (int(x2), int(y2)), (255, 255, 255), 1)
        if crops[i] is not None:
            x1, y1, x2, y2 = map(int, crops[i])
            cv2.rectangle(right, (x1, y1), (x2, y2), (0, 0, 255), 2)
        left, right = (cv2.resize(x, (half, int(ih * sx))) for x in (left, right))
        for img, label, coco, rep, color in ((left, "A: no detector", coco_a[i], rep_a[i], COLOR_A),
                                             (right, "B: RTMDet person crop", coco_b[i], rep_b[i], COLOR_B)):
            cv2.putText(img, label, (10, 26), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
            cv2.putText(img, f"frame {i}  body conf {coco[BODY, 2].mean():.2f}", (10, 52),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
            cv2.putText(img, f"MP wrist L:{'Y' if rep[0] else '-'} R:{'Y' if rep[1] else '-'}", (10, 76),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
        panel = np.full((360, half * 2, 3), 255, np.uint8)
        draw_3d_overlay(panel, a3d[i], b3d[i])
        cv2.putText(panel, "3D MotionAGFormer-XS  orange=A  cyan=B", (10, 350),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (60, 60, 60), 1)
        writer.write(np.vstack([np.hstack([left, right]), panel]))
    writer.release()
    print(json.dumps(summary, indent=2))
    print(f"output={out}")


if __name__ == "__main__":
    main()
