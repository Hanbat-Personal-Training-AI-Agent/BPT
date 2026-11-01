"""Synthetic finite degeneracy, full-span invalidity and old valid-output parity."""
import csv
import hashlib
import json
from pathlib import Path

import numpy as np
import pytest

import deep_metrics
import deep_worker
from checks import Rejected
from test_deep_analysis import manifest, skeleton, supported_metrics


def test_fully_valid_reports_keep_prechange_canonical_bytes():
    frozen = json.loads((Path(__file__).parent / 'fixtures/deep_metrics_valid_sha256.json').read_text())
    for key, expected in frozen['canonicalJsonSha256'].items():
        exercise, side = key.split('/')
        m = manifest(); m['exerciseId'] = exercise
        for r in m['reps']:
            r['side'] = side
        report = supported_metrics(skeleton(), 30, m, confidence=np.full(120, .8))
        canonical = json.dumps(report, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False)
        assert hashlib.sha256(canonical.encode()).hexdigest() == expected, key


def test_unused_out_of_rep_chain_cannot_reject_or_change_selected_report():
    m = manifest(1)
    expected = supported_metrics(skeleton(), 30, m)
    joints = skeleton()
    joints[119, 16] = joints[119, 15]  # right wrist, outside left rep0..29
    assert supported_metrics(joints, 30, m) == expected


def test_other_side_degeneracy_preserves_selected_angles_and_primary_metrics():
    expected = supported_metrics(skeleton(), 30, manifest(1))['reps'][0]
    joints = skeleton(); joints[10, 16] = joints[10, 15]
    r = supported_metrics(joints, 30, manifest(1))['reps'][0]
    assert r['anglesDeg'] == expected['anglesDeg']
    for key in ['romDeg', 'depthAngleDeg', 'tempoSeconds', 'trunkStability']:
        assert r[key] == expected[key]
    assert r['symmetryDeg']['elbow'] == {'mean': None, 'max': None}
    assert r['handPath']['length'] is None  # bilateral wrist path uses the corrupt wrist
    assert r['metricValidity']['handPath']['assessment'] == 'withheld'


def test_used_wrist_withholds_only_dependent_metrics_and_never_emits_nan():
    expected = supported_metrics(skeleton(), 30, manifest(1))['reps'][0]
    joints = skeleton(); joints[10, 13] = joints[10, 12]
    with np.errstate(all='raise'):
        report = supported_metrics(joints, 30, manifest(1))
    r = report['reps'][0]
    assert set(r['anglesDeg']['elbow'].values()) == {None}
    assert r['metricValidity']['elbow']['reasons'] == ['invalid_geometry']
    assert r['handPath']['samples'] == [] and r['handPath']['length'] is None
    for angle in ['knee', 'hip', 'shoulder', 'torso']:
        assert r['anglesDeg'][angle] == expected['anglesDeg'][angle]
        assert r['metricValidity'][angle]['assessment'] == 'available'
    for key in ['romDeg', 'depthAngleDeg', 'tempoSeconds', 'trunkStability']:
        assert r[key] == expected[key]
    json.dumps(report, allow_nan=False)


def test_invalid_primary_whole_span_and_baseline_are_not_replaced_by_valid_subsets():
    joints = skeleton(); joints[10, 6] = joints[10, 5]  # only one left lower-leg sample
    report = supported_metrics(joints, 30, manifest())
    first, last = report['reps'][0], report['reps'][-1]
    assert first['romDeg'] is None and first['depthAngleDeg'] is None
    assert set(first['tempoSeconds'].values()) == {None}
    for key in ['topFrame', 'bottomFrame', 'topTime', 'bottomTime']:
        assert first[key] is None
    assert first['anglesDeg']['hip']['min'] is not None
    assert first['anglesDeg']['hip']['top'] is None  # primary-selected phase unavailable
    assert first['metricValidity']['phase']['assessment'] == 'withheld'
    assert last['anglesDeg']['knee']['min'] is not None
    assert last['metricValidity']['knee']['assessment'] == 'available'
    assert last['fatigueDrift'] == {'depthDriftDeg': None, 'romDropDeg': None, 'tempoDriftRatio': None, 'comparable': False}
    assert 'invalid_baseline_geometry' in last['metricValidity']['romDropDeg']['reasons']
    assert last['metricValidity']['trunkStdDeg']['assessment'] == 'available'
    assert report['consistency']['romStdDeg'] is None and report['consistency']['tempoCv'] is None
    json.dumps(report, allow_nan=False)


