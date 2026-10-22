# 가로로 든 폰 — 분석을 중력 기준으로 (ai/orientation-m2b98256)

브랜치 `ai/orientation-m2b98256`(origin/integration/ai `2b98256` = main에서 시작). **main/integration에는 미병합.**
Codex 재개에서 기기 에이전트가 `ai/lift-app-m2b98256` 시험 브랜치에 회전 및 시간창 분리 패치를 적용했다(`ebcfb38`, C1 `50194eb` 위).
기기 확인은 그 시험 빌드에서 진행한다(아래 “lift-app 병합 메모”).

**용어**
- 버퍼 = 카메라가 주는 프레임. 캡처 연결이 `.portrait`로 고정이라 항상 세로 720×1280이다.
- 회전(CaptureRotation) = 버퍼 안에서 장면이 시계 방향으로 돌아간 각도(0/90/180/270). 폰을 가로로 들면 90 또는 270.
- 분석 프레임 = 버퍼를 회전만큼 되돌린 영상. 여기서는 중력이 영상 아래쪽이다(사람이 서 있으면 머리가 위).
- 세로 = 회전 0. 이때는 분석 프레임 = 버퍼, 아무것도 바뀌지 않는다.

## 문제 (기기 에이전트 측정, de42b9a m COCO17, Exercise3D 푸시업 15클립을 카메라 대신)
반전 뒤 시계 방향 90°로 돌려 가로로 든 폰을 흉내 냈다(`BPT_CAMERA_VIDEO_ROTATE=90`). 로그: Home
`/home/junjeon/bpt-runs/lift-app/20261020-device-video-landscape-pushup-de42b9a/`(270°는 `…-landscape-pushup270-de42b9a/`).
- 렙은 맞았다(90°·270° 모두 150/150). 렙 상태기계는 관절 사이 각도만 써서 회전에 영향을 안 받는다.
- 3D가 무너졌다. 90°: 사선 cam2 두 클립 ok 92–95% → 6–7%(partial_3d 85–90%). 270°: 낮은 측면 cam3 세 클립 ok 88–96% → 26–31%.
- 가로에서만 나오는 경고: 90°에서 hip_pike 9클립, hand_position 10클립, 정면 head_up 4–9렙. 정면의 setup_side_view(옆으로 서 주세요)가 사라짐.
  270°에서도 방향만 다른 같은 종류의 오경보.
- 원인: 방향 처리가 없다. 규칙·옆면 판정·crop은 “영상 위 = 세상 위”를 가정하고, XS(MotionAGFormer, 똑바로 선 카메라로 학습)는 누운 사람을 그대로 받는다.

## 설계

### 1. 회전 신호 — CoreMotion 중력, 사분면 + 히스테리시스
- 이미 있는 `DeviceMotionMonitor`(Calibration, CoreMotion 30 Hz, 락으로 보호된 최신 값)를 운동 카메라에서도 하나 띄운다. 새 센서 코드 없음.
- 중력 → 회전: 버퍼 x = 기기 x, 버퍼 y = 기기 −y(전면 카메라도 같다 — 버퍼가 미리보기처럼 좌우 반전돼 있어서). 그래서 세상 위쪽은 버퍼 위쪽에서
  시계 방향 `atan2(−gx, −gy)`도에 있다. 예: 기기 오른쪽 면이 아래(gx = +1) → 270, 기기 왼쪽 면이 아래(gx = −1) → 90.
- `CaptureRotationTracker`(PoseCoordinateTransforms.swift): 지금 사분면 중심에서 45° + **20°**를 넘어야 새 사분면으로 바뀐다(대각선 근처에서 깜빡임 없음).
  화면 평면 안 중력이 **0.5 g** 미만(화면이 수평면에서 30° 미만으로 눕혀짐)이면 각도를 무시하고 지금 값을 유지한다. 처음 값은 0(세로). 두 값은 제안값이고 기기에서 맞춘 값이 아니다.
- 처리 큐에서 프레임마다 한 번 갱신한다(CoreMotion 최신 표본). 회전이 바뀌면 사람 crop을 버린다(crop은 이전 프레임 좌표라). 콘솔에
  `CameraPosePreview capture rotation 0 -> 270`.
