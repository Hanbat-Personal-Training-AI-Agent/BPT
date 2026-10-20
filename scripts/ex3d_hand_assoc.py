"""Hand-crop association in the app's hand branch, replayed on Exercise3D clips (labels = Sapiens pseudo labels).

  conda run -n bpt-ai python -I scripts/ex3d_hand_assoc.py <clips_dir> <replay_dir> <labels_root> <hand_landmarker.task> <out.json> [--mirrored] clip ...

--mirrored: clips and replay are horizontally flipped (front-camera emulation); labels are flipped and the
appearance-consistent target (crop "left" = mirrored anatomical right hand) counts as "own".

For each frame: the app's wrist crops (256 px square centred on each RTMPose wrist, clamped to the frame, only when the
wrist confidence >= 0.3; HandCropBuilder), MediaPipe HandLandmarker per side (VIDEO mode, numHands = 1, thresholds 0.5,
like MediaPipeHandLandmarkerRunner). A detection is "own" when its landmark 0 is closer to that side's labelled wrist,
"crossed" when closer to the other labelled wrist (the other hand), and "both_same_hand" when both sides' detections
sit within 0.25 x forearm of each other. reject_crossed (the XS-input rule) is applied against the RTMPose wrists.
The overlay draws every raw detection in its crop's side colour (orange/cyan = left, purple/pink = right) and moves the
drawn 2D wrist to it (useMediaPipeWristFor2DBodyOverlay) BEFORE that rejection. Frames are never saved.
"""
import csv
import json
import sys
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision

SAP = [0, 1, 2, 3, 4, 5, 6, 7, 8, 62, 41, 9, 10, 11, 12, 13, 14]
FILE_EX = {"squat": "squat", "pushup": "pushup", "barbellrow": "barbell_row"}


def landmarker(task):
    return vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=task), running_mode=vision.RunningMode.VIDEO, num_hands=1,
        min_hand_detection_confidence=0.5, min_hand_presence_confidence=0.5, min_tracking_confidence=0.5))


def main(clips_dir, replay_dir, labels_root, task, out, *clips):
    mirrored = "--mirrored" in clips
    clips = [c for c in clips if c != "--mirrored"]
    res = []
    for clip in clips:
        seq, cam = clip.rsplit("_", 1)
        ex = seq.split("_")[0]
        rows = list(csv.DictReader(open(Path(replay_dir) / f"{seq}_{cam}_{FILE_EX[ex]}_mcoco17.csv")))
        rw, rh = json.load(open(Path(replay_dir) / f"{seq}_{cam}_{FILE_EX[ex]}_mcoco17.json"))["image_size"]
        lab = np.load(Path(labels_root) / seq / "view" / f"{cam}_pose_2d.npz")
        fi = {int(f): t for t, f in enumerate(lab["frame_index"]) if lab["target_present"][t]}
        cap = cv2.VideoCapture(str(Path(clips_dir) / f"{clip}.mp4"))
        W, H = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        sr, sl = W / rw, max(W, H) / 1280.0  # replay coords -> clip, labels -> clip
        lm = {"left": landmarker(task), "right": landmarker(task)}
        c = {k: 0 for k in ("frames", "crops", "det", "own", "crossed", "both_same_hand", "crossed_kept_by_reject_rule",
                            "overlay_wrong_side")}
        per_side = {s: {"crops": 0, "det": 0, "own": 0, "crossed": 0} for s in lm}
        i = 0
        while True:
            ok, frame = cap.read()
            if not ok or i >= len(rows):
                break
            r = rows[i]
            t = fi.get(int(r["frame"]))
            i += 1
            if t is None:
                continue
            c["frames"] += 1
            lw = lab["keypoints_xy"][t][SAP][[9, 10]] * sl
            elb = lab["keypoints_xy"][t][SAP][[7, 8]] * sl
            if mirrored:  # flip x, and RTMPose "left" = the mirrored anatomical right
                lw, elb = lw[::-1].copy(), elb[::-1].copy()
                lw[:, 0], elb[:, 0] = W - lw[:, 0], W - elb[:, 0]
            forearm = float(np.mean(np.linalg.norm(lw - elb, axis=1)))
            rtm = {"left": np.array([float(r["j9_x"]), float(r["j9_y"])]) * sr,
                   "right": np.array([float(r["j10_x"]), float(r["j10_y"])]) * sr}
            conf = {"left": float(r["j9_c"]), "right": float(r["j10_c"])}
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            det = {}
            for side, k in (("left", 0), ("right", 1)):
                if conf[side] < 0.3:
                    continue
                size = min(256, W, H)
                x0 = int(min(max(rtm[side][0] - size / 2, 0), W - size))
                y0 = int(min(max(rtm[side][1] - size / 2, 0), H - size))
                crop = np.ascontiguousarray(rgb[y0:y0 + size, x0:x0 + size])
                c["crops"] += 1
                per_side[side]["crops"] += 1
                out_ = lm[side].detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=crop), int(i * 1000 / 30))
                if not out_.hand_landmarks:
                    continue
                p0 = out_.hand_landmarks[0][0]
                det[side] = np.array([x0 + p0.x * size, y0 + p0.y * size])
                c["det"] += 1
                per_side[side]["det"] += 1
                own = np.linalg.norm(det[side] - lw[k]) <= np.linalg.norm(det[side] - lw[1 - k])
                key = "own" if own else "crossed"
                c[key] += 1
                per_side[side][key] += 1
                if not own:
                    c["overlay_wrong_side"] += 1
                    other = "right" if side == "left" else "left"
                    if np.linalg.norm(det[side] - rtm[side]) <= np.linalg.norm(det[side] - rtm[other]):
                        c["crossed_kept_by_reject_rule"] += 1
            if len(det) == 2 and np.linalg.norm(det["left"] - det["right"]) < 0.25 * max(forearm, 1):
                c["both_same_hand"] += 1
        cap.release()
        res.append({"clip": clip, "size": [W, H], "mirrored": mirrored, **c, "per_side": per_side,
                    "crossed_share_of_detections": round(c["crossed"] / c["det"], 3) if c["det"] else None})
        print(json.dumps(res[-1]))
    json.dump(res, open(out, "w"), indent=1)


if __name__ == "__main__":
    main(*sys.argv[1:])
