# finetune3 — det · 2D · 3D lifting 미세조정 사전 등록 (ai/finetune3)

2026-10-20 · 브랜치 `ai/finetune3`(origin/integration/ai `81da234`에서 분기) · 결정 기록 D-F3-01–03(`docs/decisions.md`)

**이 문서의 판정 규칙은 모두 에이전트(Claude) 제안이며 사용자 승인을 받지 않았다.** 규칙을 "통과"해도 앱 기본값·번들·병합은 바꾸지 않는다. 채택은 사용자가 정한다. 규칙은 검증(held-out) 결과를 보기 **전에** 이 파일로 커밋하고, 검증 데이터는 최종 후보마다 한 번만 본다. 조정(tuning) 데이터로 고른 것은 이 문서 뒤 커밋에서 바꾸지 않는다.

## 0. 데이터 분할 (이미 고정된 것 그대로)
| 데이터 | 학습 | 조정(선택) | 검증(held-out, 최종 후보당 1회) | 등급 |
|---|---|---|---|---|
| Fit3D (모캡, Home만) | s03·s04·s05 | 모델별 아래 | s07–s11 | 진짜 3D 정답, 사선 카메라 56–75°만 |
| Exercise3D (사용자 승인 2026-10-20, D-F3-02) | P1: squat_0000/0001/0003, barbellrow_0000/0002, pushup_0000–0004 | – | P2 squat_0002·barbellrow_0003, P3 barbellrow_0001 | Sapiens2 의사 정답(3D = 삼각측량, 비계량). **정확도 주장 금지**. 푸시업은 검증 피험자 없음 |
| COCO 2017 | train 사람 크롭(정의 유지용 섞기) | 지킴이 1500 크롭(train에서 분리) | val 사람 500명 | 사람 라벨 |
| MM-Fit 18세트 | 안 씀 | – | dev/진단만 | 렙 수만 검증 |
| 공개(Mendeley mv7, YouTube CC) | 안 씀 | tuning 분할 | heldout 분할 | 미검증 라벨 |

## 1. 3D 리프팅 MotionAGFormer-XS (먼저)
**입력 경로 = 앱 그대로**: RTMPose-m COCO17 crop(pose-replay CSV) → `coco17_to_motionagformer_h36m17` → person_crop(`PersonSquareCropTracker`, D-12) → 30 fps, 27프레임 창, 선택 행 26−L(L=5). 레시피 = D-D-06(원래 H36M XS에서 10에폭, AdamW 1e-4 코사인, 배치 16, 좌우 뒤집기, 손실 = MPJPE + 0.5·N-MPJPE + 20·속도). 코드 `scripts/finetune3/xs_data.py`, `xs_train.py`, `xs_eval.py`.

학습 데이터 종류:
- **R** Fit3D 실제 카메라: 앱 경로 CSV(`~/bpt-smpl/replay`, 5운동 × 4캠), 정답 = 모캡.
- **V** Fit3D 가상 카메라: 모캡을 COCO17 정의로 옮긴 3D 점(부위별 3D 오프셋, 조정 피험자 실제 영상으로 맞춤 — `eval_pushup_virtual_side.fit_offsets`를 5운동으로 일반화)을 720×1280 세로 가상 카메라(측면 0° ~ 정면 90° 균등, 높이 0.3–1.6 m, 거리 2.2–4.5 m, f 913 px × 0.85–1.25)로 투영 + **실제 RTMPose 잔차 트랙**(Fit3D 조정 피험자 실제 영상 − 투영, Exercise3D P1 앱 CSV − Sapiens2 2D; 같은 운동군, 가까운 시점 3개 중 하나, 무작위 시작, 좌우 거울 맞춤, 신뢰도 같이). 시퀀스당 4대, deadlift 포함 6운동. 정답 = 그 가상 카메라의 모캡.
- **E** Exercise3D P1: 앱 경로 CSV(reacquire `e3d__cur`), 정답 = canonical_3d를 그 카메라 좌표로. **팔다리 8점(무릎·발목·팔꿈치·손목)만, 자기 무게중심 기준 위치 손실, 가중치 0.5** — 엉덩이·골반·어깨는 모캡과 정의가 달라(D-C-09, lift_compare §4) 학습하지 않는다.

