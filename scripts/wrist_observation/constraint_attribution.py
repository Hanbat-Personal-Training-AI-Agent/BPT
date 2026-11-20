"""Paired same-source constraint-stage description, conditional on native replay parity."""
import argparse
import collections
import importlib.util
import json
import math
from pathlib import Path

spec=importlib.util.spec_from_file_location('wrist_audit',Path(__file__).with_name('analyze.py'))
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
MODES=('full','bone_only','angle_only','fixed_prior_full')

def relative(points,joint):return a.sub(points[3*joint:3*joint+3],points[:3])
def vector_difference(x,y):return a.sub(y,x)
def speed(x,y,dt):return a.norm(a.sub(y,x))/dt

def verify_coordinates(frames,rows):
    errors=[]
    for f in frames:
        if f['constrained_3d'] is None:continue
        a.strict.require(f['frame'] in rows,'missing_replay_frame')
        row=rows[f['frame']]
        a.strict.require(len(row['full'])==51,'wrong_replay_shape')
        a.strict.require(all(a.strict.finite(v) for v in row['full']),'nonfinite_replay_coordinate')
        errors.extend(abs(x-y) for x,y in zip(f['constrained_3d'],row['full']))
        a.strict.require(sorted(f['invalid'])==row['invalid'],'invalid_mask_replay_mismatch')
    a.strict.require(errors and max(errors)<=1e-12,'native_coordinate_replay_mismatch')
    return errors


