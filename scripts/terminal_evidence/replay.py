"""Strict numeric terminal-window diagnostic. No retiming, GT, inference or score changes."""
import argparse
import hashlib
import json
import math
from pathlib import Path

SCHEMA = 'bpt.terminal-evidence.v1'
KINDS = {'terminal_header', 'terminal_start', 'terminal_frame', 'terminal_rep', 'terminal_end', 'terminal_capped'}
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
        epoch = row.get('epoch')
        require(integer(epoch), 'epoch')
        if kind == 'terminal_start':
            require(active is None and epoch not in epochs, 'overlapping_or_reused_epoch')
            require(row.get('time_basis') == 'sample_pts_seconds' and row.get('raw_source') == 'xs_output_before_constraints', 'clock_or_raw_provenance')
            require(integer(row.get('lookahead')) and integer(row.get('cadence')) and row['cadence'] >= 1 and row['lookahead'] + row['cadence'] <= 27, 'model_window')
            require(row.get('exercise') in ('squat', 'pushUp', 'pushup', 'benchPress', 'barbellRow', 'deadlift'), 'exercise')
            row['provenance'] = header['provenance']
            epochs[epoch] = {'start': row, 'frames': [], 'reps': [], 'end': None}
            active = epoch
            continue
        require(active == epoch, 'stale_or_unstarted_epoch')
        data = epochs[epoch]
        if kind == 'terminal_end':
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
