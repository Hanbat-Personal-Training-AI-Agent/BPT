"""Versioned, numeric-only shadow contract with explicit missing evidence."""
import hashlib
import json
import math

SCHEMA = 'bpt.coaching-shadow-evidence.v1'
RESULT_SCHEMA = 'bpt.coaching-shadow-result.v1'
RULES = {
    'pushup': {'native': 'pushup_shallow', 'deep': 'pushup_depth_drift', 'chain': 'elbow',
               'native_quiet_by_default': True, 'joints': {'left': (11, 12, 13), 'right': (14, 15, 16)}, 'threshold_deg': 15.0},
    'squat': {'native': 'squat_shallow', 'deep': 'squat_depth_drift', 'chain': 'knee',
              'native_quiet_by_default': False, 'joints': {'left': (4, 5, 6), 'right': (1, 2, 3)}, 'threshold_deg': 15.0},
}
CONFIDENCE_POLICY = {'id':'shadow_required_chain_2d_support_native_config_0.30',
                     'minimum':0.30, 'original_3d_judge_gate':False,
                     'source':'FormWarnings.swift:33,892-906; MotionAGFormerLive.swift:226',
                     'config_source_sha256':'b4161e2b386f46ab1db2f14075ef11e0ab9c709962ef6f7cfcf4a2ec74758449'}
STATES = {'warning', 'no_warning', 'withheld', 'missing'}


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def finite(x):
    return type(x) in (int, float) and math.isfinite(x)


def unique(pairs):
    out = {}
    for k, v in pairs:
        require(k not in out, 'duplicate_json_key')
        out[k] = v
    return out


def loads(raw):
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite_json')))


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                     allow_nan=False).encode()).hexdigest()


def validate(stream):
    require(type(stream) is dict and stream.get('schema') == SCHEMA, 'schema')
    require(stream.get('criterion_scope') == 'relative_drift', 'scope_not_implemented')
    require(stream.get('reference_kind') == 'observed_first3', 'reference_not_implemented')
    profile = stream.get('target_profile')
    if profile is not None:
        require(type(profile) is dict and set(profile) == {'id','revision','source_provenance','review_status'}, 'target_profile_shape')
        require(all(type(profile[k]) is str and bool(profile[k].strip()) for k in ('id','revision','source_provenance')), 'target_profile_provenance')
        require(profile['review_status'] in ('unreviewed','reviewed'), 'target_profile_review_status')
    for key in ('clip', 'source', 'clock'):
        require(type(stream.get(key)) is dict, key)
    sha = stream['clip'].get('observation_sha256')
    require(type(sha) is str and len(sha) == 64 and all(c in '0123456789abcdef' for c in sha), 'observation_sha256')
    require(type(stream.get('frames')) is list and type(stream.get('reps')) is list, 'records')
    frame_ids = []
    frame_map = {}
    previous_time = None
    for f in stream['frames']:
        require(type(f.get('id')) is int and f['id'] >= 0, 'frame_id')
        require(type(f.get('time')) is dict and finite(f['time'].get('seconds')), 'frame_time')
        seconds = f['time']['seconds']
        require(previous_time is None or seconds > previous_time, 'nonmonotonic_time')
        previous_time = seconds
        require(f.get('side') in ('left', 'right', None), 'side')
        require(f.get('view_eligible') is None or type(f['view_eligible']) is bool, 'view')
        confidence = f.get('confidence_h36m')
        require(confidence is None or (type(confidence) is list and len(confidence) == 17 and all(x is None or finite(x) for x in confidence)), 'confidence_h36m')
        joints = f.get('joints')
        require(joints is None or (type(joints) is list and len(joints) == 51 and
                                  all(v is None or finite(v) for v in joints)), 'joints')
        require(type(f.get('invalid_joints', [])) is list and all(type(i) is int and 0 <= i < 17 for i in f.get('invalid_joints', [])) and len(set(f.get('invalid_joints', []))) == len(f.get('invalid_joints', [])), 'invalid_joint_mask')
        require(type(f.get('chain_support', {})) is dict, 'chain_support')
        require(all(v is None or type(v) is bool for v in f.get('chain_support', {}).values()), 'support')
        frame_ids.append(f['id'])
        frame_map[f['id']] = f
    require(len(set(frame_ids)) == len(frame_ids) and frame_ids == sorted(frame_ids), 'duplicate_or_unordered_frame')
    rep_ids = []
    previous_ordinal = -1
    for rep in stream['reps']:
        require(type(rep.get('id')) is int and type(rep.get('ordinal')) is int and rep['id'] >= 1 and rep['ordinal'] >= 1, 'rep_identity')
        require(rep['ordinal'] > previous_ordinal, 'rep_order')
        previous_ordinal = rep['ordinal']
        require(type(rep.get('frame_ids')) is list and all(type(x) is int and x in frame_ids for x in rep['frame_ids']), 'rep_frames')
        require(rep['frame_ids'] == sorted(set(rep['frame_ids'])), 'duplicate_or_unordered_rep_frames')
        interval = rep.get('original_interval')
        require(type(interval) is dict and interval.get('closure') in ('closed', 'half_open'), 'original_interval')
        require(finite(interval.get('start')) and finite(interval.get('end')) and interval['end'] >= interval['start'], 'interval_bounds')
        unit = interval.get('unit')
        require(unit in ('native_frame_index', 'video_ms'), 'interval_unit')
        if unit == 'native_frame_index':
            require(interval['closure'] == 'closed' and type(interval['start']) is int and type(interval['end']) is int, 'native_interval')
            inside = [i for i in frame_ids if interval['start'] <= i <= interval['end']]
        else:
            require(interval['closure'] == 'half_open' and stream['clock'].get('frame_seconds_to_video_ms') == 1000, 'video_ms_mapping_missing')
            inside = [i for i in frame_ids if interval['start'] <= frame_map[i]['time']['seconds']*1000 < interval['end']]
        require(all(i in inside for i in rep['frame_ids']), 'frame_outside_original_interval')
        if rep.get('span_complete') is True:
            require(rep['frame_ids'] == inside and bool(inside), 'incomplete_selection_marked_complete')
            if unit == 'native_frame_index':
                require(inside == list(range(interval['start'], interval['end']+1)), 'missing_interval_frames')
        require(rep.get('runtime', {}).get('state') in STATES, 'runtime_state')
        require(rep.get('delivery', {}).get('state') in ('delivered', 'not_delivered', 'missing'), 'delivery_state')
        rep_ids.append(rep['id'])
    require(len(set(rep_ids)) == len(rep_ids), 'duplicate_rep')
    # Serializability rejects nonfinite numbers anywhere, including provenance/metadata.
    digest(stream)
    return stream
