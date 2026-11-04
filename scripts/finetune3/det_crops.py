"""RTMDet person boxes per frame -> pose-replay box CSVs, the reacquire track's det_crops.py (Home ~/bpt-runs/reacquire/
_tools/det_crops.py, not in git) unchanged except that the detector config / checkpoint are arguments, so a fine-tuned
RTMDet-m gives boxes in exactly the same format and rule: per frame persons with score >= 0.2; `online` = the box with
the largest score x area in that frame (what an app detector would pick), `det` = whole-video user track (IoU-linked, max
sum score x area; uses the future, reference only); 3:4 crop with 12.5% margin per side.

usage (Home, bpt-mmpose, GPU lock): det_crops.py --cfg CFG --ckpt CKPT --out DIR VIDEO.mp4 ...
"""
import argparse, gzip, json, os, pathlib

import cv2
from mmdet.apis import inference_detector, init_detector


def iou(a, b):
    x0, y0, x1, y1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    i = max(0, x1 - x0) * max(0, y1 - y0)
    return i / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i + 1e-9)


def crop(b, m=0.125):
    x0, y0, x1, y1 = b; w, h = x1 - x0, y1 - y0
    w, h = w * (1 + 2 * m), h * (1 + 2 * m)
    if w / h > 0.75: h = w / 0.75
    else: w = h * 0.75
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return cx - w / 2, cy - h / 2, w, h


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--cfg', required=True); p.add_argument('--ckpt', required=True); p.add_argument('--out', required=True)
    p.add_argument('videos', nargs='+')
    a = p.parse_args()
    model = init_detector(a.cfg, a.ckpt, device='cuda:0')
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
    for v in a.videos:
        if (out / (pathlib.Path(v).stem + '_detonline.csv')).exists():
            continue  # resumed run
        cap = cv2.VideoCapture(v); dets = []; ok = True
        while ok:
            imgs = []
            while len(imgs) < 16:
                ok, img = cap.read()
                if not ok: break
                imgs.append(img)
            for r in (inference_detector(model, imgs) if imgs else []):
                r = r.pred_instances
                keep = (r.labels == 0) & (r.scores >= 0.2)
                dets.append([(tuple(b), float(s)) for b, s in zip(r.bboxes[keep].cpu().numpy().tolist(), r.scores[keep].cpu().numpy().tolist())])
        tracks = []  # [last_frame, last_box, {frame: box}, mass]
        for f, ds in enumerate(dets):
            used = set()
            for b, s in sorted(ds, key=lambda d: -d[1]):
                best = max((t for t in tracks if f - t[0] <= 10 and id(t) not in used), key=lambda t: iou(t[1], b), default=None)
                if best is not None and iou(best[1], b) > 0.3:
                    best[0], best[1] = f, b; best[2][f] = b; best[3] += s * (b[2] - b[0]) * (b[3] - b[1]); used.add(id(best))
                else:
                    t = [f, b, {f: b}, s * (b[2] - b[0]) * (b[3] - b[1])]; tracks.append(t); used.add(id(t))
        user = max(tracks, key=lambda t: t[3])[2] if tracks else {}
        stem = pathlib.Path(v).stem
        with gzip.open(out / f'{stem}_dets.json.gz', 'wt') as f:
            json.dump(dets, f)
        online = {f: max(ds, key=lambda d: d[1] * (d[0][2] - d[0][0]) * (d[0][3] - d[0][1]))[0] for f, ds in enumerate(dets) if ds}
        for tag, boxes in (('det', user), ('detonline', online)):
            lines = ['frame,x,y,w,h,source,recheck']
            for f in range(len(dets)):
                lines.append(','.join([str(f)] + (['%.3f' % c for c in crop(boxes[f])] if f in boxes else ['', '', '', '']) + [tag, '']))
            (out / f'{stem}_{tag}.csv').write_text('\n'.join(lines) + '\n')
        print(stem, len(dets), len(user), len(online), flush=True)


if __name__ == '__main__':
    main()
