# integration/ai → main

AI 쪽 작업(캘리브레이션 서버, 2D/3D 포즈, 사람 crop 입력, 자세 경고, 렙 카운트, 앱 연결·음성)을 main에 합친다.

## 변경 요약

**캘리브레이션 서버 (server/calibration_modal)**
- Modal 업로드 서버 1단계: 버킷 조건부 쓰기로 접수 상태 관리, 패딩 없는 JWT secret 허용, 카메라 정보 없음 기록 접수
- L4 GPU 체형 fitting(SAM 3D Body → MHR→SMPL 공유 β → 재투영 보정 → 키 사영), 결과 스키마
- 재생 도구가 앱과 같은 업로드 묶음 사용
- 계약 정리(트랙 F): 상태 값은 계약 문서의 소문자 `queued|running|done|failed` 유지, 백엔드 `UserCalibration`과 같은 이름의 필드만 추가(`progressRate`, `result.coachComment`·`calibratedAt`·`modelGlbUrl`). 팀원 인계 `docs/handoff/teammate_calibration.md`
- 작업 감시: worker가 죽어도 `running`에 안 남음 — 조회 때 Modal 호출 상태 확인 + 접수 후 30분 기한 → `failed timeout/internal_error`, `retries=0`
- 스텁·가짜 결과는 `done`이 될 수 없음(서버 `require_real`, 앱 `fetchJob`도 거부)
- β≈0 수정: 재투영 보정에서 β를 움직이지 않고 MHR→SMPL 변환기 β 유지(`Fitter(refine_beta=False)`). People Snapshot 12명 팔다리 길이 오차(보류 6명) 4.16% → **2.83%** ("키만" 4.25%)
- GLB: 서버에서 SMPL 메시를 만들어 R2에 두고 조회 때 1시간 presigned GET(`result.modelGlbUrl`, 본인만). SMPL 모델 파일은 배포 안 함(비상업 라이선스)
- 앱 분석 화면: polling·진행률·실패 문구·결과 요약. 실제 3D 결과 화면은 팀원 파일이라 브랜치 `ai/calibration-result-screen`에만(병합 안 함)
- 운동 3D에 캘리브레이션 뼈 길이 연결은 보류(라이브 3D 꺼짐)
- 촬영 거리 단축(F10–F11): 전면 초광각(iPhone 17 84°) 우선, 몸 높이 0.40–0.85, 폰 앞뒤 기울기 25° → 키 1.70 m 기준 최소 거리 1.70 → 1.15 m(바닥에 기대면 0.75 m). manifest에 선택 필드 `camera`
- 서버 예열(F13): 촬영 화면 진입 시 `POST /v1/calibrations/warmup`(사용자당 5분 1회), `fit_body` 대기 180초 — 첫 작업 258 → 33초. 배포됨(v10)

**포즈 (iOS NativePose)**
- RTMPose-s Halpe26 모델 추가와 모델 선택 상수(기본 COCO17, `BPT_POSE_MODEL=halpe26`으로 전환)
- MotionAGFormer 3D: 사람 중심 정사각형 crop 입력(기본), 캘리브레이션 뼈 길이 제약, 무릎 과신전 감지("3D 불량" 표시)

**3D 평가 (트랙 D, 앱 동작 변경 없음)**
- 사선(30–75°)에서 3D 각도는 2D보다 낫지만(Fit3D 스쿼트 무릎 오차 21–36° → 7–11°) 측면 수준이 아니고 측면 스쿼트 몸통은 오히려 나빠짐 → 측면 요구 유지(D-D-01)
- 라이브 카메라 3D는 계속 끔, 3D 지표는 경고에 안 씀(D-D-02). 사선 렙 카운트도 2D가 나음(Fit3D 스쿼트 2D 8/8, 3D 4/8, D-D-04)
- 무릎 "3D 불량" 감지는 품질 신호로 믿지 않음(감지 유지·보정 끔, D-D-03)
- iPhone 17 라이브 3D 비용: 30 fps 안에 들어가지만 프레임당 +17 ms(9.4 → 26.2 ms), CPU 23 → 36%(D-D-05, `tools/ios_live3d_cost`)
- Fit3D 미세조정 MotionAGFormer-XS: 학습 안 한 피험자 MPJPE 160–163 → 50–67 mm, 사선 무릎은 크게 좋아지나 몸통은 나빠져 앱 미반영(다음 단계 1순위, D-D-06). Fit3D 학습 가중치는 비상업(캡스톤) 전용, 학습은 사용자 PC(Home GPU)
- 도구: `scripts/count_reps_3d_vs_2d.py`, `scripts/finetune_motionagformer_fit3d.py`, 2D·3D 각도 오차 평가

