# 자세 판정 규칙의 근거 만들기 — 사전 등록 (ai/rules-calib, 2026-10-20)

이 문서는 **held-out 결과를 보기 전에** 커밋한다. 커밋 뒤에 바꾸는 것은 근거 문장 보강과 오탈자뿐이며, 임계값 규칙·평가 규칙·판정 기준을 바꾸면 그 사실과 이유를 결과 문서에 따로 적는다.

## 0. 범위와 권한
- **실험만 한다.** 앱 기본 임계값, 번들, 병합은 바꾸지 않는다. 새 임계값과 새 규칙은 이름 붙인 설정 뒤에서만 켜진다. 앱에서는 scheme 환경변수 `BPT_RULES=<이름>`, pose-replay에서는 `--rules <이름>`이다. 기본값으로 채택하려면 사용자 승인이 필요하다.
- 새 키는 Flutter 대사가 없어 사용자에게 전달되지 않는다(`keysWithoutFlutterLines`). 설정이 없으면 판정도 하지 않는다. 그래서 기본 동작(울리는 키, 이벤트, praise_good)은 바뀌지 않는다.
- **이미 본 held-out 정보**(정직하게 적어 둔다): `lift_app.md`의 S7·T4 표를 봤다. 이 표는 Fit3D s07–s11에서 기존 규칙 지표의 정상 렙 분포와 발화율, 공개 검증 세트의 기존 키 검출·오경보를 담고 있다. 아래에서 **N**으로 표시한 새 지표의 held-out 값은 보지 않았다. S7 후보 임계값은 held-out(s07–s11)에서 뽑은 값이라 순환적이다. 그래서 이번 도출에는 쓰지 않고 비교용으로만 싣는다.

## 1. 공통 정의
- **3D 좌표**: MotionAGFormer-XS 출력 H36M17. 0 골반, 1/4 오른/왼 엉덩이, 2/5 무릎, 3/6 발목, 8 흉곽, 10 머리(두 눈 중점), 11/14 왼/오른 어깨, 12/15 팔꿈치, 13/16 손목. y는 아래, 골반 기준, crop 단위다. 그래서 비율과 각도만 쓴다.
- **위 방향 u**: 카메라 −y. 폰을 세로로 세워 두고 `setup_phone_upright`를 통과했다는 전제다. 중력 매핑(`BPT_3D_GRAVITY`)은 기기에서 검증되지 않아 기본 정의에 쓰지 않는다. Fit3D에서는 실제 중력(카메라 외부 파라미터)으로 같은 지표를 다시 재서 카메라-위와 실제 중력의 차이를 지표마다 보고한다. 이 차이로 R1에 `BPT_3D_GRAVITY`가 필요한지 판단한다.
- **좌표 보조량**:
  - 몸통 t = j8 − j0, 몸통 길이 |t|.
  - 좌우 lr = j4 − j1, 앞 f = lr × u, 등쪽 법선 b = −normalize(lr × t).
- **쪽**: 앱과 같다. 2D 신뢰도가 높은 가까운 쪽이고 히스테리시스가 있다.
- **렙 구간**:
  - 공개·Exercise3D·MM-Fit은 앱 2D 상태기계(pose-replay)의 렙이다.
  - Fit3D는 rep_ann이다(S7과 같음).
  - 렙 판정 가능 여부는 앱 규칙 그대로다(렙 프레임의 ≥50%가 ok 또는 partial_3d).
- **시점 게이트**(주 분석 = 앱 그대로):
  - 푸시업: 렙의 front_view_fraction < 0.5일 때만 판정한다.
  - 로우: 세션 측면 게이트(어깨 폭/몸통 0.66, 히스테리시스 0.03, 150프레임 중앙값)가 열렸을 때만 판정한다.
  - 스쿼트: 정면 렙은 무릎 모임만, 그 밖의 렙은 측면 규칙을 본다.
  - 보조 분석은 게이트를 무시한 "전체 시점" 값이고, 시점별로 따로 싣는다.
- **판정 경로**: lift-app과 같다(`form3DRequired`, 3D 판정, 2D 대체 없음). 기존 규칙의 2D 정의는 바꾸지 않는다. 새 규칙(N)은 3D에서만 판정하고, 2D 경로에서는 지표가 없어 울리지 않는다.