**변경(2026-10-20 17:40, 검증 결과 전 — D-F3-04·05)**: R은 **2D 출처 3가지를 섞는다**: 앱 경로 COCO17(5운동), 실험 A(lift-compare 1단계: 같은 RTMDet-m 상자 + PyTorch RTMPose-m) COCO17과 m Halpe26의 COCO 공유 17점(스쿼트·푸시업·로우). 같은 영상·같은 창 시작은 한 슬롯으로 묶고 에폭마다 출처를 하나 무작위로 뽑는다(에폭 길이는 출처 하나일 때와 같음). 조정 점검(dev, s04)은 Home 다운으로 두 번 끊겨 뺐다 — 대신 det 뒤 GPU가 남으면 R만(V·E 없음)으로 학습한 **C0를 절제 실험으로**(후보 아님) 한 번 평가한다.

**후보** (모두 s03–s05 + 위 데이터, 같은 레시피·시드):
- C1 = R + V (Fit3D만)
- C2 = R + V + E (Fit3D + Exercise3D) — C1과 차이 = Exercise3D의 영향
- 기준선: B0 = 원래 H36M XS, B1 = ft-repro-trains05(D-D-06 재현, s05만 학습; lift-compare). B1이 지금 가장 좋은 앱 입력용 XS.

**조정 점검(검증 전, 판정에 안 씀)**: s03+s05로 R / R+V / R+V+E를 학습해 s04(조정 피험자) 실제 카메라와 s04 가상 격자에서 비교 → V 잡음 모델이 실제 사선 정확도를 해치지 않는지만 본다. 결과로 레시피를 바꾸면 그 사실과 이유를 이 파일 뒤에 따로 적는다(검증 결과를 보기 전).

**판정 규칙(후보마다 따로, Fit3D 검증 s07–s11 = 주 정답)**:
- 측정: (i) 실제 카메라 = lift-app T4 코드(`eval_lift_app_t2t3.py t4`, a03ddd9 기본값: L=5, Pose3DConstraints, 스쿼트·푸시업·로우 60영상), (ii) 가상 격자 = `xs_data.py vgrid`(측면 L/R × 0/20/40/60°, 정면·후면 90°, 높이 0.8 m, 거리 3.0 m, 잡음 없음 / 잡음 시드 0, 5운동), `xs_eval.py`.
- **A. 실제 사선에서 나빠지지 않음** (B1 대비): MPJPE ≤ B1 + 1.0 mm, PA-MPJPE ≤ B1 + 1.0 mm, 렙 극값 오차 중앙값 무릎·엉덩이·팔꿈치·몸통(중력) 각각 ≤ B1 + 1.0°, 운동별(스쿼트·푸시업·로우) MPJPE ≤ B1 + 3.0 mm, 무릎 뒤집힘(θ<−30) 비율·무효 관절 프레임 비율 ≤ B1 + 0.5%p.
- **B. 이득이 있음** (둘 중 하나): (i) 실제 사선 MPJPE ≤ B1 − 2.0 mm, 또는 (ii) 가상 격자 잡음 있음 측면(≤40°) MPJPE ≤ B1 − 5.0 mm 이고 같은 칸 무릎·팔꿈치 렙 극값 중앙값 ≤ B1.
- **C. 정상 렙 오경보가 늘지 않음**: T4의 현재 앱 임계값 기준, 키별 오경보 비율 ≤ B1 + 5%p, 모든 키 합 ≤ B1 합.
- **A′. Halpe26 입력에서도 나빠지지 않음**(D-F3-05, 2D가 Halpe26로 바뀔 수 있음): 실험 A Halpe26 공유 17점 입력(s07–s11 60영상)에서 MPJPE ≤ B1(같은 입력) + 1.0 mm, 무릎·팔꿈치 렙 극값 중앙값 ≤ B1 + 1.0°.
- **D. Core ML**: 원래 XS와 같은 변환 경로(`export_motionagformer_xs_coreml.py`, coreml_safe, fp16)로 변환되고, PyTorch 대비 선택 행 관절 거리 평균 ÷ 관절 퍼짐이 computeUnits ALL ≤ 0.5%, CPU_ONLY ≤ 1.0%(lift-compare 방식, Exercise3D 앱 2D 창 400개).
- A·B·C·D를 모두 만족하면 "통과(앱 후보로 추천 가능)". 통과는 채택이 아니다.
- **C1·C2 둘 다 통과하면** C1을 추천한다(라이선스 미해결 항목이 적음: Fit3D만). 단 C2가 C1보다 실제 사선 MPJPE ≥ 2.0 mm 또는 가상 측면 MPJPE ≥ 5.0 mm 낫다면 C2를 추천한다. **Exercise3D 수치로는 고르지 않는다**(C2는 Exercise3D 라벨로 학습해 독립적이지 않다).
- 보고만(판정에 안 씀): Exercise3D P2·P3 측면·사선·정면(의사 정답, 상대 비교), 다이아몬드 푸시업·바벨 데드 로우 포함 100영상, 가속도(떨림), 렙 ROM, **입력 출처별**(앱 경로 COCO17 / 실험 A COCO17 / 실험 A Halpe26) 정확도, C0 절제(GPU 여유가 있을 때).
- MediaPipe 손(손목 교체)은 이번 학습·평가에 넣지 않는다(D-F3-06).

