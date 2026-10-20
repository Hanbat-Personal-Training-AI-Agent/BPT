"""rules-calib analysis (eval_rules_calib.py analyze): pre-registered thresholds per model, held-out false alarms,
detection, view / subject stability, praise effect and verdicts (docs/results/rules_calib_prereg.md §5–6).

Input sets: dict(meta..., up, reps=[dict(rep, judged, side_view, m, [all_ok])]). Output: <run-dir>/analysis.json,
<run-dir>/tables.md, <run-dir>/presets/<name>.json (Home); only these aggregates go to git.
"""
import json, math
from collections import defaultdict
from pathlib import Path

import numpy as np

from eval_rules_calib import add_set_quantities, load, write_manifest
from pose_feedback.feedback.form_rules import judge, load_preset

# rule, exercise, branch (side = side-view gate passed, front = squat front branch), quantity, tail, config field, sign
# (config value = sign * quantile; sign -1 = the app compares with -T).
RULES = [
    ("pushup_hip_sag", "pushup", "side", "hip_dev_max", "upper", "pushUp.hipSagDeviation", 1),
    ("pushup_hip_pike", "pushup", "side", "hip_dev_min", "lower", "pushUp.hipPikeDeviation", -1),
    ("pushup_shallow", "pushup", "side", "q_over_base_elbow_min", "upper", "pushUp.shallowOverBaselineDegrees", 1),
    ("pushup_no_lockout", "pushup", "side", "q_below_setmax_elbow_max", "upper", "pushUp.noLockoutBelowSetMaxDegrees", 1),
    ("pushup_head_drop", "pushup", "side", "head_dev_change_max", "upper", "pushUp.headDropDeviation", 1),
    ("pushup_head_up", "pushup", "side", "head_dev_change_min", "lower", "pushUp.headUpDeviation", -1),
    ("pushup_hand_position", "pushup", "side", "first_rep_top_wrist_ahead", "upper", "pushUp.handForwardRatio", 1),
    ("pushup_hand_position", "pushup", "side", "first_rep_top_wrist_ahead", "lower", "pushUp.handBackwardRatio", -1),
    ("pushup_depth_abs", "pushup", "side", "upper_arm_incline_max", "lower", "pushUp.depthAbsUpperArmInclineDegrees", 1),
    ("pushup_lockout_abs", "pushup", "side", "elbow_max", "lower", "pushUp.lockoutAbsElbowDegrees", 1),
    ("squat_hips_first", "squat", "side", "q_hips_first", "upper", "squat.hipsFirstTorsoRiseDegrees", 1),
    ("squat_shallow", "squat", "side", "q_over_base_knee_min", "upper", "squat.shallowOverBaselineDegrees", 1),
    ("squat_no_lockout", "squat", "side", "q_squat_no_lockout", "upper", "squat.noLockoutBelowSetMaxDegrees", 1),
    ("squat_knee_valgus", "squat", "front", "knee_ankle_gap_ratio_min", "lower", "squat.valgusKneeAnkleGapRatio", 1),
    ("squat_depth_abs", "squat", "side", "thigh_incline_min", "upper", "squat.depthAbsThighInclineDegrees", 1),
    ("squat_torso_lean", "squat", "side", "torso_minus_tibia_at_bottom", "upper", "squat.torsoLeanOverTibiaDegrees", 1),
    # Halpe26 feet (2D), added after the user's Halpe26 decision (20:50) — outside the pre-registration, judged in every view.
    ("squat_heel_rise", "squat", "any", "heel_rise_max", "upper", "squat.heelRiseShinRatio", 1),
    ("row_torso_swing", "barbell_row", "side", "torso_range", "upper", "row.torsoSwingRangeDegrees", 1),
    ("row_standing_up", "barbell_row", "side", "q_standing_up", "upper", "row.standingUpDegrees", 1),
    ("row_short_pull", "barbell_row", "side", "q_short_pull", "upper", "row.shortPullBelowBaseline", 1),
    ("row_head_up", "barbell_row", "side", "head_dev_change_min", "lower", "row.headUpDeviation", -1),
    ("row_hinge_shallow", "barbell_row", "side", "torso_mean", "lower", "row.hingeShallowTorsoDegrees", 1),
    ("row_knees_locked", "barbell_row", "side", "knee_max", "upper", "row.kneesLockedDegrees", 1),
    ("row_knees_bent", "barbell_row", "side", "knee_min", "lower", "row.kneesBentDegrees", 1),
    ("row_pull_high", "barbell_row", "side", "pull_peak_wrist_trunk", "upper", "row.pullHighWristTrunk", 1),
    ("row_pull_low", "barbell_row", "side", "pull_peak_wrist_trunk", "lower", "row.pullLowWristTrunk", 1),
    ("row_uneven_pull", "barbell_row", "side", "pull_peak_asym", "upper", "row.unevenPullRatio", 1),
    ("row_elbow_flare", "barbell_row", "side", "pull_peak_flare", "upper", "row.elbowFlareDegrees", 1),
    ("row_wrist_lead", "barbell_row", "side", "pull_peak_forearm_tilt", "upper", "row.wristLeadDegrees", 1),
    ("row_straight_arm", "barbell_row", "side", "elbow_min", "upper", "row.straightArmElbowDegrees", 1),
    ("row_short_pull_abs", "barbell_row", "side", "elbow_behind_max", "lower", "row.shortPullAbsBehind", 1),
]
# Variant metric (analysis only): body-relative hinge = rep mean hip angle, too open = too upright.
VARIANTS = [("row_hinge_shallow(hip)", "barbell_row", "side", "hip_angle_mean", "upper", None, 1)]
TREND = {"pushup_depth_fade", "squat_lean_drift", "squat_depth_fade"}
# Wrong-form label of each rule: AI 2-pass consensus keys (labels CSV wrong_key) or 'other:' consensus (prereg §3).
LABEL = {"pushup_depth_abs": "pushup_shallow", "pushup_lockout_abs": "pushup_no_lockout", "squat_depth_abs": "squat_shallow",
         "row_hinge_shallow": "row_standing_up", "row_hinge_shallow(hip)": "row_standing_up", "row_short_pull_abs": "row_short_pull",
         "squat_torso_lean": "other:squat_torso_lean", "row_elbow_flare": "other:row_elbow_flare",
         "row_straight_arm": "other:row_straight_arm"}
