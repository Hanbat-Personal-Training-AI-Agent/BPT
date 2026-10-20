"""Swift <-> Python parity fixtures for AdaptiveRelations and ExerciseSetup (synthetic sequences only, no dataset).

  tests/fixtures/adaptive_relations_cases.json  (AdaptiveRelationConstraint.swift)
  tests/fixtures/exercise_setup_cases.json      (ExerciseSetup.swift)
  tests/fixtures/wrist_anchor_cases.json        (WristFloorAnchor.swift)
usage: python scripts/make_setup_constraint_fixtures.py   (bpt-eval; rewrite after changing either module)
"""
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pose_feedback.body.exercise_setup import ExerciseSetup  # noqa: E402
from pose_feedback.geometry.adaptive_relations import RELATIONS, AdaptiveRelations  # noqa: E402
from pose_feedback.geometry.wrist_anchor import WristFloorAnchor  # noqa: E402


def body(t, rng, exercise, noise=0.003):
    """A moving H36M17 body in crop units: pelvis bobbing, knees / elbows flexing, noise; feet / hands fixed in the
    camera frame (so they move in pelvis-relative coordinates)."""
    drop = 0.15 * (1 - np.cos(2 * np.pi * t / 40))
    P = np.zeros((17, 3))
    P[1], P[4] = [-0.1, 0, 0.02], [0.1, 0, -0.02]
    P[7], P[8], P[9], P[10] = [0, -0.25, 0], [0, -0.5, 0.02], [0, -0.6, 0.03], [0, -0.7, 0.04]
    P[11], P[14] = [0.17, -0.5, 0.0], [-0.17, -0.5, 0.0]
    P[12], P[15] = [0.2, -0.25, 0.1 + drop], [-0.2, -0.25, 0.1 + drop]
    hands = np.array([[0.22, -0.05, 0.25], [-0.22, -0.05, 0.25]])
    feet = np.array([[0.2, 0.9, 0.05], [-0.2, 0.9, -0.05]])
    P[[2, 5]] = [[-0.16, 0.45 - drop / 2, 0.15 + drop], [0.16, 0.45 - drop / 2, 0.15 + drop]]
    P[6], P[3] = feet[0] - [0, drop, 0], feet[1] - [0, drop, 0]
    P[13], P[16] = hands[0] - [0, drop, 0], hands[1] - [0, drop, 0]
    return P + rng.normal(0, noise, P.shape)


def expect(out, frame, rep):
    """pose None = output identical to the input (observed frames must stay untouched)."""
    same = np.array_equal(out, np.array(frame["pose"]))
    return dict(pose=None if same else out.tolist(), filled={str(j): v for j, v in rep["filled"].items()}, invalid=rep["invalid"],
                events={k: v["event"] for k, v in rep["relations"].items() if v["event"]},
                established=sorted(k for k, v in rep["relations"].items() if v["state"] == "established"))


