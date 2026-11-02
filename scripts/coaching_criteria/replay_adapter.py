"""Profile-free preservation/coverage bridge for coaching_observation_evidence.v1.
Only exact pinned source definitions map into the criteria catalog. Does not
recompute geometry, infer a target, train, label form, or erase original metrics.
"""
import copy
import hashlib
import json
from pathlib import Path
from .catalog import CATALOG
from .engine import evaluate

PINNED = json.loads(Path(__file__).with_name('replay_catalog_v1.json').read_text())


def frame_request(frame, input_sha256, source_commit=None, model_sha256=None):
    source=frame['source'];context=frame['context'];observations={};children=[]
    exercise={'barbell_row':'barbell-row','row':'barbell-row'}.get(context.get('exercise'),context.get('exercise'))
    for name,metric in frame['metrics'].items():
        original=copy.deepcopy(metric);spec=CATALOG.get(name);expected=PINNED.get(name)
        matched=expected is not None and all(metric.get(k)==v for k,v in expected.items())
        contract=spec.contract() if spec else {}
        t=source.get('source_pts');index=source.get('source_index')
        phase=context.get('phase');side=context.get('side');view='side' if context.get('side_view') is True else 'front' if context.get('side_view') is False else 'unknown'
        reasons=list(metric.get('reasons',[]))
        if not matched:reasons.append('replay_definition_mismatch')
        # profile-free mapping preserves values without asserting support checks or model identity absent from this export.
        observations[name]={'metricId':name,'metricVersion':contract.get('version'),'definitionHash':contract.get('definitionHash'),
            'unit':metric.get('unit'),'coordinate':metric.get('coordinateSpace'),'aggregation':'sample',
            'available':metric.get('available'),'blockingReasons':reasons,'rawValue':metric.get('rawValue'),'correctedValue':metric.get('value'),
            'originalReplayMetric':original,'sourceBindingExact':matched,
            'scope':{'sourceIdentity':{'inputSha256':input_sha256,'sourceCommit':source_commit,'modelSha256':model_sha256,'epoch':str(source.get('epoch'))+':'+str(exercise),'clockId':'original-source-PTS'},
                'timeBasis':'source_pts_seconds' if source.get('time_basis')=='sample_pts_seconds' else source.get('time_basis'),
                'startPts':t,'endPts':t,'phase':phase,'side':side,'selectedSide':side,'view':view,'coverageComplete':True,'expectedSourceIndices':[index]},
            'samples':[{'sourceIndex':index,'pts':t,'value':metric.get('value'),'rawValue':metric.get('rawValue'),'available':metric.get('available'),
                'blockingReasons':reasons,'side':side,'phase':phase,'view':view,'flush':context.get('flush_tail',False)}],
            'support':{'gravitySynchronized':context.get('gravitySynchronized')}}
        children.append({'type':'atom','id':name,'observation':name})
    return {'evaluation':{'mode':'causal','asOfPts':source.get('source_pts')},'exercise':exercise,'variant':'unconfirmed','observations':observations,'profiles':{},
            'criterion':{'type':'group','id':'profile_free_coverage','op':'OR','children':children}}


def summarize(path):
    path=Path(path);before=hashlib.sha256(path.read_bytes()).hexdigest();summary={}
    for line in path.open():
        frame=json.loads(line)
        result=evaluate(frame_request(frame,before))
        case=summary.setdefault(result['exercise'],{'frames':0,'genuineFrames':0,'flushFrames':0,'metrics':{}});case['frames']+=1
        flush=frame['context'].get('flush_tail',False);case['flushFrames']+=bool(flush);case['genuineFrames']+=not flush
        for name,o in result['providedObservations'].items():
            a=case['metrics'].setdefault(name,{'opportunities':0,'genuineOpportunities':0,'genuineCorrectedFinite':0,'providedRawFinite':0,'providedCorrectedFinite':0,'originalAvailable':0,'sourceDefinitionMatched':0,'criterionStates':{},'criterionReasons':{}})
            from .engine import finite
            a['genuineOpportunities']+=not flush;a['genuineCorrectedFinite']+=not flush and finite(o.get('correctedValue'));a['opportunities']+=1;a['providedRawFinite']+=finite(o.get('rawValue'));a['providedCorrectedFinite']+=finite(o.get('correctedValue'));a['originalAvailable']+=o.get('available') is True;a['sourceDefinitionMatched']+=o['sourceBindingExact']
        for d in result['criterion']['children']:
            a=case['metrics'][d['observationId']];a['criterionStates'][d['state']]=a['criterionStates'].get(d['state'],0)+1
            for reason in d['reasons']:a['criterionReasons'][reason]=a['criterionReasons'].get(reason,0)+1
    after=hashlib.sha256(path.read_bytes()).hexdigest()
    if before!=after:raise RuntimeError('original replay changed')
    return {'schema':'bpt.coaching-criteria-profile-free-coverage.v1','inputSHA256':before,'originalUnchanged':True,'profilesUsed':0,
            'scope':'actual replay numeric availability only; missing target/context/source qualification stays explicit; not form accuracy','cases':summary}