### 1.3 C3 — Halpe26 전용 XS (2026-10-20 21:10 추가, D-F3-07 뒤·C3 학습·검증 전에 고정)
- **왜**: 사용자 제품 결정(D-F3-07, C1 T4 결과 뒤)으로 앱 2D가 m Halpe26만 됨 → 제품 경로 입력에 맞춘 XS를 따로 만든다. C1·C2의 사전 등록·판정은 바꾸지 않는다.
- **2D 출처**: 2절에서 선택된 Halpe26 후보가 판정 규칙을 통과하면 그 모델, 아니면 원래 m Halpe26.
  - R: Fit3D s03–s05 실험 A(lift-compare 1단계와 같은 RTMDet 상자)를 그 모델로 다시 뽑은 2D(스쿼트·푸시업·로우 × 4캠).
  - E: Exercise3D P1 앱 경로 CSV(그 모델의 Core ML로 Mac pose-replay; 원래 모델이면 기존 reacquire `cur` CSV), 팔다리 손실 × 0.5.
  - V: 가상 카메라, COCO 정의 오프셋과 잔차 풀을 Halpe26 출처로 다시 맞춤(Fit3D 조정 피험자 실험 A Halpe26 − 오프셋 보정 모캡 투영, Exercise3D P1 Halpe26 앱 CSV − Sapiens2).
