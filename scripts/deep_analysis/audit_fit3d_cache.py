import argparse, json, hashlib, pathlib, cv2, numpy as np
parser = argparse.ArgumentParser()
parser.add_argument("--out", type=pathlib.Path)
args = parser.parse_args()
h=pathlib.Path.home(); run=h/'bpt-runs/gvhmr-eval-20261026'; jobs=json.loads((run/'jobs.json').read_text()); rows=[]
def sha(p):
 d=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):d.update(b)
 return d.hexdigest()
for j in jobs:
 tag=f"{j['subject']}_{j['exercise']}_{j['cam']}"; base=h/'datasets/fit3d/train'/j['subject']; video=base/'videos'/j['cam']/(j['fit3d']+'.mp4')
 cap=cv2.VideoCapture(str(video)); n=int(cap.get(cv2.CAP_PROP_FRAME_COUNT));fps=cap.get(cv2.CAP_PROP_FPS);cap.release()
 pick=np.round(np.arange(0,n,50/30)).astype(int);pick=pick[pick<n]
 row={'tag':tag,'inputSha256':sha(video),'fps':fps,'sourceFrames':n,'expectedFrames':len(pick),'cached':{}}
 for v in ['B','C']:
  p=run/'work'/tag/v/'result.npz'
  if not p.exists():continue
  with np.load(p,allow_pickle=False) as z:
   m=json.loads(str(z['meta']));checks={'frames':len(z['h36m17_cam'])==len(pick),'fps':m['fps']==30,'sourceFPS':m['src_fps']==50,'gvhmrCommit':m['gvhmr_commit']=='ee960bb','half':m['half'] is True,'intrinsics':m['f_mm']==(None if v=='B' else j['f_mm']),'noCalibrationBeta':m.get('body_shape','gvhmr')=='gvhmr','finite':all(np.isfinite(z[k]).all() for k in z.files if z[k].dtype.kind in 'fc')}
  row['cached'][v]={'checks':checks,'sha256':sha(p),'reuseEligible':all(checks.values())}
 row['inputHashes']={name:sha(p) for name,p in {'camera':base/'camera_parameters'/j['cam']/(j['fit3d']+'.json'),'reps':base/'rep_ann.json','joints':base/'joints3d_25'/(j['fit3d']+'.json')}.items() if p.exists()}
 if j['replay']:
  row['inputHashes']['replay']=sha(j['replay'])
  import csv
  with open(j['replay']) as f: replay=list(csv.DictReader(f))
  ids=np.array([int(r['frame']) for r in replay]); times=np.array([float(r['time']) for r in replay])
  row['replayChecks']={'length':len(ids)==n,'consecutiveFrameIds':bool(np.all(np.diff(ids)==1)), 'timeMonotonic':bool(np.all(np.diff(times)>0))}
  ap=run/'work'/tag/'A.npz'
  if ap.exists():
   with np.load(ap,allow_pickle=False) as az:
    row['replayChecks'].update(AFrames=len(az['P'])==len(pick),finite=bool(np.isfinite(az['P']).all() and np.isfinite(az['K']).all()))
 rows.append(row)
manifest={'historicalInputHashAvailable':False,'sourceCommit':'54cd739452a7d18d7fdda27efff99356b752f8a8','rows':rows,'codeHashes':{str(p.relative_to(run)):sha(p) for p in (run/'code').rglob('*.py')}}
(args.out or run/'cache_audit_private.json').write_text(json.dumps(manifest,indent=2))
print(json.dumps({'jobs':len(rows),'cachedOutputs':sum(len(r['cached']) for r in rows),'allChecksPass':all(v['reuseEligible'] for r in rows for v in r['cached'].values()),'replayChecksPass':all(all(r.get('replayChecks',{}).values()) for r in rows),'historicalInputHashAvailable':False}))