## 2. 규칙 — 운동별 지표, 근거, 시점, 필요한 관절, 측정 가능성

측정 가능성: **가능** = 필요한 관절이 있고 정의가 시점에 덜 민감함 / **부분** = 관절은 있으나 측면에서는 깊이축(XS가 가장 부정확)에 의존하거나 대리 관절 / **불가** = 관절이 없음.

### 바벨로우 (사용자 예시 우선: 상체 숙임, 무릎 각, 당기는 모양)
| 키 | 지표(렙) | 정의 | 근거 | 시점·관절 | 측정 |
|---|---|---|---|---|---|
| **N** row_hinge_shallow | torso_mean < T | 렙 평균 몸통 기울기(°, 수직 0, 앞 +) = atan2(t·f̂, t·u) | 벤트오버 로우 = 몸통을 엉덩이에서 굽힌 자세, 등 중립, 바를 가슴으로(Fenwick·Brown·McGill 2009, JSCR 23(2):350–358, 방법). 수치 기준은 문헌에서 확인하지 못함 → 데이터만 | 측면·사선 / 골반·흉곽·엉덩이 | 가능(모델 오차 큼: 원래 XS 몸통(중력) 렙극값 오차 18°) |
| **N** (대안) row_hinge_shallow 몸 기준 | hip_angle_mean > T | 렙 평균 엉덩이 내각(어깨–엉덩이–무릎) | 위와 같음. 중력·카메라 기울기와 무관 | 같음 | 가능 |
| **N** row_knees_locked | knee_max > T | 가까운 쪽 무릎 내각(엉덩이–무릎–발목) 렙 최대 | "무릎은 살짝 굽힌 채"(코칭 서술 — Baechle & Earle *Weight Training: Steps to Success* 발췌라는 검색 요약만 확인, 원문 미확인). 수치는 데이터 | 측면·사선 / 엉덩이·무릎·발목 | 가능 |
| **N** row_knees_bent | knee_min < T | 같은 각 렙 최소(앉아서 당김) | 같음 | 같음 | 가능 |
| **N** row_pull_high / row_pull_low | pull_peak_wrist_trunk > T / < T | 당김 정점(가까운 쪽 elbowBehind 최대 프레임)의 손목을 몸통 축에 사영: ((손목 − j0)·t̂)/|t| (0 = 골반 높이, 1 = 흉곽) | 바를 가슴 아래·윗배로 당김(Fenwick 2009 "pulled the bar to their chest"; 발췌 문헌마다 가슴~윗배로 다름). 바 키포인트 없음 → 손목을 바의 대리로 씀 | 측면·사선 / 손목·골반·흉곽 | 부분(손목 3D 오차 큼: 원래 XS 178 mm, S4) |
| **N** row_uneven_pull | pull_peak_asym > T | 정점에서 \|elbowBehind(왼) − elbowBehind(오)\| (몸통 길이 비) | 좌우 대칭 당김(바벨은 두 손이 묶여 있음). 문헌 수치 없음 | 정면·사선이 유리. 측면은 먼 팔이 가려져 XS가 추정 | 부분 |
| **N** row_elbow_flare | pull_peak_flare > T | 정점 위팔(팔꿈치 − 어깨)과 몸 시상면 사이 각, 바깥 + : asin((a·l̂)/\|a\|), l̂ = 흉곽→그 쪽 어깨를 몸통에 수직으로 만든 단위벡터 | 공개 bad 로우의 AI 관찰 "elbows flared wide (reverse-fly)"; 문헌 수치 없음 | 측면에서는 깊이축 → 정면·사선 유리 | 부분 |
| **N** row_wrist_lead | pull_peak_forearm_tilt > T | 정점 아래팔(손목 − 팔꿈치)의 시상면 기울기 atan2(v·f̂, v·(−u)) (0 = 바닥으로 수직, + = 손목이 앞) | 아래팔을 수직으로 두고 팔꿈치로 당김(코칭 서술, 문헌 수치 없음). **손목 굴곡은 손 키포인트가 없어 측정 불가**(H36M/COCO17 손목 = 관절 중심 하나; MediaPipe 손은 XS 입력 손목 교체에만 씀, 실험적) | 측면·사선 / 팔꿈치·손목 | 부분 |
| **N** row_straight_arm | elbow_min > T | 렙 최소 팔꿈치 내각(팔을 거의 안 굽히고 뒤로 휘두름 = 킥백) | 공개 bad 로우 AI 관찰 "kickback-like"; 벤트오버 로우는 팔꿈치 굽힘으로 당김(Fenwick 2009 방법) | 측면·사선 / 어깨·팔꿈치·손목 | 가능 |
| row_short_pull (기존, 상대) | 기준선 − elbow_behind_max > T | 기존 정의(기준선 = 첫 3렙 중앙값) | — | 측면 | 가능 |
| **N** row_short_pull_abs | elbow_behind_max < T | 정점 팔꿈치가 몸통선 뒤로 간 최대 거리(몸통 길이 비, 절대) | 팔꿈치가 몸통선을 지나지 않음 = 덜 당김(AI 라벨 정의와 같음) | 측면 | 가능 |
| row_torso_swing (기존) | torso_range > T | 렙 안 몸통 기울기 최대 − 최소 | — | 측면 | 가능 |
| row_standing_up (기존, 상대) | 기준선 − torso_mean > T | — | — | 측면 | 가능 |
| row_head_up (기존) | head_dev_change_min < −T | 머리(10, 눈 중점)의 골반–흉곽선 편차 변화 | — | 측면 | 부분(머리 = 눈 중점, 목은 합성) |
| row_shrug (기존, 꺼짐) | — | 귀–어깨 거리(2D만) | — | — | 3D 불가(H36M에 귀 없음). 이번에 평가 안 함 |

