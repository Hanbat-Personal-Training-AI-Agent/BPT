# 세트 종료 후 자동 심층분석

2026-10-23 코드·합성 테스트, 2026-10-24 체형 고정(β) 자세 추정·로컬 실측·Modal 배포. 기존 캘리브레이션 API 주소와 인증 방식을 그대로 사용한다.

## 켜는 법 (기본값은 꺼짐)

세트 녹화 플래그가 켜졌을 때만 영상이 생기고 업로드된다. 꺼져 있으면 `onSetEnd`의 `videoLocalPath`·`deepAnalysis`가 null이라 대기열에 아무것도 들어가지 않고, 결과 화면 다시보기는 예전 데모 영상으로 동작한다.

- 환경 변수 `BPT_SET_RECORDING=1`(Xcode scheme) 또는 `UserDefaults` 키 `BPTSetRecording = true`.

## 단안 영상 + 체형 스캔 β 고정 (2026-10-24)

다시점 삼각측량은 쓰지 않는다. 휴대폰 영상 한 개만 쓴다.

- 업로드 완료 시 서버가 그 사용자의 가장 최근 체형 스캔 결과(`results/{user}/…/{jobId}.json`의 `smplBeta`)를 찾아 작업에 `shape{calibrationJobId, smplBeta}`로 싣는다. 앱 변경은 없다.
- GVHMR에서는 자세(global_orient·body_pose)만 받는다. 프레임별 β는 버린다.
  - 스캔 SMPL β를 SMPL로 바로 돌리면 GVHMR SMPL-X 골격과 회전이 어긋나 팔꿈치 각도가 나빠졌다(아래 v1).
  - 그래서 스캔 SMPL 휴식 자세 메시(SMPL 정점 순서로 바꾼 것)에 가장 가까운 SMPL-X β를 선형 최소제곱으로 구하고, GVHMR SMPL-X를 그 β로 돌린다. 관절은 지금처럼 H36M-17 regressor로 만든다.
- 위치·크기: 골반은 GVHMR이 둔 자리를 (사용자 키 ÷ GVHMR 체형 키) 배율로 카메라(world) 원점 기준 축척한다. 더 큰 몸은 더 멀리 있어야 같은 크기로 찍히기 때문이다.
- 스캔이 없거나 읽지 못하면 GVHMR β로 대신하고, 리포트 `bodyShape.source`를 `gvhmr_fallback`으로 남긴다. 스캔을 쓰면 `{"source":"calibration","calibrationJobId":…}`.

### 실측: Exercise3D P2 barbellrow_0003 cam2 (Home GTX 1060, 클라우드 업로드 없음)

비교 기준은 Sapiens2 3시점 삼각측량이다(`not_ground_truth`). 미터 환산에는 `smpl_fit`의 `scale_arbitrary_to_meters`로 **나눈다**(이름과 반대 방향, 허벅지 0.41 m로 확인). 팔다리 12관절, 694/757 프레임. 영상은 앱처럼 720p H.264 2.5 Mbps로 바꿨다. 반복 경계 10회는 삼각측량 팔꿈치 각도로 잘랐다(기기 경계 대신).

| 체형 | 강체 정렬 MPJPE (mm, 축척 정렬 없음) | PA-MPJPE (mm) | 무릎·고관절·팔꿈치 각도 오차 평균 (°) | 팔꿈치 R/L (°) |
| --- | --- | --- | --- | --- |
| GVHMR 자체 β | 62.7 | 50.0 | 6.75 | 11.6 / 8.5 |
| **체형 스캔 β (IMG_9900 캘리브레이션 job-cacbaa3c…)** | **48.6** | **46.4** | **6.74** | 11.9 / 9.0 |
| Exercise3D 사진 β (P2) | 50.4 | 48.1 | 6.68 | 11.8 / 8.8 |
| 평균 체형 β=0 | 53.3 | 47.2 | 6.32 | 10.7 / 7.9 |
| v1: 스캔 β를 SMPL로 바로 (폐기) | 50.8 | 49.3 | 8.22 | 16.1 / 10.7 |

