#!/usr/bin/env python3
"""Strict LOCAL-ONLY adapter for an original native video_ms capture receipt.

No network, inference, coordinate conversion, GT inputs or report reassignment.
The exact observed manifest is validated by the actual current service parser.
"""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlsplit, unquote


class IdentityError(ValueError): pass


def require(ok, message):
    if not ok: raise IdentityError(message)


def sha(path):
    result=hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda:source.read(1024*1024),b''):result.update(block)
    return result.hexdigest()


def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def load_receipt(path,expected_sha):
    path=Path(path);before=sha(path)
    require(before==expected_sha,'capture evidence SHA mismatch')
    def unique(pairs):
        result={}
        for key,value in pairs:
            require(key not in result,'duplicate JSON key');result[key]=value
        return result
    source=json.loads(path.read_text(),object_pairs_hook=unique)
    require(source.get('scope')=='local_native_capture_only','not original local native capture')
    require(source.get('uploaded') is False and source.get('queuePersisted') is False
            and type(source.get('networkAttempts')) is int and source['networkAttempts']==0,'transport provenance mismatch')
    require(isinstance(source.get('videoPath'),str) and source['videoPath'].startswith('/var/mobile/Containers/Data/Application/'), 'missing original device video path')
    require(type(source.get('durationMs')) is int and 0<source['durationMs']<=60000,'invalid actual capture duration')
    manifest=source.get('manifest');require(isinstance(manifest,dict),'missing actual manifest')
    require(isinstance(manifest.get('sessionId'),str) and re.fullmatch(r'[A-Za-z0-9_-]{1,128}',manifest['sessionId']), 'invalid session identity')
    require(manifest.get('timebase')=='video_ms' and type(manifest.get('schemaVersion')) is int and manifest['schemaVersion']==1,'wrong native timebase/schema')
    require(isinstance(manifest.get('reps'),list) and manifest['reps'],'missing observed reps')
    for rep in manifest['reps']:
        require(isinstance(rep,dict),'invalid observed rep')
        require(type(rep.get('endMs')) in (int,float) and math.isfinite(rep['endMs']) and rep['endMs']<=source['durationMs'],'rep outside original duration')
    require(sha(path)==before,'capture receipt changed during read')
    return source,before


def service_validate(manifest,service_root):
    root=Path(service_root).resolve();sys.path.insert(0,str(root))
    # Real parser, no replacement validator or mocks; imported modules have no model/network invocation.
    for name in ('deep_analysis','deep_metrics','checks'):
        existing=sys.modules.get(name)
        if existing is not None:
            require(Path(existing.__file__).resolve().parent==root,'another service snapshot already imported')
    import deep_analysis
    parsed=deep_analysis.manifest(canonical(manifest),manifest['sessionId'])
    require(parsed==manifest,'service parser changed original observations')
    return {'deep_analysis.py':sha(root/'deep_analysis.py'),'deep_metrics.py':sha(root/'deep_metrics.py'),'checks.py':sha(root/'checks.py')}


def validate_video(source,video,expected_video_sha,copy_receipt):
    require(expected_video_sha is not None and re.fullmatch('[0-9a-f]{64}',expected_video_sha),'explicit copied-video SHA required')
    video=Path(video);require(video.is_file() and not video.is_symlink(),'exact copied video missing')
    require(sha(video)==expected_video_sha,'video SHA mismatch')
    # Consume the actual devicectl read-only copy receipt, not a fabricated identity adapter.
    info,result=copy_receipt.get('info',{}),copy_receipt.get('result',{})
    args=info.get('arguments',[])
    require(info.get('outcome')=='success' and args[:4]==['devicectl','device','copy','from'],'not a successful read-only device copy')
    require(result.get('domain')=='appDataContainer' and result.get('domainIdentifier')=='com.bpt.liftdev','wrong source app container')
    source_suffix='Documents/'+source['videoPath'].split('/Documents/',1)[1]
    require(args.count('--source')==1 and args[args.index('--source')+1]==source_suffix,'copy receipt source identity mismatch')
    require(result.get('source','').endswith(source_suffix),'copy result source mismatch')
    destination=urlsplit(result.get('destination',''))
    require(destination.scheme in ('','file') and destination.netloc in ('','localhost') and not destination.query and not destination.fragment,'nonlocal copy destination URI')
    require(Path(unquote(destination.path)).resolve()==video.resolve(),'copy receipt destination mismatch')
    # Native recorder output is validated, not transformed or reconstructed from another clip.
    probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0',
        '-show_entries','stream=codec_name,width,height,duration,nb_frames,r_frame_rate,time_base','-of','json',str(video)],stderr=subprocess.DEVNULL))
    require(len(probe.get('streams',[]))==1,'video stream mismatch');stream=probe['streams'][0]
    require(stream['codec_name']=='h264','not native/service H264 input')
    require(stream['width']==source['width'] and stream['height']==source['height'],'captured dimensions mismatch')
    require(abs(float(stream['duration'])*1000-source['durationMs'])<1.01,'captured duration mismatch')
    require(sha(video)==expected_video_sha,'video changed during probe')
    return stream


