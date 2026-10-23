# 규칙 수정 — no_lockout 측정 구간, 무릎 모임 정면 판정 (ai/rules-fix-mf953336)

> 근거: `docs/results/ex3d_form_labels.md` (ai/ex3d-form-labels ec95c54, AI 시각 라벨, 사람 라벨 아님).
> 끈 6개 키(D-M-04)는 계속 끈 채로 둔다. 판정 로직만 고친다. 다시 켜는 것은 사용자 결정이다.

## 1. 사전 등록 (결과를 보기 전, 이 절을 먼저 커밋)

### 1.1 바꾸는 것
1. **squat_no_lockout / pushup_no_lockout — 측정 구간**
   - 지금: 렙 구간(beginRep → finishRep) 안의 최대 무릎·엉덩이(스쿼트) / 팔꿈치(푸시업) 각도가 세트 최대보다 10° 넘게 작으면 울린다. 렙 구간이 위 자세 전에 끝나서 락아웃을 보지 못한다(ex3d_form_labels A7).
   - 바꾼 뒤: 이번 렙의 바닥(렙 안 최소 무릎 / 팔꿈치 프레임)부터 **다음 렙이 시작될 때(beginRep)까지**, 세트 끝이면 `endSet`까지의 2D 프레임에서 최대각을 잰다.
     - 스쿼트: `knee_lockout_max < T_knee` 또는 `hip_lockout_max < T_hip`.
     - 푸시업: `elbow_lockout_max < T_elbow`.
   - **절대 기준**이다. 세트 최대 대비가 아니다. 첫 렙도 판정한다.
   - 시점 게이트는 그대로다(렙의 `front_view_fraction < 0.5`만 판정).
   - 참고(set) 등급이라 말하는 시점은 원래도 세트 끝이다. 그래서 판정을 다음 렙 시작까지 미뤄도 전달은 바뀌지 않는다.
2. **squat_knee_valgus — 정면 판정**
   - 지금: 렙 프레임 중 어깨 폭 / 몸통 길이 ≥ 0.5인 비율(`front_view_fraction`)이 0.5 이상이면 정면으로 보고 판정한다.
   - 바꾼 뒤: 위 조건에 더해, **서 있는(top) 프레임** 최근 150개의 어깨 폭 / 몸통 길이 중앙값(`standing_shoulder_ratio`)이 `R` 이상일 때만 판정한다. 30프레임이 모이기 전에는 판정하지 않는다.

### 1.2 기준값을 정하는 규칙
- **T_knee, T_hip, T_elbow**: Exercise3D **P1(튜닝)** 렙 중 AI 라벨이 락아웃 ok이고 측면 게이트를 통과한 렙의 새 지표 **최솟값 − 5°를 5° 단위로 내림**한다.
  - 입력: 기기 실행(a8b29f1, m Halpe26) 로그의 프레임별 2D 키포인트를 integration/ai pose-replay(2D 판정)에 그대로 넣은 결과.
  - T가 150° 아래로 나오면 "검출 의미가 없는 느슨한 규칙"으로 보고, 켤 후보로 쓰지 않는다고 적는다.
- **R**: P1 카메라별 서 있는 프레임 어깨 비율 중앙값으로 정한다. `R = (P1 중 45° 이하 카메라의 최댓값 + P1 중 50° 이상 카메라의 최솟값) / 2`.
  - 공개: 이 값을 정하기 전에 카메라별 시점 신호 표(어깨 비율, 아래 2.2)와 수정 전 2D 무릎 모임 발화 수는 봤다. 수정 후 결과는 보지 않았다.
  - P1 값: 45° 이하 0.23–0.36(최대 0.36), 50° 이상 0.48(63.1°)·0.54(66.3°) → **R = 0.42**.
- 다른 기준값은 바꾸지 않는다.