**자세 경고 (FormWarnings.swift)**
- 푸시업·스쿼트·바벨로우 공통 경고 기반, 렙별 판정, 세션 로그, pose-replay 도구
- 임계값: pushup_hip_sag 0.140, pushup_head_drop 0.376, row_torso_swing 39.9° (Exercise3D 정상 렙 p99). 나머지는 임시값
- 몸통 각도 ±180° 경계 버그 수정(max−min이 358°처럼 나오던 문제)

**렙 카운트**
- 스쿼트: 빠른 하강/상승(top↔bottom 직행)도 렙 시작·종료로 인정
- 바벨로우: 측면 판정 게이트(어깨폭 ÷ 몸통 길이 150프레임 중앙값 ≤ 0.56). 측면일 때만 휴식 자세 우선 판정, 한쪽 팔만 보여도 판정.
  측면 아니면 렙을 세지 않고 setup_side_view 안내
- 푸시업: 측면일 때만(푸시업 전용 컷오프 1.0) top→bottom 직행도 렙 시작, 근측 팔 하나로 팔꿈치 각도(`sideViewRepFixes`, 끄면 이전 동작)
- tracking_lost: 렙 도중에는 말하지 않고 1.0초 이상 이어지면 렙이 끝난 뒤 전달

**RTMPose 입력 (트랙 B)**
- 이전 프레임 키포인트로 사람 3:4 crop(여백 포함, 비율 유지), 놓치면 전체 프레임. 라이브 카메라·pose-replay 같은 코드(`RTMPoseCropTracker`, `PosePreprocess.drawRegion`). 끄기 `CameraPreviewOptions.personCropInput = false` / `--input full`
- 측면 렙 정확도 푸시업 COCO17 97.8→100%, 로우 97.6/94.0→98.8/98.8%, 정지 구간 키포인트 흔들림 17–49% 감소
- 바벨로우 측면 컷오프 0.56 → 0.66 (crop에서 측면 비율이 커짐; crop을 끄면 0.56으로 되돌림)
- 사람 재확인: 30프레임(≈1초)마다 전체 프레임을 한 번 더 보고, 뚜렷하고(관절 12개·평균 신뢰도 0.42) 1.5배 이상 크며 crop과 30% 이하로 겹치는 다른 사람이면 옮김(추론 +3.3%). 현재 모델 수치는 그대로, 뒤에 다른 사람이 있던 영상에서 m Halpe26 푸시업 81.1→100%. 끄기 `RTMPoseCropTracker.recheckInterval = Int.max`

**2D 모델 평가 도구 (트랙 C, 앱 동작 변경 없음)**
- `scripts/eval_pose2d.py`(COCO val·Exercise3D·Fit3D PCK), `scripts/eval_pose2d_reps.py`(후보 모델 렙 정확도), `pose-replay --model-path`, 후보 Core ML 변환(`rtmpose_s_coreml_common.py`: s body7, m COCO17/body7/Halpe26), Fit3D 미세조정 도구(Mac 전용), `tools/pose_model_bench`(iPhone 지연 XCTest, 연속 실행·발열·Vision 참고 포함; iPhone 17 결과 s 2.0 ms · m 3.3 ms, D-C-05)
- 결론: 기본 RTMPose-s COCO17 유지. Fit3D 미세조정 기각(독립 세트에서 나빠짐), m COCO17은 iPhone 17 속도 조건 만족(3.3 ms, D-C-05). m COCO17·Halpe26 전환 여부는 세 운동 트랙(스쿼트·푸시업·로우)의 검증용(held-out) 비교로 정함 — 검증용이 좋아지고 다른 것이 나빠지지 않을 때만 플래그로 m COCO17 전환
- MediaPipe Pose Landmarker 재검토(D-C-07): 벤치 호스트에만 MediaPipeTasksVision 1.0.0 연결(앱 타깃 변경 없음). iPhone 17 full CPU 8.6 ms, 30 fps 파이프라인 p95 16 ms·놓친 프레임 0, 측면 푸시업 PCK 0.924(m 0.708)지만 스쿼트·로우는 나쁨 → 기본 유지, 푸시업 전용 후보로 추천만

