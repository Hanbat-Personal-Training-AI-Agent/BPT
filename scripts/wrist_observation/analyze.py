"""Read-only actual-capture wrist description. No inference, error labels, correction or gating changes."""
import argparse
import collections
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import statistics

READER=Path(__file__).parents[1]/'terminal_evidence/replay.py'
spec=importlib.util.spec_from_file_location('pinned_terminal_reader',READER)
strict=importlib.util.module_from_spec(spec);spec.loader.exec_module(strict)
SIDES={'left':{'wrist2d':9,'elbow2d':7,'shoulder2d':5,'wrist3d':13,'elbow3d':12,'shoulder3d':11},
       'right':{'wrist2d':10,'elbow2d':8,'shoulder2d':6,'wrist3d':16,'elbow3d':15,'shoulder3d':14}}
LAYERS_2D=('raw_2d','input_2d','assessment_2d')
LAYERS_3D=('raw_3d','constrained_3d','adapted_3d','assessment_3d')


def quantile(values,p):
    x=(len(values)-1)*p;i=int(x);j=min(i+1,len(values)-1)
    return values[i]*(1-(x-i))+values[j]*(x-i)


def stats(values):
    values=sorted(v for v in values if strict.finite(v))
    if not values:return {'count':0}
    return {'count':len(values),'min':values[0],'median':statistics.median(values),'mean':sum(values)/len(values),
            'p95':quantile(values,.95),'max':values[-1]}


def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def norm(v):return math.sqrt(sum(x*x for x in v))


def point(frame,layer,joint):
    a=frame.get(layer)
    if a is None:return None
    values=a[3*joint:3*joint+3]
    if len(values)!=3 or not all(strict.finite(v) for v in values):return None
    if layer in LAYERS_2D:
        # Decoder score<=0 is an invalid-coordinate sentinel, not an invented quality threshold.
        return tuple(values[:2]) if values[2]>0 else None
    return tuple(values)


def wrist_position(frame,layer,side):
    ids=SIDES[side]
    if layer in LAYERS_2D:return point(frame,layer,ids['wrist2d'])
    if frame['raw_state'] not in ('ok','partial_3d'):return None
    if layer=='assessment_3d' and (frame['assessment_state'] not in ('ok','partial_3d') or {0,ids['wrist3d']}&set(frame['invalid'])):return None
    wrist=point(frame,layer,ids['wrist3d']);root=point(frame,layer,0)
    return sub(wrist,root) if wrist is not None and root is not None else None


def interval(frame0,frame1,layer,side):
    if frame0['flush_tail'] or frame1['flush_tail']:return None
    if any(f['raw_state']=='tracking_lost' for f in (frame0,frame1)):return None
    if frame0['raw_state'] in ('ok','partial_3d') and frame1['raw_state']=='warming_up':return None
    dt=frame1['source_pts']-frame0['source_pts']
    if not strict.finite(dt) or dt<=0:return None
    a=wrist_position(frame0,layer,side);b=wrist_position(frame1,layer,side)
    if a is None or b is None:return None
    vector=tuple(v/dt for v in sub(b,a))
    return {'dt':dt,'displacement':norm(sub(b,a)),'velocity':vector,'speed':norm(vector),
            'midpoint':(frame0['source_pts']+frame1['source_pts'])/2,
            'contiguous':frame1['frame']==frame0['frame']+1 and frame1['source_index']==frame0['source_index']+1}


def acceleration(first,second):
    dt=second['midpoint']-first['midpoint']
    return norm(tuple(v/dt for v in sub(second['velocity'],first['velocity']))) if dt>0 else None


def same_frame_change(frame,source,target,joint,root_relative=False):
    a=point(frame,source,joint);b=point(frame,target,joint)
    if a is None or b is None:return None
    if root_relative:
        ra=point(frame,source,0);rb=point(frame,target,0)
        if ra is None or rb is None:return None
        a=sub(a,ra);b=sub(b,rb)
    return norm(sub(b,a))


