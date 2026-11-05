# 신체분석 완료 화면 (2026-10-23)

`--dart-define=BPT_MESH_REVEAL=true`이면 기존 결과 화면을 작은 3D 카드와 신체 정보가 있는 **신체분석 완료!** 화면으로 교체한다. 별도 공개 화면이나 추가 로딩 단계는 없다. 기본값은 꺼짐이며, 꺼진 경우 기존 40초 애니메이션·업로드 대기·결과 화면·홈 이동을 유지한다.

## 흐름

1. 사진 4장을 기존 방식으로 업로드한다. 플래그가 켜져 있으면 접수 직후부터 분석 화면 안에서 3초 간격으로 작업을 조회한다. 기존 `관절 키포인트 추출 → 3D 체형 만들기 → 뼈 길이 추출`만 표시한다.
2. `done`의 결과를 보관하고 `modelGlbUrl`을 내려받는다. 기존 다운로드 서비스의 호스트 제한, 인증 헤더 분리, 4MB 제한을 사용한다.
3. `bpt/body_mesh.prepare`가 네이티브 작업 큐에서 GLB를 파싱하고 법선·SceneKit geometry를 준비한다. 준비된 geometry 하나만 메모리에 보관하며 결과 화면에 식별자만 전달한다. 파일로 저장하지 않는다.
4. 기존 40초 애니메이션과 결과 준비가 모두 끝나면 `/onboarding/result`로 이동한다. GLB는 결과 화면에서 다시 내려받거나 파싱하지 않는다. `/onboarding/mesh`는 호환 경로로만 남고 정상 흐름에서 사용하지 않는다.
5. **넘어가기**는 기존 결과 화면의 다음 목적지인 홈으로 바로 이동한다.

작업 실패·조회 3분 초과·주소 누락·다운로드 실패·파싱 실패·iOS 이외 환경에서는 동일한 결과 화면에 중립색 실루엣을 표시한다. 이미 받은 측정값은 유지한다. 네이티브 준비 응답도 10초로 제한하고, 제한 후 늦게 도착한 geometry는 해제한다. 화면 이탈 시 조회/다운로드를 취소하며 아직 소비하지 않은 준비 결과를 정리한다. 업로드 자체는 이전과 같이 계속 진행한다.

## 화면과 수치

- 제목: **신체분석 완료!**
- 카드 높이: 화면의 37%. 몸 색 `#AC88F6`, 가장자리 빛 `#BFED5F`.
- 기본 자세: 경계 상자의 가장 긴 축을 화면 위쪽(+Y)으로 정렬하고 yaw·pitch·roll은 0으로 시작한다. 경계 상자만으로 앞뒤를 판별할 수 없으므로 서버의 Y-up·+Z 정면 규약을 유지한다. 카메라는 높이 0의 +Z 위치에서 정면을 바라본다.
- 등장: 0.6초 동안 투명도와 크기 0.96 → 1.0만 변화.
- 회전: 등장 완료 후 Y축으로만 24초에 한 바퀴 자동 회전, 첫 터치부터 정지. 드래그로 yaw 무제한, pitch ±15°. 손을 떼면 그 자세를 유지하고 더블탭하면 정면 직립으로 초기화한다. 초기화 후 자동 회전은 재개하지 않는다. 확대·이동 없음.
- 아래 정보는 스크롤 가능하며 하단 **넘어가기**는 항상 노출한다.
- `docs/handoff/teammate_calibration.md` §5의 `userHeightCm`, `boneLengthData.unit == cm`의 `segments`만 사용한다. 몸무게는 결과에 유효한 `weightKg`가 있을 때만 표시한다. 현재 서버 계약에는 몸무게가 없어 보통 생략된다. 온보딩 기본값으로 채우지 않는다.
- 어깨 너비: `shoulder_width`. 팔: 각 측의 어깨–팔꿈치 + 팔꿈치–손목. 다리: 각 측의 엉덩이–무릎 + 무릎–발목. 몸통: `pelvis-spine` + `spine-thorax`. 합산에 필요한 구간이 모두 있을 때만 표시하고 좌우를 구분한다. 누락·0 이하·비유한 값은 생략한다.

## 메시가 보이지 않았던 원인 가설과 보강

