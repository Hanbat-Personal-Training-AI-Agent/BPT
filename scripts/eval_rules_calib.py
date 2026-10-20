"""rules-calib (docs/results/rules_calib_prereg.md): per-rep posture metrics of normal / wrong reps per 3D model, threshold
derivation and held-out evaluation of the app's form rules.

  fit3d   (Home, Fit3D never leaves it) mocap + XS checkpoints on the app 2D CSVs -> per-set rep metrics, cam-up and true
          gravity, the app's view gates mirrored from the app 2D. Writes <run-dir>/sets_fit3d.json.gz.
  pub     pose-replay outputs (this branch, per model) of the public / Exercise3D / MM-Fit app 2D + labels ->
          <run-dir>/sets_pub.json.gz.
  analyze sets_*.json.gz -> thresholds per model (pre-registered rule), presets, held-out tables (Markdown + JSON).

Each command writes <run-dir>/manifest.json (argv, code commit, sha256 of inputs and outputs). Only aggregates go to git.

usage (Home, bpt-home; code synced to ~/bpt-runs/rules-calib/_code/<sha>/):
  eval_rules_calib.py fit3d --root ~/datasets/fit3d --replay ~/bpt-smpl/replay --models orig=CKPT,c1=CKPT --cpu --threads 4 \
      --cache ~/bpt-runs/rules-calib/_cache --run-dir RUN
  eval_rules_calib.py pub --e2e orig=DIR,c1=DIR --labels data/eval_sources --run-dir RUN
  eval_rules_calib.py analyze --sets RUN_F/sets_fit3d.json.gz,RUN_P/sets_pub.json.gz --run-dir RUN
"""
import argparse, glob, gzip, hashlib, json, math, os, re, socket, sys, time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path[:0] = [str(REPO), str(HERE)]
from pose_feedback.body.form_metrics_3d import UP, frame_metrics, rep_metrics  # noqa: E402
from pose_feedback.feedback.form_rules import judge, load_preset  # noqa: E402

EXERCISES = ("squat", "pushup", "barbell_row")
FRONT_RATIO, FRONT_FRACTION = 0.5, 0.5          # FormCommonConfig.frontViewShoulderRatio / frontViewRepFraction
ROW_CUT, ROW_H, GATE_WIN, GATE_MIN = 0.66, 0.03, 150, 30  # BarbellRowFormConfig.sideViewMaxShoulderRatio, hysteresis, window
MIN_JUDGED = 0.5                                  # FormCommonConfig.min3DRepFraction


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def write_manifest(a, inputs, outputs, extra=None):
    code = REPO / "CODE_SHA"
    commit = code.read_text().strip() if code.exists() else os.popen(f"git -C {REPO} rev-parse HEAD").read().strip()
    m = dict(argv=sys.argv, python=sys.executable, host=socket.gethostname(), code_dir=str(REPO), git_commit=commit,
             finished=time.strftime("%Y-%m-%d %H:%M:%S"), extra=extra or {},
             inputs={p: sha256(p) for p in sorted(set(map(str, inputs))) if os.path.isfile(p)},
             code={str(p): sha256(p) for p in sorted(list(REPO.glob("scripts/*.py")) + list(REPO.glob("pose_feedback/**/*.py")))},
             outputs={str(p): sha256(p) for p in outputs if os.path.isfile(p)})
    json.dump(m, open(Path(a.run_dir) / "manifest.json", "w"), indent=1)


def dump(path, obj):
    with gzip.open(path, "wt") as f:
        json.dump(obj, f)


def load(path):
    with gzip.open(path, "rt") as f:
        return json.load(f)


