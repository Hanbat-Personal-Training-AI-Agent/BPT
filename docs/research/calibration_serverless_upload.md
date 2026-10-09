# 캘리브레이션 서버리스 업로드 연동

이 문서는 BPT 앱 개발자와 서버리스 API 구현 담당자를 위한 연결 계약이다. 앱은 네이티브 캘리브레이션에서 저장한 사진 4장과 메타데이터를 검증하고, 사용자 동의 후 임시 URL로 저장소에 전송한 다음 서버 접수를 확인한다. **앱의 전송 경로와 Modal 서버 코드(`server/calibration_modal/`, 1단계: 업로드·검증·접수·작업 조회와 고정 결과 스텁)는 구현했지만 배포, 실서버 연결, 실제 체형 fitting, 앱의 결과 수신은 아직 하지 않았다.** 이 문서의 URL은 예시이며 운영 서버가 아니다.

## 구현 범위

- `lib/features/onboarding/services/calibration_upload_service.dart`: 설정, 파일 검증, URL 발급 요청, 파일 스트리밍 PUT, 완료 접수, 로컬 접수 기록.
- `lib/features/onboarding/screens/onboarding_analyzing_screen.dart`: 전송 동의, 실제 바이트 진행률, 중단과 수동 재시도, 서버 미설정 안내.
- `ios/Runner/NativePose/Calibration/CalibrationStore.swift`: 사진 및 manifest 생산자. 후속 안정성 작업에서 JPEG·manifest 저장 성공 뒤 촬영 확정, 사진별 snapshot 메타데이터 저장을 적용했다.
- `test/calibration_upload_test.dart`, `test/onboarding_analyzing_test.dart`: 전송 계약 및 화면 상태 테스트.

추가 Flutter 패키지는 없다. 이미 사용 중인 Dio와 Riverpod를 이용한다. 현재 앱 인증은 `AuthService`와 `ApiClient.authToken`의 로그인 토큰이다. Firebase 패키지가 설치되어 있다는 이유로 Firebase ID 토큰이라고 가정하지 않는다. 서버리스 API는 이 토큰을 검증할 수 있어야 하며, 다른 인증을 선택하면 주입 가능한 `tokenProvider`를 교체해야 한다. 앱에 저장소 관리자 키나 클라우드 비밀키를 넣지 않는다.

## 앱 실행 설정

저장소 루트에서 실제 배포 주소와 정확한 저장소 호스트를 지정한다.

```sh
flutter run \
  --dart-define=CALIBRATION_API_BASE_URL=https://calibration.example.com/v1 \
  --dart-define=CALIBRATION_STORAGE_HOSTS=private-photos.example.com
```

`CALIBRATION_API_BASE_URL`은 기본값이 없다. 기존 Spring API 주소로 자동 전송하지 않는다. API는 HTTPS와 쿼리·fragment 없는 주소만 허용한다. `CALIBRATION_STORAGE_HOSTS`는 쉼표로 구분한 정확한 호스트 이름이며 wildcard를 허용하지 않는다. 파일 URL은 HTTPS, 포트 443, 사용자 정보 없는 URL만 허용한다. API 및 저장소의 리다이렉트는 따라가지 않는다. 두 설정 중 하나라도 없으면 UI에서 전송 버튼을 비활성화한다.

사진 4장을 촬영하면 전송 대기 화면으로 이동한다. 사용자가 `동의하고 사진 4장 전송`을 눌러야 네트워크 요청을 시작한다. 앱은 전송과 서버 접수만 확인하며 3D 분석이 끝났다고 표시하지 않는다. 서버 미연결 때도 `체형 분석 없이 홈으로 가기`로 다른 기능을 사용할 수 있으며 분석 결과를 생성하지 않는다. 디버그 빌드의 데모 결과 버튼은 실제 분석 결과가 아님을 명시한다.

## 전송 대상

