# 결정 기록

## 트랙 F — 캘리브레이션(계약·품질·인계) — 2026-10-10

### F1. 상태 값·결과 JSON은 계약 문서 쪽으로 맞춘다 (백엔드 `"COMPLETED"`가 아니라)
- 결정: `GET /v1/calibrations/jobs/{jobId}`의 `status`는 계약 문서(docs/research/calibration_serverless_upload.md)의 소문자 `queued|running|done|failed` 그대로. 결과 JSON 키도 계약 그대로 두고, 백엔드 `UserCalibration`과 같은 이름의 필드만 **추가**: `progressRate`(응답 최상위), `coachComment`, `calibratedAt`, `modelGlbUrl`(result 안).
- 근거: 배포 서버와 계약 문서를 비교한 결과 상태 값·`smplBeta`·`boneLengthData`는 이미 일치했고, 다른 것은 백엔드 엔티티뿐(기본 `status="COMPLETED"`, `progressRate`·`modelGlbUrl`·`coachComment`·`calibratedAt` 열). 팀원이 "상태 값과 결과 JSON 형식은 기존 계약 문서 기준"이라고 함. 앱(`fetchJob`)·서버·e2e가 소문자로 맞물려 있어 대문자로 바꾸면 세 곳을 다 바꿔야 함. 추가 필드만 넣었으므로 기존 클라이언트와 호환(앱은 `progressRate`가 없으면 done 100/그 외 0으로 읽음).
- 영향: 백엔드는 저장할 때 소문자를 그대로 저장하거나 대응표로 변환(docs/handoff/teammate_calibration.md 6절, 제안만 — Spring 코드는 손대지 않음). main의 `UserCalibration`에는 `coachComment` 열이 없음(일부 팀원 브랜치에만 있음).
- 버린 안: 서버를 `COMPLETED/FAILED`로 바꾸기 — 계약·앱·테스트 동시 변경, 팀원 방침과 반대.
- 되돌리기: 추가 필드는 무시해도 됨. 커밋 revert.

### F2. worker가 죽어도 작업이 `running`에 남지 않게: 조회 시 감시(watchdog) + 30분 기한
- 결정: `fit_body.spawn`의 call id를 `state/call/{jobId}`에 저장(작업 기록과 다른 키라 worker 쓰기와 경쟁 없음). 조회 때 `queued/running`이면 (a) 접수 후 30분(`service.JOB_DEADLINE_SECONDS`, fit_body 15분 제한 + 대기·cold start 여유) 지나면 `failed timeout`, (b) `modal.FunctionCall.get(timeout=0)`가 끝난 호출을 알리면 `FunctionTimeoutError → timeout`, 그 밖의 예외 → `internal_error`. worker는 시작할 때와 끝낼 때 기록이 `failed`면 덮어쓰지 않는다. `retries=0` 명시.
- 근거: worker 안의 예외는 이미 `failed`로 기록됐지만 OOM·컨테이너 중단·Modal 제한 시간은 except를 건너뜀. Modal 1.6.1 실측: 실행 중 호출의 `get(timeout=0)`은 **builtin `TimeoutError`**를 던짐(`modal.exception.TimeoutError`가 아님) — 처음 배포에서 이 차이로 모든 작업이 즉시 `internal_error`가 됐고 e2e로 잡아 고침(테스트 `tests/test_modal_app.py`).
- 검증: pytest(충돌한 worker, 기한 초과 뒤 늦게 끝난 worker, 끝난 작업은 감시 무시), 배포 e2e 성공·실패 경로.
- 버린 안: 기한만 쓰기 — 컨테이너가 죽은 경우 앱이 30분 기다림. Modal 호출 상태만 쓰기 — 상태 저장(R2) 실패처럼 호출은 끝났는데 기록이 없는 경우 외에 큐에서 사라진 호출을 못 잡음.
- 되돌리기: `create_app(call_failure=...)` 기본값(None 반환)으로 두면 기한만 동작.

### F3. 스텁·가짜 결과는 `done`이 될 수 없다
- 결정: `worker.stub_fit` 삭제, `build_result`는 항상 `stub: false`이고 β·관절 필수. `worker.require_real`이 `stub is not False`, β 10개 유한수 아님, 뼈 길이 없음/범위 밖(0~200cm)이면 `failed internal_error`. 앱 `fetchJob`도 `stub != false` 또는 `smplBeta`/`boneLengthData` 없는 `done`을 오류로 처리.
- 검증: pytest 3가지 가짜 결과 → failed·결과 파일 없음, flutter 테스트 "a stub result is never accepted as done".

