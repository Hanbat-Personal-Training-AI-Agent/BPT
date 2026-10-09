# BPT 캘리브레이션 서버 (Modal)

앱이 촬영한 사진 4장과 `manifest.json`을 받아 검증하고 체형 fitting 작업을 접수한다. 계약은 [캘리브레이션 서버리스 업로드](../../docs/research/calibration_serverless_upload.md)가 기준이다.

업로드 URL 발급, 완료 검증, 단 한 번의 작업 접수, 작업 상태 조회, 그리고 L4 GPU의 `fit_body`(`fitting.py`): manifest의 RTMPose COCO-17로 사람 상자 → SAM 3D Body(사진별) → MHR 공식 변환기로 SMPL(β 하나 공유) → 2D 키포인트 재투영으로 공동 보정 → β 키 사영 → 자세 재보정. 마스크·실루엣 손실은 없다(v1).

| 파일 | 역할 |
| --- | --- |
| `modal_app.py` | Modal 앱 `bpt-calibration`: `api`(FastAPI, CPU)와 `fit_body` |
| `service.py` | API 3개, 멱등 접수 |
| `checks.py` | 토큰, 식별자, 파일 목록, manifest, JPEG 검증 |
| `storage.py` | S3 호환 버킷(boto3): presigned PUT, 조회 |
| `worker.py` | 작업 실행과 상태 전이(`queued → running → done/failed`), 결과 JSON 형식 |
| `fitting.py` | GPU fitting (SAM 3D Body, MHR→SMPL, 재투영 보정) |
| `body.py` | β 키 사영, H36M 관절, 뼈 길이 (fitting 없이 가능한 부분) |
| `prepare_weights.py` | SMPL 중립 모델 + `J_regressor_h36m`(좌우 순서 교정)을 npz로 만들어 Volume `bpt-weights`에 업로드 |
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

버킷은 moto 서버(실제 HTTP presigned PUT과 조건부 쓰기)로 대신한다. moto는 presigned 서명의 Content-Type을 검사하지 않으므로, 그 확인은 실제 버킷에 대한 `e2e.py`가 한다.

배포 뒤 점검 (토큰은 백엔드 로그인 토큰, 출력하지 않는다):

```sh
BPT_TOKEN=<token> .venv/bin/python e2e.py \
  --api https://<workspace>--bpt-calibration-api.modal.run/v1 \
  --storage-host <account_id>.r2.cloudflarestorage.com \
  [--session-dir <앱 Documents/calibration/<sessionId> 폴더>]
```

## 체형 모델 가중치 (2단계)

SMPL과 `J_regressor_h36m.npy`는 재배포가 금지되거나 출처 라이선스가 SMPL에 묶여 있어 git에 넣지 않는다. 배포하는 사람이 각자 받아서 Volume에 올린다.

```sh
# SMPL: https://smpl.is.tue.mpg.de (SMPL for Python v1.1.0, 연구·교육용 비상업 라이선스)
# J_regressor_h36m.npy: SPIN fetch_data.sh가 받는 data.tar.gz 안의 data/J_regressor_h36m.npy
python prepare_weights.py --smpl basicmodel_neutral_lbs_10_207_0_v1.1.0.pkl --h36m J_regressor_h36m.npy --upload
```

SPIN 배포본은 1~3행이 왼쪽 다리, 4~6행이 오른쪽 다리다. 스크립트가 앱 순서(오른쪽 먼저)로 바꾸고 SMPL 휴식 자세에서 좌우를 검사한다. 공식 pickle은 chumpy가 있어야 열린다.

SAM 3D Body 체크포인트(`facebook/sam-3d-body-dinov3`, 접근 승인 필요)는 `modal run modal_app.py::download_weights`로 Volume에 받는다(Secret `bpt-hf`의 HF_TOKEN).

알려진 우회: pymomentum-cpu 0.1.114로 MHR FBX 리그를 읽으면 세그폴트가 나서, SAM 3D Body는 `MOMENTUM_ENABLED=0`으로 체크포인트의 TorchScript MHR을 쓰고, 변환기에는 MHR 면 정보만 넘긴다(`MhrTopology`, 정점 입력 변환은 면만 읽는다).

## 상태 저장과 한계

- 상태는 사진 버킷의 `state/` 아래 작은 JSON 객체다(`storage.BucketState`). 업로드 URL은 `calibrations/` 키에만 발급되므로 앱이 `state/`를 쓸 수 없다.
- 사용자·세션당 한 번만 접수되는 것은 버킷 조건부 쓰기(`If-None-Match: *`)로 보장한다. S3와 R2 모두 지원하며 만료되지 않는다. 동시 조건부 쓰기 충돌(409)은 짧게 재시도한다.
- 결과 JSON은 `results/<userId>/<sessionId>/<jobId>.json`에도 남는다.
- 사진 자동 삭제, 부분 업로드 만료 정리, 요청 제한은 아직 없다. 버킷 수명 주기 규칙으로 따로 설정해야 한다.
