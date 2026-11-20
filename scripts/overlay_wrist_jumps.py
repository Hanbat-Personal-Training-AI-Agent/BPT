"""Overlay wrist on the real app path (device video-as-camera runs): where the drawn wrist sits vs RTMPose's wrists.

  conda run -n bpt-eval python -I scripts/overlay_wrist_jumps.py <run_dir> [<run_dir> ...]

The drawn wrist per side and frame is rebuilt from the judged-frame lines of VideoRunLog. Before ai/lift-refine (no
`hand_dedupe` in camera_started) the overlay drew the raw MediaPipe wrist whenever that side's crop found a hand. After
it, the overlay draws the XS input wrist: MediaPipe only where accepted (`wrists` flags), RTMPose otherwise.

Per clip it counts:
- frames where the drawn wrist sits on the other RTMPose wrist (nearer to it, with the wrists >= 0.25 forearm apart);
- frame-to-frame jumps of the drawn wrist > 0.5 forearm while RTMPose's wrist moved < 0.2 forearm;
- frames where both crops found the same hand (raw detections < 0.25 forearm apart; `same_hand` = dropped by the dedupe).
The new overlay's display smoothing (One-Euro) is not applied here, so jumps are counted before smoothing.
"""
import json
import sys
from pathlib import Path

import numpy as np


def drawn_wrists(r, new):
    kp = np.array(r["kp"]).reshape(17, 3)[:, :2]
    hands = r.get("hands", {})
    flags = r.get("wrists", [False, False])
    out = {}
    for side, idx, flag in (("left", 9, 0), ("right", 10, 1)):
        h = hands.get(side)
        use = h is not None and (bool(flags[flag]) if new else True)
        out[side] = np.array(h, dtype=float) if use else kp[idx]
    return kp, out


def analyze(path):
    rows = [json.loads(line) for line in open(path) if line.strip()]
    cam = next((r for r in rows if r["type"] == "camera_started"), {})
    clip = next((r["clip"] for r in rows if r["type"] == "clip_start"), "?").removesuffix(".mp4")
    new = "hand_dedupe" in cam
    judged = sorted((r for r in rows if r["type"] == "judged" and "kp" in r), key=lambda r: r["frame"])
    other = {"left": 0, "right": 0}
    jumps = {"left": 0, "right": 0}
    same_detect = same_dropped = 0
    prev = None
    for r in judged:
        kp, d = drawn_wrists(r, new)
        forearm = max(1.0, float(np.mean([np.linalg.norm(kp[9] - kp[7]), np.linalg.norm(kp[10] - kp[8])])))
        apart = np.linalg.norm(kp[9] - kp[10]) >= 0.25 * forearm
        for side, own, oth in (("left", 9, 10), ("right", 10, 9)):
            if apart and np.linalg.norm(d[side] - kp[oth]) < np.linalg.norm(d[side] - kp[own]):
                other[side] += 1
            if prev is not None and r["frame"] == prev[0] + 1:
                _, pkp, pd = prev
                if (np.linalg.norm(d[side] - pd[side]) > 0.5 * forearm
                        and np.linalg.norm(kp[own] - pkp[own]) < 0.2 * forearm):
                    jumps[side] += 1
        h = r.get("hands", {})
        if "left" in h and "right" in h and np.linalg.norm(np.subtract(h["left"], h["right"])) < 0.25 * forearm:
            same_detect += 1
        same_dropped += int(bool(r.get("same_hand")))
        prev = (r["frame"], kp, d)
    return {"clip": clip, "log": Path(path).name, "overlay": "lift-refine (XS input wrist)" if new else "old (raw MediaPipe wrist)",
            "hand_dedupe": cam.get("hand_dedupe"), "frames": len(judged),
            "drawn_on_other_wrist": [other["left"], other["right"]], "drawn_wrist_jumps": [jumps["left"], jumps["right"]],
            "both_crops_same_hand": same_detect, "same_hand_dropped": same_dropped}


def main(*dirs):
    res = [analyze(p) for d in dirs for p in sorted(Path(d).glob("run_*.jsonl"))]
    print("| clip | log | overlay | dedupe | frames | drawn on other wrist L/R | jumps L/R | both crops same hand | same_hand dropped |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in res:
        print(f'| {r["clip"]} | {r["log"]} | {r["overlay"]} | {r["hand_dedupe"]} | {r["frames"]} | '
              f'{r["drawn_on_other_wrist"][0]}/{r["drawn_on_other_wrist"][1]} | {r["drawn_wrist_jumps"][0]}/{r["drawn_wrist_jumps"][1]} | '
              f'{r["both_crops_same_hand"]} | {r["same_hand_dropped"]} |')
    return res


if __name__ == "__main__":
    main(*sys.argv[1:])
