"""Squat knee valgus relative to the foot direction (docs/results/valgus_foot_dir_prereg.md): per-rep V1 (2D, knee medial
of the big toe), V2 (3D knee vs the vertical foot plane, foot yaw from the Halpe26 heel -> big-toe vector) and the
current knee/ankle gap ratio (3D rules-calib metric, app 2D) on the rules-calib data and pipeline. Measurement only.

  pub    pose-replay JSON (--ref) + Halpe26 CSVs (--csv-dirs), original XS on the Python app path -> <run-dir>/reps_pub.json.gz
  fit3d  Fit3D sequences, experiment-A Halpe26 2D, XS cache (L5) + constraints, mocap toes for V2* -> reps_fit3d.json.gz
  analyze reps_*.json.gz -> <run-dir>/tables.md, analysis.json

Usage (Home, bpt-home): the same inputs as the rules-calib manifests (see docs/results/valgus_foot_dir.md).
"""
import argparse, glob, json, os, sys, time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent), str(HERE)]
import eval_rules_calib as R  # noqa: E402
from pose_feedback.body.form_metrics_3d import UP, frame_metrics, rep_metrics  # noqa: E402

C = 0.3
FOOT_LEN = 0.6  # heel -> big toe / shin (prior, prereg §2)
H26 = {"left": dict(hip=11, knee=13, ankle=15, toe=20, heel=24), "right": dict(hip=12, knee=14, ankle=16, toe=21, heel=25)}
H36 = {"left": dict(hip=4, knee=5, ankle=6), "right": dict(hip=1, knee=2, ankle=3)}
OTHER = {"left": "right", "right": "left"}


def unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else None


def v1_frame(k):
    """max over legs of ((toe - knee)_x * outward) / shin_2D; None when a joint is below confidence."""
    out = []
    for sd, j in H26.items():
        o = H26[OTHER[sd]]
        K, A, T, A2 = k[j["knee"]], k[j["ankle"]], k[j["toe"]], k[o["ankle"]]
        if min(K[2], A[2], T[2], A2[2]) < C or abs(A[0] - A2[0]) < 1:
            continue
        shin = np.hypot(K[0] - A[0], K[1] - A[1])
        if shin > 1e-6:
            out.append((T[0] - K[0]) * np.sign(A[0] - A2[0]) / shin)
    return max(out) if out else None


def gap2d_frame(k):
    """App measure2D kneeAnkleGapRatio (no front-view condition here; the gate is applied per rep)."""
    lk, rk, la, ra = k[13], k[14], k[15], k[16]
    if min(lk[2], rk[2], la[2], ra[2]) < C or abs(la[0] - ra[0]) <= 1:
        return None
    return float((lk[0] - rk[0]) / (la[0] - ra[0]))


def plane_dev(K, A, A2, f, up):
    """((K - A) . n) / |K - A|, n = horizontal normal of the vertical plane through A containing f, toward A2."""
    n = unit(np.cross(up, f))
    if n is None or np.linalg.norm(K - A) < 1e-9:
        return None
    if float(np.dot(A2 - A, n)) < 0:
        n = -n
    return float(np.dot(K - A, n)) / float(np.linalg.norm(K - A))


def px_scale(K2, P):
    """Set median of |hip - ankle|_2D / |hip - ankle|_3D,xy (both legs): px per 3D unit (weak perspective)."""
    r = []
    for k, p in zip(K2, P):
        if p is None:
            continue
        for sd in ("left", "right"):
            a, b = H26[sd], H36[sd]
            if min(k[a["hip"]][2], k[a["ankle"]][2]) < C:
                continue
            d3 = np.hypot(*(p[b["hip"]][:2] - p[b["ankle"]][:2]))
            if np.isfinite(d3) and d3 > 1e-9:
                r.append(np.hypot(*(k[a["hip"]][:2] - k[a["ankle"]][:2])) / d3)
    return float(np.median(r)) if r else None