- **입력 매핑(학습 전 정의 점검, 조정 피험자만)**: 원래 m Halpe26의 실험 A 예측으로, 합성 관절 골반(0)·흉곽(8)·머리(10)를 (a) 앱 현재 매핑(앞 17점 → 엉덩이 중간·어깨 중간·눈 중간)과 (b) Halpe 고유점(19 hip·18 neck·17 head)으로 만들어 투영 모캡 H36M 점과의 거리(투영 모캡 몸통 길이 단위)를 잰다. **관절마다 거리 중앙값이 더 작은 쪽을 쓴다**(척추 7 = 골반·흉곽 중간, 9 = 코·흉곽 중간은 같은 식으로 다시 만듦). (b)를 하나라도 고르면 앱 Swift 매핑(`coco17ToH36M17`)도 바꿔야 한다 → 결과 문서 G에 적는다(앱 코드는 이 트랙에서 안 고침).
- **레시피**: C1·C2와 같음(10에폭, AdamW 1e-4 코사인, 배치 16, 뒤집기, 시드 0, 간격 R 3·V 6·E 6). 학습 s03–s05 + Exercise3D P1.
- **판정 규칙**: C1·C2의 A–D와 같은 문턱을 **Halpe26 입력**으로 잰다 — 기준 B1(ft-repro-trains05)도 같은 입력(같은 매핑을 쓸 수 없으면 앱 매핑)으로.
  - A·B(i): Fit3D s07–s11 실험 A(선택된 Halpe26 모델의 2D, 원래 RTMDet 상자) 60영상, xs_eval 지표(MPJPE·PA-MPJPE·렙 극값 무릎·엉덩이·팔꿈치·몸통(중력)·운동별 MPJPE). 무릎 뒤집힘·무효 관절은 T4 경로가 아니라서 **측정 안 함**.
  - B(ii): 가상 격자 잡음 있음 측면(≤40°), 잔차 풀만 Halpe26 출처.
  - C(정상 렙 오경보): 앱 매핑을 고른 경우에만 T4(같은 2D를 replay CSV 형식으로 써서)로 잼, 고유점 매핑이면 **측정 안 함**(T4 규칙 코드는 앱 매핑만 지원).
  - D: Core ML 패리티 같은 문턱.
- 보고만: COCO17 입력(기준 행), Exercise3D P2·P3(의사 정답), 종단 E2·E3.

## 2. 2D — RTMPose-m Halpe26 (사용자 D-F3-05, COCO17은 비교 기준)
이전 시도(ai/rtmpose-ft, D-C-08–10, COCO17): 팔다리 8점 학습으로 Fit3D 팔다리 PCK 0.784 → 0.94였지만 COCO 지킴이를 모든 에폭에서 못 넘어 채택 안 함. 동결 해제 D-F3-01. 2026-10-20 17:30 사용자 결정으로 미세조정 대상을 **m Halpe26**(`rtmpose-m_simcc-body7_pt-body7-halpe26_700e-256x192-4d3e73dd`, halpe-decision과 같은 설정)으로 바꿈. 아래 규칙은 결과 전에 고정(17:45).

- **라벨(26점)**: COCO 공유 0–16 + Halpe 17 머리·18 목·19 엉덩이(골반) + 20/21 엄지발가락·22/23 새끼발가락·24/25 발뒤꿈치(좌/우).
  - Fit3D: 팔다리 8점(투영 모캡, D-C-09 검증)만 가중치 1. 어깨·엉덩이·얼굴·머리·목·Halpe 엉덩이는 0(증류가 맡음). **발 6점**: 공식 SMPL-X 맞춤의 발 꼭짓점(smplx 라이브러리의 OpenPose 발 꼭짓점: 왼 5770·5780·8846, 오른 8463·8474·8635)을 투영 — 아래 검증을 통과한 점만 가중치 1.
  - Exercise3D P1: Sapiens2 COCO17(엉덩이 정의 확인됨: 앱 RTMPose 대비 평균 차이 ≤ 0.005 crop 단위) + 발 6점(Sapiens2 big_toe·small_toe·heel), Halpe 17–19는 0.
  - COCO train 크롭: 17점 정답 + **원래 m Halpe26 출력에 대한 증류(SimCC KL, 26점 전부)**.
