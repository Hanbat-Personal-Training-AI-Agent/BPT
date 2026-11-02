"""Read-only existing capture/report adapters. Never infer missing runtime decisions."""
import hashlib
from pathlib import Path
from .contract import SCHEMA, RULES, digest, loads, require
from scripts.terminal_evidence.replay import load as load_terminal

NATIVE_SOURCE = '1a35d3fef5cd4b5b5bc49ac003a4584306cce344'
EXERCISES = {'pushUp': 'pushup', 'squat': 'squat', 'barbellRow': 'barbell-row'}


def file_sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checked_read(path, expected):
    raw = Path(path).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == expected, 'input_sha256_mismatch')
    return raw


def native(path, expected_sha256, source_revision=NATIVE_SOURCE):
    """One evidence stream per actual capture epoch, with original closed intervals.

    Model/raw/corrected layers remain hash-addressed in the immutable original JSONL;
    only the assessment layer is interpreted. No raw scores are clamped.
    The caller's revision assertion is provenance, not derivable from model hashes.
    """
    raw = checked_read(path, expected_sha256)
    header = loads(raw.splitlines()[0])
    epochs, capped, actual_sha = load_terminal(path)
    require(actual_sha == expected_sha256, 'input_changed_during_read')
    streams = []
    for epoch_id, epoch in epochs.items():
        exercise = EXERCISES.get(epoch['start']['exercise'], epoch['start']['exercise'])
        frames = []
        for f in epoch['frames']:
            support = {}
            invalid = f.get('invalid')
            for ex in RULES.values():
                side = f.get('side')
                chain = ex['joints'].get(side)
                support[ex['chain']] = (f.get('assessment_state') in ('ok', 'partial_3d') and
                                         not any(j in invalid for j in chain)) if chain is not None and type(invalid) is list else None
            frames.append({'id': f['frame'], 'source_index': f['source_index'],
                           'time': {'value': f['source_time_value'], 'scale': f['source_time_scale'],
                                    'seconds': f['source_pts']},
                           'side': f['side'], 'phase': f['phase'], 'view_eligible': f['side_view'],
                           'joints': f['assessment_3d'], 'invalid_joints': invalid,
                           'confidence_h36m': f['confidence_h36m'],
                           'chain_support': support, 'uncertainty_known': type(invalid) is list and f.get('assessment_state') is not None,
                           'assessment_state': f['assessment_state'], 'raw_state': f['raw_state'],
                           'layer_hashes': {k: digest(f[k]) for k in ('raw_3d','constrained_3d','adapted_3d','assessment_3d')},
                           'raw_and_correction_provenance': {k: f[k] for k in ('invalid','row','filled','flush_tail','rotation','front_camera','source_mirrored','judgement_up','source_gravity_available')},
                           'original_record_sha256': digest(f)})
        reps = []
        for r in epoch['reps']:
            selected = [f for f in frames if r['start_frame'] <= f['id'] <= r['end_frame']]
            ids = [f['id'] for f in selected]
            gaps = sum(max(0, b['source_index']-a['source_index']-1) for a,b in zip(selected,selected[1:]))
            reps.append({'id': r['rep'], 'ordinal': r['rep'],
                         'original_interval': {'start':r['start_frame'],'end':r['end_frame'],'closure':'closed','unit':'native_frame_index'},
                         'original_record': r, 'frame_ids': ids, 'source_gaps': gaps,
                         'span_complete': not capped and ids == list(range(r['start_frame'],r['end_frame']+1)),
                         'runtime': {'state':'missing','reason':'terminal_rep_does_not_log_shallow_judge_result',
                                     'form_source':r['form_source'], 'declared_side':r['side']},
                         'delivery': {'state':'missing','reason':'actual_rule_delivery_not_logged'}})
        streams.append({'schema': SCHEMA, 'exercise':exercise, 'criterion_scope':'relative_drift',
                        'reference_kind':'observed_first3','target_profile':None,
                        'first3_reference_identity':{'origin':'observed_set_start','set_id':str(epoch['start']['set']),
                                                     'epoch':epoch_id,'observation_sha256':actual_sha,
                                                     'first3_rep_ids':[r['id'] for r in reps[:3]]},
                        'clip':{'media_sha256':None,'observation_sha256':actual_sha,
                                'identity_kind':'original_numeric_capture_only','media_identity':'not_retained_in_terminal_stream'},
                        'source':{'kind':'actual_native_terminal_capture','candidate_revision':source_revision,
                                  'revision_provenance':'caller_bound_published_capture_receipt_not_embedded_header',
                                  'epoch':epoch_id,'model_hashes':header['model_hashes'],
                                  'joint_definition':'BPT_H36M17','coordinate_frame':'camera_x_right_y_down_z_away_pelvis_relative',
                                  'pose_units':header['units_3d'],'layer_role':'assessment','side_policy':'actual_per_frame',
                                  'provenance':header['provenance'], 'original_header_sha256':digest(header)},
                        'clock':{'kind':'original_sample_pts','epoch':epoch_id,'unit':'seconds','time_basis':epoch['start']['time_basis']},
                        'capture_end':epoch.get('end'),'frames':frames,'reps':reps})
    require(file_sha(path)==actual_sha,'input_changed_after_read')
    return streams


