"""Writes tests/fixtures/live3d_parity.json: the Python reference LiveMotionAGFormer (+ Pose3DConstraints)
on a synthetic COCO17 sequence, for ios MotionAGFormerLiveTests (Swift <-> Python parity).

  conda run -n bpt-coreml python scripts/make_live3d_parity_fixture.py [--coreml assets/coreml/motionagformer_xs.mlpackage]

`fake` cases use a closed-form predictor (both sides implement it), so the window / row / state / constraint logic
is compared exactly. `coreml` (when --coreml is given) stores Core ML XS outputs for the same sequence so the Swift
test can compare its own Core ML run (same model file, fp16 output) end to end.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pose_feedback.body.live_motionagformer import LiveMotionAGFormer  # noqa: E402

W, H = 720, 1280


def sequence(n=90, lost=(50, 68)):
    """A standing person bobbing (squat-like) with a tracking gap (confidence 0.05) in `lost`."""
    base = np.array([[360, 300], [370, 290], [350, 290], [385, 295], [335, 295], [410, 380], [310, 380],
                     [430, 480], [290, 480], [440, 570], [280, 570], [390, 600], [330, 600],
                     [400, 760], [320, 760], [405, 920], [315, 920]], dtype=float)
    frames = []
    for t in range(n):
        k = base.copy()
        dip = 120 * (0.5 - 0.5 * math.cos(2 * math.pi * t / 30))
        k[:13, 1] += dip
        k[13:15, 0] += np.array([1, -1]) * 0.3 * dip
        k[:, 0] += 15 * math.sin(t / 7)
        conf = np.full((17, 1), 0.9) - 0.01 * (np.arange(17)[:, None] % 5)
        if lost[0] <= t < lost[1]:
            conf[:] = 0.05
        if t == 20:
            conf[:12] = 0.1  # one isolated low frame (kept in the window, state tracking_lost)
        frames.append(np.concatenate([k, conf], axis=1))
    return frames


def fake_predict(window):
    out = np.empty_like(window, dtype="float64")
    t = np.arange(window.shape[0])[:, None]
    out[..., 0] = window[..., 0]
    out[..., 1] = window[..., 1]
    out[..., 2] = 0.3 * window[..., 0] * window[..., 1] + 0.01 * t
    return out


def run(predict, frames, lookahead, cadence):
    live = LiveMotionAGFormer(predict, lookahead=lookahead, cadence=cadence)
    out = []
    for i, k in enumerate(frames):
        out += live.push(i, k, W, H)
    out += live.flush()
    rows = []
    for r in out:
        c = r["constraints"]
        rows.append({
            "frame": r["frame"], "state": r["state"], "filled": r["filled"], "row": r["row"],
            "raw": None if r["raw"] is None else np.round(r["raw"], 8).tolist(),
            "pose3d": None if r["pose3d"] is None else np.round(r["pose3d"], 8).tolist(),
            "bone_max_correction": None if c is None else c["bone_max_correction"],
            "bone_source": None if c is None else c["bone_source"],
            "angle_corrections": None if c is None else c["angle_corrections"],
        })
    return {"lookahead": lookahead, "cadence": cadence, "inferences": live.inferences, "frames": rows}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--coreml")
    ap.add_argument("--out", default=str(ROOT / "tests/fixtures/live3d_parity.json"))
    a = ap.parse_args()
    frames = sequence()
    fixture = {"image_size": [W, H], "coco17": [np.round(k, 6).tolist() for k in frames],
               "fake": [run(fake_predict, frames, la, cad) for la, cad in ((5, 1), (5, 2), (0, 1), (13, 1))]}
    if a.coreml:
        import coremltools as ct
        model = ct.models.MLModel(a.coreml, compute_units=ct.ComputeUnit.CPU_ONLY)
        predict = lambda w: model.predict({"input_2d_sequence": w[None].astype("float32")})["pred_3d_sequence"][0]  # noqa: E731
        fixture["coreml"] = {"model": Path(a.coreml).name, **run(predict, frames, 5, 1)}
    Path(a.out).write_text(json.dumps(fixture, separators=(",", ":")))
    print("wrote", a.out)


if __name__ == "__main__":
    main()
