# 자세 판정 규칙의 근거 만들기 — 결과 (ai/rules-calib)

사전 등록: [rules_calib_prereg.md](rules_calib_prereg.md)(8eb5841, held-out 결과 보기 전). 실행 기록: Home `~/bpt-runs/rules-calib/<run-id>/manifest.json`. **실험 결과만 적는다.** 기본값·번들·병합은 바꾸지 않았다(새 규칙은 `BPT_RULES=<이름>` / pose-replay `--rules <이름>` 뒤에서만).

## 2026-10-20 22:40 KST 복구 점검 — A–G

### A. 확인한 사실
- Home의 공개 held-out(192클립), 기존 조정·Exercise3D(65+39클립), 추가 조정 part 1(54클립), Fit3D Halpe 실험 A C1 held-out 평가 프로세스 4개가 계속 실행 중이다. 재시작하지 않았다. Fit3D Halpe 원래 XS·모캡 출력은 `20261020-fit3d-h26A-orig`에 22:04 완료되었다.
- Mac의 추가 정상 조정 Halpe26 2D는 62클립 모두 완료되었다. 실행 중인 part 1이 캡처한 54개 외 **8개가 후속 3D 처리 대상**이다.
- C1 몸통 지표 추천 보류(`c4b8763`)에 구현상 빈틈이 있었다. 새 threshold를 생략해도 프리셋이 `app_default`와 합쳐져 기존 몸통 경고가 살아났다. 보류 키를 `off`에도 넣어 프리셋과 praise 계산에서 모두 제외했다.
- 합성 회귀검증에서 C1 학습 피험자의 Fit3D 값은 도출에 쓰이지 않고, Exercise3D 조정 값만 쓰이며, held-out 값은 threshold를 바꾸지 않는 것을 확인했다. 몸통 보류 키가 기존 기본값으로 다시 발화하지 않는 것도 확인했다. 관련 pytest 5개 통과(`bpt-eval`).

### B. 가설과 남은 불확실성
- 최종 Halpe26 임계값·오경보·검출 판정은 아직 없다. 오래된 COCO17 Fit3D 전용 분석 `20261020-analysis-c17-fit3d-v3`는 비교용 부분 결과이며, 전체 Halpe26 결과나 제품 권고로 쓰지 않는다.
- 기존 CPU 실행은 진행 로그를 자주 쓰지 않는 스냅숏으로 시작되어 남은 시간을 정확히 추정할 수 없다. C2도 아직 학습 중이며 완료 뒤 별도 평가가 필요하다.

### C. 이전 판단 수정
- 아래 "C2 중단"은 과거 상태다. C2는 21:58 재시작되어 정상 학습 중이다. C2 threshold가 없는 이유는 아직 그 모델의 독립 조정·평가 결과가 없기 때문이다.
- C1의 몸통 오차 보류는 문구와 override 생략만으로 충분하지 않았다. 실제 비활성 목록과 praise 분석까지 일치하도록 수정했다.
- Fit3D 지표 오차 표는 실제 중력으로 계산했는데 제목에 "카메라-위"라고 잘못 적혀 있었다. 표 제목을 계산 정의에 맞게 고쳤다. 수치 계산은 바꾸지 않았다.

### D. 데이터 신뢰도
- C1은 Fit3D s03–s05를 threshold 도출에 쓰지 않는다. C2는 Fit3D s03–s05와 Exercise3D P1을 도출에 쓰지 않는다. 공개 사람 분할과 정상 판정 조건은 사전 등록 그대로다.
- Fit3D Halpe26 입력은 실험 A이며 앱 crop 추적 경로가 아니다. Fit3D·Exercise3D 정상 렙은 정상 시범이라는 전제이며, 공개 키별 틀린 자세 라벨은 사람이 검수하지 않은 AI 2패스 합의다.
- C1 몸통 오차 원인은 미확인이다. 관련 키를 추천하지 않는다. 앱 시점 게이트 때문에 측면 지표를 잴 수 없는 표본은 정답 근거로 확대 해석하지 않는다.
- 새 실행 manifest에는 2D CSV·가중치 외에 **렙 구간 JSON, 사람 분할·AI 라벨 CSV, Exercise3D 시점 metadata**의 hash도 기록한다. 이미 실행 중인 이전 manifest는 보존한다.

### E. 재현·재개
- `scripts/rules_calib_resume_home.sh`는 기존 4개 평가의 완료 파일과 manifest hash를 기다린 뒤, 남은 8개 조정 클립만 처리한다. 그 다음 원래 XS/C1 분석 → C2 학습 완료 manifest 확인 → C2 공개·Exercise3D 및 Fit3D s07–s11 평가 → 전체 분석 순서다. CPU 4스레드를 쓰며 GPU 사슬에 새 작업을 넣지 않는다.
- Home의 immutable `_code/<SHA>/`에서 `SHA=<SHA> setsid nohup bash _code/<SHA>/scripts/rules_calib_resume_home.sh > resume-20261020.log 2>&1 < /dev/null &`로 실행한다. 중복 실행은 `.resume-20261020.lock`으로 거부한다. 생산 프로세스가 사라졌는데 완료 파일이 없으면 실패로 기록한다.
- 후속 출력: `20261020-pubpy-h26-tune2d-part2/`, `20261020-analysis-h26-orig-c1-resumed/`, `20261020-pubpy-h26-c2/`, `20261020-fit3d-h26A-c2/`, `20261020-analysis-h26-all-resumed/`.
- 분석의 `presets/`는 Home의 실험 산출물이다. 저장소/Swift 기본값에 자동 적용하지 않는다. 최종 보고에는 `tables.md`, `analysis.json`, `manifest.json`을 대조한 집계만 옮긴다.

