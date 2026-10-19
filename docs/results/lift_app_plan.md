# 실시간 3D AI PT — 조사와 구현 계획 (ai/lift-app, 2026-10-19)

목표(사용자 2026-10-19): iPhone에서 실시간 3D 자세 추정 → 3D 운동 분석 → 자세 평가 → 교정 피드백.
렙 카운트는 보조(P2). 성공 판단 기준은 렙 정확도가 아님.

필수 파이프라인: 카메라 → 사람 검출·추적(RTMPoseCropTracker) → RTMPose 2D → 손목 crop MediaPipe 손 → XS 입력 손목 교체
→ MotionAGFormer-XS(27프레임) → 3D → 해부학 제약(뼈 길이 → 관절 각도) → 3D 운동 분석 → 자세 평가 → 피드백(Flutter).

기준 커밋: integration/ai `c113150`. 이 문서의 "현재"는 그 커밋 기준. 줄 번호는 그 커밋의 파일 기준.

---

## (a) 조사

### a1. 3D 리프팅이 왜 앱에서 꺼져 있었나
- 플래그 `CameraPreviewOptions.enableMotion3DForCamera = false` (ios/Runner/NativePose/Camera/CameraPosePreview.swift:19).
  이 값은 로그 한 줄(:352)에만 쓰이고 3D 실행 코드는 카메라 경로에 없다. `processFrame`(:355–428)은 RTMPose → 손 분기
  → `CameraProcessingResult`, `runEvaluator`(:464–499)는 모든 평가기를 `pose3D` 없이 부른다. 모델도 Runner 번들에 없다
  (ios/Runner/NativePose/Models: rtmpose_m/s/s_halpe26, hand_landmarker.task만).
- 결정 기록(모두 **에이전트 결정**, 사용자 지시 아님 — 상세 근거는 lift_app.md §Q1에 커밋·대화 증거로 정리):
  - D-D-02 (docs/decisions.md, 2026-10-11) "라이브 카메라 3D는 계속 끈다, 3D 지표는 경고에 쓰지 않는다".
    근거로 든 것: D-D-01(측면에서는 2D가 같거나 더 정확, 사선에서는 3D 오차 7–19°), 3D 실행 코드 없음, 번들에 모델 없음,
    5프레임(167 ms) 지연 정렬 작업 필요, "얻는 정확도가 없다".
  - D-D-05: 비용 +17 ms/프레임, CPU +13%p (`tools/ios_live3d_cost`, 무작위 입력, 모델 추론만).
  - D-D-06 / D-D-07: Fit3D 미세조정 XS는 "앱에 아직 안 넣음" — 틀린 자세 영상 없음, 몸통(카메라 위 기준) 악화, 피험자 1–3명, +17 ms, 비상업.
  - D-C-06: 기기 전체 파이프라인 측정에서 3D 켜면 무제한 FPS −40%, 30 fps 페이스 p95 33.2 ms(예산 끝) → 켜지 않음.
- 즉 "꺼졌다"기보다 **처음부터 카메라 경로에 붙은 적이 없고**(플래그는 a949023 첫 네이티브 카메라 커밋부터 false),
  이후 에이전트가 정확도 이득 부재·비용을 이유로 계속 끄기로 결정했다. 목표가 "3D PT"로 재정의된 지금 그 근거
  ("3D 지표는 경고에 안 씀")는 목표와 맞지 않는다.

