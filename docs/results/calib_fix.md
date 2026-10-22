# 체형 촬영(캘리브레이션)이 안 찍히는 문제 — calib_fix

- 사용자 보고: 2026-10-22 16:20 "캘리 겁나 안됨". 정면(1/4)에서 끝까지 안 찍힘.
- 브랜치: `ai/calib-fix-mf953336`(origin/integration/ai `f953336`에서 분기). 분석 메모 `ai/calib-fix-meb301ad`를 병합했다.
- 상태: **F1–F7 구현 완료, 기기 확인(E2) 대기**. 임계값은 모두 **제안값**이다. 사용자 승인 전에는 integration에 병합하지 않는다.
- 원인과 명세: `docs/results/calib_root_cause.md`(`ai/calib-rca-meb301ad` 5fd6cde). 아래 "분석 메모"는 그 전에 쓴 1차 메모이고, 결론은 근본 원인 문서를 따른다. 메모의 가설 (b) 회전이 맞았고, (a)·(c)는 기각됐다.

## 분석 메모

### 자료 (git 밖)

사용자 얼굴이 나오므로 저장소에 넣지 않는다.

- `~/bpt-data/user_tests/2026-10-22/screenrec_161547.mp4` — 실패한 촬영 화면 녹화. 38 s, 1206×2622. #64 이전 화면이다: 말풍선과 버튼이 아래에 있다.
- `~/bpt-data/user_tests/2026-10-22/IMG_9900.MOV` — 사용자가 만든 테스트 영상. 1080×1920, 22 s. 전신이 보이는 거리에서 정면, 옆, 뒤, 옆 순서로 돈다.

### 재생 방법

`calibration-replay`는 앱의 `CalibrationFrameAnalyzer`와 `CalibrationEngine`을 그대로 쓴다. 폰은 똑바로 서 있고 움직이지 않는다고 가정한다.

```
swift build -c release --package-path ios/CalibrationEngineKit --product calibration-replay
ios/CalibrationEngineKit/.build/release/calibration-replay --overlay --output-dir <dir> \
  ~/bpt-data/user_tests/2026-10-22/IMG_9900.MOV <screenrec 좌우반전본>.mp4
```

화면 녹화는 미리보기를 좌우 반전해 보여 준다. 그래서 `ffmpeg -vf hflip`으로 되돌려서 넣었다. 미리보기는 9:16 버퍼를 aspect-fill로 그리므로 세로 범위는 버퍼 전체와 같고, 좌우만 잘린다. 녹화에는 실루엣 선과 UI가 덮여 있어서 버퍼와 똑같지는 않다.

### 재생 결과 (수정 전, eb301ad. 이 구간의 네이티브 캘리브레이션 코드는 2b98256과 같다)

| 영상 | 프레임 | 가장 많은 안내 | 촬영 |
|---|---|---|---|
| IMG_9900 | 658 | 팔 A자로 516 (78%), 오른쪽/왼쪽으로 77, 뒤로 33, 발끝까지 21 | **없음** |
| 화면 녹화 | 2281 | 팔 A자로 1284 (56%), 뒤로 621, 발끝까지 229 | **없음** |

### 발견 1 — 기기와 재생이 다른 판정을 낸다 (가장 큰 미해결 문제)

녹화 속 말풍선은 처음부터 끝까지 "조금만 앞으로 와 줘!"(stepForward)와 "머리부터 발끝까지"(showFullBody)만 오갔다. "팔 A자로"는 한 번도 나오지 않았다. 반면 같은 장면을 재생하면 t ≈ 0–5 s에서 bodyH 0.63–0.75가 나오고, 거리 관문을 통과해 A자 관문에서 막힌다.

녹화 t ≈ 1 s 프레임을 직접 재 보면:
- 머리 꼭대기 y ≈ 0.11, 발 y ≈ 0.77이고, 몸 높이는 약 0.66이다.
- 그런데 실루엣은 '맞지 않음' 상태의 기본 크기(0.62)로 그려졌다. 실루엣 발은 y ≈ 0.61에 있다.
- 따라서 기기 엔진이 받은 `person`은 feet ≈ 0.61, bodyHeight < 0.40이다(stepForward 조건).
- 미리보기에 보이는 몸보다 대략 0.4–0.6배 작고 위치도 다르다.

