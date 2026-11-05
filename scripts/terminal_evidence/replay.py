"""Strict numeric terminal-window diagnostic. No retiming, GT, inference or score changes."""
import argparse
import hashlib
import json
import math
from pathlib import Path

SCHEMA = 'bpt.terminal-evidence.v1'
KINDS = {'terminal_header', 'terminal_start', 'terminal_frame', 'terminal_rep', 'terminal_end', 'terminal_capped'}
CANDIDATE_KINDS = {'terminal_candidate_config','terminal_candidate_start','terminal_candidate_begin','terminal_candidate_frame','terminal_candidate_tick','terminal_candidate_end','terminal_candidate_report'}
KINDS |= CANDIDATE_KINDS | {'terminal_eof_flush'}
STATES = {'warming_up', 'tracking_lost', 'bad_3d', 'partial_3d', 'ok'}


class InvalidCapture(ValueError):
    pass


def require(condition, reason):
    if not condition:
        raise InvalidCapture(reason)


def finite(x):
    try:
        return type(x) in (int, float) and math.isfinite(x)
    except OverflowError:
        return False


def integer(x):
    return type(x) is int and x >= 0


def vector(value, length, nullable=False, missing=False):
    if value is None and missing:
        return
    require(type(value) is list and len(value) == length, 'array_shape')
    require(all(finite(x) or (nullable and x is None) for x in value), 'array_nonfinite_or_type')


def validate_coaching_summary(row, exercise=None):
    """Optional profile-free v1 payload must bind to this exact terminal opportunity."""
    if 'coaching_criteria' not in row:return
    payload=row['coaching_criteria']
    require(type(payload) is dict, 'coaching_summary_schema')
    try: encoded=json.dumps(payload,allow_nan=False,separators=(',',':')).encode()
    except (ValueError,TypeError,RecursionError) as error:raise InvalidCapture('coaching_summary_json') from error
    require(len(encoded)<=32768,'coaching_summary_budget')
    require(payload.get('schema')=='bpt.coaching-criteria-terminal.v1' and payload.get('catalogVersion')=='bpt.coaching-metrics.v1', 'coaching_summary_schema')
    require(type(payload.get('profilesUsed')) is int and payload['profilesUsed']==0 and payload.get('scope')=='profile_free_observations_only' and payload.get('state') in ('unknown','not_applicable'), 'coaching_summary_profile_scope')
    require(payload.get('profileAuthority')=='scoped_reference_only_not_whole_form_or_clinical_validation', 'coaching_summary_authority')
    allowed={'schema','status','catalogVersion','state','profilesUsed','scope','profileAuthority','source','context','metrics','unmappedMetrics','unsuppliedCatalogMetrics'}
    if payload.get('status')=='withheld_error':allowed.add('errorReason')
    require(set(payload)==allowed,'coaching_summary_fields')
    source=payload.get('source');context=payload.get('context')
    require(type(source) is dict and type(context) is dict,'coaching_summary_binding')
    for key in ('epoch','frame','source_index','source_pts','source_time_value','source_time_scale','time_basis'):
        require(key in source and type(source[key]) is type(row.get(key)) and source[key]==row.get(key),'coaching_summary_source_mismatch')
    for key in ('phase','side','side_view','source_kind','flush_tail'):
        require(key in context and type(context[key]) is type(row.get(key)) and context[key]==row.get(key),'coaching_summary_context_mismatch')
    require(context.get('gravitySynchronized') is False,'coaching_summary_gravity_unproven')
    aliases={'pushUp':'pushup','push-up':'pushup','barbellRow':'barbell-row','barbell_row':'barbell-row','row':'barbell-row'}
    if exercise is not None:require(aliases.get(context.get('exercise'),context.get('exercise'))==aliases.get(exercise,exercise),'coaching_summary_exercise_mismatch')
    metrics=payload.get('metrics')
    require(payload.get('status') in ('observed','withheld_error'),'coaching_summary_status')
    if payload['status']=='withheld_error':
        require(payload.get('errorReason') in ('observation_encoding_failed','criteria_evaluation_failed') and payload['state']=='unknown' and metrics=={} and payload.get('unmappedMetrics')==[], 'coaching_summary_error')
        require(type(payload.get('unsuppliedCatalogMetrics')) is list and len(payload['unsuppliedCatalogMetrics'])==11 and all(type(x) is str and len(x.encode())<=128 for x in payload['unsuppliedCatalogMetrics']), 'coaching_summary_error_coverage')
        return
    require('errorReason' not in payload,'coaching_summary_status')
    require(type(metrics) is dict and 0<len(metrics)<=32,'coaching_summary_metrics')
    def names(value):return type(value) is list and len(value)<=32 and all(type(x) is str and len(x.encode())<=128 for x in value)
    for name,metric in metrics.items():
        require(type(name) is str and len(name.encode())<=128 and type(metric) is dict,'coaching_summary_metric')
        require(all(k in metric for k in ('rawValue','value','available','reasons','state','criterionReasons','interpretation')),'coaching_summary_metric_fields')
        require(all(metric.get(k) is None or finite(metric.get(k)) for k in ('rawValue','value')) and type(metric.get('available')) is bool,'coaching_summary_value')
        require(metric.get('state') in ('unknown','not_applicable') and metric.get('interpretation')=='unresolved','coaching_summary_decision')
        require(names(metric.get('reasons')) and names(metric.get('criterionReasons')),'coaching_summary_reasons')
        if metric['state']=='unknown':require('profile_required' in metric['criterionReasons'],'coaching_summary_profile_reason')
        if context['flush_tail'] and metric['state']=='unknown':require('flush_sample_not_observation' in metric['criterionReasons'],'coaching_summary_flush')
    require(names(payload.get('unmappedMetrics')) and names(payload.get('unsuppliedCatalogMetrics')),'coaching_summary_coverage')


