# 팀원(프론트엔드·앱) 요청 정리 — 2026-10-20

main 병합 뒤 요청과 별도 AI 브랜치의 작업 상태를 정리했다.

## 1. 데모 경고

- **상태**: main 운동 화면의 `_advanceDemoFeedback`(렙마다 칭찬 ↔ 운동별 대표 경고)과 `koriDemoWarningKeyByExercise` 때문에 실제 판정과 무관한 경고가 화면·음성·세트 기록·"자주 나온 실수"에 들어갔다. AI 쪽에서 데모를 제거하고 네이티브 판정 경고를 기본 전달하도록 바꿨으며(`FormCommonConfig.enabledFeedbackKeys`), 세트 시작·끝 알림(`startSet`/`endSet`)도 복구했다. 2026-10-20 integration/ai와 main에 병합(사용자 승인, D-M-02).
- **근거(파일·커밋)**: `lib/features/workout/screens/native_pose_workout_screen.dart`, `lib/features/workout/data/kori_feedback_lines.dart`, `ios/Runner/NativePose/Evaluators/FormWarnings.swift`. 수정: `ai/real-feedback`의 `a938ab1`.
- **제안**: 실제 판정 경고만 화면·음성·기록에 들어가는지 확인. 판정 기준값은 아직 검증 전이라 정상 자세에도 경고가 날 수 있다.

## 2. 음성 끊김

- **상태**: `KoriSpeaker.speak`가 매번 `stop()`을 먼저 불러, 렙이 빨리 이어지면 대사가 중간에 끊긴다.
- **근거(파일·커밋)**: `ios/Runner/NativePose/Bridge/KoriSpeaker.swift`. 촬영 화면 음성(`ios/Runner/NativePose/Calibration/CalibrationVoice.swift`)은 `ai/calib-voice-calm`의 `47cb42d`에서 같은 안내가 1초 유지돼야 말하고, 대사 사이 1.5초 쉬도록 바꿨다.
- **제안**: 운동 중 경고가 아닌 대사는 말하는 중이면 건너뛰고, 대사 사이 1초 정도 쉰다.

## 3. 푸시업 가로 촬영

- **상태**: 화면 회전·안내는 프론트엔드 작업. AI 파이프라인의 가로 입력 처리는 AI 쪽에서 확인 중.
- **근거(파일·커밋)**: 사용자 요청 "푸시업할 때는 폰을 가로로 돌리라고 하는 게 낫다, 인터페이스도 가로로". 관련 화면: `lib/features/workout/screens/native_pose_workout_screen.dart`.
- **제안**: 푸시업에서 가로 촬영 안내와 가로 인터페이스를 적용하고, AI 쪽 입력 확인 결과와 맞춘다.

## 4. 화면 자동 꺼짐

- **상태**: 운동 화면은 자동 잠금을 막지 않아 폰을 세워 두고 운동하면 세트 중간에 화면이 꺼진다(체형 촬영 화면만 막음). AI 쪽 네이티브 코드에서 수정, 2026-10-20 integration/ai와 main에 반영(사용자 승인, D-M-02).
- **근거(파일·커밋)**: `ios/Runner/NativePose/Camera/CameraPosePreview.swift`. 수정: `ai/lift-app`의 `0a4d830`을 integration에 맞게 옮김.
- **제안**: 화면을 터치하지 않아도 세트 중 화면이 유지되는지 실제 기기에서 확인.

## 5. 소리 끄기 버튼

- **상태**: main 운동 화면의 `_SoundToggleButton`은 아이콘만 바뀌고 실제 음성(`KoriVoiceService`)은 꺼지지 않는다.
- **근거(파일·커밋)**: `lib/features/workout/screens/native_pose_workout_screen.dart`, `lib/services/kori_voice_service.dart`.
- **제안**: 버튼의 음소거 상태를 실제 음성 재생에 연결한다.

## 6. ElevenLabs 키

- **상태**: git 제외 키 파일의 값이 빌드할 때 `Info.plist`의 `ElevenLabsApiKey`에 평문으로 들어가 앱 파일에서 꺼낼 수 있다.
- **근거(파일·커밋)**: `docs/handoff/security_followup.md` 3-1, `ios/Runner/Info.plist`. 키 파일 경로는 `ios/Flutter/Secrets.xcconfig`이며, 이 워크트리에는 없다(내용 열람 안 함).
- **제안**: 대시보드에서 키 권한을 TTS만으로 제한하고 월 한도를 설정한다. 장기적으로 서버를 거치는 방식으로 바꾼다.

## 7. 세트 요약 경고

- **상태**: AI 쪽 세트 요약 경고(`scope: "set"`, 참고 등급)는 운동 기록의 경고 횟수에만 들어가고 말풍선·음성은 없다. 세트 요약 음성과 겹치지 않게 한 처리다.
- **근거(파일·커밋)**: `ios/Runner/NativePose/Evaluators/FormWarnings.swift`, `lib/features/workout/screens/native_pose_workout_screen.dart`의 AI 쪽 변경(`ai/real-feedback` `a938ab1`).
- **제안**: 결과 화면에도 보일지는 팀원이 결정.

## 8. 체형 분석 화면

- **상태**: main 버전을 쓰기로 해서(D-M-01) 작업 상태 polling이 없고, 앱이 서버 분석 결과를 받아오지 않는다. `CalibrationUploadService.fetchJob`은 남아 있다.
- **근거(파일·커밋)**: `docs/decisions.md` D-M-01, `lib/features/onboarding/screens/onboarding_analyzing_screen.dart`, `lib/features/onboarding/services/calibration_upload_service.dart`.
- **제안**: 결과가 필요해지면 `fetchJob`으로 polling·진행률·실패 문구를 다시 얹는다. 서버 결과 형식은 `docs/handoff/teammate_calibration.md` §5.

## 9. 벤치프레스·데드리프트 경고 대사

- **상태**: 경고 키 6개는 Flutter 대사가 없어 꺼져 있다(`FormWarningTracker.keysWithoutFlutterLines`).
- **근거(파일·커밋)**: `ios/Runner/NativePose/Evaluators/FormWarnings.swift`의 AI 쪽 변경(`ai/real-feedback` `a938ab1`, integration·main 반영). 대사 초안은 `docs/progress/2026-10-10.md`.
- **제안**: 초안을 확인해 `lib/features/workout/data/kori_feedback_lines.dart`에 대사를 넣으면 해당 키가 켜진다.