def distribution_kinematics(frames,layer,side):
    primary=[];gaps=[];acc=[];edges=[];previous=None
    for i,(a,b) in enumerate(zip(frames,frames[1:])):
        value=interval(a,b,layer,side)
        if value is None:previous=None;continue
        if value['contiguous']:
            primary.append(value);edges.append((i,value))
            if previous is not None and previous[0]==i-1:acc.append(acceleration(previous[1],value))
            previous=(i,value)
        else:gaps.append(value);previous=None
    return {'contiguous_intervals':len(primary),'displacement':stats([x['displacement'] for x in primary]),
            'speed':stats([x['speed'] for x in primary]),'acceleration_finite_difference':stats(acc),
            'dropped_source_gap_intervals':len(gaps),'gap_endpoint_average_speed':stats([x['speed'] for x in gaps]),
            'gap_dt':stats([x['dt'] for x in gaps])},edges


def score(frame,side,joint='wrist2d'):
    return frame['raw_2d'][3*SIDES[side][joint]+2]


def event_description(frames,index,value,side,rank):
    a,b=frames[index:index+2];ids=SIDES[side]
    out={'rank_by_raw3d_root_relative_speed':rank,'source_interval_seconds':[a['source_pts'],b['source_pts']],
         'dt_seconds':value['dt'],'raw3d_root_relative_displacement_model_units':value['displacement'],
         'raw3d_root_relative_speed_model_units_per_second':value['speed'],
         'RTMPose_wrist_scores_unclipped':[score(a,side),score(b,side)],
         'RTMPose_elbow_scores_unclipped':[score(a,side,'elbow2d'),score(b,side,'elbow2d')],
         'RTMPose_shoulder_scores_unclipped':[score(a,side,'shoulder2d'),score(b,side,'shoulder2d')],
         'raw_states':[a['raw_state'],b['raw_state']],'assessment_states':[a['assessment_state'],b['assessment_state']],
         'wrist_invalid':[ids['wrist3d'] in f['invalid'] for f in [a,b]],
         'elbow_invalid':[ids['elbow3d'] in f['invalid'] for f in [a,b]],
         'shoulder_invalid':[ids['shoulder3d'] in f['invalid'] for f in [a,b]],
         'input_crop_unit_px':[a['unit_px'],b['unit_px']],
         'raw_to_input_wrist_shift_px':[same_frame_change(f,'raw_2d','input_2d',ids['wrist2d']) for f in [a,b]],
         'raw_to_constrained_wrist_shift_model_units':[same_frame_change(f,'raw_3d','constrained_3d',ids['wrist3d']) for f in [a,b]]}
    for layer in ('raw_2d','input_2d','assessment_3d'):
        x=interval(a,b,layer,side)
        out[layer+'_displacement']=None if x is None else x['displacement'];out[layer+'_speed']=None if x is None else x['speed']
    for name in ('elbow3d','shoulder3d'):
        vectors=[]
        for f in [a,b]:
            p=point(f,'raw_3d',ids[name]);root=point(f,'raw_3d',0)
            vectors.append(None if p is None or root is None else sub(p,root))
        out[name+'_raw_root_relative_displacement_model_units']=norm(sub(vectors[1],vectors[0])) if all(v is not None for v in vectors) else None
    forearms=[]
    for f in [a,b]:
        wrist=point(f,'raw_3d',ids['wrist3d']);elbow=point(f,'raw_3d',ids['elbow3d'])
        forearms.append(None if wrist is None or elbow is None else sub(wrist,elbow))
    out['raw_forearm_lengths_model_units']=[None if v is None else norm(v) for v in forearms]
    out['raw_wrist_relative_to_elbow_vector_change_model_units']=norm(sub(forearms[1],forearms[0])) if all(v is not None for v in forearms) else None
    return out


def joint_angle(frame,layer,indices):
    a,b,c,d=[point(frame,layer,j) for j in indices]
    if any(p is None for p in (a,b,c,d)):return None
    u=sub(b,a);v=sub(d,c);den=norm(u)*norm(v)
    return math.degrees(math.acos(max(-1,min(1,sum(x*y for x,y in zip(u,v))/den)))) if den>0 else None