- 스캔 β는 3D 위치·크기 오차를 줄였다(강체 −14 mm, PA −3.6 mm). 각도 오차는 그대로다(±0.1°).
- 평균 체형이 각도에서는 조금 낫다(−0.4°). 영상 한 개, 비교 기준도 정답이 아니어서 차이의 원인을 확정하지 않는다. 엉덩이 관절 정의도 H36M과 COCO식이 다르다.
- 이 영상은 다른 사람이 30 % 이상 추적돼 서버 규칙 `multiple_people`에 걸린다. 로컬 실측에서만 규칙을 건너뛰었다.
- Home 기록: `~/bpt-runs/deep-test/20261024-p2-row3-cam2/manifest.json`(sha256, 명령, v1 비교 파일).

## 변경 파일과 흐름

- `ios/Runner/NativePose/Bridge/WorkoutSessionBridge.swift`, `Camera/CameraPosePreview.swift`, `Evaluators/BenchPressEvaluator.swift`: 기본 세트 녹화, 영상 PTS와 반복 경계 대응, 벤치프레스의 마지막 보류 판정 마감. 720p H.264, 2.5Mbps, 무음, 최대 60초. 60초 안에 온전히 담긴 반복만 전송한다. 긴 세트 전체를 분석한 것으로 표시하지 않는다. 최근 원본 영상 20개를 보관하는 기존 정책을 유지한다.
- `lib/features/workout/data/deep_analysis_service.dart`, `deep_analysis_queue.dart`, `native_pose_channel.dart`: Bearer 인증 API, 별도 무인증 R2 클라이언트, 계정·API 주소별 영속 대기열, 자동 업로드·폴링·재시도. 서명 URL·토큰·리포트는 로컬 대기열에 저장하지 않는다. 접수 전에는 재전송에 필요한 영상 경로와 반복 데이터를 저장하고, 접수 후 지운다.
- `lib/main.dart`, `native_pose_workout_screen.dart`, `workout_result_screen.dart`, 홈·달력 화면: 세트 종료 이벤트에서 자동 접수. 운동 기록 UUID와 작업을 연결한다. 세트 결과·최근 기록·달력에 `심층분석 중…` / `완료`를 작게 표시하며 완료한 세트에서 리포트를 연다. 다른 운동 기록의 분석을 섞지 않는다.
- `deep_analysis_report_screen.dart`: 세로 화면에서 원래 영상 비율의 플레이어, 스크럽·재생, 총평과 반복별 코리 타임라인, 탭 시 seek, 펼쳐 보는 상세 지표·근거, MP4 사진 저장·공유. 다운로드 때 URL을 새로 받고 재생 중에는 50분마다 및 앱 복귀 때 갱신한다.
- `server/calibration_modal/{deep_analysis,deep_metrics,deep_worker}.py`, `deep_rules.csv`, `service.py`, `modal_app.py`: 별도 작업 계약, 합성 검증 가능한 지표, GVHMR L4 작업, ffmpeg 오버레이. 기존 캘리브레이션 endpoint와 작업 키는 유지한다.
- `server/calibration_modal/tests/test_deep_analysis.py`, `test/deep_analysis_test.dart`: 계약·지표·타임라인·재시도·자동 시작 검증.

자동 작업은 앱 화면 전환과 무관하게 이어 간다. iOS가 앱 프로세스를 정지하면 업로드·폴링도 멈추며 다음 실행/복귀 때 재개한다. 서버에 접수된 GPU 작업은 계속된다. OS 백그라운드 URLSession이나 강제 종료 후의 전송을 보장하는 구현은 아니다. 다른 기기에 로컬 분석 이력을 동기화하지 않는다.

전송은 영상 **32MiB**, 반복 JSON **256KiB**가 절대 상한이다. 시작할 때 Wi-Fi가 아니면 **8MiB 이하** 영상만 전송한다. 30–60초 영상은 대략 9.4–18.8MB여서 보통 Wi-Fi를 기다린다. 전송 중 연결 전환을 OS가 허용하면 32MiB 상한 내에서 셀룰러가 사용될 수 있다. 연결 오류는 팝업 없이 30/60/120/300초 간격으로 재시도하고, GPU 실패는 멱등 retry endpoint로 한 번만 재실행한다. 두 번째 GPU 실패 또는 원본 소실 시 상태 표시는 조용히 숨긴다. 원본 20개 정리로 오래 대기한 영상이 사라질 수 있다.

