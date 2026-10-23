"""Merge 2nd-pass (PT strict) labels into docs CSV (one row per physical rep x item) and print grade counts.

Usage: python merge_strict.py <ex3dlab_dir> <sheets_dir> <out_csv> <out_md>
"""
import csv, json, math, sys
from collections import Counter
from pathlib import Path

D, SH, OUT, OM = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4]
ITEMS = {
    "squat": ["sq2_depth", "sq2_butt_wink", "sq2_valgus", "sq2_weight_forward", "sq2_bottom_tempo", "sq2_torso_lean", "sq2_hips_first", "sq2_lockout"],
    "pushup": ["pu2_elbow_flare", "pu2_scapula", "pu2_hip_sag", "pu2_hip_pike", "pu2_depth", "pu2_lockout", "pu2_head_up", "pu2_head_drop", "pu2_hand"],
    "barbellrow": ["row2_back_round", "row2_torso_hold", "row2_torso_angle", "row2_retraction", "row2_pull_height", "row2_shrug", "row2_head"],
}
PERSON = {"squat_0000": "P1", "squat_0001": "P1", "squat_0003": "P1", "squat_0002": "P2",
          "barbellrow_0000": "P1", "barbellrow_0002": "P1", "barbellrow_0003": "P2", "barbellrow_0001": "P3",
          **{f"pushup_{i:04d}": "P1" for i in range(5)}}
gt = json.load(open(D / "gt.json"))
lab = {}
for f in ("squat.csv", "pushup.csv", "row.csv"):
    for r in csv.DictReader(open(D / "labels_strict" / f)):
        r = {k: (v or "").strip() for k, v in r.items()}
        ex = r["set"].split("_")[0]
        assert r["criterion"] in ITEMS[ex], r
        assert r["label"] in ("error", "tip", "good", "unsure"), r
        k = (r["set"], int(r["phys_rep"]), r["criterion"])
        assert k not in lab, f"duplicate {k}"
        lab[k] = r
rows, missing = [], []
for s in sorted(gt):
    ex = s.split("_")[0]
    for fr in json.load(open(SH / f"{s}_frames.json")):
        ph = dict(fr["phases"])
        for c in ITEMS[ex]:
            r = lab.get((s, fr["phys_rep"], c))
            if r is None:
                missing.append((s, fr["phys_rep"], c))
                continue
            rows.append({"set": s, "person": PERSON[s], "split": "tuning" if PERSON[s] == "P1" else "heldout",
                         "phys_rep": fr["phys_rep"], "anchor_frame": fr["anchor"],
                         "t_start_s": round(ph["T0"] / 30, 2), "t_end_s": round(ph["T3"] / 30, 2),
                         "criterion": c, "label": r["label"], "confidence": r["confidence"],
                         "cams_used": r["cams_used"], "notes": r["notes"]})
assert not missing, (len(missing), missing[:5])
with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)


def wilson(k, n, z=1.96):
    if n == 0:
        return (math.nan, math.nan)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


md = ["| 항목 | 렙 | error | tip | good | unsure | 개선점 이상(tip+error) 비율 [95%] | 사람별 tip+error |", "|---|---|---|---|---|---|---|---|"]
for ex, items in ITEMS.items():
    for c in items:
        rs = [r for r in rows if r["criterion"] == c]
        n = Counter(r["label"] for r in rs)
        k, m = n["tip"] + n["error"], n["tip"] + n["error"] + n["good"]
        lo, hi = wilson(k, m)
        per = {}
        for p in ("P1", "P2", "P3"):
            pr = [r for r in rs if r["person"] == p and r["label"] != "unsure"]
            if pr:
                per[p] = f"{sum(r['label'] in ('tip', 'error') for r in pr)}/{len(pr)}"
        md.append(f"| {c} | {len(rs)} | {n['error']} | {n['tip']} | {n['good']} | {n['unsure']} | "
                  + ("–" if m == 0 else f"{k / m:.0%} [{lo:.0%}–{hi:.0%}]") + f" | {', '.join(f'{a} {b}' for a, b in per.items())} |")
open(OM, "w").write("\n".join(md) + "\n")
print("rows", len(rows))
print("\n".join(md))
