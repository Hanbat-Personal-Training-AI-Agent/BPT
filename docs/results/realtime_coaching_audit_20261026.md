# 실시간 코칭 감사 및 기본 OFF 관측 실험 — 2026-10-26

## A. 범위와 분리

검토 브랜치 `ai/realtime-coaching-audit-20261026`은 XS·캘리브레이션·개인화와 심층분석을 보존한 `a05848a`에서 분기했다. 기기 인계 브랜치, main/integration, 모델, 기본 음성 필터는 변경하지 않았다. 이 결과는 54개 오류의 정교한 코칭 완료 또는 실제 운동 정확도 검증이 아니다.

별도 안전 수정 `0dbe442`: 이전 경고가 사라졌다는 이유만으로 `praise_fixed`를 발화하던 경로를 `judged && fired.isEmpty`로 제한했다. 관측 실패나 다른 오류 잔존은 교정 완료가 아니다. 선행 `69a2bca`는 trial의 DemoConfig를 Foundation 파일로 옮겨 Swift 패키지에서도 같은 환경 읽기 코드를 사용하도록 한 빌드 구성 수정이다.

## B. 54개 항목 대조

`realtime_coaching_coverage_20261026.csv`는 과거 `ai/coaching-team-mf953336:docs/coaching/fault_catalog.csv`의 54행을 현재 trial 구현과 대조했다. 과거 measurable 열(yes 15 / partial 22 / no 17)은 보존하되 현재 구현의 정확성 판정으로 사용하지 않는다.

- 운동별: 로우 12 / 스쿼트 9 / 푸시업 10 / 데드리프트 7 / 벤치프레스 8 / 랫풀다운 8.
- 기존 FormWarningTracker의 동일 ID 26개, ID 없음 28개. ID가 있다고 카탈로그 조건·정확도·전달이 완성된 것은 아니다.
- 26개 전달 상태: 기본 전달 후보 12, 기본 조용히 보류 6, Dart 문구 부재로 차단 6, 규칙 자체 비활성·3D 지표 부재 2.
- 측정 분류: 3D proxy 18, head-centre 대용 3, 3D 각도+2D 높이 혼합 3, 비활성 2D 전용 2, 기하 가능하지만 계약 누락 5, 추가 관측 필요 15, 미지원 운동 8.
- 3개의 새 실험 후보는 별도 모듈에만 추가했다. 기존 26개 규칙이나 기본 발화 개수를 늘리지 않았다. CSV의 after 열은 실험과 기존 구현을 구분한다.

`row_head_up` 등은 귀/경추 분절이 아닌 H36M head centre다. `squat_hips_first`, `deadlift_hips_first`, `bench_hips_up`의 높이·속도는 골반 상대 3D만으로 얻지 못해 2D 높이를 혼합한다. 기존 처음 3회 자동 기준과 후보 임계가 카탈로그의 승인 ROM/변형별 기준과 같다고 볼 수 없다. 로우 몸통 반동의 현재 max−min 39.9°도 카탈로그 P95−P05 기준과 동일하지 않다.

## C. 관측 실험 구현

`ExperimentalCoaching.swift`는 포즈를 수정하거나 기존 음성을 발생시키지 않는 독립 모듈이다. `BPT_EXPERIMENTAL_COACHING=1`일 때만 현재 네이티브 XS 프레임을 읽고, 이미 활성화된 DemoPoseLog/VideoRunLog에 `experimental_coaching`을 기록한다. 로그가 꺼져 있으면 별도 화면이나 새 파일은 생성하지 않는다. 기본값 OFF.

입력은 같은 프레임의 raw/최종 masked 3D, H36M 관절 confidence, 실제 invalid mask, 평가기의 실제 phase, 도착 시각, 사용 가능한 중력이다. 카메라 UI 문구에서 phase를 추측하지 않는다. `barbellRow` 같은 UI 운동명은 FormExercise의 정규화된 ID로 전달한다.

