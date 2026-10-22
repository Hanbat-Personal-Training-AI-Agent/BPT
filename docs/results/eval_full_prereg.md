# 새 파이프라인 종합 성능 평가 — 사전 등록 (ai/eval-full)

2026-10-22 12:45 KST. **이 문서는 새 계산을 하나도 하기 전에 커밋한다**(커밋 시각이 증거). 결과는 [eval_full.md](eval_full.md)에 쓴다.
이 평가는 측정만 한다. 모델 채택·앱 기본값·번들·병합은 하지 않는다. 합격/불합격 문턱은 두지 않는다(각 구성요소의 판정은 각 브랜치의 사전 등록이 이미 했다). 여기서 고정하는 것은 **무엇을, 어느 데이터로, 어떤 정의로 비교하는가**다.

## 1. 구성 (configuration)

파이프라인: 카메라 → 사람 det/crop → RTMPose 2D → MotionAGFormer-XS 3D(27프레임, lookahead L) → 3D 제약 → 자세 규칙 → 피드백.

### 1.1 부품 기호
| 기호 | 뜻 | 출처 |
|---|---|---|
| K17 / H26 / H26ft | RTMPose-m COCO17 / RTMPose-m Halpe26(원래) / Halpe26 미세조정 h26ft | main 2b98256 / ai/halpe-default-m2b98256 / ai/finetune3-m2b98256 |
| X0 | 원래 MotionAGFormer-XS(H36M) | 앱 번들 weight.bin `37a5c834…f38e` |
| B1, C1, C2 | Fit3D 미세조정 XS(앱 매핑 `coco17ToH36M17`) | ai/finetune3-m2b98256 |
| C3 | Halpe26 전용 XS(Halpe 고유점 매핑: 골반←19, 흉곽←18, 머리←17) | 〃, 사용자 결정(10-22) "C3를 앱 후보로 진행" |
| C4 | h26ft 출력으로 다시 학습한 Halpe26 전용 XS | 〃 1.4절. 오늘 학습 중. **끝나면 넣고, 끝나지 않으면 "대기"로 표시** |
| Ka | 현재 lift-app 기본 제약(a03ddd9): 뼈 길이(세션 중앙값), 내각 한계, 무릎 뒤집힘 감지, 스쿼트 무릎 반사, **무릎 과신전 고정 없음** | ai/lift-app |
| clamp | 무릎 과신전 −15° 고정 | ai/lift-refine-m2b98256 |
| calib | 사람별 SMPL 캘리브레이션 뼈 길이 목표(`BPT_BONE_TARGETS`, SAM 3D Body → MHR→SMPL, 키 없음) | 〃 |
| K* | Ka + clamp + calib (= lift-refine `all_new`) | 〃 |
| adapt | 적응형 가림 관계 제약(`BPT_ADAPTIVE_3D`, 선택 매개변수 reliable_conf 0.5, decay 135, max_gap 180), K* 뒤에 적용 | ai/setup-constraint-m2b98256 |
| anchor | 푸시업 2D 손목 바닥 고정 v2(`BPT_WRIST_ANCHOR`, r 1.0 아래팔, c 0.1, T 15) | 〃 |
| rot | 가로 촬영 회전 처리(CaptureRotation) | ai/orientation-m2b98256 (기기 시험 빌드 a8b29f1에 포함) |
| R-all / R-6off / R-rc1 | 현재 임계값·현재 전달 키 전부 / 현재 임계값, 시끄러운 6키 전달 끔(squat_no_lockout, squat_knee_valgus, pushup_no_lockout, pushup_hip_pike, pushup_shallow, pushup_head_up) / 모델별 rc1 임계값 | ai/rules-calib |

