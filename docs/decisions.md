# 결정 기록

## 트랙 E — 앱 연결 (onFeedback·WorkoutVoice·onSetEnd·세트별 녹화) — 2026-10-10

### E1. onFeedback 계약: `{key, n?, scope: "rep"|"set"}` (기존 `silent` 폐기)
- 결정: 렙마다 고른 1개 키(우선·개선·셋업·praise_fixed, setup_full_body·tracking_lost)는 `scope:"rep"`, `n` 없음(그 대사들엔 `{n}`이 없고, main의 `_nativeFeedbackCounts`가 이벤트마다 `n ?? 1`을 더하므로 누적 n을 보내면 과다 집계됨). 참고 등급 키는 렙마다 보내지 않고 Flutter `endSet` 때 키당 1번 `scope:"set"`, `n` = 그 세트에서 걸린 렙 수(`{n}` 대사: pushup_no_lockout·pushup_head_drop·pushup_head_up·squat_no_lockout·row_head_up). 고르지 못한 우선·개선 키는 보내지 않는다(렙 리포트·세션 로그·세트 집계(worstJoint)에만 남음).
- 근거: 팀원 요청 1의 형식, 스펙 "참고 = 세트 후 요약만". 키 활성 목록(`enabledFeedbackKeys`)·전달 규칙(1렙 1개, 3렙 쿨다운, 개선 2연속, 셋업 1회, praise_fixed)은 그대로이고 테스트로 고정(FormWarningsTests 기존 + `testSetEndSummaryScope`).
- 기본값에서 실제로 나가는 키는 바뀌지 않음: setup_full_body, tracking_lost(+로우 setup_side_view). 참고 키는 전부 OFF라 `scope:"set"`은 아직 안 나간다.
- 버린 안: 고르지 못한 키도 `silent`로 보내기 — 요청 형식에 없고, Flutter(main)가 모든 onFeedback을 말풍선·횟수로 세므로 중복 집계됨.
- 되돌리기: 이 커밋 revert.

### E2. 벤치프레스·데드리프트: 폼 키 없이 setup_full_body·tracking_lost·praise만
- 결정: `FormExercise.benchPress/deadlift`(규칙 0개) + `StatusDrivenFormTracker`가 평가기 상태로 렙 구간을 잡는다(벤치 lowering/bottom/pressing, 데드 rising/top/lowering, unknown은 렙 유지, 렙 수 증가 = 렙 끝). 필수 관절: 벤치 어깨·팔꿈치·손목(누우면 다리가 벤치에 가림, 추정), 데드 어깨·엉덩이·무릎·발목(스쿼트와 같음). 평가기 파일은 트랙 G 소유라 손대지 않음.
- 근거: 팀원 요청 2. tracking_lost는 다른 운동과 같이 렙 도중엔 미루고 1.0초 이상일 때만(테스트 `testStatusDrivenBenchDeadlift`).
- 주의(추정): 벤치·데드 실영상으로 셋업 키 오경보를 재지 않았다. 지금까지는 아무 키도 안 나갔으므로 셋업 키 오경보가 "늘 수 있는" 유일한 변화 — 트랙 G가 실영상으로 확인하고 필요하면 `StatusDrivenFormTracker` 생성을 빼면 된다(CameraPosePreview `statusFormTracker`).

### E3. 대사 원문은 dart에만: 네이티브는 onFeedback의 **답**으로 대사를 받는다
- 결정: Flutter가 onFeedback을 처리하며 `{text, lang}`(kori_feedback_lines.dart `render`, `{n}`·언어 반영)를 돌려주고 네이티브 WorkoutVoice가 그걸 말한다(`lib/features/workout/data/native_pose_channel.dart` `koriVoiceReply`). 답이 null(모르는 키·일시정지·세트 끝난 뒤의 rep 이벤트)이면 말하지 않는다 → 말풍선과 음성이 항상 같다.
- 버린 안: (a) 시작 때 대사표 전체를 채널로 보내기 — 언어 전환·`{n}` 채우기를 네이티브에 다시 구현해야 함. (b) 네이티브 사본 — 금지 조건.
- 지연: MethodChannel 왕복 1회(ms 단위, 추정)라 "렙 직후" 규칙에 영향 없음.

### E4. WorkoutVoice: ★ = 우선 등급, mp3 우선, 대기 3초 넘으면 버림
- ★ 표시는 스펙(docs/research/form_feedback_spec.md)에 없다. "렙 직후 바로"인 **우선** 등급 키(pushup_hip_sag, squat_hips_first, squat_knee_valgus, row_torso_swing)를 ★로 봤다(추정 — 사용자 확인 필요). ★는 말하던 것을 끊고 바로, 나머지는 줄 서고 3초 넘게 기다리면 버린다.
- 음원: Flutter 에셋 `assets/kori_voice/<key>.mp3`, `{n}` 대사는 `<key>_<n>.mp3`(한국어일 때만). 없으면 AVSpeechSynthesizer(ko-KR / en-US). 에셋 폴더는 아직 없음(트랙 H가 만들면 pubspec에 `assets/kori_voice/` 추가).
- 음소거: `setVoiceMuted {muted}` → 재생 중지·대기열 비움. 음소거 상태는 화면이 들고(세트 사이 HUD가 사라져도 유지), 버튼은 상태 없는 위젯으로 바꿈.
- 주의: main의 팀원 코드(`KoriVoiceService`, ElevenLabs 실시간 TTS, 채널 `bpt/kori_voice`)도 onFeedback 때 대사를 말한다. integration/ai에는 아직 없지만 main과 합칠 때 둘 중 하나만 남겨야 이중 재생이 안 된다(사용자 요청 목록).