세션 폴더는 기존 네이티브 코드가 생성하는 `Documents/calibration/<sessionId>`다. 아래 다섯 파일만 전송하고 로그, 임시 파일, 접수 기록은 보내지 않는다.

| 파일 | Content-Type | 앱 검증 상한 |
| --- | --- | --- |
| manifest.json | application/json | 1 MiB |
| view_front.jpg | image/jpeg | 25 MiB |
| view_rightfront.jpg | image/jpeg | 25 MiB |
| view_back.jpg | image/jpeg | 25 MiB |
| view_leftfront.jpg | image/jpeg | 25 MiB |

상한은 이번 클라이언트 구현에서 정한 보호 한도이며, 클라우드 서비스의 한도나 실제 촬영 크기가 아니다. 네 파일의 중복 없는 label, 고정 파일명, 17×3 유한수 키포인트, 양수 이미지 크기·사용자 키, schemaVersion 1, `coco17_pixel_unmirrored` 형식을 검증한다. 파일 누락, 빈 파일, 파일 symlink, manifest 내 경로 삽입은 전송 전에 거절한다. 서버도 독립적으로 검증해야 한다. JPEG 디코딩과 실제 사진 내용 검증은 현재 클라이언트에서 하지 않는다.

manifest 원문을 수정하거나 keypoint 좌표를 재정규화하지 않는다. 주요 값은 사진의 원본 픽셀 좌표, confidence, 키, intrinsics와 그 출처, 중력, 시간, `nominalYawDeg`다. `rightfront`는 사용자가 왼쪽으로 돌아 카메라에 오른쪽 앞면이 보이는 +60° 라벨이다. `leftfront`는 −60°, `back`은 180°, `front`는 0°다. 각도는 목표 라벨이지 정밀 측정한 실제 회전각이 아니다.

후속 네이티브 변경은 schemaVersion 1을 유지하면서 `isComplete`, `perViewCameraMetadata`, `views[].imageWidth/imageHeight/intrinsics/deviceTimestamp/deviceMotionAvailable`을 추가했다. 새 서버는 사진별 camera 값을 우선 사용하고, 해당 필드가 없는 이전 manifest만 top-level 값으로 처리해야 한다. 기기에서 카메라 intrinsics와 화각을 모두 얻지 못하면 앱은 `fx = fy = 0`, 중심점, `source: "fov_estimate"`를 기록한다. 서버는 이 조합을 초점거리 미상으로 받아들이고 fitting에서 추정한다. 그 밖의 0 이하 초점거리는 거절한다. 새 manifest의 top-level camera 정보는 **정면 사진의 호환용 값**이다. IMU는 사진 도착 시점에 읽은 최신 표본으로, camera PTS와 동기화된 동일 timestamp가 아니다.

manifest는 각 사진 저장 뒤 갱신하므로 1~3장의 부분 manifest도 존재한다(`isComplete: false`). 앱 업로더는 네 view가 모두 있어야 전송하므로 부분 세션은 거절한다. 서버도 네 view와 파일 존재를 검증하고 명시적인 `isComplete: false`를 거절해야 한다. 필드가 없던 이전 완성 세션과의 호환성은 유지한다. 저장 실패 시 미확정 JPEG가 남을 수 있지만 성공 manifest에는 포함되지 않는다. 상세 구현·테스트 범위는 [안정성 개선 현황](calibration_realtime_ai_review.md)에 기록했다.

## 전송 순서

1. 앱이 파일 전체를 검증하고 로그인 토큰을 확인한다.
2. 서버리스 API가 인증 및 소유권을 확인하고 파일별 임시 PUT URL을 발급한다.
3. 앱이 저장소에 다섯 파일을 순서대로 스트리밍 전송한다. 원본 전체를 메모리에 한꺼번에 올리거나 base64로 포장하지 않는다.
4. 앱이 완료 API를 호출한다. 서버가 실제 파일을 검증하고 분석 작업 접수를 기록한다.
5. 서버의 `accepted`와 `jobId`를 받은 뒤에만 접수 완료를 표시한다.

