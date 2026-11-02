"""Typed JSON atom/group contract. No eval, model, thresholds, I/O or app wiring.
positive_evidence means the supplied comparator holds in its explicitly labelled
reference scope, never that an exercise is globally correct or unsafe.
"""
from __future__ import annotations
from dataclasses import dataclass
import copy
import math
from statistics import median
from typing import Any, Literal
from .catalog import CATALOG, CATALOG_VERSION

State = Literal['positive_evidence','negative_evidence','unknown','not_applicable']
KINDS = {'explicit_target':'scoped_target_predicate', 'engineering_candidate':'candidate_predicate', 'observed_first3':'relative_change_predicate'}
IDENTITY = ('metricId','metricVersion','definitionHash','unit','coordinate','aggregation')
CONTEXT = ('sourceIdentity','timeBasis','startPts','endPts','phase','side','selectedSide','view')
SOURCE_IDENTITY = ('inputSha256','sourceCommit','modelSha256','epoch','clockId')
PHASES = ('top','bottom','descending','ascending','pulling','lowering','rising','set','rep')
SIDES = ('left','right','bilateral')
VIEWS = ('side','front','oblique')

@dataclass(frozen=True)
class Atom:
    id: str
    observation: str
    profile: str | None = None

@dataclass(frozen=True)
class Group:
    id: str
    op: Literal['AND','OR']
    children: tuple[Atom | Group, ...]
    pairing: dict


def finite(x): return type(x) in (int,float) and math.isfinite(x)
def unique(values): return list(dict.fromkeys(values))
def identity(o): return {k:o.get(k) for k in IDENTITY}
def context(o):
    scope=o.get('scope',{}) if isinstance(o,dict) else {}
    return {k:scope.get(k) for k in CONTEXT} if isinstance(scope,dict) else {}

def parse(node):
    if not isinstance(node,dict) or not isinstance(node.get('id'),str): raise ValueError('criterion id required')
    if node.get('type')=='atom' and isinstance(node.get('observation'),str):
        if node.get('profile') is not None and not isinstance(node['profile'],str):raise ValueError('profile id must be string or null')
        return Atom(node['id'],node['observation'],node.get('profile'))
    if node.get('type')=='group' and node.get('op') in ('AND','OR') and isinstance(node.get('children'),list) and node['children']:
        return Group(node['id'],node['op'],tuple(parse(x) for x in node['children']),node.get('pairing',{}))
    raise ValueError('invalid typed criterion')


def predicate(value, profile):
    op=profile['comparator'];lo=profile.get('lower');hi=profile.get('upper')
    return {'gt':lambda:value>hi,'gte':lambda:value>=hi,'lt':lambda:value<lo,'lte':lambda:value<=lo,
            'inside':lambda:lo<=value<=hi,'outside':lambda:value<lo or value>hi}[op]()


def bounds_valid(p):
    op=p.get('comparator')
    if op in ('gt','gte'): return finite(p.get('upper'))
    if op in ('lt','lte'): return finite(p.get('lower'))
    return op in ('inside','outside') and finite(p.get('lower')) and finite(p.get('upper')) and p['lower']<=p['upper']


def coverage(o, samples):
    scope=o.get('scope',{});expected=scope.get('expectedSourceIndices')
    indices=[s.get('sourceIndex') for s in samples]
    evidence=scope.get('coverageEvidence',{})
    return (isinstance(evidence,dict) and evidence.get('phaseStartObserved') is True and evidence.get('phaseEndObserved') is True and isinstance(evidence.get('membershipSource'),str) and bool(evidence['membershipSource']) and scope.get('coverageComplete') is True and isinstance(expected,list) and bool(expected)
            and all(type(i) is int for i in expected) and expected==indices
            and len(set(indices))==len(indices) and all(s.get('available') is True and finite(s.get('value')) and not s.get('flush',False) for s in samples)
            and all(indices[i]+1==indices[i+1] for i in range(len(indices)-1)))