# Literature candidates (evaluated, never tuned): config value.
LITERATURE = {"squat_depth_abs": 0.0, "squat_torso_lean": 0.0, "pushup_depth_abs": 0.0}
# S7 candidates (lift_app.md, derived on the held-out original-XS reps: circular) as (quantity, op, threshold).
S7 = {"pushup_hip_pike": ("hip_dev_min", "<", -0.328), "pushup_hip_sag": ("hip_dev_max", ">", 0.099),
      "pushup_head_up": ("head_dev_change_min", "<", -0.275), "pushup_head_drop": ("head_dev_change_max", ">", 0.261),
      "pushup_shallow": ("q_over_base_elbow_min", ">", 2.6), "pushup_no_lockout": ("q_below_setmax_elbow_max", ">", 13.1),
      "squat_shallow": ("q_over_base_knee_min", ">", 8.5), "squat_hips_first": ("q_hips_first", ">", 8.6),
      "squat_knee_valgus": ("knee_ankle_gap_ratio_min", "<", 0.675), "row_torso_swing": ("torso_range", ">", 38.2),
      "row_standing_up": ("q_standing_up", ">", 2.9), "row_short_pull": ("q_short_pull", ">", 0.099),
      "row_head_up": ("head_dev_change_min", "<", -0.15)}
# Derivation sources per model (prereg §3, coordinator 2026-10-20: no fine-tuned thresholds from its training data).
DERIVE = {"mocap": [("fit3d", "tuning")], "orig": [("fit3d", "tuning"), ("public", "tuning"), ("ex3d", "tuning")],
          "c1": [("public", "tuning"), ("ex3d", "tuning")], "c2": [("public", "tuning")]}
