"""Verify the fixed RTMDet user box used in experiment A, numeric only.
Per video: frames with a box, the user-track score (from the raw detections), IoU between consecutive user boxes, and how
well an INDEPENDENT keypoint reference falls inside the 3:4 crop: Exercise3D Sapiens2 labels (conf > 0.5, x1.5) or MM-Fit
authors' pose_2d (OpenPose-18, shifted by the measured label<->video frame offset per set).
usage: box_verify.py ex3d <det_dir> <out.json> | box_verify.py mmfit <det_dir> <mm-fit root> <offsets.json> <out.json>
"""
import csv, gzip, json, sys, pathlib
import numpy as np
MAIN = pathlib.Path("/Users/6_month/github/06-month/hanbat/repositories/BPT")
SAP = [0, 1, 2, 3, 4, 5, 6, 7, 8, 62, 41, 9, 10, 11, 12, 13, 14]


def crops(p):
    out = {}
    for r in csv.DictReader(open(p)):
        if r["x"]: out[int(r["frame"])] = [float(r[k]) for k in "xywh"]
    return out


def iou(a, b):
    ax1, ay1, bx1, by1 = a[0] + a[2], a[1] + a[3], b[0] + b[2], b[1] + b[3]
    iw = max(0, min(ax1, bx1) - max(a[0], b[0])); ih = max(0, min(ay1, by1) - max(a[1], b[1]))
    i = iw * ih; return i / (a[2] * a[3] + b[2] * b[3] - i)


def summary(stem, C, n_frames, ref):  # ref: frame -> (k x 2 points)
    fr = sorted(C); ious = [iou(C[a], C[b]) for a, b in zip(fr, fr[1:]) if b == a + 1]
    inside = []
    for f, pts in ref.items():
        if f not in C or len(pts) == 0: continue
        x, y, w, h = C[f]
        inside.append(np.mean((pts[:, 0] >= x) & (pts[:, 0] <= x + w) & (pts[:, 1] >= y) & (pts[:, 1] <= y + h)))
    inside = np.array(inside)
    return dict(video=stem, frames=n_frames, frames_with_box=len(C), iou_med=round(float(np.median(ious)), 3) if ious else None,
                iou_min=round(float(min(ious)), 3) if ious else None, iou_lt07=int(sum(i < 0.7 for i in ious)),
                ref_frames=len(inside), ref_inside_med=round(float(np.median(inside)), 3) if len(inside) else None,
                ref_inside_min=round(float(inside.min()), 3) if len(inside) else None,
                ref_frames_all_inside=round(float(np.mean(inside == 1)), 3) if len(inside) else None)


def ex3d(det, outp):
    res = []
    for p in sorted(pathlib.Path(det).glob("*_det.csv")):
        stem = p.name[:-8]; seq, cam = stem.rsplit("_", 1)
        lab = np.load(MAIN / "outputs/exercise3d_labels" / seq / "view" / f"{cam}_pose_2d.npz")
        ref = {}
        for t, f in enumerate(lab["frame_index"]):
            if not lab["target_present"][t]: continue
            v = lab["valid_mask"][t][SAP] & (lab["confidence"][t][SAP] > 0.5)
            ref[int(f)] = lab["keypoints_xy"][t][SAP][v] * 1.5
        n = len(json.load(gzip.open(pathlib.Path(det) / f"{stem}_dets.json.gz", "rt")))
        res.append(summary(stem, crops(p), n, ref)); print(res[-1], flush=True)
    json.dump(res, open(outp, "w"), indent=1)


def mmfit(det, root, offs, outp):
    off = json.load(open(offs)); res = []
    for p in sorted(pathlib.Path(det).glob("*_det.csv")):
        stem = p.name[:-8]; w = stem[:3]
        lab = pathlib.Path(root) / w / f"{w}_labels.csv"
        rows = [r for r in csv.reader(open(lab)) if r and r[3] == "pushups"]
        s = int(rows[int(stem.split("_s")[1]) - 1][0]); a = max(0, s - 90); d = off[stem]["best_offset"]
        P = np.load(pathlib.Path(root) / w / f"{w}_pose_2d.npy"); fr = P[0, :, 0].astype(int)
        idx = {int(f): i for i, f in enumerate(fr)}
        n = len(json.load(gzip.open(pathlib.Path(det) / f"{stem}_dets.json.gz", "rt")))
        ref = {}
        for k in range(n):
            i = idx.get(a + k + d)
            if i is None: continue
            pts = np.stack([P[0, i, 1:], P[1, i, 1:]], 1); pts = pts[(pts[:, 0] > 0) & (pts[:, 1] > 0)]
            ref[k] = pts
        r = summary(stem, crops(p), n, ref); r["label_video_offset"] = d; res.append(r); print(r, flush=True)
    json.dump(res, open(outp, "w"), indent=1)


if __name__ == "__main__":
    assert abs(iou([0, 0, 2, 2], [1, 0, 2, 2]) - 1 / 3) < 1e-9
    (ex3d if sys.argv[1] == "ex3d" else mmfit)(*sys.argv[2:])
