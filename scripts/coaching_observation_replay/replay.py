"""Strict original-native observation evidence export. No profile approval, inference or pose changes."""
import argparse,collections,fcntl,hashlib,importlib.util,json,math,re,shutil,statistics,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
s=importlib.util.spec_from_file_location('strict_reader',ROOT/'scripts/terminal_evidence/replay.py');strict=importlib.util.module_from_spec(s);s.loader.exec_module(strict)
SIDES={'left':(4,5,6,11,12,13),'right':(1,2,3,14,15,16)}
NAMES={'pushUp':'pushup','barbellRow':'barbell_row'}

def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def extract(text,name):
    start=text.index('    static func '+name+'(');brace=text.index('{',start);depth=1;i=brace+1
    while depth:
        if text[i]=='{':depth+=1
        elif text[i]=='}':depth-=1
        i+=1
    return text[start:i]
def stats(v):
    v=sorted(x for x in v if strict.finite(x))
    if not v:return {'count':0}
    q=lambda p: v[int((len(v)-1)*p)]*(1-((len(v)-1)*p%1))+v[min(int((len(v)-1)*p)+1,len(v)-1)]*((len(v)-1)*p%1)
    return dict(count=len(v),min=v[0],median=statistics.median(v),mean=sum(v)/len(v),p95=q(.95),max=v[-1])
def require_native_output_hash(folder,receipt):
    expected=receipt.get('native_output_sha256')
    if not expected:raise ValueError('missing_native_output_hash')
    if digest(folder/'native_outputs.json')!=expected:raise ValueError('native_output_hash_mismatch')

def available(m):return m.get('value') is not None and not m.get('reasons',[])
def wrap(d):
    r=math.remainder(d,360);return 180 if r==-180 else r
def unwrap(values):
    out=[]
    for v in values:out.append(out[-1]+wrap(v-out[-1]) if out else v)
    return out

def interval_reasons(a,b):
    r=[]
    if a['flush_tail'] or b['flush_tail']:r.append('flush_tail')
    if b['frame']!=a['frame']+1 or b['source_index']!=a['source_index']+1:r.append('noncontiguous_source')
    dt=b['source_pts']-a['source_pts']
    if not strict.finite(dt) or dt<=0:r.append('invalid_source_dt')
    elif dt>.25:r.append('existing_max_gap_exceeded')
    for k in ('phase','side','side_view'):
        if a[k] is None or b[k] is None:r.append('unknown_'+k)
        elif a[k]!=b[k]:r.append(k+'_changed')
    if a['phase'] not in ('top','bottom','ascending','descending','pulling','lowering','rising'):r.append('unknown_phase_definition')
    if any(f['assessment_state'] not in ('ok','partial_3d') for f in (a,b)):r.append('unusable_3d')
    return sorted(set(r))

def strict_range(frames,metrics,key,side):
    reasons=[]
    if not frames:return {'available':False,'value':None,'reasons':['missing_window']}
    if any(f['flush_tail'] for f in frames):reasons.append('flush_tail')
    if any(not available(metrics[f['frame']][key]) for f in frames):reasons.append('incomplete_metric_support')
    if any(b['source_index']!=a['source_index']+1 or b['frame']!=a['frame']+1 for a,b in zip(frames,frames[1:])):reasons.append('noncontiguous_source')
    if any(f['side']!=side for f in frames):reasons.append('original_report_side_not_stable')
    if any(f['side_view'] is None for f in frames) or len({f['side_view'] for f in frames})!=1:reasons.append('view_unknown_or_changed')
    if any(f['phase'] is None for f in frames):reasons.append('unknown_phase')
    values=[metrics[f['frame']][key].get('value') for f in frames];raw=[metrics[f['frame']][key].get('rawValue') for f in frames]
    if reasons:return {'available':False,'value':None,'rawValue':None,'reasons':sorted(set(reasons)),'member_frames':len(frames)}
    if key=='cameraTorsoSignedDeg':values=unwrap(values);raw=unwrap(raw)
    return {'available':True,'value':max(values)-min(values),'rawValue':max(raw)-min(raw),'reasons':[],'member_frames':len(frames),'scope':'original_inclusive_report_window_range_not_physical_rep_completion'}