- **발 라벨 검증(학습 전, 조정 피험자만)**: Fit3D s03–s05 실험 A 프레임에서 SMPL-X 발 점 vs 원래 m Halpe26 발 예측(정의 비교용) — 점 종류별로 거리 중앙값 ≤ 상자 긴 변의 3.5%, 좌우 뒤바뀜 ≤ 0.5%, 발 방향(발뒤꿈치→엄지) 기준 체계적 치우침 ≤ 2% 이면 학습에 넣음. 아니면 그 점은 가중치 0.
- **변형**(조정 데이터로만 고름): h1 증류 + 지도, lr 5e-5·2에폭; h2 같은 것, lr 2e-5·2에폭. 학습 s03·s04 + Exercise3D P1 + COCO 0.5, 조정 s05.
- **선택 규칙(조정)**: COCO 지킴이 body-12 PCK@0.05 ≥ 에폭 0 − 0.005 인 (변형, 에폭) 중 Fit3D s05 팔다리(+검증된 발) PCK@0.05 최고. 없으면 원래 모델(채택 없음).
- **판정 규칙(검증, 선택된 1개만, 기준 = 원래 m Halpe26)**:
  1. Fit3D s07–s11 팔다리 8점 PCK@0.05 ≥ 원래 + 0.02, 팔꿈치·손목·무릎·발목 각각 원래 − 0.01 이상.
  2. 발 6점(라벨 검증 통과한 종류만): Fit3D s07–s11 PCK@0.05가 종류별로 원래 − 0.01 이상(나빠지지 않음).
  3. COCO val2017 500명 body-12 PCK@0.05 ≥ 원래 − 0.005, 얼굴 5점 PCK ≥ 원래 − 0.01.
  4. Fit3D s07–s11 팔다리 좌우 뒤바뀜 ≤ 원래 + 0.2%p, 한쪽 교차 ≤ 원래 + 1%p.
  5. 3D 영향(실험 A, 같은 RTMDet 상자): 원래 XS와 1절의 추천 XS(없으면 B1) 각각 MPJPE ≤ 원래 Halpe26 입력 + 1.0 mm, 무릎·팔꿈치 렙 극값 중앙값 ≤ + 1.0°.
  6. 앱 경로 안전(Mac pose-replay `--model halpe26 --model-path`, Core ML): 가짜 렙 0 유지(흔들림 합성 44, squat_03 2/2, 더미 6), 앱에서 켜진 셋업 키 알람 합계가 원래 Halpe26 이하.
  - 보고만: m COCO17 대비 같은 표, 렙 정확도(P2), Exercise3D P2·P3 PCK(발 포함, 의사 정답), MM-Fit dev 처음 잡기, Core ML 패리티.
- 모두 만족하면 "통과". 통과해도 앱 기본값·번들은 바꾸지 않는다(사용자 승인).

## 3. det — 2D 앞의 사람 검출기
- **검출기 확인**: 파이프라인 실험(eval-reliability 실험 A, reacquire `det` 설정 D-T3-20, lift-compare 실험 A)이 쓴 것은 **RTMDet-m COCO** `rtmdet_m_8xb32-300e_coco_20220719_112220-229f527c`(mmdet 3.3.0, Apache-2.0)의 사람 클래스(점수 ≥ 0.2, 점수×넓이 최대). `pose_feedback/body/yolo26_runner.py`(Ultralytics YOLO, AGPL-3.0)는 2D 포즈 비교 스크립트에만 쓰였다. 앱은 검출기를 돌리지 않는다(D-B-01 crop 추적).
- **정답 상자**: Fit3D SMPL-X 메시(피험자 제공 파라미터, 공식 SMPL-X 모델)를 카메라로 투영한 꼭짓점의 최소·최대(사람 몸 표면 상자, 옷·머리카락 제외). 학습 s03·s04(47운동, 50 fps에서 25프레임마다), 조정 s05, 검증 s07–s11.
- **Exercise3D 상자(2026-10-20 추가, det 결과 보기 전)**: 데이터셋 SMPL 맞춤(smpl_fit.npz, Sapiens2 삼각측량에 맞춘 것 = 의사 정답)의 메시를 그 카메라로 투영한 최소·최대 — Fit3D와 같은 "몸 표면 상자" 정의. 맞춤 관절 vs 삼각측량 거리 중앙값 2.5–8.6 cm, 메시 상자 vs Sapiens2 키포인트 상자 IoU 중앙값 0.65–0.79(메시 쪽이 머리 위·몸 두께만큼 큼). P1(10시퀀스 × 3캠, 30 fps에서 10프레임마다, 2397장)은 학습, P2·P3(660장)은 보고만(판정에 안 씀).
- **학습**: RTMDet-m 사람 미세조정, Fit3D s03·s04 + Exercise3D P1 + COCO train 사람 이미지 6000장 섞기(정의·일반성 유지), 짧은 일정(2에폭, 에폭 선택은 조정 s05로).
- **선택 규칙(조정)**: COCO val2017 사람 AP@[.5:.95] ≥ 원래 − 1.0 인 에폭 중 Fit3D s05 사람 AP 최고. 없으면 원래(채택 없음).
- **판정 규칙(검증, 선택된 1개만)**:
  1. Fit3D s07–s11 사람 상자 AP@[.5:.95] ≥ 원래 + 2.0, AP50 ≥ 원래.
  2. COCO val2017 사람 AP ≥ 원래 − 1.0.
  3. 처음 잡기·재획득(reacquire `det` 설정, Mac pose-replay `--acquire-boxes`): MM-Fit dev 18·Exercise3D 39·공개 heldout에서 늦은 시작 세트 수 ≤ 원래 상자일 때, 가짜 렙 0 유지. **2D는 m Halpe26과 m COCO17 둘 다**(D-F3-05: Halpe26 실패는 처음 잡기 때문), 비교 대상은 원래 RTMDet 상자와 앱 crop 추적(`cur`) — 첫 잠금 프레임·재획득 프레임 수·놓친 뒤 다시 잡음 비율.
