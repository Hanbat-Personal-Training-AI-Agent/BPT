#!/usr/bin/env python3
"""Prepare a NEW task and export native fault decisions from closed source-bound traces.

No model inference or labels are generated. The header intentionally predates the
native boundaries; task/manifest binding is derived explicitly after execution.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys

from independent_form_eval import (COMMIT, HEX64, IDENTITY, PROTOCOL, RULES, ContractError,
    finite, keys, load, require, templates, unchanged, validate_manifest, write_new)
from import_predictions import CONTRACT, candidate_source, convert, file_sha

TRACE_CONTRACT = 'bpt-native-fault-trace-v1'
BINDING_CONTRACT = 'bpt-native-derived-task-v1'
CORE = {key: RULES[key] for key in ('pushup', 'squat', 'barbell_row')}
SOURCE_FIELDS = ('frame','sourceIndex','timeValue','timeScale','timeEpoch','timeFlags',
                 'seconds','session','kind','flush','sourceKey')
EVALUATOR = {'pushup':'PushUpEvaluator.swift', 'squat':'SquatEvaluator.swift', 'barbell_row':'BarbellRowEvaluator.swift'}


def dumps(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False)+'\n').encode()


def integer(value):
    return type(value) is int


def digest(value):
    return hashlib.sha256(value).hexdigest()


def source_key(source):
    if source['sourceIndex'] is None:
        return f"{source['session']}/frame/{source['frame']}"
    return f"{source['session']}/source/{source['sourceIndex']}"


def usable_clock(source):
    return (integer(source['timeValue']) and integer(source['timeScale']) and source['timeScale']>0
            and source['timeEpoch']==0 and integer(source['timeFlags'])
            and bool(source['timeFlags'] & 1) and not bool(source['timeFlags'] & (4|8|16))
            and finite(source['seconds']) and source['seconds']==source['timeValue']/source['timeScale']
            and source['seconds']>=0)


def validate_source(source, allow_failed_sentinel=False):
    keys(source,SOURCE_FIELDS,'source')
    sentinel=(allow_failed_sentinel and integer(source['sourceIndex']) and
              source['sourceIndex']>=0 and source['frame']==-1-source['sourceIndex'])
    require(integer(source['frame']) and (source['frame']>=0 or sentinel),'invalid processing frame')
    require(source['sourceIndex'] is None or integer(source['sourceIndex']) and source['sourceIndex']>=0,'invalid source index')
    require(isinstance(source['session'],str) and source['session'] and isinstance(source['kind'],str) and source['kind'],'missing source identity')
    require(type(source['flush']) is bool,'invalid flush provenance')
    for key in ('timeValue','timeScale','timeEpoch','timeFlags'):
        require(source[key] is None or integer(source[key]),'invalid rational source clock')
    require(source['seconds'] is None or finite(source['seconds']),'invalid source seconds')
    require(source['sourceKey']==source_key(source),'source key mismatch')
    return source


def load_lines(path):
    raw=Path(path).read_bytes()
    def unique(pairs):
        result={}
        for key,value in pairs:
            require(key not in result,'duplicate JSON field')
            result[key]=value
        return result
    try:
        require(raw.endswith(b'\n'),'trace does not end at a complete record boundary')
        rows=[json.loads(line,object_pairs_hook=unique,
              parse_constant=lambda _:(_ for _ in ()).throw(ContractError('nonfinite JSON literal')))
              for line in raw.splitlines()]
    except (ValueError,UnicodeError) as error:
        raise ContractError('invalid JSONL trace') from error
    require(len(rows)>=2,'trace has no header/footer')
    return rows,digest(raw)


def git_bytes(repo,candidate,path):
    require(isinstance(path,str) and path and not Path(path).is_absolute() and '..' not in Path(path).parts,
            'source path must be repository-relative')
    try:
        return subprocess.check_output(['git','-C',str(repo),'show',candidate+':'+path],stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as error:
        raise ContractError('candidate source missing') from error


def artifact_sha(path):
    path=Path(path)
    if path.is_file():return file_sha(path)
    require(path.is_dir(),'model artifact missing')
    state=hashlib.sha256()
    for item in sorted(p for p in path.rglob('*') if p.is_file()):
        state.update(str(item.relative_to(path)).encode()+b'\0'+file_sha(item).encode()+b'\n')
    return state.hexdigest()


class Trace:
    def __init__(self,path,clip,executable,receipt,repo):
        self.path,self.clip,self.executable=map(Path,(path,clip,executable))
        self.rows,self.sha=load_lines(self.path)
        header,footer=self.rows[0],self.rows[-1]
        require(header.get('type')=='header' and footer.get('type')=='footer','trace requires ordered header/footer')
        self.run_id=header.get('runID')
        require(isinstance(self.run_id,str) and self.run_id,'missing run ID')
        counts=Counter()
        for sequence,row in enumerate(self.rows):
            require(isinstance(row,dict) and row.get('contract')==TRACE_CONTRACT,'unsupported trace contract')
            require(row.get('runID')==self.run_id and type(row.get('sequence')) is int and row['sequence']==sequence,
                    'trace sequence/run identity mismatch')
            require(row.get('type') in ('header','frame','rep','reset','ingress_failure','footer'),'unsupported record type')
            counts[row['type']]+=1
        require(counts['header']==counts['footer']==1,'duplicate header/footer')
        require(footer.get('writerComplete') is True and footer.get('sourceDrained') is True and footer.get('failure') is None,
                'truncated/capped/failed trace cannot be exported')
        require(footer.get('recordsBeforeFooter')==len(self.rows)-1,'footer record count mismatch')
        require(footer.get('frameRecordsWritten')==counts['frame'] and footer.get('repRecordsWritten')==counts['rep'],'footer type counts mismatch')
        self.binding=header.get('binding')
        require(isinstance(self.binding,dict),'missing trace binding')
        b=self.binding
        self.candidate=b.get('candidateId');self.exercise=b.get('exercise');self.clip_id=b.get('clipId')
        require(isinstance(self.candidate,str) and COMMIT.fullmatch(self.candidate),'invalid candidate commit')
        require(self.exercise in CORE,'unsupported exercise')
        require(isinstance(self.clip_id,str) and self.clip_id,'missing clip identifier')
        require(b.get('taskBinding')=='unbound_native_windows','trace must explicitly declare unbound native windows')
        require(b.get('executionScope')=='headless_original_video_native_evaluator','unsupported execution provenance')
        self.clip_sha=file_sha(self.clip);self.executable_sha=file_sha(self.executable)
        require(b.get('sourceSHA256')==self.clip_sha,'full original clip hash mismatch')
        require(b.get('executableSHA256')==self.executable_sha,'native executable hash mismatch')
        sources=b.get('runtimeSourceSHA256')
        require(isinstance(sources,dict) and sources,'missing runtime source hashes')
        needed={'ios/Runner/NativePose/Evaluators/FormWarnings.swift',
                'ios/Runner/NativePose/Evaluators/FormFaultEvidence.swift',
                'ios/Runner/NativePose/Evaluators/'+EVALUATOR[self.exercise]}
        require(needed<=set(sources),'runtime source map omits actual rule/evaluator instrumentation')
        for relative,expected in sources.items():
            require(isinstance(expected,str) and HEX64.fullmatch(expected),'invalid runtime source hash')
            require(digest(git_bytes(repo,self.candidate,relative))==expected,'runtime source differs from candidate')
        self.rule_sha=digest(candidate_source(repo,self.candidate))
        build=b.get('buildManifest')
        require(isinstance(build,dict) and build.get('contract')=='bpt-pose-replay-build-v1','missing build manifest')
        require(build.get('candidateId')==self.candidate and build.get('executableSHA256')==self.executable_sha
                and build.get('sourceStableAcrossBuild') is True,'unbound/unstable native build')
        build_sources=build.get('sourceSHA256')
        require(isinstance(build_sources,dict) and sources.items()<=build_sources.items(),'build/runtime source mismatch')
        for relative,expected in build_sources.items():
            require(digest(git_bytes(repo,self.candidate,relative))==expected,'build source differs from candidate')
        self.receipt_path=Path(receipt)
        receipt,receipt_sha=load(receipt)
        require(receipt.get('contract')=='bpt-pose-replay-receipt-v1' and receipt.get('runID')==self.run_id and
                receipt.get('candidateId')==self.candidate,'execution receipt identity mismatch')
        require(Path(receipt.get('tracePath','')).resolve()==self.path.resolve() and receipt.get('traceSHA256')==self.sha,
                'execution receipt trace hash mismatch')
        require(receipt.get('artifactsStable') is True and receipt.get('sourceSHA256Before')==self.clip_sha and
                receipt.get('sourceSHA256After')==self.clip_sha,'source changed during native execution')
        require(receipt.get('modelDigestAlgorithm')=='sha256-relative-path-nul-file-sha256-lf-v1',
                'unsupported model artifact digest algorithm')
        self.models=b.get('modelArtifactSHA256')
        require(isinstance(self.models,dict) and self.models and receipt.get('modelArtifactSHA256Before')==self.models and
                receipt.get('modelArtifactSHA256After')==self.models,'model execution receipt mismatch')
        for model,sha in self.models.items():
            require(Path(model).is_absolute() and isinstance(sha,str) and HEX64.fullmatch(sha),'invalid model artifact identity')
            require(artifact_sha(model)==sha,'actual model artifact differs from execution')
        require(type(receipt.get('lifterActive')) is bool and type(receipt.get('formSource3D')) is bool,'unknown execution source mode')
        self.receipt=receipt
        self.frames={};self.reps={};self.expected={}
        self.failed_sources=set()
        expected=header.get('expectedSourceManifest')
        require(expected is None or isinstance(expected,list),'invalid expected source manifest')
        if expected is not None:
            require(header.get('expectedSourceScope')=='declared_input_manifest','unexpected ledger scope')
            for source in expected:
                validate_source(source,allow_failed_sentinel=True)
                key=source['sourceKey'];require(key not in self.expected,'duplicate expected source')
                self.expected[key]=source
            require(header.get('expectedSources')==len(self.expected),'declared source count mismatch')
        else:
            require(header.get('expectedSourceScope')=='observed_judgements_only','unexpected observed-only scope')
        source_keys=set()
        for row in self.rows[1:-1]:
            if row['type']=='frame':
                source=row.get('source')
                if source is not None:
                    validate_source(source)
                    require(source['sourceKey'] not in source_keys,'duplicate observed source')
                    source_keys.add(source['sourceKey'])
                    if row.get('observation')!='observed':
                        self.failed_sources.add(source['sourceKey'])
                    require(source['frame'] not in self.frames,'duplicate processing frame')
                    self.frames[source['frame']]=row
                    if self.expected:
                        wanted=self.expected.get(source['sourceKey'])
                        require(wanted is not None,'observation outside declared source manifest')
                        require(all(source[k]==wanted[k] for k in SOURCE_FIELDS if k not in ('flush',)),
                                'observed source differs from declaration')
            elif row['type']=='rep':
                key=row.get('traceID');require(isinstance(key,str) and key and key not in self.reps,'duplicate/missing rep trace ID')
                self.reps[key]=row
            elif row['type']=='ingress_failure':
                source=validate_source(row.get('source'),allow_failed_sentinel=True)
                require(source['sourceKey'] in self.expected,'failed ingress outside declared manifest')
                self.failed_sources.add(source['sourceKey'])
        require(footer.get('duplicateSources')==0 and footer.get('mismatchedSources')==0,'source identity failure')
        require(footer.get('observedSources')==len(source_keys),'observed source count mismatch')
        require(footer.get('failedSourcesCount')==len(self.failed_sources),'failed source count mismatch')
        missing=len(set(self.expected)-source_keys) if expected is not None else None
        require(footer.get('missingSources')==missing and footer.get('expectedSources')==(len(self.expected) if expected is not None else None),
                'source ledger footer mismatch')
        unknown=sum(row['type']=='frame' and (row.get('source') is None or row['source']['seconds'] is None) for row in self.rows)
        require(footer.get('unknownSources')==unknown,'unknown source count mismatch')
        require(footer.get('bytesBeforeFooter')==sum(len(line)+1 for line in self.path.read_bytes().splitlines()[:-1]),
                'footer byte count mismatch')
        coverage=expected is not None and missing==0 and unknown==0 and not self.failed_sources
        require(footer.get('sourceCoverageComplete') is coverage,'source coverage claim inconsistent with ledger')
        if footer.get('sourceCoverageComplete') is True:
            require(self.expected and source_keys==set(self.expected),'false complete source coverage claim')
            require(footer.get('unknownSources')==0 and footer.get('missingSources')==0,'inconsistent coverage totals')
        self.footer=footer
        self.judges={}
        for rep in self.reps.values():
            require(rep.get('formSource')==('3d' if rep.get('enough3D') is True else '3d_unavailable')
                    if receipt['formSource3D'] else rep.get('formSource')=='2d','selected source conflicts with execution receipt')
            if receipt['formSource3D']:require(receipt['lifterActive'],'3D judgement without active lifter')
            judges=rep.get('judgements')
            require(isinstance(judges,dict) and set(judges)=={'2d','3d'},'invalid judgement sources')
            for source,judge in judges.items():
                if judge is not None:
                    require(judge.get('source')==source and judge.get('traceID')==rep['traceID']+'/'+source,'judgement identity mismatch')
                    require(judge['traceID'] not in self.judges,'duplicate judgement ID')
                    self.judges[judge['traceID']]=(rep,judge,source)
        self.snapshots=[(self.path,self.sha),(self.clip,self.clip_sha),(self.executable,self.executable_sha),
                        (self.receipt_path,receipt_sha)]

    def rep_sources(self,rep):
        frames=rep.get('frames2D')
        require(isinstance(frames,list) and len(frames)>=2 and all(integer(f) for f in frames),'rep has no valid native span')
        require(frames==sorted(set(frames)),'rep frames duplicate or reordered')
        require(rep.get('startFrame')==frames[0] and rep.get('endFrame')==frames[-1],'rep endpoint mismatch')
        require(all(f in self.frames for f in frames),'rep refers to unavailable frame record')
        sources=[self.frames[f]['source'] for f in frames]
        require(all(usable_clock(s) for s in sources),'native boundary has no usable rational source clock')
        require(len({s['session'] for s in sources})==1,'rep crosses source session')
        require(all(a['seconds']<b['seconds'] for a,b in zip(sources,sources[1:])),'native source time is not increasing')
        return sources


def read_bundle(bundle,repo):
    document,bundle_sha=load(bundle)
    keys(document,('schemaVersion','traces'),'trace bundle')
    require(document['schemaVersion']==1 and type(document['schemaVersion']) is int,'unsupported bundle version')
    require(isinstance(document['traces'],list) and document['traces'],'empty trace bundle')
    traces=[]
    for entry in document['traces']:
        keys(entry,('tracePath','clipPath','executablePath','receiptPath'),'trace bundle entry')
        paths=[Path(entry[key]) for key in ('tracePath','clipPath','executablePath','receiptPath')]
        paths=[p if p.is_absolute() else Path(bundle).parent/p for p in paths]
        traces.append(Trace(*paths,repo))
    require(len({t.candidate for t in traces})==1,'bundle mixes candidate commits')
    require(len({t.clip_sha for t in traces})==len(traces),'duplicate clip bytes in task')
    require(len({t.run_id for t in traces})==len(traces),'duplicate trace run IDs')
    return traces,[(bundle,bundle_sha)]+[entry for t in traces for entry in t.snapshots]


def unchanged_artifacts(traces,snapshots):
    unchanged(snapshots)
    for trace in traces:
        for path,sha in trace.models.items():require(artifact_sha(path)==sha,'model artifact changed during export')


def task_documents(traces,protocol_sha):
    samples=[];boundaries=[]
    for clip_index,trace in enumerate(traces,1):
        for ordinal,rep in enumerate(trace.reps.values(),1):
            sources=trace.rep_sources(rep)
            start,end=sources[0]['seconds'],sources[-1]['seconds']
            require(start<end,'empty native boundary')
            side=rep.get('reportedSide');require(side in ('left','right'),'unknown native report side')
            prefix=f'c{clip_index:04d}.r{ordinal:04d}'
            boundaries.append({'samplePrefix':prefix,'clipSha256':trace.clip_sha,'traceSha256':trace.sha,
                'runID':trace.run_id,'traceID':rep['traceID'],'nativeRepIndex':rep.get('nativeRepIndex'),
                'startSeconds':start,'endSeconds':end,'side':side})
            for rule in CORE[trace.exercise]:
                samples.append({'sampleId':prefix+'.'+rule,'clipSha256':trace.clip_sha,'exercise':trace.exercise,
                    'rep':ordinal,'rule':rule,'side':side,'startSeconds':start,'endSeconds':end,
                    'timeUnit':'seconds','labelUnit':'per_rep_rule_binary_fault','split':'development',
                    'splitGroup':'native_all_sources_development','visibility':'unknown',
                    'contactChange':'unknown','windowCoverage':'unknown'})
    require(samples,'trace bundle has no completed native reps')
    boundary={'contract':BINDING_CONTRACT,'boundarySource':'ai_windows','boundaries':boundaries}
    boundary_raw=dumps(boundary)
    manifest={'schemaVersion':1,'protocolId':PROTOCOL,'protocolSha256':protocol_sha,
        'candidateCommit':traces[0].candidate,'splitPlanId':'new_native_trace_development_only',
        'dataKind':'evaluation','boundarySource':'ai_windows','boundaryManifestSha256':digest(boundary_raw),'samples':samples}
    validate_manifest(manifest)
    manifest_raw=dumps(manifest);labels,predictions=templates(manifest,digest(manifest_raw))
    return manifest,boundary,labels,predictions


def prepare(bundle,repo,protocol,output_dir):
    output=Path(output_dir)
    require(not output.exists() and not output.is_symlink(),'output task already exists')
    traces,snapshots=read_bundle(bundle,repo)
    protocol_sha=file_sha(protocol);snapshots.append((protocol,protocol_sha))
    manifest,boundary,labels,predictions=task_documents(traces,protocol_sha)
    manifest_raw=dumps(manifest);boundary_raw=dumps(boundary)
    unchanged_artifacts(traces,snapshots)
    output=Path(output_dir);output.mkdir(mode=0o700)
    for name,raw in (('boundary_manifest.json',boundary_raw),('manifest.json',manifest_raw)):
        with (output/name).open('xb') as f:f.write(raw)
    write_new(output/'labels.json',labels);write_new(output/'predictions.json',predictions)
    write_new(output/'clip_index_PRIVATE.json',[{'clipSha256':t.clip_sha,'localClipPath':str(t.clip.resolve())} for t in traces])
    write_new(output/'source_bindings_PRIVATE.json',{'contract':BINDING_CONTRACT,'bundlePath':str(Path(bundle).resolve()),
        'bundleSha256':snapshots[0][1],'traces':[{'runID':t.run_id,'traceSha256':t.sha,'clipSha256':t.clip_sha} for t in traces]})
    return {'status':'prepared','nativeReps':len(boundary['boundaries']),'opportunities':len(manifest['samples']),
            'unknownLabels':len(manifest['samples']),'missingPredictions':len(manifest['samples']),'holdoutOpportunities':0,
            'manifestSha256':digest(manifest_raw),'boundaryManifestSha256':digest(boundary_raw)}


class Unproven(Exception):
    """Valid trace, but the requested rule proposition is not established."""


def proof(condition, reason):
    if not condition:
        raise Unproven(reason)


PHASE = {
    'pushup_shallow':('bottom',), 'pushup_no_lockout':('top',),
    'pushup_hand_position':('top',), 'pushup_depth_fade':('bottom',),
    'squat_hips_first':('bottom','ascending'), 'squat_shallow':('bottom',),
    'squat_no_lockout':('top',), 'squat_lean_drift':('bottom',),
    'squat_depth_fade':('bottom',), 'squat_knee_valgus':('bottom','ascending'),
    'row_short_pull':('top',),
}
OPERAND_CONTRACT = {
    'pushup_hip_sag':('over','hip_dev_max'), 'pushup_hip_pike':('under','hip_dev_min'),
    'pushup_shallow':('over_baseline','elbow_min'), 'pushup_no_lockout':('below_set_max','elbow_max'),
    'pushup_head_drop':('over','head_dev_change_max'), 'pushup_head_up':('under','head_dev_change_min'),
    'pushup_depth_fade':('trend','elbow_min'), 'squat_shallow':('over_baseline','knee_min'),
    'squat_lean_drift':('trend','torso_at_bottom'), 'squat_depth_fade':('trend','knee_min'),
    'squat_knee_valgus':('under','knee_ankle_gap_ratio_min'), 'squat_heel_rise':('over','heel_rise_max'),
    'row_standing_up':('wrapped_baseline_minus_current','torso_mean'),
    'row_short_pull':('baseline_minus_current','elbow_behind_max'),
    'row_head_up':('under','head_dev_change_min'), 'row_shrug':('over','ear_shoulder_drop'),
}


class Support:
    """Check source lineage, never synthesize a native rule evaluation.

    A failed proposition is withholding, while conflicting identity is rejected.
    The trace is a source-bound native attestation, not a rerun of native geometry.
    """
    def __init__(self, trace, rep, judge, source, rule):
        self.trace,self.rep,self.judge,self.source,self.rule=trace,rep,judge,source,rule
        self.witness=set()
        self.reference_ids=[]
        self.metric_checks=[]
        self.expected=self.scope_frames(rep)

    def checkpoint(self):
        return self.witness.copy(),list(self.reference_ids),list(self.metric_checks)

    def restore(self, state):
        self.witness,self.reference_ids,self.metric_checks=state

    def scope_frames(self, rep):
        sources=self.trace.rep_sources(rep)
        start,end=sources[0],sources[-1]
        proof(bool(self.trace.expected),'no_declared_source_ledger')
        relevant=[s for s in self.trace.expected.values() if s['session']==start['session'] and
                  usable_clock(s) and start['seconds']<=s['seconds']<=end['seconds']]
        proof(relevant,'empty_declared_rep_scope')
        proof(all(usable_clock(s) for s in self.trace.expected.values() if s['session']==start['session']),
              'unknown_source_clock_in_session')
        return [s['frame'] for s in sorted(relevant,key=lambda s:s['seconds'])]

    def sample(self, frame, rep=None, source=None):
        rep=rep or self.rep;source=source or self.source
        row=self.trace.frames.get(frame)
        proof(row is not None,'missing_source_frame')
        proof(row['source']['sourceKey'] not in self.trace.failed_sources,'failed_source_ingress')
        proof(not row['source']['flush'],'flush_output_not_observation')
        sample=row.get('sample2D' if source=='2d' else 'sample3D')
        proof(isinstance(sample,dict),'selected_source_unavailable')
        proof(sample.get('frame')==frame and sample.get('side')==rep.get('reportedSide'),'sample_side_or_frame_unproven')
        proof(frame in rep.get('frames2D' if source=='2d' else 'frames3D',[]),'source_not_in_native_rep')
        if source=='3d':
            proof(sample.get('state3D') in ('ok','partial_3d'),'unusable_3d_state')
        return sample

    def covered(self, frames, rep=None, source=None):
        for frame in frames:
            self.sample(frame,rep,source)

    def facing(self, frame):
        # The initial state must be witnessed. A finite inherited state alone
        # cannot establish its provenance. Missing ingress breaks the chain.
        target=self.trace.frames[frame]['source']
        target_sequence=self.trace.frames[frame]['sequence']
        reset=max((r['sequence'] for r in self.trace.rows if r['type']=='reset' and r['sequence']<target_sequence),default=-1)
        before_reset=[r['source']['seconds'] for r in self.trace.frames.values() if r['sequence']<reset and
                      r['source']['session']==target['session']]
        cutoff=max(before_reset,default=-1)
        prior=sorted((s for s in self.trace.expected.values() if s['session']==target['session'] and
                      s['seconds']>cutoff and
                      usable_clock(s) and s['seconds']<=target['seconds']),key=lambda s:s['seconds'])
        previous=None;previous_run=0;proven=False;candidate_proven=True
        for index,item in enumerate(prior):
            row=self.trace.frames.get(item['frame'])
            proof(row is not None,'unwitnessed_facing_history')
            sample=row.get('sample2D')
            proof(isinstance(sample,dict),'unwitnessed_facing_history')
            facing=(sample.get('inputSupport') or {}).get('facing')
            proof(isinstance(facing,dict),'missing_facing_lineage')
            proof(facing.get('before')==previous,'inherited_or_broken_facing_history')
            proof(facing.get('candidateRunBefore')==previous_run,'unwitnessed_facing_candidate_history')
            if index==0:
                proof(facing.get('before') is None,'inherited_facing_state')
            inputs=sample['inputSupport']
            proof('facingObservation' in inputs,'missing_facing_observation_lineage')
            observation=inputs['facingObservation']
            after=facing.get('after');run=facing.get('candidateRun')
            require(integer(run) and run>=0,'invalid facing candidate run')
            if observation is None:
                require(after==previous and run==previous_run,'unrecorded facing state update')
            else:
                require(isinstance(observation,dict) and observation.get('before')==previous and observation.get('after')==after and
                        observation.get('candidateRunBefore')==previous_run and observation.get('candidateRunAfter')==run,
                        'facing observation/state mismatch')
                seen=observation.get('seen');kind=observation.get('updateKind')
                require(seen in (-1,1) and type(seen) is not bool,'invalid observed facing sign')
                require(observation.get('sourceJoints')==facing.get('sourceJoints'),'facing source-joint mismatch')
                evidence={j.get('joint'):j for j in inputs.get('jointEvidence',[])}
                good=all(evidence.get(j,{}).get('finiteCoordinates') is True and
                         evidence.get(j,{}).get('finiteScore') is True and
                         evidence.get(j,{}).get('confidenceAccepted') is True for j in observation['sourceJoints'])
                if kind=='establish':
                    require(previous is None and after==seen and run==0,'invalid facing establishment')
                    proven=good;candidate_proven=True
                elif kind=='confirm':
                    require(previous==seen==after and run==0,'invalid facing confirmation')
                    proven=good;candidate_proven=True
                elif kind=='candidate':
                    require(previous is not None and seen!=previous and after==previous and run==previous_run+1,
                            'invalid facing candidate')
                    candidate_proven=(candidate_proven if previous_run else True) and good
                elif kind=='flip':
                    require(previous is not None and seen!=previous and after==seen and run==0,'invalid facing flip')
                    proven=candidate_proven and good;candidate_proven=True
                else:raise ContractError('unknown facing observation update')
            previous=facing.get('after')
            previous_run=run
        proof(finite(previous) and proven,'facing_not_established_by_trustworthy_observation')

    def field(self, frame, field, rep=None, source=None):
        rep=rep or self.rep;source=source or self.source
        sample=self.sample(frame,rep,source)
        proof(finite(sample.get('measurements',{}).get(field)),'missing_or_nonfinite_'+field)
        inputs=sample.get('inputSupport')
        proof(isinstance(inputs,dict),'missing_input_lineage')
        if source=='3d' and field in inputs.get('borrowed2DFields',[]):
            return self.field(frame,field,rep,'2d')
        joints=inputs.get('measurementJoints',{}).get(field)
        proof(isinstance(joints,list) and bool(joints),'missing_measurement_dependencies')
        evidence={j.get('joint'):j for j in inputs.get('jointEvidence',[]) if isinstance(j,dict)}
        for joint in joints:
            observed=evidence.get(joint,{})
            proof(observed.get('finiteCoordinates') is True,'unobserved_joint_dependency')
            if source=='2d':
                proof(observed.get('finiteScore') is True and observed.get('confidenceAccepted') is True,
                      'unreliable_joint_dependency')
        if source=='2d' and field in inputs.get('facingRequiredFields',[]):
            self.facing(frame)
        if source=='3d' and field in inputs.get('upRequiredFields',[]):
            proof(len(inputs.get('up',[]))==3 and all(finite(v) for v in inputs['up']), 'unknown_native_up_vector')
        if field=='heelToe':
            minimum=inputs.get('footMinimumConfidence')
            proof(finite(minimum),'unknown_foot_confidence_contract')
            for item in ('heel','bigToe'):
                foot=inputs.get('feet',{}).get(item,{})
                proof(foot.get('finiteCoordinates') is True and foot.get('finiteScore') is True and
                      finite(foot.get('score')) and foot['score']>=minimum,'unobserved_foot_dependency')

    def finite_fields(self, frames, fields, rep=None, source=None):
        for frame in frames:
            for field in fields:
                self.field(frame,field,rep,source)

    def scope(self, support, rep):
        frames=support.get('scopeFrames')
        require(isinstance(frames,list) and frames==sorted(set(frames)) and all(integer(f) for f in frames),
                'invalid metric support scope')
        allframes=self.scope_frames(rep)
        proof(bool(frames) and set(frames)<=set(allframes),'metric_scope_outside_rep')
        return frames,allframes

    def metric(self, name, mode='complete', rep=None, judge=None, source=None):
        rep=rep or self.rep;judge=judge or self.judge;source=source or self.source
        support=judge.get('metricSupport',{}).get(name)
        proof(isinstance(support,dict) and support.get('finite') is True and finite(support.get('value')),
              'missing_metric_support_'+name)
        require(support['value']==judge.get('metrics',{}).get(name),'metric support value mismatch')
        frames,allframes=self.scope(support,rep)
        fields=support.get('dependencyFields') or [support.get('field')]
        proof(all(isinstance(f,str) and f for f in fields),'missing_metric_fields')
        selected=support.get('selectedFrames',[]);reference=support.get('referenceFrames',[])
        proven_selected=selected
        require(isinstance(selected,list) and isinstance(reference,list),'invalid metric witnesses')
        proof(set(selected+reference)<=set(allframes),'metric_witness_outside_rep')
        selector=support.get('selectorFrames',[])
        selector_fields=support.get('selectorFields',[])
        if selector_fields and not (name=='ear_shoulder_drop' and mode=='witness'):
            proof(selector==allframes or name.startswith('hips_first_'),'incomplete_selector_scope')
            if name.startswith('hips_first_'):
                proof(selector==frames,'incomplete_end_selector_scope')
            self.finite_fields(selector,selector_fields,rep,source)
        for stage in support.get('selectionStages',[]):
            proof(stage.get('scopeFrames')==allframes,'incomplete_selection_stage')
            self.finite_fields(allframes,stage.get('fields',[]),rep,source)
            proof(set(stage.get('selectedFrames',[]))<=set(allframes),'invalid_stage_selection')
        # Positives that rely on a search minimum being too high or maximum
        # being too low must examine its whole search, just like negatives.
        full = mode=='complete' or name in ('torso_min','torso_max','torso_mean','torso_at_bottom',
                    'first_rep_top_wrist_ahead') or name.startswith('hips_first_')
        if full:
            expected_scope=allframes[allframes.index(frames[0]):allframes.index(frames[-1])+1]
            proof(frames==expected_scope,'incomplete_metric_scope')
            if name not in ('knee_ankle_gap_ratio_min','ear_shoulder_drop') and not name.startswith('hips_first_'):
                proof(frames==allframes,'incomplete_whole_rep_search')
            if name in ('torso_at_bottom','first_rep_top_wrist_ahead'):
                proof(bool(selected),'missing_selected_value')
                self.finite_fields(selected,fields,rep,source)
            else:
                self.finite_fields(frames,fields,rep,source)
        else:
            proof(bool(selected),'no_selected_native_witness')
            errors=[]
            for frame in selected:
                try:
                    self.finite_fields([frame],fields,rep,source)
                    proven_selected=[frame]
                    break
                except Unproven as error:errors.append(str(error))
            else:raise Unproven('no_trustworthy_selected_witness:'+','.join(errors))
        if reference:
            self.finite_fields(reference,fields,rep,source)
            if name.startswith('head_dev_change') or name in ('heel_rise_max','ear_shoulder_drop'):
                self.covered(allframes[:allframes.index(reference[0])+1],rep,source)
        if name=='ear_shoulder_drop':
            proof(bool(reference),'missing_first_jointly_available_reference')
            self.finite_fields(reference+proven_selected,['headAngle','earShoulder'],rep,source)
            # Positive only needs its actual accepted minimum plus first-ref
            # origin. Negative must classify the entire head-angle filter.
            if mode=='complete':
                self.finite_fields(allframes,['headAngle','earShoulder'],rep,source)
        # Phase is attached to the exact native selector scope, not UI aliases.
        for phase in PHASE.get(self.rule,()):
            proof(any(self.sample(f,rep,source).get('phase')==phase and
                      all(finite(self.sample(f,rep,source).get('measurements',{}).get(k)) for k in fields)
                      for f in frames),'required_phase_not_observed_'+phase)
        if rep is self.rep:
            self.witness.update(frames if full else proven_selected+reference)
        self.metric_checks.append({'traceID':judge['traceID'],'metric':name,'mode':mode,
                                   'scopeFrames':frames,'selectedFrames':selected,'referenceFrames':reference,
                                   'provenSelectedFrames':proven_selected})
        return support['value']

    def references(self, operand, positive):
        operation=operand['operation'];metric=operand['metric']
        history=self.judge.get('history')
        require(isinstance(history,list),'missing native offered history')
        entries=operand.get('referenceEntries')
        require(isinstance(entries,list),'invalid reference entries')
        indices=[entry.get('index') for entry in entries]
        count=operand.get('expectedReferenceCount')
        require(integer(count) and count>=0,'invalid expected reference count')
        if operation=='below_set_max':
            require(indices==list(range(len(history)+1)) and count==len(history)+1 and
                    operand.get('currentIncluded') is True,'offered max history membership mismatch')
        elif operation in ('over_baseline','wrapped_baseline_minus_current','baseline_minus_current'):
            proof(operand.get('completeReference') is True,'incomplete_prefix_reference')
            require(indices==list(range(count)) and count<=len(history),'prefix reference membership mismatch')
        elif operation=='trend':
            proof(operand.get('completeReference') is True,'incomplete_trend_reference')
            require(count%2==0,'invalid trend reference count')
            n=count//2;total=len(history)+1
            require(total>=count and indices==list(range(n))+list(range(total-n,total)),'trend reference membership mismatch')
        resolved=[]
        for entry in entries:
            index=entry['index']
            require(integer(index) and 0<=index<=len(history),'reference index out of offered history')
            if index==len(history):
                expected={'traceID':self.judge['traceID'],'repIndex':self.rep['nativeRepIndex'],
                          'metrics':self.judge['metrics']}
                ref=(self.rep,self.judge,self.source)
            else:
                expected=history[index]
                ref=self.trace.judges.get(expected.get('traceID'))
            require(entry.get('traceID')==expected.get('traceID') and entry.get('repIndex')==expected.get('repIndex') and
                    entry.get('value')==expected.get('metrics',{}).get(metric),'reference does not match offered history')
            resolved.append((entry,ref))
        if operation=='below_set_max' and positive:
            # The largest actually consumed finite value proves the historical
            # lower bound. Missing other maxima can only increase this bound.
            candidates=[pair for pair in resolved if finite(pair[0].get('value')) and
                        pair[0]['value']==operand.get('referenceValue')]
            proof(candidates,'no_finite_maximum_reference_witness')
            errors=[]
            for entry,ref in candidates:
                checkpoint=self.checkpoint()
                try:
                    self.reference_metric(entry,ref,metric,'witness')
                    return
                except Unproven as error:
                    self.restore(checkpoint)
                    errors.append(str(error))
            raise Unproven('maximum_reference_unproven:'+','.join(errors))
        proof(operand.get('completeReference') is True,'incomplete_reference')
        for entry,ref in resolved:
            self.reference_metric(entry,ref,metric,'complete')

    def reference_metric(self, entry, ref, metric, mode):
        proof(ref is not None,'unresolved_historical_trace')
        rep,judge,source=ref
        proof(source==self.source and rep['reportedSide']==self.rep['reportedSide'],'reference_source_or_side_changed')
        proof(finite(entry.get('value')),'missing_offered_historical_metric')
        require(judge['metrics'].get(metric)==entry['value'],'historical metric value mismatch')
        if rep is not self.rep:
            require(self.trace.rep_sources(rep)[-1]['seconds']<=self.trace.rep_sources(self.rep)[0]['seconds'],
                    'reference is not earlier than current rep')
            self.reference_ids.append(judge['traceID'])
        self.metric(metric,mode,rep,judge,source)
        support=judge['metricSupport'][metric]
        frames=self.scope_frames(rep) if mode=='complete' else sorted(set(self.metric_checks[-1]['provenSelectedFrames']+support.get('referenceFrames',[])))
        self.view(mode=='complete',rep,judge,source,frames)

    def operand(self, operand, positive):
        proof(operand.get('result') is positive,'operand_does_not_support_condition')
        proof(operand.get('positiveOperandEvidence' if positive else 'negativeOperandEvidence') is True,
              'native_operand_evidence_incomplete')
        proof(operand.get('finiteCurrent') is True and operand.get('finiteThreshold') is True,'nonfinite_operand')
        operation=operand.get('operation');metric=operand.get('metric')
        require(operation in ('over','under','over_baseline','below_set_max','trend',
                              'wrapped_baseline_minus_current','baseline_minus_current'),'unknown native operation')
        if operation in ('over','under'):
            self.metric(metric,'witness' if positive else 'complete')
        elif operation=='trend':
            self.references(operand,positive)
        else:
            self.metric(metric,'complete')
            self.references(operand,positive)

    def view(self, full, rep=None, judge=None, source=None, frames=None):
        rep=rep or self.rep;judge=judge or self.judge;source=source or self.source
        view=judge.get('view',{})
        proof(view.get('qualified') is True,'native_view_unqualified')
        front=self.rule=='squat_knee_valgus'
        if self.rule!='squat_heel_rise':
            proof(view.get('actualSideView') is (not front),'wrong_native_view_branch')
        if frames is None:
            frames=self.expected if full else sorted(self.witness)
        proof(frames,'no_source_witness')
        for frame in frames:
            sample=self.sample(frame,rep,source)
            observed=sample.get('frontView')
            proof(type(observed) is bool,'unknown_view_at_witness')
            if self.rule!='squat_heel_rise':
                proof(observed is front,'ineligible_view_at_witness')
            # frontView is borrowed from 2D for the 3D path.
            inputs=self.sample(frame,rep,'2d').get('inputSupport') or {}
            joints=inputs.get('measurementJoints',{}).get('frontView')
            proof(isinstance(joints,list) and bool(joints),'missing_view_dependencies')
            evidence={x.get('joint'):x for x in inputs.get('jointEvidence',[])}
            proof(all(evidence.get(j,{}).get('finiteCoordinates') is True and
                      evidence.get(j,{}).get('finiteScore') is True and
                      evidence.get(j,{}).get('confidenceAccepted') is True for j in joints),'unobserved_view_dependencies')

    def evaluate(self, row, positive):
        proof(row.get('executionEnabled') is True,'rule_execution_disabled')
        proof(row.get('callState')==('true' if positive else 'false') and row.get('condition') is positive,
              'rule_not_definitively_evaluated')
        if positive:
            proof(row.get('rawFired') is True,'positive_not_fired')
        else:
            proof(row.get('rawFired') is False,'false_rule_reported_fired')
            self.covered(self.expected)
        proof(row.get('positiveOperandEvidence' if positive else 'negativeOperandEvidence') is True,
              'native_rule_evidence_incomplete')
        operands=row.get('operands')
        require(isinstance(operands,list),'missing rule operands')
        if self.rule=='squat_no_lockout':
            require(all(o.get('metric') in ('knee_max','hip_angle_max') and o.get('operation')=='below_set_max' for o in operands),
                    'unexpected lockout operand')
            require(len({o['metric'] for o in operands})==len(operands),'duplicate lockout operand')
            if positive:
                errors=[]
                for operand in operands:
                    if operand.get('result') is True:
                        checkpoint=self.checkpoint()
                        try:
                            self.operand(operand,True);break
                        except Unproven as error:
                            self.restore(checkpoint);errors.append(str(error))
                else: raise Unproven('no_supported_true_lockout_branch:'+','.join(errors))
            else:
                proof({o['metric'] for o in operands}=={'knee_max','hip_angle_max'},'incomplete_false_lockout_branches')
                for operand in operands:self.operand(operand,False)
        elif operands:
            require(len(operands)==1,'unexpected compound operands')
            require(self.rule in OPERAND_CONTRACT and
                    (operands[0].get('operation'),operands[0].get('metric'))==OPERAND_CONTRACT[self.rule],
                    'rule operand contract mismatch')
            self.operand(operands[0],positive)
        else:
            manual=row.get('manualInputs');thresholds=row.get('manualThresholds')
            proof(isinstance(manual,dict) and manual and all(finite(v) for v in manual.values()) and
                  isinstance(thresholds,dict) and thresholds and all(finite(v) for v in thresholds.values()),
                  'missing_manual_rule_inputs')
            allowed={
                'pushup_hand_position':('outside_signed_hand_position_range',('first_rep_top_wrist_ahead',)),
                'squat_hips_first':('rise_and_relative_speed',('hips_first_torso_rise','hips_first_hip_rise_speed','hips_first_shoulder_rise_speed')),
                'row_torso_swing':('torso_range',('torso_min','torso_max')),
            }
            require(self.rule in allowed and row.get('manualOperation')==allowed[self.rule][0], 'unknown manual operation')
            require(set(manual)==set(allowed[self.rule][1]),'manual metric membership mismatch')
            if self.rule=='pushup_hand_position':
                proof(not self.judge.get('history'),'hand_position_not_first_native_rep')
            for metric in allowed[self.rule][1]:
                require(manual[metric]==self.judge['metrics'].get(metric),'manual metric value mismatch')
                self.metric(metric,'complete')
        self.view(not positive)
        # Witness intervals describe observed support, never clipped crossing
        # events. A single point needs an adjacent, observed in-window interval.
        times=sorted((self.trace.frames[f]['source']['seconds'],f) for f in self.witness)
        proof(times,'no_positive_duration_witness')
        if not positive:
            return self.trace.rep_sources(self.rep)[0]['seconds'],self.trace.rep_sources(self.rep)[-1]['seconds']
        if len(times)==1:
            frame=times[0][1];index=self.expected.index(frame)
            neighbours=self.expected[max(0,index-1):index+2]
            choices=[f for f in neighbours if f!=frame and f in self.trace.frames]
            proof(choices,'isolated_positive_witness')
            other=choices[0];self.sample(other)
            times.append((self.trace.frames[other]['source']['seconds'],other));times.sort()
        proof(times[0][0]<times[-1][0],'empty_witness_exposure')
        return times[0][0],times[-1][0]


def decision(trace,rep,rule,sample):
    source=rep.get('formSource')
    require(source in ('2d','3d','3d_unavailable'),'unknown selected form source')
    judge=rep['judgements'].get(source)
    base={**sample,'ruleId':rule,'decisionSemantic':'fault_presence',
          'exposureStartSeconds':sample['startSeconds'],'exposureEndSeconds':sample['endSeconds'],
          'checks':{k:False for k in ('ruleEnabled','ruleEvaluated','requiredPhaseObserved','viewEligible','referenceReady','finiteInputs')},
          'positiveEvidenceSufficient':False}
    audit={'sampleId':sample['sampleId'],'traceID':rep['traceID'],'selectedSource':source}
    if judge is None:
        return {**base,'state':'withheld','reason':'source_unavailable'},{**audit,'disposition':'selected_source_unavailable'}
    rules=judge.get('rules');require(isinstance(rules,list),'missing native rule catalogue')
    require(len(rules)==len(CORE[trace.exercise]) and {r.get('rule') for r in rules}==set(CORE[trace.exercise]),
            'native rule catalogue mismatch')
    row=next(r for r in rules if r['rule']==rule)
    require(row.get('callState') in ('not_called','true','false','nil'),'unknown native rule call state')
    expected_condition={'not_called':None,'nil':None,'true':True,'false':False}[row['callState']]
    require(row.get('condition') is expected_condition,'native call state/condition mismatch')
    audit.update({'callState':row.get('callState'),'executionEnabled':row.get('executionEnabled'),
                  'deliveryEnabled':row.get('deliveryEnabled'),'deliveryAssessed':row.get('deliveryAssessed')})
    base['checks']['ruleEnabled']=row.get('executionEnabled') is True
    base['checks']['ruleEvaluated']=row.get('callState') in ('true','false')
    positive=row.get('condition') is True
    support=None
    try:
        support=Support(trace,rep,judge,source,rule)
        start,end=support.evaluate(row,positive)
        require(sample['startSeconds']<=start<end<=sample['endSeconds'],'support outside exact frozen opportunity')
        base.update({'state':'warning' if positive else 'no_warning','reason':None,
                     'exposureStartSeconds':start,'exposureEndSeconds':end,
                     'checks':dict.fromkeys(base['checks'],True),'positiveEvidenceSufficient':positive})
        audit['disposition']='supported_positive' if positive else 'supported_negative'
    except Unproven as error:
        base.update({'state':'withheld','reason':'insufficient_evidence'})
        audit['disposition']=str(error)
    if support is not None:
        audit.update({'metricChecks':support.metric_checks,'referenceTraceIDs':support.reference_ids,
                      'witnessFrames':sorted(support.witness)})
    return base,audit


def export(task_dir,repo,protocol,output_dir):
    task=Path(task_dir);output=Path(output_dir)
    require(not output.exists() and not output.is_symlink(),'output export already exists')
    binding,binding_sha=load(task/'source_bindings_PRIVATE.json')
    keys(binding,('contract','bundlePath','bundleSha256','traces'),'task source binding')
    require(binding['contract']==BINDING_CONTRACT,'unsupported derived task binding')
    require(file_sha(binding['bundlePath'])==binding['bundleSha256'],'trace bundle changed after task preparation')
    traces,snapshots=read_bundle(binding['bundlePath'],repo)
    require(binding['traces']==[{'runID':t.run_id,'traceSha256':t.sha,'clipSha256':t.clip_sha} for t in traces],
            'native trace identity changed after task preparation')
    manifest,manifest_sha=load(task/'manifest.json');boundary,boundary_sha=load(task/'boundary_manifest.json')
    labels,labels_sha=load(task/'labels.json');predictions,predictions_sha=load(task/'predictions.json')
    protocol_sha=file_sha(protocol)
    wanted,wanted_boundary,wanted_labels,wanted_predictions=task_documents(traces,protocol_sha)
    require(manifest==wanted and boundary==wanted_boundary,'task changed from complete native-derived opportunity set')
    require(manifest_sha==digest(dumps(wanted)) and boundary_sha==digest(dumps(wanted_boundary)),
            'derived task byte encoding changed')
    require(labels==wanted_labels and predictions==wanted_predictions,'export requires untouched unknown/missing base task')
    index,index_sha=load(task/'clip_index_PRIVATE.json')
    require(index==[{'clipSha256':t.clip_sha,'localClipPath':str(t.clip.resolve())} for t in traces],'task clip identity changed')
    snapshots += [(task/'source_bindings_PRIVATE.json',binding_sha),(task/'manifest.json',manifest_sha),
                  (task/'boundary_manifest.json',boundary_sha),(task/'labels.json',labels_sha),
                  (task/'predictions.json',predictions_sha),(task/'clip_index_PRIVATE.json',index_sha),(protocol,protocol_sha)]
    by_run={t.run_id:t for t in traces};by_prefix={b['samplePrefix']:b for b in boundary['boundaries']}
    observations=[];audit=[]
    for sample in manifest['samples']:
        prefix=sample['sampleId'].rsplit('.',1)[0];bound=by_prefix[prefix];trace=by_run[bound['runID']]
        rep=trace.reps[bound['traceID']]
        row,detail=decision(trace,rep,sample['rule'],sample)
        observations.append(row);audit.append(detail)
    rule_hashes={t.rule_sha for t in traces};require(len(rule_hashes)==1,'bundle rule source mismatch')
    evidence={'schemaVersion':1,'contract':CONTRACT,'candidateCommit':manifest['candidateCommit'],
        'manifestSha256':manifest_sha,'protocolId':manifest['protocolId'],'protocolSha256':protocol_sha,
        'boundaryManifestSha256':boundary_sha,'ruleSourceSha256':next(iter(rule_hashes)), 'observations':observations}
    convert(evidence,manifest,manifest_sha,next(iter(rule_hashes)))
    states=dict(Counter(row['state'] for row in observations))
    policy=Path(__file__).resolve().parents[2]/'docs/evaluation/native_fault_export_policy_v1.md'
    snapshots.extend([(Path(__file__),file_sha(__file__)),(policy,file_sha(policy))])
    receipt={'contract':'bpt-native-fault-export-receipt-v1','status':'complete','candidateCommit':manifest['candidateCommit'],
        'manifestSha256':manifest_sha,'boundaryManifestSha256':boundary_sha,'protocolSha256':protocol_sha,
        'exporterSHA256':file_sha(__file__),'supportPolicySHA256':file_sha(policy),
        'evidenceSHA256':digest(dumps(evidence)), 'states':states,'opportunities':len(observations),
        'traceSHA256':[t.sha for t in traces],'fullClipSHA256':[t.clip_sha for t in traces],
        'executableSHA256':sorted({t.executable_sha for t in traces}),
        'scope':'native_evidence_development_only_not_independent_ground_truth',
        'inputHashesUnchanged':True,'decisions':audit}
    unchanged_artifacts(traces,snapshots)
    output.mkdir(mode=0o700)
    with (output/'evidence.json').open('xb') as destination:
        destination.write(dumps(evidence))
    write_new(output/'export_audit.json',receipt)
    return {k:receipt[k] for k in ('status','states','opportunities','evidenceSHA256','inputHashesUnchanged')}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    commands=parser.add_subparsers(dest='command',required=True)
    for command in ('prepare','export'):
        sub=commands.add_parser(command)
        sub.add_argument('--repo',required=True,type=Path)
        sub.add_argument('--protocol',required=True,type=Path)
        sub.add_argument('--output',required=True,type=Path)
        sub.add_argument('--bundle' if command=='prepare' else '--task',required=True,type=Path)
    args=parser.parse_args()
    try:
        result=prepare(args.bundle,args.repo,args.protocol,args.output) if args.command=='prepare' else export(args.task,args.repo,args.protocol,args.output)
        print(json.dumps(result,sort_keys=True))
    except (ContractError,ValueError,OSError) as error:
        print('native fault export rejected: '+str(error),file=sys.stderr)
        return 2
    return 0


if __name__=='__main__':
    sys.exit(main())