파일 데이터를 함수의 JSON 요청 본문에 넣지 않는 설계다. 저장소 임시 URL로 특정 객체의 업로드 권한을 제한할 수 있으며, URL 자체도 자격증명처럼 보호해야 한다. 이는 서비스 선정이 아니라 공통 설계의 근거다. [S3 임시 URL 공식 문서](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)

## URL 발급 API

`POST {CALIBRATION_API_BASE_URL}/calibrations/uploads`

헤더:

```text
Authorization: Bearer <현재 로그인 토큰>
Idempotency-Key: <manifest.sessionId>
Content-Type: application/json
```

요청 예시의 크기는 설명용이다. 실제 요청에는 각 파일의 바이트 수를 넣는다.

```json
{
  "schemaVersion": 1,
  "clientSessionId": "capture-session-1",
  "files": [
    {"name": "manifest.json", "sizeBytes": 12345, "contentType": "application/json"},
    {"name": "view_front.jpg", "sizeBytes": 1200000, "contentType": "image/jpeg"},
    {"name": "view_rightfront.jpg", "sizeBytes": 1200000, "contentType": "image/jpeg"},
    {"name": "view_back.jpg", "sizeBytes": 1200000, "contentType": "image/jpeg"},
    {"name": "view_leftfront.jpg", "sizeBytes": 1200000, "contentType": "image/jpeg"}
  ]
}
```

응답은 200 또는 201과 아래 JSON이다. `files`에는 반드시 다섯 파일 각각의 URL을 넣는다. 순서는 자유다.

```json
{
  "status": "upload_required",
  "uploadId": "upload-1",
  "files": [
    {"name": "manifest.json", "method": "PUT", "url": "https://private-photos.example.com/manifest.json?signature=example"},
    {"name": "view_front.jpg", "method": "PUT", "url": "https://private-photos.example.com/view_front.jpg?signature=example"},
    {"name": "view_rightfront.jpg", "method": "PUT", "url": "https://private-photos.example.com/view_rightfront.jpg?signature=example"},
    {"name": "view_back.jpg", "method": "PUT", "url": "https://private-photos.example.com/view_back.jpg?signature=example"},
    {"name": "view_leftfront.jpg", "method": "PUT", "url": "https://private-photos.example.com/view_leftfront.jpg?signature=example"}
  ]
}
```

실제 객체 경로는 서버가 인증된 사용자·세션별로 격리해 발급한다. 위의 평면 경로를 여러 사용자가 공유하지 않는다. `uploadId`, `jobId`, `clientSessionId`는 영문·숫자·`_`·`-`로 된 1~128자 식별자다.

이전 시도에서 이미 완료 접수가 확정된 동일 사용자·세션이면 200으로 다음을 반환한다. 앱은 사진을 다시 올리지 않고 접수 기록을 복구한다. 로컬 receipt만 믿고 서버 접수를 생략하지 않는다.

```json
{"status": "accepted", "jobId": "job-1"}
```

## 저장소 PUT 계약

앱은 발급된 URL을 그대로 사용하며 `Content-Type`과 `Content-Length`를 지정하고 원본 바이트를 전송한다. 응답은 성공을 의미하는 2xx여야 한다. 앱 로그인 토큰, 쿠키, 기존 API 로거를 이 저장소 요청에 붙이지 않는다. 임의 추가 헤더나 multipart POST가 필수인 저장소는 현재 계약과 바로 호환되지 않으므로 서버 어댑터 또는 계약 확장이 필요하다.

서버는 PUT, 객체 키, content type, 유효 기간과 가능한 범위의 크기 제한을 포함해 URL을 발급해야 한다. 서버리스 공급자에서 제공하는 SDK를 쓰며 서명을 직접 구현하지 않는다. UI는 실제 전송 바이트 기준 퍼센트를 표시한다. 100% 전송과 서버의 완료 접수는 별개다.

