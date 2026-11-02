#!/usr/bin/env python3
"""Read-only pinned-source coaching audit. No models/media/network or config writes."""
import argparse
import csv
import functools
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]
BASE='2aed537ca3f4e01e6c6943631d03a80d2aecac5b'
CATALOG='20d897c279a693117706750cddac37454e5b663d'
FORM='ios/Runner/NativePose/Evaluators/FormWarnings.swift'
LINES='lib/features/workout/data/kori_feedback_lines.dart'
EXERCISES={'pushUp':'pushup','squat':'squat','barbellRow':'barbell-row'}
# Explicit semantic annotations; defaults/messages/flags/line anchors are extracted from pinned source.
# key: metric; aggregation/predicate; H36M joints; 2D dependencies; live phase; existing deep counterpart.
A={
'pushup_hip_sag':('hip_dev_max','max signed pelvis offset from thorax-to-ankle-midpoint line > hipSagDeviation',[0,8,3,6],[],'always',None),
'pushup_hip_pike':('hip_dev_min','min signed pelvis offset < -hipPikeDeviation',[0,8,3,6],[],'always',None),
'pushup_shallow':('elbow_min','current minimum elbow - median(first 3 earlier rep minima) > shallowOverBaselineDegrees','selected shoulder/elbow/wrist',[],'bottom','pushup_depth_drift'),
'pushup_no_lockout':('elbow_max','max(all earlier maxima + current maximum) - current maximum > noLockoutBelowSetMaxDegrees','selected shoulder/elbow/wrist',[],'top',None),
'pushup_head_drop':('head_dev_change_max','max head-centre line deviation - first valid deviation in rep > headDropDeviation',[10,0,8],[],'none',None),
'pushup_head_up':('head_dev_change_min','min head-centre line deviation - first valid deviation in rep < -headUpDeviation',[10,0,8],[],'none',None),
'pushup_hand_position':('first_rep_top_wrist_ahead','first rep only: wrist headward projection/arm length at maximum-elbow frame outside [-handBackwardRatio,+handForwardRatio]','selected shoulder/elbow/wrist plus 0/8',[],'none',None),
'pushup_depth_fade':('elbow_min','mean(last 3 minima incl current) - mean(first 3 minima) > depthFadeDegrees; >=6 reps','selected shoulder/elbow/wrist',[],'none',None),
'squat_hips_first':('hips_first_torso_rise + hip/shoulder rise speed','after first minimum-knee frame over up to 8+1 frames: max wrapped torso rise>8deg AND normalized 2D hip rise/frame > shoulder rise/frame','selected hip/knee/ankle plus 0/8/1/4',['selected 2D hipY, shoulderY, torsoLength; actual frame index delta'],'ascending',None),
'squat_shallow':('knee_min','current minimum knee - median(first 3 earlier rep minima) > shallowOverBaselineDegrees','selected hip/knee/ankle',[],'bottom','squat_depth_drift'),
'squat_no_lockout':('knee_max OR hip_angle_max','running set max - current max >10deg for knee OR hip; includes current in set max','selected shoulder/hip/knee/ankle',[],'top',None),
'squat_lean_drift':('torso_at_bottom','mean(last3 torso at first minimum-knee frame) - mean(first3) > leanDriftDegrees; >=6 reps','selected hip/knee/ankle plus 0/8/1/4',[],'none',None),
'squat_depth_fade':('knee_min','mean(last3 minima incl current) - mean(first3 minima) > depthFadeDegrees; >=6 reps','selected hip/knee/ankle',[],'none',None),
'squat_knee_valgus':('knee_ankle_gap_ratio_min','front view only: minimum projected knee gap/ankle gap from lowest 2D hip frame through end <1.0',[1,4,2,5,3,6],['2D selected hipY selects bottom'],'bottomOrAscending',None),
'squat_heel_rise':('heel_rise_max','first valid heelToe - min heelToe >heelRiseShinRatio; heelRiseEnabled=false',[],['Halpe26 heel/toe, shin; min foot confidence0.30; no 3D heelToe assigned'],'none',None),
'row_torso_swing':('torso_max - torso_min','max-min of per-rep unwrapped signed torso angle >torsoSwingRangeDegrees',[0,8,1,4],[],'inRep',None),
'row_standing_up':('torso_mean','wrap(median(first3 earlier torso means)-current torso mean)>standingUpDegrees',[0,8,1,4],[],'inRep',None),
'row_short_pull':('elbow_behind_max','median(first3 earlier maxima)-current max normalized elbow-behind-torso >shortPullBelowBaseline','selected elbow plus 0/8/1/4',[],'top',None),
'row_head_up':('head_dev_change_min','min head-centre line deviation-first valid deviation < -headUpDeviation',[10,0,8],[],'none',None),
'row_shrug':('ear_shoulder_drop','1 - min eligible earShoulder/start >shrugEarShoulderDrop; head angle change<=15deg; shrugEnabled=false',[],['2D ear/shoulder/head angle; earShoulder/headAngle NOT assigned in 3D'],'none',None),
}
PARAMS={
'pushup_hip_sag':['hipSagDeviation'],'pushup_hip_pike':['hipPikeDeviation'],'pushup_shallow':['shallowOverBaselineDegrees'],
'pushup_no_lockout':['noLockoutBelowSetMaxDegrees'],'pushup_head_drop':['headDropDeviation'],'pushup_head_up':['headUpDeviation'],
'pushup_hand_position':['handForwardRatio','handBackwardRatio'],'pushup_depth_fade':['depthFadeDegrees'],
'squat_hips_first':['hipsFirstWindowFrames','hipsFirstTorsoRiseDegrees'],'squat_shallow':['shallowOverBaselineDegrees'],
'squat_no_lockout':['noLockoutBelowSetMaxDegrees'],'squat_lean_drift':['leanDriftDegrees'],'squat_depth_fade':['depthFadeDegrees'],
'squat_knee_valgus':['valgusKneeAnkleGapRatio'],'squat_heel_rise':['heelRiseEnabled','heelRiseShinRatio','footMinConfidence'],
'row_torso_swing':['torsoSwingRangeDegrees'],'row_standing_up':['standingUpDegrees'],'row_short_pull':['shortPullBelowBaseline'],
'row_head_up':['headUpDeviation'],'row_shrug':['shrugEnabled','shrugEarShoulderDrop','shrugMaxHeadAngleChangeDegrees']}
CONFIGS={'pushUp':'PushUpFormConfig','squat':'SquatFormConfig','barbellRow':'BarbellRowFormConfig'}
FILES=[FORM,LINES,'ios/Runner/NativePose/Camera/CameraPosePreview.swift','ios/Runner/NativePose/Camera/VideoCameraSource.swift',
'ios/Runner/NativePose/PosePipeline/MotionAGFormerLive.swift','ios/Runner/NativePose/PosePipeline/PoseCoordinateTransforms.swift','ios/Runner/NativePose/Types/NativePoseExercise.swift',
'lib/features/workout/screens/native_pose_workout_screen.dart','lib/services/kori_voice_service.dart',
'ios/Runner/NativePose/Bridge/KoriSpeaker.swift','ios/Runner/NativePose/Bridge/WorkoutSessionBridge.swift',
'server/calibration_modal/deep_metrics.py','server/calibration_modal/deep_worker.py','server/calibration_modal/deep_rules.csv','server/calibration_modal/modal_app.py']

