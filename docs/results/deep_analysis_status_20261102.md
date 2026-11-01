# 심층분석 완료 범위와 남은 검증 — 2026-11-02

**자세 정확도 개선까지 모두 끝난 상태는 아니다. 다만 이번에 남아 있던 motion18·native 녹화·기존 리포트의 iPhone 기능 검증은 완료했다.** 서버 기능 실행, 기존 자료의 정량 평가, 실패 원인 분석과 추가 실험도 수행했다. 남은 것은 로우·푸시업의 자세 판정 정확도 실패 해결, 독립 전문가 기준 검증, 후속 후보 `6734902`의 실제 표시·음성 및 배포 API 검증이다. 속도 제한은 사용자의 10월29일 지시에 따라 채택 기준에서 제외했다.

녹화 시험과 리포트 시험은 입력과 목적이 다르다. 저장 로우 영상의 native 녹화/반복 시간 계약과, 기존 동의된 캘리브레이션 분석 작업의 인증·영상 열기·탐색을 각각 확인했다. 같은 실제 운동 세트를 녹화→업로드→서버 분석→리포트로 연결한 전체 E2E 또는 자세 정확도 검증으로 합치지 않는다.

## 완료한 분석과 구현

| 작업 | 확인한 결과 | 의미와 한계 |
|---|---|---|
| 실제 인증 서버 경로 | 기존 동의된 캘리브레이션 영상으로 로그인→업로드→L4 분석→리포트·영상 조회 완료. 20/30/60초 입력의 계약 검사 통과 | 서버 기능 실행 증거. 실제 운동 세트의 자세 정확도 또는 iPhone 녹화부터의 전체 흐름 증거는 아님 |
| Fit3D 20영상 평가 | 4개 운동, 103반복의 저장 결과 확보. 기존 XS 대비 GVHMR의 네 각도 평균 오차 감소 | 로우·푸시업 경계 판정은 악화해 정확도 기준 실패. GT 각도에서 만든 임계값 진단이며 독립 전문가 오자세 라벨 검증이 아님 |
| 프레임별 원인 분석 | 4,632개 저장 점수 재현. 로우의 지속적인 움직임 폭 축소, 푸시업의 상대 기준 반복 선택 영향을 확인 | 단일 프레임 제거·단순 시간 이동만으로 해결되지 않음. 원인 조사 완료가 수정 완료를 뜻하지 않음 |
| 관절 중심 대체 실험 | 같은 20영상에서 native SMPL-X 관절을 양측·모든 반복에 비교 | 로우와 반대쪽 팔꿈치, 상대 팔 펴짐 판정이 악화. 채택하지 않음 |
| 불확실성·피드백 처리 | 관측되지 않은 항목을 정상/교정 성공으로 단정하던 표시·집계 경로 수정 | 후보 `6734902`: Swift 75개·Dart 25개 및 정적 분석, unsigned iOS Release 빌드 통과. 실기기 표시·음성/배포 API 검증은 남음 |
| motion iPhone 비교 | 원본16회+서명 갱신 후2회, 총18/18 수치 로그 검증·보관 완료 | 실행 날짜·서명 그룹을 구분. 예측 관절을 확정 평가하지 않는 동작과 모듈 비용 관측이며 자세 정확도 개선 증거는 아님 |
| native 녹화/코칭 진단 | 저장 로우 입력에서3반복/6,266ms/720×1280 및187진단 프레임 확인 | deep API 시도0회. 실험 항목의 보류 동작 확인이며 새 촬영·음성 청취·업로드 E2E는 아님 |
| 기존 리포트 iPhone 기능 | 정상 소유자 로그인·실제 완료 작업 조회·20초 영상 초기화·10초 지점 이동·provider 계정 경계 검사 완료 | 실제 폰 로그인 저장값 보존. 별도 기존 테스트 계정의 정상 로그인과 메모리 저장소 사용. 지속 재생·실제 OS 로그아웃·후속673 앱의 증거는 아님 |

기본 GVHMR(B)의 네 각도 평균 오차는 XS(A) 대비 스쿼트 14.479→6.836°, 로우 12.855→7.461°, 푸시업 21.513→9.330°였다. 그러나 사전 경계 판정 일치는 로우 2/3→1/3, 푸시업 1/1→0/1이었다. 분모가 작으므로 일반 사용자 정확도로 확대하지 않으며, 평균 개선만으로 채택하지 않는다.

