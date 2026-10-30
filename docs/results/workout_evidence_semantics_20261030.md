# 완료 횟수·경고 이벤트·자세 근거 분리 — 2026-10-30

**완료 횟수에서 경고 이벤트를 빼서 올바른 반복/완료율로 만들던 연결을 제거했다.** 수행 목표를100% 마쳐도 전체 자세 판정은 미확인으로 표시한다. 이전 경고가 현재 실제 평가되지 않았는데 “교정됐다”고 말하는 경로도 제한했다. 이 변경은 client/native 의미 계약이며 자세 정확도나 전문가 오자세 판별 성능의 개선 실험이 아니다. 기반 `8355122`, 같은 격리 브랜치이며 main·설치/동결 앱·backend는 수정하지 않았다.

## 완료와 저장 계약

native 라우트는 NativePoseWorkoutScreen이다. 전달 warning event 수와 고유 warning key 수는 반복의 정오 라벨이 아니며, quiet/누락/초기 reference에 따라0일 수 있다. 이제 native 결과는 실제 `totalReps`를 그대로 기록하고, 기존 numeric `correctReps`/`incorrectReps`에는 **0/0 unknown 호환 placeholder**를 보낸다.0회 모두 틀림/모두 맞음이라는 판정이 아니다. 경고를 반복 수에서 빼지 않는다.

기존 `poseMetricsSummary.workoutEvidence`에 version1 메타데이터를 추가한다. completedReps, recordedWarningEvents, 그 이벤트의 `delivered_rep_scope_only` 범위, 실제 세트별 reps/weight/badCount와 `formAssessment=not_available`, assessedReps/validatedCorrectReps/postureScore=null, legacy placeholder 설명을 저장한다. 기존 key별 feedbackCounts와 event ID/grade/kind·quiet 설정·raw pose/XS·threshold·warning 수집은 유지했다. set-scope summary는 별도 흐름이며 rep event와 중복 가능한 key 집계다. 이 메타데이터도 full-form 평가 분모를 만들어 내지 않는다.

DTO·model·local JSON cache·offline sync queue·record copy가 이 메타데이터를 보존한다. 홈/캘린더→history navigation도 summary를 전달한다. score가 없으면 nullable raw value로 유지하며0으로 치환하지 않는다. 과거 numeric0/95 등은 raw legacy 값으로 보존하지만 독립 검증 근거로 인정하지 않는다. model.accuracy와 assessedPostureScore는 현재 생성자가 유효한 full-form 검증 계약을 제공하지 않으므로 null이다. raw correct/incorrect를 나눠 정확도를 만들지 않는다. completion achievement만 totalReps/targetReps이며 target이 없으면 null이다. 홈 평균도 검증된 score가 없으면 null이다. `copyWith`의 score null은 기존 값 유지이며, 명시적 clearPostureScore는 null로 지우는 별도 계약으로 테스트했다. 이번 흐름은 과거 score를 지우지 않는다.

결과 UI는 완료 목표를 performed reps로 표시하며 “전체 자세 판정: 미확인 · 완료율은 수행 횟수 기준”을 함께 표시한다. target0/누락을100%로 만들지 않는다. legacy incorrectReps에서 세트별 경고를 균등 배분하던 추정을 제거했다. 원 setResults/새 summary가 없으면 경고 기록 미확인이며, 없음/정상으로 단정하지 않는다. 기존 세트 원시 기록이 있으면 그 수는 그대로다. 과거 저장 레코드의 correctness 값을 마이그레이션하거나 재평가하지 않았다.

## 계정과 서버 응답의 제한

현재 MAIN backend source를 read-only로 확인했다. request의 correct/incorrect는 primitive int이고 source service에 합=total 검사나 score 필드는 없었다. poseMetricsSummary는 entity에 JSON으로 저장하지만 record response에는 포함하지 않는다. 따라서 새 기기/캐시 없는 서버-only history는 원 근거를 복원할 수 없고 unknown으로 남긴다.

같은 계정의 일반 refresh에서 누락된 summary·feedbackCounts·raw historical score/legacy counters를 이전 local record에서 보존한다. 이 보존은 계정별 queue/cache owner가 확정되고 현재 identity와 일치하며 provider가 여전히 active일 때만 가능하다. await 이후도 확인해 logout/switch/late response는 fail closed한다. nonempty 반환 client ID가 우선이고 상충하는 server ID로 붙이지 않는다. client ID가 없을 때만 유일한 server-ID mapping을 허용한다. 다른 계정의 재사용 ID 또는 동일 계정의 상충 client/server ID에는 근거를 붙이지 않는다.

**이것은 로컬 source 확인이지 실제 배포 API 호환성 검증이 아니다.** 아래 MAIN source SHA256으로 읽은 버전을 구분한다.

| backend 상대 경로 | SHA256 |
|---|---|
| dto/WorkoutMetadataRequestDto.java | 3aae663b73f86faf1d9eb89ab9ba0be11be9d8e7492478d961db4ba7a914ba6e |
| dto/WorkoutRecordResponseDto.java | 9416c2a93d7ad1fb2a2fce688c68ac441c886e7fbb73097d645294c2e8481b5b |
| service/WorkoutService.java | 7ff953a965e915cf6c5b059e698c643a1a9a0dfd5667a05c65dd738a5dfbb7d9 |
| entity/WorkoutRecord.java | e88149a41926eb7babdeffd5c5a1729d8422d221ba0eb72ce3aa4fe66bac351c |

