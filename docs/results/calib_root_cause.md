# 체형 촬영(캘리브레이션)이 안 찍히는 근본 원인 — calib_root_cause

- 보고: 사용자 2026-10-22 "캘리 겁나 안됨". 4방향(정면·왼쪽·뒷면·오른쪽) 중 1/4에서 한 장도 안 찍혔다.
- 분석 기준: `origin/integration/ai` = `main` = `f953336`. 이 문서의 코드 줄 번호는 모두 이 커밋 기준이다.
  - 캘리브레이션 네이티브 코드는 `eb301ad`와 같다. #66·#67은 캘리브레이션을 건드리지 않는다(6절).
- 브랜치: `ai/calib-rca-meb301ad`. 앱 코드는 바꾸지 않았다. 분석 도구와 이 문서만 있다.
- 자료(git 밖, 사용자 얼굴이 나옴):
  - `~/bpt-data/user_tests/2026-10-22/screenrec_161547.mp4`: 실패한 시도의 화면 녹화. 38 s, 1206×2622.
  - `~/bpt-data/user_tests/2026-10-22/IMG_9900.MOV`: 사용자가 만든 시험 영상. 1080×1920, 22 s.
  - 프레임별 판정 CSV 78개와 말풍선 OCR: `~/bpt-data/user_tests/2026-10-22/calib_rca/`. 관절 좌표가 들어 있어 저장소에는 넣지 않았다.
- 도구: `scripts/calib_rca/` (부록 A). 앱의 `CalibrationFrameAnalyzer`·`CalibrationEngine` 소스를 심볼릭 링크로 그대로 쓴다.
  - 프레임마다 다음을 CSV 한 줄로 남긴다.
    - 관절 17개의 좌표와 신뢰도, RTMPose crop(사람 상자)
    - 몸 높이·머리·발·중심, 팔·발 관문 값
    - 방향 후보, 움직임(멈춤 판정), 유지 진행도, 촬영 여부
  - 폰 기울기는 영상에 없어서 0°로 넣는다. 기울기 실험은 그림을 돌려서 했다(4절).
  - CSV 열: `i`(원본 프레임 번호), `t`(초), `guidance`, `classified`/`candidate`(관문을 무시한 방향 후보)/`target`, `hold`, `pass`, `captured`, `motion`, `face*`, `crop*`(사람 상자), `torso, headTop, feet, bodyH, midX`, `wristDrop*, elbow*, wristReach, ankleGap`, `swT, hwT, noseOffset, chest`, `r, delta`, `k0x…k16s`(관절별 좌표·신뢰도).
  - 이 문서는 시각 t(초)로 적는다. 녹화는 60 fps에서 2프레임마다 하나씩 썼으므로 i = 원본 프레임 번호다.

## 0. 결론

1. **사용자 실패의 1순위 원인은 분석 버퍼가 미리보기와 90° 돌아가 있는 것이다** (재생으로 재현해 확인. 기전은 기기 로그로 확정해야 함).
   - 판정 엔진이 받는 그림에서 사람은 옆으로 누워 있다. 그런데 미리보기는 똑바로 보인다.
   - 그래서 몸 높이가 거리와 상관없이 늘 0.1대로 재진다. 화면에는 35초 내내 "조금만 앞으로 와 줘!"와 "머리부터 발끝까지"만 나왔다.
   - 이 버그는 사용자 폰의 빌드(liftdev `a8b29f1`)와 지금 main에 똑같이 있다.
2. **버퍼가 바로 서 있어도 정면 A자 관문이 이 사용자를 통과시키지 못한다** (확인).
   - `minWristReach 0.8`이 원인이다. 두 영상 모두 0.8초 유지 구간이 0번이었다.
3. **정면을 찍은 뒤에는 제자리 관문(발 0.03)과 가운데 관문(0.06)이 걸린다** (확인, IMG_9900). 제자리에서 돌기만 해도 걸린다.
4. **좌우 기울기 3°는 이번 실패의 원인이 아니다.** "폰이 기울었어"는 녹화 끝, 폰을 집어 들 때만 나왔다.
   - 서버는 중력을 쓰지 않는다. 앱 판정이 기울기에 민감하다.
   - 키포인트를 중력으로 바로 세워서 판정하면 10°까지 허용할 수 있다(4절).

## 1. 원인 순위

| 순위 | 원인 | 상태 | 핵심 근거 |
|---|---|---|---|
| R1 | 분석 버퍼 90° 회전. 사람이 옆으로 누운 그림을 판정한다 | **확인**(재생 재현). 기전 M1/M3는 가설 | 기기 안내 100%가 FULL/FWD. 같은 회전을 준 재생만 이 패턴과 발 위치 0.60을 재현한다 |
| R2 | 정면 A자 `minWristReach 0.8` 과엄격 | **확인** | 녹화 0.8초 유지 0회(0.5–0.6이면 16회). IMG_9900 0/516 프레임 |
| R3 | 정면 뒤 제자리 `maxFeetDrift 0.03`, 가운데 `maxCentreOffset 0.06` 과엄격 | **확인**(IMG_9900) | 정면 뒤 프레임의 66%가 발 이동 > 0.03 |
| R4 | 실루엣 튐 | **확인** | person이 없으면 기본 위치(발 0.88)로, 있으면 발 0.61로 오간다. 22회 이상 |
| R5 | 발목이 신뢰도 0.3 미만이면 "뒤로" 대신 "발끝까지" | 확인, 부차 | 녹화를 바로 세운 재생에서 FULL 170 중 47 |
| R6 | 사선에서 0.8초 멈춤이 안 됨 | 영상 한계(가설 아님, 원인 아님) | IMG_9900은 사선 구간을 0.27–0.63초에 지나간다 |
| — | 좌우 3°, 초광각 화각·crop 차이, Center Stage | 이번 실패 원인 아님 | 4절, R1 표의 화각 1.8배 행 |

### R1. 분석 버퍼가 90° 돌아가 있다