# ---------------------------------------------------------------- shared per-rep quantities (judge() inputs)
def add_set_quantities(ms):
    """judge() quantities that need the set (on the judged reps, in order): baseline = median of the first 3 reps
    (from the 4th rep), set max including this rep. Adds q_* keys in place."""
    for i, m in enumerate(ms):
        h = ms[:i]
        for n in ("elbow_min", "knee_min"):
            b = [x[n] for x in h[:3] if n in x]
            if i >= 3 and n in m and b:
                m[f"q_over_base_{n}"] = m[n] - float(np.median(b))
        for n in ("elbow_max", "knee_max", "hip_angle_max"):
            if n in m:
                m[f"q_below_setmax_{n}"] = max([x[n] for x in h if n in x] + [m[n]]) - m[n]
        b = [x["torso_mean"] for x in h[:3] if "torso_mean" in x]
        if i >= 3 and "torso_mean" in m and b:
            m["q_standing_up"] = math.remainder(float(np.median(b)) - m["torso_mean"], 360)
        b = [x["elbow_behind_max"] for x in h[:3] if "elbow_behind_max" in x]
        if i >= 3 and "elbow_behind_max" in m and b:
            m["q_short_pull"] = float(np.median(b)) - m["elbow_behind_max"]
        if "torso_min" in m and "torso_max" in m:
            m["torso_range"] = m["torso_max"] - m["torso_min"]
        if all(k in m for k in ("hips_first_torso_rise", "hips_first_hip_rise_speed", "hips_first_shoulder_rise_speed")):
            m["q_hips_first"] = m["hips_first_torso_rise"] if m["hips_first_hip_rise_speed"] > m["hips_first_shoulder_rise_speed"] else -1e9
        q = [m[k] for k in ("q_below_setmax_knee_max", "q_below_setmax_hip_angle_max") if k in m]
        if q:
            m["q_squat_no_lockout"] = max(q)


# ---------------------------------------------------------------- Fit3D (Home)
def shoulder_ratio(K, c=0.3):
    """FormWarningTracker.measure2D shoulderRatio per frame (NaN when a shoulder / hip is below confidence c)."""
    ls, rs, lh, rh = K[:, 5], K[:, 6], K[:, 11], K[:, 12]
    ok = (ls[:, 2] >= c) & (rs[:, 2] >= c) & (lh[:, 2] >= c) & (rh[:, 2] >= c)
    torso = np.hypot((ls[:, 0] + rs[:, 0] - lh[:, 0] - rh[:, 0]) / 2, (ls[:, 1] + rs[:, 1] - lh[:, 1] - rh[:, 1]) / 2)
    r = np.abs(ls[:, 0] - rs[:, 0]) / np.where(torso > 1e-8, torso, np.nan)
    r[~ok] = np.nan
    return r


def row_gate(ratio):
    """FormWarningTracker.updateSideView: per-frame session side-view gate (None until GATE_MIN ratios)."""
    out, buf, sv = [], [], None
    for r in ratio:
        if np.isfinite(r):
            buf = (buf + [float(r)])[-GATE_WIN:]
            if len(buf) >= GATE_MIN:
                med = float(np.median(buf))
                sv = med <= ROW_CUT if sv is None else (med <= ROW_CUT + ROW_H if sv else med < ROW_CUT - ROW_H)
        out.append(sv)
    return out


def rep_gate(ex, ratio, gate, s, e):
    """judge()'s side-view value for a rep [s, e]: row = the session gate at the rep's end, else front fraction < 0.5."""
    r = ratio[s:e + 1]
    r = r[np.isfinite(r)]
    ff = float((r >= FRONT_RATIO).mean()) if len(r) else 0.0
    if ex == "barbell_row" and gate[e] is not None:
        return bool(gate[e]), ff
    return ff < FRONT_FRACTION, ff


def set_reps(P, seg, ex, side, up, td, judged):
    frames = []
    for t, p in enumerate(P):
        f = frame_metrics(p, side, up, None if td is None else td[t])
        f["frame"] = t
        frames.append(f)
    ms = []
    for r, (s, e) in enumerate(seg):
        ms.append(rep_metrics(frames[s:e + 1], ex, is_first_rep=r == 0))
    return ms


