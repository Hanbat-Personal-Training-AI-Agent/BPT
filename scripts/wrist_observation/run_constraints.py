"""Compile unchanged native constraints and replay existing raw outputs; no model inference.
Private row arrays and temporary binaries stay in --scratch outside the repository.
"""
import argparse
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('wrist_audit',Path(__file__).with_name('analyze.py'))
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)

def run(paths,scratch):
    if scratch.resolve().is_relative_to(ROOT):raise ValueError('private scratch must be outside repository')
    scratch.mkdir(parents=True,exist_ok=True)
    groups=[]
    for path in paths:
        epochs,capped,_=a.strict.load(path);a.strict.require(not capped,'capped_capture')
        for data in epochs.values():
            a.strict.require(data['end'] is not None and not data['end']['incomplete'],'incomplete_capture')
            frames=[{'frame':f['frame'],'raw':f['raw_3d']} for f in data['frames'] if f['raw_state'] in ('ok','partial_3d') and f['raw_3d'] is not None]
            groups.append({'exercise':data['start']['exercise'],'frames':frames})
    (scratch/'input.json').write_text(json.dumps(groups,allow_nan=False))
    source=ROOT/'ios/Runner/NativePose/PosePipeline'
    files=[source/(name+'.swift') for name in ('Pose3DConstraints','BoneLengthConstraint','KneeHingeLimit')]
    tracker=ROOT/'ios/Runner/NativePose/Evaluators/FormWarnings.swift'
    median=re.search(r'    static func median\(_ values: \[Double\]\) -> Double\? \{.*?\n    \}',tracker.read_text(),re.S).group()
    (scratch/'median.swift').write_text('import Foundation\nenum FormWarningTracker {\n'+median+'\n}\n')
    (scratch/'main.swift').write_bytes(Path(__file__).with_name('constraints_replay.swift').read_bytes())
    with open('/tmp/bpt-heavy.lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        subprocess.run(['swiftc','-O',*map(str,files),str(scratch/'median.swift'),str(scratch/'main.swift'),'-o',str(scratch/'replay')],check=True)
        subprocess.run([str(scratch/'replay'),str(scratch/'input.json'),str(scratch/'output.json')],check=True)
    proof={'production_source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},'median_source_sha256':hashlib.sha256(median.encode()).hexdigest(),'replay_helper_sha256':hashlib.sha256(Path(__file__).with_name('constraints_replay.swift').read_bytes()).hexdigest(),'rows':{g['exercise']:len(g['frames']) for g in groups},'scope':'raw3D postprocessing only; no model, confidence unused by production Pose3DConstraints, native frame order including explicit flush preserved'}
    (scratch/'receipt.json').write_text(json.dumps(proof,indent=2))
    return proof

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('captures',nargs='+',type=Path);p.add_argument('--scratch',type=Path,required=True);args=p.parse_args();print(json.dumps(run(args.captures,args.scratch),indent=2))