## HTTP 계약

모든 API는 `Authorization: Bearer <로그인 토큰>`. 업로드 준비와 완료에는 `Idempotency-Key: <sessionId>`가 필요하다. 인증 헤더는 presigned PUT/GET에 전달하지 않는다.

| 메서드·경로 | 요청·응답 |
| --- | --- |
| `POST /v1/deep-analysis/uploads` | `schemaVersion: 1`, `clientSessionId`, `files[{name,sizeBytes,contentType}]`. 영상 `video.mp4`와 `reps.json`만 받는다. `upload_required` + `uploadId` + PUT URL 또는 이미 접수된 `accepted` + `jobId`. |
| `POST /v1/deep-analysis/uploads/{uploadId}/complete` | `clientSessionId`. 저장 객체의 크기·타입 및 반복 구간 검증 후 202 `accepted` + `jobId`. 중복 완료는 GPU 작업을 늘리지 않는다. |
| `GET /v1/deep-analysis/jobs/{jobId}` | `queued/running/done/failed`, `progressRate`. 완료 시 `result{report,reportUrl,videoUrl}`. GET URL은 각각 **3600초**. 다시 조회하면 갱신한다. 실패 시 `error`, `retryable`. 타인 작업은 404. |
| `POST /v1/deep-analysis/jobs/{jobId}/retry` | 실패 작업의 원본 입력으로 한 번만 재접수. 중복·동시 호출은 같은 새 `jobId`. 두 번째 실패의 retry는 409. |

`type: deep_analysis`, 상태 키 `deep-upload/deep-session/deep-job/deep-call/deep-retry`, 입력 `deep-analysis/{user}/{session}/{upload}/`, 출력 `deep-results/{user}/{job}/`. 캘리브레이션과 서로 겹치지 않는다. worker 제한 15분, 조회 시 watchdog 30분. 다운로드와 응답의 사용자 구분은 JWT `sub`로만 결정한다.

`reps.json`:

```json
{
  "schemaVersion": 1,
  "sessionId": "set-example",
  "exerciseId": "squat",
  "timebase": "video_ms",
  "reps": [{
    "repIndex": 1, "startMs": 0, "endMs": 3000, "side": "left",
    "onDeviceRepIndex": 1, "onDeviceWarnings": [],
    "onDeviceMetrics2D": {}, "onDeviceMetrics3D": {}
  }]
}
```

경계는 영상 시작 기준 `[startMs,endMs)`. 최대 100회, 0–60000ms, 겹침·NaN·음수·잘못된 운동 ID는 거절한다. 기기 원래 반복 번호도 보존하며 영상에 들어온 반복은 1부터 다시 번호를 매긴다. `onDeviceMetrics2D/3D`는 선택 필드다.

## 지표·피드백·영상

GVHMR 고정 카메라 경로가 매 프레임 생성한 H36M-17 world 좌표(y 위, m)로 지표를 계산한다. 원본은 PTS를 유지한 30fps로 정규화한다. camera 좌표와 K로 원본 위에 골격을 투영하고, 우측 반투명 패널에 3D 골격·관절 각도·반복 번호를 그려 ffmpeg H.264 MP4를 만든다. 패널은 영상 안에 겹쳐 **9:16 / 16:9 원본 비율**을 유지한다.

`report`는 `schemaVersion`, `exerciseId`, `fps`, `summary`, `reps`, `timeline`, `faults`, `consistency`, `rules`, `notes`를 담는다.

