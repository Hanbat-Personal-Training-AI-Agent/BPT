"""Render SMPL A-pose silhouette outlines for the calibration camera guide.

Loads the neutral SMPL body, poses it in the A-pose the calibration asks for,
projects it at the four capture yaws, and writes the outer contour of each
silhouette as a normalized polygon that Flutter draws over the camera preview.

    conda run -n bpt-ai python scripts/build_calibration_silhouettes.py

Model files are not in git: unzip SMPL_python_v.1.1.0.zip into external/smpl/.
"""
import argparse
import json
import pickle
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "external/smpl/SMPL_python_v.1.1.0/smpl/models/basicmodel_neutral_lbs_10_207_0_v1.1.0.pkl"
OUTPUT = ROOT / "assets/calibration/silhouettes.json"

# SMPL joint indices used to build the A-pose.
L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW, L_HIP, R_HIP = 16, 17, 18, 19, 1, 2

# yaw in degrees, counter-clockwise seen from above (user turning to their left).
VIEWS = {"front": 0.0, "leftfront": -60.0, "rightfront": 60.0, "back": 180.0}


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--arm-drop-deg", type=float, default=50.0, help="shoulder rotation from T-pose")
    p.add_argument("--leg-spread-deg", type=float, default=-3.0, help="negative widens the stance")
    p.add_argument("--render-size", type=int, default=1024)
    p.add_argument("--epsilon", type=float, default=0.0015, help="contour simplification, fraction of height")
    p.add_argument("--output", default=str(OUTPUT))
    return p.parse_args()


def load_smpl(path):
    # chumpy (used by the official pickles) still expects numpy's removed aliases.
    for name, alias in (("bool", bool), ("int", int), ("float", float), ("complex", complex),
                        ("object", object), ("unicode", str), ("str", str)):
        if not hasattr(np, name):
            setattr(np, name, alias)
    with open(path, "rb") as fh:
        data = pickle.load(fh, encoding="latin1")
    plain = {}
    for key in ("v_template", "shapedirs", "posedirs", "J_regressor", "weights", "kintree_table", "f"):
        value = data[key]
        if hasattr(value, "toarray"):  # scipy sparse J_regressor
            value = value.toarray()
        plain[key] = np.asarray(value, dtype="float64" if key != "kintree_table" and key != "f" else None)
    return plain


def rodrigues(rotvec):
    theta = np.linalg.norm(rotvec)
    if theta < 1e-8:
        return np.eye(3)
    k = rotvec / theta
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + np.sin(theta) * K + (1 - np.cos(theta)) * K @ K


def pose_mesh(model, pose):
    """Standard SMPL LBS: pose blend shapes, then skinning. pose: (24, 3) axis-angle."""
    v_template, posedirs = model["v_template"], model["posedirs"]
    J = model["J_regressor"] @ v_template
    rots = np.stack([rodrigues(p) for p in pose])
    pose_feature = (rots[1:] - np.eye(3)).reshape(-1)  # 23 * 9 = 207
    v_posed = v_template + (posedirs.reshape(-1, 207) @ pose_feature).reshape(-1, 3)

    parents = model["kintree_table"][0].astype(int)
    globals_ = [np.eye(4)] * len(pose)
    for i in range(len(pose)):
        local = np.eye(4)
        local[:3, :3] = rots[i]
        local[:3, 3] = J[i] - (J[parents[i]] if i > 0 else 0)
        globals_[i] = local if i == 0 else globals_[parents[i]] @ local
    # remove the rest-pose offset so the rest pose maps to itself
    transforms = np.stack([
        g - np.pad((g @ np.concatenate([J[i], [0]]))[:, None], ((0, 0), (3, 0)))
        for i, g in enumerate(globals_)
    ])
    T = np.einsum("vj,jab->vab", model["weights"], transforms)
    v_h = np.concatenate([v_posed, np.ones((len(v_posed), 1))], axis=1)
    return np.einsum("vab,vb->va", T, v_h)[:, :3]


def a_pose(arm_drop_deg, leg_spread_deg):
    pose = np.zeros((24, 3))
    drop, spread = np.deg2rad(arm_drop_deg), np.deg2rad(leg_spread_deg)
    # -z rotation swings the model's left arm down, +z the right arm.
    pose[L_SHOULDER] = [0, 0, -drop]
    pose[R_SHOULDER] = [0, 0, drop]
    pose[L_ELBOW] = [0, 0, -drop * 0.12]
    pose[R_ELBOW] = [0, 0, drop * 0.12]
    pose[L_HIP] = [0, 0, -spread]
    pose[R_HIP] = [0, 0, spread]
    return pose