def validate_candidate_summary(row,start):
    """Experimental candidates may be positive/negative, but never approved form or default delivery."""
    summary=row.get('coaching_candidate');error=row.get('coaching_candidate_error')
    require(not ('coaching_candidate' in row and 'coaching_candidate_error' in row),'candidate_summary_conflicting_error')
    if summary is None and error is None:return
    payload=summary if summary is not None else error
    require(type(payload) is dict,'candidate_summary_schema')
    try:encoded=json.dumps(payload,allow_nan=False,separators=(',',':')).encode()
    except (ValueError,TypeError,RecursionError) as exception:raise InvalidCapture('candidate_summary_json') from exception
    require(len(encoded)<=24576,'candidate_summary_budget')
    source=payload.get('source')
    require(type(source) is dict,'candidate_summary_source')
    for key in ('epoch','frame','source_index','source_pts','source_time_value','source_time_scale','time_basis'):
        require(key in source and type(source[key]) is type(row.get(key)) and source[key]==row.get(key),'candidate_summary_source_mismatch')
    require(payload.get('delivered') is False,'candidate_summary_delivery_claim')
    config=start.get('coaching_candidate_config')
    require(type(config) is dict or start.get('coaching_candidate_configuration_error') is True,'candidate_summary_configuration_missing')
    if error is not None:
        require(set(error)=={'schema','source','reason','delivered'} and error.get('schema')=='bpt.core3-candidate-error.v1' and error.get('reason')=='invalid_configuration_or_candidate_evaluation','candidate_summary_error')
        return
    require(type(config) is dict,'candidate_summary_configuration_missing')
    require(summary.get('schema')=='bpt.core3-candidate-frame.v1' and summary.get('authority')=='engineering_candidate_not_validated_form','candidate_summary_schema')
    require(set(summary)=={'schema','registryVersion','authority','experimentID','experimentDeclaredAt','variant','captureId','evaluationMode','source','context','rules','windowResetReasons','delivered','parameters'},'candidate_summary_fields')
    for key in ('registryVersion','experimentID','experimentDeclaredAt','variant','captureId','evaluationMode','parameters'):
        require(type(summary.get(key)) is type(config.get(key)) and summary.get(key)==config.get(key),'candidate_summary_config_mismatch')
    require(type(summary['parameters']) is dict and all(type(k) is str and len(k)<=128 and finite(v) for k,v in summary['parameters'].items()),'candidate_summary_parameters')
    context=summary.get('context');require(type(context) is dict,'candidate_summary_context')
    for key in ('phase','side','side_view','source_kind','flush_tail','rotation','size','source_mirrored'):
        require(key in context and type(context[key]) is type(row.get(key)) and context[key]==row.get(key),'candidate_summary_context_mismatch')
    aliases={'pushUp':'pushup','barbellRow':'barbell-row','barbell_row':'barbell-row'}
    require(aliases.get(context.get('exercise'),context.get('exercise'))==aliases.get(start.get('exercise'),start.get('exercise')),'candidate_summary_exercise_mismatch')
    def strings(value):return type(value) is list and len(value)<=64 and all(type(x) is str and len(x.encode())<=256 for x in value)
    require(strings(summary.get('windowResetReasons')),'candidate_summary_reset_reasons')
    rules=summary.get('rules');require(type(rules) is list and 0<len(rules)<=9,'candidate_summary_rules')
    known={'pushup':{'pushup.camera_body_line_transfer','pushup.projected_arm_range','pushup.bottom_target','pushup.top_extension_target'},'squat':{'squat.early_ascent_coordination','squat.bottom_target','squat.top_extension_target'},'barbell-row':{'row.camera_torso_window_transfer','row.phase_prefix_leg_arm_cooccurrence'}}
    require({x.get('id') for x in rules if type(x) is dict}==known.get(aliases.get(start.get('exercise'),start.get('exercise'))),'candidate_summary_rule_binding')
    states=('positive_evidence','negative_evidence','unknown','not_applicable')
    for rule in rules:
        require(type(rule) is dict and rule.get('state') in states and type(rule.get('configured')) is bool and rule.get('meaning') in ('deviation','desired_match') and strings(rule.get('reasons')),'candidate_summary_rule')
        require(type(rule.get('target')) is str and len(rule['target'].encode())<=2048,'candidate_summary_target')
        if not rule['configured']:require(rule['state'] not in ('positive_evidence','negative_evidence'),'candidate_summary_unconfigured_claim')
        components=rule.get('components');require(type(components) is list and 0<len(components)<=4,'candidate_summary_components')
        for component in components:
            require(type(component) is dict and type(component.get('metric')) is str and component.get('state') in states and strings(component.get('reasons')),'candidate_summary_component')
            require(all(k in component and (component[k] is None or finite(component[k])) for k in ('rawValue','value','evaluatedValue')),'candidate_summary_component_number')
            proof=component.get('proof');require(type(proof) is dict and integer(proof.get('count')) and proof['count']<=512 and proof.get('causal') is True,'candidate_summary_window')
            if row['flush_tail']:require(component['state'] not in ('positive_evidence','negative_evidence'),'candidate_summary_flush_claim')
    proposal=row.get('coaching_candidate_proposal')
    if proposal is not None:
        require(type(proposal) is dict and proposal.get('schema')=='bpt.coaching-candidate-proposal.v1' and proposal.get('authority')=='engineering_candidate_not_validated_form' and proposal.get('presentation')=='visual_only_no_tts' and proposal.get('delivery')=='proposed','candidate_proposal_schema')
        require(not row['flush_tail'] and proposal.get('captureId')==summary['captureId'] and proposal.get('source')==summary['source'] and proposal.get('context')==summary['context'],'candidate_proposal_source')
        require(type(proposal.get('proposalId')) is str and len(proposal['proposalId'])==64 and all(x in '0123456789abcdef' for x in proposal['proposalId']),'candidate_proposal_id')
        matching=[rule for rule in rules if rule['id']==proposal.get('ruleId')]
        require(len(matching)==1 and matching[0]['configured'],'candidate_proposal_rule')
        rule=matching[0]
        require(proposal.get('predicateMeaning')==rule['meaning'] and proposal.get('predicateState')==rule['state'],'candidate_proposal_predicate')
        require((rule['meaning']=='deviation' and rule['state']=='positive_evidence' and proposal.get('assessment')=='deviation_candidate') or (rule['meaning']=='desired_match' and rule['state']=='negative_evidence' and proposal.get('assessment')=='target_not_met_candidate'),'candidate_proposal_direction')



