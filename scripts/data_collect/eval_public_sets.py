"""Score pose-replay outputs (app default: RTMPose-m Halpe26 since D-M-03, crop, ready-pose off) against merged hand labels.

usage: python3 -I eval_public_sets.py <replay_dir[:replay_dir...]> <out.md> <labels.csv>...
Env POSE_MODEL: which pose-replay --model outputs to score (default mhalpe26, the app's workout model; older m COCO17 runs are mcoco17).
Rep accuracy (project metric, set-level counts): missed = max(0, truth - counted), extra = max(0, counted - truth),
acc = sum(truth - missed) / sum(truth + extra). Only rows with rep_status ok. Lenient: a count between reps and
reps + partial (rep already under way at the clip start / cut at the end) counts as exact.
Setup keys: setup_full_body and tracking_lost events per set (app ON for all), setup_side_view (app ON for row only).
Form keys (all OFF in the app; pose-replay logs every rule that held): a wrong clip "detects" its key when the key
fired on >= 1 counted rep (or as a set event); per-rep rate = reps with the key / counted reps.
False alarm = share of counted reps of agreed-normal clips on which the key fired.
"""
import csv, json, os, sys
from collections import defaultdict
from pathlib import Path

FILE_EX = {"squat": "squat", "pushup": "pushup", "row": "barbell_row"}
MODEL = os.environ.get("POSE_MODEL", "mhalpe26")
SETUP = ("setup_full_body", "tracking_lost", "setup_side_view")
FORM_KEYS = {
    "squat": ["squat_shallow", "squat_hips_first", "squat_lean_drift", "squat_no_lockout", "squat_depth_fade", "squat_knee_valgus", "squat_heel_rise"],
    "pushup": ["pushup_hip_sag", "pushup_hip_pike", "pushup_shallow", "pushup_no_lockout", "pushup_head_drop", "pushup_head_up", "pushup_hand_position", "pushup_depth_fade"],
    "row": ["row_torso_swing", "row_standing_up", "row_short_pull", "row_head_up", "row_shrug"],
}


def load(replay_dirs, row):
    for d in replay_dirs.split(":"):  # several replay dirs, colon-separated
        p = Path(d) / f"{Path(row['file']).stem}_{FILE_EX[row['exercise']]}_{MODEL}.json"
        if p.exists():
            return json.load(open(p))
    return None


def score(rows, lenient=False):
    t = m = x = exact = 0
    for r in rows:
        truth, c = r["truth"], r["counted"]
        if lenient and truth <= c <= truth + r["partial"]:
            c = truth
        t += truth; m += max(0, truth - c); x += max(0, c - truth); exact += c == truth
    return {"sets": len(rows), "truth": t, "missed": m, "extra": x, "exact": exact,
            "acc": (t - m) / (t + x) if t + x else float("nan")}


def unknown_frac(j):
    """Share of frames the evaluator spent in status 'unknown' (pose too unsure to judge), from transitions."""
    t = [(int(f), st) for f, st in (x.split(":", 1) for x in j["transitions"])] + [(j["frames"], "end")]
    unk = sum(b[0] - a[0] for a, b in zip(t, t[1:]) if a[1] == "unknown")
    return unk / j["frames"] if j["frames"] else 1.0


def fired(j, key):
    per_rep = [key in rep["warnings"] for rep in j["reps"]]
    return per_rep, any(per_rep) or any(e["key"] == key for e in j["events"])


def table_reps(rows, title):
    out = [f"### {title}", "", "| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |",
           "|---|---|---|---|---|---|---|---|---|---|---|"]
    g = defaultdict(list)
    for r in rows:
        for key in [(r["exercise"], r["angle_deg"], r["split"]), (r["exercise"], "전체", r["split"])]:
            g[key].append(r)
    order = {"side": 0, "diag": 1, "front": 2, "back": 3, "전체": 9}
    for (ex, ang, sp), rs in sorted(g.items(), key=lambda kv: (kv[0][0], order.get(kv[0][1], 5), kv[0][2])):
        s, l = score(rs), score(rs, True)
        out.append(f"| {ex} | {ang} | {sp} | {s['sets']} | {s['truth']} | {s['missed']} | {s['extra']} | {s['acc']:.1%} | {s['exact']}/{s['sets']} | {l['acc']:.1%} | {l['exact']}/{l['sets']} |")
    return out


