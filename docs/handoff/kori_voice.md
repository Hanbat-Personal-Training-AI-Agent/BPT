# 코리 음성 파일 (ElevenLabs) — 트랙 H

스크립트: `scripts/generate_kori_voice.py`, 테스트: `tests/test_generate_kori_voice.py`.

## 대사 원문 (복사하지 않고 매번 파싱)
- 운동: `lib/features/workout/data/kori_feedback_lines.dart`의 `key`·`ko` (28키)
- 캘리브레이션: `ios/Runner/NativePose/Calibration/CalibrationTypes.swift`의 `CalibrationGuidance.message` (27줄 = 고정 23 + 촬영 완료 4방향)
- 대사를 바꾸면 해당 파일만 고치고 `--only <키> --overwrite`로 다시 생성.

## 파일 이름
| 파일 | 내용 | 찾는 쪽 |
|---|---|---|
| `assets/kori_voice/<key>.mp3` | 자리표시자 없는 운동 대사 | WorkoutVoice (`workoutVoiceAudioNames`, 트랙 E) |
| `assets/kori_voice/<key>_<n>.mp3` | `{n}`·`{reps}`·`{k}` 대사, n = 1..20 (`--max-n`) | WorkoutVoice: `<key>_<n>` → 없으면 TTS |
| `assets/kori_voice/calibration_<case>.mp3` | 캘리브레이션 안내, `<case>` = Swift case 이름 (예: `calibration_holdPhoneUpright`) | CalibrationVoice (아직 TTS만 씀 — 연결 필요) |
| `assets/kori_voice/calibration_captured_<view>.mp3` | 촬영 완료 (`front`, `rightfront`, `back`, `leftfront`) | 같음 |

- 숫자는 세는 말로 읽힘: `{n}번` → "세 번", `{reps}개` → "열 개" (`native_count`).
- `praise_clean_set`(`{reps}`)·`set_summary`(`{k}`)도 `<key>_<n>`으로 만듦. 앱이 이 키에 숫자를 n으로 넘기지 않으면 TTS로 떨어짐(트랙 E와 맞출 것).
- 한국어만 생성. 영어는 기기 TTS.
- 앱에 넣을 때: `pubspec.yaml`의 `flutter: assets:`에 `assets/kori_voice/` 추가(트랙 E 메모).

## 실행
```sh
# 키 없이 목록·글자 수만 (네트워크 안 씀)
conda run -n bpt-eval python scripts/generate_kori_voice.py --dry-run
# 생성: 키는 환경변수로만. 이미 있는 파일은 건너뜀(--overwrite로 다시)
ELEVENLABS_API_KEY=... conda run -n bpt-eval python scripts/generate_kori_voice.py --voice-id <voice id>
```
- 옵션: `--set workout|calibration`, `--only key1,key2`(키 또는 접두사), `--max-n 20`, `--model-id eleven_multilingual_v2`, `--out`.
- 키는 인자로 받지 않고 출력·로그에 찍지 않음. 셸 기록에 남지 않게 `read -s ELEVENLABS_API_KEY; export ELEVENLABS_API_KEY` 권장.

## 비용
- 전체(운동 28키, 숫자 1..20 + 캘리브레이션 27줄): **188파일, 5,623자**(`--dry-run` 출력).
- ElevenLabs는 글자 수로 크레딧을 씀. Starter 월 크레딧(약 30,000자, 추정 — 가격 페이지 확인 필요) 안에 여러 번 다시 만들 수 있는 양.
- 결제·키 발급·목소리(voice id) 선택은 사용자 몫. 상업 이용 조건은 요금제 약관 확인(Free 요금제는 출처 표기 필요, 추정).
