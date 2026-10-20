# 개인화 준비 자세 · 적응형 가림 제약 (ai/setup-constraint)

기준: `origin/ai/lift-app` 104ea89에서 분기. 사전등록: [setup_constraint_prereg.md](setup_constraint_prereg.md)(검증 결과 보기 전에 커밋, 변경 기록 포함). **모든 기능은 기본 끔이며, integration 병합이나 기본값 변경은 하지 않았다.**

## 1. 조사 — 기존 구현과 데이터 흐름 (코드로 확인)
1. **캘리브레이션 서버가 돌려주는 값**(`server/calibration_modal/worker.py build_result`, `body.py`):
   - `smplBeta` 10개(SMPL neutral v1.1.0, 키 `userHeightCm`에 투영)
   - `boneLengthData.segments`(cm, 휴식 자세): H36M17 부모–자식 16구간 + `shoulder_width`·`hip_width`. 두 너비는 `J_regressor_h36m` 관절 중심 사이 거리라 견봉 너비·골반 외곽 너비가 아니다.
   - `appDefinitionDiffers`(앱이 COCO 평균으로 합성하는 몸통·머리 6구간), `jointsH36m`(17×3 m, 휴식 자세), `quality`, `coachComment`, `calibratedAt`, `modelGlbUrl`(1시간 만료)
   - 발 길이·발끝·뒤꿈치·관절 가동성·그립 선호는 없다.
2. **앱 저장·전달**: 저장하지 않았다.
   - D-M-01 이후 분석 화면은 `receipt.jobId`를 로그로만 남긴다. `CalibrationUploadService.fetchJob`은 있으나 아무도 부르지 않는다.
   - 네이티브 `Pose3DConstraints.calibrationTargetsCm` 연결점은 있으나 늘 nil이라 뼈 길이는 세션 중앙값 또는 사전 비율을 쓴다.
   - 이 브랜치에서 플래그로 연결했다(4절).
3. **신체 치수**:
   - SMPL에서 바로 나오는 값: 어깨·골반 관절 너비, 위팔·아래팔·허벅지·정강이(좌우), 팔·다리 길이(합), 키.
   - 영상 관측이 필요한 값: 실제 발·손·그립 간격, 발 방향·발끝(COCO17·H36M17 출력에 없음, Halpe26은 `BPT_POSE_MODEL=halpe26` 옵션으로만), 가동성, 바 접촉 위치.
4. **3D 좌표**:
   - XS 출력은 골반 기준이고 축은 카메라 축이다(x 오른쪽, y 아래, z 깊이). 단위는 person-crop 정규화 단위(crop 변/2 = 1)라 미터가 아니다.
   - crop은 히스테리시스로 대부분 고정이지만, 바뀌면 단위도 함께 바뀐다.
   - 평가의 mm는 모캡 루트 깊이로 환산한 oracle 값이다. 앱에는 절대 스케일도 전역 위치도 없다. 중력 매핑(`BPT_3D_GRAVITY`)은 미검증이다.
5. **신뢰도·추적 품질**:
   - 관절별 RTMPose SimCC 최댓값 신뢰도(COCO → H36M 매핑, 합성 관절은 평균)가 XS 입력의 3번째 채널로 들어간다.
   - 추적: crop 추적기가 신뢰도 0.3 이상 관절 6개 이상이면 crop을 유지하고, 30프레임마다 다시 검사하며, 사람 전환 규칙이 있다.
   - 3D 상태: warming_up / tracking_lost / partial_3d / bad_3d / ok.
   - XS 자체의 3D 신뢰도 출력은 없다.
6. **준비 자세 검증**: 일반 게이트만 있다. setup_full_body(첫 렙 전 필수 관절 누락), tracking_lost, setup_side_view(로우 측면), pushup_hand_position(첫 렙 꼭대기 손목 위치, 로그 전용). 개인화된 간격 확인이나 "준비 완료" 판정은 없다.
7. **안정 상태 저장**: 세션 뼈 길이 중앙값(300프레임), FormWarningTracker 첫 3렙 기준선, crop 히스테리시스뿐이다. 관절·관계별 기준 상태와 접촉 상태는 없다.
8. **Flutter**:
   - 운동 화면은 정렬 안내 1.8초와 카운트다운 3초가 끝난 뒤에 네이티브 뷰를 만든다. 그래서 준비 자세 안내는 live 단계에서만 할 수 있다.
   - `onPoseUpdate.pose3d`로 3D 상태 배너를 띄운다. `camera_guide_screen`은 정적인 120° 사선 안내 그림이다.

