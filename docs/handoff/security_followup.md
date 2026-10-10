# 보안 후속 조치 체크리스트 (실행하지 않음 — 사용자·서버 담당 팀원 확인 필요)

비밀값은 이 문서에도 적지 않습니다. 항목마다 "누가"를 적었습니다.

## 1. JWT secret 교체 (Spring과 Modal을 함께)
Modal 캘리브레이션 서버는 Spring 백엔드가 발급한 토큰을 같은 HMAC 키로 검증합니다(`server/calibration_modal/checks.py`). 둘 중 하나만 바꾸면 캘리브레이션 업로드가 전부 401이 됩니다.
- [ ] **저장소에 기본값이 들어 있음**: `backend/src/main/resources/application.yml`의 `jwt.secret: ${JWT_SECRET:<기본값>}` — 환경변수가 없으면 git에 공개된 값으로 토큰을 서명합니다. 운영 서버에 `JWT_SECRET`가 설정돼 있는지 확인하고, 기본값을 지우는 변경은 백엔드 담당 팀원에게 요청(백엔드 코드라 직접 수정 안 함). (누가: 백엔드 팀원)
- [ ] 새 secret 생성: 32바이트 이상 무작위 → base64 (예: `openssl rand -base64 48`). 패딩 없는 base64도 Modal 쪽은 허용(`4c69d32`). (누가: 사용자/백엔드 팀원)
- [ ] 같은 시점에 두 곳 교체 (누가: 백엔드 팀원 + 사용자)
  1. Spring 운영 서버 환경변수 `JWT_SECRET`
  2. Modal: `modal secret create bpt-jwt JWT_SECRET=<새 값> --force` 후 `modal deploy server/calibration_modal/modal_app.py`
- [ ] 교체 뒤 기존 access 토큰(1시간)·refresh 토큰(14일)은 모두 무효 → 앱 사용자 재로그인 필요. 발표·시연 일정과 겹치지 않게.
- [ ] 확인: 새 로그인 토큰으로 `server/calibration_modal/e2e.py`(토큰은 환경변수 `BPT_TOKEN`, 출력 안 함) → 업로드 성공, 옛 토큰 → 401.

## 2. HTTPS
- [ ] 앱 기본 API가 평문 HTTP: `lib/core/network/api_client.dart:45` `http://151.145.79.106:8080/api/v1`. 로그인 비밀번호·JWT가 암호화 없이 오갑니다. 도메인 + TLS(리버스 프록시) 뒤로 옮기고 앱 기본값을 `https://`로. (누가: 서버 담당 팀원)
- [ ] iOS ATS 예외 `NSAllowsArbitraryLoads`가 켜져 있음(`ios/Runner/Info.plist:31`). HTTPS 전환 후 제거. (누가: 앱 담당 팀원)
- [ ] 서버 공개 포트 확인: 8080(Spring), 80(Swagger가 보였음 — 프록시 설정이 저장소에 없음). 운영에서 Swagger 공개 여부 결정. (누가: 서버 담당 팀원)
- Modal(`*.modal.run`)·R2 presigned URL은 이미 HTTPS. 앱도 저장소 URL은 https·443·허용 호스트만 받음(`CalibrationUploadConfig.allowsStorage`).

## 3. 테스트 토큰·계정 정리
- [ ] e2e·디버깅에 쓴 로그인 토큰: 셸 기록(`~/.zsh_history`)·`.env`·노트에 남았으면 지움. 토큰은 만료(1시간)되지만 refresh 토큰(14일)이 있으면 그것도.
- [ ] e2e용 테스트 계정이 운영 DB에 있으면 삭제 또는 비밀번호 변경. (누가: 사용자 — 운영 데이터 삭제는 사용자 결정)
- [ ] R2 버킷의 e2e 업로드(`e2e-…` 세션)와 Modal job 상태 정리 여부 결정. (누가: 사용자)
- [ ] ElevenLabs 키: 생성 후 셸에서 `unset ELEVENLABS_API_KEY`, 키는 저장소·로그에 넣지 않음.

## 4. 그 밖에 확인할 것
- [ ] Modal secret `bpt-r2`(R2 키)·`bpt-hf`(HF 토큰) 권한 최소화: R2 키는 해당 버킷 읽기/쓰기만.
- [ ] 워커가 죽으면 job이 "running"으로 남음(실패 처리기 없음) — 보안은 아니지만 운영 항목. 트랙 F.