### a2. 기존 3D 자세 분석 로직은 어디까지 구현됐나
| 부분 | 위치 | 상태 |
|---|---|---|
| COCO17 → H36M17 매핑 | PoseCoordinateTransforms.swift:168–191 ↔ motionagformer_adapter.py `_coco2h36m_xy` | 구현·Python과 같은 식 |
| XS 입력 정규화(D-12 person_crop) | PoseCoordinateTransforms.swift:269–344 ↔ adapter.py `PersonSquareCropTracker` | 구현, 패리티 테스트 있음(MotionAGFormerNormalizationTests ↔ tests/fixtures/motionagformer_normalization_cases.json) |
| 27프레임 창·lookahead 5·선택 행 21 | pose-replay main.swift:179–201(오프라인, 미래 프레임 사용 가능) ↔ live_motionagformer.py | **오프라인 전용**. 라이브(과거만) 버퍼·지연 정렬 없음 |
| 3D 지표 | FormWarnings.swift:279–305 `signedTorsoAngle3D`, `signedHipDeviation3D`, :483–504 observe, :819–832 `metrics3D` | 몸통 각·엉덩이 편차 2개만, **로그 전용** |
| 3D 판정 | FormWarnings.swift:12–13 "Warnings fire from 2D only", :843 `judge`는 metrics2D만 받음 | **없음** |
| 무릎 과신전 감지/보정 | KneeHingeLimit.swift (감지 ON, 보정 OFF) | 감지만 FormWarnings:495에서 "3D 불량" 표시. 보정 OFF(D-12, D-D-03) |
| 뼈 길이 제약 | BoneLengthConstraint.swift (캘리브레이션 cm 비율) | 구현만, **어디에도 연결 안 됨** (주석 :13 "Not wired") |
| 평가기 3D 입력 | Squat/PushUp/BarbellRow `evaluate(..., pose3D:)` (SquatEvaluator.swift:141, PushUpEvaluator.swift:264, BarbellRowEvaluator.swift:119) | 매개변수만 있고 앱은 nil. Bench/Deadlift는 매개변수 없음(Deadlift `selected3D`는 "available" 플래그만) |
| 브리지 | WorkoutSessionBridge.swift:7–13: onPoseUpdate {rep, status, done}, onFeedback {key,n,scope}, onSetEnd | 3D 상태 필드 없음 |

### a3. 자세 오류 감지 키 (현재 상태)
기본 켜짐(`FormCommonConfig.enabledFeedbackKeys`, FormWarnings.swift:59 + 로우 init :447): **setup_full_body, tracking_lost, setup_side_view(로우)** — 셋 다 2D(관절 신뢰도·어깨폭 비).
나머지는 전부 **판정은 돌지만 Flutter로 안 보냄(로그 전용, D-02·D-T3-06)**, 전부 **2D**:

| 운동 | 키 (등급) | 쓰는 2D 지표 | 3D 사용 |
|---|---|---|---|
| 푸시업 | pushup_hip_sag(우선), pushup_hip_pike(개선), pushup_shallow(개선), pushup_no_lockout(참고), pushup_head_drop(참고), pushup_head_up(참고), pushup_hand_position(셋업), pushup_depth_fade(참고), setup_side_view(셋업, 푸시업은 꺼짐) | 엉덩이 선편차, 팔꿈치 각, 귀 선편차, 손목 앞섬 | 없음 |
| 스쿼트 | squat_hips_first(우선), squat_knee_valgus(우선, 정면), squat_shallow(개선), squat_heel_rise(개선, **판정도 꺼짐** D-03), squat_no_lockout(참고), squat_lean_drift(참고), squat_depth_fade(참고) | 무릎·엉덩이 각, 몸통 각, 엉덩이/어깨 상승 속도, 무릎/발목 간격 비, 뒤꿈치 | 없음 |
| 바벨로우 | row_torso_swing(우선), row_standing_up(개선), row_short_pull(개선), row_shrug(개선, **판정도 꺼짐**), row_head_up(참고) | 몸통 각 범위·평균, 팔꿈치 뒤 거리, 귀 선편차, 귀–어깨 거리 | 없음 |
| 벤치·데드 | bench_* 3개, deadlift_* 3개 (전부 꺼짐, D-G-04) | 2D | 없음 |

3D가 하는 일은 지금 단 두 가지: 렙 보고서의 `metrics_3d`(몸통 min/max/mean, 엉덩이 편차 min/max) 로그와 "3D 불량" 프레임 수.

### a4. 2D만 쓰는 기능
렙 카운트(5개 평가기 상태기계 전부), 모든 자세 키(위 표), 측면 게이트(어깨폭/몸통 비), setup_full_body·tracking_lost,
캘리브레이션(체형 측정, s COCO17), 손 분기(MediaPipe 손 — **그림 표시용만**, 아래 a7), 렙 보고서·세트 요약·worstJoint.

