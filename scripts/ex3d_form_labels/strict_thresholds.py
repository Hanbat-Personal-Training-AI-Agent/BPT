"""Strictness-mode threshold candidates (PT strict / standard / relaxed) from the 2nd-pass (strict) labels
and the rules-calib Python-path rep metrics (strict rubric section 5).

Run on Home (bpt-home) from ~/bpt-runs/rules-calib:
  python strict_thresholds.py <code_dir> <labels_pass1_csv> <labels_strict_csv> <out_json> <out_md> [model]
"""
import csv, json, sys
from collections import defaultdict

CODE, LAB1, LAB2, OJ, OM = sys.argv[1:6]
MODEL = sys.argv[6] if len(sys.argv) > 6 else "orig"
sys.path.insert(0, f"{CODE}/scripts")
sys.path.insert(0, CODE)
import numpy as np  # noqa: E402
import rules_calib_analysis as A  # noqa: E402
from eval_rules_calib import load  # noqa: E402
from pose_feedback.feedback.form_rules import load_preset  # noqa: E402

# criterion -> list of (metric, tail 'upper' = larger is worse, gate branch, preset field for current/rc1, sign)
METRICS = {
    "sq2_depth": [("thigh_incline_min", "upper", "side", "squat.depthAbsThighInclineDegrees", 1), ("knee_min", "upper", "side", None, 1)],
    "sq2_valgus": [("knee_ankle_gap_ratio_min", "lower", "front", "squat.valgusKneeAnkleGapRatio", 1)],
    "sq2_weight_forward": [("heel_rise_max", "upper", "any", "squat.heelRiseShinRatio", 1)],
    "sq2_torso_lean": [("torso_minus_tibia_at_bottom", "upper", "side", "squat.torsoLeanOverTibiaDegrees", 1)],
    "sq2_hips_first": [("q_hips_first", "upper", "side", "squat.hipsFirstTorsoRiseDegrees", 1)],
    "sq2_lockout": [("q_squat_no_lockout", "upper", "side", "squat.noLockoutBelowSetMaxDegrees", 1)],
    "pu2_hip_sag": [("hip_dev_max", "upper", "side", "pushUp.hipSagDeviation", 1)],
    "pu2_hip_pike": [("hip_dev_min", "lower", "side", "pushUp.hipPikeDeviation", -1)],
    "pu2_depth": [("elbow_min", "upper", "side", None, 1), ("upper_arm_incline_max", "lower", "side", "pushUp.depthAbsUpperArmInclineDegrees", 1)],
    "pu2_lockout": [("elbow_max", "lower", "side", "pushUp.lockoutAbsElbowDegrees", 1),
                    ("q_below_setmax_elbow_max", "upper", "side", "pushUp.noLockoutBelowSetMaxDegrees", 1)],
    "pu2_head_up": [("head_dev_change_min", "lower", "side", "pushUp.headUpDeviation", -1)],
    "pu2_head_drop": [("head_dev_change_max", "upper", "side", "pushUp.headDropDeviation", 1)],
    "pu2_hand": [("first_rep_top_wrist_ahead", "upper", "side", "pushUp.handForwardRatio", 1)],
    "row2_torso_hold": [("torso_range", "upper", "side", "row.torsoSwingRangeDegrees", 1)],
    "row2_torso_angle": [("torso_mean", "lower", "side", "row.hingeShallowTorsoDegrees", 1), ("hip_angle_mean", "upper", "side", None, 1)],
    "row2_pull_height": [("pull_peak_wrist_trunk", "lower", "side", "row.pullLowWristTrunk", 1),
                         ("elbow_behind_max", "lower", "side", "row.shortPullAbsBehind", 1)],
    "row2_retraction": [("elbow_behind_max", "lower", "side", "row.shortPullAbsBehind", 1)],
    "row2_head": [("head_dev_change_min", "lower", "side", "row.headUpDeviation", -1)],
}
EX = {"sq2": "squat", "pu2": "pushup", "row2": "barbell_row"}
MIN_PHYS = 5

phys = {}  # (clip, replay_rep) -> phys_rep
for r in csv.DictReader(open(LAB1)):
    if r["replay_rep"]:
        phys[(r["clip"], int(r["replay_rep"]))] = int(r["phys_rep"])
lab2 = {}
for r in csv.DictReader(open(LAB2)):
    lab2[(r["set"], int(r["phys_rep"]), r["criterion"])] = r["label"]

sets = [s for s in load("20261020-pubpy-h26-tune-ex3d/sets_pubpy_halpe26_orig_c1.json.gz")
        if s["dataset"] == "ex3d_own_v1" and s["model"] == MODEL]
sets = A.prepare(sets)
dv, _ = load_preset("app_default")
rc1 = json.load(open(f"20261022-analysis-h26-withfit3d/presets/xs_{MODEL}_rc1.json"))["values"]
RC1_EXTRA = {"hip_angle_mean": 175.0} if MODEL == "orig" else {}  # row_hinge_shallow(hip) variant (analysis only)


def cfg_to_t(v, sign):
    return None if v is None else (v if sign == 1 else -v)


def youden(neg, pos, tail):
    """Threshold (fire if worse than it) maximizing sens + spec - 1; median of the tied optimal midpoints."""
    vals = np.unique(np.concatenate([neg, pos]))
    if len(vals) < 2:
        return None, None
    cands = (vals[:-1] + vals[1:]) / 2
    js = []
    for t in cands:
        sens = np.mean(pos > t) if tail == "upper" else np.mean(pos < t)
        spec = np.mean(neg <= t) if tail == "upper" else np.mean(neg >= t)
        js.append(sens + spec - 1)
    js = np.array(js)
    best = cands[js >= js.max() - 1e-12]
    return float(np.median(best)), float(js.max())