def run_fit3d(a):
    import torch
    import eval_lift_app_fit3d as E
    from eval_lift_app_fit3d import apply_constraints, load_seqs, predict_rows, seq_key
    from eval_lift_app_t2t3 import two_d
    from finetune_motionagformer_fit3d import load as load_ckpt
    torch.set_num_threads(a.threads)
    E.CACHE["dir"] = None
    seqs = load_seqs(a)
    pose2d = "mcoco17"
    if a.pose2d_dir:  # experiment-A 2D (RTMDet box + mmpose) instead of the app CSV, e.g. Halpe26 (first 17 = COCO17 order)
        from finetune_motionagformer_fit3d import mag_input
        pose2d = f"{a.pose2d_key}A"
        for d in seqs:
            z = np.load(f"{a.pose2d_dir}/{d['subj']}_{d['cam']}_{d['ex']}.npz")
            idx = np.searchsorted(z["pick"], d["pick"])
            assert (z["pick"][np.clip(idx, 0, len(z["pick"]) - 1)] == d["pick"]).all(), seq_key(d)
            d["K"] = z[a.pose2d_key][idx][:, :17].astype(float)
            w, h = (float(v) for v in z["wh"])
            d["x"], _ = mag_input(d["K"], w, h)
    models = [kv.split("=", 1) for kv in a.models.split(",")] if a.models else []
    dev = "cuda" if torch.cuda.is_available() and not a.cpu else "cpu"
    sets = []
    for d in seqs:
        d["ratio"] = shoulder_ratio(d["K"])
        d["gate"] = row_gate(d["ratio"])
        d["td_app"], d["td_gt"] = two_d(a, d)
    for tag, ck in [("mocap", None)] + models:
        model = None if ck is None else load_ckpt(a.mag_repo, ck, dev)[0].eval()
        for d in seqs:
            side = {"L": "left", "R": "right"}[d["side"]]
            meta = dict(src="fit3d", model=tag, pose2d=pose2d, subj=d["subj"], cam=d["cam"], exercise=d["ex"], group=d["group"],
                        view=round(float(d["view"]), 1), view_bin=d["bin"], set_id=f"fit3d/{seq_key(d)}")
            if model is None:
                P, td, state = d["G"], d["td_gt"], np.zeros(len(d["G"]), int)
            else:
                cache = Path(a.cache) / f"{tag}_{pose2d}" / f"{seq_key(d)}.npz" if a.cache else None
                if cache and cache.exists():
                    raw = np.load(cache)["L5"].astype(float)
                else:
                    raw = predict_rows(model, dev, d["x"], [5], None, batch=256 if dev == "cuda" else 16)[5]
                    if cache:
                        cache.parent.mkdir(parents=True, exist_ok=True)
                        np.savez(cache, L5=raw.astype(np.float32))
                Q, rp = apply_constraints(raw, dict(reflect_flipped_knee=d["ex"] == "squat"))
                inv = [r.get("invalid_joints", []) for r in rp]
                state = np.array([0 if not j else 2 if len(j) == 17 else 1 for j in inv])
                P = (Q - Q[:, :1]) * (d["mm"][:, None, None] / 1000)
                for i, j in enumerate(inv):
                    if j:
                        P[i, j] = np.nan
                td = d["td_app"]
            for up_name, up in (("cam", UP), ("grav", d["up_c"])):
                ms = set_reps(P, d["seg"], d["ex"], side, up, td, None)
                reps = []
                for r, ((s, e), m) in enumerate(zip(d["seg"], ms)):
                    sv, ff = rep_gate(d["ex"], d["ratio"], d["gate"], s, e)
                    m["front_view_fraction"] = ff
                    reps.append(dict(rep=r + 1, judged=bool((state[s:e + 1] <= 1).mean() >= MIN_JUDGED), side_view=sv, m=m,
                                     all_ok=bool((state[s:e + 1] == 0).all())))
                sets.append(dict(meta, up=up_name, label="normal", reps=reps,
                                 cam_tilt=round(float(np.degrees(np.arccos(np.clip(-d["up_c"][1] / np.linalg.norm(d["up_c"]), -1, 1)))), 2)))
            print(tag, d["subj"], d["ex"], d["cam"], flush=True)
        del model
    out = Path(a.run_dir) / f"sets_fit3d_{pose2d}.json.gz"
    dump(out, sets)
    write_manifest(a, [d["csv"] for d in seqs] + [ck for _, ck in models], [out],
                   dict(note="Fit3D-derived per-rep metrics (Home only); fine-tuned checkpoints = NON-COMMERCIAL"))


