"""Home-local numeric-only diagnostics; exports pooled metrics, never identities/arrays.

GT is used exclusively as a scoring reference. Does not infer, rescore acceptance,
modify predictions or derive an exercise's correct-form target.
"""
import argparse
from collections import defaultdict
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import numpy as np


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(2**20), b''):
            h.update(b)
    return h.hexdigest()


def support(x, peak, high=True, tolerance=2.):
    mask = x >= x[peak]-tolerance if high else x <= x[peak]+tolerance
    lo = hi = int(peak)
    while lo > 0 and mask[lo-1]: lo -= 1
    while hi+1 < len(x) and mask[hi+1]: hi += 1
    return (hi-lo+1)/30.


def series_stats(x):
    x = np.asarray(x, float)
    if len(x) < 7 or not np.isfinite(x).all():
        raise ValueError('short/nonfinite diagnostic trace')
    hi, lo = int(np.argmax(x)), int(np.argmin(x))
    ordered = np.sort(x)
    med = np.median(np.stack([np.r_[x[0], x[:-1]], x, np.r_[x[1:], x[-1]]]), axis=0)
    out = dict(lengthFrames=len(x), rawMin=float(x.min()), rawMax=float(x.max()), rawRange=float(np.ptp(x)),
               p95=float(np.percentile(x,95)), p05=float(np.percentile(x,5)),
               p95p05Range=float(np.percentile(x,95)-np.percentile(x,5)),
               rangeDropSingleMax=float(ordered[-2]-ordered[0]), rangeDropSingleMin=float(ordered[-1]-ordered[1]),
               median3Range=float(np.ptp(med)), inset3Range=float(np.ptp(x[3:-3])),
               disjointEndRange=float(np.ptp(x[:-1])), finiteFraction=float(np.isfinite(x).mean()))
    for name, idx, high in [('max',hi,True),('min',lo,False)]:
        neighbors=np.r_[x[max(0,idx-3):idx],x[idx+1:min(len(x),idx+4)]]
        out[name+'Phase']=idx/(len(x)-1)
        out[name+'Within3FramesOfEndpoint']=int(min(idx,len(x)-1-idx)<=3)
        out[name+'Support2degSeconds']=support(x,idx,high)
        out[name+'Support10pctRangeSeconds']=support(x,idx,high,max(float(np.ptp(x))*.1,1e-9))
        out[name+'MinusNeighborMedian']=float(x[idx]-np.median(neighbors))
    return out


def compare_series(x, g):
    x,g=np.asarray(x,float),np.asarray(g,float)
    hi,lo=int(np.argmax(g)),int(np.argmin(g))
    scale=float(np.std(g))
    def rms(lag):
        a,b=(x[lag:],g[:-lag]) if lag>0 else ((x[:lag],g[-lag:]) if lag<0 else (x,g))
        return float(np.sqrt(np.mean(((a-a.mean())-(b-b.mean()))**2))/(scale+1e-9))
    candidates=range(-min(15,len(x)-7),min(15,len(x)-7)+1)
    lag=min(candidates,key=lambda q:(rms(q),abs(q)))
    return dict(ownRangeError=float(np.ptp(x)-np.ptp(g)),
                atGtExtremeSignedRange=float(x[hi]-x[lo]),
                atGtExtremeRangeError=float(x[hi]-x[lo]-np.ptp(g)),
                maxTimingAbsSeconds=abs(int(np.argmax(x))-hi)/30.,
                minTimingAbsSeconds=abs(int(np.argmin(x))-lo)/30.,
                bestLagFrames=lag, zeroLagCenteredNormalizedRms=rms(0), bestLagCenteredNormalizedRms=rms(lag))


def summarize(values):
    x=np.asarray(values,float);x=x[np.isfinite(x)]
    return dict(count=len(x),min=float(x.min()) if len(x) else None,
                median=float(np.median(x)) if len(x) else None,max=float(x.max()) if len(x) else None,
                mean=float(x.mean()) if len(x) else None)


def load_module(path):
    spec=importlib.util.spec_from_file_location('frozen_eval',path)
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    return mod