**기기에서 실제로 나온 안내** (`scripts/calib_rca/ocr_bubble.swift`, 녹화 말풍선 첫 줄을 10 fps로 OCR)
- 폰을 집기 전 0–35.6 s, 357 표본: "머리부터 발끝까지"(FULL) 75%, "조금만 앞으로 와 줘!"(FWD) 25%, 그 밖 **0%**.
- 시간표: 0–0.4 FULL, 0.5–1.2 FWD, 1.3–1.7 FULL, 1.8–4.8 FWD, 4.9–5.3 FULL, 5.4–5.7 FWD, 5.8–15.4 FULL, 그 뒤 26.5 s까지 FULL/FWD가 계속 바뀐다. 26.6–35.6에도 FULL/FWD뿐이다.
  - 사용자는 이 동안 처음 자리(전신 보임) → 매우 가까이(무릎 아래 잘림) → 중간 거리 → 옆으로 돌기를 했다.
  - 그런데도 A자·뒤로·좌우·멈춤 안내가 한 번도 없었다.
- 35.7 s 이후: "어디 있어?" 11, "폰이 흔들려!" 2, "폰이 기울었어!" 9. 폰을 집어 들 때다.

**기기가 잰 발 위치**
- FWD일 때 실루엣은 '안 맞음' 상태로 그려진다. 높이는 0.62, 발 위치는 엔진이 잰 `person.feet`다(`calibration_silhouette.dart:165-167`).
- 윤곽 맨 아래를 녹화에서 쟀다: t=2.0 s 0.641, t=3.0 s 0.624.
- 윤곽 단위의 발 기준점 보정 −0.012(`assets/calibration/silhouettes.json` engineAnchors)를 빼면 기기 feet는 **0.63, 0.61**이다.
- 같은 순간 미리보기 속 실제 발은 약 0.76이다.

**가설별 재생** (녹화를 좌우 반전하고 양옆을 9:16로 채웠다. 30 fps, 0–35.6 s)

| 가설(분석 버퍼에 준 변형) | FULL | FWD | 그 밖 | FWD 때 feet 중앙값 | t=2·3 s 안내 |
|---|---|---|---|---|---|
| 기기 실제(OCR) | 75% | 25% | **0%** | 0.61–0.63(실루엣) | FWD |
| 기준: 버퍼 = 미리보기 | 12% | 0% | 88% | – | openArmsWider |
| **90° 회전, 가로 버퍼** (`oriented(.right)`) | 24% | 76% | **0%** | **0.60** | **FWD** |
| 270° 회전, 가로 버퍼 | 22% | 76% | 1% | 0.77 | FULL |
| 90° 회전, 세로 모양 버퍼(16:9 장면을 돌림) | 45% | 55% | 0% | 0.54 | FWD/FULL |
| 180° 회전 | 100% | 0% | 0% | – | FULL |
| 화각 1.8배(초광각·crop 가설) | 0% | 4% | 95% | 0.67 | openArmsWider |

- 기기의 두 특징을 모두 재현하는 것은 **가로 버퍼에 장면이 시계 방향 90°로 누운 경우**뿐이다. 두 특징은 다음과 같다.
  - 안내가 FULL/FWD 두 가지뿐이다.
  - FWD일 때 feet가 0.6 근처다.
- FULL/FWD 비율이 반대로 나오는 것은 설명된다.
  - 누운 몸에서는 몸통 길이가 0 근처라, 부호와 관절 신뢰도에 따라 둘 중 하나로 갈린다.
  - 녹화에는 UI·실루엣 선과 양옆 검은 띠가 있다.
- 화각/crop 가설(calib_fix 메모의 (a)·(c))은 **기각한다**. 사람만 작게 보이면 A자 안내가 95% 나와야 하는데, 기기에서는 0%였다.
- 사용자를 잘 찍은 IMG_9900에 같은 90° 회전을 주어도 결과는 같다: FULL 60%, FWD 38%, 촬영 0장. 사용자의 거리나 자세와 무관한 실패다.

**누운 몸에서 "앞으로 와"가 나오는 계산** (90° 재생, t=3.0 s 실제 값)
- 어깨 y는 0.626과 0.362, 엉덩이 y는 0.595와 0.421이다. 사람이 누워 있어서 위아래가 몸의 좌우 방향이다.
- torso = 0.508 − 0.494 = **0.0138**
- headTop = 0.494 − 0.75 × 0.0138 = 0.484
- feet = max(발목 0.615, 0.465) + 0.06 × 0.0138 = 0.616
- bodyHeight = 0.13 < 0.40 → `stepForward`
- torso ≤ 0이거나 관절 하나가 0.3 미만인 프레임은 `measure()`가 nil을 돌려주고 `showFullBody`가 된다.

**빌드 확인**
- 16:15에 폰에 있던 것은 com.bpt.liftdev Release(`a8b29f1` 기반)다.
- 녹화에 디버그 글자가 없고, #64 이전 화면이다. 말풍선이 아래에 있고 정면 힌트 두 줄이 있다.
- `git diff a8b29f1 f953336 -- ios/Runner/NativePose/Calibration`의 차이는 음성 볼륨 한 줄뿐이다.
- `a8b29f1`의 `CaptureRotation`(강제 회전 env)은 운동 카메라에만 쓰인다. 사용자가 홈 화면에서 연 실행에는 env가 없다.

**관련 코드** (`ios/Runner/NativePose/Calibration/`)
- `CalibrationSession.swift:438-439`: 전면 `builtInUltraWideCamera`를 먼저 고른다.
  - iPhone 17에서 새로 생긴 카메라다. 정사각 센서를 쓴다.
  - F9/F10(2026-10-11)에서 "실기기 촬영 1회로 확인 필요"로 남았고, 그 뒤 실기기 4장 완주 기록이 없다.
- `CalibrationSession.swift:446-449`: 4K 프리셋.
- `CalibrationSession.swift:488-500` `applyPortraitRotation`
  - RotationCoordinator가 준 각이 90/270이 아니면 **무조건 90으로 바꾼다**(493).
  - `isVideoRotationAngleSupported`가 거짓이면 아무것도 안 하고 기록도 남기지 않는다(494-496).
  - 적용된 각을 다시 읽지 않고, 폰 방향 변화(KVO)도 따라가지 않는다.
- `CalibrationCameraPlatformView.swift:32-33`: 미리보기 레이어는 자기 기본 회전을 쓴다. 데이터 출력 회전과 따로 정해진다.
  - 그래서 미리보기는 바르고 분석은 누워 있는 상태가 **조용히** 생긴다.
- `CalibrationSession.swift:181`: `CIImage(cvPixelBuffer:)`를 그대로 분석에 넘긴다. 방향을 확인하지 않는다.

