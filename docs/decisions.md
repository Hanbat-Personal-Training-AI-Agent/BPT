# 결정 기록

한 결정에 한 항목: 날짜, 결정, 근거 수치, 기각한 대안과 이유, 되돌리는 방법.
근거가 수치로 없는 추정은 "추정"으로 표시합니다. 각 트랙은 맨 아래에 자기 항목을 덧붙입니다.

용어
- **렙 정확도** = (정답 렙 − 놓친 렙) ÷ (정답 렙 + 추가로 센 렙). 놓침/추가는 정답 렙 저점과 앱 렙 끝을 순서대로 맞춰 셉니다.
- **정확 일치 세트**: 센 렙 수가 정답과 같은 세트(카메라 1개 = 1세트).
- **측면(±40°)**: 카메라가 몸 옆에서 40° 이내(0° = 정측면). Exercise3D gt.json 각도 기준.
- **p99**: 정상 렙 지표 값을 작은 순서로 늘어놓았을 때 99% 지점. 정상 렙의 1%만 이 값을 넘습니다.
- **Exercise3D**: 스쿼트 4·푸시업 5·바벨로우 4세트 × 카메라 3대. 정답 렙은 Sapiens 기반 삼각측량 라벨(`not_ground_truth`, 검토 전).
- 이 문서의 수치는 모두 같은 Exercise3D 데이터로 조정하고 같은 데이터로 잰 값입니다(조정용/검증용 분리 전). 사람 단위 분리 후 수치는 각 트랙이 덧붙입니다.
- 근거 파일 `outputs/rep_validation/*`은 git 밖(로컬)입니다.

---

## D-01 앱 2D 기본 모델 COCO17, Halpe26은 선택 (2026-10-09)
- **결정**: `RTMPoseModel.active = .coco17`. Halpe26은 `BPT_POSE_MODEL=halpe26`(Xcode scheme) / `pose-replay --model halpe26`. (`4c5890e`, 직전 `66a811a`의 Halpe26 전환을 되돌림)
- **근거**: 전환 당시 커밋 본문에는 수치 없음(사용자 지시로 되돌림 — 추정). 이후 측면 렙 정확도는 COCO17이 같거나 높음:
  | 운동 | COCO17 | Halpe26 |
  |---|---|---|
  | 스쿼트 | 100% | 100% |
  | 바벨로우 | 97.6% (7/8) | 94.0% (4/8) |
  | 푸시업(현재) | 97.8% (8/9) | 100% (9/9) |
  Halpe26은 푸시업에서 엉덩이·발목 신뢰도가 0.22–0.30으로 낮아 tracking_lost 오경보 7회(규칙 변경 전, `I_setup_keys.md`).
- **기각**: Halpe26 기본(`66a811a`) — squat_03 1→2렙, 캘리브레이션 guided 영상 4장 완료가 근거였으나 SQ1/SQ2 뒤 COCO17도 squat_03 2/2. 발뒤꿈치(heel_rise)는 Halpe26만 되지만 그 키는 꺼져 있음(D-03).
- **되돌리기**: `RTMPoseModel.active = .halpe26`. 최종 모델 선택은 트랙 C가 이어서 기록.

## D-02 자세 경고 Flutter 전달 기본 끔 + 키별로 켜기 (2026-10-09)
- **결정**: `FormCommonConfig.enabledFeedbackKeys`(기본 빈 집합)에 든 키만 `onFeedback`으로 보냄. 판정·렙 리포트·세션 로그는 항상 기록. (`122c2af`)
- **근거**: 경고 임계값이 전부 임시값이었고 틀린 자세 영상이 없어 어떤 키도 검증 불가. 임시 임계값에서 정상 렙 초과율 pushup_hip_sag 81%, pushup_head_drop 44%, row_torso_swing 37%(`E_warning_dist_coco17.md`).
- **기각**: 전부 켜기 — 정상 렙에도 경고가 쏟아짐. 전역 on/off 하나 — 키별 검증 순서와 안 맞음.
- **되돌리기/켜기**: 키 이름을 `enabledFeedbackKeys`에 추가. 켜려면 해당 키의 틀린 자세 영상에서 렙별 검출률과 정상 영상 오경보율을 이 문서에 기록(BRIEF §4).

