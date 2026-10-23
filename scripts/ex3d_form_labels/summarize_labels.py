"""Occurrence of each labelled form error (physical reps) and the second-instance check agreement.

Usage: python summarize_labels.py <ex3dlab_dir> <out_md>
"""
import csv, math, sys
from collections import Counter, defaultdict
from pathlib import Path

D, OUT = Path(sys.argv[1]), sys.argv[2]
PERSON = {"squat_0000": "P1", "squat_0001": "P1", "squat_0003": "P1", "squat_0002": "P2",
          "barbellrow_0000": "P1", "barbellrow_0002": "P1", "barbellrow_0003": "P2", "barbellrow_0001": "P3",
          **{f"pushup_{i:04d}": "P1" for i in range(5)}}


def wilson(k, n, z=1.96):
    if n == 0:
        return (float("nan"), float("nan"))
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


lab = {}
for f in ("squat.csv", "pushup.csv", "row.csv"):
    for r in csv.DictReader(open(D / "labels" / f)):
        lab[(r["set"], int(r["phys_rep"]), r["criterion"])] = r
md = ["| 기준 | 사람 | 물리적 렙 | error | ok | unsure | n/a | error 비율 [95%] | confidence(error) |", "|---|---|---|---|---|---|---|---|---|"]
crits = sorted({k[2] for k in lab}, key=lambda c: (c.split("_")[0], c))
for c in crits:
    for grp in ("P1", "P2", "P3", "all"):
        rows = [r for (s, p, cc), r in lab.items() if cc == c and (grp == "all" or PERSON[s] == grp)]
        if not rows:
            continue
        n = Counter(r["label"] for r in rows)
        conf = Counter(r["confidence"] for r in rows if r["label"] == "error")
        k, m = n["error"], n["error"] + n["ok"]
        lo, hi = wilson(k, m)
        md.append(f"| {c} | {grp} | {len(rows)} | {k} | {n['ok']} | {n['unsure']} | {n['n/a']} | "
                  + ("–" if m == 0 else f"{k / m:.0%} [{lo:.0%}–{hi:.0%}]") + " | "
                  + ", ".join(f"{a} {b}" for a, b in sorted(conf.items())) + " |")
# second-instance check
chk = list(csv.DictReader(open(D / "labels_check.csv")))
agree, dis = 0, []
for r in chk:
    f = lab.get((r["set"], int(r["phys_rep"]), r["criterion"]))
    if f is None:
        continue
    if f["label"] == r["label"]:
        agree += 1
    else:
        dis.append((r["set"], r["phys_rep"], r["criterion"], f["label"], f["confidence"], r["label"], r["confidence"], f["notes"], r["notes"]))
md += ["", f"두 번째 인스턴스 점검(세트마다 무작위 1렙, 13렙 {len(chk)}항목): 일치 {agree}/{len(chk)} = {agree / len(chk):.0%}", "",
       "| 세트 | 렙 | 기준 | 라벨(포크) | 점검 | 포크 notes | 점검 notes |", "|---|---|---|---|---|---|---|"]
for s, p, c, fl, fc, cl, cc, fn, cn in dis:
    md.append(f"| {s} | {p} | {c} | {fl}/{fc} | {cl}/{cc} | {fn} | {cn} |")
open(OUT, "w").write("\n".join(md) + "\n")
print("\n".join(md))