def q(v, p):
    return float(np.percentile(v, p)) if len(v) else None


out, md = {}, []
md += [f"모델 {MODEL}, Ex3D 39클립 Python 앱 경로, 앱 게이트 통과 렙. 묶음 표기: 물리적 렙 수 / 카메라 렙 수, 중앙값 [p10–p90].", ""]
for crit, mets in METRICS.items():
    ex = EX[crit.split("_")[0]]
    for metric, tail, branch, field, sign in mets:
        groups = defaultdict(list)  # label -> [(phys key, value)]
        for s in sets:
            if s["exercise"] != ex:
                continue
            clip = s["set_id"].split("/")[1]
            set_id = clip.rsplit("_", 1)[0]
            for r in s["jreps"]:
                if not A.gate_ok(r, branch) or metric not in r["m"]:
                    continue
                p = phys.get((clip, r["rep"]))
                L = lab2.get((set_id, p, crit)) if p else None
                if L is None:
                    continue
                groups[L].append(((set_id, p), float(r["m"][metric])))
        G = np.array([v for _, v in groups["good"]])
        T = np.array([v for _, v in groups["tip"]])
        E = np.array([v for _, v in groups["error"]])
        nph = {k: len({pk for pk, _ in groups[k]}) for k in ("good", "tip", "error", "unsure")}
        worse_p = (lambda a, lo, hi: q(a, hi)) if tail == "upper" else (lambda a, lo, hi: q(a, lo))
        # PT strict: G vs T∪E
        TE = np.concatenate([T, E])
        if nph["good"] >= MIN_PHYS and nph["tip"] + nph["error"] >= MIN_PHYS:
            t_strict, j_strict = youden(G, TE, tail)
            strict_note = f"Youden J={j_strict:.2f}"
        elif nph["good"] >= MIN_PHYS:
            t_strict, strict_note = worse_p(G, 10, 90), "잠정: good p90/p10(개선점 예 부족)"
        elif nph["tip"] + nph["error"] >= MIN_PHYS:
            # deviation from the rubric (single-grade items): flag 90% of the labelled tip reps; false alarms unknown
            better_p = (lambda a: q(a, 10)) if tail == "upper" else (lambda a: q(a, 90))
            t_strict, strict_note = better_p(TE), "잠정: good 예 없음, 개선점 렙의 90%를 잡는 값(오경보 모름)"
        else:
            t_strict, strict_note = None, "good·개선점 예 부족"
        # standard: G∪T vs E
        GT = np.concatenate([G, T])
        if nph["error"] >= MIN_PHYS and nph["good"] + nph["tip"] >= MIN_PHYS:
            t_std, j_std = youden(GT, E, tail)
            std_note = f"Youden J={j_std:.2f}"
        elif nph["good"] + nph["tip"] >= MIN_PHYS:
            t_std, std_note = worse_p(GT, 1, 99), "error 예 부족: (good∪tip) p99/p1"
        else:
            t_std, std_note = None, "데이터 부족"
        t_relax = cfg_to_t(rc1.get(field), sign) if field else RC1_EXTRA.get(metric)
        t_cur = cfg_to_t(dv.get(field), sign) if field else None

        def rate(a, t):
            if t is None or len(a) == 0:
                return None
            return float(np.mean(a > t) if tail == "upper" else np.mean(a < t))

        rec = dict(criterion=crit, metric=metric, tail=tail, branch=branch, n_phys=nph,
                   n_clip={k: len(groups[k]) for k in ("good", "tip", "error", "unsure")},
                   dist={k: (None if len(a) == 0 else [q(a, 50), q(a, 10), q(a, 90)]) for k, a in (("good", G), ("tip", T), ("error", E))},
                   strict=t_strict, strict_note=strict_note, standard=t_std, standard_note=std_note, relaxed=t_relax, current=t_cur,
                   fire={name: {k: rate(a, t) for k, a in (("good", G), ("tip", T), ("error", E))}
                         for name, t in (("strict", t_strict), ("standard", t_std), ("relaxed", t_relax), ("current", t_cur))})
        out[f"{crit}/{metric}"] = rec

        def d(k):
            x = rec["dist"][k]
            return "–" if x is None else f"{nph[k]}/{rec['n_clip'][k]}, {x[0]:.3g} [{x[1]:.3g}–{x[2]:.3g}]"

        def tt(name, t):
            if t is None:
                return "–"
            f = rec["fire"][name]
            fr = "/".join("–" if f[k] is None else f"{f[k]:.0%}" for k in ("good", "tip", "error"))
            return f"{t:.3g} ({fr})"

        md.append(f"| {crit} | {metric} | {'>' if tail == 'upper' else '<'} | {d('good')} | {d('tip')} | {d('error')} | "
                  f"{tt('strict', t_strict)} | {tt('standard', t_std)} | {tt('relaxed', t_relax)} | {tt('current', t_cur)} | "
                  f"{strict_note}; {std_note} |")
hdr = ["| 항목 | 지표 | 울림 방향 | good | tip | error | PT 엄격 (발화 g/t/e) | 표준 (발화 g/t/e) | 여유 = rc1 (발화 g/t/e) | 현재 앱 (발화 g/t/e) | 근거 |",
       "|---|---|---|---|---|---|---|---|---|---|---|"]
md = md[:2] + hdr + md[2:]
json.dump(out, open(OJ, "w"), indent=1)
open(OM, "w").write("\n".join(md) + "\n")
print("\n".join(md))
