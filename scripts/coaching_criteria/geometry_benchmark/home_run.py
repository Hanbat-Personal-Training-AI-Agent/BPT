"""Home CPU-only score of existing saved outputs. No inference, GT feedback, phase or target fitting."""
from pathlib import Path
import collections,hashlib,json,os,sys,time
import numpy as np
from metrics import measure,supported,rolling_range,circular_difference,APPLICABILITY

sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def stats(values):
 a=np.concatenate(values) if values else np.empty(0);a=a[np.isfinite(a)]
 return {'n':int(a.size),'mean':float(a.mean()),'median':float(np.median(a)),'p95':float(np.percentile(a,95)),'max':float(a.max()),'min':float(a.min())} if len(a) else {'n':0}
def probes(name):
 if name=='cameraHipLineDeviationRatio':return [('camera_sag_transfer_gt_0.14','gt',.14),('camera_pike_transfer_lt_minus0.08','lt',-.08)]
 if name=='cameraTorsoCausalRangeDeg':return [('phase_free_camera_range_transfer_gt39.9','gt',39.9)]
 if name.endswith('UpperArmDeg'):return [('generic_geometry_gt90_NOT_posture','gt',90.)]
 if name.endswith(('KneeDeg','HipDeg','ElbowDeg')):return [(f'generic_geometry_gt{cut}_NOT_posture','gt',float(cut)) for cut in [90,120,150]]
 return []
def predicate(value,op,cut):return value>cut if op=='gt' else value<cut

