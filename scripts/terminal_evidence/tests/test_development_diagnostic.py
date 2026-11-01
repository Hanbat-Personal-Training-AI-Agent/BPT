import importlib.util
from pathlib import Path
import sys
import pytest

sys.path.insert(0,str(Path(__file__).parents[1]))
spec=importlib.util.spec_from_file_location('terminal_development',Path(__file__).parents[1]/'development_diagnostic.py')
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)


def original():return {'exercise':'pushup','side':'left','startFrame':0,'endFrame':10}

def frame(i,angle=170,phase='top'):
    return {'frame':10+i,'sourceIndex':10+i,'sourceTime':i/30,'hostTime':i/30,'coordinateKey':'fixed',
        'side':'left','required2D':True,'sideView':True,'state':'ok','flushed':False,'setEndFlushTail':False,
        'phase':phase,'activeRepStart':None,'assessmentAngles':{'elbow':angle},'rawAngles':{'elbow':angle}}


def test_development_peak_closes_before_actual_next_rep_without_plateau_or_future_geometry():
    frames=[frame(0,130,'ascending'),frame(1,150,'ascending'),frame(2,175),frame(3,160)]
    next_rep=frame(4,180);next_rep['activeRepStart']=14;next_rep['required2D']=False;frames.append(next_rep)
    result=d.development_span(original(),frames)
    assert result['maxima']=={'elbow':175}
    assert result['supported_peak_window'] is True and result['stop']=='actual_next_rep_begin'
    assert len(result['frames'])==3
    assert 'assessment' not in result  # development coverage does not make a warning/correct-form decision


def test_top_exit_and_missing_support_never_select_the_later_attractive_value():
    frames=[frame(0),frame(1,150),frame(2,175),frame(3,180,'lowering')]
    result=d.development_span(original(),frames)
    assert result['maxima']=={'elbow':175} and result['stop']=='actual_top_phase_exit'
    frames[2]['required2D']=False
    result=d.development_span(original(),frames)
    assert result['maxima']=={'elbow':150}
    assert result['supported_peak_window'] is False and result['stop']=='native_support_or_side_missing'


def test_source_gap_and_clamped_anchor_remain_unavailable():
    frames=[frame(0),frame(1)];frames[1]['sourceTime']=.5
    result=d.development_span(original(),frames)
    assert result['maxima']=={} and result['stop']=='source_gap'
    frames[0]['flushed']=True
    assert d.development_span(original(),frames)['supported_peak_window'] is False


def test_continuous_top_can_fail_frozen_speed_stability_without_missing_support():
    frames=[frame(0,130)]+[frame(i,140+i) for i in range(1,21)]
    record={'original':original(),'host':0,'frames':frames,'report':{'closure':'watchdog_timeout','topFrames':20},
        'trigger':{'type':'terminal_candidate_tick','host_time':1.5}}
    result=d.frozen_attribution(record,{'timeoutSeconds':1.5,'maximumAngularSpeed':10})
    assert result['maximum_continuous_top_seconds']==pytest.approx(19/30)
    assert result['maximum_stable_run_seconds']==0
    assert result['angle_speed_resets']==19 and result['joint_speed_resets']['elbow']==19
    assert result['deadline_branch']=='operational_watchdog_deadline'
    assert result['top_samples']==20


def test_fixed15_comparison_keeps_its_original_denominator_and_next_begin_boundary(tmp_path):
    from test_replay import capture,write
    epochs,_,_=d.strict.load(write(tmp_path,capture()))
    o={'exercise':'pushup','side':'left','rep':1,'startFrame':0,'endFrame':2}
    assert d.fixed15_pair(o,epochs[1],'elbow')==pytest.approx((90,150))
    epochs[1]['frames'][12]['active_rep_start']=12
    assert d.fixed15_pair(o,epochs[1],'elbow') is None
