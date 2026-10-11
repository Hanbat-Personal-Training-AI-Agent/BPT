# 코리 음성 mp3 파일 이름 규칙 (팀원이 직접 생성해서 넣을 때)

음성 파일은 팀원이 ElevenLabs에서 직접 뽑아 넣는다. 생성 스크립트(`scripts/generate_kori_voice.py`)는 쓰지 않기로 해서 삭제했다(2026-10-11, D-H-02). 앱이 파일을 찾는 규칙만 남긴다.

| 파일 | 내용 | 찾는 쪽 |
|---|---|---|
| `assets/kori_voice/<key>.mp3` | 자리표시자 없는 운동 대사 (`<key>` = `lib/features/workout/data/kori_feedback_lines.dart`의 key) | WorkoutVoice (`workoutVoiceAudioNames`, 트랙 E) |
| `assets/kori_voice/<key>_<n>.mp3` | `{n}`·`{reps}`·`{k}`가 들어간 대사, 숫자별 파일 | WorkoutVoice: `<key>_<n>` → 없으면 기기 TTS |

- 파일이 없으면 기기 TTS(AVSpeechSynthesizer ko-KR)로 말한다. 일부만 넣어도 된다.
- 앱에 넣을 때 `pubspec.yaml`의 `flutter: assets:`에 `assets/kori_voice/`를 추가한다.
- 캘리브레이션 안내 음성은 main #40의 `KoriSpeaker`가 맡는다.
