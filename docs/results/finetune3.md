# finetune3 — det · 2D · 3D 리프팅 미세조정 결과 (ai/finetune3)

2026-10-20 · 사전 등록 [finetune3_plan.md](finetune3_plan.md)(판정 규칙은 에이전트 제안·미승인) · 결정 D-F3-01–03 · 실행 기록 Home `~/bpt-runs/finetune3/<run>/manifest.json`

**이 문서는 실험 결과만 적는다.** 모델 채택, 앱 기본값·번들 변경, 병합은 하지 않았다(사용자 승인 필요).

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
(결과 대기)

## 2. 2D RTMPose-m COCO17
(결과 대기)

## 3. det RTMDet-m
(결과 대기)

## 4. 도구 확인(결과 전)
- **Core ML 변환 경로**: XS — 원래 XS를 같은 도구(`scripts/finetune3/coreml_xs_export.py` = lift-compare `coreml_ft_export.py`)로 변환하면 PyTorch 대비 선택 행 관절 거리/퍼짐 ALL 0.20%, CPU_ONLY 0.25%(lift-compare 기록과 같음). RTMPose-m — 원래 가중치를 `coreml_rtm_export.py`(trace는 Home, 변환은 Mac)로 변환한 패키지가 앱 패키지(`rtmpose_m_forward.mlpackage`)와 COCO val 100크롭에서 같은 결과(키포인트 차이 중앙값 0 px, p99 2.06 px, 최대 112 px — 최대는 두 패키지 모두 같은 크롭의 fp16 argmax 뒤집힘).
- **Exercise3D SMPL 맞춤의 오차 표기**: `smpl_fit.npz`의 `per_frame_joint_rmse_m`(~5 mm)는 파이프라인(`Exercise3D-Dataset-Pipeline/tools/fit_smpl_sequence.py`)이 `joints × scale ≈ canonical`로 맞춘 뒤 오차에 scale을 곱해(나눠야 함) 약 1/scale² ≈ 18배 작게 적혀 있다. 실제 SMPL 관절 ↔ 삼각측량 거리 중앙값은 2.5–8.6 cm(검증: 우리 재구성으로 미터 = canonical / scale일 때 강체 정렬 = 단위 행렬).
- **학습 전 기준(앱 경로 RTMPose-m vs Sapiens2 라벨, Exercise3D)**: P1 측면 푸시업(cam2·cam3, 10–48°)에서 무릎 하나라도 반대쪽 무릎 라벨에 더 가까운 프레임이 31–100%(라벨상 두 무릎 간격은 몸통 길이의 0.13–0.24), 두 무릎이 모두 바뀐 프레임은 0–10%. 먼 쪽(가려진) 무릎을 가까운 쪽 무릎 근처에 놓는 형태다. 정면(cam1, 70–88°)은 0%. 스쿼트·로우, P2·P3는 0%. P1은 2D 후보의 학습 데이터라 이 칸의 학습 후 값은 독립 평가가 아니다(푸시업 검증 피험자 없음).
