# BPT 구현·심층평가 완료 작업 — 2026-11-02

검토 브랜치는 **review/project-completion-20261102**, 작업 폴더는 `.claude/worktrees/project-completion-20261102`다. iPhone 체형 촬영 → 운동 준비 → RTMPose/MotionAGFormer-XS 코칭 → 기록 → 심층분석 → 리포트 흐름의 문제를 수정하고 실제 실행 근거를 모았다. **자세 정확도와 전체 출시가 완료됐다는 선언은 아니다.**

사용자가 정한 범위에 따라 새 학습, 모델 교체, 실험 기본 활성화, main/integration 병합 및 배포는 하지 않았다. 원래 `feat/ai:9f0003e`의 사용자 변경 4개, 계정·촬영 자료·원본 로그·ZIP을 보존했다. 폰은 Wi-Fi로만 사용했다. 심층분석의 과거 180초 제한은 채택 기준에서 제외했고 정확도 실패는 그대로 남겼다.

## 수정한 동작

| 영역 | 검토 후보의 동작 | 근거 |
| --- | --- | --- |
| 실제 수행량 | 목표 3세트/실제 1세트는 1세트로 기록·표시한다. 명시적 0과 미확인을 구분하고 소수 중량을 유지한다. 경고 이벤트·반복 완료·검증된 자세 정확도를 구분한다. | [기록 계약](workout_evidence_roundtrip_20261102.md), [집계](workout_aggregate_session_20261102.md) |
| 기록 동기화 | POST 전에 계정별 대기열에 보관한다. 같은 기록 재전송은 중복 저장하지 않고 늦은 GET은 새 기록을 지우지 않는다. 거절된 한 행이 정상 행을 막지 않는다. | [대기열·동시성](workout_sync_session_20261102.md) |
| 계정 전환 | A의 요청·응답·토큰 갱신을 B나 재로그인한 A에 적용하지 않는다. 정상 갱신은 유지한다. 새 계정 홈에 이전 계정 집계가 잠깐 남는 문제도 수정했다. | [인증·촬영 소유권](calibration_owner_20261102.md), [심층분석 수명](deep_analysis_session_20261102.md) |
| 개인 체형 | 촬영 시작 계정을 router·업로드·결과 숫자·mesh까지 전달한다. 계정별 저장, cm 단위·유한 수치·품질 근거 검사를 적용한다. 소유자 불명 자료를 삭제하거나 새 계정에 귀속시키지 않는다. | [캘리브레이션](calibration_owner_20261102.md) |
| 부분 관절 실패 | 퇴화한 관절에 의존하는 지표만 null·판정 보류한다. 다른 유효 수치는 보존하고 나쁜 프레임을 빼서 ROM을 좋게 계산하지 않는다. 불명확한 근거 시각으로 영상 이동을 실행하지 않는다. | [부분 유효성](deep_partial_validity_20261102.md) |
| 실제 저장 경로 | 실제 Spring 보안·로그인/JWT·HTTP·transaction·PostgreSQL을 거쳐 저장하고 새 GET으로 회수했다. 그 응답을 Flutter 기록 파서·화면 계약에 넣었다. | [HTTP/PostgreSQL](workout_http_postgres_contract_20261102.md) |
| 독립 자세 평가 도구 | 영상/반복/규칙/측/구간/후보 해시를 대조한다. 미확인 라벨·보류 예측을 보존하고 양성 보류·누락을 엄격한 누락률에 포함한다. | [평가 도구](../evaluation/expert_form_kit_receipt_20261102.md), [프로토콜](../evaluation/independent_form_protocol_v1.md) |

공유 저장소의 늦은 A 로그아웃이 B 토큰을 지우거나 A 프로필 저장이 B 정보를 덮는 반례를 재현한 뒤 수정했다. 홈의 실제 세트 수가 목표 세트 수로 표시되는 문제도 재현했다. 미확인을 정상/0으로 바꿔 해결하지 않았다.