## D-03 squat_heel_rise 끔 (2026-10-09)
- **결정**: `SquatFormConfig.heelRiseEnabled = false`. 지표는 로그에 남김. (`122c2af`)
- **근거**: 발뒤꿈치 점은 Halpe26에만 있고 기본 모델은 COCO17(D-01). Exercise3D 분포 N렙 0(COCO17), 정상/틀린 자세 데이터 모두 없음.
- **기각**: Halpe26일 때만 켜기 — 검증 데이터 없음.
- **되돌리기**: `heelRiseEnabled = true` (+ Halpe26).

## D-04 스쿼트 빠른 렙: SQ1(top→bottom 직행 시작) + SQ2(bottom→top 직행 종료) (2026-10-09)
- **결정**: 빠르게 앉거나 일어나 descending/ascending을 거치지 않아도 렙 시작·종료로 인정. (`1438963`)
- **근거**: 측면 스쿼트 렙 정확도 COCO17 48.8%→**100%**, Halpe26 38.8%→**100%** (8/8). 놓친 렙 원인 1위가 no_start 47·54건(`C_baseline.md`). 진단에 안 쓴 squat_03(정답 2) COCO17 1→2. 흔들림 합성 88건·더미 6개 0렙 유지.
- **기각**: 확정 프레임 수 줄이기 — 흔들림 가짜 렙 위험(시험 안 함, 추정).
- **되돌리기**: `1438963` 이전 전이 규칙(커밋 단위로 되돌림, 플래그 없음).

## D-05 바벨로우: RW1(휴식 자세 우선) + RW2(한쪽 팔 허용) + 측면 게이트 0.56 (2026-10-09)
- **결정**: 어깨폭 ÷ 몸통 길이의 최근 150프레임 중앙값 ≤ **0.56**(첫 판정 30프레임, 히스테리시스 ±0.03)이면 측면. 측면일 때만 RW1(깊이<0.06 또는 팔꿈치>145°면 delta보다 먼저 bottom), RW2(한쪽 팔 관절만 확실해도 통과). 측면 아니면 렙을 세지 않고 setup_side_view. (`3b4274a`)
- **근거**: 측면 로우 렙 정확도 COCO17 62.1%→**97.6%**, Halpe26 63.5%→**94.0%**. 카메라별 비율: 20–25° 0.11–0.19, 33–36° 0.38–0.51, 후면 76–81° 0.66–0.84 → 측면 16/16, 후면 8/8 전 프레임 구분. 0.56 = 가장 넓은 36° 피험자(0.509) × sin40°/sin36°. 로우 평가기 흔들림 합성(측면으로 본 44건) 가짜 렙 12→0.
- **기각**: 게이트 없이 RW1+RW2만 — 후면 카메라가 무너짐(barbellrow_0001 cam3 10→0, 0002 cam3 12→2, `D_SQ1_SQ2_RW1_RW2.md`). 회귀식(비율=a·sinθ+b)의 40°≈0.44 — 실제 36° 카메라 2개가 측면 아님이 됨.
- **한계**: 40° 근처 데이터가 없어 0.51–0.66 사이 어느 값이든 결과가 같음. 사용자 0/30/40° 영상으로 확인 필요.
- **되돌리기**: 컷오프 값 변경 또는 `3b4274a` 되돌림.

## D-06 경고 임계값 = Exercise3D 정상 렙 p99 (2026-10-09)
- **결정**: pushup_hip_sag 0.06→**0.140**, pushup_head_drop 0.15→**0.376**, row_torso_swing 15°→**39.9°** (COCO17, 측면 ≤40°). (`1aebe63`)
- **근거** (`E_warning_dist_coco17.md`):
  | 키 | N렙 | p95 | p99 | 이전 임계 → 정상 렙 초과율 |
  |---|---|---|---|---|
  | pushup_hip_sag | 80 | 0.118 | 0.140 | 0.06 → 81% |
  | pushup_head_drop | 80 | 0.333 | 0.376 | 0.15 → 44% |
  | row_torso_swing | 84 | 26.9° | 39.9° | 15° → 37% |
  나머지 키는 이전 임계에서 정상 초과율 0–12%라 그대로.
