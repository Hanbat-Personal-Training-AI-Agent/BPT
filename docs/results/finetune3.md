# finetune3 — det · 2D · 3D 리프팅 미세조정 결과 (ai/finetune3)

2026-10-20 · 사전 등록 [finetune3_plan.md](finetune3_plan.md)(판정 규칙은 에이전트 제안·미승인) · 결정 D-F3-01–03 · 실행 기록 Home `~/bpt-runs/finetune3/<run>/manifest.json`

**이 문서는 실험 결과만 적는다.** 모델 채택, 앱 기본값·번들 변경, 병합은 하지 않았다(사용자 승인 필요).

## 진행 상태와 재개 방법 (2026-10-20 20:35 KST, Home 시계)

**Home에서 무인으로 도는 사슬**(모두 `setsid nohup`, GPU 단계는 `flock ~/.bpt-gpu.lock`, 로그·manifest는 `~/bpt-runs/finetune3/`):
1. `xs_c1_gpu.sh` — C1 검증 평가(T4 끝, xs_eval 진행 중: XS 순전파가 GTX 1060에서 초당 ~150창이라 모델당 ~50분) → **C2를 처음부터 다시 학습**(같은 명령·시드, `_code/e8fd720`) → `xs_chain4.log`에 ALLDONE.
2. `xs_final_waiter.sh` → `xs_final_eval.sh`: ALLDONE 직후 **C2만** T4 + xs_eval(C1·원래·ft-repro는 같은 데이터·코드로 이미 평가함) → `xs-final-t4-heldout-C2/`, `xs-final-xseval-heldout-C2/`.
3. `rtm26_chain.sh`(ALLDONE 대기) → Halpe26 2D h1(lr 5e-5)·h2(lr 2e-5) → `rtm26-h1-lr5e-5/`, `rtm26-h2-lr2e-5/`.
4. `rtm26_post.sh` → 사전 등록 선택 → `rtm26_eval.sh`(검증 1회: Fit3D s07–s11 + SMPL-X 발, COCO val, Exercise3D, 실험 A 2D) → Core ML trace(`coreml-h26ft/`).
5. `det_chain.sh`(2D 끝 대기) → RTMDet-m 미세조정 `det-ft1/` + 조정 평가 `det-tune-eval/` → `det_post.sh` → 선택 → 검증 1회 `det-final-eval/` + 상자(`det-boxes-ft/`: 처음 잡기용 클립, Fit3D s07–s11).
6. `e2e_chain.sh` → 종단 E2·E3(새 2D·새 det → XS) `e2e-fit3d-heldout/`.
- 끊긴 실행은 지우지 않고 이름표: `xs-dev-RV-INTERRUPTED-homeoffline-1527`(Home 재부팅), `xs-dev-RV-STOPPED-1730-xs-moved-to-mac`, `xs-C2-STOPPED-for-C1-eval`, `xs-final-t4-heldout-C1-STOPPED-cpu-too-slow`, `xs-dev-eval-base-ABORTED-cpu-contention`.
- **재개**: 사슬이 멈췄으면 `~/bpt-runs/finetune3/*chain*.log`·`*_post.log`·`xs_c1_gpu.log`로 어디까지 갔는지 보고, 같은 스크립트를 `SHA=<그 스크립트의 코드 스냅숏> setsid nohup ./<script>.sh > <script>.out 2>&1 < /dev/null &`로 다시 띄운다(각 단계는 결과 파일이 있으면 건너뜀). 실행 중인지 볼 때 `pgrep -f`에 스크립트 이름을 쓰지 말 것(자기 명령줄과 겹침 — `ps -eo pid,cmd | grep -E '^ *[0-9]+ /bin/bash ./<name>.sh'`).
- **Mac에서 남은 일**(Home 결과 뒤): C2·2D 후보 Core ML 변환·패리티(`scratchpad/ft3/xs_coreml.sh`, `coreml_rtm_export.py convert`), 앱 경로 실행(`scripts/finetune3/apppath.py`: 2D 후보 `cur`, det 후보 상자 `det`, 흔들림 `sway_ft3.py`), Exercise3D 종단(새 2D CSV → Home에서 XS).

