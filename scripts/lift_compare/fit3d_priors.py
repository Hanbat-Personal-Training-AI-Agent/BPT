"""Fit3D mocap priors for the 3D constraints (aggregates only; Home): joint-angle percentiles and bone lengths.

Angles (deg) on Fit3D joints3d_25 mapped to H36M17 (world, z up), every frame of every exercise file present:
  * ai/lift-app Pose3DConstraints limit angles, same definition: angle between (ref_to - ref_from) and
    (child - joint) for each DEFAULT_ANGLE_LIMITS row (knee/elbow flexion = interior angle, hip = trunk-up vs thigh,
    spine = interior angle at the spine joint);
  * lift-compare metric angles: knee, hip (shoulder-hip-knee), elbow interior, trunk_g (mid-hip -> mid-shoulder vs up).
Percentiles p0.1 p1 p5 p50 p95 p99 p99.9 per group (tuning s03-s05 / heldout s07-s11 / all) and per exercise group
(all exercises, and squat / pushup / barbell_row). Bones: per subject segment length (mocap skeleton is fixed per
subject: median over frames) and ratios to the thigh, plus the left/right-averaged PRIOR_LENGTHS-style ratios.

usage: fit3d_priors.py --root ~/datasets/fit3d --out priors.json
"""
import argparse, glob, json, os, sys
from pathlib import Path
import numpy as np

sys.path[:0] = [str(Path(__file__).resolve().parents[2]), str(Path(__file__).resolve().parents[1])]
from eval_3d_angles import FIT3D_TO_H36M, interior, incline  # noqa: E402
from pose_feedback.geometry.bone_lengths import H36M17_PARENTS, SEGMENT_NAMES  # noqa: E402

LIMITS = (  # copy of ai/lift-app ed67a6e pose_feedback/geometry/pose3d_constraints.py DEFAULT_ANGLE_LIMITS (names, indices)
    ("right_knee_flexion", 2, 1, 2, 3), ("left_knee_flexion", 5, 4, 5, 6),
    ("right_elbow_flexion", 15, 14, 15, 16), ("left_elbow_flexion", 12, 11, 12, 13),
    ("right_hip", 0, 8, 1, 2), ("left_hip", 0, 8, 4, 5), ("spine", 7, 0, 7, 8))
PCT = (0.1, 1, 5, 50, 95, 99, 99.9)
TUNING, HELDOUT = {'s03', 's04', 's05'}, {'s07', 's08', 's09', 's10', 's11'}


def limit_angle(J, rf, rt, j, c):
    a, b = J[:, rt] - J[:, rf], J[:, c] - J[:, j]
    return np.degrees(np.arctan2(np.linalg.norm(np.cross(a, b), axis=-1), (a * b).sum(-1)))


def angles(J):
    out = {n: limit_angle(J, *ix) for n, *ix in LIMITS}
    up = np.array([0, 0, 1.])
    for s, (h, k, a, sh, el, wr) in {'R': (1, 2, 3, 14, 15, 16), 'L': (4, 5, 6, 11, 12, 13)}.items():
        out[f'knee_{s}'] = interior(J[:, h], J[:, k], J[:, a])
        out[f'hip_{s}'] = interior(J[:, sh], J[:, h], J[:, k])
        out[f'elbow_{s}'] = interior(J[:, sh], J[:, el], J[:, wr])
    out['trunk_g'] = incline((J[:, 11] + J[:, 14]) / 2 - (J[:, 1] + J[:, 4]) / 2, up)
    return out


