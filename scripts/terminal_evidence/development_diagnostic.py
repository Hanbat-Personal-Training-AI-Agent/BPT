"""DEVELOPMENT only: explain frozen candidate failures and observed causal peak coverage.
No warning decisions, GT, retiming, threshold search, source/model changes or inference.
"""
import argparse
import collections
import hashlib
import json
import math
import statistics
from pathlib import Path
import replay as strict


def stats(values):
    values=sorted(v for v in values if strict.finite(v))
    if not values:return {'count':0}
    return {'count':len(values),'mean':sum(values)/len(values),'min':values[0],'median':statistics.median(values),
            'p95':values[min(len(values)-1,int(.95*(len(values)-1)))],'max':values[-1]}


def metrics(original):
    return ('knee','hip') if original['exercise']=='squat' else ('elbow',)


def trustworthy(frame,original):
    return (frame.get('side')==original['side'] and frame.get('required2D') is True and frame.get('sideView') is True
            and frame.get('state') in ('ok','partial_3d') and
            all(strict.finite(frame.get('assessmentAngles',{}).get(k)) for k in metrics(original)))


def longest_top(frames):
    start=None;last=None;longest=0
    for frame in frames:
        if frame.get('phase')=='top':
            start=frame['sourceTime'] if start is None else start;last=frame['sourceTime'];longest=max(longest,last-start)
        else:start=None
    return longest


def development_span(original,frames,maximum_gap=.15):
    """Predeclared after the first frozen result. No1.5s or plateau criterion.
    Stop before actual next begin/top exit; stop at first missing support/gap/flush.
    This is observed peak coverage, never proof of correct or full extension.
    """
    anchor=next((f for f in frames if f['frame']==original['endFrame']),None)
    result={'frames':[],'stop':'missing_original_anchor','bounded':False,'seen_top':False,'supported_peak_window':False,'maxima':{},'raw_maxima':{}}
    if anchor is None or anchor.get('flushed') or not strict.finite(anchor.get('sourceTime')):return result
    previous=anchor;coordinate=anchor['coordinateKey']
    for frame in frames:
        if frame['frame']<=original['endFrame']:continue
        if not strict.finite(frame.get('sourceTime')) or frame.get('sourceIndex') is None:
            result['stop']='missing_clock';break
        if frame['sourceTime']<=previous['sourceTime'] or frame['sourceIndex']<=previous['sourceIndex']:
            result['stop']='regressing_source';break
        if frame['sourceTime']-previous['sourceTime']>maximum_gap+1e-9:
            result['stop']='source_gap';break
        if frame.get('activeRepStart') is not None and frame['activeRepStart']>original['startFrame']:
            result.update(stop='actual_next_rep_begin',bounded=True);break
        if frame.get('flushed'):
            result['stop']='lifter_flush_boundary';break
        if frame.get('coordinateKey')!=coordinate:
            result['stop']='coordinate_change';break
        if not trustworthy(frame,original):
            result['stop']='native_support_or_side_missing';break
        if frame.get('phase') not in ('top','descending','bottom','ascending'):
            result['stop']='unknown_phase';break
        # Unlike an actual next-begin event above, a phase exit must itself be
        # a known, supported, genuine observation in the same coordinate context.
        if result['seen_top'] and frame['phase']!='top':
            result.update(stop='actual_top_phase_exit',bounded=True);break
        result['seen_top']|=frame['phase']=='top';result['frames'].append(frame)
        for key in metrics(original):
            value=frame['assessmentAngles'][key];result['maxima'][key]=max(result['maxima'].get(key,value),value)
            raw=frame.get('rawAngles',{}).get(key)
            if strict.finite(raw):result['raw_maxima'][key]=max(result['raw_maxima'].get(key,raw),raw)
        previous=frame
    else:result.update(stop='recorded_set_end',bounded=True)
    result['supported_peak_window']=result['bounded'] and result['seen_top'] and bool(result['frames'])
    return result


def fixed15_pair(original,source,joint):
    frames=source['frames']
    next_starts=[rep['start_frame'] for rep in source['reps'] if rep['rep']>original['rep']]
    next_starts += [f['active_rep_start'] for f in frames if f['active_rep_start'] is not None and f['active_rep_start']>original['startFrame']]
    stop=min(next_starts,default=math.inf)
    following=[f for f in frames if original['endFrame']<f['frame']<stop and not f['flush_tail']][:15]
    old=[f for f in frames if original['startFrame']<=f['frame']<=original['endFrame']]
    if len(following)!=15 or not old:return None
    a=[strict.angle(f,'assessment_3d',original['side'],joint) for f in old]
    b=[strict.angle(f,'assessment_3d',original['side'],joint) for f in following]
    if not all(strict.finite(v) for v in a+b):return None
    return max(a),max(a+b)


