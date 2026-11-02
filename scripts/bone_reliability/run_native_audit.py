"""Compile offline evidence only; synthetic parity + original native capture coordinate gates.
All actual row arrays and compiled binaries stay in outside-repository scratch.
"""
import argparse,fcntl,hashlib,importlib.util,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
s=importlib.util.spec_from_file_location('terminal_reader',ROOT/'scripts/terminal_evidence/replay.py');reader=importlib.util.module_from_spec(s);s.loader.exec_module(reader)

def run(paths,scratch):
    assert not scratch.resolve().is_relative_to(ROOT)
    scratch.mkdir(parents=True,exist_ok=False)
    groups=[];digests=[]
    for p in paths:
        epochs,capped,digest=reader.load(p);assert not capped;digests.append(digest)
        for data in epochs.values():
            assert data['end'] and not data['end']['incomplete']
            groups.append({'exercise':data['start']['exercise'],'frames':[{'frame':f['frame'],'raw':f['raw_3d'],'full':f['constrained_3d'],'invalid':f['invalid']} for f in data['frames'] if f['constrained_3d'] is not None]})
    (scratch/'input.json').write_text(json.dumps(groups,allow_nan=False))
    tracker=ROOT/'ios/Runner/NativePose/Evaluators/FormWarnings.swift'
    median=re.search(r'    static func median\(_ values: \[Double\]\) -> Double\? \{.*?\n    \}',tracker.read_text(),re.S).group()
    (scratch/'median.swift').write_text('import Foundation\nenum FormWarningTracker {\n'+median+'\n}\n')
    (scratch/'main.swift').write_bytes(Path(__file__).with_name('reliability_replay.swift').read_bytes())
    base=ROOT/'ios/Runner/NativePose/PosePipeline';files=[base/(x+'.swift') for x in ('Pose3DConstraints','BoneLengthConstraint','KneeHingeLimit')]+[Path(__file__).with_name('BoneCorrectionReliability.swift')]
    input_hash=hashlib.sha256((scratch/'input.json').read_bytes()).hexdigest()
    with open('/tmp/bpt-heavy.lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        subprocess.run(['swiftc','-O',*map(str,files),str(scratch/'median.swift'),str(scratch/'main.swift'),'-o',str(scratch/'replay')],check=True)
        subprocess.run([str(scratch/'replay'),'--synthetic',str(scratch/'synthetic.json')],check=True)
        subprocess.run([str(scratch/'replay'),str(scratch/'input.json'),str(scratch/'native_result.json')],check=True)
    assert input_hash==hashlib.sha256((scratch/'input.json').read_bytes()).hexdigest()
    proof={'original_raw_full_input_file_unchanged':True,'input_sha256':input_hash,'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},'median_shim_sha256':hashlib.sha256((scratch/'median.swift').read_bytes()).hexdigest(),'helper_sha256':hashlib.sha256((scratch/'main.swift').read_bytes()).hexdigest(),'combined_original_capture_manifest_sha256':hashlib.sha256('\n'.join(sorted(digests)).encode()).hexdigest()}
    (scratch/'receipt.json').write_text(json.dumps(proof,indent=2))
    return proof

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('captures',nargs='+',type=Path);p.add_argument('--scratch',type=Path,required=True);a=p.parse_args();print(json.dumps(run(a.captures,a.scratch),indent=2))