관절 중심 대체안에서는 원래 실패한 로우 2반복의 범위 오차가 약 3.9° 더 커졌다. 푸시업 선택측 팔꿈치 평균 오차는 좋아졌지만 반대측은 나빠졌고, 전체 25반복의 상대 팔 펴짐 일치는 B에서 19/25→15/25로 낮아졌다. 원 데이터·임계값·모델을 바꾸지 않고 이 대체안을 기각했다.

근거: [서버 인증 실행](deep_authenticated_flow_20261026.md), [Fit3D 최종 평가](../deep_analysis/gvhmr_fit3d_20261026.md), [프레임별 분석](../deep_analysis/quality_extrema_results_20261029.md), [관절 중심 실험](../deep_analysis/joint_definition_results_20261030.md), [코칭 근거 계약](workout_evidence_semantics_20261030.md), [전체 iOS 빌드](coaching_release_build_20261030.md).

## 11월2일 실기기 재개와 서명 갱신

사용자가 폰을 사용할 수 있다고 알려 Wi-Fi 검증을 재개했다. 01:39 KST경 새 연결, 정상 파일 조회, `passcodeRequired=false`를 확인했다. **이번에는 폰 연결이나 잠금이 장애가 아니다.** 기존 motion 로그 16개가 있고 17·18 원본은 없었다.

17번 실행 요청은 성공 응답 없이 서명/프로비저닝 관련 Security 오류로 거절됐다. 기존 motion 및 준비된 deep local/report 앱의 프로비저닝 만료 시각은 2026-10-27 01:40:34 UTC였다. 보존 앱 복사본으로 기존 개발자 계정의 정상 서명 갱신을 시도했으나, Xcode export가 코드70과 계정 로그인 거절·일치 프로파일 없음으로 실패했다. 새 프로파일·새 앱 설치·17/18 완료 결과는 생성되지 않았다.

사용자가 **Mac Xcode → Settings → Accounts에서 기존 Apple 계정 재로그인**을 완료했다. 이후 로그인 오류는 사라졌지만 export의 자동 인증서 종류 오류, 수동 방식의 갱신 프로파일 부재, generic destination의 대상 기기 부재를 각각 확인했다. 같은 기존 앱 ID/팀/인증서와 현재 iPhone을 지정한 작은 독립 진단 타깃의 정상 빌드로 프로파일을 발급받았다. 진단 앱은 설치하지 않았고 운동 앱 소스나 모델은 다시 빌드하지 않았다.

새 프로파일은 2026-11-09 01:49:31 KST까지 유효하며 기존 인증서·기기·팀·권한이 그대로다. motion/local/report 3개 보존 앱의 **복사본만** 다시 서명했다. strict 코드 서명 검사와 모든 비서명 에셋, Mach-O 섹션 및 서명 길이/영역 크기 필드만 정규화한 코드·데이터 바이트 비교를 통과했다. root에서도 실제 새 Runner/AOT 해시와 증거 일치를 확인했다. 서명 때문에 달라진 전체 실행 파일 해시를 원본과 구분하며, 기존 16개 기록을 새 앱 실행으로 바꾸어 기록하지 않는다.

로컬 증거: `~/Documents/bpt-handoff/device-finish-20261026/motion18/resume-20261102-013927/`의 연결/잠금/파일 조회·실행 오류, 각 단계 export/probe 결과, `verified-*-signing-lineage.json`과 코드/에셋 비교다. 서명 갱신 직후, 새 실행 전 상태는 **16/18**이고 deep local/report 하니스는 미실행이었다. 이후 측정 결과는 아래 완료 기록으로 구분한다.

## motion18 완료와 로그 회수

**11월2일에 원본 16회 + 추가 2회, 총 18/18의 로그 검증을 완료했다.** 원본 16회 manifest는 그대로 보존했고 별도 continuation manifest와 파생 combined manifest에 새 서명 앱의 17·18회를 기록했다. 실행 소스는 동일한 `deda231`이며 각 회차의 실제 설치 앱 해시·서명·날짜를 구분한다.