def sample_reasons(o, samples):
    scope=o.get('scope',{});reasons=[]
    source=scope.get('sourceIdentity',{})
    if not isinstance(source,dict) or any(not isinstance(source.get(k),str) or not source.get(k) for k in SOURCE_IDENTITY):reasons.append('complete_source_identity_required')
    if scope.get('selectedSide') not in SIDES:reasons.append('selected_side_required')
    if scope.get('timeBasis')!='source_pts_seconds': reasons.append('source_pts_time_basis_required')
    if not finite(scope.get('startPts')) or not finite(scope.get('endPts')) or scope.get('startPts',0)>scope.get('endPts',0): reasons.append('invalid_window_boundaries')
    if scope.get('phase') not in PHASES or scope.get('side') not in SIDES or scope.get('view') not in VIEWS: reasons.append('unknown_observation_context')
    indices=[s.get('sourceIndex') for s in samples]
    if any(type(i) is not int or i<0 for i in indices) or len(set(indices))!=len(indices) or any(indices[i]>=indices[i+1] for i in range(len(indices)-1)): reasons.append('invalid_or_duplicate_source_indices')
    previous=None
    for s in samples:
        t=s.get('pts')
        if not finite(t) or finite(previous) and t<=previous: reasons.append('nonmonotonic_or_invalid_source_pts')
        if finite(t) and finite(scope.get('startPts')) and finite(scope.get('endPts')) and not scope['startPts']<=t<=scope['endPts']: reasons.append('sample_outside_window')
        if s.get('flush',False): reasons.append('flush_sample_not_observation')
        if any(s.get(k)!=scope.get(k) for k in ('side','phase','view')): reasons.append('context_transition_in_window')
        previous=t if finite(t) else None
    return unique(reasons)


