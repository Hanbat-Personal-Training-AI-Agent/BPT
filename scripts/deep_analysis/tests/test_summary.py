"""Acceptance aggregation tests; no videos, profiles or GPU."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('summary', Path(__file__).resolve().parents[1]/'summarize_gvhmr_fit3d.py')
summary = importlib.util.module_from_spec(spec); spec.loader.exec_module(summary)


def fixture(near_agreement):
    exercises = ['squat', 'barbell_row', 'pushup', 'deadlift']
    rows = []
    for exercise in exercises:
        variants = ['B', 'C'] if exercise == 'deadlift' else ['A', 'B', 'C']
        rows.append({'exercise': exercise, 'frames': 100, 'reps_truth': 6,
                     'angle_err': {v: dict.fromkeys(['knee', 'hip', 'elbow', 'torso'], 10 if v == 'A' else 5) for v in variants},
                     'pa_mpjpe_mm': dict.fromkeys(variants, 50), 'reps': dict.fromkeys(variants, 6)})
    evaluator = SimpleNamespace(EXERCISES=exercises, KEYS={e: (e, None, 15) for e in exercises[:3]},
                               rep_acc=lambda rows, variant: 1,
                               decisions=lambda rows, key: {'A': [9, 10, 2, 2], 'B': [10, 10, near_agreement, 2], 'C': [10, 10, 2, 2]})
    return rows, evaluator


def test_near_threshold_regression_blocks_b_even_with_better_overall_agreement():
    rows, evaluator = fixture(1)
    report = summary.summarize(rows, evaluator)
    assert not report['preregisteredCriterion1']['B']['criterion1Pass']
    assert report['preregisteredCriterion1']['C']['criterion1Pass']
    assert report['preregisteredCriterion1']['B']['exercises']['squat']['agreementScope'] == 'near_threshold'
    assert 'A' not in report['exercises']['deadlift']['variants']
    assert 'rep_metrics' not in str(report)


def test_all_exercises_and_four_angles_are_included():
    rows, evaluator = fixture(2)
    rows[2]['angle_err']['B']['torso'] = 30  # (5+5+5+30)/4 > A's 10
    report = summary.summarize(rows, evaluator)
    assert report['exercises']['pushup']['variants']['B']['fourAngleMeanDeg'] == 11.25
    assert not report['preregisteredCriterion1']['B']['criterion1Pass']
