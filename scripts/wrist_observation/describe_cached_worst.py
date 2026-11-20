"""Read already-completed predictions and final GT scores; no estimator rerun."""
import hashlib,json
from pathlib import Path
import sys
import numpy as np
root=Path.home()/'bpt-runs/target-continuity-20261102/results'
a=json.load(open(root/'aggregate.json'));assert a['complete']
r=Path.home()/'bpt-runs/motion-contact/20261020-v3-clean96';m=json.load(open(r/'manifest.json'));records=sorted([x for x in json.load(open(r/'results.json'))['records'] if x['variant']=='A' and x['split']=='heldout'],key=lambda x:x['name'])
code=Path(m['argv'][0]).parents[1];sys.path[:0]=[str(code),str(code/'scripts')]
from motion_contact.data import load_observations,load_score_reference,JOINTS
argv=m['argv'];opt=lambda k,d=None:argv[argv.index(k)+1] if k in argv else d
hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/'predictions').glob('*.npz')}
assert hashlib.sha256(json.dumps(hashes,sort_keys=True).encode()).hexdigest()==a['candidate_output_hash_manifest_sha256']
best=None
for i,record in enumerate(records):
    if record['exercise']!='squat':continue # the frozen aggregate identifies the global maximum in squat
    o=load_observations(Path(opt('--cache'))/(record['name']+'.npz'),Path(opt('--pose2d'))/(record['name']+'.npz'))
    with np.load(root/'predictions'/f'stream_{i:02d}.npz') as z:
        full=z['full'].copy();candidate=z['candidate'].copy();bi=z['full_invalid'].copy();ci=z['candidate_invalid'].copy();targets=z['original_targets'].copy();filtered=z['filtered_shapes'].copy()
    ref=load_score_reference(opt('--dataset-root',str(Path.home()/'datasets/fit3d')),o)
    errors={name:np.linalg.norm((p-p[:,:1])*ref.metres_per_crop_unit[:,None,None]-ref.joints_m,axis=-1)*1000 for name,p in [('raw',o.raw),('full',full),('candidate',candidate)]}
    d=errors['candidate'][90:]-errors['full'][90:];t,j=np.unravel_index(np.argmax(d),d.shape);t+=90;value=float(d.max())
    if best is not None and value<=best['candidate_minus_full_error_mm']:continue
    first=a['anonymous_stream_summaries'][i]['first_session_frame'];unfiltered=targets[t-21];unfiltered=unfiltered/unfiltered.sum()
    best={'exercise':record['exercise'],'joint':JOINTS[j],'source_frame_index':int(t),'source_time_seconds':float(o.timestamps[t]),'partition':'main/late','tail5':bool(t>=len(o.raw)-5),'first_session_frame':first,'frames_after_first_session':int(t-first),'errors_mm':{name:float(x[t,j]) for name,x in errors.items()},'candidate_minus_full_error_mm':value,'original_full_invalid':bool(bi[t,j]),'candidate_invalid':bool(ci[t,j]),'target_shape_source':'session','target_shape_L1_lag':float(np.abs(unfiltered-filtered[t-21]).sum()),'position_difference_full_candidate_mm':float(np.linalg.norm((candidate[t,j]-candidate[t,0])-(full[t,j]-full[t,0]))*ref.metres_per_crop_unit[t]*1000),'interpretation':'Existing-array GT-distance worsening at one joint/frame, not independent ground-truth causal posture/occlusion label. No stream/subject/camera identity exported.'}
assert abs(best['candidate_minus_full_error_mm']-a['summaries']['primary']['all']['paired']['candidate_minus_full']['max'])<1e-9
print(json.dumps(best,indent=2))