### 1.3 평가와 성공 기준
- 평가 데이터
  - Exercise3D 37클립(기기 로그 2D, 위와 같은 입력). 스쿼트 P2(squat_0002)는 held-out이다. 푸시업에는 held-out 사람이 없어 in-sample이다.
  - 공개 held-out(rules-calib `public_held_own_v1`, Halpe26 2D CSV) `good` 스쿼트·푸시업 클립: 정상 렙 오경보 변화.
  - 기기 3D 판정(lift-app) 무릎 모임: 기기 로그의 `warnings_3d`에 새 시점 게이트를 같은 2D 키포인트로 적용해 다시 센다.
- 성공 기준
  1. 라벨 ok 렙에서 squat_no_lockout 발화 ≤ 1, pushup_no_lockout 발화 ≤ 1(수정 전 기기 13·7).
  2. 45° 이하 카메라에서 squat_knee_valgus 발화 0(2D 재생과 기기 3D 모두).
  3. 진짜 뒤 카메라(79°, squat_0002_cam3)의 무릎 모임 판정 렙 수와 발화 수가 수정 전과 같다.
  4. 공개 held-out good 클립에서 세 키의 판정 렙 대비 발화율이 수정 전보다 2%p 넘게 늘지 않는다.
  5. 다른 키의 발화는 렙마다 수정 전과 같다.
- 한계(미리 적음): 틀린 자세 렙이 없어서 검출(잡아내는 능력)은 이 데이터로 보일 수 없다.

### 1.4 사전 등록 추가 — 엄격도 모드 새 지표 (2026-10-23, 지표 분포를 보기 전)
- 사용자 결정(조정자 전달): 엄격도 모드 PT 엄격 / 표준 / 여유. 엄격 모드 전용 새 지표 둘. 기본(표준)은 기록만.
- `elbow_flare_at_bottom`(푸시업, 3D): 렙 바닥(최소 팔꿈치 프레임)에서 위팔(어깨→팔꿈치)과 몸통(흉곽→골반) 사이 3D 각도. PT 기준 약 45°.
- `head_trunk_at_bottom`(푸시업, 2D): 렙 바닥에서 어깨→귀 선이 엉덩이→어깨 선보다 바닥 쪽으로 꺾인 각도(+ = 머리 처짐). 렙 안 변화가 아니라 절대값.
- 기준값 규칙: Exercise3D 2차 PT 라벨에서 두 항목은 푸시업 50렙 모두 tip이다(팔꿈치 약 60°, 목 약 25–30° 굽힘). good 렙이 없으므로 ex3d_form_labels_strict.md 5절의 한 등급 규칙을 그대로 쓴다: **엄격 T = 측면 게이트를 통과한 tip 카메라 렙 지표의 p10**(tip의 90%를 잡는 값). 오경보율은 모른다 → "잠정(근거 부족)".
  - 입력: 기기 2D 키포인트(m Halpe26) → pose-replay, 3D는 같은 키포인트를 원래 XS(`assets/coreml/motionagformer_xs.mlpackage`, pose-replay `lift3D`)로 올린 것. 기기의 MotionAGFormerLive와 같은 경로는 아니다.
  - 엘보 벌림 T가 PT 기준 45°보다 작게 나오면 45°를 쓴다(정상 동작까지 울리게 하지 않는다).

## 2. 결과 (사전 등록 뒤)

### 2.1 요약 (쉬운 말)
- **두 no_lockout 키는 Exercise3D에서 고쳐졌다.** 라벨상 다 일어선(편) 렙에서 squat_no_lockout 8 → 0, pushup_no_lockout 19 → 0(integration/ai 2D 판정). 성공 기준 1 통과.
- **무릎 모임은 45° 이하 사선 카메라에서 더 이상 판정하지 않는다.** 2D 판정 1 → 0, 기기 3D 판정(시뮬레이션) 15 → 0. 성공 기준 2 통과.
- **뒤 카메라(79°)는 발화가 같고(0 → 0), 판정 렙이 10 → 9다.** 첫 렙 때 서 있는 프레임이 30개가 안 모였기 때문이다. 성공 기준 3은 발화는 통과, 판정 렙 수는 1 차이(사전 등록대로 30프레임 규칙을 바꾸지 않았다).
- 공개 held-out good 클립의 오경보는 셋 다 줄었다(성공 기준 4 통과). 다른 키 발화는 1,591렙 모두 같다(기준 5 통과).
- **검출은 여전히 증명되지 않았다.** 틀린 자세(덜 일어섬, 무릎 모임) 렙이 Ex3D에 없고, 공개 데이터에서 no_lockout 라벨이 붙은 bad 클립은 재생 CSV가 없다(2.6).
- 6개 키는 그대로 기본 전달 꺼짐이다(D-M-04).