**앱 연결 (트랙 E)**
- onFeedback `{key, n?, scope: "rep"|"set"}`: 참고 등급 키는 세트 끝(`endSet`)에 scope "set"으로 1번. 기본값에서 나가는 키는 그대로
- 네이티브 WorkoutVoice: Flutter가 onFeedback에 답으로 준 대사만 말함(대사 원문은 dart에만), 우선 등급 키 끼어들기, 대기 3초 넘으면 버림, `setVoiceMuted`. 음원 `assets/kori_voice/<key>[_<n>].mp3` → 없으면 기기 TTS
- `startSet`/`endSet` ↔ `onSetEnd {setIndex, videoLocalPath, worstJoint}`, worstJoint는 켜진 키만(지금은 null)
- 벤치·데드: setup_full_body·tracking_lost만 전달(트랙 G에서 평가기 자체 트래커로 바뀜)
- 세트별 녹화(720p H.264, 최근 20개) 기본 꺼짐(`BPT_SET_RECORDING=1`), perf 로그 `BPT_PERF_LOG=1`, `scripts/compare_perf_logs.py`

**벤치프레스·데드리프트 (트랙 G)**
- 벤치 렙: 락아웃을 본 뒤에만 렙 시작, 적응 임계값은 팔꿈치 범위 50° 이상부터(`repStartRequiresTop`, `minRequiredElbowRange`), 한쪽 팔만 보여도 측정(`allowOneArm`)
- 데드 렙: 락아웃 진행도 0.28→0.10, 바 내림 = 손목이 무릎 아래, 바닥→top 직행도 렙 시작(`directBottomToTopStartsRep`). 이전엔 Exercise3D·Fit3D 전부 0렙
- 측면(≤40°) 렙 정확도 조정 / 검증: 벤치 88.9/90.9% → **100/100%**, 데드 0/0% → **100/100%**, 데드 Fit3D 가상 측면 30렙 100%. 정지 합성 가짜 렙 벤치 73→0, 데드 0. 스쿼트·푸시업·로우 78영상 결과 동일
  - 입력은 Exercise3D의 Sapiens2 2D 키포인트(**대리 입력**, 앱 RTMPose 아님 — 원본 영상 없음). 사람 단위 분리는 뼈 길이 비율 추정
- 경고 키 6개 추가(`bench_hips_up`, `bench_shallow`, `bench_no_lockout`, `deadlift_hips_first`, `deadlift_no_lockout`, `deadlift_lean_back`), **전부 꺼짐**·dart 대사 없음(팀원 결정 대기). 평가기가 자기 `FormWarningTracker`를 가짐(트랙 E의 `StatusDrivenFormTracker` 대체)
- pose-replay `--exercise bench|deadlift`, `--keypoints-csv`

**평가 도구**
- `scripts/eval_side_videos.py` + `data/side_videos/labels_template.csv`: 직접 찍은 영상으로 렙 정확도, 측면 비율 분포, 경고 발생률, 셋업 키 집계

**음성·문서**
- 코리 음성 mp3는 팀원이 직접 생성해 넣음. 파일 이름 규칙 `docs/handoff/kori_voice.md`(생성 스크립트는 삭제, D-H-02)
- `docs/decisions.md`(결정 기록), `docs/results/summary.md`(발표용 결과표), `docs/handoff/security_followup.md`(JWT 교체·HTTPS·테스트 토큰 정리 체크리스트, 실행 안 함), `docs/progress/`

## 기본 꺼짐(플래그)
| 항목 | 기본 | 비고 |
|---|---|---|
| 자세 경고 Flutter 전달 | 끔 | `FormCommonConfig.enabledFeedbackKeys`에 키별로 추가해야 전달. 판정·로그는 항상 |
| 준비 자세 확인(첫 렙 전 정지) | 끔 | `readyPoseHoldFrames = 0`. 평가용 프리셋: 스쿼트·로우 0.5초 + 허용치 2배, 푸시업 없음 |
| squat_heel_rise | 끔 | 지표는 기록 |
| row_shrug | 끔 | 실험 |
| 무릎 과신전 보정 | 끔 | 감지("3D 불량" 표시)만 켜짐 |
| 세트별 녹화 | 끔 | `BPT_SET_RECORDING=1` 또는 UserDefaults `BPTSetRecording`. iPhone 17 측정(D-E-08): FPS −5.4%지만 30 fps에서 놓친 프레임 3→9라 OFF 유지 |
| (켜짐) crop 경계 재맞춤 | 켬 | 관절이 crop 경계에 붙으면 crop을 다시 맞춤(모든 운동). 끄기 `RTMPoseCropTracker.refitAtCropEdge = false` (D-T3-10) |
| (켜짐) 푸시업 어깨 높이 렙 신호 | 켬 | 측면에서 렙 수 = max(팔꿈치, 높이). 끄기 `PushUpEvaluatorConfig.heightRepSignal = false` (D-T3-11) |
| (켜짐) 사람 3:4 crop 입력 | 켬 | 끄기 `CameraPreviewOptions.personCropInput = false` — 끄면 로우 컷오프도 0.56으로 |