def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate_json_key')
        result[key] = value
    return result


def load(path):
    path = Path(path)
    require(path.stat().st_size <= 64 * 1024 * 1024, 'file_limit')
    raw = path.read_bytes()
    rows = []
    for line in raw.splitlines():
        require(0 < len(line) <= 65536, 'line_limit')
        try:
            row = json.loads(line, object_pairs_hook=unique_object, parse_constant=lambda x: (_ for _ in ()).throw(InvalidCapture('nonfinite_json')))
        except (ValueError, UnicodeError) as error:
            raise InvalidCapture('invalid_json') from error
        require(type(row) is dict and row.get('schema') == SCHEMA, 'schema')
        require(row.get('type') in KINDS, 'record_type')
        require(not any(k in row for k in ('arrival_host', 't_host', 't', 'env', 'token', 'path')), 'mixed_clock_or_private_field')
        require(type(row.get('sequence')) is int and row['sequence'] == len(rows), 'record_sequence')
        rows.append(row)
    require(0 < len(rows) <= 6002, 'record_limit')
    header = rows[0]
    require(header['type'] == 'terminal_header' and sum(r['type'] == 'terminal_header' for r in rows) == 1, 'header')
    require(header.get('clock') == 'sample_pts_seconds', 'clock')
    require(header.get('provenance') in ('ios_video_as_camera_pipeline','ios_live_camera_pipeline','synthetic_test'), 'provenance')
    require(header.get('units_3d') == 'h36m17_xs_model_space_no_metric_guarantee' and header.get('units_2d') == 'analysis_image_pixels', 'units')
    require(header.get('configuration_location') == 'terminal_start', 'configuration_location')
    epochs = {}
    active = None
    capped = False
    for row in rows[1:]:
        kind = row['type']
        require(not capped, 'records_after_cap')
        if kind == 'terminal_capped':
            require(row.get('incomplete') is True, 'cap_incomplete')
            capped = True
            continue
        if kind in CANDIDATE_KINDS:
            require(header.get('candidate_protocol') == 'bpt.terminal-candidate.v1', 'candidate_protocol')
            payload = row.get('payload')
            if kind in ('terminal_candidate_config','terminal_candidate_begin','terminal_candidate_frame','terminal_candidate_report'):
                require(type(payload) is dict and row.get('candidate_protocol') == 'bpt.terminal-candidate.v1', 'candidate_payload')
                def numeric_tree(x):
                    if isinstance(x, dict): return all(numeric_tree(v) for v in x.values())
                    if isinstance(x, list): return all(numeric_tree(v) for v in x)
                    return type(x) not in (int,float) or finite(x)
                require(numeric_tree(payload), 'candidate_nonfinite')
            if kind == 'terminal_candidate_begin':
                require(type(payload.get('original')) is dict and integer(payload['original'].get('epoch')) and payload['original']['epoch'] == active and finite(payload.get('hostTime')), 'candidate_begin')
                epochs[active]['candidate_originals'].append(payload['original'])
            if kind == 'terminal_candidate_frame':
                require(integer(payload.get('epoch')) and payload['epoch'] == active, 'candidate_stale_epoch')
                require(integer(payload.get('frame')) and finite(payload.get('hostTime')), 'candidate_clock')
                require(type(payload.get('required2D')) is bool and type(payload.get('flushed')) is bool and type(payload.get('setEndFlushTail')) is bool, 'candidate_support')
                require(payload.get('sideView') is None or type(payload['sideView']) is bool, 'candidate_support')
                require(payload.get('sourceTime') is None or finite(payload['sourceTime']), 'candidate_clock')
                for key in ('assessmentAngles','rawAngles'):
                    require(type(payload.get(key)) is dict and all(k in ('elbow','knee','hip') and finite(v) for k,v in payload[key].items()), 'candidate_angles')
            if kind == 'terminal_candidate_frame':
                epochs[active]['candidate_frames'].append(payload)
            if kind in ('terminal_candidate_start','terminal_candidate_end','terminal_candidate_tick'):
                require(integer(row.get('epoch')) and row['epoch'] == active, 'candidate_stale_epoch')
            if kind == 'terminal_candidate_tick':
                require(integer(row.get('rep')) and finite(row.get('host_time')), 'candidate_tick')
            if kind == 'terminal_candidate_end':
                require(finite(row.get('host_time')) and type(row.get('reason')) is str, 'candidate_end')
            continue  # raw frame/rep order and sequence remain intact; derived reports are not GT
        epoch = row.get('epoch')
        require(integer(epoch), 'epoch')
        if kind == 'terminal_start':
            require(active is None and epoch not in epochs, 'overlapping_or_reused_epoch')
            require(row.get('time_basis') == 'sample_pts_seconds' and row.get('raw_source') == 'xs_output_before_constraints', 'clock_or_raw_provenance')
            require(integer(row.get('lookahead')) and integer(row.get('cadence')) and row['cadence'] >= 1 and row['lookahead'] + row['cadence'] <= 27, 'model_window')
            require(row.get('exercise') in ('squat', 'pushUp', 'pushup', 'benchPress', 'barbellRow', 'deadlift'), 'exercise')
            row['provenance'] = header['provenance']
            epochs[epoch] = {'start': row, 'frames': [], 'reps': [], 'candidate_frames': [], 'candidate_originals': [], 'end': None}
            active = epoch
            continue
        require(active == epoch, 'stale_or_unstarted_epoch')
        data = epochs[epoch]
        if kind == 'terminal_eof_flush':
            require(row.get('trigger') == 'video_eof_test_hook' and row.get('processing_queue_drained') is True, 'eof_flush_provenance')
        elif kind == 'terminal_end':
            require(type(row.get('incomplete')) is bool and type(row.get('flush_complete')) is bool, 'end_status')
            require(row['incomplete'] or row['flush_complete'], 'false_complete')
            data['end'] = row
            active = None
        elif kind == 'terminal_rep':
            require(integer(row.get('rep')) and integer(row.get('start_frame')) and integer(row.get('end_frame'))
                    and row['start_frame'] <= row['end_frame'] and row.get('side') in ('left', 'right'), 'rep_boundary')
            require(not data['reps'] or row['rep'] > data['reps'][-1]['rep'], 'duplicate_rep')
            data['reps'].append(row)
        elif kind == 'terminal_frame':
            validate_coaching_summary(row, data['start'].get('exercise'))
            validate_candidate_summary(row,data['start'])
            require(integer(row.get('frame')) and integer(row.get('source_index')) and finite(row.get('source_pts')) and row['source_pts'] >= 0, 'source_time')
            require(type(row.get('source_time_value')) is int and abs(row['source_time_value']) <= 2**63-1 and integer(row.get('source_time_scale')) and 0 < row['source_time_scale'] <= 2**31-1, 'source_rational_time')
            require(math.isclose(row['source_time_value']/row['source_time_scale'],row['source_pts'],rel_tol=1e-12,abs_tol=1e-9), 'source_clock_mismatch')
            require(row.get('time_basis') == 'sample_pts_seconds' and row.get('source_kind') in ('video_frame', 'camera_capture_index'), 'clock')
            if data['frames']:
                previous = data['frames'][-1]
                require(all(row[k] > previous[k] for k in ('frame', 'source_index', 'source_pts')), 'duplicate_or_regressing_source')
                require(row['source_kind'] == previous['source_kind'], 'mixed_source')
                require(row['rotation'] == previous['rotation'] and row['size'] == previous['size'], 'coordinate_system_changed')
            vector(row.get('size'), 2)
            require(all(x > 0 for x in row['size']) and type(row.get('rotation')) is int and row['rotation'] in (0, 90, 180, 270), 'image_geometry')
            for key in ('raw_2d', 'input_2d', 'assessment_2d'):
                vector(row.get(key), 51)
            for key in ('raw_3d', 'constrained_3d', 'adapted_3d', 'assessment_3d'):
                require(key in row, 'missing_layer')
                vector(row[key], 51, nullable=True, missing=True)
            vector(row.get('confidence_h36m'), 17, missing=True)
            require(type(row.get('invalid')) is list and all(integer(i) and i < 17 for i in row['invalid']) and len(set(row['invalid'])) == len(row['invalid']), 'invalid_mask')
            require(row.get('raw_state') in STATES and row.get('assessment_state') in STATES, 'state')
            require(row.get('side') in (None, 'left', 'right') and (row.get('side_view') is None or type(row['side_view']) is bool), 'side_or_view')
            require(type(row.get('flush_tail')) is bool and integer(row.get('filled')) and row['filled'] <= 27, 'window')
            require(row.get('row') is None or integer(row['row']) and row['row'] < 27, 'model_row')
            if row['raw_3d'] is not None:
                require(row['row'] is not None and row['filled'] > 0, 'raw_window')
            if row['raw_state'] in ('ok', 'partial_3d'):
                require(row['raw_3d'] is not None and row['constrained_3d'] is not None, 'missing_native_3d')
            require(row.get('source_gravity_available') is False and row.get('up_time_basis') == 'judgement_time_not_source_sensor', 'gravity_provenance')
            vector(row.get('judgement_up'), 3, missing=True)
            require('active_rep_start' in row and (row['active_rep_start'] is None or integer(row['active_rep_start']) and row['active_rep_start'] <= row['frame']), 'active_rep_boundary')
            require(row.get('phase') is None or type(row['phase']) is str and len(row['phase']) < 128, 'phase')
            require(row.get('unit_px') is None or finite(row['unit_px']) and row['unit_px'] > 0, 'input_crop_scale')
            data['frames'].append(row)
    require(epochs, 'no_capture')
    require(active is None or capped, 'missing_footer')
    for data in epochs.values():
        frames = {f['frame']: f for f in data['frames']}
        for rep in data['reps']:
            require(rep['start_frame'] in frames and rep['end_frame'] in frames, 'missing_boundary_frame')
        for candidate in data['candidate_frames']:
            source = frames.get(candidate['frame'])
            require(source is not None and candidate.get('sourceTime') == source['source_pts'] and candidate.get('sourceIndex') == source['source_index'], 'candidate_source_binding')
            require(candidate.get('side') == source.get('side') and candidate.get('phase') == source.get('phase') and candidate.get('activeRepStart') == source.get('active_rep_start'), 'candidate_native_binding')
            require(candidate.get('state') == source['assessment_state'] and candidate.get('flushed') == source['flush_tail'], 'candidate_assessment_binding')
            for metric,value in candidate['assessmentAngles'].items():
                require(candidate.get('side') in ('left','right'), 'candidate_geometry_binding')
                actual=angle(source,'assessment_3d',candidate['side'],metric)
                require(actual is not None and math.isclose(actual,value,rel_tol=1e-9,abs_tol=1e-7), 'candidate_geometry_binding')
        for original in data['candidate_originals']:
            matches = [rep for rep in data['reps'] if rep['rep'] == original.get('rep')]
            require(len(matches) == 1 and matches[0]['start_frame'] == original.get('startFrame') and matches[0]['end_frame'] == original.get('endFrame') and matches[0]['side'] == original.get('side'), 'candidate_original_binding')

    return epochs, capped, hashlib.sha256(raw).hexdigest()