def diagnose(run, root):
    frozen=run/'code/deep_analysis/eval_gvhmr_fit3d.py'
    ev=load_module(frozen); e=ev.ev()
    rows=json.loads((run/'score_full_private.json').read_text())
    jobs=json.loads((run/'jobs.json').read_text())
    if len(rows)!=20 or len(jobs)!=20: raise ValueError('expected frozen20')
    score={(r['subject'],r['exercise'],r['cam']):r for r in rows}
    buckets=defaultdict(list);counts=defaultdict(int);hashes=[]; maxdiff=0.
    def add(prefix, data):
        for k,v in data.items(): buckets[prefix+'/'+k].append(float(v))
    for j in jobs:
        d=run/'work'/ev.tag(j); sd=root/'train'/j['subject']
        G=e.load_joints(str(sd),j['fit3d'])
        if G is None: raise ValueError('missing numeric GT')
        hashes.append(hashlib.sha256(G.tobytes(order='C')).hexdigest())
        hashes.append(sha(sd/'rep_ann.json'))
        hashes.append(sha(sd/'camera_parameters'/j['cam']/(j['fit3d']+'.json')))
        R,T,_=ev.load_cam(root,j['subject'],j['cam'],j['fit3d'])
        up=ev.world_up(R);pick=ev.pick_frames(len(G)); G=G[pick]
        P={};K=None;confidence={};tracked={}
        for v in ('B','C'):
            path=d/v/'result.npz';hashes.append(sha(path))
            with np.load(path) as z:
                P[v]=z['h36m17_cam'].astype(float);P[v+'w']=z['h36m17_world'].astype(float)
                confidence[v]=z['vitpose_coco17'][:,:,2]
                if 'tracked_mask' in z: tracked[v]=z['tracked_mask']
        for v,filename in [('A','A.npz'),('floor','floor.npz')]:
            path=d/filename
            if path.exists():
                hashes.append(sha(path))
                with np.load(path) as z:
                    P[v]=z['P'].astype(float)
                    if v=='A': K=z['K'];confidence[v]=K[:,:,2]
        n=min([len(G)]+[len(p) for p in P.values()]+([len(K)] if K is not None else []))
        G=G[:n];P={v:p[:n] for v,p in P.items()}
        side=e.near_side(K[:n]) if K is not None else j['side_gt'];other='R' if side=='L' else 'L'
        segs=[(int(np.searchsorted(pick,s)),min(int(np.searchsorted(pick,t)),n-1)) for s,t in zip(j['reps'],j['reps'][1:]) if int(np.searchsorted(pick,s))<n-1]
        ang={'GT':e.angles_3d(G,up,side)}
        ups={'GT':up}
        for v,pred in P.items():
            ups[v]=up if v=='floor' else (np.array([0,1.,0]) if v.endswith('w') else np.array([0,-1.,0]))
            ang[v]=e.angles_3d(pred,ups[v],side)
        if K is not None:ang['A2D']=e.angles_2d(K[:n],side)
        metrics={v:ev.rep_metrics(a,segs) for v,a in ang.items()}
        saved=score[(j['subject'],j['exercise'],j['cam'])]
        for v,reps in metrics.items():
            if len(reps)!=len(saved['rep_metrics'][v]):raise ValueError('rep count mismatch')
            for a,b in zip(reps,saved['rep_metrics'][v]):
                for k in a:
                    delta=abs(float(a[k])-float(b[k]));maxdiff=max(maxdiff,delta)
                    if not np.isclose(a[k],b[k],rtol=0,atol=1e-8,equal_nan=True):raise ValueError('frozen score mismatch')
                    counts['scoreValuesChecked']+=1
        counts['videosVerified']+=1
        counts['adjacentRepSharedEndpoints']+=sum(t==segs[i+1][0] for i,(s,t) in enumerate(segs[:-1]))
        if j['exercise'] in ('squat','pushup'):
            field='knee_min' if j['exercise']=='squat' else 'elbow_min'
            maxfield='knee_max' if j['exercise']=='squat' else 'elbow_max'
            for v,m in metrics.items():
                vals=np.array([q[field] for q in m]);peaks=np.array([q[maxfield] for q in m])
                add('selfRelative/'+j['exercise']+'/'+v,dict(first3Median=float(np.median(vals[:3])),allMedian=float(np.median(vals)),lateMedianMinusFirst3=float(np.median(vals[3:])-np.median(vals[:3])),
                    initialUndefinedShallowCount=min(3,len(m)),nonpositiveRunningDeficitCount=int((np.maximum.accumulate(peaks)-peaks<=0).sum()),repCount=len(m),runningPeakReferenceFirst3Fraction=float(np.mean([np.argmax(peaks[:i+1])<3 for i in range(len(peaks))]))))
        key='row_torso_swing' if j['exercise']=='barbell_row' else ('pushup_no_lockout' if j['exercise']=='pushup' else None)
        if key is None:continue
        _,fn,threshold=ev.KEYS[key]
        values={v:np.array(fn(m),float) for v,m in metrics.items()}
        near=np.isfinite(values['GT'])&(abs(values['GT']-threshold)<=ev.BOUNDARY)
        failed=np.zeros(len(segs),bool)
        for v in ('B','C'):
            wrong=near&((values['GT']>threshold)!=(values[v]>threshold));failed|=wrong
            counts[key+'/'+v+'/falsePositive']+=int((wrong&(values['GT']<=threshold)).sum())
            counts[key+'/'+v+'/falseNegative']+=int((wrong&(values['GT']>threshold)).sum())
            counts[key+'/'+v+'/nearCount']+=int(near.sum())
        trace='torso' if key.startswith('row') else 'elbow'
        joints={'GT':G,**P}
        for idx in np.flatnonzero(failed):
            counts[key+'/failedUnionCases']+=1;s,t=segs[idx];sl=slice(s,t+1)
            for v,a in ang.items():
                prefix=key+'/'+v
                add(prefix,series_stats(a[trace][sl]));add(prefix,compare_series(a[trace][sl],ang['GT'][trace][sl]))
                add(prefix,dict(frozenDecisionValue=values[v][idx],frozenMargin=values[v][idx]-threshold,
                    p95p05RangeError=float(np.percentile(a[trace][sl],95)-np.percentile(a[trace][sl],5)-(np.percentile(ang['GT'][trace][sl],95)-np.percentile(ang['GT'][trace][sl],5)))))
                if v in joints:
                    J=joints[v];opp=e.angles_3d(J,ups[v],other)['elbow']
                    alt=e.incline(J[:,11 if side=='L' else 14]-J[:,4 if side=='L' else 1],ups[v])
                    spine=e.incline(J[:,8]-J[:,0],ups[v])
                    add(prefix,dict(otherSideElbowMax=float(np.max(opp[sl])),selectedMinusOtherElbowMax=float(np.max(a['elbow'][sl])-np.max(opp[sl])),nearSideTorsoRange=float(np.ptp(alt[sl])),thoraxPelvisRange=float(np.ptp(spine[sl])),jointFiniteFraction=float(np.isfinite(J[sl]).mean())))
                    ia,ib,ic=e.H36M['elbow'][side]
                    add(prefix,dict(degenerateElbowSegments=int((np.linalg.norm(J[sl,ia]-J[sl,ib],axis=-1)<=1e-6).sum()+(np.linalg.norm(J[sl,ic]-J[sl,ib],axis=-1)<=1e-6).sum())))
                if v in confidence:
                    conf=confidence[v][sl];jointids=e.COCO['elbow'][side] if trace=='elbow' else (5,6,11,12)
                    add(prefix,dict(retainedRelevantConfidenceMean=float(np.mean(conf[:,jointids])),retainedRelevantConfidenceBelow03Fraction=float(np.mean(conf[:,jointids]<.3))))
                add(prefix,dict(trackingMaskRetained=int(v in tracked)))
                if v in tracked:add(prefix,dict(observedTrackingFraction=float(tracked[v][sl].mean())))
                if trace=='elbow':
                    peaks=np.array([q['elbow_max'] for q in metrics[v]])
                    gpeaks=np.array([q['elbow_max'] for q in metrics['GT']])
                    ri=int(np.argmax(peaks[:idx+1]));gri=int(np.argmax(gpeaks[:idx+1]));rs,rt=segs[ri]
                    sustained=[np.percentile(a[trace][ss:tt+1],95) for ss,tt in segs[:idx+1]]
                    gs,gt=segs[gri]
                    opposite=e.angles_3d(joints[v],ups[v],other)['elbow'] if v in joints else None
                    if opposite is not None:
                        otherpeaks=[np.max(opposite[ss:tt+1]) for ss,tt in segs[:idx+1]]
                        add(prefix,dict(otherSideRunningDeficit=float(max(otherpeaks)-otherpeaks[idx])))
                    add(prefix,dict(predictedDeficitUsingGtReferenceRep=float(peaks[gri]-peaks[idx]),
                        predictedMaxErrorOnGtReferenceRep=float(peaks[gri]-gpeaks[gri])))
                    add(prefix+'/atGtReferenceRep',series_stats(a[trace][gs:gt+1]))
                    add(prefix+'/atGtReferenceRep',compare_series(a[trace][gs:gt+1],ang['GT'][trace][gs:gt+1]))
                    add(prefix+'/reference',series_stats(a[trace][rs:rt+1]))
                    add(prefix,dict(referenceRepMatchesGt=int(ri==gri),referenceIsCurrent=int(ri==idx),referenceOrdinalMinusCurrent=ri-idx,runningReferenceMaxError=float(peaks[ri]-gpeaks[gri]),currentMaxError=float(peaks[idx]-gpeaks[idx]),p95RelativeDeficit=float(max(sustained)-sustained[idx])))
            camup=-R[1]/np.linalg.norm(R[1]);gtcam=e.angles_3d(G,camup,side)['torso'][sl]
            add(key+'/coordinate',dict(gtCameraUpMinusFrozenRange=float(np.ptp(gtcam)-np.ptp(ang['GT']['torso'][sl])),upAngleDegrees=float(np.degrees(np.arccos(np.clip(np.dot(up,camup),-1,1))))))
    return dict(purpose='diagnostic_only_no_acceptance_rescore',counts=dict(counts),maximumFrozenScoreReconstructionDelta=maxdiff,
                distributions={k:summarize(v) for k,v in sorted(buckets.items())},
                jobsSha256=sha(run/'jobs.json'),scoreSha256=sha(run/'score_full_private.json'),evaluatorSha256=sha(frozen),angleSourceSha256=sha(run/'code/eval_3d_angles.py'),
                numericInputCohortHash=hashlib.sha256(''.join(sorted(hashes)).encode()).hexdigest(),helperSha256=sha(__file__))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--run',type=Path,required=True);p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();result=diagnose(args.run,args.root)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(json.dumps({'counts':result['counts'],'maximumFrozenScoreReconstructionDelta':result['maximumFrozenScoreReconstructionDelta']}))
