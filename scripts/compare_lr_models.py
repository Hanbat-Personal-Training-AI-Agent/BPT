"""Per-joint left/right swap rates of two 2D models side by side (device runs, ex3d_lr_swap_device.py outputs).

  conda run -n bpt-eval python -I scripts/compare_lr_models.py <nameA> <a.json>[,<a2.json>] <nameB> <b.json>[,<b2.json>]

One row per clip present in both; the swap share per pair (wrist, elbow, shoulder, hip, knee, ankle) and whole-body
swaps, A → B. Labels are Exercise3D Sapiens pseudo labels (see ex3d_lr_swap_device.py).
"""
import json
import sys

PAIRS = ("wrist", "elbow", "shoulder", "hip", "knee", "ankle")


def load(spec):
    rows = {}
    for path in spec.split(","):
        for r in json.load(open(path)):
            rows[r["clip"]] = r
    return rows


def pct(v):
    return "–" if v is None else f"{100 * v:.0f}%"


def main(name_a, a_spec, name_b, b_spec):
    a, b = load(a_spec), load(b_spec)
    print(f"| clip | 각도 | 가까운 쪽 | " + " | ".join(f"{p} {name_a}→{name_b}" for p in PAIRS) + f" | 몸 전체 {name_a}→{name_b} |")
    print("|---|---|---|" + "---|" * (len(PAIRS) + 1))
    for clip in sorted(set(a) & set(b)):
        ra, rb = a[clip], b[clip]
        cells = [f'{pct(ra.get("swap_" + p))} → {pct(rb.get("swap_" + p))}' for p in PAIRS]
        print(f'| {clip} | {ra["angle"]:.0f}° | {ra["near_side"]} | ' + " | ".join(cells)
              + f' | {pct(ra.get("whole_body_swap"))} → {pct(rb.get("whole_body_swap"))} |')


if __name__ == "__main__":
    main(*sys.argv[1:])
