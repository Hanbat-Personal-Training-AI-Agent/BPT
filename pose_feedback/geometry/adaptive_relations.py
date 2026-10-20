"""Confidence-aware adaptive relation constraint on the final 3D (experimental, OFF by default) - reference.

ios/Runner/NativePose/PosePipeline/AdaptiveRelationConstraint.swift mirrors this; tests/fixtures/
adaptive_relations_cases.json pins both. Rules and their evaluation: docs/results/setup_constraint_prereg.md.

Runs after Pose3DConstraints on MotionAGFormer-XS H36M17 output (pelvis-relative, camera axes, crop units). A relation
is the camera-frame vector between two joints, v = P[b] - P[a], kept in px (crop units x `unit`, so a crop change does
not change it). For two contacts that stay put (both feet on the floor, both hands on the floor or on one bar) and a
static camera, v stays constant although each joint moves in pelvis-relative coordinates: the pelvis cancels out.
This is NOT a world-frame contact constraint - XS has no global position, so a single contact point is never anchored.

  - observed joint (2D confidence >= reliable_conf): never changed, whatever the relation says.
  - a relation is established only from frames where both joints are observed (init_frames in a row whose spread is
    <= init_spread x body scale). Before that (setup) there is no constraint at all.
  - both observed: a small deviation (<= track_tol x scale) moves the reference slowly (EMA `beta`: gradual foot
    shifts are followed); reanchor_frames deviating frames in a row replace it (real motion: re-anchor, no snap back).
  - one observed, the other not: the other joint becomes w * target + (1 - w) * XS, target = anchor + reference
    (or, with ball_base set, XS pulled back onto a ball around it - only implausible XS guesses move),
    w = (1 - r) * exp(-gap / decay_frames), r = confidence ramp low_conf..reliable_conf, gap = frames since the joint
    was last observed. sigma^2 = spread^2 + growth * gap (x scale) is reported, never hidden.
  - gap > max_gap_frames: the relation no longer fills that joint (expired); with confidence < low_conf the joint is
    reported invalid (posture metrics that need it are skipped) instead of being held.
  - neither observed: no anchor, XS is kept (invalid as above when the gap is long and the confidence low).
"""
import math

import numpy as np

# H36M17
R_HIP, R_KNEE, R_ANKLE, L_HIP, L_KNEE, L_ANKLE = 1, 2, 3, 4, 5, 6
L_WRIST, R_WRIST = 13, 16

# Candidate relations per exercise (name, a, b): v = P[b] - P[a]. Fit3D mocap (E0, tuning s03-s05): during the set
# feet move 14-22 mm (squat) / 2-5 mm (row) / 23-50 mm (push-up) from their setup value, hands 31-40 mm (push-up),
# grip 27-64 mm (row: wrist centres turn around the bar), push-up hand-foot 62-109 mm (ankles roll over the toes).
RELATIONS = {
    "squat": (("feet", R_ANKLE, L_ANKLE),),
    "pushup": (("feet", R_ANKLE, L_ANKLE), ("hands", R_WRIST, L_WRIST),
               ("hand_foot_r", R_ANKLE, R_WRIST), ("hand_foot_l", L_ANKLE, L_WRIST)),
    "barbell_row": (("feet", R_ANKLE, L_ANKLE), ("hands", R_WRIST, L_WRIST)),
}

DEFAULTS = dict(reliable_conf=0.5, low_conf=0.3, init_frames=15, init_spread=0.10, track_tol=0.08, beta=0.05,
                reanchor_frames=6, decay_frames=45.0, max_gap_frames=90, growth=0.0004, scale_window=300,
                ball_base=None, ball_growth=0.0)
# ball_base (fraction of the body scale) switches the fill from "replace" to "bounded": the unobserved joint keeps its
# XS position when that is within ball_base + ball_growth * gap (x scale) of anchor + reference, and is only pulled back
# onto that ball when XS puts it farther away - a plausible XS guess is never replaced, the ball grows with the gap.