def events(rows):
    records={};active=None
    for row in rows:
        kind=row['type']
        if kind=='terminal_candidate_begin':
            value=row['payload'];o=value['original'];active=(o['epoch'],o['rep'])
            records[active]={'original':o,'host':value['hostTime'],'frames':[],'trigger':None}
        elif kind=='terminal_candidate_frame' and active is not None:
            records[active]['frames'].append(row['payload']);records[active]['trigger']=row
        elif kind in ('terminal_candidate_tick','terminal_candidate_end') and active is not None:
            records[active]['trigger']=row
        elif kind=='terminal_candidate_report':
            report=row['payload'];key=(report['original']['epoch'],report['original']['rep'])
            records[key]['report']=report
            if active==key:active=None
    return records


def frozen_attribution(record,config):
    original=record['original'];report=record['report'];anchor=None;accepted=[];top=[];previous=None
    last_top=None;run_start=None;max_run=0;resets=0;joint_resets=collections.Counter();speeds=collections.defaultdict(list)
    for frame in record['frames']:
        if frame.get('setEndFlushTail'):continue
        if frame['frame']==original['endFrame']:anchor=frame;previous=frame;continue
        if frame['frame']<original['endFrame'] or anchor is None:continue
        if frame.get('activeRepStart') is not None and frame['activeRepStart']>original['startFrame']:break
        if frame['hostTime']-record['host']>=config['timeoutSeconds']:break
        if frame['sourceTime']-anchor['sourceTime']>=config['timeoutSeconds']:break
        if frame.get('flushed') or not trustworthy(frame,original):break
        if frame['phase']!='top':
            if top:break
            accepted.append(frame);previous=frame;continue
        accepted.append(frame);top.append(frame)
        angles=frame['assessmentAngles'];exceeded=[]
        if last_top is not None:
            dt=frame['sourceTime']-previous['sourceTime']
            for joint in metrics(original):
                speed=abs(angles[joint]-last_top[joint])/dt;speeds[joint].append(speed)
                if speed>config['maximumAngularSpeed']+1e-9:exceeded.append(joint)
        if last_top is None or exceeded:
            if last_top is not None:resets+=1;joint_resets.update(exceeded)
            run_start=frame['sourceTime']
        max_run=max(max_run,frame['sourceTime']-run_start);last_top=angles;previous=frame
    trigger=record['trigger'];branch=report['closure']
    if branch=='timeout' and trigger and trigger['type']=='terminal_candidate_frame':
        branch='operational_host_deadline' if trigger['payload']['hostTime']-record['host']>=config['timeoutSeconds'] else 'source_time_deadline'
    elif branch=='watchdog_timeout':branch='operational_watchdog_deadline'
    return {'accepted':accepted,'top':top,'maximum_continuous_top_seconds':longest_top(accepted),
            'maximum_stable_run_seconds':max_run,'angle_speed_resets':resets,'joint_speed_resets':joint_resets,
            'joint_speeds':speeds,'deadline_branch':branch,
            'top_samples':len(top),'reported_top_samples':report['topFrames']}


