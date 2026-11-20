import importlib.util
from pathlib import Path
import pytest
s=importlib.util.spec_from_file_location('candidate_analysis',Path(__file__).with_name('continuity_analysis.py'))
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)

def test_same_frame_geometry_does_not_invent_missing_or_smooth_angles():
    p=[0.]*51;p[33:42]=[0,1,0,0,0,0,1,0,0]
    x=m.paired_angles(p,p,p)
    assert x['left_elbow']==pytest.approx([90,90,90])
    assert x['right_elbow']==[None,None,None]

def test_native_signed_torso_axis_and_sign():
    p=[0.]*51;p[3:6]=[-1,0,0];p[12:15]=[1,0,0];p[24:27]=[0,-1,-1]
    assert m.geometry(p)['torso_signed']==pytest.approx(45)
    p[26]=1
    assert m.geometry(p)['torso_signed']==pytest.approx(-45)
