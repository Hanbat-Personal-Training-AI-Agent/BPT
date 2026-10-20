# 실제 Runner 앱에서 3D PT 기능 검증 — Exercise3D 클립을 카메라 대신 (ai/lift-app)

사용자 지시(2026-10-20): 직접 촬영하지 않고 Exercise3D 영상을 실제 앱의 카메라 입력에 넣어, 3D 기반 PT 기능이 실제로 동작하는지 확인.
“모델 추론이 정상적으로 실행된 것만으로 PT 기능이 완성됐다고 판단하지 마.”
기기: iPhone 17 (iPhone18,3), 앱 com.bpt.liftdev(무료 팀 개발 빌드, Release). 모든 실행의 manifest(클립·로그·앱 바이너리·모델 sha256, 명령)는
Mac `devruns/<실행>/manifest.json`·`home_manifest.json`, Home `~/bpt-runs/lift-app/20261020-device-video-*`(Home이 꺼져 있던 동안의 실행은
manifest에 “pending sync to Home”).

## 방법
- **영상-카메라 모드**(이 브랜치 한정, 기본 끔): `BPT_CAMERA_VIDEO=<Documents 기준 경로>`. `ios/Runner/NativePose/Camera/VideoCameraSource.swift`가 클립을
  AVAssetReader(BGRA)로 풀어 **클립 자체 타임스탬프(30 fps)로 페이스**하고, 모든 프레임을 미리보기(AVSampleBufferDisplayLayer)에 그린 뒤
  `CameraCaptureManager`의 **같은 프레임 입구·같은 처리 큐**로 넘긴다. 처리 큐가 앞 프레임을 처리 중이면 그 프레임은 버린다
  (`alwaysDiscardsLateVideoFrames`와 같은 규칙). 그 뒤는 앱 경로 그대로: RTMPose-m 2D → 손(MediaPipe) → XS(liftQueue) → 평가기·
  FormWarningTracker → WorkoutSessionBridge → Flutter 운동 화면.
- 전면 카메라 재현: 앱 카메라는 전면·좌우 반전 연결이라, 영상 모드도 기본으로 프레임을 vImage로 좌우 반전해 넣는다(`BPT_CAMERA_VIDEO_MIRROR=0`이면
  녹화된 그대로). 반전 비용(vImage, 프레임당 1 ms 미만)은 실제 카메라에는 없는 비용이다. 가로 촬영 재현은 `BPT_CAMERA_VIDEO_ROTATE=90|270`.
- 카메라와 다른 점(재현 안 함): 카메라 캡처 자체·자동 노출·실제 조명, 푸시업 클립은 가로 1280×720(앱 카메라는 세로 720×1280).
- 음성: 영상 모드에서는 소리만 0(`BPT_VOICE_MUTE`, 합성·재생 경로는 그대로 돎). 실행 로그에 `voice_muted`.
- Flutter 진입: `BPT_AUTOSTART_WORKOUT=<운동>`(+ `BPT_AUTOSTART_REPS`)이면 로그인 없이 운동 화면으로 바로 감(네이티브가 shared_preferences로 넘김,
  일반 실행에서는 키 삭제). 목표 렙 = 클립의 정답 렙(`--reps-from-gt`)이면 Flutter가 10번째 렙에서 endSet을 보낸다.
- 기록(`VideoRunLog`, 영상 모드에서만): 판정 프레임마다 3D 상태·지연·키포인트, onPoseUpdate·onFeedback의 **Flutter 응답 콜백까지** 지연, 렙 보고서
  (2D·3D 지표와 경고), 보낸 키, Flutter가 코리 음성에 말하라고 한 대사(`KoriVoiceChannel` speak), startSet/endSet·3D 꼬리 flush·세트 범위 키·
  onSetEnd, 초당 처리·드롭·판정·XS 추론 수·프로세스 CPU·발열·배터리, 앱 번들 안 컴파일된 모델 파일의 sha256.
- 실행 `scripts/device_video_runs.py`(클립마다 앱을 새로 띄움), 분석 `scripts/analyze_device_video_runs.py`, 표 `scripts/device_runs_tables.py`,
  빌드 전후 비교 `scripts/compare_device_runs.py`, 오버레이 손목 `scripts/overlay_wrist_jumps.py`, 좌우 `scripts/ex3d_lr_swap_device.py`.
- 클립: Exercise3D 13시퀀스 × 3시점 = 39클립(로우 12, 푸시업 15, 스쿼트 12). 정답 렙·각도·가까운 쪽은 `outputs/rep_validation/gt.json`(Sapiens 의사 정답).
  이 클립들은 정상 동작으로 찍은 것으로 보이므로, 여기서 나온 자세 경고는 **오경보일 가능성이 높다**(검증된 라벨 없음).

