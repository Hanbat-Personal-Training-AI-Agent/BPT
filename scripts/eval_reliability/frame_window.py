"""Per-frame record of the tracker around acquisition / loss, numeric. One CSV row per frame:
input rect used this frame (blank = whole frame 1280x720 stretched to 192x256), why the NEXT rect is what it is
(full = <6 joints >= 0.3 -> lost / still lost; retarget/refit/kept = tracking), the 17 confidences, the count >= 0.3
(the tracker's keep/acquire rule: >= 6), the RTMDet user box (verified, experiment A) relative to the input rect
(x0,y0,x1,y1 as fractions; whole frame when the rect is blank), its size as a share of the input, rep state and count.
usage: frame_window.py <run_dir> <clip> <model> <first> <last> <det_csv|-> <out.csv>
"""
import csv, sys
run, clip, model, a, b, det, outp = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6], sys.argv[7]
rows = list(csv.DictReader(open(f"{run}/{clip}_pushup_{model}.csv")))
crops = list(csv.DictReader(open(f"{run}/{clip}_pushup_{model}_crops.csv")))
D = {}
if det != "-":
    for r in csv.DictReader(open(det)):
        if r["x"]:
            x, y, w, h = (float(r[k]) for k in "xywh")
            # det_crops.crop(): 3:4 rect around the box with 12.5% margin -> undo the margin to get the box back (approx.)
            D[int(r["frame"])] = (x, y, w, h)
with open(outp, "w", newline="") as f:
    wr = csv.writer(f)
    wr.writerow(["frame", "rect_x", "rect_y", "rect_w", "rect_h", "next_source", "recheck", "n_conf_ge_0.3", "rule_ok",
                 "det_rect_in_input_x0", "det_rect_in_input_y0", "det_rect_in_input_x1", "det_rect_in_input_y1",
                 "det_rect_area_share", "status", "rep"] + [f"c{j}" for j in range(17)])
    for i in range(a, min(b, len(rows) - 2) + 1):
        c, r = crops[i], rows[i]
        rect = [float(c[k]) for k in "xywh"] if c["x"] else [0.0, 0.0, 1280.0, 720.0]
        conf = [float(r[f"j{j}_c"] or 0) for j in range(17)]
        n = sum(v >= 0.3 for v in conf)
        rel = [""] * 5
        if i in D:
            x, y, w, h = D[i]; X, Y, W, H = rect
            rel = [round((x - X) / W, 3), round((y - Y) / H, 3), round((x + w - X) / W, 3), round((y + h - Y) / H, 3), round(w * h / (W * H), 3)]
        wr.writerow([i] + ([round(v, 1) for v in rect] if c["x"] else ["", "", "", ""]) + [crops[i + 1]["source"], c["recheck"], n, int(n >= 6)]
                    + rel + [r["status"], r["rep"]] + [round(v, 3) for v in conf])
print("wrote", outp)
