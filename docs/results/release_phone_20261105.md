# 릴리스 실기기 검증 — release/bpt-final-20261105 (a197e83), iPhone 17

2026-11-05에 실행했고 11-16에 복원과 기록을 마쳤다. 기기는 `00008150-0011745A26F8401C`이고, 절차는 11-05 재진입 시험과 같다(preflight 백업 → 설치 → 설정 → 실행 → 수집 → 복원). push와 main 병합은 하지 않았다. 런타임 코드는 바꾸지 않았다.

## A. 검증된 사실

| 단계 | 결과 | 근거 |
|---|---|---|
| 1-a capture + observer H (`pushup-observerH2`) | **통과** | Dart 실행기 통과. terminal 562행(프레임 548, 반복 10, 후보 판정 147). 네트워크 0회, Flutter 오류 0건, 실제 기록 쓰기 0건. observer 523행 중 521행이 terminal 원출력과 정확히 짝지어졌다. 짝이 없는 1행은 정지된 세대이고, 누락은 0건이다. 11-03 기준선(509프레임)과는 보존된 원본 순서가 달라 비교하지 않았다. |
| 1-b 재진입·기록·재생 (`reentry-pushup`) | **통과** | 진입 2회, 기록 저장 2건, 다시 열기 2건, 재생 2건. 닫힌 화면으로 늦게 온 이벤트 0건. 네트워크·전송 0회. 시험이 만든 녹화는 지웠다. |
| 2-a 가입·온보딩 | **통과** | 데모 자동조종으로 새 계정 `bptrel1105a`를 운영 Spring에 가입했다. 비밀번호는 비공개 파일에서 바로 폰으로 보냈고, 앱이 읽는 즉시 지웠다. 로그와 문서에는 남기지 않았다. |
| 2-b 체형 측정 → 결과 화면 | **통과** | 사용자 본인 영상 `IMG_9900_slowdiag`를 썼다. 업로드 receipt는 `job-22154e1b1c6a4f44a7aba3b4106540e9`이고, 재배포한 v19에서 accepted 됐다. 서버 상태는 `done` 100 %, `stub: false`, SMPL 결과다. 재투영 오차는 정면 9.1, 왼쪽 앞 8.5, 오른쪽 앞 9.3, 뒤 17.4 px였다. 메시 공개 화면은 기본으로 꺼져 있어 기존 결과 화면으로 넘어갔다. |
| 2-c 운동(영상 입력) → 세트 종료 → 결과 저장 | **통과** | 바벨로우 3세트 × 11회. 결과 화면에 3세트·33회·1,320 kg이 나왔다. '기록 보기'를 누르면 리포트(1m, 33회, 1일)로 넘어갔다. |
| 2-d 세트 녹화 업로드 → 심층분석 → 코리 리포트 → 다시 열기 | **검증 못 함** | 반복이 나오는 입력 영상은 Exercise3D 클립뿐이다. Exercise3D는 클라우드에 올리지 않는다는 규칙이 있어, 이 실행은 `BPT_SET_RECORDING=0`으로 업로드를 막았다. 앱에는 업로드만 따로 끄는 스위치가 없다. 사용자 본인 영상(IMG_9900)은 제자리에서 도는 영상이라 반복이 0이고, 세트가 끝나지 않는다. 심층분석 Modal 작업은 0건이다. |
| FPS | 측정 | 영상 입력이라 원본의 30 fps가 상한이다. 세트 녹화를 켠 재진입 2회는 판정 fps 중앙값 30(최저 30, 28), 지연 p50 191 ms였다. 녹화를 끈 capture는 30(최저 28), 192 ms였다. 데모(녹화 끔, 79초)는 30(최저 27), 189 ms였다. 열 상태는 모두 nominal이었다. 녹화 때문에 fps가 떨어진 것은 보이지 않았다. 실시간 카메라 수치는 아니다. |
| Modal | 재배포 | 배포본은 v18(`0b18bf1*`, 10-26)이었고, 그 뒤 서버 커밋 9개(JWT 클레임 검증, 심층 지표 근거, 팀 카탈로그 조건)가 빠져 있었다. pytest 216 통과·1 건너뜀을 확인한 뒤 v19로 배포했다(`release-a197e83-20261105`, 11-05 11:03). 가입 직후 운영 토큰으로 체형 업로드가 accepted 됐다. 새 JWT 검사(username/email 필요)가 운영 Spring 토큰과 맞는다는 뜻이다. |
| 복원 | 부분 완료 | `bpt_demo.json`, 환경설정 plist, `demo/flow_steps.log`가 원본 SHA와 같다. 원래 항목 760개는 지워지거나 크기가 바뀐 것이 없다. 보호 파일 6개의 SHA도 보존됐다. **원래 앱(app_motion.app)은 다시 설치하지 못했다.** 서명 프로파일이 11-08에 만료됐기 때문이다(아래 G). |