## 0. 데이터와 등급
| 등급 | 데이터 | 쓰임 |
|---|---|---|
| **[Fit3D·verified 3D]** | Fit3D 모캡(H36M17, 카메라 좌표). 학습 s03–s05, 검증 s07–s11(최종 후보당 1회) | 3D 정확도 주장은 여기서만 |
| **[Fit3D·가상 시점·합성 2D]** | 같은 모캡을 가상 카메라(측면~정면)로 투영 + 실제 RTMPose 잔차 트랙 | 측면 일반화 진단(실제 2D 아님) |
| **[E3D·의사 정답]** | Exercise3D(사용자 승인 D-F3-02). 2D = Sapiens2 의사 라벨, 3D = 그 삼각측량(비계량), 상자 = SMPL 맞춤 메시. P1 학습, P2·P3 평가 | 상대 비교만, 정확도 주장 금지. Exercise3D로 학습한 후보에는 독립적이지 않음 |
| 공개(Mendeley·YouTube CC), MM-Fit | 학습 안 함 | 앱 경로 렙·알람 안전 점검(렙 정확도는 P2, 판정에 안 씀) |

- Fit3D는 Home에만 있다(원본·크롭·가중치). 저장소에는 집계 숫자만. Claude는 Fit3D·Exercise3D 프레임을 열지 않았다.
- 푸시업은 Exercise3D 검증 피험자가 없다(P1뿐) → 푸시업 판단은 Fit3D s07–s11에 의존한다.

## 1. 3D 리프팅 MotionAGFormer-XS

### 1.1 방법 (사전 등록 그대로)
- 입력 = 앱 경로: pose-replay RTMPose-m COCO17 crop CSV(2026-10-16 Mac, `~/bpt-smpl/replay`) → 앱 매핑 → person_crop(D-12) → 30 fps, 27프레임 창, 선택 행 21(L=5). 정답 = 모캡(카메라 좌표, 루트 기준, crop 단위, 루트 깊이 약원근).
- 레시피 = D-D-06(원래 H36M XS에서 10에폭, AdamW 1e-4 코사인(스텝 단위), 배치 16, 좌우 뒤집기, MPJPE + 0.5·N-MPJPE + 20·속도). 시드 0.
- 데이터(창 간격): R(Fit3D 실제 카메라, 5운동 × 4캠 × 피험자, 간격 3), V(가상 카메라 4대 × 6운동 × 피험자, 간격 6), E(Exercise3D P1 10시퀀스 × 3캠, 간격 6, 팔다리 8점 무게중심 기준 손실 × 0.5).
- COCO 정의 3D 오프셋(조정 피험자 s03–s05 실제 영상 60개로 최소제곱, 중앙 2D 오차 px 전 → 후): 엉덩이 19.5 → 9.9(몸통 축 −6.2 cm, 안쪽 3.2 cm, 앞 4.2 cm), 어깨 8.0 → 6.4, 무릎 6.8 → 5.3, 발목 7.9 → 5.5, 팔꿈치 6.0 → 4.9, 손목 4.3 → 4.3.
- 잔차 풀: Fit3D 조정 실제 영상 60클립 + Exercise3D P1 30클립(Sapiens2 대비, 관절별 평균 제거). 중앙 크기 crop 한 변의 0.6–1.7%, p90 1.7–5.3%.
- 학습 세트: dev(s03+s05) R 40시퀀스 7,840창, V 48시퀀스; 최종 C1 = R 60 + V 72, C2 = C1 + E 30.

