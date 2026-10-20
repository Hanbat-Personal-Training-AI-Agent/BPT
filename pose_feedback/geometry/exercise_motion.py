"""Causal experimental motion/contact estimator; no model, labels or GT access.

Inputs are root-relative XS coordinates converted to image-height units and
matching H36M image coordinates. See docs/experiments/motion_contact_contract.md.
Contact depth is never locked. Predicted/strongly corrected joints carry explicit
uncertainty and assessment invalidation; raw observations are always preserved.
"""
from collections import deque
import numpy as np


EDGES = ((0, 1), (1, 2), (2, 3), (0, 4), (4, 5), (5, 6),
         (0, 7), (7, 8), (8, 9), (9, 10), (8, 11), (11, 12),
         (12, 13), (8, 14), (14, 15), (15, 16))
PARENT = {b: a for a, b in EDGES}
DISTAL = (2, 3, 5, 6, 12, 13, 15, 16)
VARIANTS = ("A", "B", "C", "D", "E", "F", "G", "H", "HOLD")


def _leg(p):
    values = []
    for a, b, c in ((1, 2, 3), (4, 5, 6)):
        if np.isfinite(p[[a, b, c]]).all():
            v = np.linalg.norm(p[a] - p[b]) + np.linalg.norm(p[b] - p[c])
            if v > 1e-6:
                values.append(v)
    return float(np.median(values)) if values else None


class ContactState:
    """Image-plane support proxy, not a root-relative 3D position."""

    def __init__(self):
        self.state = "UNINITIALIZED"
        self.anchor = None
        self.history = deque(maxlen=8)
        self.candidate = deque(maxlen=5)
        self.last_seen = None
        self.last_point = None
        self.previous_point = None

    def update(self, point, reliable, now, scale, enabled):
        if not enabled:
            self.__init__()
            return
        radius, release = .035 * scale, .10 * scale
        if not reliable or not np.isfinite(point).all():
            if self.anchor is not None:
                self.state = "OCCLUDED"
                if self.last_seen is None or now - self.last_seen > .5:
                    self.anchor = None
                    self.state = "UNINITIALIZED"
                    self.history.clear()
                    self.candidate.clear()
            return
        self.last_seen = now
        self.previous_point, self.last_point = self.last_point, point.copy()
        if self.anchor is None and self.state not in ("MOVING", "REACQUIRE"):
            self.history.append(point.copy())
            if len(self.history) == 8:
                h = np.asarray(self.history)
                mid = np.median(h, axis=0)
                if np.max(np.linalg.norm(h - mid, axis=1)) <= radius:
                    self.anchor = mid
                    self.state = "CONTACT"
            return
        if self.state in ("MOVING", "REACQUIRE"):
            self.state = "REACQUIRE"
            self.candidate.append(point.copy())
            if len(self.candidate) == 5:
                h = np.asarray(self.candidate)
                mid = np.median(h, axis=0)
                if np.max(np.linalg.norm(h - mid, axis=1)) <= radius:
                    self.anchor = mid
                    self.state = "CONTACT"
                    self.candidate.clear()
            return
        if np.linalg.norm(point - self.anchor) <= release:
            self.state = "CONTACT"
            self.candidate.clear()
            return
        self.candidate.append(point.copy())
        if len(self.candidate) >= 3:
            h = np.asarray(self.candidate)[-3:]
            steps = np.diff(h, axis=0)
            stable = np.max(np.linalg.norm(h - np.median(h, axis=0), axis=1)) <= radius
            coherent = (np.dot(steps[0], steps[1]) >= 0
                        and np.max(np.linalg.norm(steps, axis=1)) <= .25 * scale)
            if stable or coherent:
                self.anchor = None
                self.state = "MOVING"
                self.history.clear()
                self.candidate.clear()