- 실행 시 고정: `BPT_FORCE_CAPTURE_ROTATION=0|90|180|270`이면 그 값으로 고정하고 CoreMotion을 켜지 않는다. 영상-카메라 모드용 — 폰 자체의 중력은
  흉내 낸 영상과 관계가 없다. **`BPT_CAMERA_VIDEO_ROTATE=N`은 `BPT_FORCE_CAPTURE_ROTATION=N`이 정확히 되돌린다**(단위 테스트로 고정, 아래).
- 쓰지 않은 것:
  - `UIDevice.orientation` — 사용자가 제어 센터의 세로 고정을 켜 두면 세로에 머문다. 폰은 방 건너편에 세워져 있다.
  - `AVCaptureDevice.RotationCoordinator` — iOS 17+라 배포 대상(iOS 16)에서는 CoreMotion 경로가 어차피 필요하다. 두 경로가 되고, 영상 모드·pose-replay에도 도움이 안 된다.
  - 캡처 연결 자체를 돌리기(`videoOrientation = .landscapeRight`) — 세션 중에 바꾸면 프레임이 끊기고, 세트 녹화(AVAssetWriter)는 중간에 크기가 바뀌면 깨지며,
    영상 모드는 연결을 거치지 않아 흉내 낼 수 없다.

### 2. 적용 위치 — 프레임의 CGImage 하나
- 회전은 `CameraPosePreview.cgImageFromSampleBuffer`에서 `CIImage.oriented`로 한다. 이 함수는 원래 매 프레임 CIContext로 버퍼 전체를 CGImage로 그린다.
  회전은 그 그리기에 얹히므로 코드상 **CGImage 렌더 호출이 추가되지 않는다**. 실기기 회전 처리 시간은 별도 측정이 필요하다.
- 작업 지시는 “사람 crop affine에서” 돌리기를 권했지만 여기서는 프레임 단계가 더 싸고 깔끔하다. crop affine만 돌리면 같은 영상을 보는 나머지 세 곳 —
  사람을 잃었을 때의 전체 프레임 입력, 1초마다 전체 프레임 재확인, 손목 crop(MediaPipe) — 이 따로 돌려야 하고, 키포인트가 버퍼 좌표로 돌아와
  규칙 앞에서 한 번 더 돌려야 한다. 프레임에서 돌리면 모든 소비자가 같은 분석 프레임 하나를 본다.
- 세로(0)에서는 `analysisImage`가 **같은 CIImage 객체를 그대로** 돌려준다 → 오늘과 같은 그리기, 같은 바이트.

### 3. 좌표가 흐르는 곳 (전부 확인)
| 소비자 | 좌표 | 바뀐 것 |
|---|---|---|
| RTMPoseCropTracker(사람 crop, 잃었을 때 전체 프레임, 1초 재확인) | 분석 프레임 픽셀 | 없음. 회전이 바뀌면 `reset()` |
| RTMPose 디코드(SimCC → crop 역변환) | 분석 프레임 픽셀 | 없음 |
| Halpe26 발(발가락·뒤꿈치) | 분석 프레임 | 없음(halpe-default 브랜치와 충돌 없음 — 아래) |
| 손 분기(손목 crop, MediaPipe) | 분석 프레임 | 없음(같은 CGImage를 자름) |
| 평가기·FormWarningTracker(렙, 자세 규칙, setup_side_view·setup_full_body) | 분석 프레임 | 없음 |
| 3D 입력(coco17ToH36M17 + MotionAGFormerInputNormalizer, lift-app `MotionAGFormerLive.push(imageWidth: cgImage.width …)`) | 분석 프레임 | 없음 — 이미 cgImage 크기를 쓴다 |
| 오버레이(CameraLiveView: 뼈대·손) | 분석 → 버퍼(`bufferPoint`), aspect-fill은 버퍼 크기 | **바뀜**: `CameraFrameData.rotation`으로 그릴 때만 되돌림 |
| 미리보기(AVCaptureVideoPreviewLayer, `.portrait`) | 버퍼 | 없음 |
| Flutter 채널(onPoseUpdate rep/status/done, onFeedback key, onSetEnd) | 좌표 없음 | 없음 |
| 기록: WorkoutFormLog(렙 지표), WorkoutPerfLog(FPS·발열) | 지표만 | 없음(지표 뜻이 이제 중력 기준) |
| 세트 녹화(WorkoutSetRecorder, 기본 끔) | 버퍼 그대로 | 없음 — 가로 세트는 옆으로 누운 영상(E) |
| pose-replay | `--rotate N`(가로 흉내) · `--capture-rotation N`(앱의 되돌림) | 새 옵션, 둘 다 없으면 출력 바이트 그대로 |