HELDOUT = [("fit3d", "heldout"), ("public", "heldout"), ("ex3d", "heldout")]
MIN_N, FA_TARGET, MIN_BAD = 20, 0.05, 5


def wilson(k, n, z=1.96):
    if n == 0:
        return (float("nan"), float("nan"))
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def fisher_greater(a, b, c, d):
    """One-sided Fisher exact p for [[a, b], [c, d]] (rows bad / good, cols fired / not): bad fires more often."""
    from scipy.stats import fisher_exact
    return float(fisher_exact([[a, b], [c, d]], alternative="greater")[1])


def is_normal(s):
    if s["src"] in ("fit3d", "ex3d"):
        return True
    if s["src"] == "public":
        return s.get("label") == "good" and s.get("ai_form") == "normal" and s.get("form_status") == "ok"
    return False


def is_bad(s):
    return s["src"] == "public" and s.get("label") == "bad" and s.get("form_status") != "excluded_duplicate"


def has_label(s, rule):
    lab = LABEL.get(rule, rule)
    if lab.startswith("other:"):
        return (s.get("other") or {}).get(lab[6:]) == "consensus"
    return s.get("form_status") == "ok" and lab in (s.get("ai_keys") or [])


def prepare(sets):
    """Judged reps per set in order with the set quantities (q_*) on them."""
    for s in sets:
        reps = [dict(r, m=dict(r["m"])) for r in s["reps"] if r["judged"]]
        add_set_quantities([r["m"] for r in reps])
        for r in reps:
            if "q_hips_first" in r["m"] and r["m"]["q_hips_first"] < -1e8:
                r["m"]["q_hips_first"] = 0.0  # hip not faster than the shoulder: never fires for T >= 0
        s["jreps"] = reps
    return sets


def gate_ok(r, branch, gate=True):
    if not gate or branch == "any":
        return True
    sv = r["side_view"]
    return bool(sv) if branch == "side" else (sv is False)


def values(sets, ex, branch, q, gate=True):
    return [r["m"][q] for s in sets if s["exercise"] == ex for r in s["jreps"] if gate_ok(r, branch, gate) and q in r["m"]]


def fires(r, rule, q, tail, t, branch, gate=True):
    if not gate_ok(r, branch, gate) or q not in r["m"]:
        return False
    return r["m"][q] > t if tail == "upper" else r["m"][q] < t


