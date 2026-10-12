"""Assign each person (subject / YouTube channel) to tuning or held-out BEFORE any evaluation.

usage: python3 -I make_split.py <split.csv> <source> <person_id>...
Existing rows are never changed; new persons of a source are shuffled with a fixed seed and
alternated tuning/held-out (about 50/50, held-out gets the odd one).
"""
import csv, random, sys
from pathlib import Path

SEED = 20261012


def add(path, source, persons):
    path = Path(path)
    rows = list(csv.DictReader(open(path))) if path.exists() else []
    known = {(r["source"], r["person_id"]) for r in rows}
    new = sorted(p for p in set(persons) if (source, p) not in known)
    random.Random(f"{SEED}:{source}").shuffle(new)
    n_held = sum(r["split"] == "heldout" for r in rows if r["source"] == source)
    n_tune = sum(r["split"] == "tuning" for r in rows if r["source"] == source)
    for p in new:
        s = "tuning" if n_tune < n_held else "heldout"
        n_tune, n_held = n_tune + (s == "tuning"), n_held + (s == "heldout")
        rows.append({"source": source, "person_id": p, "split": s})
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, ["source", "person_id", "split"])
        w.writeheader()
        w.writerows(rows)
    return rows


if __name__ == "__main__":
    import tempfile, os
    t = os.path.join(tempfile.mkdtemp(), "s.csv")
    r = add(t, "x", ["a", "b", "c"]); assert [x["split"] for x in r].count("heldout") == 2
    r2 = add(t, "x", ["a", "d"]); assert r2[:3] == r and r2[3]["split"] == "tuning"
    add(sys.argv[1], sys.argv[2], sys.argv[3:])
