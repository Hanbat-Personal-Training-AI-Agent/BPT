"""Deterministic Python/Swift numerical contract, synthetic data only."""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pose_feedback.geometry.exercise_motion import ExerciseMotionEstimator, VARIANTS


def pose():
    return np.array([
        [0, 0, 0], [.08, .02, 0], [.10, .25, .01], [.12, .48, 0],
        [-.08, .02, 0], [-.10, .25, .01], [-.12, .48, 0],
        [0, -.2, 0], [0, -.4, 0], [0, -.45, 0], [0, -.52, 0],
        [-.20, -.36, 0], [-.35, -.15, 0], [-.45, .05, 0],
        [.20, -.36, 0], [.35, -.15, 0], [.45, .05, 0]])


def plain(v):
    if isinstance(v, np.ndarray):
        return v.tolist()
    if isinstance(v, np.generic):
        return v.item()
    if isinstance(v, dict):
        return {k: plain(x) for k, x in v.items()}
    if isinstance(v, (tuple, list)):
        return [plain(x) for x in v]
    return v


cases = []
for name, exercise in (("row_occlusion_turn", "barbell_row"),
                       ("pushup_relocation", "pushup"),
                       ("squat_root_motion", "squat"),
                       ("profile_reset", "barbell_row"),
                       ("low_confidence_leg_scale", "pushup"),
                       ("contact_candidate_expiry", "pushup"),
                       ("contact_reacquire_expiry", "pushup"),
                       ("covariance_reacquisition", "barbell_row")):
    frames = []
    for t in range(240 if name == "covariance_reacquisition" else 80):
        p = pose()
        confidence = np.ones(17)
        context = dict(fixed_camera=True, camera_motion=False, person_id=0,
                       grip_confirmed=name == "profile_reset")
        if name == "row_occlusion_turn":
            p[[12, 13, 15, 16], 1] -= .004 * (t if t <= 35 else 70 - t)
        if name == "pushup_relocation" and t >= 32:
            p[13, 0] += .15
        if name == "squat_root_motion":
            p[:, 1] -= .06 * np.sin(t / 15)
            p[0] = 0
        if name == "profile_reset":
            p[13, 0] -= .08
            context["person_id"] = 1 if t >= 60 else 0
        if name == "contact_reacquire_expiry" and t >= 16:
            p[13, 0] += .15
        if name == "covariance_reacquisition" and t >= 180:
            p[13, 0] += .15 + (.002 * (t - 183) if t >= 183 else 0)
        uv = p[:, :2] + [.5, .55]
        if name == "low_confidence_leg_scale" and 10 <= t <= 12:
            p[3] = [0, 100, 0]
            confidence[3] = 0.
            p[13, 0] += 1.
        if (name == "contact_candidate_expiry" and 7 <= t <= 67
                or name == "contact_reacquire_expiry" and 23 <= t <= 73):
            confidence[13] = .1
        if name == "covariance_reacquisition" and (30 <= t < 180 or t >= 210):
            confidence[13] = .05
        if name == "squat_root_motion":
            uv[[3, 6]] = pose()[[3, 6], :2] + [.5, .55]
        if name in ("row_occlusion_turn", "profile_reset") and 25 <= t <= 45:
            confidence[13] = .1
            p[13] += [.3, -.2, .2]
        if name == "pushup_relocation" and 15 <= t <= 23:
            confidence[13] = .1
            p[13] += [.3, -.2, .2]
            uv[13] += [.3, -.2]
        frames.append(dict(raw=p.tolist(), screen2d=np.column_stack((uv, confidence)).tolist(),
                           timestamp=t / 30, context=context))
    profile = {"12-13": .40, "15-16": .40, "1-2": .50, "2-3": .50}
    checks = {}
    for variant in VARIANTS:
        m = ExerciseMotionEstimator(exercise, variant, profile, .7)
        expected = {}
        checkpoints = ((0, 29, 179, 180, 181, 182, 183, 209, 210, 239)
                       if name == "covariance_reacquisition"
                       else (0, 7, 14, 23, 31, 39, 47, 59, 71, 79))
        for i, f in enumerate(frames):
            r = m.update(f["raw"], f["screen2d"], f["timestamp"], **f["context"])
            if i in checkpoints:
                expected[str(i)] = plain({k: r[k] for k in
                    ("corrected", "uncertainty", "invalid", "contacts",
                     "correction_magnitude", "used_prediction", "phase", "roles")})
        checks[variant] = expected
    cases.append(dict(name=name, exercise=exercise, bone_profile=profile,
                      calibration_confidence=.7, frames=frames, expected=checks))
source = ROOT / "pose_feedback/geometry/exercise_motion.py"
out = ROOT / "tests/fixtures/exercise_motion_cases.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(dict(schema_version=1, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                               tolerance=1e-8, cases=cases), separators=(",", ":"), allow_nan=False) + "\n")
print(out, out.stat().st_size, "bytes")
