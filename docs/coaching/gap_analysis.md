# 현재 앱 규칙과 운동팀 명세의 차이

기준: 2026-10-23, 브랜치 `ai/coaching-team-mf953336`, HEAD `3cef41d`. 앱 코드는 수정하지 않았다. 평가기·타입·공통 판정·Kori 문구를 정적으로 확인했으며, 연결 확인에 필요한 카메라 호출부와 세트 요약 화면도 읽었다. 원본 영상·데이터셋·가중치·실행 결과 파일은 읽지 않았다. 코드 주석의 데이터셋 기반 보정 설명은 독립적으로 검증한 결과가 아니다.

## 우선순위

P0=잘못된 안전 확신·과제 혼동 방지, P1=실제 코칭 범위와 정확도 확장, P2=피드백 품질·유지관리 개선. 아래 조치는 모두 **후속 구현 제안**이다. 이번 [CSV](fault_catalog.csv)는 배포 설정이 아니다.

| 우선순위 | 현재 근거·차이 | 사용자 영향 | 권장 조치·완료 확인 | 원칙의 외부 근거 |
| --- | --- | --- | --- | --- |
| P0 | [C1] `deliver`는 이전 발화 키가 이번 `fired`에서 사라지면 `praise_fixed`. 결측·게이트 배제와 실제 개선을 구분하지 않음. [C9]는 `fixCount==0`이면 “다 완벽해” 선택 | 못 본 자세·꺼진 규칙도 개선/완벽으로 들릴 수 있음 | `unknown`과 관측 정상 분리. 유효 관측·개선 지속·상위 문제 없음 확인 후 구체적 칭찬. 결측·비활성 상황에서 완벽 칭찬이 나오지 않는지 확인 | [G], [F] |
| P0 | [C2]·[C1]의 로우는 단일 `barbellRow`이고 장비·변형·그립 입력이 없음 | 랜드마인 방향 오류는 누락하고 정상 Yates/T-bar에 부적절한 큐를 적용할 수 있음 | 일반/Pendlay/Yates/랜드마인 프로필과 장비 셋업 먼저 추가. 고정점 미관측이면 방향 판정 보류. 45° T-bar를 일반 로우 절대각으로 경고하지 않는지 확인 | [R], [Y] |
| P0 | [C8]은 평가기에 `rawCoco17`을 전달하며 3D 인수를 넘기지 않음. [C1] `judge`는 2D 전용; 3D는 기록용 | 목표의 “3D 자세 판정”을 현재 기능으로 오해할 수 있음 | 리포트에 실제 판정 차원·관측 가능 범위 표시. 3D 도입 시 좌표계·중력·품질·키포인트 매핑부터 검증 | [G] |
| P0 | [C1]·[C7]에는 바·고정점·손바닥·척추 분절·견갑 관측 없음 | 바 도착점·그립·요추 위험을 신체 대리량만으로 단정할 위험 | `needs`에 따라 보류. 객체·손 감지 또는 사람 확인 후에만 관련 규칙 허용. 관절각으로 관절 힘·부상 확률을 출력하지 않는지 확인 | [R], [B], [L] |
| P1 | [C1] 벤치·데드리프트 각 3키는 판정/로그와 발화가 분리되고, Dart 문구 없음으로 발화 제외 | 반복은 세어도 해당 교정 안내가 없음 | 문구·라벨·운동 ID 연결과 결함별 검증을 함께 완료한 뒤 활성화 | [B], [D] |
| P1 | [C1] `FormExercise`·규칙 목록과 Evaluators에 랫풀다운 없음 | 여섯 운동 중 하나의 실시간 코칭 공백 | 단계 머신→프로필→검증된 신체 신호→바·그립 확인 순서로 추가 | [LP] |
| P1 | [C1] 기준은 첫 3반복; 깊이·로우 자세는 상대 변화 중심 | 처음부터 같은 오류가 반복되면 기준으로 흡수 | 승인한 목표 ROM/변형 셋업과 개인 변화 기준을 함께 사용. 초기 3회가 얕거나 세운 자세여도 비교 대상이 정상으로 확정되지 않는지 확인 | [R], [F] |
| P1 | [C1] 임시값 하나씩만 존재, PT 엄격/표준/여유 없음 | 세 모드의 코칭 기대를 구현하지 못함 | 카탈로그 후보값을 검증하고 모드별 노출 정책 분리. 안전주의 기준은 공통 유지 | [F], [A] |
| P1 | [C1] 신체점 confidence 0.30, max/min 집계, 고정 프레임 창. 반복 전체의 최소 유효 관측 비율은 별도 확인하지 않음 | 한두 이상점·FPS 변화·가림이 경고를 바꿀 수 있음 | confidence를 정답 확률로 해석하지 말고 관측률·연속성·시간 기반 창과 이상점 완화 검증 | [G] |
| P1 | [C1] 푸시업 카운팅 게이트는 rolling shoulder ratio 1.0, `judge`는 로우 외에는 rep별 front fraction 기준 사용 | 반복 집계와 자세 판정의 시점 허용 범위가 다를 수 있음 | 공통 관측 가능성 계약을 정하고 카운팅/자세의 차이를 명시. 비측면 반복 수를 자세 합격으로 쓰지 않음 | [G], [P] |
| P2 | [C1] 한 반복 한 키·3반복 쿨다운은 있으나 초 단위 쿨다운 없음. 참고 키는 세트 종료 때 여러 이벤트 가능. [C9] 경고 음성은 기존 음성을 중단 가능 | 빠른 반복·세트 요약에서 말이 몰릴 수 있음 | 시간+반복 쿨다운, 안전 큐 우선, 효율 큐 전환점 전달, 세트 요약 1과제 선택 검증 | [F] |
| P2 | [C6] 측정한 지표보다 더 구체적이거나 강한 큐가 있음 | 실제 결함과 다른 수정 유도 | 아래 문구 표 기준으로 변형별 큐·관찰 범위를 일치시킴 | [R], [B], [P] |
| P2 | [C1] 보고서는 지표·warnings·spoken을 기록하지만 근거 URL·변형·모드·규칙 버전·보류 사유 계약이 없음 | 서버 재분석과 실시간 결론의 추적이 어려움 | [team.md](team.md)의 공통 이벤트·GVHMR 보고 형식 연결. 불일치 이유와 다음 세트 한 과제를 보존 | [G], [F] |

