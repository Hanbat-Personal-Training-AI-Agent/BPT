"""Knee hyperextension clamp for MotionAGFormer H36M17 3D output.

Reference implementation; ios/Runner/NativePose/PosePipeline/KneeHingeLimit.swift
mirrors it and both are pinned by tests/fixtures/knee_hinge_limit_cases.json.

Per leg (H36M17: hip, knee, ankle = 1,2,3 right / 4,5,6 left):
  u = knee - hip, v = ankle - knee
  a = normalize((L hip - R hip) projected onto the plane perpendicular to u)
  theta = atan2((u x v) . a, u . v)
theta > 0 is normal flexion and theta < 0 hyperextension. The sign was checked on
real MotionAGFormer-XS output (see README.md next to this file). If theta < -limit,
the shin is rotated about a, around the knee, onto theta == -limit; only the ankle
moves (it is a leaf joint in H36M17) and shin length is kept. Otherwise the input
is returned as is (same object). Elbows are deliberately not handled (README.md).

Order once the 3D path is wired: selected3D -> bone length fix (if any) -> this.
"""

import math

try:
    import numpy as np
except ModuleNotFoundError:  # pragma: no cover
    np = None


DEFAULT_LIMIT_DEG = 10.0
MIN_BONE_LENGTH = 1e-6  # model units; MotionAGFormer-XS bones are ~0.3-0.5
MIN_SIN_PARALLEL = 0.05  # |sin| below this (~2.9 deg) counts as parallel

R_HIP, L_HIP = 1, 4
LEGS = {"right": (1, 2, 3), "left": (4, 5, 6)}


# Off by default until the portrait-normalisation fix is re-measured (README).
def clamp_knee_hyperextension(joints_3d, limit_deg=DEFAULT_LIMIT_DEG, enabled=False):
    """Return (joints, report) for one H36M17 [17,3] frame.

    report[leg] = {"theta_deg": float | None, "corrected": bool,
                   "correction_deg": float, "degenerate": bool}
    theta_deg is the angle before correction; correction_deg is how far the shin
    was rotated (>= 0, towards flexion).
    """
    if np is None:  # pragma: no cover
        raise ImportError("numpy is required for the knee hinge limit")
    j = np.asarray(joints_3d, dtype="float64")
    if j.shape != (17, 3):
        raise ValueError("joints_3d must have shape (17, 3)")
    out = joints_3d
    report = {}
    for leg, (hip, knee, ankle) in LEGS.items():
        theta, axis = _knee_theta(j, hip, knee, ankle)
        entry = {"theta_deg": theta, "corrected": False, "correction_deg": 0.0, "degenerate": theta is None}
        report[leg] = entry
        if not enabled or theta is None or theta >= -limit_deg:
            continue
        phi = math.radians(-limit_deg - theta)
        v = j[ankle] - j[knee]
        v_rot = (
            v * math.cos(phi)
            + np.cross(axis, v) * math.sin(phi)
            + axis * float(np.dot(axis, v)) * (1.0 - math.cos(phi))
        )
        if out is joints_3d:
            out = j.copy()
        out[ankle] = j[knee] + v_rot
        entry["corrected"] = True
        entry["correction_deg"] = -limit_deg - theta
    return out, report


def knee_theta_deg(joints_3d, leg):
    """Signed knee flexion in degrees for "left"/"right", or None if degenerate."""
    return _knee_theta(np.asarray(joints_3d, dtype="float64"), *LEGS[leg])[0]


def _knee_theta(j, hip, knee, ankle):
    u = j[knee] - j[hip]
    v = j[ankle] - j[knee]
    lr = j[L_HIP] - j[R_HIP]
    nu, nv, nl = (float(np.linalg.norm(x)) for x in (u, v, lr))
    if nu < MIN_BONE_LENGTH or nv < MIN_BONE_LENGTH or nl < MIN_BONE_LENGTH:
        return None, None
    u_hat = u / nu
    a = lr - u_hat * float(np.dot(lr, u_hat))
    na = float(np.linalg.norm(a))
    if na < MIN_SIN_PARALLEL * nl:  # pelvis axis ~ parallel to thigh
        return None, None
    a /= na
    # Shin along the hinge axis has no defined flexion angle.
    if float(np.linalg.norm(v - a * float(np.dot(v, a)))) < MIN_SIN_PARALLEL * nv:
        return None, None
    theta = math.degrees(math.atan2(float(np.dot(np.cross(u, v), a)), float(np.dot(u, v))))
    return theta, a
