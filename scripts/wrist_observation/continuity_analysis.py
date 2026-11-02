"""Frozen half-life0.2s target-shape candidate, actual cached outputs only."""
import argparse
import collections
import importlib.util
import json
import math
from pathlib import Path
spec=importlib.util.spec_from_file_location('attribution',Path(__file__).with_name('constraint_attribution.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
a=m.a
# Exact configured angle vectors; hip_native additionally matches FormWarningTracker's shoulder-hip-knee.
METRICS={'right_knee':(2,1,2,3),'left_knee':(5,4,5,6),'right_elbow':(15,14,15,16),'left_elbow':(12,11,12,13),
 'right_hip_limit':(0,8,1,2),'left_hip_limit':(0,8,4,5),'right_shoulder':(8,0,14,15),'left_shoulder':(8,0,11,12),'spine':(7,0,7,8),
 'left_hip_native':(4,11,4,5),'right_hip_native':(1,14,1,2)}

def geometry(points):
    frame={'points':points}
    out={name:a.joint_angle(frame,'points',ids) for name,ids in METRICS.items()}
    p=lambda i:points[3*i:3*i+3]
    hips=a.sub(p(4),p(1));trunk=a.sub(p(8),p(0));up=(0,-1,0)
    forward=(hips[2],0,-hips[0]) # cross(hips,up)
    if a.norm(forward)>1e-8 and a.norm(trunk)>1e-8:
        out['torso_signed']=math.degrees(math.atan2(sum(x*y for x,y in zip(trunk,forward))/a.norm(forward),sum(x*y for x,y in zip(trunk,up))))
    else:out['torso_signed']=None
    return out

def paired_angles(raw,full,candidate):
    geos=[geometry(x) for x in (raw,full,candidate)]
    return {name:[g[name] for g in geos] for name in (*METRICS,'torso_signed')}

def analyze(paths,replay_path,receipt_path):
    replay={g['exercise']:{r['frame']:r for r in g['frames']} for g in json.loads(replay_path.read_text())}
    output={};all_errors=[]
    for path in paths:
        epochs,capped,_=a.strict.load(path);a.strict.require(not capped,'capped_capture')
        for data in epochs.values():
            a.strict.require(data['end'] is not None and not data['end']['incomplete'],'incomplete_capture')
            ex=data['start']['exercise'];fs=data['frames'];rs=replay[ex];all_errors+=m.verify_coordinates(fs,rs)
            good=[f for f in fs if not f['flush_tail'] and f['frame'] in rs]
            modes={mode:[] for mode in ('full','candidate')}
            for mode in modes:
                for f in fs:
                    g=f.copy();g['analysis_3d']=rs[f['frame']][mode] if f['frame'] in rs else None
                    modes[mode].append(g)
            out={'genuine_usable_frames':len(good),'filter_statuses':dict(collections.Counter(rs[f['frame']]['target_filter_status'] for f in good)),
                 'original_bone_source':dict(collections.Counter(rs[f['frame']]['target_source'] for f in good)),
                 'original_invalid_frame_count':sum(bool(f['invalid']) for f in good),'candidate_invalid_frame_count':sum(bool(rs[f['frame']]['candidate_invalid']) for f in good),
                 'invalid_mask_changed_frames':sum(sorted(f['invalid'])!=rs[f['frame']]['candidate_invalid'] for f in good),'sides':{},'angles':{},'original_rep_window_angles':[]}
            for side,ids in a.SIDES.items():
                layers={};edges={}
                layers['raw'],edges['raw']=a.distribution_kinematics(fs,'raw_3d',side)
                for mode in modes:layers[mode],edges[mode]=a.distribution_kinematics(modes[mode],'analysis_3d',side)
                # Match primary interval eligibility exactly across all modes, never remove a bad-looking sample.
                a.strict.require({i for i,_ in edges['raw']}=={i for i,_ in edges['full']}=={i for i,_ in edges['candidate']},'paired_interval_mismatch')
                rank_events={}
                for basis in ('full','candidate'):
                    events=[]
                    for rank,(i,value) in enumerate(sorted(edges[basis],key=lambda x:x[1]['speed'],reverse=True)[:3],1):
                        f0,f1=fs[i:i+2];r0,r1=rs[f0['frame']],rs[f1['frame']];dt=value['dt'];j=ids['wrist3d']
                        events.append({'rank':rank,'source_interval_seconds':[f0['source_pts'],f1['source_pts']],
                          'same_interval_speed':{mode:m.speed(m.relative(r0[mode],j),m.relative(r1[mode],j),dt) for mode in ('full','candidate')}|{'raw':a.interval(f0,f1,'raw_3d',side)['speed']},
                          'RTMPose_score_endpoints':[a.score(f0,side),a.score(f1,side)],
                          'input2d_displacement_px':a.interval(f0,f1,'input_2d',side)['displacement'],
                          'target_sources':[r0['target_source'],r1['target_source']],
                          'target_filter_statuses':[r0['target_filter_status'],r1['target_filter_status']]})
                    rank_events[basis]=events
                out['sides'][side]={'kinematics':layers,'ranked_events':rank_events,'candidate_minus_full_wrist_position_model_units':a.stats([a.norm(a.sub(m.relative(rs[f['frame']]['candidate'],ids['wrist3d']),m.relative(rs[f['frame']]['full'],ids['wrist3d']))) for f in good])}
            angles=[(f,paired_angles(f['raw_3d'],rs[f['frame']]['full'],rs[f['frame']]['candidate'])) for f in good]
            for name in (*METRICS,'torso_signed'):
                pairs=[v[name] for f,v in angles if all(x is not None for x in v[name])]
                out['angles'][name]={'paired_frames':len(pairs),'unavailable_frames':len(good)-len(pairs),'raw_degrees':a.stats([p[0] for p in pairs]),'full_degrees':a.stats([p[1] for p in pairs]),'candidate_degrees':a.stats([p[2] for p in pairs]),'candidate_minus_full_degrees':a.stats([p[2]-p[1] for p in pairs]),'absolute_candidate_minus_full_degrees':a.stats([abs(p[2]-p[1]) for p in pairs])}
            for rep in data['reps']:
                entries=[v for f,v in angles if rep['start_frame']<=f['frame']<=rep['end_frame']]
                count=sum(rep['start_frame']<=f['frame']<=rep['end_frame'] for f in fs)
                record={'original_rep_index':rep['rep'],'original_reported_side':rep['side'],'window_geometry_complete':len(entries)==count,'metrics':{}}
                for name in (*METRICS,'torso_signed'):
                    record['metrics'][name]={}
                    for index,mode in enumerate(('raw','full','candidate')):
                        values=[v[name][index] for v in entries]
                        record['metrics'][name][mode]=({'min':min(values),'max':max(values),'range':max(values)-min(values)} if len(values)==count and values and all(x is not None for x in values) else None)
                out['original_rep_window_angles'].append(record)
            output[ex]=out
    return {'native_source_commit':'1a35d3f','candidate_protocol_commit':'e376f90','half_life_seconds':0.2,'maximum_gap_seconds':1.0,'baseline_all_coordinates_max_absolute_error':max(all_errors),'baseline_all_coordinate_comparisons_including_flush':len(all_errors),'replay_receipt':json.loads(receipt_path.read_text()),'groups':output,'interpretation':'Engineering candidate only. Pelvis-relative model-space numerical changes; no GT/accuracy/contact-motion/form-FN or adoption claim. Complete-coordinate angle diagnostics are not native requiredOK/view/phase/reference rule replay. All original raw arrays and original boundaries retained.'}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('captures',nargs='+',type=Path);p.add_argument('--replay',type=Path,required=True);p.add_argument('--receipt',type=Path,required=True);args=p.parse_args();print(json.dumps(analyze(args.captures,args.replay,args.receipt),indent=2,allow_nan=False))
