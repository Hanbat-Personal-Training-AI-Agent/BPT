# Motion/contact experiment: evidence and scope

The original MotionAGFormer work evaluates a learned 2D-to-3D temporal model on Human3.6M and MPI-INF-3DHP. Its official XS configuration uses 27 frames. These facts justify preserving the existing XS window and comparing all post-processors at the same output timestamp; they do not establish reliability under BPT's exercise-specific occlusions. [Original paper](https://arxiv.org/abs/2310.16288), [official implementation](https://github.com/TaatiTeam/MotionAGFormer).

Fit3D supplies synchronized camera views, marker-based motion capture, 25-joint skeletons, repetition intervals, and fitted GHUM/SMPL-X shapes. The official shape annotations incorporate marker, multiview and body-scan evidence. They therefore belong to ground-truth scoring, rather than being silently substituted for an on-device user's calibration. This experiment instead separates existing RGB-derived calibration estimates and causal online length estimates. [Official Fit3D data description](https://fit3d.imar.ro/fit3d).

Single-image body-shape reconstruction remains ambiguous under occlusion, clothing and perspective. A statistical body model can constrain plausible shape but does not make a wrist's location uniquely identifiable from forearm length. Here, bone intervals are soft and uncertainty-dependent; they do not impose a good exercise pose. [SMPLify original paper](https://arxiv.org/abs/1607.08128).

## BPT-specific evidence, not a universal ranking of causes

- The separate C1 audit found a 6–8° input/target torso-direction difference dominated by fitted joint-definition offsets in virtual side-view training. B1 also shows a related torso bias. This is a specific calibration/definition mechanism, not proof that all occlusion errors have that cause.
- Existing matched-crop MM-Fit controls found that a Halpe26 run with poor rep recovery recovered its count when given the COCO crop path, while the converse worsened. Those runs concern particular clips/encodings and demonstrate upstream crop dependence, not a global model ranking.
- The app's XS coordinates depend on crop size and are root-relative. Contact in the camera image is consequently distinct from a fixed root-relative joint. The new state estimator receives an invertible crop-to-image-height conversion and never invents absolute contact depth.
- Camera rotation boundaries previously required explicit temporal-state resets. That implementation issue has a separate tested fix; it must not be attributed to the model's intrinsic depth ambiguity.

The new A–H experiments measure error on clean, corrupted and moving intervals separately. Low 2D confidence is an operational proxy, not a ground-truth occlusion annotation. Synthetic RGB masks test a specific controlled perturbation; they are not equivalent to every natural self-occlusion or to general home-camera validation.

## What the existing confidence actually means

The app already retains one RTMPose confidence value per joint. In
`ios/Runner/NativePose/PosePipeline/SimCCDecoder.swift`, it is the smaller of
the peak X-bin and peak Y-bin scores. It is not a calibrated probability that
the joint's 2D position, identity, or inferred 3D depth is correct. H36M torso
joints also contain synthesized coordinates from the COCO mapping, rather
than independent directly detected landmarks.

The experimental `.45` reliable threshold and `.30` missing threshold are
fixed engineering settings. Confidence, current-image motion, temporal
innovation and adjacent-joint consistency determine whether an observation is
trusted. G/H then preserve a trusted raw XS observation exactly. A plausible
wrong observation can still pass those checks; persistent model bias and
monocular depth ambiguity are not solved by a confidence threshold.

The estimator's covariance likewise describes its chosen temporal model and
noise assumptions. It is not a calibrated bound on total XS error. Empirical
coverage against held-out scorer-only 3D references is reported separately.

## 실제 가림 데이터의 충분성 확인

2026-10-21 공식 자료를 다시 확인했다. 현재 BPT 평가 입력에는 Fit3D의
동기화된 운동·mocap과 Exercise3D 기기 재생 영상이 있지만, 이 실험이
사용한 자료에는 관절별 자연 가림 시작/끝, 실제 접촉 변경, 사람이
판정한 잘못된 자세 라벨이 함께 있지 않다. 낮은 confidence와 인위적
RGB 사각형은 그 라벨을 대체하지 못한다. 따라서 현재 자료만으로
자연 가림·발 재배치·실제 자세 오류 보존의 충분한 검증을 완료했다고
판정할 수 없다.

| 공개 후보 | 공식 자료에서 확인한 내용 | BPT 후속 검증에서의 해석 |
| --- | --- | --- |
| 3DOH50K | 물체에 가려진 실제 사람 이미지 51,600개, 2D/3D 자세·SMPL·mask 제공. [저자 데이터 페이지](https://www.yangangwang.com/papers/ZHANG-OOH-2020-03.html) | 실제 물체 가림의 이미지별 검증 후보다. 연속 시각·운동별 접촉/자세 오류 라벨은 이 페이지에서 확인되지 않아 시간적 anchor 복구 성공률 자료로 바로 간주하지 않는다. |
| 3DPW | 움직이는 폰 카메라의 60개 영상, 영상+IMU 기반 3D 자세와 프레임별 카메라 자세 제공. [공식 설명](https://virtualhumans.mpi-inf.mpg.de/3DPW/) | 일반 환경의 시간적 추적 검증 후보다. 움직이는 카메라이므로 본 구현의 고정 영상 anchor를 켜는 근거가 되지 않는다. 운동별 contact/잘못된 자세 라벨의 충분성은 별도 확인이 필요하다. |
| VOccl3D | 시간적 가림 평가용 영상과 3D 자세·체형을 제공하며, 그래픽 렌더링으로 가림·의복·동작을 생성한다. [원 논문](https://arxiv.org/abs/2508.06757) | 제목의 “real Occlusions”를 실제 촬영 데이터로 오해하면 안 된다. 시간적 가림 실험 후보지만 렌더링 데이터이며 자연 사용자 검증을 대신하지 못한다. |

오른쪽 열은 공식 데이터 설명과 현재 모듈의 좌표계 조건에서 내린
적합성 판단이다. 후보를 새로 내려받거나 학습·평가한 결과가 아니다.
우선 완료한 Fit3D A–H 비교와 실제 RTMPose/XS 재추론 결과를 보존하고,
자연 가림과 의도적인 지지점 변경의 독립 라벨이 필요한 부분을
미검증으로 남긴다.
