# reacquire 트랙 재개 메모 (2026-10-19, 재부팅으로 중단)

- 스크래치: `/private/tmp/claude-501/-Users-6-month-github-06-month-hanbat-repositories-BPT/d083b446-4e06-45ed-8204-8c6e9f22bd1c/scratchpad` (재부팅 뒤 /private/tmp는 지워질 수 있음 → 사본 Home `~/bpt-runs/reacquire/_tools/scratch/`, 실행 출력 `~/bpt-runs/reacquire/<ds>__<cfg>/`, 각 폴더 manifest_<model>.json).
- 바이너리: 커밋 0d4724c 빌드 `bin/pose-replay-0d4724c`(sha256 fbee0539…21e2, Home `_tools/pose-replay-ba62142` 옆에 복사 필요 시 다시 빌드: `swift build -c release --product pose-replay`).
- **완료**: fake·e3dkeep·e3d·mmfit(Home 클립) 모든 후보, mmfit_mac·mmfit_ref(eval-reliability 클립) 후보, public cur·s15·lb·m0.8(COCO17) 두 모델 / m0.8 COCO17. 탐색 대상에서 뺀 public 후보(a4·a5·h*·s5·s30·det30·m0.5·s15+m0.5)는 MM-Fit·Exercise3D 조정 결과로 제외.
- **남음**: public m0.8 halpe26(289/544 클립 끝, manifest_halpe26_INCOMPLETE.json), public det mcoco17, public det halpe26. 그 뒤 표 생성·선택·문서(D-T3-20)·최종 보고.
- **재개 명령**(스크래치에서):
  ```
  conda run --no-capture-output -n bpt-eval python run.py public m0.8 halpe26 --only-lost
  conda run --no-capture-output -n bpt-eval python run.py public det mcoco17 --only-lost
  conda run --no-capture-output -n bpt-eval python run.py public det halpe26 --only-lost
  conda run --no-capture-output -n bpt-eval python choose_cfg.py cur,lb,s15,m0.8,det
  conda run --no-capture-output -n bpt-eval python report.py public cur,lb,s15,m0.8,det "tune|held"
  ./sync_all.sh
  ```
  (스크래치가 지워졌으면 Home `_tools/scratch/`와 `<ds>__<cfg>/`를 되돌려 받고, 클립은 Home `clips/`·`datasets/`에서 다시 복사.)
- 기기(iPhone) 측정: 앱 실행이 코드 서명 신뢰 문제로 거부되어 미측정(사용자가 기기에서 개발자 프로필 신뢰 필요).
- 2026-10-19 14:01:43 완료: public m0.8 halpe26 --only-lost (manifest out/public/m0.8/manifest_halpe26.json, Home ~/bpt-runs/reacquire/public__m0.8/)
- 2026-10-19 14:31:29 완료: public det mcoco17 --only-lost (manifest out/public/det/manifest_mcoco17.json, Home ~/bpt-runs/reacquire/public__det/)
- 2026-10-19 16:16:59 완료: public det halpe26 --only-lost (재부팅 뒤 스크래치 복원: Home _tools/scratch·<ds>__<cfg>·clips·datasets(mendeley clips30, yt_cc segments)·eval-reliability clips, 입력 클립 sha256 4849/4849 manifest와 같음, 바이너리 fbee0539…21e2 Home 사본 그대로; 복원한 출력으로 만든 e3d·mmfit 조정·MM-Fit 3클립 표가 재부팅 전 표와 같음. 이번 실행 204클립 manifest out/public/det/manifest_halpe26.json, 재부팅 전 340클립(재사용 300)은 manifest가 없어 manifest_halpe26_prereboot.json에 사후 기록, Home ~/bpt-runs/reacquire/public__det/). 사용자 지시로 실험은 여기서 멈춤(새 후보·재실행 없음).
