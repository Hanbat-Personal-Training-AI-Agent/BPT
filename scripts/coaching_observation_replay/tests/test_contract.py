import importlib.util
from pathlib import Path
import pytest
s=importlib.util.spec_from_file_location('observation_replay',Path(__file__).parents[1]/'replay.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)

def frame(i=0):return dict(frame=i,source_index=i,source_pts=i/30,flush_tail=False,phase='pulling',side='left',side_view=True,assessment_state='ok')
def test_zero_is_observed_not_approval_and_missing_not_zero():
    assert m.available({'value':0,'reasons':[]})
    assert not m.available({'value':None,'reasons':['missing_geometry']})
    metric={'value':60,'rawValue':61,'reasons':['low_joint_support']}
    assert not m.available(metric) and metric['value']==60

@pytest.mark.parametrize('kind',['phase','side','side_view','gap','flush','unknown','state'])
def test_temporal_context_never_silently_bridged(kind):
    a,b=frame(),frame(1)
    if kind=='gap':b['source_index']=4
    elif kind=='flush':b['flush_tail']=True
    elif kind=='unknown':b['side_view']=None
    elif kind=='state':b['assessment_state']='tracking_lost'
    else:b[kind]={'phase':'lowering','side':'right','side_view':False}[kind]
    assert m.interval_reasons(a,b)

def test_source_time_not_arrival_clock_and_native_unwrap():
    a,b=frame(),frame(1);a['arrival_host']=100;b['arrival_host']=99
    assert not m.interval_reasons(a,b)
    assert m.unwrap([179,-179])==[179,181]
    assert m.stats([1,3])['median']==2

def test_range_missing_member_or_side_switch_is_not_finite_subset_extrema():
    fs=[frame(i) for i in range(3)];metrics={i:{'cameraTorsoSignedDeg':{'value':v,'rawValue':v,'reasons':[]}} for i,v in enumerate([179,-179,-178])}
    assert m.strict_range(fs,metrics,'cameraTorsoSignedDeg','left')['value']==3
    metrics[1]['cameraTorsoSignedDeg']['reasons']=['invalid_joint']
    assert m.strict_range(fs,metrics,'cameraTorsoSignedDeg','left')['value'] is None
    metrics[1]['cameraTorsoSignedDeg']['reasons']=[];fs[1]['side']='right'
    assert not m.strict_range(fs,metrics,'cameraTorsoSignedDeg','left')['available']

def test_current_geometry_extraction_is_verbatim_not_profile_threshold():
    src=(m.ROOT/'ios/Runner/NativePose/Evaluators/FormWarnings.swift').read_text()
    body=m.extract(src,'signedHipDeviation3D');assert body in src and 'signedLineDeviation3D' in body
    c=m.build_catalog('a','b');assert c['leftHipDeg']['requiredJoints']==[4,5,8]
    assert c['leftUpperArmDeg']['scope']=='projected_body_frontal_abduction_from_caudal_axis'

def test_reused_native_output_requires_manifest_and_unchanged_bytes(tmp_path):
    p=tmp_path/'native_outputs.json';p.write_text('[]')
    with pytest.raises(ValueError,match='missing_native_output_hash'):m.require_native_output_hash(tmp_path,{})
    proof={'native_output_sha256':m.digest(p)};m.require_native_output_hash(tmp_path,proof)
    p.write_text('[0]')
    with pytest.raises(ValueError,match='native_output_hash_mismatch'):m.require_native_output_hash(tmp_path,proof)
