# 세트별 녹화 성능 측정 (녹화 OFF vs ON, 사용자 실기기)

녹화는 측정 전까지 기본 OFF(`WorkoutDebugFlags.setRecording`). 결과 FPS 감소가 10% 이하면 기본 ON으로 바꾼다.

1. 준비: 배터리 50% 이상, 케이블 뽑기, 폰 위치·조명 고정. 설치 `flutter build ios --profile && xcrun devicectl device install app --device 6886E076-24C5-54CD-BE2A-7B4276775949 build/ios/iphoneos/Runner.app`
2. OFF 먼저: `xcrun devicectl device process launch --device 6886E076-24C5-54CD-BE2A-7B4276775949 --terminate-existing --environment-variables '{"BPT_PERF_LOG":"1"}' com.bpt.bpt` → 스쿼트 운동 화면을 열고 카메라 앞에서 5분 동안 스쿼트·서 있기 → 앱 종료.
3. 5분 식힌 뒤 ON: 같은 명령에 `"BPT_SET_RECORDING":"1"`를 더해 실행하고 같은 자리에서 5분.
4. 로그 받기: `xcrun devicectl device copy from --device 6886E076-24C5-54CD-BE2A-7B4276775949 --domain-type appDataContainer --domain-identifier com.bpt.bpt --source Documents/workout_form_logs --destination perf_logs` (Finder 파일 공유도 됨).
5. 비교: `python scripts/compare_perf_logs.py perf_logs/perf_squat_<OFF시각>.jsonl perf_logs/perf_squat_<ON시각>.jsonl` → 표의 FPS 감소가 10%를 넘으면 녹화는 OFF 유지(videoLocalPath = null).
