#!/usr/bin/env python3
"""Prepare by default. Explicitly approved single private L4 verification only; no deploy/API job.

Reuses a PINNED existing image and read-only weights volume. No secrets, downloads,
foreign beta, retries, additional invocations or production configuration changes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

BEFORE='17583f391f6dd028bf0515b2be3e8d2257c95866'
CURRENT='4eea822'
IMAGE='im-4SiTgQLfJqcNflEuz14dR3'
VOLUME='vo-PaJI2oGtteoNeTikv2DP3O'
REQUIRED={'gvhmr/gvhmr_siga24_release.ckpt':163508011,'hmr2/epoch=10-step=25000.ckpt':2709494041,
'vitpose/vitpose-h-multi-coco.pth':2549075546,'yolo/yolov8x.pt':136867539,'smpl_neutral_h36m.npz':35029082,
'body_models/smplx/SMPLX_NEUTRAL.npz':108752058,'body_models/smpl/SMPL_NEUTRAL.pkl':89461460}
CURRENT_FILES=['server/calibration_modal/deep_worker.py','server/calibration_modal/deep_analysis.py',
 'server/calibration_modal/deep_metrics.py','server/calibration_modal/checks.py','server/calibration_modal/deep_rules.csv',
 'scripts/deep_analysis/gvhmr_runner.py']
OLD_FILES=['server/calibration_modal/deep_metrics.py','server/calibration_modal/checks.py','server/calibration_modal/deep_rules.csv']


def sha(data):return hashlib.sha256(data).hexdigest()
def canonical(data):return json.dumps(data,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def prepare(root,package,video,expected_video_sha,expected_manifest_sha,capture_source_commit):
    root=Path(root);package=Path(package);video=Path(video)
    verification=json.loads((package/'verification.json').read_text())
    manifest=json.loads((package/'reps.json').read_text())
    if video.stat().st_size>32*1024*1024 or (package/'reps.json').stat().st_size>256*1024:raise ValueError('service input size cap exceeded')
    import re
    if not re.fullmatch('[0-9a-f]{64}',expected_video_sha) or not re.fullmatch('[0-9a-f]{64}',expected_manifest_sha) or not re.fullmatch('[0-9a-f]{40}',capture_source_commit):raise ValueError('explicit exact input/capture-source digests required')
    if verification['status']!='exact_video_and_manifest_verified' or verification['copiedVideoSha256']!=expected_video_sha or verification['canonicalNativeManifestSha256']!=expected_manifest_sha or sha(video.read_bytes())!=expected_video_sha or sha(canonical(manifest))!=expected_manifest_sha:
        raise ValueError('not the approved-scope original video/native manifest')
    snapshots={}
    for relative in CURRENT_FILES:snapshots['current/'+relative]=subprocess.check_output(['git','-C',str(root),'show',CURRENT+':'+relative])
    for relative in OLD_FILES:snapshots['before/'+relative]=subprocess.check_output(['git','-C',str(root),'show',BEFORE+':'+relative])
    # Preserve catalog presence/absence independently; never silently inject a different rubric.
    for label,commit in [('current',None),('before',BEFORE)]:
        path='docs/coaching/fault_catalog.csv'
        if commit:
            result=subprocess.run(['git','-C',str(root),'show',commit+':'+path],capture_output=True)
            if result.returncode==0:snapshots[label+'/'+path]=result.stdout
        else:
            result=subprocess.run(['git','-C',str(root),'show',CURRENT+':'+path],capture_output=True)
            if result.returncode==0:snapshots[label+'/'+path]=result.stdout
    plan={'schemaVersion':1,'purpose':'isolated_current_worker_not_deployed_API','videoSha256':expected_video_sha,
      'nativeManifestCanonicalSha256':expected_manifest_sha,'videoBytes':video.stat().st_size,'manifestBytes':len((package/'reps.json').read_bytes()),
      'sourceKind':'verified_native_capture_current_service_replay','captureSourceCommit':capture_source_commit,
      'currentSourceCommit':subprocess.check_output(['git','-C',str(root),'rev-parse',CURRENT],text=True).strip(),
      'beforeScorerCommit':BEFORE,'imageId':IMAGE,'volumeId':VOLUME,'weightFilesAndBytes':REQUIRED,
      'sourceSha256':{name:sha(data) for name,data in snapshots.items()},
      'executionScriptSha256':sha(Path(__file__).read_bytes()),
      'resources':{'gpu':'L4','gpuCount':1,'cpuRequested':2,'cpuLimit':4,'memoryRequestedMiB':8192,'memoryLimitMiB':16384,
       'timeoutSeconds':900,'startupTimeoutSeconds':120,'scaledownSeconds':2,'maxContainers':1,'minContainers':0,'retries':0,'maxInvocations':1},
      'precision':'production_runner_default_fp32_half_false','externalBeta':None,'bodyShape':'gvhmr_model_estimated_no_personal_profile',
      'networkBlockedInGpuContainer':True,'secretsAttached':False,'weightsReadOnly':True,'newImageBuild':False,
      'sourceMountedWithoutCrossVersionPickle':True,
      'remoteTempFilesRemovedInFinally':True,'providerMetadataRetentionNotErasedByUs':True,
      'expectedPrivateArtifacts':['result.npz','timing.json','worker_report.json','current_metrics.json','before_metrics.json_or_error','overlay.mp4','evidence.json','run.log'],
      'mediaTransportApproved':False,'gpuExecuted':False}
    return plan,snapshots,manifest


# Self-contained source-mounted function: no cross-Python serialized code objects.
def gpu_once(payload):
    import hashlib,json,os,subprocess,sys,tempfile,traceback,zipfile
    from pathlib import Path
    def h(path):
        obj=hashlib.sha256()
        with Path(path).open('rb') as source:
            for block in iter(lambda:source.read(1024*1024),b''):obj.update(block)
        return obj.hexdigest()
    plan=payload['plan']
    if hashlib.sha256(payload['video']).hexdigest()!=plan['videoSha256']:raise ValueError('remote input SHA mismatch')
    manifest_sha=hashlib.sha256(json.dumps(payload['manifest'],sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
    if manifest_sha!=plan['nativeManifestCanonicalSha256']:raise ValueError('remote pinned manifest SHA mismatch')
    # Existing immutable assets only; missing/mutated sizes STOP before any model invocation.
    weights={}
    for name,size in plan['weightFilesAndBytes'].items():
        path=Path('/vol')/name
        if not path.is_file() or path.stat().st_size!=size:raise ValueError('existing asset missing/size changed')
        weights[name]=h(path)
    with tempfile.TemporaryDirectory(prefix='bpt-owned-native-verify-') as temporary:
        work=Path(temporary)
        for relative,data in payload['sources'].items():
            if relative.startswith('/') or '..' in Path(relative).parts:raise ValueError('unsafe snapshot path')
            if hashlib.sha256(data).hexdigest()!=plan['sourceSha256'][relative]:raise ValueError('source SHA mismatch')
            path=work/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
        (work/'video.mp4').write_bytes(payload['video'])
        (work/'reps.json').write_text(json.dumps(payload['manifest'],allow_nan=False))
        (work/'plan.json').write_text(json.dumps(plan))
        # Fresh child imports exactly staged source, never bundled old worker modules.
        code=r'''
import hashlib,json,os,sys,subprocess
from pathlib import Path
import numpy as np
work=Path(sys.argv[1]);plan=json.loads((work/'plan.json').read_text());m=json.loads((work/'reps.json').read_text())
sys.path[:0]=[str(work/'current/server/calibration_modal'),str(work/'current/scripts/deep_analysis')]
import deep_analysis,deep_metrics,deep_worker,checks,gvhmr_runner
pinned_manifest_sha=hashlib.sha256(json.dumps(m,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
if pinned_manifest_sha!=plan['nativeManifestCanonicalSha256']:raise ValueError('staged pinned manifest SHA mismatch')
if deep_analysis.manifest((work/'reps.json').read_bytes(),m['sessionId'])!=m:raise ValueError('manifest changed')
if gvhmr_runner.run.__defaults__[1] is not False:raise ValueError('unexpected default precision')
source_hashes={name:hashlib.sha256((work/name).read_bytes()).hexdigest() for name in plan['sourceSha256']}
if source_hashes!=plan['sourceSha256']:raise ValueError('staged sources changed')
actual={name:hashlib.sha256(Path(module.__file__).read_bytes()).hexdigest() for name,module in [('deep_analysis.py',deep_analysis),('deep_metrics.py',deep_metrics),('deep_worker.py',deep_worker),('checks.py',checks),('gvhmr_runner.py',gvhmr_runner)]}
module_paths={'deep_analysis.py':'current/server/calibration_modal/deep_analysis.py','deep_metrics.py':'current/server/calibration_modal/deep_metrics.py','deep_worker.py':'current/server/calibration_modal/deep_worker.py','checks.py':'current/server/calibration_modal/checks.py','gvhmr_runner.py':'current/scripts/deep_analysis/gvhmr_runner.py'}
modules={'deep_analysis.py':deep_analysis,'deep_metrics.py':deep_metrics,'deep_worker.py':deep_worker,'checks.py':checks,'gvhmr_runner.py':gvhmr_runner}
for name,relative in module_paths.items():
 if actual[name]!=plan['sourceSha256'][relative] or Path(modules[name].__file__).resolve()!=(work/relative).resolve():raise ValueError('bundled or changed source imported')
upstream=subprocess.check_output(['git','-C','/opt/GVHMR','rev-parse','HEAD'],text=True).strip()
if upstream!='ee960bb6e2ea2d381aa97f08e9b71ef320b624b1':raise ValueError('upstream model code changed')
out=work/'analysis';out.mkdir()
try:
 report,overlay=deep_worker.analyze(work/'video.mp4',out,m,lambda n:None,beta=None)
except Exception as error:
 (work/'current_error.json').write_text(json.dumps({'errorType':type(error).__name__,'code':getattr(error,'code',None),'scope':'actual_current_worker_analyze_rejected_no_retry'}))
 raise
report['bodyShape']={'source':'gvhmr_fallback'}
(work/'worker_report.json').write_text(json.dumps(report,allow_nan=False))
result=out/'gvhmr/result.npz';meta=json.loads((out/'gvhmr/timing.json').read_text())
with np.load(result,allow_pickle=False) as arrays:
 if 'tracked_mask' not in arrays:raise ValueError('actual tracking provenance absent; no mask invented')
 tracked=arrays['tracked_mask'];world=arrays['h36m17_world'];raw_support=arrays['vitpose_coco17'][:,:,2]
 if tracked.dtype!=np.bool_ or tracked.shape!=(len(world),):raise ValueError('invalid observed tracking')
 support=np.clip(raw_support,0,1)*(meta['person_frames']/meta['frames'])
 current=deep_metrics.metrics(world,30,m,confidence=support.mean(axis=1),joint_confidence=support,tracked_mask=tracked)
 (work/'current_metrics.json').write_text(json.dumps(current,sort_keys=True,separators=(',',':'),allow_nan=False))
 # Same numerical arrays/support; scorer-only subprocess, no second inference.
 np.savez(work/'metric_inputs.npz',world=world,support=support,tracked=tracked)
old=r"""
import sys,json,numpy as np
from pathlib import Path
work=Path(sys.argv[1]);sys.path.insert(0,str(work/'before/server/calibration_modal'))
import deep_metrics
if Path(deep_metrics.__file__).resolve()!=(work/'before/server/calibration_modal/deep_metrics.py').resolve():raise ValueError('wrong before scorer import')
expected=json.loads((work/'plan.json').read_text())['sourceSha256']['before/server/calibration_modal/deep_metrics.py']
if __import__('hashlib').sha256(Path(deep_metrics.__file__).read_bytes()).hexdigest()!=expected:raise ValueError('before scorer hash mismatch')
m=json.loads((work/'reps.json').read_text())
try:
 with np.load(work/'metric_inputs.npz',allow_pickle=False) as z:
  report=deep_metrics.metrics(z['world'],30,m,confidence=z['support'].mean(axis=1),joint_confidence=z['support'],tracked_mask=z['tracked'])
 (work/'before_metrics.json').write_text(json.dumps(report,sort_keys=True,separators=(',',':'),allow_nan=False))