def v2_frame(k, p, up, s):
    """V2: knee deviation from the foot plane, foot yaw from the 2D heel -> big-toe x extent (prereg §2)."""
    if p is None or s is None or not np.isfinite(p[[1, 2, 3, 4, 5, 6]]).all():
        return None
    up = unit(np.asarray(up, float))
    zh = unit(np.array([0, 0, 1.0]) - up * up[2])
    xh = unit(np.cross(zh, up))
    fwd = np.cross(p[4] - p[1], up)
    out = []
    for sd, j in H26.items():
        b, b2 = H36[sd], H36[OTHER[sd]]
        H, T = k[j["heel"]], k[j["toe"]]
        if min(H[2], T[2]) < C:
            continue
        K, A, A2 = p[b["knee"]], p[b["ankle"]], p[b2["ankle"]]
        L = FOOT_LEN * float(np.linalg.norm(K - A))
        fx = float(np.clip((T[0] - H[0]) / s, -L, L))
        fz = np.sign(float(np.dot(fwd, zh)) or 1.0) * np.sqrt(max(L * L - fx * fx, 0.0))
        v = plane_dev(K, A, A2, fx * xh + fz * zh, up)
        if v is not None:
            out.append(v)
    return max(out) if out else None


def v2_mocap(J25, up):
    """V2* on Fit3D world joints3d_25 (raw order: 1-3 left hip/knee/ankle, 4-6 right, 18 / 20 left / right toe tip)."""
    out = []
    for (kn, an, toe, an2) in ((2, 3, 18, 6), (5, 6, 20, 3)):
        f = J25[toe] - J25[an]
        f = f - up * float(np.dot(f, up))
        v = plane_dev(J25[kn], J25[an], J25[an2], f, up)
        if v is not None:
            out.append(v)
    return max(out) if out else None


def window(vals, hipY, s, e):
    """Rep metric: max (or min) from the lowest-hip frame (2D hipY max) to the rep end, like knee_ankle_gap_ratio_min."""
    ys = [(hipY[t], t) for t in range(s, e + 1) if hipY[t] is not None]
    if not ys:
        return None
    b = max(ys)[1]
    return [vals[t] for t in range(b, e + 1) if vals[t] is not None]


def rep_rec(meta, rep, judged, sv, ff, per_frame, hipY, s, e, gap3d):
    m = {"gap3d": gap3d}
    for name, agg in (("v1", max), ("v2", max), ("v2_mocap", max), ("gap2d", min)):
        if name in per_frame:
            w = window(per_frame[name], hipY, s, e)
            m[name] = agg(w) if w else None
    return dict(meta, rep=rep, judged=judged, side_view=sv, front_frac=ff, m=m)


def view_bucket(meta):
    v = meta.get("view_label")
    if meta["src"] == "fit3d":
        b = meta.get("view_bin", "")
        return "side" if b.startswith("0-") else "front" if b.startswith("75") else "diag"
    return {"diag": "diag", "front": "front", "side": "side"}.get(v, v or "?")