## 완료 API

`POST {CALIBRATION_API_BASE_URL}/calibrations/uploads/{uploadId}/complete`

인증 및 멱등성 헤더는 URL 발급 API와 동일하다.

```json
{"clientSessionId": "capture-session-1"}
```

서버가 검증과 접수를 끝낸 경우 200 또는 202:

```json
{"status": "accepted", "jobId": "job-1"}
```

이 응답은 **분석 작업 접수 완료**를 의미하며 SMPL 최적화나 체형 측정의 완료를 의미하지 않는다. 서버는 파일 존재·크기·MIME·JPEG 디코딩·manifest schema·사용자 소유권을 확인해야 한다. 중복 요청이 동일 작업을 여러 번 생성하지 않도록 사용자 ID와 session ID 기준의 원자적 상태 전이 및 작업 등록을 구현한다. 파일이 불완전하면 성공을 반환하지 않는다. 업로드 전용 함수의 응답 안에서 무거운 체형 fitting을 동기로 수행하는 구조는 이 계약에 포함하지 않는다.

### 거절 응답

검증에 실패하면 성공 상태를 반환하지 않고 아래 형식의 4xx를 반환한다. `detail`은 문제가 된 파일 이름이나 manifest 필드이며 없을 수 있다. 앱은 현재 401만 구분하고 나머지는 재시도 안내로 표시한다.

```json
{"error": "file_missing", "detail": "view_back.jpg"}
```

| 상태 | `error` | 의미 |
| --- | --- | --- |
| 400 | `invalid_idempotency_key`, `session_mismatch`, `unsupported_schema`, `invalid_files`, `invalid_content_type`, `invalid_file_size`, `invalid_upload_id`, `invalid_job_id` | 요청 헤더·본문 오류 |
| 401 | `unauthorized` | 토큰 없음, 서명·만료 오류 |
| 404 | `upload_not_found`, `job_not_found` | 없거나 다른 사용자의 업로드·작업 |
| 422 | `file_missing`, `invalid_file_size`, `invalid_content_type`, `invalid_manifest`, `invalid_jpeg` | 저장소에 올라온 파일 검증 실패 |

## 작업 상태 API

`GET {CALIBRATION_API_BASE_URL}/calibrations/jobs/{jobId}`

헤더는 `Authorization: Bearer <로그인 토큰>`만 보낸다. 작업을 만든 사용자만 조회할 수 있고, 다른 사용자의 작업은 없는 작업과 같은 404다.

```json
{"status": "queued"}
{"status": "running"}
{"status": "done", "result": {"...": "체형 fitting 결과"}}
{"status": "failed", "error": "person_not_found"}
```

`accepted`(완료 API)는 접수만 뜻하고, 체형 결과는 이 API가 `done`을 반환할 때만 있다. 실패 코드는 `person_not_found`, `low_keypoint_confidence`, `fit_diverged`, `internal_error` 등이다. 1단계 서버의 `result`는 입력 검증 뒤 반환하는 고정 값(`"stub": true`)이며 실제 체형 측정이 아니다. 앱의 결과 polling은 아직 구현하지 않았다.

## 실패와 재시도

API 연결 제한 시간은 10초, API 송수신 제한은 각각 30초다. 저장소 연결은 10초, 송신은 2분, 수신은 30초다. 이 값은 앱 설정이며 전체 분석 시간 예측이 아니다.

실패하면 사진을 지우지 않고 같은 화면에서 수동 재시도를 제공한다. 새로운 URL을 발급받아 미접수 세션의 다섯 파일을 다시 전송한다. 파일 중간 바이트부터 이어받는 multipart resume는 아니다. 같은 session ID를 멱등성 키로 보내므로 백엔드가 계약을 지키면 중복 분석을 방지할 수 있다. 401은 재로그인 안내, 그 외 네트워크·저장소 오류는 재시도 안내로 표시하며 URL이나 토큰을 오류 화면에 노출하지 않는다.

