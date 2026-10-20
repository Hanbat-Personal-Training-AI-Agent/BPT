# 자세 판정 규칙의 근거 만들기 — 결과 (ai/rules-calib)

사전 등록: [rules_calib_prereg.md](rules_calib_prereg.md)(8eb5841, held-out 결과 보기 전). 실행 기록: Home `~/bpt-runs/rules-calib/<run-id>/manifest.json`. **실험 결과만 적는다.** 기본값·번들·병합은 바꾸지 않았다(새 규칙은 `BPT_RULES=<이름>` / pose-replay `--rules <이름>` 뒤에서만).

## 진행 상황 (2026-10-20 ~20:45, 체크포인트)

### 끝난 것
- 브랜치: `ai/rules-calib` = origin/ai/lift-app-m2b98256(1431a7e) 위.
  - 8eb5841: 사전 등록.
  - 6eed051: 새 3D 지표·규칙 14개(기본 꺼짐), `FormRulePreset`, Python 판정 미러.
- 테스트: swift test 128 통과(1 건너뜀), pytest 200 통과. 앱(Runner) 빌드는 아직 확인 안 함 — CameraPosePreview 변경이 있다.
- 문헌 확인:
  - 원문 확인: FMS 깊은 스쿼트 기준(Cook 2006, NAJSPT 1(2):62–72, PMC2953313), KASR(Mizner 2012, CJSM 22(3):221–227 — 컷오프 없음, 정상 여자 선수 평균 0.76 ± 0.15), Fenwick·Brown·McGill 2009(JSCR 23(2):350–358, 로우 자세 서술, 수치 없음).
  - 2차 출처만 확인: FM 7-22, FitnessGram 90°.

### 돌고 있는 것
- 공개 조정 2D 채우기(Mac): 스쿼트 72, 푸시업 45클립. 코드는 2ef3ced pose-replay(held-out 2D와 같은 커밋)다. 끝나면 held-out 3클립을 다시 돌려 기존 CSV와 같은지 확인한다.
  - Home `~/bpt-runs/rules-calib/20261020-pub-tune2d-2ef3ced`, `20261020-pub-repro3-2ef3ced`
- 원래 XS 3D 재생(Mac, 이 브랜치 pose-replay): 공개 held-out, Exercise3D, MM-Fit 순서.
  - Home `~/bpt-runs/rules-calib/20261020-e2e-orig-<commit>/`

### 남은 단계(순서)
1. 원래 XS: 공개 조정 3D 재생(2D 채우기가 끝난 뒤).
2. C1 Core ML(scratch 복사본, 비상업)로 같은 재생을 한다. C2는 학습(~20:50)과 Core ML 변환이 끝난 뒤.
3. Fit3D(Home CPU, PyTorch): 모캡, 원래, C1, C2. 새 지표, 카메라-위와 실제 중력, 시점 게이트 미러.
4. 도출(모델별 출처는 사전 등록 §3) → 임계값 → `pose_feedback/rules/xs_{orig,c1,c2}_rc1.json` + Swift 프리셋 → held-out 평가 1회 → 이 문서 A–G.
5. 앱 빌드 확인(`flutter build ios --debug --no-codesign`).

### 폰에서 보고 싶은 것(요청은 하지 않음 — 조정자 부재 중)
- `BPT_RULES=xs_orig_rc1`로 실제 Runner 카메라 앱을 돌려 본다. 확인할 것:
  - 정상 렙에서 새 키(로그 전용) 발화율, praise_good 빈도.
  - 폰을 앞뒤로 15° 기울였을 때 row_hinge_shallow의 몸통 평균(카메라-위)이 얼마나 변하는지. 이것으로 `BPT_3D_GRAVITY`가 필요한지 판단한다.
