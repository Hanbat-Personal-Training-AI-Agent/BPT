import copy
import importlib.util
import json
import math
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location('terminal_replay', Path(__file__).parents[1] / 'replay.py')
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)


def frame(index, angle=90):
    p = [0.] * 51
    for shoulder, elbow, wrist in ((11,12,13),(14,15,16)):
        for j, xyz in ((shoulder, (1,0,0)), (elbow, (0,0,0)), (wrist, (math.cos(math.radians(angle)),math.sin(math.radians(angle)),0))):
            p[3*j:3*j+3] = xyz
    kp = [100., 100., .8] * 17
    return dict(schema=r.SCHEMA, type='terminal_frame', epoch=1, frame=index, source_index=index,
        source_pts=index/30, source_time_value=index, source_time_scale=30, source_kind='camera_capture_index', time_basis='sample_pts_seconds', size=[640,480], rotation=0,
        raw_2d=kp, input_2d=kp, assessment_2d=kp, raw_3d=p, constrained_3d=p, adapted_3d=None, assessment_3d=p,
        confidence_h36m=[.8]*17, invalid=[], raw_state='ok', assessment_state='ok', phase='top', active_rep_start=None, side='left', side_view=True,
        filled=27, row=21, flush_tail=False, unit_px=200., judgement_up=[0,-1,0],
        up_time_basis='judgement_time_not_source_sensor', source_gravity_available=False)


def capture():
    common = dict(schema=r.SCHEMA)
    rows = [dict(common, type='terminal_header', clock='sample_pts_seconds', provenance='synthetic_test', units_3d='h36m17_xs_model_space_no_metric_guarantee', units_2d='analysis_image_pixels', configuration_location='terminal_start'),
        dict(common, type='terminal_start', epoch=1, exercise='pushUp', time_basis='sample_pts_seconds', raw_source='xs_output_before_constraints', lookahead=5, cadence=1)]
    rows += [frame(i, 90 if i < 3 else 150) for i in range(18)]
    rows += [dict(common, type='terminal_rep', epoch=1, rep=1, start_frame=0, end_frame=2, side='left'),
        dict(common, type='terminal_end', epoch=1, incomplete=False, flush_complete=True)]
    return rows


def write(tmp_path, rows):
    p = tmp_path/'capture.jsonl'
    p.write_text('\n'.join(json.dumps(dict(x, sequence=i), allow_nan=False) for i,x in enumerate(rows))+'\n')
    return p


def test_same_capture_fixed_side_bilateral_and_layers(tmp_path):
    result = r.replay(write(tmp_path, capture()))
    assert len(result['groups']) == 4
    for group in result['groups'].values():
        assert group['paired'] == 1
        assert group['max_delta_deg']['mean'] == pytest.approx(60)
        assert group['range_delta_deg']['mean'] == pytest.approx(60)
    assert 'input_sha256' in result
    assert 'terminal_frame' not in json.dumps(result)  # only aggregate leaves the capture host


@pytest.mark.parametrize('mutation,reason', [
    (lambda x: x[0].update(clock='arrival_host'), 'clock'),
    (lambda x: x[2].update(arrival_host=1), 'mixed_clock'),
    (lambda x: x[2].update(schema='legacy'), 'schema'),
    (lambda x: x[2].update(epoch=2), 'stale'),
    (lambda x: x[2].update(frame=True), 'source_time'),
    (lambda x: x[2].update(rotation=False), 'image_geometry'),
    (lambda x: x[2].update(side_view=1), 'side_or_view'),
    (lambda x: x[2].update(raw_3d=[0]*50), 'array_shape'),
    (lambda x: x[2].update(raw_3d=None), 'missing_native'),
    (lambda x: x[3].update(source_pts=0,source_time_value=0), 'duplicate'),
    (lambda x: x[3].update(source_index=0), 'duplicate'),
    (lambda x: x[3].update(frame=0), 'duplicate'),
    (lambda x: x[3].update(rotation=90), 'coordinate'),
    (lambda x: x.pop(), 'missing_footer'),
    (lambda x: x[-1].update(incomplete=False,flush_complete=False), 'false_complete'),
    (lambda x: x[-2].update(start_frame=100), 'rep_boundary'),
    (lambda x: x[-2].update(end_frame=40), 'missing_boundary'),
    (lambda x: x[2].update(confidence_h36m=[True]*17), 'array_nonfinite'),
])
def test_strict_rejections(tmp_path, mutation, reason):
    rows = capture(); mutation(rows)
    with pytest.raises(r.InvalidCapture, match=reason):
        r.replay(write(tmp_path, rows))


def test_nonfinite_json_rejected(tmp_path):
    p=write(tmp_path,capture());p.write_text(p.read_text().replace('0.8','NaN',1))
    with pytest.raises(r.InvalidCapture):r.replay(p)