### 1.2 C1 검증 결과 — Fit3D s07–s11 실제 카메라, 앱 경로 COCO17, L=5, a03ddd9 기본 제약 (T4, 1회)
| 모델 | MPJPE | PA-MPJPE | 떨림(가속도) | 무릎 렙 극값 (p90) | 엉덩이 | 팔꿈치 | 몸통(중력) | 무릎 뒤집힘 | 무효 관절 프레임 |
|---|---|---|---|---|---|---|---|---|---|
| 원래 XS (B0) | 144.7 | 87.7 | 8.56 | 17.1 (66) | 12.9 | 9.0 | 18.4 | 0.14% | 0.90% |
| ft-repro-trains05 (B1, D-D-06 재현) | 56.3 | 40.6 | 4.77 | 4.9 (16) | 4.0 | 6.8 | 3.3 | 0 | 0 |
| **C1** (R 혼합 + V, s03–s05) | **53.2** | **37.5** | **4.56** | **4.0 (12)** | **3.1** | 7.0 | 4.5 | 0 | 0 |
- 단위 mm, 각도 °(렙 극값 오차 중앙값), 떨림 = 가속도 오차(mm/프레임²). 운동별 MPJPE(B1 → C1): 스쿼트 53.4 → 53.0, 푸시업 64.8 → **55.7**, 로우 53.0 → 51.4. 몸통(중력) 렙 극값: 스쿼트 3.5 → 5.7, 로우 4.0 → 6.5, 푸시업 3.0 → 2.3.
- 정상 렙 오경보(현재 앱 임계값, B1 → C1): pushup_no_lockout 24 → **2%**, pushup_hand_position 7 → 2%, pushup_hip_pike 23 → 21%, squat_hips_first 1 → 4%, squat_no_lockout 5 → 5%, 로우 키 0 → 0%.
- Core ML(규칙 D): computeUnits ALL 0.25%, CPU_ONLY 0.74% → 통과(패키지는 Home `coreml-xs-C1/`에만, Fit3D 유래·비상업).
- **사전 등록 규칙 A는 불통과**: 몸통(중력) 렙 극값 중앙값 4.5° > B1 + 1.0° = 4.3°. 나머지 A 항목(MPJPE·PA·무릎·엉덩이·팔꿈치·운동별·뒤집힘·무효)은 통과, B(i)(MPJPE ≤ B1 − 2.0 mm = 54.3) 통과, D 통과. A′(Halpe26 입력)·B(ii)(가상 측면)·Exercise3D는 xs_eval이 끝나면 아래에 추가.

## 2. 2D RTMPose-m Halpe26 (D-F3-05)

### 2.1 발 라벨 검증 (학습 전, 사전 등록 기준: 거리 중앙값 ≤ 상자 3.5%, 좌우 뒤바뀜 ≤ 0.5%, 발 방향 치우침 ≤ 2%)
| 라벨 | 비교 대상 | 엄지발가락 | 새끼발가락 | 발뒤꿈치 | 판정 |
|---|---|---|---|---|---|
| Fit3D SMPL-X 발 꼭짓점(smplx OpenPose 발 id, 템플릿 점검 통과) | 원래 m Halpe26, 조정 s03–s05 실험 A 36영상 | 2.5% · 0% · −1.5% | 2.4% · 0.09% · −1.0% | 1.4% · 0.03% · +0.7% | 통과 → 학습에 넣음 |
| Exercise3D Sapiens2 발(big_toe·small_toe·heel) | 원래 m Halpe26 앱 경로, P1 30영상 | 1.9% · 0.16% | 2.0% · 0.03% | 1.9% · 0.08% | 통과 → 학습에 넣음 |
(칸 = 거리 중앙값 ÷ 상자 긴 변 · 좌우 뒤바뀜 · 발 방향 치우침(Fit3D만). 이 표는 라벨 정의가 모델과 맞는지 보는 것이지 정확도가 아니다. 모델의 엄지발가락이 SMPL-X 발끝 꼭짓점보다 상자의 1.5%만큼 뒤에 있다 — 발끝 꼭짓점 정의 차이로 보임(가설).)
- 원래 m Halpe26의 Fit3D 조정 s05 스쿼트 발 PCK@0.05(SMPL-X 정답, 204프레임 스모크): 엄지 0.79, 새끼 0.86, 뒤꿈치 0.99.

### 2.2 방법
- 시작 가중치 = m Halpe26 `4d3e73dd`(sha256 4d3e73dd…dbb90), mmpose 1.3.2, BN 고정, 앱 조건 증강(`--aug app`: 앱 crop 추적기 비율·여유, 흐림·저조도·JPEG).
- 학습: Fit3D s03·s04 크롭(4360 + 4032장, 50 fps에서 5프레임마다, 5운동 × 4캠) 팔다리 8점 + SMPL-X 발 6점, Exercise3D P1 7953장(Sapiens2 COCO17 + 발, 무효 점 0), COCO train 사람 크롭(에폭마다 학습 크롭 수만큼, 풀 22500 / 지킴이 1500) — COCO는 17점 정답 + 원래 m Halpe26 26점 증류(가중치 1). 2에폭, AdamW, OneCycle, 배치 16.
- 변형: h1 lr 5e-5, h2 lr 2e-5. 조정 선택 = 사전 등록(COCO 지킴이 body-12 ≥ 에폭 0 − 0.005 중 Fit3D s05 팔다리+발 PCK 최고).
- Core ML: 원래 m Halpe26을 같은 도구로 변환하면 앱 패키지(`~/bpt-models/rtmpose_m_halpe26_forward.mlpackage`)와 COCO val 100크롭에서 같은 결과(키포인트 차이 중앙값 0.5 px, p99 74.6 px, 최대 255.5 px — **원래 패키지도 1%의 점에서 fp16 argmax가 크게 뒤집힌다**; COCO17 패키지는 p99 2 px).

