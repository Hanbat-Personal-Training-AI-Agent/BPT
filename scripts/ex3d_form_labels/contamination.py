"""Re-derive rules-calib rc1 thresholds without the Exercise3D P1 reps labelled as errors (rubric section 6),
and split the Ex3D 'false alarms' (current / rc1 thresholds) by label.

Run on Home (bpt-home) from ~/bpt-runs/rules-calib:
  python contamination.py <code_dir> <labels_csv> <out_json> <out_md>
Uses the same sets, filters and quantile rule as 20261022-analysis-h26-withfit3d (code 1682416).
"""
import csv, json, sys
from collections import defaultdict

CODE, LAB, OJ, OM = sys.argv[1:5]
sys.path.insert(0, f"{CODE}/scripts")
sys.path.insert(0, CODE)
import numpy as np  # noqa: E402
import rules_calib_analysis as A  # noqa: E402
from eval_rules_calib import load  # noqa: E402
from pose_feedback.feedback.form_rules import load_preset  # noqa: E402

SETS = ["20261020-fit3d-h26A-orig/sets_fit3d_halpeA.json.gz", "20261020-fit3d-h26A-c1held/sets_fit3d_halpeA.json.gz",
        "20261020-pubpy-h26-held/sets_pubpy_halpe26_orig_c1.json.gz", "20261020-pubpy-h26-tune-ex3d/sets_pubpy_halpe26_orig_c1.json.gz",
        "20261020-pubpy-h26-tune2d-part1/sets_pubpy_halpe26_orig_c1.json.gz", "20261020-pubpy-h26-tune2d-part2/sets_pubpy_halpe26_orig_c1.json.gz"]
# rule -> (abs criterion, rel criterion)
CRIT = {
    "pushup_hip_sag": ("pu_hip_sag", None), "pushup_hip_pike": ("pu_hip_pike", None),
    "pushup_shallow": ("pu_depth", "pu_depth_rel"), "pushup_no_lockout": ("pu_lockout", "pu_lockout_rel"),
    "pushup_head_drop": ("pu_head_drop", None), "pushup_head_up": ("pu_head_up", None), "pushup_hand_position": ("pu_hand", None),
    "pushup_depth_abs": ("pu_depth", None), "pushup_lockout_abs": ("pu_lockout", None),
    "squat_hips_first": ("sq_hips_first", None), "squat_shallow": ("sq_depth", "sq_depth_rel"),
    "squat_no_lockout": ("sq_lockout", "sq_lockout_rel"), "squat_knee_valgus": ("sq_valgus", None),
    "squat_depth_abs": ("sq_depth", None), "squat_torso_lean": ("sq_torso_lean", None), "squat_heel_rise": ("sq_heel_rise", None),
    "row_torso_swing": ("row_swing", None), "row_standing_up": ("row_standing", None), "row_short_pull": ("row_pull", None),
    "row_head_up": ("row_head_up", None), "row_hinge_shallow": ("row_standing", None), "row_hinge_shallow(hip)": ("row_standing", None),
    "row_short_pull_abs": ("row_pull", None), "row_pull_low": ("row_pull", None),
}
MODELS = ["orig", "c1"]

lab = defaultdict(dict)  # (clip, replay_rep) -> criterion -> label
for r in csv.DictReader(open(LAB)):
    if r["replay_rep"]:
        lab[(r["clip"], int(r["replay_rep"]))][r["criterion"]] = r["label"]

sets = []
for p in SETS:
    sets += load(p)
sets = [s for s in sets if s.get("pose2d", "mcoco17").startswith("halpe")]
seen, uniq = set(), []
for s in sets:
    k = (s["src"], s["model"], s.get("pose2d"), s["set_id"], s.get("up"))
    if k not in seen:
        seen.add(k)
        uniq.append(s)
sets = A.prepare(uniq)
cam = [s for s in sets if s.get("up", "cam") == ("grav" if s["src"] == "fit3d" else "cam")]
# sanity: pubpy rep numbering vs replay reps (reps matching no physical rep stay unlabelled and are kept)
NOLAB = sorted({(s["set_id"], r["rep"]) for s in cam if s["src"] == "ex3d" for r in s["jreps"]
                if (s["set_id"].split("/")[1], r["rep"]) not in lab})
print("unlabelled ex3d judged reps:", len(NOLAB), NOLAB[:20])


def rep_label(s, r, rule, kind):
    a, b = CRIT[rule]
    L = lab.get((s["set_id"].split("/")[1], r["rep"]))
    if L is None:
        return "nolabel"
    la, lb = L.get(a), (L.get(b) if b else None)
    if kind == "abs":
        return la
    if kind == "rel":
        return lb if b else la
    # any: error if either is error, unsure if neither error and one unsure
    vals = [x for x in (la, lb) if x is not None]
    if "error" in vals:
        return "error"
    if "unsure" in vals:
        return "unsure"
    return "ok"


def pool(model, src, group):
    return [s for s in cam if s["model"] == model and s["src"] == src and s.get("group") == group and A.is_normal(s)]


def vals(sets_, ex, branch, q, keep=None):
    return [r["m"][q] for s in sets_ if s["exercise"] == ex for r in s["jreps"]
            if A.gate_ok(r, branch) and q in r["m"] and (keep is None or keep(s, r))]


out = {"derive": {}, "ex3d_fires": {}}
md = ["## rc1 다시 내기 (Ex3D P1에서 error 라벨 렙을 뺌)", "",
      "| 규칙 | 모델 | 꼬리 | 라벨(any) | Ex3D P1 판정 렙 | error | unsure | Ex3D 분위수: 전체 → error 뺌 → error·unsure 뺌 | 다른 출처 | T: rc1 → error 뺌 → error·unsure 뺌 | 결정 출처 |",
      "|---|---|---|---|---|---|---|---|---|---|---|"]
