import copy
import importlib.util
from pathlib import Path
import pytest
spec=importlib.util.spec_from_file_location('audit',Path(__file__).with_name('analyze.py'))
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)

def frame(t,index,x=0,root=0):
    pts=[0.0]*51;pts[0]=root;pts[39]=x+root
    xy=[0.,0.,1.2]*17;xy[27]=x
    return dict(source_pts=t,frame=index,source_index=index,flush_tail=False,raw_state='ok',assessment_state='ok',invalid=[],raw_3d=pts,constrained_3d=pts.copy(),assessment_3d=pts.copy(),adapted_3d=None,raw_2d=xy,input_2d=xy.copy(),assessment_2d=xy.copy())

def test_actual_nonuniform_time_acceleration():
    fs=[frame(t,i,t*t) for i,t in enumerate((0.,.1,.3))]
    edges=[a.interval(x,y,'raw_3d','left') for x,y in zip(fs,fs[1:])]
    assert edges[0]['speed']==pytest.approx(.1)
    assert a.acceleration(*edges)==pytest.approx(2.)

def test_root_translation_is_removed_and_mapping_is_explicit():
    assert a.wrist_position(frame(0,0,2,100),'raw_3d','left')==(2,0,0)
    assert a.SIDES['left']['wrist2d']==9 and a.SIDES['left']['wrist3d']==13
    assert a.point(frame(0,0,2),'raw_2d',9)==(2,0)

def test_score_above_one_preserved_missing_layer_never_falls_back():
    f=frame(0,0);assert a.score(f,'left')==1.2
    assert a.wrist_position(f,'adapted_3d','left') is None
    f['raw_2d'][29]=0;assert a.point(f,'raw_2d',9) is None

def test_same_coordinate_residual_not_adapter_difference():
    f=frame(0,0,2);assert a.same_frame_change(f,'raw_2d','input_2d',9)==0
    f['input_2d'][27]+=3;assert a.same_frame_change(f,'raw_2d','input_2d',9)==3
    assert f['input_2d'][29]==f['raw_2d'][29]==1.2

@pytest.mark.parametrize('kind',['flush','gap','reset'])
def test_no_acceleration_across_flush_gap_or_reset(kind):
    fs=[frame(t,i,t*t) for i,t in enumerate((0.,.1,.2))]
    if kind=='flush':fs[1]['flush_tail']=True
    elif kind=='gap':fs[1]['source_index']=4;fs[2]['source_index']=5
    else:fs[1]['raw_state']='tracking_lost'
    result,_=a.distribution_kinematics(fs,'raw_3d','left')
    assert result['acceleration_finite_difference']['count']==0

def test_angle_definition_and_median():
    f=frame(0,0);f['raw_3d'][36:42]=[0,0,0,1,0,0];f['raw_3d'][33:36]=[0,1,0]
    assert a.joint_angle(f,'raw_3d',(12,11,12,13))==pytest.approx(90)
    assert a.stats([1,3])['median']==2