### 2.2 원인 확인 — front_view_fraction이 사선을 정면으로 본 이유 (2D 어깨 폭 / 몸통 길이, 기기 m Halpe26 키포인트)
| 클립 | 카메라 각(측면 0°) | 렙 안 프레임 중앙값(렙별 범위) | 렙 안 ≥ 0.5 비율 | **서 있는(top) 프레임 중앙값** |
|---|---|---|---|---|
| squat_0003_cam1 | 17.5 | 0.25–0.30 | 0.00 | 0.23 |
| squat_0001_cam1 | 27.4 | 0.40–0.46 | 0.00–0.16 | 0.31 |
| squat_0002_cam2 (P2) | 31.1 | 0.29–0.36 | 0.00 | 0.28 |
| squat_0000_cam2 | 31.8 | 0.36–0.42 | 0.00–0.02 | 0.32 |
| squat_0001_cam2 | 33.8 | 0.47–0.55 | 0.11–0.89 | 0.36 |
| squat_0000_cam1 | 36.6 | 0.43–0.50 | 0.04–0.49 | 0.34 |
| squat_0002_cam1 (P2) | 39.6 | 0.49–0.53 | 0.44–0.68 | 0.36 |
| squat_0001_cam3 | 63.1 | 0.50–0.54 | 0.54–1.00 | 0.48 |
| squat_0000_cam3 | 66.3 | 0.57–0.61 | 1.00 | 0.54 |
| squat_0002_cam3 (P2) | 79.1 | 0.57–0.60 | 1.00 | 0.55 |
- 렙 안에서는 상체가 앞으로 숙여져 2D 몸통 길이가 짧아진다. 그래서 어깨 비율이 커지고, 34–40° 카메라가 0.5 선을 넘는다. 39.6°와 63.1°의 렙 안 값이 겹친다(0.49–0.53 vs 0.50–0.54).
- 서 있는 프레임으로 재면 40° 이하 0.23–0.36, 63° 이상 0.48–0.55로 갈린다. R = 0.42(사전 등록 규칙, P1만으로 계산).
- 공개 held-out 스쿼트(서 있는 프레임 중앙값): side 0.03–0.15, diagonal 0.37–0.64, front 0.63–0.92. front는 모두 게이트를 통과한다.

### 2.3 락아웃 기준값 도출 (P1, 측면 게이트 통과, 라벨 락아웃 ok)
| 지표 | 렙 | 최솟값 | 중앙값 | 규칙(최솟값 − 5°, 5° 내림) |
|---|---|---|---|---|
| knee_lockout_max | 44 | 174.3° | 178.8° | **165°** |
| hip_lockout_max | 44 | 167.7° | 174.5° | **160°** |
| elbow_lockout_max | 100 | 155.4° | 168.3° | **150°** |
- 셋 다 150° 이상이라 사전 등록의 "너무 느슨함" 조건에 걸리지 않는다.
- P2(held-out) 스쿼트 11렙: 무릎 최솟값 175.0°, 엉덩이 168.6° → 기준 아래로 내려간 렙 없음.

### 2.4 Exercise3D 37클립, 라벨 ok 렙 — 수정 전 / 후 (integration/ai pose-replay 2D 판정, 기기 키포인트)
"판정"은 그 키의 시점 게이트를 통과한 렙, "발화"는 그중 울린 렙이다.