def main():
    p = argparse.ArgumentParser(); p.add_argument('--root', required=True); p.add_argument('--out', required=True)
    a = p.parse_args()
    acc, bones, files = {}, {}, {}
    for sd in sorted(glob.glob(f'{a.root}/train/s*')):
        subj = os.path.basename(sd); grp = 'tuning' if subj in TUNING else 'heldout' if subj in HELDOUT else 'other'
        for f in sorted(glob.glob(f'{sd}/joints3d_25/*.json')):
            ex = os.path.basename(f)[:-5]
            J = np.array(json.load(open(f))['joints3d_25'], float)[:, FIT3D_TO_H36M]
            files[subj] = files.get(subj, 0) + 1
            for name, v in angles(J).items():
                for g in (grp, 'all'):
                    for e in ('all', ex) if ex in ('squat', 'pushup', 'barbell_row') else ('all',):
                        acc.setdefault((g, e, name), []).append(v)
            L = np.linalg.norm(J[:, 1:] - J[:, H36M17_PARENTS[1:]], axis=-1)  # [N,16]
            bones.setdefault(subj, []).append(L)
    out = {'source': 'Fit3D joints3d_25 (mocap), H36M17 order, metres; non-commercial licence, aggregates only',
           'files_per_subject': files, 'percentiles': PCT, 'angles': {}, 'bones': {}}
    for (g, e, name), vs in sorted(acc.items()):
        v = np.concatenate(vs)
        out['angles'].setdefault(g, {}).setdefault(e, {})[name] = dict(n=int(len(v)), **{f'p{q}': round(float(np.percentile(v, q)), 2) for q in PCT})
    per = {}
    for subj, Ls in bones.items():
        L = np.median(np.concatenate(Ls), 0)
        cv = (np.concatenate(Ls).std(0) / np.concatenate(Ls).mean(0)).max()
        per[subj] = {'lengths_m': {SEGMENT_NAMES[i]: round(float(L[i]), 4) for i in range(16)}, 'max_cv_over_frames': round(float(cv), 4)}
    out['bones']['per_subject'] = per
    def ratio(subj, num, den): return per[subj]['lengths_m'][num] / per[subj]['lengths_m'][den]
    pairs = {'shin/thigh': ('right_knee-right_ankle', 'right_hip-right_knee'), 'upperarm/thigh': ('right_shoulder-right_elbow', 'right_hip-right_knee'),
             'forearm/thigh': ('right_elbow-right_wrist', 'right_hip-right_knee'), 'forearm/upperarm': ('right_elbow-right_wrist', 'right_shoulder-right_elbow'),
             'hipwidth/thigh': ('pelvis-right_hip', 'right_hip-right_knee'), 'spine+thorax/thigh': ('pelvis-spine', 'right_hip-right_knee'),
             'thorax-shoulder/thigh': ('thorax-right_shoulder', 'right_hip-right_knee')}
    for g, subs in (('tuning', TUNING), ('heldout', HELDOUT), ('all', set(per))):
        s = sorted(x for x in per if x in subs)
        out['bones'].setdefault('ratios', {})[g] = {
            k: {'min': round(min(ratio(x, *v) for x in s), 3), 'median': round(float(np.median([ratio(x, *v) for x in s])), 3),
                'max': round(max(ratio(x, *v) for x in s), 3), 'n_subjects': len(s)} for k, v in pairs.items()}
        # PRIOR_LENGTHS style: L/R averaged limb lengths / thigh
        lr = lambda x, a_, b_: (per[x]['lengths_m'][a_] + per[x]['lengths_m'][b_]) / 2
        out['bones'].setdefault('prior_lengths', {})[g] = {
            'thigh': 1.0,
            'shin': round(float(np.median([lr(x, 'right_knee-right_ankle', 'left_knee-left_ankle') / lr(x, 'right_hip-right_knee', 'left_hip-left_knee') for x in s])), 3),
            'upper_arm': round(float(np.median([lr(x, 'right_shoulder-right_elbow', 'left_shoulder-left_elbow') / lr(x, 'right_hip-right_knee', 'left_hip-left_knee') for x in s])), 3),
            'forearm': round(float(np.median([lr(x, 'right_elbow-right_wrist', 'left_elbow-left_wrist') / lr(x, 'right_hip-right_knee', 'left_hip-left_knee') for x in s])), 3)}
    json.dump(out, open(a.out, 'w'), indent=1)
    print(json.dumps(out['bones']['prior_lengths'], indent=1))
    print(json.dumps({k: out['angles']['all']['all'][k] for k in ('right_knee_flexion', 'right_elbow_flexion', 'right_hip', 'spine', 'trunk_g')}, indent=1))


if __name__ == '__main__':
    main()