### 실행 목록
| 실행 | 앱(커밋) | 화면 | 반전 | 발열 | 용도 |
|---|---|---|---|---|---|
| `unmirrored_def` 39클립 | fddf82d | main 데모 화면 | 안 함 | 대부분 serious(29/39) | 참고(반전 전) |
| `mirrored_def` 39클립 | 104ea89 | main 데모 화면 | 함 | 39/39 serious | 데모 화면 기준 층 (a)–(c) |
| `newdef_short` 3클립 | 1dee827(+ai/real-feedback) | 실제 판정 화면 | 함 | nominal | 새 기본값 (b)·(c)·세트 |
| `overlay_pre` 3클립 | 1dee827 | 〃 | 함 | nominal | 오버레이 변경 전 기준 |
| `refine_after_1/2`, `refine_dedupe0` | 5b14ee9(+ai/lift-refine) | 〃 | 함 | nominal | 새 오버레이·손 중복 제거 |
| `colours_view(2)` | a70ac36 / 6d856a3 | 〃 | 함 | nominal | 연속 색 오버레이 |

데모 화면 실행 두 개는 연속 실행·충전 중이라 **serious 발열 상태**에서 돌았다(D절). 같은 클립의 nominal 실행과 비교하면 푸시업 정면 클립의 드롭·지연이
발열 영향을 받았을 수 있다.

## 핵심
- **3D는 실제 앱 경로에서 매 프레임 돈다**: XS 추론 26.9–29.3회/초(운동 평균), 판정 프레임의 ok 85–98%, 판정 FPS ≈ 30(측면), 도착→판정 p50 188 ms
  (lookahead 5프레임 = 167 ms 포함). 정면 푸시업(70–88°)만 무거움(21–28 fps, 드롭 최대 150/551, 발열 serious에서).
- **자세 경고가 사용자에게 가는가**: 데모 화면(main)에서는 **아니오** — 말한 대사의 95%가 데모(칭찬 ↔ 운동별 대표 경고, 판정 아님)이고 3D 자세 키는 하나도
  안 나갔다. ai/real-feedback 병합 뒤(새 기본값)에는 **예** — 스쿼트 squat_knee_valgus가 말풍선·음성으로 2회 나감. 다만 이 클립은 정상 동작이라 **오경보일
  가능성이 높고**(Ex3D 스쿼트 3D knee_valgus 20/120렙, 앞선 문서), 임계값은 검증되지 않았다.
- **endSet**: 병합 뒤 Flutter가 목표 렙에서 endSet을 보내고, 네이티브가 3D 꼬리 5프레임을 flush·판정(5/5 ok)한 다음 세트 범위 키
  (squat_no_lockout n=2, pushup_no_lockout n=8)와 onSetEnd(worstJoint)를 보낸다. 세트 범위 키는 기록에만 들어가고 말하지 않는다(설계).
- 좌우: RTMPose 손목 좌우 바뀜 0%(39클립, Mac 재생 vs 라벨). 로우 20° 클립의 “왼손을 오른손으로” 현상은 RTMPose가 아니라 **손 crop 분기**
  (두 crop이 같은 손, 94%) — 예전 오버레이가 원시 MediaPipe 손목을 그려서 보였다. lift-refine 오버레이(XS 입력 손목을 그림)에서는 0프레임.

## 1. End-to-End (Runner 카메라 입력 → Flutter 피드백) — FPS·지연
측정 끝점: 프레임 도착(클립 PTS 페이스 시계) → (판정) 메인 스레드 평가 끝 → (Flutter) onPoseUpdate·onFeedback의 메서드 채널 **응답 콜백**.
위젯 그리기(≤ 1 vsync)는 **측정 안 함**. 판정은 3D lookahead 5프레임(167 ms)을 기다린 뒤라 지연의 대부분이 그 기다림이다.

운동별(반전·데모 화면 39클립, 104ea89, **발열 serious**):
| 운동 | 클립 | 처리 FPS(클립 범위) | 드롭 | 도착→판정 p50 | 도착→판정 p95 | 도착→Flutter 응답 p50 / p95 | CPU p50 |
|---|---|---|---|---|---|---|---|
| 로우 | 12 | 28.3–30.05 | 84/8,404 (1.0%) | 188.0–202.2 ms | 192.3–268.3 ms | 184.3–199.8 / 189.4–235.4 ms | 53–83% |
| 푸시업 | 15 | 21.2–30.05 | 473/8,257 (5.7%) | 188.3–276.7 ms | 191.8–376.1 ms | 188.2–275.8 / 194.0–378.1 ms | 54–92% |
| 스쿼트 | 12 | 29.96–30.02 | 12/13,720 (0.1%) | 187.2–190.3 ms | 190.9–197.3 ms | 186.9–190.4 / 192.7–201.1 ms | 49–60% |

- 푸시업 정면(cam1, 70–88°) 5클립이 드롭의 대부분(39–150개/클립, 처리 21–28 fps, CPU 78–92%). 측면·사선 푸시업은 0–16개. 이 실행은 발열
  serious 상태라(충전 중 연속 실행) nominal보다 나쁘게 나왔을 수 있다 — nominal 상태 같은 클립(pushup_0003_cam2)은 드롭 0–1, p95 193 ms.
- nominal 상태 새 기본값(3클립, 1dee827): 30 fps, 드롭 0–1, 도착→판정 p50 188 / p95 193–194 ms, 도착→Flutter p95 193–194 ms, onFeedback 응답 190–230 ms.
- 클립별 표(39행 × 3): `devruns/mirrored_def/tables.md`(Home `20261020-device-video-mirrored-104ea89/tables.md`), 반전 전 `…-unmirrored-fddf82d/tables.md`.