## B. 가설

- 첫 capture 시도(`pushup-observerH1`)는 시작 직후 앱이 백그라운드로 가며 멈췄다(`idle timer disabled=false (background)`). 화면이 잠기고 무선 연결이 끊긴 것과 같은 시각이다. 앱 결함이 아니라 기기가 잠긴 탓으로 본다. 같은 빌드로 다시 실행한 H2가 통과했다.
- 서버 배포 태그의 `*`(dirty)는 작업 트리의 추적하지 않는 빌드 산출물 때문으로 본다. 추적하는 파일은 a197e83과 같다.

## C. 수정한 이전 판단

- `release_merge_20261105.md`의 Release 빌드는 `--dart-define` 없이 만들었다. 그래서 `CALIBRATION_API_BASE_URL`이 비었고, 그대로 배포하면 체형 업로드와 심층분석이 "주소가 설정되지 않았어요"로 막힌다. 이번 검증 빌드에는 기존 공개 설정 두 개를 넣었다.
  `flutter build ios --release --no-codesign --dart-define=CALIBRATION_API_BASE_URL=https://hqbfgym--bpt-calibration-api.modal.run/v1 --dart-define=CALIBRATION_STORAGE_HOSTS=1de0e5ab10d7233b02491befb246f0ff.r2.cloudflarestorage.com`
- 무선 연결이 자주 끊겨(연결 무효, usage assertion, 즉시 끊김) 기기 명령 래퍼에 재시도를 넣었다. 전송 오류일 때만 최대 30회 재시도한다.

## D. 자료 신뢰도

- 운동은 영상을 카메라처럼 쓰는 입력이다(바벨로우는 Exercise3D P2 클립을 폰 안에서만 재생). 반복 수는 엔진 카운터 값이며, 자세 정확도는 주장하지 않는다.
- 심층분석은 이 실행에서 끝까지 검증하지 못했다. 앞선 폰 검증도 저장된 HTTP 응답을 썼고, 실제 앱→Modal 심층분석 업로드를 폰에서 한 적은 아직 없다.
- 운영에 남은 것: Spring 계정 `bptrel1105a`와 운동 기록 1건, R2 체형 작업 1건. 폰 Documents에는 시험 출력과 체형 업로드 묶음 등 새 항목 48개가 남아 있다.

## E. 재현 자료

- 앱과 controller: `~/Documents/bpt-handoff/release-phone-20261105/`
  - `sign.py`, `provenance-{harness,release}.json`: 모델 5개 원본 일치, codesign deep/strict, entitlements 일치
  - `device.py`, `restore_files.py`
- 빌드: `~/bpt-runs/release-phone-20261105/`
  - unsigned 앱 3개: 원래 release, harness, defines 포함 release
  - 빌드 로그, Modal 배포 로그, `jobcheck/`(읽기 전용 상태 조회)
- 기기 자료: `~/bpt-data/release-phone-20261105-private/`
  - preflight, cases, `restoration-proof.json`
  - 스크린샷 `cases/demo1/shots/`. 자동조종이 끝난 뒤 사용자가 폰을 쓴 화면은 지웠다.
- Modal 비용: 체형 fit(L4) 1건과 CPU 상태 조회 2건이다. 대략 $0.5 미만으로 추정하며, 대시보드로 확인하지는 않았다. 심층분석 작업은 0건이다.

## F. 권장

- 배포용 Release 빌드 명령에 위 두 `--dart-define`를 넣는다.
- 심층분석 E2E: 본인 운동 영상을 새로 찍어 `~/bpt-data`에 두거나, Exercise3D P2(본인) 클립 업로드를 허용받은 뒤 같은 데모 흐름을 `BPT_SET_RECORDING=1`로 다시 실행한다. 리포트 화면 열기와 다시 열기는 자동조종에 단계를 추가해야 한다.
- 폰 시험은 화면 잠금을 '안 함'으로 두고 USB로 연결해 진행한다.

## G. 사용자 승인·조치 필요

1. **서명 프로파일 갱신**(11-08 만료). 갱신해야 원래 앱을 다시 설치할 수 있다. 지금 폰에는 만료된 `release_signed.app`이 설치돼 있어 실행되지 않는다. 데이터 컨테이너는 보존됐다.
2. 심층분석 E2E에 쓸 입력 영상(새 본인 영상 또는 P2 클립 업로드 허용).
3. 운영에 만든 시험 계정 `bptrel1105a`의 정리 여부.