실제 사용자 메시나 기기 화면으로 원인을 확정하지 않았다. 기존 코드에서 다음 가능성을 확인하고 보강했다.

| 가능성 | 보강 |
| --- | --- |
| Y축·키만 가정한 카메라와 Y축만의 중심 이동으로 다른 축/원점의 모델이 화면 밖에 있을 수 있음 | 전체 경계 상자의 가장 긴 축을 위로 회전, XYZ 중심을 원점으로 이동, 높이를 1로 정규화. 미터·센티미터 및 X/Y/Z-up 대응 |
| 작은 카드나 가로세로 비율 변화에서 몸이 잘리거나 near/far 범위를 벗어날 수 있음 | 실제 SceneKit node bounding box로 회전 전체를 감싸는 구를 구하고, 수직 FOV 35°와 카드 비율 중 좁은 방향을 기준으로 카메라 거리 계산. 여백 12%, near/far 명시 |
| 생성 시 platform view frame이 0이어서 카메라 설정/등장이 레이아웃보다 먼저 실행될 수 있음 | `layoutSubviews`의 너비·높이가 모두 양수일 때 카메라 설정과 최초 등장, 이후 크기 변경에도 재계산. Flutter 측 카드 너비·높이 명시 |
| 면 방향·누락된 법선·조명 때문에 검게 보이거나 면이 사라질 수 있음 | 양면 재질, 누락 법선의 면적 가중 계산, 제공된 법선 정규화, ambient + directional 조명. 긴 뒤집기/빛 띠 제거 |
| 버퍼 뷰 경계 밖 접근 또는 인덱스 변환이 잘못된 geometry를 만들 수 있음 | little-endian을 명시적으로 해석. UNSIGNED_SHORT/UNSIGNED_INT 인덱스를 정수로 유지. accessor/view offset, stride, 타입, count, 각 view 경계, 삼각형/인덱스 범위를 검증 |
| 결과 화면 메인 스레드에서 파싱하여 첫 표시가 늦어질 수 있음 | 분석 대기 중 작업 큐에서 파싱·법선·geometry 준비. scene 연결과 UIKit 설정은 메인 스레드로 제한 |

첫 유효 레이아웃에서 `os_log`의 `bpt.body_mesh / render`에 정점 수, 원본 bbox, 정규화된 표시 좌표계의 카메라 거리, frame 크기를 한 번 남긴다. URL이나 GLB 내용은 기록하지 않는다. 이 파서는 서버 계약의 단일 정적 삼각형 메시용이며 임의의 glTF 장면/스킨을 로드하는 범용 로더는 아니다.

## 파일

| 파일 | 역할 |
| --- | --- |
| `lib/features/onboarding/screens/onboarding_analyzing_screen.dart` | 기존 분석 대기 안에서 조회·다운로드·준비 |
| `lib/features/onboarding/models/body_analysis_result.dart` | 결과/geometry 식별자 전달, 존재하는 측정값만 요약 |
| `lib/features/onboarding/screens/onboarding_mesh_screen.dart` | 작은 메시 카드 + 정보 + 홈 이동 |
| `lib/features/onboarding/widgets/body_mesh_reveal.dart` | 준비/해제 채널, 준비된 뷰 또는 실루엣, 데모 회전 |
| `lib/core/router/app_router.dart` | 플래그에 따른 결과 화면 교체 |
| `ios/Runner/NativePose/BodyMesh/GLBMesh.swift` | 안전한 파싱·법선·축/단위 정규화·카메라 계산 |
| `ios/Runner/NativePose/BodyMesh/BodyMeshPlatformView.swift` | 비동기 geometry 준비, 레이아웃·재질·조명·회전 |

## 데모

결과 화면에서 `await BodyMeshReveal.demoSpin(turns: 1, seconds: 7)`로 한 번 천천히 돌린 뒤 **넘어가기**를 누른다. 데모도 yaw만 회전하며 pitch를 기울이지 않는다. 작은 뷰에서도 기존 `bpt/body_mesh` 채널의 `spin`을 유지한다.

## 검증 (기존 메시 표시 보강)

