"""Frozen, streaming CPU replay of original terminal frames through native candidates.
No model execution. Outputs aggregate counts, paired raw/assessment states, sensitivity and hashes only.
"""
import atexit
import argparse
from collections import Counter
import datetime
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import tempfile
import threading
from scripts.coaching_criteria.engine import evaluate, finite
from scripts.terminal_evidence.replay import load, validate_candidate_summary


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def geometry_source(root):
    original=(root/'ios/Runner/NativePose/Evaluators/FormWarnings.swift').read_text()
    def function(name):
        begin=original.index('    static func '+name+'(');brace=original.index('{',begin);depth=1;end=brace+1
        while depth:
            depth+=(original[end]=='{')-(original[end]=='}');end+=1
        return original[begin:end]
    functions={name:function(name) for name in ['signedTorsoAngle3D','signedHipDeviation3D','signedLineDeviation3D']}
    return 'import Foundation\nimport simd\nenum FormGeometry {\nstatic let up3D=SIMD3<Double>(0,-1,0)\n'+'\n'.join(functions.values())+'\n}\n',{name:hashlib.sha256(body.encode()).hexdigest() for name,body in functions.items()}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--capture-root',type=Path,required=True);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    root=Path(__file__).resolve().parents[3];out=args.output_root
    if out.exists():raise SystemExit('Output directory must be new to preserve frozen receipts')
    out.mkdir(parents=True)
    source_paths=[root/'ios/Runner/NativePose/Evaluators'/name for name in ['CoachingCriteria.swift','ExperimentalCoaching.swift','CoachingCandidateEngine.swift','CoachingCandidateRuntime.swift','FormWarnings.swift','CoachingCandidateProposal.swift']]
    source_paths += [Path(__file__),Path(__file__).with_name('native_replay.swift'),Path(__file__).with_name('registry_v1.json'),Path(__file__).with_name('experiment_v1.json'),root/'scripts/coaching_criteria/engine.py',root/'scripts/coaching_criteria/catalog.py',root/'scripts/terminal_evidence/replay.py',root/'docs/evaluation/core3_candidate_execution_protocol_v1.md']
    before={str(p.relative_to(root)):sha(p) for p in source_paths}
    for path in source_paths:
        snapshot=out/'source-snapshot'/path.relative_to(root);snapshot.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,snapshot)
    experiment=json.loads(Path(__file__).with_name('experiment_v1.json').read_text());experiment['experimentDeclaredAt']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    experiment_path=out/'experiment-declared.json';experiment_path.write_text(json.dumps(experiment,indent=2)+'\n')
    cases=[];input_hashes={}
    for directory,exercise in [('squat','squat'),('pushup','pushup'),('barbellrow','barbell-row')]:
        path=args.capture_root/directory/'terminal-original.jsonl';input_hashes[directory]=sha(path)
        # Existing strict numeric reader validates source clock, footer and original membership.
        validated=load(path)
        rows=validated[0] if isinstance(validated,tuple) else validated
        if isinstance(rows,dict):rows=[frame for epoch in rows.values() for frame in epoch['frames']]
        else:rows=[row for row in rows if row['type']=='terminal_frame']
        cases.append((exercise,path,rows))
    geometry,function_hashes=geometry_source(root)
    freeze={'schema':'bpt.core3-candidate-replay-freeze.v1','declaredAt':experiment['experimentDeclaredAt'],'sourceFiles':before,'inputHashes':input_hashes,'experimentSHA256':sha(experiment_path),'extractedFunctions':function_hashes,'selectionPolicy':experiment['selectionPolicy'],'noInference':True}
    (out/'pre-outcome-freeze.json').write_text(json.dumps(freeze,indent=2,sort_keys=True)+'\n')
    aggregates={};raw_matrices={};opportunities=Counter();parity_requests=0;maximum_payload=0
    with tempfile.TemporaryDirectory(prefix='bpt-candidate-native-') as temporary:
        temporary=Path(temporary);geometry_path=temporary/'geometry.swift';geometry_path.write_text(geometry);binary=temporary/'candidate-replay'
        sources=[source_paths[i] for i in [0,1,2,3,5]]+[geometry_path,Path(__file__).with_name('native_replay.swift')]
        command=['swiftc','-O','-whole-module-optimization',*map(str,sources),'-o',str(binary)]
        with open('/tmp/bpt-heavy.lock','a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            with (out/'native-compile.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
        (out/'native-binary-sha256.txt').write_text(sha(binary)+'\n')
        shutil.copy2(binary,out/'candidate-replay-native')
        for exercise,path,rows in cases:
            process=subprocess.Popen([str(binary),str(experiment_path)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1)
            atexit.register(lambda p=process: p.kill() if p.poll() is None else None)
            writer_errors=[]
            def write_rows():
                try:
                    for row in rows:process.stdin.write(json.dumps({'row':row,'exercise':exercise,'captureID':'terminal-jsonl:'+input_hashes[path.parent.name]},allow_nan=False)+'\n')
                    process.stdin.close()
                except BaseException as error:writer_errors.append(str(error))
            writer=threading.Thread(target=write_rows,daemon=True);writer.start()
            case_counts=Counter()
            for row in rows:
                line=process.stdout.readline()
                if not line:raise RuntimeError('native replay truncated')
                result=json.loads(line);maximum_payload=max(maximum_payload,len(line));flush=row['flush_tail'];kind='flush' if flush else 'genuine'
                for key in ['frame','source_index','source_pts','source_time_value','source_time_scale','epoch','time_basis']:
                    if result['source'][key]!=row[key]:raise RuntimeError('native changed source binding')
                main={x['id']:x for x in result['results']['base']['assessment_checked']['rules']}
                for request in result['requests']:
                    expected=evaluate(request)['criterion'];actual=main[expected['id']]
                    if expected['state']!=actual['state']:raise RuntimeError('Python/native rule state mismatch')
                    for expected_atom,actual_atom in zip(expected['children'],actual['components']):
                        if expected_atom['state']!=actual_atom['state'] or expected_atom['reasons']!=actual_atom['reasons']:raise RuntimeError('Python/native atom state/reasons mismatch')
                        a=expected_atom.get('evaluatedValue');b=actual_atom['evaluatedValue']
                        if a!=b and not (finite(a) and finite(b) and abs(a-b)<=1e-10):raise RuntimeError('Python/native evaluated metric mismatch')
                        if expected_atom.get('profile') and expected_atom['profile']['referenceKind']!='engineering_candidate':raise RuntimeError('invented approval')
                    parity_requests+=1
                for setting,modes in result['results'].items():
                    for mode,output in modes.items():
                        declared={key:output[key] for key in ('registryVersion','experimentID','experimentDeclaredAt','variant','captureId','evaluationMode','parameters')}
                        declared['schema']='bpt.core3-candidate-config.v1'
                        validate_candidate_summary({**row,'coaching_candidate':output},{'exercise':exercise,'coaching_candidate_config':declared})
                        if output['delivered'] is not False or output['authority']!='engineering_candidate_not_validated_form':raise RuntimeError('unexpected feedback/authority')
                        encoded=json.dumps(output,separators=(',',':')).encode()
                        if len(encoded)>24576:raise RuntimeError('native compact payload unbounded')
                        for rule in output['rules']:
                            key=(exercise,setting,mode,rule['id']);aggregate=aggregates.setdefault(key,{'genuine':Counter(),'flush':Counter(),'reasons':Counter(),'configured':rule['configured']})
                            aggregate[kind][rule['state']]+=1
                            why=set(rule['reasons'])|{reason for component in rule['components'] for reason in component['reasons']}
                            aggregate['reasons'].update(why)
                raw={x['id']:x for x in result['results']['base']['raw_only']['rules']};assessment={x['id']:x for x in result['results']['base']['assessment_only']['rules']}
                for name in raw:
                    matrix=raw_matrices.setdefault((exercise,name,kind),Counter());matrix[raw[name]['state']+' -> '+assessment[name]['state']]+=1
                case_counts[kind]+=1
            if process.stdout.readline():raise RuntimeError('native replay surplus')
            writer.join();code=process.wait()
            if code or writer_errors:raise RuntimeError('native replay failed: '+str((code,writer_errors)))
            opportunities[exercise]=dict(case_counts)
    after={str(p.relative_to(root)):sha(p) for p in source_paths}
    if before!=after:raise RuntimeError('candidate source changed during frozen outcome replay')
    if any(sha(path)!=input_hashes[path.parent.name] for _,path,_ in cases):raise RuntimeError('original capture changed')
    report={'schema':'bpt.core3-candidate-native-results.v1','freezeSHA256':sha(out/'pre-outcome-freeze.json'),'experimentSHA256':sha(experiment_path),'sourceUnchanged':True,'originalsUnchanged':True,'opportunities':dict(opportunities),'pythonNativeParityRequests':parity_requests,'maximumDriverLineBytes':maximum_payload,'results':[], 'rawAssessmentMatrices':[],'scope':'reused actual development captures; engineering predicate outcomes, not independent form accuracy; phase and source clocks frozen from original capture'}
    for (exercise,setting,mode,rule),aggregate in sorted(aggregates.items()):report['results'].append({'exercise':exercise,'setting':setting,'mode':mode,'rule':rule,**{k:dict(v) if isinstance(v,Counter) else v for k,v in aggregate.items()}})
    for (exercise,rule,kind),counts in sorted(raw_matrices.items()):report['rawAssessmentMatrices'].append({'exercise':exercise,'rule':rule,'opportunityKind':kind,'counts':dict(counts)})
    (out/'aggregate.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps({'output':str(out/'aggregate.json'),'opportunities':dict(opportunities),'parityRequests':parity_requests,'originalsUnchanged':True}),flush=True)

if __name__=='__main__':main()
