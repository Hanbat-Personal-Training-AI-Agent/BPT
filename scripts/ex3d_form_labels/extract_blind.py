"""Split device + 2D-replay rep logs into a blind table (boundaries, keypoints) and a sealed table (warnings, metrics).

Run on Home (bpt-home). Blind output is safe to read before labelling; sealed output is not.
"""
import csv, glob, gzip, hashlib, json, os, sys

DEV = os.path.expanduser("~/bpt-runs/lift-app/20261020-device-halpe-ab-a8b29f1-partial-20261021-103959/full_mhalpe26_r0")
REF = os.path.expanduser("~/bpt-runs/rules-calib/20261020-refs-h26/ex3d_own_v1/2d")
OUT = sys.argv[1]
SEAL_KEYS = {"warnings", "warnings_2d", "warnings_3d", "spoken", "grades", "metrics_2d", "metrics_3d", "metrics"}
SETS = ["barbellrow_0000", "barbellrow_0001", "barbellrow_0002", "barbellrow_0003",
        "pushup_0000", "pushup_0001", "pushup_0002", "pushup_0003", "pushup_0004",
        "squat_0000", "squat_0001", "squat_0002", "squat_0003"]
EXNAME = {"barbellrow": "barbell_row", "pushup": "pushup", "squat": "squat"}
os.makedirs(f"{OUT}/blind", exist_ok=True)
os.makedirs(f"{OUT}/sealed", exist_ok=True)
inputs = {}

def sha(p):
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    inputs[p] = h

for s in SETS:
    ex = s.split("_")[0]
    for cam in (1, 2, 3):
        clip = f"{s}_cam{cam}"
        blind = {"clip": clip, "set": s, "cam": cam}
        sealed = {"clip": clip}
        # --- device run
        p = f"{DEV}/run_cx_full_mhalpe26_r0_{clip}.jsonl"
        if os.path.exists(p):
            sha(p)
            f2s, reps, sreps, sess = {}, [], [], None
            for line in open(p):
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                t = d.get("type")
                if t == "judged":
                    f2s[d["frame"]] = d.get("src", d["frame"])
                elif t == "rep":
                    reps.append({k: v for k, v in d.items() if k not in SEAL_KEYS})
                    sreps.append({k: d.get(k) for k in ["rep_index"] + sorted(SEAL_KEYS) if k in d})
                elif t == "session_end":
                    sess = d
                elif t == "clip_start":
                    blind["device_size"] = d.get("size")
            for r in reps:
                for k in ("start_frame", "end_frame", "judged_frame"):
                    if r.get(k) is not None:
                        r[k.replace("frame", "src")] = f2s.get(r[k])
            blind["device_reps"] = reps
            blind["device_frames_delivered"] = len(f2s)
            blind["device_frame_eq_src"] = all(k == v for k, v in f2s.items())
            sealed["device_reps"] = sreps
            sealed["device_session_end"] = sess
        else:
            blind["device_reps"] = None
        # --- 2D-mode replay (rules-calib rep intervals), full-res video frames
        pj = f"{REF}/{clip}_{EXNAME[ex]}_halpe26.json"
        pc = f"{REF}/{clip}_{EXNAME[ex]}_halpe26.csv"
        sha(pj); sha(pc)
        rj = json.load(open(pj))
        blind["replay_image_size"] = rj["image_size"]
        blind["replay_reps"] = [{"rep": i + 1, "start_frame": r.get("start_frame"), "end_frame": r.get("end_frame")}
                                for i, r in enumerate(rj["reps"])]
        blind["replay_transitions"] = rj.get("transitions")
        sealed["replay_reps"] = [{k: r.get(k) for k in sorted(SEAL_KEYS) if k in r} for r in rj["reps"]]
        sealed["replay_events"] = rj.get("events")
        sealed["replay_session"] = rj.get("session")
        # keypoints (Halpe26, full-res) -> compact per-frame rows: frame, status, then x,y,c for 26 joints
        rows = []
        with open(pc) as fh:
            rd = csv.reader(fh)
            hdr = next(rd)
            for row in rd:
                rows.append([int(row[0]), row[2]] + [round(float(v), 1) if i % 3 != 2 else round(float(v), 3)
                                                     for i, v in enumerate(row[4:])])
        blind["kp_header"] = "frame,status,j0_x,j0_y,j0_c,...,j25_c (Halpe26, replay image coords)"
        with gzip.open(f"{OUT}/blind/{clip}_kp.json.gz", "wt") as g:
            json.dump(rows, g)
        json.dump(blind, open(f"{OUT}/blind/{clip}.json", "w"), indent=1)
        json.dump(sealed, open(f"{OUT}/sealed/{clip}.json", "w"))
json.dump({"inputs": inputs, "argv": sys.argv}, open(f"{OUT}/inputs.json", "w"), indent=1)
print("done", len(inputs))