| 반복 필드 | 정의 |
| --- | --- |
| `anglesDeg` | 무릎·고관절·팔꿈치·어깨·몸통의 min/max/ROM 및 동일한 top/bottom 프레임에서의 각도. 몸통은 중력 기준, 나머지는 관절 내각. |
| `romDeg`, `depthAngleDeg`, `depthMeters` | 주 관절 최대−최소, 최소 내각, 골반의 수직 이동 폭. 운동 간 공통의 절대 깊이 점수는 아니다. |
| `tempoSeconds`, `tempoOrder` | 늘림(eccentric), 전환점 ±3°에 연속 머문 멈춤, 수축(concentric). 스쿼트·푸시업·벤치는 늘림 먼저, 로우·데드리프트는 수축 먼저. 정지한 세트/불완전한 반복에서는 해석에 주의한다. |
| `handPath` | 골반 상대 좌·우 손목 3D 경로(반복당 최대 90개 시각 표본), 평균 손목 경로 길이·수평 이동·수직 폭. 바벨을 검출한 값은 아니다. |
| `symmetryDeg`, `trunkStability` | 양쪽 관절 각도 차이(mean/max), 몸통 기울기 std/range 및 골반 상대 수평 흔들림. |
| `fatigueDrift`, `consistency` | 첫 3회 중앙값 대비 깊이·ROM·템포 변화, 세트 ROM 표준편차·템포 변동. 4회부터 비교 가능. 피로의 원인을 확정하지 않는다. |
| `comparison`, `evaluatedKeys`, `unassessedDeviceWarnings` | 같은 경고 키의 유무만 비교. 평가하지 않은 기기 경고를 일치 판정에 넣지 않는다. native 2D 판정과 서버 3D·세트 기준은 다를 수 있다. |
| `faults` | 키·심각도·임계값·관측값·설명·신뢰도 및 `evidence[{frame,t,view:"overlay"}]`. 실제 소견을 낸 반복 구간 안의 근거 프레임을 가리킨다. |

신뢰도는 ViTPose 2D 관절 검출 평균 × 추적 프레임 비율의 지지도다. 판정 정확도 확률이 아니다. 0.35 미만이면 규칙 판정과 기기 비교를 보류한다. 타임라인은 `{t,title,body,severity,rep}`이고 첫 항목은 `총평`, 이어 반복 항목과 근거 소견을 시간순으로 제공한다. 문구는 코리 반말이다.

### 코칭 카탈로그가 아직 없는 경우

이 작업트리에는 `docs/coaching/fault_catalog.csv`가 없다. `deep_rules.csv`를 **임시 규칙**으로 사용하며 `report.rules.placeholder=true`로 남긴다. 다른 브랜치의 파일을 가져오거나 병합하지 않았다. 현재 공유할 CSV 열 계약은 다음과 같다.

```text
fault_id,exercise_id,metric,threshold,severity,title_ko,body_ko,device_key
```

팀 카탈로그의 실제 열은 아직 확인하지 못했다. `ai/coaching-team-mf953336`의 파일을 이 작업트리에 반영할 때 위 열과 대조하고 필요하면 어댑터를 맞춰야 한다. 임시 파일을 공식 카탈로그로 오인하지 않도록 별도 경로에 두었다. 해당 파일이 생기면 Modal 이미지에 포함하고 우선 사용한다. 열이 다르면 `invalid_fault_catalog`로 명시적으로 실패한다. 코드를 실행하는 표현식은 CSV에 넣지 않는다.

현재 지원 metric: `depthDriftDeg`, `romDropDeg`, `tempoDriftRatio`, `symmetryMaxDeg`, `trunkStdDeg`. 그 밖의 카탈로그 항목은 판정하지 않는다. 임계값은 임시 휴리스틱이며 데이터셋·실제 영상으로 정확도를 검증했다는 뜻이 아니다.

## 배포 상태 (2026-10-24)

- Volume `bpt-gvhmr`: GVHMR 체크포인트 4개(sha256 확인), SMPL-X·SMPL 중립 모델, `smpl_neutral_h36m.npz`를 올렸다.
- `bpt-calibration`에 `deep_analysis_job`(L4)과 `/v1/deep-analysis` 라우트를 배포했다. 배포 직후 약 17분 동안 컨테이너 경로 오류(`parents[2]`)로 API가 시작하지 못했다(14:48–15:05 KST). 수정 후 캘리브레이션·심층분석 경로 모두 401(인증 필요)로 정상 응답한다.
- 이미지에 `libtk8.6`을 넣었다. GVHMR `body_model.py`가 import 때 turtle(tkinter)을 불러온다.
- 스모크 테스트: 사용자 본인 IMG_9900(이미 캘리브레이션에 쓴 영상)을 720p 20초로 바꿔 R2에 직접 올리고 worker를 호출했다. `done`, `bodyShape.source=calibration`. GPU 단계 합 119초, 클라이언트 왕복 135초(콜드 스타트 포함). L4 ≈ $0.80/시간 기준 약 $0.03/세트 + 유휴 60초 $0.013. 공개 CC BY 로우 영상은 `multiple_people`로 거절됐다.