def main(replay_dir, out_md, *label_csvs):
    labels = [r for p in label_csvs for r in csv.DictReader(open(p))]
    rep_rows, form_rows, missing = [], [], []
    for r in labels:
        if r["rep_status"].startswith("excluded") or r["rep_status"] == "missing_pass" and r["form_status"] == "missing_pass":
            continue
        j = load(replay_dir, r)
        if j is None:
            missing.append(r["file"]); continue
        r["j"], r["counted"] = j, j["session"]["rep_count"]
        r["unk"] = unknown_frac(j)
        if r["rep_status"] == "ok":
            r["truth"] = int(r["reps"])
            r["partial"] = max(int(x) for x in r["partial"].split("|") if x.strip().isdigit()) if r["partial"] else 0
            rep_rows.append(r)
        if r["form_status"] == "ok":
            form_rows.append(r)
    L = [f"# 공개 데이터 평가 (pose-replay --model {MODEL}, crop, ready-pose off, 3D 없음)", "",
         f"라벨 행 {len(labels)}, 렙 평가 세트 {len(rep_rows)}, 자세 평가 세트 {len(form_rows)}, replay 없음 {len(missing)}", ""]
    for src in sorted({r["source"] for r in rep_rows}) + ["전체"]:
        rs = [r for r in rep_rows if src in ("전체", r["source"])]
        L += [""] + table_reps(rs, f"렙 정확도 — {src} (모든 자세)")
        L += [""] + table_reps([r for r in rs if r["form"] == "normal"], f"렙 정확도 — {src} (정상 자세만)")
    L += ["", "### 렙 정확도 × 추적 품질 (unknown = 관절 신뢰도가 낮아 상태를 못 정한 프레임 비율)", "",
          "| 운동 | 분할 | unknown 비율 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 |", "|---|---|---|---|---|---|---|---|"]
    g = defaultdict(list)
    for r in rep_rows:
        g[(r["exercise"], r["split"], "< 10%" if r["unk"] < 0.1 else "≥ 10%")].append(r)
    for (ex, sp, b), rs in sorted(g.items()):
        s = score(rs)
        L.append(f"| {ex} | {sp} | {b} | {s['sets']} | {s['truth']} | {s['missed']} | {s['extra']} | {s['acc']:.1%} |")
    # setup keys
    L += ["", "### 셋업 키 (세트당 발생, 괄호 = 센 렙 안에서)", "", "| 운동 | 시점 | 분할 | 세트 | setup_full_body | tracking_lost | setup_side_view | 앱에서 켜진 키 알람 세트 |", "|---|---|---|---|---|---|---|---|"]
    g = defaultdict(list)
    for r in rep_rows + [r for r in form_rows if r not in rep_rows]:
        g[(r["exercise"], r["angle_deg"], r["split"])].append(r)
    for (ex, ang, sp), rs in sorted(g.items()):
        cells, alarm_sets = [], set()
        for k in SETUP:
            n = inrep = 0
            for r in rs:
                spans = [(x["start_frame"], x["end_frame"]) for x in r["j"]["reps"]]
                fr = [e["frame"] for e in r["j"]["events"] if e["key"] == k]
                n += len(fr); inrep += sum(any(a <= f <= b for a, b in spans) for f in fr)
                if fr and (k != "setup_side_view" or ex == "row"):
                    alarm_sets.add(r["file"])
            cells.append(f"{n} ({inrep})")
        L.append(f"| {ex} | {ang} | {sp} | {len(rs)} | {' | '.join(cells)} | {len(alarm_sets)}/{len(rs)} |")
    # form keys
    L += ["", "### 자세 키 (앱에서 꺼짐 — pose-replay 판정 로그)", "",
          "검출 = 그 키 라벨(두 패스 합의)이 붙은 잘못된 세트 중 키가 1렙 이상(또는 세트 이벤트) 나온 비율. 렙 비율 = 그 세트들의 센 렙 중 키가 나온 비율. 오경보 = 합의된 정상 세트의 센 렙 중 키가 나온 비율.", "",
          "| 운동 | 키 | 시점 | 분할 | 잘못 세트 | 검출 | 렙 비율 | 정상 세트 | 정상 렙 | 오경보(렙) | 오경보(세트) |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    for ex, ks in FORM_KEYS.items():
        for k in ks:
            g = defaultdict(lambda: {"w": [], "n": []})
            for r in form_rows:
                if r["exercise"] != ex:
                    continue
                for ang in (r["angle_deg"], "전체"):
                    if r["form"] == "wrong" and k in r["wrong_key"].split(";"):
                        g[(ang, r["split"])]["w"].append(r)
                    elif r["form"] == "normal":
                        g[(ang, r["split"])]["n"].append(r)
            for (ang, sp), d in sorted(g.items()):
                if not d["w"] and not any(fired(r["j"], k)[1] for r in d["n"]):
                    continue
                det = sum(fired(r["j"], k)[1] for r in d["w"])
                wr = [x for r in d["w"] for x in fired(r["j"], k)[0]]
                nr = [x for r in d["n"] for x in fired(r["j"], k)[0]]
                ns = sum(fired(r["j"], k)[1] for r in d["n"])
                f = lambda a, b: f"{a}/{b} ({a / b:.0%})" if b else "-"
                L.append(f"| {ex} | {k} | {ang} | {sp} | {len(d['w'])} | {f(det, len(d['w']))} | {f(sum(wr), len(wr))} | {len(d['n'])} | {len(nr)} | {f(sum(nr), len(nr))} | {f(ns, len(d['n']))} |")
    L += ["", "### 세트별", "", "| 파일 | 분할 | 시점 | 자세 | wrong_key | 정답 | 셈 | unknown | 경고(렙별) |", "|---|---|---|---|---|---|---|---|---|"]
    for r in sorted({id(r): r for r in rep_rows + form_rows}.values(), key=lambda r: r["file"]):
        w = ",".join("+".join(x["warnings"]) or "-" for x in r["j"]["reps"])
        L.append(f"| {r['file']} | {r['split']} | {r['angle_deg']} | {r['form']} | {r['wrong_key']} | {r.get('truth', r['reps'])} | {r['counted']} | {r['unk']:.0%} | {w[:160]} |")
    if missing:
        L += ["", "replay 없음: " + " ".join(missing)]
    Path(out_md).write_text("\n".join(L) + "\n")
    print(out_md)


if __name__ == "__main__":
    s = score([{"truth": 10, "counted": 9, "partial": 0}, {"truth": 10, "counted": 11, "partial": 1}], lenient=True)
    assert s["missed"] == 1 and s["extra"] == 0 and s["exact"] == 1
    assert abs(score([{"truth": 10, "counted": 11, "partial": 1}])["acc"] - 10 / 11) < 1e-9
    assert unknown_frac({"transitions": ["0:top", "5:unknown", "8:top"], "frames": 10}) == 0.3
    main(*sys.argv[1:])