def deep_report(report_path, report_sha256, evidence_path, verification_path):
    """Actual worker report adapter. No raw-frame evidence is fabricated from summary.

    This existing report is barbell-row, outside this engine's two-rule scope. It
    is still an executable negative-control replay, carrying original evaluated
    keys, warnings, intervals and validity. It is NOT a new model invocation.
    """
    raw = checked_read(report_path, report_sha256)
    report = loads(raw)
    evidence, proof = loads(Path(evidence_path).read_bytes()), loads(Path(verification_path).read_bytes())
    require(proof.get('status') == 'verified_actual_isolated_report_not_authenticated_API', 'unverified_worker_artifact')
    artifacts = proof.get('artifactSha256', {})
    require(artifacts.get('worker_report.json') == report_sha256, 'worker_report_binding')
    require(artifacts.get('evidence.json') == file_sha(evidence_path), 'worker_evidence_binding')
    require(evidence.get('inputVideoSha256') == proof.get('inputVideoSha256'), 'video_binding')
    require(evidence.get('pinnedNativeManifestCanonicalSha256') == proof.get('serviceManifestSha256'), 'manifest_binding')
    reps = []
    rule = RULES.get(report.get('exerciseId'))
    for r in report['reps']:
        evaluated, warnings = r.get('evaluatedKeys'), r.get('serverWarnings')
        key = rule['native'] if rule else None  # evaluatedKeys/serverWarnings are DEVICE keys, not fault IDs
        if key is not None and type(evaluated) is list and key in evaluated:
            state = 'warning' if key in (warnings or []) else 'no_warning'
        else:
            state = 'withheld' if key else 'missing'
        reps.append({'id':r['repIndex'],'ordinal':r['repIndex'], 'frame_ids':[], 'span_complete':False,
                     'original_interval':{'start':r['startMs'],'end':r['endMs'],'closure':'half_open','unit':'video_ms'},
                     'runtime':{'state':state,'reason':'target_rule_not_evaluated_or_outside_scope' if state in ('missing','withheld') else 'explicit_evaluated_key',
                                'evaluated_keys':evaluated,'server_warnings':warnings,'metric_validity':r.get('metricValidity'),
                                'original_faults':r.get('faults')},
                     'delivery':{'state':'missing','reason':'isolated_worker_is_not_live_delivery'}})
    return {'schema':SCHEMA,'exercise':report['exerciseId'],'criterion_scope':'relative_drift',
            'reference_kind':'observed_first3','target_profile':None,
            'clip':{'media_sha256':evidence['inputVideoSha256'],'observation_sha256':report_sha256,
                    'service_manifest_sha256':proof['serviceManifestSha256'],'identity_kind':'verified_worker_report'},
            'source':{'kind':'actual_isolated_deep_worker','candidate_revision':'8e00f543a70dd85b93b6ed716c1377a70586dffd',
                      'revision_provenance':'published_verified_isolated_run_receipt_source_hashes_below',
                      'source_hashes':evidence['actualImportedSourceSha256'],'joint_definition':'BPT_H36M17',
                      'coordinate_frame':'gvhmr_world_y_up','pose_units':'model_world_meters','layer_role':'assessment',
                      'side_policy':'fixed_manifest_policy','raw_frame_evidence':'not_adapted_from_summary',
                      'evidence_sha256':file_sha(evidence_path),'verification_sha256':file_sha(verification_path)},
            'clock':{'kind':'original_native_video_ms_intervals','fps_reported':report['fps'],
                     'retimed':evidence.get('nativeManifestRetimed'),'frame_seconds_to_video_ms':1000},'frames':[],'reps':reps}
