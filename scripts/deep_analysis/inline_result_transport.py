#!/usr/bin/env python3
"""Strict inline-chunk transport and prepare-only public-byte CPU comparison.

No GPU, media, volumes, secrets, model imports, image build or deployment.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

SCHEMA='bpt.inline-result.v1'
CHUNK_BYTES=65536
MAX_BYTES=256*1024*1024
PUBLIC_BYTES=4*1024*1024
IMAGE='im-4SiTgQLfJqcNflEuz14dR3'
APP='bpt-owned-inline-public-cpu'
PROTECTED_APP='ap-7wHY4ormhfi1kaOWNIh5xr'


def require(ok,reason):
    if not ok:raise ValueError(reason)


def digest(data):return hashlib.sha256(data).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def save_once(path,value):
    fd=os.open(str(path),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'wb') as out:out.write(canonical(value))


def emit_result(result,diagnostics=None):
    require(type(result) is dict and type(result.get('archive')) is bytes,'result shape')
    data=result['archive'];code=result.get('returnCode')
    require(type(code) is int,'return code must be exact int')
    require(0<len(data)<=MAX_BYTES,'payload size')
    count=(len(data)+CHUNK_BYTES-1)//CHUNK_BYTES;sha=digest(data)
    yield {'schema':SCHEMA,'kind':'header','bytes':len(data),'chunks':count,'chunkBytes':CHUNK_BYTES,
           'sha256':sha,'returnCode':code,'diagnostics':diagnostics or {}}
    for index in range(count):
        block=data[index*CHUNK_BYTES:(index+1)*CHUNK_BYTES]
        yield {'schema':SCHEMA,'kind':'chunk','index':index,'data':block,'sha256':digest(block)}
    yield {'schema':SCHEMA,'kind':'end','bytes':len(data),'chunks':count,'sha256':sha,'returnCode':code}


def collect_result(records,output):
    """Only EOF after a verified end commits a successful artifact; failures retain .part."""
    output=Path(output);part=output/'artifact.incomplete.part';complete=output/'artifact.complete.bin'
    require(not complete.exists() and not (output/'completion.json').exists(),'existing completed artifact')
    header=None;ended=False;count=0;size=0;hash_state=hashlib.sha256()
    fd=os.open(str(part),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    try:
        with os.fdopen(fd,'wb') as out:
            for record in records:
                require(type(record) is dict and record.get('schema')==SCHEMA,'record schema')
                require(not ended,'record after end')
                kind=record.get('kind')
                if header is None:
                    require(kind=='header','header required first')
                    require(type(record.get('bytes')) is int and 0<record['bytes']<=MAX_BYTES,'declared bytes')
                    require(type(record.get('chunks')) is int and record['chunks']==(record['bytes']+CHUNK_BYTES-1)//CHUNK_BYTES,'declared chunks')
                    require(type(record.get('chunkBytes')) is int and record['chunkBytes']==CHUNK_BYTES,'chunk size contract')
                    require(type(record.get('returnCode')) is int,'return code must be exact int')
                    require(type(record.get('sha256')) is str and len(record['sha256'])==64 and all(c in '0123456789abcdef' for c in record['sha256']),'declared digest')
                    header=record;continue
                if kind=='chunk':
                    require(type(record.get('index')) is int and record['index']==count and count<header['chunks'],'chunk order/duplicate')
                    block=record.get('data');require(type(block) is bytes,'chunk data type')
                    expected=min(CHUNK_BYTES,header['bytes']-size)
                    require(len(block)==expected and expected>0,'chunk length')
                    require(record.get('sha256')==digest(block),'chunk digest')
                    out.write(block);hash_state.update(block);size+=len(block);count+=1
                elif kind=='end':
                    require(all(type(record.get(k)) is type(header[k]) and record[k]==header[k] for k in ('bytes','chunks','sha256','returnCode')),'end/header mismatch')
                    require(count==header['chunks'] and size==header['bytes'] and hash_state.hexdigest()==header['sha256'],'incomplete payload/digest')
                    ended=True
                else:raise ValueError('unexpected record')
            require(header is not None and ended,'stream ended without verified end')
            require(header['returnCode']==0,'analysis returned nonzero; incomplete artifact withheld')
            out.flush();os.fsync(out.fileno())
        part.rename(complete)
        receipt={'status':'complete_transport_and_zero_return_code','bytes':size,'chunks':count,'sha256':hash_state.hexdigest(),'returnCode':0,'diagnostics':header.get('diagnostics',{})}
        save_once(output/'completion.json',receipt)
        return receipt
    except BaseException as error:
        save_once(output/'failure.json',{'status':'incomplete_not_consumable','errorType':type(error).__module__+'.'+type(error).__name__,
            'receivedBytes':size,'receivedChunks':count,'verifiedEndSeen':ended,'declaredReturnCode':None if header is None else header['returnCode'],
            'partFilePresent':part.exists(),'completeArtifactPresent':complete.exists()})
        raise


def public_payload():return bytes(range(256))*(PUBLIC_BYTES//256)


def runtime_diagnostics():
    import inspect
    import modal
    import modal._utils.blob_utils as blob
    import modal._runtime.container_io_manager as manager
    return {'python':sys.version,'modalSdkVersion':modal.__version__,'blobThresholdBytes':blob.MAX_OBJECT_SIZE_BYTES,
        'formatBlobDataSource':inspect.getsource(blob.format_blob_data),
        'blobUtilsSha256':digest(Path(inspect.getsourcefile(blob)).read_bytes()),
        'runtimeContainerManagerSha256':digest(Path(inspect.getsourcefile(manager)).read_bytes())}


def direct_public():
    info=runtime_diagnostics();print(json.dumps({'publicTransportDiagnostic':info}),flush=True)
    return {'archive':public_payload(),'returnCode':0,'diagnostics':info}


def chunks_public():
    info=runtime_diagnostics();print(json.dumps({'publicTransportDiagnostic':info}),flush=True)
    yield from emit_result({'archive':public_payload(),'returnCode':0},info)


def definition(modal,mode):
    app=modal.App(APP+'-'+mode)
    function=direct_public if mode=='direct' else chunks_public
    retry_options={'retries':0} if mode=='direct' else {}  # SDK rejects retries keyword for generators; they do not support retries.
    call=app.function(image=modal.Image.from_id(IMAGE),cpu=(.125,.5),memory=(128,512),
        timeout=10,startup_timeout=30,min_containers=0,max_containers=1,buffer_containers=0,
        scaledown_window=2,single_use_containers=True,secrets=[],volumes={},
        block_network=True,restrict_modal_access=True,serialized=False,include_source=True,**retry_options)(function)
    return app,call


def plan():
    return {'purpose':'public_deterministic_4MiB_direct_vs_inline_chunks_no_GPU_or_media','imageId':IMAGE,
        'maxFunctionCalls':2,'modes':['direct','chunks'],'payloadBytes':PUBLIC_BYTES,'payloadSha256':digest(public_payload()),
        'chunkBytes':CHUNK_BYTES,'cpuRequested':.125,'cpuLimit':.5,'memoryRequestedMiB':128,'memoryLimitMiB':512,
        'timeoutSecondsPerCall':10,'startupTimeoutSeconds':30,'localWaitSecondsPerCall':90,'maxContainers':1,
        'minContainers':0,'retries':0,'singleUseContainers':True,'secrets':[],'volumes':[],
        'restrictModalAccess':True,'blockNetwork':True,'newImageBuild':False,'mediaTransferred':False,
        'scriptSha256':digest(Path(__file__).read_bytes())}


def child(mode,out):
    import modal
    app,call=definition(modal,mode)
    # Receipts exist before app.run / function invocation, including failures before first chunk.
    save_once(out/'input.json',{'mode':mode,'bytes':PUBLIC_BYTES,'sha256':digest(public_payload()),'privateInput':False})
    save_once(out/'attempt.json',{'status':'about_to_start_one_CPU_call','mode':mode,'maxCalls':1,'gpu':False})
    try:
        with app.run(detach=False):
            save_once(out/'app.json',{'appId':app.app_id,'expectedName':APP+'-'+mode})
            if mode=='direct':
                response=call.remote()
                require(type(response) is dict and response.get('archive')==public_payload() and type(response.get('returnCode')) is int and response['returnCode']==0,'direct response mismatch')
                save_once(out/'direct-completion.json',{'status':'verified_public_direct_return','sha256':digest(response['archive']),'bytes':len(response['archive']),'diagnostics':response.get('diagnostics',{})})
            else:
                def records():yield from call.remote_gen()
                collect_result(records(),out)
    except BaseException as error:
        save_once(out/'call-failure.json',{'status':'failed_no_retry','errorType':type(error).__module__+'.'+type(error).__name__,'modelCalls':0,'gpuCalls':0})
        raise


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-dir',required=True)
    parser.add_argument('--execute',action='store_true');parser.add_argument('--approved-plan-sha');parser.add_argument('--child-mode',choices=['direct','chunks'])
    args=parser.parse_args();out=Path(args.output_dir)
    if args.child_mode:child(args.child_mode,out);return 0
    spec=plan();raw=canonical(spec);sha=digest(raw)
    if not args.execute:
        print(json.dumps({'mode':'prepared_only','planSha256':sha,'plan':spec}));return 0
    require(args.approved_plan_sha==sha and os.environ.get('BPT_PUBLIC_CPU_TRANSPORT_APPROVED')==sha,'separate exact public CPU approval required')
    out.mkdir(mode=0o700);save_once(out/'plan.json',spec);results=[]
    for mode in spec['modes']:
        folder=out/mode;folder.mkdir(mode=0o700);started=time.monotonic();timed_out=False
        # Persist immutable per-call plan BEFORE launching the remote-capable child.
        save_once(folder/'precall-plan.json',{'planSha256':sha,'mode':mode,'maxCalls':1,'publicPayloadSha256':spec['payloadSha256']})
        with (folder/'log-private.txt').open('x') as log:
            proc=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),'--output-dir',str(folder),'--child-mode',mode],stdout=log,stderr=log)
            try:proc.wait(timeout=90)
            except subprocess.TimeoutExpired:
                timed_out=True;proc.terminate()
                try:proc.wait(timeout=5)
                except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=5)
        cleanup='no_app_id'
        if (folder/'app.json').exists():
            app=json.loads((folder/'app.json').read_text());app_id=app['appId']
            require(app_id.startswith('ap-') and app_id!=PROTECTED_APP,'unsafe cleanup identity')
            cli=str(Path(sys.executable).with_name('modal'))
            info=subprocess.run([cli,'app','info',app_id,'--json'],capture_output=True,text=True,timeout=15)
            if info.returncode==0:
                data=json.loads(info.stdout);require(data['description']==APP+'-'+mode,'cleanup ownership mismatch')
                if data['lifecycle']['state']=='stopped':cleanup='already_stopped_verified'
                else:
                    stopped=subprocess.run([cli,'app','stop',app_id],capture_output=True,text=True,timeout=15)
                    cleanup='own_app_stop_requested' if stopped.returncode==0 else 'own_app_stop_failed'
            else:cleanup='identity_unavailable_no_stop'
        complete=(folder/('direct-completion.json' if mode=='direct' else 'completion.json')).exists()
        item={'mode':mode,'elapsedLocalSeconds':round(time.monotonic()-started,3),'localTimedOut':timed_out,'childReturnCode':proc.returncode,'verifiedResult':complete,'cleanup':cleanup,'gpuCalls':0,'modelCalls':0}
        save_once(folder/'execution.json',item);results.append(item)
        for file in folder.iterdir():file.chmod(0o600)
    save_once(out/'comparison.json',{'results':results,'maxCPUCalls':2,'GPUCalls':0,'mediaTransferred':False})
    print(json.dumps({'results':results,'GPUCalls':0,'mediaTransferred':False}));return 0


if __name__=='__main__':raise SystemExit(main())