기기 엔진이 분석하는 버퍼가 미리보기에 보이는 화면과 다르다는 뜻이다. 가설은 다음과 같고, 모두 기기에서 확인하지 못했다.
- (a) 전면 초광각(iPhone 17, F10, 2026-10-11 도입)에서 `AVCaptureVideoDataOutput` 버퍼와 `AVCaptureVideoPreviewLayer`의 화각이나 크롭이 다르다. F10 기록에도 "실기기 1회 확인 필요"로 남아 있고, 초광각 도입 뒤 실기기에서 4장을 다 찍은 기록은 찾지 못했다.
- (b) `applyPortraitRotation`의 회전 각도(RotationCoordinator가 준 90/270, 또는 지원 안 됨)가 맞지 않아, 버퍼 속 사람이 눕거나 뒤집혀 있다. 이 경우 RTMPose가 엉뚱한 자세를 내고, 세로 길이가 짧게 재져 stepForward가 나온다.
- (c) iOS 26 / iPhone 17 전면 카메라의 자동 프레이밍(Center Stage 계열)이 버퍼와 미리보기에 다르게 적용된다. `isCenterStageEnabled = false`는 이미 설정되어 있다.

확인할 방법은 기기 세션 폴더의 `debug_frames.csv`(bodyH, feet, midX)와 캡처한 원본 버퍼 1장을 같은 시각의 화면과 비교하는 것이다. 취소한 세션은 지워지므로, 취소해도 남기는 디버그 경로나 `formatWidth/Height`, `videoRotationAngle` 로그가 필요하다.

### 발견 2 — "앞으로 와"와 "발끝까지"가 서로를 부르는 순환

`CalibrationEngine.framingGuidance` 순서는 다음과 같다.
1. 크기 > 0.85 → 뒤로
2. 머리·발이 가장자리 → 발끝까지
3. 크기 < 0.40 → 앞으로

발목이 신뢰도 0.3 아래면 `measure()`가 nil을 돌려주고, 곧바로 showFullBody가 나온다. 이때 "뒤로 가라"는 정보가 없다.

녹화에서 일어난 일은 이렇다.
- 사용자가 "앞으로 와"를 따라 다가갔다(t ≈ 6 s 이후 무릎 아래가 화면 밖).
- 그러자 발목을 잃어 "발끝까지"가 나왔다.
- 기기 판정은 여전히 몸을 작게 보니 다시 "앞으로"가 나왔다.

발견 1이 해결되면 이 순환의 앞쪽 절반은 사라진다. 그래도 발목이 화면 밖일 때 "발끝까지"가 아니라 "뒤로"를 말하게 하는 것은 따로 필요하다(과제 요구사항). 예: 어깨·엉덩이는 신뢰도가 있고 무릎이나 발목이 아래 가장자리에 붙었거나 신뢰도가 낮을 때 → stepBack.

재생에서도 사용자가 가까울 때(녹화 t 6.8–15 s) RTMPose는 화면 밖 발목을 아래 가장자리 근처(feet ≈ 0.86)에 지어낸다. 그러면 bodyH > 0.85가 되어 "뒤로"가 나온다. 재생 쪽은 이미 맞게 말한다.

### 발견 3 — A자 관문이 이 사용자에게 너무 엄격하다

IMG_9900에서 사용자는 팔을 몸 옆에 살짝 띄운 채로 선다. 앱 도움말의 "A자"보다 좁다.
- `wristReach`(몸 중심과 가까운 손목 사이 거리 / 몸통)의 중앙값은 0.38이다. 기준 0.8을 넘은 프레임은 516개 중 0개다.
- `wristDrop`도 절반(256/516)이 상한 0.97을 넘는다.
- 화면 녹화에서도 A자 관문에 걸린 프레임 1284개 중 7개만 기준을 넘었다.

"IMG_9900이 정면, 옆, 뒤, 옆을 제때 통과"하려면 A자 기준(`minWristReach`, `maxWristDrop`)을 낮추는 결정이 필요하다. 서버 fit이 팔을 몸통과 분리할 수 있는 최소 간격이 근거가 되어야 한다. 재생 도구의 `--lenient-pose`(reach 0.2, drop 1.15, 발 간격 0.5)로 상한·하한을 미리 볼 수 있다.

### 발견 4 — 화면 겹침 (#64 반영 후)

