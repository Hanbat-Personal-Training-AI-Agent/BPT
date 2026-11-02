"""Home-only frozen candidate CPU postprocessing. GT loaded strictly after stream outputs.
No model imports/inference; immutable original inputs. Export aggregate only.
"""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import sys
import time


def stats(x):
    import numpy as np
    x=np.asarray(x).ravel();assert np.isfinite(x).all()
    return {'n':int(x.size),'mean':float(x.mean()),'median':float(np.median(x)),'p95':float(np.percentile(x,95)),'max':float(x.max()),'min':float(x.min())} if x.size else {'n':0}


def paired(a,b):
    import numpy as np
    d=np.asarray(b)-np.asarray(a)
    return dict(candidate_minus_full=stats(d),worsened_joint_frames=int((d>1e-9).sum()),improved_joint_frames=int((d< -1e-9).sum()),equal_within_1e_9mm_joint_frames=int((np.abs(d)<=1e-9).sum()))


def produce(raw,timestamps,exercise):
    """GT-free state boundary: only existing model outputs, source time and exercise identity."""
    import numpy as np
    from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints
    from bone_target_continuity import BoneTargetContinuity
    full=Pose3DConstraints(reflect_flipped_knee=exercise=='squat');candidate=Pose3DConstraints(reflect_flipped_knee=exercise=='squat');filter=BoneTargetContinuity()
    b=raw.copy();c=raw.copy();bi=np.ones((len(raw),17),bool);ci=bi.copy();first=None;target_rows=[];filter_rows=[];sources=[]
    immutable=hashlib.sha256(raw.tobytes()).hexdigest()
    for t in range(21,len(raw)):
        targets=full.session_targets() or full.prior_lengths;source='session' if full.session_targets() else 'prior'
        if source=='session' and first is None:first=t
        filtered=filter.update(targets,float(timestamps[t]),source,'stream')
        assert filtered['filtered_shape'] is not None
        candidate.calibration_targets_cm=filtered['filtered_shape']
        b[t],br=full.apply(raw[t]);c[t],cr=candidate.apply(raw[t])
        bi[t]=False;ci[t]=False;bi[t,br['invalid_joints']]=True;ci[t,cr['invalid_joints']]=True
        keys=sorted(targets);target_rows.append([targets[k] for k in keys]);filter_rows.append([filtered['filtered_shape'][k] for k in keys]);sources.append(source)
    assert immutable==hashlib.sha256(raw.tobytes()).hexdigest()
    return dict(full=b,candidate=c,full_invalid=bi,candidate_invalid=ci,first_session=first,original_targets=np.asarray(target_rows),filtered_shapes=np.asarray(filter_rows),target_sources=np.asarray(sources),target_keys=keys)