- **기각**: p95 — 정상 렙 5% 오경보. p99는 정상 기준의 상한일 뿐, 틀린 자세를 잡는지는 모름 → 키는 계속 끔(D-02).
- **되돌리기**: `PushUpFormConfig`/`BarbellRowFormConfig` 값 또는 `1aebe63` 되돌림.

## D-07 몸통 각도 ±180° 언랩 (2026-10-09)
- **결정**: 렙 안 몸통 각도를 프레임 간 차이 (−180, 180]로 언랩한 뒤 min/max/평균. hips_first_torso_rise, row_standing_up, 3D 몸통 각도, 머리 각도 차이도 같은 처리. (`ac7a934`)
- **근거**: Fit3D barbell_dead_row에서 row_torso_swing p99 359°(179°와 −179°가 한 렙에 섞임). 수정 후 Exercise3D 측면 COCO17 p99 39.9°로 동일(오염 없었음).
- **기각**: 없음(버그 수정).
- **되돌리기**: `ac7a934` 되돌림(권장 안 함).

## D-08 준비 자세 확인(ReadyPoseGate) 기본 끔, 프리셋도 끔 (2026-10-09)
- **결정**: `readyPoseHoldFrames = 0`. 평가용 프리셋(스쿼트·로우 0.5초 + 허용치 2배, 푸시업 없음)은 `applyReadyPosePreset(fps:)` / `pose-replay --ready-pose preset`로만. (`d6396bd`, `f376ede`)
- **근거** (`G_ready_pose.md`, 측면 렙 정확도 COCO17/Halpe26):
  | 조건 | 스쿼트 | 푸시업(당시) | 로우 |
  |---|---|---|---|
  | 끔 | 100 / 100 | 84.8 / 81.1 | 97.6 / 94.0 |
  | 1초 | 73.8 / 78.8 | 0 / 0 | 23.8 / 32.1 |
  | 0.5초 + 허용치 2배 | 100 / 100 | 55.4 / 38.9 | 97.6 / 94.0 |
  세트 전 추가 렙: 끔 1건 → 켬 0건.
- **기각**: 기본 켬 — Exercise3D는 시작 후 1초 안에 첫 렙이라 정답 렙 손실. 프리셋은 손실 없지만 사용자 영상(2초 정지 후 시작)으로 확인 전까지 끔.
- **되돌리기/켜기**: 앱에서 프리셋 적용. 사용자 영상 검증 대기(트랙 A).

## D-09 푸시업 측면 판정: PU1 + PU2-B, 푸시업 측면 컷오프 1.0 (2026-10-10)
- **결정**: 측면일 때만 PU1(top→bottom 직행도 렙 시작) + PU2-B(경고 트래커가 고른 근측 팔 하나로 팔꿈치 각도). `sideViewRepFixes = true`, `sideViewArm = .trackerSide`. 측면 컷오프는 `PushUpFormConfig.sideViewMaxShoulderRatio = 1.0`(로우 0.56과 별도). (`6f29b5f`)
- **근거** (`J_pushup_side.md`, `H_pushup_failures.md`):
  | 모델 | 방식 | 측면 9세트 | 비측면 6세트 추가 렙 |
  |---|---|---|---|
  | COCO17 | 수정 전 | 3/9, −12/+2, 84.8% | +1 |
  | COCO17 | A(신뢰도 높은 팔) | 8/9, −2/+0, 97.8% | +2 |
  | COCO17 | **B** | **8/9, −2/+0, 97.8%** | **0** |
  | Halpe26 | 수정 전 | 4/9, −17/+0, 81.1% | +1 |
  | Halpe26 | A | 6/9, −5/+0, 94.4% | +2 |
  | Halpe26 | **B** | **9/9, 0/0, 100%** | +1 |
  컷오프: 0.56이면 40° Halpe26(0.75) 측면 아님, 48°(0.44–0.48) 측면 → 못 가름. 1.0이면 ≤48° 전부 측면, 70–88°(1.8–2.8) 전부 측면 아님.
- **기각**: A안 — Halpe26 pushup_0001 cam2(25°) 10→8 손실. PU3(팔꿈치 5프레임 중앙값 평활) — 지연으로 bottom을 놓쳐 93.3/87.8%. 0.56 공유 — 위 이유.
- **한계**: 1.0은 40°와 48°를 가르지 못함(48°도 측면).
- **되돌리기**: `sideViewRepFixes = false`(이전 동작), 컷오프 값 변경.

