#!/usr/bin/env python3
"""Fixed15 retrospective Mac RAW geometry only. Never native assessment or fault labels."""
import argparse
from collections import Counter
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics

EXTRA=15
SIDES={'left':{'knee':(4,5,6),'hip':(11,4,5),'elbow':(11,12,13)},
       'right':{'knee':(1,2,3),'hip':(14,1,2),'elbow':(14,15,16)}}


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_csv(path):
    with Path(path).open() as f: rows=list(csv.DictReader(f))
    result={}
    for row in rows:
        index=int(row['frame'])
        if index in result:raise ValueError('duplicate processed frame')
        result[index]=row
    return result


def angle(row,prefix,joints):
    try:
        points=[[float(row[f'{prefix}{j}_{axis}']) for axis in 'xyz'] for j in joints]
        if not all(math.isfinite(v) for p in points for v in p):return None
        a,b,c=points
        u=[x-y for x,y in zip(a,b)];v=[x-y for x,y in zip(c,b)]
        nu=math.sqrt(sum(x*x for x in u));nv=math.sqrt(sum(x*x for x in v))
        if nu<=1e-6 or nv<=1e-6:return None
        # Acos roundoff guard only. Raw SimCC scores are NEVER clipped.
        cosine=max(-1.0,min(1.0,sum(x*y for x,y in zip(u,v))/(nu*nv)))
        return math.degrees(math.acos(cosine))
    except (KeyError,ValueError):return None


def distribution(values):
    return {'count':len(values),'median':statistics.median(values) if values else None,
            'min':min(values) if values else None,'max':max(values) if values else None}