### 스쿼트
| 키 | 지표(렙) | 정의 | 근거 | 시점·관절 | 측정 |
|---|---|---|---|---|---|
| squat_shallow (기존, 상대) | knee_min − 기준선 > T | — | — | 측면 | 가능 |
| **N** squat_depth_abs | thigh_incline_min > T | 렙 최소 허벅지 기울기 asin(((무릎 − 엉덩이)·(−u))/\|·\|) (+90 = 섬, 0 = 수평, − = 무릎보다 엉덩이가 낮음) | FMS 깊은 스쿼트 3점 "Femur below horizontal"(Cook·Burton·Hoogenboom 2006, NAJSPT 1(2):62–72). 앱 명세: 절대 깊이는 사용자 옵션일 때만 | 측면·사선 / 엉덩이·무릎, 위 방향 필요 | 가능 |
| **N** squat_torso_lean | torso_minus_tibia_at_bottom > T | 바닥(무릎 최소각) 프레임의 몸통 기울기 − 정강이 기울기(발목→무릎, atan2(s·f̂, s·u)) | FMS 3점 "Upper torso is parallel with tibia or toward vertical"(같은 논문). 차이라서 위 방향 회전(카메라 롤)이 1차로 상쇄된다 | 측면·사선 / 골반·흉곽·무릎·발목 | 가능 |
| squat_knee_valgus (기존) | knee_ankle_gap_ratio_min < T | 골반 좌우축에 사영한 무릎 간격 ÷ 발목 간격, 바닥~상승(KASR = 무릎 최대 굽힘 때 무릎선 ÷ 발목선, 1.0 = 무릎이 발목 바로 위, < 1.0 = 동적 외반; 컷오프 없음, 건강한 여자 선수 36명 드롭 점프 평균 0.76 ± 0.15 — Mizner·Chmielewski·Toepke·Tofte 2012, Clin J Sport Med 22(3):221–227) | FMS 3점 "Knees are aligned over feet" | 정면·사선(측면은 깊이축) | 부분 |
| squat_hips_first (기존) | 몸통 상승 > T 그리고 엉덩이가 어깨보다 빨리 | — | — | 측면 | 가능(높이는 2D) |
| squat_no_lockout (기존) | 세트 최대 − knee_max 또는 hip_angle_max > T | — | — | 측면 | 가능 |
| squat_lean_drift / depth_fade (기존, 추세) | 마지막 3렙 − 처음 3렙 | — | — | 측면 | 가능(Fit3D는 5렙 세트라 못 잼) |
| squat_heel_rise (기존, 꺼짐) | — | Halpe26 2D 발만 | — | — | 3D 불가(H36M에 발 없음). 기본 2D 모델 COCO17에도 발 없음 → 이번에 평가 안 함 |