# ---------------------------------------------------------------- public / Exercise3D
def run_pub(a):
    import torch
    from finetune_motionagformer_fit3d import load as load_ckpt
    from pose_feedback.body.live_motionagformer import LiveMotionAGFormer
    from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints
    torch.set_num_threads(a.threads)
    L = R.read_labels(a.labels)
    ex3d_views = {f"{seq}_{cam}": v.get("angle_deg") for seq, g in json.load(open(a.ex3d_gt)).items()
                  for cam, v in g.get("views", {}).items()}
    csv_dirs = dict(kv.split("=", 1) for kv in a.csv_dirs.split(","))
    model = load_ckpt(a.mag_repo, a.ckpt, "cpu")[0].eval()

    def run_live(K, W, H):  # == eval_rules_calib.run_pub_py.run_live (squat: reflect_flipped_knee)
        rec = []
        live = LiveMotionAGFormer(lambda w: rec.append(w.copy()) or np.zeros((27, 17, 3), np.float32), lookahead=5,
                                  constraints=Pose3DConstraints(reflect_flipped_knee=True))
        for t, k in enumerate(K):
            live.push(t, k, W, H)
        live.flush()
        outs = []
        with torch.no_grad():
            for i in range(0, len(rec), 128):
                outs.append(model(torch.from_numpy(np.stack(rec[i:i + 128]))).numpy())
        it = iter(np.concatenate(outs) if outs else [])
        live = LiveMotionAGFormer(lambda w: next(it), lookahead=5, constraints=Pose3DConstraints(reflect_flipped_knee=True))
        fr = []
        for t, k in enumerate(K):
            fr += live.push(t, k, W, H)
        return fr + live.flush()

    refs = sorted(glob.glob(f"{a.ref}/*/3d/*_squat_halpe26.json") + glob.glob(f"{a.ref}/*/2d/*_squat_halpe26.json"))
    out, inputs = [], [a.ckpt, a.ex3d_gt] + R.label_inputs(a)
    for js in refs:
        ds = js.split("/")[-3]
        if ds not in csv_dirs:
            continue
        j = json.load(open(js))
        stem = os.path.basename(js)[: -len("_squat_halpe26.json")]
        csv = f"{csv_dirs[ds]}/{stem}_squat_halpe26.csv"
        inputs += [js, csv]
        K26 = R.read_csv_all(csv)
        K = K26[:, :17]
        W, H = j.get("image_size", [720, 1280])
        fr = run_live(K, W, H)
        state = {f["frame"]: f["state"] for f in fr}
        pose = {}
        for f in fr:
            if f["state"] in ("ok", "partial_3d"):
                p = np.array(f["pose3d"], float)
                inv = (f["constraints"] or {}).get("invalid_joints", [])
                if inv:
                    p[inv] = np.nan
                pose[f["frame"]] = p
        sides = R.near_sides(K)
        td = R.two_d_px(K26, sides)
        ratio = R.shoulder_ratio(K)
        P = [pose.get(t) for t in range(len(K26))]
        s = px_scale(K26, P)
        pf = dict(v1=[v1_frame(k) for k in K26], gap2d=[gap2d_frame(k) for k in K26],
                  v2=[v2_frame(k, p, UP, s) for k, p in zip(K26, P)])
        hipY = [x["hipY"] for x in td]
        meta = dict(set_id=f"{ds}/{stem}", clip=stem, dataset=ds, exercise="squat")
        if stem in L:
            lb = L[stem]
            meta.update(src="public", subj=lb["person"], group="tuning" if lb["split"] == "tuning" else "heldout",
                        view_label=lb["view"], label=lb["clip_label"], ai_form=lb["ai_form"], form_status=lb["form_status"],
                        ai_keys=lb["ai_keys"])
        elif stem.startswith("squat_"):
            seq = "_".join(stem.split("_")[:2])
            ang = ex3d_views.get(stem)
            meta.update(src="ex3d", subj=seq, group="heldout" if seq in R.EX3D_HELD else "tuning", label="good",
                        view=ang, view_label=None if ang is None else ("side" if ang <= 40 else "diag" if ang <= 75 else "front"))
        else:
            continue  # MM-Fit has no squat
        meta["bucket"] = view_bucket(meta)
        hist_empty = True
        for r in j["reps"]:
            s0, e0 = r["start_frame"], r["end_frame"]
            f3 = [t for t in range(s0, e0 + 1) if t in pose]
            judged = len(f3) >= R.MIN_JUDGED * (e0 - s0 + 1)
            frames = []
            for t in f3:
                f = frame_metrics(pose[t], sides[t], UP, td[t])
                f["frame"] = t
                frames.append(f)
            m3 = rep_metrics(frames, "squat", is_first_rep=hist_empty) if frames else {}
            fv = [bool(ratio[t] >= R.FRONT_RATIO) for t in f3 if np.isfinite(ratio[t])]
            ff = float(np.mean(fv)) if frames and fv else 0.0
            out.append(rep_rec(meta, r["rep_index"], judged, ff < R.FRONT_FRACTION, ff, pf, hipY, s0, e0,
                               m3.get("knee_ankle_gap_ratio_min")))
            hist_empty = hist_empty and not judged
        print(len(out), "reps", stem, time.strftime("%H:%M:%S"), flush=True)
    p = Path(a.run_dir) / "reps_pub.json.gz"
    R.dump(p, out)
    R.write_manifest(a, inputs, [p], dict(note="valgus foot-direction measurement (original XS, Halpe26)"))


