# 신체 캘리브레이션·실시간 AI 개선 현황

2026-10-05 로컬 `feat/ai`, 기반 커밋 `50d68c09ec1e5730b8512b8737d58d8371ed0bba`를 조사하고 아래 변경을 적용했다. 변경은 아직 커밋하지 않았다. 원격 최신 브랜치 조사나 실제 iPhone 성능 측정을 했다는 의미는 아니다.

이번 작업은 **촬영 데이터 일관성·저장 실패 복구·시간 기반 정지 판정**을 우선 보강하고, 입력 버퍼 재사용과 스쿼트의 불필요한 손 추론 생략을 적용했다. MotionAGFormer 앱 통합, 해상도 변경, 서버 배포는 포함하지 않는다. 지연·발열·전력 개선율은 아직 측정하지 않았다.

## 현재 연결 경로

- 캘리브레이션: 미러링하지 않은 카메라 영상 → 이전 사람 영역 기반 3:4 crop → RTMPose-s + Vision 얼굴 검출 → 캘리브레이션 판정 → 사진 4장·manifest → 사용자 동의 후 서버리스 업로드 클라이언트.
- 운동 카메라: fast direct resize → RTMPose-s → 원래 COCO17 2D → 운동별 evaluator. 손 추론 결과는 overlay 보정용이며 evaluator 입력이 아니다.
- MotionAGFormer 전체 2D→3D 경로는 연구 도구에 있으나 현재 앱 카메라에는 연결되지 않았다. 연구 M0의 full-image affine·27프레임 lookahead5 정의는 변경하지 않았다.

## 적용한 변경

### 1. 저장 성공 뒤에만 촬영 완료 확정

`CalibrationEngine.swift`는 UUID가 있는 capture 요청을 만들고, `resolveCapture(id:saved:)`가 성공해야 reference·capturedViews·완료 상태를 확정한다. 저장 대기 중 중복 요청과 오래된 ACK는 무시한다.

`CalibrationSession.swift`는 JPEG 인코딩과 `CalibrationStore.writeCapture` 성공 뒤 ACK한다. 실패하면 `saveFailed` 안내를 보내고 동일 view를 다시 촬영할 수 있다. 저장 오류를 영구적인 카메라 오류로 표시하지 않는다.

`CalibrationStore.swift`는 매 view마다 JPEG를 먼저 원자적으로 쓰고 manifest를 원자적으로 교체한다. manifest가 commit 기준이며 두 파일을 묶은 파일시스템 트랜잭션은 아니다. manifest 쓰기가 실패하면 참조되지 않은 JPEG가 남을 수 있지만 이전 manifest와 촬영 개수는 유지된다. 재촬영은 미확정 view 파일만 교체한다. 앱 강제 종료 후 캡처 상태 복원 UI는 구현하지 않았다.

### 2. 선택 사진과 메타데이터를 같은 snapshot으로 보관

hold 중 필수 관절 평균 confidence가 가장 높은 프레임을 선택한다. 선명도 점수를 계산하는 방식은 아니다. 이미지·키포인트·측정값·camera PTS·이미지 크기·intrinsics·카메라 콜백 시점의 최신 IMU 상태를 함께 보관한다. hold가 끊겼다가 시작되면 이전 후보를 재사용하지 않는다.

`r`, `delta`, 귀·얼굴 confidence, 중력은 선택 사진의 snapshot에서 계산한다. 정면 reference는 기존 방식대로 hold 표본의 중앙값이다. 사진별 camera 정보는 `views[].intrinsics`, `imageWidth`, `imageHeight`에 기록한다. schemaVersion 1의 top-level camera 값은 정면 사진의 호환용 값이다.

CoreMotion의 `deviceTimestamp`도 별도로 저장한다. 이는 사진이 도착했을 때의 최신 IMU 표본이며, camera PTS와 같은 clock이라고 가정하거나 하드웨어 동기화·보간이 완료됐다고 주장하지 않는다. intrinsics의 회전 보정 추정 로직 자체도 아직 그대로다.

### 3. FPS에 덜 의존하는 정지 판정

`CalibrationConfig.swift`, `CalibrationEngine.swift`에서 다음을 고정했다.