### E5. onSetEnd·worstJoint
- 세트 경계는 Flutter가 정한다(목표 렙 도달·끝내기). Flutter → `endSet {setIndex}` / `startSet {setIndex}`(1세트는 카메라 시작 때 자동). 네이티브는 endSet 때 세트 요약(scope set) → 녹화 파일 닫기 → `onSetEnd {setIndex, videoLocalPath|null, worstJoint|null}`.
- worstJoint = 그 세트에서 가장 많은 렙에 걸린 **켜진**(enabledFeedbackKeys) 경고 키의 관절, 동률은 규칙 순서(등급 높은 것). 꺼진 키는 검증 안 된 판정이라 사용자에게 새지 않게 뺐다 → 지금 기본값에선 항상 null. 키→관절 표는 `FeedbackJoint.byKey`, dart 경고 키 집합과 같음을 테스트로 고정.

### E6. 세트별 녹화(기본 OFF)·perf 로그·보관 개수
- 녹화: 포즈 추정에 쓴 같은 샘플 버퍼를 AVAssetWriter(H.264, 720p = 캡처 720×1280 그대로, 2.5 Mbit/s)로 `Documents/workout_videos/<시각>_<운동>_set<k>.mp4`. 카메라 세션 추가 없음.
- 기본 OFF: 실기기 FPS 측정 전(사용자 일). 켜기: 실행 환경변수 `BPT_SET_RECORDING=1` 또는 UserDefaults `BPTSetRecording`. 측정에서 FPS 감소 ≤10%면 기본 ON으로 바꿀 것. 절차 docs/research/set_recording_perf.md, 비교 `scripts/compare_perf_logs.py`.
- perf 로그: `BPT_PERF_LOG=1` → 1초마다 `workout_form_logs/perf_<운동>_<시각>.jsonl` {pose_fps, dropped_frames, thermal, battery, recording}.
- 보관 N = 20: 운동 1회 ≈ 2종목 × 5세트 = 10파일, 최근 2회분. 1분 세트 ≈ 19 MB라 최대 ≈ 0.4 GB. 새 녹화 시작 때 오래된 것부터 지움. 서버엔 경로만 저장되므로 지워진 옛 기록의 영상은 재생 불가 — 앱이 파일 없음을 처리해야 함(팀원).

### E7. main의 팀원 음성(#40, 0d00676)과 겹침 — 경쟁 경로를 만들지 않는 방식
- 확인한 사실(origin/main, integration/ai엔 아직 없음): `KoriVoiceService.speak`(채널 `bpt/kori_voice` → 네이티브 `KoriSpeaker`, ElevenLabs 실시간 합성·실패 시 AVSpeech)가 onFeedback마다 말풍선 대사를 말하고, 말하던 것을 매번 끊는다(대기열·★·3초 버림 없음). 음소거 버튼은 화면 표시만 바뀌고 음성은 안 끔. onFeedback은 `{key, n}`만 읽고 `scope`는 모름, `endSet/startSet`은 안 보냄.
- 결정: 네이티브 WorkoutVoice는 **Flutter가 onFeedback에 대사를 답할 때만** 말한다(E3). main의 핸들러는 null을 돌려주므로 main 코드 그대로면 WorkoutVoice는 소리를 내지 않는다 → 이중 재생이 구조적으로 안 생김. integration/ai의 화면(이 트랙이 고친 판)은 답을 돌려주고 자체 TTS 호출은 없음.
- 채널 계약 충돌 없음: 메서드 이름(`onFeedback`·`onPoseUpdate`) 같음, 키 이름은 같은 dart 표 기준(테스트), `scope`는 main이 무시해도 안전(세트 요약은 세트 끝난 뒤 와서 main에선 버려짐), `n`은 E1대로 맞춤. `setVoiceMuted`·`startSet`·`endSet`·`onSetEnd`는 새 메서드라 main 쪽엔 없음(없으면 녹화가 1세트 파일 하나로 이어지고 onSetEnd가 안 옴 — 녹화는 기본 OFF).
- 팀원 합의 필요(main과 합칠 때 한쪽 선택): (a) 네이티브 WorkoutVoice 유지(★·대기열·음소거 처리) + 음원 백엔드를 KoriSpeaker(ElevenLabs)로 바꿔 끼우기, Flutter의 `_speakFeedback` 호출 제거 — 권장. (b) 팀원 Flutter TTS 유지, onFeedback 답을 null로 → WorkoutVoice 무음, 대신 음소거 버튼을 KoriVoiceService에 연결해야 함. 어느 쪽이든 native_pose_workout_screen.dart는 양쪽이 고쳐서 수동 병합 필요.
