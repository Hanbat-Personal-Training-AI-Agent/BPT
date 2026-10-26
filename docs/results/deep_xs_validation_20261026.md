# XS 보존 심층분석 검증 브랜치 — 2026-10-26

## A. 범위

`ai/deep-xs-validation-20261026`은 trial `74768a9` 기반 review 브랜치다. `24ebee0`의 심층분석 앱 기능과 `6c4e21a` 계정/인증/정리 수정, `67553b1` 관절별 판정 보류 표시와 `be96543` 관측/기준 부족 구분를 선택 이식했다. integration/main을 병합하지 않았다. 서버는 별도 검증/배포된 기존 API를 사용한다.

## B. 보존한 동작

XS lifter/비동기 큐, lookahead tail flush, 기존 모델·기본 옵션, VideoCameraSource, 체형·운동 개인화, 셋업 UI를 보존한다. 카메라 전체 파일을 2D 기반 deep 브랜치로 바꾸지 않았다. 네이티브 변경은 세트 recorder의 PTS/60초 경계, 실제 반복 manifest, `finishEndSet` 뒤 전송에 한정한다. `BPT_SET_RECORDING` 기본은 OFF다.

## C. 서로 분리한 두 증거

- `integration_test/deep_local_capture_test.dart`: 기존 기억된 로그인 복원 → 실제 클립/XS/네이티브 반복 → 세트 녹화 → video_ms manifest와 720p/60초 경계 확인. **모든 deep API 메서드를 차단하고 대기열 저장/복원을 메모리로 제한**한다. 결과 버튼을 누르지 않아 계정에 운동 기록도 저장하지 않는다. 기본 목표는 실제 3회이며 `DEEP_LOCAL_TARGET_REPS`로 조정한다. 클립의 전체 10회를 검증했다고 표현하지 않는다.
- `integration_test/deep_existing_report_test.dart`: 별도로 동의된 IMG9900 완료 job을 실제 기존 인증으로 GET → 서명 영상 재생 → 실제 플레이어 중간 지점 seek → provider identity 변경 시 화면/플레이어 폐기를 확인한다. 신원 변경은 **provider 경계 모사**이며 저장 로그인은 지우지 않는다. 실사용 로그아웃·다른 실제 계정 로그인으로 표현하지 않는다. 업로드 API는 호출하지 않는다.

두 테스트를 하나의 실제 운동 업로드 E2E 성공으로 합치지 않는다. IMG9900 작업의 합성 구간은 transport/report 검증용이며 운동 정확도 근거가 아니다. 다른 사람이 포함될 수 있는 P2 영상은 Modal/R2에 보내지 않는다.

두 하니스는 `app.main()`과 기존 DemoAutopilot을 호출하지 않는다. 따라서 기존 trial의 신규 회원가입·약관 동의·`prefs.clear()`가 실행되지 않는다. 실제 저장 계정과 `autoLogin=true`가 없으면 실패하며 우회하지 않는다. 리포트 job과 저장 계정의 소유자가 다르면 404가 정상이다.

## D. 기기 담당 준비

기기는 전담 agent만 제어한다. 소스·로그·기존 앱 데이터를 보존하고 빌드 산출물은 기존 캐시/APFS clone을 활용한다. 폰 측정과 새 앱 빌드를 겹치지 않는다.

로컬 입력의 `Documents/bpt_demo.json`에는 검증할 단일 720p 클립 경로와 `BPT_CAMERA_VIDEO_LOOPS=1`을 둔다. 반전/회전은 기존 클립 계약에 맞춘다. 하니스는 파일 존재만 확인하며 영상 정답이나 반복 수를 주입하지 않는다. 영상 끝은 setEnd가 아니므로 실제 목표 반복에 도달하지 않으면 실패한다. 재생 루프·여러 클립은 PTS가 다시 시작할 수 있어 금지한다.

녹화 플래그는 **프로세스 시작 env `BPT_SET_RECORDING=1`**로만 시험 때 켠다. bpt_demo.json에 이 키만 쓰는 것으로 켜지지 않는다. 영구 UserDefaults를 바꾸지 않는다. 기존 workout_videos에 MP4가 20개 이상이면 하니스는 시작 전에 실패한다. 실제 recorder의 보존 개수 정리가 기존 영상을 삭제하지 못하게 하기 위한 검사다. `BPT_AUTOSTART_WORKOUT`은 로그인 우회이므로 사용하지 않는다.

기기 전담자가 사용할 빌드 target:

```text
integration_test/deep_local_capture_test.dart
integration_test/deep_existing_report_test.dart
```

로컬 target에는 `DEEP_LOCAL_TARGET_REPS`(기본 3)만 선택한다. 리포트 target에는 기존 공개 `CALIBRATION_API_BASE_URL`, `CALIBRATION_STORAGE_HOSTS`, 동의된 `DEEP_REPORT_JOB_ID`를 전달한다. 암호·토큰을 Dart define/저장소/로그에 넣지 않는다. job ID는 private `/Users/6_month/bpt-data/deep_test/authenticated_20261026/run20/evidence.json`의 `job_id`를 기기 담당자가 읽는다. root가 제공한 완료 작업은 기존 final1602 계정 소유다.

## E. 자동 검증 결과

- 기존 캐시를 사용한 `flutter pub get --offline` 성공. 의존성 lock 변경 없음, 네트워크 다운로드 없음.
- trial 소스 전체 `flutter analyze --no-pub`: 문제 0.
- 7개 표적 테스트 파일 **32개 모두 통과**. trial에는 기존 XS pose3d 채널 테스트가 1개 더 있다.
- 변경 Swift 3파일의 `swiftc -frontend -parse` 성공. 타입 검사·링크·iOS 빌드 검증을 대신하지 않는다.
- 이후 기준 반복 수만 부족한 경우를 다룬 UI 회귀를 원 앱 브랜치에서 추가해 deep11 통과/analyze0을 확인하고 동일 패치를 이식했다. 최종 trial analyze도 문제 0(17:54:39–17:54:43 KST).
- 하니스 2개는 analyze를 통과했지만 **실기기 실행 전**이다.

로그는 `/tmp/bpt-deep-xs-offline-pub-20261026.log`, `/tmp/bpt-deep-xs-analyze-20261026.log`, `/tmp/bpt-deep-xs-swift-parse-20261026.log`, `/tmp/bpt-deep-xs-test-20261026.log`에 보존한다.

## F. 실행 산출물

실기기 성공 시 앱 Documents/deep_validation에 local_capture.json 또는 existing_report.json을 쓴다. 서명 URL/인증 토큰을 기록하지 않는다. local_capture에는 실제 녹화 경로·크기·길이·manifest와 uploaded=false/queuePersisted=false가 들어간다. report에는 duration/seek 시각과 provider 경계 모사 여부를 기록한다. 파일이 없는 실행을 성공으로 추정하지 않는다.

## G. 남은 기기 확인

실제 앱 빌드/설치, 30·60초 세로/가로 녹화, 사진 저장·공유, 실제 OS 복귀/장기 URL 갱신은 기기 담당의 별도 실행 증거가 필요하다. 현재 하니스는 원본 운동 영상의 업로드를 의도적으로 차단하므로 서버 업로드까지 연결한 운동 E2E 검증으로 사용하지 않는다. 기존 인증 API smoke 결과는 root의 별도 증거를 따른다.
