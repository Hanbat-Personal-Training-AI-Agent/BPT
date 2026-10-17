"""RTMDet-m person boxes per frame -> user track (max sum score*area, IoU-linked) -> 3:4 crop CSV (pose-replay
CropSequence format, 12.5% margin per side). usage: det_crops.py <out_dir> <video.mp4>...  (offline upper bound)"""
import sys, pathlib, cv2, gzip, json, numpy as np
from mmdet.apis import init_detector, inference_detector
CFG = "/home/junjeon/miniconda3/envs/bpt-mmpose/lib/python3.10/site-packages/mmdet/.mim/configs/rtmdet/rtmdet_m_8xb32-300e_coco.py"
CKPT = "/home/junjeon/models/rtmpose_ft/src/rtmdet_m_8xb32-300e_coco_20220719_112220-229f527c.pth"
def iou(a, b):
    x0, y0, x1, y1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    i = max(0, x1 - x0) * max(0, y1 - y0)
    return i / ((a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - i + 1e-9)
def crop(b, m=0.125):
    x0, y0, x1, y1 = b; w, h = x1 - x0, y1 - y0
    w, h = w * (1 + 2*m), h * (1 + 2*m)
    if w / h > 0.75: h = w / 0.75
    else: w = h * 0.75
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return cx - w/2, cy - h/2, w, h
model = init_detector(CFG, CKPT, device="cuda:0")
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
for v in sys.argv[2:]:
    cap = cv2.VideoCapture(v); dets = []
    while True:
        ok, img = cap.read()
        if not ok: break
        r = inference_detector(model, img).pred_instances
        keep = (r.labels == 0) & (r.scores >= 0.2)
        dets.append([(tuple(b), float(s)) for b, s in zip(r.bboxes[keep].cpu().numpy().tolist(), r.scores[keep].cpu().numpy().tolist())])
    tracks = []  # [last_frame, last_box, {frame: box}, mass]
    for f, ds in enumerate(dets):
        used = set()
        for b, s in sorted(ds, key=lambda d: -d[1]):
            best = max((t for t in tracks if f - t[0] <= 10 and id(t) not in used), key=lambda t: iou(t[1], b), default=None)
            if best is not None and iou(best[1], b) > 0.3:
                best[0], best[1] = f, b; best[2][f] = b; best[3] += s * (b[2]-b[0]) * (b[3]-b[1]); used.add(id(best))
            else:
                t = [f, b, {f: b}, s * (b[2]-b[0]) * (b[3]-b[1])]; tracks.append(t); used.add(id(t))
    user = max(tracks, key=lambda t: t[3])[2] if tracks else {}
    stem = pathlib.Path(v).stem
    with gzip.open(out / f"{stem}_dets.json.gz", "wt") as f: json.dump(dets, f)  # raw: per frame [(x0,y0,x1,y1), score]
    # offline: the user track (whole-video max sum score*area; uses the future -> reference only)
    # online: that frame alone, the box with the largest score*area (what an app detector run would pick)
    online = {f: max(ds, key=lambda d: d[1] * (d[0][2]-d[0][0]) * (d[0][3]-d[0][1]))[0] for f, ds in enumerate(dets) if ds}
    for tag, boxes in (("det", user), ("detonline", online)):
        lines = ["frame,x,y,w,h,source,recheck"]
        for f in range(len(dets)):
            lines.append(",".join([str(f)] + (["%.3f" % c for c in crop(boxes[f])] if f in boxes else ["", "", "", ""]) + [tag, ""]))
        (out / f"{stem}_{tag}.csv").write_text("\n".join(lines) + "\n")
    print(stem, len(dets), len(user), len(online), flush=True)