### 1.2 비교하는 구성
| ID | 구성 | 역할 |
|---|---|---|
| **S0 기존** | main 2b98256: K17, 라이브 3D 꺼짐(2D 규칙만) | 앱 기준선 |
| **S1 3D 기준** | K17 + X0 + Ka, L=5, R-all | 3D 기준선("원래 XS + COCO17 + 새 제약 없음") |
| S2 | H26 + X0 + Ka, L=5, R-all | 2D만 바꾼 단계 |
| **P\* 제안 전체** | H26 + C3 + K*, L=5, R-6off, rot 켬, adapt 끔, anchor 끔 | 제안 파이프라인 |
| Alt-C1 / Alt-C2 / Alt-B1 | H26 + C1 / C2 / B1 + K*, 나머지 P*와 같음 | 다른 XS 후보 |
| Alt-C4 | H26ft + C4 + K*, 나머지 P*와 같음 | C4 끝나면 |
| Alt-L3 | P*에서 L=3 | 지연 대안 |

- adapt·anchor는 각 브랜치 권고("기본 끔", "시험 빌드에서만")를 따라 P*에서 끈다. 절제에서 **하나씩 켜서** 잰다.
- calib을 P*에 넣는 이유: 제품의 캘리브레이션 결과(β·뼈 길이)를 쓰는 경로가 설계 목표다. 실제 앱에서는 아직 연결되지 않았다(D-M-01). 이 한계를 결과에 적는다.

## 2. 절제 축 (P*에서 한 번에 하나만 바꿈)
| 축 | 변형 | 비고 |
|---|---|---|
| A1 2D | H26 → K17 | C3는 Halpe 고유점이 필요해 K17 입력이 정의되지 않는다. 그래서 2D 축은 **C1을 쓴 P*(Alt-C1)**에서 잰다(C1은 COCO17·Halpe26 혼합 학습). X0에서도 같이 잰다(S1 vs S2) |
| A2 XS | C3 → X0 / B1 / C1 / C2 / C4 | 각 모델의 자기 매핑(X0·B1·C1·C2 = 앱 매핑, C3·C4 = Halpe 고유점) |
| A3 | clamp 끔 | |
| A4 | 내각 한계 끔(`angle_limits=()`) | |
| A5 뼈 길이 | 없음(`bone_lengths=False`) / 세션 중앙값 / 모집단 비율(prior) / calib(P*) / 모캡 길이(oracle, **상한, 제품 입력 아님**) | |
| A6 | 제약 전부 끔(raw) | |
| A7 | adapt 켬 | 깨끗한 입력만(합성 가림은 setup-constraint 결과 인용) |
| A8 | anchor 켬(푸시업) | 계산이 어려우면 setup-constraint 10절 값(X0 기준)을 **다른 기준 구성**으로 표시해 인용 |
| A9 | L=5 → L=3 | |
| A10 | rot 끔 | 기기 가로 흉내(90°/270°)에서만 |
| A11 규칙 | R-6off → R-all / R-rc1 | R-rc1은 X0·C1·C2에만 정의됨(C3용 rc1 없음 → "정의 없음") |

## 3. 데이터 분할
| 등급 | 데이터 | 쓰임 |
|---|---|---|
| **헤드라인(정답 3D)** | Fit3D 검증 피험자 s07–s11, 실제 카메라 4대 × 스쿼트·푸시업·바벨로우 = 60영상, 모캡 정답. 미세조정 모델 학습에 안 씀(학습 s03–s05) | 3D 정확도·정상 렙 오경보의 주 숫자 |
| 입력 경로 | Fit3D는 Home 밖으로 못 나가 앱 crop 추적기(Mac pose-replay)를 못 쓴다. 그래서 **실험 A 2D**(RTMDet-m 상자 + PyTorch RTMPose, 30 fps 선택 프레임, lift-compare `A-pose2d-20261019`; h26ft는 finetune3 `c4-data/raw/h26ft`)를 쓴다. 앱 경로 COCO17 CSV(10-16)는 **재현 점검**(lift-refine 표와 같은지)에만 쓴다 | 모든 Fit3D 숫자에 "실험 A 입력" 표기 |
| 의사 정답 | Exercise3D P2·P3(Sapiens2 삼각측량, 비계량). **의사 정답이라 표기**. C2·C3·h26ft는 P1로 학습해 P1 숫자는 쓰지 않는다 | 측면·정면 시점 보조 |
| 과제(렙·경고) | 기기·Mac 재생 Exercise3D 39클립(P1–P3, 의사 정답 렙), Mac 회귀 13케이스(비운동 12), 공개 held-out 정상 렙(rules-calib) | 렙 정확도, 오경보 |
| 개발 전용 | MM-Fit | 헤드라인에 안 씀 |