**기전 후보** (가설, 기기 로그로 가린다. 8절 E1)
- M1: 데이터 출력의 90° 회전이 적용되지 않는다(지원 안 됨 등). 센서 기본 방향의 가로 버퍼(3840×2160)가 그대로 온다.
- M3: 이 카메라의 세로 수평 각이 90이 아닌데(예: 0), 493줄이 90으로 강제한다. 결과 버퍼의 모양은 카메라 기본 방향에 따라 가로 또는 세로가 된다.
- 재생에서는 가로 모양 버퍼(feet 0.60)가 세로 모양 버퍼(0.54)보다 기기 값(0.61–0.63)에 가깝다.
  - 그래서 M1, 또는 기본 방향이 세로인 M3 쪽이 유력하다.
- 고칠 방법(7절 F1)은 M1과 M3 둘 다를 덮는다. F1은 코디네이터 값과 실제 적용 각으로 "지금 버퍼를 몇 도 더 돌려야 수평인지"를 계산하기 때문이다.

### R2. 정면 A자 관문 `minWristReach 0.8`이 너무 엄격하다

- 위치: `CalibrationConfig.swift:51`, `CalibrationEngine.swift:305-306`. 정면 단계에서만 검사한다.
- 녹화를 바로 세운 재생: 크기·가운데 통과 646 → 팔 높이·팔꿈치 통과 620 → reach ≥ 0.8은 **4프레임**. 0.8초 유지 구간은 0회였다.
  - 사용자는 안내대로 A자를 했는데도 reach가 0.63–0.67이었다(t=2–4 s).
  - reach ≥ 0.6이나 0.5로 바꾸면 유지 구간이 16회 생기고, **정면이 2.8 s에 찍힌다**.
- IMG_9900: reach 중앙값 0.38, p90 0.65. 0.8 이상은 0/516. 0.6이면 1회(3.2 s), 0.5면 3회.
- 그러니 R1을 고쳐도 기본값으로는 사용자 시도에서 정면이 안 찍혔다.
- `maxWristDrop 0.97`은 기울기가 없으면 정면 단계에서 거의 상관없다(IMG_9900 통과 프레임 0.97: 118, 1.05: 120).
  - 하지만 폰이 3–5° 기울면 한쪽 손목이 0.98–1.03이 되어 막는다(4절).
  - 정면 뒤 IMG_9900에서도 0.97이면 openArmsWider가 52%다(562프레임 중 294). 1.05로 하면 14%로 준다.

### R3. 정면 뒤 제자리·가운데 관문이 너무 엄격하다

IMG_9900에서 A자 관문을 끄면 정면은 3.2 s에 찍힌다. 그 뒤가 문제다.
- `returnToStart` 48%. 정면 기준 대비 발 이동은 중앙값 0.034, p90 0.065이고, 0.03을 넘는 프레임이 66%다(`CalibrationConfig.swift:41`, `CalibrationEngine.swift:116-121`).
  - 돌면서 발을 디디면 바닥에 가까운 카메라에서는 발 y가 3–6% 바뀐다.
- `moveToCentre` 9%. 몸이 돌면 어깨·엉덩이 중점이 움직인다(뒷면 0.07–0.10).
  - `maxCentreOffset 0.06`은 화면 **너비**의 6%다. 1.5 m에서 약 ±8 cm다(`CalibrationConfig.swift:33`).
- 서버는 사진마다 `global_orient`·`pose`·`transl`을 따로 맞추고 β만 공유한다(`server/calibration_modal/fitting.py:136-157`). 자리가 조금 바뀌어도 fit에는 문제가 없다.
  - r(어깨·엉덩이 폭/몸통)과 δ(코 위치/몸통)도 몸통 길이로 나눈 값이라 거리와 무관하다.
- 발 0.08, 중심 이동 0.15, 가운데 0.10으로 넓히면 정면 3.2 s와 뒷면 18.9 s가 찍힌다.

### R4. 실루엣이 뛴다 (3절)

### R5. 발이 잘렸을 때 "뒤로"가 아니라 "발끝까지"가 나온다 (calib_fix 발견 2, 부차)

- 발목 신뢰도가 0.3 미만이면 `measure()`가 nil을 돌려준다(`CalibrationEngine.swift:103-106`). 그러면 거리 정보 없이 `showFullBody`가 나간다.
- 녹화를 바로 세운 재생에서 FULL은 170프레임이다.
  - 123프레임은 머리 < 0.02(가까이 서서 머리가 위로 잘림)다.
  - 47프레임은 관절 누락이다. 오른손목 45, 오른발목 40, 무릎 37–40.
  - 가장 가까이 선 8.4–15.5 s는 `stepBack`이다(전체의 23%). RTMPose가 가장자리에 발목을 지어내서 bodyH > 0.85가 됐다.
- 버퍼가 바르면 "앞으로 와"는 나오지 않는다. 기준 재생에서 FWD는 0프레임이다.
- 그래서 사용자가 겪은 "발이 잘렸는데 앞으로 와"는 R1 때문이다. R5는 문구를 더 정확하게 만드는 개선이다(F6).

### R6. 사선(±60°)은 IMG_9900에서 멈춤 0.8초가 안 된다 (영상 한계)

- A자와 제자리 관문을 넓혀도 사선 두 장은 안 찍힌다.
- 분류는 맞다. 왼쪽(rightfront, δ>0)은 4.5–5.1 s, 오른쪽(leftfront, δ<0)은 12.9–13.4 s와 16.2–16.4 s에 잡힌다.
- 하지만 사용자가 밴드(r 0.31–0.75)를 0.27–0.63초에 지나간다. 움직임은 0.3–1.1 몸통/초(기준 0.45)이고, 유지 진행도는 최대 0.29였다.
- 안내 음성이 없는 영상이라 멈추지 않았을 뿐이다. 문턱을 바꾸지 말고 기기 안내 실행(E2)으로 확인한다.
- 참고: 기울기 −3° 재생에서는 뒷면 r이 0.89–0.93으로 기준 0.90에 걸쳐 유지가 끊겼다. 데이터가 더 생기기 전에는 바꾸지 않는다.

## 2. 발이 잘렸는데 "조금만 앞으로 와 줘!"가 나오는 이유

계산(`CalibrationEngine.swift:197-213, 281-284`):