### F. 권고
- 완성되지 않은 부분 분석에서 기준값을 채택하지 않는다. 전체 정상·틀린 자세 분포와 게이트별 표본 수를 함께 보고 판단한다.
- C1 몸통 계열 규칙은 오차 원인이 해결될 때까지 보류한다.

### G. 사용자 승인이 필요한 결정
- 모델별 threshold 채택, 새 규칙 활성화, 기존 키 비활성화, 중력 사용, 앱 기본값·번들 변경, integration 병합은 별도 제품 결정이다. 이번 복구는 승인된 실험과 분석의 연속 실행만 준비한다.

## 입력 2D 변경 — 사용자 제품 결정 (2026-10-20 20:50, 결과 보기 전)

사용자는 "할페만 남기자"고 결정했다. 앱 기본 2D가 RTMPose-m Halpe26이 되고 COCO17은 빠진다(전환 작업은 ai/halpe-default-m2b98256). 그래서 이 문서의 **주 결과는 m Halpe26 입력의 정상 렙 분포로 도출한 기준값**이다.

사전 등록 문서(8eb5841)는 고치지 않는다. 바뀐 것은 입력 출처뿐이고, 임계값 규칙·평가 규칙·판정 기준·도출 출처의 역할은 그대로다. 결정 시점에 held-out 결과는 하나도 보지 않았다.
- 공개·Exercise3D: eval-reliability가 만든 앱 경로 Halpe26 2D CSV를 쓴다. held-out 2D와 같은 2ef3ced pose-replay에서 나왔다. 빠진 공개 조정 정상 클립(스쿼트·푸시업 62개)은 같은 코드의 Halpe26으로 채운다.
- Fit3D: Halpe26 앱 경로 2D가 없다. Fit3D 영상은 Home 밖으로 못 나가고, Mac pose-replay도 쓸 수 없다. 그래서 lift-compare의 **실험 A 2D**(RTMDet 상자 + mmpose RTMPose-m Halpe26, 앞 17점)를 쓴다. 앱의 crop 추적·Core ML 경로가 아니라는 점을 결과마다 적는다.
- COCO17로 이미 돌린 것은 비교 행으로 남긴다. Fit3D 전체(모캡·원래·C1, 앱 경로 COCO17 CSV)와 공개 held-out 일부(원래 XS 36클립 Swift)다. 남은 COCO17 전용 재생은 시간이 들어 뺐다.
- 3D 재생 방법도 바꿨다. 공개·Exercise3D의 모델별 3D는 Mac pose-replay 대신 Home의 Python 앱 경로로 돌린다. Python 앱 경로는 LiveMotionAGFormer·Pose3DConstraints를 Swift와 패리티 테스트로 고정한 미러다. 바꾼 이유는 Mac이 다른 작업으로 붐벼 클립당 45초 이상 걸렸기 때문이다(앞서 8초).
  - Swift와 같은지 확인한 범위(COCO17, 원래 XS, 공개 held-out 12클립 40렙): 판정 여부 40/40, 지표 키 40/40이 같다.
  - 각도 차이 중앙값은 0.02–0.15°(p90 < 0.8°), 선 편차 차이 중앙값은 ≤ 0.001이다.
  - 가장 큰 차이는 아래팔 기울기 5.3°와 torso_min 3.2°이고, 각각 렙 1개다. 정점 프레임이 바뀐 것으로 보인다(가설).
  - 렙 구간과 로우 측면 게이트는 이 브랜치 pose-replay를 Halpe26 CSV에 2D 모드로 돌린 결과를 쓴다(2D 상태기계는 3D 모델과 무관).
- C2 학습은 fine-tune 에이전트가 C1 평가를 위해 멈췄다(`xs-C2-STOPPED-for-C1-eval`). 그래서 C2의 기준값은 아직 없다.

## 분석 정의 보충 (2026-10-20 21:35, held-out 결과를 계산하기 전)
- **Fit3D의 "위" 방향.** 앱 정의는 카메라 −y이고 폰을 세워 둔다는 전제가 붙는다. Fit3D 카메라는 약 11° 아래로 기울어 있다(카메라마다 외부 파라미터로 측정, 예: 50591643 11.4°). 그래서 Fit3D의 카메라 −y는 앱 조건이 아니다. 폰을 세운 앱의 카메라 −y는 실제 중력과 거의 같으므로, Fit3D의 주 분석(도출·오경보)에는 **실제 중력**을 쓴다.
  - Fit3D 카메라-위 값은 "카메라가 11° 기울면 지표가 얼마나 틀리나" 표(R1, `BPT_3D_GRAVITY` 판단)에만 쓴다.
  - 근거: 조정 피험자 s03–s05 모캡 로우의 렙 평균 몸통각이 카메라-위로는 7–74°(p1–p99), 중력으로는 S7과 같은 40–63°대였다. 카메라마다 ±8–11°씩 엇갈렸다.
- **모캡 행은 앱 모델이 아니다.** 판정(근거 있음/약함/끄기)은 원래 XS·C1·C2에만 붙인다.
- **squat_heel_rise(Halpe26 발, 2D)를 평가에 더했다.** 사전 등록 밖이고, 사용자 Halpe26 결정 뒤에 추가했다. 기존 규칙 그대로 모든 시점에서 판정한다.
  - 3D 판정 경로에서 이 규칙을 쓰려면 2D heelToe를 3D 표본에 넘겨야 한다. 높이와 같은 "2D 보조 신호" 방식으로 Swift와 Python을 둘 다 고쳤다. 기본값은 여전히 꺼짐이다.

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
