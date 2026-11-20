#!/usr/bin/env python3
"""Prepare-only default: same analysis once, strict inline return transport.

A new exact video/plan authorization is mandatory before any remote GPU call.
The historical approved analysis script is imported unchanged and source-pinned.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import sys
import time
import traceback
import zipfile

import native_deep_isolated_l4 as analysis
import inline_result_transport as transport

APP='bpt-owned-native-inline-report-verification'
OLD_SCRIPT_SHA='e7dc9ec5e9d7aefbc6f11a00696dc6c9841e11c7fa51e549570ea98b97e057f1'
PUBLIC_FILES=('native_deep_inline_l4.py','native_deep_isolated_l4.py','inline_result_transport.py')


def source_inventory():
    directory=Path(__file__).resolve().parent
    return [{'remotePath':'/root/'+name,'sha256':transport.digest((directory/name).read_bytes())} for name in PUBLIC_FILES]


def prepare(root,package,video,video_sha,manifest_sha,capture_commit):
    transport.require(transport.digest(Path(analysis.__file__).read_bytes())==OLD_SCRIPT_SHA,'historical approved analysis script changed')
    plan,sources,manifest=analysis.prepare(root,package,video,video_sha,manifest_sha,capture_commit)
    plan['approvedAnalysisScriptSha256']=plan['executionScriptSha256']
    plan['executionScriptSha256']=transport.digest(Path(__file__).read_bytes())
    plan['resources'].update(timeoutSeconds=600,startupTimeoutSeconds=90)
    plan['resultTransport']={'schema':transport.SCHEMA,'chunkBytes':transport.CHUNK_BYTES,'maximumArchiveBytes':transport.MAX_BYTES,
        'requiresEndAndEOF':True,'requiresZeroReturnCode':True,'generatorAutomaticRetriesSupported':False,
        'partialFile':'artifact.incomplete.part','completeFile':'artifact.complete.bin','completionReceipt':'completion.json'}
    plan['publicSourceMounts']=source_inventory()
    plan['sourceMountScope']='three_exact_public_files_no_directory_mount_copyFalse_no_image_build'
    plan['previousAttemptContainerToOutputErrorSeconds']=186
    plan['maximumAdditionalFunctionPlusStartupSeconds']=690
    plan['maximumCombinedPriorAndNewFunctionPlusStartupSeconds']=876
    plan['idleSecondsSeparate']=2
    return plan,sources,manifest


def gpu_stream(payload):
    import hashlib
    from pathlib import Path
    for expected in payload['plan']['publicSourceMounts']:
        path=Path(__file__).resolve().parent/Path(expected['remotePath']).name
        if hashlib.sha256(path.read_bytes()).hexdigest()!=expected['sha256']:
            raise ValueError('mounted public source hash mismatch')
    # Exactly one model-analysis invocation. Splitting happens only after it returns.
    result=analysis.gpu_once(payload)
    yield from transport.emit_result(result,{'analysisInvocations':1,'remoteTempCleanupOnReturn':result.get('remoteTempCleanupOnReturn')})


def definition(modal,volume):
    directory=Path(__file__).resolve().parent
    # copy=False mounts these two individual public files at startup; it does NOT build a new Image.
    image=modal.Image.from_id(analysis.IMAGE)
    for name in PUBLIC_FILES[1:]:image=image.add_local_file(directory/name,'/root/'+name,copy=False)
    app=modal.App(APP)
    # SDK generator functions do not support retries (including retries=0 keyword).
    call=app.function(image=image,gpu='L4',cpu=(2,4),memory=(8192,16384),timeout=600,startup_timeout=90,
        min_containers=0,max_containers=1,buffer_containers=0,scaledown_window=2,
        single_use_containers=True,secrets=[],volumes={'/vol':volume.read_only()},
        block_network=True,restrict_modal_access=True,serialized=False,include_source=True)(gpu_stream)
    return app,call,image


def local_sdk_mount_inventory(call,image):
    """Read local SDK descriptors only, without hydrate/app.run/remote or directory scans."""
    entries=[];seen=set()
    def add(mount):
        for entry in mount.entries:
            transport.require(hasattr(entry,'local_file') and hasattr(entry,'remote_path'),'directory source mount forbidden')
            path=Path(entry.local_file).resolve()
            entries.append({'remotePath':str(entry.remote_path),'sha256':transport.digest(path.read_bytes()),'localFileName':path.name})
    for mount in call._get_source_info().get_entrypoint_mount().values():add(mount)
    def walk(obj):
        if id(obj) in seen:return
        seen.add(id(obj))
        deps=getattr(obj,'_deps_',None)
        for dep in deps() if deps else []:
            if hasattr(dep,'entries'):add(dep)
            else:walk(dep)
    walk(image)
    normalized=[{'remotePath':e['remotePath'],'sha256':e['sha256']} for e in entries]
    transport.require(sorted(normalized,key=lambda e:e['remotePath'])==sorted(source_inventory(),key=lambda e:e['remotePath']),'unexpected or missing source mount')
    return sorted(entries,key=lambda e:e['remotePath'])


def inspect_failed_archive(output):
    """Explicit forensic log extraction only; never mark nonzero report/arrays complete."""
    output=Path(output);failure=output/'failure.json';part=output/'artifact.incomplete.part'
    if not failure.exists() or not part.exists():return {'status':'no_failed_archive_available'}
    info=json.loads(failure.read_text());code=info.get('declaredReturnCode')
    if not(info.get('verifiedEndSeen') is True and type(code) is int and code!=0):return {'status':'unverified_or_transport_partial_no_extraction'}
    folder=output/'failed-analysis-log-excerpts-private';folder.mkdir(mode=0o700)
    extracted=[]
    with zipfile.ZipFile(part) as archive:
        names=archive.namelist();transport.require(len(names)==len(set(names)),'duplicate ZIP names')
        for name in ('run.log','current_error.json','before_error.json'):
            if name not in names:continue
            with archive.open(name) as source:data=source.read(1024*1024+1)
            truncated=len(data)>1024*1024;data=data[:1024*1024]
            path=folder/name;fd=os.open(str(path),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
            with os.fdopen(fd,'wb') as out:out.write(data)
            extracted.append({'name':name,'bytes':len(data),'truncated':truncated,'sha256':transport.digest(data)})
    return {'status':'forensic_logs_only_not_complete_report','analysisReturnCode':code,'extracted':extracted,'reportReady':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('root','package','video','expected-video-sha','expected-service-manifest-sha','capture-source-commit','output-dir'):parser.add_argument('--'+name,required=True)
    parser.add_argument('--execute',action='store_true');parser.add_argument('--approved-plan-sha')
    args=parser.parse_args();plan,sources,manifest=prepare(args.root,args.package,args.video,args.expected_video_sha,args.expected_service_manifest_sha,args.capture_source_commit)
    digest=transport.digest(transport.canonical(plan));output=Path(args.output_dir)
    if not args.execute:
        output.mkdir(mode=0o700);transport.save_once(output/'run_plan.json',plan)
        transport.save_once(output/'preparation.json',{'planSha256':digest,'mediaTransferred':False,'gpuCalls':0})
        print(json.dumps({'mode':'prepared_only','planSha256':digest,'gpuCalls':0,'mediaTransferred':False}));return 0
    transport.require(args.approved_plan_sha==digest and os.environ.get('BPT_NATIVE_INLINE_TRANSFER_APPROVED')==plan['videoSha256'],'new exact inline plan/video authorization required')
    output.mkdir(mode=0o700)
    # Persist immutable input/plan binding BEFORE any remote-capable SDK operation.
    transport.save_once(output/'run_plan.json',plan)
    transport.save_once(output/'attempt.json',{'status':'authorized_about_to_attempt_one_GPU_call','planSha256':digest,
        'inputVideoSha256':plan['videoSha256'],'serviceManifestSha256':plan['serviceReadyManifestCanonicalSha256'],
        'maximumGPUCalls':1,'automaticRetries':0,'normalApiJobCreated':False,
        'recordedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat()})
    phase='SDK_preflight';local_started=time.monotonic()
    try:
        import modal
        deployed=modal.Function.from_name('bpt-calibration','deep_analysis_job')
        transport.require(deployed.info().image_info.image_id==analysis.IMAGE,'existing image identity changed')
        volume=modal.Volume.from_name('bpt-gvhmr',create_if_missing=False);volume.hydrate()
        transport.require(volume.object_id==analysis.VOLUME,'existing volume identity changed')
        app,call,image=definition(modal,volume)
        mounts=local_sdk_mount_inventory(call,image);transport.save_once(output/'source-mounts.json',{'files':mounts})
        phase='app_setup'
        with app.run(detach=False):
            transport.save_once(output/'app.json',{'appId':app.app_id,'expectedName':APP})
            info=call.info(refresh=True)
            transport.require(info.image_info.image_id==analysis.IMAGE,'defined function image changed')
            transport.save_once(output/'defined-function.json',{'functionId':call.object_id,'imageId':info.image_info.image_id,
                'gpus':info.gpus,'cpu':info.cpu,'memoryMiB':info.memory_mib,'timeout':info.timeout,'maxRetries':info.max_retries})
            transport.save_once(output/'invocation-submission.json',{'status':'about_to_submit_single_generator_input',
                'atUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'planSha256':digest,'maximumCalls':1})
            phase='single_remote_generator_iteration'
            def records():
                yield from call.remote_gen({'plan':plan,'sources':sources,'manifest':manifest,'video':Path(args.video).read_bytes()})
            receipt=transport.collect_result(records(),output)
        transport.save_once(output/'execution.json',{'status':'complete_transport_zero_analysis_return_code','planSha256':digest,
            'returnCode':receipt['returnCode'],'artifactSha256':receipt['sha256'],'gpuCalls':1,'retried':False,'normalApiJobCreated':False,
            'completedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'localElapsedSecondsIncludingQueueAndDownload':round(time.monotonic()-local_started,3)})
        print(json.dumps({'status':'complete_transport_zero_return_code','gpuCalls':1,'retried':False}));return 0
    except BaseException as error:
        forensic={'status':'no_forensic_extraction'}
        try:forensic=inspect_failed_archive(output)
        except Exception as forensic_error:forensic={'status':'forensic_extraction_failed','errorType':type(forensic_error).__name__}
        transport.save_once(output/'execution-failure.json',{'status':'incomplete_not_report_ready','phase':phase,'planSha256':digest,
            'errorType':type(error).__module__+'.'+type(error).__name__,'automaticRetries':0,'normalApiJobCreated':False,
            'reportReady':False,'forensic':forensic,'observedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'localElapsedSecondsIncludingQueueAndDownload':round(time.monotonic()-local_started,3)})
        fd=os.open(str(output/'traceback-private.txt'),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as out:out.write(traceback.format_exc())
        print(json.dumps({'status':'failed_no_retry','phase':phase,'errorType':type(error).__name__,'reportReady':False}));return 2


if __name__=='__main__':raise SystemExit(main())
