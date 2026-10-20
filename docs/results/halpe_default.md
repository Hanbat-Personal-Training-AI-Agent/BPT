# 운동 기본 모델 Halpe26 전환 (D-M-03 / D8)

상태: 제품 변경 C1·C2 완료, CSV 발 관절 보존 C3 완료. Mac 통제 재생과 iPhone 동일 빌드 A/B 진행 중. 아래 완료 수치만 검증된 사실이며, 실행 중인 전체 비교의 최종 결과가 아니다.
기준: main/integration `2b98256`에서 `ai/halpe-default-m2b98256`. 사용자가 승인한 운동 기본값은 m Halpe26, 캘리브레이션은 s COCO17.

## A. 검증된 사실

## 1. 바꾼 것

| 커밋 | 내용 |
|---|---|
| C1 `f715c3b` | `0024c50`(우리 커밋, m Halpe26 번들 제외)의 반대: `rtmpose_m_halpe26_forward.mlpackage`를 Runner 번들·pbxproj(4줄)에 되살리고 `RTMPoseModel.mhalpe26` 복구. `RTMPoseModel.workout = .mhalpe26`, `workoutUsesMediumModel` 플래그 삭제(m 두 개 중 고르는 뜻이 없어짐). 캘리브레이션 `RTMPoseModel.active = .coco17`(s COCO17) 그대로. 이 커밋에서는 m COCO17이 아직 번들에 있음 → 기기 A/B(`BPT_POSE_MODEL=mcoco17`)용. |
| C2 `24d0466` | m COCO17 제거: `rtmpose_m_forward.mlpackage`(27.3 MB) 삭제, pbxproj 4줄, `RTMPoseModel.mcoco17` 삭제. pose-replay 사용법·오류 문구에서 `mcoco17` 뺌. 평가 스크립트 4개의 기본 모델(“앱 운동 기본”)을 `mcoco17` → `mhalpe26`(eval_public_sets, replay_remote_clips, eval_pushup_mmfit, eval_side_videos). |
| C3 `5edbb26` | pose-replay `--keypoints-csv`/`--keypoints-dir`: 26관절 CSV면 j17–j25(머리·목·골반과 발끝·발뒤꿈치 6점)도 읽어 평가기에 발을 넘김(전에는 버려서 CSV 재생의 `heel_rise_max`가 영상 실행과 달랐음). 도구 전용, 앱 코드 아님. |
| 문서 | 이 문서, `docs/decisions.md` D-M-03. |

- 모델 파일: 되살린 m Halpe26 세 파일의 sha256이 `0024c50^` 커밋의 blob, `~/bpt-models/rtmpose_m_halpe26_forward.mlpackage` 사본, `eval_reliability.md`에 적힌 값과 모두 같다 — weight.bin `eec87e9d…1e`, model.mlmodel `9629373a…e0`, Manifest.json `649d0274…8a`.
- 번들 크기: m COCO17 27,275,243 B → m Halpe26 27,953,272 B, 순증가 **+0.68 MB**(main 대비). C1만 넣으면 +27.95 MB(두 m 모델 공존).
- 바꾸지 않은 것: 캘리브레이션(s COCO17), s Halpe26(`halpe26`, 10/9 사용자 지시대로 선택 가능하게 남김), 평가기·임계값·셋업 키·Flutter·서버, 3D 경로(integration은 라이브 3D 꺼짐 그대로), `BPT_POSE_MODEL` 덮어쓰기 규칙(운동·캘리브레이션 둘 다 바뀜, 기존 그대로).
- m COCO17 기준선은 평가에서만 쓴다: `pose-replay --model coco17 --model-path ~/bpt-models/rtmpose_m_forward.mlpackage`(sha256 = 마지막 번들 blob, weight.bin `c03d3ca1…74`). 이때 출력 파일 이름이 `_coco17`이 되어 s COCO17과 겹치므로 출력 폴더를 나눈다.

## 2. 2D 키포인트를 쓰는 곳 점검 (26관절)

