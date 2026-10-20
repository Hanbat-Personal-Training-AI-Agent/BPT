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
- **3D는 실제 앱 경로에서 매 프레임 돈다**: XS 추론 26.9–29.3회/초(운동 평균), 판정 프레임의 ok 82–97%(새 기본값 39클립), 판정 FPS ≈ 30(측면), 도착→판정 p50 188–191 ms
  (lookahead 5프레임 = 167 ms 포함). 정면 푸시업(70–88°)만 무거움(21–28 fps, 드롭 최대 150/551, 발열 serious에서).
- **자세 경고가 사용자에게 가는가**: 데모 화면(main)에서는 **아니오** — 말한 대사의 95%가 데모(칭찬 ↔ 운동별 대표 경고, 판정 아님)이고 3D 자세 키는 하나도
  안 나갔다. ai/real-feedback 병합 뒤(새 기본값)에는 **예** — 스쿼트 squat_knee_valgus가 말풍선·음성으로 2회 나감. 다만 이 클립은 정상 동작이라 **오경보일
  가능성이 높고**(Ex3D 스쿼트 3D knee_valgus 20/120렙, 앞선 문서), 임계값은 검증되지 않았다.
- **endSet**: 병합 뒤 Flutter가 목표 렙에서 endSet을 보내고, 네이티브가 3D 꼬리 5프레임을 flush·판정(5/5 ok)한 다음 세트 범위 키
  (squat_no_lockout n=2, pushup_no_lockout n=8)와 onSetEnd(worstJoint)를 보낸다. 세트 범위 키는 기록에만 들어가고 말하지 않는다(설계).
- 좌우: RTMPose 손목 좌우 바뀜 0%(39클립, Mac 재생 vs 라벨). 로우 20° 클립의 “왼손을 오른손으로” 현상은 RTMPose가 아니라 **손 crop 분기**
  (두 crop이 같은 손, 94%) — 예전 오버레이가 원시 MediaPipe 손목을 그려서 보였다. lift-refine 오버레이(XS 입력 손목을 그림)에서는 0프레임.

## 1. End-to-End (Runner 카메라 입력 → Flutter 피드백) — FPS·지연
> 항목 1–4·6의 **기준 값은 아래 “새 기본값 39클립”(nominal 발열, 실제 판정 화면)** 절이다. 이 절과 2–4절의 39클립 표는 그 전에 데모 화면·serious 발열에서 돈 실행이라
> 비교·참고용으로 남긴다.

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
  로우·스쿼트는 모든 관절 0.2% 이하. 앱 경로(반전) 기기 키포인트로 같은 측정: 아래 “기기 경로 좌우” 표(새 기본값 39클립).
- **사용자가 본 “왼손을 오른손으로”(barbellrow_0000_cam2, 20°, 가까운 쪽 오른쪽, 13:59)**: 오버레이 반전 문제 아님(영상 모드에서 미리보기·오버레이 같은
  좌표, isFrontCamera=false), RTMPose 바뀜 아님(위 0%). 원인은 **손 분기**: 두 손목이 몸 높이의 0.16(≈110 px)만큼만 떨어져 256 px crop이 겹치고,
  MediaPipe(numHands=1)가 왼쪽 crop에서도 보이는 오른손을 돌려줌(검출의 94%), 두 crop이 같은 손인 프레임 488/590. 예전 오버레이는 crop마다 원시
  MediaPipe 손목을 그려서 손목 점이 다른 손으로 튀어 보였다. XS 입력은 reject_crossed로 대부분 막혔다(6/590만 샘).
- 기기 실측(오버레이 손목 재구성, `overlay_wrist_jumps.py`): 예전 오버레이(1dee827) 그린 손목이 다른 손 위 L 94 / R 344(585 프레임), 0.5 아래팔 넘게 튐
  8 / 30. **lift-refine 오버레이(5b14ee9 이후, XS 입력 손목을 그림)는 0 / 0, 튐 0 / 0** — 손 중복 제거를 꺼도(`BPT_HAND_DEDUPE=0`) 0 / 0. 중복 제거는
  같은 손 프레임 409개에서 MediaPipe 손목을 안 써서 XS 입력 손목 교체를 L 473 → 135, R 132 → 63 프레임으로 줄인다(판정·렙은 같음).

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