except Exception as error:
 (work/'before_error.json').write_text(json.dumps({'errorType':type(error).__name__,'code':getattr(error,'code',None)}))
"""
subprocess.run([sys.executable,'-c',old,str(work)],check=True)
def count_null(value):
 return sum(count_null(v) for v in value.values()) if isinstance(value,dict) else sum(count_null(v) for v in value) if isinstance(value,list) else int(value is None)
before=work/'before_metrics.json'
evidence={'inputVideoSha256':hashlib.sha256((work/'video.mp4').read_bytes()).hexdigest(),'nativeManifestUnchanged':m==json.loads((work/'reps.json').read_text()),'pinnedNativeManifestCanonicalSha256':pinned_manifest_sha,'actualImportedSourceSha256':actual,'sourceSnapshotsSha256':source_hashes,'upstreamCommit':upstream,'trackedMaskSource':'observed_saved_runner_output','trackedFrames':int(tracked.sum()),'frames':len(world),'precisionHalf':meta['half'],'externalBetaUsed':False,'bodyShape':'gvhmr_model_estimated','workerScope':'isolated_current_analyze_not_authenticated_API','currentReportNullScalars':count_null(current),'beforeReportAvailable':before.exists(),'canonicalContentParity':before.read_bytes()==(work/'current_metrics.json').read_bytes() if before.exists() else None,'currentMetricsSha256':hashlib.sha256((work/'current_metrics.json').read_bytes()).hexdigest(),'beforeMetricsSha256':hashlib.sha256(before.read_bytes()).hexdigest() if before.exists() else None}
def clock(path):
 if not path.exists():return {'available':False}
 command=['ffprobe','-v','error','-select_streams','v:0','-show_frames','-show_entries','stream=duration,r_frame_rate,avg_frame_rate,nb_frames,time_base:frame=best_effort_timestamp_time','-of','json',str(path)]
 data=json.loads(subprocess.check_output(command));pts=[float(f['best_effort_timestamp_time']) for f in data.get('frames',[]) if 'best_effort_timestamp_time' in f]
 return {'available':True,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'stream':data.get('streams',[]),'decodedFrameCount':len(data.get('frames',[])),'timestampCount':len(pts),'firstPtsSeconds':min(pts) if pts else None,'lastPtsSeconds':max(pts) if pts else None,'uniquePtsCount':len(set(pts)),'minObservedPtsDeltaSeconds':min([b-a for a,b in zip(pts,pts[1:])]) if len(pts)>1 else None,'maxObservedPtsDeltaSeconds':max([b-a for a,b in zip(pts,pts[1:])]) if len(pts)>1 else None,'ptsSha256':hashlib.sha256(json.dumps(pts,separators=(',',':')).encode()).hexdigest()}
def validity_counts(report):
 counts={};reasons={}
 for rep in report.get('reps',[]):
  for value in rep.get('metricValidity',{}).values():
   if not isinstance(value,dict):continue
   key=value.get('assessment','unknown');counts[key]=counts.get(key,0)+1
   for reason in value.get('reasons',[]):reasons[reason]=reasons.get(reason,0)+1
 return {'assessmentFields':counts,'reasonFields':reasons}
evidence['currentMetricValidityCounts']=validity_counts(current)
evidence['beforeMetricValidityCounts']=validity_counts(json.loads(before.read_text())) if before.exists() else None
evidence['videoClocks']={'original':clock(work/'video.mp4'),'workerNormalized':clock(out/'normalized.mp4'),'runnerPrepared':clock(out/'gvhmr/input_30fps.mp4')}
evidence['nativeManifestRetimed']=False
evidence['preprocessingDuplicatesAreNewIndependentObservations']=False
(work/'evidence.json').write_text(json.dumps(evidence,indent=2,allow_nan=False))
'''
        environment=os.environ.copy()
        environment['BPT_GVHMR_ROOT']='/opt/GVHMR';environment['BPT_SMPL_H36M_NPZ']='/vol/smpl_neutral_h36m.npz'
        with (work/'run.log').open('w') as log:
            result=subprocess.run([sys.executable,'-c',code,str(work)],stdout=log,stderr=log,env=environment)
        evidence=work/'evidence.json'
        if evidence.exists():
            value=json.loads(evidence.read_text());value['weightsSha256']=weights;evidence.write_text(json.dumps(value,indent=2))
        # Return only private artifacts, never model weights or source video. Temp dir removed afterward.
        import io
        archive=io.BytesIO()
        choices={'analysis/gvhmr/result.npz':'result.npz','analysis/gvhmr/timing.json':'timing.json',
          'analysis/overlay.mp4':'overlay.mp4','worker_report.json':'worker_report.json','current_metrics.json':'current_metrics.json',
          'before_metrics.json':'before_metrics.json','before_error.json':'before_error.json','current_error.json':'current_error.json','evidence.json':'evidence.json','run.log':'run.log'}
        with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as target:
            for relative,name in choices.items():
                path=work/relative
                if path.is_file():target.write(path,name)
        return {'returnCode':result.returncode,'archive':archive.getvalue(),'remoteTempCleanupOnReturn':True}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',required=True);p.add_argument('--package',required=True);p.add_argument('--video',required=True)
    p.add_argument('--expected-video-sha',required=True);p.add_argument('--expected-native-manifest-sha',required=True);p.add_argument('--capture-source-commit',required=True)
    p.add_argument('--output-dir',required=True);p.add_argument('--execute',action='store_true');p.add_argument('--approved-plan-sha')
    args=p.parse_args();plan,sources,manifest=prepare(args.root,args.package,args.video,args.expected_video_sha,args.expected_native_manifest_sha,args.capture_source_commit)
    plan_sha=sha(canonical(plan));output=Path(args.output_dir)
    if not args.execute:
        output.mkdir(mode=0o700)
        (output/'run_plan.json').write_bytes(canonical(plan))
        (output/'run_plan.sha256').write_text(plan_sha+'\n')
        print(json.dumps({'mode':'prepared_only','planSha256':plan_sha,'gpuInvocations':0,'mediaTransferred':False}));return 0
    # Transfer authorization is external/user-controlled, never inferred from credentials or metadata lookup.
    import os
    if args.approved_plan_sha!=plan_sha or os.environ.get('BPT_NATIVE_VIDEO_TRANSFER_APPROVED')!=plan['videoSha256']:
        raise PermissionError('explicit approval for this exact frozen video/plan is required')
    if output.exists():raise FileExistsError('execution output must be new')
    import modal
    deployed=modal.Function.from_name('bpt-calibration','deep_analysis_job');info=deployed.info()
    if info.image_info.image_id!=IMAGE:raise ValueError('pinned existing image changed; no automatic replacement')
    volume=modal.Volume.from_name('bpt-gvhmr',create_if_missing=False);volume.hydrate()
    if volume.object_id!=VOLUME:raise ValueError('weights volume identity changed')
    image=modal.Image.from_id(IMAGE)
    app=modal.App('bpt-owned-native-report-verification')
    call=app.function(image=image,gpu='L4',cpu=(2,4),memory=(8192,16384),timeout=900,startup_timeout=120,
      min_containers=0,max_containers=1,buffer_containers=0,scaledown_window=2,retries=0,
      secrets=[],volumes={'/vol':volume.read_only()},block_network=True,restrict_modal_access=True,
      serialized=False,include_source=True,max_inputs=1)(gpu_once)
    output.mkdir(mode=0o700)
    with app.run(detach=False):
        result=call.remote({'plan':plan,'sources':sources,'manifest':manifest,'video':Path(args.video).read_bytes()})
    (output/'artifacts_PRIVATE.zip').write_bytes(result['archive'])
    (output/'run_plan.json').write_bytes(canonical(plan))
    (output/'execution.json').write_text(json.dumps({'returnCode':result['returnCode'],'planSha256':plan_sha,
      'imageId':IMAGE,'volumeId':VOLUME,'invocations':1,'retried':False,'normalApiJobCreated':False,
      'remoteTempCleanupOnReturn':result['remoteTempCleanupOnReturn']},indent=2))
    print(json.dumps({'returnCode':result['returnCode'],'invocations':1,'retried':False}))
    return 0 if result['returnCode']==0 else 2


if __name__=='__main__':raise SystemExit(main())