| 쓰는 곳 | 받는 것 | Halpe26(26관절)에서 | 변경 |
|---|---|---|---|
| `SimCCDecoder.decodeToInputCoordinates` | simcc_x/y | 관절 수를 출력 모양에서 읽음(17 또는 26). 0–16 → `inputCoordinates`, 17–25 → `extra…` | 없음 |
| `RTMPoseCropTracker`(crop·재확인·사람 바꿈) | `applyInverseAffine` = 17관절 | 처음 17관절만 씀(`prefix(17)`) | 없음 |
| 평가기 5종(스쿼트·푸시업·로우·벤치·데드) | `rawCoco17` 17관절, 스쿼트만 `feet` | `count == 17` 확인, 발은 `FootKeypoints` | 없음 |
| `FormWarningTracker` 셋업 키(setup_full_body·tracking_lost·setup_side_view)·자세 키 | 17관절 + 발 | 17관절 기준. 발은 `heel_rise_max` 기록뿐(`heelRiseEnabled = false`) | 없음 |
| 화면 뼈대(`CameraLiveView`, lift-app `PoseOverlayRenderer`) | `visualCoco17` 17관절 | COCO17 선 16개, `count == 17` | 없음 |
| 손 분기(`BundledVideoHandFrameProcessor`, `HandCropBuilder`) | 17관절 손목 | `count == 17` | 없음 |
| 3D(`coco17ToH36M17` → MotionAGFormer-XS, Python `coco17_to_motionagformer_h36m17`) | 17관절 | Halpe26 0–16 = COCO17 같은 순서. 17 머리·18 목·19 골반은 쓰지 않음(D-T3-22 변형 a, 지금 방식) | 없음 |
| Flutter 브리지(onPoseUpdate·onFeedback·onSetEnd) | 렙·상태·키 | 키포인트를 보내지 않음 | 없음 |
| 로그(`WorkoutFormLog`, `WorkoutPerfLog`) | 렙 보고·성능 | 키포인트 없음. 2D 모델 이름도 안 적음(lift-app 실행 manifest에는 `rtmpose`가 있음) | 없음(E) |
| pose-replay CSV 쓰기 | 17 + 9관절 | j0–j25 | 없음 |
| pose-replay CSV 읽기(`--keypoints-csv/-dir`) | j0–j16 | 추가 9관절(발 6점 포함)을 버렸음 | **C3** |
| 캘리브레이션(`CalibrationFrameAnalyzer`, 서버 업로드 `coco17_pixel_unmirrored`) | `RTMPoseModel.active` = s COCO17 | 바꾸지 않음 | 없음(범위 밖) |
| 기기 벤치(`tools/pose_model_bench`) | `BENCH_MODEL`, 모델은 경로로 복사 | Runner 번들의 m COCO17에 기대지 않음 | 없음 |

### 테스트 상태

| 대상 | 실제 확인 | 범위 / 한계 |
|---|---|---|
| C1 `f715c3b` | Swift 105 통과, Flutter 98 통과, flutter analyze 문제 없음 | 원래 Claude 실행 로그 재확인 |
| C1 기기 대상 컴파일 | `flutter build ios --debug --no-codesign` 성공 | `hd/build_ios_c1.log`; C2 제거 뒤 앱 빌드와 구분 |
| C2 + C3 | release `pose-replay`, `calibration-replay` 빌드 성공 | `hd/build_release_final.log` (29.77초); CSV 3종(각 362프레임) 모두 통과; 최종 Swift **105 통과**(22:43:19) |
| C2 제거 정적 점검 | Runner/Swift 테스트/pbxproj의 m COCO17 enum 참조 없음 | 기존 평가 결과 이름 `_mcoco17`은 과거 데이터 호환용으로 남음 |
| iPhone 실험 빌드 | C1 이식 `50194eb` + 회전 `ebcfb38` + 로그 `a8b29f1` | m COCO17은 동일 빌드 실험 기준선에만 남음; **Release arm64 서명 빌드 성공·iPhone 설치 완료**, COCO 세로 smoke 3개 완료 |

C3 실제 검증: 같은 362프레임 CSV에서 26점과 17점 모두 2렙, 입력 좌표·신뢰도 전부 왕복 보존(오차 ≤ 0.000501). 26점의 `heel_rise_max`는 0.136901 / 0.002019, 17점 투영에서는 두 값 모두 없음. 발 위치만 바꾼 대조군은 0.003866 / 0.002244로 달라져 실제 지표 경로에 발이 전달됨을 확인했다. 경고 기본값은 그대로 OFF다. 해시·집계: `halpe_default_manifest.json`.

### w20_s3 재확인: 완료된 Mac 인코딩 앱 경로

바이너리 `pose-replay-f715c3b`, `--motion3d none --ready-pose off`, 각 모델이 자기 crop을 갱신. `mmfit_mac`은 기존 D-T3-18 Mac 클립이며 Home 인코딩/정확 프레임 ref와 합치지 않는다.