```
torso      = 엉덩이 y 평균 − 어깨 y 평균                       (버퍼 높이 단위)
headTop    = 어깨 y 평균 − 0.75 × torso
feet       = max(왼발목 y, 오른발목 y) + 0.06 × torso
bodyHeight = feet − headTop
판정 순서:  bodyHeight > 0.85 → 뒤로 / headTop < 0.02 또는 feet > 0.98 → 발끝까지
           / bodyHeight < 0.40 → 앞으로 / |midX − 0.5| > 0.06 → 좌우
입력:      12관절(어깨~발목) 모두 신뢰도 ≥ 0.3이어야 measure() 성공. 하나라도 모자라면 nil → 발끝까지
```

- 기기에서는 분석 그림 속 사람이 누워 있다. 어깨와 엉덩이의 y가 거의 같아서 torso가 0.01 안팎이다.
- 그러면 bodyHeight가 약 0.1–0.15로, 늘 0.40 아래다. 사용자가 다가가도(무릎 아래가 잘려도) 마찬가지다.
- torso의 부호가 음수로 바뀌거나 관절 하나가 0.3 아래로 떨어지면 "발끝까지"가 된다. 두 문구가 번갈아 나온 이유다.
- 입력값 예는 R1 계산(t=3.0 s)에 있다.
- 버퍼가 바로 서 있으면 다음처럼 된다. 이 경우 "앞으로 와"는 나오지 않는다.
  - 발이 잘렸을 때: RTMPose가 가장자리에 발목을 지어내면 bodyH > 0.85가 되어 "뒤로", 발목 신뢰도가 낮으면 "발끝까지".
  - t=2–4 s의 정상 자세: bodyH 0.70–0.75로 크기 관문을 통과하고 A자에서 막힌다.

## 3. 실루엣이 뛰는 이유

- 그리는 위치(`lib/features/onboarding/widgets/calibration_silhouette.dart:160-167`):
  - `fits`(사람 있음, 중심 ±0.06, 높이 0.40–0.85)면 사람의 midX·feet·bodyHeight에 붙는다.
  - 아니면 `(0.5, person?.feet ?? 0.88, 0.62)`다. 사람이 없으면 발 0.88(156줄)이다.
- `person`은 엔진 측정값이 있을 때만 온다(`CalibrationSession.swift:298`).
  - 다음 경우에는 측정값이 없다(`CalibrationEngine.swift:87-106`).
    - 폰 관문(좌우 > 3°, 앞뒤 > 25°, 흔들림)에서 실패했을 때
    - 관절이 모자랄 때
    - 분석에 실패했을 때
  - Dart는 매 업데이트마다 `_person`을 덮어쓴다(`onboarding_scan_screen.dart:90`).
- 녹화에서 일어난 일
  - FULL 프레임에서는 person이 없다. 윤곽 발이 0.88, 머리가 0.27이고, 몸 위에 작게 얹힌 모양이다.
  - FWD 프레임에서는 feet가 약 0.61이다. 윤곽 머리가 화면 위로 나가고 발은 무릎 높이다.
  - 둘 사이 거리는 화면 높이의 0.27(약 235 pt)이다. 10 fps 표본으로만 세도 35초에 22번 바뀌었고, 실제로는 더 자주 바뀐다. 180 ms 트윈이 이것을 미끄러지듯 보여 준다.
  - 크기는 내내 0.62다. 한 번도 `fits`가 아니었다.
- R1을 고친 뒤에도 남는 원인
  - 3° 경계에서 기울기 관문이 켜졌다 꺼졌다 한다.
  - 관절이 한 프레임 빠진다.
  - 이때마다 0.88로 튄다.
  - `fits` 경계(0.40/0.85/±0.06)에서는 크기가 0.62와 실제 몸 높이 사이를 오간다.

## 4. 좌우 기울기 3°는 너무 엄격한가

**중력과 기울기를 어디서 쓰나**
- 앱은 사진마다 `views[].gravity`를 manifest에 넣는다(`CalibrationStore.swift:123`).
- 서버(`server/calibration_modal/*.py`)는 `gravity`를 한 번도 읽지 않는다(grep 0건).
- 서버 fit은 사진마다 자기 intrinsics로 투영하고, 사진마다 `global_orient`·`pose`·`transl`을 자유롭게 맞춘다. β는 공유하고 키로 사영한다(`fitting.py:136-157`).
  - 그래서 카메라가 굴러도(roll) 사진별 몸 방향이 흡수한다. F11이 앞뒤 기울기 25°를 허용한 근거와 같다.
  - 서버 쪽만 보면 roll도 허용할 수 있다.
  - 다만 SAM 3D Body가 10° 돌아간 사진에서 얼마나 정확한지는 GPU로 재지 않았다(가설).
- 서버의 사진 조건은 12관절 중 8개 이상이 신뢰도 ≥ 0.3인 것뿐이다(`fitting.py:92`).

**앱 판정은 roll에 민감하다**
- 그림을 돌려 기울기를 흉내 냈다(`--tilt-image`). 폰 관문은 끄고 그림만 돌렸다.
- 정면 코 위치(`noseOffset`)가 약 0.6 × tan θ만큼 밀린다. 정면 판정 한도는 0.08이다.

  | 그림 기울기 | 0° | +3° / −3° | +5° / −5° | +8° / −8° | +12° / −12° |
  |---|---|---|---|---|---|
  | 녹화 \|noseOffset\| 중앙값(t 0.7–2.7 s, 정면으로 선 구간) | 0.005 | 0.032 / 0.023 | 0.051 / 0.037 | 0.078 / 0.064 | 0.122 / 0.103 |
  | 녹화 정면 촬영(F2+F3 값) | 2.8 s | 2.8 / 3.3 s | 2.8 / 3.0 s | 32.1 s(끝 무렵) / 3.1 s | **없음 / 없음** |
  | IMG_9900 정면 촬영(reach 0.5, drop 0.97) | 3.2 s | 없음 / 3.1 s | 없음 / 3.0 s | 없음 / 2.6 s | 없음 / 없음 |
  | IMG_9900 정면 촬영(reach 0.5, **drop 1.05**) | 3.2 s | 15.3 / 3.1 s | 15.2 / 3.0 s | 없음 / 2.4 s | 없음 / 없음 |