## 고정 소스 검증

서로 다른 검증을 하나의 실제 사용자 end-to-end 성공으로 합산하지 않는다.

| 검사 | 결과 | 범위 |
| --- | --- | --- |
| 기본 Flutter, `bb88a32` | **239 통과 / 4 건너뜀 / 실패 0** | 실제 PostgreSQL GET 산출물을 주입한 전체 검사. 건너뜀은 feature 전용 |
| setup+mesh 동시 활성화, 같은 소스 | **247 통과 / 1 건너뜀 / 실패 0** | 전체 Flutter 검사. 건너뜀은 setup-only route 검사 |
| Dart 정적 검사, 같은 소스 | **문제 없음** | `flutter analyze --no-pub lib test` |
| 서버·수치 스크립트, `6835d3c` | **158 통과 / 3 건너뜀** | 이후 해당 소스 동일. 정상 리포트 10종 전체 JSON이 수정 전과 byte 단위 일치 |
| 실제 HTTP/PostgreSQL 포함 backend, `8001f4f` | **36 통과 / 건너뜀·실패 0** | localhost 임시 PostgreSQL 16.14, 합성 A/B 계정. 이후 backend 동일 |
| Swift 소스 빌드, `6734902` | **210 통과 / 3 건너뜀 / 실패 0** | `swift test --package-path ios/CalibrationEngineKit --jobs 2`; 이후 native 동일 |
| 독립 자세 평가 CLI | **15 통과** | 합성 수식·계약 회귀. Home 실제 미확인 작업팩 생성/채점도 실행 |

Python 건너뜀은 로컬 모델/SMPL 자산이 필요한 항목이다. Home의 별도 실제 모델 검증과 중복 계산하지 않는다. Swift 건너뜀은 선택 비용 시험, CoreML parity 자산, 별도 수치 replay 입력을 요구한다. Python의 기존 deprecation·합성 짧은 JWT 키 경고는 남아 있다.

초기 합동 Flutter의 익명 report fixture 2개가 새 provider 의존성을 선언하지 않아 실패했다. 테스트 fixture에 익명 집계 범위를 명시한 후 위 전체 검사가 통과했다. production 오류를 숨기거나 기존 화면 검증을 지우지 않았다.

setup과 mesh 플래그를 함께 켠 최초 검사는 52 통과/7 실패였다. 분석 화면과 저장 추적기의 중복 poll 및 종료 후 pending timer를 [수정](calibration_combined_flags_20261102.md)한 뒤 위 두 가지 전체 검사가 통과했다. setup-only 접수 작업은 정상 화면 이동 뒤에도 같은 계정에서 저장되며, 계정 교체/소유 provider 폐기 때 로컬 관측만 종료한다. 접수된 서버 작업과 사진을 삭제하지 않는다. mesh-on은 단일 poll에서 측정 저장과 미리보기를 처리한다. 별도 setup-only35개·mesh-only18개 검사도 통과했다. 설정별 검사는 겹치는 시험이므로 합산하지 않는다.

로그·소스 해시·실제 응답은 `~/Documents/bpt-handoff/project-completion-20261102/`에 보존한다. `final-combined-verification-bb88a32.json`은 182개 소스/fixture 해시와 검사 로그 해시를 기록한다. backend 70개 소스가 실제 HTTP/DB 시험 때와 같고 native 두 tree가6734902와 같음을 재확인했다. 실제 GET SHA256은 `130dab9f10e26e2bd6d70ea4c13c3bdb5df13a31be652228edcd481775ea2776`이다. root 소유 임시 PostgreSQL은 시험 후 중지·자동 삭제됐고 부재를 확인했다. 기존 Docker 컨테이너는 건드리지 않았다.

## iPhone

