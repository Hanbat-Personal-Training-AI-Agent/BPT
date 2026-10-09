"""Compare MotionAGFormer 2D-input normalizations on pipeline npz output.

Usage:
  python scripts/compare_motionagformer_3d_normalization.py \
      --motionagformer-coreml assets/coreml/motionagformer_xs.mlpackage \
      --calibration result_guided.json clip1.npz [clip2.npz ...]

npz files come from scripts/run_coreml_rtmpose_s_motionagformer_xs_pipeline.py (any
--normalization; only `h36m17_2d` and `image_size` are used). Each method re-runs
MotionAGFormer-XS Core ML on the same 2D keypoints (lookahead 5, 27-frame window).

Metrics per clip and method (medians over frames unless noted):
  shin/thigh   |knee-ankle| / |hip-knee| per leg, 3D vs 2D (pixels) vs calibration target
  ank/torso    (ankle_y - pelvis_y) / |thorax - pelvis|, 3D vs 2D (scale-free)
  ank raw      ankle_y - pelvis_y in the method's normalized input units vs 3D output units
  LR leg %     |(thigh+shin)_L - (thigh+shin)_R| / mean, 3D
  clamp %      share of frames the knee hinge clamp (enabled=True, 10 deg) would correct
  bone %       mean |correction| % of the calibration bone-length constraint, legs / arms
  jitter       median frame-to-frame 3D joint speed / median 3D leg length (x1000)
  recrops      person_crop only: how often the crop moved
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pose_feedback.body.motionagformer_adapter import (  # noqa: E402
    NORMALIZATION_LONG_SIDE,
    NORMALIZATION_SCREEN,
    PersonSquareCropTracker,
    image_square_crop,
    normalize_motionagformer_sequence,
    square_crop_normalize,
)
from pose_feedback.body.motionagformer_buffer import MotionAGFormerWindowBuilder  # noqa: E402
from pose_feedback.geometry.bone_lengths import apply_bone_lengths, load_bone_length_targets  # noqa: E402
from pose_feedback.geometry.hinge_limit import clamp_knee_hyperextension  # noqa: E402

LEGS = {"R": (1, 2, 3), "L": (4, 5, 6)}
LEG_SEGS = ("right_hip-right_knee", "right_knee-right_ankle", "left_hip-left_knee", "left_knee-left_ankle")
ARM_SEGS = ("left_shoulder-left_elbow", "left_elbow-left_wrist", "right_shoulder-right_elbow", "right_elbow-right_wrist")


class CountingTracker(PersonSquareCropTracker):
    def __init__(self, **kw):
        super().__init__(**kw)
        self.moves = 0

    def update(self, joints_2d, confidence):
        before = self.crop
        crop = super().update(joints_2d, confidence)
        self.moves += before is not None and crop is not before
        return crop


def ema_crop_sequence(xy, conf, w, h, margin=2.0, alpha=0.1):
    """Research-only alternative to the hysteresis tracker: EMA of centre and side."""
    out, crop, fallback = [], None, image_square_crop(w, h, NORMALIZATION_LONG_SIDE)
    for f, c in zip(xy, conf):
        tracker = PersonSquareCropTracker(margin=margin)
        target = tracker.update(f, c)
        if target is not None:
            crop = target if crop is None else tuple(a + alpha * (b - a) for a, b in zip(crop, target))
        out.append(square_crop_normalize(f, crop or fallback))
    return np.stack(out)


def methods():
    def crop(margin, max_ratio=2.0):
        def run(xy, conf, w, h):
            t = CountingTracker(margin=margin, max_ratio=max_ratio)
            return normalize_motionagformer_sequence(xy, conf, w, h, "person_crop", tracker=t), t.moves
        return run

    return {
        "screen (current)": lambda xy, conf, w, h: (normalize_motionagformer_sequence(xy, conf, w, h, NORMALIZATION_SCREEN), None),
        "A long_side": lambda xy, conf, w, h: (normalize_motionagformer_sequence(xy, conf, w, h, NORMALIZATION_LONG_SIDE), None),
        "B crop m2.0": crop(2.0),
        "B crop m2.0 band1.6": crop(2.0, 1.6),
        "B crop m1.25": crop(1.25),
        "B ema m2.0": lambda xy, conf, w, h: (ema_crop_sequence(xy, conf, w, h), None),
    }


def run_model(model, normalized, conf, lookahead=5, window=27):
    frames = np.concatenate([normalized, conf[..., None]], axis=-1).astype("float32")
    builder = MotionAGFormerWindowBuilder(window_size=window)
    sel = window - 1 - lookahead
    out = []
    for i in range(len(frames)):
        w, _ = builder.build_lookahead_padded(frames, i, lookahead)
        pred = model.predict({"input_2d_sequence": w[None].astype("float32")})["pred_3d_sequence"]
        out.append(np.asarray(pred, dtype="float64")[0, sel])
    return np.stack(out)


def seg(p, a, b):
    return np.linalg.norm(p[:, b] - p[:, a], axis=-1)


def metrics(p3, p2_px, p2_norm, targets, moves):
    r = {}
    for leg, (hip, knee, ank) in LEGS.items():
        r[f"st3_{leg}"] = np.median(seg(p3, knee, ank) / seg(p3, hip, knee))
        r[f"st2_{leg}"] = np.median(seg(p2_px, knee, ank) / seg(p2_px, hip, knee))
    side = {"R": "right", "L": "left"}
    for leg in LEGS:
        s = side[leg]
        r[f"stT_{leg}"] = targets[f"{s}_knee-{s}_ankle"] / targets[f"{s}_hip-{s}_knee"]
    ank3 = 0.5 * (p3[:, 3, 1] + p3[:, 6, 1]) - p3[:, 0, 1]
    ank2 = 0.5 * (p2_norm[:, 3, 1] + p2_norm[:, 6, 1]) - p2_norm[:, 0, 1]
    r["ank3_raw"], r["ank2_raw"] = np.median(ank3), np.median(ank2)
    r["ank3_torso"] = np.median(ank3 / seg(p3, 0, 8))
    r["ank2_torso"] = np.median(ank2 / seg(p2_norm, 0, 8))
    leg_r = seg(p3, 1, 2) + seg(p3, 2, 3)
    leg_l = seg(p3, 4, 5) + seg(p3, 5, 6)
    r["lr_pct"] = 100 * np.median(np.abs(leg_l - leg_r) / (0.5 * (leg_l + leg_r)))
    corr = {"R": 0, "L": 0}
    bone = {s: [] for s in LEG_SEGS + ARM_SEGS}
    for f in p3:
        _, rep = clamp_knee_hyperextension(f, enabled=True)
        corr["R"] += rep["right"]["corrected"]
        corr["L"] += rep["left"]["corrected"]
        _, b = apply_bone_lengths(f, targets)
        for s in bone:
            e = b["segments"][s]
            bone[s].append(abs(e["output"] - e["observed"]) / e["observed"])
    r["clamp_R"], r["clamp_L"] = 100 * corr["R"] / len(p3), 100 * corr["L"] / len(p3)
    r["bone_legs"] = 100 * np.mean([np.mean(bone[s]) for s in LEG_SEGS])
    r["bone_shins"] = 100 * np.mean([np.mean(bone[s]) for s in LEG_SEGS[1::2]])
    r["bone_arms"] = 100 * np.mean([np.mean(bone[s]) for s in ARM_SEGS])
    speed = np.linalg.norm(np.diff(p3, axis=0), axis=-1)
    r["jitter"] = 1000 * np.median(speed) / np.median(0.5 * (leg_l + leg_r))
    r["in_ymax"] = float(np.percentile(np.abs(p2_norm[..., 1]), 99))
    r["moves"] = moves
    return r


COLUMNS = [
    ("shin/thigh R 3D|2D|tgt", lambda r: f"{r['st3_R']:.2f} / {r['st2_R']:.2f} / {r['stT_R']:.2f}"),
    ("shin/thigh L 3D|2D|tgt", lambda r: f"{r['st3_L']:.2f} / {r['st2_L']:.2f} / {r['stT_L']:.2f}"),
    ("ank/torso 3D|2D", lambda r: f"{r['ank3_torso']:.2f} / {r['ank2_torso']:.2f}"),
    ("ank raw 3D|2D", lambda r: f"{r['ank3_raw']:.2f} / {r['ank2_raw']:.2f}"),
    ("|y| p99 in", lambda r: f"{r['in_ymax']:.2f}"),
    ("LR leg %", lambda r: f"{r['lr_pct']:.1f}"),
    ("clamp R|L %", lambda r: f"{r['clamp_R']:.0f} / {r['clamp_L']:.0f}"),
    ("bone % legs|shins|arms", lambda r: f"{r['bone_legs']:.1f} / {r['bone_shins']:.1f} / {r['bone_arms']:.1f}"),
    ("jitter", lambda r: f"{r['jitter']:.1f}"),
    ("recrops", lambda r: "-" if r["moves"] is None else str(r["moves"])),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--motionagformer-coreml", required=True)
    ap.add_argument("--calibration", required=True)
    ap.add_argument("--json-out")
    ap.add_argument("npz", nargs="+")
    args = ap.parse_args()
    import coremltools as ct

    model = ct.models.MLModel(args.motionagformer_coreml, compute_units=ct.ComputeUnit.ALL)
    targets = load_bone_length_targets(json.loads(Path(args.calibration).read_text()))
    all_results = {}
    for path in args.npz:
        data = np.load(path)
        h36m = data["h36m17_2d"].astype("float32")
        w, h = (int(v) for v in data["image_size"])
        xy, conf = h36m[..., :2], h36m[..., 2]
        name = Path(path).stem
        print(f"\n## {name}  {w}x{h}  frames={len(h36m)}")
        print("| method | " + " | ".join(c for c, _ in COLUMNS) + " |")
        print("|---" * (len(COLUMNS) + 1) + "|")
        all_results[name] = {}
        for label, fn in methods().items():
            norm, moves = fn(xy, conf, w, h)
            p3 = run_model(model, norm, conf)
            r = metrics(p3, xy.astype("float64"), norm.astype("float64"), targets, moves)
            all_results[name][label] = {k: (None if v is None else float(v)) for k, v in r.items()}
            print(f"| {label} | " + " | ".join(fn_(r) for _, fn_ in COLUMNS) + " |", flush=True)
    if args.json_out:
        Path(args.json_out).write_text(json.dumps(all_results, indent=1))


if __name__ == "__main__":
    main()