## 새 기본값 39클립 — 실제 판정 화면, 반전, nominal 발열 (항목 1·2·3·4·6의 기준 실행)
세 운동 모두 ai/lift-app-m2b98256 de42b9a(praise_good·말풍선 사양 포함; 로우는 21:4x에 다시 돌림 — 처음 e21a25f 실행은 Home `…-newdefault-row-e21a25f`). 목표 렙 = 정답(의사 정답),
Wi-Fi(로그는 폰에 쓰고 나중에 가져옴), 음성 0. 발열: 푸시업·스쿼트 nominal, 로우 재실행은 연속 실행 뒤라 serious. Home `20261020-device-video-newdefault-{row-de42b9a,pushup-de42b9a,squat-de42b9a}`(클립별 표 `tables.md`).

| 항목 | 로우(12) | 푸시업(15) | 스쿼트(12) |
|---|---|---|---|
| 1 처리 FPS(클립 범위) | 29.8–30.1 | 27.6–30.1 | 29.7–30.0 |
| 1 드롭 | 16/8,404 (0.2%) | 139/8,257 (1.7%) | 89/13,720 (0.6%) |
| 1 도착→판정 p50 / p95(클립 범위) | 187.9–190.8 / 191.4–198.6 ms | 189.6–199.7 / 195.3–376.5 ms | 189.8–190.7 / 195.5–204.2 ms |
| 1 도착→Flutter 응답 p95 | 188.7–197.6 ms | 196.1–382.8 ms | 197.8–232.0 ms |
| 1 프로세스 CPU p50 | 51–60% | 57–85% | 54–59% |
| 2 XS 추론/초 | 28.0 | 27.2 | 28.6 |
| 2 ok / warming_up / tracking_lost / partial_3d / bad_3d | 93.7 / 5.0 / 1.0 / 0.2 / 0% | 81.9 / 6.3 / 0 / 11.8 / 0% | 96.7 / 3.3 / 0 / 0 / 0% |
| 4 무릎 뒤집힘 / 각도 한계 걸린 프레임 | 16 / 10 | 35 / 1,353 | 0 / 1,353 |
| 4 XS 입력 손목 MediaPipe 교체 L/R | 5,577 / 4,460 (8,342 중) | 1,258 / 1,667 (8,043 중) | 9,094 / 9,391 (13,571 중) |
| 렙(앱/의사 정답), 정확한 클립 | 112/126, 9/12 | 151/150, 12/15 | 120/120, 12/12 |
| 3 (a) 3D 경고(렙) | standing_up 1 (e21a25f 실행은 torso_swing 1 추가) | no_lockout 8, setup_side_view 5, hand_position 1 | knee_valgus 20, no_lockout 17 |
| 3 (a) 비교용 2D 경고 | head_up 5, torso_swing 1, standing_up 1 | head_up 22, no_lockout 8, setup_side_view 5 … | no_lockout 19 |
| 3 (b) 렙 범위로 보냄 | praise_good 32, setup_side_view 4, tracking_lost 1 | praise_good 29, praise_fixed 6, setup_side_view 5, hand_position 1 | praise_good 30, knee_valgus 7, praise_fixed 1 |
| 3 (b) 세트 범위로 보냄(n 합) | 없음 | no_lockout 8 | no_lockout 17 |
| 3 (c) 말풍선·음성 | praise_good 32, setup_side_view 4(tracking_lost는 세트 끝 뒤라 안 보임) | 보낸 것 전부(41) | 보낸 렙 범위 전부(38) |
| 6 endSet → 꼬리 flush 판정 | 10/12 클립(5/5); 2클립은 렙이 목표에 못 미쳐 endSet 없음 | 14/15 | 12/12 |

- 데모 대사 0. 화면에 보이는 것 = 말한 것(같은 `_onNativeFeedback`). “세트 범위” 키(no_lockout)는 기록에만 들어가고 말하지 않는다.
- 렙 못 셈: 로우 뒤쪽 시점(76–80°) barbellrow_0001_cam3 0/10, barbellrow_0002_cam3 7/12 — 세트가 안 끝나 endSet도 없음. 푸시업 정면 pushup_0003_cam1 9/10.
- 정면 푸시업(cam1, 70–88°): partial_3d 20–74%, 도착→판정 p50 196–200 ms, 드롭 15–42, CPU 최대 85% — 무거운 시점은 정면 푸시업뿐.
- 반전·데모 화면 39클립(104ea89, serious 발열)과 비교하면 푸시업 드롭 5.7% → 1.7%, p95 최악 378 → 383 ms(정면 한 클립), 측면은 비슷 — 발열 상태 차이가 크다.

