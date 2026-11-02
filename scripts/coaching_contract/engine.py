"""Causal first-three relative depth shadow. No target/normal-form classification."""
from collections import Counter
import math
import statistics
from .contract import RULES, RESULT_SCHEMA, digest, finite, validate


def angle(points, chain):
    if points is None:
        return None
    p = [points[3*i:3*i+3] for i in chain]
    if not all(finite(x) for v in p for x in v):
        return None
    a = [p[0][i]-p[1][i] for i in range(3)]
    b = [p[2][i]-p[1][i] for i in range(3)]
    na, nb = math.sqrt(sum(x*x for x in a)), math.sqrt(sum(x*x for x in b))
    if na <= 1e-10 or nb <= 1e-10:
        return None
    return math.degrees(math.acos(max(-1.0, min(1.0, sum(x*y for x, y in zip(a,b))/(na*nb)))))


def _observe(stream, rep, rule):
    frames = {f['id']: f for f in stream['frames']}
    selected = [frames[i] for i in rep['frame_ids']]
    reasons, values = set(), []
    if not selected:
        reasons.add('no_observations')
    if stream['source'].get('joint_definition') != 'BPT_H36M17':
        reasons.add('joint_definition_unverified')
    if not stream['source'].get('coordinate_frame') or not stream['source'].get('pose_units'):
        reasons.add('coordinate_or_units_missing')
    if stream['source'].get('layer_role') != 'assessment':
        reasons.add('assessment_layer_unverified')
    if stream['source'].get('side_policy') != 'actual_per_frame':
        reasons.add('actual_side_history_missing')
    if rep.get('span_complete') is not True:
        reasons.add('span_coverage_unverified')
    if rep.get('source_gaps', 0):
        reasons.add('source_observation_gaps')
    for f in selected:
        side = f.get('side')
        if side not in rule['joints']:
            reasons.add('side_missing')
            continue
        value = angle(f.get('joints'), rule['joints'][side])
        if value is None:
            reasons.add('required_chain_nonfinite_or_degenerate')
        else:
            values.append(value)
        support = f.get('chain_support', {}).get(rule['chain'])
        if support is not True:
            reasons.add('required_chain_support_missing' if support is None else 'required_chain_unsupported')
        if f.get('view_eligible') is not True:
            reasons.add('view_missing' if f.get('view_eligible') is None else 'view_ineligible')
        # Preserve actual phases. A scalar over the full rep does not invent a bottom phase.
        if f.get('phase') is None:
            reasons.add('phase_history_missing')
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
                baseline = observations[:3]
                refs = stream['reps'][:3]
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
    source_equal = left['source'] == right['source']
    rows = []
    rmap = {r['id']: r for r in right['reps']}
    for l in left['reps']:
        r = rmap.get(l['id'])
        row_reasons = list(reasons)
        if r is None:
            row_reasons.append('counterpart_missing')
        elif l['original_interval'] != r['original_interval']:
            row_reasons.append('original_interval_mismatch')
        lv = l['common_scalar']['value_deg']
        rv = r['common_scalar']['value_deg'] if r else None
        # Numeric comparison remains descriptive even across sources. It cannot assert parity.
        rows.append({'id': l['id'], 'left': l, 'right': r,
                     'descriptive_delta_deg': lv-rv if lv is not None and rv is not None else None,
                     'comparison_state': 'withheld' if row_reasons else 'descriptive_only',
                     'reasons': row_reasons})
    return {'schema': 'bpt.coaching-shadow-comparison.v1', 'shadow_only': True,
            'same_source_provenance': source_equal, 'same_pose_asserted': False,
            'ground_truth': False, 'semantic_parity_asserted': False, 'reps': rows}
