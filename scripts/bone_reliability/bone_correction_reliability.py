"""Offline stateless mirror of BoneCorrectionReliability.swift. No pose modification/GT/score inputs."""
import math
PARENTS=(-1,0,1,2,0,4,5,0,7,8,9,8,11,12,8,14,15)
JOINTS=('pelvis','right_hip','right_knee','right_ankle','left_hip','left_knee','left_ankle','spine','thorax','neck','head','left_shoulder','left_elbow','left_wrist','right_shoulder','right_elbow','right_wrist')
NAMES=tuple(JOINTS[PARENTS[i]]+'-'+JOINTS[i] for i in range(1,17))
SEGMENTS={NAMES[i-1] for i in (2,3,5,6,12,13,15,16)}
MAXIMUM_EXPANSION=4.
MIN_LENGTH=1e-6

def subtree(joint):
    out=set();stack=[joint]
    while stack:
        k=stack.pop();out.add(k);stack.extend(j for j,p in enumerate(PARENTS) if p==k)
    return out

def finite(x):return isinstance(x,(float,int)) and not isinstance(x,bool) and math.isfinite(x)
def length(a,b):return math.sqrt(sum((float(x)-float(y))**2 for x,y in zip(a,b)))

def evaluate(raw,segments,scale,existing_invalid):
    existing=set(existing_invalid);proposed=set();global_reasons=[];evidence=[]
    if len(raw)!=17 or any(len(p)!=3 for p in raw) or any(type(i) is not int or i not in range(17) for i in existing):
        return dict(segments=[],existing_invalid=sorted(existing),additional_invalid=sorted(set(range(17))-existing),invalid=sorted(existing|set(range(17))),global_reasons=['unsupported_pose_or_mask_shape'])
    for j,p in enumerate(raw):
        if not all(finite(x) for x in p):proposed|=subtree(j);global_reasons.append('unsupported_nonfinite_raw_joint_'+str(j))
    for child,name in enumerate(NAMES,1):
        if name not in SEGMENTS:continue
        parent=PARENTS[child]
        try:n=length(raw[child],raw[parent])
        except (ValueError,OverflowError,TypeError):n=float('nan')
        reasons=[];observed=output=correction=ratio=None
        if not math.isfinite(n):reasons.append('unsupported_nonfinite_raw_segment')
        elif n<MIN_LENGTH:reasons.append('unsupported_degenerate_raw_segment')
        if not finite(scale) or scale<=0:reasons.append('unsupported_scale')
        r=segments.get(name)
        if r is None:reasons.append('unsupported_missing_segment_report')
        else:
            a=r['observed'];b=r['output'];target=r.get('target_cm')
            if finite(a):observed=a
            if finite(b):output=b
            if not finite(a) or a<=0:reasons.append('unsupported_report_observed')
            elif math.isfinite(n) and abs(n-a)>1e-10*(1+n):reasons.append('unsupported_inconsistent_observed')
            if not finite(b) or b<=0:reasons.append('unsupported_report_output')
            if not finite(target) or target<=0:reasons.append('unsupported_target')
            if r['degenerate']:reasons.append('unsupported_report_degenerate')
            if not r['constrained']:reasons.append('unsupported_not_constrained')
            if observed is not None and output is not None:
                c=abs(output-observed)
                if math.isfinite(c):correction=c
                if observed>0:
                    q=output/observed
                    if math.isfinite(q):ratio=q
                    else:reasons.append('unsupported_expansion_overflow')
        unsupported=bool(reasons)
        if not unsupported and ratio is not None and ratio>MAXIMUM_EXPANSION:reasons.append('expansion_above_4')
        if reasons:proposed|=subtree(child)
        evidence.append(dict(name=name,parent=parent,child=child,observed=observed,output=output,absolute_length_correction=correction,expansion=ratio,status='unsupported' if unsupported else 'expansion_flagged' if reasons else 'within_candidate_bound',reasons=reasons))
    return dict(segments=evidence,existing_invalid=sorted(existing),additional_invalid=sorted(proposed-existing),invalid=sorted(existing|proposed),global_reasons=global_reasons)
