# 분석 뒤 3D 몸 공개 화면 (2026-10-23)

체형 사진 4장의 SMPL fitting이 끝나면 사용자 본인 3D 몸을 BPT 색으로 "짜잔" 하고 보여 주고, 손으로 돌려 볼 수 있게 한다. 브랜치 `ai/mesh-reveal-mf953336`(기준 `integration/ai` 3cef41d).

## 서버

바꾸지 않았다. `fit_body`가 이미 정면 사진의 서 있는 자세를 똑바로 세운 GLB(정점 6,890, 삼각형 13,776, 약 250KB, m, y 위, 발바닥 y = 0, 법선·텍스처 없음)를 `models/<jobId>.glb`에 올리고, `GET calibrations/jobs/{jobId}`의 `result.modelGlbUrl`로 1시간짜리 presigned 주소를 준다(`docs/handoff/teammate_calibration.md` §5). 결과 계약 변경 없음, 재배포 없음.

## 앱

| 파일 | 역할 |
| --- | --- |
| `lib/features/onboarding/widgets/body_mesh_reveal.dart` | `BodyMeshReveal(jobId:, onUnavailable:)`: `fetchJob`을 3초마다(최대 3분) 조회 → `done`이면 GLB 내려받기 → 네이티브 뷰 `bpt/body_mesh`. `BodyMeshReveal.demoSpin()`은 데모 녹화용 천천히 돌리기 |
| `lib/features/onboarding/screens/onboarding_mesh_screen.dart` | `/onboarding/mesh`: 카드 배경(보라→회색 그라데이션, 초록 테두리) 위 메시, "짜잔! 이게 너의 3D 몸이야", "다음" → 기존 결과 화면 |
| `lib/features/onboarding/services/calibration_upload_service.dart` | `fetchModel(url)`: 허용된 저장소 호스트만, 앱 토큰 없이, `glTF` 시작·4MB 이하만 |
| `ios/Runner/NativePose/BodyMesh/GLBMesh.swift` | GLB(메시 하나) 읽기 + 면적 가중 법선. SceneKit은 glTF를 못 읽는다 |
| `ios/Runner/NativePose/BodyMesh/BodyMeshPlatformView.swift` | SceneKit 뷰(배경 투명): 등장 연출, 셰이더, 드래그 |

- **색**: 몸 `AppColors.purple`(#AC88F6), 가장자리 빛 `AppColors.green`(#BFED5F), 화면 배경 `AppColors.black`.
- **등장(약 2.1초)**: 아래에서 올라오며 뒤에서 앞으로 반 바퀴 뒤집히고(1.3초, 크기 0.6 → 1.06 → 1.0), 이어서 흰 빛 띠가 대각선으로 몸을 한 번 훑는다(0.8초). 문구는 1.6초 뒤에 나타난다.
- **대기**: 24초에 한 바퀴 천천히 돈다. 처음 만지면 멈춘다.
- **드래그**: 방향만. 좌우 = 세로축 회전(제한 없음), 위아래 = 기울기 ±15°. 확대·이동 없음(`allowsCameraControl = false`, 팬 제스처 하나).
- **대체 동작**: 작업 실패·3분 초과·주소 없음·내려받기 실패·GLB 파싱 실패·iOS 아님 → 바로 기존 결과 화면(`/onboarding/result`, 변경 없음).
- **켜기**: 흐름 변경이라 기본 꺼짐. `--dart-define=BPT_MESH_REVEAL=true`일 때만 분석 화면이 접수 번호를 들고 이 화면으로 간다. 업로드가 안 됐으면(설정 없음·실패) 접수 번호가 없어 기존처럼 결과 화면으로 간다. `docs/handoff/teammate_requests.md` §10.

## 데모 자동 진행

분석 화면 다음에 "다음" 버튼이 있는 이 화면이 나온다. 메시가 나타난 뒤("짜잔! 이게 너의 3D 몸이야") 8–10초 머물며 `await BodyMeshReveal.demoSpin(turns: 1, seconds: 7)`을 부르면 손으로 끄는 것처럼 천천히 한 바퀴(살짝 기울였다 돌아옴) 돈다. 합성 터치는 네이티브 뷰에 닿지 않아 채널(`bpt/body_mesh`의 `spin`)로 돌린다. 그다음 "다음" → 결과 화면의 "홈으로 가기".

## 라이선스

메시는 SMPL 파생물이다. SMPL 모델 라이선스는 비상업 연구·교육 목적만 허용한다(`docs/decisions.md` 체형 모델 항목). 캡스톤 용도로 본인에게만 보여 주고, 모델 파일은 저장소·앱에 넣지 않는다. 상업화하면 상업 라이선스가 필요하다.

## 확인

- `flutter analyze` 문제 없음, `flutter test` 111 통과(`fetchModel` 2개 추가).
- `swift test --package-path ios/CalibrationEngineKit` 113 통과(`GLBMeshTests`: trimesh가 서버와 같은 방식으로 내보낸 상자 GLB 읽기, 법선 바깥 방향, 잘린·다른 데이터 거부).
- `flutter build ios --debug --no-codesign --dart-define=BPT_MESH_REVEAL=true` 성공.
- 셰이더(가장자리 빛, 빛 띠)는 Mac SceneKit 오프스크린 렌더로 컴파일·모양 확인. 실제 기기·실제 SMPL 메시 화면은 아직 못 봤다(기기는 데모 담당 에이전트가 씀).
