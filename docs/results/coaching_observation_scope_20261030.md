# 실시간 overlay 관측 범위와 평가 보류 분리 — 2026-10-30

**평가하지 못한 항목이나 자기 기준 대비 변화가 없다는 사실을 overlay의 정상 녹색 기본값으로 합치던 경로를 분리했다.** 이 변경은 표시 의미를 고치는 독립 검토 브랜치이며, 실측 자세 정확도 개선이나 앱 전체 정상 판정 문제 해결을 뜻하지 않는다.

기반: `5f4b099`, branch `fix/coaching-observation-scope-20261030`, 별도 worktree. main·설치 앱·동결 앱·다른 worktree는 수정하지 않았다. 모델/XS 입력/관절/프레임·반복 수·history·judge/음성·threshold·quiet/default-disabled 설정은 유지했다. 새 실험 기능을 켜지 않았고 배포·설치·merge·모델 다운로드·Home/GPU/폰 호출은 없다. 속도 최적화 작업도 재개하지 않았다.

## 확인한 문제와 변경

기존 `OverlayValue.notApplicable`는 기준 부족과 잘못된 view를 포함했고, 미측정 segment는 렌더러의 plain green 기본값으로 갔다. `unknown.subtracting(out.severity.keys)`는 같은 segment의 다른 정상 측정이 누락 증거를 지우게 했다. squat lockout의 knee/hip `compactMap`도 한쪽 누락을 숨겼다. self-relative lockout은 세트 전체가 계속 덜 펴져도 자기 최대와 같으면0이다.

`FormWarnings.swift`에 rule identity를 유지하는 `OverlayObservation`을 추가했다. segment마다 측정한 rule과 scope(`frameGeometry`, `withinRepChange`, `selfRelative`), 현재 필요한데 빠진 증거(`baseline`, `missingQuantity`, `reference`, `viewUnknown`, `noObservation`), 알려진 phase/view 제외를 따로 보존한다. 알려진 phase/반대 view는 inactive metadata이며, 적용되는 다른 rule의 관측을 지우지 않는다. 적용되는 rule도 측정도 없으면 neutral/unassessed다. 모르는 view를 side view로 간주하지 않는다. row는 검증된 session side-view gate를 우선하고, 그 전에는 명시적인 frame view만 사용한다.

합성 knee/hip rule은 알려진 수치와 누락 이유를 동시에 보존한다. 따라서 정상 knee 수치가 hip 누락을 지우지 않으며, knee의 큰 편차가 알려진 상태에서도 hip 누락을 함께 표시한다. display baseline은 원래 첫 N회 reference를 쓰되, 그 metric이 모든 N회에 실제로 존재해야 준비 완료가 된다. 이 보수적인 표시 계약은 judge의 reference 계산이나 원 보고서를 변경하지 않는다.

`OverlayShade`로 CameraFrameData→smoother→실제 PoseOverlayRenderer를 연결했다. 렌더러의 기본값도 neutral이다.

| 표시 상태 | 의미 / 표시 |
|---|---|
| unassessed / partial인데 수치 편차0 | 회색 점선. 필요한 증거가 부족하거나 적용되는 관측이 없음 |
| self-relative 또는 동작 내 변화만 측정했고 편차0 | slate 점선. 제한된 상대 일관성만 관찰; 올바른 폄/깊이/전체 자세 승인 아님 |
| 해당 frame geometry rule들이 측정됨 | 기존 연속 색상. 표시한 항목의 관측 범위만 뜻함 |
| 상대/partial 범위에서 수치 편차>0 | 해당 연속 색상의 점선. 누락/scope를 유지한 관측 편차 |
| 원 손목/지지 관측 불확실 | 위 모든 상태보다 우선한 기존 회색 점선, solid glow/joint dot 없음 |

**severity>0는 연속 수치 편차이며 threshold를 넘은 자세 오류라는 뜻이 아니다.** 내부 style명 `limitedIssue`도 scope/coverage가 제한된 표시 편차를 뜻한다.0–1 severity ramp와 임계값은 바꾸지 않았다. 녹색이 나오는 경우도 그 frame에서 표시한 geometry rule의 범위이며 신체 부위 전체/운동 전체 정상 승인으로 정의하지 않는다. 상태는 smoothing하지 않으며 상태가 바뀌면 과거 녹색/빨강을 이어 붙이지 않는다. 상대 수치가0이 되거나 증거가 사라지면 이전 편차를 즉시 해제한다.

