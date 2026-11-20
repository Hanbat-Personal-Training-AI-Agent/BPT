"""Markdown tables from analyze_device_video_runs.py summaries (one row per clip, plus per-exercise totals).

  conda run -n bpt-eval python -I scripts/device_runs_tables.py <summary.json> <gt.json> [label]
"""
import json
import sys
from collections import Counter, defaultdict


def pct(values, q):
    s = sorted(values)
    return round(s[min(len(s) - 1, int(q * len(s)))], 1) if s else None


def main(path, gt_path, label=""):
    rows = [r for r in json.load(open(path)) if "error" not in r]
    gt = json.load(open(gt_path))
    angle = lambda clip: gt[clip.rsplit("_cam", 1)[0]]["views"]["cam" + clip.rsplit("_cam", 1)[1][0]]["angle_deg"]  # noqa: E731
    print(f"### {label} 1. E2E (frame arrival → judgement / → Flutter handler reply), FPS, drops — per clip")
    print("| clip | 각도 | 처리/판정 FPS | 드롭 | 도착→판정 p50/p95/max ms | 도착→Flutter 응답(onPoseUpdate) p50/p95/max ms | onFeedback 응답 p50/max | 미판정 끝 프레임 | CPU p50 | 발열 시작→끝 |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        e = r["item1_e2e"]
        j, u, f = e["arrival_to_judgement_ms"], e["arrival_to_flutter_reply_ms_onPoseUpdate"], e["arrival_to_flutter_reply_ms_onFeedback"]
        th = r["device"]["thermal_start_end"] or ["?", "?"]
        print(f'| {r["clip"].removesuffix(".mp4")} | {angle(r["clip"]):.0f}° | {e["processed_fps"]} / {e["judged_fps"]} | {e["dropped"]} | '
              f'{j["p50"]} / {j["p95"]} / {j["max"]} | {u["p50"]} / {u["p95"]} / {u["max"]} | {f["p50"]} / {f["max"]} ({f["n"]}) | '
              f'{e["unjudged_tail_frames"]} | {r["device"]["cpu_pct_p50"]} | {th[0]}→{th[1]} |')
    print()
    print(f"### {label} 2·4. XS 실행·3D 상태·품질 — per clip")
    print("| clip | XS 추론/초 | ok | warming_up | tracking_lost | partial_3d | bad_3d | 무릎 뒤집힘 프레임 | 각도 한계 프레임 | 손목 교체 프레임 L/R | 렙 앱/정답(의사) |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        x, q = r["item2_xs"], r["item4_quality"]
        st = x["states"]
        w = q["wrist_replaced_frames"]
        print(f'| {r["clip"].removesuffix(".mp4")} | {x["inferences_per_s"]} | {st.get("ok", 0):.3f} | {st.get("warming_up", 0):.3f} | '
              f'{st.get("tracking_lost", 0):.3f} | {st.get("partial_3d", 0):.3f} | {st.get("bad_3d", 0):.3f} | {q["knee_flip_frames"]} | '
              f'{q["angle_limit_frames"]} | {w[0]}/{w[1]} | {r["reps"]["app_last_rep"]}/{r["reps"]["truth_pseudo_gt"]} |')
    print()
    print(f"### {label} 3. 자세 — (a) 네이티브 판정·로그 / (b) Flutter로 보냄 / (c) Flutter가 말함(실제 vs 데모) — per clip")
    print("| clip | 렙 | 3D 판정 렙 | (a) 3D 경고(렙 수) | (a) 비교용 2D 경고 | (b) Flutter로 보낸 키 | (c) 말한 대사 |")
    print("|---|---|---|---|---|---|---|")
    totals = defaultdict(Counter)
    for r in rows:
        p = r["item3_posture"]
        ex = r["exercise"]
        totals[ex]["clips"] += 1
        totals[ex]["reps"] += len(p["a_native_reps"])
        totals[ex]["reps_3d"] += p["a_form_sources"].get("3d", 0)
        for k, v in p["a_native_fired_3d"].items():
            totals[ex]["a3d:" + k] += v
        for k, v in p["a_native_fired_2d"].items():
            totals[ex]["a2d:" + k] += v
        for k, v in p["b_sent_to_flutter"].items():
            totals[ex]["b:" + k] += v
        for k, v in p["c_spoken_by_flutter"].items():
            totals[ex]["c:" + k] += v
        fmt = lambda d: ", ".join(f"{k} {v}" for k, v in sorted(d.items())) or "–"  # noqa: E731
        print(f'| {r["clip"].removesuffix(".mp4")} | {len(p["a_native_reps"])} | {p["a_form_sources"].get("3d", 0)} | '
              f'{fmt(p["a_native_fired_3d"])} | {fmt(p["a_native_fired_2d"])} | {fmt(p["b_sent_to_flutter"])} | {fmt(p["c_spoken_by_flutter"])} |')
    print()
    if any(r.get("item6_sets", {}).get("end_set_received") for r in rows):
        print(f"### {label} 3(b·c)·6. 세트 경계 — endSet, 3D 꼬리 flush, 세트 범위 키, Flutter가 버린 키 — per clip")
        print("| clip | startSet | endSet(렙 시점) | flush 꼬리 프레임(상태) | 꼬리 판정됨 | (b) 렙 범위 보냄 | (b) 세트 범위 보냄(n) | onSetEnd worstJoint | (c) 세트 끝 뒤라 안 보임 | (c) 대사 없어 안 보임 |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for r in rows:
            s6, p = r["item6_sets"], r["item3_posture"]
            fmt = lambda d: ", ".join(f"{k} {v}" for k, v in sorted(d.items())) or "–"  # noqa: E731
            fl = "; ".join(f'{f["tail_frames"]} ({fmt(f["tail_states"])})' for f in s6["flush"]) or "–"
            ends = ", ".join(f'set {e["set"]}{" (중복)" if e["duplicate"] else ""}' for e in s6["end_set_received"]) or "없음"
            wj = ", ".join(str(e.get("worst_joint")) for e in s6["set_end_sent"]) or "–"
            print(f'| {r["clip"].removesuffix(".mp4")} | {s6["start_set"] or "–"} | {ends} (렙 {s6["rep_at_end_set"]}) | {fl} | '
                  f'{s6["tail_frames_judged"]} | {fmt(p["b_sent_rep_scope"])} | {fmt(p["b_sent_set_scope"])} | {wj} | '
                  f'{fmt(p["c_not_shown_after_set_end"])} | {fmt(p["c_not_shown_no_flutter_line"])} |')
        print()
    print(f"### {label} 운동별 합계")
    for ex, c in totals.items():
        print(f"- **{ex}**: 클립 {c['clips']}, 렙 {c['reps']}, 3D 판정 렙 {c['reps_3d']}")
        for prefix, name in (("a3d:", "(a) 3D 경고"), ("a2d:", "(a) 2D 경고(비교용)"), ("b:", "(b) Flutter로 보냄"), ("c:", "(c) 말함")):
            items = {k[len(prefix):]: v for k, v in c.items() if k.startswith(prefix)}
            print(f"  - {name}: " + (", ".join(f"{k} {v}" for k, v in sorted(items.items())) or "없음"))
    # pooled E2E per exercise
    print()
    print(f"### {label} 운동별 E2E (클립 p50의 범위)")
    by_ex = defaultdict(list)
    for r in rows:
        by_ex[r["exercise"]].append(r)
    for ex, rs in by_ex.items():
        fps = [r["item1_e2e"]["processed_fps"] for r in rs]
        j50 = [r["item1_e2e"]["arrival_to_judgement_ms"]["p50"] for r in rs]
        u95 = [r["item1_e2e"]["arrival_to_flutter_reply_ms_onPoseUpdate"]["p95"] for r in rs]
        drops = sum(r["item1_e2e"]["dropped"] for r in rs)
        frames = sum(r["item1_e2e"]["frames_arrived"] for r in rs)
        print(f"- {ex}: 처리 FPS {min(fps)}–{max(fps)}, 도착→판정 p50 {min(j50)}–{max(j50)} ms, 도착→Flutter p95 {min(u95)}–{max(u95)} ms, "
              f"드롭 {drops}/{frames} ({100 * drops / max(frames, 1):.1f}%)")


if __name__ == "__main__":
    main(*sys.argv[1:])
