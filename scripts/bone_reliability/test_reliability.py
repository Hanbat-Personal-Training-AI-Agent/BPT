import copy,importlib.util
from pathlib import Path
import pytest
s=importlib.util.spec_from_file_location('reliability',Path(__file__).with_name('bone_correction_reliability.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m)

def fixture():
    p=[[float(i),0.,0.] for i in range(17)]
    reports={name:dict(observed=m.length(p[c],p[m.PARENTS[c]]),output=m.length(p[c],p[m.PARENTS[c]]),target_cm=1.,constrained=True,degenerate=False) for c,name in enumerate(m.NAMES,1)}
    return p,reports

def test_normal_raw_immutable_and_existing_mask_union():
    p,r=fixture();before=copy.deepcopy((p,r));o=m.evaluate(p,r,1.,[5,10]);assert o['invalid']==[5,10] and not o['additional_invalid'];assert (p,r)==before

def test_child_subtree_only_strict_four_and_direction_independent():
    p,r=fixture();name='right_shoulder-right_elbow';r[name]['output']=4*r[name]['observed']
    assert not m.evaluate(p,r,1.,[])['invalid']
    r[name]['output']*=2;o=m.evaluate(p,r,1.,[]);assert o['invalid']==[15,16];assert 2 not in o['invalid'] and 12 not in o['invalid']
    p[15][0]=2*p[14][0]-p[15][0];r[name]['observed']=m.length(p[15],p[14]);assert m.evaluate(p,r,1.,[])['invalid']==[15,16]

@pytest.mark.parametrize('kind',['zero','nonfinite','target','scale','missing','mismatch','unprojected'])
def test_unsupported_never_normal(kind):
    p,r=fixture();edge='right_shoulder-right_elbow';scale=1.
    if kind=='zero':p[15]=p[14].copy();r[edge].update(observed=0.,output=0.,degenerate=True,constrained=False)
    elif kind=='nonfinite':p[15][0]=float('nan')
    elif kind=='target':r[edge]['target_cm']=0
    elif kind=='scale':scale=None
    elif kind=='missing':r.pop(edge)
    elif kind=='mismatch':r[edge]['observed']+=.2
    else:r[edge]['constrained']=False
    o=m.evaluate(p,r,scale,[]);assert {15,16}<=set(o['invalid']);assert next(x for x in o['segments'] if x['name']==edge)['status']=='unsupported'

def test_mirror_and_fixed_order():
    p,r=fixture();r['left_shoulder-left_elbow']['output']*=8
    a=m.evaluate(p,r,1.,[]);b=m.evaluate(p,dict(reversed(list(r.items()))),1.,[])
    assert a==b and a['invalid']==[12,13]

def test_missing_pose_whole_uncertain_and_no_confidence_override_api():
    p,r=fixture();assert m.evaluate(p[:16],r,1.,[])['invalid']==list(range(17))
    import inspect
    assert 'confidence' not in inspect.signature(m.evaluate).parameters

def test_out_of_bounds_mask_forensic_preserved_bounded_public_indices():
    p,r=fixture();o=m.evaluate(p,r,1.,[5,99]);assert o['existing_invalid']==[5,99]
    assert o['invalid']==list(range(17)) and o['additional_invalid']==[i for i in range(17) if i!=5]

@pytest.mark.parametrize('raw',[None,[None]*17,[[0,0,0]]*16])
def test_malformed_raw_has_explicit_uncertainty(raw):
    _,r=fixture();o=m.evaluate(raw,r,1.,[]);assert o['invalid']==list(range(17))

@pytest.mark.parametrize('mask',[None,[[1],2],['x',2],{'a':1}])
def test_malformed_mask_does_not_raise_or_leak_indices(mask):
    p,r=fixture();o=m.evaluate(p,r,1.,mask);assert o['invalid']==list(range(17))

@pytest.mark.parametrize('report',[{},None,{'observed':1.}])
def test_missing_report_fields_not_normal(report):
    p,r=fixture();r['right_shoulder-right_elbow']=report;o=m.evaluate(p,r,1.,[])
    assert {15,16}<=set(o['invalid']);assert next(e for e in o['segments'] if e['child']==15)['status']=='unsupported'
