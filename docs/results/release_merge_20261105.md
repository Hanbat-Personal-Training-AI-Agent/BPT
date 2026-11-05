# 릴리스 병합 — release/bpt-final-20261105 (2026-11-05)

`integration/ai`(9f3e30c, origin/main 0eef70f 포함)에서 브랜치 `release/bpt-final-20261105`를 만들고 아래 순서로 `--no-ff` 병합했다. push·main/integration ref 변경·rebase·force는 하지 않았다. 작업 트리: `.claude/worktrees/release-20261105`.

## 병합한 것

| # | 브랜치 | 병합 커밋 | 결과 |
| --- | --- | --- | --- |
| 1 | `review/bpt-completion-20261104` (1f61cae) | eca1f7e | 충돌 6개, 결정 문서대로 해결 |
| 2 | `test/phone-reentry-record-20261105` (09f6e4e) | bfadb7a | 충돌 없음 |
| 3 | `ai/deep-analysis-mf953336` (7a0ebbb) | 8549159 | 충돌 15개 모두 review 쪽 |
| 4 | `ai/mesh-reveal-mf953336` (01803d6) | 5d9a30c | 충돌 8개 모두 review 쪽 |
| 5 | `ai/rules-fix-mf953336` (f76b518) | 631488f | FormStrictness만 review 코드 위에 다시 넣음 |
| 6 | `ai/real-feedback-m0eef70f` (da797c8) | d42f812 | 코드 변화 없음(review 쪽 유지) |
| 7 | `ai/coaching-team-mf953336` (20d897c) | c22b785 | 문서만, 충돌 없음 |

병합하지 않은 것: `ai/finetune3-*`(C3 모델 채택 미승인). 모델 기본값은 바꾸지 않았다.

병합 뒤 커밋:
- a2f4d15 `feat(workout)`: 세트 녹화·심층분석 업로드 기본 켬(사용자 결정 2026-11-05). `BPT_SET_RECORDING=0`(실행 환경 또는 `bpt_demo.json`), UserDefaults `BPTSetRecording NO`로 끔.
- 3934e66 `fix(server)`: 팀 결함 카탈로그가 있다는 것만으로 심층분석 규칙이 바뀌지 않게 함(`BPT_DEEP_TEAM_CATALOG=1`일 때만 읽음).
- 4ffc6c2 `fix(camera)`: rules-fix 충돌 해결에서 빠진 `CameraPoseViewModel.init`의 닫는 괄호를 복구했다. 첫 Release 빌드가 이 때문에 실패했다. 이 파일은 swift test 패키지에 없어 시험으로는 잡히지 않았다.

## 충돌 해결