def main(args):
    import numpy as np
    from check_continuity_parity import check
    run=Path.home()/'bpt-runs/motion-contact/20261020-v3-clean96';manifest=json.loads((run/'manifest.json').read_text());old=json.loads((run/'results.json').read_text())
    assert old['complete'];digest=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
    assert digest(run/'results.json')==next(v for k,v in manifest['outputs'].items() if Path(k).name=='results.json')
    reference=Path(manifest['argv'][0]).resolve().parents[1]
    for p,value in manifest['code'].items():assert digest(reference/p)==value
    # Re-run synthetic native parity on the exact existing Home reference before reading real raw arrays.
    gate=check(args.fixture,reference);assert gate['passed']
    sys.path[:0]=[str(reference),str(reference/'scripts')]
    from motion_contact.data import load_observations,load_score_reference,JOINTS
    from motion_contact.metrics import pose_angles
    args.out.mkdir(parents=True,exist_ok=True)
    assert not (args.out/'aggregate.json').exists() and not (args.out/'predictions').exists(),'fresh output required'
    (args.out/'predictions').mkdir()
    (args.out/'parity.json').write_text(json.dumps(gate,indent=2))
    argv=manifest['argv'];option=lambda n,d=None:argv[argv.index(n)+1] if n in argv else d
    assert option('--scenario-dir') is None and option('--limit') is None
    cache=Path(option('--cache'));pose=Path(option('--pose2d'));dataset=Path(option('--dataset-root',str(Path.home()/'datasets/fit3d')))
    records=sorted([r for r in old['records'] if r['variant']=='A' and r['split']=='heldout'],key=lambda r:r['name']);assert len(records)==60
    buckets={};streams=[];inputs={};started=time.monotonic();raw_max_error=0.;candidate_output_hashes={};source_switches=[]
    for index,record in enumerate(records):
        o=load_observations(cache/(record['name']+'.npz'),pose/(record['name']+'.npz'))
        for p,value in o.inputs.items():assert manifest['inputs'][p]==value;inputs[p]=value
        outputs=produce(o.raw,o.timestamps,o.exercise)
        target=args.out/'predictions'/f'stream_{index:02d}.npz'
        np.savez_compressed(target,**{k:v for k,v in outputs.items() if isinstance(v,np.ndarray)},source_time=o.timestamps)
        candidate_output_hashes[target.name]=digest(target)
        # FIRST and only GT access for this stream, after both full/candidate arrays are complete and saved.
        ref=load_score_reference(dataset,o)
        for p,value in ref.inputs.items():assert manifest['inputs'][p]==value;inputs[p]=value
        predictions={'raw':o.raw,'full':outputs['full'],'candidate':outputs['candidate']}
        meters={mode:(x-x[:,:1])*ref.metres_per_crop_unit[:,None,None] for mode,x in predictions.items()}
        errors={mode:np.linalg.norm(x-ref.joints_m,axis=-1)*1000 for mode,x in meters.items()}
        raw_max_error=max(raw_max_error,abs(float(errors['raw'][90:].mean())-record['metrics']['mpjpe_mm']['mean']))
        assert raw_max_error<1e-9
        angles={mode:pose_angles(x,ref.up_camera) for mode,x in meters.items()};gt_angles=pose_angles(ref.joints_m,ref.up_camera)
        angle_errors={mode:{k:np.abs(v-gt_angles[k]) for k,v in values.items()} for mode,values in angles.items()}
        first=outputs['first_session'];n=len(o.raw);cut=first if first is not None else n;source_switches.append(first)
        partitions={'primary':(90,n),'prior':(21,min(cut,n)),'early':(cut,90) if cut<90 else (90,90),'late':(90,n),'primary_no_tail5':(90,max(90,n-5))}
        stream={'stream_index':index,'exercise':o.exercise,'raw_frames':n,'first_session_frame':first,'first_session_source_seconds':None if first is None else float(o.timestamps[first]),'partitions':{}}
        for part,(start,end) in partitions.items():
            for exercise in ('all',o.exercise):
                key=(part,exercise)
                bucket=buckets.setdefault(key,{'errors':{m:[] for m in predictions},'invalid':{m:[] for m in ('full','candidate')},'angles':{m:collections.defaultdict(list) for m in predictions},'motion':{m:[] for m in predictions},'motion_stationary':{m:[] for m in predictions},'streams':0})
                if end<=start:continue
                bucket['streams']+=1
                for mode in predictions:
                    bucket['errors'][mode].append(errors[mode][start:end])
                    for k,v in angle_errors[mode].items():assert np.isfinite(v[start:end]).all();bucket['angles'][mode][k].append(v[start:end])
                for mode in ('full','candidate'):bucket['invalid'][mode].append(outputs[mode+'_invalid'][start:end])
                if end-start>5:
                    gt_delta=ref.joints_m[start+5:end]-ref.joints_m[start:end-5];distance=np.linalg.norm(gt_delta,axis=-1);eligible=distance>.020;stationary=distance<.005
                    for mode,x in meters.items():
                        delta=x[start+5:end]-x[start:end-5];gain=np.sum(delta*gt_delta,axis=-1)/np.maximum(distance**2,1e-12)
                        bucket['motion'][mode].append(gain[eligible]);bucket['motion_stationary'][mode].append((np.linalg.norm(delta,axis=-1)[stationary]>.020))
            stream['partitions'][part]={'joint_frames':int(max(0,end-start)*17),'MPJPE_mm':{mode:float(e[start:end].mean()) if end>start else None for mode,e in errors.items()}}
        streams.append(stream)
        print(f'completed {index+1}/60 ({o.exercise}), elapsed {time.monotonic()-started:.1f}s',file=sys.stderr,flush=True)
    # Original data identity verified once again after processing; no raw/source file may change.
    for p,value in inputs.items():assert digest(p)==value
    summary={}
    for (part,exercise),bucket in buckets.items():
        if not bucket['errors']['raw']:continue
        e={m:np.concatenate(v) for m,v in bucket['errors'].items()};inv={m:np.concatenate(v) for m,v in bucket['invalid'].items()}
        result={'streams':bucket['streams'],'frames':len(e['raw']),'joint_frames':int(e['raw'].size),'MPJPE_mm':{m:stats(v) for m,v in e.items()},'paired':paired(e['full'],e['candidate']),
          'invalid_joint_frames':{m:int(v.sum()) for m,v in inv.items()},'changed_invalid_joint_frames':int((inv['full']!=inv['candidate']).sum()),
          'per_joint':{name:{'MPJPE_mm':{m:stats(v[:,j]) for m,v in e.items()},'paired':paired(e['full'][:,j],e['candidate'][:,j])} for j,name in enumerate(JOINTS)},'angle_MAE_degrees':{},'motion_proxy':{}}
        for name in gt_angles:
            result['angle_MAE_degrees'][name]={m:stats(np.concatenate(bucket['angles'][m][name])) for m in e}
        for mode in e:
            values=np.concatenate(bucket['motion'][mode]) if bucket['motion'][mode] else np.empty(0)
            stationary=np.concatenate(bucket['motion_stationary'][mode]) if bucket['motion_stationary'][mode] else np.empty(0)
            result['motion_proxy'][mode]={'eligible_joint_intervals':int(values.size),'suppressed_count':int((values<.5).sum()),'suppressed_fraction':float((values<.5).mean()) if values.size else None,'gain':stats(values),'GT_stationary_joint_intervals':int(stationary.size),'stationary_false_movement_fraction':float(stationary.mean()) if stationary.size else None}
        summary.setdefault(part,{})[exercise]=result
    primary=summary['primary']['all'];assert primary['joint_frames']==568004 and round(primary['MPJPE_mm']['raw']['mean'],3)==146.839
    diffs=[s['partitions']['primary']['MPJPE_mm']['candidate']-s['partitions']['primary']['MPJPE_mm']['full'] for s in streams]
    output={'complete':True,'protocol_commit':'5a38764+ea0692a','candidate_protocol_commit':'e376f90','half_life_seconds':.2,'maximum_gap_seconds':1.,'threads':1,'nice':19,'wall_seconds':time.monotonic()-started,'streams':60,'parity_gate':gate,'A_max_stream_MPJPE_disagreement_mm':raw_max_error,'source_manifest_sha256':digest(run/'manifest.json'),'source_results_sha256':digest(run/'results.json'),'combined_input_hash_manifest_sha256':hashlib.sha256(json.dumps(inputs,sort_keys=True).encode()).hexdigest(),'input_file_count':len(inputs),'all_original_inputs_unchanged_after':True,'code_sha256':{p.name:digest(p) for p in Path(__file__).parent.glob('*.py')},'summaries':summary,'anonymous_stream_summaries':streams,'paired_primary_streams':{'candidate_minus_full_mm':stats(diffs),'worsened':sum(x>1e-9 for x in diffs),'improved':sum(x< -1e-9 for x in diffs),'equal':sum(abs(x)<=1e-9 for x in diffs)},'runtime_GT_inputs':False,'GT_load_order':'only after produce(raw,timestamps,exercise) completes and prediction arrays are saved for each stream','candidate_output_hash_manifest_sha256':hashlib.sha256(json.dumps(candidate_output_hashes,sort_keys=True).encode()).hexdigest(),'limitations':['Reused original validation streams, not fresh holdout.','Dataset sample time not native sensor PTS; pure Halpe/XS not phone hybrid path.','GT depth/focal conversion, gravity, angles and motion enter final scoring only.','All-error denominator includes masked predictions and clamped tail5; separate sensitivity retained.','GT displacement proxy is not human form-error FN, floor contact success or independent real-motion validation.']}
    (args.out/'aggregate.json').write_text(json.dumps(output,indent=2,allow_nan=False)+'\n')
    print(json.dumps({'complete':True,'streams':60,'primary_MPJPE_mm':{m:v['mean'] for m,v in primary['MPJPE_mm'].items()},'primary_joint_frames':primary['joint_frames'],'wall_seconds':output['wall_seconds']}),flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--out',type=Path,required=True);main(p.parse_args())
