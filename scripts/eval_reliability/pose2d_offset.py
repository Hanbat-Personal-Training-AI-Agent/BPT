"""Label-frame <-> video-frame alignment check, numeric. Our COCO-17 keypoints on an exact-frame clip (clip frame k = video
frame a+k, a = s-90) vs. the MM-Fit authors' pose_2d (OpenPose COCO-18, indexed by the same frame numbers as the labels).
For offset d in [-RANGE, RANGE] (env RANGE, default 15; 400 was used): median pixel distance between the mean of our confident shoulders+wrists+elbows and the mean of
the authors' same joints at frame a+k+d. d* = argmin; d* = 0 means label frame n is video frame n (0-based).
usage: pose2d_offset.py <pose_2d dir root (mm-fit)> <labels_root> <run_dir> <model> <out.json>
"""
import csv, json, sys, pathlib
import numpy as np
root, labels, run, model, outp = sys.argv[1:6]
RANGE = int(__import__("os").environ.get("RANGE", "15"))
OURS = [5, 6, 7, 8, 9, 10]            # COCO shoulders, elbows, wrists
THEIRS = [2, 5, 3, 6, 4, 7]           # OpenPose-18: r/l shoulder, r/l elbow, r/l wrist (+1 for the frame column)
res = {}
for lab in sorted(pathlib.Path(labels).glob("*/*_labels.csv")):
    w = lab.name[:3]
    rows = [r for r in csv.reader(open(lab)) if r and r[3] == "pushups"]
    for k, (s, e, n, _) in enumerate(rows, 1):
        cid = f"{w}_s{k}"; f = pathlib.Path(run) / f"{cid}_pushup_{model}.csv"
        if not f.exists(): continue
        s = int(s); a = max(0, s - 90)
        p = np.load(f"{root}/{w}/{w}_pose_2d.npy"); fr = p[0, :, 0].astype(int)
        X, Y = p[0, :, 1:][:, THEIRS], p[1, :, 1:][:, THEIRS]
        ok = (X > 0) & (Y > 0)
        tx = np.where(ok, X, np.nan); ty = np.where(ok, Y, np.nan)
        theirs = {int(fi): (np.nanmean(tx[i]), np.nanmean(ty[i])) for i, fi in enumerate(fr) if ok[i].sum() >= 3}
        ours = []
        for r in csv.DictReader(open(f)):
            c = [(float(r[f"j{j}_x"]), float(r[f"j{j}_y"])) for j in OURS if float(r[f"j{j}_c"] or 0) >= 0.5]
            ours.append(tuple(np.mean(c, 0)) if len(c) >= 3 else None)
        score = {}
        for d in range(-RANGE, RANGE + 1):
            dist = [np.hypot(o[0] - theirs[a + i + d][0], o[1] - theirs[a + i + d][1]) for i, o in enumerate(ours)
                    if o is not None and (a + i + d) in theirs]
            if len(dist) > 0.6 * len(ours) * 0.5: score[d] = float(np.median(dist))
        best = min(score, key=score.get)
        res[cid] = dict(best_offset=best, median_px=round(score[best], 2), at0=round(score.get(0, float("nan")), 2),
                        atm1=round(score.get(-1, float("nan")), 2), atp1=round(score.get(1, float("nan")), 2))
        print(cid, res[cid], flush=True)
json.dump(res, open(outp, "w"), indent=1)
