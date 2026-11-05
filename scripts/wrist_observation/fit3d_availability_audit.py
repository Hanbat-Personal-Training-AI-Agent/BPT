"""Read-only Home cache/baseline compatibility audit. No inference, candidate, file writes or raw export.
Run via SSH stdin in the existing bpt-home environment; stdout is aggregate only.
"""
import hashlib
import json
from pathlib import Path
import sys


def main():
    import numpy as np
    run=Path.home()/'bpt-runs/motion-contact/20261020-v3-clean96'
    manifest=json.loads((run/'manifest.json').read_text());results=json.loads((run/'results.json').read_text())
    assert results['complete']
    digest=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
    expected=next(v for k,v in manifest['outputs'].items() if Path(k).name=='results.json')
    assert digest(run/'results.json')==expected
    code=Path(manifest['argv'][0]).resolve().parents[1]
    for relative,expected in manifest['code'].items():assert digest(code/relative)==expected,relative
    sys.path[:0]=[str(code),str(code/'scripts')]
    from motion_contact.data import load_observations,load_score_reference,HELDOUT
    argv=manifest['argv'];option=lambda name,default=None:argv[argv.index(name)+1] if name in argv else default
    assert option('--scenario-dir') is None and option('--limit') is None
    cache=Path(option('--cache'));pose=Path(option('--pose2d'));dataset=Path(option('--dataset-root',str(Path.home()/'datasets/fit3d')))
    records=[r for r in results['records'] if r['variant']=='A' and r['split']=='heldout'];assert len(records)==60
    errors=[];perstream_differences=[];raw_saved_differences=[];corrected_raw_differences=[];timesteps=[];lengths=[];fingerprints={};groups={};first_last=[];first_usable=21
    for record in records:
        name=record['name'];o=load_observations(cache/(name+'.npz'),pose/(name+'.npz'));assert o.subject in HELDOUT
        prediction=run/'predictions_HOME_ONLY'/(name+'_A.npz')
        # Predicted arrays are immutable cache evidence, not regenerated outputs.
        assert digest(prediction)==record['artifact_sha256']
        with np.load(prediction) as z:
            raw_saved_differences.append(float(np.max(np.abs(z['raw_model']-o.raw))))
            corrected_raw_differences.append(float(np.max(np.abs(z['corrected']-(o.raw-o.raw[:,:1])))))
        assert np.isfinite(o.raw).all();assert np.all(np.diff(o.timestamps)>0)
        timesteps.extend(np.diff(o.timestamps).tolist());lengths.append(len(o.raw));first_last.append([float(o.timestamps[0]),float(o.timestamps[-1])])
        # GT access occurs here only for final scoring and compatibility verification.
        ref=load_score_reference(dataset,o)
        for path,value in {**o.inputs,**ref.inputs}.items():assert manifest['inputs'][path]==value;fingerprints[path]=value
        error=np.linalg.norm((o.raw-o.raw[:,:1])*ref.metres_per_crop_unit[:,None,None]-ref.joints_m,axis=-1)[90:]*1000
        assert np.isfinite(error).all() and error.size==record['metrics']['joint_frames']
        assert error.size==record['metrics']['mpjpe_mm']['n']
        perstream_differences.append(abs(float(error.mean())-record['metrics']['mpjpe_mm']['mean']))
        errors.append(error.ravel());groups.setdefault(o.exercise,[]).append(error.ravel())
    all_error=np.concatenate(errors);assert all_error.size==568004
    weighted=sum(r['metrics']['mpjpe_mm']['mean']*r['metrics']['mpjpe_mm']['n'] for r in records)/568004
    assert max(perstream_differences)<1e-9 and abs(float(all_error.mean())-weighted)<1e-9
    assert round(float(all_error.mean()),3)==146.839
    output={'scope':'read-only existing Home arrays and scorer; no inference, candidate processing, raw transfer or new profile',
        'original_run_complete':True,'source_manifest_sha256':digest(run/'manifest.json'),'source_results_sha256':digest(run/'results.json'),
        'frozen_code_files_hash_verified':len(manifest['code']),'unique_observation_and_GT_files_hash_verified':len(fingerprints),
        'combined_input_hash_manifest_sha256':hashlib.sha256(json.dumps(fingerprints,sort_keys=True).encode()).hexdigest(),
        'streams':len(records),'joint_frames_including_pelvis':int(all_error.size),'scored_frames':int(all_error.size//17),'score_start_index':90,'raw_first_usable_index':first_usable,
        'A_raw_root_relative_MPJPE_mm':float(all_error.mean()),'original_A_records_weighted_MPJPE_mm':weighted,
        'max_perstream_MPJPE_disagreement_mm':max(perstream_differences),'saved_raw_model_max_absolute_difference':max(raw_saved_differences),'saved_A_corrected_vs_rootcentered_raw_max_absolute_difference':max(corrected_raw_differences),
        'exercise_groups':{ex:{'streams':len(chunks),'joint_frames':int(sum(len(c) for c in chunks)),'MPJPE_mm':float(np.concatenate(chunks).mean())} for ex,chunks in groups.items()},
        'raw_frames_total':sum(lengths),'raw_frames_per_stream_range':[min(lengths),max(lengths)],'finite_raw_all_streams':True,
        'timestamp_contract':'retained Fit3D pick index / 50Hz; loader verifies pick==round(arange(n)*50/30); never invented uniform30fps',
        'actual_source_dt_seconds_unique':sorted(set(round(x,9) for x in timesteps)),'maximum_source_time_seconds':max(t[1] for t in first_last),
        'coordinate_contract':'XS H36M17 crop-model coordinates; center at current pelvis. GT camera=(joints-T)@R.T, H36M mapping retained. Scoring-only metres_per_crop_unit=crop.side/2*GTcameraRootDepth/meanFocal; multiply Euclidean error by1000 for mm.',
        'data_boundary':'Files are full stream reset boundaries, fixed subject/exercise/camera; raw producer edge-clamps L5 windows at both ends, first usable21; tail5 are clamped and original A denominator includes them.',
        'baseline_distinction':'A is original pretrained cached XS, not current native full constraints or phone hybrid MP input. Native full vs continuity would be a new offline postprocessing ablation on these raw caches.',
        'split_status':'60 streams were heldout from original tuning36 but have already been evaluated/inspected for A-H and v4; reused development evidence for this followup, not a fresh independent holdout.',
        'candidate_executed':False,'runtime_modified':False,'gt_runtime_input':False}
    print(json.dumps(output,indent=2,allow_nan=False))

if __name__=='__main__':main()