def calculate(paths,replay_path,receipt_path):
    replay={g['exercise']:{f['frame']:f for f in g['frames']} for g in json.loads(replay_path.read_text())}
    groups={};all_errors=[];source=[]
    # First verify every logged constrained coordinate, including flush, before any counterfactual.
    loaded=[]
    for path in paths:
        epochs,capped,digest=a.strict.load(path);a.strict.require(not capped,'capped_capture');source.append(digest)
        for data in epochs.values():
            a.strict.require(data['end'] is not None and not data['end']['incomplete'],'incomplete_capture')
            ex=data['start']['exercise'];frames=data['frames'];rows=replay[ex];errors=[]
            errors=verify_coordinates(frames,rows)
            all_errors+=errors;loaded.append((ex,frames,rows,errors))
    for ex,frames,rows,errors in loaded:
        genuine=[f for f in frames if not f['flush_tail'] and f['frame'] in rows]
        source_changes=[];previous=None;angle_counts=collections.Counter()
        for f in genuine:
            r=rows[f['frame']]
            if previous and r['bone_source']!=previous['bone_source']:source_changes.append({'frame':f['frame'],'source_pts_seconds':f['source_pts'],'from':previous['bone_source'],'to':r['bone_source']})
            angle_counts.update(r['angle_corrections'].keys());previous=r
        out={'all_coordinate_max_absolute_error':max(errors),'all_coordinate_comparisons_including_flush':len(errors),'genuine_usable_frames':len(genuine),'bone_source_counts':dict(collections.Counter(rows[f['frame']]['bone_source'] for f in genuine)), 'source_changes':source_changes,'angle_limit_firing_frames':dict(angle_counts),'knee_reflection_frames':sum(rows[f['frame']]['knees_reflected']>0 for f in genuine),'knee_clamp_frames':sum(rows[f['frame']]['knee_clamp_degrees']>0 for f in genuine),'sides':{}}
        for side,ids in a.SIDES.items():
            _,edges=a.distribution_kinematics(frames,'assessment_3d',side)
            ranked=sorted(edges,key=lambda x:x[1]['speed'],reverse=True)
            all_stage_speeds={m:[] for m in MODES};target_steps=[];events=[];j=ids['wrist3d']
            for i,value in edges:
                f0,f1=frames[i:i+2];r0,r1=rows[f0['frame']],rows[f1['frame']];dt=value['dt']
                for mode in MODES:all_stage_speeds[mode].append(speed(relative(r0[mode],j),relative(r1[mode],j),dt))
                # Fixed current raw input, prior frame's targets vs current frame's targets.
                target_steps.append(a.norm(a.sub(relative(r1['current_targets_bone'],j),relative(r1['previous_targets_bone'],j))))
            for rank,(i,value) in enumerate(ranked[:3],1):
                f0,f1=frames[i:i+2];r0,r1=rows[f0['frame']],rows[f1['frame']];dt=value['dt']
                event=a.event_description(frames,i,a.interval(f0,f1,'raw_3d',side),side,rank)
                event.pop('rank_by_raw3d_root_relative_speed')
                event['rank_by_assessment3d_root_relative_speed']=rank
                event['rank_basis']='assessment3d_root_relative_speed'
                event['speeds_by_independent_mode']={mode:speed(relative(r0[mode],j),relative(r1[mode],j),dt) for mode in MODES}
                event['constraint_reports']=[{k:r[k] for k in ('bone_source','bone_scale','bone_max_correction','angle_corrections','knees_reflected','knee_clamp_degrees','invalid')} for r in (r0,r1)]
                event['segments']={}
                for name,parent,child in [('upper_arm',ids['shoulder3d'],ids['elbow3d']),('forearm',ids['elbow3d'],j)]:
                    raw_vectors=[a.sub(f['raw_3d'][3*child:3*child+3],f['raw_3d'][3*parent:3*parent+3]) for f in (f0,f1)]
                    bone_vectors=[a.sub(r['bone_only'][3*child:3*child+3],r['bone_only'][3*parent:3*parent+3]) for r in (r0,r1)]
                    raw_lengths=[a.norm(v) for v in raw_vectors];bone_lengths=[a.norm(v) for v in bone_vectors]
                    cosine=sum(x*y for x,y in zip(*raw_vectors))/(raw_lengths[0]*raw_lengths[1]) if min(raw_lengths)>0 else None
                    event['segments'][name]={'raw_lengths_model_units':raw_lengths,'bone_only_lengths_model_units':bone_lengths,'output_over_raw_length':[b/r if r>0 else None for b,r in zip(bone_lengths,raw_lengths)],'raw_direction_change_degrees':math.degrees(math.acos(max(-1,min(1,cosine)))) if cosine is not None else None}
                event['bone_interval_speed_with_previous_targets_at_current_frame']=speed(relative(r0['bone_only'],j),relative(r1['previous_targets_bone'],j),dt)
                event['targets_changed']=r0['targets']!=r1['targets']
                event['bone_target_update_same_current_raw_wrist_displacement']=a.norm(a.sub(relative(r1['current_targets_bone'],j),relative(r1['previous_targets_bone'],j)))
                # Vector accounting is additive before taking norms; scalar speeds are not additive.
                raw_v=a.interval(f0,f1,'raw_3d',side)['velocity']
                full_v=tuple(v/dt for v in a.sub(relative(r1['full'],j),relative(r0['full'],j)))
                event['correction_vector_change_speed']=a.norm(a.sub(full_v,raw_v))
                # Retain per-endpoint target shape without declaring its arbitrary units physical.
                event['target_shape_normalized_to_sum']=[{k:v/sum(r['targets'].values()) for k,v in r['targets'].items()} for r in (r0,r1)]
                events.append(event)
            out['sides'][side]={'assessment_ranked_top3':events,'independent_mode_speed_distributions':{mode:a.stats(v) for mode,v in all_stage_speeds.items()},'target_update_same_current_raw_displacement':a.stats(target_steps)}
        groups[ex]=out
    return {'native_source_commit':'1a35d3f','coordinate_parity_required_max_absolute_error':1e-12,'all_coordinate_max_absolute_error':max(all_errors),'all_coordinate_comparisons_including_flush':len(all_errors),'replay_receipt':json.loads(receipt_path.read_text()),'groups':groups,'interpretation':'Independent postprocessing ablations on identical already-inferred raw arrays and native frame order. No GT or accuracy claim. Full/prior include angular stages; bone-only removes angular stages; angle-only removes bone stage. Neither speed norms nor nonlinear stage effects are additive. Prior/session target updates and per-frame bone scale are separate causes.'}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('captures',nargs='+',type=Path);p.add_argument('--replay',type=Path,required=True);p.add_argument('--receipt',type=Path,required=True);args=p.parse_args();print(json.dumps(calculate(args.captures,args.replay,args.receipt),indent=2,allow_nan=False))
