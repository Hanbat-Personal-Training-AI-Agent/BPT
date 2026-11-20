"""RTMPose left/right swaps vs the Exercise3D 2D labels (Sapiens pseudo labels, NOT ground truth).

  conda run -n bpt-eval python -I scripts/ex3d_lr_swap.py <replay_dir> <labels_root> <gt.json> <out.json> [--mirrored]

replay_dir: pose-replay outputs <seq>_<cam>_<exercise>_mcoco17.{csv,json} (app RTMPose-m, crop input). Labels: <labels_root>/<seq>/view/<cam>_pose_2d.npz
(1280-long-side copy -> scaled to the replay image size). For each labelled frame and each L/R pair (shoulder, elbow,
wrist, hip, knee, ankle) with both label points confident (> 0.5) and apart (> 0.05 x body box), the pair is
"swapped" when the crossed assignment is closer than the straight one. --mirrored: the replay ran on horizontally
flipped clips; labels are flipped too and the appearance-consistent assignment (RTMPose "left" = the mirrored
anatomical right) counts as not swapped, so the rate measures inconsistency, not the mirror itself.
Per clip: swap rate per pair, whole-body swaps (>= 4 of 6 pairs), partial swaps (wrists swapped, shoulders+hips not),
temporal flips of the wrist assignment, RTMPose wrist confidence.
"""
import csv
import json
import sys
from pathlib import Path

import numpy as np

SAP = [0, 1, 2, 3, 4, 5, 6, 7, 8, 62, 41, 9, 10, 11, 12, 13, 14]  # Sapiens -> COCO17 (as scripts ex3d_score.py)
PAIRS = {"shoulder": (5, 6), "elbow": (7, 8), "wrist": (9, 10), "hip": (11, 12), "knee": (13, 14), "ankle": (15, 16)}
FILE_EX = {"squat": "squat", "pushup": "pushup", "barbellrow": "barbell_row"}


def main(replay_dir, labels_root, gt_path, out, *flags):
    mirrored = "--mirrored" in flags
    gt = json.load(open(gt_path))
    res = []
    for seq, g in sorted(gt.items()):
        for cam in ("cam1", "cam2", "cam3"):
            stem = f"{seq}_{cam}_{FILE_EX[g['exercise']]}_mcoco17"
            p_csv, p_json = Path(replay_dir) / f"{stem}.csv", Path(replay_dir) / f"{stem}.json"
            if not p_csv.exists():
                continue
            w, h = json.load(open(p_json))["image_size"]
            lab = np.load(Path(labels_root) / seq / "view" / f"{cam}_pose_2d.npz")
            scale = max(w, h) / 1280.0
            fi = {int(f): t for t, f in enumerate(lab["frame_index"]) if lab["target_present"][t]}
            counts = {k: [0, 0] for k in PAIRS}
            whole = partial = n_frames = flips = 0
            prev = None
            conf_w = []
            for r in csv.DictReader(open(p_csv)):
                t = fi.get(int(r["frame"]))
                if t is None:
                    continue
                k = lab["keypoints_xy"][t][SAP] * scale
                v = lab["valid_mask"][t][SAP] & (lab["confidence"][t][SAP] > 0.5)
                if v[5:].sum() < 6:
                    continue
                if mirrored:
                    k = k.copy()
                    k[:, 0] = w - k[:, 0]
                box = max(np.ptp(k[5:][v[5:]][:, 0]), np.ptp(k[5:][v[5:]][:, 1]))
                pr = np.array([[float(r[f"j{j}_x"]), float(r[f"j{j}_y"])] for j in range(17)])
                pc = np.array([float(r[f"j{j}_c"]) for j in range(17)])
                state = {}
                for name, (a, b) in PAIRS.items():
                    if not (v[a] and v[b]) or np.linalg.norm(k[a] - k[b]) < 0.05 * box:
                        continue
                    la, lb = (k[b], k[a]) if mirrored else (k[a], k[b])  # appearance-consistent targets
                    straight = np.linalg.norm(pr[a] - la) + np.linalg.norm(pr[b] - lb)
                    crossed = np.linalg.norm(pr[a] - lb) + np.linalg.norm(pr[b] - la)
                    s = crossed < straight
                    state[name] = s
                    counts[name][0] += int(s)
                    counts[name][1] += 1
                if len(state) >= 4:
                    n_frames += 1
                    whole += int(sum(state.values()) >= 4)
                    if "wrist" in state and state["wrist"] and not state.get("shoulder", False) and not state.get("hip", False):
                        partial += 1
                if "wrist" in state:
                    if prev is not None and state["wrist"] != prev:
                        flips += 1
                    prev = state["wrist"]
                conf_w.append(float(min(pc[9], pc[10])))
            res.append({"seq": seq, "cam": cam, "exercise": g["exercise"], "angle": g["views"][cam]["angle_deg"],
                        "near_side": g["views"][cam]["near_side"], "mirrored": mirrored, "frames": n_frames,
                        **{f"swap_{k}": round(a / b, 3) if b else None for k, (a, b) in counts.items()},
                        "whole_body_swap": round(whole / n_frames, 3) if n_frames else None,
                        "wrist_only_swap": round(partial / n_frames, 3) if n_frames else None,
                        "wrist_flips": flips, "wrist_conf_min_p50": round(float(np.median(conf_w)), 3) if conf_w else None})
    json.dump(res, open(out, "w"), indent=1)
    for r in res:
        print(f'{r["seq"]:16s} {r["cam"]} {r["angle"]:5.1f} {r["near_side"]:5s} n={r["frames"]:4d} wrist {r["swap_wrist"]} '
              f'elbow {r["swap_elbow"]} shoulder {r["swap_shoulder"]} hip {r["swap_hip"]} knee {r["swap_knee"]} '
              f'whole {r["whole_body_swap"]} wrist_only {r["wrist_only_swap"]} flips {r["wrist_flips"]} conf {r["wrist_conf_min_p50"]}')


if __name__ == "__main__":
    main(*sys.argv[1:])