def build_catalog(source_sha,form_sha):
    result={}
    for side,(hip,knee,ankle,shoulder,elbow,wrist) in SIDES.items():
        for suffix,ids in [('KneeDeg',[hip,knee,ankle]),('ElbowDeg',[shoulder,elbow,wrist]),('HipDeg',[hip,knee,8]),('UpperArmDeg',[0,8,11,14,shoulder,elbow])]:
            key=side+suffix;result[key]={'definitionId':'ExperimentalCoaching.'+suffix,'unit':'degrees','coordinateSpace':'XS_H36M17_model_space_body_relative','scope':'projected_body_frontal_abduction_from_caudal_axis' if suffix=='UpperArmDeg' else 'frame_geometry_not_approved_form','requiredJoints':ids,'sourceDefinitionSha256':source_sha}
    result['trunkInclineDeg']={'definitionId':'ExperimentalCoaching.trunkInclineDeg','unit':'degrees','coordinateSpace':'source_synchronized_up_required','scope':'gravity_referenced_geometry','requiredJoints':[0,8],'sourceDefinitionSha256':source_sha}
    for key,fn,unit,ids in [('cameraTorsoSignedDeg','signedTorsoAngle3D','degrees',[0,1,4,8]),('cameraHipLineDeviationRatio','signedHipDeviation3D','dimensionless_ratio',[0,8,3,6])]:result[key]={'definitionId':'FormGeometry.'+fn+'(up=(0,-1,0))','unit':unit,'coordinateSpace':'XS_H36M17_camera_reference_no_verified_ground','scope':'camera_reference_proxy','requiredJoints':ids,'sourceDefinitionSha256':form_sha}
    return result

