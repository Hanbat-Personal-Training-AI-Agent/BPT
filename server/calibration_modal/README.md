# BPT 캘리브레이션 서버 (Modal)

앱이 촬영한 사진 4장과 `manifest.json`을 받아 검증하고 체형 fitting 작업을 접수한다. 계약은 [캘리브레이션 서버리스 업로드](../../docs/research/calibration_serverless_upload.md)가 기준이다.

현재 1단계: 업로드 URL 발급, 완료 검증, 단 한 번의 작업 접수, 작업 상태 조회. `fit_body`는 입력을 다시 검증한 뒤 **고정 결과(`"stub": true`)** 를 저장하는 스텁이며 실제 체형 측정이 아니다. GPU도 아직 쓰지 않는다.

| 파일 | 역할 |
| --- | --- |
| `modal_app.py` | Modal 앱 `bpt-calibration`: `api`(FastAPI, CPU)와 `fit_body` |
| `service.py` | API 3개, 멱등 접수 |
| `checks.py` | 토큰, 식별자, 파일 목록, manifest, JPEG 검증 |
| `storage.py` | S3 호환 버킷(boto3): presigned PUT, 조회 |
| `worker.py` | 작업 실행과 상태 전이(`queued → running → done/failed`) |
| `e2e.py` | 배포된 서버에 앱과 같은 요청을 보내는 점검 스크립트 |

## 준비

1. 버킷: Cloudflare R2 버킷 하나(예: `bpt-calibration`)와 그 버킷에만 Object Read & Write 권한이 있는 API 토큰. 버킷은 공개하지 않는다.
2. Modal 로그인: `pip install modal && modal setup`
3. Secret (값은 터미널에서 직접 입력, 저장소에 남기지 않는다):

```sh
modal secret create bpt-r2 \
  R2_ENDPOINT_URL=https://<account_id>.r2.cloudflarestorage.com \
  R2_BUCKET=bpt-calibration \
  R2_ACCESS_KEY_ID=<access key id> \
  R2_SECRET_ACCESS_KEY=<secret access key>
modal secret create bpt-jwt JWT_SECRET=<백엔드 jwt.secret과 같은 base64 값>
```

S3를 쓰면 `R2_ENDPOINT_URL=https://s3.<region>.amazonaws.com`, `R2_REGION=<region>`을 넣는다.

## 배포와 앱 설정

```sh
cd server/calibration_modal
modal deploy modal_app.py
```

배포 출력의 `api` URL(예: `https://<workspace>--bpt-calibration-api.modal.run`)에 `/v1`을 붙여 앱에 넣는다. 저장소 호스트는 `R2_ENDPOINT_URL`의 호스트다(presigned URL은 path style이라 버킷 이름이 호스트에 붙지 않는다).

```sh
flutter run \
  --dart-define=CALIBRATION_API_BASE_URL=https://<workspace>--bpt-calibration-api.modal.run/v1 \
  --dart-define=CALIBRATION_STORAGE_HOSTS=<account_id>.r2.cloudflarestorage.com
```

## 테스트

```sh
python -m venv .venv && .venv/bin/pip install modal "fastapi[standard]" boto3 pyjwt pillow pytest "moto[server]" httpx
.venv/bin/python -m pytest -q tests
```

버킷은 moto 서버(실제 HTTP presigned PUT), `modal.Dict`는 메모리 대역으로 대신한다. moto는 presigned 서명의 Content-Type을 검사하지 않으므로, 그 확인은 실제 버킷에 대한 `e2e.py`가 한다.

배포 뒤 점검 (토큰은 백엔드 로그인 토큰, 출력하지 않는다):

```sh
BPT_TOKEN=<token> .venv/bin/python e2e.py \
  --api https://<workspace>--bpt-calibration-api.modal.run/v1 \
  --storage-host <account_id>.r2.cloudflarestorage.com \
  [--session-dir <앱 Documents/calibration/<sessionId> 폴더>]
```

## 상태 저장과 한계

- 상태는 사진 버킷의 `state/` 아래 작은 JSON 객체다(`storage.BucketState`). 업로드 URL은 `calibrations/` 키에만 발급되므로 앱이 `state/`를 쓸 수 없다.
- 사용자·세션당 한 번만 접수되는 것은 버킷 조건부 쓰기(`If-None-Match: *`)로 보장한다. S3와 R2 모두 지원하며 만료되지 않는다. 동시 조건부 쓰기 충돌(409)은 짧게 재시도한다.
- 결과 JSON은 `results/<userId>/<sessionId>/<jobId>.json`에도 남는다.
- 사진 자동 삭제, 부분 업로드 만료 정리, 요청 제한은 아직 없다. 버킷 수명 주기 규칙으로 따로 설정해야 한다.
