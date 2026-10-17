"""Exercise3D scores from pose-replay outputs: rep accuracy (outputs/rep_validation/analyze.py match: a rep end credits
the latest unclaimed GT trough at or before it +5 frames) and PCK vs the Sapiens2 2D pseudo labels (NOT ground truth,
D-C-01; labels in a 1280-long-side copy -> x1.5 for 1920x1080, joints with confidence > 0.5, box = longer side of the
body-12 label box; same rule as scripts/eval_pose2d.py), every 5th frame.
usage: ex3d_score.py <run_dir> <out.json> [seq ...]   (default: all 13; P1 = tuning, P2/P3 = squat_0002, barbellrow_0001/0003)
"""
import csv, json, sys, pathlib
import numpy as np
MAIN = pathlib.Path("/Users/6_month/github/06-month/hanbat/repositories/BPT")
GT = json.load(open(MAIN / "outputs/rep_validation/gt.json"))
SAP = [0, 1, 2, 3, 4, 5, 6, 7, 8, 62, 41, 9, 10, 11, 12, 13, 14]
GROUPS = {"body12": list(range(5, 17)), "limbs8": [7, 8, 9, 10, 13, 14, 15, 16], "hip": [11, 12], "shoulder": [5, 6]}
HELD = {"squat_0002", "barbellrow_0001", "barbellrow_0003"}
FILE_EX = {"squat": "squat", "pushup": "pushup", "barbellrow": "barbell_row"}


def match(troughs, ends):
    credited, extra, last = {}, [], -1
    for i, e in enumerate(ends):
        cand = [k for k, t in enumerate(troughs) if t <= e + 5 and k > last]
        if cand: last = cand[-1]; credited[last] = i
        else: extra.append(i)
    return credited, extra


def main(run, outp, *seqs):
    run = pathlib.Path(run); res = []
    for seq, g in sorted(GT.items()):
        if seqs and seq not in seqs: continue
        for cam in ("cam1", "cam2", "cam3"):
            lab = np.load(MAIN / "outputs/exercise3d_labels" / seq / "view" / f"{cam}_pose_2d.npz")
            fi = {int(f): t for t, f in enumerate(lab["frame_index"]) if lab["target_present"][t]}
            for model in ("mcoco17", "halpe26"):
                stem = f"{seq}_{cam}_{FILE_EX[g['exercise']]}_{model}"
                if not (run / f"{stem}.json").exists(): continue
                js = json.load(open(run / f"{stem}.json"))
                ends = [r["end_frame"] for r in js["reps"]]
                cr, ex = match(g["rep_frames"], ends)
                rows = list(csv.DictReader(open(run / f"{stem}.csv")))
                hit = {k: [0, 0] for k in GROUPS}
                for r in rows[::5]:
                    t = fi.get(int(r["frame"]))
                    if t is None: continue
                    k = lab["keypoints_xy"][t][SAP] * 1.5
                    v = lab["valid_mask"][t][SAP] & (lab["confidence"][t][SAP] > 0.5)
                    if v[5:].sum() < 4: continue
                    kb = k[5:][v[5:]]; box = max(np.ptp(kb[:, 0]), np.ptp(kb[:, 1]))
                    p = np.array([[float(r[f"j{j}_x"]), float(r[f"j{j}_y"])] for j in range(17)])
                    d = np.linalg.norm(p - k, axis=1) / box
                    for gname, idx in GROUPS.items():
                        m = v[idx]; hit[gname][0] += int((d[idx][m] < 0.05).sum()); hit[gname][1] += int(m.sum())
                res.append(dict(seq=seq, cam=cam, angle=g["views"][cam]["angle_deg"], exercise=g["exercise"], model=model,
                                split="held" if seq in HELD else "tune", truth=g["truth_reps"], counted=len(ends),
                                missed=g["truth_reps"] - len(cr), extra=len(ex),
                                **{f"pck05_{k}": round(a / b, 4) if b else None for k, (a, b) in hit.items()},
                                full_inputs=js["full_frame_inputs"], crops_in=js.get("crops_in") is not None))
    json.dump(res, open(outp, "w"), indent=1)
    for r in res: print(r["seq"], r["cam"], r["angle"], r["model"], r["truth"], r["counted"], r["missed"], r["extra"], r["pck05_body12"], r["pck05_limbs8"], r["full_inputs"])


if __name__ == "__main__":
    assert match([10, 20, 30], [12, 22, 32]) == ({0: 0, 1: 1, 2: 2}, [])
    assert match([10, 20, 30], [12, 26, 40]) == ({0: 0, 2: 1}, [2])  # the existing rule skips trough 20 (quirk kept)
    main(*sys.argv[1:])