### 기기 경로 좌우(반전, 라벨은 같은 좌우 반전 후 비교) — `lr_device.json`
| 운동 | RTMPose 손목·팔꿈치·어깨 바뀜 | 엉덩이·무릎 바뀜(높은 클립) | 손 crop: 다른 손 검출 / 두 crop 같은 손 |
|---|---|---|---|
| 로우 | 0% (최대 0.1%) | 무릎 최대 1.3% | cam2(20–25°, 가까운 쪽 오른쪽)에서 검출의 43–50% / 프레임의 70–93%; 나머지 시점 0–1% |
| 푸시업 | 손목 0%, 팔꿈치 최대 16.9%(pushup_0003_cam3, 라벨 프레임 61개뿐) | 낮은 측면 cam3: 무릎 33–76%, 엉덩이 최대 79%(pushup_0002_cam3); cam2 최대 20% | 측면(17–35°)에서 49–50% / 83–99%; 정면 0% |
| 스쿼트 | 0% | 0% | 최대 8프레임 |

- 결론: **손목 좌우는 RTMPose 문제가 아니다**(39클립 전부 0%). 측면에서 손 crop이 같은 손을 잡는 것이 원인이고, 지금 오버레이는 그 손목을 그리지 않는다.
  **하체 좌우 바뀜은 실제로 있다** — 낮은 측면 푸시업에서 무릎·엉덩이가 30–80% 프레임에서 바뀐다(가려진 먼 쪽 다리). 3D(T2)에서 본 “먼 쪽 다리 과굽힘”과 같은 장면.

## L=3 vs L=5 (기기, 같은 빌드 de42b9a, 측면 6클립, 연달아)
| 클립 | 도착→판정 p50 / p95 L=5 → L=3 | 도착→Flutter p95 L=5 → L=3 | 처리 FPS | 드롭 | ok 비율 | 렙 | 3D 경고 차이 |
|---|---|---|---|---|---|---|---|
| barbellrow_0000_cam2 | 189.9 / 199.0 → 123.4 / 132.8 ms | 222.7 → 169.3 | 29.89 → 29.79 | 3 → 5 | 92.8 → 92.1% | 10 = 10 | 없음 |
| barbellrow_0003_cam2 | 190.2 / 205.5 → 123.6 / 139.9 | 199.9 → 149.8 | 29.76 → 29.64 | 7 → 10 | 91.5 → 90.7 | 11 = 11 | L=3에 head_up 1 추가 |
| pushup_0003_cam3 | 190.2 / 197.7 → 123.6 / 133.2 | 199.5 → 162.7 | 29.88 → 29.66 | 3 → 7 | 93.6 → 92.6 | 10 = 10 | 없음 |
| pushup_0004_cam3 | 189.9 / 196.3 → 123.0 / 130.2 | 199.5 → 154.2 | 29.93 → 29.81 | 2 → 4 | 88.3 → 90.2 | 10 = 10 | 없음 |
| squat_0001_cam1 | 190.9 / 199.2 → 123.9 / 133.1 | 226.7 → 147.5 | 29.83 → 29.83 | 8 → 8 | 96.7 → 96.3 | 10 = 10 | 없음 |
| squat_0003_cam1 | 190.6 / 199.3 → 123.9 / 132.0 | 224.9 → 158.5 | 29.90 → 29.85 | 5 → 7 | 97.2 → 96.8 | 10 = 10 | no_lockout 3 → 4 |

- L=3은 판정 지연을 **정확히 2프레임(−67 ms)** 줄이고 FPS·CPU는 같다. 렙은 같고 경고는 클립당 0–1렙 차이. 3D 정확도 차이는 기기에서 **평가 불가**(정답 없음) —
  Fit3D T3 결과는 `lift_app.md`. 기본값은 L=5 그대로(환경 변수로만 L=3).

