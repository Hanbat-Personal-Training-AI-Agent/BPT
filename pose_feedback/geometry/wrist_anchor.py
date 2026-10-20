"""Push-up wrist floor anchor on the 2D (experimental, OFF by default) - reference.

ios/Runner/NativePose/PosePipeline/WristFloorAnchor.swift mirrors this; tests/fixtures/wrist_anchor_cases.json pins both.
Rules and how the values were chosen: docs/results/setup_constraint_prereg.md section 8 (user request 2026-10-20 21:15:
small hand moves are fine, a wrist flying off is not - the same principle as the feet).

Per wrist (COCO17 px): once the set is underway (`active`: rep >= 1 or setup ready) and the wrist and elbow were seen
reliably (confidence >= init_conf) for init_frames frames within r of each other, their median is the floor reference
(r = radius x the 2D forearm of those frames; v2: v1 also took low-confidence frames and frames before the set, and
locked onto a screen-edge guess - section 8 change log). Then an observed wrist within r is
kept and the reference follows it slowly (beta); a wrist out of r or not observed is replaced by the reference with
confidence held_conf (just under the evaluators' 0.30 joint gate: never a new observation, still the floor contact for
the push-up height samples) - "held". Observed positions out of r that stay within r/2 of each other for
reanchor_frames frames are a moved hand: the reference jumps there. The output feeds the overlay, the XS input and the
evaluators alike.
"""
import numpy as np

# radius / conf / reanchor_frames: section 8 rules on Fit3D tuning subjects s03-s05 (RTMPose-m COCO17 app 2D; Home
# 20261020-wrist-tune): mocap wrist motion p99 <= 0.21 forearm, every flying frame held at every radius, so the largest
# grid radius; 17 flying runs, none >= 15 frames. 제안값 (사용자 미승인), validation: docs/results/setup_constraint.md.
DEFAULTS = dict(conf=0.1, radius=1.0, reanchor_frames=15, init_frames=15, beta=0.05, held_conf=0.29, init_conf=0.5)
WRISTS = ((9, 7), (10, 8))  # COCO17 (wrist, elbow): left, right


class WristFloorAnchor:
    def __init__(self, **params):
        self.p = dict(DEFAULTS, **params)
        self.reset()

    def reset(self):
        self.state = {w: dict(ref=None, f=None, init=[], out=[]) for w, _ in WRISTS}

    def update(self, K, active=True):
        """K [17,3] COCO17 px (x, y, confidence) -> (K with the wrists anchored, {wrist: none|observed|held|reanchored}).
        active: the push-up set is underway (a reference is only taken then; one taken stays)."""
        K = np.asarray(K, dtype="float64")
        out, report = K.copy(), {}
        for w, e in WRISTS:
            s, seen = self.state[w], K[w, 2] >= self.p["conf"]
            if s["ref"] is None:
                report[w] = "none"
                if not active or K[w, 2] < self.p["init_conf"] or K[e, 2] < self.p["init_conf"]:
                    s["init"] = []
                    continue
                s["init"] = (s["init"] + [(K[w, :2].copy(), float(np.hypot(*(K[w, :2] - K[e, :2]))))])[-self.p["init_frames"]:]
                if len(s["init"]) == self.p["init_frames"]:
                    P = np.array([q for q, _ in s["init"]])
                    f, med = float(np.median([a for _, a in s["init"]])), np.median(P, axis=0)
                    if f > 1e-6 and np.linalg.norm(P - med, axis=1).max() <= self.p["radius"] * f:
                        s.update(ref=med, f=f, init=[], out=[])
                continue
            r = self.p["radius"] * s["f"]
            if seen and np.linalg.norm(K[w, :2] - s["ref"]) <= r:
                s["ref"] = s["ref"] + self.p["beta"] * (K[w, :2] - s["ref"])
                s["out"], report[w] = [], "observed"
                continue
            if seen:  # observed out of the radius: a jump, or the hand was put down elsewhere
                s["out"] = (s["out"] + [K[w, :2].copy()])[-self.p["reanchor_frames"]:]
                P = np.array(s["out"])
                if len(P) == self.p["reanchor_frames"] and np.linalg.norm(P - np.median(P, axis=0), axis=1).max() <= r / 2:
                    s["ref"], s["out"], report[w] = np.median(P, axis=0), [], "reanchored"
                    continue
            else:
                s["out"] = []
            out[w] = [s["ref"][0], s["ref"][1], self.p["held_conf"]]
            report[w] = "held"
        return out, report
