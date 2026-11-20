"""Exact vectorized catalog geometry, without labels, gravity, phase or model access."""
import numpy as np

REQUIRED={}
APPLICABILITY={}
for side,hip,knee,ankle,shoulder,elbow,wrist in [('left',4,5,6,11,12,13),('right',1,2,3,14,15,16)]:
    for suffix,ids,exercises in [('KneeDeg',(hip,knee,ankle),('squat','pushup','barbell_row')),('HipDeg',(8,hip,knee),('squat','pushup','barbell_row')),('ElbowDeg',(shoulder,elbow,wrist),('pushup','barbell_row')),('UpperArmDeg',(0,8,11,14,shoulder,elbow),('pushup',))]:
        REQUIRED[side+suffix]=ids;APPLICABILITY[side+suffix]=exercises
REQUIRED.update(cameraTorsoSignedDeg=(0,1,4,8),cameraHipLineDeviationRatio=(0,8,3,6))
APPLICABILITY.update(cameraTorsoSignedDeg=('squat','pushup','barbell_row'),cameraHipLineDeviationRatio=('pushup',))


def unit(v):
    length=np.linalg.norm(v,axis=-1);valid=np.isfinite(v).all(-1)&np.isfinite(length)&(length>1e-8)
    with np.errstate(invalid='ignore',divide='ignore'):result=v/length[...,None]
    return result,valid


def angle(a,b):
    a,av=unit(a);b,bv=unit(b)
    value=np.degrees(np.arccos(np.clip(np.sum(a*b,axis=-1),-1,1)))
    return np.where(av&bv&np.isfinite(value),value,np.nan)


def measure(joints):
    joints=np.asarray(joints,dtype=float)
    if joints.ndim!=3 or joints.shape[1:]!=(17,3):raise ValueError('expected Nx17x3')
    out={};up=np.array([0.,-1.,0.])
    for name,ids in REQUIRED.items():
        if name.endswith(('KneeDeg','HipDeg','ElbowDeg')):
            a,b,c=ids;value=angle(joints[:,a]-joints[:,b],joints[:,c]-joints[:,b])
        elif name.endswith('UpperArmDeg'):
            _,_,_,_,shoulder,elbow=ids
            down,dv=unit(joints[:,0]-joints[:,8]);lateral,lv=unit(joints[:,11]-joints[:,14]);normal,nv=unit(np.cross(down,lateral))
            arm=joints[:,elbow]-joints[:,shoulder];projected=arm-np.sum(arm*normal,axis=-1)[:,None]*normal
            value=np.where(dv&lv&nv,angle(down,projected),np.nan)
        elif name=='cameraTorsoSignedDeg':
            forward,fv=unit(np.cross(joints[:,4]-joints[:,1],up));trunk=joints[:,8]-joints[:,0];_,tv=unit(trunk)
            value=np.where(fv&tv,np.degrees(np.arctan2(np.sum(trunk*forward,axis=-1),trunk@up)),np.nan)
        else:
            point=joints[:,0];a=joints[:,8];b=(joints[:,3]+joints[:,6])*.5;line=b-a;direction,lv=unit(line);normal=-up-direction*(direction@(-up))[:,None];normal_unit,nv=unit(normal)
            length=np.linalg.norm(line,axis=-1);nlength=np.linalg.norm(normal,axis=-1)
            with np.errstate(invalid='ignore',divide='ignore'):value=np.sum((point-a)*normal_unit,axis=-1)/length
            value=np.where(lv&nv&(nlength>=.3)&np.isfinite(value),value,np.nan)
        out[name]=value
    return out


def supported(values,confidence,invalid,threshold):
    confidence=np.asarray(confidence);invalid=np.asarray(invalid,dtype=bool)
    if confidence.shape!=invalid.shape or confidence.ndim!=2 or confidence.shape[1]!=17:raise ValueError('support Nx17 required')
    return {name:np.isfinite(value)&np.isfinite(confidence[:,ids]).all(-1)&(confidence[:,ids]>=threshold).all(-1)&(~invalid[:,ids]).all(-1) for name,value in values.items() for ids in [list(REQUIRED[name])]} 


def circular_difference(a,b):return (np.asarray(a)-np.asarray(b)+180)%360-180


def rolling_range(values,timestamps,support=None,seconds=2.,maximum_gap=.25):
    """Causal observed bracket only; no rep/phase/GT segmentation."""
    values=np.asarray(values);timestamps=np.asarray(timestamps);n=len(values);result=np.full(n,np.nan);valid=np.zeros(n,bool);start=0
    good=np.isfinite(values) if support is None else np.isfinite(values)&np.asarray(support,bool)
    unwrapped=np.full(n,np.nan)
    for i in range(n):
        if not np.isfinite(values[i]):continue
        if i and np.isfinite(unwrapped[i-1]) and np.isfinite(timestamps[i]) and np.isfinite(timestamps[i-1]) and 0<timestamps[i]-timestamps[i-1]<=maximum_gap:
            unwrapped[i]=unwrapped[i-1]+circular_difference(values[i],values[i-1])
        else:unwrapped[i]=values[i]
    for end in range(n):
        if not np.isfinite(timestamps[end]):start=end+1;continue
        if end and (not np.isfinite(timestamps[end-1]) or timestamps[end]<=timestamps[end-1] or timestamps[end]-timestamps[end-1]>maximum_gap):start=end
        while start+1<=end and timestamps[start+1]<=timestamps[end]-seconds:start+=1
        if start>end or not np.isfinite(timestamps[start]) or timestamps[end]-timestamps[start]<seconds or not good[start:end+1].all():continue
        result[end]=np.max(unwrapped[start:end+1])-np.min(unwrapped[start:end+1]);valid[end]=True
    return result,valid