## 배포 담당자의 수동 절차 (참고)

1. 코칭 카탈로그의 열·임계값·기기 경고 키를 확인한다. 아래 Flutter 테스트와 iOS 확인을 먼저 끝낸다. GVHMR/SMPL-X/SMPL의 기존 연구·비상업 사용 조건은 `scripts/deep_analysis/modal_bench.py`, `gvhmr_runner.py`의 안내를 따른다.
2. 기존 Modal 비밀 설정 `bpt-r2`, `bpt-jwt`의 존재 여부만 담당 환경에서 확인한다. 값을 소스·앱·문서에 복사하지 않는다. 심층분석 worker에는 R2 설정만, API에는 R2/JWT 설정이 연결된다.
3. 기존 벤치와 같은 private Modal Volume **`bpt-gvhmr`**를 준비한다. 소스 코드는 GVHMR commit `ee960bb6e2ea2d381aa97f08e9b71ef320b624b1`로 고정했다. 이미지가 `/vol`을 `inputs/checkpoints`에 연결한다.

| `/vol` 상대 경로 | 준비 방법 |
| --- | --- |
| `gvhmr/gvhmr_siga24_release.ckpt` | 기존 `modal_bench.py::download_weights`의 체크섬 확인 경로 |
| `hmr2/epoch=10-step=25000.ckpt` | 위와 같음 |
| `vitpose/vitpose-h-multi-coco.pth` | 위와 같음 |
| `yolo/yolov8x.pt` | 위와 같음 |
| `body_models/smplx/SMPLX_NEUTRAL.npz` | 담당자가 사용 권한이 있는 모델을 private Volume에 올림 |
| `body_models/smpl/SMPL_NEUTRAL.pkl` | 위와 같음 |
| `smpl_neutral_h36m.npz` | 기존 `prepare_weights.py`로 준비한 BPT 좌우 수정 H36M regressor 포함 파일 |

가중치는 저장소·앱에 넣지 않는다. 없으면 `weights_missing`으로 실패하며 서버가 가짜 결과를 만들지 않는다. 파일 확인·다운로드·Volume 업로드는 이 작업에서 수행하지 않았다.

담당 환경에서만 실행할 배포 명령:

```sh
# 저장소 루트. 기존 벤치 이미지의 체크포인트 준비가 필요한 경우에만 실행.
(cd scripts/deep_analysis && modal run modal_bench.py::download_weights)
# 라이선스가 있는 body model 3개는 위 경로로 담당자가 별도 업로드.
(cd server/calibration_modal && modal deploy modal_app.py)
```

4. 앱의 `CALIBRATION_API_BASE_URL`, `CALIBRATION_STORAGE_HOSTS`는 [기존 연결 안내](../handoff/teammate_calibration.md)의 공개 설정을 사용한다. 새 앱 배포 전에 `/v1/deep-analysis` 라우트가 추가된 API를 확인한다. R2 보존 정책에는 입력·출력·작업 상태 키를 함께 포함하고 담당자가 보존 기간을 정한다.
5. 별도 동의받은 본인 테스트 영상으로 30초·60초, 가로·세로 각각 한 세트를 확인한다. 실제 사용자·데이터셋 영상을 이 개발 세션에 가져오지 않는다.

### L4 세트당 예상 비용 산식