(결과 대기)

## 3. det RTMDet-m

### 3.1 방법
- 시작 = RTMDet-m COCO `229f527c`(80클래스 머리 그대로, 사람 = 클래스 0), mmdet 3.3.0. 학습 파이프라인 = stock 2단계(모자이크·믹스업 없음, 크기 0.1–2.0, 640 crop, HSV, 뒤집기). AdamW 1e-4(300스텝 워밍업, 코사인), 배치 4, 2에폭, EMA(stock).
- 데이터: Fit3D s03·s04 SMPL-X 메시 상자(47운동 × 4캠, 50 fps에서 25프레임마다 → 학습은 그중 절반), Exercise3D P1 SMPL 맞춤 메시 상자 2397장, COCO train 사람 이미지 6000장(사람 상자만).
- 평가: 사람 AP@[.5:.95]/AP50/AP75(pycocotools, 사람만), 파이프라인 선택 상자(점수 ≥ 0.2 중 점수×넓이 최대)의 IoU ≥ 0.5 / 0.75 적중률·놓침. 조정 = Fit3D s05(4장마다) + COCO val 사람 2693장(지킴이). 처음 잡기 = reacquire `det` 설정을 같은 pose-replay(0d4724c)·같은 클립에서, 앱 crop 추적(`cur`)·원래 RTMDet 상자와 비교.

(결과 대기)

## 4. 도구 확인(결과 전)
- **Core ML 변환 경로**: XS — 원래 XS를 같은 도구(`scripts/finetune3/coreml_xs_export.py` = lift-compare `coreml_ft_export.py`)로 변환하면 PyTorch 대비 선택 행 관절 거리/퍼짐 ALL 0.20%, CPU_ONLY 0.25%(lift-compare 기록과 같음). RTMPose-m — 원래 가중치를 `coreml_rtm_export.py`(trace는 Home, 변환은 Mac)로 변환한 패키지가 앱 패키지(`rtmpose_m_forward.mlpackage`)와 COCO val 100크롭에서 같은 결과(키포인트 차이 중앙값 0 px, p99 2.06 px, 최대 112 px — 최대는 두 패키지 모두 같은 크롭의 fp16 argmax 뒤집힘).
- **Exercise3D SMPL 맞춤의 오차 표기**: `smpl_fit.npz`의 `per_frame_joint_rmse_m`(~5 mm)는 파이프라인(`Exercise3D-Dataset-Pipeline/tools/fit_smpl_sequence.py`)이 `joints × scale ≈ canonical`로 맞춘 뒤 오차에 scale을 곱해(나눠야 함) 약 1/scale² ≈ 18배 작게 적혀 있다. 실제 SMPL 관절 ↔ 삼각측량 거리 중앙값은 2.5–8.6 cm(검증: 우리 재구성으로 미터 = canonical / scale일 때 강체 정렬 = 단위 행렬).
- **학습 전 기준(앱 경로 RTMPose-m vs Sapiens2 라벨, Exercise3D)**: P1 측면 푸시업(cam2·cam3, 10–48°)에서 무릎 하나라도 반대쪽 무릎 라벨에 더 가까운 프레임이 31–100%(라벨상 두 무릎 간격은 몸통 길이의 0.13–0.24), 두 무릎이 모두 바뀐 프레임은 0–10%. 먼 쪽(가려진) 무릎을 가까운 쪽 무릎 근처에 놓는 형태다. 정면(cam1, 70–88°)은 0%. 두 관절 모두 바뀐 비율(엄격 기준)은 스쿼트·로우·P2·P3의 팔꿈치·손목·무릎·발목 모두 0%(한쪽 교차는 푸시업만 계산). P1은 2D 후보의 학습 데이터라 이 칸의 학습 후 값은 독립 평가가 아니다(푸시업 검증 피험자 없음).