## 2. MotionAGFormer-XS 실행 여부·빈도·3D 상태 비율
| 운동 | XS 추론/초 | ok | warming_up | tracking_lost | partial_3d | bad_3d | 판정 프레임 |
|---|---|---|---|---|---|---|---|
| 로우 | 28.5 | 95.5% | 3.2% | 1.1% | 0.2% | 0% | 8,270 |
| 푸시업 | 26.9 | 85.3% | 4.1% | 0% | 10.7% | 0% | 7,709 |
| 스쿼트 | 29.3 | 98.2% | 1.9% | 0% | 0% | 0% | 13,648 |

- 추론 = liftQueue에서 실제로 돈 XS Core ML 예측 수(cadence 1이라 판정 프레임 ≈ 추론; 워밍업 27프레임 동안은 추론 없음).
- XS·RTMPose 연산 장치(xctrace Core AI, 1dee827, squat_0001_cam2, 15초 구간): **둘 다 Neural Engine** — ANE 구간 XS 376회/초(추론당 약 13구간,
  0.21 ms씩, ANE 사용 7.8%), RTMPose-m 62회/초(0.67 ms, 4.1%). MPS(GPU) ML 구간 0. 앱의 GPU 작업은 화면 그리기·blit뿐(앱 GPU 사용 약 2.6%,
  합성기 backboardd 9.8%). 프로세스 CPU 47.9%(코어 하나 기준) 중 Core ML/ANE 드라이버 16.1%, MediaPipe(drishti 스레드) 13.5%, 화면 그리기 6.2%.
  XS가 추론당 ANE 구간 13개로 나뉘는 것은 일부 연산이 CPU에서 돈다는 뜻일 수 있다(가설, 연산별 배치는 측정 안 함).

## 3. 운동별 3D 자세 지표와 실제로 발동한 경고 — 세 층
(a) 네이티브가 판정하고 로그에 남김(렙 보고서의 warnings_3d) → (b) Flutter로 보냄(onFeedback) → (c) 화면 말풍선·음성(Flutter가 KoriVoice에 speak 요청).
데모(판정 아님)는 따로 셌다. **기본값만**(전 키 켜기 실행 없음; 새 기본값 자체가 벤치·데드리프트 6키 뺀 전 키다).

### 3-1. 병합 전(main 데모 화면, 반전 39클립)
| 운동 | 렙(3D 판정) | (a) 3D 경고(렙 수) | (b) Flutter로 보냄 | (c) 말함 — 실제 판정 / 데모 |
|---|---|---|---|---|
| 로우 | 112 (112) | row_standing_up 1 | setup_side_view 4, tracking_lost 1 | 실제 5(setup_side_view 4, tracking_lost 1) / 데모 85(칭찬 43, row_torso_swing 42) |
| 푸시업 | 151 (149, 3D 없음 2) | pushup_no_lockout 8, setup_side_view 5, pushup_hand_position 1 | 없음 | 실제 0 / 데모 151(칭찬 77, pushup_hip_sag 74) |
| 스쿼트 | 120 (120) | squat_knee_valgus 20, squat_no_lockout 16 | 없음 | 실제 0 / 데모 120(칭찬 60, squat_knee_valgus 60) |

- 그때 기본 `enabledFeedbackKeys` = setup_full_body·tracking_lost(+로우 setup_side_view)뿐이라 3D 자세 키는 (a)에서 멈췄다. 화면·음성의 자세 대사는
  전부 main 화면의 `_advanceDemoFeedback`(렙마다 칭찬 ↔ 운동별 대표 경고)이었다 — **판정과 무관**.
- 비교용 2D 경고(같은 렙, 로그에만): 로우 row_head_up 5·row_standing_up 1·row_torso_swing 1, 푸시업 pushup_head_up 22·no_lockout 8 등, 스쿼트 no_lockout 18.

### 3-2. 병합 뒤(새 기본값: 데모 없음, 전 키 − 벤치·데드리프트 6키, 목표 렙 = 정답 10)
| 클립 | (a) 3D 경고(렙) | (b) 렙 범위로 보냄 | (b) 세트 범위로 보냄(endSet) | (c) 말풍선·음성 |
|---|---|---|---|---|
| squat_0001_cam2 (34°) | knee_valgus 4(렙 6·7·9·10), no_lockout 2(렙 2·5) | knee_valgus 2(렙 6·10; 7·9는 쿨다운) | no_lockout n=2 | “잠깐! 무릎이 안으로 모여…” 2회(실제 판정). no_lockout은 기록에만 |
| pushup_0003_cam2 (40°) | no_lockout 8(렙 3–10) | 없음(참고 등급은 렙마다 안 보냄) | no_lockout n=8 | 없음(세트 범위는 기록에만) |
| barbellrow_0003_cam2 (20°) | standing_up 1(렙 11, 세트 끝 뒤) | 없음(개선 등급은 두 렙 연속이어야) | 없음 | 없음 |