## 기본으로 켜진 키
- 모든 운동: `setup_full_body`, `tracking_lost`
- 바벨로우만: `setup_side_view` (측면 아님 판정 시 첫 렙 전 세션당 1회)

## 검증 (Exercise3D, 측면 ±40° 카메라, COCO17 / Halpe26)
| 운동 | 렙 정확도 수정 전 | 렙 규칙 수정 후 | + crop 입력 (현재) | 검증 피험자(P2·P3) |
|---|---|---|---|---|
| 스쿼트 | 48.8% / 38.8% | 100% / 100% | 100% / 100% | 100% / 100% (2/2) |
| 바벨로우 | 62.1% / 63.5% | 97.6% / 94.0% | 98.8% / 98.8% | 100% / 100% (4/4) |
| 푸시업 | 84.8% / 81.1% | 97.8% / 100% | 100% / 100% | 없음(푸시업은 P1 한 명) |

- 피험자 ID가 없어 영상을 보고 사람을 나눔(추정). 사람 재확인 경계값은 검증 영상까지 보고 정해서 그 부분은 검증 수치가 아님
- 셋업 키 오경보(측면): crop 뒤 COCO17 3→0, Halpe26 2→0

- 진단에 안 쓴 squat_03(정답 2렙): 1/2 → 2/2
- 움직임 없음(서서 흔들림 합성 88건, 더미 영상 6개): 추가 렙 0
- 후면 카메라 로우는 모두 측면 아님으로 판정

## 테스트
- `swift test --package-path ios/CalibrationEngineKit`: 96 통과
- `pytest tests/`: 185 통과
- 서버 `pytest tests` (server/calibration_modal): 82 통과, 1 건너뜀
- `flutter test`: 79 통과
- `xcodebuild` Runner, iOS Simulator Debug, `CODE_SIGNING_ALLOWED=NO`: 성공

## main과의 차이 (병합 전 확인)
integration/ai는 main보다 팀원 커밋 11개가 뒤처져 있습니다(2026-10-11 기준): #35 `a03fd9e` 계정 찾기 이메일 인증, #36 `d780665` 계정 찾기 안내, #37 `8017c09` 체형 측정일·세트 기록·피드백 횟수·알림 백엔드 연동, #38 `374ef52` 리포트 자주 나온 실수·코리 잔소리 알림, #39 `becec54` 프로필 저장 수정, #40 `0d00676` 코리 음성 ElevenLabs 실시간 TTS. 이어서 #41 `7c3270e` 체형 촬영 후 전송 대기 페이지 제거·로딩 화면에서 자동 전송, #42 `62abda4` 계정 찾기 인증 대기·비밀번호 재설정, #43 `8848fd7` 토스트 위치, #44 `293468e` 체형 촬영 코리 음성 반복 수정(`CalibrationVoice.swift`), #45 `24bc396` 리포트 분석 탭 위치.

양쪽에서 고친 파일(충돌 가능):
| 파일 | main | integration/ai | 처리 |
|---|---|---|---|
| `lib/features/workout/screens/native_pose_workout_screen.dart` | #37·#38 세트 기록·피드백 횟수, #40 `_speakFeedback`/`_speakSetSummary`(대사 읽기) | 경고 기본 끔·셋업 키, 트랙 E의 onFeedback·음소거·onSetEnd | 줄 단위 충돌 가능성 높음. **음성**: 트랙 E 화면은 onFeedback에 대사를 답하고(WorkoutVoice가 말함) 자체 TTS 호출이 없음, main #40 화면은 `_speakFeedback`으로 직접 말하고 답은 null. 수동 병합 때 둘을 섞으면 이중 재생 → 한쪽 선택(decisions E7, D-H-01) |
| `lib/features/workout/data/kori_feedback_lines.dart` | #38 `koriMistakeLabels`, `koriMistakeExerciseId`를 파일 끝에 추가 | 바로 앞의 `koriDemoWarningKeyByExercise`(임시 데모 경고) 삭제 | 붙어 있는 부분이라 충돌 가능. 맵 삭제 + main 추가분 유지로 해결하고, main 화면 코드가 삭제된 맵을 아직 쓰는지 확인. 대사 원문은 그대로라 음성 스크립트 영향 없음 |
| `lib/features/onboarding/screens/onboarding_analyzing_screen.dart`, `test/onboarding_analyzing_test.dart` | #41이 화면을 크게 바꿈(+505줄 변경, 전송 대기 페이지 제거, 로딩 화면에서 자동 전송) | 트랙 F의 작업 상태 polling·진행률·실패 문구·결과 요약 | **충돌 가능성 높음**. #41의 자동 전송 흐름 위에 트랙 F의 polling(`fetchJob`, `progressRate`, 스텁 결과 거부)을 다시 얹고 두 테스트를 다 통과시킬 것 |
| `ios/Runner.xcodeproj/project.pbxproj` | #40 `KoriSpeaker.swift` 추가 | Halpe26 모델·평가기·트랙 E 파일 추가 | 파일 목록 충돌 가능. 양쪽 항목 다 남기고 xcodebuild로 확인 |