| 클립 | 렙 m Halpe26 / m COCO17 | unknown 프레임 H / C | 전체 프레임 입력 H / C |
|---|---|---|---|
| w20_s3 | 1 / 10 | 810/863 / 29/863 | 808 / 26 |
| w20_s2 | 8 / 10 | 184/768 / 2/768 | 178 / 1 |
| w13_s2 | 10 / 11 | 2/510 / 2/510 | 1 / 1 |

- 같은 Mac 클립의 이전 바이너리 `f583d5d` 재실행에서도 w20_s3는 H 1 / C 10, w13_s2는 H 10 / C 11이다. 따라서 이 조건의 결과를 이번 모델 선택 코드 변경으로 생긴 회귀라고 해석할 근거는 없다.
- 과거 보관된 `prior/macA_f583d5d`의 w13_s2 COCO17은 12렙인데 이번 같은 구버전 재실행은 11렙이다. 이 차이는 별도 재현성 한계로 남긴다. 모델 간 수치 차이와 섞지 않는다.
- 이 표만으로 모델의 일반 성능이나 실패 원인을 확정하지 않는다. `mmfit_run.py`가 세 인코딩 × 각자 crop / 상대 모델 crop / 전체 프레임 입력을 비교 중이다.

### iPhone 동일 빌드 비교: 23:00 회수 checkpoint (전체 결과 아님)

- Runner SHA256 `674a755e8e3c7eff708b7f6bc92e98a2995abccf2047e60452f4fc78e71e2adb`, 소스 `a8b29f1`. 원본 H36M XS, 강제 캡처 회전 0, gravity OFF. 미세조정 모델이나 이후 motion/contact 실험은 넣지 않았다.
- 기존 `de42b9a` 대비 COCO 세로 smoke(row0000cam2·pushup0003cam2·squat0001cam2)는 렙 10/10/10이 같다. 스쿼트 3D 경고는 no_lockout 2→4, knee_valgus 4→3으로 달라 경고까지 같다고 주장하지 않는다. 새 A/B 기준선은 두 모델을 모두 실행한 `a8b29f1`이다.
- 회수·종료·해시를 확인한 **3쌍/39쌍**(row0000 세 시점)만 집계하면 두 모델 모두 정확 렙 3/3, 무릎 2D 좌우 바뀜은 C 0/1,734, H 0/1,737이다. 3D ok는 C 92.734%, H 92.746%, 실제 판정 프레임을 합친 E2E p50/p95는 C 190.35/201.97 ms, H 190.71/203.81 ms. 낮은 측면 푸시업이나 전체 39클립 결과로 일반화하지 않는다.
- 이후 Wi-Fi 파일 서비스의 socket closed/timeout 때문에 일부 로그 회수가 지연됐다. 기기는 연결돼 있고 앱 실행은 가능했다. 사용자가 Wi-Fi 진행을 요청하여 폰 측정은 계속하며, `launch+wait`와 `session_end+SHA 검증완료`를 분리한다. 회수하지 못한 런은 완료 분모에 넣지 않는다. 모델·회전 불일치는 조용히 건너뛰지 않고 중단한다.
- `setup_ready`는 현재 빌드에 setup gate가 없어 **미측정**. 기존 성공 기록은 s Halpe26 데모였고 m Halpe26 준비자세 실행은 없었다. 이후 setup 수정 브랜치에서 별도 m 모델 A/B가 필요하다.

## B. 가설

- w20_s3의 매우 높은 전체 프레임 입력/unknown 비율은 사람을 처음 찾거나 추적을 유지하는 과정이 관련됨을 시사한다. 같은 crop 통제와 세 인코딩 비교가 끝나기 전에는 원인 확정으로 쓰지 않는다.
- Halpe26의 발 6점은 CSV 재생에서도 `heel_rise_max`에 영향을 줄 수 있다. 발 전달이 없던 과거 CSV 결과는 이 지표에 한해 영상 실행과 동등하지 않았다.

## C. 이전 판단 정정

- D8은 사용자가 결과를 보고 승인한 제품 결정이다. 미승인 D-T3-17 기준을 통과해서 채택한 것으로 고쳐 쓰지 않는다.
- `j17..j25`는 9개의 추가 관절이며, 그중 발은 `j20..j25` 6개다. 머리·목·골반 3개를 발이라고 부르지 않는다.
- 기기 A/B는 새 회전 코드까지 포함한 동일 빌드에서 두 모델을 다시 실행한다. 이전 `de42b9a`와 새 Halpe 결과를 동일 빌드 대조라고 표기하지 않는다.