17번은 정상 회수했다. 18번은 폰에 원본이 있었지만 Wi-Fi 대용량 복사가 두 번 실패했다. 별도 전송 도구의 기존 Network 연결과 명시적 RSD 경로도 사용할 수 없었다. 이후 파일 크기가 계속 증가하는 것을 확인하고, 고정 소스의 `VideoRunLog`가 영상 종료 후에도 1초 타이머를 유지하는 점을 확인했다. 해당 테스트 프로세스만 SIGTERM으로 정상 종료하고 두 번의 메타데이터 조회로 파일이 고정된 것을 확인한 뒤, 원본 복사에 성공했다. 서비스 리셋·USB 연결·재추론은 없었다. 파일을 닫은 뒤 복사 성공을 관측했지만 이전 전송 실패의 유일한 원인이라고 단정하지 않는다. 뒤늦게 사용자가 완료한 파일 앱 ZIP은 추가 백업으로 보존하며, 같은 회차를 다시 추론하거나 중복 등록하지 않는다.

최종 18번 원본은 **8,013,235바이트**, SHA256 `171a252df20af7fd824f9d159e289edc45686ccf52876a9073a7ac4a5b9a2745`다. 고유 start/camera/video_end/session_end, 정확한 환경·모델 해시, 원래 detail 검증 조건을 통과했다. root에서도 실제 파일 크기·해시와 combined manifest의 18회/서명 그룹 16+2를 확인했다. 중간에 관측한 7,791,793바이트를 최종 파일 크기로 사용하지 않는다.

마지막 로그에는 회수 대기 중의 tick 기록이 많이 포함된다. 고정 분석기의 FPS는 clip_end의 영상 길이, CPU는 processed>0 tick을 사용하지만 발열·배터리 끝값은 전체 로그 범위다. 원래 수치를 덮어쓰지 않고 실제 처리 tick과 종료 후 대기 구간을 별도로 구분한다. 날짜 차이와 서명 갱신을 포함한 이 측정으로 보정 정확도나 모드별 인과적 속도 우위를 주장하지 않는다.

완료 근거는 위 로컬 폴더의 `close-original18-source-021718/`, `continuation-runs/manifest.json`, `combined-study/runs/manifest.json`이다. 원본16과 실패한 전송 파일·오류 기록도 보존했다.

18회 모두 반복수는 기존 pseudo-GT 10회와 일치했다. detail 4,533프레임에서 예측 관절 표본 1,377개 중 자세 평가에 유효하다고 표시된 것은 0개였다. 이는 예측을 확정적 평가로 사용하지 않는 동작 증거이며, 예측 좌표 정확도나 전문가 기준의 오자세 판별 성능은 아니다. 직접 측정한 H-light/H-detail 모듈 시간 p95는 각각 0.020417/0.021125ms다. 이 타이머는 후속 제약·최종 게이트·로깅을 제외하므로 앱 전체 추가 지연으로 해석하지 않는다.

18번의 영상 종료 후 대기 기록은 1,094.678초/1,095tick이었다. 첫 경계 tick 1개가 마지막 처리 구간과 겹쳤고, 그 뒤의 기록 증가를 새로운 XS 추론으로 집계하지 않았다. `combined-study/latest_archive.json`에 수치 로그·집계·해시 참조만으로 만든 Home 보관본의 SHA 검증 완료를 기록했다. 영상·계정 정보·프로비저닝·앱·모델은 이 보관본에 포함하지 않았다.

## native 녹화 및 코칭 진단 — 실기기 완료

고정 소스 `770b2a0`의 local 하니스를 02:22:22 KST에 실행했고, 기존 결과 파일이 없는 상태에서 02:22:47에 새 assertion 통과 증거가 생성됐다. 저장된 로우 입력을 iPhone의 RTMPose→원본 XS→native 반복/녹화 경로로 처리하여 **3반복, 6,266ms, 720×1280**을 확인했다. 이는 폰 앞에서 새로 운동한 카메라 시험이 아니라 저장 영상 입력의 native 녹화 경계 시험이다.

반복 구간은 `video_ms` 기준 약 1,533–2,733 / 3,100–4,500 / 4,733–6,067ms로 순서와 영상 범위를 만족했다. 실제 작성된 영상의 재생기 초기화·길이·크기 확인을 거쳤다. `_NoTransport`의 deep API 시도 0회, 업로드 false, 영구 대기열 저장 false였으며 결과 저장 버튼을 누르지 않았다. 업로드부터 서버 분석까지 하나로 이어지는 실제 운동 E2E 시험으로 확대하지 않는다.

같은 실행의 수치 pose 로그 580,195바이트(SHA256 `2e95eb67118a8ab7ffd915c6fe21a740544bdcadb02927818f1dd884a31d4d37`)를 보존하고 root에서도 재검증했다. frame 187개, experimental coaching 187개, rep 3개였다. 모든 진단은 증가하는 source `sample_pts`를 사용했다. 상태는 ok 164/warming_up 23, 위상은 bottom 72/pulling 48/top 27/lowering 40이었다.

