#!/usr/bin/env python3
"""Real LOCAL HTTP + production Bucket/BucketState, emulated S3, inference boundary replay.
Never imports Modal, performs inference, reads credential fallbacks, or connects off-loopback.
Private actual inputs are read-only and hash-gated before servers start.
"""
from __future__ import annotations
import argparse
import base64
import contextlib
import copy
import hashlib
import importlib.abc
import json
import logging
import os
from pathlib import Path
import shutil
import socket
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
VIDEO_SHA = '53658c052b52bde1285b3e3ee6a1951f201419831e9ce776af094f31749c44d8'
MANIFEST_SHA = '70a1e8d88b83acb13b9d2d322fa2675625e4060e0346b3d12f2204ed8118ec09'
MANIFEST_CANONICAL_SHA = '2cc367da42da9c2b218990a730e0e5e1310645ef043392ec2d1d53dfb147c66f'
REPORT_SHA = 'f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa'
OVERLAY_SHA = 'b1630a93c243911bb154f8daad6dd489f2581f037cb9b2dd4bd9099fd6728113'
SYNTHETIC_KEY = b'LOCAL-ONLY-BPT-CONTRACT-KEY-NOT-A-REAL-SPRING-SECRET-000000000000000'
SYNTHETIC_ACCESS = 'local-only-synthetic-access'
SYNTHETIC_SECRET = 'local-only-synthetic-secret'

def digest(data): return hashlib.sha256(data).hexdigest()
def canonical(obj): return json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode()
def core(report): return {k:v for k,v in report.items() if k not in {'runtime', 'bodyShape'}}

class ForbiddenImports(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split('.')[0] in {'modal','gvhmr_runner'}:
            raise AssertionError('Forbidden model/cloud import in LOCAL replay: '+fullname)
        return None

class LoopbackFence:
    def __init__(self): self.ports=set(); self.connections=[]
    def address(self, address):
        if isinstance(address, tuple):
            host,port=address[:2]
            assert host == '127.0.0.1' and port in self.ports, 'Network fence rejected non-owned address'
            self.connections.append({'host':host,'port':port})
    def url(self, url):
        u=urlsplit(str(url))
        assert u.scheme=='http' and u.hostname=='127.0.0.1' and u.port in self.ports and not u.username, 'Non-owned URL rejected'
    def __enter__(self):
        self.old_connect=socket.socket.connect;self.old_ex=socket.socket.connect_ex
        fence=self
        def connect(sock,address):fence.address(address);return fence.old_connect(sock,address)
        def connect_ex(sock,address):fence.address(address);return fence.old_ex(sock,address)
        socket.socket.connect=connect;socket.socket.connect_ex=connect_ex
        return self
    def __exit__(self,*_): socket.socket.connect=self.old_connect;socket.socket.connect_ex=self.old_ex

class ApiServer:
    def __init__(self,app,fence):
        import uvicorn
        self.sock=socket.socket();self.sock.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);self.sock.bind(('127.0.0.1',0));self.port=self.sock.getsockname()[1];self.sock.listen(128);fence.ports.add(self.port)
        self.server=uvicorn.Server(uvicorn.Config(app,host='127.0.0.1',port=self.port,log_level='critical',access_log=False,timeout_keep_alive=1))
        self.thread=threading.Thread(target=self.server.run,kwargs={'sockets':[self.sock]},name='bpt-local-contract-api')
        self.thread.start();until=time.monotonic()+5
        while not self.server.started and self.thread.is_alive() and time.monotonic()<until:time.sleep(.01)
        assert self.server.started,'Owned API failed to start'
    def stop(self):
        self.server.should_exit=True;self.thread.join(5)
        assert not self.thread.is_alive(),'Owned API thread did not stop'
        self.sock.close()


