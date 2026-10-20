"""Offline scoring only. Nothing in this module supplies estimator state."""
import numpy as np

from .data import BONES, JOINTS

LIMBS = (1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16)
WRISTS = (13, 16)
ANKLES = (3, 6)
LIMB_EDGES = ((1, 2), (2, 3), (4, 5), (5, 6), (11, 12), (12, 13), (14, 15), (15, 16))


def stats(values):
    x = np.asarray(values, float).ravel()
    x = x[np.isfinite(x)]
    if not len(x):
        return {"n": 0, "mean": None, "p50": None, "p90": None, "p95": None}
    return dict(n=int(len(x)), mean=float(x.mean()), p50=float(np.median(x)),
                p90=float(np.percentile(x, 90)), p95=float(np.percentile(x, 95)))


def angle(a, b):
    n = np.linalg.norm(a, axis=-1) * np.linalg.norm(b, axis=-1)
    c = np.sum(a * b, axis=-1) / np.maximum(n, 1e-12)
    result = np.degrees(np.arccos(np.clip(c, -1, 1)))
    return np.where(n > 1e-10, result, np.nan)


def pose_angles(pose, up):
    out = {}
    for name, h, k, a, s, e, w in (("right", 1, 2, 3, 14, 15, 16),
                                   ("left", 4, 5, 6, 11, 12, 13)):
        out["knee_" + name] = angle(pose[:, h] - pose[:, k], pose[:, a] - pose[:, k])
        out["elbow_" + name] = angle(pose[:, s] - pose[:, e], pose[:, w] - pose[:, e])
        out["hip_" + name] = angle(pose[:, s] - pose[:, h], pose[:, k] - pose[:, h])
    torso = (pose[:, 11] + pose[:, 14] - pose[:, 1] - pose[:, 4]) * .5
    out["torso"] = angle(torso, np.broadcast_to(up, torso.shape))
    return out


def derivative(x, timestamps):
    if len(x) < 2:
        return np.zeros_like(x)
    return np.gradient(x, timestamps, axis=0)


def pa_error(predicted, reference):
    """Similarity Procrustes per frame, scoring only."""
    finite = np.isfinite(predicted).all(axis=(1, 2)) & np.isfinite(reference).all(axis=(1, 2))
    result = np.full(len(predicted), np.nan)
    if not finite.any():
        return result
    p, g = predicted[finite], reference[finite]
    p = p - p.mean(1, keepdims=True)
    g = g - g.mean(1, keepdims=True)
    pn = np.linalg.norm(p, axis=(1, 2), keepdims=True)
    gn = np.linalg.norm(g, axis=(1, 2), keepdims=True)
    p0, g0 = p / pn.clip(1e-12), g / gn.clip(1e-12)
    u, singular, vh = np.linalg.svd(np.swapaxes(p0, 1, 2) @ g0)
    flip = np.linalg.det(u @ vh)
    u[:, :, -1] *= flip[:, None]
    singular[:, -1] *= flip
    aligned = p0 @ (u @ vh) * singular.sum(1)[:, None, None] * gn
    result[finite] = np.linalg.norm(aligned - g, axis=-1).mean(1) * 1000
    return result