H36M = {'left': {'elbow': (11, 12, 13), 'knee': (4, 5, 6), 'hip': (11, 4, 5)},
         'right': {'elbow': (14, 15, 16), 'knee': (1, 2, 3), 'hip': (14, 1, 2)}}


def angle(frame, layer, side, joint):
    p = frame[layer]
    ids = H36M[side][joint]
    if p is None or layer == 'assessment_3d' and (frame['assessment_state'] not in ('ok', 'partial_3d') or set(ids) & set(frame['invalid'])):
        return None
    points = [p[i * 3:i * 3 + 3] for i in ids]
    if not all(finite(x) for v in points for x in v):
        return None
    a, b, c = points
    u, v = [x-y for x, y in zip(a, b)], [x-y for x, y in zip(c, b)]
    den = math.sqrt(sum(x*x for x in u) * sum(x*x for x in v))
    if den < 1e-8:
        return None
    return math.degrees(math.acos(max(-1, min(1, sum(x*y for x, y in zip(u, v))/den))))


def extrema(frames, layer, side, joint):
    values = [angle(f, layer, side, joint) for f in frames]
    if not values or any(v is None for v in values):
        return None
    return {'max': max(values), 'range': max(values)-min(values)}


def replay(path):
    epochs, capped, digest = load(path)
    summaries = []
    for data in epochs.values():
        exercise = data['start']['exercise']
        if exercise not in ('squat', 'pushUp', 'pushup'):
            continue
        for i, rep in enumerate(data['reps']):
            frames = data['frames']
            original = [f for f in frames if rep['start_frame'] <= f['frame'] <= rep['end_frame']]
            next_start = data['reps'][i+1]['start_frame'] if i+1 < len(data['reps']) else math.inf
            # Includes a subsequent rep that began but never produced a completed report.
            active_starts = [f['active_rep_start'] for f in frames if f['active_rep_start'] is not None and f['active_rep_start'] > rep['start_frame']]
            next_start = min([next_start, *active_starts])
            # Exactly15 DISTINCT observed sources, never duplicated/clamped flush output.
            following = [f for f in frames if rep['end_frame'] < f['frame'] < next_start and not f['flush_tail']][:15]
            complete = len(following) == 15 and not capped
            for joint in (('knee', 'hip') if exercise == 'squat' else ('elbow',)):
                for side in ('left', 'right'):
                    for layer in ('raw_3d', 'assessment_3d'):
                        a = extrema(original, layer, side, joint)
                        b = extrema(original + following, layer, side, joint) if complete else None
                        summaries.append({'exercise': exercise, 'joint': joint, 'side': 'selected' if side == rep['side'] else 'opposite',
                            'layer': layer, 'original': a, 'extended': b, 'following': len(following),
                            'capture_complete': data['end'] is not None and not data['end']['incomplete'],
                            'new_source_gaps': sum(y['source_index'] != x['source_index']+1 for x,y in zip(original+following, (original+following)[1:]))})
    grouped = {}
    for row in summaries:
        key = '/'.join(row[k] for k in ('exercise', 'joint', 'side', 'layer'))
        group = grouped.setdefault(key, {'comparisons': 0, 'paired': 0, 'original_available': 0, 'incomplete_capture': 0,
                                        'short_followup': 0, 'source_gaps': 0, 'max_delta_deg': [], 'range_delta_deg': []})
        group['comparisons'] += 1
        group['original_available'] += row['original'] is not None
        group['incomplete_capture'] += not row['capture_complete']
        group['short_followup'] += row['following'] < 15
        group['source_gaps'] += row['new_source_gaps']
        if row['original'] is not None and row['extended'] is not None:
            group['paired'] += 1
            for metric in ('max', 'range'):
                group[f'{metric}_delta_deg'].append(row['extended'][metric] - row['original'][metric])
    for group in grouped.values():
        for key in ('max_delta_deg', 'range_delta_deg'):
            values = group[key]
            group[key] = {'mean': sum(values)/len(values), 'min': min(values), 'max': max(values)} if values else None
    return {'schema': SCHEMA, 'input_sha256': digest, 'epochs': len(epochs), 'capped': capped,
            'capture_provenance': next(iter(epochs.values()))['start'].get('provenance', 'see_header'),
            'protocol': 'fixed15-distinct-nonflush-sources-before-next-recorded-rep-start', 'groups': grouped,
            'interpretation': 'Observed window/extrema differences only.15 observations do not establish completed extension, correct form or accuracy improvement. Fixed original reported side and both sides. Geometry-only reconstruction, not native requiredOK/view/reference/phase eligibility or judgement parity. Comparison counts are geometry windows, not assessable reps. No GT, threshold changes or model inference.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(replay(args.capture), ensure_ascii=False, indent=2, allow_nan=False))
    except (InvalidCapture, OSError) as error:
        parser.exit(2, f'capture_rejected: {error}\n')