def test_bad_current_primary_does_not_corrupt_valid_baseline_or_unrelated_metrics():
    expected = supported_metrics(skeleton(), 30, manifest())
    joints = skeleton(); joints[100, 6] = joints[100, 5]
    report = supported_metrics(joints, 30, manifest())
    assert report['reps'][:3] == expected['reps'][:3]
    last = report['reps'][-1]
    assert last['romDeg'] is None and last['fatigueDrift']['romDropDeg'] is None
    assert 'invalid_baseline_geometry' not in last['metricValidity']['romDropDeg']['reasons']
    assert last['trunkStability'] == expected['reps'][-1]['trunkStability']
    assert last['handPath'] == expected['reps'][-1]['handPath']
    json.dumps(report, allow_nan=False)


def test_all_invalid_or_nonfinite_global_skeleton_still_rejects():
    for joints in [np.zeros((120, 17, 3)), np.full((120, 17, 3), np.nan), np.full((120, 17, 3), np.inf)]:
        with pytest.raises(Rejected, match='invalid_skeleton'):
            supported_metrics(joints, 30, manifest())
    joints = skeleton(); joints[119, 16, 0] = np.nan
    with pytest.raises(Rejected, match='invalid_skeleton'):
        supported_metrics(joints, 30, manifest(1))  # nonfinite validation remains global


def test_catalog_mean_never_uses_a_finite_subset_of_invalid_baseline(tmp_path, monkeypatch):
    path = tmp_path / 'fault_catalog.csv'
    contract = deep_metrics.DEPTH_FADE_CONTRACTS['squat_depth_fade']
    row = dict.fromkeys(deep_metrics.TEAM_COLUMNS, '')
    row.update(fault_id='squat_depth_fade', exercise=contract[0], metric_definition=contract[1], threshold_standard=contract[2])
    with path.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=deep_metrics.TEAM_COLUMNS); writer.writeheader(); writer.writerow(row)
    monkeypatch.setattr(deep_metrics, 'CATALOG_PATH', path)
    reps = [{'repIndex': i+1, 'depthAngleDeg': value, 'confidence': .8,
             'metricValidity': {'depthAngleDeg': {'assessment': 'available'}}}
            for i, value in enumerate([None, 80, 90, 100, 110, 120])]
    measured = deep_metrics.catalog_measurements(reps, 'squat', path.name)[0]
    assert measured['value'] is None and measured['assessment'] == 'withheld'
    assert 'invalid_geometry' in measured['reasons']


def test_video_panel_handles_null_metrics_even_with_inconsistent_available_metadata():
    keys = ['knee', 'hip', 'elbow', 'shoulder', 'torso', 'romDeg', 'tempoSeconds']
    r = {'repIndex': 1, 'side': 'left', 'primaryJoint': 'knee', 'romDeg': None,
         'tempoSeconds': {'total': None}, 'metricValidity': {k: {'assessment': 'available'} for k in keys}}
    angles = {'left': {k: np.array([45.]) for k in keys[:5]}}
    angles['left']['elbow'][:] = np.nan
    lines = deep_worker.panel_lines(r, 0, angles, np.ones((1, 17)), np.array([True]))
    assert '무릎 45.0°' in lines and '몸통 45.0°' in lines
    assert '팔꿈치 판정 보류' in lines and '가동 범위 판정 보류' in lines and '반복 시간 판정 보류' in lines
    assert not any('None' in line or 'nan' in line.lower() for line in lines)


def test_flutter_phone_fixture_is_the_actual_strict_json_scorer_output():
    joints = skeleton(); joints[10, 6] = joints[10, 5]
    actual = supported_metrics(joints, 30, manifest(), confidence=np.full(120, .8))
    fixture = Path(__file__).resolve().parents[3] / 'test/fixtures/deep_partial_primary.json'
    assert json.loads(fixture.read_text()) == actual
    json.dumps(actual, allow_nan=False)