def angle_description(frames,side):
    ids=SIDES[side];out={}
    for name,indices,low,high in [('elbow',(ids['elbow3d'],ids['shoulder3d'],ids['elbow3d'],ids['wrist3d']),22,180),('shoulder',(8,0,ids['shoulder3d'],ids['elbow3d']),0,172)]:
        pairs=[(joint_angle(f,'raw_3d',indices),joint_angle(f,'constrained_3d',indices)) for f in frames]
        pairs=[(a,b) for a,b in pairs if a is not None and b is not None]
        out[name]={'raw_degrees':stats([a for a,b in pairs]),'constrained_degrees':stats([b for a,b in pairs]),'absolute_net_change_degrees':stats([abs(b-a) for a,b in pairs]),'raw_outside_configured_interval_frames':sum(a<low or a>high for a,b in pairs),'configured_interval_degrees':[low,high]}
    return out


def analyze(paths,private_evidence=None):
    output={};private=[];hashes=[]
    for path in paths:
        epochs,capped,digest=strict.load(path);strict.require(not capped,'capped_capture');hashes.append(digest)
        for epoch,data in epochs.items():
            strict.require(data['end'] is not None and not data['end']['incomplete'],'incomplete_capture')
            frames=data['frames'];exercise=data['start']['exercise'];strict.require(exercise not in output,'duplicate_exercise');genuine=[f for f in frames if not f['flush_tail']]
            candidate={f['frame']:f for f in data['candidate_frames']}
            identity={'source_frames':len(frames),'genuine_nonflush_frames':len(genuine),'flush_frames':len(frames)-len(genuine),
                'explicit_set_end_flush_frames':sum(f['flush_tail'] and candidate.get(f['frame'],{}).get('setEndFlushTail',False) for f in frames),
                'source_time_seconds':[frames[0]['source_pts'],frames[-1]['source_pts']],
                'source_dt_seconds':stats([b['source_pts']-a['source_pts'] for a,b in zip(frames,frames[1:])]),
                'source_index_gap_intervals':sum(b['source_index']!=a['source_index']+1 for a,b in zip(frames,frames[1:])),
                'tracking_lost_frames':sum(f['raw_state']=='tracking_lost' for f in genuine),
                'warming_up_frames':sum(f['raw_state']=='warming_up' for f in genuine),
                'warming_up_after_usable_state':sum(b['raw_state']=='warming_up' and a['raw_state'] in ('ok','partial_3d') for a,b in zip(frames,frames[1:])),
                'raw_state_counts':dict(collections.Counter(f['raw_state'] for f in genuine)),
                'assessment_state_counts':dict(collections.Counter(f['assessment_state'] for f in genuine)),
                'size':frames[0]['size'],'rotation':frames[0]['rotation'],'source_mirrored':frames[0]['source_mirrored'],
                'layers_present_genuine':{layer:sum(f[layer] is not None for f in genuine) for layer in LAYERS_3D},
                'raw_input_nonwrist_xy_changes':sum(any(f['raw_2d'][3*j+c]!=f['input_2d'][3*j+c] for c in (0,1)) for f in genuine for j in range(17) if j not in (9,10)),
                'sides':{}}
            for side,ids in SIDES.items():
                result={'raw_RTMPose_score':stats([score(f,side) for f in genuine]),
                        'h36m_wrist_confidence_differs_from_raw_RTMPose_frames':sum(f['confidence_h36m'] is not None and f['confidence_h36m'][ids['wrist3d']]!=score(f,side) for f in genuine),
                        'raw_score_above_one_frames':sum(score(f,side)>1 for f in genuine),
                        'raw_score_nonpositive_frames':sum(score(f,side)<=0 for f in genuine),
                        'below_existing_native_0_3_joint_score_gate_frames':sum(score(f,side)<.3 for f in genuine),
                        'assessment_wrist_point_unavailable_frames':sum(wrist_position(f,'assessment_3d',side) is None for f in genuine),
                        'assessment_invalid_wrist_frames':sum(ids['wrist3d'] in f['invalid'] for f in genuine),
                        'kinematics':{},'layer_changes':{},'joint_angles_net_not_per_stage':angle_description(genuine,side)}
                for layer in LAYERS_2D+LAYERS_3D:
                    result['kinematics'][layer],edges=distribution_kinematics(frames,layer,side)
                    if layer=='raw_3d':raw_edges=edges
                for source,target,joint in [('raw_2d','input_2d',ids['wrist2d']),('raw_2d','assessment_2d',ids['wrist2d']),('raw_3d','constrained_3d',ids['wrist3d']),('constrained_3d','adapted_3d',ids['wrist3d']),('constrained_3d','assessment_3d',ids['wrist3d'])]:
                    values=[same_frame_change(f,source,target,joint) for f in genuine];known=[(f,v) for f,v in zip(genuine,values) if v is not None];changed=[(f,v) for f,v in known if v!=0]
                    pair=source+'->'+target
                    result['layer_changes'][pair]={'paired_frames':len(known),'exactly_changed_frames':len(changed),'magnitude':stats([v for _,v in known]),
                        'magnitude_when_changed':stats([v for _,v in changed]),'RTMPose_score_changed':stats([score(f,side) for f,_ in changed]),
                        'RTMPose_score_unchanged':stats([score(f,side) for f,v in known if v==0])}
                    if source=='raw_2d':
                        result['layer_changes'][pair]['score_value_changed_frames']=sum(f[source][3*joint+2]!=f[target][3*joint+2] for f in genuine)
                        result['layer_changes'][pair]['shift_over_raw_forearm_length']=stats([v/norm(sub(point(f,'raw_2d',ids['wrist2d']),point(f,'raw_2d',ids['elbow2d']))) for f,v in changed if point(f,'raw_2d',ids['wrist2d']) is not None and point(f,'raw_2d',ids['elbow2d']) is not None and norm(sub(point(f,'raw_2d',ids['wrist2d']),point(f,'raw_2d',ids['elbow2d'])))>0])
                ordered=sorted(raw_edges,key=lambda x:x[1]['speed'],reverse=True)
                top=ordered[:max(1,math.ceil(.1*len(ordered)))]
                result['largest_speed_decile_descriptive']={'intervals':len(top),'raw_RTMPose_endpoint_mean_score':stats([(score(frames[i],side)+score(frames[i+1],side))/2 for i,_ in top]),
                    'raw_2d_endpoint_speed_px_per_second':stats([v['speed'] for i,_ in top if (v:=interval(frames[i],frames[i+1],'raw_2d',side)) is not None]),
                    'input_2d_endpoint_speed_px_per_second':stats([v['speed'] for i,_ in top if (v:=interval(frames[i],frames[i+1],'input_2d',side)) is not None])}
                result['largest_raw3d_speed_events']=[event_description(frames,i,v,side,rank+1) for rank,(i,v) in enumerate(ordered[:3])]
                for rank,(i,v) in enumerate(ordered[:3]):private.append({'exercise':exercise,'side':side,'rank':rank+1,'input_file_sha256':digest,'source_rows':[frames[i],frames[i+1]]})
                identity['sides'][side]=result
            output[exercise]=identity
    if private_evidence:Path(private_evidence).write_text(json.dumps(private,indent=2,allow_nan=False)+'\n')
    return {'native_source_commit':'1a35d3f','strict_reader_sha256':hashlib.sha256(READER.read_bytes()).hexdigest(),
            'capture_count':len(paths),'combined_input_hash_manifest_sha256':hashlib.sha256('\n'.join(sorted(hashes)).encode()).hexdigest(),
            'protocol':'descriptive-all-valid-contiguous-source-intervals; rank-top-decile-and-top3-not-error-labels',
            'acceleration':'difference of adjacent interval velocities divided by midpoint-time difference; never crosses a gap/reset/flush',
            'units':{'2d':'analysis_image_pixels (px/s, px/s^2)','3d':'explicit pelvis-relative XS model-space (units/s, units/s^2), not meter/world/contact movement'},
            'groups':output,'interpretation':'Three reused development captures. Scores are unclipped RTMPose outputs retained after hand XY substitution, not probabilities or MP location accuracy. No GT motion/occlusion/model-error separation, accuracy, form-FN, contact-movement success rate or correction benefit claim.'}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('captures',nargs='+',type=Path);parser.add_argument('--private-evidence',type=Path);args=parser.parse_args()
    print(json.dumps(analyze(args.captures,args.private_evidence),ensure_ascii=False,indent=2,allow_nan=False))
