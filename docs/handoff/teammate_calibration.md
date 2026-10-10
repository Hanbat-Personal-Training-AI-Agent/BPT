# 체형 캘리브레이션 연동 안내 (팀원용)

팀원 요청 6(주소·호스트 값)과 7(3D 결과를 앱이 받는 방법, 결과 형식)에 대한 답이다. 계약의 원본은 [캘리브레이션 서버리스 업로드](../research/calibration_serverless_upload.md)이고, 이 문서는 바로 쓸 값과 예시만 모았다. 비밀값(JWT secret, R2 키, Modal 토큰)은 여기에도, 앱에도 넣지 않는다.

## 1. 앱 실행 값 (요청 6)

| 이름 | 값 |
| --- | --- |
| `CALIBRATION_API_BASE_URL` | `https://hqbfgym--bpt-calibration-api.modal.run/v1` |
| `CALIBRATION_STORAGE_HOSTS` | `1de0e5ab10d7233b02491befb246f0ff.r2.cloudflarestorage.com` |

```sh
flutter run \
  --dart-define=CALIBRATION_API_BASE_URL=https://hqbfgym--bpt-calibration-api.modal.run/v1 \
  --dart-define=CALIBRATION_STORAGE_HOSTS=1de0e5ab10d7233b02491befb246f0ff.r2.cloudflarestorage.com
```

- 둘 다 `--dart-define`으로만 들어간다. 기본값이 없어서 빠지면 전송 버튼이 꺼진다(기존 Spring 주소로 보내지 않음).
- 인증은 앱의 로그인 토큰(`ApiClient.authToken`, 백엔드 jjwt) 그대로다. 서버가 백엔드와 같은 `jwt.secret`으로 검증하고 `sub`(userId)로 작업 주인을 정한다.
- 저장소 호스트는 사진 PUT 주소와 3D 모델(GLB) GET 주소가 같은 호스트다.

## 2. 흐름

1. 사진 4장 + `manifest.json` 업로드 → `POST .../uploads/{uploadId}/complete`가 `{"status":"accepted","jobId":"job-..."}`. **접수일 뿐 분석 완료가 아니다.**
2. 앱이 `GET {CALIBRATION_API_BASE_URL}/calibrations/jobs/{jobId}`를 3초마다 부른다(아래 3절). `done` 또는 `failed`가 오면 멈춘다.
3. `done`이면 `result`가 체형 결과다. 백엔드 `UserCalibration`에 저장하려면 5절의 대응표를 따른다.

앱 구현(integration/ai에 반영): `CalibrationUploadService.fetchJob`(lib/features/onboarding/services/calibration_upload_service.dart)과 분석 화면의 polling·진행률·실패 문구·결과 요약(onboarding_analyzing_screen.dart). 결과 화면(`onboarding_result_screen.dart`)을 실제 결과로 바꾸는 변경은 팀원 코드라 브랜치 `ai/calibration-result-screen`에만 있다(6절).

## 3. 작업 상태 polling (요청 7)

`GET /v1/calibrations/jobs/{jobId}` — 헤더 `Authorization: Bearer <로그인 토큰>`만. 다른 사용자의 작업은 404.

| `status` | 뜻 | `progressRate` | 그 밖의 필드 |
| --- | --- | --- | --- |
| `queued` | 접수됨, GPU 대기 | 0 | |
| `running` | 분석 중 | 5 시작 → 30 3D 추정 → 50 SMPL 변환 → 90 보정 끝 | |
| `done` | 끝, 결과 있음 | 100 | `result` |
| `failed` | 실패 | 실패 직전 값 | `error` (4절) |

- 상태 값은 계약 문서 그대로 **소문자 4개**다. 대문자(`COMPLETED` 등)는 오지 않는다.
- 측정 시간(L4 GPU, 2026-10-10): 서버가 이미 켜져 있으면 접수→`done` 약 15초, 꺼져 있으면(모델 로드 포함) 약 65초. e2e 한 번에 접수부터 `done`까지 78초.
- 30분 안에 끝나지 않거나 worker가 죽으면(메모리 초과, 컨테이너 중단, Modal 15분 제한) 다음 조회 때 `failed`로 바뀐다. 영원히 `running`으로 남지 않는다.
- `progressRate`가 없는 응답(옛 서버)은 `queued`/`running` 0, `done` 100으로 읽는다.

## 4. 오류 코드

작업 실패(`{"status":"failed","error":"..."}`):