모든 숫자에는 출처 실행(Home `~/bpt-runs/<트랙>/<run>` 또는 기기 실행 폴더)과 분할을 붙인다. 기존 결과는 **구성과 분할이 정확히 같을 때만** 그대로 인용하고, 다르면 "다른 구성"으로 따로 적는다.

## 4. 지표 (정의는 기존 도구 그대로)
**정확도**(Fit3D, lift-refine `eval_lift_refine.py constraints`·lift-app T4의 정의):
- MPJPE, PA-MPJPE(mm, 루트 기준, 모든 프레임 평균).
- 렙 극값 관절각 오차 중앙값(°, p90): 무릎·엉덩이·팔꿈치·몸통(실제 중력), 가까운 쪽, 정답 렙 구간.
- 떨림 = 가속도 오차(mm/프레임²).
- 무효 관절 프레임 비율(제약 보고서의 invalid_joints), 불가능 각(정의 D) 프레임 비율.
- 무릎 뒤집힘 비율 = XS 원출력에서 무릎 θ < −30°인 다리×프레임 비율.
- 2D 좌우 바뀜 = 예측 왼(오른) 관절이 투영 모캡의 반대쪽 관절에 더 가까운 프레임 비율(한쪽 교차), 무릎·발목·팔꿈치·손목.
- 비교 통계: 영상별 평균의 짝지은 차이, 영상 단위 bootstrap 2000회(시드 0) 95% 신뢰구간. 주 비교는 P* vs S1, P* vs S2, 그리고 각 절제 vs P*.

**과제**:
- 렙 수 정확 클립 수·절대 오차 합(Exercise3D 39클립 기기 / Mac 30+13).
- 정상 렙 오경보율, 키별(judge_py 현재 임계값; Fit3D 렙은 모두 트레이너의 정상 렙으로 본다). 사용자에게 가는 비율 = 전달 키 중 하나라도 울린 렙 비율.
- setup_ready 시점(첫 렙 전 준비 완료 프레임).

**실시간**(iPhone 17, 영상-카메라 모드):
- 단계별(2D+손, lift3d) p50/p95, 도착→판정·도착→Flutter p50/p95, 처리 FPS, 드롭, 발열 상태, 배터리, ANE 사용.

## 5. 계산 계획(무엇을 새로 계산하나)
- Home CPU(4스레드, nice 10, GPU 잠금 안 씀 — C4 학습 중): 새 스크립트 `scripts/eval_full/fit3d_ablate.py`. lift-refine 코드 스냅숏(195c0f4)의 함수·정의를 그대로 쓰고, 입력만 실험 A 2D로 바꾼다(finetune3 `t4_halpe.py`와 같은 방식). XS 원출력은 (모델, 입력) 한 번만 계산하고 모든 제약 변형을 같은 행에 건다.
  - 재현 점검: X0 + 앱 경로 COCO17 CSV에서 Ka·clamp·calib가 lift-refine 5.1b 표(144.73 / 87.74 …)와 같아야 한다. 다르면 원인을 찾기 전에는 새 숫자를 쓰지 않는다.