# ---------------------------------------------------------------- Fit3D (Home only)
def run_fit3d(a):
    from eval_lift_app_fit3d import apply_constraints, load_seqs, seq_key
    from eval_lift_app_t2t3 import two_d
    from finetune_motionagformer_fit3d import mag_input
    a.exercises = ["squat"]
    seqs = load_seqs(a)
    out, inputs = [], []
    for d in seqs:
        z = np.load(f"{a.pose2d_dir}/{d['subj']}_{d['cam']}_{d['ex']}.npz")
        idx = np.searchsorted(z["pick"], d["pick"])
        assert (z["pick"][np.clip(idx, 0, len(z["pick"]) - 1)] == d["pick"]).all(), seq_key(d)
        K26 = z["halpe"][idx].astype(float)
        d["K"] = K26[:, :17]
        d["ratio"] = R.shoulder_ratio(d["K"])
        td, _ = two_d(a, d)
        cache = Path(a.cache) / "orig_halpeA" / f"{seq_key(d)}.npz"
        inputs.append(str(cache))
        Q, rp = apply_constraints(np.load(cache)["L5"].astype(float), dict(reflect_flipped_knee=True))
        inv = [r.get("invalid_joints", []) for r in rp]
        state = np.array([0 if not j else 2 if len(j) == 17 else 1 for j in inv])
        P = (Q - Q[:, :1]) * (d["mm"][:, None, None] / 1000)
        for i, j in enumerate(inv):
            if j:
                P[i, j] = np.nan
        up = d["up_c"]
        jf = f"{a.root}/train/{d['subj']}/joints3d_25/squat.json"
        J25 = np.array(json.load(open(jf))["joints3d_25"], float)[d["pick"]]
        up_w = R_up_world(d)
        side = {"L": "left", "R": "right"}[d["side"]]
        s = px_scale(K26, list(P))
        pf = dict(v1=[v1_frame(k) for k in K26], gap2d=[gap2d_frame(k) for k in K26],
                  v2=[v2_frame(k, p, up, s) for k, p in zip(K26, P)], v2_mocap=[v2_mocap(j, up_w) for j in J25])
        hipY = [x["hipY"] for x in td]
        frames = []
        for t, p in enumerate(P):
            f = frame_metrics(p, side, up, td[t])
            f["frame"] = t
            frames.append(f)
        meta = dict(src="fit3d", set_id=f"fit3d/{seq_key(d)}", subj=d["subj"], cam=d["cam"], exercise="squat", group=d["group"],
                    label="normal", view=round(float(d["view"]), 1), view_bin=d["bin"])
        meta["bucket"] = view_bucket(meta)
        for r, (s0, e0) in enumerate(d["seg"]):
            m3 = rep_metrics(frames[s0:e0 + 1], "squat", is_first_rep=r == 0)
            sv, ff = R.rep_gate("squat", d["ratio"], [None] * len(d["ratio"]), s0, e0)
            out.append(rep_rec(meta, r + 1, bool((state[s0:e0 + 1] <= 1).mean() >= R.MIN_JUDGED), sv, ff, pf, hipY, s0, e0,
                               m3.get("knee_ankle_gap_ratio_min")))
        inputs.append(jf)
        print(seq_key(d), len(out), flush=True)
    p = Path(a.run_dir) / "reps_fit3d.json.gz"
    R.dump(p, out)
    R.write_manifest(a, inputs, [p], dict(note="Fit3D (Home only), original XS cache"))


def R_up_world(d):
    up_w = -d["R"][1] / np.linalg.norm(d["R"][1])
    return np.array([0, 0, 1.0]) if abs(up_w[2]) > 0.8 else up_w  # == eval_lift_app_fit3d.load_seqs