def run(args):
    if not __debug__:
        raise RuntimeError('This validation harness refuses Python -O; assertions must remain enabled')
    os.umask(0o077)
    out=Path(args.out).expanduser().resolve();private_root=(Path.home()/'bpt-data').resolve()
    assert out.is_relative_to(private_root) and not out.exists(),'Fresh private bpt-data output required'
    out.mkdir(parents=True,mode=0o700)
    def save(name,obj):
        p=out/name;p.write_bytes(json.dumps(obj,indent=2,ensure_ascii=False,allow_nan=False).encode());p.chmod(0o600)
    inputs={k:Path(getattr(args,k)).expanduser().resolve() for k in ['video','manifest','report','overlay']}
    hashes={k:digest(p.read_bytes()) for k,p in inputs.items()}
    assert hashes=={'video':VIDEO_SHA,'manifest':MANIFEST_SHA,'report':REPORT_SHA,'overlay':OVERLAY_SHA},'Actual input hash gate failed before any server'
    assert inputs['video'].stat().st_size==6534978
    manifest=json.loads(inputs['manifest'].read_bytes());original=json.loads(inputs['report'].read_bytes())
    assert digest(canonical(manifest))==MANIFEST_CANONICAL_SHA and len(manifest['reps'])==10
    selected=original
    selected_path=getattr(args,'replay_report',None)
    selected_sha=getattr(args,'replay_report_sha256',None)
    assert bool(selected_path)==bool(selected_sha),'Replay report path and explicit SHA256 required together'
    if selected_path:
        selected_path=Path(selected_path).expanduser().resolve()
        assert selected_path.is_relative_to(private_root),'Replay report must stay in private bpt-data'
        assert len(selected_sha)==64 and digest(selected_path.read_bytes())==selected_sha,'Replay report SHA256 gate failed'
        selected=json.loads(selected_path.read_bytes())
        assert set(selected)==set(original)|{'assessmentEvidence'},'Only additive assessment evidence accepted'
        assert {k:v for k,v in selected.items() if k!='assessmentEvidence'}==original,'Original report fields must remain exact'
        evidence=selected['assessmentEvidence']
        assert evidence['schema']=='bpt.deep-assessment-evidence.v1'
        assert evidence['exerciseId']==original['exerciseId'] and evidence['fps']==original['fps']
        assert evidence['sourceTimeBasis']=='video_ms' and len(evidence['reps'])==len(original['reps'])
        for er,rep in zip(evidence['reps'],original['reps']):
            assert all(er[k]==rep[k] for k in ['repIndex','startMs','endMs','side'])
        save('selected-report-receipt.json',{'path':str(selected_path),'sha256':selected_sha,
             'originalReportSHA256':REPORT_SHA,'originalFieldsUnchanged':True,
             'source':'local_saved_array_rescore_not_new_inference'})
    source_start={str(p.relative_to(ROOT)):digest(p.read_bytes()) for p in [ROOT/'server/calibration_modal'/name for name in ['service.py','storage.py','deep_analysis.py','deep_worker.py','checks.py']]}
    harness_start=digest(Path(__file__).read_bytes())
    save('input-receipt.json',{'paths':{k:str(p) for k,p in inputs.items()},'sha256':hashes,'manifestCanonicalSHA256':MANIFEST_CANONICAL_SHA,'originals_read_only':True})
    # No ambient credentials, proxy, or cloud fallback may influence the run.
    removed_prefixes=('AWS_','R2_','MODAL_')
    for key in list(os.environ):
        if key.startswith(removed_prefixes) or key.upper() in {'HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY'}:os.environ.pop(key,None)
    os.environ.update(AWS_EC2_METADATA_DISABLED='true',AWS_DEFAULT_REGION='us-east-1',AWS_ACCESS_KEY_ID=SYNTHETIC_ACCESS,AWS_SECRET_ACCESS_KEY=SYNTHETIC_SECRET)
    sys.meta_path.insert(0,ForbiddenImports());sys.path.insert(0,str(ROOT/'server/calibration_modal'))
    import httpx,jwt
    from moto.server import ThreadedMotoServer
    logging.getLogger("werkzeug").setLevel(logging.ERROR)
    import service,storage,deep_worker
    def no_fallback(*_):raise AssertionError('Credential/environment fallback forbidden')
    storage.Bucket.from_env=classmethod(no_fallback)
    def no_model(*_,**__):raise AssertionError('Model/normalize/render subprocess is forbidden')
    deep_worker.normalize=no_model;deep_worker.render=no_model;deep_worker.command=no_model
    secret=base64.b64encode(SYNTHETIC_KEY).decode()
    def auth(user):return {'Authorization':'Bearer '+jwt.encode({'sub':str(user),'exp':int(time.time())+600},SYNTHETIC_KEY,algorithm='HS512')}
    spawned=[];callbacks=[];requests=[];buckets=[];servers=[];moto=None;client=None;cleanup={};error=None
    def spawn(job):spawned.append(copy.deepcopy(job));return SimpleNamespace(object_id='local-captured-spawn-1')
    def deny_calibration(_):raise AssertionError('Calibration inference not in this test')
    def analyze_replay(video,directory,m,progress,beta=None):
        assert digest(video.read_bytes())==VIDEO_SHA and m==manifest and beta is None
        callbacks.append({'video_sha256':VIDEO_SHA,'manifest_canonical_sha256':digest(canonical(m)),'beta_is_none':beta is None})
        progress(75);target=directory/'existing-actual-overlay.mp4';shutil.copyfile(inputs['overlay'],target)
        assert digest(target.read_bytes())==OVERLAY_SHA
        return copy.deepcopy(selected),target
    tmp=out/'worker-tmp';tmp.mkdir(mode=0o700);old_tmp=tempfile.tempdir;tempfile.tempdir=str(tmp)
    with LoopbackFence() as fence:
      try:
        moto=ThreadedMotoServer(ip_address='127.0.0.1',port=0,verbose=False);moto.start();host,s3port=moto.get_host_and_port();assert host=='127.0.0.1';fence.ports.add(s3port)
        def make_bucket():
            b=storage.Bucket(f'http://127.0.0.1:{s3port}','bpt-local-contract-only',SYNTHETIC_ACCESS,SYNTHETIC_SECRET,region='us-east-1');buckets.append(b);return b
        bucket=make_bucket();bucket.client.create_bucket(Bucket=bucket.bucket);state=storage.BucketState(bucket)
        assert state.put('contract:conditional',{'winner':1},skip_if_exists=True)
        assert not state.put('contract:conditional',{'winner':2},skip_if_exists=True)
        assert storage.BucketState(make_bucket()).get('contract:conditional')=={'winner':1}
        app=service.create_app(bucket,state,deny_calibration,secret,deep_spawn=spawn);api=ApiServer(app,fence);servers.append(api)
        def hook(request):fence.url(request.url)
        client=httpx.Client(timeout=15,trust_env=False,follow_redirects=False,event_hooks={'request':[hook]})
        def request(method,path,expected,headers=None,body=None):
            url=f'http://127.0.0.1:{api.port}'+path;fence.url(url);r=client.request(method,url,headers=headers,json=body)
            requests.append({'method':method,'path':path,'status':r.status_code,'body_sha256':digest(r.content)})
            assert r.status_code==expected,(method,path,r.status_code,r.text[:250]);return r
        session=manifest['sessionId'];payload={'schemaVersion':1,'clientSessionId':session,'files':[{'name':name,'contentType':ct,'sizeBytes':inputs[label].stat().st_size} for name,ct,label in [('video.mp4','video/mp4','video'),('reps.json','application/json','manifest')]]}
        h=auth(42)|{'Idempotency-Key':session};wrong=auth(43)|{'Idempotency-Key':session}
        request('POST','/v1/deep-analysis/uploads',401,body=payload)
        rejected=auth(42)|{'Idempotency-Key':session};rejected['Authorization']='Bearer '+jwt.encode({'sub':'42','exp':int(time.time())-10},SYNTHETIC_KEY,algorithm='HS512')
        request('POST','/v1/deep-analysis/uploads',401,headers=rejected,body=payload)
        prepared=request('POST','/v1/deep-analysis/uploads',200,headers=h,body=payload).json();assert prepared['status']=='upload_required';save('actual-prepare-response.json',prepared)
        complete=f"/v1/deep-analysis/uploads/{prepared['uploadId']}/complete";finish={'clientSessionId':session}
        request('POST',complete,404,headers=wrong,body=finish)
        request('POST',complete,422,headers=h,body=finish);assert not spawned
        for item in prepared['files']:
            fence.url(item['url']);assert urlsplit(item['url']).port==s3port
            label='video' if item['name']=='video.mp4' else 'manifest';ct='video/mp4' if label=='video' else 'application/json'
            if label=='manifest':
                bad=client.put(item['url'],content=inputs[label].read_bytes(),headers={'Content-Type':'text/plain','Content-Length':str(inputs[label].stat().st_size)});assert bad.status_code==200
                response=request('POST',complete,422,headers=h,body=finish);assert response.json()['error']=='invalid_content_type';assert not spawned
            r=client.put(item['url'],content=inputs[label].read_bytes(),headers={'Content-Type':ct,'Content-Length':str(inputs[label].stat().st_size)});assert r.status_code==200
        accepted=request('POST',complete,202,headers=h,body=finish).json();job_id=accepted['jobId'];assert len(spawned)==1
        assert request('POST',complete,202,headers=h,body=finish).json()==accepted
        assert request('POST','/v1/deep-analysis/uploads',200,headers=h,body=payload).json()==accepted
        path=f'/v1/deep-analysis/jobs/{job_id}'
        request('GET',path,401);request('GET',path,404,headers=auth(43));request('POST',complete,404,headers=wrong,body=finish)
        assert request('GET',path,200,headers=auth(42)).json()['status']=='queued'
        outcome=deep_worker.run(spawned[0],bucket,state,analyze_video=analyze_replay);assert outcome=={'status':'done'} and len(callbacks)==1
        assert not list(tmp.iterdir()),'Production TemporaryDirectory did not clean up'
        persisted=state.get('deep-job:'+job_id);assert persisted['status']=='done'
        assert core(persisted['report'])==core(selected)
        assert persisted['report']['bodyShape']=={'source':'gvhmr_fallback'} and persisted['report']['runtime']['scope']=='worker_process_reuse_not_proof_of_modal_cold_or_warm_start'
        response=request('GET',path,200,headers=auth(42));envelope=response.json();(out/'actual-local-api-job-response.json').write_bytes(response.content);(out/'actual-local-api-job-response.json').chmod(0o600);save('actual-local-api-response-metadata.json',{'status':response.status_code,'contentType':response.headers['content-type'],'ownedAPIPort':api.port,'bodySHA256':digest(response.content),'manuallyConstructedEnvelope':False})
        for key,expected_key,expected_sha in [('reportUrl','reportKey',None),('videoUrl','videoKey',OVERLAY_SHA)]:
            url=envelope['result'][key];fence.url(url);assert urlsplit(url).port==s3port;r=client.get(url);assert r.status_code==200;stored=bucket.get(persisted[expected_key]);assert r.content==stored
            if expected_sha:assert digest(r.content)==expected_sha
            else:assert json.loads(r.content)==envelope['result']['report']
        request('GET',path,404,headers=auth(43));request('POST',path+'/retry',409,headers=auth(42));request('POST',path+'/retry',404,headers=auth(43));assert len(spawned)==1
        # Stop API1. New Bucket, state and API objects may only recover persisted S3 state.
        api.stop();restarted_bucket=make_bucket();restarted_state=storage.BucketState(restarted_bucket)
        assert restarted_state.get('deep-job:'+job_id)==persisted
        api=ApiServer(service.create_app(restarted_bucket,restarted_state,deny_calibration,secret,deep_spawn=spawn),fence);servers.append(api)
        restart_response=request('GET',path,200,headers=auth(42));restart_body=restart_response.json();assert restart_body['status']=='done' and restart_body['result']['report']==envelope['result']['report']
        for key in ['reportUrl','videoUrl']:
            fence.url(restart_body['result'][key]);assert urlsplit(restart_body['result'][key]).port==s3port
        (out/'actual-local-api-after-restart.json').write_bytes(restart_response.content);(out/'actual-local-api-after-restart.json').chmod(0o600)
        assert request('POST','/v1/deep-analysis/uploads',200,headers=h,body=payload).json()==accepted
        request('GET',path,401);request('GET',path,404,headers=auth(43));assert len(spawned)==len(callbacks)==1
        blocked=False
        try:fence.url('https://not-owned.invalid/object')
        except AssertionError:blocked=True
        assert blocked
        save('contract-observations.json',{'http_requests':requests,'captured_spawn_count':len(spawned),'inference_callback_replays':callbacks,'bucket_state_conditional_write':True,'fresh_bucket_state_api_restart':True,'response_report_core_sha256':digest(canonical(core(envelope['result']['report']))),'source_report_core_sha256':digest(canonical(core(selected))),'original_report_core_sha256':digest(canonical(core(original))),'selected_replay_report_sha256':selected_sha,'all_core_fields_unchanged_except_runtime_bodyShape':True,'production_added_metadata':{'runtime':persisted['report']['runtime'],'bodyShape':persisted['report']['bodyShape']},'loopback_ports':sorted(fence.ports),'socket_connect_count':len(fence.connections),'socket_destinations_all_owned_loopback':all(x['host']=='127.0.0.1' and x['port'] in fence.ports for x in fence.connections),'all_presigned_hosts_owned':True,'external_URL_guard_rejected_without_request':True,'actual_local_API_response_not_manual_wrapper':True})
      except BaseException as exc:
        error={'type':type(exc).__name__,'message':str(exc)};save('failure.json',error);raise
      finally:
        cleanup_errors=[]
        def clean(label, action):
            try:action()
            except BaseException as exc:cleanup_errors.append({'stage':label,'type':type(exc).__name__})
        if client:clean('client_close',client.close)
        for server in reversed(servers):
            if server.thread.is_alive():clean('API_stop',server.stop)
        cleanup['API_threads_stopped']=all(not x.thread.is_alive() for x in servers)
        def clear_bucket():
            b=buckets[0];objects=b.client.list_objects_v2(Bucket=b.bucket).get('Contents',[])
            if objects:b.client.delete_objects(Bucket=b.bucket,Delete={'Objects':[{'Key':x['Key']} for x in objects]})
            assert not b.client.list_objects_v2(Bucket=b.bucket).get('Contents');b.client.delete_bucket(Bucket=b.bucket)
            cleanup['owned_S3_bucket_objects_deleted']=len(objects)
        if buckets and moto:clean('owned_bucket_clear',clear_bucket)
        for b in buckets:clean('bucket_client_close',b.client.close)
        if moto:clean('Moto_stop',moto.stop)
        cleanup['Moto_stopped']=moto is None or not moto._thread.is_alive()
        cleanup['worker_temp_empty']=not list(tmp.iterdir());tempfile.tempdir=old_tmp
        clean('owned_temp_remove',lambda:shutil.rmtree(tmp))
        closed=[]
        for port in sorted(fence.ports):
            with socket.socket() as sock:sock.settimeout(.2);code=sock.connect_ex(('127.0.0.1',port));assert code!=0;closed.append(port)
        cleanup['owned_ports_no_longer_listening']=closed
        cleanup['original_input_hashes_unchanged']={k:digest(p.read_bytes())==hashes[k] for k,p in inputs.items()}
        cleanup['cleanup_errors']=cleanup_errors
        save('cleanup.json',cleanup)
        assert all(cleanup['original_input_hashes_unchanged'].values()) and not cleanup_errors
        assert cleanup['API_threads_stopped'] and cleanup['Moto_stopped'] and cleanup['worker_temp_empty']

    if selected_path:
        assert digest(selected_path.read_bytes())==selected_sha,'Selected replay report changed during run'
    sources={str(p.relative_to(ROOT)):digest(p.read_bytes()) for p in [ROOT/'server/calibration_modal'/name for name in ['service.py','storage.py','deep_analysis.py','deep_worker.py','checks.py']]}
    assert sources==source_start and digest(Path(__file__).read_bytes())==harness_start
    save('source-hashes.json',{'production':sources,'harness_sha256':harness_start,'source_unchanged_during_run':True})
    summary={'status':'PASS_LOCAL_HTTP_PRODUCTION_BUCKET_BUCKETSTATE_EMULATED_S3_REPLAYED_INFERENCE_BOUNDARY','scope_not_production':True,'Moto_S3_emulator_not_R2':True,'synthetic_JWT_not_Spring_login':True,'actual_model_inference_new_runs':0,'external_uploads_requests_GPU_deployments':0,'actual_payload_video_bytes':6534978,'input_hashes':hashes,'captured_spawn_count':len(spawned),'analyze_callback_replay_count':len(callbacks),'HTTP_contract_assertions':len(requests),'genuine_LOCAL_API_response':str(out/'actual-local-api-job-response.json'),'local_api_response_sha256':digest((out/'actual-local-api-job-response.json').read_bytes()),'source_report_core_sha256':digest(canonical(core(selected))),'original_report_core_sha256':digest(canonical(core(original))),'selected_replay_report_sha256':selected_sha,'runtime_bodyShape_only_report_exclusions':True,'cleanup':cleanup,'production_source_hashes':sources}
    save('summary.json',summary);print(json.dumps({'status':summary['status'],'private_output':str(out),'HTTP_assertions':len(requests),'cleanup_pass':True}))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--out',required=True)
    parser.add_argument('--video',default=str(Path.home()/'bpt-data/terminal-device-capture-20261102/barbellrow/native-full-row-original.mp4'))
    parser.add_argument('--manifest',default=str(Path.home()/'bpt-data/native-deep-current-row-20261103-final-private/reps.json'))
    parser.add_argument('--report',default=str(Path.home()/'bpt-data/native-deep-inline-l4-20261103-verified-private/worker_report.json'))
    parser.add_argument('--replay-report',help='Optional private additive saved-array re-score; original remains hash-gated')
    parser.add_argument('--replay-report-sha256',help='Explicit expected SHA256 for --replay-report')
    parser.add_argument('--overlay',default=str(Path.home()/'bpt-data/native-deep-inline-l4-20261103-verified-private/overlay.mp4'))
    run(parser.parse_args())