def _median(values):
    v = sorted(values)
    n = len(v)
    return v[n // 2] if n % 2 else 0.5 * (v[n // 2 - 1] + v[n // 2])


class AdaptiveRelations:
    """Stateful per set: feed frames in time order with `update` (frame indices may jump over frames without 3D)."""

    def __init__(self, exercise, relations=None, **params):
        self.p = dict(DEFAULTS, **params)
        self.relations = tuple(RELATIONS.get(exercise, ()) if relations is None else relations)
        self.reset()

    def reset(self):
        self.scale_history = []
        self.state = {name: dict(ref=None, spread=0.0, init=[], out=[]) for name, _, _ in self.relations}
        self.last_seen = {}  # joint -> frame index when last observed (the first frame stands in until then)
        self.first_frame = None

    def scale(self):
        return _median(self.scale_history) if self.scale_history else None

    def seed_reference(self, name, ref_px, spread_px=0.0):
        """Exercise setup confirmed a stable relation (px): start from it instead of waiting for init_frames."""
        st = self.state[name]
        st["ref"], st["spread"], st["init"], st["out"] = np.asarray(ref_px, dtype="float64"), float(spread_px), [], []

    def _record_scale(self, P, conf):
        legs = [np.linalg.norm(P[h] - P[k]) + np.linalg.norm(P[k] - P[a]) for h, k, a in ((R_HIP, R_KNEE, R_ANKLE), (L_HIP, L_KNEE, L_ANKLE))
                if min(conf[h], conf[k], conf[a]) >= self.p["reliable_conf"]]
        if legs:
            self.scale_history.append(float(sum(legs) / len(legs)))
            if len(self.scale_history) > self.p["scale_window"]:
                self.scale_history.pop(0)

    def update(self, P, conf, frame, unit=1.0):
        """P [17,3] crop units (after Pose3DConstraints), conf [17] H36M 2D confidences of the same frame, frame index,
        unit = px per crop unit. Returns (P_out [17,3] crop units, report)."""
        p = self.p
        X = np.asarray(P, dtype="float64") * unit
        conf = [float(c) for c in conf]
        seen = [c >= p["reliable_conf"] for c in conf]
        if self.first_frame is None:
            self.first_frame = frame
        for j in range(17):
            if seen[j]:
                self.last_seen[j] = frame
        self._record_scale(X, conf)
        s = self.scale()
        out = X.copy()
        report = dict(relations={}, filled={}, invalid=[], scale=s)
        if s is None:
            return out / unit, report
        estimates = {}  # joint -> [(estimate, w, sigma)]
        for name, a, b in self.relations:
            st = self.state[name]
            v = X[b] - X[a]
            rr = report["relations"][name] = dict(state="none", event=None, dev=None)
            if seen[a] and seen[b]:
                if st["ref"] is None:
                    st["init"].append(v)
                    if len(st["init"]) > p["init_frames"]:
                        st["init"].pop(0)
                    if len(st["init"]) == p["init_frames"]:
                        med = np.array([_median([q[i] for q in st["init"]]) for i in range(3)])
                        spread = max(float(np.linalg.norm(q - med)) for q in st["init"])
                        if spread <= p["init_spread"] * s:
                            st["ref"], st["spread"], st["init"] = med, spread, []
                            rr["event"] = "established"
                else:
                    dev = float(np.linalg.norm(v - st["ref"]))
                    rr["dev"] = dev / s
                    if dev <= p["track_tol"] * s:
                        st["ref"] = st["ref"] + p["beta"] * (v - st["ref"])
                        st["out"] = []
                    else:
                        st["out"].append(v)
                        if len(st["out"]) >= p["reanchor_frames"]:
                            st["ref"] = np.array([_median([q[i] for q in st["out"]]) for i in range(3)])
                            st["spread"] = max(float(np.linalg.norm(q - st["ref"])) for q in st["out"])
                            st["out"] = []
                            rr["event"] = "reanchored"
            elif st["ref"] is None:
                st["init"] = []  # an init run needs consecutive frames with both joints observed
            if st["ref"] is None:
                continue
            rr["state"] = "established"
            if seen[a] == seen[b]:
                continue
            anchor, other, sign = (a, b, 1.0) if seen[a] else (b, a, -1.0)
            gap = frame - self.last_seen.get(other, self.first_frame)
            if gap > p["max_gap_frames"]:
                continue
            r = min(max((conf[other] - p["low_conf"]) / (p["reliable_conf"] - p["low_conf"]), 0.0), 1.0)
            w = (1.0 - r) * math.exp(-gap / p["decay_frames"])
            sigma = math.sqrt((st["spread"] / s) ** 2 + p["growth"] * gap)
            target = X[anchor] + sign * st["ref"]
            if p["ball_base"] is not None:
                radius = (p["ball_base"] + p["ball_growth"] * gap) * s
                off = X[other] - target
                dist = float(np.linalg.norm(off))
                target = X[other] if dist <= radius else target + off * (radius / dist)
            estimates.setdefault(other, []).append((target, w, sigma))
        for j, est in estimates.items():
            w = sum(e[1] for e in est) / len(est)
            target = sum(e[0] for e in est) / len(est)
            out[j] = w * target + (1.0 - w) * X[j]
            report["filled"][j] = dict(w=w, sigma=min(e[2] for e in est), gap=frame - self.last_seen.get(j, self.first_frame))
        for j in range(17):
            if not seen[j] and conf[j] < p["low_conf"] and frame - self.last_seen.get(j, self.first_frame) > p["max_gap_frames"] \
                    and j not in report["filled"]:
                report["invalid"].append(j)
        return out / unit, report