# ---------------------------------------------------------------- analysis
def is_normal(r):
    if r["src"] in ("fit3d", "ex3d"):
        return True
    return r.get("label") == "good" and r.get("ai_form") == "normal" and r.get("form_status") == "ok"


METRICS = [  # name, quantity, tail, fixed thresholds (name -> T)
    ("V2 발 평면(3D+2D 발)", "v2", "upper", {"고정 0.10": 0.10}),
    ("V1 엄지보다 안쪽(2D)", "v1", "upper", {"고정 0": 0.0}),
    ("간격비 3D(rules-calib)", "gap3d", "lower", {"현재 1.0": 1.0, "rc1 0.224": 0.224}),
    ("간격비 2D(앱)", "gap2d", "lower", {"현재 1.0": 1.0}),
]


def fires(v, tail, t):
    return v > t if tail == "upper" else v < t


def pct(v):
    return "–" if not v else "/".join(f"{np.percentile(v, q):.2f}" for q in (1, 5, 50, 95, 99))


def run_analyze(a):
    reps = []
    for p in a.reps.split(","):
        reps += R.load(p)
    reps = [r for r in reps if r["judged"]]
    from rules_calib_analysis import wilson
    out, md = dict(thresholds={}, fa={}, dist={}, mocap={}, detection={}, parity={}), []
    # derived thresholds (rules-calib rule: per tuning source p99 / p1, loosest; n < 20 sources skipped; gate = all views,
    # since the foot metrics are meant to work beyond the front gate -- the app-gate variant is in the tables)
    md += ["## 도출 임계값 (조정 정상 렙, 출처마다 p99/p1, 가장 느슨한 값, n<20 제외; 게이트 = 앱 정면 렙 / 전체)", "",
           "| 지표 | 게이트 | 출처별 | 도출 |", "|---|---|---|---|"]
    for name, q, tail, fixed in METRICS:
        for gate in ("front", "all"):
            qs, parts = [], []
            for src in ("fit3d", "public", "ex3d"):
                v = [r["m"][q] for r in reps if r["src"] == src and r["group"] == "tuning" and is_normal(r)
                     and r["m"].get(q) is not None and (gate == "all" or r["side_view"] is False)]
                if len(v) >= 20:
                    qs.append(float(np.percentile(v, 99 if tail == "upper" else 1)))
                    parts.append(f"{src} {len(v)} → {qs[-1]:.3g}")
                else:
                    parts.append(f"{src} {len(v)} (n<20)")
            t = (max(qs) if tail == "upper" else min(qs)) if qs else None
            out["thresholds"][f"{q}/{gate}"] = t
            md.append(f"| {name} | {gate} | {'; '.join(parts)} | {'없음' if t is None else f'{t:.3g}'} |")
    # held-out normal false alarms per source x bucket x gate
    md += ["", "## held-out 정상 렙 오경보 (k/n = 비율 [Wilson 95%]; 앱 게이트 = 정면으로 분류된 렙만, 전체 = 게이트 무시)", ""]
    cells_keys = [(src, b) for src in ("fit3d", "public", "ex3d") for b in ("front", "diag", "side")]
    held = [r for r in reps if r["group"] == "heldout" and is_normal(r)]
    present = [(s, b) for s, b in cells_keys if any(r["src"] == s and r["bucket"] == b for r in held)]
    md += ["| 지표 | 임계값 | 게이트 | " + " | ".join(f"{s} {b}" for s, b in present) + " |", "|---" * (3 + len(present)) + "|"]
    for name, q, tail, fixed in METRICS:
        ths = dict(fixed)
        for gate in ("front", "all"):
            if out["thresholds"].get(f"{q}/{gate}") is not None:
                ths[f"도출({gate}) {out['thresholds'][f'{q}/{gate}']:.3g}"] = out["thresholds"][f"{q}/{gate}"]
        for tname, t in ths.items():
            for gate in ("front", "all"):
                row = []
                for s, b in present:
                    v = [r["m"][q] for r in held if r["src"] == s and r["bucket"] == b and r["m"].get(q) is not None
                         and (gate == "all" or r["side_view"] is False)]
                    k = sum(fires(x, tail, t) for x in v)
                    lo, hi = wilson(k, len(v))
                    out["fa"][f"{q}/{tname}/{gate}/{s}/{b}"] = dict(k=k, n=len(v))
                    row.append(f"{k}/{len(v)} = {k / len(v):.0%} [{lo:.0%}–{hi:.0%}]" if v else "–")
                md.append(f"| {name} | {tname} | {'앱' if gate == 'front' else '전체'} | " + " | ".join(row) + " |")
    # distributions
    md += ["", "## held-out 정상 렙 분포 (p1/p5/p50/p95/p99, 게이트 무시; 괄호 = 앱 게이트 정면 렙 수)", "",
           "| 지표 | " + " | ".join(f"{s} {b}" for s, b in present) + " |", "|---" * (1 + len(present)) + "|"]
    for name, q, tail, fixed in METRICS + [("V2* 모캡 발(Fit3D)", "v2_mocap", "upper", {})]:
        row = []
        for s, b in present:
            sel = [r for r in held if r["src"] == s and r["bucket"] == b and r["m"].get(q) is not None]
            v = [r["m"][q] for r in sel]
            out["dist"][f"{q}/{s}/{b}"] = pct(v)
            row.append(f"{pct(v)} (n={len(v)}, 정면 {sum(r['side_view'] is False for r in sel)})" if v else "–")
        md.append(f"| {name} | " + " | ".join(row) + " |")
    # mocap reference (Fit3D, all subjects)
    fr = [r for r in reps if r["src"] == "fit3d" and r["m"].get("v2") is not None and r["m"].get("v2_mocap") is not None]
    if fr:
        e = np.abs([r["m"]["v2"] - r["m"]["v2_mocap"] for r in fr])
        mc = [r["m"]["v2_mocap"] for r in fr]
        out["mocap"] = dict(n=len(fr), err_p50=float(np.median(e)), err_p90=float(np.percentile(e, 90)), v2_mocap=pct(mc),
                            corr=float(np.corrcoef([r["m"]["v2"] for r in fr], mc)[0, 1]))
        md += ["", f"## 모캡 참값 (Fit3D s03–s11 정상 렙 n = {len(fr)})", "",
               f"- V2*(모캡 발끝) 분포 p1/p5/p50/p95/p99 = {pct(mc)}.",
               f"- |V2(XS + 2D 발) − V2*| 중앙값 {out['mocap']['err_p50']:.3f}, p90 {out['mocap']['err_p90']:.3f}; 상관 r = {out['mocap']['corr']:.2f}."]
    # detection on held-out public bad clips with the AI consensus label
    bad = {}
    for r in reps:
        if r["src"] == "public" and r["group"] == "heldout" and r.get("label") == "bad" and r.get("form_status") != "excluded_duplicate" \
                and r.get("form_status") == "ok" and "squat_knee_valgus" in (r.get("ai_keys") or []):
            bad.setdefault(r["set_id"], []).append(r)
    md += ["", f"## 검출 (공개 held-out bad, AI 합의 squat_knee_valgus 라벨 클립 {len(bad)}개; 발화 클립 / 판정 렙이 있는 클립)", ""]
    for name, q, tail, fixed in METRICS:
        for tname, t in list(fixed.items()) + [(f"도출(all)", out["thresholds"].get(f"{q}/all"))]:
            if t is None:
                continue
            for gate in ("front", "all"):
                cl = [[x for x in rs if x["m"].get(q) is not None and (gate == "all" or x["side_view"] is False)] for rs in bad.values()]
                cl = [c for c in cl if c]
                k = sum(any(fires(x["m"][q], tail, t) for x in c) for c in cl)
                out["detection"][f"{q}/{tname}/{gate}"] = dict(k=k, n=len(cl))
                md.append(f"- {name} {tname} ({'앱 게이트' if gate == 'front' else '전체'}): {k}/{len(cl)}")
    # parity: gap3d here vs the rules-calib sets (same set_id / rep, model orig)
    if a.sets:
        ref = {}
        for p in a.sets.split(","):
            for s in R.load(p):
                if s["model"] == "orig" and s["exercise"] == "squat" and s.get("up") == ("grav" if s["src"] == "fit3d" else "cam"):
                    for r in s["reps"]:
                        ref[(s["set_id"], r["rep"])] = (r["m"].get("knee_ankle_gap_ratio_min"), r["side_view"])
        d = [(abs(r["m"]["gap3d"] - ref[k][0]), r["side_view"] == ref[k][1]) for r in reps
             if (k := (r["set_id"], r["rep"])) in ref and ref[k][0] is not None and r["m"].get("gap3d") is not None]
        if d:
            out["parity"] = dict(n=len(d), max_abs=float(max(x for x, _ in d)), p50=float(np.median([x for x, _ in d])),
                                 gate_same=int(sum(g for _, g in d)))
            md += ["", f"## 패리티 (rules-calib 세트와 같은 렙의 3D 간격비): n = {len(d)}, |차| 중앙값 {out['parity']['p50']:.2g}, "
                       f"최대 {out['parity']['max_abs']:.2g}, 게이트 같음 {out['parity']['gate_same']}/{len(d)}"]
    Path(a.run_dir, "tables.md").write_text("\n".join(md) + "\n")
    json.dump(out, open(Path(a.run_dir) / "analysis.json", "w"), indent=1, ensure_ascii=False)
    R.write_manifest(a, a.reps.split(",") + (a.sets.split(",") if a.sets else []),
                     [Path(a.run_dir) / "tables.md", Path(a.run_dir) / "analysis.json"])
    print("\n".join(md))