녹화 시점(#64 이전)에는 말풍선이 화면 y ≈ 0.77–0.86, 버튼이 y ≈ 0.88–0.94에 있었다. 그래서 사용자 눈에는 발이 UI 뒤에 숨었다. 판정은 원본 버퍼로 하므로, 판정에는 영향이 없고 사용자가 자기 발을 못 보는 문제다.

#64(e13d558)는 말풍선을 위로 올리고 버튼을 한 줄로 바꿨다. 디버그 빌드 전용 '테스트용 촬영' 버튼도 추가했다. 새 화면에서 발 영역이 가려지는지는 새 녹화로 다시 봐야 한다. 엔진 쪽 수정은 필요 없다.

### 발견 5 — 좌우 기울기 3° 제한 검토

`maxRollDeg = 3.0`이고, 다른 모든 관문보다 먼저 검사한다.
- 녹화에서는 마지막에 폰을 집어 들 때만 "폰이 기울었어"가 나왔다. 이번 실패의 원인은 아니다.
- 다만 벽이나 물건에 기대 세운 폰은 3°를 쉽게 넘는다.
- 서버는 사진마다 중력 방향을 받는다(manifest). 그래서 3°는 판정 정확도보다 사용 편의 쪽 제약일 가능성이 크다.
- 5–8°로 넓히는 안은 서버 fit 영향(roll 보정 여부)을 확인한 뒤 결정한다. 확인 전에는 바꾸지 않는다.

### 수정 방향 (보류. max 분석 결론 뒤 확정)

1. 발견 1의 원인을 기기 로그로 확정하고, 그 층에서 고친다. 버퍼와 미리보기를 맞추거나, 회전을 바로잡거나, 광각으로 되돌린다.
2. 발목·무릎이 아래 가장자리 밖이면 showFullBody 대신 stepBack을 말한다. 엔진 한 곳만 고치면 된다.
3. A자와 발 간격 기준은 서버 영향을 확인한 뒤 조정한다.
4. 두 영상 재생을 회귀 검사로 남긴다. 영상은 `~/bpt-data`에만 두고, 검사는 파일이 있을 때만 돌린다.
- 서버 업로드 계약(키포인트 묶음)은 바꾸지 않는다.
- 안내 문구는 `ai/kori-short-meb301ad` 담당이므로 로직만 바꾼다.

## 수정 (F1–F7)

근거는 `calib_root_cause.md` 1–4절과 7절이다.
- 서버 업로드 형식(manifest 필드, `coco17_pixel_unmirrored`, JPEG 픽셀 좌표)은 그대로다.
- 안내 문구는 바꾸지 않았다. "뒤로" 안내는 기존 `stepBack`을 쓴다. `ai/kori-short-*`를 병합하면 문구가 "뒤로 한 걸음!"이 된다.

| 번호 | 바꾼 것 | 파일 |
|---|---|---|
| F1 (P0) | 분석 그림을 늘 바로 세운다. 회전 각도를 "90°가 아니면 90°로" 강제하던 코드를 지웠다. 연결에는 코디네이터의 수평 각을 그대로 요청한다. 실제로 적용된 각을 다시 읽고, 수평 각은 KVO로 따라간다. 둘의 차이 `residualDegrees`(0/90/180/270, 시계 방향)만큼 프레임마다 `CIImage`를 돌린 뒤 분석·저장·intrinsics에 같은 그림을 쓴다. 이 차이가 바뀌면 분석 crop과 엔진의 유지 상태를 초기화한다 | `CalibrationSession.swift`, `CalibrationTypes.swift`(`CalibrationRotation.residualDegrees`) |
| F2 (P0) | `minWristReach` 0.8 → **0.5**, `maxWristDrop` 0.97 → **1.05** (제안값) | `CalibrationConfig.swift` |
| F3 (P1) | `maxFeetDrift` 0.03 → **0.08**, `maxCentreDrift` 0.08 → **0.15**, `maxCentreOffset` 0.06 → **0.10** (제안값). Dart 기본값도 0.10으로 맞췄다 | `CalibrationConfig.swift`, `calibration_silhouette.dart` |
| F4 (P1) | 판정 전에 키포인트를 폰 roll만큼 화면 가운데 기준으로 되돌린다(`CalibrationEngine.levelled`, 측정용 사본). `maxRollDeg` 3 → **10** (제안값). 저장·업로드하는 키포인트는 원본 그대로다 | `CalibrationEngine.swift`, `CalibrationConfig.swift` |
| F5 (P1) | 측정값(person)이 없는 업데이트가 와도 직전 실루엣을 0.5초 유지한다 | `onboarding_scan_screen.dart` (필드 하나와 분기 하나. 팀원 화면은 그 밖에 손대지 않았다) |
| F6 (P2) | 하체가 잘리면 "뒤로"를 낸다. 두 경로가 있다. ① 측정 실패 중 어깨·엉덩이는 신뢰도가 있고, 무릎·발목 중 하나가 < 0.3이며, 엉덩이 y > 0.55일 때 `showFullBody` 대신 `stepBack`. ② 머리 꼭대기가 잘렸고(< 0.02) 발 > 0.9이거나 몸 높이 > 0.75일 때 `stepBack`. 기준값 3개는 `framing.cutLegsMinHipY / cutHeadMinFeet / cutHeadMinBodyHeight`에 있다 | `CalibrationEngine.swift`, `CalibrationConfig.swift` |
| F7 | `BPT_CALIB_DIAG=1` 진단 기록. 아래 "기기 실험" 절에 내용이 있다 | `CalibrationDebugLog.swift`, `CalibrationSession.swift`, `CalibrationStore.swift`(`deviceModel` 공개) |

### F1의 각도 계산

- 기전 M1에서는 `appliedAngle` = 0, 수평 = 90이므로 잔여는 90이고 `.right`로 돌린다.
- 기전 M3에서는 수평 = 0인데 예전 코드가 90을 적용했다. 고친 코드는 0을 요청하므로 잔여가 0이 된다. 0이 지원되지 않아 90이 남아 있으면 잔여는 270이고 `.left`로 돌린다.
- 계산식은 Apple의 각도 정의(시계 방향 회전)만 믿는다. 기기에서 실제 방향은 `camera.json`과 `analysis_*.jpg`로 확인한다(E2).
- 이 방식으로 못 잡는 경우가 하나 있다. 연결이 90을 적용했다고 보고하는데 버퍼가 실제로는 돌지 않은 경우다. 이때는 잔여가 0이라 잡지 못한다. `camera.json`의 `firstBufferWidth > firstBufferHeight`로 드러나며, 그러면 명세의 대안(전면 광각 + `videoOrientation = .portrait`)으로 간다.

### 제안 임계값 (채택은 사용자 승인 필요)

| 값 | 이전 | 제안 | 근거 |
|---|---|---|---|
| `aPose.minWristReach` | 0.8 | 0.5 | 녹화와 IMG_9900 모두 0.8에서 0.8초 유지가 0회. 0.5면 녹화 16회, IMG_9900 3회. 손목이 엉덩이 바깥선 근처 |
| `aPose.maxWristDrop` | 0.97 | 1.05 | 3–5° 기울기에서 한쪽 손목이 0.98–1.03. 정면 뒤 openArmsWider가 52% → 14% |
| `stance.maxFeetDrift` | 0.03 | 0.08 | 제자리에서 돌아도 발 이동 중앙값 0.034, p90 0.065. 서버는 사진마다 위치(transl)를 따로 맞춘다 |
| `stance.maxCentreDrift` | 0.08 | 0.15 | 몸이 돌면 어깨·엉덩이 중점이 0.07–0.10 움직인다 |
| `framing.maxCentreOffset` | 0.06 | 0.10 | 같음. 너비 6%는 1.5 m에서 ±8 cm |
| `device.maxRollDeg` | 3 | 10 | 키포인트를 roll만큼 되돌린 뒤에는 정면 코 위치가 밀리지 않는다. 서버는 gravity를 읽지 않는다. SAM 3D Body의 10° 정확도는 GPU로 재지 않았다(가설) |

서버 fit 정확도 영향(팔을 몸에 더 붙인 사진, 10° 돌아간 사진)은 GPU로 재지 않았다.

## 회귀 검사 결과 (2026-10-23)

| 검사 | 결과 |
|---|---|
| `swift test --package-path ios/CalibrationEngineKit` | 110개 통과. 새 테스트 7개: `residualDegrees` 6가지, ±8° roll 되돌림(측정값 ±0.01), 부호 반대면 실패, 프레임 키포인트 불변, 다리 잘림 → stepBack, 엉덩이가 높거나 어깨가 없으면 showFullBody 유지, 머리 잘림(크기 관문 안) → stepBack. 바뀐 값에 맞춰 roll 4° → 8°/−11°, 발 이동 0.04 → 0.09로 기존 테스트 2개를 고쳤다 |
| `flutter analyze` | 문제 없음 |
| `flutter test` | 109개 통과 |
| `flutter build ios --debug --no-codesign` | 성공(`Runner.app`, 190 s). Release 전용 경로(env 읽기 한 줄)는 기기 에이전트의 Release 빌드에서 컴파일된다 |
| 재생 `scripts/check_calibration_user_replay.py` | ALL PASSED (아래 표) |

### 재생 (calib-rca, 앱 엔진·분석기 심볼릭 링크)

| 영상 | 수정 전 (`f953336` 값, 그림 바름) | 수정 후 |
|---|---|---|
| IMG_9900 | 촬영 없음. openArmsWider 516/658 | **정면 3.2 s, 뒷면 18.9 s**. stepForward 0 |
| IMG_9900, 그림 +8° 기울임, roll −8 | 촬영 없음(명세 표) | 정면 4.0 s, 뒷면 18.9 s |
| IMG_9900, 그림 −8° 기울임, roll +8 | 2.4 s(되돌림 없이 F2+F3만 썼을 때) | 정면 2.4 s, 뒷면 18.9 s |
| 화면 녹화 (`--hflip --pad-aspect 0.5625 --step 2`) | 촬영 없음. openArmsWider 642/1141, 가까이 선 5.5–15.5 s는 stepBack 215 · showFullBody 85 | **정면 2.8 s**. stepForward 0. 가까이 선 5.5–15.5 s는 **stepBack 300/300** |
| 화면 녹화 +8° / roll −8 | 32.1 s(되돌림 없이) | 정면 4.6 s |
| 화면 녹화 −8° / roll +8 | 3.1 s | 정면 3.1 s |
| 부호 반대(그림 +8°, roll +8) | – | 두 영상 모두 촬영 없음. 되돌림 부호가 고정됐다는 뜻이다 |
| 더미 v1 dummy_03 | 0장 | **4장**(0.88 / 5.8 / 11.6 / 19.5 s). 명세값과 같다 |
| 더미 v1 dummy_01·02, v2 3개 | 0장 | 0장. 명세대로다. People Snapshot 자세가 BPT 안내와 다르고, v2는 연속 회전이라 멈춤이 없다 |

- 사선 두 장(IMG_9900)은 여전히 안 찍힌다. 사용자가 사선 구간을 0.3–0.6초에 지나가기 때문이다(R6, 영상 한계). 기기 E2에서 안내를 들으며 확인한다.
- 기울임 재생의 부호 관례: `--tilt-image +θ`(그림을 반시계로 돌림) = 폰 roll −θ. 폰을 사용자 쪽에서 볼 때 시계 방향으로 돌리면 roll이 +이고, 좌우 반전이 없는 전면 버퍼에서는 장면이 시계 방향으로 돈다(추론). 기기 E2의 "기울이기" 단계에서 확인한다.
- F1은 재생 도구가 세션을 거치지 않아 재생으로 확인할 수 없다. 단위 테스트(`residualDegrees`)와 기기 E2로 확인한다.

다시 돌리는 법:
```
W=.claude/worktrees/ai-calib-fix
lockf -k /tmp/bpt-heavy.lock nice -n 10 swift build -c release --package-path $W/scripts/calib_rca
lockf -k /tmp/bpt-heavy.lock nice -n 10 conda run -n bpt-eval python -I $W/scripts/check_calibration_user_replay.py
```
- 사용자 영상은 `~/bpt-data/user_tests/2026-10-22/`에만 있다(git 밖). 없으면 그 항목은 건너뛴다.
- 더미 영상은 본 체크아웃의 `outputs/calibration_dummy_videos/`에서 찾는다.

## 기기 실험 (기기 에이전트용, `calib_root_cause.md` 8절)

빌드
- 이 브랜치(`ai/calib-fix-mf953336`)를 체험용 빌드(com.bpt.liftdev Release)에 합친다. 평소 서명·설치 절차를 따른다.
- 진단은 Release에서도 env로만 켜진다. env가 없으면 동작 변화가 없다.

실행
```
xcrun devicectl device process launch --device <UDID> --terminate-existing \
  --environment-variables '{"BPT_CALIB_DIAG":"1"}' com.bpt.liftdev
```

`BPT_CALIB_DIAG=1`이 켜는 것
- 미리보기 위 초록 디버그 글자(roll·pitch·bodyH·feet 등). 화면 녹화에 같이 찍힌다.
- `Documents/calibration_diag/<세션ID>/`. 취소해도 남는다.
  - `camera.json`(첫 프레임에 한 번)
    - 카메라: `deviceType`, `fieldOfViewDeg`, `formatWidth/Height`, `sessionPreset`, `model`, `iosVersion`
    - 회전: `horizonCaptureAngle`, `requestedAngle`, `appliedAngle`, `rotationSupported`(0/90/180/270), `residualDegrees`
    - 버퍼: `firstBufferWidth/Height`, `isVideoMirrored`
    - `intrinsicsAttachment`(fx, fy, cx, cy. 첨부가 없으면 null)
    - 미리보기 연결 각은 넣지 않았다. 세션이 미리보기 레이어를 모른다. 미리보기는 녹화에서 바르게 보였다.
  - `debug_frames.csv`: 기존 열에 `bufferW, bufferH, residualDeg, torso, headTop`을 더했다. 프레임마다 한 줄이다.
  - `raw_<t>.jpg`(돌리기 전 버퍼)와 `analysis_<t>.jpg`(판정한 그림). 처음 10초 동안 1초에 1장씩, 긴 변 960 px다. **사용자 얼굴이 나오므로** 폰과 `~/bpt-data`에만 둔다.
- 디버그 빌드에서는 env 없이도 켜진다. `debug_frames.csv`는 이제 세션 폴더가 아니라 이 진단 폴더에 쌓인다.

사용자 동작(약 4분, 사람 1명 필요)
- 시작: 화면 녹화를 켠다. 홈 → 체형 촬영. 폰을 세로로 허리 높이에 세운다.
- 정면: 1.5–2 m 앞에서 전신이 보이게 선다. 팔은 A자(손목이 엉덩이에서 한 뼘), 발은 어깨너비. 찍힐 때까지 그대로 선다.
- 돌기: 왼쪽으로 천천히 돈다. 비프를 따라 약 60°, 등, 반대 사선에서 각각 2초씩 멈춘다.
- 가까이: 4장을 다 찍었거나 90초가 지나면, 무릎 아래가 잘릴 만큼 다가가 5초 선다. "뒤로" 확인용이다.
- 기울이기: 폰을 손으로 좌우 약 5°씩 3초 기울인다. roll 부호 확인용이다.
- 끝: ×로 닫고 녹화를 멈춘다.

회수
```
xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer \
  --domain-identifier com.bpt.liftdev --source Documents/calibration_diag \
  --destination ~/bpt-data/user_tests/<날짜>/calibration_diag
```
- 4장을 다 찍었으면 `--source Documents/calibration`(사진 4장과 manifest.json)도 받는다.
- 화면 녹화는 AirDrop으로 `~/bpt-data`에 둔다. git과 외부에는 올리지 않는다.

통과 조건
- 기전
  - `camera.json`의 각도로 M1/M3/그 밖을 판정한다.
  - `analysis_*.jpg`에서 사람이 서 있어야 한다(머리가 위).
  - `firstBufferWidth > firstBufferHeight`인데 `residualDegrees`가 0이면 F1이 덮지 못한 경우다. 대안으로 전면 광각 + `.portrait`.
- 판정
  - `debug_frames.csv`의 bodyH·feet가 같은 시각 녹화 화면과 0.05 안에서 맞아야 한다.
  - A자·멈춤·돌기 안내가 나와야 한다. FULL/FWD만 나오면 실패다.
- 촬영
  - A자로 서서 10초 안에 정면이 찍혀야 한다.
  - 안내대로 돌면 90초 안에 4장이 찍혀야 한다.
  - 무릎 아래가 잘렸을 때 "앞으로 와"가 0번이어야 한다.
  - manifest 키포인트가 JPEG 위에 맞게 올라가야 한다(업로드 계약 확인).
- 기울이기
  - 5° 기울여도 "폰이 기울었어"가 나오지 않아야 한다.
  - 정면 판정(코 위치)이 흔들리지 않아야 한다. 흔들리면 roll 부호가 반대다. 이때는 `levelled`의 θ 부호를 바꾸고 테스트 `testRollIsLevelledBeforeMeasuring`도 함께 고친다.
