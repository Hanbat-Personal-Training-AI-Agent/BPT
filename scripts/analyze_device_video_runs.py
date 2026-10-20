"""Summaries of Exercise3D-as-camera runs of the real Runner app (logs from scripts/device_video_runs.py).

  conda run -n bpt-eval python -I scripts/analyze_device_video_runs.py <run_dir> [<run_dir> ...] --gt GT.json --out OUT.json

Per clip (run_<tag>_<clip>.jsonl), the six items the user asked for, kept separate:
 1 E2E: frame arrival (pace clock) -> Flutter handler completion (method-channel reply) for every onPoseUpdate /
   onFeedback; arrival -> native judgement for every frame; processed / judged FPS, drops. The final widget paint
   (<= 1 vsync) is NOT included.
 2 XS: inferences per second, share of frame states (ok / warming_up / tracking_lost / bad_3d / partial_3d).
 3 posture: (a) judged + logged natively per rep (delivered keys, warnings_2d, warnings_3d, form_source, 3D metrics),
   (b) onFeedback actually sent to Flutter, (c) what Flutter asked the Kori voice to speak, split into lines that
   follow a native onFeedback (real) and the main screen's demo lines (praise_fixed / demo warning, no native event).
 4 tracking lost / bad 3D / partial invalidation frequency.
 6 sets: Flutter startSet / endSet as received natively, the 3D tail flushed at endSet (and whether those frames were
   judged), set-scope keys sent, onSetEnd; rep-scope keys sent after the set ended (Flutter drops them).
 Reps vs Exercise3D gt.json truth (pseudo-GT labels) for context only.
"""
import argparse
import json
import re
import statistics
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEMO_KEYS = {"pushup": "pushup_hip_sag", "squat": "squat_knee_valgus", "barbell-row": "row_torso_swing"}


def kori_lines():
    """key -> (regex for the ko line, regex for the en line) from lib/features/workout/data/kori_feedback_lines.dart."""
    text = (ROOT / "lib/features/workout/data/kori_feedback_lines.dart").read_text()
    out = {}
    for m in re.finditer(r"key:\s*'([^']+)'.*?ko:\s*'((?:[^'\\]|\\.)*)'.*?en:\s*(['\"])((?:(?!\3).)*)\3", text, re.S):
        key, ko, en = m.group(1), m.group(2), m.group(4)

        def rx(s):
            return re.compile("^" + re.sub(r"\\\{[a-z]+\\\}", r".+?", re.escape(s.replace("\\'", "'"))) + "$")
        out[key] = (rx(ko), rx(en))
    return out


def classify_text(text, lines):
    keys = [k for k, (ko, en) in lines.items() if ko.match(text) or en.match(text)]
    return keys[0] if keys else None


def pct(values, q):
    if not values:
        return None
    s = sorted(values)
    return round(s[min(len(s) - 1, int(q * len(s)))], 1)


def stats(values):
    return {"n": len(values), "p50": pct(values, 0.5), "p95": pct(values, 0.95),
            "max": round(max(values), 1) if values else None}