## 2. 무엇을 만들었나 (모두 기본 끔)
| 부분 | 파일 | 켜는 법 | 하는 일 |
|---|---|---|---|
| 적응형 관계 제약 | `PosePipeline/AdaptiveRelationConstraint.swift` ↔ `pose_feedback/geometry/adaptive_relations.py` | Xcode scheme `BPT_ADAPTIVE_3D=1` | 아래 3절 |
| 연결점 | `MotionAGFormerLive.emitWindow` — `constraints.apply` 바로 뒤 한 곳 | – | `raw`(XS)·`pose3D`(제약) 그대로, `adapted`·`adaptive` 보고를 더함. 무효 관절 = 제약 ∪ 적응형. 끄면 비트 단위로 이전과 같음 |
| 준비 자세 | `Evaluators/ExerciseSetup.swift` ↔ `pose_feedback/body/exercise_setup.py` | Flutter `--dart-define=BPT_EXERCISE_SETUP=true` (creationParams `exerciseSetup`) | 운동별 척도 없는 항목·관측 품질·정지 기반 준비 완료·내 기준 비교, `onPoseUpdate.setup`(≤5 Hz, 첫 렙 전) |
| Flutter 패널 | `lib/features/workout/widgets/exercise_setup_panel.dart` | 같은 플래그 | 운동·변형, 체형 너비(cm 참고), 항목 비율, 품질(측정 중/측면 추정), 준비 상태, 내 기준이 있을 때만 조정 안내, 다시 설정·내 기준 저장 |
| 체형 결과 저장 | `lib/features/onboarding/services/calibration_result_store.dart` | 같은 플래그 | 접수 뒤 job polling → β·뼈 길이·키 저장(GLB 주소 저장 안 함), 운동 화면에 전달 |
| 오프라인 재생 | pose-replay `--adaptive on` | – | Swift 경로로 CSV 재생, `_3d.csv`에 adapted·채움·무효 |

흐름: 체형 캘리브레이션 → (운동 화면 live) 준비 자세 측정 → 관측이 안정되면 "준비 완료"(+ 관계 기준 시드) → 2D/3D → 제약 → 적응형 관계 제약(실험) → 3D 판정 → 피드백. 사용자 문구는 Flutter, 디버그 정보(채움·무효·관계 사건)는 VideoRunLog / kDebugMode에만.

## 3. 적응형 관계 제약의 규칙 (사전등록 2절과 같음)
- 관계 = 두 관절의 카메라 좌표 차 벡터(px). 두 접촉점(두 발, 바닥의 두 손, 같은 바를 쥔 두 손)이 그대로이고 카메라가 고정이면, 골반이 움직여도 차 벡터는 일정하다(골반이 빠짐). **세계 좌표 접촉 제약이 아니다** — XS에는 전역 위치가 없어 한 점의 접촉 위치는 복원하지 않는다.
- 운동별 관계(E0 근거): 스쿼트 {두 발목}, 푸시업 {두 발목, 두 손목, 같은 쪽 손목–발목 ×2}, 로우 {두 발목, 두 손목(그립 근사)}. 무릎·엉덩이·팔꿈치·몸통에는 관계를 걸지 않는다(크게 움직여야 하는 관절).
- 관측된 관절(신뢰도 ≥ reliable_conf)은 절대 바꾸지 않는다 → 확실히 관측된 실제 움직임·자세 오류는 그대로 남는다.
- 수립은 두 관절이 연속으로 관측될 때만(셋업 전에는 제약 없음). 작은 편차는 천천히 따라가고(점진 이동 수용), 큰 편차가 연속되면 재기준(실제 이동 수용, 되돌리지 않음).
- 한쪽만 안 보이면 w·(기준점 + 기준) + (1−w)·XS, w는 신뢰도 램프 × exp(−gap/decay). 불확실성은 gap에 따라 커지고, max_gap을 넘으면 보완을 멈추며 신뢰도가 매우 낮으면 그 관절을 무효(자세 지표에서 제외)로 표시한다.
- 선택 사항 ball 모드: XS 위치가 관계 예측에서 반지름(커지는 공) 안이면 그대로, 밖이면 공 위로만 당김.