quietByDefault는 기존처럼 음성/Dart 전달을 제어한다. overlay table에서 해당 측정을 임의로 제거하거나 새 규칙을 추가하지 않았다. heel-rise/shrug 등 기존 미활성 규칙도 켜지 않았다. wrist guard의 raw/assessment copy 및 지지 corridor 소스는 수정하지 않았다.

## 검증

최종 동작 코드에서 실행:

```sh
swift test --package-path ios/CalibrationEngineKit \
  --filter 'FormWarningsTests|PushUpSupportCorridor2DTests|PushUpSupportEvidence2DTests'
```

**63개 통과**: FormWarnings35, support corridor16, raw support evidence12. 기존 overlay smoothing 테스트를 새 관측 계약으로 갱신했고,8개 의미 회귀 테스트를 추가했다.

- 처음3회 모두 팔꿈치를 덜 편 synthetic 반복에서도 live lockout0이 유지되지만, 실제 tracker/table의 top과 bottom 상태는 relativeConsistency/상대 점선이며 정상 승인 스타일이 아님.
- 기준 미준비, first3 중 관련 metric 누락, phase 전체 비적용, 알려진 반대 view, view 미상은 각각 보류/비적용 metadata와 neutral 처리.
- 실제 partial3D에서 knee 정상/hip 누락이 지워지지 않음. knee 편차가 threshold 이상일 때도 수치와 hip 누락이 같이 남고 제한된 점선으로 표시.
- 다른 rule의 정상 수치가 누락 rule을 지우지 않음. 완전한 frame geometry 관측만 observed scope로 분류.
- row session gate 미확정+frame view 누락은 보류, session side-view 확정 이후 frame view 누락은 기존 session 근거를 사용.
- quiet 전달 설정은 그대로이며 raw wrist uncertainty가 known deviation보다 우선. 기존 원본 관측·assessment copy·지지 guard 회귀도 통과.

실제 renderer와 package engine sources를 함께 `swiftc -typecheck -parse-as-library -module-name OverlayRendererCheck ios/CalibrationEngineKit/Sources/CalibrationEngineKit/*.swift ios/Runner/NativePose/Overlays/PoseOverlayRenderer.swift`로 검사해 통과했다(macOS SDK; 기존 AVFoundation deprecation 경고만 있음). CameraPosePreview는 `swiftc -frontend -parse` 통과했으며 전체 iOS 앱 타입검사/링크/빌드나 실기기 시각 검증을 대신하지 않는다. `git diff --check` 통과. package의 기존 로컬 소스만 빌드했으며 Pods 복원/다운로드나 전체 앱 빌드는 하지 않았다.

## 남은 정확도 범위

이 테스트의 synthetic geometry는 표시 계약을 검증하며, 실제 영상의 자세/관절 정확도 또는 전문가 라벨 대비 FP/FN을 측정하지 않는다. GVHMR row 범위 압축·pushup 기준 반복 선택 오류·관절 정의 문제는 해결되지 않았다. 기존 rep judge와 `praise_good`/음성은 범위 밖이어서 그대로다. 따라서 이 overlay 패치만으로 앱 전체의 허위 정상 피드백이 없어졌다고 주장하지 않는다.

다음 검토는 이 소스의 실제 iPhone 표시에서 neutral/relative/partial의 구분과 손목 우선순위를 확인하고, 전문가 기준·독립 절대 정상 표준과 관측 phase가 고정된 독립 검증에서 표시/판정/음성 의미를 함께 검사하는 것이다. 처음 나쁜3회를 올바른 자세의 표준으로 사용하거나 임의 절대 각도·대칭 보정을 추가하지 않는다. 설치/배포는 이번 범위에 없다.

## 같은 세트 요약의 허위 정상 표현 후속 수정

후속 범위는 native 화면의 세트 완료 요약, 그 화면이 넘긴 저장 세트 기록 표시, 공유 `praise_clean_set` 대사다. `praise_good`/`praise_fixed`와 event ID/kind·grade·quiet·집계·metrics·스키마·모델/기준은 변경하지 않았다.

