"""Real-data Swift <-> Python parity of the adaptive relation constraint (no dataset in git, aggregates printed only).

pose-replay --keypoints-csv K.csv --motion3d motionagformer_xs.mlpackage --adaptive on writes <base>_3d.csv with the
constrained (c*) and adapted (a*) 3D of every frame. This feeds the same constrained poses, the frame's H36M
confidences (COCO -> H36M, as the app) and px-per-unit (person-crop side / 2, Python mirror of the normalizer) to
pose_feedback.geometry.adaptive_relations and compares.

usage: python scripts/check_adaptive_parity_replay.py --keypoints K.csv --replay-3d K_3d.csv --exercise squat|pushup|barbell_row
"""
import argparse, csv, sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / 'scripts')]
from eval_3d_angles import read_csv  # noqa: E402
from finetune_motionagformer_fit3d import mag_input  # noqa: E402
from pose_feedback.geometry.adaptive_relations import AdaptiveRelations  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--keypoints', required=True); p.add_argument('--replay-3d', required=True); p.add_argument('--exercise', required=True)
    a = p.parse_args()
    K = read_csv(a.keypoints); x, crops = mag_input(K); unit = crops[:, 2] / 2
    rows = list(csv.DictReader(open(a.replay_3d)))
    m = AdaptiveRelations(a.exercise); worst, n, fill_mismatch, filled = 0.0, 0, 0, 0
    for r in rows:
        if r['state'] not in ('ok', 'partial_3d', 'bad_3d'): continue
        t = int(r['frame'])
        C = np.array([[float(r[f'c{j}_{q}']) for q in 'xyz'] for j in range(17)])
        A = np.array([[float(r[f'a{j}_{q}']) for q in 'xyz'] for j in range(17)])
        out, rep = m.update(C, x[t, :, 2], t, float(unit[t]))
        worst = max(worst, float(np.abs(out - A).max())); n += 1
        sw = sorted(int(j) for j in r['adaptive_filled'].split()) if r['adaptive_filled'] else []
        fill_mismatch += sw != sorted(rep['filled']); filled += bool(sw)
    print(f'{Path(a.keypoints).name}: frames {n}, frames with a fill (Swift) {filled}, filled-set mismatches {fill_mismatch}, '
          f'max |Swift - Python| {worst:.2e} crop units')
    # _3d.csv holds the constrained pose at 4 decimals: Python recomputes from rounded inputs, so allow ~1e-3 and rare
    # threshold flips (deviation vs track_tol at the boundary)
    sys.exit(0 if fill_mismatch <= 0.01 * max(n, 1) and worst < 2e-3 else 1)


if __name__ == '__main__':
    main()
