"""Derived reliability coverage on preserved original native captures; no GT or pose edits."""
import argparse,collections,hashlib,importlib.util,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
s=importlib.util.spec_from_file_location('wrist_metrics',ROOT/'scripts/wrist_observation/analyze.py');a=importlib.util.module_from_spec(s);s.loader.exec_module(a)

def summarize(paths,scratch):
    gate=json.loads((scratch/'parity.json').read_text());assert gate['passed'] and gate['max_evidence_numerical_error']==0
    native=json.loads((scratch/'native_result.json').read_text());assert native['baseline_max_coordinate_error']<=1e-12 and native['existing_masks_exact'] and native['raw_arrays_unchanged']
    rows={g['exercise']:{r['frame']:r['result'] for r in g['frames']} for g in native['groups']};groups={};digests=[]
    for path in paths:
        epochs,capped,digest=a.strict.load(path);assert not capped;digests.append(digest)
        for data in epochs.values():
            assert data['end'] and not data['end']['incomplete']
            fs=data['frames'];ex=data['start']['exercise'];r=rows[ex];good=[f for f in fs if not f['flush_tail'] and f['frame'] in r]
            before=hashlib.sha256(json.dumps([[f['raw_3d'],f['constrained_3d']] for f in fs]).encode()).hexdigest()
            reasons=collections.Counter();statuses=collections.Counter();perjoint=collections.Counter();expansions=[];corrections=[]
            for f in good:
                result=r[f['frame']];assert result['existing_invalid']==sorted(f['invalid'])
                perjoint.update(result['additional_invalid'])
                for e in result['segments']:
                    reasons.update(e['reasons']);statuses[e['status']]+=1
                    if e['expansion'] is not None:expansions.append(e['expansion'])
                    if e['absolute_length_correction'] is not None:corrections.append(e['absolute_length_correction'])
            events=[]
            for side,ids in a.SIDES.items():
                for layer in ('raw_3d','constrained_3d'):
                    _,edges=a.distribution_kinematics(fs,layer,side)
                    for rank,(i,value) in enumerate(sorted(edges,key=lambda p:p[1]['speed'],reverse=True)[:3],1):
                        f0,f1=fs[i:i+2];joint=ids['wrist3d'];parents={ids['elbow3d'],joint}
                        events.append({'side':side,'ranking_layer':layer,'rank':rank,'source_interval_seconds':[f0['source_pts'],f1['source_pts']],'original_wrist_speed_model_units_s':value['speed'],'RTMPose_score_endpoints':[a.score(f0,side),a.score(f1,side)],'original_wrist_invalid':[joint in f['invalid'] for f in (f0,f1)],'proposed_wrist_invalid':[joint in r[f['frame']]['invalid'] for f in (f0,f1)],'relevant_segment_evidence':[[e for e in r[f['frame']]['segments'] if e['child'] in parents] for f in (f0,f1)]})
            newframes=sum(bool(r[f['frame']]['additional_invalid']) for f in good)
            groups[ex]={'source_frames':len(fs),'genuine_nonflush_frames':sum(not f['flush_tail'] for f in fs),'usable_genuine_frames':len(good),'warmup_or_missing_genuine_frames':sum(not f['flush_tail'] and f['frame'] not in r for f in fs),'flush_frames':sum(f['flush_tail'] for f in fs),'source_gaps':sum(b['source_index']!=b0['source_index']+1 for b0,b in zip(fs,fs[1:])),'original_invalid_joint_frames':sum(len(f['invalid']) for f in good),'additional_invalid_joint_frames':sum(len(r[f['frame']]['additional_invalid']) for f in good),'additional_invalid_frames':newframes,'partial_union_frames':sum(0<len(r[f['frame']]['invalid'])<17 for f in good),'whole_union_frames':sum(len(r[f['frame']]['invalid'])==17 for f in good),'wholepose_if_any_additional_extra_joint_frames':sum(17-len(f['invalid']) for f in good if r[f['frame']]['additional_invalid']),'per_joint_additional':{str(j):perjoint[j] for j in range(17)},'segment_status_counts':dict(statuses),'reason_counts':dict(reasons),'all_segment_expansions':a.stats(expansions),'absolute_segment_length_correction_model_units':a.stats(corrections),'ranked_original_wrist_events':events}
            assert before==hashlib.sha256(json.dumps([[f['raw_3d'],f['constrained_3d']] for f in fs]).encode()).hexdigest()
        assert hashlib.sha256(path.read_bytes()).hexdigest()==digest
    return {'candidate_maximum_expansion':4.,'parity_and_baseline_gate':gate,'native_receipt':json.loads((scratch/'receipt.json').read_text()),'combined_original_capture_hash_manifest':hashlib.sha256('\n'.join(sorted(digests)).encode()).hexdigest(),'stored_raw_full_arrays_unchanged':True,'groups':groups,'interpretation':'Diagnostic counterfactual extra masks only. Original native outputs/counts/reports not changed. No GT, MPJPE, posture/FN or accurate-error-detector claim; RTMPose scores retained after hybrid input are descriptive, not probability/MP localization accuracy.'}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('captures',nargs='+',type=Path);p.add_argument('--scratch',type=Path,required=True);args=p.parse_args();print(json.dumps(summarize(args.captures,args.scratch),indent=2,allow_nan=False))