- Mac: C3·X0 Core ML 패키지 연산 그래프 비교(같은 그래프면 기기 지연은 가중치와 무관 → X0 기기 측정값을 C3에 쓴다; **추론이지 직접 측정이 아님**을 적는다).
- 기존 결과 인용: 기기(lift_app_device.md, halpe_default.md), Exercise3D xs_eval(finetune3), rules-calib 표, setup-constraint 판정, orientation.

## 6. 기기 실행 요청 (기기 에이전트가 실행; 이 에이전트는 폰을 쓰지 않음)
빌드: 이미 설치된 시험 빌드 `a8b29f1`(Runner SHA256 `674a755e…e2adb`; m COCO17·m Halpe26 둘 다, 원래 XS, clamp 포함, 회전 처리 포함). **새 빌드·새 설치 없음.** 영상-카메라 모드, 반전, 목표 렙 = 정답, 음성 0, `BPT_PERF_LOG=1`.
클립 4개: `barbellrow_0000_cam2`, `pushup_0003_cam2`, `squat_0001_cam2`(측면 3), `pushup_0004_cam1`(정면, 무거움).

| # | 구성 | 환경 변수 | 클립 × 반복 | 예상 시간 |
|---|---|---|---|---|
| D1 | S0 기존(2D만) | `BPT_POSE_MODEL=mcoco17 BPT_CAMERA_3D=0` | 4 × 2 | ~9분 |
| D2 | S1 3D 기준 | `BPT_POSE_MODEL=mcoco17` | 4 × 2 | ~9분 |
| D3 | P* 근사(H26 + X0 + clamp + calib) | 기본(mhalpe26) + `BPT_BONE_TARGETS=<P별 json>` | 4 × 2 | ~9분 |
| D4 | Alt-L3 | D3 + `BPT_3D_LOOKAHEAD=3` | 4 × 2 | ~9분 |
| D5 | 회전 처리 끔/켬(A10) | `BPT_CAMERA_VIDEO_ROTATE=90`, `BPT_FORCE_CAPTURE_ROTATION=0` vs `=90` | `pushup_0001_cam2`, `pushup_0004_cam2` × 2 | ~5분 |
| D6 | 〃 270° | `ROTATE=270`, `FORCE=0` vs `=270` | `pushup_0000_cam3`, `pushup_0001_cam3` × 2 | ~5분 |
| D7 | 30분 발열·배터리, P* 근사 | D3 + `BPT_CAMERA_VIDEO_LOOPS`로 squat_0001_cam2 반복, 전원 뺌 | 1 × 31분 | ~33분 |

- 순서: D1–D4는 클립마다 D1→D2→D3→D4로 번갈아(발열 영향 분산), 그다음 D5·D6, 마지막 D7. 합계 약 80분(재실행 여유 포함 90분 이내).
- 각 실행에서 필요한 것: perf 로그(초별 FPS·드롭·lift3d·2D+손·발열·배터리), 실행 로그의 도착→판정·도착→Flutter, 렙, 보낸 키, manifest(SHA).
- 하지 않는 것: C3 가중치 기기 실행(앱 매핑 코드 변경 필요 → 측정만 하는 이 작업 범위 밖), adapt·anchor·setup_ready(a8b29f1에 없음 → setup-constraint 시험 빌드가 필요, 미측정으로 남김), xctrace ANE(USB 필요).

## 7. 보고 규칙
- 주 표 1개(S0, S1, S2, P*, 주요 대안) + 절제 표 + 실시간 표.
- 의사 정답·실험 A 입력·다른 구성 인용은 칸마다 표시. 측정하지 않은 칸은 "미측정"/"대기"로 두고 다른 값으로 메우지 않는다.
- 결과를 본 뒤 구성·지표 정의를 바꾸면 eval_full.md에 "사후 변경"으로 적고 이 문서는 고치지 않는다.
- 한계: 사람이 라벨한 틀린 자세 데이터 없음, 의사 정답, 측면 모캡 없음(Fit3D 40–90°), C1 몸통 치우침.
