"""Per-clip tracking events from pose-replay outputs (<stem>_<ex>_<model>.csv, _crops.csv, .json). Numeric only.

Tracker rule (RTMPoseCropTracker.update, RTMPoseInputTensor.swift): a frame whose COCO-17 keypoints have < 6 joints with
confidence >= 0.3 (or a degenerate box) resets the crop -> the NEXT frame is the whole frame stretched to 192x256.
Each lost frame is itself the re-acquisition attempt (no separate search); acquisition = a whole-frame pass with >= 6.

Per clip:
  first_track      first frame whose input is a crop (source != full)
  first_sustained  first frame of the first crop run >= 30 frames
  initial_failure  'late_acquire' if first_sustained > label start (90 for MM-Fit clips, else 0) else
                   the first frame after first_sustained whose input is the whole frame again ('lost' at f-1)
  loss_window      for the first loss: per frame in [loss-10, loss]: rect, keypoint box inside rect, n_conf>=0.3,
                   sorted 17 confidences, source of next rect, status, rep
  lost_frames_in_window  whole-frame inputs inside [label_start, label_end]
  reacq_delays     for every loss after a sustained track: frames until the next sustained (>=30) crop run
usage: python -I track_events.py <out.json> <label_start> <label_end|-1> <csv>...  (label args apply to all csvs;
       pass 'mmfit:<labels_root>' as label_start to take them from MM-Fit labels by clip name)
"""
import csv, json, pathlib, sys

MIN_C, MIN_J = 0.3, 6


def load(csvp):
    rows = list(csv.DictReader(open(csvp)))
    crops = list(csv.DictReader(open(str(csvp)[:-4] + "_crops.csv")))
    js = json.load(open(str(csvp)[:-4] + ".json"))
    return rows, crops, js


def conf(r):
    return [float(r[f"j{j}_c"] or 0) for j in range(17)]


def kbox(r):
    p = [(float(r[f"j{j}_x"]), float(r[f"j{j}_y"])) for j in range(17) if float(r[f"j{j}_c"] or 0) >= MIN_C]
    if len(p) < 1: return None
    xs, ys = [a for a, _ in p], [b for _, b in p]
    return [min(xs), min(ys), max(xs), max(ys)]


def runs(is_crop):
    out, st = [], None
    for i, c in enumerate(is_crop + [False]):
        if c and st is None: st = i
        if not c and st is not None: out.append((st, i - 1)); st = None
    return out


def analyse(csvp, ls, le):
    rows, crops, js = load(csvp)
    n = len(rows)
    is_crop = [c["source"] not in ("full",) and c["x"] != "" for c in crops][:n]
    nconf = [sum(c >= MIN_C for c in conf(r)) for r in rows]
    R = runs(is_crop)
    sus = [r for r in R if r[1] - r[0] + 1 >= 30]
    first_track = next((i for i, c in enumerate(is_crop) if c), None)
    first_sus = sus[0][0] if sus else None
    le = n - 1 if le < 0 else min(le, n - 1)
    res = dict(clip=pathlib.Path(csvp).name, frames=n, reps=js["session"]["rep_count"],
               full_inputs=sum(not c for c in is_crop), first_track=first_track, first_sustained=first_sus,
               lost_frames_in_window=sum(not is_crop[i] for i in range(ls, le + 1)),
               acquirable_full_frames=sum(1 for i in range(n) if not is_crop[i] and nconf[i] >= MIN_J))
    # losses after a sustained track: end of a run (not the last frame)
    losses = [r[1] for r in R if r[1] - r[0] + 1 >= 30 and r[1] < n - 1]
    res["losses_after_sustained"] = len(losses)
    delays = []
    for l in losses:
        nxt = next((s[0] for s in sus if s[0] > l), None)
        delays.append(None if nxt is None else nxt - l)
    res["reacq_delays"] = delays
    if first_sus is None or first_sus > ls:
        res["initial_failure"] = "late_acquire" if first_sus is not None else "never_sustained"
        f0 = ls
    elif losses:
        res["initial_failure"] = "lost"; f0 = losses[0]
    else:
        res["initial_failure"] = "none"; f0 = None
    res["initial_failure_frame"] = f0
    if f0 is not None and res["initial_failure"] == "lost":
        win = []
        for i in range(max(0, f0 - 10), min(n, f0 + 2)):
            c = crops[i]; r = rows[i]; kb = kbox(r)
            rect = [float(c[k]) for k in "xywh"] if c["x"] else None
            inside = None
            if rect and kb:
                x, y, w, h = rect
                inside = [round((kb[0] - x) / w, 3), round((kb[1] - y) / h, 3), round((kb[2] - x) / w, 3), round((kb[3] - y) / h, 3)]
            win.append(dict(frame=i, rect=rect, source=c["source"], next_source=crops[i + 1]["source"] if i + 1 < len(crops) else None,
                            n_conf=nconf[i], conf_sorted=sorted([round(v, 3) for v in conf(r)], reverse=True),
                            kbox_in_rect=inside, status=r["status"], rep=int(r["rep"])))
        res["loss_window"] = win
    if res["initial_failure"] in ("late_acquire", "never_sustained"):
        # the whole-frame frames before acquisition: how close to the 6-joint rule
        pre = [nconf[i] for i in range(0, (first_sus if first_sus is not None else n)) if not is_crop[i]]
        res["preacq_nconf_hist"] = {k: pre.count(k) for k in sorted(set(pre))}
        res["preacq_frames_ge6"] = sum(v >= MIN_J for v in pre)
    return res


def mmfit_labels(root):
    out = {}
    for lab in sorted(pathlib.Path(root).glob("*/*_labels.csv")):
        w = lab.name[:3]
        rows = [r for r in csv.reader(open(lab)) if r and r[3] == "pushups"]
        for k, (s, e, n, _) in enumerate(rows, 1):
            s, e = int(s), int(e); off = round(min(90, s)); out[f"{w}_s{k}"] = (off, off + e - s)
    return out


if __name__ == "__main__":
    assert runs([False, True, True, False, True]) == [(1, 2), (4, 4)]
    out, a, b, *csvs = sys.argv[1:]
    lab = mmfit_labels(a.split(":", 1)[1]) if a.startswith("mmfit:") else None
    res = []
    for c in csvs:
        stem = pathlib.Path(c).name.split("_pushup_")[0]
        ls, le = lab[stem] if lab else (int(a), int(b))
        res.append(analyse(c, ls, le))
    json.dump(res, open(out, "w"), indent=1)
    for r in res:
        print(r["clip"], r["reps"], r["initial_failure"], r["initial_failure_frame"], "full", r["full_inputs"],
              "lost_in_win", r["lost_frames_in_window"], "losses", r["losses_after_sustained"], r["reacq_delays"])
