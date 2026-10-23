"""Per-physical-rep contact sheets for Exercise3D form labelling (3 synced cams x 4 phases), plus a per-set overview.

Frames are chosen from 2D keypoints only (rules-calib 2D replay, Halpe26); no warning or metric is read.
Usage: python make_sheets.py <blind_dir> <gt.json> <synced_root> <out_dir> [set ...]
"""
import gzip, json, os, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw

BLIND, GT, ROOT, OUT = sys.argv[1:5]
ONLY = sys.argv[5:]
FPS = 30.0
gt = json.load(open(GT))
os.makedirs(OUT, exist_ok=True)


def kp_table(clip):
    rows = json.load(gzip.open(f"{BLIND}/{clip}_kp.json.gz", "rt"))
    n = max(r[0] for r in rows) + 1
    a = np.full((n, 26, 3), np.nan)
    for r in rows:
        a[r[0]] = np.array(r[2:], float).reshape(26, 3)
    return a


def signal(kp, joints, conf=0.3):
    y = kp[:, joints, 1].copy()
    y[kp[:, joints, 2] < conf] = np.nan
    s = np.nanmean(y, axis=1)
    idx = np.arange(len(s))
    ok = ~np.isnan(s)
    s = np.interp(idx, idx[ok], s[ok])
    return np.convolve(np.pad(s, 2, mode="edge"), np.ones(5) / 5, mode="valid")


def pick(set_id):
    g = gt[set_id]
    ex = set_id.split("_")[0]
    views = g["views"]
    ref = min(views, key=lambda c: views[c]["angle_deg"])
    kp = kp_table(f"{set_id}_{ref}")
    nf = g["frames"]
    if ex == "squat":
        s, low_is_max = signal(kp, [11, 12]), True    # hip y; bottom = max y
    elif ex == "pushup":
        s, low_is_max = signal(kp, [5, 6]), True      # shoulder y; bottom = max y
    else:
        s, low_is_max = -signal(kp, [9, 10]), True    # -wrist y; peak pull = max(-y)
    anchors = g["rep_frames"]
    I = int(np.median(np.diff(anchors)))
    t1 = []
    for a in anchors:
        lo, hi = max(0, a - int(0.3 * I)), min(nf - 1, a + int(0.3 * I))
        t1.append(lo + int(np.argmax(s[lo:hi + 1])))
    reps = []
    for j, b in enumerate(t1):
        lo0 = t1[j - 1] if j else max(0, b - I)
        hi3 = t1[j + 1] if j + 1 < len(t1) else min(nf - 1, b + I)
        t0 = lo0 + int(np.argmin(s[lo0:b + 1]))
        t3 = b + int(np.argmin(s[b:hi3 + 1]))
        if ex == "barbellrow":
            mid = t0 + (b - t0) // 2
            phases = [("T0", t0), ("Tm", mid), ("T1", b), ("T3", t3)]
        else:
            phases = [("T0", t0), ("T1", b), ("T2", b + (t3 - b) // 3), ("T3", t3)]
        reps.append({"phys_rep": j + 1, "anchor": anchors[j], "ref_cam": ref, "phases": phases})
    return reps


def crop_box(kp, f0, f1, W, H, aspect, conf=0.3):
    pts = kp[f0:f1 + 1].reshape(-1, 3)
    pts = pts[pts[:, 2] >= conf]
    if len(pts) == 0:
        return 0, 0, W, H
    x0, y0 = np.percentile(pts[:, 0], 1), np.percentile(pts[:, 1], 1)
    x1, y1 = np.percentile(pts[:, 0], 99), np.percentile(pts[:, 1], 99)
    m = 0.12 * max(x1 - x0, y1 - y0)
    x0, y0, x1, y1 = x0 - m, y0 - m, x1 + m, y1 + m
    w, h = x1 - x0, y1 - y0
    if w / h < aspect:
        cx = (x0 + x1) / 2; w = h * aspect; x0, x1 = cx - w / 2, cx + w / 2
    else:
        cy = (y0 + y1) / 2; h = w / aspect; y0, y1 = cy - h / 2, cy + h / 2
    return int(max(0, x0)), int(max(0, y0)), int(min(W, x1)), int(min(H, y1))


def frames(path, want):
    want = sorted(set(want))
    W, H = map(int, subprocess.check_output(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
         "-of", "csv=p=0", path]).decode().strip().split(","))
    expr = "+".join(f"eq(n\\,{f})" for f in want)
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", f"select='{expr}'", "-fps_mode", "passthrough",
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], capture_output=True, check=True).stdout
    n = len(raw) // (W * H * 3)
    out = {}
    for i in range(min(n, len(want))):
        out[want[i]] = Image.frombuffer("RGB", (W, H), raw[i * W * H * 3:(i + 1) * W * H * 3])
    return out, W, H


