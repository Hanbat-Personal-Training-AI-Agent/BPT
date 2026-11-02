"""Private local replay; aggregate export only. python -m scripts.coaching_contract.replay"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
from .adapters import native, deep_report, file_sha
from .engine import evaluate, compare


def write(path, value):
    with open(path, 'x', encoding='utf8') as out:
        os.chmod(path, 0o600)
        json.dump(value, out, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        out.write('\n')


def aggregate(result):
    reps=result['reps']
    return {'exercise':result['exercise'],'observation_sha256':result['clip']['observation_sha256'],
            'input_contract_sha256':result['input_sha256'],'source_kind':result['source']['kind'],
            'rep_count':len(reps),'qualified_states':dict(Counter(r['qualified_shadow']['state'] for r in reps)),
            'withheld_reason_counts':dict(Counter(reason for r in reps for reason in r['qualified_shadow']['reasons'])),
            'runtime_states':dict(Counter(r['runtime']['state'] for r in reps)),
            'retained_original_fault_keys':dict(Counter(f['key'] for r in reps for f in (r['runtime'].get('original_faults') or []))),
            'delivery_states':dict(Counter(r['delivery']['state'] for r in reps)),
            'scalar_available':sum(r['common_scalar']['value_deg'] is not None for r in reps),
            'observed_subset_positive':sum(r['common_scalar']['observed_subset_predicate'] is True for r in reps),
            'absolute_normality':result['absolute_normality'],'reference_correctness':result['reference_correctness']}


def run(args):
    output=Path(args.output)
    output.mkdir(mode=0o700,parents=False,exist_ok=False)
    (output/'INCOMPLETE').touch(mode=0o600)
    try:
        inputs=[(Path(p),sha) for p,sha in args.native]
        if args.deep_report:
            for p in (args.deep_report,args.deep_evidence,args.deep_verification):
                if not p:raise ValueError('all_deep_paths_required')
            inputs.extend((Path(p),file_sha(p)) for p in (args.deep_report,args.deep_evidence,args.deep_verification))
        write(output/'input-receipt.json',{'schema':'bpt.coaching-shadow-replay-receipt.v1','read_only':True,
                                         'inputs':[{'path':str(p),'expected_sha256':sha} for p,sha in inputs]})
        streams=[]
        for p,sha in args.native: streams.extend(native(p,sha))
        if args.deep_report:
            streams.append(deep_report(args.deep_report,args.deep_sha256,args.deep_evidence,args.deep_verification))
        aggregates=[]
        results=[]
        for i,stream in enumerate(streams):
            result=evaluate(stream)
            write(output/('stream-%02d.json'%i),stream)
            write(output/('result-%02d.json'%i),result)
            aggregates.append(aggregate(result))
            results.append(result)
        for p,sha in inputs:
            if file_sha(p)!=sha:raise ValueError('input_changed')
        comparisons=[]
        for i,left in enumerate(results):
            for j,right in enumerate(results[i+1:],i+1):
                if left['exercise'] != right['exercise'] or left['source']['kind'] == right['source']['kind']:
                    continue
                compared=compare(left,right)
                write(output/('comparison-%02d-%02d.json'%(i,j)),compared)
                comparisons.append({'exercise':left['exercise'],'left_index':i,'right_index':j,
                                    'states':dict(Counter(r['comparison_state'] for r in compared['reps'])),
                                    'reason_counts':dict(Counter(v for r in compared['reps'] for v in r['reasons'])),
                                    'numeric_pair_count':sum(r['descriptive_delta_deg'] is not None for r in compared['reps']),
                                    'semantic_parity_asserted':False})
        summary={'schema':'bpt.coaching-shadow-replay-aggregate.v1','shadow_only':True,
                 'new_inference':False,'ground_truth_used':False,'accuracy_claim':False,
                 'streams':aggregates,'comparisons':comparisons,'input_files_unchanged':True}
        write(output/'aggregate.json',summary)
        (output/'INCOMPLETE').unlink()
        return summary
    except Exception as error:
        write(output/'failure.json',{'status':'incomplete','error_type':type(error).__name__,'reason':str(error)})
        raise


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--native',nargs=2,action='append',default=[],metavar=('JSONL','EXPECTED_SHA256'))
    p.add_argument('--deep-report');p.add_argument('--deep-sha256');p.add_argument('--deep-evidence');p.add_argument('--deep-verification')
    p.add_argument('--output',required=True)
    a=p.parse_args()
    if not a.native and not a.deep_report:p.error('at_least_one_existing_input_required')
    print(json.dumps(run(a),ensure_ascii=False,sort_keys=True))

if __name__=='__main__':main()