def adaptive_cases():
    cases = []
    for exercise in ("squat", "pushup", "barbell_row"):
        rng = np.random.default_rng(7)
        frames = []
        for t in range(150):
            P = body(t, rng, exercise); c = np.full(17, 0.85) + rng.normal(0, 0.02, 17)
            if 40 <= t < 52: c[6] = 0.12; P[6] += [0.3, -0.1, 0.2]          # short occlusion, XS wrong
            if 60 <= t < 70: c[13] = 0.4                                     # partial confidence
            if 75 <= t < 85: P[3] += [0.004 * (t - 75), 0, 0]                # observed gradual shift
            if t >= 85: P[3] += [0.04, 0, 0]
            if 95 <= t < 140: c[3] = 0.05; P[3] += [0.2, 0.1, 0]             # long occlusion -> expiry
            if 95 <= t < 140: c[16] = 0.05                                   # hidden wrist: flagged only with a hands relation
            frame = t + (3 if t > 120 else 0)                                # a gap in frame indices
            frames.append(dict(pose=P.tolist(), conf=c.tolist(), frame=frame, unit=180.0 + (20.0 if t > 100 else 0.0)))
        frames = _round(frames)  # the Swift test feeds exactly these values
        m = AdaptiveRelations(exercise, max_gap_frames=30)
        exp = []
        for f in frames:
            out, rep = m.update(np.array(f["pose"]), f["conf"], f["frame"], f["unit"])
            exp.append(expect(out, f, rep))
        cases.append(dict(exercise=exercise, params=dict(max_gap_frames=30), frames=frames, expected=exp))
    # seeded (variant F): reference given at frame 0, no online init
    rng = np.random.default_rng(3)
    frames = [dict(pose=body(t, rng, "squat").tolist(), conf=[0.9] * 17, frame=t, unit=200.0) for t in range(30)]
    for f in frames[10:20]:
        f["conf"][3] = 0.1
    frames = _round(frames)
    m = AdaptiveRelations("squat", init_frames=10 ** 6)
    m.seed_reference("feet", [80.0, 0.0, 20.0], 5.0)
    exp = []
    for f in frames:
        out, rep = m.update(np.array(f["pose"]), f["conf"], f["frame"], f["unit"])
        exp.append(expect(out, f, rep))
    cases.append(dict(exercise="squat", params=dict(init_frames=10 ** 6), seed=dict(name="feet", ref=[80.0, 0.0, 20.0], spread=5.0),
                      frames=frames, expected=exp))
    return dict(relations={k: [list(r) for r in v] for k, v in RELATIONS.items()}, cases=cases)


COCO_H36M = ((5, 11), (6, 14), (7, 12), (8, 15), (9, 13), (10, 16), (11, 4), (12, 1), (13, 5), (14, 2), (15, 6), (16, 3))


def setup_cases():
    cases = []
    for exercise, ref in (("squat", {"feet_width": 2.4}), ("pushup", {"hand_width": 1.0}), ("barbell_row", {}), ("squat", {})):
        side = len(cases) == 3  # 4th case: squat seen side-on, XS's depth guess of the left ankle wobbling
        rng = np.random.default_rng(11)
        frames = []
        for t in range(110):
            P = body(0, rng, exercise, noise=0.0005); c = np.full(17, 0.9)
            if side:
                P[:, 0], P[:, 2] = -P[:, 2].copy(), P[:, 0].copy()
                P[6, 2] += 0.04 * (t % 3 - 1)
            if t < 20: P[6] += [0.05 * (t % 3), 0, 0]   # fidgeting
            if 30 <= t < 33: c[6] = 0.2                  # feet lost briefly
            if 85 <= t < 88: c[4] = 0.4                  # far hip half seen: torso still from the near side
            if side and 60 <= t < 64: c[6] = 0.4         # side view: far ankle half seen, the side-on width does not block
            fr = dict(pose=P.tolist(), conf=c.tolist(), usable=not (45 <= t < 47), unit=200.0)
            drop = 4.0 * max(0, t - 90)                  # the body sinking in the image, 3D unchanged
            px = lambda v: [v[0] * 200 + 360, v[1] * 200 + 640 + drop]
            coco = [[0.0, 0.0, 0.9] for _ in range(17)]
            for cj, hj in COCO_H36M:
                coco[cj] = px(P[hj]) + [float(c[hj])]
            fr["coco2d"] = coco  # COCO17 2D (px) every frame; Halpe26 feet only off push-up (push-up = COCO17 model)
            if exercise != "pushup":
                lf, rf = px(P[6]), px(P[3])
                fr["feet"] = {"left_heel": [lf[0] - 2, lf[1] + 9, 0.8], "right_heel": [rf[0] + 2, rf[1] + 9, 0.8],
                              "left_big_toe": [lf[0] + 14 + t % 3, lf[1] + 14, 0.25 if 60 <= t < 62 else 0.7],
                              "right_big_toe": [rf[0] - 14, rf[1] + 14, 0.7]}
            frames.append(fr)
        frames = _round(frames)
        s = ExerciseSetup(exercise, reference=ref)
        exp = []
        for f in frames:
            r = s.update(np.array(f["pose"]) if f["usable"] else None, f["conf"], usable=f["usable"], unit=f["unit"],
                         feet={k: tuple(v) for k, v in f["feet"].items()} if "feet" in f else None, coco2d=f.get("coco2d"))
            exp.append(r)
        seeds = {k: [v[0].tolist(), v[1]] for k, v in s.seeds(RELATIONS[exercise]).items()} if s.window else {}
        cases.append(dict(exercise=exercise, reference=ref, frames=frames, expected=exp, ready=s.ready, seeds=seeds))
    return dict(cases=cases)


