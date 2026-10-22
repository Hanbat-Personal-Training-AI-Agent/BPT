# 오경보 큰 키 6개를 기본 전달에서 뺌 (D-M-04)

브랜치 `ai/quiet-keys-m2b98256`(origin/integration/ai 2b98256에서). **사용자 결정 2026-10-22 "추천대로 진행"** — `docs/results/rules_calib.md`(ai/rules-calib 4deb16c) F1(R5) 승인. R6(rc1 기준값 기본 채택)은 승인되지 않아 **기준값은 하나도 바꾸지 않았다**.

## 바뀐 것
- `FormWarningTracker.quietByDefault`(FormWarnings.swift) = 아래 6개. `FormCommonConfig.enabledFeedbackKeys` 기본값에서 뺀다.
- Flutter로 가는 말풍선·음성(onFeedback)과 세트의 worstJoint에서 빠진다. **판정은 그대로 돌고** `FormRepReport.warnings`, 세션 로그, 세트 횟수, pose-replay(모든 키를 켬)에는 남는다.
- 다시 켜기: 코드에서 `quietByDefault`에서 키를 빼거나, `tracker.common.enabledFeedbackKeys.insert("<key>")`.

| 키 | 현재 기준 오경보(held-out 정상 렙, m Halpe26 입력·원래 XS; Fit3D / 공개 / Ex3D) |
|---|---|
| squat_no_lockout | – / 52% / 19% |
| squat_knee_valgus | 90% / 63% / 29% |
| pushup_no_lockout | – / 23% / – |
| pushup_hip_pike | – / 11% / – |
| pushup_shallow | – / 11% / – |
| pushup_head_up | – / 10% / – |

무릎 모임 원인(기기 에이전트): 27–34° 사선이 "정면"으로 분류되고, 그 시점에서는 무릎/발목 간격비가 늘 0.45–0.8이라 기준 1.0 아래로 떨어진다.

## 확인
- `swift test`(CalibrationEngineKit): 104 통과. `testFeedbackDefaultAndPerKeyFlag`가 기본 집합에 6개가 없는 것, 키 이름이 실제 규칙 키인 것, 기본 트래커에서 pike가 판정·기록되지만 보내지지 않는 것을 확인한다.
- `flutter analyze` 문제 없음, `flutter test` 98 통과, `flutter build ios --debug --no-codesign` 성공(Runner.app).

## 다른 브랜치로 옮기기 (이 브랜치에서는 손대지 않음)
두 브랜치 모두 2b98256 위에 있고 기본 집합이 같은 식(`allKeys.subtracting(keysWithoutFlutterLines)`)이다.
- `ai/halpe-default-m2b98256`(7db0b33): FormWarnings·테스트를 건드리지 않아 `git cherry-pick <이 커밋>`이 충돌 없이 들어간다(merge-tree로 확인).
- `ai/lift-app-m2b98256`(dfe4b6c): FormWarnings.swift는 자동 병합된다. `FormWarningsTests.swift`의 `testFeedbackDefaultAndPerKeyFlag`에서 충돌이 난다 — 그 브랜치 쪽 테스트를 두고 `delivered`에 `.subtracting(FormWarningTracker.quietByDefault)`와 이 커밋의 assert 3개(키 이름·disjoint·pike 미전달)를 손으로 넣으면 된다.
