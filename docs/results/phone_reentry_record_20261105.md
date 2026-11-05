# iPhone 재진입·기록 저장·재생 검증 — 2026-11-05

**33b88e8 소스에 재진입·기록 시험만 추가한 `4528647` 앱을 실제 iPhone 17에서 2건 실행했다. 2건 모두 통과했고, 원래 앱·설정을 복원했다.** 런타임(`lib/`, Swift)은 33b88e8과 같다. 바뀐 것은 `integration_test/`의 시험 2개 파일뿐이다. 이미 허용받은 푸시업 영상만 재생했다. 실시간 카메라 촬영, 실제 기록·계정 저장, 네트워크 전송, 모델·기본값 변경, 병합, 배포는 하지 않았다.

## A. 검증된 사실

| 시험 | 결과 |
|---|---|
| 기존 capture + observer H (`pushup-observerH1`) | Dart 실행기 통과. terminal 550행(프레임 536, 반복 10)이며, 확인된 후보 판정은 140건이다. 네트워크 0회, Flutter 오류 0건. observer sidecar 509행이 같은 실행의 XS 원출력과 509/509 정확히 일치했다. 설명되지 않는 누락은 0건이다. footer는 정지된 세대 1프레임 때문에 `incomplete`·`stopped_generation`으로 표시됐고, 대기열은 비워진 상태(`drained`, `pending_frames 0`)였다. |
| 재진입·기록·재생 (`reentry-pushup`, 새 시험) | 한 앱 프로세스 안에서 실제 네이티브 카메라 화면을 열고, 영상 끝에서 세트를 종료하고, 화면을 닫는 과정을 2회 반복했다. 진입마다 영상이 처음부터 다시 재생됐다(video_end·session_end·start_set 각 2회). 처리 프레임은 진입마다 544/543으로 따로 셌고, 반복은 각 10회였다. 진입마다 따로 녹화됐다(5.89MB/5.88MB, 1280×720, 18.4초). 닫힌 화면으로 늦게 도착한 이벤트는 0건이다. 각 세트를 실제 `WorkoutResultScreen`으로 저장하고(메모리 계정 저장소), 다시 읽은 기록 2개를 Home과 같은 경로로 열었다. 두 기록의 녹화 경로는 해당 진입의 파일과 일치했다. 재생 버튼을 누르면 두 영상 모두 실제로 재생됐다(위치 527ms·635ms까지 진행). 전송하지 않은 기록 2개는 대기열에 남았고, Dart 네트워크·전송 시도는 0회였다. 시험이 만든 녹화 2개는 지웠으며, 기존 영상 목록과 크기가 원래대로 돌아온 것을 확인했다. |
| 복원 | 원래 앱을 재설치했다. demo 설정은 원본과 정확히 일치하고, 환경설정은 덮어쓰지 않은 채 동일하다. 기존 Documents 항목 730개와 보호 파일 6개의 SHA가 보존됐다. |

빌드: Release 3-target 빌드에 80.8초가 걸렸다. 빌드 전후 소스가 같고, 새 패키지는 내려받지 않았다. 서명: 기존 팀·기기 프로파일로 서명했다(11-08 만료). 모델 5개의 가중치·MIL이 원본과 일치하고, codesign deep/strict와 entitlements도 일치한다. `flutter analyze integration_test/`에서 문제가 없었다. `lib/`과 Swift를 바꾸지 않았으므로 Dart 단위 시험과 Swift 시험은 다시 돌리지 않았다. 기존 근거(Swift 364개, Dart 282개)는 같은 런타임 소스에 대한 것이다.

## B. 가설

- Swift가 같은데도 unsigned Runner의 SHA가 33b88e8 빌드(`228f68…`)와 다르다(`b99271…`). 빌드 위치·메타데이터 차이로 보지만, 바이트 단위로 원인을 확인하지는 않았다. 입력 소스 해시의 차이는 테스트 2개 파일뿐이다.

## C. 수정한 이전 판단

- 11-04 controller(`current-phone-20261104/device.py`)는 namespace를 `current-phone-`로 만들었다. 33b88e8 시험은 `^coaching-candidate-`를 요구하므로 반드시 실패했을 것이다. 이번에 `coaching-candidate-`로 고쳤다.
- preflight는 현재 앱을 11-02 메타데이터와 정확히 같은지 비교했다. 그런데 11-03 복원 때 같은 원래 앱을 재설치하면서 container URL이 바뀌어 거절됐다. URL 외의 필드는 정확히 일치하는지, URL은 11-03 `restoration-proof.json`에 기록된 값과 같은지 확인하도록 바꿨다.
- `audit_observer.py`는 observer의 17×3 배열과 terminal의 51개 평탄 배열을 그대로 비교해 "원출력 변경"으로 실패했다. 값은 509행 모두 같고 배열 모양만 다르다. 평탄화한 뒤 정확히 같은지 비교하도록 고쳤고, 그 결과 통과했다. 이 때문에 capture의 collect 마지막 단계(perf 회수·결과 저장·정지)는 같은 함수 순서로 수동 마무리했다.
- observer 경로(`BPT_MOTION_OBSERVER`)는 33b88e8에 들어 있으며, 실제 기기에서 sidecar가 생성되는 것을 확인했다.

## D. 자료 신뢰도

- 재진입 시험은 영상을 카메라처럼 쓰는 입력이며, 실시간 카메라가 아니다. 반복 10회는 엔진 카운터 값이고, 정답 반복 수로 검증한 것이 아니다. 자세 정확도 주장은 없다.
- 기록 저장은 실제 저장소·대기열 코드를 거치지만, 계정 저장소는 메모리 모의 환경설정이다. 서버 전송과 실제 계정 기록은 검증하지 않았다.
- 이전 하네스와 마찬가지로, 시험 출력(`coaching_candidate_validation/`, 실행기 영수증, 실행 로그, namespace 폴더, observer sidecar, perf 로그)은 폰 Documents에 추가된 상태로 남는다. 원래 항목은 바뀌지 않았다.

## E. 재현 자료

- 소스: `test/phone-reentry-record-20261105` `4528647` (기반 `33b88e8`)
- 빌드: `~/bpt-runs/phone-reentry-record-20261105/` (`build.py`, `result.json`, `manifest.json`의 sha256과 명령). DerivedData는 서명 후 지웠다.
- 앱·controller: `~/Documents/bpt-handoff/phone-reentry-record-20261105/` (서명 앱, `signing-provenance.json`, `device.py`, `audit_observer.py`)
- 기기 자료: `~/bpt-data/phone-reentry-record-20261105-private/` (preflight, cases, `restoration-proof.json`)

## F. 권장

- 재진입·기록·재생 시험은 같은 하네스에 `BPT_PHONE_TEST_MODE=reentry`로 남겨 다음 런타임 변경 때 다시 실행한다.
- 서명 프로파일은 11-08에 만료된다. 그 뒤의 폰 시험은 갱신된 프로파일이 필요하다.

## G. 사용자 승인 필요

- 이 시험 브랜치를 검토·병합할지(시험 코드만 있고 런타임 변경은 없음)
- 폰 Documents에 남은 시험 출력의 정리 여부(원래 항목은 보존됨)