- 같은 기울기에서 손목 높이도 양쪽이 반대로 밀린다. IMG_9900 +3°에서 오른손목 drop이 0.98–1.03으로 0.97을 넘는다.
- 즉 지금 3°에서도 경계에 있는 사용자는 한쪽 방향 기울기에 막힌다.

**권고**
- (a) 권장: `CalibrationEngine.measure()` 안에서 그 프레임의 `device.rollDeg`만큼 키포인트를 되돌린 사본으로 잰다. 그다음 `maxRollDeg` 3 → **10**.
  - 저장·업로드하는 키포인트는 원본 그대로 둔다. 서버 계약은 바뀌지 않는다.
  - 10°면 코 위치 이동이 보정 전 0.1 수준이고, 이것이 0이 된다.
  - RTMPose 자체는 10° 회전에 강하다고 본다(학습 때 회전 증강, 추정).
  - 재생에서 ±8–12°일 때 '발끝까지'가 늘어난 것은 근거로 쓰지 않았다. 그림을 돌리며 생긴 검은 모서리 때문일 가능성이 크다.
  - 부호를 반드시 테스트로 고정한다(7절 F4).
- (b) (a)를 하지 않을 때: 최대 **5°**까지만 넓힌다. 이때도 `maxWristDrop 1.05`가 같이 있어야 한다.
  - IMG_9900 +5°는 이 값으로도 정면이 15.2 s로 늦다.
  - 8°에서는 사용자 본래 코 위치와 같은 쪽으로 기울면 정면이 거의 안 찍히고(녹화 +8° 32.1 s, IMG_9900 +8° 없음), 12°는 둘 다 못 찍는다.
- "앞뒤 25°와 중력이 있으니 roll도 허용되나?"에 대한 답
  - 서버는 그렇다.
  - 앱 판정은 키포인트를 중력으로 바로 세워야 한다. 앞뒤 기울기는 그림을 화면 안에서 돌리지 않는다. roll은 돌린다.

## 5. IMG_9900이 4방향을 통과하나 — 아니오

| 설정 | 찍힌 방향 | 막는 관문 |
|---|---|---|
| 현재 값 | **없음** | 정면 A자: openArmsWider 78%. reach ≥ 0.8은 0/516. 그다음은 가운데 관문(좌우 12%) |
| A자 끔(reach 0, drop 제한 없음) | 정면 3.2 s | 제자리 관문 returnToStart 48%(발 이동 > 0.03이 66%), moveToCentre 9% |
| A자 끔 + 제자리·가운데 끔 | 정면 3.2 s, 뒷면 18.9 s | 사선 두 장: 0.8초 멈춤 없음(R6). turnedTooFar 34% |
| 권고값 F2+F3(reach 0.5, drop 1.05, 발 0.08, 중심 이동 0.15, 가운데 0.10) | 정면 3.2 s, 뒷면 18.9 s | 사선 멈춤 없음(R6) |
| 90° 회전 버퍼(기기 상태) | **없음** | FULL 60%, FWD 38%(R1) |

- 이 영상으로는 사선 두 장을 검증할 수 없다. 기기에서 안내를 들으며 도는 실행이 필요하다(E2).

## 6. #64가 바꾼 것 (그리고 #66·#67)

- #64 `e13d558`(16:40, 녹화 16:15 이후)는 Flutter 화면만 바꿨다. `onboarding_scan_screen.dart`와 테스트다.
  - 말풍선을 위로 올려 실시간 안내 한 줄짜리 알약 모양으로 바꿨다. 방향별 힌트 두 줄("카메라 보고 팔은 A자로, 발은 어깨너비로…")은 없앴다.
  - 상태 칩을 한 줄로 바꿨다.
  - 디버그 빌드(`kDebugMode`) 전용 '테스트용 촬영' 버튼을 넣었다. 사진 없이 화면 상태만 넘기고, 4번째에 네이티브 세션을 취소한다. 업로드도 건너뛴다.
- 네이티브·엔진은 바뀌지 않았다. **실패는 그대로다.**
- 좋아진 점은 하나다. 화면 아래 0.77–0.86을 덮던 말풍선이 사라져서, 사용자가 자기 발을 볼 수 있다.
- 남는 점
  - 위로 간 말풍선이 화면 약 0.17–0.21에 있어서, 바르게 선 사용자의 얼굴 높이와 겹칠 수 있다(추정).
  - A자 힌트가 없어져서, 사용자는 "팔을 몸에서 조금 더 떼서 A자로!"가 나올 때까지 A자 요구를 모른다.
- 테스트 버튼은 Release(liftdev)에는 없다. 실제 촬영 대신 쓸 수도 없다.
- #66 `42271fe`(분석 화면 로딩 문구)와 #67 `f953336`(푸시업 가로 화면)은 캘리브레이션 코드를 건드리지 않는다.
  - #67의 `lockLandscape()`는 푸시업 화면에서만 부르고, 끝나면 `lockPortrait()`로 되돌린다.

## 7. 수정 명세 (수정 에이전트용)

공통 조건
- 서버 키포인트 업로드 계약을 바꾸지 않는다.
  - manifest 필드와 `coco17_pixel_unmirrored`는 그대로다.
  - 키포인트는 저장한 JPEG의 픽셀 좌표다.
- 안내 문구는 `ai/kori-short-meb301ad` 담당이다. 여기서는 로직만 바꾼다.
- 우선순위: F1·F2는 P0, F3·F4·F5는 P1, F6은 P2. F7(진단)은 F1과 같이 넣는다.

### F1 (P0) 분석 그림을 늘 수평으로 — `CalibrationSession.swift`