def run_analyze(a):
    sets = []
    for p in a.sets.split(","):
        sets += load(p)
    if a.pose2d:  # one 2D family at a time (Fit3D experiment-A sets: halpe26A / cocoA match their prefix)
        sets = [s for s in sets if s.get("pose2d", "mcoco17").startswith(a.pose2d)]
    seen, uniq = set(), []
    for s in sets:  # the same set from two runs (e.g. mocap in every Fit3D run) counts once
        k = (s["src"], s["model"], s.get("pose2d"), s["set_id"], s.get("up"))
        if k not in seen:
            seen.add(k)
            uniq.append(s)
    sets = uniq
    prepare(sets)
    models = sorted({s["model"] for s in sets}, key=lambda m: ["mocap", "orig", "c1", "c2"].index(m) if m in ["mocap", "orig", "c1", "c2"] else 9)
    # Primary "up": the app's camera −y with the phone upright. Fit3D cameras are pitched ~11° down, so their camera −y is
    # not that condition; their true gravity is (an upright phone's camera −y ≈ gravity). Fit3D camera −y is used only for
    # the camera-up vs gravity table. (Recorded in rules_calib.md before any held-out result was computed.)
    cam = [s for s in sets if s.get("up", "cam") == ("grav" if s["src"] == "fit3d" else "cam")]
    out = dict(thresholds={}, fa={}, detection={}, discrimination={}, verdict={}, views={}, subjects={}, praise={},
               metric_error={}, grav={}, label_counts={}, n_reps={})
    md = []

    def pool(model, src, group, normal=True):
        return [s for s in cam if s["model"] == model and s["src"] == src and s.get("group") == group and (is_normal(s) if normal else True)]

    # ---- derivation
    md += ["## 도출 임계값 (모델별, 사전 등록 규칙: 출처마다 p99/p1, 가장 느슨한 값; n<20 출처 제외)", "",
           "| 규칙 | 지표 | 꼬리 | 현재 | " + " | ".join(f"{m} (출처: n → 분위수)" for m in models) + " |", "|---" * (4 + len(models)) + "|"]
    for rule, ex, branch, q, tail, field, sign in RULES + VARIANTS:
        cur = None
        if field:
            dv, _ = load_preset("app_default")
            cur = dv.get(field)
        row = [rule, q, tail, "-" if cur is None else f"{cur:g}"]
        for m in models:
            parts, qs = [], []
            for src, group in DERIVE.get(m, []):
                v = values(pool(m, src, group), ex, branch, q)
                if len(v) >= MIN_N:
                    qq = float(np.percentile(v, 99 if tail == "upper" else 1))
                    qs.append(qq)
                    parts.append(f"{src} {len(v)} → {qq:.3g}")
                else:
                    parts.append(f"{src} {len(v)} (n<20)")
            t = (max(qs) if tail == "upper" else min(qs)) if qs else None
            key = f"{m}/{rule}/{tail}"
            out["thresholds"][key] = dict(q=q, threshold=t, config=None if t is None or field is None else sign * t, field=field, parts=parts)
            row.append(("**" + f"{t:.3g}" + "** ← " if t is not None else "없음 ← ") + "; ".join(parts))
        md.append("| " + " | ".join(row) + " |")

    # ---- presets (rc1): derived values; rules without a threshold keep the default (old) / stay off (new)
    presets = {}
    for m in models:
        if m == "mocap":
            continue
        vals = {}
        for rule, ex, branch, q, tail, field, sign in RULES:
            t = out["thresholds"][f"{m}/{rule}/{tail}"]["threshold"]
            if t is not None:
                vals[field] = round(sign * t, 4)
                if rule == "squat_heel_rise":
                    vals["squat.heelRiseEnabled"] = 1.0
        presets[m] = vals

    # ---- held-out evaluation per rule and threshold variant
    def variants_for(m, rule, ex, branch, q, tail, field, sign):
        v = {}
        dv, _ = load_preset("app_default")
        if field in dv:
            c = dv[field]
            v["current"] = (q, tail, sign * c if sign == 1 else -c)
        t = out["thresholds"].get(f"{m}/{rule}/{tail}", {}).get("threshold")
        if t is not None:
            v["rc1"] = (q, tail, t)
        if rule in LITERATURE:
            v["literature"] = (q, tail, LITERATURE[rule])
        if rule in S7 and m != "mocap":
            sq, op, st_ = S7[rule]
            v["S7"] = (sq, "upper" if op == ">" else "lower", st_)
        return v

    md += ["", "## held-out 정상 렙 오경보 (게이트 = 앱 그대로; 판정된 렙 중 발화 비율 [Wilson 95%], 목표 ≤ 5%)", ""]
    for m in models:
        md += [f"### 모델 {m}", "", "| 규칙 | 변형 | 임계값 | Fit3D s07–s11 | 공개 held-out 정상 | Ex3D P2·P3 | 검출(키 라벨 bad 클립, ≥1렙) | 조건부 검출 | 변별 bad vs good (클립) | 판정 |",
               "|---|---|---|---|---|---|---|---|---|---|"]
        for rule, ex, branch, q, tail, field, sign in RULES + VARIANTS:
            for vname, (vq, vtail, t) in variants_for(m, rule, ex, branch, q, tail, field, sign).items():
                cells, fa_ok, fa_bad_n, fa_n_ok = [], [], 0, 0
                for src, group in HELDOUT:
                    reps = [r for s in pool(m, src, group) if s["exercise"] == ex for r in s["jreps"] if gate_ok(r, branch)]
                    if not any(vq in r["m"] for r in reps):
                        reps = []  # quantity never measured here (e.g. heel rise without feet): not "0 false alarms"
                    k = sum(fires(r, rule, vq, vtail, t, branch) for r in reps)
                    n = len(reps)
                    lo, hi = wilson(k, n)
                    out["fa"][f"{m}/{rule}/{tail}/{vname}/{src}"] = dict(k=k, n=n, rate=k / n if n else None, ci=[lo, hi])
                    if n >= MIN_N:
                        fa_n_ok += 1
                        fa_bad_n += (k / n) > FA_TARGET
                    cells.append(f"{k}/{n} = {k / n:.1%} [{lo:.0%}–{hi:.0%}]" if n else "–")
                # detection on held-out public bad clips with the rule's label
                bad = [s for s in cam if s["model"] == m and s["src"] == "public" and s.get("group") == "heldout" and is_bad(s)
                       and s["exercise"] == ex]
                lab = [s for s in bad if has_label(s, rule)]
                det = [any(fires(r, rule, vq, vtail, t, branch) for r in s["jreps"]) for s in lab]
                judgedc = [s for s in lab if any(gate_ok(r, branch) for r in s["jreps"])]
                cdet = [any(fires(r, rule, vq, vtail, t, branch) for r in s["jreps"]) for s in judgedc]
                good = [s for s in pool(m, "public", "heldout") if s["exercise"] == ex and any(gate_ok(r, branch) for r in s["jreps"])]
                gfire = [any(fires(r, rule, vq, vtail, t, branch) for r in s["jreps"]) for s in good]
                p = fisher_greater(sum(cdet), len(cdet) - sum(cdet), sum(gfire), len(gfire) - sum(gfire)) if cdet and gfire else None
                dl, dh = wilson(sum(det), len(det))
                out["detection"][f"{m}/{rule}/{tail}/{vname}"] = dict(labelled=len(lab), fired=sum(det), judged_clips=len(cdet),
                                                                       fired_judged=sum(cdet), ci=[dl, dh], good_clips=len(gfire),
                                                                       good_fired=sum(gfire), fisher_p=p)
                # verdict (rc1 only; prereg §6)
                verdict = ""
                if vname == "rc1" and m != "mocap":
                    det_ok = len(cdet) >= MIN_BAD and p is not None and p < 0.05
                    if fa_n_ok and fa_bad_n == 0 and det_ok:
                        verdict = "근거 있음(AI 라벨)"
                    elif fa_n_ok and (fa_bad_n == 0 or (fa_bad_n == 1 and det_ok)):
                        verdict = "근거 약함"
                    else:
                        verdict = "데이터 없음 → 끄기 권장"
                    out["verdict"][f"{m}/{rule}/{tail}"] = dict(verdict=verdict, fa_sources=fa_n_ok, fa_over=fa_bad_n, detection_ok=det_ok)
                label = rule + (f" ({'앞' if tail == 'upper' else '뒤'})" if rule == "pushup_hand_position" else "")
                md.append(f"| {label} | {vname} | {t:.3g} | "
                          + " | ".join(cells) + f" | {sum(det)}/{len(det)} [{dl:.0%}–{dh:.0%}]" + f" | {sum(cdet)}/{len(cdet)} | "
                          + (f"{sum(cdet)}/{len(cdet)} vs {sum(gfire)}/{len(gfire)}, p={p:.3f}" if p is not None else "–") + f" | {verdict} |")
        md.append("")
    # rules without a threshold anywhere (rc1 missing) also get a verdict
    for m in models:
        if m == "mocap":
            continue
        for rule, ex, branch, q, tail, field, sign in RULES:
            out["verdict"].setdefault(f"{m}/{rule}/{tail}", dict(verdict="데이터 없음 → 끄기 권장", fa_sources=0, fa_over=0, detection_ok=False))

    def off_list(m):
        bad = lambda r: out["verdict"].get(f"{m}/{r[0]}/{r[4]}", {}).get("verdict", "").startswith("데이터 없음")
        offs = {r[0] for r in RULES if r[0] != "pushup_hand_position" and bad(r)}
        if all(bad(r) for r in RULES if r[0] == "pushup_hand_position"):
            offs.add("pushup_hand_position")
        return sorted(offs)

    # ---- view and subject stability (rc1, gate as the app)
    md += ["## 시점·피험자별 오경보 (rc1; 게이트 = 앱, 괄호 = 게이트 무시(모든 시점에서 3D로 판정했다면); '최대' = 피험자별 오경보율의 최대, n≥10 피험자만)", "",
           "| 모델 | 규칙 | 출처 | 시점별 k/n (게이트 무시 k/n) | 피험자 최대 |", "|---|---|---|---|---|"]
    for m in models:
        for rule, ex, branch, q, tail, field, sign in RULES:
            t = out["thresholds"].get(f"{m}/{rule}/{tail}", {}).get("threshold")
            if t is None:
                continue
            for src, group in HELDOUT:
                ss = [s for s in pool(m, src, group) if s["exercise"] == ex]
                byv, bys, bya = defaultdict(lambda: [0, 0]), defaultdict(lambda: [0, 0]), defaultdict(lambda: [0, 0])
                for s in ss:
                    vk = s.get("view_bin") or s.get("view_label") or "?"
                    for r in s["jreps"]:
                        if q in r["m"]:
                            fa = (r["m"][q] > t) if tail == "upper" else (r["m"][q] < t)
                            bya[vk][0] += fa; bya[vk][1] += 1
                        if gate_ok(r, branch):
                            f = fires(r, rule, q, tail, t, branch)
                            byv[vk][0] += f; byv[vk][1] += 1
                            bys[s.get("subj")][0] += f; bys[s.get("subj")][1] += 1
                if not byv and not bya:
                    continue
                mx = max((k / n for k, n in bys.values() if n >= 10), default=None)
                out["views"][f"{m}/{rule}/{tail}/{src}"] = dict(gated={k: v for k, v in byv.items()}, all={k: v for k, v in bya.items()})
                out["subjects"][f"{m}/{rule}/{tail}/{src}"] = {k: v for k, v in bys.items()}
                md.append(f"| {m} | {rule} | {src} | " + ", ".join(f"{k} {byv[k][0]}/{byv[k][1]} ({bya[k][0]}/{bya[k][1]})"
                                                                  for k in sorted(set(byv) | set(bya)))
                          + f" | {'–' if mx is None else f'{mx:.0%}'} |")

    # ---- praise effect: judged, all-ok reps with nothing fired (current defaults vs rc1), held-out normal sets
    md += ["", "## praise_good 영향 (held-out 정상 세트, 판정된 렙 중 아무 키도 안 울린 렙 비율; 쿨다운 전 상한)", "",
           "| 모델 | 운동 | 출처 | 렙 | 현재 기본값 | rc1 |", "|---|---|---|---|---|---|"]
    for m in models:
        if m not in presets:
            continue
        rc1 = {**load_preset("app_default")[0], **presets[m]}
        rc1_off = set(off_list(m))
        for ex in ("squat", "pushup", "barbell_row"):
            for src, group in HELDOUT:
                ss = [s for s in pool(m, src, group) if s["exercise"] == ex and s["jreps"]]
                if not ss:
                    continue
                n = c0 = c1 = 0
                for s in ss:
                    ms = [r["m"] for r in s["jreps"]]
                    sv = [r["side_view"] for r in s["jreps"]]
                    f0 = judge(ms, ex, load_preset("app_default")[0], side_view=sv)
                    f1 = judge(ms, ex, rc1, rc1_off, side_view=sv)
                    for r, a0, a1 in zip(s["jreps"], f0, f1):
                        if not r.get("all_ok", True):
                            continue
                        n += 1; c0 += not a0; c1 += not a1
                out["praise"][f"{m}/{ex}/{src}"] = dict(n=n, current=c0 / n if n else None, rc1=c1 / n if n else None)
                md.append(f"| {m} | {ex} | {src} | {n} | {c0 / n:.0%} | {c1 / n:.0%} |" if n else f"| {m} | {ex} | {src} | 0 | – | – |")

    # ---- metric error vs mocap (Fit3D held-out, same rep) and camera-up vs gravity
    md += ["", "## 지표 오차 (Fit3D s07–s11, 같은 렙의 모캡 대비 |모델 − 모캡| 중앙값 (p90); 카메라-위)", ""]
    qs = sorted({q for _, _, _, q, _, _, _ in RULES + VARIANTS})
    ref = {(s["set_id"], r["rep"]): r["m"] for s in cam if s["model"] == "mocap" and s.get("group") == "heldout" for r in s["jreps"]}
    md += ["| 지표 | " + " | ".join(m for m in models if m != "mocap") + " |", "|---" * (1 + len([m for m in models if m != "mocap"])) + "|"]
    for q in qs:
        cells = []
        for m in models:
            if m == "mocap":
                continue
            e = [abs(r["m"][q] - ref[(s["set_id"], r["rep"])][q]) for s in cam if s["model"] == m and s["src"] == "fit3d" and s.get("group") == "heldout"
                 for r in s["jreps"] if q in r["m"] and q in ref.get((s["set_id"], r["rep"]), {})]
            out["metric_error"][f"{m}/{q}"] = dict(n=len(e), p50=float(np.median(e)) if e else None, p90=float(np.percentile(e, 90)) if e else None)
            cells.append(f"{np.median(e):.3g} ({np.percentile(e, 90):.3g}) n={len(e)}" if e else "–")
        md.append(f"| {q} | " + " | ".join(cells) + " |")
    md += ["", "## 카메라-위 vs 실제 중력 (Fit3D 전체, 같은 렙: 카메라-위 값 − 중력 값; 중앙값 (p5–p95))", "",
           "| 모델 | 운동 | 지표 | 차이 | 카메라 기울기(°) 중앙값 |", "|---|---|---|---|---|"]
    grav = {(s["model"], s["set_id"], r["rep"]): r["m"] for s in sets if s.get("up") == "grav" for r in s["jreps"]}
    tilt = {s["set_id"]: s.get("cam_tilt") for s in sets if s.get("up") == "grav"}
    camup = [s for s in sets if s["src"] == "fit3d" and s.get("up") == "cam"]
    for m in models:
        for ex, q in (("barbell_row", "torso_mean"), ("barbell_row", "pull_peak_forearm_tilt"), ("squat", "thigh_incline_min"),
                      ("squat", "torso_minus_tibia_at_bottom"), ("squat", "torso_at_bottom"), ("pushup", "upper_arm_incline_max"),
                      ("pushup", "hip_dev_max")):
            d, tl = [], []
            for s in camup:
                if s["model"] != m or s["exercise"] != ex:
                    continue
                for r in s["jreps"]:
                    g = grav.get((m, s["set_id"], r["rep"]), {})
                    if q in r["m"] and q in g:
                        d.append(r["m"][q] - g[q]); tl.append(tilt.get(s["set_id"]) or np.nan)
            if d:
                out["grav"][f"{m}/{ex}/{q}"] = dict(n=len(d), p50=float(np.median(d)), p5=float(np.percentile(d, 5)), p95=float(np.percentile(d, 95)))
                md.append(f"| {m} | {ex} | {q} | {np.median(d):+.3g} ({np.percentile(d, 5):+.3g} – {np.percentile(d, 95):+.3g}) | {np.nanmedian(tl):.1f} |")

    # ---- label counts (held-out public bad clips per rule label, by view)
    md += ["", "## 키 라벨 held-out bad 클립 수 (시점별; AI 2패스 합의, 사람 검수 없음)", "", "| 라벨 | side | diag | front | 합 |", "|---|---|---|---|---|"]
    ref_model = models[1] if len(models) > 1 else models[0]
    by_label = {}
    for r in RULES + VARIANTS:
        by_label.setdefault(LABEL.get(r[0], r[0]), r[0])
    for lab, rule in sorted(by_label.items()):
        ss = [s for s in cam if s["model"] == ref_model and s["src"] == "public" and s.get("group") == "heldout" and is_bad(s)
              and has_label(s, rule)]
        byv = defaultdict(int)
        for s in ss:
            byv[s.get("view_label")] += 1
        out["label_counts"][lab] = dict(byv)
        md.append(f"| {lab} | {byv.get('side', 0)} | {byv.get('diag', 0)} | {byv.get('front', 0)} | {len(ss)} |")

    # ---- parity on real data: Python judge (app defaults) vs the Swift warnings_3d in the pose-replay outputs
    agree = total = 0
    for s in sets:
        if s["src"] == "fit3d" or s.get("impl") == "python" or not s["jreps"] or s.get("rules") not in (None, "app_default"):
            continue
        got = judge([r["m"] for r in s["jreps"]], s["exercise"], load_preset("app_default")[0], side_view=[r["side_view"] for r in s["jreps"]])
        for r, g in zip(s["jreps"], got):
            want = [k for k in (r.get("warnings_3d") or []) if k != "setup_side_view"]
            total += 1; agree += [k for k in g if k != "setup_side_view"] == want
    out["parity_real"] = dict(agree=agree, total=total)
    md += ["", f"## 확인: Python judge(앱 기본값) = Swift warnings_3d — 실제 pose-replay 렙 {agree}/{total} 일치(setup_side_view 제외)"]

    # ---- summary: one row per rule and model (rc1 vs current), for the report
    def fa_cell(key):
        c = out["fa"].get(key)
        return "–" if not c or not c["n"] else f"{c['k']}/{c['n']} ({c['rate']:.0%})"
    summ = ["## 요약 (모델별: rc1 기준값 · held-out 정상 렙 오경보 Fit3D / 공개 / Ex3D · 검출(조건부) · 판정; 괄호 = 현재 앱 기준값의 오경보)", "",
            "| 규칙 | 모델 | rc1 | 오경보 rc1 (현재) | 검출 rc1 (현재) | 변별 p | 판정 |", "|---|---|---|---|---|---|---|"]
    for rule, ex, branch, q, tail, field, sign in RULES + VARIANTS:
        for m in models:
            if m == "mocap":
                continue
            th = out["thresholds"].get(f"{m}/{rule}/{tail}", {}).get("threshold")
            fa = " / ".join(fa_cell(f"{m}/{rule}/{tail}/rc1/{src}") for src, _ in HELDOUT)
            fc = " / ".join(fa_cell(f"{m}/{rule}/{tail}/current/{src}") for src, _ in HELDOUT)
            d1, d0 = out["detection"].get(f"{m}/{rule}/{tail}/rc1"), out["detection"].get(f"{m}/{rule}/{tail}/current")
            dc = lambda d: "–" if not d or not d["judged_clips"] else f"{d['fired_judged']}/{d['judged_clips']}"
            v = out["verdict"].get(f"{m}/{rule}/{tail}", {}).get("verdict", "–") if rule in {r[0] for r in RULES} else "(분석 전용)"
            label = rule + (f" ({'앞' if tail == 'upper' else '뒤'})" if rule == "pushup_hand_position" else "")
            pv = "–" if not d1 or d1.get("fisher_p") is None else f"{d1['fisher_p']:.3f}"
            ths = "없음" if th is None else f"{th:.3g}"
            summ.append(f"| {label} | {m} | {ths} | {fa} ({fc}) | {dc(d1)} ({dc(d0)}) | {pv} | {v} |")
    md = summ + [""] + md

    rd = Path(a.run_dir)
    (rd / "presets").mkdir(exist_ok=True)
    outs = []
    for m, vals in presets.items():
        off = off_list(m)
        p = rd / "presets" / f"xs_{m}_rc1.json"
        json.dump(dict(name=f"xs_{m}_rc1", model=m, pose2d=a.pose2d or "mcoco17", values=vals, off=off,
                       sources=[f"{src}/{group}" for src, group in DERIVE.get(m, [])],
                       note="rules-calib candidate (proposal, not adopted): pre-registered derivation, off = verdict '데이터 없음 → 끄기 권장'"),
                  open(p, "w"), indent=1, ensure_ascii=False)
        outs.append(p)
    (rd / "analysis.json").write_text(json.dumps(out, ensure_ascii=False, indent=1, default=float))
    (rd / "tables.md").write_text("\n".join(md) + "\n")
    write_manifest(a, a.sets.split(","), [rd / "analysis.json", rd / "tables.md"] + outs)
    print("\n".join(md[:60]))