class ExerciseMotionEstimator:
    def __init__(self, exercise, variant="G", bone_profile=None,
                 calibration_confidence=0.0):
        if variant not in VARIANTS:
            raise ValueError(f"Unknown variant {variant}")
        self.exercise = exercise.replace("-", "_")
        if self.exercise not in ("pushup", "squat", "barbell_row"):
            raise ValueError(f"Unsupported exercise {exercise}")
        self.variant = variant
        self.bone_profile = dict(bone_profile or {})
        self.calibration_confidence = float(np.clip(calibration_confidence, 0, 1))
        self.reset()

    def set_bone_profile(self, bone_profile, calibration_confidence):
        """Explicit calibration update; callers enforce source/time provenance."""
        profile = {}
        for edge, ratio in bone_profile.items():
            if edge not in {f"{a}-{b}" for a, b in EDGES}:
                raise ValueError(f"Unknown bone {edge}")
            if not np.isfinite(ratio) or ratio <= 0:
                raise ValueError("Bone ratios must be finite and positive")
            profile[edge] = float(ratio)
        self.bone_profile = profile
        self.calibration_confidence = float(np.clip(calibration_confidence, 0, 1))

    def reset(self):
        self.p = np.zeros((17, 3))
        self.v = np.zeros((17, 3))
        self.p00 = np.zeros(17)
        self.p01 = np.zeros(17)
        self.p11 = np.zeros(17)
        self.initialized = np.zeros(17, dtype=bool)
        self.last_seen = np.full(17, -np.inf)
        self.last_observed = np.full((17, 3), np.nan)
        self.previous_screen = np.full((17, 2), np.nan)
        self.candidate_raw = np.full((17, 3), np.nan)
        self.candidate_count = np.zeros(17, dtype=int)
        self.time = None
        self.person_id = None
        self.scale = .3
        self.contacts = {j: ContactState() for j in
                         ((3, 6, 13, 16) if self.exercise == "pushup" else (3, 6))}
        self.grip_history = deque(maxlen=8)
        self.grip_reference = None
        self.grip_seen = None
        self.previous_phase_distance = None
        self.phase_speed = 0.
        self.phase = "unknown"
        self.phase_elbow_position = {}
        self.phase_elbow_velocity = {}

    def _phase(self, raw, conf, dt):
        # Distance-to-shoulder trend is available now; no rep/phase labels.
        if self.exercise != "barbell_row":
            self.phase = "unknown"
            return False
        elbow_turning = False
        for j in (12, 15):
            if conf[j] < .45 or not np.isfinite(raw[j]).all():
                self.phase_elbow_position.pop(j, None)
                self.phase_elbow_velocity.pop(j, None)
                continue
            previous = self.phase_elbow_position.get(j)
            if previous is not None:
                velocity = (raw[j] - previous) / dt
                old = self.phase_elbow_velocity.get(j, np.zeros(3))
                old_norm, norm = np.linalg.norm(old), np.linalg.norm(velocity)
                if (old_norm > .1 * self.scale and norm > .05 * self.scale
                        and np.linalg.norm(raw[j] - previous) < .1 * self.scale
                        and np.dot(old, velocity) < -.2 * old_norm * norm):
                    elbow_turning = True
                self.phase_elbow_velocity[j] = .5 * old + .5 * velocity
            self.phase_elbow_position[j] = raw[j].copy()
        if (np.min(conf[[11, 13, 14, 16]]) < .45
                or not np.isfinite(raw[[11, 13, 14, 16]]).all()):
            self.previous_phase_distance = None
            self.phase_speed = 0.
            self.phase = "transition" if elbow_turning else "unknown"
            return elbow_turning
        distance = .5 * (np.linalg.norm(raw[13] - raw[11])
                         + np.linalg.norm(raw[16] - raw[14]))
        turning = elbow_turning
        if self.previous_phase_distance is not None:
            speed = (distance - self.previous_phase_distance) / dt
            turning |= speed * self.phase_speed < 0 and abs(self.phase_speed) > .1 * self.scale
            self.phase_speed = .5 * self.phase_speed + .5 * speed
            self.phase = ("transition" if turning or abs(self.phase_speed) < .05 * self.scale
                          else "pulling" if self.phase_speed < 0 else "lowering")
        self.previous_phase_distance = float(distance)
        return turning

    def update(self, raw, screen2d, timestamp, *, fixed_camera=False,
               camera_motion=False, person_id=0, phase=None, grip_confirmed=False):
        raw = np.asarray(raw, dtype=float).copy()
        screen = np.asarray(screen2d, dtype=float)
        if raw.shape != (17, 3) or screen.shape != (17, 3):
            raise ValueError("raw and screen2d must both be H36M [17,3]")
        now = float(timestamp)
        if not np.isfinite(now):
            raise ValueError("Timestamp must be finite")
        if (camera_motion or (self.person_id is not None and self.person_id != person_id)
                or (self.time is not None and (now <= self.time or now - self.time > .5))):
            if self.person_id is not None and self.person_id != person_id:
                self.bone_profile = {}
                self.calibration_confidence = 0.
            self.reset()
        dt = 1 / 30 if self.time is None else max(1e-4, now - self.time)
        self.time, self.person_id = now, person_id
        scale = _leg(raw)
        if scale is not None:
            # A robust pose scale is a tolerance unit, not a GT metric scale.
            self.scale = max(scale, 1e-4)
        s = self.scale
        conf = np.nan_to_num(np.clip(screen[:, 2], 0, 1))
        finite = np.isfinite(raw).all(axis=1) & np.isfinite(screen[:, :2]).all(axis=1)
        measured = finite & (conf >= .3)
        reliable = finite & (conf >= .45)
        variant = self.variant
        adaptive = variant in ("G", "H")
        kalman = variant in ("D", "E", "G", "H")
        contact_enabled = variant in ("F", "G", "H")
        kin_enabled = variant in ("E", "G", "H") and self.calibration_confidence > 0
        turning = self._phase(raw, conf, dt) if variant == "H" else False
        if phase in ("pulling", "transition", "lowering") and variant == "H":
            self.phase = phase
            turning |= phase == "transition"
        if turning:
            self.v[[12, 13, 15, 16]] *= .3

        pred = self.p + dt * self.v
        accepted = measured.copy()
        innovation = np.linalg.norm(raw - pred, axis=1)
        rejected = np.zeros(17, dtype=bool)
        if adaptive:
            for j in range(17):
                if not (self.initialized[j] and measured[j] and innovation[j] > .25 * s):
                    self.candidate_count[j] = 0
                    continue
                delta2 = screen[j, :2] - self.previous_screen[j]
                delta3 = raw[j, :2] - self.last_observed[j, :2]
                agreement = (np.isfinite(delta2).all() and np.isfinite(delta3).all()
                             and np.linalg.norm(delta2) > .01 * s
                             and np.dot(delta2, delta3) > 0)
                parent = PARENT.get(j)
                plausible = True
                if parent is not None and np.isfinite(self.last_observed[[j, parent]]).all():
                    old_length = np.linalg.norm(self.last_observed[j] - self.last_observed[parent])
                    new_length = np.linalg.norm(raw[j] - raw[parent])
                    plausible = .4 * old_length <= new_length <= 1.8 * max(old_length, 1e-6)
                persistent = (np.isfinite(self.candidate_raw[j]).all()
                              and np.linalg.norm(raw[j] - self.candidate_raw[j]) < .12 * s)
                self.candidate_count[j] = (self.candidate_count[j] + 1
                                           if reliable[j] and plausible and (agreement or persistent)
                                           else 0)
                self.candidate_raw[j] = raw[j]
                accepted[j] = self.candidate_count[j] >= 3
                rejected[j] = not accepted[j]
                if accepted[j]:
                    # Reliable relocation releases stale prediction immediately.
                    pred[j] = raw[j]
                    self.v[j] = 0
                    self.p00[j] = (.03 * s) ** 2
        trusted = reliable & accepted
        passthrough = trusted & adaptive
        corrected = raw.copy()
        used_prediction = np.zeros(17, dtype=bool)
        uncertainty = (.015 + .10 * (1 - conf)) * s
        for j in range(17):
            if not self.initialized[j]:
                if measured[j]:
                    self.p[j] = raw[j]
                    pred[j] = raw[j]
                    self.last_observed[j] = raw[j]
                    self.last_seen[j] = now
                    self.p00[j], self.p11[j] = (.03 * s) ** 2, (.5 * s) ** 2
                    self.initialized[j] = True
                else:
                    uncertainty[j] = s
                    continue
            elapsed = now - self.last_seen[j]
            if kalman:
                acc2 = (1.5 * s) ** 2
                pp = self.p00[j] + 2 * dt * self.p01[j] + dt * dt * self.p11[j] + acc2 * dt**4 / 4
                pv = self.p01[j] + dt * self.p11[j] + acc2 * dt**3 / 2
                vv = self.p11[j] + acc2 * dt**2
                self.p[j] = pred[j]
                if accepted[j]:
                    std = ((.015 + .10 * (1 - conf[j])) if adaptive else .03) * s
                    den = pp + std * std
                    kp, kv = pp / den, pv / den
                    residual = raw[j] - pred[j]
                    self.p[j] += kp * residual
                    self.v[j] += kv * residual
                    self.p00[j] = max(0., (1 - kp) * pp)
                    self.p01[j] = (1 - kp) * pv
                    self.p11[j] = max(0., vv - kv * pv)
                else:
                    self.p00[j], self.p01[j], self.p11[j] = pp, pv, vv
                    used_prediction[j] = True
                # v2: a confirmed current observation is the position authority.
                # Kalman velocity/covariance remain useful for the next occlusion,
                # but cannot smooth genuine observed motion or posture errors.
                if passthrough[j]:
                    self.p[j] = raw[j]
                corrected[j] = self.p[j]
                uncertainty[j] = np.sqrt(max(self.p00[j], 0))
            elif variant == "B":
                if finite[j]:
                    alpha = 1 - np.exp(-dt / .08)
                    self.p[j] += alpha * (raw[j] - self.p[j])
                corrected[j] = self.p[j]
                used_prediction[j] = not finite[j]
            elif variant in ("C", "HOLD"):
                if measured[j]:
                    if np.isfinite(self.last_observed[j]).all() and elapsed > 1e-4:
                        velocity = (raw[j] - self.last_observed[j]) / elapsed
                        norm = np.linalg.norm(velocity)
                        self.v[j] = velocity * min(1., 3 * s / max(norm, 1e-9))
                    self.p[j] = raw[j]
                else:
                    if variant == "C":
                        # Stop extrapolating after the stated bounded horizon.
                        step = max(0., min(dt, .35 - max(0., elapsed - dt)))
                        self.p[j] += self.v[j] * step
                    used_prediction[j] = True
                corrected[j] = self.p[j]
                uncertainty[j] = (.03 + .5 * elapsed) * s
            else:
                if measured[j]:
                    self.p[j] = raw[j]
            if accepted[j]:
                self.last_seen[j] = now
                self.last_observed[j] = raw[j]
            if finite[j]:
                self.previous_screen[j] = screen[j, :2]

        support_available = bool(fixed_camera and not camera_motion)
        leg2d = _leg(screen[:, :2]) or .3
        contact_used = []
        # Robust instantaneous weak-perspective scale uses observations only.
        ratios = []
        for a, b in EDGES:
            d2 = np.linalg.norm(screen[a, :2] - screen[b, :2])
            if trusted[a] and trusted[b] and d2 > .02 * leg2d:
                ratios.append(np.linalg.norm(raw[a, :2] - raw[b, :2]) / d2)
        xy_scale = float(np.median(ratios)) if len(ratios) >= 4 else None
        for j, contact in self.contacts.items():
            contact.update(screen[j, :2], trusted[j], now,
                           leg2d, contact_enabled and support_available)
            if (contact_enabled and support_available and not accepted[j]
                    and contact.anchor is not None and contact.state == "OCCLUDED"
                    and trusted[0] and xy_scale is not None
                    and now - contact.last_seen <= .35 and self.initialized[j]):
                target = (contact.anchor - screen[0, :2]) * xy_scale
                # Only XY; no invented global root or fixed contact depth.
                delta = target - corrected[j, :2]
                if np.isfinite(delta).all():
                    corrected[j, :2] += delta * min(1., .10 * s / max(np.linalg.norm(delta), 1e-9))
                    uncertainty[j] = max(uncertainty[j], .10 * s)
                    used_prediction[j] = True
                    contact_used.append(j)

        kinematic_used = []
        if kin_enabled:
            for j in DISTAL:
                a = PARENT[j]
                ratio = self.bone_profile.get(f"{a}-{j}")
                if ratio is None or reliable[j] or not trusted[a] or not np.isfinite(corrected[[a, j]]).all():
                    continue
                target = float(ratio) * s
                if not np.isfinite(target) or target <= 0:
                    continue
                vector = corrected[j] - corrected[a]
                length = np.linalg.norm(vector)
                tolerance = .15 + .25 * (1 - self.calibration_confidence)
                desired = np.clip(length, target * (1 - tolerance), target * (1 + tolerance))
                if length > 1e-8 and abs(length - desired) > 1e-8:
                    correction = vector * (desired / length - 1) * self.calibration_confidence
                    corrected[j] += correction * min(1., .10 * s / max(np.linalg.norm(correction), 1e-9))
                    uncertainty[j] = max(uncertainty[j], .08 * s)
                    used_prediction[j] = True
                    kinematic_used.append(j)

        if contact_enabled and self.exercise == "barbell_row" and grip_confirmed:
            if trusted[13] and trusted[16]:
                distance = float(np.linalg.norm(raw[13] - raw[16]))
                self.grip_seen = now
                if (self.grip_reference is not None
                        and not .8 * self.grip_reference <= distance <= 1.2 * self.grip_reference):
                    self.grip_reference = None
                    self.grip_history.clear()
                self.grip_history.append(distance)
                if len(self.grip_history) == 8:
                    h = np.asarray(self.grip_history)
                    if np.ptp(h) < .1 * s:
                        self.grip_reference = float(np.median(h))
            elif (self.grip_reference is not None and self.grip_seen is not None
                  and now - self.grip_seen <= .5):
                for j, other in ((13, 16), (16, 13)):
                    if not reliable[j] and trusted[other] and np.isfinite(corrected[[j, other]]).all():
                        vector = corrected[j] - corrected[other]
                        length = np.linalg.norm(vector)
                        desired = np.clip(length, .8 * self.grip_reference, 1.2 * self.grip_reference)
                        if length > 1e-8:
                            delta = vector * (desired / length - 1)
                            corrected[j] += delta * min(.5, .10 * s / max(np.linalg.norm(delta), 1e-9))
                            used_prediction[j] = True
            elif self.grip_seen is not None and now - self.grip_seen > .5:
                self.grip_reference = None
                self.grip_history.clear()
        else:
            self.grip_reference = None
            self.grip_seen = None
            self.grip_history.clear()

        age = now - self.last_seen
        uncertainty = np.maximum(uncertainty, np.where(used_prediction, (.03 + .3 * np.minimum(age, 2)) * s, 0))
        correction = np.linalg.norm(corrected - raw, axis=1)
        invalid = (~np.isfinite(corrected).all(axis=1) | ~self.initialized
                   | (age > .5) | (uncertainty > .15 * s)
                   | (correction > .08 * s) | used_prediction)
        roles = ["dynamic_joint"] * 17
        for j in range(17):
            if j in self.contacts and contact_enabled and support_available:
                roles[j] = ("contact_anchor" if self.contacts[j].state in ("CONTACT", "OCCLUDED")
                            else "dynamic_joint")
            elif j in (13, 16) and self.grip_reference is not None:
                roles[j] = "relative_anchor"
            if used_prediction[j]:
                roles[j] = "temporarily_occluded_joint"
            if not self.initialized[j] or age[j] > .5 or uncertainty[j] > .15 * s:
                roles[j] = "uncertain_joint"
        return dict(raw=raw, corrected=corrected, correction_magnitude=correction,
                    uncertainty=uncertainty, invalid=invalid, roles=roles,
                    contacts={str(j): c.state for j, c in self.contacts.items()},
                    used_prediction=used_prediction, phase=self.phase,
                    diagnostics=dict(scale=s, fixed_camera=support_available,
                                     contact_corrected=contact_used, bone_corrected=kinematic_used,
                                     rejected_joints=np.flatnonzero(rejected).tolist(),
                                     observation_passthrough=np.flatnonzero(passthrough).tolist(),
                                     observation_policy="trusted_passthrough_v2",
                                     calibration_used=kin_enabled and bool(self.bone_profile),
                                     grip_used=self.grip_reference is not None))