## 운동별 현재 구현

아래는 **현재 코드값**이다. 새 카탈로그의 `P:` 제안값과 같다고 가정하지 않는다. 모든 현재 임계값은 [C1] 자체에서도 임시값으로 명시한다.

| 운동 | 현재 동작·값 | 남는 공백 | 코드 |
| --- | --- | --- | --- |
| 로우 | `row_torso_swing`: max−min >39.9°; `row_standing_up`: 첫 3회 대비 직립 >10°; `row_short_pull`: 팔꿈치 뒤 이동 감소 >0.10 L; `row_head_up`: 시작 대비 >0.15 L | 장비 방향·그립·절대 셋업·무릎 반동·바닥 재설정 없음. `row_shrug` 판정 비활성 | [C1] 125–149, 929–948; [C2] |
| 스쿼트 | 힙 선행: 하단 이후 8프레임, 몸통 전경 >8°와 골반 속도 우세. 깊이: 첫 3회 대비 무릎 최소각 +15°. 외반: 정면 하단~상승의 무릎/발목 간격비 <1.0 | 발끝·스탠스 보정 부족. 외반은 기본 발화 제외. 뒤꿈치 지표는 있으나 판정 꺼짐. 고정 절대 전경·무릎 발끝 초과 규칙은 없음 | [C1] 101–121, 909–928; [C3] |
| 푸시업 | 처짐 >0.140, 들림 >0.08, 깊이 +15°, 상단 세트 최고 대비 −10°, 고개 떨굼 변화 >0.376, 고개 듦 >0.15, 손 전후 위치 ±0.35 팔 길이 | 손 너비·손 회전·상완 벌림 없음. 기본 발화 제외 키 다수. 가슴 접촉을 직접 측정하지 않음 | [C1] 72–98, 891–908; [C4] |
| 벤치프레스 | 골반 들림 >0.10 L, 깊이 +15°, 상단 세트 최고 대비 −10°. 카운팅 후 15프레임 락아웃 기록 창 | 세 키 모두 사용자 전달 제외. 바운스·그립·손목·바 경로·견갑·실제 벤치 접촉 없음 | [C1] 150–161, 949–956; [C5] |
| 데드리프트 | 힙 선행: 10프레임, 몸통 전경 >8°와 골반 속도 우세. 상단 세트 최고 대비 −10°. 뒤 기울임 >15° | 세 키 모두 사용자 전달 제외. 바 경로 대신 손목/팔꿈치 높이 proxy가 반복 보조 신호. `selected3D`는 유효성 표시가 있어도 측정 본체는 2D | [C1] 163–173, 957–969; [C10] 349 이후 |
| 랫풀다운 | 평가기·형식·규칙·Dart 키 없음 | 셋업부터 단계·신호·피드백 연결까지 신규 작업 필요 | [C1] `FormExercise`, [C6] |