- `row_leg_drive`는 187개 모두 withheld였다. 승인된 수행 방식과 위상 기준 부재를 이유로 기록했으며, 준비되지 않은 항목을 평가 가능으로 승격하지 않았다.
- 실험 코칭 진단의 `trunkInclineDeg`는 187개 모두 동기화된 중력 부재로 수치를 제공하지 않았다. 저장 영상에 폰의 현재 IMU를 정답 중력으로 주입하지 않았다. 기존 반복별 `torso_mean/min/max`는 별도 카메라 축 기준 지표로 여전히 기록되므로, 앱의 모든 몸통 관련 기존 판정이 보류됐다고 해석하지 않는다.
- 8개 양측 관절 지표에 raw/value 쌍 1,312개를 기록했다. 경고 보류와 수치 기록은 관측 정확도 검증과 구분한다.
- 음성을 끈 시험이므로 실제 음성 출력 검증이 아니다. 이후 `6734902`의 표시·집계·칭찬 수정은 이 고정 앱에 포함되지 않는다.

근거는 `motion18/resume-20261102-013927/harness-validation/local-capture-evidence-summary.json` 및 개인 보호 폴더의 새 원본 evidence/pose 로그다. 원본 evidence SHA256은 `a9902d5fc54b9f33ca33b7d74c59bac6f41b237ec9f992494bd76291acb5f522`다. 개인 영상과 인증 저장값은 git/Home에 넣지 않는다.

## 기존 리포트 실기기 검증 — 완료 및 시험 설정 수정

기존 동의된 완료 작업만 사용하는 report 하니스로 실제 인증 조회·영상 초기화·탐색·계정 경계 처리를 검증했다. 새 계정·영상 업로드·분석 작업은 만들지 않았다. local 자동 로그인으로 정상 갱신된 access/refresh token은 보존했으며, 파일 바이트 동일성을 만들기 위해 과거 토큰으로 되돌리지 않았다.

첫 report 시도는 02:28:53 KST 설치·실행 성공 응답을 받았지만, 4분 시험 창이 지난 02:33에도 새 `existing_report.json`이 없었다. console을 붙인 동일 앱의 두 번째 시도에서도 242초 뒤 완료 파일이 없었고, console에는 native 실행/대기 메시지만 있었다. 두 시도를 통과로 처리하지 않으며 파일 부재만으로 코드 오류를 단정하지 않는다. 두 실행 기록은 보존했다.

이후 같은 configured job에 대해 local 로그인 이후 토큰으로 Mac에서 GET 한 번을 수행해 **HTTP404**를 확인했다. redirect·토큰 갱신·POST·새 분석 실행은 없었다. 이 첫 응답만으로는 작업 부재와 소유 계정 불일치를 구분하지 않았다.

기존 승인된 `final_1602` 테스트 계정으로 정상 login API를 한 번 호출하자 HTTP200을 받았고, 응답 JWT의 주체 해시가 당시 `authenticated_probe.json`의 owner 해시와 일치했다. 같은 기존 job GET은 **HTTP200/status done**이었다. 현재 폰의 저장 사용자 ID 및 토큰 주체는 이 owner와 다르다. 따라서 **현재 폰 계정으로 다른 테스트 계정 소유의 리포트를 읽으려 했던 대상 선정 문제**를 확인했다. 서버의 소유권 검사를 우회하거나 현재 계정의404를 통과로 바꾸지 않는다. 이 확인은 Mac의 정상 인증/조회 결과이며, 아직 iPhone의 영상 표시·탐색 성공을 뜻하지 않는다.

공개 근거는 `harness-validation/report-existing-job-readonly-get-summary.json`과 `existing-test-owner-normal-login-readonly-job-summary.json`이다. 계정 식별자·비밀번호·JWT·서명 URL은 개인 보호 폴더에만 보존한다. 다른 계정 순차 로그인, 신규 계정·분석 작업·영상 업로드, 현재 폰 로그인 변경은 없었다.

별도 `test/report-stage-diagnostics-20261102` 브랜치의 `7715462`에 test-only 단계 기록을 추가했다. 제품 소스·모델을 유지하고 진입/설정/문서 플러그인/로그인/조회/영상/탐색/계정 경계 및 오류를 기록한다. 원래 assertion을 유지하며, 단계별 제한을 모두 관측할 수 있도록 진단 타깃의 전체 실행 창만6분으로 설정했다. 원본4분 시도를 다시 성공으로 분류하지 않는다. static analyze를 통과했다.

