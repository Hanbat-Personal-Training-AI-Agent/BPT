# integration/ai → main

AI 쪽 작업(캘리브레이션 서버, 2D/3D 포즈, 자세 경고, 렙 카운트)을 main에 합친다.

## 변경 요약

**캘리브레이션 서버 (server/calibration_modal)**
- Modal 업로드 서버 1단계: 버킷 조건부 쓰기로 접수 상태 관리, 패딩 없는 JWT secret 허용, 카메라 정보 없음 기록 접수
- L4 GPU 체형 fitting(SAM 3D Body → MHR→SMPL 공유 β → 재투영 보정 → 키 사영), 결과 스키마
- 재생 도구가 앱과 같은 업로드 묶음 사용

**포즈 (iOS NativePose)**
- RTMPose-s Halpe26 모델 추가와 모델 선택 상수(기본 COCO17, `BPT_POSE_MODEL=halpe26`으로 전환)
- MotionAGFormer 3D: 사람 중심 정사각형 crop 입력(기본), 캘리브레이션 뼈 길이 제약, 무릎 과신전 감지("3D 불량" 표시)

**자세 경고 (FormWarnings.swift)**
- 푸시업·스쿼트·바벨로우 공통 경고 기반, 렙별 판정, 세션 로그, pose-replay 도구
- 임계값: pushup_hip_sag 0.140, pushup_head_drop 0.376, row_torso_swing 39.9° (Exercise3D 정상 렙 p99). 나머지는 임시값
- 몸통 각도 ±180° 경계 버그 수정(max−min이 358°처럼 나오던 문제)

**렙 카운트**
- 스쿼트: 빠른 하강/상승(top↔bottom 직행)도 렙 시작·종료로 인정
- 바벨로우: 측면 판정 게이트(어깨폭 ÷ 몸통 길이 150프레임 중앙값 ≤ 0.56). 측면일 때만 휴식 자세 우선 판정, 한쪽 팔만 보여도 판정.
  측면 아니면 렙을 세지 않고 setup_side_view 안내
- 푸시업: 측면일 때만(푸시업 전용 컷오프 1.0) top→bottom 직행도 렙 시작, 근측 팔 하나로 팔꿈치 각도(`sideViewRepFixes`, 끄면 이전 동작)
- tracking_lost: 렙 도중에는 말하지 않고 1.0초 이상 이어지면 렙이 끝난 뒤 전달

**평가 도구**
- `scripts/eval_side_videos.py` + `data/side_videos/labels_template.csv`: 직접 찍은 영상으로 렙 정확도, 측면 비율 분포, 경고 발생률, 셋업 키 집계

**음성·문서**
- `scripts/generate_kori_voice.py`: ElevenLabs로 코리 음성 mp3 생성(운동 28키 + 숫자 1..20, 캘리브레이션 27줄 = 188파일, 5,623자). 대사는 dart/Swift 원문을 파싱, 키는 환경변수만, `--dry-run`. 이름 규칙 `docs/handoff/kori_voice.md`
- `docs/decisions.md`(결정 기록), `docs/results/summary.md`(발표용 결과표), `docs/handoff/security_followup.md`(JWT 교체·HTTPS·테스트 토큰 정리 체크리스트, 실행 안 함), `docs/progress/`

## 기본 꺼짐(플래그)
| 항목 | 기본 | 비고 |
|---|---|---|
| 자세 경고 Flutter 전달 | 끔 | `FormCommonConfig.enabledFeedbackKeys`에 키별로 추가해야 전달. 판정·로그는 항상 |
| 준비 자세 확인(첫 렙 전 정지) | 끔 | `readyPoseHoldFrames = 0`. 평가용 프리셋: 스쿼트·로우 0.5초 + 허용치 2배, 푸시업 없음 |
| squat_heel_rise | 끔 | 지표는 기록 |
| row_shrug | 끔 | 실험 |
| 무릎 과신전 보정 | 끔 | 감지("3D 불량" 표시)만 켜짐 |

## 기본으로 켜진 키
- 모든 운동: `setup_full_body`, `tracking_lost`
- 바벨로우만: `setup_side_view` (측면 아님 판정 시 첫 렙 전 세션당 1회)

## 검증 (Exercise3D, 측면 ±40° 카메라, COCO17 / Halpe26)
| 운동 | 렙 정확도 수정 전 | 수정 후 |
|---|---|---|
| 스쿼트 | 48.8% / 38.8% | 100% / 100% |
| 바벨로우 | 62.1% / 63.5% | 97.6% / 94.0% |
| 푸시업 | 84.8% / 81.1% | 97.8% / 100% |

- 진단에 안 쓴 squat_03(정답 2렙): 1/2 → 2/2
- 움직임 없음(서서 흔들림 합성 88건, 더미 영상 6개): 추가 렙 0
- 후면 카메라 로우는 모두 측면 아님으로 판정

## 테스트
- `swift test --package-path ios/CalibrationEngineKit`: 57 통과
- `pytest tests/`: 163 통과
- 서버 `pytest tests` (server/calibration_modal): 68 통과, 1 건너뜀
- `flutter test`: 67 통과
- `xcodebuild` Runner, iOS Simulator Debug, `CODE_SIGNING_ALLOWED=NO`: 성공

## 알려진 한계
- **푸시업 측면 컷오프 1.0**은 Exercise3D에서 40°와 48°를 가르지 못함(48°도 측면으로 판정). 정면(70°+)만 확실히 걸러짐.
- **Fit3D에 측면 카메라 없음**(전부 58–74° 사선): 측면 정확도 검증에는 못 쓰고 회귀 확인만 함.
- **측면 컷오프 0.56은 40° 근처에서 미검증**: 데이터가 20–36°와 76–81°뿐이라 0.51–0.66 사이 어떤 값이든 같은 결과.
  주말 촬영 영상(0/30/40°, 정면·후면)으로 확인 예정.
- 준비 자세 확인은 Exercise3D처럼 바로 시작하는 세트에서 렙을 잃어 기본 꺼짐.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