- 데모·가짜 대사 0. pushup_0003_cam2·squat_0001_cam2를 1dee827·5b14ee9·a70ac36·6d856a3에서 다시 돌려도 (a)–(c)가 렙 단위까지 같았고, barbellrow_0000_cam2는 모든 빌드에서 경고 0(lift-refine의 무릎 −15° 고정·손 중복 제거·새 오버레이가 이 클립들의 판정을 바꾸지 않음).
- 세트 범위 키가 결과 화면(feedbackCounts)에 보이는지는 “끝내기”를 눌러야 해서 영상 모드에서 **측정 안 함**.
- 화면에 보이는 것 = 말한 것(같은 `_onNativeFeedback`에서 말풍선 키를 바꾸고 바로 speak). 세트 완료 뒤 온 렙 범위 키와 Flutter 대사가 없는 키는
  화면에 안 나온다 — 이번 실행에서 둘 다 0건.
- 3D 지표(렙 보고서 metrics_3d: 무릎·엉덩이·팔꿈치 각, 몸통 기울기 등)는 렙마다 로그에 있다(`run_*.jsonl`의 `rep` 줄). 임계값은 검증되지 않은 값이라,
  정상 동작 클립에서 knee_valgus·no_lockout이 나오는 것은 오경보로 본다(가설; 사람이 확인한 라벨 없음).

## 4. 추적 실패·3D 불량·부분 무효화·좌우 뒤바뀜 빈도
| 운동(반전 39클립) | tracking_lost | bad_3d | partial_3d(지표별 무효화) | 무릎 뒤집힘 감지 프레임 | 각도 한계 걸린 프레임 | XS 입력 손목을 MediaPipe로 바꾼 프레임 L/R |
|---|---|---|---|---|---|---|
| 로우 | 88 (1.1%) | 0 | 19 (0.2%) | 17 | 16 | 7,761 / 4,577 (8,270 중) |
| 푸시업 | 0 | 0 | 822 (10.7%) | 45 | 1,150 | 3,775 / 3,092 (7,709 중) |
| 스쿼트 | 0 | 0 | 0 | 0 | 1,351 | 9,148 / 9,451 (13,648 중) |

- 반전 전(같은 39클립, 녹화 그대로): 푸시업 partial_3d 16.3%, 무릎 뒤집힘 480프레임 — 좌우 반전만으로 푸시업 3D 품질 지표가 크게 바뀐다(같은 영상의 거울상).
- bad_3d는 전 실행 0(현재 정의에서는 무릎 뒤집힘을 bad_3d가 아니라 지표별 무효화 partial_3d로 처리).
- 렙 수(2D 상태기계, 참고): 로우 112/126(12클립 중 9개 정확), 푸시업 151/150(15 중 12), 스쿼트 120/120(12 중 12). 정답은 Sapiens 의사 정답.

### 좌우 뒤바뀜
- **RTMPose 좌우(라벨 대비)**: Mac 재생(앱과 같은 RTMPose-m crop, 녹화 그대로) 39클립에서 손목·팔꿈치·어깨 바뀜 0%, 몸 전체 바뀜 0%.
  바뀌는 것은 낮은 측면 푸시업의 하체: 무릎 pushup_0003_cam3(10°) 55.5%, pushup_0001_cam3 39.4%, pushup_0002_cam2 36.0%, 엉덩이 pushup_0000_cam3 26.7%.
  로우·스쿼트는 모든 관절 0.2% 이하. 앱 경로(반전) 기기 키포인트로 같은 측정: ⏳ 아래 L/R 실행.
- **사용자가 본 “왼손을 오른손으로”(barbellrow_0000_cam2, 20°, 가까운 쪽 오른쪽, 13:59)**: 오버레이 반전 문제 아님(영상 모드에서 미리보기·오버레이 같은
  좌표, isFrontCamera=false), RTMPose 바뀜 아님(위 0%). 원인은 **손 분기**: 두 손목이 몸 높이의 0.16(≈110 px)만큼만 떨어져 256 px crop이 겹치고,
  MediaPipe(numHands=1)가 왼쪽 crop에서도 보이는 오른손을 돌려줌(검출의 94%), 두 crop이 같은 손인 프레임 488/590. 예전 오버레이는 crop마다 원시
  MediaPipe 손목을 그려서 손목 점이 다른 손으로 튀어 보였다. XS 입력은 reject_crossed로 대부분 막혔다(6/590만 샘).
- 기기 실측(오버레이 손목 재구성, `overlay_wrist_jumps.py`): 예전 오버레이(1dee827) 그린 손목이 다른 손 위 L 94 / R 344(585 프레임), 0.5 아래팔 넘게 튐
  8 / 30. **lift-refine 오버레이(5b14ee9 이후, XS 입력 손목을 그림)는 0 / 0, 튐 0 / 0** — 손 중복 제거를 꺼도(`BPT_HAND_DEDUPE=0`) 0 / 0. 중복 제거는
  같은 손 프레임 409개에서 MediaPipe 손목을 안 써서 XS 입력 손목 교체를 L 473 → 135, R 132 → 63 프레임으로 줄인다(판정·렙은 같음).