### a5. Fit3D 미세조정 XS 검증 범위 (D-D-06, D-D-07)
- **잰 것**: Fit3D 모캡 정답 대비 MPJPE / PA-MPJPE / 가속도 오차(검증 피험자 s07–s11, 60영상: 원래 XS 148 / 89 / 8.6, 미세조정 52 / 38 / 4.5 mm),
  렙 극값·프레임 각도 오차(무릎·엉덩이·팔꿈치·몸통, 카메라 위 vs 중력 기준), Exercise3D(정답 아님) 상대 비교, 3D 불량 비율(Ex3D 푸시업 35.3% → 0.9%).
  입력은 앱과 같은 2D(pose-replay crop, RTMPose-m), 창 27·lookahead 5 — **PyTorch 체크포인트로** 잼.
- **안 잰 것**: 틀린 자세 검출률·오경보율(라벨 없음), 측면 카메라 정답(Fit3D에 측면 없음 → 측면 몸통·푸시업 팔꿈치 악화 원인 미검증),
  Core ML 변환본의 수치 동일성, 기기 속도, 손목 교체 입력, 해부학 제약 적용 효과, 피험자 3명 이상 학습 일반화(s03–s05만).
- 체크포인트 보관·Core ML 변환 여부와 라이선스 영향은 lift_app.md §Q5에 경로·sha256으로 정리.
  Fit3D는 비상업·재배포 금지 → **Fit3D로 학습한 가중치를 앱에 넣어 배포하는 것은 라이선스 판단이 필요**(캡스톤 비상업 시연 범위와 다름). 결정은 사용자 몫.

### a6. 실제 iPhone에서 3D PT를 돌리려면 남은 것
1. 카메라 경로에 XS 실행 코드(과거 프레임만 쓰는 27프레임 버퍼, 5프레임 지연 정렬) — 없음.
2. XS Core ML을 번들에 포함(브랜치 한정, 병합은 사용자 승인) — 원래 XS는 `assets/coreml/motionagformer_xs.mlpackage`(gitignore, 메인 체크아웃에만 있음).
3. 3D 기반 자세 판정 — 없음(a2).
4. 3D 상태(채우는 중 / 추적 끊김 / 3D 불량)를 평가기·Flutter에 명시 — 없음.
5. 해부학 제약 연결과 무릎 보정 원인 수정 — 없음.
6. 손목 교체를 XS 입력에 연결 — 없음(a7).
7. 기기 측정: 개발자 프로필 신뢰 문제(handoff)로 막혀 있었음 — 다시 시도 필요.
8. 틀린 자세 라벨 영상 — 없음(D-T3-06). 이것이 없으면 자세 평가의 정확도는 검증할 수 없다.

### a7. 손 분기 → 손목 교체
- 켜진 운동: 스쿼트를 뺀 전부(`NativePoseExercise.handBranchEnabled`, NativePoseExercise.swift:10–13, 주석 "Hands are overlay-only today. Skip the two auxiliary models for lower-body squat").
- Swift: `HandCropBuilder.visualBodyKeypoints`(HandCropBuilder.swift:73–86)가 MediaPipe 손목으로 **그림용 `visualCoco17`만** 바꾸고,
  평가기는 `rawCoco17`(CameraPosePreview.swift:432)을 받는다. XS 입력에 들어가는 Swift 경로는 없다(3D 자체가 없음).
- Python: `motionagformer_wrist_source.build_motionagformer_input_2d(wrist_source="mediapipe")`가 XS 입력 사본의 손목 x/y만 바꾸고 RTMPose 신뢰도 유지,
  `reject_crossed_mediapipe_wrists`가 반대 손 검출을 버림. 커밋 `5a19403`(2026-09-26): Fit3D s12 스쿼트에서 손 crop을 사람 높이 비율 0.15로 바꿔
  손목 jitter 16.8 → 7.7 px, 그래도 손 단계 미사용 4.3 px보다 높아 **기본 비활성**.
- Swift 손 crop은 고정 256 px(CameraPreviewOptions.handCropSize), Python의 사람 높이 비율·반대 손 제거가 Swift에는 없다.

