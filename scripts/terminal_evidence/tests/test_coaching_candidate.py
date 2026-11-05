import copy
import importlib.util
from pathlib import Path
import pytest

spec=importlib.util.spec_from_file_location('candidate_fixture_helpers',Path(__file__).with_name('test_replay.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
r=h.r


def candidate(row):
    rules=[]
    for index,name in enumerate(['pushup.camera_body_line_transfer','pushup.projected_arm_range','pushup.bottom_target','pushup.top_extension_target']):
        rules.append({'id':name,'state':'positive_evidence' if index==0 else 'unknown','meaning':'deviation','target':'synthetic engineering comparison','configured':index==0,'reasons':[],'components':[{'metric':'cameraHipLineDeviationRatio','state':'positive_evidence' if index==0 else 'unknown','reasons':[],'rawValue':.2,'value':.2,'evaluatedValue':.2 if index==0 else None,'proof':{'kind':None,'count':0,'firstSourceIndex':None,'lastSourceIndex':None,'startPTS':None,'endPTS':None,'causal':True}}],'partialCoverage':False})
    payload={'schema':'bpt.core3-candidate-frame.v1','captureId':'synthetic-capture','evaluationMode':'causal','registryVersion':'20261103-r1','authority':'engineering_candidate_not_validated_form','experimentID':'synthetic','experimentDeclaredAt':'synthetic-test','variant':'floor','parameters':{'support.minimumJointScore':.5},'source':{key:row[key] for key in ('epoch','frame','source_index','source_pts','source_time_value','source_time_scale','time_basis')},'context':{**{key:row.get(key) for key in ('phase','side','side_view','source_kind','flush_tail','rotation','size','source_mirrored')},'exercise':'pushup'},'rules':rules,'windowResetReasons':[],'delivered':False}
    config={key:payload[key] for key in ('captureId','evaluationMode','registryVersion','experimentID','experimentDeclaredAt','variant','parameters')};config['schema']='bpt.core3-candidate-config.v1'
    return payload,config


def test_conditional_candidate_backward_compatibility_and_bound_positive(tmp_path):
    rows=h.capture();before=r.replay(h.write(tmp_path,rows));payload,config=candidate(rows[2]);rows[1]['coaching_candidate_config']=config;rows[2]['coaching_candidate']=payload
    after=r.replay(h.write(tmp_path,rows));assert before['groups']==after['groups']


@pytest.mark.parametrize('mutation,reason',[
    (lambda p:p['source'].update(epoch=9),'source_mismatch'),
    (lambda p:p.update(captureId='different'),'config_mismatch'),
    (lambda p:p.update(variant='other'),'config_mismatch'),
    (lambda p:p.update(parameters={'x':True}),'config_mismatch'),
    (lambda p:p.update(delivered=True),'delivery_claim'),
    (lambda p:p['context'].update(source_kind='video_frame'),'context_mismatch'),
    (lambda p:p['rules'][0].update(configured=False),'unconfigured_claim'),
    (lambda p:p['rules'][0]['components'][0].update(value=float('inf')),'candidate_summary_json'),
])
def test_candidate_source_scope_and_approval_rejection(mutation,reason):
    row=h.frame(0);payload,config=candidate(row);mutation(payload)
    with pytest.raises(r.InvalidCapture,match=reason):r.validate_candidate_summary({**row,'coaching_candidate':payload},{'exercise':'pushUp','coaching_candidate_config':config})


def test_positive_desired_match_is_not_a_fault_proposal():
    row=h.frame(0);payload,config=candidate(row);rule=payload['rules'][0];rule['meaning']='desired_match'
    proposal={'schema':'bpt.coaching-candidate-proposal.v1','captureId':payload['captureId'],'authority':payload['authority'],'presentation':'visual_only_no_tts','delivery':'proposed','source':payload['source'],'context':payload['context'],'proposalId':'0'*64,'ruleId':rule['id'],'predicateMeaning':'desired_match','predicateState':'positive_evidence','assessment':'deviation_candidate'}
    with pytest.raises(r.InvalidCapture,match='proposal_direction'):r.validate_candidate_summary({**row,'coaching_candidate':payload,'coaching_candidate_proposal':proposal},{'exercise':'pushUp','coaching_candidate_config':config})