MAIN backend domain source 검색에서 correctness 필드는 저장/응답에 남고 이를 사용하는 analytics ratio는 발견하지 못했다. 배포 버전/다른 소비자는 unknown을 설명하는 summary를 무시하고0/0을 품질 수치로 오해할 수 있다. 새 API 호출·backend migration·deployment는 하지 않았으며, 배포 전 actual API와 그 소비자의 unknown 계약 검증이 필요하다. 이 클라이언트 수정으로 서버 전체 의미 호환성이 입증됐다고 하지 않는다.

## 교정 칭찬과 실제 오디오

judge의 원 fired 조건/수치/threshold는 유지하고, 실제 실행된 branch의 조건이 관측됐는지 별도 evaluated set으로 수집한다. 기본 metrics만 충분한 것과 특정 이전 경고가 평가된 것은 다르다. praise_fixed는 이전 경고가 현재 evaluated에 있고, reference/current/view가 유한하고 충분하며 현재 gate에서 적용되고, 이전과 같은2D/3D source이고, 그 key가 여전히 전달 가능할 때만 허용한다. quiet로 바뀌거나 reference 부족·view 미상/반대·source 변경이면 부재를 교정 확인으로 간주하지 않는다. overlay 상태는 이 근거로 사용하지 않는다. composite lockout은 필요한 양쪽 metric이 있어야 clearance를 인정한다. 일반 praise_good 격려는 유지했다.

praise_fixed 문구는 “관찰한 항목이 나아졌어!” / “That measured issue improved!”로 제한했다. 한국어 native WorkoutVoice는 원래 bundled `<key>.mp3`를 현재 Flutter text보다 먼저 선택한다. 이번에는 의미를 바꾼 praise_fixed/praise_clean_set key의 bundled 후보를 반환하지 않아 current text/TTS로 간다. 파일을 삭제·재생성하거나 새 음성을 내려받지 않았다. 해당 녹음은 현재 workspace asset 경로에서 발견되지 않았으므로 청취/원음 문구를 검증했다고 하지 않는다. 녹음이 남은 bundle에서도 과거 key 녹음이 새 의미를 덮어쓰지 못하게 하는 라우팅 수정이다.

## legacy simulation과 소비자 감사

lib 전체 참조를 확인하면 legacy workoutProvider를 시작/소비하는 active workout 화면은 없으며 결과 화면이 reset하던 유일한 참조도 제거했다. 해당 demo timer를 직접 호출하더라도 random postureScore와 “Perfect rep!”를 만들지 않는다. 여전히 demo의 synthetic rep/counter 로직은 실제 관측으로 연결하지 않았으며 문서/피드백에서 demo로 구분한다. native 카운트나 XS에는 연결하지 않는다.

전체 lib/test의 raw score·accuracy·achievement·correct/incorrect 소비자를 검색했다. 홈/캘린더는 raw legacy payload를 history로 전달하되 결과는 completion adapter와 explicit unknown을 사용한다. home avg는 nullable assessed scores만 사용한다. DTO/queue/cache의 raw 과거 수치 보존은 검증된 품질로의 승격이 아니다. API 문서/다른 서버 소비자의 오래된 의미는 별도 한계다.

## 최종 검증

- Dart **25개 통과**: workout_evidence, workout_metadata_dto, native_pose_workout_screen, kori_feedback_lines, native_pose_channel, account_workout_records, record_id_conflict 테스트. warning events4/rep1에서도 accuracy unknown/완료율100%, 목표 일부와 무목표, raw legacy0/95 및 score누락, DTO/cache/queue copy, 계정A→B late response·재사용 ID와 동일 계정 client/server conflict, 원 계정 refresh 보존을 검사했다. widget은 완료100%/50%에서도 전체 자세 미확인을 표시한다. test server는 fake이며 external API/TTS를 호출하지 않는다.
- Swift **75개 통과**: FormWarnings39 + support corridor16 + raw support evidence12 + WorkoutSessionBridge8. gate/reference 누락·source변경·disabled prior rule·NaN/Infinity에서 교정 칭찬 억제, 실제 같은 rule/source의 관측된 개선 유지, changed-key bundle/TTS routing과 기존 raw wrist precedence를 검사했다. bridge의 기존 작은 합성 H.264 recorder 검사도 포함한다.
- 최종 `flutter analyze --no-pub lib test`: **No issues found**. `git diff --check` 통과. 기존 offline dependency cache만 사용했고 새 Pods/모델/녹음 다운로드는 없다.

미검증: actual API roundtrip, 독립 iPhone 시각/음성 재생, 실제 운동 전문가 기준 대비 정확도/각도·시간 정렬. root의 별도 빌드/기기 작업 결과는 이 테스트 수치에 포함하지 않는다. 원 Fit3D 정확도 FAIL과 범위 압축은 미해결이며, 이번 패치로 모든 false-normal feedback 또는 full-form validation이 완성됐다고 하지 않는다.