- 할 일: `CalibrationCaptureManager`가 "버퍼를 시계 방향으로 몇 도 더 돌려야 수평인지"(`residualDegrees`, 0/90/180/270)를 알려 준다. `handle()`은 그만큼 `CIImage`를 돌린 뒤 분석·저장한다.
  1. `applyPortraitRotation`(488-500)
     - 코디네이터의 `videoRotationAngleForHorizonLevelCapture`를 **그대로** 쓴다. 지원되면 연결에 적용한다. 493줄의 "90/270이 아니면 90" 강제를 지운다.
     - 적용 뒤 `connection.videoRotationAngle`을 다시 읽어 `appliedAngle`로 저장한다.
     - iOS 16 경로(`videoOrientation = .portrait`)는 그대로 두고, `appliedAngle = horizonAngle = 90`(잔여 0)으로 둔다.
  2. 코디네이터의 `videoRotationAngleForHorizonLevelCapture`를 KVO로 지켜본다.
     - 값은 락으로 감싼 변수에 둔다. `DeviceMotionMonitor`와 같은 방식이다.
     - 폰을 눕혀 둔 채 시작한 뒤 세우는 경우도 따라간다.
  3. 순수 함수 하나를 `CalibrationTypes.swift`에 둔다. 테스트 패키지에 심볼릭 링크로 들어가 있는 파일이다.
     `static func residualDegrees(horizon: Double, applied: Double) -> Int`
     = `(((Int(((horizon - applied) / 90).rounded()) % 4) + 4) % 4) * 90`
  4. `handle()`(181)
     - `residual != 0`이면 `CIImage(cvPixelBuffer:).oriented(o)`로 돌린다. 90 → `.right`, 180 → `.down`, 270 → `.left`.
       - `.right`가 시계 방향 90°인 것은 두 번 확인했다.
         - 2×1 그림(왼쪽 빨강, 오른쪽 파랑)에 `.right`를 주면 빨강이 위로 간다. 위아래 순서로 그리는 비트맵 기준이다.
         - 재생에서 바른 그림을 `.right`로 돌리면 머리가 오른쪽으로 간다.
     - extent 원점을 (0,0)으로 옮긴다. 분석기가 원점 0을 가정한다(`CalibrationFrameAnalyzer.swift:84-102`).
     - 이렇게 돌린 그림을 `analyzer.analyze`, `trackBestFrame`(JPEG·크기·intrinsics), `lastBufferAspect`에 똑같이 쓴다.
  5. `residual`이 이전 프레임과 다르면 한 번 `analyzer.reset()`과 `engine.invalidateFrame()`을 부른다. crop이 이전 픽셀 공간 기준이기 때문이다.
- intrinsics
  - 첨부값은 돌리기 전 버퍼 기준이다.
  - 90/270이면 기존 `looksRotated` 판정(346-369)이 fx↔fy를 바꾸고 주점을 가운데로 둔다. 지금 동작과 같으므로 그대로 둔다.
  - F7 진단에 첨부 원본을 남긴다.
- 미리보기: 녹화에서 바르게 보였으므로 이번에는 손대지 않는다. E2에서 미리보기 연결 각을 기록하고, 문제가 있으면 그때 `videoRotationAngleForHorizonLevelPreview`를 연결한다.
- 대안(F1이 기기에서도 실패할 때): 운동 카메라와 같은 설정으로 바꾼다.
  - 전면 `builtInWideAngleCamera` + `connection.videoOrientation = .portrait` 조합이다(`CameraPosePreview.swift:84-125`). 이 폰에서 매일 쓰는 경로다.
  - 이 경우 화각이 84° → 73°로 줄어 거리가 약 22% 늘어난다.
- 꼭 지킬 것
  - 저장 JPEG, 키포인트, `imageWidth/Height`가 모두 같은 그림(돌린 뒤) 기준이어야 한다.
  - 좌우 반전은 지금처럼 없다(unmirrored).

### F2 (P0) 정면 A자 — `CalibrationConfig.swift`

- `aPose.minWristReach` 0.8 → **0.5**
  - 손목이 몸 중심선에서 몸통 길이의 절반 이상 떨어지면 된다. 엉덩이 바깥선 근처다.
  - 녹화(16회)와 IMG_9900(3회)에서 유지 구간이 생기고, 기울기에도 여유가 있다.
- `aPose.maxWristDrop` 0.97 → **1.05**
  - 기울기 3–5°에서 한쪽 손목 drop이 0.98–1.03이 되는 것을 덮는다.
  - 정면 뒤 openArmsWider도 52% → 14%로 줄인다.
- 나머지 A자 값(minWristDrop 0.60, 팔꿈치 0.38–0.75, 발 간격 0.9–2.6)은 그대로 둔다. 두 영상에서 막지 않았다.
- 서버에 주는 영향
  - 서버 조건은 12관절 중 8개 이상이다.
  - 팔을 몸에 더 가깝게 둔 사진의 fit 정확도는 GPU로 재지 않았다(가설).

### F3 (P1) 제자리·가운데 — `CalibrationConfig.swift`

- `stance.maxFeetDrift` 0.03 → **0.08**, `stance.maxCentreDrift` 0.08 → **0.15**, `framing.maxCentreOffset` 0.06 → **0.10**.
- 근거: R3. 서버는 사진마다 transl을 맞추므로 제자리 조건이 fit에는 필요 없다. 화면 안에 있는지는 크기·가장자리 관문이 따로 지킨다.
- `calibration_silhouette.dart`의 Dart 기본값 `maxCentreOffset`도 같이 바꾼다. 네이티브가 `guide`로 보내므로 표시값은 맞지만, 기본값도 맞춰 둔다.

### F4 (P1) 좌우 기울기

- (a) 권장
  - `CalibrationEngine.measure()` 첫머리에서 측정용 키포인트 사본을 만든다. 화면비를 맞춘 좌표로, 그림 중심 기준 `-rollDeg`만큼 돌린다.
  - 모든 측정에 이 사본을 쓴다. `CalibrationFrame.keypoints`(저장·업로드되는 값)는 건드리지 않는다.
  - 그다음 `maxRollDeg` 3 → **10**.
  - 부호가 핵심이다.
    - `rollDeg = atan2(g.x, −g.y)`(`DeviceMotionMonitor.swift:31`)이고, 폰을 사용자 쪽에서 볼 때 시계 방향으로 돌리면 +다.
    - 좌우 반전이 없는 전면 버퍼에서는 장면이 화면상 시계 방향으로 같은 각만큼 돈다(추론).
    - 테스트와 E2에서 확인한다.
- (b) (a)를 미룰 때: `maxRollDeg` 3 → 5로만 넓힌다. F2의 `maxWristDrop 1.05`와 반드시 같이 바꾼다.

### F5 (P1) 실루엣 튐 — Flutter

- `onboarding_scan_screen.dart:90`: 새 업데이트에 `person`이 없으면 직전 `_person`을 0.5초 더 유지한다. 그 뒤에 null로 바꾼다.
  - 마지막으로 person을 받은 시각만 기억하면 된다(필드 하나).
  - 안내 문구로 분기하지 않는다. 문구는 바뀔 수 있다(kori-short). 사람이 화면을 떠나면 0.5초 뒤 저절로 기본 위치로 간다.