- 표시 좌표와 분석 좌표는 `CameraFrameData`/`CameraProcessingResult`의 `rotation` 하나로 나뉜다. 둘 다 키포인트·`imageWidth/imageHeight`는 분석 프레임이고,
  버퍼(= 미리보기)로 가는 것은 오버레이가 그릴 때뿐이다. `rotation`은 기본값 없는 필드라 새로 `CameraFrameData`를 만드는 코드가 빠뜨리면 **컴파일이 안 된다**
  (lift-app의 `showFrame`이 그 경우 — 아래).

## 테스트

2026-10-20 Codex 재개에서 직접 확인했다. 모든 Mac 빌드·재생은 `lockf -k /tmp/bpt-heavy.lock`으로 기존 작업과 직렬 실행했다.

- 본 브랜치 `88c19aa`: `swift test --package-path ios/CalibrationEngineKit` **110/110 통과**, 실패 0.
  `CaptureRotationTests` 6개가 포함된다.
- 픽셀이 서로 다른 BGRA 입력을 실제 영상 모드와 같은 vImage로 90/180/270° 돌린 뒤 분석 회전으로 되돌리면
  크기와 렌더된 픽셀 바이트가 모두 원본과 일치한다.
- 밝은 표식 픽셀을 네 회전에서 분석→버퍼 좌표로 되돌리면 동일 픽셀 중심을 가리킨다.
  세로 회전은 같은 `CIImage` 객체를 반환한다.
- 중력 사분면 선택, 평평하게 놓인 폰의 회전 유지, 45° 경계 ±15° 잡음 300표본의 깜빡임 방지를 검증했다.
  실제 폰 중력 부호·거치 각도와 히스테리시스 사용감은 별도 기기 확인 대상이다.
- 로그: scratch `orient/logs/codex_orientation_tests.log`.

- lift-app 시험 병합본 `a4334aa`: 같은 명령 **132개 실행, 실패 0, 건너뜀 1**.
  건너뛴 것은 기존 `testCoreMLParity`(그 worktree의 `assets/coreml/motionagformer_xs.mlpackage` 부재)다.
  새 시간창 테스트 두 개는 통과했다: 0→90→270→180°, cadence 1/3에서 매 XS 입력창이 한 방향 표본만 포함하며
  160개 payload가 한 번씩 순서대로 나오고 각 방향에서 준비 상태가 다시 시작된다.
  회전 경계 flush의 예측 오류를 주입해도 다음 프레임은 새 창으로 시작한다.
  로그: scratch `orient/logs/codex_trial_tests.log`.

- iOS 실기기 앱: 기기 에이전트가 `a8b29f1`의 Runner Release arm64 서명 빌드 **성공(exit 0)**을 확인했다.
  `CameraPosePreview`를 포함한 native 코드가 컴파일됐다. 폰에서 중력 기반 회전을 관찰한 결과는 아직 없다.

## Mac 재생 — 가로 흉내 전후

**이번 재개에서 실제 클립 재생은 아직 실행하지 않았다.** m Halpe26과 기존 XS로 `pushup_0000_cam2/3` 두 클립을
기준 main 세로 / 회전 브랜치 세로 / lift 시험본 세로·90·270°로 비교하는 스크립트를 준비했다.
첫 실행이 공유 락 대기 중일 때 사용자 P0(원래 Halpe26 39클립 실기기 A/B)를 우선하라는 요청을 받아
그 대기자만 취소했다(22:40, 자식 추론 프로세스 없음, 출력 로그 0바이트). 진행 중인 다른 작업과 기존 출력은 건드리지 않았다.

- 재개 스크립트: scratch `orient/codex_replay.sh`.
- 실제 영상 재생 기반의 세로 렙·경고 패리티 및 90/270° 3D 상태 회복 수치는 **미검증**이다.
- 위 픽셀·좌표 roundtrip 단위 테스트는 완료됐지만 클립 재생이나 실기기 중력 검증을 대체하지 않는다.

## 프론트엔드가 알아야 할 것

- **분석은 화면(UI) 방향과 무관하다.** 회전은 CoreMotion 중력에서 정해서, Flutter의 세로 고정(`main.dart` portraitUp/Down)이나 사용자의 세로 고정
  잠금과 상관없이 폰을 가로로 세우면 분석이 따라간다. 가로 UI를 만들어도 렙·경고·3D 쪽에서 할 일은 없다.