def tile(img, box, size, text):
    t = img.crop(box)
    t.thumbnail(size)
    canvas = Image.new("RGB", (size[0], size[1] + 14), (20, 20, 20))
    canvas.paste(t, ((size[0] - t.width) // 2, 14 + (size[1] - t.height) // 2))
    ImageDraw.Draw(canvas).text((3, 1), text, fill=(255, 255, 0))
    return canvas


def run_set(set_id):
    ex = set_id.split("_")[0]
    exdir = {"squat": "squat", "pushup": "pushup", "barbellrow": "barbellrow"}[ex]
    reps = pick(set_id)
    size = (330, 190) if ex == "pushup" else (230, 310)
    aspect = size[0] / size[1]
    cams = ["cam1", "cam2", "cam3"]
    views = gt[set_id]["views"]
    ref = reps[0]["ref_cam"]
    need = sorted({f for r in reps for _, f in r["phases"]})
    tiles = {}  # (cam, frame, rep) -> tile
    ov = {}
    for cam in cams:
        clip = f"{set_id}_{cam}"
        kp = kp_table(clip)
        imgs, W, H = frames(f"{ROOT}/{exdir}/{set_id}/{cam}.mp4", need)
        for r in reps:
            f0, f3 = r["phases"][0][1], r["phases"][-1][1]
            box = crop_box(kp, f0, min(f3, len(kp) - 1), W, H, aspect)
            for name, f in r["phases"]:
                if f in imgs:
                    tiles[(cam, r["phys_rep"], name)] = tile(
                        imgs[f], box, size, f"{cam} {views[cam]['angle_deg']:.0f}deg {name} f{f}")
        if cam == ref:
            box = crop_box(kp, reps[0]["phases"][0][1], min(reps[-1]["phases"][-1][1], len(kp) - 1), W, H, aspect)
            osize = (210, 120) if ex == "pushup" else (140, 190)
            for r in reps:
                for name, f in r["phases"]:
                    if name in ("T1", "T3") and f in imgs:
                        ov[(r["phys_rep"], name)] = tile(imgs[f], box, osize, f"r{r['phys_rep']} {name} f{f}")
    tw, th = size[0], size[1] + 14
    for r in reps:
        sheet = Image.new("RGB", (4 * tw, 18 + 3 * th), (0, 0, 0))
        ImageDraw.Draw(sheet).text((4, 3), f"{set_id} phys rep {r['phys_rep']}/{len(reps)} anchor f{r['anchor']}"
                                            f" (frames from {ref})", fill=(255, 255, 255))
        for ci, cam in enumerate(cams):
            for pi, (name, _) in enumerate(r["phases"]):
                t = tiles.get((cam, r["phys_rep"], name))
                if t:
                    sheet.paste(t, (pi * tw, 18 + ci * th))
        sheet.save(f"{OUT}/{set_id}_r{r['phys_rep']:02d}.jpg", quality=85)
    n = len(reps)
    ow, oh = (ov[(1, "T1")].width, ov[(1, "T1")].height)
    per_row = 6 if ex == "pushup" else 12
    rows = []
    for name in ("T1", "T3"):
        for k in range(0, n, per_row):
            rows.append([(i + 1, name) for i in range(k, min(n, k + per_row))])
    sheet = Image.new("RGB", (per_row * ow, 18 + len(rows) * oh), (0, 0, 0))
    ImageDraw.Draw(sheet).text((4, 3), f"{set_id} overview {ref} ({views[ref]['angle_deg']:.0f}deg): rows = T1 (bottom/peak) then T3 (top/end)",
                               fill=(255, 255, 255))
    for ri, row in enumerate(rows):
        for ci, key in enumerate(row):
            if key in ov:
                sheet.paste(ov[key], (ci * ow, 18 + ri * oh))
    sheet.save(f"{OUT}/{set_id}_overview.jpg", quality=85)
    json.dump(reps, open(f"{OUT}/{set_id}_frames.json", "w"), indent=1)
    print(set_id, n, "reps", ref)


for s in (ONLY or sorted(gt)):
    run_set(s)