실기기 진단은 03:00:13 KST 진입·설정·문서 플러그인·저장값 접근을 통과하고 `auth_complete/loggedIn=true`를 기록했다. 이어서 `fetch_start` 약5초 뒤 **DioException/HTTP404** 및 finally를 기록했다. 영상 화면을 띄우는 단계와 성공 assertion에는 도달하지 않았다. 근거는 `harness-validation/negative-diagnostic-progress-1.json`과 `negative-diagnostic-outcome.json`이다. 이것은 실제 폰에서 확인한 접근 거절이며 리포트 재생 성공으로 집계하지 않는다.

진단 앱은 처음 시작한 전체 native 클린 빌드를 완료한 앱이 아니다. Dart 테스트만 바뀌었는데 대규모 native 의존성을 다시 컴파일하는 것을 확인하고, 해당 빌드만 정상 취소한 뒤 공식 Flutter `release_ios_bundle_flutter_assets` 경로로 새 `App.framework`/AOT와 에셋을 생성했다. 원래770의 native Runner·나머지 framework·모델을 별도 복사본에서 재사용했다. native 소스97개·플러그인 등록·의존성 lock·SDK·Flutter 엔진 코드 일치, native asset 참조와 나머지189파일 불변, 권한·서명 검사를 통과했다. 전체 native 재컴파일 성공으로 표현하지 않는다. root에서도 실제 새 Runner/AOT 해시와 증거 일치를 확인했다. 빌드 출처는 `report-stage-diagnostic-build/negative-native-reuse-evidence.json`이다.

유효한 리포트의 실기기 경로는 후속 test-only `e5e0fcd`에서 기존 테스트 계정의 **정상 AuthNotifier.login API**와 임시 메모리 SharedPreferences를 사용했다. 실제 폰 사용자 저장값을 읽어 바꾸거나 토큰·사용자 객체를 강제 주입하는 방식이 아니다. 03:03:57 KST 폰에서 정상 로그인·원래 소유자 ID 일치·offline false를 확인했고, 03:03:59에는 실제 job done 조회까지 성공했다. 임시 자격 파일은 소유한 앱 tmp 경로에서 읽은 즉시 삭제했다.

그러나 이후 `tester.pump(Duration)`의 프레임 대기에서 진행하지 않아120초 반복문 deadline도 빠져나오지 못했다. 폰은 잠기지 않았고 프로세스도 살아 있었다. 이를 영상 디코더 실패나 리포트 재생 성공으로 단정하지 않는다. 같은 서명 URL의 제한된 Range GET은 HTTP206/video_mp4/총4,338,881바이트를 확인했으며1바이트만 읽고 폐기했다. 영상 객체가 존재하고 접근 가능하다는 근거다. 첫 소유자 시도 종료 후 실제 폰 preferences의 바이트·값·사용자 정보 보존과 임시 자격 파일 부재도 확인했다. `harness-validation/positive-test-owner-progress-*.json`, `existing-owner-object-metadata-probe.json`, `positive-attempt1-realprefs-and-credential-preservation.json`에 기록했다.

후속 test-only `a4b2a48`은 Flutter 테스트의 framePolicy를 fullyLive로 설정하고 대기 루프를 실제 비동기 시간 대기로 바꿨다. 초기/정리 pump는10초로 한정하고 실제 lifecycle·frame timing을 기록했다. 관측값·영상·lifecycle를 위조하지 않으며 원래 기능 assertion을 유지했다. 오류 파일은 앞선 오류가 뒤의 assertion 실패로 지워지지 않게 append한다. 정적 분석 및 별도 새 AOT 생성·서명 검사를 통과했다. 제품 `lib`와 native Runner 소스는770 대비 변경하지 않았으며 motion18과 local 성공 결과는 재실행하지 않았다.

**03:11:20–03:11:29 KST의 새 실기기 시도에서 모든 기능 assertion과 finally까지 완료했다.** 정상 로그인·원래 소유자 일치·offline false·job done을 확인했고, VideoPlayer 1개가 실제 초기화되어 오류 없는 상태였다. 영상 길이는20,000ms, 요청한 탐색 위치는10,000ms, 플레이어가 보고한 위치도10,000ms였다. 원 assertion은 `position >= target−500ms`이며 대칭 상한을 검사하지 않는다. 관측한 위치 차이는0ms이지만 프레임 단위 정확도나 지속 재생 시간의 증거로 확대하지 않는다. 제품의 onSeek가 seekTo 이후 play를 호출하는 경로를 실행했으며20초 전체 재생을 검증한 것은 아니다.