## 6. 실제로 동작하는 기능 vs 로그로만 있는 기능 (기기 실측 기준)
| 기능 | 병합 전(main 데모 화면) | 병합 뒤(ai/lift-app 현재) | 근거(실측) |
|---|---|---|---|
| RTMPose-m 2D, 손(MediaPipe), XS 3D(27프레임, L=5), 해부학 제약, 지표별 무효화 | 매 프레임 실행 | 매 프레임 실행 | XS 26.9–29.3회/초, ANE에서 실행 |
| 3D 자세 지표 계산·규칙 판정 | 실행, **로그에만** | 실행 | 렙 보고서 warnings_3d, form_source 3d 381/383렙 |
| 자세 교정 경고 → Flutter | **안 감**(기본 키 = 준비·추적 키뿐) | **감**(렙 범위: 우선·개선 등급, 쿨다운) | squat_knee_valgus 2회 onFeedback |
| 말풍선·음성 | 데모가 95%(판정 아님) | 실제 판정만, 데모 0 | speak 줄의 대사 = 보낸 키의 대사 |
| 3D 상태 안내(준비 중·추적 끊김·불안정) | 화면 배너 | 화면 배너 | onPoseUpdate.pose3d → `_Pose3DBanner` |
| startSet / endSet | Flutter가 안 보냄(꼬리 5프레임 미판정, 세트 키 0) | 보냄 — 꼬리 flush 5/5 ok·판정, 세트 범위 키, onSetEnd | end_set_flush·set_end_sent 줄 |
| 세트 범위(참고 등급) 키 | 절대 안 나감 | 기록(feedbackCounts)에만, 말 안 함 | pushup_no_lockout n=8 |
| 네이티브 WorkoutVoice(onFeedback에 Flutter가 null로 답) | 안 들림 | 안 들림 — 음성은 Flutter KoriVoiceService → KoriSpeaker | onFeedback 응답 전부 null |
| 렙 카운트 | 2D 상태기계 | 2D 상태기계 | 39클립 정확 33 |
| 오버레이 | 초록 선 + 원시 MediaPipe 손 | lift-refine: 연속 색(지표가 임계에 가까울수록 연두→주황→빨강, 모르면 흰색), 손 안 그림, XS 입력 손목 | 판정에 영향 없음, FPS·지연 차이 없음 |
| 운동 중 화면 자동 잠금 | **꺼지지 않음** — 전원 뺀 폰은 운동 중 화면이 잠김 | 0a4d830에서 카메라가 도는 동안 끔(브랜치만) | 16:37 실측: 자동 잠금 → 앱 일시정지 |
| 세트별 녹화 | 꺼짐(기본) | 꺼짐(기본) | `WorkoutDebugFlags.setRecording` |
| 중력 정렬(BPT_3D_GRAVITY) | 꺼짐 | 꺼짐 | **평가 불가** — 영상에는 기기 자세(가속도계)가 없다 |

## 보정 분류 — 효과 검증됨 vs 실험적 보정
| 보정 | 분류 | 근거 |
|---|---|---|
| 스쿼트 무릎 깊이 뒤집힘 반사(엉덩이–발목 선) | **효과 검증됨(스쿼트 한정, Fit3D 모캡)** | 반사된 스쿼트 다리 17/17이 모캡에 가까워짐(무릎 오차 319 → 142 mm). 푸시업은 40%/30%만 → 푸시업에는 안 켬. 기기 39클립에서 스쿼트 뒤집힘 0프레임이라 **앱 경로에서 발동은 관찰 안 됨** |
| MediaPipe 손목 교체(reject_crossed + 0.25 아래팔 게이트) | **실험적 보정** | 교체 프레임에서 MediaPipe 손목이 모캡에서 더 멂(5.8 vs 4.1 px), 3D 중립·손목 가속도 +9%. 기기에서 교체가 판정 프레임의 40–94%(손·운동별)에서 일어남. 같은 손 중복 제거(lift-refine)로 로우 20°에서 교체 프레임 L −71%·R −52% |
| 해부학 제약(뼈 길이·내각 한계·무릎 −15° 고정) | **실험적 보정** | Fit3D에서 정확도 거의 그대로(PA −1.3 mm), 떨림 +5%. 기기에서 각도 한계가 푸시업 15%·스쿼트 10% 프레임에서 걸림. 정확도 이득 근거 없음 |

## ai/lift-refine 폰 확인 — 새 오버레이·손 중복 제거 (사용자 관람)
같은 3클립(barbellrow_0000_cam2, pushup_0003_cam2, squat_0001_cam2), 반전, 목표 렙 = 정답, nominal 발열. 기준 = 1dee827(예전 오버레이).
| 클립 | 빌드 | 실행 수 | 처리 FPS | 드롭 | 도착→판정 p50 / p95 ms | 도착→Flutter p50 / p95 ms | CPU p50 |
|---|---|---|---|---|---|---|---|
| barbellrow_0000_cam2 | 1dee827 | 1 | 30.04 | 0 | 188.0 / 193.9 | 187.7 / 189.4 | 51.7% |
| | 5b14ee9(빛나는 연두 선, 경고 빨강) | 2 | 29.99 | 1 | 187.9 / 194.2 | 187.6 / 192.7 | 51.9% |
| | 6d856a3(연속 색) | 1 | 29.94 | 2 | 187.9 / 194.1 | 187.8 / 193.8 | 52.2% |
| pushup_0003_cam2 | 1dee827 | 2 | 30.04 | 0 | 188.0 / 193.2 | 188.0 / 191.2 | 52.2% |
| | 5b14ee9 | 1 | 29.99 | 1 | 188.3 / 193.6 | 188.4 / 191.2 | 52.4% |
| | a70ac36·6d856a3(연속 색) | 2 | 29.99 | 1 | 188.1 / 193.5 | 188.0 / 191.6 | 52.5% |
| squat_0001_cam2 | 1dee827 | 2 | 29.8 | 11(한 번은 21: 끊김 1회) | 187.8 / 194.0 | 187.2 / 279.7(끊김 포함) | 49.2% |
| | 5b14ee9 | 1 | 29.9 | 5 | 188.2 / 194.9 | 187.4 / 194.9 | 49.4% |
| | 6d856a3(연속 색) | 1 | 29.98 | 2 | 187.6 / 193.7 | 187.4 / 193.4 | 48.8% |