### 푸시업
| 키 | 지표(렙) | 정의 | 근거 | 시점·관절 | 측정 |
|---|---|---|---|---|---|
| pushup_hip_sag / hip_pike (기존) | hip_dev_max > T / hip_dev_min < −T | 골반의 흉곽–발목중점 선 편차 ÷ 선 길이 | 미 육군 FM 7-22 푸시업: 몸을 일자로 유지, 처지면 무효 렙(Wikipedia 요약으로 확인, 원문 미확인) | 측면 | 가능(원래 XS는 엉덩이를 체계적으로 높게 놓음, S7) |
| pushup_shallow (기존, 상대) | elbow_min − 기준선 > T | — | — | 측면 | 가능 |
| **N** pushup_depth_abs | upper_arm_incline_max < T | 렙 최대 위팔 기울기 asin(((팔꿈치 − 어깨)·u)/\|·\|) (−90 = 팔이 바닥으로 수직, 0 = 위팔 수평) | 미 육군 FM 7-22 "upper arms at least parallel to the ground"; FitnessGram 90° 푸시업(팔꿈치 90°) — 둘 다 2차 출처로만 확인 | 측면 / 어깨·팔꿈치, 위 방향 필요 | 가능 |
| pushup_no_lockout (기존, 상대) | 세트 최대 − elbow_max > T | — | — | 측면 | 가능 |
| **N** pushup_lockout_abs | elbow_max < T | 렙 최대 팔꿈치 내각 | FM 7-22: 위에서 팔을 끝까지 폄(2차 출처) | 측면 | 가능 |
| pushup_head_drop / head_up (기존) | head_dev_change_max > T / min < −T | 머리(10) 편차 변화 | — | 측면 | 부분 |
| pushup_hand_position (기존) | 첫 렙 top 손목 앞뒤 ÷ 팔 길이 | — | — | 측면 | 가능(첫 렙 1개라 n이 작음) |
| pushup_depth_fade (기존, 추세) | — | — | — | 측면 | 가능 |

**측정하지 않는 것**(관절 없음 또는 정의 밖): 허리 굽음(요추 굴곡·둥근 등), 손목 굴곡, 그립 폭, 바 경로(바 키포인트), 뒤꿈치(3D·COCO17), 으쓱(3D). 공개 bad 클립의 AI 관찰 중 "rounded back"은 이 범주라 검출 평가에서 뺀다.

## 3. 데이터와 분할
| 역할 | 데이터 | 쓰는 모델 |
|---|---|---|
| 도출(정상 렙) | Fit3D s03–s05, 앱 2D CSV → XS(PyTorch, Home) | 모캡(참고), **원래 XS만**. C1·C2는 s03–s05로 학습해서 쓰지 않음(조정자 지시) |
| 도출(정상 렙) | 공개 조정 사람(`data/eval_sources/split.csv` tuning): Mendeley good ∧ AI form normal, YouTube intent normal ∧ AI normal(form_status ok) | 원래·C1·C2 |
| 도출(정상 렙) | Exercise3D P1(D-B-01: squat_0000/0001/0003, barbellrow_0000/0002, pushup_0000–0004) | 원래·C1. C2는 P1로 학습해서 쓰지 않음 |
| 평가: 정상 렙 오경보 | Fit3D s07–s11(모캡과 모든 모델, 실제 3D 정답 → 지표 오차도) | 전부 |
| 평가: 정상 렙 오경보 | 공개 held-out 사람의 정상 클립(위와 같은 정의) | 전부 |
| 평가: 정상 렙 오경보 | Exercise3D P2·P3: squat_0002, barbellrow_0001, barbellrow_0003(푸시업 held-out 없음) | 전부 |
| 평가: 검출 | 공개 held-out bad 클립(Mendeley bad, YouTube intent wrong). 키별 라벨 = AI 2패스 합의 키(사람 검수 없음, D-DATA-01) | 전부 |
| 진단만 | MM-Fit 18세트(임계값 도출·판정에 쓰지 않음) | 전부 |

