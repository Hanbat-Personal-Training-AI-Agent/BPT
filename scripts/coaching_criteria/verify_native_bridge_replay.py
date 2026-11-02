"""Stream existing local evidence through independent Swift bridge and Python decisions.
python -m scripts.coaching_criteria.verify_native_bridge_replay INPUT [--output RECEIPT]
Only aggregate receipt is written; originals remain untouched. No inference/network.
"""
import argparse
from collections import Counter
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from .engine import evaluate, finite
from .catalog import CATALOG
from scripts.terminal_evidence.replay import validate_coaching_summary


def main():
    parser=argparse.ArgumentParser();parser.add_argument('input',type=Path);parser.add_argument('--output',type=Path);parser.add_argument('--app-shaped',action='store_true');args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    before=hashlib.sha256(args.input.read_bytes()).hexdigest()
    counts=Counter();states=Counter();reasons=Counter();cases={}
    with tempfile.TemporaryDirectory(prefix='bpt-criteria-bridge-') as temporary:
        binary=Path(temporary)/'bridge'
        with open('/tmp/bpt-heavy.lock','a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            subprocess.run(['swiftc',str(root/'ios/Runner/NativePose/Evaluators/CoachingCriteria.swift'),str(root/'ios/Runner/NativePose/Evaluators/CoachingCriteriaBridge.swift'),str(Path(__file__).with_name('native_bridge_replay.swift')),'-o',str(binary)],check=True)
        with args.input.open('rb') as input_stream,args.input.open() as originals:
            process=subprocess.Popen([str(binary)]+(['--app-shaped'] if args.app_shaped else []),stdin=input_stream,stdout=subprocess.PIPE,text=True)
            for original in originals:
                line=process.stdout.readline()
                if not line:raise RuntimeError('native output truncated')
                original=json.loads(original);native=json.loads(line);request=native['request'];summary=native['summary']
                expected=evaluate(request)['criterion'];decisions={x['observationId']:x for x in expected['children']}
                if summary['state']!=expected['state'] or summary['profilesUsed']!=0:raise RuntimeError('aggregate decision mismatch')
                if request['profiles'] or request['variant']!='unconfirmed':raise RuntimeError('invented target')
                for key,value in original['source'].items():
                    if key in summary['source'] and summary['source'][key]!=value:raise RuntimeError('source binding changed')
                expected_names=set(original['metrics'])-{'cameraTorsoSignedDeg','cameraHipLineDeviationRatio'} if args.app_shaped else set(original['metrics'])
                if set(summary['metrics'])!=expected_names:raise RuntimeError('metric dropped')
                containing={**original['source'],**original['context'],'coaching_criteria':summary}
                validate_coaching_summary(containing,original['context']['exercise'])
                if args.app_shaped and (summary['unmappedMetrics'] or set(summary['unsuppliedCatalogMetrics'])!={'cameraTorsoSignedDeg','cameraHipLineDeviationRatio'}):raise RuntimeError('app proxy coverage misreported')
                for name,metric in summary['metrics'].items():
                    counts['metricOpportunities']+=1;states[metric['state']]+=1;reasons.update(metric['criterionReasons'])
                    if metric['state']!=decisions[name]['state'] or metric['criterionReasons']!=decisions[name]['reasons']:raise RuntimeError('native/Python bridge mismatch')
                    if metric['state'] not in ('unknown','not_applicable'):raise RuntimeError('profile-free posture claim')
                    observed=request['observations'][name];provided=original['metrics'][name]
                    expected_original={k:v for k,v in provided.items() if k in ('rawValue','value','reasons') and v is not None} if args.app_shaped else provided
                    if observed['originalMetric']!=expected_original:raise RuntimeError('original metric changed')
                    if name in ('cameraTorsoSignedDeg','cameraHipLineDeviationRatio'):
                        if name not in summary['unmappedMetrics']:raise RuntimeError('unmapped proxy omitted')
                    else:
                        spec=CATALOG[name].contract()
                        if observed['definitionHash']!=spec['definitionHash']:raise RuntimeError('native definition mismatch')
                    for key in ('rawValue','value'):
                        actual=metric[key];wanted=provided.get(key)
                        if actual!=wanted and not (finite(actual) and finite(wanted) and abs(actual-wanted)<=1e-10):raise RuntimeError('numeric metric changed')
                    if metric['available']!=provided['available'] or metric['reasons']!=provided['reasons']:raise RuntimeError('availability changed')
                flush=original['context'].get('flush_tail',False)
                counts['frames']+=1;counts['flushFrames' if flush else 'genuineFrames']+=1
                exercise=original['context']['exercise'];case=cases.setdefault(exercise,Counter());case['frames']+=1;case['flushFrames' if flush else 'genuineFrames']+=1
            if process.wait()!=0:raise RuntimeError('native driver failed')
            if process.stdout.readline():raise RuntimeError('native output surplus')
    after=hashlib.sha256(args.input.read_bytes()).hexdigest()
    if before!=after:raise RuntimeError('original changed')
    receipt={'schema':'bpt.coaching-criteria-native-replay.v1','inputMode':'app_codable_nine' if args.app_shaped else 'full_export_with_unmapped_proxy_controls','inputSHA256':before,'originalUnchanged':True,'counts':dict(counts),'cases':{k:dict(v) for k,v in cases.items()},'criterionStates':dict(states),'criterionReasons':dict(reasons),'numericTolerance':1e-10,'profilesUsed':0,'scope':'existing actual numeric observations only; no form accuracy or posture delivery validation'}
    encoded=json.dumps(receipt,indent=2,sort_keys=True)+'\n'
    if args.output:args.output.write_text(encoded)
    print(encoded,end='')

if __name__=='__main__':main()
