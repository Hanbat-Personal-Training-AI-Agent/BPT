"""One frozen ratio4 reliability diagnostic on existing Home full outputs, no pose changes/inference.
Original full coordinates are scored unchanged; GT files open only after mask/evidence save.
"""
import argparse,collections,hashlib,json,os,sys,time
from pathlib import Path
import numpy as np
from bone_correction_reliability import evaluate,SEGMENTS,NAMES
from check_parity import check

def stats(x):
    x=np.asarray(x).ravel();assert np.isfinite(x).all()
    return {'n':int(x.size),'mean':float(x.mean()),'median':float(np.median(x)),'p95':float(np.percentile(x,95)),'max':float(x.max()),'min':float(x.min())} if x.size else {'n':0}

def generate(raw,exercise,stored,existing):
    from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints
    from pose_feedback.geometry.bone_lengths import apply_bone_lengths
    engine=Pose3DConstraints(reflect_flipped_knee=exercise=='squat');union=existing.copy();ratios=np.full((len(raw),8),np.nan);reasons=collections.Counter();source=collections.Counter();first=None;maximum=0.;nonzero=0;rows=[]
    original_bytes=hashlib.sha256(raw.tobytes()+stored.tobytes()+existing.tobytes()).hexdigest()
    for t in range(21,len(raw)):
        targets=engine.session_targets() or engine.prior_lengths;kind='session' if engine.session_targets() else 'prior'
        if kind=='session' and first is None:first=t
        _,bone=apply_bone_lengths(raw[t],targets)
        fixed,report=engine.apply(raw[t]);differences=np.abs(fixed-stored[t]);maximum=max(maximum,float(differences.max()));nonzero+=int((differences!=0).sum())
        assert np.isfinite(differences).all() and differences.max()<=1e-12 and report['invalid_joints']==np.flatnonzero(existing[t]).tolist()
        result=evaluate(raw[t],bone['segments'],bone['scale'],np.flatnonzero(existing[t]).tolist())
        union[t]=False;union[t,result['invalid']]=True
        assert np.all(union[t]|~existing[t])
        for j,e in enumerate(result['segments']):
            ratios[t,j]=e['expansion'] if e['expansion'] is not None else np.nan
            reasons.update(e['reasons']);source[e['status']]+=1
        rows.append((t,result))
    assert original_bytes==hashlib.sha256(raw.tobytes()+stored.tobytes()+existing.tobytes()).hexdigest()
    return union,ratios,rows,{'coordinate_max_error':maximum,'coordinate_nonzero_components':nonzero,'coordinate_components':(len(raw)-21)*51,'existing_masks_exact':True,'original_arrays_unchanged':True,'first_session_frame':first,'segment_statuses':dict(source),'reasons':dict(reasons)}