def main():
 out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=False);(out/'predicted-metrics').mkdir()
 code=Path(__file__).parent;protocol=json.loads((code/'protocol.json').read_text());gate=json.loads((code/'parity-receipt.json').read_text());fixture=np.asarray(json.loads((code/'fixture.json').read_text()));expected=json.loads((code/'native-expected.json').read_text());actual=measure(fixture)
 assert gate['passed'] and gate['pythonMetricsSHA256']==sha(code/'metrics.py') and gate['fixtureSHA256']==sha(code/'fixture.json') and gate['nativeExpectedSHA256']==sha(code/'native-expected.json')
 parity_max=0.
 for name,values in actual.items():
  for i,value in enumerate(values):
   native=expected[i][name]
   assert (native is None)==(not np.isfinite(value))
   if native is not None:parity_max=max(parity_max,abs(native-value))
 assert parity_max<=1e-10
 run=Path.home()/'bpt-runs/motion-contact/20261020-v3-clean96';manifest=json.loads((run/'manifest.json').read_text());prior=json.loads((run/'results.json').read_text());saved=Path.home()/'bpt-runs/target-continuity-20261102/results';saved_summary=json.loads((saved/'aggregate.json').read_text());assert prior['complete'] and saved_summary['complete']
 assert sha(run/'results.json')==next(value for name,value in manifest['outputs'].items() if Path(name).name=='results.json')
 reference=Path(manifest['argv'][0]).resolve().parents[1]
 for relative,digest in manifest['code'].items():assert sha(reference/relative)==digest
 sys.path[:0]=[str(reference),str(reference/'scripts')]
 from motion_contact.data import load_observations,load_score_reference
 argv=manifest['argv'];option=lambda key,default=None:argv[argv.index(key)+1] if key in argv else default
 records=sorted([r for r in prior['records'] if r['variant']=='A' and r['split']=='heldout'],key=lambda r:r['name']);assert len(records)==60
 cached_hashes={p.name:sha(p) for p in sorted((saved/'predictions').glob('*.npz'))};assert hashlib.sha256(json.dumps(cached_hashes,sort_keys=True).encode()).hexdigest()==saved_summary['candidate_output_hash_manifest_sha256']
 frozen={'protocolSHA256':sha(code/'protocol.json'),'codeSHA256':{p.name:sha(p) for p in code.glob('*.py')},'sourceManifestSHA256':sha(run/'manifest.json'),'sourceResultSHA256':sha(run/'results.json'),'savedPredictionManifestSHA256':saved_summary['candidate_output_hash_manifest_sha256'],'nativeParity':gate,'supportDefinition':protocol['supportDefinition'],'HomeParityMax':parity_max,'GTAccess':'predicted metric NPZ saved+hashed before first load_score_reference for each stream','GTrepSegmentsUsed':False,'GTScaleOrGravityUsedByPredictions':False,'noInference':True,'noPostprocessingRerun':True,'threads':1,'nice':os.nice(0),'historicalSplitTag':'heldout','newEvaluationPopulation':'reused benchmark/development'}
 (out/'pre-GT-freeze.json').write_text(json.dumps(frozen,indent=2)+'\n')
 buckets={};flips={};inputs={};prediction_hashes={};started=time.monotonic();stream_counts=[]
 modes=['raw','full','original_continuity_candidate'];thresholds=protocol['supportScores']
 for index,record in enumerate(records):
  o=load_observations(Path(option('--cache'))/(record['name']+'.npz'),Path(option('--pose2d'))/(record['name']+'.npz'))
  for path,digest in o.inputs.items():assert manifest['inputs'][path]==digest;inputs[path]=digest
  source=saved/'predictions'/f'stream_{index:02d}.npz';assert sha(source)==cached_hashes[source.name]
  with np.load(source) as z:
   coords={'raw':o.raw,'full':z['full'].copy(),'original_continuity_candidate':z['candidate'].copy()};invalid={'raw':np.zeros(o.raw.shape[:2],bool),'full':z['full_invalid'].copy(),'original_continuity_candidate':z['candidate_invalid'].copy()};assert np.array_equal(z['source_time'],o.timestamps)
  numeric={mode:measure(array) for mode,array in coords.items()};support={}
  payload={}
  for mode in modes:
   for score in thresholds:
    mask=supported(numeric[mode],o.normalized[...,2],invalid[mode],score)
    rate,valid=rolling_range(numeric[mode]['cameraTorsoSignedDeg'],o.timestamps,mask['cameraTorsoSignedDeg'])
    support[mode,score]={**mask,'cameraTorsoCausalRangeDeg':valid};payload[f'{mode}_range_score{score}']=rate
   numeric[mode]['cameraTorsoCausalRangeDeg']=rolling_range(numeric[mode]['cameraTorsoSignedDeg'],o.timestamps)[0]
   for name,value in numeric[mode].items():payload[mode+'_'+name]=value
   for score in thresholds:
    for name,mask in support[mode,score].items():payload[f'{mode}_support{score}_{name}']=mask
  target=out/'predicted-metrics'/f'stream_{index:02d}.npz';np.savez_compressed(target,**payload);prediction_hashes[target.name]=sha(target)
  # FIRST GT access, after all modes/slices/rolling predictions are materialized and persisted.
  ref=load_score_reference(Path(option('--dataset-root',str(Path.home()/'datasets/fit3d'))),o)
  for path,digest in ref.inputs.items():assert manifest['inputs'][path]==digest;inputs[path]=digest
  gt=measure(ref.joints_m);gt['cameraTorsoCausalRangeDeg']=rolling_range(gt['cameraTorsoSignedDeg'],o.timestamps)[0]
  n=len(o.raw);first=saved_summary['anonymous_stream_summaries'][index]['first_session_frame'];cut=n if first is None else first
  partitions={'primary':(90,n),'prior':(21,min(cut,n)),'early':(cut,90) if cut<90 else (90,90),'late':(90,n),'primary_no_tail5':(90,max(90,n-5))}
  stream_counts.append({'streamIndex':index,'exercise':o.exercise,'frames':n,'primaryFrames':n-90,'sourcePredictionSHA256':cached_hashes[source.name],'savedMetricSHA256':prediction_hashes[target.name]})
  for name,truth in gt.items():
   applies=('barbell_row',) if name=='cameraTorsoCausalRangeDeg' else APPLICABILITY[name]
   if o.exercise not in applies:continue
   for part,(begin,end) in partitions.items():
    if end<=begin:continue
    truth=gt[name][begin:end];gt_valid=np.isfinite(truth)
    for score in thresholds:
     mode_states={}
     for mode in modes:
      predicted=numeric[mode][name][begin:end];mask=support[mode,score][name][begin:end]&np.isfinite(predicted);joint=gt_valid&np.isfinite(predicted);scored=gt_valid&mask
      error=circular_difference(predicted,truth) if name=='cameraTorsoSignedDeg' else predicted-truth
      for exercise in ['all',o.exercise]:
       key=(part,exercise,name,mode,score);b=buckets.setdefault(key,{'counts':collections.Counter(),'allSigned':[],'supportedSigned':[],'probes':{}})
       b['counts'].update(opportunities=end-begin,GTmetricValid=int(gt_valid.sum()),numericCompared=int(joint.sum()),supportedCompared=int(scored.sum()),withheldOnGTvalid=int((gt_valid&~mask).sum()),GTmetricUndefined=int((~gt_valid).sum()))
       b['allSigned'].append(error[joint]);b['supportedSigned'].append(error[scored])
       for label,op,cutoff in probes(name):
        gt_positive=predicate(truth,op,cutoff)&gt_valid;pred_positive=predicate(predicted,op,cutoff)&mask
        c=b['probes'].setdefault(label,collections.Counter());c.update(GTpositive=int(gt_positive.sum()),GTnegative=int((gt_valid&~gt_positive).sum()),supportedGTpositiveConfirmed=int((gt_positive&pred_positive).sum()),supportedFalsePositive=int((gt_valid&~gt_positive&pred_positive).sum()),supportedGTnegativeConfirmed=int((gt_valid&~gt_positive&mask&~pred_positive).sum()),wrongNegativeGTpositive=int((gt_positive&mask&~pred_positive).sum()),withheldGTpositive=int((gt_positive&~mask).sum()),withheldGTnegative=int((gt_valid&~gt_positive&~mask).sum()))
      for label,op,cutoff in probes(name):mode_states[mode,label]=np.where(mask,np.where(predicate(predicted,op,cutoff),1,0),-1)
     for label,_,_ in probes(name):
      for mode in modes[1:]:
       a=mode_states['raw',label];b=mode_states[mode,label]
       for exercise in ['all',o.exercise]:
        key=(part,exercise,name,score,label,mode);count=flips.setdefault(key,collections.Counter())
        for x,y in [(-1,-1),(-1,0),(-1,1),(0,-1),(0,0),(0,1),(1,-1),(1,0),(1,1)]:count[f'{x}->{y}']+=int(((a==x)&(b==y)).sum())
  print(f'completed {index+1}/60 elapsed={time.monotonic()-started:.1f}s',flush=True)
 for path,digest in inputs.items():assert sha(path)==digest
 for name,digest in cached_hashes.items():assert sha(saved/'predictions'/name)==digest
 assert all(sha(code/name)==digest for name,digest in frozen['codeSHA256'].items())
 report={'schema':'bpt.core3-exact-geometry-results.v1','complete':True,'wallSeconds':time.monotonic()-started,'freeze':frozen,'originalsUnchanged':True,'existingSavedOutputsUnchanged':True,'inputFileCount':len(inputs),'inputHashManifestSHA256':hashlib.sha256(json.dumps(inputs,sort_keys=True).encode()).hexdigest(),'savedMetricHashManifestSHA256':hashlib.sha256(json.dumps(prediction_hashes,sort_keys=True).encode()).hexdigest(),'streams':stream_counts,'metrics':[],'rawAssessmentPredicateMatrices':[],'unsupported':['trunkInclineDeg: no synchronized source gravity; GTgravity not used to invent predicted observation','phase-anchored technique criteria: no original causal phase/anchors; GTreps never used'],'scope':'exact geometric error/crossing agreement on reused development data; NOT proper-form accuracy, injury risk or threshold adoption'}
 for key,b in sorted(buckets.items()):
  part,exercise,name,mode,score=key;row={'supportDefinition':protocol['supportDefinition'],'partition':part,'exercise':exercise,'metric':name,'mode':mode,'supportScore':score,**dict(b['counts']),'allNumericSignedError':stats(b['allSigned']),'allNumericAbsoluteError':stats([np.abs(x) for x in b['allSigned']]),'supportedSignedError':stats(b['supportedSigned']),'supportedAbsoluteError':stats([np.abs(x) for x in b['supportedSigned']]),'geometricProbes':{}}
  for label,count in b['probes'].items():
   count=dict(count);count['strictMissedGTpositiveIncludingWithheld']=count['wrongNegativeGTpositive']+count['withheldGTpositive'];count['strictGTpositiveConfirmationFraction']=count['supportedGTpositiveConfirmed']/count['GTpositive'] if count['GTpositive'] else None;count['strictAgreementFraction']=(count['supportedGTpositiveConfirmed']+count['supportedGTnegativeConfirmed'])/row['GTmetricValid'] if row['GTmetricValid'] else None;count['conditionalSupportedAgreementFraction']=(count['supportedGTpositiveConfirmed']+count['supportedGTnegativeConfirmed'])/row['supportedCompared'] if row['supportedCompared'] else None;row['geometricProbes'][label]=count
  report['metrics'].append(row)
 for key,count in sorted(flips.items()):
  part,exercise,name,score,label,mode=key;report['rawAssessmentPredicateMatrices'].append({'partition':part,'exercise':exercise,'metric':name,'supportScore':score,'probe':label,'comparison':'raw_to_'+mode,'stateEncoding':{'-1':'withheld','0':'not_exceeding','1':'exceeding'},'allOpportunityCounts':dict(count)})
 (out/'aggregate.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n');print(json.dumps({'complete':True,'streams':60,'wallSeconds':report['wallSeconds'],'metricRows':len(report['metrics'])}),flush=True)

if __name__=='__main__':main()
