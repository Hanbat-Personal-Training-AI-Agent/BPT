# 평가 데이터 출처·라이선스 장부 (트랙 data-collect, D-DATA-01)

- **용도: 평가 전용(비상업 캡스톤).** 학습·미세조정·앱 배포 자산에 쓰지 않는다. 영상·프레임·키포인트는 git에 넣지 않는다(라벨 CSV와 집계만 커밋).
- 원본 위치: `ssh Home` `~/datasets/<name>` (Mac에는 pose-replay 할 때 배치 단위로만 복사하고 바로 지움).
- 사람(피험자·채널) 단위 조정/검증 분할: `data/eval_sources/split.csv` (평가 전에 고정, `scripts/data_collect/make_split.py`, seed 20261012).

## 사용한 출처

| 이름 | 라이선스 (원문 위치) | 받는 법 | 크기 | 운동·시점 | 사람 | 라벨 |
|---|---|---|---|---|---|---|
| **mendeley_mv7** — "A Multi-View Raw Video Dataset of Seven Fitness Exercises with Good/Bad Form Labels", Mendeley Data v3, doi:10.17632/kgbb3yn47p.3 | **CC BY 4.0** — 데이터셋 메타데이터 `data_licence` 필드: https://data.mendeley.com/public-api/datasets/kgbb3yn47p?version=3 (Home `~/datasets/mendeley_mv7/metadata_v3.json`에 사본) | 로그인·신청 없음. `curl -L -A "Mozilla/5.0" https://data.mendeley.com/public-files/datasets/kgbb3yn47p/files/a31fa913-6f29-4c31-b1a6-414a718eebf4/file_downloaded` (Exercise-wise zip) | zip 3.11 GB(7운동 1,042개). 사용 3운동 438개 1.3 GB, 클립당 약 30 s, 15 fps, 810×1440 | 바디웨이트 스쿼트 150, 푸시업 144, **덤벨** 벤트오버 로우 144 · 정면/측면/사선 각각 | 26명(subject 001–026). 얼굴(가끔 몸 전체) 블러 처리됨 | 클립 단위 good/bad만 → 렙 수·잘못된 자세 키는 우리가 직접 라벨(2회 독립) |
| **youtube_cc** — YouTube "크리에이티브 커먼즈" 필터 검색 결과 중 영상 자체 `license` 필드가 "Creative Commons Attribution license (reuse allowed)"(= CC BY 3.0)인 것만 | **CC BY (YouTube 표준 CC BY 3.0)** — 영상별로 `yt-dlp --print license` 재확인, 영상 URL·채널·라이선스는 `data/eval_sources/youtube_cc_labels.csv`에 기록 | 검색 `scripts/data_collect/yt_cc_search.py`(Mac에서 실행: Home IP는 YouTube 봇 확인에 걸림), 720p 이하만 받고 필요한 구간만 잘라 30 fps로 저장 | 133 구간, 총 약 30분, 180 MB | 스쿼트 47, 푸시업 43, 바벨로우 43(덤벨 4 포함) · 측면/사선/정면/후면 | 43채널(채널 = 분할 단위, 같은 사람이 여러 채널에 있지 않음을 확인한 것은 아님) | 튜토리얼의 잘못된 자세 시연 포함. 렙 수·키는 우리가 직접 라벨(2회 독립) |

저작자 표시(CC BY): mendeley_mv7 — 데이터셋 페이지의 저자(Mendeley Data, doi 위). YouTube — 각 구간의 채널명·URL을 라벨 CSV `url`/`notes`에 기록. 수정 사항: 구간 자르기, 30 fps·720p로 재인코딩, 접촉 시트(라벨용 정지 이미지) 생성.

## 확인했지만 안 쓴 출처

| 이름 | 라이선스·접근 (확인 위치) | 안 쓴 이유 |
|---|---|---|
| Fitness-AQA (Parmar 외; BackSquat·BarbellRow·OHP 오류 라벨) | 자체 약관 + CC BY-NC 4.0, Google Form 신청(https://github.com/ParitoshParmar/Fitness-AQA, `fitness_aqa_dataset_license.pdf`) | 신청이 수동 승인(README: 안 오면 저자에게 연락). 영상도 YouTube/Instagram 제3자 콘텐츠. 바벨로우 오류 라벨은 이것뿐 → 사용자 신청 필요 |
| QEVD / QEVD-FIT-300K / FIT-COACH (Qualcomm) | Qualcomm Dataset Research License(https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/documents/Dataset-Research-License-Feb-25-2025.pdf), Qualcomm ID 로그인 후 다운로드 | 로그인 필요(자동 신청 아님, 확인 불가). 대부분 정면. 푸시업 "hips too low/high, head down" 라벨은 매우 적합 → 사용자 계정으로 받기 권장 |
| FitAQA (HF `Kelly0510/FitAQA`) | Apache-2.0, 주석만 | 영상 없음(QEVD/EgoExo를 가리킴) |
| EC3D (Zhao 외, ACCV'22) | 라이선스 명시 없음, Google Drive | RGB 영상 없음(3D 스켈레톤 pickle만) |
| FLAG3D | 서명 동의서 이메일 | 수동 승인 |
| PoseTrainer | 코드 GPL-3.0 | 스쿼트·푸시업·로우 없음, 포즈만 |
| UCO Physical Rehab / KIMORE / UI-PRMD | 요청 필요 / 공식 페이지 403 / 404 | 접근 불가 또는 스켈레톤만 |
| PushUpBench (HF `anonymousatom/pushupbench`) | CC BY 4.0(HF 카드) | 표준 푸시업이 거의 없음(변형 동작), 영상 출처 불명 |
| InfiniteRep | HF 미러 "research-use" | 합성 아바타(실제 사람 아님) |
| EgoExo-Fitness | 서명 라이선스 PDF 이메일 | 수동 승인, 74 GB 프레임 아카이브 |
| MyoMechanix/FLEX | CC BY-NC-SA, 검토 후 승인 | 수동 승인 |
| Kaggle workout 영상 모음 | CC BY-NC-SA 등이나 원본이 YouTube 표준 라이선스 | 제3자 영상 |
| RepCount-A, Countix | (이전 트랙에서 라이선스 문제로 제외) | 제외 유지 |
| Exercise3D, Fit3D, MM-Fit | 이미 사용 중 | 이 트랙 대상 아님 |

## 데이터 품질 메모 (mendeley_mv7)
- md5가 같은 파일 27개(13묶음)가 있다. 다른 피험자끼리 같은 파일인 경우도 있음(예: subject_005·006 스쿼트 측면 good/bad, 014·020 푸시업 bad 측면, 010·013 푸시업 good 측면). **묶음 전체를 평가에서 제외**(`scripts/data_collect` 실행 시 `dup_exclude`), subject_007_squat_good_diagonal은 로우 영상이라 제외.
- 얼굴 블러(일부 프레임은 몸 전체 블러), 역광 체육관 → 관절 신뢰도가 전반적으로 낮다(예: subject_001 스쿼트 측면 평균 0.4–0.6). 결과는 앱 실사용보다 나쁘게 나올 수 있다.
- 15 fps → 앱 가정(30 fps)에 맞춰 프레임 복제로 30 fps 재인코딩(새 정보 없음).
- "back" = 덤벨 벤트오버 로우(바벨 아님). BarbellRowEvaluator로 평가.
