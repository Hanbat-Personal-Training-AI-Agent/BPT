"""Score-only signed angle errors from completed cached outputs; no postprocessing rerun."""
import collections
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).parent))
from fit3d_continuity_cpu import stats

def main():
    import numpy as np
    out=Path.home()/'bpt-runs/target-continuity-20261102/results';a=json.loads((out/'aggregate.json').read_text());assert a['complete']
    r=Path.home()/'bpt-runs/motion-contact/20261020-v3-clean96';manifest=json.loads((r/'manifest.json').read_text());old=json.loads((r/'results.json').read_text())
    reference=Path(manifest['argv'][0]).resolve().parents[1];sys.path[:0]=[str(reference),str(reference/'scripts')]
    from motion_contact.data import load_observations,load_score_reference
    from motion_contact.metrics import pose_angles
    digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    hashes={p.name:digest(p) for p in sorted((out/'predictions').glob('*.npz'))}
    assert hashlib.sha256(json.dumps(hashes,sort_keys=True).encode()).hexdigest()==a['candidate_output_hash_manifest_sha256']
    argv=manifest['argv'];opt=lambda k,d=None:argv[argv.index(k)+1] if k in argv else d
    buckets={};records=sorted([r for r in old['records'] if r['variant']=='A' and r['split']=='heldout'],key=lambda r:r['name'])
    for i,record in enumerate(records):
        o=load_observations(Path(opt('--cache'))/(record['name']+'.npz'),Path(opt('--pose2d'))/(record['name']+'.npz'))
        with np.load(out/'predictions'/f'stream_{i:02d}.npz') as z:pred={'raw':o.raw,'full':z['full'].copy(),'candidate':z['candidate'].copy()}
        # Complete saved outputs exist and are verified before GT is accessed.
        ref=load_score_reference(opt('--dataset-root',str(Path.home()/'datasets/fit3d')),o)
        gt=pose_angles(ref.joints_m,ref.up_camera)
        errors={m:{k:v-gt[k] for k,v in pose_angles((p-p[:,:1])*ref.metres_per_crop_unit[:,None,None],ref.up_camera).items()} for m,p in pred.items()}
        first=a['anonymous_stream_summaries'][i]['first_session_frame'];n=len(o.raw)
        for part,(start,end) in {'primary':(90,n),'prior':(21,first or n),'early':(first or 90,90),'late':(90,n),'primary_no_tail5':(90,n-5)}.items():
            if end<=start:continue
            for exercise in ('all',o.exercise):
                bucket=buckets.setdefault((part,exercise),{m:collections.defaultdict(list) for m in pred})
                for m,values in errors.items():
                    for k,v in values.items():bucket[m][k].append(v[start:end])
    output={}
    for (part,ex),bucket in buckets.items():
        g={}
        for angle in bucket['raw']:
            values={m:np.concatenate(v[angle]) for m,v in bucket.items()}
            g[angle]={'signed_predicted_minus_GT_error_degrees':{m:stats(x) for m,x in values.items()},'paired_candidate_minus_full_absolute_error_degrees':stats(np.abs(values['candidate'])-np.abs(values['full']))}
        output.setdefault(part,{})[ex]=g
    print(json.dumps({'completed_saved_output_hash_gate':True,'postprocessing_rerun':False,'angle_definition':'Original frozen scorer unsigned interior/torso angle; signed error=predicted angle minus GT angle, not signed anatomical flexion. GT only scoring.','partitions':output},indent=2,allow_nan=False))

if __name__=='__main__':main()