def wrist_cases():
    """Push-up 2D (COCO17 px): hands planted, jitter, a slide, flying frames, low confidence, an unseen elbow, a moved
    hand; two parameter sets."""
    cases = []
    for params in (dict(), dict(radius=0.4, conf=0.4, reanchor_frames=12, init_frames=8)):
        rng = np.random.default_rng(5)
        frames = []
        for t in range(200):
            K = np.zeros((17, 3)); K[:, 2] = 0.85
            K[:, :2] = rng.normal(0, 1.5, (17, 2)) + np.array([[300.0 + 10 * j, 400.0] for j in range(17)])
            lw, rw = np.array([300.0, 600.0]), np.array([520.0, 600.0])
            if 60 <= t < 100: lw += [0.6 * (t - 60), 0]           # slow slide (24 px over 40 frames)
            if t >= 100: lw += [24, 0]
            if 110 <= t < 116: lw += [150, -220]                   # flies off
            if 120 <= t < 125: K[9, 2] = 0.05                      # not observed
            if 130 <= t < 133: K[7, 2] = 0.1                       # elbow unseen (no effect once anchored)
            if t >= 150: rw += [150, 0]                            # right hand put down elsewhere (1.4 forearm)
            K[9, :2] = lw + rng.normal(0, 1.5, 2); K[10, :2] = rw + rng.normal(0, 1.5, 2)
            K[7, :2] = lw + [0, -110]; K[8, :2] = rw + [0, -110]
            if t < 10: K[9, :2] += [40 * (t % 2), 0]               # getting down: no reference yet
            if 22 <= t < 26: K[10, 2] = 0.4                        # half seen: no reference from these
            frames.append(K.tolist())
        frames = _round(frames)
        active = [t >= 20 for t in range(len(frames))]             # the set starts (rep 1 counted) at frame 20
        a = WristFloorAnchor(**params)
        exp = []
        for K, on in zip(frames, active):
            out, rep = a.update(np.array(K), active=on)
            exp.append(dict(out=out[[9, 10]].tolist(), states=[rep[9], rep[10]]))
        cases.append(dict(params=params, frames=frames, active=active, expected=exp))
    return dict(cases=cases)


def _round(x):
    """Inputs and expectations both rounded to 1e-7: the Swift test feeds the rounded inputs and compares at 1e-6."""
    if isinstance(x, float): return round(x, 7)
    if isinstance(x, dict): return {k: _round(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)): return [_round(v) for v in x]
    return x


def main():
    out = ROOT / "tests/fixtures"
    (out / "adaptive_relations_cases.json").write_text(json.dumps(_round(adaptive_cases())))
    (out / "exercise_setup_cases.json").write_text(json.dumps(_round(setup_cases())))
    (out / "wrist_anchor_cases.json").write_text(json.dumps(_round(wrist_cases())))
    print("wrote", out / "adaptive_relations_cases.json", out / "exercise_setup_cases.json", out / "wrist_anchor_cases.json")


if __name__ == "__main__":
    main()