@functools.lru_cache(None)
def source(commit,path):return subprocess.check_output(['git','-C',str(ROOT),'show',commit+':'+path]).decode()
def digest(text):return hashlib.sha256(text.encode()).hexdigest()
def line(text,needle,start=0):
 at=text.index(needle,start);return text[:at].count('\n')+1

def ref(path,needle,commit=BASE,start=0):return {'commit':commit,'path':path,'line':line(source(commit,path),needle,start)}
def config(text,name):
 start=text.index('struct '+name);end=text.index('\n}',start)
 result={}
 for match in re.finditer(r'\bvar (\w+) = (-?\d+(?:\.\d+)?|true|false)\b',text[start:end]):
  value=match[2];result[match[1]]=value=='true' if value in ('true','false') else float(value) if '.' in value else int(value)
 return result,start

def build():
 text=source(BASE,FORM);messages={key:ko for key,ko in re.findall(r"key:\s*'([^']+)'.*?ko:\s*'([^']*)'",source(BASE,LINES),re.S)}
 def declared_set(name):
  body=re.search(r'static let '+name+r': Set<String> = \[(.*?)\]',text,re.S)[1]
  return set(re.findall(r'"([^"]+)"',body))
 quiet=declared_set('quietByDefault');held=declared_set('keysWithoutFlutterLines')
 table=text[text.index('static let rules:'):text.index('static let allKeys')]
 groups={exercise:re.findall(r'\("([^"]+)", \.(\w+)\)',body) for exercise,body in re.findall(r'\.(\w+): \[(.*?)\]',table,re.S)}
 native=[];seen=set()
 for exercise,flutter in EXERCISES.items():
  cfg,offset=config(text,CONFIGS[exercise])
  for key,grade in groups[exercise]:
   if key=='setup_side_view':continue
   seen.add(key);metric,predicate,joints,hybrid,phase,counterpart=A[key]
   condition_enabled=not(key=='squat_heel_rise' and not cfg['heelRiseEnabled'] or key=='row_shrug' and not cfg['shrugEnabled'])
   delivery=key not in quiet|held
   mode='rep_bubble_and_text_voice_candidate' if grade!='reference' else 'set_end_recorded_count_only_in_current_Flutter'
   if not delivery:mode='filtered_delivery_still_judged_logged_and_overlay_if_present'
   if not condition_enabled:mode='condition_feature_OFF'
   native.append({'exercise':flutter,'key':key,'grade':grade,'metric':metric,'repPredicate':predicate,
    'defaultThresholds':{name:cfg[name] for name in PARAMS[key]},'thresholdRefs':[ref(FORM,'var '+name, start=offset) for name in PARAMS[key]],
    'requiredH36MJoints':joints,'additional2DDependencies':hybrid,'liveOverlayPhase':phase,
    'liveOverlayFullPredicate':False if key=='squat_hips_first' else phase!='none',
    'liveOverlayNote':'angle part only; hip-vs-shoulder speed predicate not drawn' if key=='squat_hips_first' else 'quiet keys are not removed from overlay measurements',
    'defaultConditionEnabled':condition_enabled,'defaultDeliveryKeyEnabled':delivery,'effectiveDefaultPostureDelivery':condition_enabled and delivery,
    'current3DMetricAvailable':key not in ('squat_heel_rise','row_shrug'),'deliveryMode':mode,'actualDartMessageKo':messages[key],
    'judgeRef':ref(FORM,'fire("'+key+'"'),'aggregationRef':ref(FORM,'func metrics2D('),'geometryRef':ref(FORM,'private func measure3D('),
    'existingDeepCounterpart':counterpart,'comparison':'conditional_same_scalar_formula_not_default_warning_parity' if counterpart else 'no_existing_equivalent_deep_rule',
    'expertValidated':False})
 if seen!=set(A):raise ValueError('native posture-rule annotations incomplete or stale')
 raw=source(BASE,'server/calibration_modal/deep_rules.csv');deep=list(csv.DictReader(io.StringIO(raw)))
 catalog=source(CATALOG,'docs/coaching/fault_catalog.csv');proposed=list(csv.DictReader(io.StringIO(catalog)))
 for item in native:
  row=next((r for r in proposed if r['fault_id']==item['key']),None)
  item['catalogProposal']=None if row is None else {k:row[k] for k in ('metric_definition','threshold_standard','measurable_now','needs','phase')}
  if row is not None:item['catalogProposalRef']=ref('docs/coaching/fault_catalog.csv','\"'+item['key']+'\"',commit=CATALOG)
 common,_=config(text,'FormCommonConfig')
 allkeys={key for rows in groups.values() for key,_ in rows}|{'praise_fixed','praise_good','setup_full_body','tracking_lost'}
 result={'schema':'bpt.coaching-rule-crosswalk.v1','scope':'pinned_source_audit_no_runtime_accuracy_or_default_changes','baseCommit':BASE,
 'sourceSha256':{path:digest(source(BASE,path)) for path in FILES},'nativePostureRules':native,
 'globalDefaultDeliveryKeys':sorted(allkeys-quiet-held),'quietDeliveryKeys':sorted(quiet),'explicitDraftDeliveryHeld':sorted(held),
 'nativeCommon':{'defaults':common,'sourceRef':ref(FORM,'struct FormCommonConfig'),
   'jointMap':{'left':[11,12,13,4,5,6],'right':[14,15,16,1,2,3]},
   'coordinates':'XS H36M17 camera/model space x-right,y-down,z-away; pelvis-relative; defaultup=(0,-1,0); gravity opt-in unverified mapping',
   '3DFrameEligibility':'MotionAGFormer:>=6 COCO joints confidence>=0.3; 27window,L5,C1; constraints invalid joints ->NaN, ok/partial usable',
   '3DRepEligibility':'usable3D samples>=0.5 of recorded2Dframes; permetric finite compactMap; no per-rule fullcoverage guarantee',
   'side':'per-frame mean confidence of 7 body joints(ear/shoulder/elbow/wrist/hip/knee/ankle) per side,hysteresis0.08; report side=majority; may switch within rep',
   'required2DJointSets':{'pushup':'selected shoulder/elbow/wrist/hip/ankle','squat':'selected shoulder/hip/knee/ankle','barbell-row':'selected shoulder/elbow/wrist/hip'},
   'view':'frame front if 2D shoulderwidth/torsolength>=0.5; nativejudge pushup/squat uses frontfraction<0.5; row verifiedrollinggate<=0.66 else samefraction',
   'counterView':'pushup rollingcut1.0,row0.66,30minimum/150window/hysteresis0.03; counting is not form eligibility',
   'missingViewAndReferencePolicy':'legacyjudge may compute positive evidence with missing view/defaultside or partialcompactMapreference; assessed-for-praise and liveoverlay stricter; intentional-policy/coverage difference, not proven defect',
   'baseline':'first3 earlier reps median, not approved-correct target; running-setmax includescurrent; trend first3 vs last3 requires6 and3values/group',
   'delivery':'priority immediate; improve only if samekey previouslyfired; cooldown3; one selected nonreference perrep; referenceendSetcounts; enabled filtering afterjudgement',
   'sourceRefs':[ref(FORM,'func observe('),ref(FORM,'func finishRep('),ref(FORM,'func judge('),ref(FORM,'private func deliver(')]},
 'commonFeedback':[{'key':key,'ko':messages[key]} for key in ('setup_side_view','setup_full_body','tracking_lost','praise_good','praise_fixed')],
 'defaultExerciseStatus':{'pushup':'count+3D+4effectiveposturekeys','squat':'count+3D+4effectiveposturekeys','barbell-row':'count+3D+4effectiveposturekeys',
   'benchpress':'count+3D path present;3posture delivery drafts held;no liveposture table','deadlift':'count+3D path present;3posture delivery drafts held;no liveposture table'},
 'current3DInputConfidence':'COCO->H36M inferred centres average endpoint confidence; square crop normalization passes raw confidence through; accepted hand wrist XY replacements retain RTMPose confidence',
 'currentConfigurationOwners':['CameraPreviewOptions','FormCommonConfig','NativePoseWorkoutScreen.supportedExerciseIds'],'AppSettingsTypeFound':False,
 'flags':{'BPT_CAMERA_3D':'defaultON unless0; missingmodelfails,no2Dfallback','BPT_3D_LOOKAHEAD':'5','BPT_3D_CADENCE':'1','BPT_3D_ASYNC':'defaultON',
   'BPT_3D_HAND_WRISTS':'defaultON acceptedMediaPipewrists; RTMPoseconfidence retained','BPT_3D_GRAVITY':'defaultOFF','BPT_ADAPTIVE_3D':'defaultOFF',
   'BPT_PUSHUP_SUPPORT_CORRIDOR':'defaultOFF; contactunknownlive','BPT_WRIST_ANCHOR':'defaultOFF','BPT_EXERCISE_SETUP':'defaultOFF',
   'BPT_TERMINAL_CANDIDATE':'defaultOFF diagnostic only, no counter/coaching edits','BPT_FEEDBACK_ALL_KEYS':'test-only defaultOFF'},
 'deepFallback':{'rules':deep,'totalRows':len(deep),'applicableCounts':{exercise:sum(r['exercise_id'] in ('*',exercise) for r in deep) for exercise in EXERCISES.values()},
   'genericKeys':[r['fault_id'] for r in deep if r['exercise_id']=='*'],
   'eligibility':'whole applicable metric span finite+observed tracking+joint support>=0.35; baselinefirst3 all supported; first3drifts withheld',
   'coordinates':'gravity-aligned GVHMR world y-up; primaryside fixed for whole native video_ms interval; knee/hip/elbow acos-angle',
   'torso':'unsigned angle(midshoulders11/14 - midhips1/4,+worldY), std; not native signed0->8 max-min; not lumbar curvature',
   'handPath':'midpoint BOTH wrists relative to pelvis midpoint, metres, trajectory; not physical palm/floor placement',
   'comparison':'evaluatedKeys only nonempty device_key mappings; generic4 haveblankkeys; not all-rule coverage',
   'placeholder':True},
 'sourceLineReferences':{'coordinates':ref('ios/Runner/NativePose/PosePipeline/PoseCoordinateTransforms.swift','static func coco17ToH36M17'),
   'frameMask':ref('ios/Runner/NativePose/PosePipeline/MotionAGFormerLive.swift','let invalid = report.invalidJoints'),
   'overlay':ref(FORM,'static let table: [FormExercise: [OverlayRule]]'),
   'viewAndPositiveEvidence':ref(FORM,'let sideView = (exercise == .barbellRow'),
   'spokenAndSetRoute':ref('lib/features/workout/screens/native_pose_workout_screen.dart','void _onNativeSetSummary'),
   'activeVoice':ref('lib/services/kori_voice_service.dart','static Future<void> speak'),
   'deepLoader':ref('server/calibration_modal/deep_metrics.py','def load_rule_catalog'),
   'optionalCatalogPackaging':ref('server/calibration_modal/modal_app.py','if catalog.is_file():')},
 'conditionalFormulaMappings':[{'native':'pushup_shallow','deep':'pushup_depth_drift','thresholdDeg':15},
   {'native':'squat_shallow','deep':'squat_depth_drift','thresholdDeg':15}],
 'conditionalMappingPrerequisites':['same native video_ms interval/sample selection','stable per-frame selected side equals manifest side','same nondegenerate interior-angle joint triples',
    'full finite requiredjoint evidence','all first3 baseline extrema available','same camera/view/coordinate and source eligibility','rep>=4','quiet/default delivery remains separate'],
 'catalogProposal':{'commit':CATALOG,'path':'docs/coaching/fault_catalog.csv','sha256':digest(catalog),'rows':len(proposed),'exerciseCounts':dict(__import__('collections').Counter(r['exercise'] for r in proposed)),
   'ancestorOfAuditedBase':subprocess.run(['git','-C',str(ROOT),'merge-base','--is-ancestor',CATALOG,BASE]).returncode==0,
   'authority':'separate coaching documentation proposal, not approved runtime config or independent expert labels',
   'autoDiscoveryPathPresentAtBase':False,
   'frozenPackageCatalogPresent':{commit:subprocess.run(['git','-C',str(ROOT),'cat-file','-e',commit+':docs/coaching/fault_catalog.csv'],capture_output=True).returncode==0 for commit in ('8e00f543a70dd85b93b6ed716c1377a70586dffd','17583f391f6dd028bf0515b2be3e8d2257c95866')},'copyingWouldChangeDefaultRules':True,
   'loaderEffect':'TEAMschema returns zero generic rules+unassessed catalog; two exact depthfade observations remain withheld for unconfirmed view/variant/plannedROM'},
 'nonComparable':{'row_torso_swing':'native signed unwrap max-min>39.9 vsdeep unsigned different-landmark std>8 vsproposalP95-P05>15',
   'squat_knee_valgus':'projected bilateral knee/ankle GAP ratio vsdeep bilateral primary ANGLE difference, not equivalent',
   'no_lockout':'running observed setmax deficit vsabsolute full-extension target; deeprom_drop is fullROM change, not lockout',
   'depth_fade':'native last3-first3 mean vsfallback single-rep-first3median; proposedcatalog observation is distinct/alwayswithheld',
   'lumbar_flexion':'not directly measured; single torso inclination/head-centroid/spine proxy is not lumbar curvature',
   'wrist_placement':'root-relative XS cannot establish physical hand-floor contact/anchorage; serverpelvis-relative wristpath is not hand-under-shoulder placement'},
 'nextSafeIntegration':'shadow-only versioned shallow-extremum scalar comparison with explicit per-rule view/coverage/stable-side/fullbaseline provenance; keep incomparable/unknown separate; no CSVcopy, threshold or default activation',
 'accuracyClaimed':False,'appChanges':False,'modelCalls':0,'phoneCalls':0}
 return result

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output');args=parser.parse_args();result=build()
 if args.output:
  path=Path(args.output)
  if path.suffix!='.json':parser.error('audit JSON only; never write catalog/config files')
  with path.open('x') as target:json.dump(result,target,indent=2,ensure_ascii=False);target.write('\n')
  print(json.dumps({'baseCommit':BASE,'postureRuleCandidates':len(result['nativePostureRules']),'effectiveDefaultPostureKeys':sum(r['effectiveDefaultPostureDelivery'] for r in result['nativePostureRules']),'deepFallbackRows':result['deepFallback']['totalRows'],'catalogProposalRows':result['catalogProposal']['rows']}))
 else:print(json.dumps(result,indent=2,ensure_ascii=False))

if __name__=='__main__':main()