# ---------------------------------------------------------------- public / Exercise3D / MM-Fit pose-replay outputs
EX_FILE = {"squat": "squat", "pushup": "pushup", "barbell_row": "barbell_row"}
OTHER_KEYS = {  # pre-registered regex: AI 'other:' observation -> rules-calib key (rules_calib_prereg.md §3)
    "squat_torso_lean": r"forward lean|folds forward|torso folds|chest (drops|folds|pitched|collapsed)|pitches far forward|hip-hinge with chest|torso pitches|leans forward more",
    "row_elbow_flare": r"elbows? flared|reverse-fly",
    "row_straight_arm": r"kickback|swing straight back|swung back past hips with straighter|straighter arms",
}
EX3D_HELD = {"squat_0002", "barbellrow_0001", "barbellrow_0003"}


def read_labels(labels_dir):
    import csv
    L = {}
    for name, src in (("mendeley_mv7", "mendeley"), ("youtube_cc", "youtube")):
        rows = {r["file"]: r for r in csv.DictReader(open(f"{labels_dir}/{name}_labels.csv"))}
        passes = [{r["file"]: r for r in csv.DictReader(open(f"{labels_dir}/passes/{name}_pass{k}.csv"))} for k in (1, 2)]
        for f, r in rows.items():
            if src == "mendeley":
                clip = r["dataset_label"]  # authors' good / bad
            else:
                it = re.search(r"intent:(\w+)", r["dataset_label"])
                clip = {"normal": "good", "wrong": "bad"}.get(it.group(1) if it else "", "unknown")
            other = {}
            for key, pat in OTHER_KEYS.items():
                hits = [bool(re.search(pat, (p.get(f, {}).get("wrong_keys", "") + " " + p.get(f, {}).get("notes", "")), re.I))
                        for p in passes]
                other[key] = "consensus" if all(hits) else "single" if any(hits) else None
            L[f] = dict(source=src, person=r["person_id"], split=r["split"], view=r["angle_deg"], clip_label=clip,
                        ai_form=r["form"], form_status=r["form_status"],
                        ai_keys=[k for k in (r["wrong_key"] or "").split(";") if k], other=other)
    return L