## D-10 tracking_lost: 렙 도중 금지, 1.0초 이상일 때만 렙 끝에 (2026-10-10)
- **결정**: 렙이 열려 있는 동안은 미루고, 손실이 `trackingLostFrames` 30(15→30, 30fps 1.0초) 이상 이어진 채로 렙이 끝나면 한 번 전달. (`3191fa6`)
- **근거** (`I_setup_keys.md`): 정상 Halpe26 푸시업 7회(5세트, 렙 도중 6) → **0**. 로우 Halpe26 2→1, COCO17 2→2(렙 도중 0). 나머지 0→0. 원인: 엉덩이·발목·손목 신뢰도 0.22–0.30(문턱 0.30 바로 아래).
- **기각**: 신뢰도 문턱 낮추기 — 다른 판정(관절 게이트)과 공유돼 영향 범위가 큼(추정, 시험 안 함).
- **되돌리기**: `trackingLostFrames = 15` + `3191fa6` 되돌림.

## D-11 셋업 키 기본 켬: setup_full_body, tracking_lost (전 운동), setup_side_view (로우만) (2026-10-09)
- **결정**: `enabledFeedbackKeys` 기본값 = setup_full_body, tracking_lost. 바벨로우 트래커만 setup_side_view(측면 아님 첫 판정 시 첫 렙 전 세션당 1회). (`513858a`)
- **근거**: 정상 데이터 오경보(`I_setup_keys.md`): setup_full_body 전 데이터 0회. tracking_lost는 D-10 뒤 렙 도중 0회. 로우 후면 카메라 8/8에서 setup_side_view 29–32프레임에 발생, 측면 카메라 0회. 푸시업·스쿼트 setup_side_view는 정상 렙 초과율 4%(푸시업)라 기록만.
- **기각**: 자세 경고 키도 켜기 — 틀린 자세 데이터 없음(D-02).
- **되돌리기**: `enabledFeedbackKeys`에서 키 제거.

## D-12 3D: 사람 중심 정사각형 crop 정규화 기본, 무릎 과신전 보정 끔·감지 켬 (2026-10-09)
- **결정**: MotionAGFormer 입력 = person_crop(Python `DEFAULT_3D_NORMALIZATION`, Swift `MotionAGFormerNormalization.default3D`). 무릎 과신전 보정 OFF, 감지는 상시 ON(걸린 프레임 = "3D 불량", 3D 지표에서 제외). (`b6a2cd9`, `85c2a46`, `de1a265`)
- **근거**: screen 정규화는 세로 영상에서 y가 ±1.78까지 가 학습 범위(±1) 밖 → squat_03 정강이/허벅지 0.57(목표 0.96), 무릎 clamp 92% 프레임. person_crop: 0.96, clamp 0%, 뼈 보정 다리 35.5%→3.1%, 세로 더미 4개 0.59–0.73→0.94–0.97. 보정은 정면 스쿼트·회전 영상 정상 프레임 23–92%에서 걸려 끔.
- **기각**: screen(이전), long_side(A안).
- **되돌리기**: 위 상수 한 곳 변경.

---
<!-- 각 트랙 항목은 이 아래에 D-<트랙>-<번호> 형식으로 덧붙여 주세요. -->

