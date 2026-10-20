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
  | 항목 | 실시간 TTS (main #40) | 미리 만든 mp3 (팀원 직접 생성) |
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
- **같이 정해야 할 것(충돌)**: 트랙 E 설계(E7)상 WorkoutVoice는 Flutter가 onFeedback에 대사를 답할 때만 말하므로, main 코드 그대로(답 null)나 integration 코드 그대로(Flutter 자체 TTS 없음)에서는 이중 재생이 없다. `native_pose_workout_screen.dart`를 수동 병합하면서 main #40의 `_speakFeedback`과 integration의 답 반환을 **둘 다 남기면** 같은 대사를 두 번 말한다 → 한쪽 선택. E7 (a)안(WorkoutVoice 유지 + 음원 엔진을 KoriSpeaker로, Flutter `_speakFeedback` 제거)에 동의하며, 그 엔진에 이 항목의 재생 순서(파일 → 실시간 → 기기 TTS)를 넣는 것을 제안.
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

## D-B-01 RTMPose 입력을 사람 3:4 crop으로, 라이브 카메라·pose-replay 공통 (2026-10-10)

- **결정**: 이전 프레임 키포인트로 사람 상자(+여백)를 잡아 3:4 비율을 유지한 채 192×256에 넣는다(`RTMPoseCropTracker` + `PosePreprocess.drawRegion`, RTMPoseInputTensor.swift).
  신뢰도 0.3 이상 관절이 6개 미만이면 사람을 놓친 것으로 보고 다음 프레임은 전체 프레임(이전 입력: 늘려 넣기)으로 다시 찾는다.
  상자는 사람이 벗어나거나 크기가 [0.8, 1.35]×새 목표를 벗어날 때만 움직인다(캘리브레이션 CalibrationFrameAnalyzer.updateCrop과 같은 방식).
  키포인트는 crop → 전체 프레임 좌표로 되돌려(`Affine2x3`) 평가기·손·3D 정규화(person_crop, `MotionAGFormerNormalization.default3D`)는 그대로 쓴다.
- **근거** (Exercise3D 13세트×3카메라×2모델, pose-replay 실제 RTMPose 추론, 3D 없음; 측면 = 각도 반올림 ≤40°):

  | 운동 | 모델 | 분할 | 이전(전체 프레임) | crop |
  |---|---|---|---|---|
  | 스쿼트 | COCO17 / Halpe26 | 튜닝·검증 모두 | 100% / 100% | 100% / 100% |
  | 푸시업 | COCO17 | 튜닝(P1) | 97.8% (8/9) | **100%** (9/9) |
  | 푸시업 | Halpe26 | 튜닝(P1) | 100% | 100% |
  | 바벨로우 | COCO17 | 튜닝 / 검증 | 95.5% / 100% | 97.7% / 100% |
  | 바벨로우 | Halpe26 | 튜닝 / 검증 | 95.5% / 92.5% | 97.7% / **100%** |

  정지 구간 키포인트 흔들림(프레임 간 가속도 평균, px) 2.4–5.9 → 2.4–3.2 (푸시업 5.9 → 3.2).
  전체 프레임으로 되돌아간 프레임 비율 0.1–1.5%(영상 최대 7.7%). 셋업 키 오경보 측면 카메라 COCO17 3→0, Halpe26 2→0.
  squat_03·더미 6개 가짜 렙 0, 흔들림 합성 88건 0렙(소스 구간 수정 포함, 진행 기록 참고).
  상세: docs/progress/2026-10-10.md 트랙 B.
- **분할**: Exercise3D에 피험자 ID가 없어(`SUBJECT_MAPPING_UNAVAILABLE`) 영상을 보고 사람을 구분했다(추정, 옷·체형 기준).
  P1(검은 티·회색 반바지) = squat_0000/0001/0003, barbellrow_0000/0002, pushup_0000–0004 → 튜닝.
  P2(흰 티·회색 청바지) = squat_0002, barbellrow_0003, P3(모자 쓴 여성) = barbellrow_0001 → 검증(held-out).
  푸시업은 전부 P1이라 검증 세트가 없다.
- **버린 대안**
  - 첫 프레임·추적 실패 때만 가벼운 사람 검출기(RTMDet-nano/tiny): crop 추적이 78개 영상 모두 첫 프레임에서 사람을 잡았고(전체 프레임 입력은 대부분 1프레임),
    검출기 없이도 기준을 넘어서 쓰지 않음. 모델·라이선스 확인과 앱 용량·지연이 늘어나는데 이 데이터에서 이득을 보일 곳이 없다.
    주변 사람에게 붙는 문제가 실제 영상에서 나오면 다시 검토(이전 실험: outputs/crop_compare, outputs/rtmdet_tiny — Fit3D s12).
  - 전체 프레임 대신 레터박스(3:4로 검은 여백) 대체 입력: 가로 영상에서 사람이 너무 작아져 첫 검출이 더 어려워질 것(추정). 대체 입력은 기존 동작 그대로 둠.
  - 히스테리시스 상한을 3D crop처럼 2.0으로: 측정 안 함. 1.35에서 기준을 넘어 더 튜닝하지 않음.
- **되돌리기**: `CameraPreviewOptions.personCropInput = false`(CameraPosePreview.swift), pose-replay `--input full`.
  **바벨로우 측면 컷오프도 함께 0.56으로 되돌려야 한다**(D-B-02).

## D-B-02 바벨로우 측면 컷오프 0.56 → 0.66, crop 입력에 맞춤 — D-05 갱신 (2026-10-10)

- **결정**: `BarbellRowFormConfig.sideViewMaxShoulderRatio` 0.66 (scripts/eval_side_videos.py `SIDE_CUTOFF`도 0.66). 푸시업 1.0은 그대로.
- **이유**: crop은 비율을 바로 넣어 어깨폭 ÷ 몸통 길이가 측면 카메라에서 0.03–0.09 커진다. 0.56 그대로면 Halpe26 33–36° 카메라 2개에서
  첫 판정이 "측면 아님"이 되어 setup_side_view 오경보가 2건 늘었다(렙 도중 0).
- **근거** (150프레임 이동 중앙값의 범위, crop 입력):
  튜닝 P1 측면(20–36°) 0.16–0.62, 후면(77–81°) 0.71–1.27 → 중간값 0.66.
  검증 P2/P3 측면 0.17–0.63, 후면 0.69–0.82 → 0.66으로 모두 맞게 나뉨(히스테리시스 ±0.03 포함).
  | 바벨로우 | 0.56 + crop | 0.66 + crop |
  |---|---|---|
  | 측면 setup_side_view (COCO17 / Halpe26) | 0 / 2 | 0 / 0 |
  | 렙 정확도 Halpe26 튜닝 / 검증 | 97.7% / 97.5% | 97.7% / 100% |
  | 렙 정확도 COCO17 튜닝 / 검증 | 97.7% / 100% | 97.7% / 100% |
  | 후면 카메라 | 전부 측면 아님 | 전부 측면 아님 |
  이전 전체 프레임 입력에서도 0.66은 결과가 같다(정확도·셋업 키 동일)지만, 그 입력의 후면 최소값이 0.64라 여유가 없어 crop을 끄면 0.56으로 되돌린다.
- **한계**: 정면 squat_03의 crop 비율이 0.64–0.67이라 정면 촬영이 측면으로 판정될 수 있다(이전 0.56에서도 COCO17이 같은 영상을 측면으로 판정). 40° 근처는 여전히 미검증(데이터가 20–36°와 76–81°뿐). 0.66은 36° 최대(0.63)를 sin40/sin36으로 늘린 값(0.69)보다 작아 40° 카메라는 측면 아님이 될 수 있다(추정).
- **버린 대안**: 0.56 유지(오경보 증가로 회귀 기준 위반), P1만 보고 "가장 넓은 36° × sin40/sin36"(0.46×1.09=0.50 → 검증 피험자 측면 카메라가 측면 아님이 됨).
- **되돌리기**: 값 0.56.

---

## 트랙 C — 2D 모델 (fine-tune / 큰 모델 / COCO17 vs Halpe26) — 2026-10-11

용어(트랙 C)
- **PCK@0.05**: 예측 관절이 정답에서 "사람 박스 긴 변 × 5%" 안에 들어온 비율. body12 = 어깨·팔꿈치·손목·엉덩이·무릎·발목 12점, 팔다리8 = 팔꿈치·손목·무릎·발목.
- **평가 세트**: COCO val2017 사람 500명(수작업 정답, 원래 정확도 유지 확인용) / Exercise3D 2D(Sapiens2-5B 라벨 = 의사 정답, 모델 학습에 안 씀) 측면(≤40°)·비측면 / Fit3D s05(모션캡처 3D를 카메라로 투영, 학습에 안 쓴 피험자).
- **crop / stretch**: 사람 박스 3:4 crop 입력(트랙 B 이후 앱 입력) / 전체 프레임을 192×256으로 늘린 이전 입력.
- 렙 정확도는 트랙 B 병합 후 pose-replay(crop 입력, 3D 없음)로 같은 영상에서 다시 잼. 경고 이벤트 수는 꺼진 키도 "켰다면 났을" 수를 셈.

## D-C-01 Exercise3D 2D 라벨로는 학습하지 않음 (평가에만 사용) (2026-10-11)
- **결정**: Exercise3D 라벨(`facebook/sapiens2-pose-5b` 출력, `cam*_pose_metadata.json`의 `model`)을 미세조정 정답으로 쓰지 않는다. 모델 비교 평가에만 쓴다.
- **근거**: Sapiens2 License(https://github.com/facebookresearch/sapiens2/blob/main/LICENSE.md)는 "Sapiens Materials"(모델·코드·가중치)와 "derivative works"를 다루지만 출력(키포인트)으로 다른 모델을 학습하는 것은 명시하지 않는다(파생물 정의 없음). §1.b는 생체정보 처리(ii), 건강 등 민감정보 추론(vi)을 금지 — 운동 자세 교정 앱이 이에 해당하는지 해석이 갈린다. → 사용자 확인 항목.
- **되돌리기**: 사용자가 허용하면 `build_fit3d_pose2d_crops.py`와 같은 형식(labels.npz)으로 Exercise3D 크롭을 만들어 `train_pose2d_ft.py --train`에 추가.

## D-C-02 Fit3D 미세조정 모델은 채택하지 않음 (2026-10-11)
- **결정**: RTMPose-s COCO17을 Fit3D로 미세조정한 가중치는 앱에 넣지 않는다. 도구(`build_fit3d_pose2d_crops.py`, `train_pose2d_ft.py`)만 남긴다.
- **가능 여부**: Fit3D `joints3d_25`를 카메라(왜곡 포함)로 투영하면 COCO 몸 12점을 만들 수 있다(경험적 대응: 1 l_hip, 2 l_knee, 3 l_ankle, 4 r_hip, 5 r_knee, 6 r_ankle, 11–16 어깨·팔꿈치·손목, 9 ≈ 코 부근 머리 표지, 17–20 발가락, 21–24 손). 눈·귀·발뒤꿈치는 없다. 측면 카메라 없음(58–74°). Mac에서 크롭(피험자당 ~4,000장, 70 MB)·학습(MPS, 4,360장 6에폭 35분) 가능 → Modal 업로드 불필요.
- **근거** (학습 s03 1명, 선택·검증 s05 — Fit3D 다운로드가 2명에서 멈춤):
  | 모델 | COCO body12 | COCO 엉덩이 | COCO 얼굴 | Ex3D 측면 crop body12 | Ex3D 측면 푸시업 | Fit3D s05 body12 | Fit3D s05 팔다리8 |
  |---|---|---|---|---|---|---|---|
  | 현재 s COCO17 | **0.837** | **0.773** | **0.982** | **0.859** | 0.699 | 0.752 | 0.890 |
  | FT 얼굴 의사라벨 | 0.725 | 0.449 | 0.976 | 0.755 | 0.631 | **0.918** | **0.946** |
  | FT 얼굴 가중치 0 | 0.720 | 0.477 | 0.969 | 0.744 | 0.636 | 0.916 | 0.942 |
  | FT 얼굴+엉덩이·어깨 의사라벨 | 0.796 | 0.747 | 0.974 | 0.841 | **0.707** | 0.784 | 0.939 |
  | 위 + COCO train 6,000명 섞기 | 0.825 | 0.755 | 0.981 | 0.857 | 0.697 | 0.783 | 0.931 |
  - Fit3D 안에서는 좋아지지만(같은 정의를 배움), 독립 세트(COCO, Exercise3D)에서는 모두 같거나 나빠짐. 원인: Fit3D 엉덩이·어깨는 관절 중심이라 COCO 정의와 박스의 ~5% 차이(엉덩이 COCO PCK 0.77→0.45), 실험실 배경·사선 카메라만 있음.
  - 얼굴점: 의사라벨이 가중치 0보다 COCO 얼굴 PCK 0.976 vs 0.969로 약간 나음(둘 다 원래 0.982보다 낮음).
  - 신뢰도(conf p10)가 0.30→0.41–0.90으로 커져 tracking_lost·setup_full_body 임계값도 다시 맞춰야 함.
  - BN 통계를 갱신하면 학습 피험자에서도 오차가 0.046→0.067로 커져 BN을 고정함.
- **기각**: 더 많은 Fit3D 피험자로 재학습 — 정의 차이·배경 편향은 피험자 수로 안 풀림(추정). Exercise3D 라벨 학습은 D-C-01.
- **라이선스**: Fit3D로 학습한 가중치는 비상업(캡스톤) 용도만. 크롭·체크포인트는 Mac에서만 만들고 작업 후 삭제함.
- **되돌리기**: 해당 없음(앱 변경 없음).

## D-C-03 큰 모델: 기본은 RTMPose-s 유지, RTMPose-m COCO17은 기기 속도 확인 후 후보 (2026-10-11)
- **후보** (가중치 https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/, 코드·가중치 Apache-2.0 — https://github.com/open-mmlab/mmpose/blob/main/LICENSE. body7 가중치는 AIC·MPII·CrowdPose·Halpe 등 학습 데이터 각자의 라이선스(일부 비상업)를 따름 — 지금 Halpe26 모델도 같음):
  `rtmpose-m_simcc-coco_pt-aic-coco_420e-256x192-d8dd5ca4`(m COCO17), `rtmpose-m_simcc-body7_pt-body7_420e-256x192-e48f03d0`(m body7 COCO17), `rtmpose-m_simcc-body7_pt-body7-halpe26_700e-256x192-4d3e73dd`(m Halpe26), `rtmpose-s_simcc-body7_pt-body7_420e-256x192-acd4a1ef`(s body7 COCO17). 입력 1×3×256×192, SimCC 출력 그대로 → 앱 디코더 변경 없음. 기존 변환 경로(`export_rtmpose_s_coreml.py`)로 변환, PyTorch 대비 fp16 Core ML 키포인트 차이 최대 0.5–2 px(입력 좌표), 번들 s 모델은 같은 경로로 재변환 시 출력이 동일.
- **2D 정확도 / 렙 정확도** (렙: crop 입력, 측면 ≤40°, 괄호 = 정확 일치 세트, 놓침/추가):
  | 모델 | COCO body12 | Ex3D 측면 crop body12 | Ex3D 측면 푸시업 | 측면 스쿼트 | 측면 푸시업 | 측면 로우 | 비측면 푸시업 | tracking_lost / 셋업 키(측면) |
  |---|---|---|---|---|---|---|---|---|
  | s COCO17 (현재) | 0.837 | 0.859 | 0.699 | 100% (8/8) | 100% (9/9) | 98.8% (7/8, -1) | 100% | 0 / 0 |
  | s Halpe26 | 0.834 | 0.898 | 0.843 | 100% | 100% | 98.8% (-1) | 100% | 0 / 0 |
  | s body7 COCO17 | 0.833 | 0.907 | 0.887 | 100% | 100% | 98.8% (-1) | 96.7% (-1/+1) | 1 / 0 |
  | **m COCO17** | 0.858 | 0.873 | 0.702 | 100% | 100% | **100%** | 98.3% (-1) | 0 / 0 |
  | m body7 COCO17 | 0.868 | 0.943 | 0.919 | 100% | 84.6% (-13/+1) | 88.1% (-10) | 95.0% | 0 / 1 |
  | m Halpe26 | **0.872** | **0.950** | **0.927** | 100% | 81.1% (-17) | 100% | 98.3% | 1 / 2 |
  - 사람 단위: 검증 피험자(P2·P3, 트랙 B 매핑) 스쿼트 2캠·로우 4캠은 m body7(로우 75%)을 빼고 모두 100%. 푸시업은 전부 P1이라 검증 세트 없음.
  - squat_03 2/2, 더미 3개 × 스쿼트·로우 0렙: 모든 후보 유지.
  - m Halpe26·m body7의 푸시업 붕괴 원인: 첫 프레임(전체 프레임 입력)에서 바닥에 엎드린 사람 대신 뒤에 서 있는 다른 사람을 잡고, crop 추적이 그 사람을 계속 따라감(pushup_0004 cam2 재생 키포인트 PCK 0.02, 사람 박스 crop에서는 0.96). 모델 정확도가 아니라 사람 선택 문제 → 트랙 B에 전달.
- **결정**: 기본 모델은 바꾸지 않음. m COCO17은 2D(COCO +2.1%p, Ex3D 측면 +1.4%p)·측면 로우 렙(98.8→100%)이 좋아졌지만 비측면 푸시업 1렙 놓침, **실기기 속도 미측정**이라 전환 조건(실시간 유지) 미확인.
- **속도**: iPhone 17 측정 도구 `tools/pose_model_bench`(사람 없이 XCTest로 300회 추론). 기기 잠금 → 개발자 인증서 미신뢰("Developer App Certificate is not trusted")로 실행 못 함 → 사용자 확인 항목. Mac M4 참고값(다른 작업과 동시 실행, 잡음 큼, .all): s 5.4 ms, m 24.7 ms(p50 4.9 vs 14.0). GFLOPs는 s 0.68, m 1.93(RTMPose 논문 표, 추정 2.8배).
- **되돌리기/켜기**: m을 쓰려면 `assets/coreml/rtmpose_m_forward.mlpackage`를 `ios/Runner/NativePose/Models/`에 넣고 `RTMPoseModel`에 케이스 추가(번들 크기 +26 MB). 그 전에 기기 속도와 p99 재계산 필요.

## D-C-04 COCO17 vs Halpe26: 기본 COCO17 유지, Halpe26 전환은 사용자 결정 (2026-10-11)
- **근거**(같은 RTMPose-s, crop 입력):
  | | COCO17 | Halpe26 |
  |---|---|---|
  | COCO val body12 / 엉덩이 | 0.837 / 0.773 | 0.834 / 0.734 |
  | Ex3D 측면 body12 / 푸시업 | 0.859 / 0.699 | 0.898 / 0.843 |
  | Fit3D s05 body12 | 0.752 | 0.758 |
  | 측면 렙 스쿼트·푸시업·로우 | 100 / 100 / 98.8% | 100 / 100 / 98.8% |
  | 비측면 푸시업 | 100% | 100% |
  | tracking_lost·셋업 키 오경보(측면) | 0 · 0 | 0 · 0 |
  | 꺼진 경고 키가 켜졌다면 났을 수(측면) | 12 | 9 |
  | 발뒤꿈치 PCK@0.05 (Sapiens 발뒤꿈치 대비) | 없음 | 0.940 (m 0.974) |
  - p99(측면 정상 렙, crop): pushup_hip_sag 0.093 / 0.091, pushup_head_drop 0.308 / 0.170, row_torso_swing 17.1° / 20.3°. 지금 임계값(0.140, 0.376, 39.9°)은 전체 프레임 입력 기준이라 두 모델 모두 정상 렙 초과율 0%. 이 키들은 꺼져 있음.
- **판단**: 렙·오경보는 같고 2D(측면·푸시업)와 발뒤꿈치는 Halpe26이 낫다. 전환 조건(PCK 향상, 렙 유지, 오경보 비증가)은 만족. 다만 D-01에서 사용자가 Halpe26 기본을 되돌렸고, 캘리브레이션 캡처(트랙 F)에도 영향이 있어(이전 dummy_03 결과 변화) 기본값은 바꾸지 않고 사용자 결정으로 올림. 실기기 속도도 Halpe26은 미측정.
- **heel_rise**: Halpe26 발뒤꿈치는 측면 정확도가 높아 검증에 쓸 수 있으나, 발뒤꿈치 들림(틀린 자세) 영상이 없어 `heelRiseEnabled = false` 유지(D-03).
- **되돌리기**: `RTMPoseModel.active` 기본값 / `BPT_POSE_MODEL=halpe26`.

## D-B-03 crop 사람 재확인: 1초마다 전체 프레임 한 번 더, 뚜렷하고 더 큰 다른 사람이면 옮김 (2026-10-11)
- **문제**(트랙 C, D-C-03): 첫 전체 프레임에서 RTMPose-m Halpe26이 바닥의 사용자 대신 뒤에 서 있는 사람을 잡고, crop이 계속 그 사람만 봄.
  pushup_0004 cam2 1/10렙, pushup_0001 cam2 4/10렙, 측면 푸시업 81.1%.
- **결정**: `RTMPoseCropTracker`가 추적 30프레임(≈1초)마다 전체 프레임 추론을 한 번 더 요청(`wholeFrameRecheckDue` → `recheckWholeFrame`, 앱·pose-replay 공통).
  전체 프레임의 사람으로 옮기는 조건은 넷 다:
  1. 신뢰도 0.3 이상 관절 12개 이상
  2. 그 관절들의 평균 신뢰도 0.42 이상
  3. 키포인트 상자 넓이가 지금 사람의 1.5배 이상
  4. 그 상자 중 지금 crop 안에 든 부분이 30% 이하
  추가 비용은 30프레임에 추론 1번(+3.3%). 새 검출기는 쓰지 않음.
- **근거** (Exercise3D 13세트×3캠, crop 입력, 측면 ≤40°; base = 재확인 없음):
  | 모델 | 측면 스쿼트 / 푸시업 / 로우 base → new | 셋업 키 오경보(측면) base → new | 지터 |
  |---|---|---|---|
  | s COCO17 | 100 / 100 / 98.8 → 같음 | 0 → 0 | 같음 |
  | s Halpe26 | 100 / 100 / 98.8 → 같음 | 0 → 0 | 같음 |
  | m Halpe26 | 100 / **81.1** / 100 → 100 / **100** / 100 | 3(setup_side_view 2, tracking_lost 1) → 0 | 같음 |
  - 사람이 바뀐 영상: m Halpe26 푸시업 cam2 3개(0001, 0003, 0004 — 모두 렙이 정답 10으로), barbellrow_0003 cam2(s·m Halpe26, 렙 10 그대로). s COCO17은 0개.
  - squat_03 2/2, 더미 6개 0렙(스쿼트·로우, 세 모델), 흔들림 합성 m Halpe26 44건 0렙(s 두 모델은 소스 키포인트가 바뀌지 않아 이전 88건 0렙 그대로).
- **조건 2·4를 넣은 이유와 과적합 주의**: 1·3만 쓰면 squat_0002 cam2(s Halpe26)에서 잘못 옮겨 10렙→2–3렙.
  늘린 전체 프레임은 두 사람을 한 상자로 섞거나(관절 6–12개, 평균 신뢰도 0.33–0.38) 다리만 보인 사용자 상자가 작아 보였다.
  맞게 옮긴 경우는 관절 15–17개, 평균 0.46–0.71이고, 경계값 0.42는 이 사이에서 골랐다.
  **이 값은 검증 피험자 영상(squat_0002 = P2, barbellrow_0003 = P2)까지 보고 정했으므로 검증 수치가 아니다.** 실제 촬영 영상으로 다시 확인해야 한다.
- **버린 대안**: 사람이 오래 안 움직일 때만 재확인(서 있는 구경꾼과 쉬는 사용자를 구분 못 함), 가운데 사람 우선(측면 촬영은 사용자가 가장자리에 있을 수 있음, 추정), RTMDet 등 검출기(가장 단순한 규칙으로 기준 통과).
- **되돌리기**: `RTMPoseCropTracker.recheckInterval`을 `Int.max`로.

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

## 트랙 G — 벤치프레스·데드리프트 — 2026-10-11
근거 파일: `outputs/rep_validation/K_bench_deadlift.md`(로컬). 입력은 Exercise3D 벤치 5·데드 4세트의 **Sapiens2 2D 키포인트(대리 입력, 앱 RTMPose 아님)** — 원본 RGB가 Drive에 없음. 정답은 삼각측량 3D(`not_ground_truth`). 사람 단위 분리는 뼈 길이 비율로 묶은 추정(조정 = 벤치 0000–0002·데드 0000/0002/0003, 검증 = 벤치 0003·0004·데드 0001). Fit3D 데드(s03·s05 모캡 → 가상 측면 투영)는 집계만.

### D-G-01 벤치: 락아웃을 본 뒤에만 렙 시작, 적응 임계값은 팔꿈치 범위 50° 이상부터
- 결정: `BenchPressEvaluatorConfig.repStartRequiresTop = true`, `minRequiredElbowRange` 20 → 50.
- 근거(측면 ≤40°, 조정 / 검증): 렙 정확도 88.9% / 90.9% → **100% / 100%**, 추가 렙 5 / 2 → 0 / 0, 놓침 0. 원인 = 랙 바를 잡은 굽힌 팔(첫 프레임 `bottom`)과 언랙 누르기, 랙에서 꼼지락(91–126°)만으로 켜지는 적응 임계값(top 117°). 단독: top 요구만 97.6% / 100%, 범위만 90.9% / 90.9%. 벤치 정지 합성 44건 가짜 렙 73 → 0.
- 기각: 락아웃 유지 시간 요구(빠른 터치앤고 놓칠 위험, 데이터 없음). 손목 깊이(가슴까지) 요구 — 첫 렙 전엔 기준이 없음.
- 되돌리기: 두 설정값.

### D-G-02 벤치: 한쪽 팔만 보이면 그 팔로 측정
- 결정: `allowOneArm = true`(예전: 양팔 6관절 모두 ≥ 0.30).
- 근거: 누운 자세 측면 RTMPose의 대용으로 Exercise3D 측면 푸시업에서 양팔 조건이 카메라별 1–76% 프레임에서 깨짐(COCO17). 먼 팔을 40% 프레임 가린 합성(논리 확인용)에서 52.5% / 55.0% → 95.2% / 95.2%. 정상 입력 결과 동일. 로컬 benchpress_01(발 쪽, 왼어깨 신뢰도 0.11) 0 → 1(COCO17) / 2(Halpe26), 정답 3. **추정**: 실제 측면 벤치 RTMPose 영상으로는 미검증.
- 되돌리기: `allowOneArm = false`.

### D-G-03 데드리프트: 락아웃 진행도 0.10, 바 내림 = 손목이 무릎 아래, 바닥→top 직행도 렙 시작
- 결정: `topProgressThreshold` 0.28 → 0.10, `wristLowerShinRatio` 0.50 → 0.0, `directBottomToTopStartsRep = true`.
- 근거: 전에는 Exercise3D 전 세트·Fit3D 전 영상 0렙. 측면 ≤40° 조정 / 검증 0% / 0% → **100% / 100%**(58·22렙, 추가 0). Fit3D 가상 측면 0/20/40° 30렙: 0% → **100%**(직행 시작 없이는 76.7%). 실제 범위: 락아웃 엉덩이 높이 상승 0.14–0.25 다리 길이, 바닥에서 손목은 무릎–발목 사이 0.10–0.36 지점. 두 값 중 하나만 바꾸면 여전히 0%. 정지 흔들림 112건 0 → 0.
- 주의: 렙은 여전히 바를 내린 뒤 셈(마지막 렙은 바를 내려놓을 때). 정면 카메라는 지원 안 함(검증 정면 9.1%).
- 기각: 엉덩이 각 중심으로 상태 머신 재작성 — 원인이 두 임계값으로 분명해 최소 수정.
- 되돌리기: 세 설정값.

### D-G-04 벤치·데드 경고 키 6개 추가, 전부 꺼짐 / 평가기가 자기 트래커를 가짐
- 결정: `bench_hips_up`(우선) `bench_shallow`(개선) `bench_no_lockout`(참고) `deadlift_hips_first`(우선) `deadlift_no_lockout`(참고) `deadlift_lean_back`(참고). 판정·로그만, `enabledFeedbackKeys` 기본에 없음. 평가기가 `formTracker`를 직접 가져 렙 구간을 정확히 잡고(벤치는 락아웃 0.5초 뒤 판정, `lockoutWindowFrames` 15), 트랙 E의 `StatusDrivenFormTracker`(E2)는 삭제. 셋업 필수 관절은 E2 그대로(벤치 어깨·팔꿈치·손목, 데드 어깨·엉덩이·무릎·발목).
- 근거: 틀린 자세 영상 없음 → 켤 수 없음(BRIEF §4). 정상 렙 발동(대리 입력): hips_up 0/60, shallow 0/60, bench_no_lockout 9/60, hips_first 0/80, deadlift_no_lockout 3/80, lean_back 3/80. 2D로 못 보는 허리 굽음·바 경로·아치·견갑은 만들지 않음.
- 대사: `kori_feedback_lines.dart`는 팀원 파일이라 손대지 않고 초안을 진행 기록에 둠. 테스트(`WorkoutSessionBridgeTests.keysAwaitingDartLines`)가 이 6개를 "대사 대기 + 꺼짐"으로 확인.
- 되돌리기: 키를 `enabledFeedbackKeys`에 넣지 않으면 동작 변화 없음. 트래커 연결 되돌리기는 `437644f`.

## D-H-02 음성 생성 스크립트 삭제 (2026-10-11)
- 결정: `scripts/generate_kori_voice.py`와 테스트를 지운다. mp3는 팀원이 ElevenLabs에서 직접 뽑아 넣는다(사용자 지시).
- 남긴 것: 파일 이름 규칙(`docs/handoff/kori_voice.md`). WorkoutVoice의 mp3 우선 재생 → 없으면 기기 TTS 동작은 그대로.
- 되돌리기: 커밋 `af70acc`의 스크립트·테스트 복원.

## D-C-05 iPhone 17 2D 모델 속도: 모든 후보가 예산 안, m COCO17은 속도 조건 만족 → 전환은 사용자 결정 (2026-10-11)
- **측정**: `tools/pose_model_bench`(XCTest, 사람 없이), iPhone 17(iPhone18,3), 충전기 뺀 상태. 입력 = 실제 720×1280 프레임(앱 카메라와 같은 크기) 하나를 256×192로 줄인 것. 추론만 잼(crop 그리기·디코딩·평가기 제외). 워밍업 20회 뒤 300회, ms.
  | 모델 | ALL p50 / p95 | CPU+NE p50 / p95 | CPU+GPU p50 / p95 | 로드 (ALL) | 150초 연속 FPS 처음 → 끝 (최저) | 발열 시작 → 끝 |
  |---|---|---|---|---|---|---|
  | s COCO17 (기본) | 1.97 / 2.11 | 1.96 / 2.07 | 1.48 / 1.63 | 541 ms | 593 → 547 (523), −8% | 1 → 1 |
  | s Halpe26 | 2.02 / 2.18 | 1.98 / 2.15 | 1.57 / 1.65 | 495 ms | 592 → 549 (547), −7% | 1 → 2 |
  | m COCO17 | 3.31 / 4.05 | 3.29 / 3.50 | 2.42 / 2.53 | 1016 ms | 326 → 282 (218), −14% | 2 → 2 |
  | m Halpe26 | 3.29 / 3.53 | 3.24 / 3.47 | 2.43 / 2.50 | 700 ms | 미측정(대기 중 기기 자동 잠김, 사용자 추가 요청 안 함) | — |
  | Apple Vision `VNDetectHumanBodyPoseRequest` | 12.17 / 16.76 (평균 11.2, 최대 18.5) | | | | — | — |
  - 연속 실행 = 쉬지 않고 추론하며 10초마다 FPS·`thermalState`(0 정상, 1 약간 따뜻, 2 뜨거움, 3 위험) 기록. 실행 순서 s → s Halpe26 → m, 사이 60초 휴식이라 열이 쌓임: m은 2에서 시작(m에 불리). m 최대 1회 지연 39 ms(70초 근처 1번, 그 10초 p95 8.3 ms).
  - Mac M4 참고값(D-C-03, s 5.4 / m 24.7 ms)보다 iPhone이 훨씬 빠름: 기기 Neural Engine이 이 모델에 잘 맞음.
  - 예전 Vision 경로 질문 답: 같은 프레임에서 Vision 몸 자세는 1회 약 12 ms(p95 17 ms)로 RTMPose-s의 약 6배. MediaPipe는 앱에 통합된 적 없음(변환 스크립트만) → 측정 안 함.
- **판단**:
  1. 30 FPS 예산 33 ms 중 m COCO17 추론은 p95 4.05 ms(약 12%), s보다 +1.3 ms. 뜨거운 상태(2)에서도 쉬지 않고 218 FPS 이상 → D-C-03의 전환 조건 "실시간 유지"는 속도 면에서 만족.
  2. COCO17과 Halpe26은 속도 차이 없음(±0.1 ms) → D-C-04 결정에 속도는 변수가 아님.
  3. 기본 모델은 바꾸지 않음. m COCO17을 **전환 후보로 추천**하고 결정은 사용자에게: 장점 COCO body12 +2.1%p·측면 로우 렙 98.8→100%, 단점 비측면 푸시업 1렙 놓침·앱 +26 MB·발열 조금 더(추정).
  4. compute units는 `.all` 유지. CPU+GPU가 짧은 측정에서 25% 빠르지만 앱에서는 GPU를 카메라 미리보기·화면 그리기와 나눠 쓰고, 그 조건은 안 쟀음(추정). 차이도 1 ms 미만.
- **기각**: 지금 기본을 m으로 전환(정확도 장단점이 섞여 사용자 결정 사항, BRIEF), CPU+GPU로 변경(앱 조건 미측정, 이득 1 ms 미만), Vision 복귀(6배 느리고 2D 정확도 비교 근거 없음).
- **한계**: 추론 단독 수치. 앱 전체(crop·평가기·3D·녹화) FPS는 사람이 카메라 앞에 있어야 해서 따로 측정 필요. 프레임 1장(모델 지연은 입력 내용과 거의 무관, Vision은 사람 수에 따라 다를 수 있음).
- **되돌리기/다시 재기**: 앱 코드 변경 없음(문서·측정 도구만). 재측정은 `tools/pose_model_bench/project.yml` 머리말 명령, 연속 실행 사이 휴식은 `TEST_RUNNER_BENCH_COOLDOWN`(앱이 앞에 있어 기기가 안 잠김). m 전환 방법은 D-C-03.

## 트랙 F 후속 — 캘리브레이션 촬영 거리·서버 예열 — 2026-10-11
현장 피드백: "혼자 찍으면 너무 멀리 서야 하고 전신이 안 들어간다". 거리 계산은 핀홀 모델(세로 화면에서 긴 변 화각 = 세로 화각, 엔진의 머리끝 추정 1.035H·발 기준 0.02H, `assets/calibration/silhouettes.json`), 스크립트는 로컬 scratchpad(추정 계산, 실측 아님).

### F9. 화각 실측 (iPhone 17, iPhone18,3)
- 방법: 포맷만 나열하는 임시 앱(카메라 권한 불필요)을 기기에 설치해 `AVCaptureDevice.formats`의 `videoFieldOfView`(긴 변 기준)를 읽음. 무료 팀 3앱 제한 때문에 트랙 C의 PoseModelBenchHost를 잠시 지우고 같은 빌드로 다시 설치함.
- 결과: 전면 광각(`builtInWideAngleCamera`)은 모든 포맷이 **73.19°**(4K 프리셋도 같음, 왜곡 보정 시 72.59°). 전면 초광각(`builtInUltraWideCamera`, iPhone 17에서 새로 생김, 같은 정사각 센서 전체)은 **84.08°**(60fps 포맷 83.86°), 4032×4032·3840×2160 등. 후면 광각 70.65°, 후면 초광각 **106.20°**.
- 이전 추정(세로 화각 ~65°)보다 실제가 넓다.

### F10. 전면 초광각 우선 사용, manifest에 카메라 기록
- 결정: `CalibrationCaptureManager`가 전면 `builtInUltraWideCamera`를 먼저 찾고 없으면 기존 광각. 프리셋 선택(4K → 1080p → high)은 그대로. 왜곡 보정을 명시적으로 켬. manifest에 선택 필드 `camera`({deviceType, fieldOfViewDeg, formatWidth, formatHeight}) 추가 — 서버 `checks.manifest`는 모르는 필드를 무시하므로 하위 호환.
- 근거: 같은 몸 크기에서 거리 tan(36.6°)/tan(42.04°) = **0.82배**. intrinsics는 프레임별 첨부값을 그대로 쓰고, 없으면 기존처럼 화각에서 추정(`fov_estimate`) — 둘 다 선택된 포맷 기준이라 정합.
- 확인 못 한 것(추정): 전면 초광각에서 intrinsics 첨부가 실제로 오는지(카메라 권한이 필요해 임시 앱으로 못 봄), 84° 렌즈의 잔여 왜곡이 서버 fit에 미치는 영향. → 실기기 촬영 1회로 manifest의 `intrinsics.source`·`camera` 확인 필요.
- 기각: 포맷을 직접 고르는 코드(`activeFormat` 설정) — 초광각의 모든 포맷이 84°라 프리셋으로 충분. 후면 초광각(106°)은 코드로 바꾸지 않음(F12).
- 되돌리기: `AVCaptureDevice.default(.builtInUltraWideCamera…) ??` 한 줄 삭제.

### F11. 몸 높이 0.40–0.85, 폰 앞뒤 기울기 25°
- 결정: `Framing.minBodyHeight` 0.55 → **0.40**, `maxBodyHeight` 0.69 → **0.85**(가이드 윤곽 크기 0.62는 유지, 허용 범위만 넓힘; Dart 기본값 동기화). `Device.maxPitchDeg` 12 → **25**. 좌우 3°, 머리 ≥ 0.02·발 ≤ 0.98, 중심 ±0.06은 그대로.
- 왜 원래 값이었나: 0.55–0.69는 `c6e8c08`에서 "통과했는데 윤곽과 몸이 안 맞는" 화면 문제를 고치려고 윤곽(0.62) ± 0.07로 좁힌 값(처음엔 0.60–0.82, 그 뒤 0.50–0.82). 서버 요구가 아니다. 12°·3°는 `c98285e`의 "실기기 튜닝 시작값"으로 근거 기록 없음. 서버 fit은 사진마다 자기 intrinsics로 투영하고 사진별 몸 방향(global_orient)을 따로 맞추므로 카메라 기울기는 몸 방향에 흡수됨. 뼈 길이는 β(휴식 자세)에서만 나옴. 사진별 중력은 이미 `views[].gravity`에 저장됨 → 계약 변경 불필요. 몸이 작아도 4K 원본에서 사람 상자를 잘라 SAM 3D Body에 넣으므로 해상도 문제는 앱 RTMPose 쪽이 먼저 걸림.
- 근거(하한, 로컬 RTMPose = 앱의 CalibrationFrameAnalyzer + crop, calibration-replay): People Snapshot 세로 영상 6개(로컬만, 업로드 없음)를 0.48–1.9배로 크기 바꿔 54개 리플레이. 12개 몸 관절이 모두 ≥ 0.3인 프레임 비율(영상 평균 / 최저): 몸 높이 0.87 → 96.7% / 94.1%, 0.73 → 98.1%, 0.60 → 98.1%, 0.46 → 93.6% / 70.5%, **0.39 → 83.6%**(광장 배경 1개 제외 시 97–99%), 0.37 → 81.2%, 0.32 → 72.7%, **≤ 0.28 → 6–12%**(사람을 잃음). 새 기준으로 저장된 사진 20장은 모두 12/12 관절 ≥ 0.3(평균 신뢰도 0.80–0.94, 몸 높이 0.40 포함) — 서버 기준 8/12보다 여유.
- 근거(촬영 성공): 같은 54개 리플레이에서 저장된 뷰 수 이전 7 → **20**, 하나라도 찍힌 영상 5/54 → 15/54(이 영상들은 BPT 안내대로 돌지 않아 4뷰 완주가 목적 아님). 기존 더미 3개(엄격·느슨)는 이전과 같은 뷰(3·4·0)를 찍음 — 회귀 없음.
- 거리(사용자 키 1.70 m, 폰 세로·몸 중간 높이 / 바닥 h=0.10 m 기대기 / 탁자 h=0.75 m): 이전 **1.70–2.10 / 1.55–1.95 / 1.70–2.25 m** → 적용 후 **1.15–2.35 / 0.75–2.70 / 1.15–2.85 m**(1.55·1.85 m 표는 docs/progress/2026-10-11.md). 바닥에 둘 때 필요한 기울기 1.2 m 거리에서 14–25°, 1.5 m에서 8–25° → 12°로는 바닥 배치가 거의 불가했다.
- 추정·위험: 25° 위로 찍은 사진과 0.85(가까이·원근 강함)에서의 서버 fit 정확도는 GPU로 검증 안 함(People Snapshot 업로드 금지·비용). 실기기 촬영 1회로 확인 필요. 상한 0.85는 머리·발 여유(0.96)보다 작게 둠.
- 기각: 하한 0.30(관절 유지 72.7%, 광장 0%), 기울기 무제한(중력이 뒤집히면 세로 판정 자체가 깨짐), 기울기 보정해서 서버로 보내는 새 필드(이미 gravity 있음).
- 되돌리기: `CalibrationConfig` 세 값과 `calibration_silhouette.dart` 기본값 두 개.

### F12. 후면 초광각 0.5x는 사용자 결정 (코드 변경 없음)
- 거리(1.70 m, 세로 / 바닥 / 탁자): **0.80–1.60 / 0.40–2.00 / 0.75–2.15 m**, 화질도 후면이 좋음.
- 문제: 사용자가 화면을 못 봄 → 윤곽·글자 안내가 무의미, 음성·비프만으로 정면·사선·뒤 4장을 맞춰야 함. 106° 렌즈 왜곡이 커서 intrinsics 첨부·왜곡 보정 확인 필요. 화면 미러링·카운트다운 등 UX 재설계가 필요해 이번 범위 밖.

### F13. 서버 예열: 촬영 화면을 열면 GPU 컨테이너를 미리 띄움 (배포함)
- 결정: `POST /v1/calibrations/warmup`(로그인 토큰 필요) → 같은 사용자가 5분 안에 이미 깨웠으면 `skipped`, 아니면 `fit_body.spawn({"warmup": True})`(모델만 올리고 끝). `fit_body`의 `scaledown_window` 60 → **180초**(깨운 컨테이너가 업로드 올 때까지 남게). `min_containers=0` 유지. 앱은 촬영 화면 `initState`에서 한 번 호출, 실패·404(옛 서버)·토큰 없음은 무시. 2026-10-11 16:28 배포(v10).
- 근거(배포 서버, 합성 묶음, 테스트 사용자): 이전 cold 작업 접수→완료 **258.3초**(시작까지 231.4초), warm 29.9초. 적용 후 예열 → 2분 뒤 업로드: **33.2초**. cold 시작 시간은 이번에 231초로 지난번 기록(65초)보다 길었다(이미지 캐시 상태에 따라 변함, 추정).
- 비용(추정, L4 $0.000542/초 보수값 F 기록 기준; 실제 L4 단가는 이보다 낮을 수 있음): 예열만 하고 업로드 안 하면 cold 시작 + 180초 대기 ≈ 65–230 + 180초 ≈ **$0.13–0.22**, 업로드하는 정상 경우는 작업 뒤 대기가 60 → 180초로 늘어 작업당 **+$0.065**. 사용자당 5분 1회 제한.
- 한계: 업로드가 예열 완료 전에 오면 Modal이 두 번째 컨테이너를 띄울 수 있음(입력 1개/컨테이너) — 지연은 예열보다 나빠지지 않지만 그만큼 비용. 동시 첫 호출 둘은 둘 다 예열될 수 있음(무해).
- 기각: `update_autoscaler(min_containers=1)` 후 되돌리기(되돌림 실패 시 상시 비용), 예열 입력이 컨테이너를 잡고 기다리기(실제 작업이 다른 컨테이너로 감).
- 정리: e2e 테스트 사용자(999997)가 R2에 남긴 객체 34개 삭제, 테스트 토큰 파일 삭제.
- 되돌리기: 앱의 `warmUp()` 호출 한 줄 삭제(서버는 그대로 둬도 무해), 서버는 `scaledown_window`·엔드포인트 제거 후 재배포.

## 트랙 D — 3D (MotionAGFormer-XS: 사선 각도, 실시간 비용, Fit3D 미세조정) — 2026-10-11

용어: **각도 오차** = 앱이 계산한 관절 각도와 정답 각도 차이의 절댓값(°). **프레임 오차** = 렙 구간 모든 프레임, **렙 극값 오차** = 렙마다 무릎·팔꿈치 최솟값/몸통 최댓값의 차이(경고가 실제로 쓰는 값). **p90** = 90%가 이 값 이하. **MPJPE** = 관절 3D 위치 오차 평균(mm). **3D 불량** = 무릎 경첩 각 θ < −10°(과신전)로 걸린 프레임(D-12).
측정: `scripts/eval_3d_angles.py` + `summarize_3d_angles.py`. 2D = pose-replay(현재 integration, 사람 3:4 crop 입력) CSV 그대로, 3D = 같은 키포인트를 앱과 같은 person_crop·27프레임·lookahead 5로 MotionAGFormer-XS(PyTorch)에 넣은 값. 가까운 쪽 = 앱 규칙(귀~발목 신뢰도 평균이 높은 쪽). Fit3D는 앱처럼 30 fps로 뽑음.
정답: **Fit3D** s03·s05 모션캡처(진짜 정답, 카메라 58–74°만), **Exercise3D** 삼각측량 라벨(Sapiens 기반, 정답 아님, 카메라 10–88°). Exercise3D 튜닝/검증 분할은 D-B-01과 같음(P1 튜닝, P2·P3 검증, 푸시업은 검증 없음). 이 비교에는 조정한 값이 없어 두 묶음 모두 같은 방식의 측정값이다.

## D-D-01 사선(30–60°)에서도 측면 요구는 유지한다 — 3D로 각도를 계산해도 측면 수준이 안 됨 (2026-10-11)
- **결정**: `setup_side_view`·측면 컷오프(D-B-02, PushUpFormConfig 1.0)를 3D 때문에 완화하지 않는다.
- **근거** (프레임 오차 중앙값 2D → 3D, °):

  | 데이터 | 운동·각도 | 시점 | 2D | 3D | 렙 극값 2D → 3D |
  |---|---|---|---|---|---|
  | Ex3D 튜닝 | 스쿼트 무릎 | 20–40° | 18.0 | 19.3 | 37.4 → 19.0 |
  | Ex3D 튜닝 | 스쿼트 무릎 | 40–60° | 6.4 | 16.0 | 34.0 → 16.7 |
  | Ex3D 검증 | 스쿼트 무릎 | 20–40° | 13.4 | 17.7 | 38.5 → 18.2 |
  | Ex3D 튜닝 | 스쿼트 몸통 | 20–40° | 3.8 | 6.5 | 2.9 → 9.4 |
  | Ex3D 검증 | 스쿼트 몸통 | 20–40° | 1.3 | 8.7 | 1.5 → 11.1 |
  | Ex3D 튜닝 | 스쿼트 몸통 | 40–60° | 7.6 | 4.8 | 8.8 → 10.0 |
  | Ex3D 튜닝/검증 | 로우 몸통 | 20–40° | 5.1 / 6.6 | 3.4 / 2.8 | 4.9 → 2.9 / 5.7 → 1.6 |
  | Ex3D 튜닝 | 푸시업 몸통 | 40–60° | 9.6 | 5.9 | 17.0 → 9.1 |
  | Fit3D s03 / s05 | 스쿼트 무릎 | 60–75° | 16.8 / 6.0 | 13.1 / 11.0 | 21.0 → 10.5 / 36.4 → 6.8 |
  | Fit3D s03 / s05 | 스쿼트 몸통 | 60–75° | 11.3 / 10.1 | 4.5 / 5.6 | 18.6 → 10.8 / 22.5 → 12.2 |
  | Fit3D s03 / s05 | 로우 몸통 | 60–75° | 16.3 / 29.7 | 13.9 / 17.4 | 20.3 → 14.2 / 30.0 → 17.5 |
  | Fit3D s03 / s05 | 로우 팔꿈치 | 60–75° | 31.0 / 42.0 | 6.9 / 11.1 | 60.8 → 24.5 / 79.4 → 8.0 |

  - 3D는 사선에서 2D보다 덜 틀리는 경우가 많다(렙 극값 무릎, 로우 몸통·팔꿈치, 정면 75–90° 로우 팔꿈치 26 → 5°). 하지만 남는 오차가 렙 극값 기준 7–19°(p90 15–40°)로, 측면 2D에서 보던 수준(±15°에서 <2°, squat_shallow 기준값 15°·row_torso_swing p99 39.9°에 비해 큼)과 거리가 멀다.
  - 측면(≤40°) 스쿼트 몸통은 3D가 오히려 나쁘다(Ex3D 튜닝 2.9 → 9.4°, 검증 1.5 → 11.1°): 3D의 "위"는 카메라 y축이라 카메라 기울기·깊이 추정 오차가 그대로 들어간다.
  - Exercise3D 측면 스쿼트 무릎 렙 극값 2D 오차가 30°대로 큰 것은 라벨(Sapiens 엉덩이 정의, 삼각측량) 쪽 편향도 섞인 값으로 본다(추정). 진짜 정답인 Fit3D는 측면 카메라가 없어 측면 2D 오차는 잴 수 없다.
- **기각**: 사선 3D 각도로 경고 판정 — 위 오차로는 정상/틀린 자세를 가를 수 없고, 틀린 자세 영상도 없어 검증 불가(브리프 4절).
- **되돌리기**: 해당 없음(앱 변경 없음).

## D-D-02 라이브 카메라 3D는 계속 끈다, 3D 지표는 경고에 쓰지 않는다 (2026-10-11)
- **결정**: `CameraPreviewOptions.enableMotion3DForCamera = false` 유지. 3D 지표는 pose-replay 로그용으로만 남긴다(FormWarnings "Warnings fire from 2D only").
- **근거**: D-D-01(측면에서는 2D가 같거나 더 정확, 사선에서는 3D도 부족). 지금 카메라 경로에는 3D 실행 코드가 없고(플래그만 있음) MotionAGFormer 모델도 앱 번들에 없다 → 켜려면 모델 번들 추가·5프레임(30 fps에서 167 ms) 지연된 3D를 평가기에 맞추는 작업이 필요한데, 얻는 정확도가 없다. 비용은 아래 D-D-04.
- **되돌리기**: 3D 실행 코드를 넣은 뒤 같은 플래그.

## D-D-03 무릎 경첩 "3D 불량" 감지는 품질 신호로 믿지 않는다 (감지 유지, 보정 끔 유지) (2026-10-11)
- **근거**: 3D 무릎 오차 > 20°인 프레임 중 감지가 잡은 비율과, 잡은 프레임 중 실제 오차 > 20° 비율.

  | 데이터 | 운동 | 3D 불량 비율 | 큰 오차 중 잡은 비율 | 잡은 것 중 실제 큰 오차 |
  |---|---|---|---|---|
  | Fit3D s03 / s05 | 스쿼트 | 0% / 0% | 0% (484) / 0% (297) | - |
  | Fit3D s03 / s05 | 푸시업 | 15.2% / 20.4% | 19% / 25% | 90% / 82% |
  | Fit3D s03 / s05 | 다이아몬드 푸시업 | 1.5% / 28.7% | 1% / 27% | 53% / 86% |
  | Fit3D s03 / s05 | 로우·데드 로우 | 0% | 0% | - |
  | Ex3D 튜닝 | 푸시업 | 35.3% | 0% (2535) | 0% |
  | Ex3D 튜닝·검증 | 스쿼트·로우 | 0% | 0% | - |

  정답(Fit3D 모션캡처)에서 과신전(θ < −10°) 프레임은 0. 푸시업처럼 다리가 펴진 동작에서만 걸리고, 스쿼트·로우의 큰 3D 오차는 하나도 못 잡는다(재현율 0%). Exercise3D 푸시업에서는 걸린 프레임이 오히려 오차가 작았다.
- **결정**: D-12 그대로(감지 ON·보정 OFF). 3D 지표가 경고에 쓰이지 않으므로(D-D-02) 영향 없음. 3D를 경고에 쓰게 되면 이 감지 대신 다른 품질 신호가 먼저 필요하다.

## D-D-04 사선 렙 카운트에 3D 신호를 쓰지 않는다 (2026-10-11)
- **방법**: 같은 단순 카운터(9프레임 평균, 영상의 p5–p95로 정규화, 0.35/0.65 슈미트 트리거, 내려갔다 올라오면 1렙)를 2D 각도와 3D 각도에 각각 돌림(`scripts/count_reps_3d_vs_2d.py`; 스쿼트 = 가까운 무릎, 푸시업·로우 = 가까운 팔꿈치). 앱 상태기계 수(pose-replay crop 입력)도 같이 적음. 진실 = Fit3D rep_ann(세트당 5렙).
- **근거** (Fit3D 튜닝 피험자 s03·s05, 카메라 4대 × 운동, 60–75°; 센 렙 합 / 진실 렙 합, 정확히 맞은 세트):

  | 운동 | 2D 신호 | 3D 신호 | 앱(2D 상태기계) |
  |---|---|---|---|
  | 스쿼트 | 40/40, 8/8 | 56/40, 4/8 | 41/40, 7/8 |
  | 푸시업 | 41/40, 7/8 | 38/40, 5/8 | 39/40, 1/8 |
  | 바벨로우 | 42/40, 5/8 | 40/40, 6/8 | 3/40, 0/8 (측면 게이트가 사선에서 막음, 의도된 동작) |

  - 스쿼트는 3D 신호가 가짜 렙을 더 만든다(무릎 3D 각이 렙 사이에 흔들림). 로우만 3D가 한 세트 더 맞음(6/8 vs 5/8) — 차이가 작고 피험자 2명뿐이라 근거 부족.
  - Exercise3D(13세트 × 3캠, 진실 = gt.json): 2D 신호와 3D 신호 모두 측면·사선·정면 대부분 정확. 차이는 스쿼트 측면 튜닝 2D 50/50(5/5) vs 3D 59/50(4/5), 로우 측면 검증 2D 30/40 vs 3D 41/40(정확 세트는 둘 다 3/4), 앱은 스쿼트 50/50·로우 측면 43/44·40/40, 로우 정면(>60°)은 측면 게이트로 0.
- **결정**: 렙 카운트는 2D 그대로. 사선 카운트 개선은 3D가 아니라 2D 상태기계 쪽(트랙 three-ex) 문제로 넘김.

## D-D-05 라이브 3D 비용(iPhone 17, iOS 27.0): 30 fps 안에는 들어가지만 프레임당 +17 ms, CPU +13%p (2026-10-11)
- **측정**: `tools/ios_live3d_cost`(사람·카메라 없이 무작위 입력, 지연은 입력 내용과 무관). RTMPose-s만 vs RTMPose-s + MotionAGFormer-XS를 매 프레임, 30 fps 간격으로 각 180초, computeUnits = all(앱과 같음). 카메라 캡처·전처리·평가기는 포함 안 함(두 경우 같음).

  | 모드 | 프레임당 합계 평균 / p99 / 최대 (ms) | MotionAGFormer 평균 (ms) | 달성 fps | 프로세스 CPU | 발열 상태(시작 → 끝) |
  |---|---|---|---|---|---|
  | 30 fps, 2D만 | 9.4 / 10.4 / 14.9 | — | 30.0 | 23% | fair → nominal |
  | 30 fps, 2D + 3D | 26.2 / 28.2 / 41.4 | 17.1 | 30.0 (늦은 프레임 1/5400) | 36% | nominal → nominal |
  | 최대 속도, 2D만 | 1.7 / 2.3 / 3.0 | — | 588 | 67% | nominal |
  | 최대 속도, 2D + 3D | 6.7 / 7.5 / 23.7 | 5.0 | 150 | 30% | nominal → fair |

  - 30 fps 간격으로 돌리면 가속기가 쉬었다 깨어나 모델당 지연이 최대 속도 때보다 3–5배 길다(RTMPose 1.7 → 9.4 ms, MotionAGFormer 5.0 → 17.1 ms).
  - 3분씩에서는 발열 단계가 올라가지 않음. 30분 이상 운동 세션의 발열·배터리는 재지 않음(사람 앞 장시간 측정 필요).
  - 33 ms 예산 중 26 ms를 모델이 쓰므로 카메라·전처리·그리기를 더하면 프레임이 밀릴 여지가 크다(최대 41 ms).
- **결정**: D-D-02 유지(정확도 이득이 없는데 프레임당 +17 ms·CPU +13%p).

## D-D-06 Fit3D 미세조정 XS: 사선 무릎은 크게 좋아짐, 몸통(카메라 기준)은 나빠짐 → 앱에는 아직 안 넣음, 다음 단계 1순위 (2026-10-11)
- **방법**: `scripts/finetune_motionagformer_fit3d.py`. 입력 = 앱 2D(pose-replay crop, 30 fps), 정답 = Fit3D 모션캡처(카메라 좌표, 루트 기준, crop 단위). 원래 XS(H36M) 가중치에서 10에폭, AdamW 1e-4 코사인, 배치 16, 좌우 뒤집기. 운동 5종(스쿼트·푸시업·다이아몬드 푸시업·바벨로우·데드 로우) × 카메라 4대. **Home GPU(GTX 1060)에서 학습**(Mac 과부하로 코디네이터 지시, 사용자 본인 PC라 Fit3D 라이선스 범위 안). 피험자 2명뿐이라 2겹 교차: s05로 학습 → s03 평가, s03로 학습 → s05 평가.
- **MPJPE(mm, 학습에 안 쓴 피험자, 앱처럼 매 프레임 lookahead 5)**:

  | 겹 | 원래 XS | 미세조정 | 스쿼트 | 푸시업 | 바벨로우 |
  |---|---|---|---|---|---|
  | s05 학습 → s03 | 160.4 | **50.3** | 110 → 41 | 239 → 60 | 108 → 46 |
  | s03 학습 → s05 | 162.8 | **67.0** | 109 → 39 | 244 → 112 | 125 → 50 |

  원래 XS의 큰 값에는 crop 단위 ↔ mm 크기 차이도 섞여 있다(원래 모델은 H36M 화면 정규화로 학습).
- **각도(렙 극값 오차 중앙값, °; 2D → 원래 3D → 미세조정 3D)**, 독립 세트 Exercise3D 포함:

  | 데이터 | 운동·각도 | 시점 | 2D | 원래 3D | 미세조정 |
  |---|---|---|---|---|---|
  | Fit3D s03(학습 안 함) | 스쿼트 무릎 | 60–75° | 21.0 | 10.5 | **5.8** |
  | Fit3D s03 | 로우 몸통 / 팔꿈치 | 60–75° | 20.3 / 60.8 | 14.2 / 24.5 | **9.8 / 10.7** |
  | Ex3D 튜닝 | 스쿼트 무릎 | 20–40° / 40–60° / 60–75° | 37.4 / 34.0 / 16.0 | 19.0 / 16.7 / 6.6 | **6.4 / 1.3 / 1.2** |
  | Ex3D 검증 | 스쿼트 무릎 | 20–40° | 38.5 | 18.2 | **6.2** |
  | Ex3D 튜닝 / 검증 | 로우 팔꿈치 | 20–40° | 5.0 / 4.5 | 5.8 / 4.8 | **1.8 / 1.6** |
  | Ex3D 튜닝 | 스쿼트 몸통 | 20–40° | 2.9 | 9.4 | 27.2 (나빠짐) |
  | Ex3D 튜닝 / 검증 | 로우 몸통 | 20–40° | 4.9 / 5.7 | 2.9 / 1.6 | 20.0 / 18.9 (나빠짐) |
  | Ex3D 튜닝 | 푸시업 팔꿈치 | 0–20° | 1.2 | 5.7 | 17.4 (나빠짐) |

  - 무릎·팔꿈치 같은 **관절 사이 각도**는 사선에서도 미세조정 3D가 2D·원래 3D보다 훨씬 정확(Ex3D는 정답이 아닌 라벨이라 절댓값은 참고, 같은 라벨로 세 방법을 비교한 상대 비교).
  - **몸통 각도**(카메라 y축 기준)는 나빠짐: Fit3D 카메라가 모두 위에서 내려다봐 모델이 그 카메라 기울기를 출력에 배움(추정). 몸통·엉덩이 지표에는 카메라 대신 중력 방향(기기 가속도계)이 필요.
  - 측면 푸시업 팔꿈치도 나빠짐: Fit3D에 측면 카메라가 없음.
  - 3D 불량(무릎 과신전) 프레임: Ex3D 푸시업 35.3% → 0.9%.
- **결정**: 이번에는 앱에 넣지 않는다(라이브 3D 끔 유지). 이유: (1) 틀린 자세 영상으로 경고 검출률을 확인할 수 없음(브리프 4절), (2) 몸통이 나빠져 지금 경고(몸통·엉덩이 기반)에 바로 못 씀, (3) 학습 피험자 1–2명, (4) 프레임당 +17 ms(D-D-05), (5) Fit3D 유래 가중치는 비상업(캡스톤) 용도만.
- **다음 단계(1순위)**: Home에서 Fit3D 튜닝 피험자 s03·s04·s05 전부로 학습 → 나머지 피험자(검증)로 평가, 몸통은 중력 기준으로 다시 계산, Core ML 변환 후 pose-replay로 무릎 기반 키(squat_shallow·squat_depth_fade)를 틀린 자세 영상에서 확인. 체크포인트는 Mac에 남기지 않음(재현 명령은 스크립트 머리말).
- **라이선스**: Fit3D(https://fit3d.imar.ro, 비상업·양도 불가·재배포 금지) — 학습·평가 모두 사용자 본인 Mac·Home에서만. MotionAGFormer 코드·가중치: https://github.com/TaatiTeam/MotionAGFormer (Apache-2.0, LICENSE 파일).

## 실기기 전체 파이프라인 측정 (ai/device-pipeline) — 2026-10-11
**측정 방법**: `tools/pose_model_bench` 호스트 앱의 "영상 입력 라이브" 모드(`Host/PipelineBench.swift`, `run_pipeline.sh`). 사람 없이 Exercise3D 측면 영상 13개(세트마다 가장 측면인 카메라, 각도 10–32°, 720p로 줄임: 스쿼트·로우 720×1280 세로, 푸시업 1280×720 가로)를 AVAssetReader로 기기에서 디코딩해 카메라 대신 넣음. 프레임마다 라이브 카메라와 **같은 코드**: 처리 큐에서 `RTMPoseCropTracker.estimate`(사람 crop·RTMPose·디코딩·1초 재확인, 이번에 CameraPosePreview·pose-replay·벤치가 함께 쓰도록 뽑아냄) [+ MotionAGFormer-XS] [+ `WorkoutSetRecorder.append`], 메인 스레드에서 평가기·`FormWarningTracker`·브리지 변경 감지(Flutter 채널 제외). 영상 1개 = 1세트(endSet·녹화 파일 닫기 포함). Release 빌드(앱과 같음 → 폼 로그 꺼짐).
- **들어가지 않은 것**: 카메라 캡처, 미리보기 그리기, 푸시업·로우의 손 분기(MediaPipe, 화면 표시용). 그래서 실제 앱보다 가벼움 → 여유를 두고 판단.
- 변형마다 30 fps 속도 맞춤 180초("페이스") + 쉬지 않고 180초("무제한"), 각 실행 앞에 앱 안에서 60초 휴식. iPhone 17, 순서 a→b→c→d.
- 용어: 지연 = 프레임이 "도착"한 때부터 평가기 처리 끝까지(ms). 놓친 프레임 = 30 fps 시계에서 앞 프레임 처리가 안 끝나 버려진 프레임(카메라 `alwaysDiscardsLateVideoFrames`와 같은 규칙). 발열 = `thermalState`(nominal 정상 < fair 약간 따뜻 < serious 뜨거움 < critical).

| 변형 | 페이스 30 fps 지연 p50 / p95 / 최대 | 놓친 프레임 (5,400개 중) | 무제한 FPS (a 대비) | 무제한 지연 p50 / p95 | 발열 (페이스 / 무제한, 시작→끝) | 배터리 |
|---|---|---|---|---|---|---|
| a 기본 (s COCO17) | 23.7 / 26.7 / 75.8 | 3 (0.06%) | 131.0 | 7.3 / 8.2 | fair→nominal / nominal→fair | 측정 불가(충전 중) |
| b + 세트 녹화 | 23.8 / 27.7 / 51.8 | 9 (0.17%) | 124.0 (−5.4%) | 7.8 / 8.6 | serious→fair / fair→serious | 측정 불가 |
| c + 실시간 3D | 24.4 / 33.2 / 175.3 | 7 (0.13%) | 79.0 (−39.7%) | 12.5 / 13.3 | serious 내내 / fair→serious | 측정 불가 |
| d m COCO17 | 24.2 / 29.6 / 45.9 | 0 | 107.1 (−18.3%) | 8.9 / 10.6 | serious 내내 / fair→serious | 측정 불가 |

- 페이스 지연이 무제한보다 3배 큼(a: 모델 단계 16.6 vs 5.1 ms, 이미지 변환 4.4 vs 2.2 ms). 프레임 사이 쉬는 동안 CPU·Neural Engine이 저전력으로 내려가서(추정, 3D를 더 돌리는 c는 모델 단계가 9.9 ms로 오히려 빠름). 30 fps 예산 33 ms 중 실제 여유는 p95 기준 약 6 ms(a) — 추론만 잰 D-C-05(2 ms)보다 훨씬 적음.
- 배터리: 폰이 충전기에 연결돼 있어(`batteryState` 충전 중/완충) 내내 100% → 분당 소모량 못 잼. 충전 열 때문에 발열도 실제보다 불리할 수 있음(추정).
- 순서 효과: 휴식 60초로는 식지 않아 b·c·d는 serious로 시작한 실행이 있음 → 뒤 변형에 불리.

**렙 수 일치 확인**(무제한 첫 바퀴, 13개 영상, 정답 렙 = 10×12 + 12):
- 기기 키포인트를 Mac pose-replay(`--keypoints-csv`)에 넣으면 렙 수 13/13 같음 → 기기의 평가기·경고 트래커 경로는 Mac과 동일.
- Mac이 직접 포즈 추정까지 한 결과와: s 12/13 같음(barbellrow_0002 기기 9 / Mac 11 / 정답 12), m 13/13 같음(전부 정답). 차이는 Core ML 수치 차이(기기 vs Mac 키포인트 거리 영상별 중앙값 0–3.2 px, p95 2–10 px; Neural Engine fp16) — 경로 차이는 아님.
- 변형 c(3D 켬)의 렙 수는 a와 같음(3D는 지표·경고용). 페이스 실행에서는 놓친 프레임 때문에 b의 barbellrow_0002가 12로 바뀜.

## D-E-08 세트별 녹화는 기본 OFF 유지 (2026-10-11)
- **규칙**(트랙 E, E6 + 이번 여유 조건): 녹화가 FPS를 10% 넘게 깎으면 OFF. 아니어도 카메라·미리보기가 빠진 측정이라, 30 fps 페이스 실행에서 녹화를 켜고도 놓친 프레임 0일 때만 ON.
- **근거**: 무제한 FPS 131.0 → 124.0(−5.4%, 10% 조건은 통과). 페이스 실행 놓친 프레임 3 → **9**(0.17%), p95 지연 26.7 → 27.7 ms → 0 조건 실패 → **OFF 유지**(`WorkoutDebugFlags.setRecording` 기본 false, 코드 변경 없음).
- 덧붙임: 놓친 프레임은 가끔 오는 끊김에서 몰려 나오고(기본값 a도 3개), b는 serious로 시작함. 녹화 비용 자체는 작음(추정) — 충전기 뺀 상태·실제 카메라에서 다시 재면 ON 가능성 있음.
- **기각**: 10% 규칙만 보고 ON(카메라 캡처·미리보기·손 분기가 안 들어간 측정이라 여유 없음), 놓친 프레임을 a와의 차이로 보고 ON(요청 조건은 0).
- **되돌리기/다시 재기**: 켜기는 기존 플래그 `BPT_SET_RECORDING=1` / UserDefaults `BPTSetRecording`. 기본 ON 전환은 `WorkoutDebugFlags.setRecording`의 기본값 한 줄. 재측정 `tools/pose_model_bench/run_pipeline.sh b paced`, 실제 앱은 `BPT_PERF_LOG=1` + `scripts/compare_perf_logs.py`(docs/research/set_recording_perf.md).

## D-C-06 전체 파이프라인으로도 m COCO17 실시간 가능, 기본은 s 유지 · 실시간 3D는 켜지 않음 (2026-10-11)
- **결정**: 기본 모델 RTMPose-s 유지(전환은 D-C-05대로 사용자 결정 — 이번 측정으로 속도 조건 "전체 파이프라인에서 30 fps 유지"는 확인됨). 실시간 3D(`enableMotion3DForCamera`)는 계속 끔.
- **근거**: m은 페이스 30 fps에서 놓친 프레임 0, p95 29.6 ms(예산 33 ms의 90%), 무제한 107 FPS(s 대비 −18%), 렙 수는 Mac과 13/13 같고 정답과도 13/13. 3D는 무제한 −40%(79 FPS), 페이스 p95 33.2 ms로 예산 끝, 놓친 프레임 7 — 카메라·미리보기까지 더하면 30 fps를 못 지킬 가능성이 큼(추정). 또 앱의 `enableMotion3DForCamera`는 지금 실제 3D 코드가 없는 상수(로그용)라, c는 pose-replay의 lift3D와 같은 27프레임 창을 과거 프레임만으로 돌린 비용임. 트랙 D의 추론만 잰 값(D-D-05: 30 fps에서 3D +17 ms)과 같은 방향이고, 결론도 D-D-02(라이브 3D 끔)와 같음. 이번엔 crop·변환·평가기까지 넣어 페이스 p95 33.2 ms로 예산 끝에 닿음.
- **바뀐 코드**: 프레임당 포즈 단계(crop → RTMPose → 디코딩 → 원래 좌표 → 추적기 갱신 → 1초 재확인)를 `RTMPoseCropTracker.estimate`로 뽑아 CameraPosePreview·pose-replay·기기 벤치가 같은 함수를 부름(동작 변화 없음, `testEstimateMatchesTheManualPoseStep`).
- **기각**: m으로 지금 전환(정확도 장단점이 섞여 사용자 결정), 3D 실시간 켜기(예산 끝·놓친 프레임, 화면 표시용 이득만).
- **한계**: 카메라·미리보기·손 분기 제외, 충전 중(배터리 미측정), 실행 순서 열 누적, 720p로 줄인 Exercise3D 영상(푸시업은 가로 1280×720 — 앱 카메라는 세로).
- **되돌리기**: `estimate` 추출은 커밋 revert(이전 인라인 코드로). 결정은 문서만.

---

## 트랙 three-ex — 스쿼트·푸시업·바벨로우 시점별 렙 카운트, m COCO17, 자세 경고 데이터 점검 — 2026-10-11

용어(이 트랙)
- **렙 정확도**·**정확 일치 세트**는 맨 위 정의와 같음. 표의 "−놓침 +추가"는 정답 렙 저점과 앱 렙 끝을 순서대로 맞춰 센 놓친 렙·더 센 렙.
- **시점**: 측면 = 카메라가 몸 옆 40° 이내, **사선** = 40–75°, **정면/후면** = 75° 이상(0° = 정측면). Fit3D 카메라는 54–78°(측면 없음).
- **조정용 / 검증용**: Exercise3D는 D-B-01과 같음(P1 조정, P2·P3 검증, 푸시업은 P1뿐). **Fit3D는 결과를 보기 전에** s03·s04·s05 = 조정, s07·s08·s09·s10·s11 = 검증으로 고정(피험자 ID가 있어 사람 단위 분리가 확실함).
- **s / m / Halpe26**: RTMPose-s COCO17(이전 기본), RTMPose-m COCO17, RTMPose-s Halpe26. **iPhone 키포인트**: iPhone 17에서 앱과 같은 포즈 단계(`RTMPoseCropTracker.estimate`)로 뽑은 키포인트(`BENCH_DUMP=1`, Exercise3D 2/3 크기 영상)를 Mac 평가기로 재생한 값. 표의 값은 첫 실행(s 28영상); 2026-10-12 39영상 전부 m·s 재실행에서도 세트별 렙 수가 Mac과 39/39 같음(D-T3-05).
- 측정: 영상마다 Core ML RTMPose(사람 crop 입력)로 키포인트를 한 번 뽑고(Mac pose-replay, Fit3D는 50 fps 원본 그대로), 규칙은 `pose-replay --keypoints-csv`로 다시 돌림. "수정 전"은 integration `675d3e5`로 빌드한 pose-replay, "수정 후"는 이 브랜치. Fit3D 정답 = `rep_ann.json`(5–6렙/세트, 3D 주기성과 46/46 세트 일치). 근거 파일·스크립트는 로컬 scratchpad(three-ex), Fit3D는 집계만 기록하고 영상은 피험자별로 Home에서 받아 키포인트만 뽑고 바로 지움.

### 전체 표 (렙 정확도, 정확 일치 세트, −놓침 +추가)
사선 행은 Exercise3D 사선(48–70°, 조정 3세트) + Fit3D, 정면/후면 행은 Exercise3D(로우 후면 76–81°, 스쿼트 79°, 푸시업 70–88°) + Fit3D 78° 1개.

| 운동 | 시점 | 분할 | 수정 전 s | 수정 후 s | **수정 후 m (새 기본)** | iPhone 키포인트 s 전 → 후 |
|---|---|---|---|---|---|---|
| 바벨로우 | 측면 | 조정 | 97.7% (3/4, −1) | 100% (4/4) | **100% (4/4)** | 100% → 100% |
| 바벨로우 | 측면 | 검증 | 100% (4/4) | 100% (4/4) | **100% (4/4)** | 100% → 100% |
| 바벨로우 | 사선 | 조정 | 30.0% (1/12, −42) | 93.3% (9/12, −4) | **95.0% (10/12, −3)** | — |
| 바벨로우 | 사선 | 검증 | 14.8% (2/20, −92) | 89.9% (16/20, −10 +1) | **89.8% (17/20, −11)** | — |
| 바벨로우 | 후면 | 조정 | 0% (0/2, −22) | 63.6% (1/2, −8) | **86.4% (1/2, −3)** | 0% → 63.6% |
| 바벨로우 | 후면 | 검증 | 0% (0/2, −20) | 50.0% (1/2, −10) | **50.0% (1/2, −10)** | 0% → 50.0% |
| 스쿼트 | 측면 | 조정 / 검증 | 100% / 100% | 100% / 100% | **100% / 100%** | 100%(1세트) |
| 스쿼트 | 사선 | 조정 | 95.7% (12/15, +4) | 95.7% | **96.8% (12/15, +3)** | — |
| 스쿼트 | 사선 | 검증 | 79.8% (4/20, −5 +19) | 79.8% | **83.9% (7/20, −1 +18)** | — |
| 스쿼트 | 정면 | 검증 | 100% (1/1) | 100% | **100%** | — |
| 푸시업 | 측면 | 조정 | 100% (9/9) | 100% | **100%** | 100% → 100% |
| 푸시업 | 사선 | 조정 | 68.1% (3/14, −16 +14) | 78.4% (6/14, −11 +8) | **79.2% (7/14, −4 +16)** | 100% → 100%(Ex3D 2세트) |
| 푸시업 | 사선 | 검증 (Fit3D s07–s11) | 57.4% (3/19, −29 +20) | 60.6% (4/19, −29 +14) | **72.2% (9/19, −12 +20)** | — |
| 푸시업 | 정면 | 조정 / 검증 | 100% / 60.0% | 100% / 60.0% | **97.5% / 100%** | 100% → 100% |

- Halpe26(수정 후): 측면 스쿼트·푸시업·로우 100%(로우 조정 97.7→100), 후면 로우 63.6% / 50.0% — s와 같은 방향.
- 가짜 렙(움직임 없음): 서서 흔들림 합성 44건 × 3모델(D-B-01과 같은 생성기, 소스 4개 × 11조건) 로우 0렙(전·후), 스쿼트 s 3렙·Halpe26 0·m 0(전·후 같음 — s 3렙은 e3d_squat0002 cam1 "다리 길이 10% 상하 굽힘" 1건, 이 트랙 전부터 있던 것), 더미 영상 6개 스쿼트·로우 0렙, squat_03 2/2(세 모델).
- 셋업 키: 측면 카메라에서 setup_full_body·tracking_lost·setup_side_view 0 → 0(세 모델·iPhone). 늘어난 것: 후면 barbellrow_0003 cam3 tracking_lost 1(세트 끝 596 뒤 711프레임, 사람이 돌아섬 — 렙 밖), Fit3D 검증 로우 setup_side_view 1건이 첫 렙 도중(게이트가 30프레임 뒤 판정할 때 첫 렙이 이미 시작), Fit3D 푸시업 tracking_lost s 조정 10→14·검증 7→7(렙 도중 1→1), 렙을 더 세면서 "세트 시작"으로 보는 시점이 앞당겨져 생김(발목이 실제로 안 보임).

## D-T3-01 바벨로우: 측면 게이트가 "측면 아님"이어도 측면 규칙으로 렙을 센다 (2026-10-11)
- **결정**: `BarbellRowEvaluatorConfig.countOffSideView = true`. 게이트(어깨폭 ÷ 몸통, 컷오프 0.66)는 setup_side_view 안내(한 번)와 자세 경고 끄기에만 쓰고, 렙 카운트는 모든 시점에서 측면 규칙(한쪽 팔 허용, 휴식 자세 우선)으로 함. 게이트가 이미 안내했으면 첫 렙 끝의 setup_side_view는 다시 내지 않음(FormWarnings).
- **근거**: 위 표. 사선(Fit3D 54–78°) 조정 30→93%, 검증 15→90%(s), 후면 0→50–64%(m 86%). 측면 그대로 100%, 가짜 렙 0, 측면 셋업 키 0.
- **원인**: 게이트 지표가 사선과 후면을 못 가름 — 영상 전체 중앙값 Fit3D 사선 0.66–1.17, Exercise3D 후면 0.73–0.83. 그래서 "사선은 세고 후면은 막는" 컷오프가 없음. 후면에서 측면 규칙은 놓치기만 하고(팔꿈치 2D 각도가 당기는 동안 145–180°로 펴진 채 → `bottom`에 머묾) 더 세지 않았음.
- **남은 놓침**: 후면 barbellrow_0001·0002 cam3(팔꿈치 각도로 휴식 판정이 계속 참). 사선 Fit3D 검증 놓침 10–11렙은 대부분 s08·s11의 75° 근처 카메라.
- **기각**: (1) 측면 아님일 때 손목–몸통 거리만으로 세기(팔꿈치 무시): Fit3D 사선 17.5%→(휴식 비율 0.5)27.5%→(휴식 우선)46.3% — 세트 초반 기준선이 커서 휴식으로 못 돌아오고, 게이트가 세트 중 측면↔비측면을 오가며 규칙이 바뀜. (2) 컷오프를 올려 사선을 측면으로: 위 원인으로 후면과 못 가름.
- **되돌리기**: `countOffSideView = false`(pose-replay `--row-offside off`).

## D-T3-02 푸시업: 렙 판정에 발목을 요구하지 않고, 15프레임(0.5초) 미만 렙은 버린다 (2026-10-11)
- **결정**: `PushUpEvaluatorConfig.requireAnkleForRep = false`(한쪽 어깨·팔꿈치·손목·엉덩이만), `minRepFrames = 15`(시작 → 락아웃 15프레임 미만이면 세지 않고 렙 초기화). `wristMinJointConfidence`(0.30, 그대로)는 조정용 손잡이로만 추가.
- **근거**(조정용으로 정함: Fit3D s03·s05 + Exercise3D + iPhone 키포인트):
  | 변형 (s) | Fit3D 푸시업 조정 | Fit3D 다이아몬드 | Exercise3D 전 시점 | iPhone 70° pushup_0001 |
  |---|---|---|---|---|
  | 수정 전 | 61.2% (−10 +9) | 54.7% | 100% | 10/10 |
  | 최소 10프레임 | 66.7% | 60.4% | 100% | — |
  | + 발목 해제 | 75.6% (−6 +5) | 60.4% | 100% | **11/10**(+1, 14프레임 렙) |
  | + 손목 0.20 | 78.7% | 53.1% | 100% | — |
  | **최소 15프레임 + 발목 해제(채택)** | 75.6% | 63.0% | 100% | **10/10** |
  - 놓침 원인: Fit3D 64–70° 카메라에서 발목 신뢰도 0.1–0.25(상단 자세), 손목 0.20–0.27. 추가 원인: 서 있다가 엎드리거나 일어서며 팔꿈치가 흔들려 1–9프레임짜리 렙(Exercise3D 정상 렙은 24프레임 이상, Fit3D 33프레임 이상).
  - 검증(Fit3D s07–s11, 피험자 5명 × 카메라 4대, 사선): s 57.4→60.6%, m 72.2%.
- **남은 문제**: 엎드리기·일어서기 동작이 렙으로 세지는 경우(m 조정 +16, 검증 +20). Exercise3D 세트는 플랭크에서 시작해 이 동작이 없음. 몸 수평도·손 위치(손목–발목 높이)·손목 고정 정도로 구분해 봤으나 정상 렙과 겹침(손 위치 지표: 정상 렙 중앙값 −0.28, 5–95% −0.88–0.35 / 가짜 렙 −0.23, −0.83–0.46).
- **기각**: 손목 신뢰도 0.20(다이아몬드가 나빠짐), 위 세 가지 자세 지표 필터(분리 안 됨).
- **되돌리기**: `requireAnkleForRep = true`, `minRepFrames = 0`(pose-replay `--pushup-ankle on --pushup-min-frames 0`).

## D-T3-03 바벨로우: top에서 바로 bottom으로 내려가도 렙을 끝낸다 (2026-10-11)
- **결정**: 렙 도중 `top → bottom`(강제 전이, 안정된 `lowering` 없음)도 내리기를 본 것으로 보고 렙을 끝냄(스쿼트의 빠른 올라오기와 같은 방식).
- **근거**: 남아 있던 측면 로우 1렙(barbellrow_0002 cam1, s·Halpe26)이 바로 이 경우 — 778 top → 810 bottom에서 렙이 안 끝나고 다음 렙과 합쳐짐. 측면 조정 97.7 → 100%(s·Halpe26), 후면 조정 m 59→86%. 가짜 렙 0 그대로. 테스트 `testRowFastLoweringStillEndsTheRep`(수정 전 코드에서 0렙으로 실패 확인).
- **되돌리기**: 이 커밋 revert.

## D-T3-04 스쿼트: 규칙은 그대로 둔다 (2026-10-11)
- 사선 Fit3D 검증 추가 18–19렙은 **모두 정답 구간 밖**: 세트 전 바닥의 바를 들어 올리며 앉았다 서기, 세트 끝 바를 내려놓기(바닥에서 드는 실제 스쿼트 동작). 구간 안 추가 0. 놓침 5렙(s)은 s11 69° 한 세트 — 세트 전 카메라 쪽으로 걸어오며 서 있는 엉덩이 기준선이 낡아 세트 내내 `bottom`.
- **기각**: (1) 무릎이 30프레임 펴져 있는데 `top`이 아니면 기준선 다시 잡기 — s11을 고치지만 검증 피험자에서 찾은 수정이고, 다른 세트의 렙 위치를 여럿 바꾸며 s11 65906101에 구간 안 추가 1렙이 생겨 버림. (2) 준비 자세 프리셋: 바를 들기 전에 가만히 서 있어서 효과 없음(79.8% 그대로).
- 사용자 영상(랙에서 바를 빼는 경우)에서 다시 볼 것.

## D-T3-05 운동 카메라 2D 모델을 RTMPose-m COCO17로 바꾼다(플래그), 캘리브레이션은 s 유지 (2026-10-11)
- **결정**: `RTMPoseModel.workout`(CameraPosePreview·pose-replay 기본) = m COCO17, `RTMPoseModel.workoutUsesMediumModel = true`. 캘리브레이션 캡처(`RTMPoseModel.active`)는 s 그대로(트랙 F 기준값이 s로 맞춰져 있음). `BPT_POSE_MODEL=coco17|halpe26|mcoco17`은 둘 다 덮어씀. `rtmpose_m_forward.mlpackage`(26 MB) 번들 추가.
- **근거**(위 표, 같은 새 규칙에서 s → m):
  - 측면: 셋 다 100% 같음(조정·검증, 가짜 렙 0, 측면 셋업 키 0).
  - 검증 사선(Fit3D 5명): 스쿼트 79.8→83.9%, 푸시업 60.6→72.2%, 로우 89.9→89.8%(추가 1→0, 놓침 10→11). 후면 로우 조정 63.6→86.4%.
  - 흔들림 합성: 스쿼트 s 3렙 → m 0렙.
  - iPhone 일치: D-C-06에서 m은 iPhone·Mac 렙 수 13/13 같음(s는 barbellrow_0002 측면에서 9 vs 11).
  - 속도: iPhone 17 추론 3.31 ms(s 1.97), 전체 파이프라인 30 fps 놓친 프레임 0, p95 29.6 ms(D-C-05·06).
  - **잃은 것**: Exercise3D 정면 푸시업 pushup_0003 cam1(86°) 첫 렙 1개. 원인: 정면에서 2D 팔꿈치 범위가 좁고(179→108°) 첫 렙 동안 적응 임계값이 아직 고정값(130/105°)이라 bottom을 못 찍음. s가 이 렙을 센 것은 프레임 10–30에서 오른팔 키포인트가 8–28°로 튄 오류가 범위를 미리 넓혀 준 우연. 정면 푸시업은 앱이 측면 촬영을 안내하는 시점.
  - 셋업 안내 차이: 더미 영상(제자리 회전) 로우 setup_side_view s 1 → m 3, 서 있는 합성 0 → 11 — 정면이 보이는 영상에서 "측면으로" 안내가 더 잘 나옴(측면 영상에서는 0).
- **기각**: s 유지(검증 사선이 낮고 기기 일치가 덜 안정적), Halpe26(캘리브레이션 영향, D-C-04 사용자 결정 대기).
- **iPhone 확인(2026-10-12, 케이블 연결)**: Exercise3D 39영상 전부를 iPhone 17에서 m·s로 뽑아(`BENCH_DUMP=1`, 무제한 106 FPS로 끊김 없이) 새 규칙으로 재생 → 세트별 렙 수가 Mac과 **m 39/39, s 39/39 같음**. 정확도 표의 Exercise3D 값(측면 전부 100%, 후면 로우 m 86.4% / 50.0%, 정면 푸시업 m 97.5%)이 iPhone 키포인트에서도 그대로. 셋업 키도 같음(후면 barbellrow_0003 cam3 세트 끝 뒤 tracking_lost 1건).
- **한계**: 배터리·발열 장시간 미측정.
- **되돌리기**: `workoutUsesMediumModel = false`(또는 Xcode scheme `BPT_POSE_MODEL=coco17`).

## D-T3-06 자세 경고 키는 그대로 끈다 — Fit3D·Exercise3D에 틀린 자세 라벨이 없음 (2026-10-11)
- **확인**: Fit3D train(피험자 8명 × 37개 동작)에는 `rep_ann.json`(렙 경계), `joints3d_25`, `smplx`, `gpp`, `camera_parameters`, 영상뿐 — 자세 오류 라벨 없음. Exercise3D 라벨(`exercise3d_labels`)도 `not_ground_truth` 3D·뷰 메타데이터뿐, form/mistake 필드 없음. 두 데이터 모두 정상 시범 동작(트레이너)으로 보임(추정).
- **결정**: pushup_hip_sag·pushup_head_drop·row_torso_swing 등 자세 키 OFF 유지, 임계값 변경 없음. 검출률(틀린 렙 중 경고 비율)을 잴 데이터가 없음.
- **필요한 영상**(폰 세로, 몸 옆 0–30°, 사람당 키별 1세트 5–8렙 + 같은 사람 정상 1세트, 가능하면 2명 이상): 푸시업 허리 처짐(hip_sag)·엉덩이 들기(hip_pike)·머리 떨굼(head_drop)·덜 내려가기(shallow)·팔 덜 펴기(no_lockout), 스쿼트 덜 앉기(shallow)·엉덩이 먼저(hips_first)·덜 일어서기(no_lockout)·뒤꿈치 들림(heel_rise, Halpe26), 정면 영상으로 무릎 모임(knee_valgus), 로우 몸통 흔들기(torso_swing)·상체 세우기(standing_up)·덜 당기기(short_pull)·으쓱(shrug). `data/side_videos/labels_template.csv` 형식(form=wrong, wrong_key)으로 넣고 `scripts/eval_side_videos.py`로 검출률·오경보율을 잼.

## D-T3-07 경고 임계값 점검(crop 입력 정상 렙 분포) — 표만, 변경 없음 (2026-10-11)
| 키 | 모델 | 데이터·시점 | 정상 렙 | p50 | p95 | p99 | 최대 | 임계값 | 넘은 렙 |
|---|---|---|---|---|---|---|---|---|---|
| pushup_hip_sag | s | Ex3D 측면 | 90 | 0.066 | 0.087 | 0.092 | 0.094 | 0.140 | 0 |
| pushup_hip_sag | m | Ex3D 측면 | 90 | 0.059 | 0.073 | 0.082 | 0.084 | 0.140 | 0 |
| pushup_hip_sag | Halpe26 | Ex3D 측면 | 90 | 0.064 | 0.090 | 0.091 | 0.095 | 0.140 | 0 |
| pushup_hip_sag | s / m | Fit3D 사선(조정) | 37 / 44 | −0.070 / −0.049 | 0.226 / 0.041 | 0.250 / 0.052 | | 0.140 | 3 (8%) / 0 |
| pushup_head_drop | s | Ex3D 측면 | 90 | 0.060 | 0.202 | 0.306 | 0.319 | 0.376 | 0 |
| pushup_head_drop | m | Ex3D 측면 | 90 | 0.045 | 0.189 | 0.218 | 0.240 | 0.376 | 0 |
| pushup_head_drop | Halpe26 | Ex3D 측면 | 90 | 0.065 | 0.144 | 0.167 | 0.195 | 0.376 | 0 |
| pushup_head_drop | s / m | Fit3D 사선(조정) | 39 / 45 | 0.188 / 0.114 | 0.508 / 0.750 | 1.127 / 1.129 | | 0.376 | 9 (23%) / 7 (16%) |
| row_torso_swing | s | Ex3D 측면 조정 / 검증 | 44 / 40 | 4.8° / 9.5° | 8.2° / 15.8° | 9.4° / 17.3° | | 39.9° | 0 / 0 |
| row_torso_swing | m | Ex3D 측면 조정 / 검증 | 44 / 40 | 5.2° / 9.4° | 7.9° / 18.0° | 10.6° / 18.8° | | 39.9° | 0 / 0 |
| row_torso_swing | Halpe26 | Ex3D 측면 조정 / 검증 | 44 / 40 | 5.9° / 9.5° | 8.9° / 19.8° | 13.3° / 21.0° | | 39.9° | 0 / 0 |
| row_torso_swing | s / m | Fit3D 사선(조정) | 38 / 40 | 5.6° / 4.9° | 34.4° / 32.0° | 64.6° / 58.9° | | 39.9° | 2 (5%) / 1 (2%) |
- 측면 정상 렙은 세 키 모두 임계값의 약 1/2–2/3에서 끝남(crop 입력이 전체 프레임 입력보다 조용함, D-C-04와 같은 결론). 임계값은 전체 프레임 입력 p99라 crop 기준으론 느슨함 — 틀린 자세 영상이 오면 crop·m 기준으로 다시 맞춰야 함.
- Fit3D 사선 값이 큰 것은 시점 탓(2D 몸통 각도·선 거리가 사선에서 늘어남). 측면 판정(로우 = 게이트, 푸시업 = 렙의 `front_view_fraction`)이 "측면 아님"인 렙은 판정하지 않지만, 게이트가 정해지기 전·측면으로 잠깐 돌아온 렙은 판정됨: Fit3D 사선에서 "켰다면 났을" 횟수(수정 후, 렙 수 대비) row_torso_swing s 2/195·m 3/194, row_standing_up 2·1, pushup_head_drop 2/175·1/221, pushup_hip_pike 2·8, squat_knee_valgus(정면 키) 126/178·113/180. 모두 꺼진 키라 말하지 않음. 켤 때는 사선 렙 판정도 막아야 함(특히 squat_knee_valgus).

## D-T3-08 측면 푸시업 검증(P1 아닌 사람): 규칙 변경 없이 측정만 — 실제 측면 약 80%, 합성 측면 61% (2026-10-11)
- **결정**: 이번에는 규칙·임계값을 바꾸지 않는다(측정 트랙). 측면 푸시업 "100%"는 P1 한 사람 수치로만 쓰고, 다른 사람 기준 값은 아래로 기록한다. 상세 `docs/results/pushup_heldout_side.md`.
- **근거**(앱 기본 RTMPose-m COCO17, crop 입력, integration/ai `ab07ba5` 규칙):
  | 출처 | 사람 | 시점 | 렙 정확도 (−놓침 +추가) |
  |---|---|---|---|
  | MM-Fit 실제 영상(CC BY 4.0) | 약 15명, 65세트 | 몸 옆 약 90°±20 | **80.2%** (−125 +4), 정확 세트 36/65 |
  | Fit3D 모캡 → 가상 측면, Exercise3D 오차 모델(합성, 검출기 없음) | 검증 s07–s11 | 0 / 20 / 40° | 62.8 / 57.5 / 63.7%, 합계 **61.4%** (−142 +52; 세트 구간만 68.0%) |
  | 같은 합성 | 조정 s03–s05 | 0 / 20 / 40° | 90.0 / 84.6 / 81.3%, 합계 85.2% |
  - 합성 놓침의 주원인은 동작 모양: s07·s10은 팔꿈치를 옆으로 벌려 내려가 측면 2D 팔꿈치 각도가 바닥에서도 169–174°(3D는 92–112°까지 굽음) → 2D 팔꿈치 각도 하나로 세는 규칙이 못 봄. 오차를 빼도(깨끗한 투영) 검증 61.7%로 거의 같음.
  - 실제 영상 놓침: 버그 후보 3개(고치지 않음) — (1) crop이 몸 아래쪽에 고정돼 상체 관절이 crop 경계 x에 붙음(w02_s3 x=675.388 60–186프레임 등, 0렙 세트 3개), 1초 재확인이 같은 사람의 잘린 crop은 못 고침(추정), (2) 가까운 팔 손목 신뢰도 0.22–0.36 < 0.30이라 그 팔이 빠지고 안 움직이는 먼 팔(161–176°)로 판정(w17 41렙 중 1렙), (3) 첫 렙이 적응 탑 임계값(약 151°)까지 안 펴져 두 렙이 합쳐짐(w00_s1).
- **오차 모델**: Exercise3D 측면 푸시업 9영상(P1) RTMPose-m − Sapiens2 의사라벨 잔차·신뢰도를 영상 통째로 재사용(몸통 길이 단위, 평균 제거). COCO 정의 차이는 조정 피험자 실제 영상(4대 × 3명)으로 부위별 3D 오프셋을 맞춤(엉덩이 중앙 오차 16.8 → 6.3 px, 어깨 11.3 → 8.5 px). Sapiens2는 2D 잡음 모델에만 쓰고 캘리브레이션에는 안 씀.
- **기각**: RepCount-A/LLSP(데이터 라이선스 없음, 제3자 YouTube), Countix(YouTube ID만 — 라이선스 모호, 받지 않음), PushupBench(표준 푸시업 없음), UCFRep(라이선스 없음). MM-Fit 결과로 바로 규칙 고치기 — MM-Fit이 유일한 실제 측면 검증 세트라 거기서 고치면 검증값이 없어짐(고칠 땐 MM-Fit 세션을 조정/검증으로 먼저 나눌 것).
- **한계**: MM-Fit 라벨은 세트 렙 수뿐(놓침·추가가 상쇄될 수 있음), 사람 구분은 외모 추정. 합성은 카메라 한 설정(높이 0.5 m, 3.5 m), 오차 모델이 P1 한 사람에서 옴(추정: 다른 사람의 실제 검출 오차는 더 클 수 있음).
- **라이선스**: Fit3D는 Home에서만 계산, 키포인트·합성 CSV는 Mac scratchpad에서 쓰고 삭제(집계만 문서에). MM-Fit 클립·출력도 측정 후 삭제.
- **되돌리기**: 해당 없음(앱 변경 없음). 스크립트 `scripts/eval_pushup_virtual_side.py`, `scripts/eval_pushup_mmfit.py`, `scripts/fetch_zip_members.py`.

## D-C-07 MediaPipe Pose Landmarker 재검토: 기본은 RTMPose-m 유지, 푸시업 전용 후보로만 추천 (2026-10-12)
- **결정(추천만, 앱 변경 없음)**: 운동 카메라 기본 2D 모델은 RTMPose-m COCO17(D-T3-05) 그대로. MediaPipe Pose Landmarker **full**(CPU, VIDEO 모드)은 속도는 충분하고 측면 푸시업 키포인트가 크게 좋아서 **푸시업 전용 후보**로 다시 볼 가치가 있음. 전환 전에 MediaPipe 키포인트로 렙 정확도(측면 푸시업 Exercise3D + MM-Fit 검증 세트)를 먼저 잴 것. lite·heavy는 기각.
- **측정 1 — iPhone 17 속도** (`tools/pose_model_bench` 호스트 앱, `run_pipeline.sh mp all` 한 번 실행으로 연달아, 사람 없이 D-C-05와 같은 720×1280 프레임 1장을 카메라처럼 BGRA 픽셀 버퍼로, `detect`만 잼, 워밍업 20회 뒤 300회, ms). MediaPipeTasksVision 1.0.0(앱 `ios/Podfile.lock`과 같은 pod·버전, 벤치 호스트에만 연결).
  | 모델 | 델리게이트 | VIDEO p50 / p95 | IMAGE p50 / p95 | 로드 | 150초 연속(VIDEO, 빠른 쪽) FPS 처음 → 끝 (최저), 1회 p50 끝 | 발열 시작 → 끝 |
  |---|---|---|---|---|---|---|
  | lite | **CPU** | **6.87 / 7.59** | 15.51 / 16.07 | 67 ms | 131 → 93 (93), −29%, 10.8 ms | 2 → 2 |
  | lite | GPU | 10.41 / 11.72 | 20.16 / 22.00 | 1020 ms(첫 GPU 초기화) | — | — |
  | full | **CPU** | **8.56 / 9.04** | 17.18 / 19.74 | 71 ms | 91 → 73 (67), −20%, 13.7 ms | 2 → 2 |
  | full | GPU | 12.56 / 14.02 | 22.56 / 24.24 | 157 ms | — | — |
  | heavy | CPU | 19.39 / 20.31 | 35.76 / 38.76 | 78 ms | — | — |
  | heavy | **GPU** | **12.21 / 13.33** | 16.81 / 19.69 | 331 ms | 82 → 35 (35), −58%, 28.2 ms (20초 뒤부터) | 2 → 2 |
  | 참고 RTMPose-s COCO17 (D-C-05) | Core ML ALL | 1.97 / 2.11 (모델만) | | 541 ms | 593 → 547 (523) | 1 → 1 |
  | 참고 RTMPose-m COCO17 (D-C-05, 현재 기본) | Core ML ALL | 3.31 / 4.05 (모델만) | | 1016 ms | 326 → 282 (218) | 2 → 2 |
  | 참고 Apple Vision (D-C-05) | Vision | 12.17 / 16.76 | | | — | — |
  - VIDEO 모드 = 앞 프레임 결과로 사람 위치를 추적해 검출기를 건너뜀(라이브 카메라와 같음), IMAGE 모드 = 매 프레임 사람 검출부터. 같은 프레임 반복이라 VIDEO는 추적이 항상 성공하는 가장 좋은 경우.
  - MediaPipe 수치는 사람 검출·crop·랜드마크·후처리까지 포함한 `detect` 전체, RTMPose 수치는 모델 추론만(crop 그리기·디코딩 제외) → 직접 비교는 아래 전체 파이프라인 표로.
  - lite·full은 CPU(XNNPACK)가 GPU보다 빠름, heavy만 GPU가 빠름. heavy GPU는 20초 뒤 GPU 클럭이 내려가 1회 28 ms(35 FPS)로 떨어짐 → 30 fps 파이프라인에 못 넣음.
- **측정 2 — 30 fps 페이스 영상 입력 파이프라인** (`PipelineBench`, 같은 실행 안에서 60초 휴식 후 각 180초, Exercise3D 720×1280 영상 4개(스쿼트 2·로우 2) 반복, 5,400프레임). MediaPipe는 카메라 픽셀 버퍼를 바로 받고(CGImage 변환·사람 crop 없음) 33개 중 COCO-17 부분을 평가기에 넣음.
  | 변형 | 지연 p50 / p95 / 최대 (ms) | 놓친 프레임 | 포즈 단계 p50 / p95 | 이미지 변환 p50 | 렙 수(영상 4개 첫 바퀴) | 발열 |
  |---|---|---|---|---|---|---|
  | MediaPipe full, CPU | **15.5 / 16.0 / 21.0** | **0** | 11.1 / 11.6 | 0(필요 없음) | 12·10·10·10 | serious 내내 |
  | RTMPose-m COCO17 (현재 기본, 같은 세션) | 20.6 / 30.0 / 212.3 | 11 (0.20%, 한 번 멈춤) | 13.6 / 20.6 | 3.85 | 12·10·10·10 | serious 내내 |
  | 참고 D-C-06 d (m, 이전 세션, 13영상) | 24.2 / 29.6 / 45.9 | 0 | | | | serious 내내 |
  - 렙 수는 두 모델이 4/4 같음(row_0002 12, row_0003 10, squat_0001 10, squat_0002 10). 4개 영상뿐이라 정확도 근거는 아님.
- **측정 3 — 키포인트 품질** (Mac, `scripts/eval_mediapipe_pose2d.py`, bpt-ft의 mediapipe 0.10.21 Python, IMAGE 모드). 지표는 §3과 같은 PCK@0.05 body12(어깨·팔꿈치·손목·엉덩이·무릎·발목이 정답에서 사람 박스 긴 변의 5% 안에 든 비율), Exercise3D 측면(≤40°) 25영상 1,312프레임(15프레임마다), 정답 = Sapiens2 의사 라벨. RTMPose-m은 앱 Core ML 모델을 같은 프레임의 정답 박스 crop에 돌림(§3의 "crop" 행과 같은 방식, 전체 0.877 = §3 0.873 재현).
  | 모델 | 입력 | 전체 | 스쿼트 | 푸시업 | 바벨로우 | 사람 찾음 |
  |---|---|---|---|---|---|---|
  | RTMPose-m COCO17 (기본) | 정답 박스 crop | **0.877** | **0.917** | 0.708 | **0.961** | 100% |
  | MediaPipe lite | 전체 프레임 | 0.709 | 0.779 | 0.697 | 0.609 | 99.9% |
  | MediaPipe full | 전체 프레임 | 0.846 | 0.857 | **0.924** | 0.761 | 99.9% |
  | MediaPipe full | 정답 박스 crop | 0.814 | 0.829 | 0.892 | 0.720 | 98.2% |
  | MediaPipe heavy | 전체 프레임 | **0.890** | 0.878 | **0.943** | 0.860 | 99.9% |
  | MediaPipe heavy | 정답 박스 crop | 0.876 | 0.854 | 0.932 | 0.861 | 98.0% |
  - MediaPipe는 자기 검출기로 전체 프레임을 받을 때가 더 좋음(crop을 주면 검출기가 오히려 놓침). RTMPose는 정답 박스(앱보다 유리한 조건)라 RTMPose 쪽이 약간 유리.
  - MediaPipe의 엉덩이·어깨 정의(BlazePose)가 COCO·Sapiens와 달라 일정한 오프셋이 있을 수 있음(추정) → 스쿼트·로우 점수가 실제보다 낮게 나왔을 수 있음.
- **판단**:
  1. 속도: full CPU VIDEO 8.6 ms(p95 9.0)로 RTMPose-m 모델만(3.3 ms)보다 느리지만 사람 검출·crop이 들어간 값이고, 앱과 같은 프레임 경로에서는 오히려 빠름(페이스 p95 16.0 vs 30.0 ms, 놓친 프레임 0 vs 11). 픽셀 버퍼를 바로 받아 CGImage 변환(3.9 ms)과 crop 그리기가 없어서. 30 fps 예산 33 ms의 약 절반.
  2. 품질: 측면 푸시업 0.924 vs 0.708(+21.6%p) — RTMPose의 약점(D-T3-08 푸시업 측면 실제 80%)과 정확히 겹침. 스쿼트 −6.0%p, 로우 −20.0%p로 나쁨 → 전체 기본 교체는 안 됨.
  3. 의존성: 앱은 이미 손 분기 때문에 MediaPipeTasksVision 1.0.0을 링크함 → 추가 비용은 모델 9.4 MB(full)뿐.
  4. heavy는 품질 최고(0.890)지만 지속 실행에서 28 ms로 떨어져 기각, lite는 품질 0.709로 기각.
- **기각**: 지금 기본 교체(스쿼트·로우 키포인트가 나쁨, 렙 정확도 미검증), 푸시업만 바로 전환(렙 수 검증 전 — BRIEF: 검증 없는 변경 금지), GPU 델리게이트(lite·full은 CPU가 빠름, 앱에서는 GPU를 미리보기와 나눠 씀).
- **한계**: 폰이 충전 중이었고 앞 작업(three-ex 기기 실행) 직후라 처음부터 발열 serious(2) → 지속 FPS는 실제보다 불리할 수 있고 배터리 소모는 측정 불가. RTMPose 지연 표의 s·m·Vision 행은 D-C-05의 다른 세션(발열 1–2) 값. 프레임 1장 반복이라 VIDEO 추적은 항상 성공(실제 움직임에서는 추적 실패 시 검출기가 다시 돌아 IMAGE 쪽 값(17 ms)에 가까운 프레임이 섞임, 추정). 품질 정답은 Sapiens2 의사 라벨(사람 라벨 아님), 사람 P1–P3만.
- **모델·라이선스**: `pose_landmarker_{lite,full,heavy}.task`(float16/latest, 2023-04-27/28) — https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_{lite,full,heavy}/float16/latest/pose_landmarker_{lite,full,heavy}.task (공식 페이지 https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker#models). Apache-2.0. 크기 5.8 / 9.4 / 30.7 MB, sha256 lite 59929e1d…574a, full 4eaa5eb7…c4ad, heavy 64437af8…c7b. 저장소에는 넣지 않음(벤치 자산은 git-ignored). 라이브러리 라이선스 텍스트는 pod 안 `Pods/MediaPipeTasksVision/LICENSE`(Apache-2.0).
- **되돌리기/다시 재기**: 앱 코드 변경 없음(벤치 도구·평가 스크립트·문서만). 재측정 `BPT_MP_DIR=<task 3개 + frame.jpg> tools/pose_model_bench/run_pipeline.sh setup <clips> && run_pipeline.sh mp all`(지연 → 지속 3개 → 페이스 full·m, 한 번 실행이라 기기 자동 잠금 없음). 품질 `scripts/eval_mediapipe_pose2d.py pack|eval|rtmpose`.
## 트랙 pushup-fix — 측면 푸시업 렙 카운트를 P1 아닌 사람에게 일반화 — 2026-10-11

### D-T3-09 MM-Fit 사람 단위 조정/검증 분할 (수정 결과를 보기 전에 고정)
- **분할**(사람 = D-T3-08의 외모 추정 A–O, 15명; 약 60/40):
  - **검증(held-out) 6명 / 18세트**: 저자 "unseen test" 세션 w00(A)·w05(F)·w12(I)·w13(J)·w20(O) + 저자 val 분할에서만 나오는 사람 w19(N, 무릎 푸시업).
  - **조정(tuning) 9명 / 47세트**: w01(B), w02·w09(C), w03·w06·w08·w14(D), w04·w15(E), w07·w10(G), w11(H), w16(K), w17(L), w18(M).
- **규칙**: 저자 분할(train/val/test)을 따라 "train 세션에 한 번도 안 나오는 사람" = 검증. 수정 후 결과를 본 뒤 바꾸지 않는다.
- **주의**: D-T3-08(측정만)에서 전체 65세트의 수정 전 결과는 이미 공개돼 있었다(이 분할은 그 뒤에 정함). 버그 후보 3의 예시 w00_s1은 검증 세트라 조정에 쓰지 않고 조정 세트에서 같은 현상을 따로 찾는다. 사람 구분은 외모 추정이라 "?" 세션(w06·w09·w10·w11·w14·w18)이 실제로는 다른 사람일 수 있음(추정).
- Fit3D 가상 측면은 three-ex 분할 그대로(조정 s03–s05, 검증 s07–s11), Exercise3D는 P1 조정.

### D-T3-10 crop이 관절을 경계에 붙이면 crop을 다시 맞춘다 (모든 운동) (2026-10-12)
- **결정**: `RTMPoseCropTracker.refitAtCropEdge = true`. 신뢰도 0.3 이상 관절이 crop 경계에서 1 입력픽셀(crop 폭/192, 높이/256) 안에 있으면 crop을 유지하지 않고 키포인트로 다시 맞춘다(여백만큼 잘린 쪽으로 커짐, 몇 프레임 안에 몸 전체를 다시 덮음). pose-replay JSON `crop_edge_refits`에 횟수.
- **원인**(버그 후보 1 확인): RTMPose(SimCC)는 crop 밖을 가리킬 수 없어 crop 밖으로 나간 머리·팔 관절을 crop 경계 x 하나에 붙여 냄(w02_s3 x=675.388). 기존 유지 조건 `crop.contains(person)`은 경계 위 점도 "안"으로 보고, 세로로만 8% 늘려 보는 사람 상자 때문에 가로(엎드린 몸) 방향 잘림을 못 봄. 1초 재확인은 "더 큰 다른 사람"만 바꿈.
- **근거**(MM-Fit 조정 9명, 규칙 그대로·crop만): 80.2% → 89.3%(−91 +3 → −44 +7), w02_s3 0→10, w01_s2 7→10, w03_s1 4→10, w16_s3 5→10, w16_s4 0→11. 앱에서 켜진 셋업 키 setup_full_body 3→0, tracking_lost 8→0. 검증 6명은 crop만으로 80.4% → 80.1%(−34 +1 → −33 +3) — 검증 세트에는 crop 잘림 세트가 적음. 높이 신호(D-T3-11)와 같이 쓸 때 효과는 아래 표.
- **회귀**(새 tracker로 키포인트를 다시 뽑아 이전 캐시와 비교, 규칙은 D-T3-11까지 켠 최종): Exercise3D 39영상 × m·s — refit은 푸시업 25/30, 로우 3/24(1–2회), 스쿼트 0. 렙 정확도 표는 전과 완전히 같음(측면 스쿼트·로우·푸시업 m·s 모두 100%, 사선·정면도 같은 값, 셋업 키 같은 수). Fit3D 실제 영상 사선(스쿼트·로우, s03–s07은 m·s, s08–s11은 m만 — 잠금 대기로 s 생략): refit 1회(s08 스쿼트 1대), 정확도 그대로 — m 스쿼트 조정 95.2%·검증 83.9%, 로우 조정 95.0%·검증 89.8%(D-T3 표와 같음). 흔들림 합성 44건·squat_03·더미 6개: 스쿼트·로우 추가 렙 0(squat_03 2/2), 표 전체가 전과 같음(서 있는 영상에 푸시업 평가기를 돌린 값도 50/59/8 그대로).
- **iPhone**: iPhone 17에서 이 브랜치 bench host(`RTMPoseCropTracker.estimate`, m)로 Exercise3D 39영상 키포인트를 뽑아 같은 규칙으로 재생 → 렙 수 Mac과 **39/39 일치**, 측면 세 운동 100%.
- **기각**: 1초 재확인에서 같은 사람의 더 큰 상자로 바꾸기 — 재확인 주기(1초)만큼 늦고, 전체 프레임(늘린 입력) 키포인트가 덜 정확함. 경계 허용 오차를 키우기(예: 5픽셀) — 정상 관절도 걸려 crop이 자주 흔들림(추정, 측정 안 함).
- **되돌리기**: `refitAtCropEdge = false`(pose-replay `--crop-edge off`).

### D-T3-11 측면 푸시업: 어깨 높이 신호를 두 번째 렙 신호로, 렙 수 = max(팔꿈치, 높이) (2026-10-12)
- **결정**: `PushUpEvaluatorConfig.heightRepSignal = true`(측면 게이트가 "측면 아님"이면 안 씀). 신호 = (손목 y − 어깨 y) ÷ 어깨–엉덩이 길이, 폼 트래커가 고른 쪽(카메라 가까운 쪽) 관절. 어깨·엉덩이 신뢰도 0.30, 손목 0.10, 어깨–엉덩이 선이 수평에서 35° 이내(플랭크)인 프레임만. `PushUpHeightCounter`: 5프레임 중앙값, 최근 90프레임(3초) 최소/최대로 범위, 범위 ≥ 0.30 몸통일 때만, 위 = 최소 + 0.70×범위 이상, 아래 = 최소 + 0.35×범위 이하, 아래→위 15프레임 이상이면 1렙. 앱 렙 수는 팔꿈치 각도 렙과 높이 렙 중 큰 값(둘이 같은 렙을 세면 한 번).
- **고친 것**: 버그 후보 2(가까운 손목 신뢰도 < 0.30이라 안 움직이는 먼 팔로 판정, w17), 3(첫 렙이 적응 탑 임계값까지 안 펴짐), 4(팔꿈치를 옆으로 벌린 푸시업 — 2D 팔꿈치 각도가 바닥에서도 169–174°, Fit3D s07·s10). 셋 다 "팔꿈치 각도 하나로 센다"가 원인이라 팔 선택·임계값을 따로 고치지 않고 팔꿈치와 무관한 신호를 하나 더함(손잡이 2개 대신 1개).
- **조정 과정**(조정 데이터만: MM-Fit 조정 9명·Fit3D s03–s05 가상 측면·Exercise3D P1): Python 원형으로 높이 카운터 단독·max·합집합(±D프레임 중복 제거) 비교. 전체 기간 최소/최대(팔꿈치와 같은 방식)는 세트 전 자세 잡기가 범위를 오염시켜 MM-Fit 조정 78.1% → 최근 90프레임으로 97.9%(120: 97.2, 180: 94.5). 단독은 Exercise3D 측면 96.7%(−2 +1)라 팔꿈치(100%)를 대체 못 함 → max. 합집합은 Fit3D 추가가 늘어(82.5%) 기각. 수평 게이트 없음(90°)이면 Exercise3D 측면 m +1 → 45°·35° 모두 0, 35° 채택(서 있기·무릎 꿇기 배제 여유). 위 0.75 / 아래 0.30 / 최소 20프레임 / 범위 0.4는 MM-Fit 조정이 92.7–98.3%로 흔들려 중간값(0.70/0.35/15/0.30) 유지.
- **근거**: 아래 전후 표(D-T3-09 분할, 검증은 조정이 끝난 뒤 한 번만 봄).
- **남은 것**: Fit3D s07 0°(검증) 17.6% — 벌린 팔꿈치 + 0°에서 어깨가 내려가는 폭이 범위 0.30 몸통보다 작음(추정). MM-Fit 추가 +7(조정)·+3(검증)은 전부 라벨 시작 전(클립 22–61프레임, 라벨 시작 90) 자세 잡기 — 이전부터 있던 팔꿈치 신호 쪽(D-T3-02 남은 문제). 높이 신호는 폼 경고에 안 씀.
- **되돌리기**: `heightRepSignal = false`(pose-replay `--pushup-height off`). 끄면 이전과 렙 끝 프레임까지 같음(조정 데이터 전부 비교).

### D-T3-12 푸시업 전용 MediaPipe Pose full 키포인트는 넣지 않는다 (후보 비교, 조정으로 선택) (2026-10-12)
- **배경**: D-C-07(integration 9a07dda) — MediaPipe Pose full(CPU, VIDEO)이 측면 푸시업 PCK body12 0.924(RTMPose-m 0.708), iPhone 30 fps p95 16 ms·드롭 0. 앱은 손용 MediaPipeTasksVision 1.0.0을 이미 링크.
- **방법**: `scripts/mediapipe_pose_keypoints_csv.py`(VIDEO 모드, 전체 프레임, 1명, 33→COCO17 매핑과 신뢰도 = visibility는 D-C-07 iPhone 벤치와 같음)로 MM-Fit 65세트·Exercise3D 푸시업 15영상 키포인트를 Home(CPU, bpt-home mediapipe 0.10.21)에서 뽑고, 앱 푸시업 규칙(pose-replay `--keypoints-csv`)으로 재생. Fit3D 가상 측면은 검출기가 없어 규칙 비교만(MediaPipe 해당 없음).
- **조정 데이터로 선택**(렙 정확도):
  | 후보 | MM-Fit 조정 9명 | Exercise3D 측면(P1) | Exercise3D 사선 / 정면(P1) |
  |---|---|---|---|
  | RTMPose-m + crop 재맞춤 + 높이 신호(D-T3-10·11) | **98.1%** (−2 +7) | **100%** | 100% / 97.5% |
  | MediaPipe full + 높이 신호 | 97.1% (−5 +9) | 100% | 55.0% / 61.0% |
  | MediaPipe full, 팔꿈치만 | 93.9% (−21 +8) | 98.9% | 55.0% / 61.0% |
  → 조정에서 RTMPose 경로가 최고 → 채택.
- **검증(선택 뒤 한 번)**: MM-Fit 검증 6명 RTMPose 경로 94.5% (−7 +3) / MediaPipe + 높이 96.1% (−6 +1) / MediaPipe만 89.9%. 차이 2렙(18세트)이고, MediaPipe는 Exercise3D 사선·정면 푸시업이 크게 떨어지고(−9·−15렙), MM-Fit 검증 tracking_lost 0 → 4 → "회귀 없이 이김" 조건 불충족이라 앱에 넣지 않음.
- **남은 가능성**: MediaPipe는 키포인트 자체는 더 정확(PCK) — 측면 게이트가 확실할 때만 MediaPipe로 바꾸는 혼합은 별도 트랙 후보(추정, 측정 안 함). 이번에 만든 키포인트 CSV는 삭제.
- **되돌리기**: 해당 없음(앱 변경 없음).

## D-DATA-01 공개 평가 데이터 채택: Mendeley 7운동 멀티뷰(CC BY 4.0) + YouTube CC BY 구간, AI 2패스 라벨, 사람 단위 분할 — 측정만, 키는 계속 끔 (2026-10-12)
- **결정**: 사용자가 검증 영상을 찍을 수 없어 공개 데이터로 대신한다. (1) Mendeley "Multi-View Raw Video Dataset of Seven Fitness Exercises with Good/Bad Form Labels" v3(doi:10.17632/kgbb3yn47p.3, CC BY 4.0, 26명, 정면·측면·사선, 스쿼트·푸시업·덤벨 로우 good/bad) 438클립, (2) YouTube에서 영상 자체 라이선스가 CC BY인 것만 133구간(43채널). **평가 전용(비상업 캡스톤)**, 영상은 Home `~/datasets/{mendeley_mv7,yt_cc}`에만, git에는 라벨·집계만. 장부 `docs/data/sources.md`, 결과 `docs/results/public_eval_data.md`.
- **라벨**: 3 fps 접촉 시트를 AI 라벨러(Claude 서브에이전트) 두 개가 독립으로 봄. 렙 수 정확히 일치 + 자세 키 1개 이상 일치만 채택, 나머지 "uncertain" 제외(렙 386/544세트, 자세 429/544세트 채택). Mendeley md5 중복 13묶음 27클립 전부 제외.
- **분할**: 평가 전에 `data/eval_sources/split.csv` 고정(사람 = Mendeley 피험자, YouTube 채널; seed 20261012, 약 50/50). 검증 목록은 NOTES.md "held-out only"로 pushup-fix 트랙에 전달.
- **근거**(렙 정확도 조정 / 검증, 두 출처 합계): 스쿼트 측면 42.8 / 49.3%, 사선 76.9 / 66.0%, 정면 49.8 / 68.5%; 푸시업 측면 50.3 / 76.3%, 사선 91.8 / 85.8%, 정면 53.9 / 44.2%; 로우 측면 11.5 / 11.4%(Mendeley 덤벨 4–5%, YouTube 바벨 82.6 / 100%). 추가 렙은 386세트에서 +24뿐 — 문제는 놓침. 스쿼트 측면은 unknown ≥ 10% 세트(23/49)가 27.8%, < 10%는 60.9% → 추적 품질(역광·블러 데이터)이 주원인(추정). 셋업 키: 측면 스쿼트·로우 0회, 측면 푸시업 렙 도중 1회.
- **현재 integration(b68ce19, pushup-fix 병합 후) 재측정**(같은 클립): 측면 푸시업 조정 50.3 → 86.5%, 검증 76.3 → 89.4%(추가 렙 그대로) — pushup-fix를 독립 검증 세트로 확인. 스쿼트 측면 검증 49.8 → 47.6%(−5렙, 2세트 subject_009·024, crop 재맞춤 2·12회 — D-T3-10 영향 추정).
- **자세 키(모두 끔 유지)**: pushup_hip_pike 측면만 후보 — 현재 규칙에서 검출 5/6세트(23/46렙), 정상 측면 렙 오경보 2/262(0.8%). 잘못된 세트 6개라 "측면 게이트가 측면일 때만 켜기"를 제안만 함(사선 오경보 9–28%). pushup_hip_sag 검출 2/13세트, head_drop 0/10, squat_shallow 1/32(규칙이 첫 렙 대비라 처음부터 얕은 세트는 못 잡음), squat_knee_valgus 정면 정상 렙 96–98% 오경보, row_torso_swing 측면 3/9세트(센 렙이 적음).
- **기각**: Fitness-AQA(수동 승인 Google Form, 영상은 제3자 YouTube/Instagram), QEVD(Qualcomm ID 로그인 필요 — 사용자 계정으로 받을 것을 제안), EC3D(RGB 없음), FLAG3D·EgoExo-Fitness·MyoMechanix(서명·수동 승인), InfiniteRep(합성), PushUpBench(변형 동작), UCO/KIMORE/UI-PRMD(접근 불가·스쿼트 없음), Kaggle 모음(원본이 표준 라이선스 YouTube), YouTube 표준 라이선스 영상 전부. Home에서의 yt-dlp(봇 확인) → Mac에서 검색·다운로드.
- **한계(추정 포함)**: Mendeley 15 fps를 프레임 복제로 30 fps, 얼굴·몸 블러와 역광으로 관절 신뢰도 0.4–0.6 → 실사용보다 나쁘게 나올 수 있음. 로우는 덤벨이라 바벨 규칙 평가로는 부적합. 라벨은 사람 검수 없음.
- **되돌리기**: 앱 변경 없음. 데이터 폐기 = Home `rm -rf ~/datasets/mendeley_mv7 ~/datasets/yt_cc`, 리포의 `data/eval_sources/`·`scripts/data_collect/` 삭제.


## D-D-07 각도·경고에 쓸 만한 3D 소스: MediaPipe 월드 3D는 기각, Fit3D 미세조정 XS만 "사선 몸통(중력)·엉덩이" 후보 — 앱 기본은 그대로 (2026-10-12)
- **결정(추천만, 앱 변경 없음)**: 라이브 3D 끔(D-D-02)·경고는 2D만 유지. 관절·시점별 판단(기준: 렙 극값 오차 중앙값 ≤ 5° **그리고** p90 ≤ 10°, 경고 문턱 15°대와 가를 수 있는 수준):

  | 관절 | 측면(≤40°) | 사선(56–75°) |
  |---|---|---|
  | 몸통 기울기 | **2D 유지**(Ex3D 1–7°; 미세조정 XS 10–18°로 나쁨) | **미세조정 XS + 중력(가속도계)** 기준만 통과: 스쿼트 3.4 (p90 8.9) / 푸시업 2.7 (6.2) / 로우 4.6 (9.4)°. MediaPipe 13–19°, 원래 XS 14–20°, 2D 30–38° → 불가 |
  | 엉덩이 각(스쿼트 깊이·푸시업 처짐·로우 힌지) | 2D 유지(정답으로 못 잼) | **미세조정 XS** 2.2–3.4° (p90 9–12) — 경계, 후보 |
  | 무릎 | 2D 유지 | 아무것도 통과 못 함: 미세조정 6.1 (p90 17), MediaPipe full 11.9 (23), 2D 20.9 (95) |
  | 팔꿈치 | 2D 유지(측면 푸시업·로우 2D 3–4°) | 통과 없음: 미세조정 6.8–6.9 (p90 16–19), MediaPipe 18–34 |

- **근거**: `docs/results/eval_3d_mediapipe.md`. Fit3D 모캡 정답, **검증 피험자 s07–s11**(60영상, 학습·선택에 안 씀), 앱 2D = RTMPose-m crop.
  - 3D 위치(검증): MPJPE / PA-MPJPE / 가속도 오차 — MediaPipe lite 168 / 104 / 20.3, full 151 / 98 / 17.4, heavy 150 / 101 / 18.5, XS 원래 148 / 89 / 8.6, **XS 미세조정 52 / 38 / 4.5** (mm, mm/프레임²). 조정 s03–s05: MediaPipe 143–155 / 96–100, XS 원래 148 / 95.
  - MediaPipe 월드 3D는 정렬 후에도 관절당 ~10 cm, 떨림 2–4배, 렙 극값 9–36°(p90 20–60°); 팔꿈치는 2D보다 나쁨. lite·heavy가 full보다 낫지 않음. 엉덩이 정의 차이: MediaPipe 엉덩이 폭 0.70–0.76배·7–10 cm 아래, 어깨 폭 1.15–1.20배·3–5 cm 아래(오프셋 표).
  - D-D-06의 "미세조정 몸통이 나빠짐"은 **카메라 위** 기준(사선 9–11°)이었고, **중력** 기준으로는 사선에서 가장 정확(3–5°). 측면(Ex3D)에서는 중력 기준으로도 10–18° → Fit3D에 측면 카메라가 없는 탓(추정).
- **기각**: MediaPipe 월드 3D를 각도·경고에 쓰기(모든 관절·시점에서 기준 미달, D-C-07의 푸시업 2D 후보 판단과는 별개), 원래 XS(사선 엉덩이·로우 팔꿈치 5–6° 외 12–39°), 미세조정 XS를 지금 켜기 — (1) 틀린 자세 영상 검출률 미검증(브리프 4절), (2) 기기 가속도계 중력 경로 없음, (3) 측면 몸통이 나빠 시점별 소스 전환이 필요, (4) 프레임당 +17 ms(D-D-05), (5) Fit3D 유래 가중치 비상업.
- **다음 단계(추천)**: 사선 전용으로 미세조정 XS + 가속도계 중력 몸통을 pose-replay에 붙여 틀린 자세 영상(Mendeley 검증 피험자 등)에서 `torso_swing`·`hip_sag` 검출률을 2D와 비교. 측면 카메라가 있는 3D 정답 데이터로 추가 학습해야 측면 몸통이 해결됨(추정).
- **되돌리기**: 해당 없음(앱 변경 없음). 평가 스크립트만 추가(`scripts/eval_3d_mediapipe.py`).
- **라이선스**: Fit3D(비상업·재배포 금지) — 사용자 본인 Mac·Home에서만, 영상·CSV·MediaPipe 출력·체크포인트 모두 측정 후 삭제, 집계값만 기록. MediaPipe 모델 Apache-2.0(D-C-07과 같은 파일), MotionAGFormer Apache-2.0.

## 트랙 squat-fix — 스쿼트 렙 카운트를 실제 사람에게 일반화 — 2026-10-12
상세 표 `docs/results/squat_fix.md`. 분할 = `data/eval_sources/split.csv`(data-collect가 평가 전에 고정한 사람 단위). 규칙은 조정 세트(스쿼트 72세트)만 보고 정했고 검증(81세트)은 마지막에 한 번 봄. 앱 기본 RTMPose-m COCO17, crop 재맞춤 켬.

### D-T3-13 스쿼트: 근거 없는 프레임은 상태 유지, 가까운 다리, 선 자세 기준선 재설정, 엉덩이 높이 두 번째 렙 신호 (2026-10-12)
- **결정**: `SquatEvaluatorConfig` 네 플래그 기본 켬 — `holdStatusThroughUnknown`(경계 사이 느린 프레임·30프레임까지의 다리 신뢰도 부족은 현재 상태에 투표, `unknown`으로 강제 전이 안 함), `nearLegFallback`(한쪽 다리 엉덩이·무릎·발목만 보여도 그 다리로), `rebaselineStraightLegFrames = 30`(top이 아닌데 무릎이 1초 펴져 있으면 선 자세 기준선을 지금 높이로), `heightRepSignal`(엉덩이 높이 = (발목 y − 엉덩이 y) ÷ 최근 90프레임 최장 다리, `PushUpHeightCounter` 재사용, 범위 ≥ 0.25 다리; 렙 수 = max(상태 기계, 높이), ready-pose가 켜지면 그 뒤부터).
- **진단(조정)**: unknown 프레임의 25.5%만 신뢰도 부족, 나머지는 관절이 다 보이는데 top·bottom 경계 사이에서 느리게 움직여 8프레임 뒤 `unknown`으로 강제 전이 → `unknown → top`은 렙을 안 끝냄. 그 밖에 낡은 선 자세 기준선(첫 프레임 오검출·서는 높이 변화로 세트 내내 `bottom`), 렙 사이 무릎 145° 미만, 측면 먼 다리 신뢰도.
- **근거**(렙 정확도 수정 전 → 후): 조정 전 시점 56.7 → 92.2%(−337 +5 → −43 +20), 측면 43.6 → 92.8%. **검증(한 번)**: 측면 47.1 → **91.8%**(−118 +2 → −12 +7), 사선 67.2 → 96.6%, 정면 68.5 → 93.5%, 전 시점 61.8 → 93.7%(관대 96.2%). 추가 렙은 대부분 영상 끝 부분 렙.
- **회귀**: Exercise3D 세 운동 × 측면·사선·정면 × m·s 표 전체 같음, 흔들림 합성·squat_03·더미 출력 같음(스쿼트 m 0렙, s 3렙은 이전부터), 공개 스쿼트·Exercise3D 셋업 키 같음. MM-Fit 푸시업·Fit3D 로우는 평가기·crop 미변경이라 동일. Fit3D 사선 스쿼트 m: 정답 구간 안 조정 100 → 100%, 검증 99.0 → 100%(s11 낡은 기준선 놓침 해결); **영상 전체 기준은 조정 95.2 → 93.8%, 검증 83.9 → 82.6%** — 늘어난 1·3렙은 전부 세트 전후 바를 바닥에서 들고 내려놓는 동작(구간 밖, D-T3-04와 같은 종류). "Fit3D 사선이 떨어지면 안 됨"을 세트 구간 기준으로 판단한 것(영상 전체 기준으로는 떨어짐 — 판단 근거를 여기 남김).
- **기각**: (1) 근거 없는 프레임이 아예 투표하지 않기(복제 프레임에서도 하강 연속 유지) — 조정 95.0%였지만 흔들림 합성 m에서 서 있는 상태 +1렙. (2) 높이 범위 0.10–0.15 — 흔들림 합성 s 3 → 6렙. (3) 기준선 재설정 15프레임 — 조정 +0.3%p뿐, Fit3D 조정 세트 밖 추가 +1. (4) crop 재맞춤 수정 — D-T3-14. (5) MediaPipe 스쿼트 — D-T3-16.
- **iPhone**: 이 트랙 동안 iPhone 17이 CoreDevice "unavailable"(무선) → 기기 키포인트 재생 못 함. 포즈 단계 코드는 그대로라 기존 Mac=iPhone 키포인트 일치(D-T3-05·D-T3-10, 39/39)는 유지(추정). 남은 iPhone s 키포인트(squat_0000 cam1)는 전후 10/10.
- **되돌리기**: 네 플래그 끄기(pose-replay `--squat-hold off --squat-near-leg off --squat-rebaseline 0 --squat-height off`) — 조정 72세트에서 세트별 렙 수가 수정 전과 같음을 확인. 또는 이 커밋 revert.

### D-T3-14 crop 재맞춤(D-T3-10)은 그대로 둔다 (2026-10-12)
- **근거**: 조정 측면(Mendeley 19세트)에서 재맞춤 끔 42.1% vs 켬 43.0%(수정 전 규칙) — 조정 데이터에선 손해가 없어 고칠 근거가 없음. data-collect가 본 검증 −5렙(subject_009·024)은 새 규칙에서 9/9·11/11로 사라짐, 켬/끔 측면 정확도가 조정 92.9 / 92.9%, 검증 93.5 / 93.5%로 같음.
- **기각**: 재맞춤 히스테리시스·쿨다운 — 증거 없음, 그리고 crop 변경은 세 운동 키포인트 전부를 다시 뽑아 검증해야 함.
- **되돌리기**: 해당 없음(변경 없음).

### D-T3-15 pushup_hip_pike는 계속 끈다 (2026-10-12)
- **근거**: 측면 검출 5/6세트(23/46렙), 정상 측면 렙 오경보 2/262(D-DATA-01). 잘못된 세트가 6개뿐이고 라벨은 AI 2패스 합의뿐(사람 검수 없음). 조정/검증 데이터에 측면 hip_pike 라벨을 더 붙일 세트가 없음(합의된 hip_pike 15세트 중 측면 6). BRIEF 규칙(잘못된 자세 실제 증거가 있을 때만 키 켬)에 못 미침.
- **켜려면**: 사람이 라벨한 측면 hip_pike 세트(사람 2명 이상, 키별 5–8렙)로 검출률을 다시 재고, 측면 게이트가 측면일 때만 켤 것(사선 정상 렙 오경보 9–28%).
- **되돌리기**: 해당 없음.

### D-T3-16 이번에 하지 않은 것: 푸시업 정면, YouTube 바벨로우 사선, MediaPipe 스쿼트 (2026-10-12)
- **푸시업 정면(48%)**: 앱이 측면 촬영을 안내하는 시점이고 정면에서는 다리가 가려 tracking_lost가 거의 항상 울림(D-DATA-01 §3) — 렙을 세게 해도 셋업 안내와 충돌. 우선순위 낮음.
- **YouTube 바벨로우 사선**: 조정 세트가 1개(2렙)라 조정할 데이터가 없음.
- **MediaPipe Pose full로 스쿼트**: RTMPose-m 경로가 조정 92.2%까지 올라 남은 놓침이 적고, D-C-07에서 MediaPipe는 스쿼트·로우 PCK가 더 나빴음. 평가하려면 공개 클립 153개를 Home CPU로 다시 뽑아야 해서 이번엔 생략.

## 트랙 halpe-decision — 운동 카메라 RTMPose-m COCO17 vs RTMPose-m Halpe26 — 2026-10-16
배경: D-01(Halpe26 기본 되돌림), D-C-04(Halpe26 전환은 사용자 결정으로 올림), D-T3-05(운동 카메라 = m COCO17)로, "Halpe26으로 바꾸기로 했다"는 결정은 실행된 적이 없음. 이번 트랙에서 수치로 정함. 캘리브레이션 캡처(`RTMPoseModel.active` = s COCO17)는 범위 밖, 바꾸지 않음.

### D-T3-17 판정 규칙 (검증 결과를 보기 전에 고정, 2026-10-16)
- **비교**: 운동 카메라 기본 m COCO17(현재) vs m Halpe26. s Halpe26은 참고로만 같이 잼. 세 모델 모두 같은 현재 규칙(D-T3-13 스쿼트, D-T3-10/11 푸시업, D-T3-01/03 로우, crop 입력, crop 재맞춤 켬, ready-pose 끔, 3D 없음)을 같은 pose-replay 바이너리로.
- **검증(held-out) 세트**(이미 고정된 분할 그대로): 공개 데이터 `data/eval_sources/split.csv`의 heldout(Mendeley + YouTube CC), MM-Fit 푸시업 D-T3-09 검증 6명 18세트, Exercise3D P2·P3(푸시업은 P1뿐이라 검증 없음), Fit3D s07–s11(사선). 조정 세트(공개 tuning, MM-Fit 조정 9명, Exercise3D P1, Fit3D s03–s05)는 같이 표에 싣지만 판정에 쓰지 않음.
- **m Halpe26으로 바꾸는 조건(모두 만족해야 함)**:
  1. 검증 렙 정확도가 **운동 × 측면** 칸마다 낮아지지 않음 — 측면 검증 데이터가 있는 출처(공개, MM-Fit, Exercise3D)별로 각각, 그리고 출처 합계로.
  2. 검증 전체 렙 정확도(모든 출처·시점 합산: Σ(정답−놓침) ÷ Σ(정답+추가))가 **더 높음**.
  3. 가짜 렙 0 유지: 흔들림 합성(소스 4개 × 11조건, 그 모델의 키포인트로 만듦), squat_03(정답 2 — 2를 넘으면 가짜 렙), 더미 영상 6개, 스쿼트·로우 평가기.
  4. 셋업 키 오경보가 늘지 않음: 앱에서 켜진 키(setup_full_body·tracking_lost 전 운동, setup_side_view 로우만)의 실제 영상 전체(모든 출처·분할·시점, 합성·더미 제외) 합계가 m COCO17 이하.
  5. iPhone 속도: 영상 입력 전체 파이프라인(`tools/pose_model_bench/run_pipeline.sh`, 30 fps 페이스)에서 p95 지연 ≤ 33.3 ms이고 놓친 프레임이 m COCO17(D-C-06: 0)보다 의미 있게 많지 않음(0.1% 이하). 기기를 1시간 동안 못 쓰면 "미측정"으로 두고, D-C-05(추론 m COCO17 3.31 ms vs m Halpe26 3.29 ms)대로 같은 속도로 봄.
- **렙 정확도 계산**(출처별, 세 모델 같은 방식): 공개·MM-Fit = 세트 렙 수(놓침 = max(0, 정답−셈), 추가 = max(0, 셈−정답), 공개는 엄격 기준 — 관대 기준은 참고), Exercise3D = 정답 저점과 렙 끝을 순서대로 맞춤(`eval_pose2d_reps.py`, analyze.py), Fit3D = 영상 전체 세트 렙 수(정답 = rep_ann 경계 수 − 1, 50 fps 원본, 시점 40–75°만 사선). 시점: 공개는 라벨의 side/diag/front/back, Exercise3D·Fit3D는 각도(측면 ≤40°, 사선 40–75°, 정면/후면 ≥75°).
- 하나라도 어기면 m COCO17 유지, 어긴 조건을 수치로 적음. 어느 쪽이든 두 모델 모두 플래그(`BPT_POSE_MODEL`, pose-replay `--model`)로 고를 수 있게 둠.
- 발뒤꿈치: Halpe26 발뒤꿈치 PCK와 squat_heel_rise 평가 가능성은 측정만. 틀린 자세 데이터가 없으면 키는 OFF(D-03).

### D-T3-18 운동 카메라 기본은 m COCO17 유지 — m Halpe26은 측면 푸시업 검증에서 떨어짐 (2026-10-17)
- **결정**: `RTMPoseModel.workout` = m COCO17 그대로(`workoutUsesMediumModel = true`). m Halpe26은 번들에 넣고 `BPT_POSE_MODEL=mhalpe26` / pose-replay `--model mhalpe26` / `run_pipeline.sh f`로 고를 수 있게 함. 캘리브레이션(`RTMPoseModel.active` = s COCO17)은 손대지 않음. 표 전체 `docs/results/halpe_decision.md`.
- **D-T3-17 조건별** (m COCO17 → m Halpe26, 검증):
  1. 운동 × 측면: 스쿼트 공개 91.8 → 96.1%, Exercise3D 100 → 100% / 로우 공개 11.4 → 11.4%, Exercise3D 100 → 100% / **푸시업 공개 89.4 → 90.4%, MM-Fit 94.5 → 91.1%(−7 +3 → −15 +1), 합계 91.8 → 90.7% → 불통과.**
  2. 검증 전체(모든 출처·시점): 71.8 → 72.8% → 통과.
  3. 가짜 렙: 흔들림 합성 44건·squat_03(2/2)·더미 6개 모두 0 → 통과.
  4. 셋업 키 알람(실제 영상 전체): 232 → 199 → 통과(측면만은 5 → 7).
  5. iPhone 17 페이스 30 fps: p95 21.5 ms(m COCO17 30.0–33.0), 놓친 프레임 0–7(m COCO17 0–63) → 통과.
- **불통과 원인**: MM-Fit 검증 w20_s3에서 m Halpe26이 1렙(정답 10, m COCO17 10) — 세트 내내 관절 신뢰도 중앙값 0.10–0.22(m COCO17 0.48–0.86)이고 상태가 `unknown`에서 안 나옴, setup_full_body 1회. 사람·crop을 잘못 잡은 추적 실패로 보임(추정, D-C-03의 사람 선택 문제와 같은 종류). w20_s2 10 → 8, w13_s2 12 → 10(추가 2 감소)도 있음. 조정 세트에서도 MM-Fit 98.1 → 97.3%, Exercise3D 조정 98.7 → 97.1%(사선 푸시업·후면 로우), 공개 스쿼트 측면 조정 92.8 → 87.3%로 m Halpe26이 낮은 칸이 있어 "검증에서만 운이 나빴다"고 보기도 어려움.
- **m Halpe26이 나은 점(기록)**: 2D 정확도(Exercise3D 측면 body12 PCK 0.935 vs 0.864), 공개 측면 스쿼트 검증 +4.3%p, Fit3D 사선 검증 85.6 → 88.3%(스쿼트·푸시업 추가 렙 감소), 공개 정면 푸시업 47.9 → 53.9%, 셋업 알람 −33, 페이스 지연이 더 낮음, 발뒤꿈치 PCK 0.955(측면).
- **발뒤꿈치**: squat_heel_rise는 검증 세트에 틀린 자세가 0개이고, 조정 3세트에서도 heel_rise_max가 정상 렙보다 작아 가르지 못함 → OFF 유지(D-03).
- **기각**: m Halpe26 기본 전환(조건 1 불통과 — 규칙대로), 측면 푸시업만 COCO17·나머지 Halpe26 혼합(검증 결과를 보고 만든 규칙이라 과적합, 이번 범위 밖).
- **다시 볼 것**: w20_s3 같은 추적 실패를 crop 재확인(D-B-03)이 왜 못 잡는지 — 고치면 m Halpe26 재평가 후보. 그때는 새 검증 데이터로.
- **되돌리기/켜기**: m Halpe26을 기본으로 쓰려면 `RTMPoseModel.workout`의 기본 케이스를 `.mhalpe26`으로(한 줄), 시험은 Xcode scheme `BPT_POSE_MODEL=mhalpe26`(캘리브레이션도 같이 바뀜 — 기존 덮어쓰기 규칙).

### D-T3-18 정정 (2026-10-17, 사용자 지시)
- **사용자 결정**: 운동 기본은 RTMPose-m COCO17 유지. Halpe26의 최종 채택·기각은 **결정하지 않음**(보류). 위 D-T3-17 판정 규칙과 D-T3-18 "결정"은 에이전트가 정한 것으로 사용자 승인을 받지 않았음 — 공식 채택 기준이 아니라 실험 기록으로만 봄.
- **앱 구성**: m Halpe26(`rtmpose_m_halpe26_forward.mlpackage`, 27.8 MB)을 Runner 번들·pbxproj·`RTMPoseModel`에서 뺌(사용자 지시). 실험용 사본은 git 밖 `~/bpt-models/rtmpose_m_halpe26_forward.mlpackage`, 결과는 `docs/results/halpe_decision.md` 그대로. 재실험: pose-replay `--model halpe26 --model-path ~/bpt-models/rtmpose_m_halpe26_forward.mlpackage`, iPhone 속도는 벤치 앱 `run_pipeline.sh f`(extra models). s Halpe26은 10/9 사용자 지시("설정으로 켤 수 있게 유지")대로 남김.
- **w20_s3 원인**: "사람 추적 실패"는 **검증 안 된 가설**(신뢰도·상태만 관찰). 같은 crop·검증된 bbox·프레임별 분석으로 원인 분리 중 — 결과 전에는 Halpe26 결론 없음.

## D-D-09 실시간 3D(MotionAGFormer-XS) 앱 통합 — 조사 결과와 추천만, 결정 아님 (2026-10-19, ai/lift-app)
상세: `docs/results/lift_app.md`, 계획·운동별 명세 `docs/results/lift_app_plan.md`. **아래는 사실과 제안이고, 승인된 결정이 아니다.**
- **왜 없었나(검증됨)**: 카메라 경로에는 3D 실행 코드가 처음부터 없었다(`a949023`부터 `enableMotion3DForCamera = false`, 어떤 브랜치에서도 true였던 적 없음, XS mlpackage는 Runner에 들어간 적 없음). 꺼 둔 것은 에이전트 결정(D-D-02/05/06/07, D-C-06, D-D-08)이고, 사용자 메시지(218개 검사)에 3D를 끄라는 지시는 없다. 사용자 지시는 2026-10-09 "경고 발동은 일단 2D 기준" · "푸쉬업은 3D 지표 판정 제외(2D만)"(경고 기준, 3D 실행이 아님)와 2026-10-19 "3D Lifting을 제거하거나 비활성화하지 마라".
- **ai/lift-app에 구현한 것(이 브랜치 한정, 병합 안 함)**: 과거 프레임만 쓰는 27프레임 XS(L=5, 프레임 t의 2D·3D를 함께 평가기로), 상태 warming_up/tracking_lost/bad_3d/ok를 평가기·Flutter에 명시, 해부학 제약(뼈 길이 → 무릎 깊이 뒤집힘 감지 → 관절 내각 한계), 3D 자세 판정(같은 규칙을 3D 지표로, 3D 없는 렙은 판정 불가로 표시하고 2D로 대체하지 않음, 2D 판정은 비교용 로그), MediaPipe 손목 → XS 입력(0.25×아래팔 게이트), 선택적 중력 "위"(BPT_3D_GRAVITY=1, 기본 끔). `enableMotion3DForCamera = true` + XS mlpackage 번들(4.9 MB)은 이 브랜치만.
- **정확성(검증됨, Fit3D 검증 피험자)**: Core ML = PyTorch(MPJPE 차 < 1 mm). 마지막 행(L=0)도 창 가운데(L=13)보다 MPJPE 2.6 mm 나쁠 뿐, 바뀌는 것은 떨림(L 0 → 5에서 −16%). 무릎 과신전 감지가 정상 프레임에서 걸리는 원인은 임계값·축이 아니라 XS가 무릎 깊이를 반대로 놓는 것(걸린 다리 100%). 해부학 제약은 정확도를 거의 바꾸지 않고(MPJPE ±1 mm, PA −1.3 mm) 떨림을 약 5% 늘린다 — 각도 오차를 줄이지 못한다. MediaPipe 손목 교체는 RTMPose 손목보다 2D·3D 모두 조금 나쁘다(교체 프레임 5.8 vs 4.1 px, 손목 떨림 +9%).
- **종단(같은 앱 2D, 실험 B)**: 렙 수는 모든 세트에서 2D와 같음(렙 카운트는 아직 2D). 3D 판정은 검출률이 2D와 거의 같고(공개 검증, 미검증 라벨, 잘못 세트 1–13개), 오경보가 푸시업 머리(30 → 4%)·엉덩이 들기(15 → 11%)에서 줄고 스쿼트 무릎 모임(38 → 43%)·락아웃(14 → 17%)에서 늘었다. 푸시업 렙의 23%(공개)·26%(MM-Fit)는 bad_3d(무릎 깊이 뒤집힘) 때문에 3D 판정 불가.
- **속도(iPhone 17, 영상 입력 전체 파이프라인, 카메라 캡처·미리보기·Flutter 제외)**: lift-app 경로(m + 손 + 라이브 XS 비동기) 30 fps 페이스 29.95 fps, 놓친 프레임 4/3,600, 처리 p95 26.9 ms(예산 33.3 ms), 입력→판정 지연 p50 193 / p95 199 ms(그중 lookahead 167 ms), XS+제약 5.8 / 7.6 ms, 프로세스 CPU 54%. 무제한 57 FPS(2D만 116; 손이 XS보다 비쌈). cadence 2는 이득 없이 지연 p95 +35 ms, 동기 실행은 처리 p95 30.7 ms. GPU/ANE 사용률·장시간 발열·실제 카메라 앱은 측정 안 함.
- **추가 검증(0dda987)**: 무릎 깊이 뒤집힘을 엉덩이–발목 선 반사로 고치면 스쿼트는 17/17 모캡에 가까워지지만 푸시업은 40%(검증)·30%(조정)만 가까워져 스쿼트에서만 켬(S6). XS 출력이 골반 기준이라 3D 엉덩이 높이가 항상 0이던 버그를 고침(높이는 2D 보조 신호). 정상 렙(Fit3D)에서 현재 규칙이 XS 출력으로 울리는 비율: pushup_hip_pike 81%, head_up 22%, no_lockout 12%, squat_no_lockout 12–18%, 3D 무릎 모임(< 1.0) 87–100% — 2D 임계값은 3D에 그대로 못 씀. 후보 임계값(정상 XS 렙의 1%/5% 초과값)은 lift_app.md S7 표, 확정 아님.
- **추가 검증(a03ddd9, 2026-10-20)**: 지표별 3D 무효화(믿을 수 없는 관절만 NaN, 상태 partial_3d)로 푸시업 “3D 판정 불가” 렙이 199 → 26으로 줄었다(MM-Fit 46 → 0, 공개 검증 119 → 25). 대신 판정 렙이 늘어 푸시업 오경보가 늘었다(head_up 4 → 9%, no_lockout 17 → 23%). 푸시업 무릎 θ<−30°의 원인은 깊이 거울상이 아니라 2D에서 펴진 저신뢰(주로 먼 쪽) 다리를 XS가 과굽힘한 것이고(T2), 학습 없는 고치기 중 각도 오차를 줄이는 것은 없었다. lookahead 3은 5보다 MPJPE +0.6 mm·떨림 +3%, 오경보 ±3%p(T3). 시뮬레이터 빌드 실패는 깨끗한 integration/ai에서도 재현(Xcode 27.1 도구 문제).
- **미세조정 XS 재현본(T4, Fit3D 유래·비상업)**: Fit3D 검증 MPJPE 144.7 → 56.3 mm, 무릎 렙극값 17.1 → 4.9°, 무릎 뒤집힘·무효 관절 0. 앱 경로 다른 데이터에서는 무효 관절이 Ex3D 푸시업 15 → 0%지만 MM-Fit 26 → 22%로 일반화는 미확인. pushup_no_lockout 오경보는 12 → 24%로 늘어 임계값은 모델별로 다시 정해야 함. 채택·번들은 하지 않음(사용자 결정, 라이선스).
- **추천(제안, 승인 필요)**: (1) integration에서 3D 켜기·XS 번들은 iPhone 30 fps 페이스 측정이 예산 안일 때 사용자 결정으로, (2) bad_3d를 프레임 전체가 아니라 지표별로(무릎 깊이 뒤집힘은 무릎·엉덩이 각만 무효) 바꾸기, (3) 3D 판정 임계값은 2D 값을 옮긴 것이므로 3D 정상 렙 분포로 다시 정하기(특히 squat_knee_valgus), (4) 손목 교체는 이득이 확인될 때까지 RTMPose 손목을 쓰는 안을 사용자에게 묻기(사용자 요구는 "손목 교정 단계가 동작해야 함"이라 끄지 않고 게이트로 둠), (5) 렙 카운트에 3D 확인 신호(P2), (6) 중력 축 매핑을 기기에서 확인한 뒤 BPT_3D_GRAVITY 켜기, (7) 사람이 검수한 틀린 자세 영상 확보.
- **되돌리기**: 브랜치 미병합 — integration 영향 없음. 이 브랜치에서 3D를 끄려면 Xcode scheme `BPT_CAMERA_3D=0`.

## main 병합 — 2026-10-20

### D-M-01 충돌 파일은 main(팀원) 버전을 쓴다 (2026-10-20, 사용자 지시)
- **사용자 결정**: "팀원 메인쪽이 더 중요함". origin/main(`52c2f61`, #35–#61)을 integration/ai에 병합하고, 충돌 난 Dart 파일 4개는 main 버전을 그대로 쓴다: `native_pose_workout_screen.dart`, `kori_feedback_lines.dart`, `onboarding_analyzing_screen.dart`, `test/onboarding_analyzing_test.dart`.
- **예외**: `ios/Runner.xcodeproj/project.pbxproj`는 양쪽 등록을 다 남긴다(`WorkoutSessionBridge.swift`와 main의 `KoriSpeaker.swift`). 우리 줄을 빼면 네이티브 빌드가 깨지고, 팀원 동작은 바뀌지 않는다.
- **결과로 빠진 것**(다시 넣으려면 main 화면 위에 새로 얹는다):
  - 운동 화면: onFeedback 답(네이티브 WorkoutVoice 대사), startSet/endSet 알림(세트 요약 경고·세트별 녹화·onSetEnd), 음소거 버튼의 네이티브 연결. 음성은 main의 `KoriVoiceService`(ElevenLabs) 하나만 남는다 — E7의 (b) 쪽. WorkoutVoice는 답이 null이라 말하지 않는다.
  - main 화면의 임시 데모 경고(`_advanceDemoFeedback`, 렙마다 칭찬 ↔ 운동별 대표 경고)는 남는다. 네이티브는 기본으로 setup_full_body·tracking_lost만 보내서 데모가 계속 돈다. 팀원에게는 사용자가 직접 전달하기로 함.
  - 분석 화면: 작업 상태 polling·진행률·실패 문구·결과 요약. 앱은 업로드만 하고 40초 뒤 결과 화면(자리표시)으로 간다. 서버 분석은 그대로 돈다. `CalibrationUploadService.fetchJob`은 남아 있다.
  - `ai/lift-app`의 3D 상태 안내(운동 화면 변경)는 main 화면 위에 다시 얹어야 한다.
- **확인**: `flutter analyze` 문제 없음, `flutter test` 98 통과, `flutter build ios --debug --no-codesign`(아래 병합 커밋 기준).

### D-M-02 main 업데이트: integration + 오늘 끝난 수정 (2026-10-20, 사용자 지시)
- **사용자 결정**: "메인을 업데이트하라" → 선택지 "integration + 오늘 끝난 수정". 아래를 integration/ai에 병합한 뒤 main을 integration/ai로 빨리감기(일반 push).
  - `ai/real-feedback` a938ab1: 데모 경고 제거, 실제 판정 경고 기본 전달(FormCommonConfig.enabledFeedbackKeys = Flutter 대사가 있는 모든 키), startSet/endSet 복구. 판정 임계값은 그대로(임시값).
  - `ai/calib-voice-calm` 47cb42d: 촬영 음성 1초 안정 후 말하기, 대사 사이 1.5초 쉼.
  - 운동 화면 자동 잠금 끔(`ai/lift-app` 0a4d830을 integration 코드에 맞게 옮김, 카메라가 도는 동안만, 멈춤·백그라운드에서 원래 값).
  - `ai/teammate-notes` 4bba51a: docs/handoff/teammate_requests.md, PR 초안 갱신.
- **제외**(검증 중): 3D 켜기·XS 번들(`ai/lift-app`), 새 뼈대 화면(`ai/lift-refine`), 가림 보정·준비 자세(`ai/setup-constraint`), 파인튜닝(`ai/finetune3`), 운동 중 대기 문구 변경(6a78a29, 사용자가 다른 사양을 줌).

## D-D-10 3D 보정 다듬기 — 관절 각 한 설정·무릎 과신전 클램프·사람별 뼈 길이 목표·손 crop 중복 제거·오버레이 (2026-10-20, ai/lift-refine) — 제안, 결정 아님
상세: `docs/results/lift_refine.md`(판정 규칙은 결과 전에 d305a49로 고정).
- **관절 각 한계**: 값은 `pose_feedback/geometry/anatomical_limits.json` 한 곳(근거 포함), Swift는 같은 값(테스트로 강제). 내각 한계는 384e684 값 그대로(이미 모캡 p0.1/p99.9였다 — 작업 지시의 “느슨하다”는 ed67a6e 값 이야기). 새로 넣은 것은 **무릎 과신전 클램프 θ ≥ −15°**(CDC 정상 폄 평균 1.0–1.6°, Beighton > 10°, Fit3D 세 운동 −10° 아래 없음): 뒤로 꺾인 무릎이 출력에 남지 않는다. θ < −30° 무효 표시·스쿼트 반사는 그대로.
- **사람별 뼈 길이**: 제품 캘리브레이션(SAM 3D Body → MHR→SMPL β 공유 → H36M 길이)을 로컬 CPU로 재현(`scripts/calib_subject_shapes.py`, 데이터는 Home/Mac 밖으로 안 나감). 키를 몰라 키 투영은 생략 — 제약은 비율만 쓰므로(프레임마다 s = median(관측/목표)) 단위·키가 상쇄됨. 앱(영상 모드) `BPT_BONE_TARGETS`, pose-replay `--bone-targets`. 실제 앱은 아직 결과를 안 받는다(D-M-01).
- **손 crop 중복 제거**: 두 crop의 손 랜드마크 상자 IoU > 0.5면 두 MediaPipe 손목 모두 버림(`BPT_HAND_DEDUPE=0`으로 끔). 몸 오버레이 손목 = XS 입력 손목(거른 뒤).
- **오버레이**(사용자 기기 피드백 2회 반영): 몸만 빛나는 선(얼굴·머리·손 안 그림), 저신뢰 숨김, 기본 연두, 연결마다 규칙 지표의 연속 색(연두→주황→빨강), 3D가 불확실하면 흐린 연두(빨강 안 됨) — 표시 전용, 판정·임계값 그대로.
- **발 고정**: ai/setup-constraint로 넘김(코드 없음).
- **검증 상태**(Fit3D 검증 s07–s11, 사전 규칙 d305a49; Home 재부팅 뒤 다시 돌림): 무릎 과신전 클램프 R-LIMITS 통과(불가능 각 프레임 0.97% → 0, 정확도·규칙 그대로) → 효과 검증됨. 캘리브레이션 목표 R-BONE 통과(세션 중앙값 대비 PA −1.87 mm) → 효과 검증됨이지만 모집단 비율만 써도 PA −2.57 mm로 더 좋음(사람별 정보의 이득은 확인 안 됨). 손 crop 중복 제거·오버레이 손목은 lift_refine.md §5.3.
- **되돌리기**: `kneeClampDegrees = nil`, `BPT_HAND_DEDUPE=0`, 오버레이는 커밋 revert.