| 키 | 묶음 | 수정 전 판정 / 발화 | 수정 후 판정 / 발화 |
|---|---|---|---|
| squat_no_lockout | 전체(모두 ≤ 45° 카메라) | 55 / 8 | 55 / **0** |
| | P1 / P2 | 44 / 4 · 11 / 4 | 44 / 0 · 11 / 0 |
| squat_knee_valgus | ≤ 45° | 15 / 1 | **0 / 0** |
| | 50–66° | 20 / 2 | 20 / 2 |
| | 79°(뒤) | 10 / 0 | 9 / 0 |
| pushup_no_lockout | ≤ 45° | 90 / 17 | 90 / **0** |
| | 48° | 10 / 2 | 10 / 0 |
- 이 2D 판정의 수정 전 발화(8·19)는 기기 3D 판정(13·7, ex3d_form_labels A3)과 숫자가 다르다. 판정 경로가 다르기 때문이다(아래 2.5, 4).

### 2.5 기기 3D 판정(lift-app a8b29f1) — 새 무릎 모임 게이트를 같은 2D 키포인트로 적용
| 묶음 | 수정 전 판정 / 발화 | 새 게이트 판정 / 발화 |
|---|---|---|
| ≤ 45° | 15 / 15 | **0 / 0** |
| 50–66° | 20 / 1 | 20 / 1 |
| 79°(뒤) | 10 / 0 | 9 / 0 |
- 수정 전 숫자는 ex3d_form_labels A3(15/15, 1/20, 0/10)과 같다.
- 3D no_lockout은 이 시뮬레이션에 넣지 않았다. 기기 로그에 프레임별 3D가 없고, 3D 각도에는 2D 기준값을 그대로 쓸 수 없다.

### 2.6 공개 held-out(rules-calib public_held_own_v1, Halpe26 2D)
good 클립(저자 라벨 정상):

| 키 | 시점 | 클립 | 렙 | 수정 전 판정 / 발화 | 수정 후 판정 / 발화 |
|---|---|---|---|---|---|
| squat_no_lockout | side | 9 | 122 | 122 / 67 | 122 / 25 |
| | diagonal | 10 | 129 | 7 / 1 | 7 / 0 |
| squat_knee_valgus | diagonal | 10 | 129 | 122 / 60 | 117 / 57 |
| | front | 10 | 142 | 142 / 75 | 137 / 73 |
| pushup_no_lockout | side | 9 | 101 | 101 / 20 | 101 / 8 |
| | diagonal | 12 | 157 | 149 / 61 | 149 / 35 |
- squat_no_lockout이 아직 25렙 울린다. 두 사람(subject_003, 010)의 렙별 무릎 최대가 156–167°다. 푸시업 subject_020은 팔꿈치 134–137°다. 진짜 덜 편 것인지 2D 오차인지는 영상을 보지 않아 모른다(공개 영상은 열람 범위 밖).
- **squat_knee_valgus는 진짜 정면에서도 정상 렙의 절반이 울린다(73/137).** 시점 게이트는 고쳤지만 기준값 1.0은 그대로다. 그래서 이 키는 아직 켤 수 없다.
- bad 클립(키 라벨 없음): squat_no_lockout 50 → 0, pushup_no_lockout 20 → 0, valgus 157 → 152렙. 옛 규칙이 bad 클립에서 울리던 것이 진짜 검출이었는지는 모른다. no_lockout 라벨(rules-calib AI 2패스 합의)이 붙은 bad 클립(subject_003·005·006·011 스쿼트, 014·020·021 푸시업)은 held-out 2D CSV에 없어서 검출률을 잴 수 없었다.

## 3. 엄격도 모드 (사용자 결정 2026-10-23, 조정자 전달)

### 3.1 구조
- 네이티브 `FormStrictness`(`strict` / `standard` / `relaxed`, FormWarnings.swift).
  - 기준값은 rules-calib `FormRulePreset`와 같은 이름(`<설정>.<필드>`)으로 덮어쓴다. FormRulePreset은 ai/rules-calib에만 있고 integration/ai에는 없어서, 같은 이름 규칙의 작은 표를 새로 만들었다.
  - **standard = 지금 값 그대로.** 기본값이다.
  - 모드별 전달 키: strict는 꺼 둔 6키 중 이번 수정으로 Ex3D 오경보가 0이 된 squat_no_lockout, pushup_no_lockout을 더 보낸다. squat_knee_valgus는 기준값 문제가 남아 strict에서도 끈다. relaxed는 rc1이 "끄기"로 둔 pushup_hand_position, row_short_pull, row_standing_up을 보내지 않는다(판정·기록은 함).