측정: 좌우 무릎·팔꿈치·고관절각, 전체 몸통과 중력 사이 각도, 몸통 정면 평면에 투영한 상완 각도. 상완각은 몸통의 아래 방향에 대한 **부호 없는 각도**이며 앞뒤 어깨 굽힘을 제거한다. 요추 곡률·척추 분절·관절 부하·통증을 측정하지 않는다.

관절별 confidence 0.5 미만, invalid 관절, raw 부재, 관측 불량, raw/보정 각 차이 10° 초과, 퇴화 기하를 개별 보류한다. 중력이 없으면 몸통 기울기를 보류한다. 0.25초 넘는 관측 간격/시간 역행/위상 변경은 지속 상태를 초기화한다. 이 수치들은 실험용 품질 가드이며 임상·카탈로그 검증 임계가 아니다.

후보 3개:

| 후보 | 필요한 계약 | 실제 의미와 한계 |
|---|---|---|
| row_leg_drive | 승인 strict_row 변형, pulling, 양측 무릎·팔꿈치, 승인 변화 임계/지속시간 | 같은 pulling 구간 시작 대비 양측 무릎 폄과 팔꿈치 굽힘이 함께 지속됨. 힘·반동 원인·바 경로를 입증하지 않음 |
| pushup_elbow_flare | 승인 pushup 변형 및 상완 범위, 활성 phase, 양측 어깨/상완·몸통 | 투영 상완각이 승인 범위를 벗어난 상태의 지속. 보편적 이상 각도를 임의 설정하지 않음 |
| deadlift_arm_pull | 승인 double-overhand 변형, rising, 팔꿈치, 승인 변화 임계/지속시간 | 같은 상승 구간 시작 대비 팔꿈치 굽힘 증가. 바/그립/힘을 직접 보지 못하므로 승인 변형 필수 |

구간 시작 값은 움직임 차분을 위한 좌표일 뿐 정상 자세 기준이 아니다. 초기 반복을 정상으로 자동 승인하지 않는다. 현재 앱에는 승인 변형·ROM 프로필 입력 UI가 없으므로 호출부가 profile을 전달하지 않는다. 따라서 앱 실험에서 후보는 명시적으로 보류되고 수치 관측만 남는다. 후보 발화/사용자 코칭 완료로 표시하지 않는다.

## D. 허리 굽힘과 문구

어깨–골반 기울기와 pelvis0–spine7–thorax8 proxy는 요추 곡률이 아니다. 팀의 별도 수치 감사에서도 XS proxy와 GT의 MAE 및 상관이 요추 경고 활성화를 지지하지 않았다. 이 모듈에는 척추 굽힘 진단을 추가하지 않았다. 랫풀다운 미지원, 장비 고정점·손 회전·벤치 접촉·통증 등 추가 관측 필요 항목도 구현 완료로 바꾸지 않았다.

벤치/데드 6개 한국어·영어 문구와 보고서 라벨/운동 ID를 준비했다. 과거 초안의 “벤치에서 확실히 떨어짐”, “바를 가슴까지 내려야 함” 같은 현재 입력으로 확정할 수 없는 표현은 측정 변화 확인 문구로 줄였다. 역사적 이름 `keysWithoutFlutterLines`의 집합 6개를 그대로 유지하므로 **문구 추가만으로 기본 발화가 켜지지 않는다**. 별도 정확도 검증/활성화 판단이 필요하다.

## E. 실행 증거와 실패