- **Flutter 채널은 그대로다.** onPoseUpdate `{rep, status, done}`, onFeedback `{key, n?, scope}`, onSetEnd — 좌표가 없어서 바뀐 것이 없다. 폰 방향을
  Flutter에 알려 주지는 않는다(필요하면 onPoseUpdate에 `rotation`을 붙이는 것은 한 줄 — F2).
- **UI를 세로 고정으로 두고 위젯만 돌리는 경우**(RotatedBox 등, 기본 카메라 앱 방식): 네이티브 미리보기와 뼈대 오버레이는 이 브랜치 그대로 맞는다.
  미리보기는 폰과 함께 돌기 때문에 가로로 든 폰에서도 세상 기준으로 똑바로 보인다.
- **UI 자체를 가로로 돌리는 경우**(`SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])`): 네이티브 미리보기 연결이 `.portrait`
  고정이라(CameraPreviewUIView) **카메라 화면이 90° 옆으로 누워** 가로로 긴 뷰에 aspect-fill로 잘려 보인다. 오버레이는 그 누운 미리보기 위에 맞게 그려진다
  (둘 다 버퍼를 그림). 고치려면 네이티브 두 곳 — 미리보기 연결 방향을 인터페이스 방향에 맞추고, 오버레이의 버퍼 → 화면 변환에 같은 회전을 넣기 — 을
  바꿔야 하고, 이 브랜치는 **하지 않았다**(UI를 만들지 않으므로, F1).
- 운동 안내 문구: `camera_guide_screen.dart`의 “폰은 세로로, 거치대에 고정해줘”는 푸시업 가로 촬영과 맞지 않는다(문구는 프론트엔드 몫).
- 세트 녹화(`BPT_SET_RECORDING`, 기본 끔)는 버퍼를 그대로 저장한다 → 가로 세트 영상은 옆으로 누워 있다. 결과 화면에서 재생한다면 회전 표시가 필요(E).
- 캘리브레이션(서서 찍는 전신 촬영)은 세로 전용 그대로다 — 이 브랜치는 운동 카메라만 바꿨다.

## lift-app 병합 메모 (기기 에이전트용)

시험 병합: `ai/lift-app-m2b98256` fa3f004 + `88c19aa`. 중단 당시 미해결 인덱스를 정리하고 시간창 분리까지 추가해
스크래치 worktree에 `a4334aa`로 로컬 커밋했다. 같은 변경은 기기 시험 브랜치의 `ebcfb38`에 있다.
원래 `ai/halpe-default-m2b98256`(f715c3b)과 충돌 없음은 기존 `git merge-tree` 확인 기록이다.
1. **충돌 1곳** — `CameraPosePreview.swift`의 `drawSkeleton`. lift-app 쪽 본문(`PoseOverlayRenderer.draw`)을 쓰고, rect 두 줄만 이 브랜치 것으로:
   ```swift
   let buffer = frame.rotation.bufferSize(width: frame.imageWidth, height: frame.imageHeight)
   let rect = aspectFillRect(imageWidth: buffer.width, imageHeight: buffer.height, in: size)
   ```
   `drawHands`는 lift-app 쪽(삭제)을 따른다.
2. **컴파일 오류 1곳** — lift-app의 `showFrame`이 `CameraFrameData`를 `rotation` 없이 만든다 → `rotation: result.rotation,` 한 인자 추가.
  (`processFrame`·`handleProcessingResult`·`cgImageFromSampleBuffer`·pose-replay는 자동 병합됨. 빌드·재생의 실제 검증 결과는 위 테스트 절을 따른다.)
3. **영상 모드 실행**: 가로 실행은 `BPT_CAMERA_VIDEO_ROTATE=N`과 **`BPT_FORCE_CAPTURE_ROTATION=N`**을 같이, 세로 실행은 `BPT_FORCE_CAPTURE_ROTATION=0`.
   고정하지 않으면 폰 자체 중력이 정한다 — 책상에 눕혀 두면 0에 머물지만, 가로 거치대에 세워 두면 세로 클립을 돌려 버린다. (영상 모드가 자동으로
   고정하게 하려면 `CaptureRotation.forced ?? (VideoCameraOptions.isActive ? CaptureRotation(rawValue: VideoCameraOptions.rotate) : nil)` 한 줄 —
   VideoCameraOptions가 lift-app에만 있어 여기서는 안 함.)