- 브리지: Flutter 플랫폼 뷰 생성 인자 `formStrictness`("strict" | "standard" | "relaxed"). 없거나 모르는 값은 standard. `NativePoseWorkoutScreen(formStrictness: ...)`, 기본 'standard'. 모드 선택 UI는 팀원 몫이다.
- pose-replay `--strictness <모드>`, CSV 재생에서 3D를 쓰는 `--image-size WxH`.
- 새 키 셋(`pushup_elbow_flare`, `pushup_head_hang`, `squat_torso_lean`)은 참고 등급이고 Flutter 대사가 없어 `keysWithoutFlutterLines`에 넣었다. 어느 모드에서도 지금은 기록만 한다.

### 3.2 모드별 값
| 필드 | 표준(지금) | PT 엄격 | 근거 | 여유(rc1 xs_orig_rc1) |
|---|---|---|---|---|
| row.torsoSwingRangeDegrees | 39.9 | **7.0** | 근거 있음: good p90–p95 5.8–7.9° | 34.153 |
| squat.torsoLeanOverTibiaDegrees(새, squat_torso_lean) | 끔 | **0.0** | 근거 있음(약함, J 0.26): FMS와 같음 | 37.8529 |
| squat.hipsFirstTorsoRiseDegrees | 8 | 4.4 | 잠정(근거 부족) | 8.3071 |
| squat.valgusKneeAnkleGapRatio | 1.0 | 0.47 | 잠정 | 0.2235 |
| squat.heelRiseShinRatio(키는 꺼짐) | 0.05 | 0.10 | 잠정 | 0.4091 |
| squat.shallowOverBaselineDegrees | 15 | – | | 30.8123 |
| pushUp.hipSagDeviation | 0.14 | 0.054 | 잠정 | 0.1786 |
| pushUp.hipPikeDeviation | 0.08 | −0.002 | 잠정(hip_dev_min < 0.002) | 0.2346 |
| pushUp.headUpDeviation | 0.15 | 0.058 | 잠정 | 0.2571 |
| pushUp.headDropDeviation | 0.376 | – | | 0.1514 |
| pushUp.shallowOverBaselineDegrees | 15 | – | | 43.8707 |
| pushUp.elbowFlareDegrees(새) | 끔 | 45 | 잠정(1.4 규칙: tip p10 21.3° < 45° → 45°) | 끔 |
| pushUp.headHangDegrees(새) | 끔 | −5.4 | 잠정(1.4 규칙: tip p10) | 끔 |
| row.standingUpDegrees / shortPullBelowBaseline / headUpDeviation | 10 / 0.10 / 0.15 | – | | 2.587 / 0.0429 / 0.1688 |
- "–" = 표준과 같음. no_lockout의 rc1 값은 정의가 바뀌어 쓰지 않았다. 스쿼트 깊이(thigh_incline)·푸시업 절대 깊이·로우 상체 각도·당김 높이는 integration/ai에 해당 지표가 없어 넣지 않았다.
- **주의: PT 엄격·여유 값은 3D 경로(원래 XS, Python 앱 경로)에서 나왔다. integration/ai는 2D로 판정한다.** 같은 이름이라도 2D 양을 잰다. 아래 3.4가 그 결과다.
- 잠정값 중 무릎 모임 0.47과 뒤꿈치 0.10은 표준보다 오히려 느슨하다. 지금 표준값(1.0, 0.05)이 정상 렙에도 크게 울리는 값이기 때문이다.