def run_pub(a):
    L = read_labels(a.labels)
    ex3d_views = {}
    if a.ex3d_gt and os.path.exists(a.ex3d_gt):
        for seq, g in json.load(open(a.ex3d_gt)).items():
            for cam, v in g.get("views", {}).items():
                ex3d_views[f"{seq}_{cam}"] = v.get("angle_deg")
    sets, inputs = [], []
    for kv in a.e2e.split(","):
        tag, root = kv.split("=", 1)
        for js in sorted(glob.glob(f"{root}/*/3d/*_*.json")):
            ds = js.split("/")[-3]
            j = json.load(open(js))
            inputs.append(js)
            ex = j["exercise"] if j["exercise"] in EXERCISES else {"row": "barbell_row"}.get(j["exercise"], j["exercise"])
            stem = os.path.basename(js)[: -len(f"_{EX_FILE.get(ex, ex)}_{j.get('model', 'mcoco17')}.json")]
            meta = dict(src=None, model=tag, pose2d=j.get("model", "mcoco17"), dataset=ds, clip=stem, exercise=ex, set_id=f"{ds}/{stem}")
            if stem in L:
                lb = L[stem]
                meta.update(src="public", subj=lb["person"], group="tuning" if lb["split"] == "tuning" else "heldout",
                            view_label=lb["view"], label=lb["clip_label"], ai_form=lb["ai_form"], form_status=lb["form_status"],
                            ai_keys=lb["ai_keys"], other=lb["other"], public_source=lb["source"])
            elif stem.startswith(("squat_", "pushup_", "barbellrow_")):
                seq = "_".join(stem.split("_")[:2])
                ang = ex3d_views.get(stem)
                meta.update(src="ex3d", subj=seq, group="heldout" if seq in EX3D_HELD else "tuning", label="good",
                            view=ang, view_label=None if ang is None else ("side" if ang <= 40 else "diag" if ang <= 75 else "front"))
            else:
                meta.update(src="mmfit", subj=stem, group="dev", label="good")
            reps = []
            for r in j["reps"]:
                st = r.get("states_3d", {})
                reps.append(dict(rep=r["rep_index"], judged=r.get("warnings_3d") is not None, side_view=r.get("side_view_judged"),
                                 m=r.get("metrics_3d") or {}, warnings_3d=r.get("warnings_3d"), states=st,
                                 all_ok=bool(st) and all(k == "ok" for k, v in st.items() if v)))
            sets.append(dict(meta, up="cam", reps=reps, rules=j.get("rules")))
    out = Path(a.run_dir) / "sets_pub.json.gz"
    dump(out, sets)
    write_manifest(a, inputs, [out])
    print(len(sets), "sets", flush=True)


# ---------------------------------------------------------------- Python app path for pose-replay 2D CSVs (Home)
SIDE7 = {"left": [3, 5, 7, 9, 11, 13, 15], "right": [4, 6, 8, 10, 12, 14, 16]}


def near_sides(K, margin=0.08):
    """FormWarningTracker.updateSide per frame (mean confidence ear..ankle, switch past `margin`)."""
    out, side = [], None
    for k in K:
        l, r = float(k[SIDE7["left"], 2].mean()), float(k[SIDE7["right"], 2].mean())
        if side is None:
            side = "left" if l >= r else "right"
        elif side == "left" and r > l + margin:
            side = "right"
        elif side == "right" and l > r + margin:
            side = "left"
        out.append(side)
    return out


def two_d_px(K, sides, c=0.3):
    """measure2D hipY / shoulderY / torsoLength of the near side (None when below confidence)."""
    out = []
    for k, sd in zip(K, sides):
        sh, hp = (k[5], k[11]) if sd == "left" else (k[6], k[12])
        if sh[2] >= c and hp[2] >= c:
            tl = float(np.hypot(sh[0] - hp[0], sh[1] - hp[1]))
            out.append(dict(hipY=float(hp[1]), shoulderY=float(sh[1]), torsoLength=tl if tl > 1e-8 else None))
        else:
            out.append(dict(hipY=None, shoulderY=None, torsoLength=None))
    return out


