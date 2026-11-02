"""Numerical/discrete synthetic native Swift gate; abort before real-data scoring."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).parent))
from bone_target_continuity import BoneTargetContinuity

def check(fixture,reference):
    import numpy as np
    sys.path[:0]=[str(reference),str(reference/'scripts')]
    from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints
    data=json.loads(fixture.read_text());f=BoneTargetContinuity();max_shape=0.;max_coordinate=0.;coordinates=0;rows_count=0;invalid_rows=0
    def shape_error(a,b):
        if a is None or b is None:assert a is b;return 0.
        assert a.keys()==b.keys();return max(abs(a[k]-b[k]) for k in a)
    for r in data['filter_cases']:
        o=f.update(r['targets'],r['time'],r['source'],r['epoch'],r['tracking'])
        assert o['status']==r['status'];assert o['source']==r['source']
        max_shape=max(max_shape,shape_error(o['original_shape'],r['original_shape']),shape_error(o['filtered_shape'],r['filtered_shape']))
        assert o['alpha'] is None if r['alpha'] is None else abs(o['alpha']-r['alpha'])<=1e-10
    for group in data['groups']:
        full=Pose3DConstraints(reflect_flipped_knee=group['exercise']=='squat');candidate=Pose3DConstraints(reflect_flipped_knee=group['exercise']=='squat');f=BoneTargetContinuity();epoch='A'
        for r in group['rows']:
            if r.get('tracking') is False:f.reset();continue
            if epoch!=r['epoch']:
                full=Pose3DConstraints(reflect_flipped_knee=group['exercise']=='squat');candidate=Pose3DConstraints(reflect_flipped_knee=group['exercise']=='squat');epoch=r['epoch']
            targets=full.session_targets() or full.prior_lengths;source='session' if full.session_targets() else 'prior'
            max_shape=max(max_shape,shape_error(targets,r['targets']));assert source==r['source']
            o=f.update(targets,r['time'],source,epoch);assert o['status']==r['status']
            max_shape=max(max_shape,shape_error(o['filtered_shape'],r['filtered_shape']))
            candidate.calibration_targets_cm=o['filtered_shape']
            raw=np.asarray(r['raw']).reshape(17,3);b,br=full.apply(raw);c,cr=candidate.apply(raw)
            assert br['invalid_joints']==r['full_invalid'] and cr['invalid_joints']==r['candidate_invalid']
            invalid_rows+=bool(br['invalid_joints'])
            for value,key in [(b,'full'),(c,'candidate')]:
                error=float(np.max(np.abs(value.ravel()-r[key])));assert np.isfinite(error) and error<=1e-10
                max_coordinate=max(max_coordinate,error);coordinates+=value.size
            rows_count+=1
    assert max_shape<=1e-10 and invalid_rows>0,dict(max_shape=max_shape,invalid_rows=invalid_rows,max_coordinate=max_coordinate)
    return dict(passed=True,synthetic_only=True,coordinate_components=coordinates,rows=rows_count,filter_cases=len(data['filter_cases']),invalid_full_rows=invalid_rows,max_coordinate_error=max_coordinate,max_target_or_shape_error=max_shape,tolerance=1e-10,fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest())

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('fixture',type=Path);p.add_argument('--reference',type=Path,required=True);args=p.parse_args();print(json.dumps(check(args.fixture,args.reference),indent=2))