- 보고만(판정에 안 씀): Exercise3D P2·P3 상자 AP·파이프라인 선택 상자 적중률(의사 정답, 미세조정 후보는 P1으로 학습해 정의가 같아짐 → 독립적이지 않음).
- 모두 만족하면 "통과". 앱에는 검출기 자체가 없으므로 통과해도 앱 통합은 별도 결정(번들·지연, 기기용은 RTMDet-tiny/nano가 현실적 — 측정 안 함).

## 4. 종단 비교 (D-F3-06, 결과 전 고정)
- 검증 데이터: Fit3D s07–s11(진짜 3D, 사선만) + Exercise3D P2·P3(의사 정답). 같은 지표(MPJPE·PA·떨림·렙 극값 각도·무효 3D)로:
  - E0 원래 det + 원래 2D(COCO17 / Halpe26) + 원래 XS
  - E1 원래 det + 원래 2D + 새 XS
  - E2 원래 det + 새 2D(Halpe26) + 새 XS
  - E3 새 det + 새 2D + 새 XS
  - E4 det 대신 앱 crop 추적: Fit3D는 원래 COCO17만 가능(기존 앱 경로 CSV; Fit3D 영상은 Mac 금지라 새 2D 앱 경로는 **측정 불가**), Exercise3D P2·P3는 Mac pose-replay로 원래·새 2D 모두.
- 새 2D가 통과하면: E2 vs E1로 옛 2D로 학습한 XS가 버티는지 수치로 보이고, 나빠지면(MPJPE +1 mm 초과) 새 2D 출력으로 XS를 같은 레시피로 짧게 다시 학습한다.

## 5. 라이선스 (가중치)
- Fit3D로 학습한 모든 가중치: **비상업**(Fit3D: 비상업·단일 사용자·양도·재배포 금지). git에 안 넣음, Home(`~/bpt-runs/finetune3/`)에만, 파일 이름·체크포인트 note에 NONCOMMERCIAL.
- Exercise3D(E)를 쓴 가중치: 위 + Sapiens2 라이선스의 출력 사용·생체정보 조항이 **미해결**(D-C-01, summary 3·11) — 사용자는 이를 알고 학습을 승인함(D-F3-02).
- SMPL-X 메시 상자(det): SMPL-X 모델 라이선스도 비상업.
- MotionAGFormer·RTMPose·RTMDet 코드·원래 가중치: Apache-2.0.