- **오버레이 그리기 비용 변화는 측정 오차 안**: FPS·지연·CPU 차이가 같은 빌드 실행 사이 차이(CPU ±0.8%p, 드롭 0–21)보다 작다. 그리기는 메인 스레드
  SwiftUI Canvas(xctrace: 메인 스레드 화면 그리기 약 2% 코어)라 판정 경로(처리 큐·liftQueue)를 막지 않는다. GPU 쪽 합성 비용 전후 비교는 ⏳(xctrace).
- 판정·렙·보낸 키는 모든 빌드에서 같다(3절).
- 손 중복 제거·손목: 4절 “좌우 뒤바뀜” 참고. 뼈 길이 목표(BPT_BONE_TARGETS, P1) 실행은 Home이 꺼져 P1.json을 못 가져와 **측정 안 함**.
- 실행 사고(세지 않음, 다시 함): 설치 직후 첫 실행은 Core ML이 모델을 ANE용으로 컴파일하느라 약 31초 늦게 시작(cv_barbellrow, 1초만 재생); 전원을 뺀 뒤
  폰이 자동 잠금되어 cv_squat·th30이 2초 만에 일시정지. 둘 다 `partial_not_counted`/`thermal30_failed`에 사유와 함께 둠.

## 운동 중 화면 자동 잠금 (제품 문제, 브랜치에서 고침)
- 실측: 전원을 뺀 폰에서 아무도 만지지 않으니 16:37 자동 잠금 → 운동 화면 앱이 일시정지(로그 끊김). 운동 화면은 isIdleTimerDisabled를 켜지 않았다
  (체형 촬영 `CalibrationSession`만 켬). 실제 사용자도 세트 중에는 화면을 만지지 않으므로 같은 일이 생긴다.
- 고침(0a4d830, ai/lift-app만, 통합은 사용자 승인 필요): 운동 카메라(카메라·영상)가 도는 동안 끄고, 카메라 멈춤·백그라운드에서 원래 값으로 되돌리고,
  돌아오면 다시 끈다. 전환마다 로그 `[Workout] idle timer disabled=… (사유)`와 실행 로그 `idle_timer` 줄.
- 기기 확인(ef0f33d, 사용자가 폰을 만진 실행 v3d_barbellrow_0000_cam2): camera_start → 끔(5.1초) → 백그라운드 → 되돌림(17.4초) → 포그라운드 → 끔(25.9초)
  → 사용자가 운동 끝내기(endSet 41.1초) → camera_stop → 되돌림(41.4초). 이 실행은 중간에 멈춰서 E2E에는 세지 않음.

## 30분 발열·배터리 (전원 뺀 폰, 화면 켜짐, 음성 0)
`thermal30`(Home `20261020-device-thermal30-6d856a3`): squat_0001_cam2를 45번 이어 재생(31.7분, 57,000프레임), 앱 6d856a3, 목표 렙 999(세트가 안 끝남),
16:48–17:20 KST, 실내. 값은 앱의 초 단위 perf 로그(완전, 1,900초)에서.
| 구간 | pose / 판정 FPS | 드롭 | 입력→판정 p50 / p95(초별 중앙) / p95 최악 | lift3d p50 | 2D+손 p50 | 배터리 | 발열 |
|---|---|---|---|---|---|---|---|
| 0–5분 | 29.98 / 29.97 | 8 | 187.8 / 192.9 / 225.2 ms | 6.14 ms | 14.66 ms | 100 → 95% | nominal |
| 5–10분 | 30.00 / 30.00 | 3 | 187.7 / 192.7 / 224.7 | 6.14 | 14.68 | 95 → 90% | nominal → **fair(6.8분)** |
| 10–15분 | 29.99 / 29.99 | 6 | 187.7 / 193.1 / 251.1 | 6.13 | 14.64 | 90% | fair |
| 15–20분 | 29.99 / 29.99 | 6 | 187.7 / 193.0 / 223.3 | 6.12 | 14.65 | 90 → 85% | fair → **serious(19.4분)** |
| 20–25분 | 29.98 / 29.98 | 8 | 187.6 / 193.1 / 223.6 | 6.10 | 14.62 | 85% | serious |
| 25–31.7분 | 29.99 / 29.99 | 5 | 187.6 / 192.8 / 226.9 | 6.12 | 14.60 | 85 → 80% | serious |

