# 관측 근거 코칭 후보 — iOS 전체 빌드 검증, 2026-10-30

**후보 소스 `673490212caf28df2b1927d5d61ed62e007535c9`의 iOS arm64 Release 컴파일·링크가 통과했다.** 실제 Runner Swift 컴파일에 `FormWarnings.swift`와 `WorkoutSessionBridge.swift`가 포함됐으며 Dart AOT도 생성됐다. Swift 75개·Dart 25개 단위 테스트와 전체 `lib/test` 정적 분석은 [구현 보고서](workout_evidence_semantics_20261030.md)에 기록했다. 앱 설치·실행과 배포 API 호환성은 이번 빌드의 검증 범위가 아니다.

## 재현 조건과 산출물

구현 브랜치는 `fix/coaching-observation-scope-20261030`, 빌드 전용 브랜치는 `build/coaching-review-20261030`이다. 구현 소스를 그대로 고정하고 별도 worktree에서 빌드했다. 최종 검토 브랜치에는 이 보고서만 모았으며 다른 기반의 native 코드를 무리하게 합치지 않았다.

- Xcode 27.1 / iOS SDK 27.1 / Flutter 3.41.4.
- `xcodebuild -jobs 2 -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -destination generic/platform=iOS`.
- 새 DerivedData, 자동 Swift package resolution/update 금지, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`.
- 기존 로컬 의존성으로 offline pub resolution과 CocoaPods deployment/no-repo-update 준비. 모델·음성의 새 다운로드 없음.
- `lib/main.dart`, 기존 `com.bpt.bpt` bundle ID 유지. Flutter SDK 정의 외 BPT 환경 정의를 추가하지 않았다.
- 빌드 중 소스 입력 181개 해시 불변, pubspec.lock 불변. 추적 파일 차이는 사전에 확인한 생성 Podfile.lock뿐이며 앱 소스/프로젝트 기본 설정 수정 없음.
- 실제 빌드 453.46초. 개발 빌드 소요시간이며 서버 처리시간 또는 iPhone 실행 비용 측정이 아니다.

전체 증거는 로컬 `~/Documents/bpt-handoff/coaching-review-build-20261030/`에 있다. `evidence-final.json`, `build-summary.json`, `xcodebuild-final.log`, `final-build-command.json`, `compiled-source-inputs.json`, `app-file-manifest.json`을 보존했다. 산출물은 그 디렉터리의 `dd/Build/Products/Release-iphoneos/Runner.app`이며 **서명하지 않은 검증용 앱**이다.

| 산출물 | SHA256 |
|---|---|
| native Runner | `1f49789105617d401f6e2f85b81af040c4992b9f3ea2d94dc3cb4cb98377daab` |
| Dart AOT App | `c5f8955e828c8c2471e166d4043f6d12604942b7a5e04f78c27dbac0af416618` |
| 앱 전체 파일 목록 기반 tree hash | `34349c6c45f9db0c1d90de47798bd7b95dd86a52970ba343436499600a997b83` |

앱은 221개 파일이며 tree hash는 정렬한 상대 경로→파일 SHA256 맵을 compact JSON으로 직렬화한 값의 SHA256이다. root 검토에서도 실제 Runner와 AOT 파일을 다시 해시해 기록과 일치함을 확인했다.

## 모델과 기존 결과 보존

원본 XS를 포함한 5개 모델의 소스 패키지 16파일이 wrist-guard 기준과 동일하다. 생성된 각 `.mlmodelc`의 `weights/weight.bin`과 `model.mil`도 기준과 정확히 일치한다. 따라서 모델 가중치나 연산 정의를 교체한 빌드가 아니다.

컴파일된 컨테이너 전체가 바이트 단위로 같은 것은 아니다. 4개 `metadata.json`은 바이트 해시가 다르지만 파싱한 JSON은 동일하고, 5개 `coremldata.bin`은 바이트 해시가 다르다. 차이를 전부 증거 JSON에 기록했다. 이를 근거 없이 무시하거나 이전 앱과 수치적·런타임 동등성이 입증됐다고 하지 않는다.

기존 보존 앱 9개의 총 2,200파일은 빌드 전후 해시가 모두 같다. 모델·기존 측정 로그·완료 앱을 덮어쓰지 않았다. 중복 무거운 작업을 막는 lock은 종료 후 해제됐고 다시 획득 가능한 상태를 확인했다.

## 남은 검증

현재 폰은 마지막 확인에서 `passcodeRequired=true`였으며 기존 motion18은 16/18 원본 로그 검증 상태다. 이 빌드 때문에 폰을 설치·실행·리셋하지 않았다. 나머지 원본 측정을 마치기 전 다른 앱을 덮어 설치하지 않는다.

실제 표시·음성, 데이터 저장과 배포 API의 unknown 계약, 기존 deep local/report 하니스, 일반 사용자/독립 전문가 기준의 자세 정확도는 남아 있다. 컴파일 통과는 그 검증을 대신하지 않는다. 신규 학습·모델 채택·실험 기본 활성화·main/integration 병합·배포는 수행하지 않았다.