- R1이 고쳐지면 큰 튐(FULL↔FWD)은 사라진다. 이것은 기울기 관문이 켜졌다 꺼질 때와 관절이 한 프레임 빠질 때를 위한 것이다.

### F6 (P2) 하체가 잘렸을 때 "뒤로"

- `CalibrationEngine.process`에서 `measure()`가 nil인데 아래 조건이면 `showFullBody` 대신 `stepBack`을 낸다.
  - 양 어깨와 양 엉덩이는 ≥ 0.3
  - 무릎이나 발목이 < 0.3
  - 엉덩이 y 평균 > 0.55
- `framingGuidance`에서 `headTop < 0.02`이면서 `feet > 0.9`이거나 `bodyHeight > 0.75`이면 `stepBack`을 낸다.
- 대상은 녹화를 바로 세운 재생의 FULL 170프레임이다. 대부분 5.5–8.2 s, 다가가는 구간이다.
- 문구는 기존 `stepBack`을 쓴다.

### F7 진단 (F1과 함께) — `BPT_CALIB_DIAG=1`

Release 빌드에서도 env로 켠다. 끄면 동작 변화는 없다.
- `CalibrationDebugLog.isEnabled`를 `DEBUG || env BPT_CALIB_DIAG == "1"`로 바꾼다.
  - 같은 값이 미리보기 위 초록 디버그 글자(`CalibrationCameraPlatformView.swift:35-43`)도 켠다. 그러면 화면 녹화에 roll·pitch·bodyH·feet가 같이 찍힌다.
- 기록 폴더는 `Documents/calibration_diag/<세션ID>/`로 한다. 취소해도 지워지지 않는 곳이다. 지금은 세션 폴더라 취소하면 사라진다.
- `camera.json`(첫 프레임에 한 번)
  - 카메라: deviceType, activeFormat 가로·세로, sessionPreset, videoFieldOfView, iOS 버전, 기종
  - 회전: 코디네이터 capture 각, 연결에 요청한 각과 적용된 각, `isVideoRotationAngleSupported(0/90/180/270)`, `residualDegrees`
  - 버퍼: 첫 버퍼 `CVPixelBufferGetWidth/Height`, `isVideoMirrored`
  - intrinsics 첨부: 있는지, fx/fy/cx/cy
  - 미리보기 연결 각: 플랫폼 뷰가 알려 줄 수 있으면 넣는다
- `debug_frames.csv`: 기존 열에 `bufferW,bufferH,residualDeg,torso,headTop`을 더한다.
- `raw_<t>.jpg`·`analysis_<t>.jpg`: 처음 10초 동안 1초에 1장씩, 긴 변 960 px로 남긴다. 돌리기 전 버퍼와 분석 그림이다. 사용자 얼굴이 나오므로 폰과 `~/bpt-data`에만 둔다.

### 회귀 검사

1. `swift test --package-path ios/CalibrationEngineKit`: 기존 테스트가 모두 통과하고, 다음을 더한다.
   - `residualDegrees`: (90,90)→0, (90,0)→90, (0,90)→270, (270,90)→180, (−90,0)→270.
   - F4(a)를 할 경우
     - 정면 A자 합성 키포인트를 +8°와 −8°로 돌리고, 같은 rollDeg를 주면 측정값(bodyHeight, noseOffset, wristReach, wristDrop)이 0°와 ±0.01 안에서 같아야 한다.
     - 부호를 반대로 주면 실패해야 한다. 부호 고정용이다.
   - 바뀐 기본값을 확인하는 기존 테스트가 있으면 새 값으로 고친다.
2. 재생: `scripts/calib_rca` 또는 `calibration-replay`. 영상이 있을 때만 돌린다.
   - IMG_9900(새 기본값): 정면 ≤ 3.5 s, 뒷면이 찍혀야 한다. stepForward는 0프레임이어야 한다.
   - 녹화(`--hflip --pad-aspect 0.5625 --step 2`): 정면 ≤ 3.5 s, stepForward 0프레임.
   - F4(a)를 할 경우: `--tilt-image ±8 --roll ±8 --set maxRollDeg=10`(부호는 구현에 맞춤)에서 두 영상 모두 정면이 찍혀야 한다.
     - 참고: 되돌림 없이 F2+F3 값만 쓰면 +8°에서 녹화는 32.1 s(끝 무렵)에야 찍히고, IMG_9900은 정면이 없다. −8°는 둘 다 찍힌다. + 기울기에서 코 위치가 한도 0.08에 더 가깝게 밀리기 때문이다(녹화 중앙값 +8° 0.078, −8° 0.064).
   - `--rotate 90`은 고친 뒤에도 FULL/FWD만 나온다. 재생 도구는 세션의 F1을 거치지 않는다. 고장 패턴 확인용이지 통과 조건이 아니다.
   - 더미(`outputs/calibration_dummy_videos/` v1 3개, v2 3개): 현재 값에서 찍히는 장수보다 적으면 안 된다.
     - 현재 값: 6개 모두 0장.
     - F2+F3 값: v1 dummy_03이 **4장**(정면 0.9 s, 왼쪽 5.8 s, 뒷면 11.6 s, 오른쪽 19.5 s), 나머지 5개는 0장.
       - v1 dummy_01·02는 lowerArms·widenFeet·가운데 관문에서 막힌다. People Snapshot 자세가 BPT 안내와 달라서다.
       - v2 3개는 6–8초짜리 연속 회전이라 0.8초 멈춤이 없다.
3. `flutter test` 전체(촬영 화면 테스트 포함). iOS 빌드도 한다.
4. 기기 E2(8절)가 통과 조건을 만족해야 한다.

## 8. 기기 실험 절차

- 사람 1명(사용자)이 카메라 앞에 서야 한다.
- 기기 에이전트가 실행한다. 폰 점유는 약 10분이다: 설치 2–3분, 촬영 4–5분, 회수 1–2분.
- Mac 빌드는 무거운 작업 잠금 아래에서 10–15분 걸린다.