| 항목 | 현재 값·정의 |
| --- | --- |
| 정지 지표 | 필수 관절 평균 이동량 / torso 길이 / timestamp 차이 |
| 최대 속도 | `0.45 torso/s` |
| 최대 frame gap | `0.25 s` |
| hold | `0.8 s`, 최소 유효 표본 5개 |
| 오류 | 잘못된 timestamp·키포인트, 분석 실패, 큰 gap은 hold 연속성 해제 |
| 얼굴 검출 오류 | `.unknown`으로 분리, 얼굴 없음 `.none`과 구분 |

속도 임계값은 기존 `0.015 torso/frame`을 **30 Hz 기준으로 환산**한 값이다. 실기기에서 재튜닝·정확도 검증된 최적값이 아니다. 4 FPS 미만에서는 250 ms gap 제한 때문에 hold가 이어지지 않을 수 있다. 합성 동일 동작의 10·15·30 FPS와 불규칙 표본 테스트는 통과했다. 운동 evaluator의 프레임 개수 기반 상태 전이는 이번에 바꾸지 않았다.

### 4. 큐 동기화와 생명주기 정리

`CalibrationFrameGate`의 NSLock으로 카메라 큐의 acquire와 처리 큐의 release를 동기화한다. 프레임 하나만 처리하는 정책과 늦은 프레임 폐기는 유지한다. capture handler의 설정·해제는 카메라 큐가 소유한다.

권한 요청에는 실행 ID를 부여해 취소 후 늦게 도착한 권한 응답이 카메라를 시작하지 못하게 했다. 부분 setup 실패에서도 camera·motion·로그·analyzer를 정리한다. DeviceMotion callback에는 generation 검사를 넣어 이전 실행의 늦은 결과를 무시한다. 실제 권한 팝업·빠른 화면 전환은 iPhone 수동 검증이 남아 있다.

### 5. RTMPose 입력 메모리 재사용

`RTMPoseInputWorkspace`가 Float32 입력 텐서·RGBA 배열·feature provider를 보관한다. 캘리브레이션과 운동 카메라의 직렬 처리 경로가 각자의 workspace를 재사용한다. 모델·정규화·decode·좌표 복원 규칙은 변경하지 않았다. 다른 큐에서 같은 workspace를 동시에 쓰면 안 된다.

운동 fast resize의 CGContext는 copy blend로 이전 프레임 픽셀 잔존을 방지한다. 전체 CGImage 중간 생성은 아직 남아 있으므로 zero-copy 구현이라고 표현하지 않는다. 모델 로딩도 여전히 동기 경로다.

### 6. 운동별 손 추론 선택

`NativePoseExercise.handBranchEnabled`는 스쿼트에서 손 모델 초기화와 추론을 기본 생략한다. 다른 네 운동은 기존 손 overlay를 유지한다. raw COCO17을 받는 evaluator 계약은 그대로다.

Xcode 실행 환경 변수 `BPT_CAMERA_HANDS=1`은 모든 운동에서 활성화, `=0`은 모두 비활성화한다. 미지정 시 운동별 기본값을 사용한다. 비교용 기능이며 현재 Flutter 설정 UI에는 노출하지 않았다. 실제 latency·발열 A/B 측정은 남아 있다.

## 검증 결과와 재현