- Fit3D는 Home에서만 다룬다(집계 숫자만 git에 남김). Fit3D·Exercise3D 이미지는 열지 않는다.
- 공개 조정 2D가 빠진 클립(스쿼트 72개 전부, 푸시업 45개)은 held-out 2D와 같은 코드(pose-replay `2ef3ced`, RTMPose-m COCO17 crop)로 채운다.
- Mendeley 로우는 **덤벨** 로우다(바벨 아님). 로우 지표 분포에 변형 차이가 섞인다는 점을 결과에 적는다.
- **AI 'other:' 관찰 → 새 키 매핑**(사전 고정, 두 패스가 모두 같은 범주를 말하면 "합의", 한 패스만이면 "단일"; 주 분석 = 합의):
  - squat_torso_lean ← `forward lean|folds forward|torso folds|chest (drops|folds|pitched|collapsed)|pitches far forward|hip-hinge with chest|torso pitches|leans forward more`
  - row_elbow_flare ← `elbows? flared|reverse-fly`
  - row_straight_arm ← `kickback|swing straight back|swung back past hips with straighter|straighter arms`
- **기존 AI 키 → 비교할 규칙**:
  - row_standing_up(AI 정의: "good보다 훨씬 서 있음") → row_standing_up, row_hinge_shallow
  - squat_shallow → squat_shallow, squat_depth_abs
  - pushup_shallow → pushup_shallow, pushup_depth_abs
  - pushup_no_lockout → pushup_no_lockout, pushup_lockout_abs
  - row_short_pull → row_short_pull, row_short_pull_abs
  - 나머지는 같은 이름의 키로 비교한다.

## 4. 모델
- 원래 XS: `motionagformer-xs-h36m.pth.tr`(Home), Core ML `assets/coreml/motionagformer_xs.mlpackage`(앱 번들 패키지).
- C1: Home `~/bpt-runs/finetune3/xs-C1/xs.pth`, Core ML `coreml-xs-C1/motionagformer_xs_finetune3_C1_NONCOMMERCIAL.mlpackage`. 학습 데이터는 Fit3D s03–s05 R/V이고 **비상업** 라이선스다.
- C2: Home `~/bpt-runs/finetune3/xs-C2/xs.pth`(학습 중). 학습 데이터는 C1의 것에 Exercise3D P1을 더한 것이고 **비상업**이다.
- 앱 경로 설정은 lift-app과 같다: L=5, Pose3DConstraints 기본값(스쿼트만 무릎 반사, 지표별 무효화).
- 실행 위치:
  - Fit3D는 Home PyTorch(CPU)에서 돌린다.
  - 공개·Exercise3D·MM-Fit은 Mac pose-replay(이 브랜치, 모델별 Core ML)에서 돌린다. C1·C2 패키지는 scratch에 복사해 쓰고 끝나면 지운다.
  - Core ML과 PyTorch의 차이는 lift-compare 기록 0.2% 수준이다.

## 5. 임계값 규칙 (사전 등록)
- **모델 M, 규칙 r, 비교량 q**:
  - 위꼬리 규칙(q > T이면 울림): T = max_s P99_s(q).
  - 아래꼬리 규칙(q < T이면 울림): T = min_s P1_s(q).
  - s는 M의 도출 출처 중 판정된 정상 렙이 n_s ≥ 20인 것이다. 출처마다 따로 분위수를 내고, 가장 느슨한 값을 쓴다. 시점·도메인 차이에 덜 흔들리게 하려는 것이다.