6734902 native 소스를 실제 빌드한 시험 앱에서 실제 결과/기록 위젯과 native 계약을 실행했다. 실제 WorkoutVoice와 Dart KoriVoiceService → KoriSpeaker의 한국어 AVSpeech가 각각 시작·종료 callback 1회씩을 완료했다. 합계 2회, 취소 0회다. 합성 자세·메모리 기록의 전달 경로 검사이며 사람의 청취 확인이나 실제 오자세 정확도 검증은 아니다. 일반 격려는 교정 완료 칭찬과 구분했다.

최초 음성 시도는 기존 mute 설정 때문에 실패했고 따로 보존했다. 원래 설정을 백업하고 시험에서만 mute를 해제해 성공한 뒤 원래 설정·motion 앱을 복원했다. 최신6835d3c Dart 결과/기록·부분 유효 리포트의 무음 시험 앱은 생성·서명됐지만 **첫 읽기 전용 연결 확인이 CoreDevice4016으로 실패해 설치/실행하지 않았다**. 잠금 원인으로 단정하지 않는다. 새 연결 상태를 요청한 뒤 blind retry·USB/reset 없이 대기한다. 이후bb88a32의 production Dart 차이는 onboarding 화면/저장소2개이며 해당 결과/리포트 및 native 소스는 동일하다. 자세한 출처와 보존은 [폰 검증 기록](coaching_runtime_673_20261102.md)에 있다.

직전 [motion18·영상 리포트 시험](deep_analysis_status_20261102.md)은 별도 완료 기록이다. raw 로그/ZIP 141개 metadata 항목, 보호 앱 10개/2,421개 파일 hash 보존 근거도 phone receipt에 남긴다. 실제 카메라 overlay 그림을 이번 화면 시험으로 검증했다고 표현하지 않는다.

## 심층분석의 정량 결론

- [자체 검출 신뢰도 선택측 ablation](../deep_analysis/own_side_results_20261102.md): 20/20 영상·103/103 반복에서 같은 측을 선택했다. **오차·판정 변화 0**, 과거 값 4,632개 재현. 이 가설로 로우/푸시업 실패가 해결되지는 않았다.
- 과거 XS→GVHMR 평균 4각 오차: 스쿼트14.479→6.836°, 로우12.855→7.461°, 푸시업21.513→9.330°. 그러나 작은 GT 각도 proxy 경계 표본의 로우 일치2/3→1/3, 푸시업1/1→0/1로 악화했다. 전문가 오자세 누락률과 다른 수치다.
- 기존 native joint-center 교체도 로우 범위를 약3.9° 악화시켰고 반대쪽 푸시업 악화가 남았다. 교체 근거로 채택하지 않았다.
- 과거 몸통 범위39.9°와 현재 서버 임시 몸통 표준편차8°는 다른 지표다. 팀 카탈로그 CSV가 없어 현재 placeholder 기준이 명시적으로 사용된다. 과거 성능을 현재 규칙의 성능으로 옮겨 쓰지 않는다.
- [Motion/Contact 12개 질문·A–H 표](motion_contact_status_20261102.md): G/H는 RGB 가림에서 작은 차이를 보였지만 2D 손상 관절 오차는 원본보다 악화했다. Kalman·SMPL·단계 정보가 일관된 개선을 증명하지 못했다. 기본 활성화하지 않는다.

높은 2D 점수는 3D 자세가 맞을 확률이 아니다. 여러 관절 각도·운동 단계·개인 치수·관측 상태를 함께 평가할 수 있지만 표면 관절로 실제 요추 굽힘을 확정할 수는 없다. 처음 3회와 비슷하다는 이유로 정상 자세라고 판정하지 않는다.

## 실제 전문가 평가 준비

Home의 기존 20영상/5그룹/103반복에서 **588개 규칙별 검토 항목**을 생성했다. 영상 byte 해시·50fps metadata를 확인했고 dataset 경계는 구간 후보로만 사용했다. 모든 라벨은 unknown, 모든 후보 관측은 missing이다. **전문가 판정 0, holdout 0**이므로 정확도는 null이다.

