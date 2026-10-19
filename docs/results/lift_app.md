# 실시간 3D AI PT — 앱 통합·평가·속도 (ai/lift-app)

기준: integration/ai `c113150`. 계획·운동별 명세: [lift_app_plan.md](lift_app_plan.md). 모델 정확도 비교(2D vs 3D 지표, 원래 vs Fit3D XS, COCO17 vs Halpe26)는 ai/lift-compare 담당 — 여기서는 앱 경로 통합·종단 평가·지연만 다룬다.
**이 브랜치 한정 변경**(병합 전 사용자 승인 필요): `enableMotion3DForCamera = true`, `motionagformer_xs.mlpackage`(원래 H36M XS, 4.9 MB) Runner 번들 포함, 3D 경로에서 손 분기를 모든 운동에 켬. integration/ai의 기본값은 그대로다.

<!--RESULTS-->

## Q1. 3D 리프팅이 앱에 없던 이유 (증거)
- **처음부터 카메라 경로에 3D 실행 코드가 없었다.** `enableMotion3DForCamera = false`는 첫 네이티브 카메라 커밋 `a949023`(2026-06-03, 06-month)에서 이미 false였고, 쓰임은 로그 한 줄뿐(CameraPosePreview.swift:19, :352). `git log --all -G 'enableMotion3DForCamera *= *true'` 결과 없음 — 어느 브랜치에서도 true였던 적이 없다. MotionAGFormer mlpackage는 어떤 커밋에도 Runner에 들어간 적이 없다(`assets/coreml/`은 gitignore).
- Swift 3D 실행 코드는 앱 밖에만 있었다: `tools/ios_coreml_pose_minimal`(e5397d4, 2026-08-17, README "does not integrate MotionAGFormer into the app"), `tools/ios_live3d_cost`(450be2c), `tools/pose_model_bench/Host/PipelineBench.swift`(17d1363, 인과 창 lookahead 0), pose-replay `lift3D`(오프라인, 미래 프레임 사용).
- **꺼 둔 결정은 모두 에이전트 결정이다**: D-D-02(“라이브 카메라 3D는 계속 끈다, 3D 지표는 경고에 쓰지 않는다”, 근거 = D-D-01 측면 2D가 같거나 더 정확·사선 3D도 오차 7–19°, 코드·모델 없음, 5프레임 정렬 작업, “얻는 정확도가 없다”), D-D-05(+17 ms), D-D-06/07(미세조정 XS는 “앱에 아직 안 넣음”), D-C-06(기기 전체 파이프라인에서 3D −40% FPS), D-D-08(ai/smpl-train에만, “라이브 3D는 계속 끔”).
- **사용자는 3D를 끄라고 한 적이 없다.** 두 프로젝트 대화 기록의 사람 메시지 218개(도구 결과·시스템·서브에이전트 제외)를 검사:
  - 2026-09-02 “그냥 앱 자체가 3d로 바로 나오게 할거란말야 제발”, “이미지 -> RTMPose -> MotionAGFormer -> 3D Pose 이게 되어야하는거아니야?”
  - 2026-09-19 “일단반드시 motionagformer가 돌아가야하는데 혹시 왜 안돌아가게 해놨는지 기록되어있어?”
  - 2026-10-09 (D-12 승인) “2D/3D 둘 다 지표를 계산해서 로그로 남기고, 경고 발동은 일단 2D 기준으로. 3D 전환은 테스트 영상 비교 후 결정.” / “푸쉬업은 3D 지표 판정 제외(2D만)” — 경고 발동 기준을 2D로 둔 것은 사용자 지시(조건부·임시), 3D 실행 자체를 끄라는 지시는 아님.
  - 2026-10-10 위임 브리프 트랙 D: “이득이 확인되면 실시간 3D를 켜고 …” — 조건부 지시를 에이전트가 “이득 없음”으로 판정해 끈 채로 둠.
  - 2026-10-19 “3D 자체를 다시 제거하지 마”, “MotionAGFormer-XS는 반드시 실제 앱에서 실행한다 … 3D Lifting을 제거하거나 비활성화하지 마라.”
- D-D-05 “+17 ms”는 `tools/ios_live3d_cost/Bench.swift`의 무작위 텐서(`Float.random(in: -1...1)`, :17–29)로 모델 추론만(`rtm.prediction`, `mag.prediction`, :35–36) 잰 값 — 카메라·전처리·crop·디코딩·평가기·손 분기 없음(코드로 확인).

## Q2–Q6 조사 요약
lift_app_plan.md (a)절: 3D 코드 재고(a2), 키 목록·2D/3D 구분(a3), 2D 전용 기능(a4), Fit3D 미세조정 XS 검증 범위(a5), 남은 일(a6), 손 분기(a7).
추가로 확인한 것:
- **Fit3D 미세조정 XS를 앱에 쓸 수 있나**: D-D-06/07 체크포인트는 측정 후 삭제(“체크포인트 모두 측정 후 삭제”). 남은 것은 D-D-08 변형 d(`Home:~/models/bpt-smpl-train/d.pth`, sha256 `04f08ecc…39c2`, FiLM 뼈 길이 조건 입력 `forward(x, c)`) — 앱의 단일 입력 [1,27,17,3] 모델과 입출력이 다르고 Core ML 변환본이 없다. 모든 Core ML 패키지는 원래 H36M XS(입력 `input_2d_sequence` [1,27,17,3] fp32, 출력 `pred_3d_sequence` [1,27,17,3] fp16, weight.bin sha256 `37a5c834…`, 체크포인트 `motionagformer-xs-h36m.pth.tr` sha256 `7abb32ea…4597`). **이 브랜치는 원래 XS만 쓴다.** 라이선스: MotionAGFormer Apache-2.0; Fit3D는 비상업·단일 사용자·양도/재배포 금지 → Fit3D로 학습한 가중치를 앱에 넣어 배포하면 재배포에 해당할 수 있어 캡스톤 시연 밖에서는 쓸 수 없을 가능성이 큼(판단은 사용자 몫, 여기서는 결정하지 않음). D-D-08 d는 SMPL 유래 조건(비상업)도 포함.
- **틀린 자세 라벨**: “라벨 없음”은 Fit3D·Exercise3D에 대해서만 맞다. 공개 데이터 Mendeley 7운동 멀티뷰(“Good/Bad Form Labels”, CC BY 4.0)는 데이터셋 저자가 단 good/bad 클립 라벨이 있고, 키 수준 라벨은 AI 2패스 합의(사람 검수 없음, D-DATA-01). 그래서 자세 검출은 “미검증 라벨 기준 검출률·오경보율”까지는 잴 수 있다(아래 결과).

