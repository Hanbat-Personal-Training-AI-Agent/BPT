"""Builds the fitting worker's body model file and uploads it to the Modal Volume `bpt-weights`.

    python prepare_weights.py --smpl <basicmodel_neutral_lbs_10_207_0_v1.1.0.pkl> \
        --h36m <J_regressor_h36m.npy> --out smpl_neutral_h36m.npz [--upload]

Neither input is redistributable (SMPL: research-only, no redistribution; the regressor comes with
SPIN's data and is SMPL-derived), so both stay out of git and are fetched by whoever deploys.

The regressor as SPIN ships it lists the LEFT leg at rows 1-3 and the right leg at 4-6; the app's
H36M order (rtmpose_motionagformer_image_to_pose_pipeline.md §12) is right then left. The rows are
reordered here and the sides are checked on the SMPL rest pose (subject's left is +x).
"""
import argparse
import pickle
import subprocess

import numpy as np

import body

SPIN_TO_APP = [0, 4, 5, 6, 1, 2, 3, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]


def load_smpl_pkl(path):
    # The official pickle stores chumpy arrays; numpy's removed aliases are all it needs to unpickle.
    for name, alias in (("bool", bool), ("int", int), ("float", float), ("complex", complex),
                        ("object", object), ("unicode", str), ("str", str)):
        if name not in np.__dict__:
            setattr(np, name, alias)
    with open(path, "rb") as fh:
        data = pickle.load(fh, encoding="latin1")
    regressor = data["J_regressor"]
    return {
        "v_template": np.asarray(data["v_template"], dtype=np.float64),
        "shapedirs": np.asarray(data["shapedirs"], dtype=np.float64)[:, :, :10],
        "posedirs": np.asarray(data["posedirs"], dtype=np.float64),
        "J_regressor": regressor.toarray() if hasattr(regressor, "toarray") else np.asarray(regressor),
        "weights": np.asarray(data["weights"], dtype=np.float64),
        "kintree_table": np.asarray(data["kintree_table"]),
        "f": np.asarray(data["f"]),
    }


def check_sides(joints):
    """On the rest pose every left joint must sit at +x of its right partner."""
    for side in ("hip", "knee", "ankle", "shoulder", "elbow", "wrist"):
        left, right = (joints[body.H36M_JOINTS.index(f"{s}_{side}")][0] for s in ("left", "right"))
        if not left > right:
            raise SystemExit(f"regressor sides wrong at {side}: left x {left:.3f} <= right x {right:.3f}")


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--smpl", required=True)
    args.add_argument("--h36m", required=True)
    args.add_argument("--out", default="smpl_neutral_h36m.npz")
    args.add_argument("--upload", action="store_true", help="modal volume put bpt-weights")
    opts = args.parse_args()

    model = load_smpl_pkl(opts.smpl)
    regressor = np.load(opts.h36m)
    assert regressor.shape == (17, 6890), regressor.shape
    regressor = regressor[SPIN_TO_APP]
    check_sides(body.h36m_joints(model["v_template"], regressor))
    np.savez_compressed(opts.out, **model, J_regressor_h36m=regressor)
    height = body.height_m(model["v_template"])
    print(f"wrote {opts.out}: rest height {height * 100:.1f} cm, sides ok")
    if opts.upload:
        subprocess.run(["modal", "volume", "create", "bpt-weights"], check=False)
        subprocess.run(["modal", "volume", "put", "--force", "bpt-weights", opts.out, "/smpl_neutral_h36m.npz"],
                       check=True)


if __name__ == "__main__":
    main()
