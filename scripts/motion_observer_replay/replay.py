#!/usr/bin/env python3
"""Actual retained-input CPU replay of the opt-in observer; no inference or GT."""
import argparse,collections,fcntl,hashlib,importlib.util,json,math,os,statistics,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CAPTURE=Path.home()/'bpt-data/terminal-device-capture-20261102'
EXPECTED={'squat':'c783990a63bb3aa05afd30bd122b3c9b2e513a53a3e7430a86dddc4e83db5039','pushup':'508cf87e31740b20e17b6b44775b3ab28cdc9fc94fbbcd5af69acfa031dbe3fa','barbellrow':'20f8daf37800599513bdafba20e0e4b312a66cbf593fca68aad031143bf8921a'}
SOURCES=['scripts/motion_observer_replay/main.swift','scripts/motion_observer_replay/replay.py','scripts/terminal_evidence/replay.py','ios/Runner/NativePose/PosePipeline/ExerciseMotionEstimator.swift','ios/Runner/NativePose/PosePipeline/ExerciseMotionObserver.swift','ios/Runner/NativePose/PosePipeline/BoneLengthConstraint.swift','ios/Runner/NativePose/PosePipeline/PoseCoordinateTransforms.swift','ios/Runner/NativePose/PosePipeline/SimCCDecoder.swift']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,j):p.write_text(json.dumps(j,sort_keys=True,indent=2,allow_nan=False));p.chmod(0o600)
def run(out):
    if not __debug__:raise RuntimeError('Assertions must remain enabled')
    os.umask(0o077);out=out.expanduser().resolve();assert out.is_relative_to((Path.home()/'bpt-data').resolve()) and not out.exists();out.mkdir(mode=0o700)
    spec=importlib.util.spec_from_file_location('strict',ROOT/'scripts/terminal_evidence/replay.py');strict=importlib.util.module_from_spec(spec);spec.loader.exec_module(strict)
    source_hashes={p:digest(ROOT/p) for p in SOURCES};groups=[];originals={};counts={}
    for name,want in EXPECTED.items():
        path=CAPTURE/name/'terminal-original.jsonl';assert digest(path)==want
        epochs,capped,got=strict.load(path);assert got==want and not capped
        assert len(epochs)==1;data=next(iter(epochs.values()));exercise={'pushUp':'pushup','barbellRow':'barbell_row'}.get(data['start']['exercise'],data['start']['exercise']);assert exercise=={'barbellrow':'barbell_row'}.get(name,name)
        groups.append({'exercise':exercise,'frames':data['frames']});originals[exercise]=want
        counts[exercise]={'frames':len(data['frames']),'rawAvailable':sum(r['raw_3d'] is not None for r in data['frames']),'flush':sum(r['flush_tail'] for r in data['frames'])}
    prepared=out/'prepared-input.json';save(prepared,groups)
    save(out/'freeze.json',{'sourceSHA256':source_hashes,'inputSHA256':originals,'preparedSHA256':digest(prepared),'configuration':{'variants':['A','B','C','D','E','F','G','H','HOLD'],'personalProfile':None,'onlineProfile':False,'fixedCameraAssertion':False,'nativePhaseSupplied':False,'personIdentitySupplied':False},'counts':counts,'scope':'reused development recordings; no inference/GT/form accuracy'})
    with open('/tmp/bpt-heavy.lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        binary=out/'observer-replay';compile_sources=[ROOT/p for p in SOURCES if p.endswith('.swift')]
        with (out/'compile.log').open('w') as log:subprocess.run(['/usr/bin/xcrun','swiftc','-O','-o',str(binary),*[str(p) for p in compile_sources]],check=True,stdout=log,stderr=subprocess.STDOUT)
        start=time.monotonic();subprocess.run([str(binary),str(prepared),str(out/'observations.jsonl')],check=True);elapsed=time.monotonic()-start
    groups_by_name={g['exercise']:{r['sequence']:r for r in g['frames']} for g in groups};stats={};available=0;withheld=collections.Counter();raw_exact=0;confidence_diffs=[]
    for line in (out/'observations.jsonl').open():
        row=json.loads(line);key=(row['exercise'],row['variant']);s=stats.setdefault(key,{'frames':0,'evaluatedFrames':0,'withheld':collections.Counter(),'invalidJointOpportunities':0,'usedPredictionJointOpportunities':0,'exactPassthroughJointOpportunities':0,'expiredFallbackJointOpportunities':0,'corrections':[],'roles':collections.Counter(),'contacts':collections.Counter()});s['frames']+=1
        original=groups_by_name[row['exercise']][row['sequence']];o=row.get('observation')
        if not o:s['withheld'][row['withheldReason']]+=1;withheld[row['withheldReason']]+=1;continue
        assert [v for point in o['raw'] for v in point]==original['raw_3d'];raw_exact+=1
        assert o['source']['frame']==original['frame'] and o['source']['source_index']==original['source_index'] and o['source']['source_pts']==original['source_pts']
        assert not o['adopted_for_pose'] and not o['adopted_for_feedback']
        if o['corrected'] is None:
            for reason in o['reasons']:s['withheld'][reason]+=1;withheld[reason]+=1
            continue
        available+=1;s['evaluatedFrames']+=1;d=o['details'];
        assert not row['flush'] and len(d['used_prediction'])==len(o['invalid_for_assessment'])==17
        assert all(not used or o['invalid_for_assessment'][i] for i,used in enumerate(d['used_prediction']))
        assert d['grip_confirmed'] is False and d['contact_evidence']=='unknown'
        assert set(d['contacts'].values()) <= {'UNINITIALIZED'}
        assert d['person_identity']=='unknown' and d['personal_profile_applied'] is False and not d['online_profile_applied'];assert d['model_to_image_scale']==original['unit_px']/original['size'][1]
        confidence_diffs.extend(abs(a-b) for a,b in zip(d['observation_confidence_h36m'],original['confidence_h36m']))
        s['invalidJointOpportunities']+=sum(o['invalid_for_assessment']);s['usedPredictionJointOpportunities']+=sum(d['used_prediction']);s['roles'].update(d['roles']);s['contacts'].update(d['contacts'].values());s['corrections'].extend(o['correction_magnitude']);e=d['estimator'];s['exactPassthroughJointOpportunities']+=len(e.get('observation_passthrough',[]));s['expiredFallbackJointOpportunities']+=len(e.get('expired_prediction_fallback',[]))
        assert all(d['used_prediction'][i] and o['invalid_for_assessment'][i] for i in e.get('expired_prediction_fallback',[]))
    results=[]
    for (exercise,variant),s in sorted(stats.items()):
        values=s.pop('corrections');s['correctionModelUnits']={'median':statistics.median(values) if values else None,'max':max(values) if values else None};results.append({'exercise':exercise,'variant':variant,**s})
    assert all(digest(CAPTURE/name/'terminal-original.jsonl')==want for name,want in EXPECTED.items());assert source_hashes=={p:digest(ROOT/p) for p in SOURCES}
    save(out/'aggregate.json',{'status':'PASS_ACTUAL_SAVED_OBSERVER_REPLAY','counts':counts,'results':results,'evaluatedVariantFrames':available,'withheldVariantFrames':dict(withheld),'rawExactVariantFrames':raw_exact,'maximumRetainedConfidenceDifference':max(confidence_diffs),'binarySHA256':digest(binary),'observationsSHA256':digest(out/'observations.jsonl'),'inputAndSourcesUnchanged':True,'replaySeconds':elapsed,'newInference':False,'accuracyClaim':False})
    print(json.dumps({'status':'PASS','output':str(out),'evaluatedVariantFrames':available,'withheldVariantFrames':dict(withheld),'rawExactVariantFrames':raw_exact,'maximumRetainedConfidenceDifference':max(confidence_diffs)}))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',required=True,type=Path);run(p.parse_args().out)