- **여유(margin) = 0.** 문헌에서 검증한 최소 의미 차이(MCID)를 찾지 못했다. 확인하지 못한 값(예: "고니오미터 오차 5°")은 쓰지 않는다.
- 기준선·세트 최대를 쓰는 상대 규칙은 judge()가 실제로 비교하는 양에 같은 규칙을 적용한다. 그 양은 q_over_base, q_below_setmax, q_standing_up, q_short_pull이고, 4번째 렙부터 생긴다.
- 모든 출처가 n < 20이면 임계값을 정하지 않는다 → "데이터 없음".
- **문헌 후보**(따로 평가만 하고, 데이터로 조정하지 않음):
  - squat_depth_abs T = 0°(FMS 허벅지 수평 아래)
  - squat_torso_lean T = 0°(FMS 몸통 ≤ 정강이 기울기)
  - pushup_depth_abs T = 0°(FM 7-22 위팔 수평)
  - pushup 팔꿈치 elbow_min > 90°(FitnessGram)
- **비교 대상**: 현재 앱 임계값(`FormWarnings.swift` 기본값), S7 후보(순환적, 원래 XS만).
- 모델별 결과 설정은 `pose_feedback/rules/<이름>.json`이고 Swift 프리셋과 같아야 한다(테스트로 강제). 이름은 `xs_orig_rc1`, `xs_c1_rc1`, `xs_c2_rc1`이다. 모캡 표는 참고용이고 앱 설정이 아니다.

## 6. 평가 규칙 (사전 등록)
- **정상 렙 오경보율** = 판정된 정상 렙 중 규칙이 울린 비율이다. 신뢰 구간은 Wilson 95%다.
  - 목표: 규칙마다 held-out 출처마다(Fit3D s07–s11, 공개 held-out 정상, Exercise3D P2·P3) **≤ 5%**(점추정).
  - Fit3D는 최종 후보당 1번만 계산한다.
- **검출**(공개 held-out bad):
  - 키 라벨 클립 중 판정된 렙이 1개 이상이고 규칙이 1렙 이상 울린 클립의 비율(Wilson CI).
  - 같은 비율을 판정된 렙이 있는 클립만 분모로 해서도 낸다(조건부 검출).
  - 렙 단위 발화율도 낸다.
- **클립 단위 변별(저자 라벨만)**:
  - 같은 운동·시점에서 bad 클립의 발화율과 good 클립의 발화율을 비교한다. 발화 = 그 규칙이 1렙 이상 울림.
  - 한쪽 Fisher 정확 검정을 쓴다.
  - AI 키 라벨 없이 보는 변별이다.
- **안정성**:
  - 시점별: Fit3D 10° 구간, 공개 side/diag/front, Exercise3D 측면(≤40°)/사선.
  - 피험자별: 피험자마다 오경보율과 그 최대값.
- **praise_good 영향**: 판정된 렙 중 아무 키도 안 울린 렙의 비율을 현재 설정과 새 설정에서 비교한다. praise_good은 "아무 키도 안 울림"에 의존한다.
- **판정(규칙마다, 모델마다)**:
  - **근거 있음**: 두 조건을 모두 만족한다.
    - 모든 held-out 출처(n ≥ 20렙)에서 오경보 ≤ 5%.
    - 키 라벨 held-out bad 클립이 5개 이상이고, 그 클립의 발화율이 같은 운동·같은 게이트를 통과한 held-out good 클립의 발화율보다 유의하게 높다(한쪽 Fisher p < 0.05).
    - AI 라벨 기준이라는 단서를 항상 붙인다.
  - **근거 약함**: 다음 중 하나다.
    - 오경보는 목표 안이지만 검출을 보이지 못했다(라벨 클립 < 5개, 또는 p ≥ 0.05).
    - 검출은 보였지만 한 출처에서 오경보가 5%를 넘었다.
  - **데이터 없음 → 끄기 권장**: 다음 중 하나다.
    - 측정 불가.
    - 도출 데이터 n < 20.
    - 두 출처 이상에서 오경보 > 5%.
    - 오경보와 검출 모두 실패.

## 7. 실행 기록
- 실행마다 Home `~/bpt-runs/rules-calib/<run-id>/manifest.json`에 명령, 코드 커밋, 입력·출력 sha256을 남긴다. 앞선 결과는 지우지 않는다.
- 2D·3D 원자료(공개·Exercise3D)는 Home에 보관한다. git에는 집계와 설정만 넣는다.
