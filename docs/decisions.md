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

## 트랙 E — 앱 연결 (onFeedback·WorkoutVoice·onSetEnd·세트별 녹화) — 2026-10-10

### E1. onFeedback 계약: `{key, n?, scope: "rep"|"set"}` (기존 `silent` 폐기)
- 결정: 렙마다 고른 1개 키(우선·개선·셋업·praise_fixed, setup_full_body·tracking_lost)는 `scope:"rep"`, `n` 없음(그 대사들엔 `{n}`이 없고, main의 `_nativeFeedbackCounts`가 이벤트마다 `n ?? 1`을 더하므로 누적 n을 보내면 과다 집계됨). 참고 등급 키는 렙마다 보내지 않고 Flutter `endSet` 때 키당 1번 `scope:"set"`, `n` = 그 세트에서 걸린 렙 수(`{n}` 대사: pushup_no_lockout·pushup_head_drop·pushup_head_up·squat_no_lockout·row_head_up). 고르지 못한 우선·개선 키는 보내지 않는다(렙 리포트·세션 로그·세트 집계(worstJoint)에만 남음).
- 근거: 팀원 요청 1의 형식, 스펙 "참고 = 세트 후 요약만". 키 활성 목록(`enabledFeedbackKeys`)·전달 규칙(1렙 1개, 3렙 쿨다운, 개선 2연속, 셋업 1회, praise_fixed)은 그대로이고 테스트로 고정(FormWarningsTests 기존 + `testSetEndSummaryScope`).
- 기본값에서 실제로 나가는 키는 바뀌지 않음: setup_full_body, tracking_lost(+로우 setup_side_view). 참고 키는 전부 OFF라 `scope:"set"`은 아직 안 나간다.
- 버린 안: 고르지 못한 키도 `silent`로 보내기 — 요청 형식에 없고, Flutter(main)가 모든 onFeedback을 말풍선·횟수로 세므로 중복 집계됨.
- 되돌리기: 이 커밋 revert.

### E2. 벤치프레스·데드리프트: 폼 키 없이 setup_full_body·tracking_lost·praise만
- 결정: `FormExercise.benchPress/deadlift`(규칙 0개) + `StatusDrivenFormTracker`가 평가기 상태로 렙 구간을 잡는다(벤치 lowering/bottom/pressing, 데드 rising/top/lowering, unknown은 렙 유지, 렙 수 증가 = 렙 끝). 필수 관절: 벤치 어깨·팔꿈치·손목(누우면 다리가 벤치에 가림, 추정), 데드 어깨·엉덩이·무릎·발목(스쿼트와 같음). 평가기 파일은 트랙 G 소유라 손대지 않음.
- 근거: 팀원 요청 2. tracking_lost는 다른 운동과 같이 렙 도중엔 미루고 1.0초 이상일 때만(테스트 `testStatusDrivenBenchDeadlift`).
- 주의(추정): 벤치·데드 실영상으로 셋업 키 오경보를 재지 않았다. 지금까지는 아무 키도 안 나갔으므로 셋업 키 오경보가 "늘 수 있는" 유일한 변화 — 트랙 G가 실영상으로 확인하고 필요하면 `StatusDrivenFormTracker` 생성을 빼면 된다(CameraPosePreview `statusFormTracker`).

### E3. 대사 원문은 dart에만: 네이티브는 onFeedback의 **답**으로 대사를 받는다
- 결정: Flutter가 onFeedback을 처리하며 `{text, lang}`(kori_feedback_lines.dart `render`, `{n}`·언어 반영)를 돌려주고 네이티브 WorkoutVoice가 그걸 말한다(`lib/features/workout/data/native_pose_channel.dart` `koriVoiceReply`). 답이 null(모르는 키·일시정지·세트 끝난 뒤의 rep 이벤트)이면 말하지 않는다 → 말풍선과 음성이 항상 같다.
- 버린 안: (a) 시작 때 대사표 전체를 채널로 보내기 — 언어 전환·`{n}` 채우기를 네이티브에 다시 구현해야 함. (b) 네이티브 사본 — 금지 조건.
- 지연: MethodChannel 왕복 1회(ms 단위, 추정)라 "렙 직후" 규칙에 영향 없음.

### E4. WorkoutVoice: ★ = 우선 등급, mp3 우선, 대기 3초 넘으면 버림
- ★ 표시는 스펙(docs/research/form_feedback_spec.md)에 없다. "렙 직후 바로"인 **우선** 등급 키(pushup_hip_sag, squat_hips_first, squat_knee_valgus, row_torso_swing)를 ★로 봤다(추정 — 사용자 확인 필요). ★는 말하던 것을 끊고 바로, 나머지는 줄 서고 3초 넘게 기다리면 버린다.
- 음원: Flutter 에셋 `assets/kori_voice/<key>.mp3`, `{n}` 대사는 `<key>_<n>.mp3`(한국어일 때만). 없으면 AVSpeechSynthesizer(ko-KR / en-US). 에셋 폴더는 아직 없음(트랙 H가 만들면 pubspec에 `assets/kori_voice/` 추가).
- 음소거: `setVoiceMuted {muted}` → 재생 중지·대기열 비움. 음소거 상태는 화면이 들고(세트 사이 HUD가 사라져도 유지), 버튼은 상태 없는 위젯으로 바꿈.
- 주의: main의 팀원 코드(`KoriVoiceService`, ElevenLabs 실시간 TTS, 채널 `bpt/kori_voice`)도 onFeedback 때 대사를 말한다. integration/ai에는 아직 없지만 main과 합칠 때 둘 중 하나만 남겨야 이중 재생이 안 된다(사용자 요청 목록).

