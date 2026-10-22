# 클로드 중단 작업 복구 (2026-10-20)

사용자가 기존 작업의 계속 수행을 요청했다. 로컬 클로드 주 대화와 하위 에이전트 기록, `~/Documents/bpt-handoff/SESSION_HANDOFF.md`, 각 작업 폴더의 변경 상태를 대조했다. 기존 결과를 다시 만들지 않고 22:17–22:25의 사용량 제한 중단 지점에서 이어간다.

## 실행 순서와 담당

| 담당 | 작업 폴더 | 이어받은 범위 |
|---|---|---|
| halpe_device | ai-halpe-default, ai-lift-app | Halpe26 전환의 CSV 발 6점 보존 마무리, 번들 검증, 동일 기기 빌드 COCO17/Halpe26 비교 |
| orientation | ai-orientation, 기존 orient 시험 폴더 | 가로 분석 회전, 방향 변경 때 3D 시계열 초기화, 세로 회귀와 90°/270° 점검 |
| home_training_rules | ai-finetune3, ai-rules-calib | 살아 있는 학습·평가 사슬 인수, C3 입력 비교 검증, C1 몸통 경고 보류 처리 |
| 주 에이전트 | ai-setup-constraint | 준비 자세·가림 결과 회수, 손목 v2 재생 검증과 평가 시작 시점 수정 |

무거운 Mac 작업은 `/tmp/bpt-heavy.lock` 하나로 직렬화한다. 기기 담당이 iPhone을 단독 사용한다. Home GPU 작업은 기존 `~/.bpt-gpu.lock`과 현재 학습 사슬을 유지한다. Python은 각 호스트의 기존 conda 환경을 사용한다.

## 보존과 판단

- 주 체크아웃 `feat/ai`의 lock 파일 변경과 미추적 영상 스크립트는 그대로 둔다.
- 기존 작업 폴더의 미완성 코드·결과를 보존한다. 새 실험 결과는 별도 경로와 SHA-256 manifest에 기록한다.
- D8 승인 범위는 운동 m Halpe26 전환, 캘리브레이션 s COCO17 유지다.
- integration/main 병합, 추가 모델 채택, 새 자세 경고의 기본 활성화는 이번 복구에 포함하지 않는다.
- Fit3D는 Home에 유지하고, Fit3D·Exercise3D 사진/영상은 표시하거나 git에 넣지 않는다.

## 준비 자세·손목 체크포인트

`docs/results/setup_constraint.md` 9절에 최신 결과와 남은 검증을 기록했다. 기존 Home B2 체인은 완료됐지만 가림 보정의 R1·R3·R5는 통과하지 못했다. 손목 v2도 W1·W4가 통과하지 못했으므로 실험 상태를 유지한다.

`scripts/eval_wrist_anchor.py`의 CSV 점검이 실제 첫 렙 카운트 대신 라벨로 시작 시점을 추정하던 문제를 수정했다. 17점/26점 CSV를 같은 이름 기반 관절 열로 읽고, 기기 frame 번호를 행 인덱스로 매핑한다. 원래 결과는 보존하고 새 결과는 `~/Documents/bpt-handoff/resume-20261020/wrist-v2-recorded-reps/`에 저장했다.

다른 담당의 최종 결과는 각 브랜치의 `docs/results/`에 기록하며, 전체 재개 기록은 `~/Documents/bpt-handoff/resume-20261020/`에 모은다.
