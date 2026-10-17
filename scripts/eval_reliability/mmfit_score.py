"""MM-Fit set-level rep accuracy per run dir and model (eval_pushup_mmfit.score: missed = max(0, truth-counted),
extra = max(0, counted-truth), acc = (T-M)/(T+X)). usage: mmfit_score.py <labels_root> <run_dir>..."""
import csv, json, pathlib, sys
lab = {}
for p in sorted(pathlib.Path(sys.argv[1]).glob("*/*_labels.csv")):
    rows = [r for r in csv.reader(open(p)) if r and r[3] == "pushups"]
    for k, r in enumerate(rows, 1): lab[f"{p.name[:3]}_s{k}"] = int(r[2])
def acc(pairs):
    t = sum(a for a, _ in pairs); m = sum(max(0, a - c) for a, c in pairs); x = sum(max(0, c - a) for a, c in pairs)
    return (t - m) / (t + x), m, x, sum(a == c for a, c in pairs), len(pairs)
assert abs(acc([(10, 9), (10, 11)])[0] - 19 / 21) < 1e-12
for run in sys.argv[2:]:
    for m in ("mcoco17", "halpe26"):
        pairs, per = [], []
        for js in sorted(pathlib.Path(run).glob(f"*_pushup_{m}.json")):
            cid = js.name.split("_pushup_")[0]; c = json.load(open(js))["session"]["rep_count"]
            pairs.append((lab[cid], c)); per.append(c)
        if pairs:
            a, mi, x, ex, n = acc(pairs)
            print(f"{pathlib.Path(run).name:42s} {m:8s} acc {a*100:5.1f}%  -{mi} +{x}  exact {ex}/{n}  per-set {per}")
