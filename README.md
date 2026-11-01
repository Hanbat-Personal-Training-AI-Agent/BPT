# BPT — On-Device AI Personal Trainer

iPhone의 RTMPose와 MotionAGFormer-XS 3D 관절 추정으로 운동 단계·반복·자세 근거를 분석하고, 개인 체형 참고치와 운동 후 심층 리포트를 연결하는 프로젝트입니다.

현재 브랜치 **review/project-completion-20261102**는 검토 후보입니다. main/integration 병합·배포 버전이 아닙니다. 구현 완료와 자세 정확도 검증을 구분한 [최신 상태·시험 결과·남은 조건](docs/results/project_completion_20261102.md)을 기준으로 확인하세요. 이전 소개·팀 역할·일정은 [과거 README](docs/project/readme_20261008_archive.md)에 보존했습니다.

## 현재 구조

```text
카메라 → 사람 검출·추적/crop → RTMPose-m Halpe26
       → 관절·confidence → MotionAGFormer-XS (27프레임)
       → 시점이 맞는 2D/원본 3D·유효성 → 운동별 평가 → 화면·음성 피드백
                                                  → 실제 수행 기록

체형 촬영 4장 → 계정에 귀속된 업로드/분석 → SMPL·뼈 길이 참고치
운동 영상·반복 구간 → 서버 심층분석 → 항목별 수치·판정 보류·근거 영상
```

운동 기본 2D 모델은 m Halpe26, 체형 촬영은 s COCO17입니다. 이는 기존 설정이며 이번 작업에서 교체하지 않았습니다. XS의 원본 출력과 보정·유효성 정보를 구분하고, 관측하지 못한 관절을 임의로 정상 판정하지 않습니다. 기본 3D lookahead는5프레임으로, 예를 들어30fps에서 약167ms의 시점 지연이 있으며 모델 계산 시간과 별개입니다.

native 운동 경로는 스쿼트·푸시업·바벨로우·데드리프트·벤치프레스5종입니다. 랫풀다운과 Android 실시간 추론은 완료 기능이 아닙니다. RTMPose 점수는 관절 검출 근거이며 3D 자세가 맞을 확률은 아닙니다. 반복 완료율·경고 이벤트 수·검증된 자세 정확도는 서로 다릅니다.

앱은 Flutter/Riverpod/go_router, iOS 추론은 Swift/CoreML, 인증·운동 기록은 Spring Boot/JWT/PostgreSQL 경로를 사용합니다. 체형 fitting·심층분석 Python 서버는 `server/calibration_modal`에 있습니다. Firebase 패키지가 남아 있다는 사실을 현재 인증 계약으로 해석하지 않습니다.

## 검증 상태

- 전체 Flutter·Swift·서버 검사 및 실제 localhost HTTP/PostgreSQL 저장/재조회 근거: [검토 보고서](docs/results/project_completion_20261102.md).
- 개인 체형의 계정 경계·촬영부터 결과까지의 소유권: [캘리브레이션](docs/results/calibration_owner_20261102.md).
- 기록의 실제 수행량·미확인 자세 의미: [기록 계약](docs/results/workout_evidence_roundtrip_20261102.md).
- 일부 관절만 실패한 심층 리포트: [부분 유효성](docs/results/deep_partial_validity_20261102.md).
- 기존 A–H 학습 없는 예측/접촉 실험과12개 요구 질문: [정량 결과](docs/results/motion_contact_status_20261102.md).
- 전문가 라벨·보류율·누락 평가: [평가 프로토콜](docs/evaluation/independent_form_protocol_v1.md), [실제 미확인 작업팩](docs/evaluation/expert_form_kit_receipt_20261102.md).

로우·푸시업의 각도/구간 실패와 독립 전문가 평가 부족이 남아 있습니다. 평균 오차나 jitter 감소만으로 정확한 PT 코칭이라고 선언하지 않습니다. 실제 요추 굽힘은 현재 관절 표현만으로 확정하지 않습니다. 검증되지 않은 contact/관절 제약은 기본 활성화하지 않았습니다.

## 작업과 실행

저장소 루트가 Flutter 프로젝트입니다. Dart SDK 범위는 `pubspec.yaml`, 모델·iOS 설정은 `ios/`, backend 설정은 `backend/`를 따릅니다. 현재 iPhone 빌드는 macOS/Xcode/CocoaPods와 해당 기기의 개발 서명이 필요합니다.

```sh
flutter pub get
flutter test --no-pub
flutter analyze --no-pub lib test
swift test --package-path ios/CalibrationEngineKit --jobs 2
python3 -m unittest discover -s test/python -p 'test_independent_form_eval.py'
```

Python 서버 검사에는 서버 의존성이 설치된 환경이 필요합니다. 이 Mac에서 확인한 환경은 `/opt/homebrew/Caskroom/miniconda/base/envs/bpt-eval/bin/python`입니다. 실제 모델·라이선스 자산이 필요한 시험은 자산이 없는 환경에서 건너뜁니다. 전체 backend 검사는 JDK17과 저장소의 Gradle wrapper를 사용합니다. 실제 DB 시험은 [별도 localhost guard](docs/results/workout_http_postgres_contract_20261102.md)를 충족할 때만 실행하며 사용자 DB를 대상으로 실행하지 않습니다.

앱 API는 `--dart-define=API_BASE_URL=...`, 체형/심층 서버는 `CALIBRATION_API_BASE_URL`과 `CALIBRATION_STORAGE_HOSTS`를 사용합니다. 실제 환경 값·서명·서버 비밀키는 운영 환경에서 관리합니다. 현재 API 기본 HTTP와 iOS 전송 정책은 배포 전 확인 대상이며 임의로 변경하지 않았습니다. API 계약은 [서버 문서](server/calibration_modal/README.md)와 [체형 업로드 계약](docs/research/calibration_serverless_upload.md)을 참고하되 과거 화면 설명과 최신 구현 차이는 검토 보고서를 우선합니다.

`BPT_EXERCISE_SETUP`, `BPT_MESH_REVEAL`, `BPT_WRIST_ANCHOR` 등 시험 플래그는 검증 목적과 기본값을 구분해야 합니다. 이번 검토가 새 학습·모델 채택·기본값 변경·병합·배포를 승인하지는 않습니다.

## 주요 위치

| 경로 | 내용 |
| --- | --- |
| `lib/` · `test/` | Flutter 앱·계약/화면 검사 |
| `ios/Runner/NativePose/` | 카메라·2D/3D 추론·운동별 평가·음성 |
| `ios/CalibrationEngineKit/` | Swift 검사·재생 도구 |
| `backend/` | 인증·기록·집계 Spring 서버 |
| `server/calibration_modal/` | 체형 fitting·심층분석 서버 |
| `scripts/deep_analysis/` · `scripts/form_eval/` | 수치 재현·독립 자세 평가 도구 |
| `docs/results/` · `docs/evaluation/` | 검증 결과·한계·평가 절차 |