## 가로 푸시업 — 폰을 가로로 든 경우(캡처 연결은 세로 고정 → 장면이 90° 돌아 들어옴), `BPT_CAMERA_VIDEO_ROTATE=90`
푸시업 15클립, 반전 뒤 시계 방향 90° 회전(처리 이미지 720×1280), de42b9a(m COCO17), 목표 렙 = 정답, nominal. 비교 = 같은 빌드의 세로(녹화 그대로) 실행.
Home `20261020-device-video-landscape-pushup-de42b9a`.

| 클립 | 각도 | 렙 가로/세로/정답 | 3D ok 가로/세로 | partial_3d 가로/세로 | 처리 FPS 가로/세로 | 도착→판정 p50 가로/세로 | (a) 3D 경고 가로 | (a) 세로 | (b) 가로로 보낸 렙 범위 키 |
|---|---|---|---|---|---|---|---|---|---|
| pushup_0000_cam1 | 88° | 10/11/10 | 57/59% | 38/34% | 29.75/28.07 | 197.4/198.1 | head_up 5, no_lockout 3, hand_position 1 | setup_side_view 1 | hand_position 1, praise_fixed 1 |
| pushup_0000_cam2 | 48° | 10/10/10 | 96/96% | 0/0% | 29.99/29.99 | 189.7/189.8 | **hip_pike 10** | hand_position 1 | **hip_pike 3** |
| pushup_0000_cam3 | 24° | 10/10/10 | 96/96% | 0/0% | 29.84/29.94 | 190.0/189.9 | hand_position 1 | – | hand_position 1, praise_fixed 1, praise_good 2 |
| pushup_0001_cam1 | 70° | 10/10/10 | 54/92% | 39/1% | 29.44/29.23 | 196.8/197.5 | head_up 4, hip_pike 3, no_lockout 2, hand_position 1 | setup_side_view 1 | hand_position 1, praise_fixed 1 |
| pushup_0001_cam2 | 25° | 10/10/10 | **7**/92% | **85**/0% | 29.93/29.94 | 190.2/190.4 | hip_pike 1 | – | – |
| pushup_0001_cam3 | 21° | 10/10/10 | 92/92% | 0/0% | 29.89/29.93 | 190.0/189.9 | hand_position 1 | – | hand_position 1, praise_fixed 1, praise_good 2 |
| pushup_0002_cam1 | 83° | 10/10/10 | 62/20% | 32/74% | 29.11/29.11 | 198.8/199.0 | head_up 9, hip_pike 4, hand_position 1 | setup_side_view 1 | hand_position 1, hip_pike 1, praise_fixed 1 |
| pushup_0002_cam2 | 35° | 10/10/10 | 90/93% | 3/0% | 29.87/29.82 | 190.2/190.4 | hip_pike 1 | – | praise_good 3 |
| pushup_0002_cam3 | 20° | 10/10/10 | 94/92% | 0/0% | 29.75/29.87 | 189.9/189.6 | hand_position 1 | – | hand_position 1, praise_fixed 1, praise_good 2 |
| pushup_0003_cam1 | 86° | 10/9/10 | 35/48% | 59/48% | 29.77/29.77 | 194.7/195.9 | hip_pike 1, hand_position 1 | setup_side_view 1 | hand_position 1, praise_fixed 1 |
| pushup_0003_cam2 | 40° | 10/10/10 | 94/94% | 0/0% | 29.88/29.88 | 190.1/189.7 | **hip_pike 9** | no_lockout 8 | hip_pike 2, praise_good 1 |
| pushup_0003_cam3 | 10° | 10/10/10 | 93/94% | 0/0% | 29.93/29.93 | 190.3/190.3 | hand_position 1, no_lockout 1 | – | hand_position 1, praise_fixed 1, praise_good 2 |
| pushup_0004_cam1 | 87° | 10/11/10 | 16/71% | 79/20% | 29.52/27.57 | 198.6/199.7 | head_up 8, hip_pike 3, hand_position 1 | setup_side_view 1 | hand_position 1, hip_pike 1, praise_fixed 2 |
| pushup_0004_cam2 | 31° | 10/10/10 | **6**/95% | **90**/0% | 29.99/30.06 | 190.1/189.7 | hip_pike 4 | – | hip_pike 1 |
| pushup_0004_cam3 | 18° | 10/10/10 | 94/88% | 0/7% | 29.87/30.00 | 189.9/189.8 | hand_position 1, no_lockout 1 | – | hand_position 1, praise_fixed 1, praise_good 2 |