이번에는 벤치/GPU를 실행하지 않았고 기존 `docs/deep_analysis/gvhmr_eval.md`도 처리시간 측정 결과가 아닌 목표만 적혀 있다. 따라서 아래는 **예산 가정**이며 측정값·현재 Modal 요금 견적이 아니다. 실제 L4 초당 단가 `P`는 배포 담당자가 [Modal 요금표](https://modal.com/pricing)에서 확인해야 한다.

- 30–60초 영상의 추론·인코딩 120–240초, 콜드 시작 0–60초를 가정: GPU 활성 비용 `(120~300) × P` 달러/세트.
- 예시로 **P = 0.00025달러/초를 가정**하면 약 **0.03–0.075달러/세트**. 실제 단가가 아니라 계산용 입력값이다.
- 설정된 idle window 60초를 한 세트가 전부 부담하면 `60 × P` 추가(같은 가정에서 0.015달러). 재시도는 최대 두 번의 GPU 실행 비용을 부담한다. CPU·메모리·R2 보관/요청 비용은 별도다.
- `min_containers=0`, worker timeout 900초. timeout까지 간 실패 1회의 GPU 활성 비용은 최대 `900 × P`이며 정상 세트 비용 가정과 구분한다.
- 배포 검증 때 30/60초 각 cold/warm을 재고 `report.timingSeconds`뿐 아니라 다운로드·정규화·렌더링·idle을 포함한 Modal 청구 시간을 비교해 위 가정을 교체한다.

## 검증 결과와 남은 확인

2026-10-24 재확인: `flutter analyze` 문제 0, `flutter test` 113 통과, `swift test`(CalibrationEngineKit) 111 통과, 서버 pytest 115(114 통과, 1 건너뜀), `flutter build ios --debug --no-codesign` 성공. 아래는 2026-10-23 당시 기록이다.

실행 성공: 심층분석·업로드 검증·Modal 실패 매핑 단위 테스트 **86개 통과**. 합성 골격·메모리 저장소·가짜 worker만 사용했다. 기존 캘리브레이션 준비→완료→조회도 메모리 저장소로 검증했다. 신규 Dart 파일과 위젯 테스트의 `dart format` 구문 파싱, 변경한 Swift 파일 3개의 `swiftc -frontend -parse`, `git diff --check` 확인. Swift 구문 검증은 iOS 빌드나 타입 검사를 대신하지 않는다.

```sh
mkdir -p .test-tmp
TMPDIR="$PWD/.test-tmp" PYTHONDONTWRITEBYTECODE=1 PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 \
  conda run -n bpt-eval python -I -m pytest \
  server/calibration_modal/tests/test_deep_analysis.py \
  server/calibration_modal/tests/test_checks.py \
  server/calibration_modal/tests/test_modal_app.py \
  -q -p no:cacheprovider --basetemp="$PWD/.test-tmp/pytest"
flutter test --no-pub test/deep_analysis_test.dart test/native_pose_channel_test.dart
```

실행 제한:

- Flutter 위젯 테스트: SDK `engine.stamp` 쓰기가 거절되어 테스트 시작 전 실패. 기존 Dart 런타임으로 Flutter 도구를 실행해도 SDK `lockfile` 쓰기가 거절됐다. 테스트를 통과했다고 주장하지 않는다.
- Dart analyze: 분석 서버가 사용자 홈의 `.dartServer/.plugin_manager`를 만들 수 없어 종료. 파일 포맷 검증만 완료했다.
- 기존 S3 통합 `test_api.py`를 포함한 실행은 완료되지 않아 중단했다. 이 세션에서는 소켓 기반 전체 캘리브레이션 회귀를 확인하지 못했다.
- Swift/iOS 빌드·실기기 재생·GVHMR 추론·ffmpeg 실제 인코딩·R2·Modal E2E는 실행하지 않았다. 모델과 영상은 열지 않았다.

수동 확인: 위젯 테스트에서 세트 종료 후 버튼 없이 업로드, 화면 이탈 후 폴링, 중복 방지, 재실행 복원, 실패 재시도, 타임라인 seek를 확인한다. iPhone에서는 녹화 켰을 때 포즈 FPS·발열·저장공간, 앞/뒤 카메라·가로/세로 회전, 60초 경계, 전체 반복 수와 분석 반복 수 차이, 영상·라벨·근거 시각 일치, Wi-Fi 대기와 연결 전환, 로그아웃 계정 분리, URL 만료 후 재생, 사진 권한·공유를 확인한다. 기존 캘리브레이션 업로드→결과도 한 번 회귀 확인한다.
