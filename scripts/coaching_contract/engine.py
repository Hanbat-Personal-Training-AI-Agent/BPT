"""Causal first-three relative depth shadow. No target/normal-form classification."""
from collections import Counter
import math
import statistics
from .contract import RULES, RESULT_SCHEMA, CONFIDENCE_POLICY, digest, finite, validate


def angle(points, chain):
    if points is None:
        return None
    p = [points[3*i:3*i+3] for i in chain]
    if not all(finite(x) for v in p for x in v):
        return None
    # Scale coordinates BEFORE subtraction to prevent finite extreme inputs from
    # overflowing. Normalize vectors separately before dot/cross arithmetic.
    scale = max(abs(x) for v in p for x in v)
    if scale == 0:
        return None
    p = [[x/scale for x in v] for v in p]
    a = [p[0][i]-p[1][i] for i in range(3)]
    b = [p[2][i]-p[1][i] for i in range(3)]
    na, nb = math.hypot(*a), math.hypot(*b)
    if not finite(na) or not finite(nb) or na <= 1e-14 or nb <= 1e-14:
        return None
    dot = sum((x/na)*(y/nb) for x,y in zip(a,b))
    if not finite(dot):
        return None
    return math.degrees(math.acos(max(-1.0, min(1.0, dot))))


def _observe(stream, rep, rule):
    frames = {f['id']: f for f in stream['frames']}
    selected = [frames[i] for i in rep['frame_ids']]
    reasons, values = set(), []
    if not selected:
        reasons.add('no_observations')
    if stream['source'].get('joint_definition') != 'BPT_H36M17':
        reasons.add('joint_definition_unverified')
    if (stream['source'].get('coordinate_frame'), stream['source'].get('pose_units')) not in {
            ('camera_x_right_y_down_z_away_pelvis_relative','h36m17_xs_model_space_no_metric_guarantee'),
            ('gvhmr_world_y_up','model_world_meters')}:
        reasons.add('coordinate_or_units_missing')
    if stream['source'].get('layer_role') != 'assessment':
        reasons.add('assessment_layer_unverified')
    if stream['source'].get('side_policy') != 'actual_per_frame':
        reasons.add('actual_side_history_missing')
    if stream['source'].get('confidence_policy') != CONFIDENCE_POLICY:
        reasons.add('required_chain_confidence_policy_unverified')
    if rep.get('span_complete') is not True:
        reasons.add('span_coverage_unverified')
    if rep.get('source_gaps', 0):
        reasons.add('source_observation_gaps')
    sides = {f.get('side') for f in selected}
    if len(sides) > 1:
        reasons.add('mixed_actual_sides')
    if not any(f.get('phase') == 'bottom' for f in selected):
        reasons.add('bottom_phase_not_observed')
    for f in selected:
        side = f.get('side')
        if side not in rule['joints']:
            reasons.add('side_missing')
            continue
        invalid = f.get('invalid_joints', [])
        value = None if stream['source'].get('joint_definition') != 'BPT_H36M17' or any(j in invalid for j in rule['joints'][side]) else angle(f.get('joints'), rule['joints'][side])
        if value is None:
            reasons.add('required_chain_nonfinite_or_degenerate')
        else:
            values.append(value)
        scores = f.get('confidence_h36m')
        chain = rule['joints'][side]
        if scores is None or any(scores[j] is None for j in chain):
            reasons.add('required_chain_confidence_missing')
        elif any(scores[j] < CONFIDENCE_POLICY['minimum'] for j in chain):
            reasons.add('required_chain_confidence_below_source_threshold')
        support = f.get('chain_support', {}).get(rule['chain'])
        if support is not True:
            reasons.add('required_chain_support_missing' if support is None else 'required_chain_unsupported')
        if f.get('view_eligible') is not True:
            reasons.add('view_missing' if f.get('view_eligible') is None else 'view_ineligible')
        # Preserve actual phases. A scalar over the full rep does not invent a bottom phase.
        if f.get('phase') not in ('top','descending','bottom','ascending'):
            reasons.add('phase_history_missing_or_unknown')
        if f.get('uncertainty_known') is not True:
            reasons.add('uncertainty_provenance_missing')
    return {'minimum_deg': min(values) if values else None,
            'valid_chain_frames': len(values), 'selected_frames': len(selected),
            'side_counts': dict(Counter(str(f.get('side')) for f in selected)),
            'phase_counts': dict(Counter(str(f.get('phase')) for f in selected)),
            'reasons': sorted(reasons)}