def assess(atom, request, observations, profiles):
    o=observations.get(atom.observation);p=profiles.get(atom.profile)
    out={'id':atom.id,'type':'atom','state':'unknown','reasons':[],'observationId':atom.observation,
         'observed':copy.deepcopy(o),'profileId':atom.profile,'profile':copy.deepcopy(p),'partialCoverage':False,
         'interpretation':'unresolved','scope':context(o or {}),'knownComponents':[]}
    r=out['reasons']
    if o is None:r.append('missing_observation');return out
    if not isinstance(o,dict):r.append('malformed_observation');return out
    if not isinstance(o.get('scope'),dict):r.append('malformed_observation_scope');return out
    spec=CATALOG.get(o.get('metricId')) if isinstance(o.get('metricId'),str) else None
    if spec is None:r.append('unknown_metric_definition')
    elif request.get('exercise') not in spec.exercises:
        out['state']='not_applicable';r.append('metric_not_applicable_to_exercise');return out
    if o.get('metricId')=='trunkInclineDeg' and (not isinstance(o.get('support'),dict) or o['support'].get('gravitySynchronized') is not True):r.append('synchronized_source_gravity_required')
    if spec:
        contract=spec.contract()
        for key,expected in [('metricVersion',spec.version),('definitionHash',contract['definitionHash']),('unit',spec.unit),('coordinate',spec.coordinate)]:
            if o.get(key)!=expected:r.append('observation_'+key+'_mismatch')
    if o.get('aggregation') not in ('sample','max','min','rom','delta'):r.append('unsupported_aggregation')
    if o.get('available') is not True:r.append('observation_unavailable')
    blocking=o.get('blockingReasons',[])
    if not isinstance(blocking,list) or not all(isinstance(x,str) for x in blocking):r.append('invalid_blocking_reasons')
    else:r.extend(blocking)
    samples=o.get('samples',[])
    if not isinstance(samples,list) or any(not isinstance(x,dict) for x in samples):samples=[];r.append('invalid_samples')
    r.extend(sample_reasons(o,samples))
    evaluation=request.get('evaluation',{})
    if not isinstance(evaluation,dict) or evaluation.get('mode') not in ('causal','offline_declared') or not finite(evaluation.get('asOfPts')):r.append('explicit_evaluation_clock_required')
    elif not finite(o.get('scope',{}).get('endPts')) or o['scope']['endPts']>evaluation['asOfPts']:r.append('future_observation_window')
    if not samples:r.append('actual_samples_required')
    support=o.get('support',{})
    if not isinstance(support,dict):support={}
    for check in ('requiredJointsSupported','trackingObserved','rawCorrectionChecked'):
        if support.get(check) is not True:r.append('support_'+check+'_required')
    max_correction=support.get('maximumCorrectionDifference')
    if not finite(max_correction) or max_correction<0:r.append('explicit_correction_limit_required')
    sample_evidence=[]
    for sample in samples:
        why=[]
        if sample.get('available') is not True:why.append('sample_unavailable')
        blocking=sample.get('blockingReasons',[])
        if not isinstance(blocking,list) or not all(isinstance(x,str) for x in blocking):why.append('invalid_sample_blocking_reasons')
        else:why.extend(blocking)
        raw,corrected=sample.get('rawValue'),sample.get('value')
        if type(raw) is bool or type(corrected) is bool:r.append('boolean_numeric_sample_rejected')
        if not finite(raw) or not finite(corrected):why.append('invalid_supported_raw_or_corrected_sample')
        elif finite(max_correction) and abs(raw-corrected)>max_correction:why.append('raw_correction_disagreement')
        sample_evidence.append({'sourceIndex':sample.get('sourceIndex'),'pts':sample.get('pts'),'supported':not why,'reasons':why})
    out['sampleEvidence']=sample_evidence
    if p is None:r.append('profile_required');return out
    if not isinstance(p,dict):r.append('malformed_profile');return out
    out['profileIntegrityHash']=__import__('hashlib').sha256(__import__('json').dumps(p,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    out['predicateMeaning']=p.get('predicateMeaning')
    if p.get('predicateMeaning') not in ('deviation','desired_match'):r.append('predicate_meaning_required')
    kind=p.get('referenceKind');out['interpretation']=KINDS.get(kind,'unresolved') if isinstance(kind,str) else 'unresolved'
    if not isinstance(kind,str) or kind not in KINDS:r.append('unresolved_reference_kind')
    for key in IDENTITY:
        if p.get(key)!=o.get(key):r.append('profile_'+key+'_mismatch')
    for key in ('exercise','variant'):
        if p.get(key)!=request.get(key):r.append('profile_'+key+'_mismatch')
    if p.get('ruleId')!=atom.id:r.append('profile_rule_mismatch')
    if not isinstance(p.get('revision'),str) or not p.get('revision'):r.append('profile_revision_required')
    if not isinstance(p.get('source'),str) or not p.get('source'):r.append('profile_source_required')
    confirmation=p.get('confirmation',{});review=confirmation.get('scope',{}) if isinstance(confirmation,dict) else {}
    if not isinstance(confirmation,dict) or any(not isinstance(confirmation.get(k),str) or not confirmation.get(k) for k in ('kind','at','reference')):r.append('confirmation_metadata_required')
    expected_review={**identity(o),'exercise':request.get('exercise'),'variant':request.get('variant'),'ruleId':atom.id}
    if not isinstance(review,dict) or any(review.get(k)!=v for k,v in expected_review.items()):r.append('review_scope_mismatch_or_missing')
    for key in ('phase','side','view'):
        applicability=p.get('applicability',{})
        allowed=applicability.get(key) if isinstance(applicability,dict) else None
        enum={'phase':PHASES,'side':SIDES,'view':VIEWS}[key]
        if not isinstance(allowed,list) or not allowed or any(x not in enum for x in allowed):r.append('profile_'+key+'_scope_required')
        elif o.get('scope',{}).get(key) not in allowed:
            r.append('outside_profile_'+key+'_scope')
    if not bounds_valid(p):r.append('invalid_or_nonfinite_bounds')
    start=o.get('scope',{}).get('startPts')
    if not finite(p.get('availableAtPts')) or not finite(start) or p['availableAtPts']>start:r.append('future_or_unknown_profile_availability')
    offset=0
    if kind=='observed_first3':
        refs=p.get('references',[]);valid=isinstance(refs,list) and len(refs)==3 and all(isinstance(x,dict) for x in refs)
        if valid:
            ids=[x.get('id') for x in refs];ends=[x.get('endPts') for x in refs]
            valid=(all(isinstance(x,str) and x for x in ids) and len(set(ids))==3 and all(finite(t) for t in ends)
                   and all(type(x.get('repIndex')) is int for x in refs) and [x.get('repIndex') for x in refs]==[1,2,3] and ends==sorted(ends) and all(ends[i]<ends[i+1] for i in range(2)) and finite(start) and ends[-1]<start
                   and all(finite(x.get('value')) and x.get('available') is True and x.get('coverageComplete') is True
                           and identity(x)==identity(o) and isinstance(x.get('context'),dict) and all(x['context'].get(k)==o.get('scope',{}).get(k) for k in ('sourceIdentity','selectedSide','side','phase','view')) for x in refs))
        if not valid:r.append('invalid_incomplete_or_future_first3_reference')
        else:offset=median(x['value'] for x in refs);out['referenceIds']=[x['id'] for x in refs];out['referenceValue']=offset
    out['reasons']=unique(r)
    if r:
        if all(x.startswith('outside_profile_') for x in r):out['state']='not_applicable'
        return out
    good=[s for s,e in zip(samples,sample_evidence) if e['supported']]
    full=coverage(o,samples) and len(good)==len(samples);out['partialCoverage']=not full
    if not good:out['reasons'].append('no_supported_actual_sample');return out
    aggregation=o['aggregation'];values=[s['value'] for s in good]
    if aggregation in ('min','rom','delta') and not full:
        out['reasons'].append('complete_phase_span_required');return out
    if aggregation=='sample' and len(samples)!=1:out['reasons'].append('sample_aggregation_requires_one_sample');return out
    value={'sample':lambda:values[-1],'max':lambda:max(values),'min':lambda:min(values),'rom':lambda:max(values)-min(values),'delta':lambda:values[-1]-values[0]}[aggregation]()-offset
    if not finite(value) or any(not finite(x-offset) for x in values) or not finite(o['scope']['endPts']-o['scope']['startPts']):out['reasons'].append('arithmetic_overflow');return out
    out['evaluatedValue']=value
    out['aggregation']=aggregation
    out['sampleMembership']=[{'sourceIndex':x['sourceIndex'],'pts':x['pts']} for x in samples]
    out['supportedPositiveSamples']=[{'sourceIndex':x['sourceIndex'],'pts':x['pts']} for x in good if predicate(x['value']-offset,p)]
    result=predicate(value,p)
    # Partial max supports an existential threshold exceedance, never a bounded/negative claim.
    if aggregation=='max' and not full and not (result and p['comparator'] in ('gt','gte')):
        out['reasons'].append('complete_span_required_for_max_nonpositive_or_bounded_claim');out['reasons'].extend(unique([reason for e in sample_evidence for reason in e['reasons']]));return out
    sustain=p.get('sustainSeconds',0)
    if not finite(sustain) or sustain<0:out['reasons'].append('invalid_sustain_duration');return out
    if sustain:
        if aggregation not in ('sample','max'):out['reasons'].append('sustain_requires_sample_predicate');return out
        gap=p.get('maximumGapSeconds')
        if not finite(gap) or gap<=0:out['reasons'].append('explicit_maximum_gap_required');return out
        longest=0;begin=None;previous=None;run=[];qualifying=[]
        for s,e in zip(samples,sample_evidence):
            valid=e['supported'] and predicate(s['value']-offset,p)
            contiguous=previous is not None and s['pts']-previous['pts']<=gap and type(s.get('sourceIndex')) is int and type(previous.get('sourceIndex')) is int and s['sourceIndex']==previous['sourceIndex']+1
            if not valid or not contiguous:
                if run and run[-1]['pts']-run[0]['pts']>=sustain:qualifying.extend(run)
                run=[];begin=None
            if valid:
                if begin is None:begin=s['pts']
                run.append(s)
            if begin is not None:longest=max(longest,s['pts']-begin)
            previous=s
        if run and run[-1]['pts']-run[0]['pts']>=sustain:qualifying.extend(run)
        out['supportedPositiveSamples']=[{'sourceIndex':x['sourceIndex'],'pts':x['pts']} for x in qualifying]
        out['supportedDurationSeconds']=longest;result=longest>=sustain
        has_gap=any(samples[i+1]['pts']-samples[i]['pts']>gap or samples[i+1]['sourceIndex']!=samples[i]['sourceIndex']+1 for i in range(len(samples)-1))
        if not result and (not full or has_gap or o['scope']['endPts']-o['scope']['startPts']<sustain):out['reasons'].append('incomplete_sustain_coverage');return out
    out['state']='positive_evidence' if result else 'negative_evidence'
    return out


def evaluate(request:dict[str,Any])->dict[str,Any]:
    """Pure JSON-compatible evaluation. Provided observations are always retained."""
    if not isinstance(request,dict):raise ValueError('request must be an object')
    observations=request.get('observations',{});profiles=request.get('profiles',{})
    if not isinstance(observations,dict) or not isinstance(profiles,dict):raise ValueError('observations/profiles must be objects')
    def reject_nonfinite(value):
        if isinstance(value,float) and not math.isfinite(value):raise ValueError('nonfinite JSON number rejected before decision')
        if isinstance(value,dict):
            for child in value.values():reject_nonfinite(child)
        if isinstance(value,list):
            for child in value:reject_nonfinite(child)
    reject_nonfinite(request)
    def raw_budget(node,depth=0,count=None):
        if count is None:count=[0]
        count[0]+=1
        if depth>16 or count[0]>128:raise ValueError('criterion structural budget exceeded')
        if isinstance(node,dict) and isinstance(node.get('children'),list):
            for child in node['children']:raw_budget(child,depth+1,count)
    raw_budget(request['criterion'])
    tree=parse(request['criterion'])
    seen=set()
    def check_ids(node,depth=0):
        if depth>16:raise ValueError('criterion depth budget exceeded')
        if len(seen)>=128:raise ValueError('criterion node budget exceeded')
        if not node.id or node.id in seen:raise ValueError('empty or duplicate criterion id')
        seen.add(node.id)
        if isinstance(node,Group):
            for child in node.children:check_ids(child,depth+1)
    check_ids(tree)
    def visit(node):
        if isinstance(node,Atom):return assess(node,request,observations,profiles)
        children=[visit(x) for x in node.children];active=[x for x in children if x['state']!='not_applicable'];states=[x['state'] for x in active]
        reasons=[];scope=active[0]['scope'] if active else None
        pairing=node.pairing
        valid_pairing=isinstance(pairing,dict) and pairing.get('sidePolicy') in ('same_selected_side','bilateral') and pairing.get('temporal') in ('simultaneous','same_window_summary')
        def compatible_scope(other):
            if scope is None or not isinstance(other,dict):return False
            keys=CONTEXT if pairing.get('sidePolicy')!='bilateral' else tuple(k for k in CONTEXT if k!='side')
            return all(other.get(k)==scope.get(k) for k in keys)
        compatible=valid_pairing and all(compatible_scope(x['scope']) for x in active)
        if compatible and pairing.get('temporal')=='same_window_summary':
            compatible=bool(active[0].get('sampleMembership')) and all(x.get('sampleMembership')==active[0].get('sampleMembership') for x in active)
        if node.op=='AND' and not valid_pairing:reasons.append('explicit_component_pairing_required')
        common=None
        if compatible and pairing.get('temporal')=='simultaneous':
            def summary_evidence(x):
                if x.get('type')=='atom':return x.get('aggregation') not in ('sample','max')
                return any(summary_evidence(child) for child in x.get('children',[]) if child['state']=='positive_evidence')
            if any(summary_evidence(x) for x in active):
                compatible=False;reasons.append('summary_metric_requires_same_window_contract')
            for child in active:
                samples={(x['sourceIndex'],x['pts']) for x in child.get('supportedPositiveSamples',[])}
                common=samples if common is None else common & samples
        known_scopes=[x['scope'] for x in active if isinstance(x.get('scope'),dict) and isinstance(x['scope'].get('sourceIdentity'),dict) and all(isinstance(x['scope']['sourceIdentity'].get(k),str) and x['scope']['sourceIdentity'].get(k) for k in SOURCE_IDENTITY)]
        compare_keys=tuple(k for k in CONTEXT if not (isinstance(pairing,dict) and pairing.get('sidePolicy')=='bilateral' and k=='side'))
        known_conflict=bool(known_scopes) and any(any(other.get(k)!=known_scopes[0].get(k) for k in compare_keys) for other in known_scopes[1:])
        if known_conflict:reasons.append('conflicting_known_component_contexts')
        membership_children=[x for x in active if x['state']=='positive_evidence'] if node.op=='OR' and not known_conflict else active
        membership=membership_children[0].get('sampleMembership') if membership_children else None
        if not membership or any(x.get('sampleMembership')!=membership for x in membership_children):membership=None
        if not active:state='not_applicable'
        elif node.op=='AND':
            if not compatible:state='unknown';reasons.append('noncoincident_component_scopes')
            elif 'negative_evidence' in states:state='negative_evidence'
            elif all(s=='positive_evidence' for s in states):
                if pairing['temporal']=='simultaneous' and not common:state='unknown';reasons.append('no_shared_supported_positive_sample')
                else:state='positive_evidence'
            else:state='unknown'
        else:
            state=('unknown' if known_conflict else 'positive_evidence' if 'positive_evidence' in states else 'negative_evidence' if compatible and all(s=='negative_evidence' for s in states) else 'unknown')
        return {'id':node.id,'type':'group','op':node.op,'state':state,'scope':scope if compatible else known_scopes[0] if known_scopes and not known_conflict and node.op=='OR' else None,'reasons':reasons,
                'partialCoverage':not compatible or any(x['state']=='unknown' or x.get('partialCoverage') for x in children),
                'sampleMembership':membership,'interpretation':'compound_supplied_predicates_only','predicateMeanings':unique([x.get('predicateMeaning','compound') for x in children]),'pairing':copy.deepcopy(pairing),'sharedPositiveSamples':[{'sourceIndex':i,'pts':t} for i,t in sorted(common or [])],'supportedPositiveSamples':[{'sourceIndex':i,'pts':t} for i,t in sorted(common or [])] if state=='positive_evidence' and node.op=='AND' else [sample for child in children if child['state']=='positive_evidence' for sample in child.get('supportedPositiveSamples',[])] if compatible or node.op=='OR' and not known_conflict else [],'children':children,'knownComponents':[x['id'] for x in children if x['state'] in ('positive_evidence','negative_evidence')]}
    result=visit(tree)
    return {'schema':'bpt.coaching-criteria.v1','catalogVersion':CATALOG_VERSION,'exercise':request.get('exercise'),'variant':request.get('variant'),
            'criterion':result,'providedObservations':copy.deepcopy(observations),'profileAuthority':'scoped_reference_only_not_whole_form_or_clinical_validation'}