4. **기록 좌표**: VideoRunLog의 `kp`·`size`·`hands`는 이제 분석 프레임이다. 흉내 + 고정이면 분석 프레임 = 반전된 원본 클립(1280×720) = 세로 실행과 같은
   좌표라 좌우 비교 스크립트는 그대로 쓸 수 있다. `camera_started`에 회전 값(고정 여부), `judged` 줄에 프레임별 `rotation`을 남기길 권함.
5. **회전이 세트 중에 바뀔 때 — Codex 재개에서 구현**: 시험 병합본의 `MotionAGFormerLive.push`가 `captureRotation`을 받는다.
   이전 방향과 달라지면 `flush()`로 이전 방향의 미판정 꼬리를 먼저 내보내고 정규화 crop·27프레임 창을 초기화한 뒤 새 방향을 쌓는다.
   90→270처럼 가로·세로 크기가 같은 전환도 분리한다. 예측이 실패해도 `defer { reset() }`으로 이전 방향 창을 남기지 않는다.
   그 실패 경로에서는 미판정 꼬리를 폐기하고 기존 카메라 오류 로그를 남긴다(다음 프레임부터 새 창으로 회복).
   카메라는 기존 직렬 lift 큐에서 프레임의 회전을 넘긴다. 오버레이 좌표 필터도 회전 경계에서 초기화한다.
   이 부분은 3D가 없는 본 브랜치가 아니라 시험 lift 통합 패치에 있다.
6. **`BPT_3D_GRAVITY`(기본 끔)**: `FormGeometry.cameraUp`은 중력을 버퍼 좌표로 옮긴다. 가로에서는 그 화면 평면 성분을 분석 프레임으로 한 번 더
   돌려야 한다: cw90 `(x, y) → (y, −x)`, cw180 `(−x, −y)`, cw270 `(−y, x)`, z 그대로. 발견(기하로 따진 것, 기기 검증 안 함): 운동 카메라 버퍼는 전면도
   미리보기처럼 반전돼 있어 버퍼 x = 기기 x인데, `cameraUp`은 전면에서 x를 뒤집는다(`frontCamera ? -g.x : g.x`). 세로에서는 gx ≈ 0이라 차이가 작지만
   가로에서는 위아래가 뒤집힌다 — 중력 모드를 켜기 전에 확인할 것.
7. CoreMotion: 이 브랜치가 회전용 `DeviceMotionMonitor`를 하나 띄운다(`rotationMotion`, 고정 실행에서는 안 띄움). lift-app의 `motion`(BPT_3D_GRAVITY)과
   합칠 수 있지만 시험에는 필요 없다.

## A–G

- **A — 구현**: 중력 기반 분석 회전, preview 좌표 역변환, crop 초기화, 강제 회전과 replay 옵션.
  시험 lift 통합에는 회전 경계의 XS 창·정규화·오버레이 필터 초기화까지 반영했다.
- **B — 검증**: 회전 브랜치 Swift 110/110, lift 시험본 132개 중 1개 건너뜀·실패 0.
  기존 패리티 테스트와 새 이미지·좌표·시간창 경계 테스트가 통과했다.
- **C — 남은 검증**: 세로/90/270 클립 재생, 실제 앞/뒤 카메라와 중력 부호·전환 관찰.
  사용자 우선순위대로 39클립 기기 A/B 이후 진행한다.
- **D — 적용 상태**: 로컬 시험 브랜치에만 적용. main/integration 병합과 제품 기본값 채택은 하지 않았다.
- **E — 한계**: 회전마다 새 27프레임을 모을 때까지 3D 준비 상태. 센서 임계값은 제안값.
  `BPT_3D_GRAVITY`의 전면 부호·분석 프레임 변환은 미해결이어서 해당 옵션은 꺼 둔 시험 기준을 유지한다.
  세트 녹화는 원 버퍼 방향으로 저장한다.
- **F — 프론트엔드**: 위 절의 가로 UI/preview 방향 및 안내 문구 항목을 전달한다. 이번 분석 변경에서 UI는 수정하지 않았다.
- **G — 결정**: 폰/클립 검증 후 integration 도입 판단이 남아 있다. 이 문서는 도입 승인을 요청하거나 대신하지 않는다.