### F4. β≈0의 원인과 수정: 재투영 보정에서 β를 움직이지 않는다 (`refine_beta=False`)
- 원인(측정): 재투영 보정의 β 사전항 `1e-3·‖β‖²`가 데이터항(키로 정규화한 관절 오차의 Huber, 관절당 약 1e-5)보다 두 자릿수 커서 300 step 동안 β가 0으로 끌려감. MHR→SMPL 변환기 β는 |β| 최대 2.3인데 보정 후 β2~β9가 ±0.1 안쪽. 또 지금까지의 두 결과는 모두 키 170cm 입력이라 β1(키 방향)까지 같았음 → "사람이 달라도 β≈0".
- 평가: People Snapshot 24개 영상(12명) + 앱 캡처 엔진으로 만든 묶음 2개(같은 사람). 기준은 데이터셋의 consensus 메시(SMPL 위상, 옷 offset 포함 — **정답 아님**)에 `J_regressor_h36m`. 지표 = 팔다리 12개 구간 길이의 평균 절대 % 오차(입력 키 = consensus 메시 키). "키만" = 평균 체형을 같은 키로 맞춘 것(사진 정보 0). 사람 단위로 나눔(조율 6명 / 보류 6명; 고른 것은 변형 하나뿐).

| 변형 | 조율 (13묶음) | 보류 (13묶음) | 전체 | 재투영 px | fit 초 |
| --- | --- | --- | --- | --- | --- |
| 키만 (사진 없음) | 6.02 | 4.25 | 5.13 | - | - |
| 이전 (β 사전 1e-3, β 보정) | 5.75 | 4.16 | 4.96 | 5.22 | 14.3 |
| β 사전 1e-5 | 3.88 | 3.17 | 3.53 | 4.96 | 13.7 |
| **변환기 β 유지 (채택)** | **3.13** | **2.83** | **2.98** | 5.60 | 13.7 |

- 해석: 이전 방식은 "키만"과 거의 같았다(사진이 체형에 기여 안 함). 변환기 β를 쓰면 보류 세트 오차 4.16→2.83%. 재투영 오차는 0.4px 늘지만(β를 2D에 맞추지 않으므로) 길이 정확도가 목적. 같은 사람 다른 옷(남1·남2·남3)의 허벅지 길이 사람 내 표준편차 0.92cm < 사람 간 2.10cm. 앱 RTMPose 키포인트 묶음과 데이터셋 OpenPose 키포인트 묶음의 결과 차이 0.04~0.1%p.
- 한계(추정): 기준 메시 키가 단안 추정이라 일부(male-5-sport 140cm)는 틀림 → 그 묶음 오차가 큼(≈10%). β10이 사람마다 ≈+2로 일정한 것은 MHR→SMPL 변환의 계통 치우침으로 보임. 실제 사용자 실측(줄자) 검증은 안 함.
- 버린 안: β 사전 1e-5 — 변환기 β 유지보다 나쁨. 실루엣/마스크 손실 — Sapiens2 금지, 다른 분할 모델 도입은 라이선스·비용 검토 필요(후속).
- 되돌리기: `fitting.Fitter(refine_beta=True)`.
- 재현: `scripts/build_people_snapshot_calibration_bundles.py` → `modal run server/calibration_modal/eval_fit.py --bundles <dir>`.

### F5. GLB: 서버에서 만들고 R2 presigned GET(1시간)으로 본인에게만
- 결정: fitting이 정면 사진의 자세(전역 회전 0, 키 반영 β)로 SMPL 메시를 만들어 glTF binary로 `models/{jobId}.glb`에 저장. 조회 때마다 1시간짜리 presigned GET을 `result.modelGlbUrl`로 붙임(키를 짧게 해 URL 약 410자 ≤ 백엔드 열 500자). 앱의 `CALIBRATION_STORAGE_HOSTS`와 같은 호스트.
- 라이선스: SMPL 모델 라이선스 https://smpl.is.tue.mpg.de/modellicense.html — "License Grant": 비상업 연구·교육·예술 목적만, 상업 제품·서비스·상업용 산출물 금지. "No Distribution": 모델 복사·배포 금지. 결과물(메시)에 대한 별도 조항 없음. → 모델 파일(v_template, shapedirs)은 배포하지 않고, 사용자 한 명의 메시만 본인에게 비상업(캡스톤) 용도로 제공. 상업화 땐 Meshcapade 상업 라이선스 필요. SAM 3D Body: SAM License(https://github.com/facebookresearch/sam-3d-body/blob/main/LICENSE, 1.a 상업 사용 가능, 1.b.v 군사 등 금지, 1.b.i 재배포 시 약관 사본). MHR: Apache-2.0(https://github.com/facebookresearch/MHR/blob/main/LICENSE). People Snapshot은 F8.
- 버린 안: 앱에서 β로 메시 생성 — SMPL 모델을 앱에 넣어야 해 "No Distribution" 위반. 영구 공개 URL — 비공개 버킷 원칙 위반.

