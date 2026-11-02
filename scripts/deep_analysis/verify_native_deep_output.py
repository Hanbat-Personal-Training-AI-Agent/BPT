#!/usr/bin/env python3
"""Local-only actual result verification; no inference/network/GT or output substitution."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import zipfile
import numpy as np

ALLOWED={'result.npz','timing.json','overlay.mp4','worker_report.json','current_metrics.json',
         'before_metrics.json','before_error.json','current_error.json','evidence.json','run.log'}
REQUIRED={'result.npz','timing.json','overlay.mp4','worker_report.json','current_metrics.json','evidence.json','run.log'}
MODULES={'deep_analysis.py':'current/server/calibration_modal/deep_analysis.py','deep_metrics.py':'current/server/calibration_modal/deep_metrics.py',
         'deep_worker.py':'current/server/calibration_modal/deep_worker.py','checks.py':'current/server/calibration_modal/checks.py','gvhmr_runner.py':'current/scripts/deep_analysis/gvhmr_runner.py'}


def require(ok,reason):
    if not ok:raise ValueError(reason)


def digest(data):return hashlib.sha256(data).hexdigest()
def sha(path):
    state=hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''):state.update(block)
    return state.hexdigest()
def observed_numbers(values):
    return [float(value) if np.isfinite(value) else {'nonfiniteRawValue':str(value)} for value in values]

def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def load(path):
    def unique(pairs):
        out={}
        for k,v in pairs:require(k not in out,'duplicate JSON key');out[k]=v
        return out
    def invalid(value):raise ValueError('nonfinite JSON')
    return json.loads(Path(path).read_bytes(),object_pairs_hook=unique,parse_constant=invalid)
def save(path,value):
    with Path(path).open('xb') as f:f.write(canonical(value))
    Path(path).chmod(0o600)


def unpack_checked(archive,output):
    with zipfile.ZipFile(archive) as source:
        names=source.namelist();require(len(names)==len(set(names)),'duplicate ZIP entry')
        require(set(names)<=ALLOWED and REQUIRED<=set(names),'unknown/missing archive entry')
        require('current_error.json' not in names and (('before_metrics.json' in names)!=('before_error.json' in names)),'contradictory result entries')
        require(sum(v.file_size for v in source.infolist())<=512*1024*1024,'expanded archive cap')
        for entry in source.infolist():
            require(not stat.S_ISLNK(entry.external_attr>>16) and entry.file_size<=256*1024*1024,'ZIP type/size')
            target=output/entry.filename
            with source.open(entry) as f,target.open('xb') as out:
                while True:
                    data=f.read(1048576)
                    if not data:break
                    out.write(data)
            target.chmod(0o600)


def video_clock(path):
    raw=subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_frames','-show_entries',
        'stream=duration,r_frame_rate,avg_frame_rate,nb_frames,time_base:frame=best_effort_timestamp_time','-of','json',str(path)])
    data=json.loads(raw);pts=[float(f['best_effort_timestamp_time']) for f in data.get('frames',[]) if 'best_effort_timestamp_time' in f]
    return {'decodedFrameCount':len(data.get('frames',[])),'timestampCount':len(pts),'stream':data.get('streams',[]),
        'ptsSha256':digest(json.dumps(pts,separators=(',',':')).encode())},pts


def scoring_contract(report):
    """Only null/assessment semantics, not extra finite-only admission or numeric tolerances."""
    fields={'anglesDeg','depthAngleDeg','romDeg','tempoSeconds','trunkStability','symmetryDeg','handPath','fatigueDrift',
            'topFrame','bottomFrame','topTime','bottomTime'}
    def null_paths(value,prefix):
        if value is None:return [prefix]
        if isinstance(value,dict):return [p for k,v in value.items() for p in null_paths(v,prefix+'.'+k)]
        if isinstance(value,list):return [p for i,v in enumerate(value) for p in null_paths(v,prefix+'['+str(i)+']')]
        return []
    return [{'repIndex':rep['repIndex'],
             'metricNullPaths':sorted(p for k in fields if k in rep for p in null_paths(rep[k],k)),
             'metricValidity':{key:{'assessment':value.get('assessment'),'reasons':sorted(value.get('reasons',[]))}
                               for key,value in rep.get('metricValidity',{}).items()},
             'repReasons':sorted(rep.get('validity',{}).get('reasons',[])),
             'serverWarnings':sorted(rep.get('serverWarnings',[])),
             'evaluatedKeys':sorted(rep.get('evaluatedKeys',[])),
             'faultKeys':sorted(f.get('key','') for f in rep.get('faults',[]))} for rep in report['reps']]


def replay_saved_inputs_locally(plan,manifest,world,raw_confidence,tracked,meta,output):
    """Replay only frozen numerical scorers; raw missingness/tracking is never filled."""
    repository=Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix='local-numeric-replay-',dir=output) as temporary:
        work=Path(temporary)
        for key,expected in plan['sourceSha256'].items():
            label,relative=key.split('/',1)
            require(label in ('current','before') and not relative.startswith('/') and '..' not in Path(relative).parts,'snapshot path')
            commit=plan['currentSourceCommit'] if label=='current' else plan['beforeScorerCommit']
            source=subprocess.check_output(['git','-C',str(repository),'show',commit+':'+relative])
            require(digest(source)==expected,'local replay source hash')
            target=work/key;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(source)
        # Exactly the worker's established support derivation, not a new confidence rule.
        support=np.clip(raw_confidence,0,1)*(meta['person_frames']/meta['frames'])
        np.savez(work/'observed.npz',world=world,support=support,tracked=tracked)
        save(work/'manifest.json',manifest)
        code="""