def evaluate(stream):
    validate(stream)
    rule = RULES.get(stream.get('exercise'))
    result = {'schema': RESULT_SCHEMA, 'shadow_only': True, 'input_sha256': digest(stream),
              'exercise': stream.get('exercise'), 'clip': stream['clip'], 'source': stream['source'],
              'clock': stream['clock'], 'criterion_scope': 'relative_drift',
              'reference_kind': 'observed_first3', 'reference_correctness': 'not_established',
              'absolute_normality': 'not_assessed', 'target_used': False,
              'target_profile': stream.get('target_profile'), 'reps': []}
    observations = [_observe(stream, r, rule) for r in stream['reps']] if rule else []
    for index, rep in enumerate(stream['reps']):
        out = {'id': rep['id'], 'ordinal': rep['ordinal'], 'original_interval': rep['original_interval'],
               'runtime': rep['runtime'], 'delivery': rep['delivery'],
               'reference_ids': [r['id'] for r in stream['reps'][:3]] if index >= 3 else [],
               'common_scalar': {'value_deg': None, 'observed_subset_predicate': None},
               'qualified_shadow': {'state': 'withheld', 'reasons': []}}
        reasons = set()
        if not rule:
            reasons.add('unsupported_exercise')
        else:
            out['rule'] = rule
            out['observation'] = observations[index]
            reasons.update(observations[index]['reasons'])
            if index < 3:
                reasons.add('collecting_observed_reference')
            else:
                if [r['ordinal'] for r in stream['reps'][:3]] != [1,2,3]:
                    reasons.add('first3_reference_identity_unverified')
                identity = stream.get('first3_reference_identity', {})
                if (type(identity) is not dict or type(identity.get('set_id')) is not str or
                        not identity.get('set_id', '').strip() or
                        type(identity.get('first3_rep_ids')) is not list or
                        not all(type(i) is int for i in identity.get('first3_rep_ids', [])) or
                        identity.get('observation_sha256') != stream['clip']['observation_sha256'] or
                        identity.get('first3_rep_ids') != [r['id'] for r in stream['reps'][:3]] or
                        identity.get('origin') != 'observed_set_start' or not identity.get('set_id')):
                    reasons.add('first3_reference_identity_unverified')
                baseline = observations[:3]
                refs = stream['reps'][:3]
                side_sets = [set(o['side_counts']) for o in baseline + [observations[index]]]
                if not all(x == side_sets[0] for x in side_sets) or len(side_sets[0]) != 1:
                    reasons.add('reference_current_side_mismatch')
                for ref, obs in zip(refs, baseline):
                    reasons.update('reference:' + r for r in obs['reasons'])
                    if (not ref['frame_ids'] or not rep['frame_ids'] or
                            ref['frame_ids'][-1] >= rep['frame_ids'][0]):
                        reasons.add('reference_not_strictly_past')
                minima = [o['minimum_deg'] for o in baseline]
                current = observations[index]['minimum_deg']
                if current is not None and all(v is not None for v in minima):
                    value = current - statistics.median(minima)
                    out['common_scalar'] = {'value_deg': value, 'observed_subset_predicate': value > rule['threshold_deg'],
                                            'baseline_minima_deg': minima, 'baseline_median_deg': statistics.median(minima),
                                            'current_minimum_deg': current, 'threshold_deg': rule['threshold_deg'],
                                            'meaning': 'relative_consistency_only_not_correct_form'}
                else:
                    reasons.add('minimum_unavailable')
        out['qualified_shadow']['reasons'] = sorted(reasons)
        if not reasons:
            predicate = out['common_scalar']['observed_subset_predicate']
            out['qualified_shadow']['state'] = 'warning' if predicate else 'no_warning'
        result['reps'].append(out)
    return result


def compare(left, right):
    """Comparison eligibility is stricter than having two numeric scalars."""
    reasons = []
    if left.get('exercise') not in RULES or right.get('exercise') not in RULES:
        reasons.append('unsupported_exercise')
    for name in ('exercise', 'criterion_scope', 'reference_kind'):
        if left.get(name) != right.get(name):
            reasons.append(name + '_mismatch')
    a, b = left['clip'].get('media_sha256'), right['clip'].get('media_sha256')
    if not a or not b:
        reasons.append('media_identity_missing')
    elif a != b:
        reasons.append('different_media_bytes')
    if left['clock'] != right['clock']:
        reasons.append('clock_mapping_unverified')
    for name in ('joint_definition','coordinate_frame','pose_units','layer_role','side_policy'):
        if left['source'].get(name) != right['source'].get(name):
            reasons.append(name + '_source_mismatch')
    source_equal = left['source'] == right['source']
    rows = []
    lmap = {r['id']: r for r in left['reps']}
    rmap = {r['id']: r for r in right['reps']}
    for rep_id in sorted(set(lmap) | set(rmap)):
        l, r = lmap.get(rep_id), rmap.get(rep_id)
        row_reasons = list(reasons)
        if l is None or r is None:
            row_reasons.append('counterpart_missing')
        elif l['original_interval'] != r['original_interval']:
            row_reasons.append('original_interval_mismatch')
        lv = l['common_scalar']['value_deg'] if l else None
        rv = r['common_scalar']['value_deg'] if r else None
        rows.append({'id': rep_id, 'left': l, 'right': r,
                     'descriptive_delta_deg': lv-rv if lv is not None and rv is not None else None,
                     'comparison_state': 'withheld' if row_reasons else 'descriptive_only',
                     'reasons': row_reasons})
    return {'schema': 'bpt.coaching-shadow-comparison.v1', 'shadow_only': True,
            'same_source_provenance': source_equal, 'same_pose_asserted': False,
            'ground_truth': False, 'semantic_parity_asserted': False, 'reps': rows}