## D-H-01 코리 음성: 미리 만든 mp3를 먼저, 실시간 ElevenLabs TTS는 파일이 없을 때만 (2026-10-11, 제안 — 앱 코드 반영은 팀원·사용자 결정)
- **상황**: main에 팀원 커밋 `0d00676`(#40)이 들어옴 — `KoriSpeaker.swift`가 대사를 그때그때 ElevenLabs로 합성(voice "manbo" `ZZ4xhVcc83kZBfNIlIIz`, 모델 `eleven_flash_v2_5`, 타임아웃 8초, 실패 시 iOS 기본 음성, 실행 중 메모리 캐시 64줄, 파일 저장 없음). 캘리브레이션(`CalibrationVoice`)과 운동 피드백(Flutter `KoriVoiceService` → 채널 `bpt/kori_voice`) 모두 이걸 씀. integration/ai에는 아직 없음.
- **비교**:
  | 항목 | 실시간 TTS (main #40) | 미리 만든 mp3 (`scripts/generate_kori_voice.py`) |
  |---|---|---|
  | 비용 | 앱을 켤 때마다 새로 합성(메모리 캐시는 재시작하면 사라짐). 사용자·세션 수에 비례 | 한 번 188파일 5,623자. 대사 바꿀 때만 다시 |
  | 지연 | 네트워크 왕복 + 합성(측정 없음, 수백 ms로 추정). "렙 직후 바로" 경고가 늦어질 수 있음 | 0 (로컬 재생) |
  | 오프라인·약한 망(헬스장) | 실패/8초 대기 후 iOS 기본 음성 → 목소리가 바뀜 | 그대로 재생 |
  | 키 | **API 키가 앱 번들 Info.plist에 평문으로 들어감**(아래 보안 항목) | 앱에 키 없음. 생성하는 사람 셸에만 |
  | 범위 | 모든 문장(영어, 임의 숫자) | 고정 대사 + 숫자 1..20, 한국어만. 나머지는 실시간/기기 TTS로 떨어짐 |
- **결정(제안)**: 번들 mp3를 먼저 찾고, 없을 때만 실시간 TTS(그다음 iOS 기본 음성). 같은 목소리가 되도록 스크립트 기본 voice/model을 KoriSpeaker와 맞춤. 스크립트는 `manifest.json`({앱이 띄우는 문장: 파일})도 써서, 문장만 받는 KoriSpeaker가 키 없이 파일을 찾을 수 있게 함(키를 받는 트랙 E의 WorkoutVoice는 `<key>[_<n>].mp3` 이름 규칙).
  - 연결 방법(팀원 코드라 직접 안 고침): `KoriSpeaker.speak`에서 `cache[text]` 확인 전에 `manifest[text]` 번들 파일을 재생. 캘리브레이션은 문장이 전부 고정이라 27줄 모두 파일로 커버 → 캘리브레이션은 네트워크 불필요.
  - 출시/외부 배포 빌드에서는 앱 번들의 키를 빼고(실시간 끔) 파일 + 기기 TTS만 쓰거나, 서버(Modal 등)를 거쳐 합성하는 것을 권장.
- **기각**: (a) 실시간만 — 위 지연·오프라인·키 노출. (b) 파일만 — 영어·21렙 이상 숫자 등 빈칸이 생김(그 부분은 기기 TTS로 충분할 수도 있음, 추정).
- **같이 정해야 할 것(충돌)**: main #40의 Flutter `_speakFeedback`(onFeedback 때 `KoriVoiceService.speak`)과 트랙 E의 네이티브 WorkoutVoice(onFeedback 답으로 받은 대사를 말함)가 합쳐지면 **같은 대사를 두 번 말함**. main 병합 때 하나만 남겨야 함 — 음소거(`setVoiceMuted`)·대기열·★ 끊기 규칙이 있는 WorkoutVoice를 남기고 그 재생 엔진으로 KoriSpeaker(파일→실시간→기기 TTS)를 쓰는 것을 제안.
- **되돌리기**: 앱 쪽은 아직 반영 전. 스크립트는 독립(`--voice-id`, `--model-id`로 다른 목소리).

## 트랙 F — 캘리브레이션(계약·품질·인계) — 2026-10-10

### F1. 상태 값·결과 JSON은 계약 문서 쪽으로 맞춘다 (백엔드 `"COMPLETED"`가 아니라)
- 결정: `GET /v1/calibrations/jobs/{jobId}`의 `status`는 계약 문서(docs/research/calibration_serverless_upload.md)의 소문자 `queued|running|done|failed` 그대로. 결과 JSON 키도 계약 그대로 두고, 백엔드 `UserCalibration`과 같은 이름의 필드만 **추가**: `progressRate`(응답 최상위), `coachComment`, `calibratedAt`, `modelGlbUrl`(result 안).
- 근거: 배포 서버와 계약 문서를 비교한 결과 상태 값·`smplBeta`·`boneLengthData`는 이미 일치했고, 다른 것은 백엔드 엔티티뿐(기본 `status="COMPLETED"`, `progressRate`·`modelGlbUrl`·`coachComment`·`calibratedAt` 열). 팀원이 "상태 값과 결과 JSON 형식은 기존 계약 문서 기준"이라고 함. 앱(`fetchJob`)·서버·e2e가 소문자로 맞물려 있어 대문자로 바꾸면 세 곳을 다 바꿔야 함. 추가 필드만 넣었으므로 기존 클라이언트와 호환(앱은 `progressRate`가 없으면 done 100/그 외 0으로 읽음).
- 영향: 백엔드는 저장할 때 소문자를 그대로 저장하거나 대응표로 변환(docs/handoff/teammate_calibration.md 6절, 제안만 — Spring 코드는 손대지 않음). main의 `UserCalibration`에는 `coachComment` 열이 없음(일부 팀원 브랜치에만 있음).
- 버린 안: 서버를 `COMPLETED/FAILED`로 바꾸기 — 계약·앱·테스트 동시 변경, 팀원 방침과 반대.
- 되돌리기: 추가 필드는 무시해도 됨. 커밋 revert.

### F2. worker가 죽어도 작업이 `running`에 남지 않게: 조회 시 감시(watchdog) + 30분 기한
- 결정: `fit_body.spawn`의 call id를 `state/call/{jobId}`에 저장(작업 기록과 다른 키라 worker 쓰기와 경쟁 없음). 조회 때 `queued/running`이면 (a) 접수 후 30분(`service.JOB_DEADLINE_SECONDS`, fit_body 15분 제한 + 대기·cold start 여유) 지나면 `failed timeout`, (b) `modal.FunctionCall.get(timeout=0)`가 끝난 호출을 알리면 `FunctionTimeoutError → timeout`, 그 밖의 예외 → `internal_error`. worker는 시작할 때와 끝낼 때 기록이 `failed`면 덮어쓰지 않는다. `retries=0` 명시.
- 근거: worker 안의 예외는 이미 `failed`로 기록됐지만 OOM·컨테이너 중단·Modal 제한 시간은 except를 건너뜀. Modal 1.6.1 실측: 실행 중 호출의 `get(timeout=0)`은 **builtin `TimeoutError`**를 던짐(`modal.exception.TimeoutError`가 아님) — 처음 배포에서 이 차이로 모든 작업이 즉시 `internal_error`가 됐고 e2e로 잡아 고침(테스트 `tests/test_modal_app.py`).
- 검증: pytest(충돌한 worker, 기한 초과 뒤 늦게 끝난 worker, 끝난 작업은 감시 무시), 배포 e2e 성공·실패 경로.
- 버린 안: 기한만 쓰기 — 컨테이너가 죽은 경우 앱이 30분 기다림. Modal 호출 상태만 쓰기 — 상태 저장(R2) 실패처럼 호출은 끝났는데 기록이 없는 경우 외에 큐에서 사라진 호출을 못 잡음.
- 되돌리기: `create_app(call_failure=...)` 기본값(None 반환)으로 두면 기한만 동작.

### F3. 스텁·가짜 결과는 `done`이 될 수 없다
- 결정: `worker.stub_fit` 삭제, `build_result`는 항상 `stub: false`이고 β·관절 필수. `worker.require_real`이 `stub is not False`, β 10개 유한수 아님, 뼈 길이 없음/범위 밖(0~200cm)이면 `failed internal_error`. 앱 `fetchJob`도 `stub != false` 또는 `smplBeta`/`boneLengthData` 없는 `done`을 오류로 처리.
- 검증: pytest 3가지 가짜 결과 → failed·결과 파일 없음, flutter 테스트 "a stub result is never accepted as done".

### F4. β≈0의 원인과 수정: 재투영 보정에서 β를 움직이지 않는다 (`refine_beta=False`)
- 원인(측정): 재투영 보정의 β 사전항 `1e-3·‖β‖²`가 데이터항(키로 정규화한 관절 오차의 Huber, 관절당 약 1e-5)보다 두 자릿수 커서 300 step 동안 β가 0으로 끌려감. MHR→SMPL 변환기 β는 |β| 최대 2.3인데 보정 후 β2~β9가 ±0.1 안쪽. 또 지금까지의 두 결과는 모두 키 170cm 입력이라 β1(키 방향)까지 같았음 → "사람이 달라도 β≈0".
- 평가: People Snapshot 24개 영상(12명) + 앱 캡처 엔진으로 만든 묶음 2개(같은 사람). 기준은 데이터셋의 consensus 메시(SMPL 위상, 옷 offset 포함 — **정답 아님**)에 `J_regressor_h36m`. 지표 = 팔다리 12개 구간 길이의 평균 절대 % 오차(입력 키 = consensus 메시 키). "키만" = 평균 체형을 같은 키로 맞춘 것(사진 정보 0). 사람 단위로 나눔(조율 6명 / 보류 6명; 고른 것은 변형 하나뿐).

| 변형 | 조율 (13묶음) | 보류 (13묶음) | 전체 | 재투영 px | fit 초 |
| --- | --- | --- | --- | --- | --- |
| 키만 (사진 없음) | 6.02 | 4.25 | 5.13 | - | - |
| 이전 (β 사전 1e-3, β 보정) | 5.75 | 4.16 | 4.96 | 5.22 | 14.3 |
| β 사전 1e-5 | 3.88 | 3.17 | 3.53 | 4.96 | 13.7 |
| **변환기 β 유지 (채택)** | **3.13** | **2.83** | **2.98** | 5.60 | 13.7 |

- 해석: 이전 방식은 "키만"과 거의 같았다(사진이 체형에 기여 안 함). 변환기 β를 쓰면 보류 세트 오차 4.16→2.83%. 재투영 오차는 0.4px 늘지만(β를 2D에 맞추지 않으므로) 길이 정확도가 목적. 같은 사람 다른 옷(남1·남2·남3)의 허벅지 길이 사람 내 표준편차 0.92cm < 사람 간 2.10cm. 앱 RTMPose 키포인트 묶음과 데이터셋 OpenPose 키포인트 묶음의 결과 차이 0.04~0.1%p.
- 한계(추정): 기준 메시 키가 단안 추정이라 일부(male-5-sport 140cm)는 틀림 → 그 묶음 오차가 큼(≈10%). β10이 사람마다 ≈+2로 일정한 것은 MHR→SMPL 변환의 계통 치우침으로 보임. 실제 사용자 실측(줄자) 검증은 안 함.
- 버린 안: β 사전 1e-5 — 변환기 β 유지보다 나쁨. 실루엣/마스크 손실 — Sapiens2 금지, 다른 분할 모델 도입은 라이선스·비용 검토 필요(후속).
- 되돌리기: `fitting.Fitter(refine_beta=True)`.
- 재현: `scripts/build_people_snapshot_calibration_bundles.py` → `modal run server/calibration_modal/eval_fit.py --bundles <dir>`.

### F5. GLB: 서버에서 만들고 R2 presigned GET(1시간)으로 본인에게만
- 결정: fitting이 정면 사진의 자세(전역 회전 0, 키 반영 β)로 SMPL 메시를 만들어 glTF binary로 `models/{jobId}.glb`에 저장. 조회 때마다 1시간짜리 presigned GET을 `result.modelGlbUrl`로 붙임(키를 짧게 해 URL 약 410자 ≤ 백엔드 열 500자). 앱의 `CALIBRATION_STORAGE_HOSTS`와 같은 호스트.
- 라이선스: SMPL 모델 라이선스 https://smpl.is.tue.mpg.de/modellicense.html — "License Grant": 비상업 연구·교육·예술 목적만, 상업 제품·서비스·상업용 산출물 금지. "No Distribution": 모델 복사·배포 금지. 결과물(메시)에 대한 별도 조항 없음. → 모델 파일(v_template, shapedirs)은 배포하지 않고, 사용자 한 명의 메시만 본인에게 비상업(캡스톤) 용도로 제공. 상업화 땐 Meshcapade 상업 라이선스 필요. SAM 3D Body: SAM License(https://github.com/facebookresearch/sam-3d-body/blob/main/LICENSE, 1.a 상업 사용 가능, 1.b.v 군사 등 금지, 1.b.i 재배포 시 약관 사본). MHR: Apache-2.0(https://github.com/facebookresearch/MHR/blob/main/LICENSE). People Snapshot은 F8.
- 버린 안: 앱에서 β로 메시 생성 — SMPL 모델을 앱에 넣어야 해 "No Distribution" 위반. 영구 공개 URL — 비공개 버킷 원칙 위반.

### F6. 운동 3D 분석에 캘리브레이션 뼈 길이 연결은 보류
- 결정: 이번 트랙에서 연결하지 않는다. `BoneLengthConstraint`(Swift)·`bone_lengths.py`는 이미 `result`/`boneLengthData`를 읽을 수 있음(`BoneLengthConstraint.loadTargets`).
- 근거: 라이브 카메라에서 3D가 꺼져 있음(`enableMotion3DForCamera = false`, 트랙 D 소유). 이전 측정에서 길이를 고정해도 방향은 모델 출력 그대로라 관절각이 좋아진다는 근거가 없음(pose_feedback/geometry/README.md). 효과를 재지 못하는 변경을 3D 트랙 파일에 넣으면 병합 충돌만 늘어남.
- 다음 단계: 트랙 D가 3D를 켤 때, Flutter가 `done` 결과의 `boneLengthData`를 네이티브에 넘기고 selected3D → 뼈 길이 고정 → 무릎 차단 순서로 연결, 각도 오차 전후 비교.

### F7. 2D 뼈대를 돌리는 임시 결과 화면 → 실제 결과(관절 3D) 화면은 브랜치에만
- `lib/features/onboarding/screens/onboarding_result_screen.dart`는 팀원(Jinjeonz) 코드. 실제 `jointsH36m`을 드래그로 회전해 그리는 화면과 라우터 `extra` 전달을 브랜치 `ai/calibration-result-screen`에 준비하고 integration/ai에는 합치지 않음(사용자·팀원 승인 필요). GLB 렌더는 웹뷰 패키지(model_viewer_plus 등) 추가가 필요해 보류, 관절 3D로 충분히 "실제 결과".
- integration/ai에는 우리 코드인 분석 화면(대부분 06-month 작성)의 polling·진행률·실패 문구·결과 요약만 반영.

### F8. People Snapshot(평가 데이터) 라이선스와 업로드 정리
- 라이선스 원문: https://graphics.tu-bs.de/people-snapshot 의 "Dataset" 절(사이트는 2026-10-10 서버 오류, Wayback 사본 https://web.archive.org/web/20231203010136/https://graphics.tu-bs.de/people-snapshot 에서 확인). 요지: 비독점·양도 불가; "download the Dataset and use it on computers owned, leased or otherwise controlled by you and/or your organisation"; 비상업 연구·교육·예술 목적만; "Without prior written approval from the authors, the Dataset, in whole or in part, shall not be further distributed, published, copied, or disseminated in any way or form whatsoever"; 논문 인용 의무(Alldieck et al., CVPR 2018). 우리가 받은 HF 미러(gqy2468/People-Snapshot)에는 라이선스 파일이 없었지만 원 데이터셋 조건을 따른다.
- 판단: 캡스톤 평가는 비상업 연구·교육. 로컬(scratchpad)·Modal 컨테이너(임대 컴퓨팅)·R2(임대 저장소)에서의 처리는 "leased or otherwise controlled" 범위로 볼 수 있으나 **애매함 → 사용자 확인 필요**.
- 조치(2026-10-11): (1) git에는 데이터셋 사진·프레임·메시·키포인트·개별 측정값을 넣지 않음(스크립트·집계 수치만; 인계 문서의 결과 예시는 꾸민 값으로 교체). (2) 이 트랙 e2e가 R2에 올린 객체(테스트 사용자 3명의 사진·manifest·결과 JSON·GLB·상태, 44개)를 삭제. (3) `eval_fit.py`의 임시 앱은 사진을 함수 인자로만 넘겼고 우리 쪽 저장(Volume·R2)은 없음; Modal 내부의 일시적 입력 보관은 우리가 지울 수 없음. (4) R2에 남은 `calibrations/999999`, `results/999999`(이전 세션의 e2e 사용자, 더미 영상 사진 추정)는 이 트랙이 만든 것이 아니라 지우지 않았음 → 사용자 결정. (5) 로컬 압축 해제본·묶음은 트랙 종료 때 삭제.
- 앞으로: 실제 사용자 영상(본인 동의) 또는 라이선스가 분명한 데이터로 같은 평가를 다시 하는 것이 맞다.