import json,sys,hashlib,numpy as np
from pathlib import Path
work=Path(sys.argv[1]);label=sys.argv[2];sys.path.insert(0,str(work/label/'server/calibration_modal'))
import deep_metrics
try:
 with np.load(work/'observed.npz',allow_pickle=False) as data:
  report=deep_metrics.metrics(data['world'],30,json.loads((work/'manifest.json').read_text()),confidence=data['support'].mean(axis=1),joint_confidence=data['support'],tracked_mask=data['tracked'])
 result={'ok':True,'report':report}
 json.dumps(result,allow_nan=False)
except Exception as error:result={'ok':False,'errorType':type(error).__name__,'code':getattr(error,'code',None)}
(work/(label+'-replay.json')).write_text(json.dumps(result,sort_keys=True,separators=(',',':'),allow_nan=False))
"""
        results={}
        for label in ('current','before'):
            subprocess.run([sys.executable,'-I','-c',code,str(work),label],check=True,capture_output=True,timeout=45)
            results[label]=load(work/(label+'-replay.json'))
        current=load(Path(output)/'current_metrics.json')
        require(results['current']['ok'],'current numerical CPU replay failed')
        require(scoring_contract(results['current']['report'])==scoring_contract(current),'raw per-joint/tracking null/assessment contract mismatch')
        proof={'scope':'local_CPU_frozen_scorers_actual_same_saved_inputs_no_model',
               'rawInputsFilledOrFiltered':False,'currentNullAssessmentReasonsConsistent':True,
               'currentExactCanonicalParity':canonical(results['current']['report'])==canonical(current),
               'currentMetricNullScalars':sum(len(r['metricNullPaths']) for r in scoring_contract(current))}
        before=Path(output)/'before_metrics.json'
        if before.exists():
            require(results['before']['ok'],'before numerical CPU replay unexpectedly failed')
            original=load(before)
            require(scoring_contract(results['before']['report'])==scoring_contract(original),'before null/assessment contract mismatch')
            proof['beforeExactCanonicalParity']=canonical(results['before']['report'])==canonical(original)
        else:
            original=load(Path(output)/'before_error.json')
            require(not results['before']['ok'] and all(results['before'].get(k)==original.get(k) for k in ('errorType','code')),'before error reproduction mismatch')
            proof['beforeErrorReproduced']=True
        save(Path(output)/'local-numeric-replay-proof.json',proof)
        return proof


def verify(execution,package,video,expected_plan_sha,output):
    execution,package,output=map(Path,(execution,package,output));plan=load(execution/'run_plan.json')
    require(sha(execution/'run_plan.json')==expected_plan_sha,'plan SHA')
    complete=load(execution/'completion.json');run=load(execution/'execution.json')
    require(complete['status']=='complete_transport_and_zero_return_code' and type(run.get('returnCode')) is int and run['returnCode']==0,'incomplete/nonzero execution')
    require(run['planSha256']==expected_plan_sha and run['gpuCalls']==1 and run['retried'] is False,'execution binding')
    archive=execution/'artifact.complete.bin';require(sha(archive)==complete['sha256']==run['artifactSha256'] and archive.stat().st_size==complete['bytes'],'archive SHA/size')
    require(sha(video)==plan['videoSha256'],'original video SHA')
    manifest=load(package/'reps.json');require(digest(canonical(manifest))==plan['serviceReadyManifestCanonicalSha256'],'service manifest SHA')
    output.mkdir(mode=0o700);unpack_checked(archive,output)
    report=load(output/'worker_report.json');current=load(output/'current_metrics.json');evidence=load(output/'evidence.json');meta=load(output/'timing.json')
    require(evidence['inputVideoSha256']==plan['videoSha256'] and evidence['pinnedNativeManifestCanonicalSha256']==plan['serviceReadyManifestCanonicalSha256'],'remote input binding')
    require(evidence['nativeManifestUnchanged'] is True and evidence['nativeManifestRetimed'] is False,'original interval integrity')
    require(evidence['sourceSnapshotsSha256']==plan['sourceSha256'],'source snapshots')
    require(evidence['actualImportedSourceSha256']=={name:plan['sourceSha256'][relative] for name,relative in MODULES.items()},'actual imported source')
    require(evidence['upstreamCommit']=='ee960bb6e2ea2d381aa97f08e9b71ef320b624b1','upstream model code')
    require(evidence['precisionHalf'] is False and meta['half'] is False and evidence['externalBetaUsed'] is False,'precision/body profile')
    require(set(evidence['weightsSha256'])==set(plan['weightFilesAndBytes']) and all(re.fullmatch('[0-9a-f]{64}',v) for v in evidence['weightsSha256'].values()),'actual weight hashes')
    require(report['exerciseId']==manifest['exerciseId'] and len(report['reps'])==len(manifest['reps']),'report exercise/rep count')
    for original,rep in zip(manifest['reps'],report['reps']):require(canonical({k:rep[k] for k in original})==canonical(original),'original rep observations')
    stripped={k:v for k,v in report.items() if k not in {'timingSeconds','runnerElapsedSeconds','resourceUsage','processingTimingSeconds','bodyShape'}}
    require(canonical(stripped)==canonical(current),'worker report/core report mismatch')
    require(sha(output/'current_metrics.json')==evidence['currentMetricsSha256'],'current core digest')
    before=output/'before_metrics.json'
    if before.exists():
        require(sha(before)==evidence['beforeMetricsSha256'],'before core digest')
        require((before.read_bytes()==(output/'current_metrics.json').read_bytes()) is evidence['canonicalContentParity'],'reported parity')
    require(evidence['trackedMaskSource']=='observed_saved_runner_output','tracking provenance')
    with np.load(output/'result.npz',allow_pickle=False) as data:
        world=data['h36m17_world'];conf=data['vitpose_coco17'][:,:,2];tracked=data['tracked_mask'];bbox=data['bbx_xyxy'];n=len(world)
        require(world.shape==(n,17,3) and data['vitpose_coco17'].shape==(n,17,3) and bbox.shape==(n,4),'saved observed array shapes')
        require(tracked.dtype==np.bool_ and tracked.shape==(n,) and int(tracked.sum())==evidence['trackedFrames'],'saved tracking mask/count')
        require(n==evidence['frames']==meta['frames'] and 0<=meta['person_frames']<=n,'frame/support count')
        require('h36m17_world_gvhmr_beta' not in data.files,'unexpected calibrated body output')
        array_proof={'frames':n,'worldShape':list(world.shape),'trackedFrames':int(tracked.sum()),'untrackedFrames':int((~tracked).sum()),
            'trackedMaskSha256':digest(tracked.tobytes()),'rawVitPoseConfidenceSha256':digest(conf.tobytes()),'worldArraySha256':digest(world.tobytes()),
            'nonfiniteWorldScalars':int((~np.isfinite(world)).sum()),'nonfiniteConfidenceScalars':int((~np.isfinite(conf)).sum())}
        numerical_replay=replay_saved_inputs_locally(plan,manifest,world,conf,tracked,meta,output)
        overlay,pts=video_clock(output/'overlay.mp4');require(overlay['decodedFrameCount']==overlay['timestampCount']==n,'overlay/array frame count')
        remote=evidence['videoClocks'];require(remote['original']['sha256']==plan['videoSha256'],'remote source clock input')
        require(all(remote[k]['decodedFrameCount']==n for k in ('workerNormalized','runnerPrepared')),'prepared/normalized array frame count')
        require(overlay['ptsSha256']==remote['runnerPrepared']['ptsSha256'],'overlay/prepared actual PTS grid')
        frame=min(range(n),key=lambda i:abs(pts[i]-2.1333333333333333));require(abs(pts[frame]-2.1333333333333333)<1e-6,'requested observation time unavailable')
        save(output/'occlusion-time-observation-private.json',{'scope':'saved_prediction_observations_not_visibility_GT','actualOverlayFrame':frame,
            'actualOverlayPtsSeconds':pts[frame],'trackedMask':bool(tracked[frame]),'detectorBoxXyxy':observed_numbers(bbox[frame]),
            'rawVitPoseCoco17Confidence':observed_numbers(conf[frame]),'estimatedWorldShape':list(world[frame].shape)})
    summary={'status':'verified_actual_isolated_report_not_authenticated_API','planSha256':expected_plan_sha,'archiveSha256':complete['sha256'],
        'inputVideoSha256':plan['videoSha256'],'serviceManifestSha256':plan['serviceReadyManifestCanonicalSha256'],
        'sourceSnapshotsAndActualImportedHashesMatched':True,'actualInputObservationsPreserved':True,'repetitionsEvaluatedFromNativeManifest':len(report['reps']),
        'separateRepDetectionClaimed':False,'arrays':array_proof,'localNumericalReplay':numerical_replay,'overlayClock':overlay,'occlusionSampleActualFrame':frame,
        'occlusionSampleActualPtsSeconds':pts[frame],'canonicalCoreBeforeCurrentParity':evidence['canonicalContentParity'],
        'coreValidityBefore':evidence['beforeMetricValidityCounts'],'coreValidityCurrent':evidence['currentMetricValidityCounts'],
        'currentNullScalars':evidence['currentReportNullScalars'],'beforeReportAvailable':evidence['beforeReportAvailable'],
        'artifactSha256':{f.name:sha(f) for f in output.iterdir() if f.is_file()}}
    save(output/'verification-summary.json',summary);return summary


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('execution-dir','package','video','expected-plan-sha','output-dir'):p.add_argument('--'+name,required=True)
    a=p.parse_args()
    try:r=verify(a.execution_dir,a.package,a.video,a.expected_plan_sha,a.output_dir)
    except Exception as error:print(json.dumps({'status':'rejected_not_report_ready','errorType':type(error).__name__}));return 2
    print(json.dumps(r,indent=2));return 0


if __name__=='__main__':raise SystemExit(main())