---

## (b) 운동별 AI PT 명세 (3D 기준)

공통 표기: H36M17 관절(0 골반, 1/4 R/L 엉덩이, 2/5 무릎, 3/6 발목, 7 척추(합성), 8 흉곽(어깨 중점), 9 목(코–흉곽 중점), 10 머리(두 눈 중점),
11/14 L/R 어깨, 12/15 팔꿈치, 13/16 손목). XS 출력은 골반 기준, y 아래, crop 단위(미터 아님) → **비율·각도만** 쓴다.
"수직"은 지금 카메라 y축(기기 기울기가 그대로 섞임, D-D-07). 중력(CoreMotion)은 캘리브레이션에만 연결돼 있음(DeviceMotionMonitor.swift) → 몸통 기울기류는 P1에서 중력 기준으로 바꿔야 함.
모든 임계값은 **초안(사용자 승인 전)**. "근거"가 2D 정상 렙 분포인 값은 3D에 그대로 맞는다는 근거가 없음.
피드백 문구는 **초안**. 검증 공통: 틀린 자세 라벨 데이터가 어디에도 없음(D-T3-06) → 검출률은 전부 "검증 불가 — 필요한 데이터: 키별 틀린 자세 세트 5–8렙 + 같은 사람 정상 세트(D-T3-06 목록)".
정상 렙(Fit3D·Exercise3D 트레이너 시범)에서의 **오경보율**과 Fit3D 모캡 대비 **지표 오차**만 잴 수 있다.

### 스쿼트
| 오류 | 3D 판정 양 | 기준(초안) / 근거 | 피드백(초안) | 검증 |
|---|---|---|---|---|
| 깊이 부족 squat_shallow | 무릎 내각 최소(엉덩이–무릎–발목), 렙별 | 첫 3렙 중앙값보다 15° 이상 덜 굽힘 / 근거 없음 — 임계값 미정(2D 임시값 이식). 절대 기준(허벅지 수평 ≈ 무릎 굽힘 ~90°+)은 중력 필요 | "조금 더 깊이 앉아 볼게요" | 지표: Fit3D 무릎 각 오차. 검출: 검증 불가 |
| 덜 일어섬 squat_no_lockout | 무릎·엉덩이 내각 최대 | 세트 최대보다 10° 이상 작음 / 근거 없음 | "끝까지 일어서서 무릎을 펴 주세요" | 동일 |
| 엉덩이 먼저 squat_hips_first | 바닥 후 8프레임: 몸통 기울기 증가(°)와 골반 대비 흉곽 상승 속도 | 몸통 +8° 이상 & 골반이 더 빨리 상승 / 근거 없음 | "가슴과 엉덩이를 같이 올려요" | 동일 |
| 무릎 모임 squat_knee_valgus | 좌우 무릎 간격 ÷ 발목 간격(골반 L→R 축에 사영) — 3D라 정면 아니어도 계산 | < 1.0 / 근거 없음(문헌 FPPA는 한발 스쿼트용) | "무릎을 발끝 방향으로 밀어 주세요" | 동일 |
| 상체 쏠림 추세 squat_lean_drift | 바닥 몸통 기울기의 첫/끝 3렙 평균 차 | > 8° / 근거 없음, 중력 필요 | "상체가 점점 숙여져요, 가슴을 펴요" | 동일 |
| 깊이 감소 추세 squat_depth_fade | 무릎 최소각 첫/끝 3렙 평균 차 | > 10° / 근거 없음 | "깊이가 얕아지고 있어요" | 동일 |
| 좌우 비대칭(신규 후보, 구현 안 함) | 좌우 무릎 최소각 차 | 근거 없음 — 임계값 미정 | — | 동일 |
| 뒤꿈치 들림 | **3D로 판정 불가**(H36M17에 발 관절 없음; Halpe26 2D 발만) | — | — | — |
| 바 경로·그립 | **판정 불가**(바 키포인트 없음) | — | — | — |