| `error` | 뜻 | 앱 문구(현재 구현) |
| --- | --- | --- |
| `low_keypoint_confidence` | 사진에서 어깨~발목 관절이 8개 미만으로 보임 | 관절이 잘 보이지 않았어요. 밝은 곳에서 다시 촬영해 주세요. |
| `person_not_found` | 3D 추정이 사람을 못 찾음 | 사진에서 사람을 찾지 못했어요. 전신이 보이게 다시 촬영해 주세요. |
| `fit_diverged` | 체형 맞춤이 발산, 재투영 오차가 사람 키의 15% 초과 | 체형을 맞추지 못했어요. 자세를 바르게 하고 다시 촬영해 주세요. |
| `timeout` | 30분 초과 또는 Modal 15분 제한 | 분석 시간이 초과됐어요. 잠시 뒤 다시 촬영해 주세요. |
| `internal_error` | 그 밖의 서버 오류, worker 비정상 종료, 결과 검증 실패 | 분석 중 오류가 났어요. 잠시 뒤 다시 시도해 주세요. |
| `invalid_manifest`, `invalid_jpeg` | 접수 뒤 파일 재검증 실패(드묾) | 기타와 같음 |

모르는 코드는 `internal_error`처럼 처리한다. HTTP 오류는 계약 문서의 거절 응답 표와 같다(`{"error": "...", "detail": "..."}`; 401 `unauthorized`, 404 `job_not_found`/`upload_not_found`, 400 `invalid_job_id` 등).

## 5. `done` 결과 JSON

형식 예시다. 값은 설명용으로 꾸민 숫자다(배포 e2e는 연구용 데이터셋 사진으로 했고, 그 사람의 측정값은 문서에 옮기지 않는다). `modelGlbUrl`의 서명 부분은 지웠다.

```json
{
  "status": "done",
  "progressRate": 100,
  "result": {
    "schemaVersion": 1,
    "stub": false,
    "bodyModel": "smpl_neutral_v1.1.0",
    "userHeightCm": 170,
    "smplBeta": [-0.4, 0.9, 0.8, 0.1, -0.4, -0.3, -0.4, 0.2, -0.5, 1.9],
    "boneLengthData": {
      "unit": "cm", "skeleton": "h36m17", "pose": "rest",
      "segments": {
        "pelvis-right_hip": 14.0, "right_hip-right_knee": 44.0, "right_knee-right_ankle": 42.0,
        "pelvis-left_hip": 14.0, "left_hip-left_knee": 44.0, "left_knee-left_ankle": 42.0,
        "pelvis-spine": 24.0, "spine-thorax": 24.0, "thorax-neck": 12.0, "neck-head": 11.0,
        "thorax-left_shoulder": 14.0, "left_shoulder-left_elbow": 26.5, "left_elbow-left_wrist": 24.5,
        "thorax-right_shoulder": 14.0, "right_shoulder-right_elbow": 26.5, "right_elbow-right_wrist": 24.5,
        "shoulder_width": 28.0, "hip_width": 28.0
      },
      "appDefinitionDiffers": ["pelvis-spine", "spine-thorax", "thorax-neck", "neck-head",
                               "thorax-left_shoulder", "thorax-right_shoulder"]
    },
    "jointsH36m": {"order": ["pelvis", "right_hip", "..."], "unit": "m", "pose": "rest",
                   "positions": [[0.0, -0.19, 0.02], "... 17개"]},
    "quality": {"heightErrorCm": 0.0,
                "perView": {"front": {"reprojectionErrorPx": 4.8}, "leftfront": {"reprojectionErrorPx": 4.6},
                            "rightfront": {"reprojectionErrorPx": 4.3}, "back": {"reprojectionErrorPx": 6.3}}},
    "debug": {"...": "앱·백엔드에서 쓰지 않음"},
    "coachComment": "체형 정보를 저장했어. 이제 네 몸에 맞춰 자세를 더 정확하게 봐 줄게!",
    "calibratedAt": "2026-10-10T13:00:00Z",
    "modelGlbUrl": "https://1de0e5ab10d7233b02491befb246f0ff.r2.cloudflarestorage.com/hanbat-personal-training/models/job-0123456789abcdef0123456789abcdef.glb?<서명>"
  }
}
```