### E5. onSetEnd·worstJoint
- 세트 경계는 Flutter가 정한다(목표 렙 도달·끝내기). Flutter → `endSet {setIndex}` / `startSet {setIndex}`(1세트는 카메라 시작 때 자동). 네이티브는 endSet 때 세트 요약(scope set) → 녹화 파일 닫기 → `onSetEnd {setIndex, videoLocalPath|null, worstJoint|null}`.
- worstJoint = 그 세트에서 가장 많은 렙에 걸린 **켜진**(enabledFeedbackKeys) 경고 키의 관절, 동률은 규칙 순서(등급 높은 것). 꺼진 키는 검증 안 된 판정이라 사용자에게 새지 않게 뺐다 → 지금 기본값에선 항상 null. 키→관절 표는 `FeedbackJoint.byKey`, dart 경고 키 집합과 같음을 테스트로 고정.

### E6. 세트별 녹화(기본 OFF)·perf 로그·보관 개수
- 녹화: 포즈 추정에 쓴 같은 샘플 버퍼를 AVAssetWriter(H.264, 720p = 캡처 720×1280 그대로, 2.5 Mbit/s)로 `Documents/workout_videos/<시각>_<운동>_set<k>.mp4`. 카메라 세션 추가 없음.
- 기본 OFF: 실기기 FPS 측정 전(사용자 일). 켜기: 실행 환경변수 `BPT_SET_RECORDING=1` 또는 UserDefaults `BPTSetRecording`. 측정에서 FPS 감소 ≤10%면 기본 ON으로 바꿀 것. 절차 docs/research/set_recording_perf.md, 비교 `scripts/compare_perf_logs.py`.
- perf 로그: `BPT_PERF_LOG=1` → 1초마다 `workout_form_logs/perf_<운동>_<시각>.jsonl` {pose_fps, dropped_frames, thermal, battery, recording}.
- 보관 N = 20: 운동 1회 ≈ 2종목 × 5세트 = 10파일, 최근 2회분. 1분 세트 ≈ 19 MB라 최대 ≈ 0.4 GB. 새 녹화 시작 때 오래된 것부터 지움. 서버엔 경로만 저장되므로 지워진 옛 기록의 영상은 재생 불가 — 앱이 파일 없음을 처리해야 함(팀원).

### E7. main의 팀원 음성(#40, 0d00676)과 겹침 — 경쟁 경로를 만들지 않는 방식
- 확인한 사실(origin/main, integration/ai엔 아직 없음): `KoriVoiceService.speak`(채널 `bpt/kori_voice` → 네이티브 `KoriSpeaker`, ElevenLabs 실시간 합성·실패 시 AVSpeech)가 onFeedback마다 말풍선 대사를 말하고, 말하던 것을 매번 끊는다(대기열·★·3초 버림 없음). 음소거 버튼은 화면 표시만 바뀌고 음성은 안 끔. onFeedback은 `{key, n}`만 읽고 `scope`는 모름, `endSet/startSet`은 안 보냄.
- 결정: 네이티브 WorkoutVoice는 **Flutter가 onFeedback에 대사를 답할 때만** 말한다(E3). main의 핸들러는 null을 돌려주므로 main 코드 그대로면 WorkoutVoice는 소리를 내지 않는다 → 이중 재생이 구조적으로 안 생김. integration/ai의 화면(이 트랙이 고친 판)은 답을 돌려주고 자체 TTS 호출은 없음.
- 채널 계약 충돌 없음: 메서드 이름(`onFeedback`·`onPoseUpdate`) 같음, 키 이름은 같은 dart 표 기준(테스트), `scope`는 main이 무시해도 안전(세트 요약은 세트 끝난 뒤 와서 main에선 버려짐), `n`은 E1대로 맞춤. `setVoiceMuted`·`startSet`·`endSet`·`onSetEnd`는 새 메서드라 main 쪽엔 없음(없으면 녹화가 1세트 파일 하나로 이어지고 onSetEnd가 안 옴 — 녹화는 기본 OFF).
- 팀원 합의 필요(main과 합칠 때 한쪽 선택): (a) 네이티브 WorkoutVoice 유지(★·대기열·음소거 처리) + 음원 백엔드를 KoriSpeaker(ElevenLabs)로 바꿔 끼우기, Flutter의 `_speakFeedback` 호출 제거 — 권장. (b) 팀원 Flutter TTS 유지, onFeedback 답을 null로 → WorkoutVoice 무음, 대신 음소거 버튼을 KoriVoiceService에 연결해야 함. 어느 쪽이든 native_pose_workout_screen.dart는 양쪽이 고쳐서 수동 병합 필요.