의미상 겹침(같은 파일은 아님):
- `ios/Runner/NativePose/Calibration/CalibrationVoice.swift`: main #40이 AVSpeech → KoriSpeaker로 바꿈. integration/ai는 이 파일을 안 고쳐서 충돌은 없지만, 미리 만든 mp3를 쓰려면 KoriSpeaker에 파일 우선 재생을 붙여야 함.
- `ios/Runner/Info.plist`: main #40이 `ElevenLabsApiKey` 추가 → 빌드된 앱에 키가 평문으로 들어감(`docs/handoff/security_followup.md` 3-1). integration/ai의 ATS 설정(`NSAllowsArbitraryLoads`)과 같은 파일.
- 백엔드: #37·#38이 세트 기록·피드백 횟수 API를 씀. 트랙 E의 `onSetEnd {videoLocalPath, worstJoint}`가 그 세트 기록에 들어가야 함(서버는 경로만 저장).

- 백엔드(Spring)와: 캘리브레이션 상태 값 대소문자(서버 소문자 vs 엔티티 기본 `COMPLETED`), main 엔티티에 `coachComment` 열 없음, 결과 저장 API 없음 — 제안만(`teammate_calibration.md` 6절), 백엔드 코드는 안 고침.

## 알려진 한계
- **푸시업 측면 컷오프 1.0**은 Exercise3D에서 40°와 48°를 가르지 못함(48°도 측면으로 판정). 정면(70°+)만 확실히 걸러짐.
- **Fit3D에 측면 카메라 없음**(전부 58–74° 사선): 측면 정확도 검증에는 못 쓰고 회귀 확인만 함.
- **로우 측면 컷오프 0.66(crop 입력)은 40° 근처에서 미검증**: 데이터가 20–36°와 76–81°뿐. 정면 스쿼트 영상(squat_03)의 비율이 0.64–0.67이라 정면 촬영이 측면으로 판정될 수 있음.
  주말 촬영 영상(0/30/40°, 정면·후면)으로 확인 예정.
- 벤치·데드 수치는 Sapiens2 대리 입력 기준이라 앱 RTMPose(특히 누운 자세 측면)로는 미검증. 데드는 정면 카메라 미지원.
- 캘리브레이션 체형 평가 기준은 People Snapshot의 consensus 메시(정답 아님, 단안 추정 키)이고 실제 사용자 줄자 실측 검증은 없음.
- 준비 자세 확인은 Exercise3D처럼 바로 시작하는 세트에서 렙을 잃어 기본 꺼짐.
- **측면 푸시업, P1 아닌 사람**: 수정 전 MM-Fit 80.2%·Fit3D 가상 측면 검증 61.4%(D-T3-08) → crop 경계 재맞춤 + 어깨 높이 신호(D-T3-10·11) 후 MM-Fit 검증 6명 94.5%, Fit3D 가상 측면 검증 80.1%. 남은 것: 팔꿈치를 옆으로 벌린 사람의 정측면(0°), 세트 전 자세 잡기 추가 렙.

- **공개 데이터 검증 세트(D-DATA-01)**: Mendeley 26명 + YouTube CC BY 43채널, 렙 합의 386세트. 측면 검증 렙 정확도(현재 b68ce19) 스쿼트 47.6%, 푸시업 89.4%, 바벨로우 100%(YouTube 4세트), 덤벨로우 약 5% — 대부분 놓침. 자세 키는 확실한 근거 없음(후보 pushup_hip_pike 측면, 검출 5/6세트·오경보 0.8%).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