- 거짓 칭찬 회귀: FormWarningsTests **27/27 통과**, 18:09:32. 경고 후 bad/partial/warming/tracking_lost 3D → 칭찬 없음, 유효 clean → praise_fixed, 다른 pike 잔존 → 칭찬 없음. `/tmp/bpt-coaching-praise-test-20261026.log`.
- 새 모듈 회귀: **5/5 통과**, 18:13:40. 정면 평면/강체 회전, 승인 프로필·시간 지속/간격/역행, 국소 invalid·보정 차이, 누락 raw 보류, 로우 양측 동시변화/다른 위상/팔만 움직임. `/tmp/bpt-coaching-experimental-minimal-20261026.log`.
- 처음 전체 패키지는 기존 DemoConfig 미포함으로 실패 → 공용 파일 추출 후 27개 통과. 이후 새 모듈·Bridge까지 포함한 패키지는 링크 중 ENOSPC로 실패했다. 이 실행을 통과로 세지 않는다. `/tmp/bpt-coaching-experimental-test-20261026.log`.
- 디스크를 줄여 production 모듈과 같은 XCTest 파일을 symlink한 `/tmp/bpt-coaching-minimal-20261026`의 최소 SwiftPM 패키지로 새 5개만 실행했다. 직접 swiftc+XCTest 시도는 SDK overlay 구성으로 실패했고, 이를 대신한 최소 SwiftPM 결과만 유효하다.
- 원본 device cache는 건드리지 않았다. 소유 realtime `.build` 364MiB(APFS 공유 제외 약185MiB 회수), 최소 패키지 `.build` 120MiB를 정리했다. 소스/테스트/로그/결과는 보존했다. root의 새 실행 중단 요청 이후 빌드/테스트는 중단했다.
- **새 Camera 연결부 iOS 앱 빌드·실기기·기본 필터 Bridge 통합 테스트는 미완료**다. 기존 deep 앱의 a05848a 인계를 대신하지 않는다. 최소 모듈 테스트로 이를 통과했다고 주장하지 않는다.

재현(공간·슬롯 확보 후):

```sh
swift test --package-path ios/CalibrationEngineKit --jobs 2 --filter 'ExperimentalCoachingTests|FormWarningsTests|WorkoutSessionBridgeTests'
swiftc ios/Runner/NativePose/Evaluators/ExperimentalCoaching.swift scripts/replay_experimental_coaching.swift -o /tmp/bpt-coaching-replay
/tmp/bpt-coaching-replay /Users/6_month/bpt-data/demo/final_1602/pose_20261023_160217.jsonl /Users/6_month/bpt-data/demo/final_1446/pose_20261023_144640.jsonl
```

## F. 기존 숫자 로그 정량 replay

`realtime_coaching_replay_20261026.json`은 위 Swift production 모듈로 기존 JSONL 숫자만 읽은 결과다. 영상·이미지 열기, 모델 재추론, 네트워크·업로드는 없다.

| 로그 | 입력 프레임 | 각도 산출 프레임 | 완전 지원 프레임 | 후보 보류 |
|---|---:|---:|---:|---:|
| 160217 | 2432 | 2305 | 0 | 2432 |
| 144640 | 2440 | 2314 | 0 | 2440 |

160217의 왼무릎 중앙값 121.41°(P05 92.11/P95 171.94), 오른무릎 134.02°(86.20/164.86), 왼팔꿈치 139.02°(88.52/163.32), 오른팔꿈치 101.59°(74.39/147.68). 이는 **보정 후 추정 좌표의 분포**다. 좌우 비대칭의 정답이나 사용자 운동 오류를 증명하지 않는다.

두 로그는 raw 3D, H36M confidence, invalid mask, 실제 phase, 중력, 승인 profile을 기록하지 않았다. 따라서 모든 후보와 지원 상태는 보류가 맞다. 관측 부족을 정상으로 치환하거나 유효한 오류 탐지율로 보고하지 않았다. 운동 GT/승인 프로필을 가진 실제 positive/negative 검증은 남아 있다.

## G. 남은 범위

안전 버그는 독립 선택 이식할 수 있다. 새 실험은 검토용 브랜치에서 OFF 상태로 동결한다. 다음 독립 검토는 Camera 연결부 빌드, 프로필 계약/상완각 의미, deadlift 추가 회귀, 미관측 구간·프로필 교체 시 지속 상태, Dart 문구/기본 필터 통합 검증을 확인해야 한다. 54개 전체 완성, 요추 진단, 실시간 오류 정확도, 실기기 동작 완료는 이 문서의 결론이 아니다.
