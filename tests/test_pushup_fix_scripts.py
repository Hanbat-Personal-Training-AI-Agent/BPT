"""D-T3-09 MM-Fit person split and the MediaPipe -> COCO-17 keypoint CSV row (D-T3-12)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import eval_pushup_mmfit as mm  # noqa: E402
import mediapipe_pose_keypoints_csv as mpcsv  # noqa: E402


def test_mmfit_heldout_sessions_are_fixed():
    assert mm.HELD_SESSIONS == {'w00', 'w05', 'w12', 'w13', 'w19', 'w20'}


def test_mediapipe_row_maps_blazepose_to_coco17_pixels():
    class L:
        def __init__(self, k):
            self.x, self.y, self.visibility = k / 100, k / 200, 0.25
    cells = mpcsv.row(7, 0.25, [L(k) for k in range(33)], 720, 1280).split(',')
    assert cells[:4] == ['7', '0.2500', '', ''] and len(cells) == 4 + 17 * 3
    # COCO left shoulder (5) <- BlazePose 11, right ankle (16) <- 28; confidence = visibility
    assert abs(float(cells[4 + 5 * 3]) - 0.11 * 720) < 1e-3 and abs(float(cells[4 + 16 * 3 + 1]) - 0.14 * 1280) < 1e-3
    assert float(cells[4 + 16 * 3 + 2]) == 0.25
    assert set(mpcsv.row(0, 0, None, 720, 1280).split(',')[4:]) == {'0.0000'}