## 구현 (P0)
| 단계 | 파일 | 내용 |
|---|---|---|
| 손목 교체 | MotionAGFormerLive.swift `MotionAGFormerWristSource` ↔ motionagformer_wrist_source.py | 손 crop은 RTMPose 손목 기준 좌우 → 그 쪽 손. 반대 손목에 더 가까우면 버림(reject_crossed), 없으면 RTMPose 손목, 신뢰도는 RTMPose 값. XS 입력 사본만 바꿈(원본 rawCoco17 보존, 2D 평가기는 RTMPose). 같은 이미지로 동기 실행 → 같은 프레임. Halpe26은 앞 17개가 COCO17이라 인덱스 9/10 동일 |
| 27프레임 창 | `MotionAGFormerLive` ↔ `LiveMotionAGFormer` | 과거 프레임만. 프레임 t = 창 [t+L−26, t+L]의 행 26−L(L=5) → t는 L프레임 늦게 자기 2D와 함께 나옴(시간 정렬). 첫 3D는 27번째 실프레임(프레임 26−L)부터, 그 전은 warming_up. 세트 끝 flush = 오프라인 pose-replay와 같은 창(오른쪽 끝 복제) |
| 정규화·매핑 | 기존 `coco17ToH36M17`, `MotionAGFormerInputNormalizer`(D-12 person_crop) | 변경 없음, 세션 단위 추적기 |
| 상태 | `Pose3DState` | warming_up / tracking_lost(관절 ≥0.3이 6개 미만; 15프레임 연속이면 창 초기화) / bad_3d(제약이 많이 움직임) / ok |
| 해부학 제약 | `Pose3DConstraints` ↔ pose3d_constraints.py | 뼈 길이(캘리브레이션 cm → 세션 중앙값(좌우 평균) → 사전 비율) → 무릎 과신전(감지; 보정은 원인 확인 전 끔) → 내각 한계(무릎·팔꿈치 굽힘 ≤155°, 엉덩이 ≥20°, 척추 ≥120°; **임시값**) → 평활 없음. 원출력(raw)·제약 출력 모두 보관, 프레임마다 발동량 기록 |
| 3D 판정 | FormWarnings.swift `measure3D`, `form3DRequired` | 2D와 같은 이름·부호의 지표를 3D로 계산 → 같은 `judge`. 전달 키 = 3D 판정. 렙의 ok 프레임이 50% 미만이면 `3d_unavailable`(키 없음, 2D로 대체 안 함). 2D 판정은 `warnings_2d`로 나란히 |
| 카메라 | CameraPosePreview.swift | XS 로드 실패 시 시작 안 함(2D 대체 없음). 손 → 손목 교체 → `liftQueue`(별도 직렬 큐, 비동기) → 메인에서 평가기. 그림은 2D 즉시, 판정은 L프레임 뒤. endSet 전에 flush. perf 로그에 단계별 ms·입력→판정 지연·judged_fps |
| 브리지·Flutter | `Pose3DBridge.payload`, `NativePose3DStatus` | onPoseUpdate `pose3d` {state, filled, window, usable}. ok가 아니면 화면 상단에 안내(“3D 자세 준비 중 (12/27)”, “사람이 잘 안 보여요 — 자세 판정 멈춤”, “3D 자세 인식이 불안정해요 — 이 구간은 판정 안 함”) |
| pose-replay | main.swift | 같은 스트리밍 경로, `--cadence --constraints --form-source --image-size`, CSV 모드에서도 3D, `<base>_3d.csv`(상태·행·제약량·raw·제약 후 3D) |

평가기·브리지가 상태별로 받는 것:

| 상태 | 평가기 `pose3D` | 3D 자세 지표 | 렙 판정 | Flutter `pose3d` |
|---|---|---|---|---|
| warming_up | nil | 없음 | 렙의 ok 비율 < 50% → 3d_unavailable | state, filled(n/27), usable=false |
| tracking_lost | nil | 없음 | 위와 같음 | usable=false |
| bad_3d | 제약 후 3D(세션 bad_3d 수에만 셈) | 없음 | 위와 같음 | usable=false |
| ok | 제약 후 3D | 계산 | ok ≥ 50% → 3D 판정 | usable=true |

테스트: Swift `MotionAGFormerLiveTests`(가짜 모델 4개 설정·Core ML XS 패리티, 손목 교체 패리티, 상태·시간 정렬, 브리지 상태별), `FormWarningsTests.testForm3DRequiredUses3DAndNeverFallsBackTo2D`, Python `tests/test_live_motionagformer_stream.py`(오프라인 `run_live_motionagformer_sequence`와 워밍업 뒤 프레임 동일 — 이 테스트가 flush 창 부호 버그를 잡음), Dart `native_pose_channel_test`. Core ML 패리티 최대 차 0.0076 crop 단위(fp16 출력 + Python float32 / Swift double 정규화).