### 1. review/bpt-completion-20261104
`docs/evaluation/integration_preview_refresh_20261104.md`의 결정대로 처리했다.
- `PoseReplay/main.swift`, `project.pbxproj`, `CameraPosePreview.swift`, `SimCCDecoder.swift`, mCOCO `rtmpose_m_forward.mlpackage` 3파일(되살림), 벤치 스크립트 4개 기본값: review 쪽.
- `docs/decisions.md`: 충돌 표지만 지웠다. 양쪽 항목을 모두 남겼고, 결과는 review 파일과 같다(review에 D-M 항목이 이미 있음).
- `README.md`: 결정 문서에 없던 충돌이다(integration의 main 병합에서 생김). 지시("main 병합의 README는 남긴다")대로 integration 쪽 README 전체를 썼다.
- 확인: `git diff review/bpt-completion-20261104 eca1f7e`는 README와 `backend/` 14파일(main #69 집계 일관성)뿐이다. `lib/`·`ios/` 차이 없음.

### 3. ai/deep-analysis-mf953336
review가 이미 같은 기능의 더 새 검증판을 담고 있다(`server/calibration_modal`은 ai/final-validation-20261026에서 가져옴, `BPT_SET_RECORDING` 녹화 훅, 업로드·리포트 화면). add/add 10개와 content 5개(`WorkoutSessionBridge`, `CameraPosePreview`, `native_pose_workout_screen`, `workout_result_screen`, `main.dart`) 모두 review 쪽을 썼다. 브랜치에서 실제로 새로 들어온 것은 `docs/results/deep_analysis_app.md`뿐이다. 브랜치의 `libtk8.6` 수정 등은 review `modal_app.py`에 이미 있다.

### 4. ai/mesh-reveal-mf953336
브랜치 쪽 파일은 review와 비교해 지운 줄만 있다. review에는 '신체분석 완료!' 카드, 넘어가기, 똑바로 세우기, 더블탭 원위치와 그 뒤 보완이 이미 있다. 충돌 8개 모두 review 쪽을 썼다. 화면은 계속 `--dart-define=BPT_MESH_REVEAL=true`일 때만 나온다.

### 5. ai/rules-fix-mf953336
review의 `FormWarnings.swift`(2D/3D 이중 판정, fault evidence, 오버레이)를 기준으로 두고, 브랜치 기능만 다시 넣었다.
- `FormStrictness`(strict/standard/relaxed): 기준값 덮어쓰기와 relaxed 보류 키. **standard = 기존 값 그대로(기본)**.
- 연결 경로: Flutter `NativePoseWorkoutScreen.formStrictness`(기본 `'standard'`) → `creationParams['formStrictness']` → `NativePoseCameraPlatformViewFactory` → `NativePoseCameraPlatformView` → `CameraPosePreview`/`CameraPoseViewModel` → `strictness.apply(to: tracker)`. review의 `setupOptions`와 `wristAnchor`는 그대로 두고 그 옆에 넣었다.
- `pose-replay --strictness`. review에 이미 `--image-size`가 있어 브랜치가 더한 같은 옵션은 뺐다.
- `testStrictnessModes`를 남은 기능에 맞게 고쳤다.
- review의 디버그 자막 가드(`BPT_DEBUG_CAPTION`)는 그대로다.

**옮기지 않은 것**(review의 감사 시험과 충돌):
- 5635890: `no_lockout`을 락아웃 구간 절대 기준으로 다시 정의한 것과 무릎 모임의 서 있는 자세 게이트. review의 fault evidence, 오버레이(`noLockoutBelowSetMaxDegrees`)와 시험 수십 개가 기존 정의(세트 최대 대비)를 쓴다.
- 엄격 모드에만 있는 새 지표 3개(`pushup_elbow_flare`, `pushup_head_hang`, `squat_torso_lean`). 넣어 보니 `testAllTwentyRulesHave…Witnesses`(양성·음성), `testExactlyTwentyLegacyRules…`, `FormMetrics3DParityTests`(Python 지표 일치) 7개가 실패했다.
- 그래서 strict도 `no_lockout`을 전달하지 않는다(`extraDeliveredKeys` 비움). 브랜치는 락아웃 수정을 전제로 이 키를 켰는데, 기존 정의로는 정상 렙의 23–52 %에서 잘못 울린다.

### 6. ai/real-feedback-m0eef70f
브랜치의 고유 코드인 6a78a29("자세 확인 중 · n/목표회")는 이미 review 역사에 있다. 그 뒤 d6dd1e9와 e71589d(2026-10-20)에서 "원래 대기 문구 — 사용자 사양"으로 되돌렸고, review의 `test/native_pose_workout_screen_test.dart`가 대기 문구가 유지되는지 시험한다. da797c8 병합은 호출 쪽에 `repsDone`/`repsTarget` 인자만 넣는다. 이 인자를 받을 필드가 없어 컴파일되지 않으므로 review 쪽을 유지했다. 결과적으로 코드 변화는 없다.

### 7. ai/coaching-team-mf953336 → 3934e66
문서만 병합했지만 `docs/coaching/fault_catalog.csv`가 생기면서 `deep_metrics.load_rule_catalog()`가 그 파일을 자동으로 읽었다. 그러면 `deep_rules.csv` 규칙이 모두 꺼지고(측정 계약 미구현) pytest 6개가 실패했다. 카탈로그 작성자도 "배포 설정이 아니다"(`gap_analysis.md`)라고 적었다. 그래서 `BPT_DEEP_TEAM_CATALOG=1`일 때만 읽도록 했다(Modal 이미지 포함 조건도 같다). 켜도 컨테이너 안에 같은 환경변수가 있어야 실제로 읽는다. 배포할 때 켜려면 함수 env에 넣어야 한다.

## 검증 (HEAD 기준, 이 Mac)

| 검사 | 결과 |
| --- | --- |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub` | 279 통과, 10 건너뜀, 1 실패 |
| `swift test --package-path ios/CalibrationEngineKit --jobs 2` | 366개 실행, 4 건너뜀, 0 실패 |
| `pytest server/calibration_modal/tests` (conda `bpt-eval`) | 216 통과, 1 건너뜀 |
| `flutter build ios --release --no-codesign` | 성공. `build/ios/iphoneos/Runner.app`(224.8MB, 서명 없음), Xcode 단계 50.9초 |

- flutter 실패 1개(`test/local_deep_http_response_test.dart`)는 비공개 산출물 환경변수(`BPT_LOCAL_API_RESPONSE_FILE` 등)를 요구하고 대체 입력이 없는 시험이다(`local_deep_storage_http_contract_20261102.md`). 이 시험과 `lib`은 review와 같다(`lib` 차이는 `formStrictness` 6줄뿐). 건너뜀 10개도 환경변수·플래그로 막힌 시험이다.
- swift는 review 기준 364개에서 `testStrictnessModes`와 `testSetRecordingDefaultsOn` 2개가 늘었다.
- 첫 빌드에서 `pod install`이 `ios/Podfile.lock`에 `integration_test`를 더해서, 커밋하지 않고 되돌렸다. 직접 만든 DerivedData(`Runner-anmt…`)는 지웠다.
- 기기 서명·설치·실행은 하지 않았다.

## 열린 결정

1. **main 병합**: 사용자 승인 필요(이 브랜치는 push하지 않음).
2. **엄격 모드의 락아웃 재정의와 새 지표 3개**: review의 20개 규칙 감사, Python 일치 시험과 함께 다시 설계할지.
3. **"자세 확인 중 · n/목표회" 말풍선**: 10-20 사용자 사양(대기 문구 유지)과 이번 병합 목록이 서로 다르다. 다시 켤지 확인 필요.
4. **팀 결함 카탈로그를 심층분석 규칙으로 쓸지**(`BPT_DEEP_TEAM_CATALOG`).
5. **메시 공개 화면 기본값**: `BPT_MESH_REVEAL`은 기본 꺼짐 그대로다.
6. **세트 녹화 FPS 측정**(`docs/research/set_recording_perf.md`): 기본 ON은 승인됐지만 측정은 아직 하지 않았다.
7. formStrictness를 고르는 UI는 없다(팀원 몫). 기본값은 standard다.
