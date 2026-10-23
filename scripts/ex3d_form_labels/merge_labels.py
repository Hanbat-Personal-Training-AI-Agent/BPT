"""Expand per-physical-rep labels (labels/{squat,pushup,row}.csv) to one row per clip x physical rep x criterion,
with the rep's time range and the device / 2D-replay rep it maps to (anchor frame inside the rep interval).

Usage: python merge_labels.py <ex3dlab_dir> <sheets_dir> <out_csv>
Reads only blind tables (no warnings).
"""
import csv, json, sys
from pathlib import Path

D, SHEETS, OUT = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
FPS = 30.0
gt = json.load(open(D / "gt.json"))
PERSON = {"squat_0000": "P1", "squat_0001": "P1", "squat_0003": "P1", "squat_0002": "P2",
          "barbellrow_0000": "P1", "barbellrow_0002": "P1", "barbellrow_0003": "P2", "barbellrow_0001": "P3",
          **{f"pushup_{i:04d}": "P1" for i in range(5)}}
CRITERIA = {
    "squat": ["sq_depth", "sq_depth_rel", "sq_valgus", "sq_hips_first", "sq_heel_rise", "sq_lockout", "sq_lockout_rel", "sq_torso_lean"],
    "pushup": ["pu_hip_sag", "pu_hip_pike", "pu_depth", "pu_depth_rel", "pu_lockout", "pu_lockout_rel", "pu_head_up", "pu_head_drop", "pu_hand"],
    "barbellrow": ["row_swing", "row_standing", "row_pull", "row_shrug", "row_head_up"],
}
LABELS = {"ok", "error", "unsure", "n/a"}


def view_bin(a):
    return "side" if a <= 40 else ("diag" if a <= 70 else "front")


def containing(reps, frame, s="start", e="end"):
    hits = [r for r in reps if r.get(s) is not None and r.get(e) is not None and r[s] <= frame <= r[e]]
    return hits[0] if hits else None


def load_labels():
    lab = {}
    for f, ex in (("squat.csv", "squat"), ("pushup.csv", "pushup"), ("row.csv", "barbellrow")):
        for r in csv.DictReader(open(D / "labels" / f)):
            r = {k: (v or "").strip() for k, v in r.items()}
            assert r["set"].startswith(ex), r
            assert r["criterion"] in CRITERIA[ex], r
            assert r["label"] in LABELS, r
            key = (r["set"], int(r["phys_rep"]), r["criterion"])
            assert key not in lab, f"duplicate {key}"
            lab[key] = r
    return lab


def main():
    lab = load_labels()
    rows, missing = [], []
    for set_id in sorted(gt):
        ex = set_id.split("_")[0]
        frames = json.load(open(SHEETS / f"{set_id}_frames.json"))
        for cam in ("cam1", "cam2", "cam3"):
            b = json.load(open(D / "blind" / f"{set_id}_{cam}.json"))
            dev = [dict(r, start=r.get("start_src"), end=r.get("end_src")) for r in (b.get("device_reps") or [])]
            rep = [dict(r, start=r["start_frame"], end=r["end_frame"]) for r in b["replay_reps"]]
            ang = gt[set_id]["views"][cam]["angle_deg"]
            for fr in frames:
                ph = dict(fr["phases"])
                t0, t3 = ph["T0"], ph["T3"]
                d = containing(dev, fr["anchor"]) if b.get("device_reps") is not None else None
                p = containing(rep, fr["anchor"])
                for c in CRITERIA[ex]:
                    L = lab.get((set_id, fr["phys_rep"], c))
                    if L is None:
                        missing.append((set_id, fr["phys_rep"], c))
                        continue
                    vis = dict(kv.split("=") for kv in L["cam_visible"].replace(" ", "").split(";") if "=" in kv)
                    rows.append({
                        "clip": f"{set_id}_{cam}", "set": set_id, "cam": cam, "view_deg": ang, "view": view_bin(ang),
                        "person": PERSON[set_id], "split": "tuning" if PERSON[set_id] == "P1" else "heldout",
                        "phys_rep": fr["phys_rep"], "anchor_frame": fr["anchor"],
                        "t_start_s": round(t0 / FPS, 2), "t_end_s": round(t3 / FPS, 2),
                        "device_rep": "" if d is None else d["rep_index"],
                        "device_t_start_s": "" if d is None else round(d["start"] / FPS, 2),
                        "device_t_end_s": "" if d is None else round(d["end"] / FPS, 2),
                        "replay_rep": "" if p is None else p["rep"],
                        "criterion": c, "label": L["label"], "confidence": L["confidence"],
                        "cam_visible": vis.get(cam, ""), "cams_used": L["cams_used"], "notes": L["notes"],
                    })
    if missing:
        print("MISSING labels:", len(missing), missing[:10])
    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    # device / replay reps that match no physical rep (extra reps)
    for set_id in sorted(gt):
        frames = json.load(open(SHEETS / f"{set_id}_frames.json"))
        anchors = [fr["anchor"] for fr in frames]
        for cam in ("cam1", "cam2", "cam3"):
            b = json.load(open(D / "blind" / f"{set_id}_{cam}.json"))
            for name, reps, s, e in (("device", b.get("device_reps") or [], "start_src", "end_src"),
                                     ("replay", b["replay_reps"], "start_frame", "end_frame")):
                extra = [r.get("rep_index", r.get("rep")) for r in reps
                         if not any(r[s] is not None and r[s] <= a <= r[e] for a in anchors)]
                if extra:
                    print("extra", name, set_id, cam, extra)
    print("rows", len(rows))


if __name__ == "__main__":
    main()