- **돌아가는 것**: 2D와 렙 수 — 가로에서 15/15클립 정확(세로는 12/15). FPS·지연은 세로와 같다(처리 이미지가 앱 카메라와 같은 세로 720×1280이 되어 정면 클립은
  오히려 드롭이 줄었다).
- **안 되는 것(앱에 방향 처리 없음)**: ① 3D가 일부 시점에서 무너진다(pushup_0001_cam2·0004_cam2 ok 92–95% → 6–7%, partial_3d 85–90%) — XS 입력이
  누운 사람을 세로 그대로 받는다. ② 자세 규칙이 화면 위쪽을 위로 가정해서 **가로에서만 나오는 경고**가 생긴다: hip_pike(9클립; 사선 cam2 5클립에서 1–10렙),
  hand_position(10클립, 렙 1씩), 정면의 head_up 4–9렙 — 이 중 hip_pike·hand_position은 실제로 사용자에게 나갔다. ③ 정면에서 setup_side_view(“옆으로 서 주세요”)가
  사라졌다(옆면 판정이 이미지 축 기준).
- 결론: 가로 촬영은 지금 앱에서 **지원되지 않는다**(렙만 맞음). 고치려면 기기 방향(가속도계)이나 2D 몸통 방향으로 회전 보정하는 단계가 필요하다(제안, 코드
  변경 없음; 중력 정렬 BPT_3D_GRAVITY는 영상 모드에 기기 자세가 없어 **평가 불가**).
- **반대 방향 270°**(같은 빌드, Home `20261020-device-video-landscape-pushup270-de42b9a`): 렙 다시 15/15. 3D가 무너지는 시점이 바뀐다 — 90°에서는 사선 cam2
  (ok 6–7%), 270°에서는 낮은 측면 cam3(pushup_0000·0001·0004_cam3 ok 26–31%, 세로 88–96%). hip_pike가 cam3에서 7–10렙, 정면에서 9렙(0003_cam1), hand_position
  10클립, no_lockout 정면 9렙 — 방향마다 다른 오경보. 회전 보정 브랜치(ai/orientation-m2b98256) 전후 비교의 “전” 값으로 쓴다.

## m COCO17 vs m Halpe26(사용자 결정 D8 이후) — ⏳ ai/halpe-default-m2b98256 빌드 병합 뒤 39클립·준비 자세 비교

<!--PENDING-->

## 최종 보고 (A–G) — 2026-10-20 기준
### A. 검증된 사실
1. **XS 3D는 실제 앱 경로에서 매 프레임 돈다**: 추론 26.9–29.3회/초, Neural Engine에서(xctrace, MPS·GPU ML 0). 탑재 가중치는 H36M 원본 XS
   (weight.bin `37a5c834…f38e`, 모든 실행 빌드에서 같음) — Fit3D 미세조정본 아님.
2. **E2E**(카메라 입구 → Flutter 메서드 채널 응답): 측면 30 fps, 도착→판정 p50 188–191 ms(그중 167 ms는 3D lookahead 5프레임), Flutter 응답 p95
   측면 대부분 196–232 ms, 최악 275 ms(로우 한 클립)(nominal). 정면 푸시업만 27.6–29 fps·p95 최악 383 ms. 위젯 그리기는 **측정 안 함**. L=3이면 판정이 정확히 67 ms 빨라진다(FPS·CPU 같음).
3. **자세 경고 전달**: 병합 전 main 화면에서는 3D 자세 키가 Flutter에 0건, 말한 대사의 95%가 데모(판정 아님). 병합 뒤(현재 main 2b98256과 같은 실제 판정
   기본값)에는 판정 경고가 말풍선·음성으로 나간다 — 39클립에서 스쿼트 knee_valgus 7회, 푸시업 hand_position 1회, 칭찬(praise_good) 91회(로우 32·푸시업 29·스쿼트 30), 준비 안내
   (setup_side_view) 9회. 데모 0.
4. **endSet**: Flutter가 목표 렙에서 보내고, 네이티브가 3D 꼬리 5프레임을 flush·판정(36/36 세트에서 5/5), 세트 범위 키(no_lockout)를 기록에만 보내고,
   onSetEnd(worstJoint)를 보낸다. 렙을 못 채운 3클립(로우 뒤쪽 2, 정면 푸시업 1)은 endSet 자체가 없다.