def selfcheck():
    up = np.array([0, -1.0, 0])
    A, A2 = np.zeros(3), np.array([-0.3, 0, 0])  # other ankle on -x: medial = -x
    f = np.array([0, 0, -1.0])  # foot points at the camera
    assert abs(plane_dev(np.array([-0.04, -0.4, -0.1]), A, A2, f, up) - 0.04 / np.linalg.norm([0.04, 0.4, 0.1])) < 1e-9
    assert plane_dev(np.array([0.05, -0.4, 0]), A, A2, f, up) < 0  # knee outside the foot plane
    k = np.zeros((26, 3)); k[:, 2] = 1
    k[13], k[15], k[20], k[16] = (100, 300, 1), (100, 400, 1), (110, 410, 1), (0, 400, 1)  # left: other ankle at x=0
    k[14], k[16], k[21] = (0, 300, 1), (0, 400, 1), (-10, 410, 1)
    assert abs(v1_frame(k) - 0.1) < 1e-9  # knees over the ankles, big toes 10 px out: knee 0.1 shin medial of the toe


if __name__ == "__main__":
    selfcheck()
    p = argparse.ArgumentParser()
    p.add_argument("cmd", choices=["pub", "fit3d", "analyze", "selfcheck"])
    p.add_argument("--run-dir", default=".")
    p.add_argument("--ref", default=""); p.add_argument("--csv-dirs", default="")
    p.add_argument("--labels", default=str(HERE.parent / "data/eval_sources"))
    p.add_argument("--ex3d-gt", default=None)
    p.add_argument("--mag-repo", default=os.path.expanduser("~/models/MotionAGFormer"))
    p.add_argument("--ckpt", default=os.path.expanduser("~/models/MotionAGFormer/checkpoint/motionagformer-xs-h36m.pth.tr"))
    p.add_argument("--threads", type=int, default=4)
    p.add_argument("--root"); p.add_argument("--replay"); p.add_argument("--cache"); p.add_argument("--pose2d-dir")
    p.add_argument("--subjects", type=lambda s: s.split(","), default=["s03", "s04", "s05", "s07", "s08", "s09", "s10", "s11"])
    p.add_argument("--reps", default=""); p.add_argument("--sets", default="")
    a = p.parse_args()
    if a.cmd != "selfcheck":
        os.makedirs(a.run_dir, exist_ok=True)
        {"pub": run_pub, "fit3d": run_fit3d, "analyze": run_analyze}[a.cmd](a)