### 푸시업
| 오류 | 3D 판정 양 | 기준(초안) / 근거 | 피드백(초안) | 검증 |
|---|---|---|---|---|
| 허리 처짐 pushup_hip_sag | 골반의 흉곽–발목중점 선 편차 ÷ 선 길이(바닥 쪽 +) | > 0.14 / 2D Exercise3D 정상 p99(D-06), 3D 근거 없음 | "배에 힘 주고 엉덩이를 올려요" | 지표 오차: Fit3D. 검출: 검증 불가 |
| 엉덩이 들기 pushup_hip_pike | 같은 편차(위 −) | < −0.08 / 근거 없음 | "엉덩이를 내려 몸을 일자로" | 동일 |
| 덜 내려감 pushup_shallow | 팔꿈치 내각 최소 | 기준선 +15° / 근거 없음 | "가슴을 바닥 가까이" | 동일 |
| 팔 덜 폄 pushup_no_lockout | 팔꿈치 내각 최대 | 세트 최대 −10° / 근거 없음 | "위에서 팔을 끝까지 펴요" | 동일 |
| 머리 떨굼/듦 head_drop/head_up | 머리(10)의 골반–흉곽 선 편차 변화(렙 시작 대비, 몸통 길이 비) | 0.376 / 0.15 / 2D p99·근거 없음. H36M 머리 = 눈 중점(귀 아님) | "시선은 바닥 앞쪽, 목을 일자로" | 동일 |
| 손 위치 pushup_hand_position | 첫 렙 top에서 손목의 어깨 대비 몸 앞뒤(골반→흉곽 축) 거리 ÷ 팔 길이 | ±0.35 / 근거 없음 | "손을 어깨 바로 아래에" | 동일 |
| 깊이 감소 추세 pushup_depth_fade | 팔꿈치 최소각 추세 | > 15° / 근거 없음 | "깊이가 얕아지고 있어요" | 동일 |
| 팔꿈치 벌어짐(신규 후보, 구현 안 함) | 위팔–몸통 외전 각 | 근거 없음 — 임계값 미정(코칭 통념 45°는 문헌 근거 확인 전) | — | 동일 |

### 바벨로우
| 오류 | 3D 판정 양 | 기준(초안) / 근거 | 피드백(초안) | 검증 |
|---|---|---|---|---|
| 몸통 반동 row_torso_swing | 렙 안 몸통 기울기 max−min | > 39.9° / 2D 정상 p99(D-06), 3D 근거 없음, 중력 필요 | "상체를 고정하고 팔로 당겨요" | 동일 |
| 상체 세움 row_standing_up | 렙 평균 몸통 기울기가 기준선보다 세워짐 | > 10° / 근거 없음 | "상체를 숙인 자세를 유지해요" | 동일 |
| 덜 당김 row_short_pull | 팔꿈치가 골반–흉곽 선 뒤로 간 최대 거리 ÷ 몸통 길이(3D 앞방향 = (L엉덩이−R엉덩이)×위) | 기준선 −0.10 / 근거 없음 | "팔꿈치를 더 뒤로 당겨요" | 동일 |
| 머리 듦 row_head_up | 머리(10) 선편차 변화 | 0.15 / 근거 없음 | "목을 등과 일자로" | 동일 |
| 으쓱 row_shrug | **3D로 판정 불가**(H36M17에 귀 없음, 목·머리는 합성) — 2D만, 판정도 꺼짐 | — | — | — |
| 바 경로·그립 폭 | **판정 불가** | — | — | — |

"정상 렙"이 전부 정상 자세라는 가정도 추정(D-T3-06: 트레이너 시범으로 보임).

---

## (c) 구현 계획 (기존 코드 재사용, 새 구조 없음)

**선행 차단 요인**: (1) 추적 실패 — 첫 포착 실패(D-T3-21: 늘인 전체 프레임 → 작은 첫 crop)가 2D·3D 모두를 막음. 3D 창은 끊기면 다시 27프레임을 채워야 해 영향이 더 큼.
(2) iPhone 개발자 프로필 신뢰(측정 차단). (3) 틀린 자세 라벨 없음(자세 평가 정확도 검증 차단). (4) 중력 벡터가 운동 카메라에 없음(몸통 기울기류).

