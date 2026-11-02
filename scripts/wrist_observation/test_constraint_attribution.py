import importlib.util
from pathlib import Path
import pytest
spec=importlib.util.spec_from_file_location('attribution',Path(__file__).with_name('constraint_attribution.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def rows():
    return [{'frame':21,'constrained_3d':[0.]*51,'invalid':[]}],{21:{'full':[0.]*51,'invalid':[]}}

def test_exact_full_array_parity_before_ablation():
    fs,rs=rows();assert m.verify_coordinates(fs,rs)==[0.]*51

@pytest.mark.parametrize('failure',['coordinate','mask','shape','missing','nonfinite'])
def test_replay_fail_closed(failure):
    fs,rs=rows()
    if failure=='coordinate':rs[21]['full'][50]=1e-3
    elif failure=='mask':rs[21]['invalid']=[16]
    elif failure=='shape':rs[21]['full'].pop()
    elif failure=='nonfinite':rs[21]['full'][50]=float('nan')
    else:rs.clear()
    with pytest.raises(ValueError):m.verify_coordinates(fs,rs)

def test_relative_model_coordinates_and_actual_dt():
    p=[0.]*51;p[0]=100;p[39]=102
    assert m.relative(p,13)==(2,0,0)
    assert m.speed((2,0,0),(2,3,0),.5)==6