각도에 기반한 상태 전이 문턱은 기술 합격선이 아니다. 예를 들어 벤치의 top 145°/bottom 110°와 적응형 범위, 스쿼트의 반복 인정 각도는 카운팅 장치다. 스쿼트·푸시업에는 높이 기반 보조 카운터도 있어 이 각도 하나만으로 모든 반복을 인정하는 구조도 아니다. [C3], [C4], [C5]

## 활성화 상태와 전달 경로

| 구분 | 키·조건 | 정확한 의미·후속 확인 |
| --- | --- | --- |
| 판정 자체 꺼짐 | `row_shrug`, `squat_heel_rise` | 해당 지표/문구가 있어도 `shrugEnabled=false`, `heelRiseEnabled=false`이므로 경고 판정은 안 함. 검증 후 활성화 검토. [C1] |
| 판정·로그만, 기본 전달 제외 | `squat_no_lockout`, `squat_knee_valgus`, `pushup_no_lockout`, `pushup_hip_pike`, `pushup_shallow`, `pushup_head_up` | `quietByDefault` 6키. 문구가 있다고 사용자에게 들리는 것은 아님. 주석의 오경고 설명은 이번 작업에서 재현하지 않음. [C1] 416 |
| 문구 없음으로 전달 제외 | `bench_hips_up`, `bench_shallow`, `bench_no_lockout`, `deadlift_hips_first`, `deadlift_no_lockout`, `deadlift_lean_back` | `keysWithoutFlutterLines` 6키. 판정 함수를 없앤 것은 아님. [C1] 409, [C6] |
| 개선 등급 전달 조건 | 같은 키가 이전 반복에도 발생, 쿨다운 해제 | 첫 3회 기준이 필요한 개선 규칙은 빠르면 4회째 감지·5회째 발화 가능. [C1] `overBaseline`, `deliver` |
| 참고 등급 | no_lockout·head 계열·추세 등 | 반복 직후 음성이 아니라 `endSet`에서 세트 범위 이벤트. [C1] 597 이후 |
| Dart에만 정의된 촬영 문구 | `setup_phone_upright`, `setup_front_view` | 검토한 평가기의 `allKeys`/emit 경로에는 없음. 전체 앱의 모든 경로에 없다고 단정하지 않음. [C1], [C6] |
| Flutter 세트 요약 | `praise_clean_set`, `set_summary` | [C9]에서 사용됨. 평가기 미발행 키와 앱 전체 미사용 키를 혼동하지 않음 |

`FormGrade.priority/improve/setup/reference`는 **전달 등급**이다. CSV의 안전주의/효율/셋업은 근거와 대응 우선순위이므로 1:1 매핑하지 않는다. 예를 들어 몸통 반동은 현재 priority지만, 변동만으로 부상을 확정할 근거는 없다. [C1], [R], [L]

## Kori 문구와 측정 지표의 불일치

| 현재 문구·키 | 문제 | 제안 큐·정책 | 근거 |
| --- | --- | --- | --- |
| “배꼽까지 당겨!” `row_short_pull` | 검출은 팔꿈치 뒤 이동량이며 배꼽이나 바를 보지 않음. 변형별 도착점도 다름 | “팔꿈치 뒤로 당겨!” 또는 장비 관측 후 선택 경로 큐 | [C1], [C6], [R] |
| “상체 더 숙여!” `row_standing_up` | 처음보다 세워진 변화를 말해야 하는데 절대각 지시로 들림 | “처음 몸통 각도 유지해!” | [C6], [Y] |
| “상체 세워!” `squat_lean_drift` | 로우바·체형에 필요한 전경까지 없앨 수 있음 | “처음 몸통 각도 유지해!” | [C6], [S] |
| “무릎 바깥으로 벌려!” `squat_knee_valgus` | 간격비만으로 판단한 상황에서 발보다 과하게 바깥으로 밀 수 있음 | “무릎을 발끝 방향으로 보내!”; 발 방향 불명 시 보류 | [C1], [C6], [V] |
| “더 앉아!”·“더 깊게 내려가!” | 개인 목표·통증·계획한 부분 반복 맥락이 없음 | “정한 깊이까지 내려가!”; 목표 미확정이면 셋업부터 | [C6], [A] |
| “고개 숙여! 바닥 봐” | 경추 굴곡을 새로 유도할 수 있음 | “목을 몸통과 맞춰!” | [C6], [P] |
| “팔 끝까지 펴!” | 개인 끝점과 과신전 강제를 구분하지 않음 | “팔을 편하게 펴!” | [C6], [P] |
| “잠깐 놓쳤어! 계속해” | 추적 소실 상태에서 운동 지속을 보증하는 인상 | “인식 다시 확인해!”; 세트 중 재촬영 자세 변경은 안전 전환점에 안내 | [C6], [G] |
| “{reps}개 다 완벽해!” | 미관측·꺼진 규칙·쿨다운과 무관한 전면 합격 표현 | 관찰한 한 지표만 칭찬, 보류 영역은 함께 표시 | [C6], [C9], [G] |