5. **30분 연속(전원 뺌)**: 배터리 100→80%, 발열 nominal→fair 6.8분→serious 19.4분, FPS·지연·단계 시간 드리프트 없음(측면 스쿼트).
6. **좌우**: RTMPose 손목 좌우 바뀜은 39클립 모두 0%(Mac 재생·기기 반전 경로 둘 다). 사용자가 본 “왼손→오른손”은 측면 손 crop이 같은 손을 잡는 문제
   (+ 예전 오버레이가 원시 손목을 그림) — 새 오버레이에서 0프레임. **하체는 실제로 바뀐다**: 낮은 측면 푸시업 무릎 33–76%, 엉덩이 최대 79%.
7. **운동 화면이 화면 자동 잠금을 끄지 않았다** → 전원 뺀 폰이 운동 중 잠김(실측). 고침은 ai/lift-app·main(D-M-02)에 들어감, 기기에서 전환 4종 확인.
8. 오버레이 v1→v3 그리기 비용: FPS·지연·CPU 차이가 같은 빌드 실행 간 잡음보다 작다. 판정·렙·보낸 키는 빌드 사이에 렙 단위까지 같다.
9. setup-constraint (b) 적응형 제약: 제안 규칙 통과(lift3d p95 −0.07~−0.24 ms, 렙 같음). (c) 준비 자세: COCO17에서는 준비됨 0, s Halpe26 데모에서 1.
10. 뼈 길이 목표(P1·P2): 판정·렙·지연 변화 없음.
11. **가로 촬영은 지원되지 않는다**: 렙은 15/15 맞지만 3D가 일부 시점에서 무너지고(ok 6–7%), 가로에서만 나오는 경고(hip_pike·hand_position)가 사용자에게 나간다.

### B. 가설(검증 안 됨)
- 정상 동작 클립에서 나온 knee_valgus·no_lockout 등은 **오경보**다(임계값 미검증, 사람이 확인한 라벨 없음) — 지금 사용자에게 실제로 들린다.
- 정면 푸시업이 무거운 것은 손 분기(정면에서 두 손이 보여 MediaPipe가 매 프레임 돎)와 지표별 무효화 때문(CPU 78–92%).
- XS 추론당 ANE 구간 13개 → 일부 연산이 CPU에서 돈다.
- setup_ready 0(COCO17)은 준비 항목 하나가 끝까지 안정·유효하지 않아서 — 발 점이 있는 Halpe26에서는 준비됨.
- 18:40 이후 실행의 판정 p50 +2 ms(188 → 190)는 코드가 아니라 기기 상태(배터리 전원) 차이.
- 로우 뒤쪽 시점(76–80°)의 렙 실패는 2D 상태기계가 그 시점에서 팔 움직임을 못 보는 것.
- 가로에서 렙만 맞는 것은 렙 상태기계가 관절 각(회전 불변)을 쓰고, 자세 규칙·옆면 판정은 이미지 축(위·아래)을 쓰기 때문.

### C. 고친 이전 판단
- “startSet/endSet을 Flutter가 안 보낸다”·“자세 키가 기본값에서 안 나간다”(이 문서 첫 판·main 데모 화면 기준) → ai/real-feedback 병합 뒤로는 틀림.
- “좌우 혼동은 RTMPose 탓”(사용자 추정) → 손목은 RTMPose 0%, 손 crop 분기 탓. 하체(푸시업)는 RTMPose 탓이 맞다.
- 39클립 E2E(푸시업 드롭 5.7%, p95 378 ms)는 serious 발열에서 잰 값이었다 → nominal에서 1.7%. 발열 상태를 함께 적어야 한다.
- 문서 초안의 컴파일 XS coremldata/metadata 해시(da6e95a3·2de07361)는 잘못 옮긴 값 → 모든 빌드 d97e3221·90a8ffbf.

