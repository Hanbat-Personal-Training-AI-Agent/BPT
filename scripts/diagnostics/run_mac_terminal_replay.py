#!/usr/bin/env python3
"""Exactly two authorized private Mac replays; shared advisory heavy lock, no app/default changes."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time


def now(): return datetime.now(timezone.utc).isoformat()
def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()


def process_tree_rss(pid):
    table=[]
    for line in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines():
        fields=line.split()
        if len(fields)==3: table.append(tuple(map(int,fields)))
    selected={pid}
    for _ in range(len(table)):
        added={p for p,parent,_ in table if parent in selected}
        if added<=selected:break
        selected|=added
    return sum(rss for p,_,rss in table if p in selected)


def run(command, log, timeout):
    start=time.monotonic();peak=0;reason=None
    with log.open('x') as output:
        process=subprocess.Popen(['/usr/bin/time','-l',*command],stdout=output,stderr=output,start_new_session=True)
        while process.poll() is None:
            peak=max(peak,process_tree_rss(process.pid))
            if peak>6*1024*1024:reason='sampled_process_tree_rss_exceeded_6gib'
            if time.monotonic()-start>timeout:reason='operational_timeout_not_quality_gate'
            if reason:
                os.killpg(process.pid,signal.SIGTERM)
                try:process.wait(timeout=10)
                except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
                break
            time.sleep(1)
    text=log.read_text();rss=re.findall(r'(\d+)\s+maximum resident set size',text)
    return {'returnCode':process.returncode,'elapsedSeconds':round(time.monotonic()-start,3),
            'sampledProcessTreePeakRssKiB':peak,'bsdMaximumResidentBytes':int(rss[-1]) if rss else None,
            'guardStopReason':reason,'command':command}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',required=True);parser.add_argument('--run-dir',required=True)
    args=parser.parse_args();root=Path(args.root).resolve();run_dir=Path(args.run_dir)
    run_dir.mkdir(mode=0o700)
    private=Path.home()/'bpt-data/terminal-mac-20261102/private'
    copies=json.loads((private/'copy_receipt_PRIVATE.json').read_text())
    frozen=json.loads((root/'docs/results/mac_terminal_replay_inputs_20261103.json').read_text())
    assert {x['exercise'] for x in copies}=={'squat','pushup'} and len(copies)==2
    def verify():
        for relative,expected in frozen['sourceSha256'].items():assert sha(root/relative)==expected
        for name,entry in frozen['models'].items():
            for relative,expected in entry['fileSha256'].items():assert sha(root/'ios/Runner/NativePose/Models'/(name+'.mlpackage')/relative)==expected
        for entry in copies:assert sha(entry['destinationPath'])==entry['destinationSha256']
    verify()
    receipt={'sourceKind':'mac_pose_replay_raw_geometry_only','startedAtUtc':now(),'stages':[],'nativeParityClaim':False}
    lock=open('/tmp/bpt-heavy.lock','a')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    try:
        build=run(['swift','build','-c','release','--package-path',str(root/'ios/CalibrationEngineKit'),
                   '--scratch-path',str(run_dir/'build'),'--product','pose-replay','--jobs','2'],run_dir/'build.log',900)
        receipt['stages'].append({'kind':'build',**build})
        if build['returnCode']!=0:raise RuntimeError('build failed')
        executable=run_dir/'build/release/pose-replay'
        assert executable.exists()
        for entry in copies:
            output=run_dir/entry['exercise'];output.mkdir(mode=0o700)
            command=[str(executable),'--exercise',entry['exercise'],'--model','mhalpe26',
                     '--motion3d',str(root/'ios/Runner/NativePose/Models/motionagformer_xs.mlpackage'),
                     '--lookahead','5','--cadence','1','--constraints','on','--adaptive','off','--wrist-anchor','off',
                     '--form-source','3d','--input','crop','--crop-edge','on','--ready-pose','off',
                     '--output-dir',str(output),entry['destinationPath']]
            stage=run(command,run_dir/(entry['exercise']+'.log'),600)
            receipt['stages'].append({'kind':'inference','exercise':entry['exercise'],**stage})
            verify()
            if stage['returnCode']!=0:raise RuntimeError('inference failed or stopped')
        receipt['status']='completed'
    except Exception as error:
        receipt['status']='stopped';receipt['errorType']=type(error).__name__
    finally:
        receipt['finishedAtUtc']=now()
        with (run_dir/'execution_PRIVATE.json').open('x') as f:json.dump(receipt,f,indent=2)
        lock.close()
    print(json.dumps({k:v for k,v in receipt.items() if k!='stages'}))
    return 0 if receipt['status']=='completed' else 2


if __name__=='__main__':raise SystemExit(main())
