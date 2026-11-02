#!/usr/bin/env python3
"""Prepare-only default. Separately reviewed one no-GPU/stdlib image health probe."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

IMAGE='im-4SiTgQLfJqcNflEuz14dR3'
NAME='bpt-owned-image-cpu-health-probe'


def health():
    import platform
    import sys
    return {'python':sys.version,'platform':platform.platform()}


def definition(modal):
    app=modal.App(NAME)
    call=app.function(image=modal.Image.from_id(IMAGE),cpu=(0.125,0.5),memory=(128,512),
        timeout=10,startup_timeout=30,min_containers=0,max_containers=1,
        buffer_containers=0,scaledown_window=2,retries=0,single_use_containers=True,
        secrets=[],volumes={},block_network=True,restrict_modal_access=True,
        serialized=False,include_source=True)(health)
    return app,call


def plan():
    return {'purpose':'stdlib_only_existing_image_CPU_health_no_model_no_media',
        'imageId':IMAGE,'appName':NAME,'gpu':None,'cpuRequested':0.125,'cpuLimit':0.5,'memoryRequestedMiB':128,'memoryLimitMiB':512,
        'timeoutSeconds':10,'startupTimeoutSeconds':30,'localWaitSeconds':90,
        'minContainers':0,'maxContainers':1,'maxInvocations':1,'retries':0,
        'volumes':[],'secrets':[],'mediaTransferred':False,'imageBuilt':False,
        'scriptSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir',required=True);parser.add_argument('--execute',action='store_true')
    parser.add_argument('--approved-plan-sha');parser.add_argument('--child',action='store_true')
    args=parser.parse_args();out=Path(args.output_dir)
    if args.child:
        import modal
        app,call=definition(modal)
        with app.run(detach=False):
            (out/'probe-app-id.txt').write_text(app.app_id)
            result=call.remote()
            (out/'health-result.json').write_text(json.dumps(result,indent=2))
        return 0
    current=plan();raw=json.dumps(current,sort_keys=True,separators=(',',':')).encode();digest=hashlib.sha256(raw).hexdigest()
    if not args.execute:
        print(json.dumps({'mode':'prepared_only','planSha256':digest,'plan':current}));return 0
    if args.approved_plan_sha!=digest or os.environ.get('BPT_MODAL_CPU_PROBE_APPROVED')!=digest:
        raise PermissionError('separate exact CPU probe approval required')
    out.mkdir(mode=0o700);(out/'probe-plan.json').write_bytes(raw)
    started=time.monotonic();timed_out=False
    with (out/'probe-log-private.txt').open('w') as log:
        child=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),'--output-dir',str(out),'--child'],stdout=log,stderr=log)
        try:child.wait(timeout=90)
        except subprocess.TimeoutExpired:
            timed_out=True;child.terminate()
            try:child.wait(timeout=5)
            except subprocess.TimeoutExpired:child.kill();child.wait(timeout=5)
    # Only our separately named probe app is eligible for cleanup. Never stop the L4 app.
    cleanup='no_probe_app_id'
    if (out/'probe-app-id.txt').exists():
        app_id=(out/'probe-app-id.txt').read_text().strip()
        if not app_id.startswith('ap-') or app_id=='ap-7wHY4ormhfi1kaOWNIh5xr':raise ValueError('unsafe cleanup identity')
        cli=str(Path(sys.executable).with_name('modal'))
        info=subprocess.run([cli,'app','info',app_id,'--json'],capture_output=True,text=True,timeout=15)
        if info.returncode==0 and json.loads(info.stdout).get('description')==NAME:
            stopped=subprocess.run([cli,'app','stop',app_id],capture_output=True,text=True,timeout=15)
            cleanup='own_probe_stop_requested' if stopped.returncode==0 else 'own_probe_stop_failed'
        else:cleanup='identity_unverified_no_stop'
    result={'elapsedLocalSeconds':round(time.monotonic()-started,3),'localWaitTimedOut':timed_out,
        'childReturnCode':child.returncode,'resultReturned':(out/'health-result.json').exists(),
        'cleanup':cleanup,'gpuCalls':0,'modelCalls':0,'mediaTransferred':False}
    (out/'probe-execution.json').write_text(json.dumps(result,indent=2))
    for file in out.iterdir():file.chmod(0o600)
    print(json.dumps(result));return 0 if result['resultReturned'] else 2


if __name__=='__main__':raise SystemExit(main())