### D. 데이터 신뢰도
- 정답: Exercise3D 렙·2D는 Sapiens 의사 정답, 3D 정답 없음 → 기기에서 3D 정확도·L=3 정확도·뼈 길이 목표 효과는 **평가 불가**(Fit3D 결과는 lift_app.md).
- 영상-카메라 모드는 카메라 캡처·자동 노출·조명을 재현하지 않는다. 전면 반전은 vImage(카메라에는 없는 1 ms 미만 비용). 가로는 한 방향(90°)만.
- 판정은 실행마다 조금 다르다(드롭이 판정 프레임을 바꿈: 같은 빌드에서 knee_valgus 3 vs 4렙). 한 번 실행 비교는 이 잡음 안에서만 읽을 것.
- 발열: 데모 화면 39클립 두 번은 serious에서(충전 중 연속), 새 기본값 39클립은 nominal에서.
- 배터리는 iOS가 5% 단위로 준다. 30분 실행 로그(67 MB)는 Wi-Fi 복사가 60 MB에서 끊겨 Mac 사본이 잘림 — 결과는 완전한 perf 로그에서 냈다.
- 세지 않은 실행: 설치 직후 첫 실행(모델 컴파일 ~31초), 자동 잠금된 실행 2개, 사용자가 폰을 만진 실행 1개, 27ddcd6 setup 실행(옛 오버레이) — 모두 폴더에 사유.

### E. 재현 가능한 결과
- Home `~/bpt-runs/lift-app/20261020-device-*` 36개 폴더 + `20261020-xctrace-coreai-1dee827`(각 `home_manifest.json`: 파일별 sha256·명령·git, Home에서
  `sha256sum -c` 확인). 실행 manifest(`manifest.json`)에 클립 sha256·환경 변수·앱 바이너리와 컴파일 모델 sha256·launched_at.
- 스크립트(이 브랜치): `device_video_runs.py`(실행), `analyze_device_video_runs.py`·`device_runs_tables.py`(6항목 표), `compare_device_runs.py`(빌드 전후),
  `overlay_wrist_jumps.py`, `ex3d_lr_swap.py`·`ex3d_lr_swap_device.py`·`ex3d_hand_assoc.py`(좌우), `device_perf_summary.py`, `setup_check_summary.py`.

### F. 권고
1. 실제 판정 기본값(main D-M-02)은 임계값 미검증이라 정상 스쿼트에 “무릎이 안으로 모여”가 클립당 0–2회 들린다 → 사람이 라벨한 검증 클립으로 임계값을
   확인하기 전에는 경고 키를 줄이거나(예: 우선 등급만), 검증 일정을 잡을 것(결정은 사용자).
2. 낮은 측면 푸시업의 하체 좌우 바뀜(무릎 33–76%)은 Halpe26 전환에서 꼭 다시 볼 것(사용자 결정 D8 진행 중).
3. 운동 화면 자동 잠금 끔은 이미 main에 들어감(D-M-02) — 유지.
4. 정면 푸시업은 무겁고 3D가 반쯤 무효 → 측면 안내(setup_side_view)를 유지하고, 정면 시 손 분기를 줄이는 실험을 제안(코드 변경 없음).
5. 로우 뒤쪽 시점은 렙을 못 센다 → 측면 안내 필요(이미 setup_side_view가 나감).
6. 장시간: 측면은 30분 문제없음. 무거운 시점의 30분은 아직 측정 안 함.
7. 가로 촬영: 지원하려면 회전 보정 단계(기기 자세 또는 2D 몸통 방향)가 먼저 필요 — 그 전에는 세로 촬영 안내를 유지(결정은 사용자).

### G. 사용자 승인이 필요한 것
- `ai/lift-app-m2b98256`(XS 라이브 3D·3D 판정·영상 모드 도구·lift-refine 오버레이 v3·partial_3d 안내 숨김·praise_good 말풍선 사양)을 integration에 병합할지.
- 실험적 보정 유지 여부: MediaPipe 손목 교체(효과 미확인), 해부학 제약(정확도 이득 없음), 손 crop 중복 제거(lift-refine). 스쿼트 무릎 반사는 효과 검증됨.
- setup-constraint 적응형 제약·준비 자세 채택 여부(제안 규칙 통과했지만 규칙 자체가 미승인).
- 실제 판정 경고를 지금 임계값 그대로 사용자에게 계속 들려줄지(F-1).
- 30분 실행 로그 67 MB와 새 오버레이 xctrace를 위해 폰을 USB로 잠깐 연결하기(Wi-Fi에서는 60 MB 넘는 복사와 xctrace가 안 됨).
- 가로 촬영 지원(회전 보정) 개발 여부.