# COCO-17-equivalent SMPL joints for the A-pose sanity check.
SMPL_JOINTS = {"l_shoulder": 16, "r_shoulder": 17, "l_elbow": 18, "r_elbow": 19,
               "l_wrist": 20, "r_wrist": 21, "l_hip": 1, "r_hip": 2, "l_ankle": 7, "r_ankle": 8}


def report_pose_metrics(model, verts):
    """Print the A-pose ratios the runtime engine checks, so the guide matches what we ask users to do."""
    j = model["J_regressor"] @ verts
    g = {k: j[i] for k, i in SMPL_JOINTS.items()}
    shoulder_y = (g["l_shoulder"][1] + g["r_shoulder"][1]) / 2
    hip_y = (g["l_hip"][1] + g["r_hip"][1]) / 2
    torso = shoulder_y - hip_y  # SMPL y grows upward
    for side in ("l", "r"):
        # image-space drop: y grows downward, so a lowered wrist is a positive drop
        wrist_drop = (shoulder_y - g[f"{side}_wrist"][1]) / torso
        elbow_ratio = (shoulder_y - g[f"{side}_elbow"][1]) / (shoulder_y - g[f"{side}_wrist"][1])
        reach = abs(g[f"{side}_wrist"][0] - (g["l_hip"][0] + g["r_hip"][0]) / 2) / torso
        print(f"{side}: wristDrop {wrist_drop:.2f} (0.60-0.97)  elbowRatio {elbow_ratio:.2f} (0.38-0.75)  "
              f"wristReach/T {reach:.2f} (>0.8)")
    hip_w = abs(g["l_hip"][0] - g["r_hip"][0])
    ankle_gap = abs(g["l_ankle"][0] - g["r_ankle"][0])
    print(f"ankleGap/hipWidth {ankle_gap / hip_w:.2f} (0.9-2.6)")


def silhouette_contour(verts, faces, yaw_deg, size, epsilon_frac):
    import cv2

    yaw = np.deg2rad(yaw_deg)
    c, s = np.cos(yaw), np.sin(yaw)
    rot = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])  # about the vertical axis
    p = verts @ rot.T
    x, y = p[:, 0], p[:, 1]
    # orthographic projection; image y grows downward
    minx, maxx, miny, maxy = x.min(), x.max(), y.min(), y.max()
    height = maxy - miny
    scale = (size * 0.92) / height
    px = ((x - (minx + maxx) / 2) * scale + size / 2)
    py = ((maxy - y) * scale + size * 0.04)

    mask = np.zeros((size, size), np.uint8)
    tri = np.stack([px, py], axis=1)[faces].astype(np.int32)
    cv2.fillPoly(mask, tri, 255)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contour = max(contours, key=cv2.contourArea)
    contour = cv2.approxPolyDP(contour, epsilon_frac * size, True).reshape(-1, 2).astype("float64")

    # normalize: y in [0, 1] over the body height, x in the same unit, centered on 0.5
    top, bottom = contour[:, 1].min(), contour[:, 1].max()
    body = bottom - top
    out = np.stack([(contour[:, 0] - (px.min() + px.max()) / 2) / body + 0.5,
                    (contour[:, 1] - top) / body], axis=1)
    return out, float((px.max() - px.min()) / body)


def main():
    args = parse_args()
    if not MODEL.exists():
        raise SystemExit(f"SMPL model not found: {MODEL}\nUnzip SMPL_python_v.1.1.0.zip into external/smpl/.")
    model = load_smpl(MODEL)
    verts = pose_mesh(model, a_pose(args.arm_drop_deg, args.leg_spread_deg))
    faces = model["f"].astype(int)
    report_pose_metrics(model, verts)

    views = {}
    for name, yaw in VIEWS.items():
        points, width = silhouette_contour(verts, faces, yaw, args.render_size, args.epsilon)
        views[name] = {
            "nominalYawDeg": yaw,
            "widthOverHeight": round(width, 4),
            "points": [[round(float(x), 4), round(float(y), 4)] for x, y in points],
        }
        print(f"{name:10s} yaw {yaw:6.1f}  points {len(points):3d}  w/h {width:.3f}")

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({
        "source": "SMPL neutral, A-pose",
        "armDropDeg": args.arm_drop_deg,
        "legSpreadDeg": args.leg_spread_deg,
        "coordinates": "x,y normalized by body height; y=0 head top, y=1 feet; x=0.5 body centre",
        "views": views,
    }, indent=2) + "\n")
    print(f"output={out}")


if __name__ == "__main__":
    main()
