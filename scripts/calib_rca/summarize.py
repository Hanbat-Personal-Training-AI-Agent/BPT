"""calib-rca CSV 요약: 안내 분포, 시간표, '발끝까지'의 원인 관절, 관문별 값 분포.

conda bpt-eval:  python -I scripts/calib_rca/summarize.py <run.csv> [...]
"""
import csv
import sys
from collections import Counter

import numpy as np

REQUIRED = {5: "L어깨", 6: "R어깨", 7: "L팔꿈치", 8: "R팔꿈치", 9: "L손목", 10: "R손목",
            11: "L엉덩이", 12: "R엉덩이", 13: "L무릎", 14: "R무릎", 15: "L발목", 16: "R발목"}
CONF = 0.3


def num(row, key):
    value = row[key]
    return float(value) if value else None


def pct(values, qs=(10, 50, 90)):
    values = [v for v in values if v is not None]
    if not values:
        return "-"
    return " / ".join(f"{np.percentile(values, q):.2f}" for q in qs) + f" (n={len(values)})"


def summarize(path):
    rows = list(csv.DictReader(open(path)))
    n = len(rows)
    print(f"## {path}  frames={n}")
    counts = Counter(r["guidance"] for r in rows)
    print("guidance: " + ", ".join(f"{k} {v} ({100 * v / n:.0f}%)" for k, v in counts.most_common()))

    runs = []
    for r in rows:
        t, g = float(r["t"]), r["guidance"]
        if runs and runs[-1][2] == g:
            runs[-1][1] = t
        else:
            runs.append([t, t, g])
    print("timeline (>=0.3 s): " + " | ".join(f"{a:.1f}-{b:.1f} {g}" for a, b, g in runs if b - a >= 0.3))
    print("captured: " + (rows[-1]["captured"] or "none") if rows else "")

    full = [r for r in rows if r["guidance"] == "showFullBody"]
    missing = Counter()
    edge = Counter()
    for r in full:
        if r["bodyH"]:
            edge["head<0.02" if num(r, "headTop") < 0.02 else "feet>0.98"] += 1
        else:
            for j, name in REQUIRED.items():
                if float(r[f"k{j}s"]) < CONF:
                    missing[name] += 1
    if full:
        print(f"showFullBody {len(full)}: measure 실패(관절<0.3) {len(full) - sum(edge.values())}, 가장자리 {dict(edge)}")
        print("  관절<0.3 빈도: " + ", ".join(f"{k} {v}" for k, v in missing.most_common()))

    measured = [r for r in rows if r["bodyH"]]
    print(f"measured frames {len(measured)}")
    print(f"  stepForward feet p10/p50/p90 {pct([num(r, 'feet') for r in measured if r['guidance'] == 'stepForward'])}")
    for key in ("bodyH", "headTop", "feet", "midX", "wristReach", "wristDropL", "wristDropR",
                "elbowL", "elbowR", "ankleGap", "motion"):
        print(f"  {key:10s} p10/p50/p90 {pct([num(r, key) for r in measured])}")
    print("candidate view (관문 무시 분류): " + ", ".join(
        f"{k or '-'} {v}" for k, v in Counter(r["candidate"] for r in rows).most_common()))

    def ok_frame(r):
        return 0.40 <= num(r, "bodyH") <= 0.85 and num(r, "headTop") >= 0.02 and num(r, "feet") <= 0.98 \
            and abs(num(r, "midX") - 0.5) <= 0.06

    def ok_arms(r):
        drops = (num(r, "wristDropL"), num(r, "wristDropR"))
        elbows = (num(r, "elbowL"), num(r, "elbowR"))
        return all(0.60 <= d <= 0.97 for d in drops) and all(0.38 <= e <= 0.75 for e in elbows)

    framing = [r for r in measured if ok_frame(r)]
    arms = [r for r in framing if ok_arms(r)]
    reach = [r for r in arms if num(r, "wristReach") >= 0.8]
    feet = [r for r in reach if 0.9 <= num(r, "ankleGap") <= 2.6]
    print(f"funnel: measured {len(measured)} → framing {len(framing)} → arms(drop,elbow) {len(arms)}"
          f" → front reach≥0.8 {len(reach)} → front feet gap {len(feet)}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        summarize(p)
        print()
