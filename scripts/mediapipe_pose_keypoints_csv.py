"""MediaPipe Pose Landmarker (VIDEO mode, whole frame, one person) -> COCO-17 keypoint CSV in pose-replay's format,
so the app's evaluators can replay it with `pose-replay --keypoints-csv` (push-up candidate, D-T3-12).

Mapping and confidence as the iPhone bench (tools/pose_model_bench/Host/MediaPipeBench.swift, eval_mediapipe_pose2d.py):
BlazePose 33 -> COCO-17 by BLAZEPOSE_COCO17, pixel = normalized * frame size, confidence = landmark visibility.
No person -> all joints (0, 0, 0).
usage: python mediapipe_pose_keypoints_csv.py --model pose_landmarker_full.task --out-dir DIR video.mp4 ...
"""
import argparse
import os

BLAZEPOSE_COCO17 = [0, 2, 5, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]


def row(i, t, landmarks, w, h):
    pts = [(lm.x * w, lm.y * h, lm.visibility or 0.0) for lm in (landmarks[j] for j in BLAZEPOSE_COCO17)] if landmarks \
        else [(0.0, 0.0, 0.0)] * 17
    return f'{i},{t:.4f},,,' + ','.join(f'{x:.4f},{y:.4f},{c:.4f}' for x, y, c in pts)


def run(video, model, out_dir):
    import cv2
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision
    landmarker = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=model), running_mode=vision.RunningMode.VIDEO, num_poses=1))
    cap = cv2.VideoCapture(video)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    out = os.path.join(out_dir, os.path.splitext(os.path.basename(video))[0] + '.csv')
    with open(out, 'w') as f:
        f.write('frame,time,status,rep,' + ','.join(f'j{j}_{q}' for j in range(17) for q in 'xyc') + '\n')
        i = 0
        while True:
            ok, bgr = cap.read()
            if not ok:
                break
            h, w = bgr.shape[:2]
            r = landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)),
                                            int(round(i * 1000 / fps)))
            f.write(row(i, i / fps, r.pose_landmarks[0] if r.pose_landmarks else None, w, h) + '\n')
            i += 1
    landmarker.close()
    return out, i


if __name__ == '__main__':
    class L:
        def __init__(self, k): self.x, self.y, self.visibility = k / 100, k / 200, 0.5
    cells = row(3, 0.1, [L(k) for k in range(33)], 720, 1280).split(',')
    assert len(cells) == 4 + 51 and abs(float(cells[4 + 5 * 3]) - 79.2) < 1e-3 and abs(float(cells[4 + 16 * 3 + 1]) - 179.2) < 1e-3
    assert row(0, 0, None, 1, 1).endswith('0.0000,0.0000,0.0000')
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('videos', nargs='+')
    a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)
    for v in a.videos:
        print(*run(v, a.model, a.out_dir), flush=True)