**E1(선택): 기전만 먼저 확인할 때**
- 지금 코드(`f953336`)에 F7 진단만 넣은 빌드로, 아래 E2와 같은 순서로 1회 돌린다.
- `camera.json`으로 M1과 M3를 가른다.
  - M1이면 `appliedAngle`이 0이거나 `isVideoRotationAngleSupported(90)`이 거짓이다. 버퍼는 3840×2160이다.
  - M3이면 코디네이터 각이 90이 아니다(예: 0). 적용 각은 90이다.
- `raw_*.jpg`에서 사람이 누워 있으면 R1이 확정된다.
- F1이 M1과 M3를 모두 덮으므로, 시간이 없으면 건너뛰고 E2만 한다.

**E2: 고친 빌드 확인**
1. 빌드와 설치: 수정 브랜치(F1, F2, F7, 가능하면 F3–F5)를 com.bpt.liftdev Release로 빌드해 설치한다. 기기 에이전트의 평소 서명·설치 절차를 따른다.
2. 실행
   ```
   xcrun devicectl device process launch --device <UDID> --terminate-existing \
     --environment-variables '{"BPT_CALIB_DIAG":"1"}' com.bpt.liftdev
   ```
3. 사용자 동작(약 4분)
   - 시작: 제어 센터에서 화면 녹화를 켠다. 홈 → 체형 촬영 → 카메라 켜기. 폰을 세로로 허리 높이에 세운다.
   - 정면(0–15 s): 1.5–2 m 앞에 선다. 머리부터 발까지 보이게, 팔은 A자로(손목이 엉덩이에서 손 한 뼘), 발은 어깨너비. 정면이 찍힐 때까지 그대로 선다.
   - 돌기: 찍히면 왼쪽으로 천천히 돈다. 비프와 안내를 따라 약 60°에서 2초, 등에서 2초, 반대 사선에서 2초 멈춘다.
   - 가까이: 4장을 다 찍었거나 90초가 지나면 무릎 아래가 잘릴 만큼 다가가 5초 선다. "뒤로" 경로 확인용이다.
   - 기울이기(F4를 넣었으면): 폰을 손으로 좌우 약 5°씩 3초 기울인다. 부호 확인용이다.
   - 끝: ×로 닫고 화면 녹화를 멈춘다.
4. 회수
   ```
   xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer \
     --domain-identifier com.bpt.liftdev --source Documents/calibration_diag \
     --destination ~/bpt-data/user_tests/<날짜>/calibration_diag
   ```
   - 4장을 다 찍었으면 세션 폴더 `Documents/calibration/<세션ID>/`(사진 4장과 manifest.json)도 같은 명령으로 받는다. `--source Documents/calibration`으로 바꾸면 된다.
   - 화면 녹화는 AirDrop으로 `~/bpt-data`에 둔다. git과 외부 서비스에는 올리지 않는다.
5. 통과 조건
   - 기전
     - `camera.json`의 `residualDegrees`로 실제 기전(M1/M3/둘 다 아님)을 확인한다.
     - `analysis_*.jpg`에서 사람이 서 있어야 한다(세로, 머리가 위).
   - 판정
     - `debug_frames.csv`의 bodyH·feet가 같은 시각 녹화 화면과 0.05 안에서 맞아야 한다.
     - 안내에 A자·멈춤 같은 문구가 나와야 한다. FULL/FWD만 나오면 실패다.
   - 촬영
     - A자로 서서 10초 안에 정면이 찍혀야 한다.
     - 안내를 따라 돌면 90초 안에 4장이 찍혀야 한다.
     - 무릎 아래가 잘렸을 때 "앞으로 와"가 0번이어야 한다.
     - 4장을 다 찍으면 manifest의 키포인트가 JPEG 위에 맞게 올라가야 한다(계약 확인).

## 9. calib_fix 메모(d9dc55f) 대조

- 발견 1 "기기와 재생이 다르다": 맞다. 원인은 화각이나 crop이 아니라 **회전**이다(R1 표). 메모의 가설 (b)가 맞고, (a)와 (c)는 재현되지 않는다.
- 발견 2 "발목 < 0.3 → 발끝까지": 맞다. 다만 사용자가 겪은 "앞으로 와"의 원인은 아니다(R5).
- 발견 3 "IMG_9900은 A자에서 78% 막힌다": 맞다.
  - 실제로 막는 값은 `minWristReach`다.
  - `maxWristDrop`은 기울기가 있을 때와 정면 뒤에서 문제가 된다.
- 발견 5 "3°는 이번 원인 아님": 맞다. 서버가 중력을 안 쓰는 것도 맞다.
  - 하지만 앱 판정이 roll에 민감하다. 그래서 그냥 넓히면 안 되고, 보정하거나 5°까지만 넓힌다(4절).

## 부록 A. 재현

```
W=.claude/worktrees/ai-calib-rca     # 이 브랜치
lockf -k /tmp/bpt-heavy.lock nice -n 10 swift build -c release --package-path $W/scripts/calib_rca
B=$W/scripts/calib_rca/.build/release/calib-rca
V=~/bpt-data/user_tests/2026-10-22
$B $V/IMG_9900.MOV img_base.csv                                         # 현재 값
$B --hflip --pad-aspect 0.5625 --step 2 $V/screenrec_161547.mp4 rec_base.csv
$B --hflip --pad-aspect 0.5625 --step 2 --rotate 90 $V/screenrec_161547.mp4 rec_rot90.csv   # 기기 상태 재현
$B --set minWristReach=0.5 --set maxWristDrop=1.05 --set maxFeetDrift=0.08 \
   --set maxCentreOffset=0.10 --set maxCentreDrift=0.15 $V/IMG_9900.MOV img_fin.csv
$B ... --tilt-image 5 ...                                              # 폰 좌우 기울기 흉내
conda run -n bpt-eval python -I $W/scripts/calib_rca/summarize.py *.csv   # 안내 분포·시간표·관절 누락·관문 값 분포·통과 깔때기
```

- 안내 OCR: `scripts/calib_rca/ocr_bubble.swift`(머리말의 ffmpeg 자르기 명령).
- 실루엣 발 위치: 녹화 프레임을 0.001 눈금으로 잘라 눈으로 읽었다. t=2.0 s 0.641, t=3.0 s 0.624.
- 거리 추정(참고): 84° 세로 화각에서 몸 높이 0.70이면 약 1.4–1.5 m다. "약 2 m"보다 가깝다(추정).
