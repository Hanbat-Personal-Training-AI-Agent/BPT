"""Validation stays active under -O; no model/scoring/normal-manifest change."""
import ast
import copy
import json
import math
from pathlib import Path
import subprocess
import sys

import pytest
import deep_analysis as deep
from checks import Rejected


def valid(exercise='barbell-row',side='left'):
    return {'schemaVersion':1,'sessionId':'native-session','exerciseId':exercise,'timebase':'video_ms',
        'reps':[{'repIndex':1,'onDeviceRepIndex':3,'startMs':100.25,'endMs':900.75,'side':side,
                 'onDeviceWarnings':[],'onDeviceMetrics2D':{'value':1.25},'onDeviceMetrics3D':{'value':2.5}}]}


def malformed():
    values=[]
    for field,value in [('schemaVersion',True),('schemaVersion',1.0),('timebase','frame'),('sessionId',None)]:
        m=valid();m[field]=value;values.append(json.dumps(m))
    for field,value in [('repIndex',True),('repIndex',1.0),('onDeviceRepIndex',True),('onDeviceRepIndex',1.0),
                        ('startMs',True),('endMs',float('nan')),('endMs',float('inf')),('side','guess'),('onDeviceWarnings',None)]:
        m=valid();m['reps'][0][field]=value;values.append(json.dumps(m))
    m=valid();m['reps'][0]['onDeviceMetrics3D']['value']=True;values.append(json.dumps(m))
    m=valid();m['reps'].append({**m['reps'][0],'repIndex':2,'startMs':800});values.append(json.dumps(m))
    raw=json.dumps(valid())
    values.extend([raw.replace('"schemaVersion": 1','"schemaVersion": 1, "schemaVersion": 1'),
                   raw.replace('"repIndex": 1','"repIndex": 1, "repIndex": 1'),
                   raw.replace('"value": 1.25','"value": 1.25, "value": 1.25')])
    return values


@pytest.mark.parametrize('raw',malformed())
def test_malformed_manifest_rejected(raw):
    with pytest.raises(Rejected) as error:deep.manifest(raw,'native-session')
    assert error.value.code=='invalid_reps'


@pytest.mark.parametrize('exercise',sorted(deep.EXERCISES))
@pytest.mark.parametrize('side',['left','right'])
def test_ten_valid_manifest_objects_and_serialized_output_match_previous_source(exercise,side):
    # Execute only the old pure validator function; never import old network/storage/model code.
    root=Path(__file__).resolve().parents[3]
    old=subprocess.check_output(['git','-C',str(root),'show','4eea822:server/calibration_modal/deep_analysis.py'],text=True)
    node=next(n for n in ast.parse(old).body if isinstance(n,ast.FunctionDef) and n.name=='manifest')
    namespace={'json':json,'math':math,'EXERCISES':deep.EXERCISES,'Rejected':Rejected}
    exec(compile(ast.Module(body=[node],type_ignores=[]),'previous_manifest','exec'),namespace)
    source=valid(exercise,side);untouched=copy.deepcopy(source);raw=json.dumps(source).encode()
    before=namespace['manifest'](raw,'native-session');after=deep.manifest(raw,'native-session')
    assert source==untouched and before==after==source
    assert json.dumps(before,separators=(',',':')).encode()==json.dumps(after,separators=(',',':')).encode()


def test_optimized_python_still_rejects_all_invalid_and_preserves_valid_manifest():
    source=str(Path(deep.__file__).resolve().parent)
    code='''import json,sys
sys.path.insert(0,sys.argv[1])
import deep_analysis
from checks import Rejected
payload=json.loads(sys.stdin.read())
for raw in payload['invalid']:
 try:deep_analysis.manifest(raw,'native-session')
 except Rejected as error:
  if error.code!='invalid_reps':raise SystemExit(3)
 else:raise SystemExit(2)
if deep_analysis.manifest(json.dumps(payload['valid']),'native-session')!=payload['valid']:raise SystemExit(4)
print('optimized_validation_preserved')
'''
    result=subprocess.run([sys.executable,'-O','-c',code,source],input=json.dumps({'invalid':malformed(),'valid':valid()}),text=True,capture_output=True)
    assert result.returncode==0,result.stderr
    assert result.stdout.strip()=='optimized_validation_preserved'
