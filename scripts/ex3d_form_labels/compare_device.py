"""Compare committed AI-view labels with the device run's judged warnings (rubric section 6).

Usage: python compare_device.py <labels_csv> <blind_dir> <sealed_dir> <out_json> <out_md>
"""
import csv, json, math, sys
from collections import Counter, defaultdict
from pathlib import Path

LAB, BLIND, SEALED, OJ, OM = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4], sys.argv[5]
# key -> (exercise, gate, primary criterion, secondary criterion, min rep index (1-based) the key can fire on)
KEYS = {
    "squat_no_lockout": ("squat", "squat_side", "sq_lockout", "sq_lockout_rel", 2),
    "squat_knee_valgus": ("squat", "squat_front", "sq_valgus", None, 1),
    "squat_shallow": ("squat", "squat_side", "sq_depth", "sq_depth_rel", 4),
    "squat_hips_first": ("squat", "squat_side", "sq_hips_first", None, 1),
    "pushup_no_lockout": ("pushup", "side", "pu_lockout", "pu_lockout_rel", 2),
    "pushup_hip_pike": ("pushup", "side", "pu_hip_pike", None, 1),
    "pushup_shallow": ("pushup", "side", "pu_depth", "pu_depth_rel", 4),
    "pushup_head_up": ("pushup", "side", "pu_head_up", None, 1),
    "pushup_hip_sag": ("pushup", "side", "pu_hip_sag", None, 1),
    "pushup_head_drop": ("pushup", "side", "pu_head_drop", None, 1),
    "row_torso_swing": ("barbellrow", "row_side", "row_swing", None, 1),
    "row_standing_up": ("barbellrow", "row_side", "row_standing", None, 4),
    "row_short_pull": ("barbellrow", "row_side", "row_pull", None, 4),
    "row_head_up": ("barbellrow", "row_side", "row_head_up", None, 1),
}
MUTED = ["squat_no_lockout", "squat_knee_valgus", "pushup_no_lockout", "pushup_hip_pike", "pushup_shallow", "pushup_head_up"]


def wilson(k, n, z=1.96):
    if n == 0:
        return None
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return [round(max(0.0, c - h), 3), round(min(1.0, c + h), 3)]


labels = defaultdict(dict)  # (clip, phys_rep) -> criterion -> row
meta = {}
for r in csv.DictReader(open(LAB)):
    labels[(r["clip"], int(r["phys_rep"]))][r["criterion"]] = r
    meta[r["clip"]] = (r["set"], r["view"], r["person"], r["split"])

out = {"per_rep": [], "tables": {}}
cells = defaultdict(Counter)  # (key, crit_kind, view|'all'|split) -> outcome counts
for clip in sorted(meta):
    b = json.load(open(BLIND / f"{clip}.json"))
    if b.get("device_reps") is None:
        continue
    s = json.load(open(SEALED / f"{clip}.json"))
    sealed = {r["rep_index"]: r for r in s["device_reps"]}
    set_id, view, person, split = meta[clip]
    ex = set_id.split("_")[0]
    phys = sorted(k[1] for k in labels if k[0] == clip)
    anchors = {p: int(next(iter(labels[(clip, p)].values()))["anchor_frame"]) for p in phys}
    for r in b["device_reps"]:
        hit = [p for p, a in anchors.items() if r["start_src"] is not None and r["start_src"] <= a <= r["end_src"]]
        if not hit:
            continue
        p = hit[0]
        sr = sealed[r["rep_index"]]
        fired = set(sr.get("warnings") or [])
        m3 = sr.get("metrics_3d") or {}
        fvf = m3.get("front_view_fraction")
        rec = {"clip": clip, "phys_rep": p, "device_rep": r["rep_index"], "form_source": r.get("form_source"),
               "front_view_fraction": fvf, "warnings": sorted(fired)}
        out["per_rep"].append(rec)
        for key, (kex, gate, crit, crit2, min_rep) in KEYS.items():
            if kex != ex:
                continue
            judged = r.get("form_source") == "3d" and r["rep_index"] >= min_rep
            if gate == "squat_side":
                judged = judged and fvf is not None and fvf < 0.5
            elif gate == "squat_front":
                judged = judged and fvf is not None and fvf >= 0.5
            elif gate == "side":
                judged = judged and fvf is not None and fvf < 0.5
            elif gate == "row_side":
                judged = judged and view != "front"  # session gate: side cams open, rear cams closed (rules-calib 0.66)
            for kind, c in (("abs", crit), ("rel", crit2)):
                if c is None:
                    continue
                lab = labels[(clip, p)].get(c, {}).get("label")
                f = key in fired
                if f and not judged:
                    outcome = "fired_ungated"  # should not happen; reported
                elif not judged:
                    outcome = "not_judged"
                elif lab in ("unsure", None, "", "n/a"):
                    outcome = "unsure" if lab == "unsure" else "n/a"
                elif lab == "error":
                    outcome = "TP" if f else "FN"
                else:
                    outcome = "FP" if f else "TN"
                for g in (view, "all", split):
                    cells[(key, kind, g)][outcome] += 1


def row(c):
    tp, fp, fn, tn = c["TP"], c["FP"], c["FN"], c["TN"]
    return {"TP": tp, "FP": fp, "FN": fn, "TN": tn, "unsure": c["unsure"], "n/a": c["n/a"], "not_judged": c["not_judged"],
            "fired_ungated": c["fired_ungated"],
            "ppv": None if tp + fp == 0 else round(tp / (tp + fp), 3), "ppv_ci": wilson(tp, tp + fp),
            "recall": None if tp + fn == 0 else round(tp / (tp + fn), 3), "recall_ci": wilson(tp, tp + fn),
            "fa_ok": None if fp + tn == 0 else round(fp / (fp + tn), 3), "fa_ok_ci": wilson(fp, fp + tn),
            "fired_rate_judged": None if tp + fp + fn + tn == 0 else round((tp + fp) / (tp + fp + fn + tn), 3)}


md = ["| 키 | 라벨 | 묶음 | 판정 렙 | TP | FP | 놓침 | TN | unsure | 판정 안 됨 | PPV [95%] | 검출률 [95%] | ok 렙 오경보 [95%] |",
      "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]


def fmt(v, ci):
    return "–" if v is None else f"{v:.0%} [{ci[0]:.0%}–{ci[1]:.0%}]"


for key in KEYS:
    for kind in ("abs", "rel"):
        for g in ("side", "diag", "front", "tuning", "heldout", "all"):
            c = cells.get((key, kind, g))
            if not c:
                continue
            t = row(c)
            out["tables"][f"{key}/{kind}/{g}"] = t
            n = t["TP"] + t["FP"] + t["FN"] + t["TN"]
            md.append(f"| {'**' + key + '**' if key in MUTED else key} | {kind} | {g} | {n} | {t['TP']} | {t['FP']} | {t['FN']} | {t['TN']} | "
                      f"{t['unsure']} | {t['not_judged']} | {fmt(t['ppv'], t['ppv_ci'])} | {fmt(t['recall'], t['recall_ci'])} | "
                      f"{fmt(t['fa_ok'], t['fa_ok_ci'])} |")
json.dump(out, open(OJ, "w"), indent=1)
open(OM, "w").write("\n".join(md) + "\n")
print("device reps matched:", len(out["per_rep"]))
print("form_source:", Counter(r["form_source"] for r in out["per_rep"]))
print("fired_ungated:", sum(t["fired_ungated"] for t in out["tables"].values()))