- Swift 테스트 28개 통과: 기존 엔진 동작, 저장 ACK·실패 후 재촬영, FPS·gap·timestamp, snapshot manifest, 동시 처리 제한, 손 추론 정책, 입력 workspace.
- RTMPose 실제 로컬 CoreML 모델을 macOS CPU에서 실행해 새 provider와 재사용 provider의 SimCC 전체 출력을 세 입력으로 비교했다. 허용 오차 `1e-6` 내 통과했다. UIKit resize 전체나 iPhone Neural Engine parity까지 검증한 것은 아니다.
- Thread Sanitizer는 `testGateAllowsOnlyOneInFlightFrameAcrossQueues` 1개를 실행해 통과했다. 카메라·Session 전체의 경쟁 상태를 검증한 결과는 아니다.
- Flutter 전체 테스트 64개 통과. 실제 클라우드 전송 대신 HTTP 어댑터와 합성 파일을 사용한다.
- 업로드 서비스·화면·관련 테스트 4개 Dart 파일의 정적 분석도 통과했다.
- 녹화 영상 `dummy_03_male-4-sport.mp4` 22초를 기본 설정으로 재생했다. 중단 없이 끝났지만 위치·A자 자세·발 간격 조건 때문에 **촬영 0장, finished=false**였다. 변경 전 기반 커밋을 별도 임시 폴더에서 같은 모델·영상으로 실행했을 때도 출력된 안내 timeline과 촬영 결과가 동일했다. 이 영상에서 새 촬영 회귀는 관찰하지 못했으나, 실제 영상의 4장 완료 검증은 통과하지 못했다. 조건을 완화해 성공으로 바꾸지 않았다.
- 현재 replay 결과 위치: `/tmp/bpt-calibration-smoke.QtlvI4`. 변경 전 비교 코드는 `/tmp/bpt-calibration-reference.anIOFA`. 임시 경로는 OS 정리 대상이며 재현 명령은 아래에 남긴다.
- `flutter build ios --simulator --debug --no-pub` 전체 빌드 성공(exit 0). 산출물은 `build/ios/iphonesimulator/Runner.app`. 이번 Xcode clean build는 의존성 재컴파일을 포함해 1437초(약 24분)가 걸렸다. 앱 실행·카메라·실기기 추론 성능 검증과는 별개의 컴파일 검증이다.
- 기존 `assets/icons/nav/`, `assets/icons/home/` 누락 경고와 macOS replay의 deprecated AVFoundation API 경고는 남아 있다.

```sh
swift test --package-path ios/CalibrationEngineKit
swift test --package-path ios/CalibrationEngineKit --sanitize=thread \
  --filter testGateAllowsOnlyOneInFlightFrameAcrossQueues
flutter test --no-pub
flutter build ios --simulator --debug --no-pub
```

재생 도구에는 기존 산출물 보호를 위해 `--output-dir` 옵션을 추가했다.

```sh
swift run -c release --package-path ios/CalibrationEngineKit calibration-replay \
  --output-dir /tmp/bpt-calibration-check \
  outputs/calibration_dummy_videos/dummy_03_male-4-sport.mp4
```

이 더미 영상에는 편집된 정지 구간이 있다. replay는 실제 RTMPose·Vision·엔진과 JPEG 저장을 사용하지만 카메라·IMU는 대체한다. 앱 Session의 최고-confidence 이미지 선택·manifest 저장은 replay 경로와 동일하지 않으며 별도 저장 테스트로 검사한다. 따라서 replay 성공을 자연 동작·체형 다양성이나 실제 iPhone 전체 기능의 검증으로 해석하면 안 된다.

## 아직 남은 우선순위

1. iPhone에서 단계별 p50·p95 지연, frame drop, 실효 FPS, 발열을 측정하고 손 추론 A/B를 비교한다. 250 ms gap 때문에 실제 입력이 자주 끊기는지도 확인한다.
2. intrinsics를 센서→회전 버퍼→저장 이미지 변환으로 명시적으로 변환하고 reprojection을 검증한다. `intrinsics.source` 구분은 유지한다.
3. 1080p 대 4K, 얼굴 ROI·검출 빈도를 별도 정확도 실험으로 비교한다. 현재 4K 우선 정책과 매 분석 프레임 얼굴 검출은 유지했다.
4. 운동 evaluator에 PTS를 전달해 프레임 수·프레임당 변화량 기반 상태 전이를 시간 기준으로 검증한다.
5. MotionAGFormer 모델 리소스·runner·27프레임 lookahead5·index 21 target PTS·동시점 2D/3D packet·evaluator 계약을 함께 통합한다. 사용되지 않는 플래그만 true로 바꾸면 되는 작업이 아니다.
6. 서버리스 공급자·API 주소·인증 계약이 확정되면 [업로드 계약](calibration_serverless_upload.md)에 따라 실제 서버와 연결한다. 사진 접수와 체형 분석 완료는 별개다.

후속 작업용 짧은 프롬프트:

> BPT의 docs/research/calibration_realtime_ai_review.md와 calibration_serverless_upload.md를 읽고 이어서 작업해줘. 기존 변경은 보존하고 완료 항목을 다시 구현하지 마. 미검증 항목부터 확인하고 실측하지 않은 성능·AI 결과를 만들지 마.
