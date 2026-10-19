"""lift-compare stage 2 (Home, bpt-home, CPU): MediaPipe Hand wrist replacement on the stage-1 2D (Fit3D).

Same rule as scripts/compare_person_crop_rtmpose_motionagformer.py run_hand_stage (copied: that file imports
coremltools at module level): wrist crop side = 0.15 x keypoint height, MediaPipe Hand Landmarker VIDEO mode per side
(the app's hand_landmarker.task), drop a MediaPipe wrist nearer the opposite RTMPose wrist, then
build_motionagformer_input_2d(wrist_source="mediapipe"). Run once for COCO17 and once for Halpe26 joints 0-16.

usage: mp_wrists_fit3d.py --root ~/datasets/fit3d --pose2d RUN/pose2d --out RUN/mpwrist --task hand_landmarker.task [--jobs 6]
"""
import argparse, glob, os, sys
from multiprocessing import Pool
from pathlib import Path
from types import SimpleNamespace
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
A = None


def run_hand_stage(V, frames, coco_seq, fps, task_path, crop_ratio=0.15):
    from pose_feedback.body.motionagformer_wrist_source import build_motionagformer_input_2d, reject_crossed_mediapipe_wrists
    runners, status = V.create_video_hand_runners(SimpleNamespace(
        disable_hands=False, mediapipe_runtime="tasks", hand_landmarker_task=task_path,
        mediapipe_tasks_running_mode="video", mediapipe_tasks_delegate="cpu", hand_sides="both"))
    if runners is None:
        raise RuntimeError(f"MediaPipe Hand unavailable: {status}")
    config = V.PUSHUP_SIDE_CONFIG
    crop_selector = V.HandCropSelector()
    smoothers = {s: V.CropBoxSmoother(alpha=config.crop_smoothing_alpha) for s in ("left", "right")}
    estimators = {s: V.WristEstimator(config) for s in ("left", "right")}
    motion_in, replaced, crossed = [], [], 0
    try:
        for i, (frame, coco) in enumerate(zip(frames, coco_seq)):
            ih, iw = frame.shape[:2]
            person_h = float(coco[:, 1].max() - coco[:, 1].min())
            body = V.coco_yolo_keypoints_to_body(coco, min_confidence=0.3)
            side_results = {side: V.process_side(
                side=side, image=frame, image_w=iw, image_h=ih, body=body, crop_selector=crop_selector,
                smoother=smoothers[side], estimator=estimators[side], hand_runner=runners.get(side),
                current_time_sec=i / fps, timestamp_ms=int(round(i * 1000.0 / fps)), hand_crop_mode="wrist",
                hand_crop_size=max(1, round(crop_ratio * person_h)), wrist_conf_thr=0.3) for side in ("left", "right")}
            found = V.mediapipe_wrists_from_side_results(side_results)
            wrists = reject_crossed_mediapipe_wrists(coco, found)
            crossed += len(found) - len(wrists)
            inp, _ = build_motionagformer_input_2d(coco, mediapipe_wrists_px=wrists, wrist_source="mediapipe")
            motion_in.append(inp); replaced.append([side in wrists for side in ("left", "right")])
    finally:
        V.close_hand_runners(runners)
    return np.stack(motion_in), np.array(replaced), crossed


def job(npz):
    import cv2
    sys.path[:0] = [str(ROOT), str(ROOT / 'scripts')]
    import visualize_rtmpose_body_and_both_hands_video as V
    name = os.path.basename(npz)[:-4]; out = f'{A.out}/{name}.npz'
    if os.path.exists(out): return name
    subj, cam, ex = name.split('_', 2)
    d = np.load(npz); want = {int(p): k for k, p in enumerate(d['pick'])}
    cap = cv2.VideoCapture(f'{A.root}/train/{subj}/videos/{cam}/{ex}.mp4'); frames = [None] * len(want); i = 0
    while True:
        ok, img = cap.read()
        if not ok: break
        if i in want: frames[want[i]] = img  # BGR, as the reference script (runner converts)
        i += 1
    res = {}
    for key, kp in (('coco', d['coco']), ('halpe', d['halpe'][:, :17])):
        x, rep, crossed = run_hand_stage(V, frames, kp, 30.0, A.task)
        res[f'{key}_in'] = x.astype(np.float32); res[f'{key}_replaced'] = rep; res[f'{key}_crossed'] = crossed
    np.savez(out + '.tmp.npz', **res); os.replace(out + '.tmp.npz', out)
    return name


def main():
    global A
    p = argparse.ArgumentParser()
    p.add_argument('--root', required=True); p.add_argument('--pose2d', required=True); p.add_argument('--out', required=True)
    p.add_argument('--task', required=True); p.add_argument('--jobs', type=int, default=6)
    p.add_argument('--only', default=None, help='comma list of video names')
    A = p.parse_args(); os.makedirs(A.out, exist_ok=True)
    files = sorted(glob.glob(f'{A.pose2d}/*.npz'))
    if A.only: files = [f for f in files if os.path.basename(f)[:-4] in A.only.split(',')]
    with Pool(A.jobs) as pool:
        for n in pool.imap_unordered(job, files): print(n, flush=True)


if __name__ == '__main__':
    main()