이미 분석한 20영상은 development다. Mendeley 작성자의 clip-level good/bad와 Exercise3D AI 시각 라벨을 사람의 반복별/규칙별 정답으로 승격하지 않았다. 사람 검토자·별도 판정자가 구간/규칙을 확인하고, 별도 참가자/중복 그룹 holdout과 합격 기준을 고정해야 한다. [작업팩 영수증](../evaluation/expert_form_kit_receipt_20261102.md)에 실행 위치·해시·도구가 있다.

[실제 저장 입력의 서비스 계약 감사](../evaluation/deep_report_cache_contract_20261102.md)도 수행했다. Home81개 입력 해시가 유지됐고40개 B/C 결과의 배열 형태·프레임 metadata는 맞았다. 그러나 모두 추적 마스크가 없고, JSON53개에 실제 앱의 video_ms 반복 manifest가 없었다. dataset 경계·side_gt·빈 경고 목록을 앱 관측으로 만들어 넣지 않아 최신 부분 유효성 수정 전후의 실제 리포트 비교는 미실행이다. 그 비교의 parity/부분 null/거절 개수는0이 아닌 미확인(null)으로 기록했다. 이 제한은 정상 합성 리포트10종의 byte parity와 별개다.

## 남은 완료 조건

1. **폰 연결 필요:** 준비된 최신 Dart 무음 시험을 실제 실행하고 원래 앱/설정 복원을 재확인해야 한다. 마지막 시험은 설치 전에 중단돼 기존 복원 상태를 바꾸지 않았다.
2. **자세 품질:** 로우/푸시업 각도·구간 실패, 실제 접촉점 이동, 긴 가림, 잘못된 자세를 정상화하는 누락을 독립 라벨로 검증해야 한다. 588항목 준비를 전문가 검증 완료로 부르지 않는다.
3. **종료 구간·실제 연결:** [A7 감사](terminal_boundary_closure_20261102.md)에서 squat/pushup은 rep 경계에서 즉시 평가를 끝내고 bench만 추가 관측함을 확인했다. 두 no-lockout 규칙의 quiet 기본값은 terminal completeness를 보장하지 않는다. 원본 해시가 일치하는37로그에는 프레임별 원본3D가 없어 구간을 늘린3D 비교를 복원할 수 없었다. 향후 원래 경계·추가 관측·source PTS를 함께 수집해 검증해야 한다. 또한 같은 실제 입력의 촬영→최신 서버→폰 결과→저장 전체 성공 근거는 아직 없으며 서로 다른 입력 검사를 합쳐 만들지 않는다.
4. **배포 설정·승인:** API_BASE_URL 기본값은 HTTP이고 iOS arbitrary loads가 허용돼 있다. 실제 HTTPS endpoint·전송 정책 확정이 필요하다. 임의 주소 변경·배포는 하지 않았다. 병합·모델/기본값 채택·배포는 사용자의 명시적 승인 대상이다.
5. **별도 제품 범위:** Android 실시간 추론·랫풀다운·소셜/PASS 인증·관리자 화면은 기존 장기 계획의 미완료 항목이다. 이번 iPhone 5운동 검증으로 완료 처리하지 않는다.

## 기존 파인튜닝

ai/finetune3-m2b98256:b0c5600의 과거 결과를 재확인했다. C1/C2는 원래 몸통 기준 불통과다. 기존 C3의 Halpe 검증·폰 비교가 완료됐다는 사실은 이번 후보의 모델 채택과 다르다.

C3-all8도 과거10월23일 완료 기록이 있으나 Fit3D 8명을 모두 학습해 독립 Fit3D holdout이 없다. P2로 ep5를 선택했고 P3 한 사람·로우 3클립 의사 정답에서 위치 오차9.38→8.73%인 반면 무릎/팔꿈치 극값 오차1.0→3.5°/3.2→4.9°로 악화했다. 푸시업 독립 검증도 없다. 이번 심층분석 XS 열은 원래 COCO17 XS이며 C3 평가가 아니다. 새 학습은 시작하지 않았다.
