"""Counter parity plus independently enumerated optimal event assignment."""
import importlib.util
import itertools
from fractions import Fraction
from pathlib import Path
import sys
import unittest

import numpy as np

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE))
import eval_temporal_repetitions as temporal

# Load just the original counter's function AST: no heavyweight model imports.
import ast
node = ast.parse((BASE.parent / 'count_reps_3d_vs_2d.py').read_text())
fn = next(n for n in node.body if isinstance(n, ast.FunctionDef) and n.name == 'count')
namespace = {'np': np}
exec(compile(ast.Module(body=[fn], type_ignores=[]), '<unchanged counter>', 'exec'), namespace)
count = namespace['count']


def exhaustive(pred, ref, threshold):
    best = (0, Fraction(0), 0)
    for size in range(1, min(len(pred), len(ref)) + 1):
        for ps in itertools.combinations(range(len(pred)), size):
            for rs in itertools.permutations(range(len(ref)), size):
                pairs = list(zip(ps, rs))
                if not all(temporal.iou(pred[p], ref[r]) >= threshold for p, r in pairs):
                    continue
                objective = (size, sum(temporal.iou(pred[p], ref[r]) for p, r in pairs),
                             -sum(abs(pred[p][0] - ref[r][0]) + abs(pred[p][1] - ref[r][1]) for p, r in pairs))
                best = max(best, objective)
    return best


class CounterParity(unittest.TestCase):
    def test_empty_flat_nan_and_short(self):
        for signal in ([], [1] * 30, [np.nan] * 40, list(range(8)), [np.inf] * 10):
            self.assertEqual(len(temporal.events(signal)), count(signal))
            self.assertEqual(temporal.events(signal), [])

    def test_random_and_missing_sample_parity(self):
        rng = np.random.default_rng(20261104)
        for length in (9, 10, 31, 100, 600):
            for _ in range(30):
                signal = rng.normal(size=length).cumsum()
                signal[rng.random(length) < .15] = np.nan
                found = temporal.events(signal)
                self.assertEqual(len(found), count(signal))
                for a, b, _ in found:
                    self.assertTrue(0 <= a < b < length)

    def test_cycle_and_terminal_rule(self):
        # k=1 makes the state machine endpoints directly observable.
        signal = [1.] * 10 + [0.] * 10 + [1.] * 10
        self.assertEqual(temporal.events(signal, k=1), [(9, 20, False)])
        partial = [1.] * 10 + [0.] * 10 + [.6]
        self.assertEqual(temporal.events(partial, k=1), [(9, 20, True)])
        self.assertEqual(temporal.events(partial[:-1] + [.5], k=1), [])
        self.assertEqual(temporal.events([0.] * 10 + [1.] * 10, k=1), [])


class OptimalMatching(unittest.TestCase):
    def test_one_reference_cannot_be_reused(self):
        self.assertEqual(len(temporal.matching([(0, 10), (0, 10)], [(0, 10)])), 1)

    def test_global_assignment_beats_greedy(self):
        # First prediction overlaps both; second can only match first reference.
        p, r = [(0, 20), (0, 10)], [(0, 10), (10, 20)]
        self.assertEqual(temporal.matching(p, r), [(0, 1), (1, 0)])

    def test_half_open_boundary_and_exact_cutoff(self):
        self.assertEqual(temporal.iou((0, 10), (10, 20)), 0)
        self.assertEqual(temporal.matching([(0, 20)], [(0, 10)]), [(0, 0)])
        self.assertEqual(temporal.matching([(0, 21)], [(0, 10)]), [])
        self.assertEqual(temporal.matching([], [(0, 10)]), [])
        with self.assertRaises(ValueError):
            temporal.matching([(5, 5)], [(0, 10)])

    def test_independent_exhaustive_optimality_and_determinism(self):
        rng = np.random.default_rng(418)
        for _ in range(80):
            p = [(int(a), int(a + d)) for a, d in rng.integers(1, 25, (4, 2))]
            r = [(int(a), int(a + d)) for a, d in rng.integers(1, 25, (4, 2))]
            cutoff = Fraction(1, 4)
            pairs = temporal.matching(p, r, cutoff)
            self.assertEqual(pairs, temporal.matching(p, r, cutoff))
            objective = (len(pairs), sum(temporal.iou(p[i], r[j]) for i, j in pairs),
                         -sum(abs(p[i][0] - r[j][0]) + abs(p[i][1] - r[j][1]) for i, j in pairs))
            self.assertEqual(objective, exhaustive(p, r, cutoff))

    def test_equal_counts_can_hide_miss_and_extra(self):
        p, r = [(0, 10), (40, 50)], [(0, 10), (20, 30)]
        pairs = temporal.matching(p, r)
        self.assertEqual(len(p), len(r))
        self.assertEqual((len(r) - len(pairs), len(p) - len(pairs)), (1, 1))


if __name__ == '__main__':
    unittest.main()