## D. 데이터 신뢰도

- MM-Fit 세 클립은 실패 재현·원인 분리용 개발 자료다. 전체 검증 정확도의 대체값이 아니다. 인코딩과 프레임 오프셋 한계는 `eval_reliability.md`의 D-T3-21을 따른다.
- Exercise3D의 렙·시점 표는 기존 의사 라벨을 그대로 사용한다. 3D 모캡 정답이나 사람이 검수한 잘못된 자세 라벨로 격상하지 않는다.
- Fit3D/Exercise3D 이미지는 열거나 git에 넣지 않았다. 이 보고서는 집계값만 기록한다.
- Mac latency는 iPhone latency가 아니다. 기기는 모델, 회전, 앱 해시, 입력 해시, 로그 완결 여부를 별도로 기록한다.

## E. 재현 자료와 진행 상황

scratch 기준: `/private/tmp/claude-501/-Users-6-month-github-06-month-hanbat-repositories-BPT/d083b446-4e06-45ed-8204-8c6e9f22bd1c/scratchpad/hd`.

| 실행 | 파일 | 상태 |
|---|---|---|
| MM-Fit 세 인코딩 통제 비교 | `mmfit_run.py`, `runs/mmfit/`, 완료 시 `rows.json` | 완료 캐시를 보존해 재개, 폰 우선 대기; `phone_priority_resume.json`에 정확한 argv |
| Exercise3D + 비운동 회귀 | `ex3d_run.py`, `runs/ex3d/`, 완료 시 `rows.json` | 완료 캐시 보존, 폰 뒤에서 계속 진행 |
| 구 바이너리 재현 | `runs/oldbin/` | w20_s3 / w13_s2 두 모델 완료 |
| CSV 보존 검증 | `verify_c3.py`, `runs/csv_c3/checks.json` | **통과**: 각 362프레임 26/17점 왕복, 두 입력 옵션, heel 지표 민감도 |
| 회귀 | `swift_final.log` | **105 통과**, 실패 0, 22:43:19 |
| iPhone | `device_video_runs_continue.py`, `device_plan.py`, `device_transfer_recovery.py`, `device_results.py` | smoke3 완료 → full39×2 실행·지연 회수 → 모든 로그 검증·분모 집계 → Halpe 두 클립×90/270 → 고정 snapshot 보존 |

보조 스크립트 백업: `~/Documents/bpt-handoff/tools-20261020/halpe-default/`(입력 영상 제외). 실행 스크립트에는 scratch 위치가 들어 있으므로 재부팅 후 복원 경로를 확인한다.

23:00의 **partial3/39** snapshot은 Home `~/bpt-runs/lift-app/20261020-device-halpe-ab-a8b29f1-partial-20261020-230031/`에 38파일 SHA 검증으로 보존했다. 메타데이터는 `~/Documents/bpt-handoff/device-halpe-a8b29f1/`에 별도 해시 검증했다. 완료된 클립 로그만 복사했으며 원본 영상·이미지는 포함하지 않았다.

무거운 Mac 실행은 `lockf -k /tmp/bpt-heavy.lock`으로 직렬화하며, 폰 작업이 대기하거나 실행 중일 때 새 Mac 작업은 잠금 밖에서 기다린다. Wi-Fi(localNetwork) 진행을 유지한다. 이전 67 MB 발열 원본 로그의 완전 회수는 별도 미완료이며 현재 39클립 비교와 섞지 않는다.

## F. 권고

- 승인된 기본값(m Halpe26 / 캘리브레이션 s COCO17)을 이 기능 브랜치에서 유지한다.
- w20_s3 재현과 통제 비교를 나눠 보고한다. 채택 결정을 성능 우월성의 통계적 검증으로 표현하지 않는다.
- C3 CSV 발 관절 보존 검증은 완료했다. 실제 기기 A/B를 제품 병합 판단 자료에 붙인다.

## G. 사용자 승인이 필요한 항목

- `integration/ai` 또는 main 병합은 별도 승인 대상이다. 이 작업에서 병합/push하지 않았다.
- 미세조정 Halpe26 채택, 캘리브레이션 모델 변경, 새 경고 임계값, 3D·회전·overlay 제품 기본값 채택은 이 D8 전환으로 자동 승인되지 않는다.