def reject_wrong_report_binding(source,report,verified_video_sha,report_input_sha):
    # Same shape/exercise alone is insufficient: different session/video can have identical reps.
    require(verified_video_sha is not None and report_input_sha==verified_video_sha,'report has no exact input digest binding')
    require(report.get('exerciseId')==source['manifest']['exerciseId'],'report exercise mismatch')
    expected=source['manifest']['reps'];actual=report.get('reps')
    require(isinstance(actual,list) and len(actual)==len(expected),'report repetition count mismatch')
    for left,right in zip(expected,actual):
        require(all(key in right and value==right[key] for key,value in left.items()),'report replaced original observed interval/side/warnings/metrics')


def adapt(evidence,expected_evidence_sha,service_root,output,video=None,expected_video_sha=None,copy_receipt=None,copy_receipt_file_sha=None):
    source,before=load_receipt(evidence,expected_evidence_sha)
    original=copy.deepcopy(source['manifest']);service_hashes=service_validate(original,service_root)
    stream=validate_video(source,video,expected_video_sha,copy_receipt or {}) if video else None
    verification={'scope':'local_only_no_remote_transport','sourceKind':'native_local_capture_receipt',
        'status':'exact_video_and_manifest_verified' if stream else 'manifest_verified_exact_recorded_video_pending',
        'captureEvidenceSha256':before,'canonicalNativeManifestSha256':hashlib.sha256(canonical(original)).hexdigest(),
        'serviceSourceSha256':service_hashes,'durationMs':source['durationMs'],'repetitionCount':len(original['reps']),
        'exerciseId':original['exerciseId'],'timebase':original['timebase'],'copiedVideoSha256':expected_video_sha if stream else None,
        'videoByteIdentityVerified':stream is not None,'remoteTransportAllowed':False,'onDeviceObservationsChanged':False,
        'deviceCopyReceiptCanonicalSha256':hashlib.sha256(canonical(copy_receipt)).hexdigest() if stream else None,
        'deviceCopyReceiptFileSha256':copy_receipt_file_sha if stream else None,
        'newInferenceExecuted':False,'serviceReportProduced':False,'streamMetadata':stream}
    require(sha(evidence)==before and source['manifest']==original,'original input changed')
    target=Path(output);target.mkdir(mode=0o700)
    artifacts=[('reps.json',original),('verification.json',verification)]
    if stream:
        artifacts.append(('capture.json',{'videoLocalPath':str(Path(video).resolve()),'deepAnalysis':original}))
    for name,value in artifacts:
        with (target/name).open('x') as f:json.dump(value,f,indent=2,allow_nan=False);f.write('\n')
    return verification


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence',required=True);parser.add_argument('--expected-evidence-sha',required=True)
    parser.add_argument('--service-root',required=True);parser.add_argument('--output-dir',required=True)
    parser.add_argument('--video');parser.add_argument('--expected-video-sha');parser.add_argument('--copy-receipt');parser.add_argument('--expected-copy-receipt-sha')
    args=parser.parse_args()
    try:
        receipt_sha=sha(args.copy_receipt) if args.copy_receipt else None
        if args.video:
            require(receipt_sha is not None and receipt_sha==args.expected_copy_receipt_sha,'copy receipt file SHA mismatch')
        receipt=json.loads(Path(args.copy_receipt).read_text()) if args.copy_receipt else None
        result=adapt(args.evidence,args.expected_evidence_sha,args.service_root,args.output_dir,args.video,args.expected_video_sha,receipt,receipt_sha)
        require(args.copy_receipt is None or sha(args.copy_receipt)==receipt_sha,'copy receipt changed')
        print(json.dumps({k:v for k,v in result.items() if k not in ['streamMetadata','serviceSourceSha256']},indent=2))
        return 0
    except Exception as error:
        # No tokens, video paths or per-rep numeric fields in stdout/error receipts.
        print(json.dumps({'status':'rejected','errorType':type(error).__name__}));return 2


if __name__=='__main__':raise SystemExit(main())