**P0 — XS 라이브 + 3D 정확성 + 3D 판정 연결**
1. `PosePipeline/MotionAGFormerLive.swift`(신규 1파일, CalibrationEngineKit·pose-replay에 심볼릭 링크): 과거 프레임만 쓰는 27프레임 링 버퍼,
   기존 `MotionAGFormerInputNormalizer`·`coco17ToH36M17` 재사용, 출력 행 `26 − lookahead`, 2D 프레임 지연 버퍼로 같은 프레임의 2D·3D를 묶어 냄,
   세트 끝 flush(오른쪽 끝 복제 = 오프라인 pose-replay와 같은 창). 상태: `warming_up`(27 실프레임 전) / `tracking_lost`(사람 없음·관절 부족, 오래 끊기면 버퍼 초기화) / `bad_3d`(제약 위반 큼) / `ok`.
2. 해부학 제약(같은 파일에서 순서만 정의): XS 원출력 → `BoneLengthConstraint`(캘리브레이션 cm, 없으면 세션 중앙값·문헌 비율) → 관절 각 한계(무릎 `KneeHingeLimit` 원인 수정 후 + 팔꿈치·엉덩이·어깨·척추 내각 한계) → 평활(선택, 기본 끔).
   원출력·제약 출력 둘 다 보관, 프레임별 발동 여부·크기 기록 → `bad_3d` 신호. Python 참조(`live_motionagformer.py`, `geometry/`)에 같은 로직, 패리티 테스트.
3. 손목 교체: Swift에 Python `build_motionagformer_input_2d`·`reject_crossed_mediapipe_wrists`와 같은 규칙(신뢰도 게이트, 없으면 RTMPose 손목, 원본·교체 둘 다 보관, 같은 프레임 결과만), Halpe26은 앞 17개가 COCO 순서라 같은 인덱스 9/10.
4. `FormWarningTracker`: 3D 프레임마다 **2D와 같은 이름의 지표를 3D로 계산**(`measure3D`) → 같은 `judge`로 3D 판정. 자세 키(warnings/spoken/onFeedback)는 3D 판정에서 나오고,
   2D 판정은 `warnings_2d`로 비교용으로만 남김. 렙에 유효 3D 프레임이 부족하면 "3D 판정 불가(사유)"로 표시 — 2D로 대신하지 않음.
5. CameraPosePreview: 카메라 경로에 1–4 연결(이 브랜치에서 플래그 켬, 별도 큐 비동기·cadence 옵션), XS 번들 포함(브랜치 한정, 문서에 명시, 병합은 승인 필요).
6. 브리지: onPoseUpdate에 `pose3d` {state, filled} 추가, Flutter HUD에 상태 표시(채우는 중 / 사람 안 보임 / 3D 품질 나쁨).
7. 검증: Swift↔Python 패리티(정규화·창·선택 행·제약·손목), Fit3D 모캡으로 원출력 vs 제약(MPJPE, PA-MPJPE, 관절각 오차, jitter), 손목 교체 효과.

**P1 — 운동별 오류 평가·피드백, 실시간 성능·추적 안정성**
- (b) 표대로 3D 지표 보강(중력 기준 몸통은 CoreMotion 연결이 필요 — 별도 승인 항목 아님, 코드 추가만), 오경보율(정상 렙) 측정, 피드백 문구 초안 연결(키는 기본 꺼진 상태 유지 — 켜기는 사용자 승인).
- iPhone 측정: 2D+3D 프레임당 시간, CPU/GPU, 실효 FPS, 입력→판정 지연(lookahead 포함). 3D cadence(매 프레임/2프레임마다)·별도 큐 비동기·compute units·fp16 비교. 3D는 끄지 않음.
- 추적 안정성: 끊김 후 버퍼 초기화 규칙, 첫 포착 실패의 3D 영향.

**P2 — 렙 카운트**: 2D 상태기계 유지 + 3D 확인 신호(렙 안 3D 관절 가동범위)로 2D+3D 비교. 렙 정확도는 성공 기준 아님.

결과·수치는 `docs/results/lift_app.md`, 결정 후보는 docs/decisions.md D-D-09(제안만).