def score_pose(observations, reference, corrected_crop, uncertainty_crop, invalid,
               runtime_ms, *, start=90, damage=None, clean_raw=None):
    """Return aggregate metrics. Invalid outputs remain in all-frame errors."""
    o, ref = observations, reference
    scale = ref.metres_per_crop_unit[:, None, None]
    p = (corrected_crop - corrected_crop[:, :1]) * scale
    gt = ref.joints_m
    error = np.linalg.norm(p - gt, axis=-1) * 1000
    use = np.arange(len(p)) >= start
    if damage is None:
        damage = np.zeros((len(p), 17), bool)
    conf = o.normalized[:, :, 2]
    categories = {
        "all": np.broadcast_to(use[:, None], error.shape),
        "visible": use[:, None] & (conf >= .45) & ~damage,
        "naturally_low_confidence_proxy": use[:, None] & (conf < .30) & ~damage,
        "artificially_occluded": use[:, None] & damage,
        "assessable": use[:, None] & ~invalid,
    }
    # Visible image movement is an observation proxy, not a contact label.
    xy = o.normalized[:, :, :2] * (o.crops[:, 2, None, None] / 2)
    screen = xy + o.crops[:, None, :2]
    screen /= o.image_size[1]
    speed = np.linalg.norm(derivative(screen, o.timestamps), axis=-1)
    categories["observed_moving"] = use[:, None] & (speed > .10) & (conf >= .45)
    categories["observed_still"] = use[:, None] & (speed < .02) & (conf >= .45)
    result = {
        "mpjpe_mm": stats(error[use]),
        "limb_mpjpe_mm": stats(error[use][:, LIMBS]),
        "wrist_mpjpe_mm": stats(error[use][:, WRISTS]),
        "ankle_mpjpe_mm": stats(error[use][:, ANKLES]),
        "pa_mpjpe_mm": stats(pa_error(p, gt)[use]),
        "per_joint_mm": {name: stats(error[use, j]) for j, name in enumerate(JOINTS)},
        "categories_mm": {k: stats(error[v]) for k, v in categories.items()},
        "abstention_fraction": float(invalid[use].mean()),
        "joint_frames": int(error[use].size),
        "added_cpu_ms": stats(runtime_ms[start:]),
        "added_lookahead_frames": 0,
    }
    v, vg = derivative(p, o.timestamps), derivative(gt, o.timestamps)
    a, ag = derivative(v, o.timestamps), derivative(vg, o.timestamps)
    jerk = derivative(a, o.timestamps)
    result["velocity_error_mm_s"] = stats(np.linalg.norm(v - vg, axis=-1)[use] * 1000)
    result["acceleration_error_mm_s2"] = stats(np.linalg.norm(a - ag, axis=-1)[use] * 1000)
    result["jerk_mm_s3"] = stats(np.linalg.norm(jerk, axis=-1)[use] * 1000)
    lengths = np.stack([np.linalg.norm(p[:, c] - p[:, b], axis=-1) for b, c in LIMB_EDGES], 1)
    result["limb_length_cv"] = stats(lengths[use].std(0) / lengths[use].mean(0).clip(1e-9))
    pa, ga = pose_angles(p, ref.up_camera), pose_angles(gt, ref.up_camera)
    result["angle_error_deg"] = {k: stats(np.abs(pa[k] - ga[k])[use]) for k in pa}
    result["rep_extreme_error_deg"], result["rep_rom_error_deg"] = {}, {}
    for key in pa:
        extremes, roms = [], []
        for s, e in ref.rep_segments:
            s = max(s, start)
            if e <= s or not np.isfinite(pa[key][s:e + 1]).any():
                continue
            x, y = pa[key][s:e + 1], ga[key][s:e + 1]
            extreme = np.nanmax if key == "torso" else np.nanmin
            extremes.append(abs(extreme(x) - extreme(y)))
            roms.append(abs(np.ptp(x) - np.ptp(y)))
        result["rep_extreme_error_deg"][key] = stats(extremes)
        result["rep_rom_error_deg"][key] = stats(roms)
    # Posterior spread does not include all XS/model bias: report empirical
    # calibration, never describe the filter covariance as guaranteed accuracy.
    sigma = uncertainty_crop * ref.metres_per_crop_unit[:, None]
    ok = use[:, None] & np.isfinite(sigma) & (sigma > 0)
    per_axis = np.abs(p - gt)
    result["uncertainty_calibration"] = {
        "coordinate_95pct_coverage": float(np.mean(per_axis[ok] <= 1.96 * sigma[ok, None])) if ok.any() else None,
        "radial_error_over_sigma": stats((error / 1000 / sigma.clip(1e-12))[ok]),
        "note": "Empirical covariance calibration; model bias is not assumed covered.",
    }
    # Original image-plane support proxy, not absolute world-ground contact.
    projected = screen[:, :1] + corrected_crop[:, :, :2] * (o.crops[:, 2, None, None] / (2 * o.image_size[1]))
    p_speed = np.linalg.norm(derivative(projected, o.timestamps), axis=-1)
    still = categories["observed_still"]
    support = (13, 16, 3, 6) if o.exercise == "pushup" else (3, 6)
    result["support_image_speed_height_s"] = stats(p_speed[:, support][still[:, support]])
    result["reprojection_observation_height"] = stats(np.linalg.norm(projected - screen, axis=-1)[categories["visible"]])
    if clean_raw is not None:
        base = (clean_raw - clean_raw[:, :1]) * scale
        base_error = np.linalg.norm(base - gt, axis=-1) * 1000
        recoveries, censored = [], 0
        for j in range(17):
            ends = np.flatnonzero(damage[:-1, j] & ~damage[1:, j]) + 1
            for end in ends:
                if end < start:
                    continue
                recovered = (~invalid[:, j]) & (error[:, j] <= np.maximum(50, base_error[:, j] + 20))
                hits = [t for t in range(end, min(end + 31, len(p) - 2)) if recovered[t:t + 3].all()]
                if hits:
                    recoveries.append(float(o.timestamps[hits[0]] - o.timestamps[end]))
                else:
                    censored += 1
        result["recovery_to_original_quality_s"] = dict(stats(recoveries), censored_after_1s=censored,
            definition="3 valid frames <= max(50mm, clean raw XS error +20mm); not clinical recovery")
    return result
