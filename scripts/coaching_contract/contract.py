"""Versioned, numeric-only shadow contract with explicit missing evidence."""
import hashlib
import json
import math

SCHEMA = 'bpt.coaching-shadow-evidence.v1'
RESULT_SCHEMA = 'bpt.coaching-shadow-result.v1'
RULES = {
    'pushup': {'native': 'pushup_shallow', 'deep': 'pushup_depth_drift', 'chain': 'elbow',
               'joints': {'left': (11, 12, 13), 'right': (14, 15, 16)}, 'threshold_deg': 15.0},
    'squat': {'native': 'squat_shallow', 'deep': 'squat_depth_drift', 'chain': 'knee',
              'joints': {'left': (4, 5, 6), 'right': (1, 2, 3)}, 'threshold_deg': 15.0},
}
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
    for key in ('clip', 'source', 'clock'):
        require(type(stream.get(key)) is dict, key)
    sha = stream['clip'].get('observation_sha256')
    require(type(sha) is str and len(sha) == 64 and all(c in '0123456789abcdef' for c in sha), 'observation_sha256')
    require(type(stream.get('frames')) is list and type(stream.get('reps')) is list, 'records')
    frame_ids = []
    previous_time = None
    for f in stream['frames']:
        require(type(f.get('id')) is int and f['id'] >= 0, 'frame_id')
        require(type(f.get('time')) is dict and finite(f['time'].get('seconds')), 'frame_time')
        seconds = f['time']['seconds']
        require(previous_time is None or seconds > previous_time, 'nonmonotonic_time')
        previous_time = seconds
        require(f.get('side') in ('left', 'right', None), 'side')
        require(f.get('view_eligible') is None or type(f['view_eligible']) is bool, 'view')
        joints = f.get('joints')
        require(joints is None or (type(joints) is list and len(joints) == 51 and
                                  all(v is None or finite(v) for v in joints)), 'joints')
        require(type(f.get('chain_support', {})) is dict, 'chain_support')
        require(all(v is None or type(v) is bool for v in f.get('chain_support', {}).values()), 'support')
        frame_ids.append(f['id'])
    require(len(set(frame_ids)) == len(frame_ids) and frame_ids == sorted(frame_ids), 'duplicate_or_unordered_frame')
    rep_ids = []
    previous_ordinal = -1
    for rep in stream['reps']:
        require(type(rep.get('id')) is int and type(rep.get('ordinal')) is int, 'rep_identity')
        require(rep['ordinal'] > previous_ordinal, 'rep_order')
        previous_ordinal = rep['ordinal']
        require(type(rep.get('frame_ids')) is list and all(type(x) is int and x in frame_ids for x in rep['frame_ids']), 'rep_frames')
        require(rep['frame_ids'] == sorted(set(rep['frame_ids'])), 'duplicate_or_unordered_rep_frames')
        interval = rep.get('original_interval')
        require(type(interval) is dict and interval.get('closure') in ('closed', 'half_open'), 'original_interval')
        require(finite(interval.get('start')) and finite(interval.get('end')) and interval['end'] >= interval['start'], 'interval_bounds')
        require(rep.get('runtime', {}).get('state') in STATES, 'runtime_state')
        require(rep.get('delivery', {}).get('state') in ('delivered', 'not_delivered', 'missing'), 'delivery_state')
        rep_ids.append(rep['id'])
    require(len(set(rep_ids)) == len(rep_ids), 'duplicate_rep')
    # Serializability rejects nonfinite numbers anywhere, including provenance/metadata.
    digest(stream)
    return stream