### 3.3 새 지표 분포 (Ex3D 푸시업, 측면 게이트 통과, 2차 PT 라벨 모두 tip)
| 지표 | 렙 | p10 | 중앙값 | p90 | 카메라별 |
|---|---|---|---|---|---|
| elbow_flare_at_bottom(3D) | 82 | 21.3° | 39.9° | 47.4° | cam2(25–48° 사선) 20–26°, cam3(10–24°) 40–51° |
| head_trunk_at_bottom(2D) | 100 | −5.4° | 4.8° | 18.9° | cam2 −8–11°, cam3 2–24° |
- **같은 물리적 렙인데 카메라마다 값이 크게 다르다.** 3D 팔꿈치 벌림도 카메라에 따라 20°쯤 차이 난다. 라벨(약 60° 벌림, 목 25–30° 굽힘)과도 맞지 않는다. 두 지표 모두 지금은 시점 의존이 커서 검출 근거가 없다.
- 머리-몸통 기준 −5.4°는 사전 규칙상 tip의 90%를 잡는 값이다. 그래서 거의 모든 렙에서 울린다(아래 3.4). 켤 후보가 아니다.

### 3.4 모드별 발화 (2D 판정, 푸시업은 같은 키포인트로 올린 3D 포함)
Ex3D 37클립, 2차 PT 라벨(good · tip/error) 기준, 발화 / 카메라 렙:

| 키 | 라벨 항목 | 엄격 good | 엄격 tip | 표준 good | 표준 tip | 여유 good | 여유 tip |
|---|---|---|---|---|---|---|---|
| row_torso_swing | 몸통 유지 | 4/63 | 23/51 | 0/63 | 0/51 | 0/63 | 0/51 |
| squat_torso_lean | 몸통 숙임 | 7/30 | 22/70 | 0/30 | 0/70 | 0/30 | 0/70 |
| squat_knee_valgus | 무릎 모임 | 1/100 | – | 2/100 | – | 1/100 | – |
| squat_no_lockout / pushup_no_lockout | 락아웃 | 0/100 · 0/150 | – | 0 · 0 | – | 0 · 0 | – |
| pushup_elbow_flare | 팔꿈치 벌림 | – | 11/150 | – | 0/150 | – | 0/150 |
| pushup_head_hang | 머리 처짐 | – | 89/150 | – | 0/150 | – | 0/150 |
| pushup_hip_sag | 엉덩이 처짐 | **71/150** | – | 0/150 | – | 0/150 | – |
| pushup_hip_pike | 엉덩이 들림 | 4/150 | – | 0/150 | – | 0/150 | – |
| pushup_head_up | 고개 듦 | **47/150** | – | 1/150 | – | 0/150 | – |
| row_standing_up | 상체 각도 | – | 0/114 | – | 0/114 | – | 18/114 |

공개 held-out good 클립, 발화 / 렙:

| 키 | 엄격 | 표준 | 여유 |
|---|---|---|---|
| pushup_hip_pike | 167/297 (56%) | 35/297 (12%) | 0/297 |
| pushup_head_up | 176/297 (59%) | 97/297 (33%) | 46/297 (15%) |
| pushup_head_hang | 186/297 (63%) | 0 | 0 |
| pushup_hip_sag | 68/297 (23%) | 6/297 (2%) | 1/297 |
| squat_torso_lean | 59/393 (15%) | 0 | 0 |
| squat_knee_valgus | 0/393 | 130/393 (33%) | 0/393 |
| squat_no_lockout / pushup_no_lockout | 25/393 · 43/297 | 같음 | 같음 |
- 공개 클립은 키포인트만 있어 3D를 올리지 않았다(팔꿈치 벌림은 0).
- **근거 있는 두 값은 2D에서도 good과 tip을 어느 정도 가른다**: 로우 반동 good 6% vs tip 45%, 스쿼트 몸통 숙임 good 23% vs tip 31%(약함).
- **잠정값 중 엉덩이 처짐·고개 듦·엉덩이 들림은 2D 판정에서 바른 렙에 크게 울린다**(Ex3D good 47%·31%, 공개 good 23–59%). 3D 분포로 정한 값을 2D 지표에 쓴 탓이다. 엄격 모드를 실제로 쓰려면 2D 경로용 값을 따로 내거나, lift-app 3D 판정과 함께 써야 한다.