def test_short_flush_tail_cap_and_source_gaps_are_coverage_not_completion(tmp_path):
    rows=capture();rows[6]['flush_tail']=True
    result=r.replay(write(tmp_path,rows))
    assert all(g['paired']==0 and g['short_followup']==1 for g in result['groups'].values())
    rows=capture();rows[-1]=dict(schema=r.SCHEMA,type='terminal_capped',incomplete=True)
    result=r.replay(write(tmp_path,rows))
    assert result['capped'] and all(g['paired']==0 for g in result['groups'].values())
    rows=capture()
    for row in rows:
        if row['type']=='terminal_frame':row['source_index']*=2
    result=r.replay(write(tmp_path,rows))
    assert all(g['paired']==1 and g['source_gaps']==17 for g in result['groups'].values())


def test_one_invalid_sample_never_becomes_finite_subset_extrema(tmp_path):
    rows=capture();rows[3]['assessment_3d']=copy.deepcopy(rows[3]['assessment_3d']);rows[3]['assessment_3d'][39]=None
    result=r.replay(write(tmp_path,rows))
    assert result['groups']['pushUp/elbow/selected/assessment_3d']['original_available']==0
    assert result['groups']['pushUp/elbow/opposite/assessment_3d']['paired']==1
    assert result['groups']['pushUp/elbow/selected/raw_3d']['paired']==1


def test_missing_numeric_record_is_not_confused_with_a_camera_drop(tmp_path):
    p=write(tmp_path,capture())
    lines=p.read_text().splitlines(); del lines[4]
    p.write_text('\n'.join(lines)+'\n')
    with pytest.raises(r.InvalidCapture,match='record_sequence'):r.replay(p)


def test_native_simcc_scores_are_preserved_not_probability_clamped(tmp_path):
    rows=capture()
    for f in rows:
        if f['type']=='terminal_frame':
            for layer in ('raw_2d','input_2d','assessment_2d'):
                f[layer]=copy.deepcopy(f[layer]);f[layer][2]=2.7;f[layer][5]=-0.2
            f['confidence_h36m']=[2.7,-0.2]+[.8]*15
    path=write(tmp_path,rows)
    epochs,_,_=r.load(path)
    assert epochs[1]['frames'][0]['raw_2d'][2:6:3] == [2.7,-0.2]
    assert all(g['paired']==1 for g in r.replay(path)['groups'].values())


def test_duplicate_json_keys_are_not_last_value_wins(tmp_path):
    p=write(tmp_path,capture());p.write_text(p.read_text().replace('"frame": 0','"frame": 999, "frame": 0',1))
    with pytest.raises(r.InvalidCapture):r.replay(p)


def test_unfinished_next_rep_cannot_become_previous_terminal_observation(tmp_path):
    rows=capture()
    for f in rows:
        if f['type']=='terminal_frame' and f['frame']>=4:f['active_rep_start']=4
    result=r.replay(write(tmp_path,rows))
    assert all(g['paired']==0 and g['short_followup']==1 for g in result['groups'].values())
    # There is no next completed report to reveal this boundary; only actual tracker begin evidence.
    assert len([x for x in rows if x['type']=='terminal_rep'])==1


def test_source_rational_pts_cannot_be_replaced_by_host_clock(tmp_path):
    rows=capture();rows[2]['source_time_scale']=0
    with pytest.raises(r.InvalidCapture,match='source_rational_time'):r.replay(write(tmp_path,rows))
    rows=capture();rows[2]['source_pts']=123.0
    with pytest.raises(r.InvalidCapture,match='source_clock_mismatch'):r.replay(write(tmp_path,rows))


def test_huge_malformed_numbers_reject_without_overflow(tmp_path):
    rows=capture();rows[2]['source_pts']=10**400
    with pytest.raises(r.InvalidCapture):r.replay(write(tmp_path,rows))
    rows=capture();rows[2]['source_time_scale']=10**400
    with pytest.raises(r.InvalidCapture):r.replay(write(tmp_path,rows))


def test_mixed_candidate_events_and_real_eof_flush_preserve_raw_geometry(tmp_path):
    rows=capture()
    original=r.replay(write(tmp_path,rows))['groups']
    rows[0]['candidate_protocol']='bpt.terminal-candidate.v1'
    extra=[dict(schema=r.SCHEMA,type='terminal_candidate_config',candidate_protocol='bpt.terminal-candidate.v1',payload={
        'stableSeconds':.25,'minimumSamples':5,'maximumAngularSpeed':10.,'maximumSourceGap':.15,'timeoutSeconds':1.5,'minimumReferences':3}),
        dict(schema=r.SCHEMA,type='terminal_candidate_start',epoch=1)]
    rows[2:2]=extra
    rows[-1:-1]=[dict(schema=r.SCHEMA,type='terminal_eof_flush',epoch=1,trigger='video_eof_test_hook'),
        dict(schema=r.SCHEMA,type='terminal_candidate_end',epoch=1,reason='set_end',host_time=3.0)]
    assert r.replay(write(tmp_path,rows))['groups']==original
    rows[0].pop('candidate_protocol')
    with pytest.raises(r.InvalidCapture,match='candidate_protocol'):r.replay(write(tmp_path,rows))