완료 응답을 받은 후 세션 폴더에 `upload_receipt.json`을 원자적 rename으로 기록한다. `jobId`, session ID, API 주소, 접수 시각만 저장한다. receipt 저장 실패 시 재시도하면 서버의 기존 접수를 확인할 수 있다. 사진과 manifest는 그대로 유지한다.

화면을 떠나면 진행 중 요청을 취소한다. 취소 이전에 서버에 전달된 파일까지 지워지는 것은 아니다. 고아 업로드는 서버의 만료 정책으로 정리해야 한다. iOS background URLSession, 앱 강제 종료 뒤 자동 재개, 미전송 세션 목록 UI, 로그인 갱신과 자동 재시도는 이번 구현 범위가 아니다. 동일 세션 경로로 업로드 화면을 다시 열면 수동 재시도는 가능하다.

## 서버 구현 (Modal)

`server/calibration_modal/`에 이 계약의 Modal 구현이 있다. 배포, Secret, 버킷 설정은 그 폴더의 README를 따른다. 앱 설정은 `CALIBRATION_API_BASE_URL=<Modal 배포 URL>/v1`, `CALIBRATION_STORAGE_HOSTS=<버킷 S3 API 호스트>`다.

## 운영 전 서버 담당자가 구현할 부분

1. HTTPS API 두 개와 기존 로그인 토큰 검증 또는 합의한 토큰 교환.
2. 사용자별 private 저장소 경로, 최소 권한의 짧은 유효 기간 PUT URL, 암호화·접근 제어.
3. 멱등성 상태 저장, 완료 파일 검증, 단 한 번의 분석 작업 등록.
4. 요청 제한, 용량 제한, 만료된 부분 업로드 정리, 사진 보관·삭제 정책과 동의 문구.
5. 별도 분석 worker와 작업 상태·결과 API. 앱의 결과 polling 또는 notification과 실제 3D 결과 화면은 후속 구현.

서버리스 선택만으로 체형 fitting의 실행 환경이나 비용이 결정되는 것은 아니다. 이 문서는 클라우드 리소스를 생성하거나 GPU 작업을 배포하지 않는다. 자동 삭제를 보장할 구현이 없으므로 기존 화면의 “분석 끝나면 바로 삭제” 문구도 사용하지 않는다.

## 검증과 이어서 작업하기

```sh
flutter test --no-pub test/calibration_upload_test.dart test/onboarding_analyzing_test.dart test/onboarding_scan_test.dart test/onboarding_capture_test.dart
flutter analyze --no-pub lib/features/onboarding/services/calibration_upload_service.dart lib/features/onboarding/screens/onboarding_analyzing_screen.dart test/calibration_upload_test.dart test/onboarding_analyzing_test.dart
swift test --package-path ios/CalibrationEngineKit
```

HTTP 어댑터 테스트는 합성 파일 바이트가 정확히 전송되는지, 인증 분리, 실패 후 재시도, 완료 응답 유실, 잘못된 파일·URL·리다이렉트 거절을 검사한다. 실제 서버·저장소·iPhone 네트워크 경로 검증을 대신하지 않는다. 네이티브 저장 성공 ACK·실패 복구는 Swift 테스트로 검증했지만 실제 카메라 intrinsics 정확성과 전체 iPhone 경로는 여전히 별도 검증 대상이다.

후속 작업용 짧은 프롬프트:

> BPT의 docs/research/calibration_serverless_upload.md를 읽고 이어서 작업해줘. Flutter 전송 클라이언트는 구현돼 있고 서버리스 공급자는 아직 미정이야. 기존 변경을 보존하고, 공급자·배포 주소·인증 계약을 확인한 뒤 명세대로 서버를 연결하고 실기기에서 검증해줘. 사진 접수 완료를 3D 분석 완료로 표시하지 마.