실제 호출/집계 경로를 확인했다. `_onNativeFeedback`가 전달된 warning event마다 `_badCountThisSet`를1 증가시키고 `_warningKeysThisSet`에는 서로 다른 키를 저장한다. `_SetResult.badCount`는 이 event 수, `fixCount`는 키 집합 크기다. `_speakSetSummary`와 `_KoriBreakMessage`가 모두 fixCount==0이면 같은 `praise_clean_set`을 선택한다. 전자는 native KoriVoiceService로 텍스트를 전달하고 후자는 같은 텍스트를 말풍선에 표시한다. scope=set 요약 경고는 별도 `_nativeFeedbackCounts`에만 더해지고 이 fixCount/badCount에는 들어가지 않는다. 따라서 quiet/관측 불가/초기 기준/서로 다른 집계 범위에서도0이 나올 수 있다. 이 선택/집계는 유지하고 그때 나가는 대사를 완료·수고 격려로 바꿨다: “{reps}회 완료! 수고했어!” / “{reps} reps completed! Nice effort”.

native `_SetRow`의 badCount==0 “완벽해/Perfect” 녹색은 중립 “완료/Completed”로 바꾸고 세트 번호 배경도 중립 처리했다. 동일 `setResults.badCount`를 읽는 결과 `_SetRecordRow`의 “안정/Stable” 녹색도 중립 완료로 바꿨다. 양수 count에서 운동명만으로 body part를 추정하던 row는 일반 기록 경고 횟수로 표시한다. 같은 `_FeedbackCard`의 경고0→“모든 자세 좋음”, 경고 있음→임의 inward drift 및 “depth/tempo 좋음” 문구도 각각 기록된 경고 유무와 완료 격려로 교체했다. 원 카운트만으로 특정 오자세나 별도 품질을 추정하지 않는다.

기존 캐시에서 `flutter pub get --offline` 성공했고 lock 변경/Pods/외부 패키지 다운로드는 없다. 최종 Dart 코드에서:

- `flutter test --no-pub test/kori_feedback_lines_test.dart test/native_pose_workout_screen_test.dart test/native_pose_channel_test.dart`: **12개 통과**(대사 계약3, native channel4, widget5).
- 실제 widget의 **관측·자세 이벤트 없이 rep-count만 증가시킨 세트 완료**를 ko/en으로 실행해 중립 완료 색상과 횟수 격려, 완벽/교정 단정 부재를 확인했다. read-only history fixture는 저장/네트워크 없이 badCount0/1을 각각 렌더해 완료 또는 일반 기록 경고를 표시하고 “안정/정상”이나 추정 knee fault/inward drift/depth·tempo 승인으로 바뀌지 않음을 검사했다.
- 기존 widget fixture에 mock SharedPreferences/앱 font theme를 제공하고, 기존 대사 키 계약에 이미 등록돼 있던 log-only bench/dead6개를 반영했다. 실제 활성화 키는 바꾸지 않았다. 새 테스트는 대사 복사본만 비교하는 대신 실제 완료/저장 표시 흐름을 검사한다.
- 수정된3개 lib 파일과2개 테스트에 대한 `flutter analyze --no-pub ...`: **No issues found**. `git diff --check` 통과. native runtime 코드는 앞 절의63개 테스트 이후 변경하지 않았다.

남은 의미 차이는 명확하다. 저장되는 legacy `correctReps = totalReps - warningEventCount`와 그 기반 달성률/점수는 **실제 올바른 반복 수가 아니다**. 경고 event 수·고유 경고 키 수·set-scope 경고 수가 서로 다르며 판정불가 분모도 기록하지 않는다. 이번에는 이를 스키마/계산까지 확장하지 않았다. 다른 mock/provider의 “Perfect rep!” 및 기존 `praise_fixed`의 품질 문구도 별도 남아 있고 `praise_good`는 일반 격려로 유지했다. 그러므로 앱 전체 허위 정상 피드백이 해결됐다고 부르지 않는다. 실기기 시각/음성 재생·원 자세 정확도는 여전히 미검증이며, 설치·전체 앱 빌드·배포는 하지 않았다.