for m in MODELS:
    for rule, ex, branch, q, tail, field, sign in A.RULES + A.VARIANTS:
        if rule not in CRIT:
            continue
        pct = 99 if tail == "upper" else 1
        other, ex3d = [], {}
        for src, group in A.DERIVE.get(m, []):
            P = pool(m, src, group)
            if src != "ex3d":
                v = vals(P, ex, branch, q)
                other.append((src, len(v), float(np.percentile(v, pct)) if len(v) >= A.MIN_N else None))
                continue
            allv = [(s, r) for s in P if s["exercise"] == ex for r in s["jreps"] if A.gate_ok(r, branch) and q in r["m"]]
            labs = [rep_label(s, r, rule, "any") for s, r in allv]
            for name, keep in (("all", lambda L: True), ("no_err", lambda L: L != "error"), ("no_err_unsure", lambda L: L in ("ok", "nolabel"))):
                v = [r["m"][q] for (s, r), L in zip(allv, labs) if keep(L)]
                ex3d[name] = (len(v), float(np.percentile(v, pct)) if len(v) >= A.MIN_N else None)
            ex3d["n_error"] = labs.count("error")
            ex3d["n_unsure"] = labs.count("unsure")
        if not ex3d:
            continue

        def final(qx):
            qs = [x[2] for x in other if x[2] is not None] + ([qx] if qx is not None else [])
            if not qs:
                return None, None
            t = max(qs) if tail == "upper" else min(qs)
            srcs = [x[0] for x in other if x[2] == t] + (["ex3d"] if qx == t else [])
            return t, srcs[0]

        T = {k: final(ex3d[k][1]) for k in ("all", "no_err", "no_err_unsure")}
        key = f"{m}/{rule}/{tail}"
        out["derive"][key] = dict(q=q, ex3d=ex3d, other=other, T=T)
        f = lambda x: "–" if x is None else f"{x:.3g}"
        md.append(f"| {rule} | {m} | {tail} | {'/'.join(c for c in CRIT[rule] if c)} | {ex3d['all'][0]} | {ex3d['n_error']} | "
                  f"{ex3d['n_unsure']} | {f(ex3d['all'][1])} → {f(ex3d['no_err'][1])} (n={ex3d['no_err'][0]}) → "
                  f"{f(ex3d['no_err_unsure'][1])} (n={ex3d['no_err_unsure'][0]}) | "
                  + "; ".join(f"{s} {n} → {f(v)}" for s, n, v in other) +
                  f" | {f(T['all'][0])} → {f(T['no_err'][0])} → {f(T['no_err_unsure'][0])} | {T['all'][1]} → {T['no_err'][1]} |")

# ---- Ex3D fires with current / rc1 thresholds, split by label (P1 tuning and P2/P3 held-out), original XS
md += ["", "## Ex3D 렙 발화(Python 앱 경로, 원래 XS) — 라벨로 나눔", "",
       "| 규칙 | 변형 | 임계값 | 묶음 | 판정 렙 | 발화 | 발화 중 error(맞게 잡음) | 발화 중 ok(진짜 오경보) | 발화 중 unsure | error 렙 | 그중 발화 |",
       "|---|---|---|---|---|---|---|---|---|---|---|"]
dv, _ = load_preset("app_default")
rc1 = json.load(open("20261022-analysis-h26-withfit3d/presets/xs_orig_rc1.json"))["values"]
for rule, ex, branch, q, tail, field, sign in A.RULES:
    if rule not in CRIT or rule in ("pushup_hand_position",):
        continue
    variants = {}
    if field in dv:
        variants["current"] = sign * dv[field] if sign == 1 else -dv[field]
    if field in rc1:
        variants["rc1"] = sign * rc1[field] if sign == 1 else -rc1[field]
    d = out["derive"].get(f"orig/{rule}/{tail}")
    if d and d["T"]["no_err"][0] is not None:
        variants["rc1_no_err"] = d["T"]["no_err"][0]
    for vname, t in variants.items():
        for group in ("tuning", "heldout"):
            reps = [(s, r) for s in cam if s["model"] == "orig" and s["src"] == "ex3d" and s.get("group") == group
                    and s["exercise"] == ex for r in s["jreps"] if A.gate_ok(r, branch) and q in r["m"]]
            fired = [(s, r) for s, r in reps if A.fires(r, rule, q, tail, t, branch)]
            L = [rep_label(s, r, rule, "any") for s, r in fired]
            Lall = [rep_label(s, r, rule, "any") for s, r in reps]
            err_fired = sum(1 for (s, r), l in zip(reps, Lall) if l == "error" and A.fires(r, rule, q, tail, t, branch))
            rec = dict(threshold=t, n=len(reps), fired=len(fired), fired_error=L.count("error"), fired_ok=L.count("ok"),
                       fired_unsure=L.count("unsure"), n_error=Lall.count("error"), error_fired=err_fired)
            out["ex3d_fires"][f"{rule}/{vname}/{group}"] = rec
            md.append(f"| {rule} | {vname} | {t:.3g} | {group} | {rec['n']} | {rec['fired']} | {rec['fired_error']} | {rec['fired_ok']} | "
                      f"{rec['fired_unsure']} | {rec['n_error']} | {rec['error_fired']} |")
out["unlabelled"] = NOLAB
json.dump(out, open(OJ, "w"), indent=1, default=str)
open(OM, "w").write("\n".join(md) + "\n")
print("ok", len(out["derive"]), len(out["ex3d_fires"]))