| 필드 | 설명 |
| --- | --- |
| `stub` | 항상 `false`. 서버는 가짜 결과를 `done`으로 내지 않는다(β 10개·뼈 길이가 없으면 `failed internal_error`). 앱도 `stub != false`면 결과로 받지 않는다. |
| `smplBeta` | SMPL 중립 모델 체형 계수 10개. 단위 없음. 키(`userHeightCm`)를 반영한 값. |
| `boneLengthData.segments` | 휴식 자세 H36M 17관절 사이 길이(cm). 16개 부모-자식 구간 + 어깨·엉덩이 너비. `appDefinitionDiffers`의 구간은 앱 2D 골격과 정의가 달라 앱 측정값과 비교하지 않는다. |
| `jointsH36m` | 휴식 자세 관절 좌표(m, SMPL 좌표: y 위, x 사용자 왼쪽). 3D 뼈대 화면에 쓸 수 있다. |
| `coachComment` | 규칙 기반 한 줄(255자 이하). 허벅지/키 비율이 SMPL 평균보다 2% 넘게 길거나 짧을 때만 다른 문장(추정, 코칭용 휴리스틱). |
| `calibratedAt` | 분석이 끝난 시각, ISO 8601 **UTC**(`Z`). |
| `modelGlbUrl` | 사용자 자신의 3D 몸 모델(GLB) 임시 다운로드 주소. **1시간 뒤 만료**. 필요할 때 같은 GET을 다시 부르면 새 주소가 온다. 길이 약 410자(500자 이하로 맞춤). |
| `quality` | 재투영 오차(px)와 키 오차(cm). 앱 기능에는 쓰지 않음. |

GLB: glTF 2.0 binary, 메시 하나(정점 6,890, 삼각형 13,776, 약 250KB), 텍스처·뼈대 없음, 단위 m, y 위, 발바닥이 y = 0, 수평 중심이 원점. 자세는 정면 사진의 서 있는 자세를 똑바로 세운 것.

## 6. 백엔드(Spring) 변경 제안 — 반영은 팀원 결정

백엔드 코드는 손대지 않았다. 아래는 제안이다.

| `UserCalibration` | 넣을 값 | 비고 |
| --- | --- | --- |
| `jobId` | 완료 API의 `jobId` | 이미 있음(64자, `job-` + 32자 = 36자) |
| `status` | 3절 상태 값 | **제안: 계약 값(소문자) 그대로 저장.** 지금 기본값 `"COMPLETED"`와 맞추려면 `done→COMPLETED`, `failed→FAILED`, `queued→QUEUED`, `running→RUNNING`으로 바꾸어 저장(20자 이내). |
| `progressRate` | `progressRate` 정수 | |
| `smplBeta` | `JSON.stringify(result.smplBeta)` | TEXT |
| `boneLengthData` | `JSON.stringify(result.boneLengthData)` | TEXT, 약 1KB |
| `modelGlbUrl` | 저장하지 말고 필요할 때 이 API에서 새로 받기를 권장 | 1시간 만료. 저장한다면 "만료되는 주소"로 다루고, 앱이 쓰기 직전에 job API로 갱신. 영구 주소가 필요하면 백엔드가 R2 키(`models/{jobId}.glb`)로 직접 발급하는 방식을 따로 합의해야 함(R2 키 공유 = 사용자 결정). |
| `coachComment` | `result.coachComment` | **main의 엔티티에는 이 열이 없다.** `feature/front-kori-feedback-lines`, `feat/update-auth-and-records` 브랜치에만 `@Column(length = 255) coachComment`가 있다. main에 합칠 때 추가 필요. |
| `calibratedAt` | `result.calibratedAt` | `LocalDateTime`은 `Z`를 바로 못 읽는다. `Instant.parse(...)`/`OffsetDateTime`으로 읽고 서버 기준 시간대(KST 추정)로 바꿔 저장. |

- 지금 백엔드에는 캘리브레이션 저장 API가 없다(`UserCalibration`은 대시보드의 마지막 측정일 계산에만 쓰임). 앱이 `done` 결과를 백엔드에 올리는 API(예: `POST /users/me/calibrations`)가 필요하면 위 표가 그 본문이다.
- 상태 값을 계약 쪽에 맞춘 이유: 팀원이 "상태 값과 결과 JSON 형식은 기존 계약 문서 기준"이라고 했고, 앱·서버·e2e가 이미 소문자 값으로 맞물려 있다. 대문자로 바꾸면 세 곳을 다 바꿔야 한다(docs/decisions.md F1).

## 7. 라이선스 주의

- 체형 모델 SMPL: 비상업 연구·교육용(https://smpl.is.tue.mpg.de/modellicense.html, "License Grant"와 "No Distribution" 조항). 모델 파일은 저장소·앱에 넣지 않는다. GLB는 SMPL로 만든 결과물이라 **본인에게만, 비상업(캡스톤) 용도로** 제공한다. 상업 서비스로 내려면 Meshcapade 상업 라이선스가 필요하다.
- SAM 3D Body·MHR: 서버에서만 쓴다(docs/decisions.md F4).
- Sapiens2는 캘리브레이션에 쓰지 않는다(생체정보 처리 금지 라이선스).
