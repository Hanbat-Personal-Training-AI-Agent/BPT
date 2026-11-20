"""Home-only CPU check: regenerate cached joints from predicted SMPL-X, never GT inputs."""
import sys,json,pathlib,numpy as np,torch
h=pathlib.Path.home();r=h/'bpt-runs/gvhmr-eval-20261026'
sys.path.insert(0,str(r/'code/deep_analysis'))
import gvhmr_runner as g
g._imports()
model=g.H36M(device='cpu'); worst=0.;count=0
for d in sorted((h/'gvhmr/fit3d/work').iterdir()):
 for variant in ['B','C']:
  p=d/variant/'result.npz'
  if not p.exists():continue
  with np.load(p,allow_pickle=False) as z:
   n=len(z['h36m17_world']);pick=np.unique([0,n//2,n-1])
   for coord,field in [('incam','h36m17_cam'),('global','h36m17_world')]:
    params={k:torch.from_numpy(z[f'smplx_{coord}_{k}'][pick]) for k in ['global_orient','body_pose','betas','transl']}
    regenerated=model(params,batch=3)
    worst=max(worst,float(np.max(np.abs(regenerated-z[field][pick]))));count+=1
result={'coordinateChecks':count,'framesPerCheck':3,'maxAbsoluteDifferenceMeters':worst,'toleranceMeters':1e-4,'passed':worst<=1e-4,'device':'cpu','inputs':'saved_predicted_smplx_parameters_no_gt'}
(r/'postprocess_parity_aggregate.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