- 배터리 **100 → 80%(−20%p / 31.7분, 시간당 약 38%)**. iOS 배터리 값은 5% 단위라 ±5%p. 20% 아래로는 안 내려감.
- 발열은 6.8분에 fair, 19.4분에 serious가 되어 끝까지 serious. **FPS·지연·단계 시간은 처음 5분과 마지막 5분이 같다**(드리프트 없음, 드롭 36/57,000 = 0.06%).
  이 클립(측면 스쿼트)은 무겁지 않은 쪽이다 — serious에서 돈 39클립 실행에서 정면 푸시업이 드롭을 낸 것과 같은 무거운 시점의 장시간 값은 **측정 안 함**.
- 실행 로그(VideoRunLog 67 MB)는 Wi-Fi 복사가 두 번 다 정확히 60,000,000바이트에서 끊겨(CoreDeviceError 7000) Mac 사본은 잘린 것
  (`…TRUNCATED_at_60000000_bytes.jsonl`). 위 값은 잘리지 않은 perf 로그에서 나왔다. 전체 사본은 폰에 있어 USB로 가져올 수 있다.
- 첫 시도(th30, 16:38)는 폰이 자동 잠금되어 2초 만에 일시정지 — 세지 않음(아래 화면 자동 잠금).

## 뼈 길이 목표(BPT_BONE_TARGETS) — 캘리브레이션 결과가 있을 때 (lift-refine)
Exercise3D 사람별 뼈 길이(Home `lift-refine/20261020-shapes-ex3d-all/targets/`, P1–P3; 폰 Documents에만 복사, Mac 사본은 삭제). 앱 ef0f33d, 같은 클립의
목표 없음 실행과 비교.
| 클립(사람) | 목표 | 렙 | 3D 상태 ok | (a) 3D 경고 | (b) 렙 / 세트 범위 | 처리 FPS | 도착→판정 p50 / p95 | 뼈 보정량 p50 / p95 | 각도 한계 프레임 |
|---|---|---|---|---|---|---|---|---|---|
| squat_0001_cam2 (P1) | P1.json | 10 | 96.7% | knee_valgus 4, no_lockout 2 | knee_valgus 2 / no_lockout 2 | 30.0 | 187.9 / 193.9 | 0.334 / 1.204 | 158 |
| | 없음 | 10 | 96.7% | 같음 | 같음 | 30.0 | 187.8 / 194.0 | 0.250 / 1.159 | 158 |
| squat_0002_cam2 (P2) | P2.json | 10 | 95.5% | no_lockout 4 | – / no_lockout 4 | 30.03 | 187.6 / 193.2 | 0.233 / 0.728 | 1 |
| | 없음 | 10 | 95.5% | 같음 | 같음 | 29.99 | 187.8 / 193.3 | 0.204 / 0.663 | 1 |

- 목표를 넣으면 제약이 3D를 조금 더 옮기지만(뼈 보정량 p50 +0.03–0.08, 로그 단위), 렙·상태·경고·보낸 키·지연은 **같다**. 정확도가 나아졌는지는
  Exercise3D에 3D 정답이 없어 **평가 불가**(Fit3D 모캡 평가는 lift-refine 문서).

## 화면 문구 정리 (사용자 요청)
- `partial_3d` 안내(“일부 관절 3D 불안정 …”)는 사용자 화면에서 뺌(334a409). 상태는 onPoseUpdate·로그에 그대로. 준비 중·추적 끊김·bad_3d 안내는 유지.
- 경고가 없을 때 “준비되면 시작해보자!”가 세트 내내 남던 문제: ai/real-feedback 6a78a29(e21a25f로 병합) — 첫 렙부터 중립 말풍선
  “자세 확인 중 · n/목표회”(칭찬·음성 없음). 데모를 없애자 경고가 안 나는 세트에서 말풍선이 바뀌지 않아 드러난 문제.

## ai/setup-constraint 폰 확인 — 적응형 관계 제약(BPT_ADAPTIVE_3D)·준비 자세 패널
빌드 7579aab(= lift-app e21a25f + setup-constraint; d6dd1e9와 네이티브 코드 같음 — `git diff 7579aab d6dd1e9 -- ios/Runner/NativePose` 없음,
Flutter 말풍선만 다름). 3클립 × (a) 기본 / (b) `BPT_ADAPTIVE_3D=1`, 2회씩 번갈아(a1 b1 a2 b2), 목표 렙 = 정답, 반전, nominal. lift3d는 앱 perf 로그(초별 p50/p95의
n 가중 중앙값), 도착→판정은 실행 로그의 프레임별 값. 표: `scripts/setup_check_summary.py`.

| 클립 | (a) lift3d p95 1/2회 | (b) lift3d p95 | (a) 도착→판정 p95 | (b) 도착→판정 p95 | 렙 (a)/(b) | (a) 3D 경고 | (b) 3D 경고 | (b) adaptive 채움/무효/이벤트 프레임 |
|---|---|---|---|---|---|---|---|---|
| barbellrow_0000_cam2 | 7.40 / 7.18 ms | 7.37 / 7.08 | 200.9 / 209.9 ms | 199.7 / 200.8 | 10 / 10 | 없음 | 없음 | 122–123 / 0 / 15 (581 중) |
| pushup_0003_cam2 | 7.04 / 7.11 | 6.88 / 7.04 | 195.9 / 199.9 | 197.1 / 196.7 | 10 / 10 | no_lockout 8 | no_lockout 8 | 80 / 133 / 43 (544 중) |
| squat_0001_cam2 | 8.53 / 8.62 | 8.39 / 8.29 | 200.9 / 197.5 | 198.5 / 200.2 | 10 / 10 | knee_valgus 3·4, no_lockout 2 | knee_valgus 4·5, no_lockout 2 | 0 / 769–774 / 60 (1,251 중) |