def analyze(paths):
    groups={};hashes=[]
    for path in paths:
        data,capped,digest=strict.load(path);strict.require(not capped,'development_capped_capture');hashes.append(digest)
        rows=[json.loads(line) for line in Path(path).read_text().splitlines()];records=events(rows)
        config=next(r['payload'] for r in rows if r['type']=='terminal_candidate_config')
        baseline=strict.replay(path)
        for epoch,source in data.items():
            exercise=source['start']['exercise'];group=groups.setdefault(exercise,{'captured_candidate_config':config,'original_reps':0,'candidate_reports':0,'frozen_assessments':collections.Counter(),
                'deadline_branches':collections.Counter(),'development_stops':collections.Counter(),'development_supported_peak_windows':0,
                'frozen_top_sample_counter_parity':True,'frozen_top_duration_met_captured_requirement':0,'frozen_stable_run_met_captured_requirement':0,'original_max_reconstruction_pairs':0,'original_max_maximum_abs_error':0.,
                'frozen_continuous_top_seconds':[],'frozen_maximum_stable_run_seconds':[],'development_continuous_top_seconds':[],
                'development_observed_sources':[],'angle_speed_resets':0,'joint_speed_resets':collections.Counter(),'joint_speeds':collections.defaultdict(list),
                'phase_counts_frozen':collections.Counter(),'phase_counts_development':collections.Counter(),'metrics':{},'fixed15_existing_geometry_baseline':baseline['groups']})
            strict.require(group['captured_candidate_config']==config,'mixed_candidate_configuration')
            group['original_reps']+=len(source['reps'])
            for key,record in records.items():
                if key[0]!=epoch or 'report' not in record:continue
                original=record['original'];report=record['report'];group['candidate_reports']+=1;group['frozen_assessments'][report['assessment']]+=1
                attribution=frozen_attribution(record,config)
                group['frozen_top_sample_counter_parity'] &= attribution['top_samples']==attribution['reported_top_samples']
                group['frozen_top_duration_met_captured_requirement']+=attribution['maximum_continuous_top_seconds']+1e-9>=config['stableSeconds']
                group['frozen_stable_run_met_captured_requirement']+=attribution['maximum_stable_run_seconds']+1e-9>=config['stableSeconds']
                group['deadline_branches'][attribution['deadline_branch']]+=1;group['angle_speed_resets']+=attribution['angle_speed_resets']
                group['joint_speed_resets'].update(attribution['joint_speed_resets'])
                for joint,values in attribution['joint_speeds'].items():group['joint_speeds'][joint]+=values
                group['frozen_continuous_top_seconds'].append(attribution['maximum_continuous_top_seconds']);group['frozen_maximum_stable_run_seconds'].append(attribution['maximum_stable_run_seconds'])
                group['phase_counts_frozen'].update(f['phase'] for f in attribution['accepted'])
                dev=development_span(original,source['candidate_frames'],config['maximumSourceGap'])
                group['development_stops'][dev['stop']]+=1;group['development_supported_peak_windows']+=dev['supported_peak_window']
                group['development_continuous_top_seconds'].append(longest_top(dev['frames']));group['development_observed_sources'].append(len(dev['frames']))
                group['phase_counts_development'].update(f['phase'] for f in dev['frames'])
                for joint in metrics(original):
                    metric=group['metrics'].setdefault(joint,{'original_native_max':[],'development_observed_max':[],'development_supported_peak_max':[],'fixed15_paired_original_max':[],'fixed15_paired_extended_max':[],'fixed15_paired_delta':[],'development_peak_in_fixed15_subset':[]})
                    paired=fixed15_pair(original,source,joint)
                    if paired is not None:
                        metric['fixed15_paired_original_max'].append(paired[0]);metric['fixed15_paired_extended_max'].append(paired[1]);metric['fixed15_paired_delta'].append(paired[1]-paired[0])
                        if joint in dev['maxima']:metric['development_peak_in_fixed15_subset'].append(dev['maxima'][joint])
                    observed=original['originalMaxima'].get(joint)
                    if strict.finite(observed):
                        metric['original_native_max'].append(observed)
                        original_values=[strict.angle(f,'assessment_3d',original['side'],joint) for f in source['frames'] if original['startFrame']<=f['frame']<=original['endFrame']]
                        finite=[v for v in original_values if strict.finite(v)]
                        if finite:
                            group['original_max_reconstruction_pairs']+=1;group['original_max_maximum_abs_error']=max(group['original_max_maximum_abs_error'],abs(max(finite)-observed))
                    if joint in dev['maxima']:
                        metric['development_observed_max'].append(dev['maxima'][joint])
                        if dev['supported_peak_window']:metric['development_supported_peak_max'].append(dev['maxima'][joint])
    for group in groups.values():
        for key in ('frozen_continuous_top_seconds','frozen_maximum_stable_run_seconds','development_continuous_top_seconds','development_observed_sources'):group[key]=stats(group[key])
        group['joint_speeds']={k:stats(v) for k,v in group['joint_speeds'].items()}
        group['metrics']={k:{name:stats(values) for name,values in metric.items()} for k,metric in group['metrics'].items()}
    return {'protocol':'DEVELOPMENT-predeclared-after-first-frozen-squat-no-production-change','capture_count':len(paths),
        'combined_input_hash_manifest_sha256':hashlib.sha256('\n'.join(sorted(hashes)).encode()).hexdigest(),'groups':groups,
        'interpretation':'Frozen candidate outcomes unchanged. Development peak is observed same-side/native-support geometry through causal boundaries, not full extension/correct form/accuracy or a tuned replacement. Existing fixed15 baseline is geometry-only with different eligibility denominators. No GT or new inference.'}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('captures',nargs='+',type=Path);args=parser.parse_args()
    print(json.dumps(analyze(args.captures),indent=2,ensure_ascii=False,allow_nan=False))