def run(paths,scratch,reuse_native=None):
    assert not scratch.resolve().is_relative_to(ROOT);scratch.mkdir(parents=True,exist_ok=False)
    engine=ROOT/'ios/Runner/NativePose/Evaluators/ExperimentalCoaching.swift';form=ROOT/'ios/Runner/NativePose/Evaluators/FormWarnings.swift';text=form.read_text()
    names=['signedTorsoAngle3D','signedHipDeviation3D','signedLineDeviation3D','wrapDegrees','unwrapDegrees'];methods={name:extract(text,name) for name in names}
    confidence=re.search(r'var minJointConfidence = ([0-9.]+)',text).group(1)
    source='import Foundation\nimport simd\nenum SourceGeometry {\nstatic let up3D = SIMD3<Double>(0,-1,0)\nstatic let min2DConfidence = '+confidence+'\n'+'\n'.join(methods.values())+'\n}\n'
    (scratch/'SourceGeometry.swift').write_text(source);(scratch/'main.swift').write_bytes(Path(__file__).with_name('observation.swift').read_bytes())
    groups=[];private=[];input_hashes=[]
    for path in paths:
        epochs,capped,d=strict.load(path);assert not capped;input_hashes.append(d)
        for epoch,data in epochs.items():
            assert data['end'] and not data['end']['incomplete'];ex=NAMES.get(data['start']['exercise'],data['start']['exercise']);assert ex in ('squat','pushup','barbell_row')
            groups.append({'exercise':ex,'frames':data['frames']});private.append((epoch,ex,data))
    (scratch/'input.json').write_text(json.dumps(groups,allow_nan=False));input_before=digest(scratch/'input.json')
    if reuse_native is None:
        with open('/tmp/bpt-heavy.lock','a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            subprocess.run(['swiftc','-O',str(engine),str(scratch/'SourceGeometry.swift'),str(scratch/'main.swift'),'-o',str(scratch/'observe')],check=True)
            subprocess.run([str(scratch/'observe'),'--self-test'],check=True,stdout=(scratch/'self-test.txt').open('w'))
            subprocess.run([str(scratch/'observe'),str(scratch/'input.json'),str(scratch/'native_outputs.json')],check=True)
    else:
        prior=json.loads((reuse_native/'receipt.json').read_text());require_native_output_hash(reuse_native,prior)
        assert digest(engine)==prior['ExperimentalCoaching_sha256'] and digest(form)==prior['FormWarnings_sha256']
        assert digest(scratch/'SourceGeometry.swift')==prior['compiled_extraction_sha256']
        assert digest(Path(__file__).with_name('observation.swift'))==prior['adapter_sha256']
        assert input_before==digest(reuse_native/'input.json')
        shutil.copyfile(reuse_native/'native_outputs.json',scratch/'native_outputs.json');shutil.copyfile(reuse_native/'self-test.txt',scratch/'self-test.txt')
    assert input_before==digest(scratch/'input.json')
    out=json.loads((scratch/'native_outputs.json').read_text());catalog=build_catalog(digest(engine),digest(form));summary={};evidence=[]
    for (epoch,ex,data),group in zip(private,out):
        assert ex==group['exercise'];rows={r['frame']:r for r in group['rows']};fs=data['frames'];metrics={f['frame']:rows[f['frame']]['metrics'] for f in fs}
        for f in fs:
            for k,m in metrics[f['frame']].items():
                m.setdefault('value',None);m.setdefault('rawValue',None);m['available']=available(m);m.update(catalog[k]);m.setdefault('qualifiers',[])
            evidence.append({'schema':'coaching_observation_evidence.v1','source':{k:f[k] for k in ('frame','source_index','source_pts','source_time_value','source_time_scale','time_basis') }|{'epoch':epoch},'context':{k:f[k] for k in ('phase','side','side_view','source_kind','rotation','source_mirrored','flush_tail')}|{'exercise':ex,'gravitySynchronized':False,'rawLayer':'raw_3d','correctedLayer':'assessment_3d'},'metrics':metrics[f['frame']],'candidates':rows[f['frame']]['candidates'],'profile':None})
        good=[f for f in fs if not f['flush_tail']];metric_summary={}
        for k in catalog:
            ms=[metrics[f['frame']][k] for f in good];a=[m for m in ms if m['available']];pair=[m for m in ms if m['value'] is not None and m['rawValue'] is not None]
            metric_summary[k]={'available_frames':len(a),'withheld_frames':len(ms)-len(a),'reasons':dict(collections.Counter(r for m in ms for r in m['reasons'])),'available_corrected_values':stats([m['value'] for m in a]),'numeric_withheld_values':stats([m['value'] for m in ms if not m['available'] and m['value'] is not None]),'raw_minus_corrected_absolute_difference':stats([abs(m['rawValue']-m['value']) for m in pair]),'definition':catalog[k]}
        intervals=[]
        for f0,f1 in zip(fs,fs[1:]):
            base=interval_reasons(f0,f1);dt=f1['source_pts']-f0['source_pts'];record={'source_frames':[f0['frame'],f1['frame']],'source_interval_seconds':[f0['source_pts'],f1['source_pts']],'phase':f1['phase'],'context_reasons':base,'metrics':{}}
            for side in SIDES:
                for joint in ('Knee','Elbow'):
                    key=side+joint+'Deg';mm=[metrics[f['frame']][key] for f in (f0,f1)];reasons=base+([] if all(m['available'] for m in mm) else ['incomplete_'+key])
                    numeric_ok=dt>0 and not f0['flush_tail'] and not f1['flush_tail'] and all(m.get('value') is not None and m.get('rawValue') is not None for m in mm)
                    record['metrics'][side+joint+'RateDegPerSecond']={'value':(mm[1]['value']-mm[0]['value'])/dt if numeric_ok else None,'rawValue':(mm[1]['rawValue']-mm[0]['rawValue'])/dt if numeric_ok else None,'available':not reasons,'reasons':reasons,'scope':'adjacent_interval_change_not_approved_phase_baseline'}
                for part in ('hip','shoulder'):
                    mm=[rows[f['frame']]['image_samples'].get(side,{}) for f in (f0,f1)];reasons=base+([] if all(m.get('available') for m in mm) else ['incomplete_2d_support'])
                    if f1['side_view'] is not True:reasons+=['side_view_required_for_image_timing']
                    raw_id={'left':{'hip':11,'shoulder':5},'right':{'hip':12,'shoulder':6}}[side][part]
                    raw_ok=all(f['raw_2d'][3*raw_id+2]>=.30 for f in (f0,f1))
                    numeric_ok=dt>0 and not f0['flush_tail'] and not f1['flush_tail'] and all(m.get('available') for m in mm)
                    key=side+part.title()+'RisePxPerSecond';record['metrics'][key]={'qualifiers':['endpoint_rate_not_criterion_eligible'] if reasons else [],'rawValue':-(f1['raw_2d'][3*raw_id+1]-f0['raw_2d'][3*raw_id+1])/dt if numeric_ok and raw_ok else None,'value':-(mm[1][part+'Y']-mm[0][part+'Y'])/dt if numeric_ok else None,'available':not reasons,'reasons':sorted(set(reasons)),'scope':'image_plane_y_change_not_absolute_3d_height'}
            intervals.append(record)
        relevant=[r for r in intervals if r['phase']==('pulling' if ex=='barbell_row' else 'ascending')]
        interval_summary={k:{'available_intervals':sum(r['metrics'][k]['available'] for r in relevant),'total_phase_intervals':len(relevant),'reasons':dict(collections.Counter(reason for r in relevant for reason in r['metrics'][k]['reasons'])),'values':stats([r['metrics'][k]['value'] for r in relevant if r['metrics'][k]['available']]),'numeric_withheld_values':stats([r['metrics'][k]['value'] for r in relevant if not r['metrics'][k]['available'] and r['metrics'][k]['value'] is not None])} for k in intervals[0]['metrics']} if intervals else {}
        reps=[]
        for rep in data['reps']:
            members=[f for f in fs if rep['start_frame']<=f['frame']<=rep['end_frame']]
            timing={}
            if ex=='squat':
                internal=[r for r in intervals if rep['start_frame']<=r['source_frames'][0] and r['source_frames'][1]<=rep['end_frame'] and r['phase']=='ascending' and next(f['phase'] for f in fs if f['frame']==r['source_frames'][0])=='ascending']
                side=rep['side'];keys=[side+'HipRisePxPerSecond',side+'ShoulderRisePxPerSecond']
                ok=bool(internal) and all(r['metrics'][key]['available'] for r in internal for key in keys)
                if ok:
                    peaks=[max(internal,key=lambda r:r['metrics'][key]['value']) for key in keys]
                    times=[sum(r['source_interval_seconds'])/2 for r in peaks]
                    timing={'available':True,'hip_peak_source_time':times[0],'shoulder_peak_source_time':times[1],'hip_minus_shoulder_peak_seconds':times[0]-times[1],'interval_count':len(internal),'scope':'observed_image_rise_peak_timing_not_hips_first_fault'}
                else:
                    timing={'available':False,'reasons':sorted(set(reason for r in internal for key in keys for reason in r['metrics'][key]['reasons'])) or ['missing_same_phase_intervals'],'interval_count':len(internal)}
                    if internal and all(r['metrics'][key]['value'] is not None for r in internal for key in keys):
                        peaks=[max(internal,key=lambda r:r['metrics'][key]['value']) for key in keys];times=[sum(r['source_interval_seconds'])/2 for r in peaks]
                        timing['unqualified_image_peak_delta_seconds']=times[0]-times[1];timing['unqualified_scope']='image_plane_numeric_observation_not_hips_first_fault_or_criterion_eligible'
            reps.append({'hip_shoulder_timing':timing,'original_rep_index':rep['rep'],'original_side':rep['side'],'original_start_frame':rep['start_frame'],'original_end_frame':rep['end_frame'],'boundary_semantics':'inclusive_native_report','original_start_phase':members[0]['phase'],'original_end_phase':members[-1]['phase'],'physical_completion':'not_established_by_report_boundary','camera_torso_range':strict_range(members,metrics,'cameraTorsoSignedDeg',rep['side'])})
        row_rates={}
        if ex=='barbell_row':
            keys=['leftKneeRateDegPerSecond','rightKneeRateDegPerSecond','leftElbowRateDegPerSecond','rightElbowRateDegPerSecond']
            eligible=[r for r in relevant if all(r['metrics'][k]['available'] for k in keys)]
            row_rates={'total_pulling_intervals':len(relevant),'simultaneously_available_intervals':len(eligible),'raw_direction_pattern_intervals':sum(all(r['metrics'][k]['rawValue']>0 for k in keys[:2]) and all(r['metrics'][k]['rawValue']<0 for k in keys[2:]) for r in eligible),'corrected_direction_pattern_intervals':sum(all(r['metrics'][k]['value']>0 for k in keys[:2]) and all(r['metrics'][k]['value']<0 for k in keys[2:]) for r in eligible),'scope':'coincident_signed_angular_change_only_not_leg_drive_force_or_approved_profile'}
        candidates=collections.Counter(c['assessment'] for f in good for c in rows[f['frame']]['candidates']);candidate_reasons=collections.Counter(reason for f in good for c in rows[f['frame']]['candidates'] for reason in c['reasons'])
        assert not any(rows[f['frame']]['candidates'] and any(c['assessment']!='withheld' for c in rows[f['frame']]['candidates']) for f in fs)
        summary[ex]={'genuine_frames':len(good),'flush_excluded':len(fs)-len(good),'phase_counts':dict(collections.Counter(f['phase'] for f in good)),'side_view_counts':dict(collections.Counter(str(f['side_view']) for f in good)),'metric_summary':metric_summary,'native_candidate_assessments':dict(candidates),'native_candidate_reasons':dict(candidate_reasons),'squat_candidate_not_implemented':ex=='squat','interval_summary':interval_summary,'row_simultaneous_motion':row_rates,'rep_windows':reps}
        (scratch/(ex+'_intervals.json')).write_text(json.dumps(intervals,indent=2,allow_nan=False))
    (scratch/'evidence.jsonl').write_text('\n'.join(json.dumps(r,allow_nan=False) for r in evidence)+'\n');(scratch/'catalog.json').write_text(json.dumps(catalog,indent=2))
    proof={'ExperimentalCoaching_sha256':digest(engine),'FormWarnings_sha256':digest(form),'extracted_function_sha256':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in methods.items()},'compiled_extraction_sha256':digest(scratch/'SourceGeometry.swift'),'adapter_sha256':digest(Path(__file__).with_name('observation.swift')),'reader_sha256':digest(ROOT/'scripts/terminal_evidence/replay.py'),'combined_input_hash_manifest_sha256':hashlib.sha256('\n'.join(sorted(input_hashes)).encode()).hexdigest(),'original_input_arrays_file_unchanged':input_before==digest(scratch/'input.json'),'profile':None,'native_outputs_reused_with_exact_source_and_input_hashes':reuse_native is not None,'native_output_sha256':digest(scratch/'native_outputs.json'),'native_synthetic_test':(scratch/'self-test.txt').read_text().strip()}
    (scratch/'receipt.json').write_text(json.dumps(proof,indent=2))
    return {'schema':'coaching_observation_aggregate.v1','profile':None,'proof':proof,'groups':summary,'interpretation':'Observed metrics with support/scope retained. No approved profile or normal-form/force/lumbar/GT accuracy claim; all native candidates withheld, no squat candidate implementation.'}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('captures',nargs='+',type=Path);p.add_argument('--scratch',type=Path,required=True);p.add_argument('--reuse-native',type=Path);args=p.parse_args();print(json.dumps(run(args.captures,args.scratch,args.reuse_native),indent=2,allow_nan=False))
