"""Recompute own/scan comparison from saved arrays on Home; no image or GPU use.

Example (Home only): python audit_saved_comparison.py --run ~/bpt-runs/deep-test/20261024-p2-row3-cam2
This is a triangulation proxy comparison, NOT an accuracy or personalisation acceptance test.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

PAIRS = {1: 'right_hip', 2: 'right_knee', 3: 'right_ankle', 4: 'left_hip', 5: 'left_knee', 6: 'left_ankle',
         11: 'left_shoulder', 12: 'left_elbow', 13: 'left_wrist', 14: 'right_shoulder', 15: 'right_elbow', 16: 'right_wrist'}


def align(p, g, scale):
    p, g0 = p - p.mean(0), g - g.mean(0)
    u, s, vt = np.linalg.svd(p.T @ g0)
    d = np.array([1, 1, np.sign(np.linalg.det(u @ vt))])
    factor = np.sum(s * d) / np.sum(p ** 2) if scale else 1
    return factor * p @ u @ np.diag(d) @ vt + g.mean(0)


def angles(j):
    index = {h: i for i, h in enumerate(PAIRS)}
    output = []
    for a, b, c in [(1, 2, 3), (4, 5, 6), (14, 1, 2), (11, 4, 5), (14, 15, 16), (11, 12, 13)]:
        u, v = j[:, index[a]] - j[:, index[b]], j[:, index[c]] - j[:, index[b]]
        output.append(np.degrees(np.arccos(np.clip(np.sum(u*v, -1) /
                      (np.linalg.norm(u, axis=-1)*np.linalg.norm(v, axis=-1)), -1, 1))))
    return np.array(output)


def audit(run, labels):
    with np.load(labels / 'geometry/triangulated_3d.npz', allow_pickle=False) as tri:
        names = json.loads((labels / 'geometry/metadata.json').read_text())['source_joint_names']
        indices = [names.index(n) for n in PAIRS.values()]
        gt = tri['keypoints_3d'][:, indices]
        valid = tri['valid_mask'][:, indices].all(1)
    with np.load(labels / 'smpl_fit/smpl_fit.npz', allow_pickle=False) as fit:
        scale = float(fit['scale_arbitrary_to_meters'])
    gt = gt / scale  # producer's scale convention; multiplication is not the metre conversion
    expected = json.loads((run / 'out/compare_beta.json').read_text())
    rows = {}
    with np.load(run / 'out/gvhmr/result.npz', allow_pickle=False) as saved:
        for key, name in [('h36m17_world_gvhmr_beta', 'gvhmr_own_beta'), ('h36m17_world', 'scan_beta')]:
            pred = saved[key][:, list(PAIRS)]
            n = min(len(pred), len(gt)); ok = valid[:n]
            p, g = pred[:n][ok], gt[:n][ok]
            row = {field: round(float(np.mean([np.linalg.norm(align(a, b, scaled)-b, axis=-1).mean()
                    for a, b in zip(p, g)]))*1000, 1)
                    for field, scaled in [('rigid_mpjpe_mm', False), ('pa_mpjpe_mm', True)]}
            row['angle_err_mean_deg'] = round(float(np.nanmean(np.abs(angles(p)-angles(g)))), 2)
            row['matches_saved'] = all(row[k] == expected['variants'][name][k] for k in row)
            rows[name] = row
    manifest = json.loads((run / 'manifest.json').read_text())['sha256']
    checks = {}
    for name in ['out/compare_beta.json', 'out/gvhmr/result.npz', 'out/report.json']:
        checks[name] = hashlib.sha256((run/name).read_bytes()).hexdigest() == manifest[name]
    return {'reference': 'triangulation_proxy_not_ground_truth', 'frames': int(ok.sum()),
            'scanInterpretation': 'same_person_not_independently_verified_not_personalisation_proof',
            'scaleOperation': 'divide', 'thighLengthMeters': round(float(np.nanmedian(
                np.linalg.norm(gt[valid, 0]-gt[valid, 1], axis=-1))), 4),
            'variants': rows, 'savedHashesMatch': checks}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--labels', type=Path, default=Path.home()/'bpt-smpl/ex3d/exercise3d_labels/barbellrow_0003')
    args = parser.parse_args()
    print(json.dumps(audit(args.run, args.labels), indent=2))
