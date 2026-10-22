"""Left/right on the real app path (device video-as-camera runs) vs the Exercise3D 2D labels (Sapiens pseudo labels).

  conda run -n bpt-eval python -I scripts/ex3d_lr_swap_device.py <labels_root> <gt.json> <out.json> <run_dir> [...]

Uses the judged-frame lines of VideoRunLog (kp = the RTMPose COCO17 the evaluators used, hands = raw MediaPipe wrist
per crop side, src = clip frame, size = processed image). Labels (1280-long-side copy of the original clip) are
scaled to the processed size; when the run log says mirrored, labels are flipped (x -> W - x) and the
appearance-consistent assignment (RTMPose "left" = mirrored anatomical right) counts as correct, so the rates
measure label inconsistency, not the mirror. Rotated runs are skipped.
Per clip: RTMPose swap rate per L/R pair, whole-body swaps, temporal wrist flips; hand-crop detections that are the
other hand ("crossed"), both crops on the same hand; 3D state on wrist-swapped frames vs the rest.
"""
import json
import sys
from collections import Counter
from pathlib import Path

import numpy as np

SAP = [0, 1, 2, 3, 4, 5, 6, 7, 8, 62, 41, 9, 10, 11, 12, 13, 14]
PAIRS = {"shoulder": (5, 6), "elbow": (7, 8), "wrist": (9, 10), "hip": (11, 12), "knee": (13, 14), "ankle": (15, 16)}


def analyze(log, labels_root, gt):
    rows = [json.loads(line) for line in open(log) if line.strip()]
    start = next(r for r in rows if r["type"] == "start")
    clip_row = next(r for r in rows if r["type"] == "clip_start")
    if clip_row.get("rotate"):
        return None
    mirrored = bool(start.get("mirrored", clip_row.get("mirrored", False)))
    clip = clip_row["clip"].removesuffix(".mp4")
    seq, cam = clip.rsplit("_", 1)
    lab = np.load(Path(labels_root) / seq / "view" / f"{cam}_pose_2d.npz")
    fi = {int(f): t for t, f in enumerate(lab["frame_index"]) if lab["target_present"][t]}
    counts = {k: [0, 0] for k in PAIRS}
    whole = n_frames = flips = 0
    prev = None
    hands = Counter()
    state_swapped, state_rest = Counter(), Counter()
    for r in rows:
        if r["type"] != "judged" or "kp" not in r or "src" not in r:
            continue
        t = fi.get(int(r["src"]))
        if t is None:
            continue
        w, h = r["size"]
        k = lab["keypoints_xy"][t][SAP] * (max(w, h) / 1280.0)
        v = lab["valid_mask"][t][SAP] & (lab["confidence"][t][SAP] > 0.5)
        if v[5:].sum() < 6:
            continue
        if mirrored:
            k = k.copy()
            k[:, 0] = w - k[:, 0]
        box = max(np.ptp(k[5:][v[5:]][:, 0]), np.ptp(k[5:][v[5:]][:, 1]))
        kp = np.array(r["kp"]).reshape(17, 3)
        pr = kp[:, :2]
        state = {}
        for name, (a, b) in PAIRS.items():
            if not (v[a] and v[b]) or np.linalg.norm(k[a] - k[b]) < 0.05 * box:
                continue
            la, lb = (k[b], k[a]) if mirrored else (k[a], k[b])
            s = np.linalg.norm(pr[a] - lb) + np.linalg.norm(pr[b] - la) < np.linalg.norm(pr[a] - la) + np.linalg.norm(pr[b] - lb)
            state[name] = s
            counts[name][0] += int(s)
            counts[name][1] += 1
        if len(state) >= 4:
            n_frames += 1
            whole += int(sum(state.values()) >= 4)
        if "wrist" in state:
            if prev is not None and state["wrist"] != prev:
                flips += 1
            prev = state["wrist"]
            (state_swapped if state["wrist"] else state_rest)[r["state"]] += 1
        # hand crops: is each side's detection the hand RTMPose's same-side wrist label (appearance-consistent) points to?
        lw = {"left": k[10] if mirrored else k[9], "right": k[9] if mirrored else k[10]}
        det = r.get("hands", {})
        for side, p in det.items():
            other = "right" if side == "left" else "left"
            hands["det"] += 1
            hands["own" if np.linalg.norm(np.array(p) - lw[side]) <= np.linalg.norm(np.array(p) - lw[other]) else "crossed"] += 1
        if len(det) == 2:
            forearm = float(np.mean([np.linalg.norm(k[9] - k[7]), np.linalg.norm(k[10] - k[8])]))
            if np.linalg.norm(np.array(det["left"]) - np.array(det["right"])) < 0.25 * max(forearm, 1):
                hands["both_same_hand"] += 1
        hands["frames"] += 1
    g = gt[seq]
    return {"clip": clip, "angle": g["views"][cam]["angle_deg"], "near_side": g["views"][cam]["near_side"],
            "exercise": g["exercise"], "mirrored": mirrored, "frames": n_frames,
            **{f"swap_{k}": round(a / b, 3) if b else None for k, (a, b) in counts.items()},
            "whole_body_swap": round(whole / n_frames, 3) if n_frames else None, "wrist_flips": flips,
            "hand_det": hands["det"], "hand_crossed": hands["crossed"],
            "hand_crossed_share": round(hands["crossed"] / hands["det"], 3) if hands["det"] else None,
            "both_crops_same_hand_frames": hands["both_same_hand"], "hand_frames": hands["frames"],
            "states_on_wrist_swapped_frames": dict(state_swapped), "states_on_other_frames": dict(state_rest)}


def main(labels_root, gt_path, out, *run_dirs):
    gt = json.load(open(gt_path))
    res = []
    for d in run_dirs:
        for log in sorted(Path(d).glob("run_*.jsonl")):
            r = analyze(log, labels_root, gt)
            if r:
                res.append(r)
                print(f'{r["clip"]:22s} {r["angle"]:5.1f} {r["near_side"]:5s} mir={int(r["mirrored"])} n={r["frames"]:4d} '
                      f'wrist {r["swap_wrist"]} elbow {r["swap_elbow"]} shoulder {r["swap_shoulder"]} hip {r["swap_hip"]} '
                      f'knee {r["swap_knee"]} ankle {r["swap_ankle"]} whole {r["whole_body_swap"]} flips {r["wrist_flips"]} '
                      f'| hands crossed {r["hand_crossed"]}/{r["hand_det"]} same-hand {r["both_crops_same_hand_frames"]}/{r["hand_frames"]}')
    json.dump(res, open(out, "w"), indent=1)


if __name__ == "__main__":
    main(*sys.argv[1:])