def run_pub_py(a):
    """The app's 3D path in Python (LiveMotionAGFormer + Pose3DConstraints, the tested mirrors of the Swift classes) on the
    same 2D CSVs, with PyTorch checkpoints. Rep intervals and the row gate come from the Swift pose-replay JSON of
    --ref (2D state machine: the same for every 3D model). Output sets like `pub`."""
    import torch
    from eval_3d_angles import read_csv
    from finetune_motionagformer_fit3d import load as load_ckpt
    from pose_feedback.body.live_motionagformer import LiveMotionAGFormer
    from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints
    torch.set_num_threads(a.threads)
    L = read_labels(a.labels)
    ex3d_views = {f"{seq}_{cam}": v.get("angle_deg") for seq, g in (json.load(open(a.ex3d_gt)).items() if a.ex3d_gt else [])
                  for cam, v in g.get("views", {}).items()}
    csv_dirs = dict(kv.split("=", 1) for kv in a.csv_dirs.split(","))
    pm = a.pose_model
    refs = sorted(glob.glob(f"{a.ref}/*/3d/*_{pm}.json") + glob.glob(f"{a.ref}/*/2d/*_{pm}.json"))
    sets, inputs = [], []
    for tag, ck in [kv.split("=", 1) for kv in a.models.split(",")]:
        model = load_ckpt(a.mag_repo, ck, "cpu")[0].eval()
        inputs.append(ck)

        def run_live(K, W, H, ex):
            """Two passes: the windows depend on the 2D only (crop tracker, validity), so record them first, run the model
            once in batches, then replay with the outputs in the same call order (constraints see the real 3D)."""
            rec = []
            live = LiveMotionAGFormer(lambda w: rec.append(w.copy()) or np.zeros((27, 17, 3), np.float32), lookahead=5,
                                      constraints=Pose3DConstraints(reflect_flipped_knee=ex == "squat"))
            for t, k in enumerate(K):
                live.push(t, k, W, H)
            live.flush()
            outs = []
            with torch.no_grad():
                for i in range(0, len(rec), 128):
                    outs.append(model(torch.from_numpy(np.stack(rec[i:i + 128]))).numpy())
            it = iter(np.concatenate(outs) if outs else [])
            live = LiveMotionAGFormer(lambda w: next(it), lookahead=5, constraints=Pose3DConstraints(reflect_flipped_knee=ex == "squat"))
            fr = []
            for t, k in enumerate(K):
                fr += live.push(t, k, W, H)
            return fr + live.flush()

        for js in refs:
            ds = js.split("/")[-3]
            if ds not in csv_dirs:
                continue
            j = json.load(open(js))
            ex = {"row": "barbell_row"}.get(j["exercise"], j["exercise"])
            stem = os.path.basename(js)[: -len(f"_{EX_FILE.get(ex, ex)}_{pm}.json")]
            csv = f"{csv_dirs[ds]}/{stem}_{EX_FILE.get(ex, ex)}_{pm}.csv"
            K = read_csv(csv)
            inputs.append(csv)
            W, H = j.get("image_size", [720, 1280])
            fr = run_live(K, W, H, ex)
            state = {f["frame"]: f["state"] for f in fr}
            pose = {}
            for f in fr:
                if f["state"] in ("ok", "partial_3d"):
                    p = np.array(f["pose3d"], float)
                    inv = (f["constraints"] or {}).get("invalid_joints", [])
                    if inv:
                        p[inv] = np.nan
                    pose[f["frame"]] = p
            sides = near_sides(K)
            td = two_d_px(K, sides)
            ratio = shoulder_ratio(K)
            reps, hist_empty = [], True
            for r in j["reps"]:
                s0, e0 = r["start_frame"], r["end_frame"]
                f3 = [t for t in range(s0, e0 + 1) if t in pose]
                judged = len(f3) >= MIN_JUDGED * (e0 - s0 + 1)
                frames = []
                for t in f3:
                    f = frame_metrics(pose[t], sides[t], UP, td[t])
                    f["frame"] = t
                    frames.append(f)
                m = rep_metrics(frames, ex, is_first_rep=hist_empty) if frames else {}
                fv = [bool(ratio[t] >= FRONT_RATIO) for t in f3 if np.isfinite(ratio[t])]
                if frames and fv:
                    m["front_view_fraction"] = float(np.mean(fv))
                sv = r.get("side_view_judged") if ex == "barbell_row" else m.get("front_view_fraction", 0.0) < FRONT_FRACTION
                reps.append(dict(rep=r["rep_index"], judged=judged, side_view=sv, m=m,
                                 all_ok=all(state.get(t) == "ok" for t in range(s0, e0 + 1))))
                hist_empty = hist_empty and not judged
            meta = dict(model=tag, pose2d=pm, dataset=ds, clip=stem, exercise=ex, set_id=f"{ds}/{stem}", impl="python")
            if stem in L:
                lb = L[stem]
                meta.update(src="public", subj=lb["person"], group="tuning" if lb["split"] == "tuning" else "heldout",
                            view_label=lb["view"], label=lb["clip_label"], ai_form=lb["ai_form"], form_status=lb["form_status"],
                            ai_keys=lb["ai_keys"], other=lb["other"], public_source=lb["source"])
            elif stem.startswith(("squat_", "pushup_", "barbellrow_")):
                seq = "_".join(stem.split("_")[:2])
                ang = ex3d_views.get(stem)
                meta.update(src="ex3d", subj=seq, group="heldout" if seq in EX3D_HELD else "tuning", label="good",
                            view=ang, view_label=None if ang is None else ("side" if ang <= 40 else "diag" if ang <= 75 else "front"))
            else:
                meta.update(src="mmfit", subj=stem, group="dev", label="good")
            sets.append(dict(meta, up="cam", reps=reps, rules=None))
        print(tag, "done", len(sets), flush=True)
        del model
    out = Path(a.run_dir) / f"sets_pubpy_{pm}_{'_'.join(kv.split('=')[0] for kv in a.models.split(','))}.json.gz"
    dump(out, sets)
    write_manifest(a, inputs, [out], dict(note="Python app path (LiveMotionAGFormer mirror), PyTorch; fine-tuned = NON-COMMERCIAL"))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("cmd", choices=["fit3d", "pub", "pubpy", "analyze"])
    p.add_argument("--run-dir", required=True)
    p.add_argument("--root"); p.add_argument("--replay")
    p.add_argument("--subjects", type=lambda s: s.split(","), default=["s03", "s04", "s05", "s07", "s08", "s09", "s10", "s11"])
    p.add_argument("--exercises", type=lambda s: s.split(","), default=list(EXERCISES))
    p.add_argument("--mag-repo", default=os.path.expanduser("~/models/MotionAGFormer"))
    p.add_argument("--models", default="", help="fit3d: tag=ckpt,... (fine-tuned = NON-COMMERCIAL)")
    p.add_argument("--cpu", action="store_true"); p.add_argument("--threads", type=int, default=4)
    p.add_argument("--cache", default=None)
    p.add_argument("--e2e", default="", help="pub: tag=dir,... (dir holds <dataset>/3d/*.json)")
    p.add_argument("--labels", default=str(REPO / "data/eval_sources"))
    p.add_argument("--ex3d-gt", default=None, help="pub: outputs/rep_validation/gt.json (Exercise3D camera angles)")
    p.add_argument("--sets", default="")
    p.add_argument("--ref", default="", help="pubpy: Swift pose-replay dir (<dataset>/3d/*.json) for rep intervals / row gate")
    p.add_argument("--csv-dirs", default="", help="pubpy: dataset=dir of the 2D CSVs, ...")
    p.add_argument("--pose-model", default="mcoco17", help="pubpy: 2D CSV / JSON suffix (mcoco17 or halpe26)")
    p.add_argument("--pose2d-dir", default="", help="fit3d: experiment-A 2D npz dir (lift-compare A-pose2d .../pose2d)")
    p.add_argument("--pose2d-key", default="halpe", help="fit3d: npz key (halpe or coco)")
    p.add_argument("--pose2d", default="", help="analyze: 2D family to analyse (mcoco17 or halpe26; Fit3D A sets match the prefix)")
    a = p.parse_args()
    os.makedirs(a.run_dir, exist_ok=True)
    if a.cmd == "fit3d":
        a.checkpoint = None
        run_fit3d(a)
    elif a.cmd == "pub":
        run_pub(a)
    elif a.cmd == "pubpy":
        run_pub_py(a)
    else:
        from rules_calib_analysis import run_analyze
        run_analyze(a)


if __name__ == "__main__":
    main()
