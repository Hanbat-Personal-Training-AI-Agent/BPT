#!/usr/bin/env python3
"""Compare existing private H traces; no compilation, inference or file mutation."""
import argparse,hashlib,json,math
from pathlib import Path

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text())
def compare(baseline,sensitivity,out):
    baseline=baseline.expanduser().resolve();sensitivity=sensitivity.expanduser().resolve();out=out.expanduser().resolve()
    private=(Path.home()/'bpt-data').resolve();assert all(p.is_relative_to(private) for p in [baseline,sensitivity,out]) and not out.exists()
    bf,sf=read(baseline/'freeze.json'),read(sensitivity/'freeze.json')
    assert bf['inputSHA256']==sf['inputSHA256']
    native={k:v for k,v in bf['sourceSHA256'].items() if k.startswith('ios/')}
    assert native=={k:v for k,v in sf['sourceSHA256'].items() if k.startswith('ios/')}
    assert bf['configuration']['fixedCameraAssertion'] is False and bf['configuration']['onlineProfile'] is False
    assert sf['configuration']['variants']==['H'] and sf['configuration']['fixedCameraAssertion'] and sf['configuration']['onlineProfile']
    paths=[baseline/'observations.jsonl',sensitivity/'observations.jsonl'];start={str(p):sha(p) for p in paths}
    for root,p in zip([baseline,sensitivity],paths):assert read(root/'aggregate.json')['observationsSHA256']==sha(p)
    old={}
    for line in paths[0].open():
        row=json.loads(line)
        if row['variant']=='H':old[(row['exercise'],row['sequence'])]=row
    stats={}
    for line in paths[1].open():
        new=json.loads(line);before=old.pop((new['exercise'],new['sequence']));s=stats.setdefault(new['exercise'],dict(rows=0,evaluated=0,maskChangedFrames=0,predictionChangedFrames=0,phaseChangedFrames=0,candidateChangedFrames=0,maximumCandidateDeltaModelUnits=0.0))
        s['rows']+=1;a=before.get('observation');b=new.get('observation')
        assert (a is None)==(b is None)
        if a is None:assert before['withheldReason']==new['withheldReason'];continue
        assert a['source']==b['source'] and a['raw']==b['raw'] and a['reasons']==b['reasons']
        assert (a['corrected'] is None)==(b['corrected'] is None)
        if a['corrected'] is None:continue
        s['evaluated']+=1;ad,bd=a['details'],b['details']
        assert ad['source_2d_height_normalized']==bd['source_2d_height_normalized'] and ad['model_to_image_scale']==bd['model_to_image_scale']
        s['maskChangedFrames']+=a['invalid_for_assessment']!=b['invalid_for_assessment'];s['predictionChangedFrames']+=ad['used_prediction']!=bd['used_prediction'];s['phaseChangedFrames']+=ad['phase']!=bd['phase'];s['candidateChangedFrames']+=a['corrected']!=b['corrected']
        s['maximumCandidateDeltaModelUnits']=max(s['maximumCandidateDeltaModelUnits'],max(math.dist(x,y) for x,y in zip(a['corrected'],b['corrected'])))
    assert not old and start=={str(p):sha(p) for p in paths}
    result={'schema':'bpt.motion-observer-policy-comparison.v1','policy':'separate declared fixed-camera/online-prior H sensitivity versus unknown-camera no-profile H','notContactAccuracy':True,'baselineArtifactsUnchanged':True,'nativeSourcesUnchanged':True,'traceSHA256':start,'inputSHA256':bf['inputSHA256'],'comparison':stats,'comparisonSourceSHA256':sha(Path(__file__))}
    out.write_text(json.dumps(result,indent=2,sort_keys=True));out.chmod(0o600)
    print(json.dumps(stats,sort_keys=True))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--baseline',type=Path,required=True);p.add_argument('--sensitivity',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();compare(a.baseline,a.sensitivity,a.out)