def analyze(path, gt, lines):
    rows = [json.loads(line) for line in open(path) if line.strip()]
    by = lambda t: [r for r in rows if r["type"] == t]  # noqa: E731
    start = by("start")[0] if by("start") else {}
    cam = by("camera_started")[0] if by("camera_started") else {}
    clip = by("clip_start")[0]["clip"] if by("clip_start") else "?"
    exercise = cam.get("exercise", "?")
    flutter_ex = start.get("env", {}).get("BPT_AUTOSTART_WORKOUT", "?")
    clip_end = by("clip_end")
    judged = by("judged")
    ticks = by("tick")
    states = Counter(r["state"] for r in judged)
    n = max(sum(states.values()), 1)
    # active span: first to last judged frame arrival
    span = (judged[-1]["arrival"] - judged[0]["arrival"]) if len(judged) > 1 else 0
    seconds = clip_end[0]["seconds"] if clip_end else span
    arrived = sum(t.get("arrived", 0) for t in ticks)
    dropped = sum(t.get("dropped", 0) for t in ticks)
    processed = sum(t.get("processed", 0) for t in ticks)
    infer = sum(t.get("xs_inferences", 0) for t in ticks)
    updates, feedbacks = by("update_reply"), by("feedback_reply")
    sent = by("feedback_sent")
    reps = by("rep")
    speaks = by("speak")
    rep_sent = [r for r in sent if r.get("scope", "rep") != "set"]
    set_sent = [r for r in sent if r.get("scope") == "set"]
    end_sets = by("end_set_received")
    flushes = by("end_set_flush")
    end_t = min((r["t"] for r in end_sets if not r.get("between_sets")), default=None)
    tail = {i for f in flushes for i in f.get("tail_frame_index", [])}
    judged_idx = {r["frame"] for r in judged}
    # (c) speech: classify each line; "real" = its key was sent natively before it was spoken
    sent_keys_seen, spoken = set(), []
    events = sorted([("sent", r["t"], r["key"]) for r in sent] + [("speak", r["t"], r["text"]) for r in speaks],
                    key=lambda e: e[1])
    for kind, t, v in events:
        if kind == "sent":
            sent_keys_seen.add(v)
            continue
        key = classify_text(v, lines)
        if key in sent_keys_seen:
            origin = "native_onFeedback"
        elif key in ("praise_fixed", DEMO_KEYS.get(flutter_ex)):
            origin = "demo (main screen _advanceDemoFeedback, not a judgement)"
        elif key in ("set_summary", "praise_clean_set"):
            origin = "set summary (Flutter)"
        else:
            origin = "other"
        spoken.append({"t": t, "key": key, "origin": origin})
    truth = gt.get(clip.rsplit("_cam", 1)[0], {}).get("truth_reps") if gt else None
    last_rep = max((r["rep"] for r in judged), default=0)
    perf_cpu = [t["cpu_pct"] for t in ticks if t.get("processed", 0) > 0]
    thermal = [t["thermal"] for t in ticks]
    battery = [t.get("battery") for t in ticks if t.get("battery") is not None and t.get("battery") >= 0]
    judge_ms = [r["judge_ms"] for r in judged]
    return {
        "clip": clip, "exercise": exercise, "log": path.name,
        "config": {k: cam.get(k) for k in ("lookahead", "cadence", "async", "hands", "wrists_from_hands", "gravity",
                                           "enabled_feedback_keys", "form3d_required", "reflect_flipped_knee", "rtmpose")},
        "models": start.get("models"),
        "item1_e2e": {
            "seconds": round(seconds, 1), "frames_arrived": arrived + dropped, "processed": processed,
            "dropped": dropped, "judged": len(judged),
            "processed_fps": round(processed / seconds, 2) if seconds else None,
            "judged_fps": round(len(judged) / seconds, 2) if seconds else None,
            "arrival_to_judgement_ms": stats(judge_ms),
            "arrival_to_flutter_reply_ms_onPoseUpdate": stats([r["e2e_ms"] for r in updates]),
            "arrival_to_flutter_reply_ms_onFeedback": stats([r["e2e_ms"] for r in feedbacks if "e2e_ms" in r]),
            "final_paint": "측정 안 함 (위젯 그리기 ≤ 1 vsync 제외)",
            "unjudged_tail_frames": processed - len(judged),
        },
        "item2_xs": {
            "inferences": infer, "inferences_per_s": round(infer / seconds, 2) if seconds else None,
            "states": {k: round(v / n, 4) for k, v in sorted(states.items())},
            "state_counts": dict(states),
        },
        "item3_posture": {
            "a_native_reps": [{"rep": r["rep_index"], "frames": [r["start_frame"], r["end_frame"]],
                               "form_source": r.get("form_source"), "warnings": r["warnings"],
                               "warnings_2d": r.get("warnings_2d"), "warnings_3d": r.get("warnings_3d"),
                               "states_3d": r.get("states_3d"), "metrics_3d": r.get("metrics_3d")} for r in reps],
            "a_native_fired_3d": dict(Counter(k for r in reps for k in (r.get("warnings_3d") or []))),
            "a_native_fired_2d": dict(Counter(k for r in reps for k in (r.get("warnings_2d") or []))),
            "a_form_sources": dict(Counter(r.get("form_source") for r in reps)),
            "b_sent_to_flutter": dict(Counter(r["key"] for r in sent)),
            "b_sent_rep_scope": dict(Counter(r["key"] for r in rep_sent)),
            "b_sent_set_scope": {r["key"]: r.get("n") for r in set_sent},
            "c_not_shown_after_set_end": dict(Counter(r["key"] for r in rep_sent if end_t is not None and r["t"] > end_t)),
            "c_not_shown_no_flutter_line": dict(Counter(r["key"] for r in sent if r["key"] not in lines)),
            "c_spoken_by_flutter": dict(Counter(f'{s["key"]} [{s["origin"]}]' for s in spoken)),
            "c_onFeedback_replies": dict(Counter(str(r.get("reply")) for r in feedbacks)),
        },
        "item4_quality": {
            "tracking_lost_frames": states.get("tracking_lost", 0), "bad_3d_frames": states.get("bad_3d", 0),
            "partial_3d_frames": states.get("partial_3d", 0), "warming_up_frames": states.get("warming_up", 0),
            "knee_flip_frames": sum(1 for r in judged if r.get("knee_flip")),
            "knees_reflected_frames": sum(1 for r in judged if r.get("knees_reflected")),
            "angle_limit_frames": sum(1 for r in judged if r.get("angle_corr")),
            "wrist_replaced_frames": [sum(1 for r in judged if r.get("wrists", [0, 0])[i]) for i in (0, 1)],
        },
        "item6_sets": {
            "start_set": [r["set"] for r in by("start_set")],
            "end_set_received": [{"set": r["set"], "t": r["t"], "duplicate": r["between_sets"]} for r in end_sets],
            "rep_at_end_set": max((r["rep"] for r in judged if end_t is not None and r["t"] <= end_t), default=None),
            "flush": [{"set": f["set"], "tail_frames": f["tail_frames"], "tail_states": dict(Counter(f["tail_states"]))}
                      for f in flushes],
            "tail_frames_judged": f"{len(tail & judged_idx)}/{len(tail)}" if flushes else None,
            "set_scope_sent": [{"key": r["key"], "n": r.get("n")} for r in set_sent],
            "set_scope_replies": [str(r.get("reply")) for r in feedbacks if r.get("scope") == "set"],
            "set_end_sent": by("set_end_sent"),
        },
        "reps": {"app_last_rep": last_rep, "truth_pseudo_gt": truth},
        "device": {"cpu_pct_p50": pct(perf_cpu, 0.5), "thermal_start_end": [thermal[0], thermal[-1]] if thermal else None,
                   "battery_start_end": [battery[0], battery[-1]] if battery else None},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dirs", nargs="+")
    ap.add_argument("--gt")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    gt = json.load(open(a.gt)) if a.gt else {}
    lines = kori_lines()
    out = []
    for d in a.run_dirs:
        for p in sorted(Path(d).glob("run_*.jsonl")):
            try:
                out.append(analyze(p, gt, lines))
            except Exception as e:  # noqa: BLE001
                out.append({"log": p.name, "error": repr(e)})
    Path(a.out).write_text(json.dumps(out, indent=1, ensure_ascii=False))
    for r in out:
        if "error" in r:
            print(r["log"], r["error"])
            continue
        e, x = r["item1_e2e"], r["item2_xs"]
        print(f'{r["clip"]:28s} {r["exercise"]:10s} fps {e["processed_fps"]}/{e["judged_fps"]} drop {e["dropped"]} '
              f'judge p50 {e["arrival_to_judgement_ms"]["p50"]} flutter p50 {e["arrival_to_flutter_reply_ms_onPoseUpdate"]["p50"]} '
              f'xs/s {x["inferences_per_s"]} states {x["states"]} reps {r["reps"]}')


if __name__ == "__main__":
    main()