provider의 identity를 null로 바꾸자 영상 위젯이 사라지고 계정 변경 안내가 나타났으며, 메모리 테스트 계정의 인증 세션은 유지됐다. 실제 OS 로그아웃이나 실제 폰 저장 계정의 전환 시험과 구분한다. 종료 시 lifecycle은 실제 resumed, framesEnabled는 true였고 engine FrameTiming 표본 수는1→826→960→1,081로 증가했다. 이는 실제 렌더링 활동이며 영상 FPS가 아니다. `test_error`·`flutter_error`·`platform_error` 기록은 없었다. 최종 폰 preferences의 바이트·값은 시험 전과 같았고 소유한 임시 자격 파일은 없었다.

근거는 `harness-validation/existing-report-evidence-summary.json`, `positive-live-progress-1.json`, `report-stage-diagnostic-build/positive_live-native-reuse-evidence.json`이다. 원본 결과는 개인 보호 폴더의 `existing_report_test_owner_live.json`, SHA256 `62ad89e658ba84bbd669b3747829c90970f38bcf0f044a5ec2f5bebc7e10aaf8`다. root에서도 실제 원본 해시·기존 job 일치·20,000/10,000/10,000ms·오류 없는 단계 완료를 독립 대조했다. 이것은 실제 기기에서 실행한 하니스의 assertion 증거이며 `flutter test` 또는 XCTest 전체 suite 실행 결과로 바꾸어 표현하지 않는다.

native 녹화는 고정770 앱, 마지막 리포트 시험은 동일770 제품 코드에 test-only a4b2a48을 적용한 별도 앱이다. 후속 `6734902`의 표시·음성 또는 실제 운동 정확도 검증을 대신하지 않는다. 실제 허리 내부 굽힘 진단, 독립 전문가 기준의 자세 정확도, 세로 영상 기하, 남은 오류 수정도 별도다. XS 제거·모델 교체·실험 기본 활성화·새 학습·main/integration 병합·배포는 수행하지 않았다.

## 기기 원상복구와 보존

검증 후 소유한 임시 demo 설정만 원본 바이트로 되돌리고, 검증된 재서명 `app_motion`을 삭제 없는 설치 방식으로 복구했다. 새로 자동 실행하지 않았다. 실제 폰의 로그인·설정 저장값은 지우거나 과거 백업으로 일괄 덮어쓰지 않았으며 정상 갱신된 토큰도 유지했다. root에서도 positive 시험 전·설치 후·시험 후·motion 복구 전후의 실제 preferences 원본5개가 바이트와 파싱 값 모두 같은 것을 확인했다.

원래 측정 파일 및 사용자 ZIP을 포함한136개 파일 메타데이터를 보존했다. ZIP은976,693바이트, 02:20:54 KST 생성 기록 그대로이며 새 진단 로그도 원 측정 결과와 섞거나 삭제하지 않았다. 데이터 컨테이너 UUID가 설치마다 같다고 가정하지 않고 실제 설치 경로와 DB 식별자를 확인해 `active_app.json`을 갱신했다. 근거는 `harness-validation/final-motion-restoration-proof.json`이다.

최종 감사에서 기존 앱9개/2,200파일의 해시, 원래16회 manifest·controller의 불변, 합계18회 로그의 크기·SHA를 다시 확인했다. 소유한 폰 테스트 프로세스와 Mac 실행 컨트롤러는 없고 motion 앱도 실행 중이 아니다. 새 진단 브랜치는 `a4b2a48`에서 clean이며, 소유한 생성 설정2개는 재현 patch를 남기고 원복했다. main의 기존 사용자 변경은 건드리지 않았다.

이번에 새로 만든 비활성 빌드 캐시6개 경로만 정리하고 signed 진단 앱3개·각 심볼·소스·결과 증거는 보존했다. Mac의 전달용 임시 자격 payload도 삭제했으며 기존 사용자 암호 파일은 그대로다. APFS 복제 파일의 apparent 크기를 실제 회수 공간으로 합산하지 않는다. `harness-validation/final-preservation-audit.json`, `final-device-process-proof.json`, `report-stage-diagnostic-build/new-owned-cache-cleanup-result.json` 및 `isolated-branch-final-state.json`이 최종 근거다. 추가 자동 실행 작업은 남기지 않았다.
