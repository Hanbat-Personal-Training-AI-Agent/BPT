"""Swift/Python evidence parity, including unsupported input and bounded masks."""
import argparse,json,math
from pathlib import Path
from bone_correction_reliability import evaluate

def compare(a,b):
    if isinstance(a,dict):
        assert isinstance(b,dict) and a.keys()==b.keys();return max([compare(a[k],b[k]) for k in a] or [0.])
    if isinstance(a,list):
        assert isinstance(b,list) and len(a)==len(b);return max([compare(x,y) for x,y in zip(a,b)] or [0.])
    if isinstance(a,(float,int)) and not isinstance(a,bool):
        assert isinstance(b,(float,int)) and not isinstance(b,bool) and math.isfinite(a) and math.isfinite(b)
        d=abs(a-b);assert d<=1e-12;return d
    assert a==b;return 0.

def check(synthetic,input_path=None,result_path=None):
    cases=json.loads(synthetic.read_text());error=0.
    for case in cases:
        raw=[[float('nan') if x is None else x for x in p] for p in case['raw']]
        result=evaluate(raw,case['segments'],case['scale'],case['existing_invalid'])
        error=max(error,compare(result,case['result']));assert all(0<=j<17 for j in result['invalid']+result['additional_invalid'])
    expected={'normal':[],'boundary4':[],'collapsed_right':[15,16],'direction_flip':[15,16],'collapsed_left':[12,13],'nonfinite_head':[10]}
    for name,mask in expected.items():assert next(c for c in cases if c['case']==name)['result']['invalid']==mask
    count=0;gate=None
    if input_path is not None:
        inputs={g['exercise']:{f['frame']:f for f in g['frames']} for g in json.loads(input_path.read_text())}
        gate=json.loads(result_path.read_text());assert gate['baseline_max_coordinate_error']<=1e-12 and gate['existing_masks_exact'] and gate['raw_arrays_unchanged']
        for group in gate['groups']:
            for row in group['frames']:
                old=inputs[group['exercise']][row['frame']];raw=[old['raw'][i:i+3] for i in range(0,51,3)]
                result=evaluate(raw,row['segments_input'],row['scale'],old['invalid'])
                error=max(error,compare(result,row['result']));count+=1
    return {'passed':True,'synthetic_cases':len(cases),'native_actual_rows':count,'max_evidence_numerical_error':error,'baseline_gate':None if gate is None else {k:v for k,v in gate.items() if k!='groups'}}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('synthetic',type=Path);p.add_argument('--input',type=Path);p.add_argument('--result',type=Path);a=p.parse_args();print(json.dumps(check(a.synthetic,a.input,a.result),indent=2))
