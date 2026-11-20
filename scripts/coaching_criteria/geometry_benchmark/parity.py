"""Independent native/Python exact geometry gate. Synthetic fixtures only."""
from pathlib import Path
import hashlib,json,subprocess,tempfile,fcntl
import numpy as np
from .metrics import measure
from scripts.coaching_criteria.candidates.replay import geometry_source

def main():
 root=Path(__file__).resolve().parents[3];out=Path.home()/'bpt-runs/core3-exact-geometry-parity-20261102';out.mkdir(exist_ok=True)
 rng=np.random.default_rng(17582);joints=rng.normal(size=(192,17,3));joints=np.concatenate([joints,joints[:4]*7+np.array([3,2,-9]),np.zeros((1,17,3))]);fixture=out/'fixture.json';fixture.write_text(json.dumps(joints.tolist(),allow_nan=False))
 geometry,functions=geometry_source(root);g=out/'native_geometry.swift';g.write_text(geometry);binary=out/'geometry-parity-native'
 sources=[root/'ios/Runner/NativePose/Evaluators/ExperimentalCoaching.swift',g,Path(__file__).with_name('native_metrics.swift')]
 with open('/tmp/bpt-heavy.lock','a') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX);subprocess.run(['swiftc','-O',*map(str,sources),'-o',str(binary)],check=True)
 native=json.loads(subprocess.check_output([str(binary),str(fixture)]));predicted=measure(joints);maximum=0.;count=0
 for index,row in enumerate(native):
  for name,values in predicted.items():
   actual=row[name];expected=values[index]
   if actual is None:
    if np.isfinite(expected):raise RuntimeError('validity mismatch '+name)
   else:
    if not np.isfinite(expected):raise RuntimeError('validity mismatch '+name)
    error=abs(expected-actual);maximum=max(maximum,error);count+=1
    if error>1e-10:raise RuntimeError(f'geometry parity {name}: {error}')
 (out/'native-expected.json').write_text(json.dumps(native,allow_nan=False))
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 receipt={'passed':True,'cases':len(joints),'finiteComparisons':count,'maximumAbsoluteDifference':maximum,'tolerance':1e-10,'fixtureSHA256':sha(fixture),'nativeExpectedSHA256':sha(out/'native-expected.json'),'pythonMetricsSHA256':sha(Path(__file__).with_name('metrics.py')),'nativeSourceSHA256':{p.name:sha(p) for p in sources},'extractedNativeFunctionsSHA256':functions,'binarySHA256':sha(binary),'data':'synthetic only; no models/GT'}
 (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt),flush=True)

if __name__=='__main__':main()