- Swift `GLBMeshTests` **6개 통과**. 테스트 안에서 상자 GLB를 절차적으로 생성한다. 실제 사용자 메시/외부 바이너리 fixture를 사용하지 않는다. 16/32비트 인덱스, 별도 buffer view, interleaved stride/offset, 제공/누락 법선, Y/Z-up, m/cm, 좁은 카드, 잘못된 범위/잘린 데이터 확인.
- 네이티브 platform view Swift 구문 검사 통과. iOS 타입 검사·실기기 렌더 검증은 완료하지 못했다.
- SDK의 Dart 실행 파일을 직접 호출하고 분석 캐시를 작업 폴더 안으로 지정한 `dart analyze --fatal-infos`는 **문제 없음**. 변경한 Dart 파일 포맷과 `git diff --check`도 통과했다.
- `flutter analyze --no-pub`, `flutter test --no-pub`, `flutter build ios --debug --no-codesign --no-pub --dart-define=BPT_MESH_REVEAL=true`를 실행했으나 모두 Flutter SDK의 작업 폴더 밖 `engine.stamp` 쓰기가 차단되어 코드 검사/빌드 시작 전에 중단됐다. 패키지 설치나 작업 폴더 밖 변경은 하지 않았다.
- 전체 `swift test`는 빌드 후 기존 `CaptureRotationTests.swift:16`의 `CVPixelBufferCreate` 결과가 nil인 상태에서 중단됐다. 이번 메시 테스트는 별도로 실행해 통과했다. 테스트 임시 파일과 모듈 캐시는 작업 폴더 안으로 지정했다.
- Dart 테스트 추가: 측정값 누락·불완전 구간·잘못된 단위, 작은 화면의 실루엣/홈 이동, 네이티브 실패·시간 제한·늦은 결과 해제, 플래그 off의 조회 없음, on의 준비 완료 대기/다운로드 실패/작업 시간 제한.

권한이 허용된 개발 환경에서 위 Flutter 명령과 전체 Swift 테스트를 다시 실행해야 한다. 플래그 on 분기 테스트는 `flutter test --dart-define=BPT_MESH_REVEAL=true test/onboarding_analyzing_test.dart test/onboarding_mesh_test.dart`로 추가 실행한다. 기기에서는 작은 카드 안의 전신 표시, 첫 터치 정지, 회전 범위, 한 번의 bbox 로그, 실패 시 정보와 버튼 유지, 플래그 off의 이전 화면을 확인한다.

## 검증 (직립 기본 자세 보강, 2026-10-23)

- `flutter analyze --no-pub` 통과: **No issues found**.
- Swift `GLBMeshTests` **8개 통과**. 절차적으로 생성한 X/Y/Z-up 상자로 로딩 후 +Y 직립, +Z 정면, pitch 0, 정면 법선·삼각형 방향, 카메라의 +Z·높이 0을 확인한다. 원본 XYZ 읽기 순서와 대칭 경계 상자에서 서버 규약을 유지하는 회귀 검사도 포함한다.
- `swift test --package-path ios/CalibrationEngineKit --filter GLBMeshTests`에 워크트리 내부 빌드·캐시 경로를 지정했지만 `sandbox-exec: sandbox_apply: Operation not permitted`로 manifest 실행이 차단됐다. 대신 같은 소스와 XCTest 파일을 `swiftc`로 직접 컴파일하고 테스트 스위트를 실행했다. 임시 파일·모듈 캐시·실행 파일은 워크트리의 `.build/` 안에만 생성했다.
- 네이티브 Swift 구문 검사와 `git diff --check` 통과. iOS 앱 빌드·실기기 렌더/제스처 검증은 미실시.
- 기기 확인: 첫 등장 정면 직립, 자동·데모 회전 중 기울임 없음, 드래그 pitch ±15° 및 손을 뗀 자세 유지, 더블탭 정면 직립 복귀와 자동 회전 미재개.

## 서버·라이선스

서버 및 결과 계약은 변경하지 않았다. `modelGlbUrl`은 기존 분석에서 생성한 GLB의 만료되는 주소다. SMPL 파생물의 기존 라이선스 조건은 `docs/decisions.md` 체형 모델 항목을 따른다. 모델 파일은 저장소·앱에 추가하지 않는다.
