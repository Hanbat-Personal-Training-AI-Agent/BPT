"""Aggregate saved torso diagnostics without inference; Home-only predictions."""
import argparse
import ast
import json
from collections import defaultdict
from pathlib import Path

import numpy as np

from xs_torso_diagnostic import direction_angle, label_mask, load_seqs, stats, torso, unit


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--run", required=True)
    a = p.parse_args()
    root = Path(a.run)
    report = json.loads((root / "summary.json").read_text())
    seqs = load_seqs([report["arguments"]["data"]])
    pred = np.load(root / "predictions_HOME_ONLY.npz")
    labels = Path(report["arguments"]["ex3d_labels"])
    groups, world = defaultdict(lambda: defaultdict(list)), {}
    for tag in report["rows"]:
        for i, s in enumerate(seqs):
            idx = pred[f"index_{i}"]
            pp = pred[f"{tag}_{i}"]
            pv, gv = torso(pp), torso(s["y"][idx])
            iv = torso(s["x"][idx])[:, :2]
            valid = label_mask(labels, s["subject"], len(s["x"]))[idx] & s["fmask"][idx]
            valid &= np.array([any(start <= t <= end for start, end in s["seg"]) for t in idx])
            up = np.asarray(s["up_c"])
            signed = direction_angle(pv, up) - direction_angle(gv, up)
            bucket = "side<=40" if s["view"] <= 40 else "front>=75" if s["view"] >= 75 else "oblique"
            vals = dict(vector_angle=direction_angle(pv, gv), signed_inclination=signed,
                        absolute_inclination=np.abs(signed), xy_direction_error=direction_angle(pv[:, :2], gv[:, :2]),
                        model_xy_vs_input=direction_angle(pv[:, :2], iv),
                        label_xy_vs_input=direction_angle(gv[:, :2], iv),
                        depth_fraction_difference=unit(pv)[:, 2] - unit(gv)[:, 2])
            for key, val in vals.items():
                groups[f"{tag}/{bucket}"][key].extend(val[valid].tolist())
            seq, camera = s["name"].split("/")
            metadata = json.loads((labels / seq / "geometry/metadata.json").read_text())["camera_geometry"]
            if isinstance(metadata, str):
                metadata = ast.literal_eval(metadata)
            rotation = np.asarray(metadata[camera]["extrinsic_world_to_camera"])[:, :3]
            # Row vectors: camera = world @ R.T, therefore world = camera @ R.
            world[(tag, seq, camera)] = (idx, unit(pv) @ rotation, valid)
    pairs, all_pairs = [], defaultdict(list)
    for tag in report["rows"]:
        for seq in sorted({s["subject"] for s in seqs}):
            for left, right in (("cam1", "cam2"), ("cam1", "cam3"), ("cam2", "cam3")):
                ix, x, vx = world[(tag, seq, left)]
                iy, y, vy = world[(tag, seq, right)]
                assert np.array_equal(ix, iy), (seq, "camera time grids differ")
                err = direction_angle(x, y)[vx & vy]
                all_pairs[tag].extend(err.tolist())
                pairs.append(dict(model=tag, sequence=seq, cameras=[left, right], world_direction_difference=stats(err)))
    result = dict(
        note="Post-result diagnostic, fixed stride5. Estimated camera up and pseudo GT. Cross-camera rotations are internally consistent but not independently validated.",
        input_run=str(root), by_view={g: {k: stats(v) for k, v in vals.items()} for g, vals in groups.items()},
        cross_camera=pairs, cross_camera_all={tag: stats(v) for tag, v in all_pairs.items()})
    (root / "aggregate.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