## 4. 한계
1. 라벨은 AI 시각 라벨(사람 아님)이다. Ex3D에는 덜 일어섬·무릎 모임 렙이 없어 **검출력은 증명되지 않았다.** 푸시업은 held-out 사람이 없다(in-sample).
2. 판정 경로: integration/ai는 2D로 판정한다. 기기 실행(lift-app)은 3D로 판정한다. lift-app을 병합하면 락아웃 구간 수정은 3D 표본에도 적용해야 하고, 3D 각도용 기준값을 따로 내야 한다. 무릎 모임 게이트는 2D 신호라 그대로 쓸 수 있다(2.5).
3. 락아웃 구간: 이번 렙 바닥부터 다음 렙 beginRep 또는 endSet까지다. 세트 끝에 오래 서 있거나 걸어 나가면 그 프레임도 들어간다. 이것은 놓침(검출 못 함) 쪽으로만 작용한다.
4. 렙 요약(SquatRepSummary·PushUpRepSummary.warnings)과 기기 디버그 JSONL의 렙 줄은 렙을 셀 때 바로 만들어진다. 그래서 no_lockout이 들어가지 않는다. 세트 수(setWarningRepCounts → 세트 끝 참고 전달, worstJoint)와 tracker.reports(pose-replay)에는 들어간다.
5. 무릎 모임: 첫 렙 전 서 있는 프레임이 30개(약 1초) 안 되면 첫 렙은 판정하지 않는다.
6. Python 판정기 미러: rules-calib Python 판정기(`pose_feedback/feedback/form_rules.py`)는 ai/rules-calib에만 있고 integration/ai에는 없다. 그래서 이 브랜치에서는 미러하지 않았다. rules-calib을 병합할 때 같은 정의로 고쳐야 한다(`noLockoutBelowSetMaxDegrees` 이름도 바뀌었다).
7. 새 지표 둘은 시점 의존이 크다(3.3). 3D 팔꿈치 벌림은 앱 라이브 3D(MotionAGFormerLive)가 아니라 pose-replay `lift3D`로 쟀다.

## 5. 재현
- 스크래치 `rulesfix/`(Mac, git 밖): `tools/dev2csv.py`(기기 JSONL → pose-replay CSV), `tools/run.sh`·`run_modes.sh`(재생), `tools/derive.py`(2.3), `tools/evaluate.py`(2.4·2.6), `tools/device3d_valgus.py`(2.5), `tools/view_ratio*.py`·`pub_view.py`(2.2), `tools/strict_dist.py`(3.3), `tools/modes_eval.py`(3.4).
- 입력: Home `~/bpt-runs/lift-app/20261020-device-halpe-ab-a8b29f1-partial-20261021-103959/full_mhalpe26_r0/`(기기 37클립), `~/bpt-runs/rules-calib/20261020-refs-h26-all/public_held_own_v1/2d/`(공개 held-out 152 CSV), `~/bpt-runs/ex3d-form-labels/20261023-compare/ex3d_form_labels.csv`, ai/ex3d-form-labels `docs/results/ex3d_form_labels_strict.csv`(fb153e6).
- 재생: pose-replay `--keypoints-dir` (수정 전 3cef41d, 수정 후 이 브랜치). 푸시업 3D: `--image-size 1280x720 --motion3d assets/coreml/motionagformer_xs.mlpackage`.

## 6. 사용자 승인이 필요한 것
1. squat_no_lockout·pushup_no_lockout을 표준에서도 켤지(지금은 엄격 모드에서만 전달).
2. 엄격 모드의 잠정값(특히 2D에서 바른 렙에 크게 울리는 엉덩이 처짐·들림·고개 듦)을 그대로 둘지, 2D용 값을 다시 낼지.
3. 새 키 셋의 Flutter 대사(팀원)와 전달 여부.
4. 이 브랜치를 integration/ai에 병합할지(병합하지 않았다).