Kori의 `koriMistakeLabels`와 `koriMistakeExerciseId`는 푸시업·스쿼트·로우만 다룬다. CSV의 `barbell_row`와 Dart의 `barbell-row`처럼 운동 ID 표기도 다르다. 후속 연결 시 명시적 매핑과 54개 결함의 상태(미구현/측정만/판정/전달)를 관리해야 한다. 형식·버전 계약은 제품 제안이다. [C6], [G]

## 검토 순서와 수용 기준

1. **이번 문서 검토:** 랜드마인 기본 방향, 변형 예외, 14열 CSV, 모든 결함의 출처·측정 한계·모드 조건을 확인한다. [R], [G]
2. **후속 규칙 검증:** 승인된 검증 자료에서 변형·시점·체형별 정상/결함/미관측을 구분해 정밀도·재현율·오경고·보류율을 평가한다. 한 분포의 백분위수를 위험 임계값으로 해석하지 않는다. [G], [B]
3. **후속 전달 검증:** 결측에서 칭찬 금지, 같은 키 쿨다운, 한 큐 선택, 중단 안내 우선, 세트 요약의 관측 범위를 확인한다. 숫자 정책은 사용성 결과로 조정한다. [F], [G]
4. **후속 서버 검증:** GVHMR/실시간 결론의 동일 구간 비교와 불일치 설명을 확인한다. 객체·손 증거가 없는 항목은 3D 리포트에서도 보류한다. [G]

## 코드와 외부 근거

[C1]: ../../ios/Runner/NativePose/Evaluators/FormWarnings.swift
[C2]: ../../ios/Runner/NativePose/Evaluators/BarbellRowEvaluator.swift
[C3]: ../../ios/Runner/NativePose/Evaluators/SquatEvaluator.swift
[C4]: ../../ios/Runner/NativePose/Evaluators/PushUpEvaluator.swift
[C5]: ../../ios/Runner/NativePose/Evaluators/BenchPressEvaluator.swift
[C6]: ../../lib/features/workout/data/kori_feedback_lines.dart
[C7]: ../../ios/Runner/NativePose/PosePipeline/SimCCDecoder.swift
[C8]: ../../ios/Runner/NativePose/Camera/CameraPosePreview.swift
[C9]: ../../lib/features/workout/screens/native_pose_workout_screen.dart
[C10]: ../../ios/Runner/NativePose/Evaluators/DeadliftEvaluator.swift
[G]: https://arxiv.org/abs/2409.06662
[F]: https://pubmed.ncbi.nlm.nih.gov/37410360/
[R]: https://doi.org/10.1519/SSC.0000000000000751
[Y]: https://www.muscleandfitness.com/flexonline/training/row-shadow/
[B]: https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2024.1393235/full
[L]: https://pubmed.ncbi.nlm.nih.gov/31775556/
[D]: https://www.acefitness.org/continuing-education/prosource/september-2015/5579/technique-series-how-to-deadlift/
[LP]: https://www.acefitness.org/resources/everyone/exercise-library/158/seated-lat-pulldown/
[P]: https://www.acefitness.org/resources/everyone/exercise-library/41/push-up/
[S]: https://pubmed.ncbi.nlm.nih.gov/34541522/
[V]: https://pubmed.ncbi.nlm.nih.gov/30026952/
[A]: https://pubmed.ncbi.nlm.nih.gov/41843416/
