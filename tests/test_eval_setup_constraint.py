"""scripts/eval_setup_constraint.py engine pieces on synthetic data: partial XS recompute, 2D damage, episode schedule."""
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT)]
import eval_setup_constraint as E  # noqa: E402


def fake_xs(windows):
    """Stand-in model: output row r = cumulative mean of the input xy over the window (depends on every frame)."""
    xy = windows[..., :3].astype(float)
    return np.cumsum(xy, axis=1) / np.arange(1, xy.shape[1] + 1)[None, :, None, None]


def test_partial_recompute_equals_full_recompute():
    rng = np.random.default_rng(0)
    x = rng.normal(size=(120, 17, 3)).astype(np.float32)
    clean, _ = E.rows_partial(fake_xs, None, x, np.ones(120, bool), np.zeros((120, 17, 3)))
    x2 = x.copy(); x2[50:60, 6] += 1.0                      # one damaged episode
    changed = np.abs(x2 - x).max((1, 2)) > 0
    part, n = E.rows_partial(fake_xs, None, x2, changed, clean)
    full, _ = E.rows_partial(fake_xs, None, x2, np.ones(120, bool), np.zeros((120, 17, 3)))
    np.testing.assert_allclose(part, full, atol=1e-6)
    assert n == 10 + E.WIN - 1  # frames whose window [t+5-26, t+5] touches 50..59
    rows = E.rows_at(fake_xs, None, x2, [0, 55, 119])
    np.testing.assert_allclose(np.stack([rows[0], rows[55], rows[119]]), full[[0, 55, 119]], atol=1e-6)


def test_damage_models_and_schedule():
    rng = np.random.default_rng(1)
    K = np.zeros((100, 17, 3)); K[..., 2] = 0.9
    K[:, :, 0] = np.arange(17)[None] * 10.0; K[:, :, 1] = np.arange(100)[:, None]  # every joint moves down 1 px/frame
    eps = [(10, 20, [9], 'freeze'), (40, 50, [15], 'mirror'), (70, 80, [13], 'keep')]
    D = E.corrupt(K, eps, rng)
    for s, e, (j,), _ in eps:
        assert (D[s:e, j, 2] >= 0.05).all() and (D[s:e, j, 2] <= 0.25).all()
    np.testing.assert_array_equal(D[10:20, 9, :2], np.repeat(K[9:10, 9, :2], 10, 0))      # stuck at the last value
    assert np.linalg.norm(D[40:50, 15, :2] - K[40:50, 16, :2], axis=-1).max() < 0.5 * 10   # snapped to the other ankle
    np.testing.assert_array_equal(D[70:80, 13, :2], K[70:80, 13, :2])                      # right place, low confidence
    untouched = np.ones(100, bool); untouched[10:20] = untouched[40:50] = untouched[70:80] = False
    np.testing.assert_array_equal(D[untouched], K[untouched])
    sched = E.schedule(0, 400, 60, np.random.default_rng(2))
    assert all(b - a == 60 for a, b in sched) and all(n[0] - p[1] >= 45 for p, n in zip(sched, sched[1:]))
    assert sched[-1][1] + E.RECOVERY <= 400
