"""Offline stateless mirror of BoneCorrectionReliability.swift. No pose modification/GT/score inputs."""
import math
import numbers
import copy
from collections.abc import Mapping
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

def finite(x):return isinstance(x,numbers.Real) and not isinstance(x,bool) and math.isfinite(x)
def length(a,b):return math.sqrt(sum((float(x)-float(y))**2 for x,y in zip(a,b)))

def evaluate(raw,segments,scale,existing_invalid):
    proposed=set();global_reasons=[];evidence=[]
    try:
        mask_shape=not isinstance(existing_invalid,(str,bytes,Mapping))
        items=list(existing_invalid) if mask_shape else []
    except (TypeError,ValueError):mask_shape=False;items=[]
    valid_old={int(i) for i in items if isinstance(i,numbers.Integral) and not isinstance(i,bool) and 0<=i<17}
    valid_mask=mask_shape and all(isinstance(i,numbers.Integral) and not isinstance(i,bool) and 0<=i<17 for i in items)
    forensic=sorted(valid_old) if valid_mask else copy.deepcopy(items if mask_shape else existing_invalid)
    try:
        pose_shape=not isinstance(raw,(str,bytes,Mapping)) and len(raw)==17 and all(not isinstance(p,(str,bytes,Mapping)) and len(p)==3 for p in raw)
    except (TypeError,ValueError):pose_shape=False
    if not pose_shape or not valid_mask:
        return dict(segments=[],existing_invalid=forensic,additional_invalid=sorted(set(range(17))-valid_old),invalid=list(range(17)),global_reasons=['unsupported_pose_or_mask_shape'])
    existing=valid_old
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
        r=segments.get(name) if isinstance(segments,Mapping) else None
        if r is None:reasons.append('unsupported_missing_segment_report')
        elif not isinstance(r,Mapping):reasons.append('unsupported_malformed_segment_report')
        else:
            if not {'observed','output','constrained','degenerate'}<=r.keys():reasons.append('unsupported_missing_report_fields')
            a=r.get('observed');b=r.get('output');target=r.get('target_cm')
            if finite(a):observed=a
            if finite(b):output=b
            if not finite(a) or a<=0:reasons.append('unsupported_report_observed')
            elif math.isfinite(n) and abs(n-a)>1e-10*(1+n):reasons.append('unsupported_inconsistent_observed')
            if not finite(b) or b<=0:reasons.append('unsupported_report_output')
            if not finite(target) or target<=0:reasons.append('unsupported_target')
            if type(r.get('degenerate')) is not bool or type(r.get('constrained')) is not bool:reasons.append('unsupported_report_state')
            if r.get('degenerate') is True:reasons.append('unsupported_report_degenerate')
            if r.get('constrained') is not True:reasons.append('unsupported_not_constrained')
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