- 제안 통과 규칙(미승인) 기준: lift3d p95 (b)−(a) = −0.07 / −0.12 / −0.24 ms(< +1 ms), 도착→판정 p95 −5.1 / −1.0 / +0.2 ms(로우의 −5.1은 (a) 2회의 209.9
  이상값 때문), 렙 같음 — **통과**. 보낸 키도 같다(스쿼트 knee_valgus 2 + 세트 no_lockout 2; (b) 2회만 praise_fixed 1 추가).
- 스쿼트 knee_valgus 렙 수는 (a)끼리도 3·4로 다르다 — 드롭이 판정되는 프레임을 바꿔서. (b)−(a) 차이(+1)는 이 실행 간 차이 안.
- (b)에서 스쿼트 판정 프레임의 61%가 관계로 무효화(adaptive_invalid) — 그래도 렙·경고는 그대로. 이것이 의도대로인지는 setup-constraint 문서 쪽 판단.
- (c) 준비 자세 패널(`--dart-define=BPT_EXERCISE_SETUP=true` + (b)), squat_0001_cam2: `exercise_setup`·`adaptive_3d` 켜짐 확인.
  COCO17(앱 기본 m)로는 7579aab·d6dd1e9 두 빌드 모두 **setup_ready 0** — 패널이 “준비됨”까지 가지 않았다. 같은 빌드에서 **s Halpe26 데모**
  (`BPT_POSE_MODEL=halpe26`, 번들에 있는 s 모델 — 계획한 m Halpe26 아님)로는 **setup_ready 1**: 클립 시작 1.9초 뒤(7.4초, 첫 렙 전) 준비됨, 발 관계(feet)
  씨앗, 스냅숏 feet_width 1.55·heel_width 1.68·toe_out 1.18·torso_incline 11.1° 등. 렙 10은 같다. 가설: COCO17에서는 준비에 필요한 항목 하나가
  끝까지 안정·유효하지 않다(어느 항목인지는 setup-constraint 쪽 확인 필요).
- 이 빌드들의 도착→판정 p50(189.5–190.2 ms)은 18:40 이전 lift-app 실행(187.6–188.3)보다 약 2 ms 높다. 같은 시간대 lift-app e21a25f 로우 실행도
  189.6–191.7이라 코드가 아니라 기기 상태(전원 뺀 뒤 배터리) 차이로 본다(가설).
- m Halpe26 실행(발 항목): 번들에 없고 enum 항목도 0024c50에서 빠져, 넣으려면 코드·pbxproj 변경이 필요해 **안 함**. 번들의 s Halpe26(`BPT_POSE_MODEL=halpe26`)은
  환경 변수만으로 가능 — 요청 시.

<!--PENDING-->

## 5. 탑재된 XS 가중치 (정확한 버전·체크섬)
| 위치 | 파일 | sha256 |
|---|---|---|
| 소스 `ios/Runner/NativePose/Models/motionagformer_xs.mlpackage` (커밋 `192ad47`에서 추가) | Data/com.apple.CoreML/weights/weight.bin | `37a5c83431601e421a4d3d1e6fa6af39951062a08a7372cea172b98110d2f38e` |
| | Data/com.apple.CoreML/model.mlmodel | `62cfec0dd4ac48fde2cb2c682755b30cdf898c301eb0e5afd5611ce79d376b61` |
| | Manifest.json | `4f8c28b49a69e017891a3ba238e5be7ac4c5e418ccccb3502badfa0ea09a24e0` |
| 빌드된 Runner.app(liftdev; 이 문서의 모든 실행 빌드 fddf82d·104ea89·1dee827·5b14ee9·a70ac36·6d856a3·0a4d830에서 파일 5개 모두 같음) `motionagformer_xs.mlmodelc` | weights/weight.bin | `37a5c834…f38e` (소스와 같음) |
| | model.mil | `768b5f53b06c471b667005b71d0e17d6c2a87cc15f1a975dbd135456ca910c49` |
| | coremldata.bin / metadata.json | `d97e3221…b7e` / `90a8ffbf…7b48` |

- 출처: 원래 MotionAGFormer-XS **H36M** 가중치 `motionagformer-xs-h36m.pth.tr`(sha256 `7abb32ea…4597`, 업스트림 TaatiTeam, Apache-2.0)를
  `scripts/export_motionagformer_xs_coreml.py`(coreml_safe)로 변환. 메타데이터: coremltools 9.0, torch 2.12.0, fp16, conversion_date 2026-09-20.
- **Fit3D 미세조정 모델이 아님(확인됨)**: 미세조정 재현본 trains05의 weight.bin은 `73c009e4…22a5`로 다르고, 패키지 이름도
  `…_NONCOMMERCIAL`이며 번들에 없다. 앱이 실제로 불러온 컴파일 모델의 해시는 모든 실행 로그의 `start.models`에 기록되어 있고 위와 같다.
