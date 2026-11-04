"""Post-result C1 torso investigation; fixed sampled windows, CPU only, no tuning.

Inputs and predictions remain on Home. Exercise3D labels are pseudo 3D, and their
up_c is estimated from cameras rather than measured gravity. This diagnostic does
not replace the pre-registered full-frame evaluation or choose a model/threshold.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent), str(HERE.parent.parent)]
from finetune_motionagformer_fit3d import load
from xs_train import load_seqs


def unit(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return np.divide(v, n, out=np.full_like(v, np.nan), where=n > 1e-9)


def direction_angle(v, w):
    return np.degrees(np.arccos(np.clip(np.sum(unit(v) * unit(w), axis=-1), -1, 1)))


def torso(p):
    return (p[:, 11] + p[:, 14] - p[:, 1] - p[:, 4]) / 2


def stats(a):
    a = np.asarray(a)
    a = a[np.isfinite(a)]
    return dict(n=len(a), median=float(np.median(a)) if len(a) else None,
                p10=float(np.percentile(a, 10)) if len(a) else None,
                p90=float(np.percentile(a, 90)) if len(a) else None,
                mean=float(np.mean(a)) if len(a) else None)


def axis_rotation(axis, degrees):
    v = np.eye(3)[axis]
    x, y, z = v
    K = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    theta = np.radians(degrees)
    return np.eye(3) + np.sin(theta) * K + (1 - np.cos(theta)) * (K @ K)


def selected_predict(model, x, indices, batch=64):
    # Identical input windows and selected row as app_predict; only output times are sampled.
    windows = np.clip(indices[:, None] + 5 - 26 + np.arange(27)[None], 0, len(x) - 1)
    with torch.no_grad():
        return np.concatenate([model(torch.from_numpy(x[windows[i:i + batch]]))[:, 21].numpy()
                               for i in range(0, len(indices), batch)])


def label_mask(root, seq, n):
    z = np.load(Path(root) / seq / "geometry/canonical_3d.npz")
    js = [list(z["joint_names"]).index(name) for name in
          ("left_hip", "right_hip", "left_shoulder", "right_shoulder")]
    return z["valid_mask"][:n, js].all(1) & np.isfinite(z["keypoints_3d"][:n, js]).all((1, 2))


def describe(s, prediction, idx, valid):
    ref = torso(s["y"][idx])
    pred = torso(prediction)
    inside = np.array([any(start <= t <= end for start, end in s["seg"]) for t in idx])
    masks = dict(rep_frames=inside, rep_and_limb_fmask=inside & s["fmask"][idx],
                 rep_and_torso_valid=inside & valid[idx],
                 rep_and_both=inside & s["fmask"][idx] & valid[idx])
    up = np.asarray(s["up_c"])
    ups = dict(estimated_up=up, camera_up=np.array([0., -1., 0.]))
    # Fixed sensitivity checks, not a search for a favorable gravity direction.
    for axis in range(3):
        for deg in (-10, 10):
            ups[f"common_up_axis{axis}_{deg:+d}"] = axis_rotation(axis, deg) @ up
    row = dict(name=s["name"], view=s["view"], exercise=s["exercise"], estimated_up=up.tolist(),
               up_tilt_deg=float(direction_angle(up, np.array([0., -1., 0.]))),
               frames=len(idx), masks={name: int(mask.sum()) for name, mask in masks.items()}, axes={})
    for name, mask in masks.items():
        pa, ga = direction_angle(pred, up), direction_angle(ref, up)
        row[name] = dict(vector_angle=stats(direction_angle(pred, ref)[mask]),
                         signed_inclination=stats((pa-ga)[mask]),
                         absolute_inclination=stats(np.abs(pa-ga)[mask]),
                         xy_direction_error=stats(direction_angle(pred[:, :2], ref[:, :2])[mask]),
                         pred_depth_fraction=stats(unit(pred)[mask, 2]),
                         ref_depth_fraction=stats(unit(ref)[mask, 2]),
                         length_ratio=stats((np.linalg.norm(pred, axis=1) / np.linalg.norm(ref, axis=1))[mask]))
    both = masks["rep_and_both"]
    for name, axis in ups.items():
        pa, ga = direction_angle(pred, axis), direction_angle(ref, axis)
        rep_bias = []
        for start, end in s["seg"]:
            keep = both & (idx >= start) & (idx <= end)
            if keep.any():
                rep_bias.append(float(np.max(pa[keep]) - np.max(ga[keep])))
        row["axes"][name] = dict(pred_angle=stats(pa[both]), ref_angle=stats(ga[both]),
                                 signed_error=stats((pa-ga)[both]), absolute_error=stats(np.abs(pa-ga)[both]),
                                 signed_sampled_rep_extreme=stats(rep_bias),
                                 absolute_sampled_rep_extreme=stats(np.abs(rep_bias)))
    # A separate anatomical definition check: root->thorax is not the evaluated torso metric.
    root_thorax = prediction[:, 8] - prediction[:, 0]
    row["skeleton_definition"] = dict(
        model_midpoints_vs_root_thorax=stats(direction_angle(pred, root_thorax)[both]),
        label_midpoints_vs_root_thorax=stats(direction_angle(ref, s["y"][idx, 8]-s["y"][idx, 0])[both]))
    return row


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--data", required=True)
    p.add_argument("--models", required=True)
    p.add_argument("--names", default="", help="Optional comma-separated fixed sequence names for a narrow follow-up")
    p.add_argument("--ex3d-labels", default=str(Path("~/bpt-smpl/ex3d/exercise3d_labels").expanduser()))
    p.add_argument("--mag-repo", default=str(Path("~/models/MotionAGFormer").expanduser()))
    p.add_argument("--stride", type=int, default=5)
    p.add_argument("--threads", type=int, default=2)
    p.add_argument("--out", required=True)
    a = p.parse_args()
    assert a.stride > 0
    torch.set_num_threads(a.threads)
    seqs = load_seqs([a.data])
    if a.names:
        names = a.names.split(",")
        seqs = [s for s in seqs if s["name"] in names]
        assert {s["name"] for s in seqs} == set(names), names
    assert all(s["kind"] == "E" and s["split"] == "heldout" for s in seqs)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    report, arrays, predictions = dict(arguments=vars(a), rows={}, model_difference=[]), {}, {}
    for tag, ckpt in (kv.split("=", 1) for kv in a.models.split(",")):
        model = load(a.mag_repo, ckpt, "cpu")[0].eval()
        report["rows"][tag] = []
        predictions[tag] = []
        for i, s in enumerate(seqs):
            idx = np.arange(0, len(s["x"]), a.stride)
            pred = selected_predict(model, s["x"], idx)
            valid = label_mask(a.ex3d_labels, s["subject"], len(s["x"]))
            report["rows"][tag].append(describe(s, pred, idx, valid))
            arrays[f"{tag}_{i}"] = pred
            arrays[f"index_{i}"] = idx
            predictions[tag].append(pred)
            (out / "summary.partial.json").write_text(json.dumps(report, indent=2))
            print(tag, s["name"], len(idx), "sampled outputs complete", flush=True)
        del model
    tags = list(predictions)
    if len(tags) == 2:
        for i, s in enumerate(seqs):
            report["model_difference"].append(dict(name=s["name"], models=tags,
                torso_direction_difference=stats(direction_angle(
                    torso(predictions[tags[0]][i]), torso(predictions[tags[1]][i])))))
    np.savez_compressed(out / "predictions_HOME_ONLY.npz", **arrays)
    (out / "summary.json").write_text(json.dumps(report, indent=2))
    print("DONE", out, flush=True)


if __name__ == "__main__":
    main()