def main(args):
    # Structural Swift/Python gate is independent of any actual-data thresholds or labels.
    parity=check(args.synthetic);assert parity['passed']
    run=Path.home()/'bpt-runs/motion-contact/20261020-v3-clean96';m=json.load(open(run/'manifest.json'));old=json.load(open(run/'results.json'));assert old['complete']
    original=Path.home()/'bpt-runs/target-continuity-20261102/results';original_summary=json.load(open(original/'aggregate.json'));assert original_summary['complete']
    digest=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();full_hashes={p.name:digest(p) for p in (original/'predictions').glob('*.npz')}
    assert hashlib.sha256(json.dumps(full_hashes,sort_keys=True).encode()).hexdigest()==original_summary['candidate_output_hash_manifest_sha256']
    reference=Path(m['argv'][0]).parents[1]
    for p,h in m['code'].items():assert digest(reference/p)==h
    dependency_expected={'pose_feedback/geometry/bone_lengths.py':'cd09e68b75cb7b1568e9327735c58444ada7d4892533ed981cd71d3806f55fb5','pose_feedback/geometry/hinge_limit.py':'ec19d683ce65d0b345529ebfadd41b8c8cf169943e942a64e005118017cf7664'}
    for p,h in dependency_expected.items():assert digest(reference/p)==h
    sys.path[:0]=[str(reference),str(reference/'scripts')]
    from motion_contact.data import load_observations,load_score_reference,JOINTS
    argv=m['argv'];opt=lambda key,default=None:argv[argv.index(key)+1] if key in argv else default
    records=sorted([r for r in old['records'] if r['variant']=='A' and r['split']=='heldout'],key=lambda r:r['name']);assert len(records)==60
    args.out.mkdir(parents=True,exist_ok=False);(args.out/'diagnostics').mkdir()
    buckets={};stream_summaries=[];inputs={};max_error=0.;nonzero=0;components=0;worst_nongated=[];worst_added=[];code_hashes={p.name:digest(p) for p in Path(__file__).parent.glob('*.py')};started=time.monotonic();output_hashes={};statuses=collections.Counter();allreasons=collections.Counter()
    for i,r in enumerate(records):
        o=load_observations(Path(opt('--cache'))/(r['name']+'.npz'),Path(opt('--pose2d'))/(r['name']+'.npz'))
        for p,h in o.inputs.items():assert m['inputs'][p]==h;inputs[p]=h
        with np.load(original/'predictions'/f'stream_{i:02d}.npz') as z:stored=z['full'].copy();existing=z['full_invalid'].copy()
        union,ratios,rows,gate=generate(o.raw,o.exercise,stored,existing);max_error=max(max_error,gate['coordinate_max_error']);nonzero+=gate['coordinate_nonzero_components'];components+=gate['coordinate_components'];statuses.update(gate['segment_statuses']);allreasons.update(gate['reasons'])
        new=union & ~existing;path=args.out/'diagnostics'/f'stream_{i:02d}.npz';np.savez_compressed(path,invalid=union,additional=new,expansion_ratios=ratios,source_time=o.timestamps);output_hashes[path.name]=digest(path)
        # FIRST GT joint/camera/rep access: all reliability masks/evidence are already complete and saved.
        ref=load_score_reference(opt('--dataset-root',str(Path.home()/'datasets/fit3d')),o)
        for p,h in ref.inputs.items():assert m['inputs'][p]==h;inputs[p]=h
        pose_m=(stored-stored[:,:1])*ref.metres_per_crop_unit[:,None,None];error=np.linalg.norm(pose_m-ref.joints_m,axis=-1)*1000;assert np.isfinite(error).all()
        raw_error=np.linalg.norm((o.raw-o.raw[:,:1])*ref.metres_per_crop_unit[:,None,None]-ref.joints_m,axis=-1)*1000
        first=gate['first_session_frame'];n=len(o.raw);cut=first if first is not None else n
        partitions={'main':(90,n),'prior':(21,cut),'early':(cut,90) if cut<90 else (90,90),'tail5_excluded':(90,max(90,n-5))}
        for part,(a,b) in partitions.items():
            if b<=a:continue
            for exercise in ('all',o.exercise):
                key=(part,exercise);bucket=buckets.setdefault(key,{'error':[],'old':[],'union':[],'new':[],'confidence':[],'streams':0})
                bucket['error'].append(error[a:b]);bucket['old'].append(existing[a:b]);bucket['union'].append(union[a:b]);bucket['new'].append(new[a:b]);bucket['confidence'].append(o.normalized[a:b,:,2]);bucket['streams']+=1
        for label,mask,destination in [('remaining',~union,worst_nongated),('additional',new,worst_added)]:
            available=mask.copy();available[:90]=False
            indices=np.argwhere(available)
            if len(indices):
                order=np.argsort(error[available])[-3:][::-1]
                for k in order:
                    t,j=indices[k];destination.append({'exercise':o.exercise,'joint':JOINTS[j],'source_frame_index':int(t),'source_time_seconds':float(o.timestamps[t]),'full_error_mm':float(error[t,j]),'raw_error_mm':float(raw_error[t,j]),'RTMPose_score_unclipped':float(o.normalized[t,j,2]),'baseline_invalid':bool(existing[t,j]),'new_invalid':bool(union[t,j]),'tail5':bool(t>=n-5)})
        # Previously frozen left-wrist position-worsening case, identified without retuning the bound.
        original_worst=None
        if o.exercise=='squat' and n>112 and abs(float(error[112,13])-300.65182260030224)<1e-8:
            original_worst={'exercise':'squat','joint':'left_wrist','source_frame_index':112,'source_time_seconds':float(o.timestamps[112]),'full_error_mm':float(error[112,13]),'new_invalid':bool(union[112,13]),'additional_invalid':bool(new[112,13]),'segments':[e for t,res in rows if t==112 for e in res['segments'] if e['child'] in (12,13)]}
        stream_summaries.append({'stream_index':i,'exercise':o.exercise,'gate':gate,'main_additional_joint_frames':int(new[90:].sum()),'main_all_error_mean_unchanged_mm':float(error[90:].mean()),'previous_frozen_worst':original_worst})
        print(f'completed {i+1}/60 ({o.exercise}) {time.monotonic()-started:.1f}s',file=sys.stderr,flush=True)
    for p,h in inputs.items():assert digest(p)==h
    for name,h in full_hashes.items():assert digest(original/'predictions'/name)==h
    summaries={}
    for (part,exercise),b in buckets.items():
        error=np.concatenate(b['error']);existing=np.concatenate(b['old']);union=np.concatenate(b['union']);new=np.concatenate(b['new']);confidence=np.concatenate(b['confidence']);retained=~union
        subsets={'all':np.ones_like(new),'existing_invalid':existing,'additional_withheld':new,'union_invalid':union,'remaining_not_invalid':retained}
        anynew=new.any(1);wholefallback_additional=int((~existing[anynew]).sum())
        g={'streams':b['streams'],'frames':len(error),'joint_frames':int(error.size),'all_baseline_error_unchanged_mm':stats(error),'subsets':{name:{'joint_frames':int(mask.sum()),'full_error_mm':stats(error[mask]),'raw_RTMPose_score':stats(confidence[mask])} for name,mask in subsets.items()},'additional_joint_frames':int(new.sum()),'additional_frame_count':int(anynew.sum()),'partial_union_frame_count':int((union.any(1)&~union.all(1)).sum()),'whole_union_frame_count':int(union.all(1).sum()),'wholepose_if_any_additional_extra_joint_frames':wholefallback_additional,'per_joint':{name:{'all_error_unchanged_mm':stats(error[:,j]),'additional_joint_frames':int(new[:,j].sum()),'additional_error_mm':stats(error[:,j][new[:,j]]),'remaining_error_mm':stats(error[:,j][retained[:,j]])} for j,name in enumerate(JOINTS)}}
        summaries.setdefault(part,{})[exercise]=g
    assert summaries['main']['all']['joint_frames']==568004
    assert abs(summaries['main']['all']['all_baseline_error_unchanged_mm']['mean']-original_summary['summaries']['primary']['all']['MPJPE_mm']['full']['mean'])<1e-12
    result={'complete':True,'protocol_commit':'eacdece+4cd98ff+fa95e71','maximum_expansion':4.,'coordinate_gate_tolerance':1e-12,'baseline_max_coordinate_error':max_error,'baseline_nonzero_coordinate_components':nonzero,'baseline_coordinate_components':components,'existing_masks_exact':True,'original_arrays_and_full_cache_unchanged':True,'synthetic_parity':parity,'threads':1,'nice':19,'wall_seconds':time.monotonic()-started,'statuses_all_usable':dict(statuses),'reasons_all_usable':dict(allreasons),'summaries':summaries,'anonymous_stream_summaries':stream_summaries,'largest_remaining_nongated_errors':sorted(worst_nongated,key=lambda e:e['full_error_mm'],reverse=True)[:5],'largest_additional_withheld_errors':sorted(worst_added,key=lambda e:e['full_error_mm'],reverse=True)[:5],'combined_input_manifest_sha256':hashlib.sha256(json.dumps(inputs,sort_keys=True).encode()).hexdigest(),'combined_original_full_cache_sha256':hashlib.sha256(json.dumps(full_hashes,sort_keys=True).encode()).hexdigest(),'combined_output_manifest_sha256':hashlib.sha256(json.dumps(output_hashes,sort_keys=True).encode()).hexdigest(),'code_sha256':code_hashes,'reference_dependency_sha256':dependency_expected,'interpretation':'No coordinates changed: all-error MPJPE unchanged. Conditional retained error is selection with extra withholding, not correction or verified accuracy/FN improvement. ratio4 is an uncalibrated engineering uncertainty diagnostic. GT joint arrays loaded only after masks saved; historical result score summaries read upfront for fixed stream identity/compatibility.'}
    (args.out/'aggregate.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n');print(json.dumps({'complete':True,'main_joint_frames':568004,'coordinate_max_error':max_error,'main_additional_joint_frames':summaries['main']['all']['additional_joint_frames']}))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--synthetic',type=Path,required=True);p.add_argument('--out',type=Path,required=True);main(p.parse_args())