def analyze(report,two,three):
    exercise=report['exercise']
    if exercise not in ('squat','pushup'):raise ValueError('unsupported exercise')
    if report.get('motion3d') is None or report.get('form_source')!='3d':raise ValueError('no actual 3D replay')
    if len(two)!=report['frames']:raise ValueError('2D/source report count mismatch')
    times={i:float(row['time']) for i,row in two.items()}
    if not all(math.isfinite(t) for t in times.values()):raise ValueError('nonfinite source PTS')
    ordered=sorted(times)
    if any(times[a]>=times[b] for a,b in zip(ordered,ordered[1:])):raise ValueError('nonmonotonic saved source PTS')
    global_guard=None
    if set(three)!=set(two) or ordered!=list(range(report['frames'])):global_guard='incomplete_full_run_frame_correspondence'
    elif report.get('lookahead')!=5 or report.get('cadence')!=1:global_guard='unverified_lift_configuration'
    elif report.get('rotate',0)!=0 or report.get('capture_rotation',0)!=0:global_guard='unverified_orientation'
    elif any(row['state']=='tracking_lost' for row in three.values()):global_guard='legacy_implicit_flush_provenance_unavailable'
    elif any(row.get('row','') not in ('','21') for row in three.values()):global_guard='unexpected_lift_output_row'
    # Row21 does NOT prove absence of clamping: frozen flush keeps row21 while
    # padding the input. With constant orientation/no tracking_lost/successful run,
    # only explicit EOF flush remains; exclude its last5 processed frames.
    tail_start=report['frames']-5
    reps=report['reps'];details=[];reasons=Counter();pooled={} 
    for index,rep in enumerate(reps):
        start,end=rep['start_frame'],rep['end_frame'];entry={'originalRepIndex':rep['rep_index'],
            'originalStart':start,'originalEnd':end,'reportedSide':rep['side'],'extraObservations':EXTRA,
            'nativeAssessmentEligible':False,'metrics':{}}
        reason=global_guard
        if reason is not None:pass
        elif type(start) is not int or type(end) is not int or start<0 or end<start:reason='invalid_original_interval'
        elif rep['side'] not in SIDES:reason='missing_observed_report_side'
        elif index+1>=len(reps):reason='last_or_open_next_rep_unknown'
        elif reps[index+1]['start_frame']<=end+EXTRA:reason='next_completed_report_start_inside_fixed_window'
        elif end+EXTRA>=tail_start:reason='known_eof_flush_tail_in_fixed_window'
        elif any(i not in times or i not in three for i in range(start,end+EXTRA+1)):reason='incomplete_observed_window'
        if reason:
            entry['withheldReason']=reason;reasons[reason]+=1;details.append(entry);continue
        entry['nextCompletedReportStart']=reps[index+1]['start_frame']
        entry['extraSpanSeconds']=times[end+EXTRA]-times[end]
        entry['futureClosureRequired']=True
        entry['observedStateCounts']=dict(Counter(three[i]['state'] for i in range(start,end+EXTRA+1)))
        for metric in (('knee','hip') if exercise=='squat' else ('elbow',)):
            for prefix,mode in [('r','raw'),('c','constrained')]:
                key=f'{mode}_{metric}'
                values=[angle(three[i],prefix,SIDES[rep['side']][metric]) for i in range(start,end+EXTRA+1)]
                if any(v is None for v in values):
                    entry['metrics'][key]={'value':None,'reason':'nonfinite_or_degenerate_chain_anywhere'}
                    pooled.setdefault(key,{'valid':[],'withheld':0})['withheld']+=1;continue
                original=values[:end-start+1];maximum=max(values)
                peak=start+values.index(maximum)
                value={'originalMaximumDegrees':max(original),'extendedMaximumDegrees':maximum,
                       'differenceDegrees':maximum-max(original),'earliestExtendedMaximumOffsetFrames':peak-end,
                       'earliestExtendedMaximumOffsetSeconds':times[peak]-times[end]}
                entry['metrics'][key]=value;pooled.setdefault(key,{'valid':[],'withheld':0})['valid'].append(value)
        details.append(entry)
    score_values=[float(v) for row in two.values() for k,v in row.items() if k.startswith('j') and k.endswith('_c')]
    finite_scores=[v for v in score_values if math.isfinite(v)]
    output={'sourceKind':'mac_pose_replay_raw_geometry_only','exercise':exercise,'extraObservations':EXTRA,
      'processed2DFrames':len(two),'stored3DFrameRows':len(three),'originalObservedReports':len(reps),
      'windowWithheldReasons':dict(reasons),'completeFutureClosedWindows':len(reps)-sum(reasons.values()),
      'wholeRun3DStates':dict(Counter(row['state'] for row in three.values())),
      'nativeAssessmentEligible':False,'constraintInvalidMaskAvailable':False,'supportCorridorAssessmentAvailable':False,
      'originalPacketIndexAvailable':False,'sourceRationalPtsAvailable':False,'savedCsvPrecisionDecimals':4,
      'observedClampedFlagAvailable':False,'row21ProvesUnclamped':False,
      'legacyFlushSafety':global_guard or 'only_explicit_eof_tail_reachable_from_frozen_source',
      'knownEofTailExcludedFrames':5,
      'rawSimccScores':{'finiteCount':len(finite_scores),'nonfiniteCount':len(score_values)-len(finite_scores),
                       'min':min(finite_scores) if finite_scores else None,'max':max(finite_scores) if finite_scores else None,
                       'outsideZeroOne':sum(not 0<=v<=1 for v in finite_scores),'clamped':False},
      'metrics':{}}
    for key,entry in pooled.items():
        rows=entry['valid'];output['metrics'][key]={'completeFiniteWindows':len(rows),'geometryWithheldWindows':entry['withheld'],
            'positiveObservedDifferenceCount':sum(r['differenceDegrees']>0 for r in rows),
            'differenceDegrees':distribution([r['differenceDegrees'] for r in rows]),
            'maxOffsetFrames':distribution([r['earliestExtendedMaximumOffsetFrames'] for r in rows]),
            'maxOffsetSeconds':distribution([r['earliestExtendedMaximumOffsetSeconds'] for r in rows])}
    output['extraSpanSeconds']=distribution([r['extraSpanSeconds'] for r in details if 'extraSpanSeconds' in r])
    return output,details


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--report',required=True);p.add_argument('--csv2d',required=True);p.add_argument('--csv3d',required=True)
    p.add_argument('--private-output',required=True);p.add_argument('--aggregate-output',required=True);args=p.parse_args()
    paths=[args.report,args.csv2d,args.csv3d];before={str(f):sha(f) for f in paths}
    report=json.loads(Path(args.report).read_text());aggregate,detail=analyze(report,read_csv(args.csv2d),read_csv(args.csv3d))
    assert all(sha(f)==value for f,value in before.items())
    aggregate['inputSha256']={'report':before[args.report],'csv2d':before[args.csv2d],'csv3d':before[args.csv3d]}
    for path,value in [(args.private_output,detail),(args.aggregate_output,aggregate)]:
        with Path(path).open('x') as f:json.dump(value,f,indent=2,allow_nan=False);f.write('\n')
    return 0


if __name__=='__main__':raise SystemExit(main())