### F6. 운동 3D 분석에 캘리브레이션 뼈 길이 연결은 보류
- 결정: 이번 트랙에서 연결하지 않는다. `BoneLengthConstraint`(Swift)·`bone_lengths.py`는 이미 `result`/`boneLengthData`를 읽을 수 있음(`BoneLengthConstraint.loadTargets`).
- 근거: 라이브 카메라에서 3D가 꺼져 있음(`enableMotion3DForCamera = false`, 트랙 D 소유). 이전 측정에서 길이를 고정해도 방향은 모델 출력 그대로라 관절각이 좋아진다는 근거가 없음(pose_feedback/geometry/README.md). 효과를 재지 못하는 변경을 3D 트랙 파일에 넣으면 병합 충돌만 늘어남.
- 다음 단계: 트랙 D가 3D를 켤 때, Flutter가 `done` 결과의 `boneLengthData`를 네이티브에 넘기고 selected3D → 뼈 길이 고정 → 무릎 차단 순서로 연결, 각도 오차 전후 비교.

### F7. 2D 뼈대를 돌리는 임시 결과 화면 → 실제 결과(관절 3D) 화면은 브랜치에만
- `lib/features/onboarding/screens/onboarding_result_screen.dart`는 팀원(Jinjeonz) 코드. 실제 `jointsH36m`을 드래그로 회전해 그리는 화면과 라우터 `extra` 전달을 브랜치 `ai/calibration-result-screen`에 준비하고 integration/ai에는 합치지 않음(사용자·팀원 승인 필요). GLB 렌더는 웹뷰 패키지(model_viewer_plus 등) 추가가 필요해 보류, 관절 3D로 충분히 "실제 결과".
- integration/ai에는 우리 코드인 분석 화면(대부분 06-month 작성)의 polling·진행률·실패 문구·결과 요약만 반영.

### F8. People Snapshot(평가 데이터) 라이선스와 업로드 정리
- 라이선스 원문: https://graphics.tu-bs.de/people-snapshot 의 "Dataset" 절(사이트는 2026-10-10 서버 오류, Wayback 사본 https://web.archive.org/web/20231203010136/https://graphics.tu-bs.de/people-snapshot 에서 확인). 요지: 비독점·양도 불가; "download the Dataset and use it on computers owned, leased or otherwise controlled by you and/or your organisation"; 비상업 연구·교육·예술 목적만; "Without prior written approval from the authors, the Dataset, in whole or in part, shall not be further distributed, published, copied, or disseminated in any way or form whatsoever"; 논문 인용 의무(Alldieck et al., CVPR 2018). 우리가 받은 HF 미러(gqy2468/People-Snapshot)에는 라이선스 파일이 없었지만 원 데이터셋 조건을 따른다.
- 판단: 캡스톤 평가는 비상업 연구·교육. 로컬(scratchpad)·Modal 컨테이너(임대 컴퓨팅)·R2(임대 저장소)에서의 처리는 "leased or otherwise controlled" 범위로 볼 수 있으나 **애매함 → 사용자 확인 필요**.
- 조치(2026-10-11): (1) git에는 데이터셋 사진·프레임·메시·키포인트·개별 측정값을 넣지 않음(스크립트·집계 수치만; 인계 문서의 결과 예시는 꾸민 값으로 교체). (2) 이 트랙 e2e가 R2에 올린 객체(테스트 사용자 3명의 사진·manifest·결과 JSON·GLB·상태, 44개)를 삭제. (3) `eval_fit.py`의 임시 앱은 사진을 함수 인자로만 넘겼고 우리 쪽 저장(Volume·R2)은 없음; Modal 내부의 일시적 입력 보관은 우리가 지울 수 없음. (4) R2에 남은 `calibrations/999999`, `results/999999`(이전 세션의 e2e 사용자, 더미 영상 사진 추정)는 이 트랙이 만든 것이 아니라 지우지 않았음 → 사용자 결정. (5) 로컬 압축 해제본·묶음은 트랙 종료 때 삭제.
- 앞으로: 실제 사용자 영상(본인 동의) 또는 라이선스가 분명한 데이터로 같은 평가를 다시 하는 것이 맞다.
