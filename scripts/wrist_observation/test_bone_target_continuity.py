import importlib.util
from pathlib import Path
import pytest
s=importlib.util.spec_from_file_location('shape_filter',Path(__file__).with_name('bone_target_continuity.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m)

def test_half_life_and_profile_epoch_ownership():
    f=m.BoneTargetContinuity();f.update({'a':1,'b':1},0,'prior','A')
    step=f.update({'a':3,'b':1},.2,'session','A');assert step['filtered_shape']['a']==pytest.approx(.625)
    restart=f.update({'a':1,'b':3},0,'session','B');assert restart['status']=='reset_profile_epoch';assert restart['filtered_shape']['a']==.25

@pytest.mark.parametrize('time',[None,float('nan'),float('inf'),-1])
def test_missing_or_invalid_clock_has_no_fps_fallback(time):
    f=m.BoneTargetContinuity();f.update({'a':1},0,'prior','A')
    assert f.update({'a':1},time,'prior','A')['filtered_shape'] is None
    assert f.shape is None

def test_tracking_and_bad_target_clear_history():
    f=m.BoneTargetContinuity();f.update({'a':1},0,'prior','A')
    assert f.update({'a':1},1,'prior','A',False)['status']=='unsupported_tracking'
    assert f.update({'a':0},1,'prior','A')['status']=='unsupported_target'
    assert f.update({'a':1},2,'prior','A')['status']=='initialized'
