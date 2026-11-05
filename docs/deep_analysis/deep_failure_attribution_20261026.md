# 심층분석 실패 원인 분해와 다음 검증 — 2026-10-26

**기존 사전 평가의 FAIL은 유지한다.** 이번 작업은 새 GPU 실행 없이 보존한 점수·계측과 실제 코드를 읽어 실패를 분해했다. 평균 관절각 개선, 인증 API 성공, 네이티브 앱 빌드 성공은 각각 확인됐지만 경계 판정·60초 처리시간·폰 전체 운동 E2E의 통과를 뜻하지 않는다. 제품 모델은 MotionAGFormer-XS 유지, 기본값·서버 설정·배포·기존 평가 기준은 변경하지 않았다.

## 1. 확인한 자료와 수행 범위

기반은 final-validation `b0904bb`이며 독립 브랜치에서 수행했다. Home frozen 소스 HEAD `54cd739452a7d18d7fdda27efff99356b752f8a8`와 `~/bpt-runs/gvhmr-eval-20261026/score_full_private.json` 존재를 확인했다. 추가 추론·학습·GPU 호출·영상/이미지 열람·새 데이터 다운로드·기기 호출은 없다. Home CPU에서 기존 숫자 점수만 읽었다. GT는 평가에만 사용했으며 예측 입력이나 앵커로 사용하지 않았다. 피험자/카메라/반복 식별자·원배열·프로필은 반출하지 않았다.

기존 [정량 평가](gvhmr_fit3d_20261026.md), [척추 proxy 분석](spine_proxy_20261026.md), [인증·성능 보고서](../results/deep_authenticated_flow_20261026.md)를 먼저 읽었다. 새 [경계 집계 JSON](gvhmr_boundary_attribution_20261026.json)은 기존 Bw/Cw 계산을 다시 추론하지 않고 저장된 rep_metrics를 분해한다. 모든 기존 nearTotal/nearAgree 집계와 정확히 일치했다. 표본은 로우 경계 3항목·반복, 푸시업 경계 1항목·반복으로 매우 작다. 아래 FP/FN은 **GT 관절각 임계값 대비 불일치 방향**이며 전문가 오자세 라벨의 precision/recall이 아니다.

Mac에 보존한 run60 `report.json`의 timingSeconds, runnerElapsedSeconds, processingTimingSeconds가 저장소 집계와 모두 일치함도 확인했다. 해당 private 보고서 SHA256은 `834eeaa826f64d81fb0615ed76ba16501e085dddd985aad2ce760c1dcba8b360`이다. 비공개 원문이나 개인 관절은 이 문서에 옮기지 않았다.

## 2. 어떤 경계 판정이 실패했는가

frozen scorer의 비교는 `value > threshold`이며 동점은 경고 아님이다. GT가 임계값 ±5° 안인 유한한 항목만 경계 분모에 들어간다. 스쿼트 shallow/no_lockout 및 푸시업 shallow에는 경계 사례가 없었다. 로우는 `torso_range`, 푸시업은 `no_lockout`에서 원래 FAIL이 발생했다.

| 항목 | 정의·문턱 | A | B / C | 불일치 방향 |
|---|---|---:|---:|---|
| row_torso_swing | 반복 내 부호 없는 몸통 수직각 max−min >39.9° | 2/3 | 각각 1/3 | B/C 각각 2 false negatives |
| pushup_no_lockout | 현재까지 반복의 elbow_max 최댓값−현재 반복 elbow_max >10° | 1/1 | 각각 0/1 | B/C 각각 1 false positive |

로우의 실패 2개에서 GT margin은 문턱보다 **+2.203…+2.866°**였다. B의 range 오차는 **−14.172…−7.251°**, C는 **−14.111…−6.909°**였다. 따라서 B의 예측 margin은 **−11.306…−5.048°**, C는 **−11.246…−4.706°**로 문턱 반대편에 놓였다. B/C는 A가 맞춘 경계 사례 1개를 추가로 놓쳤다. 평균 각도 MAE 개선이 반복의 max−min 보존을 보장하지 않는 구체적인 예다. 현재 점수에는 torso_range만 저장돼 있어 GT 극값 프레임의 단일 잡음인지, 예측 동작 범위 압축인지, 관절 정의 차이인지까지 분리하지 못한다.

푸시업 실패에서 GT deficit margin은 **−2.738°**였지만 B 오차 **+3.984°**, C **+3.343°**가 더해져 예측 margin이 각각 **+1.246° / +0.605°**가 됐다. 기존 elbow_max를 분해하면 원인이 단순한 각도 상수 오프셋만은 아님을 확인할 수 있다.

| 실패 경계의 성분 | B | C |
|---|---:|---:|
| running-set 최대 elbow_max 오차 | −10.277° | −10.487° |
| 현재 반복 elbow_max 오차 | −14.261° | −13.830° |
| deficit 오차 = 위 행−아래 행 | +3.984° | +3.343° |

즉 현재 반복의 최대 폄을 기준 반복보다 더 적게 추정한 **차등 오차**가 임계값을 넘겼다. 전체 elbow 각도에 동일한 보정값을 더하는 것만으로 이 상대 지표 오차가 해결되지 않는다. 이 결과로 오프셋 보정이나 임계값 완화를 적용하지 않았다.

### 좌표 정의 민감도는 별도 진단이다

GT 몸통은 Fit3D world-up, A/B/C 몸통은 camera image-up −Y, Bw/Cw는 별도로 저장된 GVHMR world joints의 +Y를 쓴다(`eval_gvhmr_fit3d.py:220–224`). torso는 어깨 중점−고관절 중점의 부호 없는 수직 대비 각이다(`eval_3d_angles.py:60–63`). 실제 요추 굽음이나 현재 팀 카탈로그의 signed P95−P05 swing과 다른 정의다.

기존 집계만으로도 Bw/Cw가 로우1/3·푸시업0/1임을 알 수 있었다. 새 분해에서는 camera→world 전환이 **로우3개·푸시업1개 경계 중 어떤 판정도 바꾸지 않았음**을 확인했다. 따라서 이번 FAIL을 image-up/world-up 차이 하나로 설명하거나 world 열로 통과시키는 것은 근거가 없다. 팔꿈치 내부각은 원래 rigid rotation 불변이고 up 벡터를 사용하지 않는다. Camera/world 배열은 별도로 후처리된 예측이므로 작은 elbow 값 차이까지 up축 변경의 효과라고 해석하지 않는다. GT 관절 정의 및 모델 후처리 차이는 여전히 남는다. floor oracle도 로우2/3에 그쳐 정의 차이 진단의 필요성을 보여 주지만 오차 하한이나 제품 정확도 보장은 아니다.

## 3. 60초 처리시간의 병목과 제거 가능한 작업

인증 run60은 worker **356.878초**, runner **319.048초**였다. runner만으로도 180초를 넘는다. baseline30/60은 동일 프로세스의 작업1/2지만 모델은 매 작업 다시 로드한다. CPU4 단회 결과는 worker368.576/runner329.556초였고 개선을 입증하지 못했다. 서로 다른 프로세스·조건당1회이므로 CPU 설정의 인과 효과도 확정하지 않는다. 반복한 캘리브레이션 영상은 운동 정확도 시험이 아니다.

| runner stage | 초 | runner 대비 | 코드상 포함 범위 |
|---|---:|---:|---|
| normalize | 20.552 | 6.44% | OpenCV decode/rotation/frame pick/PyAV H.264 encode |
| track | 67.087 | 21.03% | YOLOv8x 생성·프레임별 추적·track 정렬/보간/평활화 |
| vitpose | 140.817 | 44.14% | ViTPose-H 로드·공통 crop 준비·16프레임씩 원본+flip 추론·UDP decode |
| features | 81.837 | 25.65% | HMR2 로드·동일 crop 재준비·16프레임씩 추론 |
| network | 3.765 | 1.18% | Hydra/model/가중치 로드와 GVHMR predict |
| postprocess | 4.748 | 1.49% | SMPL-X→H36M 관절, 체형 처리 |

단계 합318.806초와 runner의 차이는 **0.242초**다. 많은 시간이 알 수 없는 wrapper overhead에 숨어 있는 상황이 아니다. track+vitpose+features가 **289.741초(90.81%)**다. 각 stage는 GPU 계산뿐 아니라 CPU 준비·로드·전송·후처리를 포함하므로 289.741초를 순수 GPU 시간으로 부르지 않는다.

worker−runner **37.830초**에는 외부 normalize6.841초, render22.803초, metrics0.024초, 저장소 입출력·진행률·정리 등이 포함된다. 누적 analyze/infer/worker 시간을 다시 더하지 않는다. runner180초를 위해 관측치의43.58%, worker180초를 위해49.56% 감소가 필요하다는 것은 **산술상 요구량**이며 가능한 개선률 예측이 아니다. 외부 작업·작은 GVHMR network만 손봐서는 충분하지 않다.

### 코드로 확인한 중복과 최소 제안 (미구현·미측정)

1. **동일 crop/decode 준비를 1회 공유하는 후보가 우선이다.** runner `vitpose:157–160`과 `features:179–181`이 같은 영상·bbx·img_ds=0.5로 각각 get_batch를 부른다. Home upstream ee960bb의 vitpose.py는 `from .vitfeat_extractor import get_batch`이므로 실제로 같은 함수다. 이 함수는 read_video_np→GaussianBlur→crop_and_resize→동일 정규화 tensor를 매번 생성한다. 한 번 만든 CPU tensor/box를 두 기존 stage가 읽도록 하고, ViTPose의 `32:224` slice·flip·UDP 및 HMR2 입력은 그대로 유지하는 제안이다. 모델·배치16·가중치·추론 순서·입력 픽셀을 바꾸지 않는다. full tensor를 공유하면1800×3×256×256×4 ≈1.42GB(1.32GiB)이며 디스크 캐시는 필요하지 않다. 기존에도 stage마다 전체 tensor를 만들지만 공유 수명과 decoder 임시배열 때문에 RSS peak는 따로 검증해야 한다. 시간 중 얼마가 중복 준비인지 현재 계측은 분리하지 않으므로 절약 초수는 주장하지 않는다.
2. **중복 영상 정규화는 실제 존재하나 바로 제거하면 동일성 보장이 없다.** deep_worker `analyze:164–169`의 ffmpeg 정규화 후 runner `run:321`의 normalize_video가 다시 손실 H.264로 쓴다. 6.841+20.552초의 경로지만, 두 코드는 PTS/저FPS 복제·메타 회전·frame pick·인코딩 정책이 다르다. 단순 skip은 픽셀과 경우에 따라 프레임 대응을 바꾼다. 안전한 CPU crop 공유와 분리해, 향후 단일 canonical 입력 계약·PTS/회전/프레임수·픽셀/각도 영향 검증이 필요한 변경으로 남긴다. 현재 frozen 평가 및 서비스 출력은 바꾸지 않는다.
3. **모델 재로드는 확인됐으나 비용은 미분리다.** runner158/180/205–207에서 모델을 생성하고 각 stage 끝에서 del/empty_cache한다. 프로세스 재사용은 모델 재사용이 아니다. 향후 각 load/crop/forward/CPU decode 시간을 분리한 계측을 먼저 제안한다. 세 대형 모델을 동시에 GPU에 보관하거나 배치를 늘리는 것은 현재 측정된 저메모리 수치로 안전하다고 추론할 수 없다. YOLO를 재사용할 경우 tracker identity state를 작업마다 완전히 재설정해야 한다.
4. **거절할 다중 인물 영상도 현재는 끝까지 추론한다.** runner track 단계에서 others를 알지만 deep_worker171–172는 run이 전체 완료된 뒤 multiple_people를 거절한다. server-only 조기 거절 옵션은 실패 입력의 낭비를 줄일 후보지만 성공한 run60 병목 해결책은 아니다. standalone frozen evaluator의 다중 인물 처리와 서버 오류 우선순위를 섞지 않도록 별도 계약/모사 테스트가 필요하다.

위 제안의 최소 검증 순서는 (a) GPU 없이 crop 공급 경로 호출1회·동일 tensor/box·모델별 slice 및 순서 계약을 합성 데이터로 확인, (b) 허용된 기존 입력에 대한 전처리 tensor hash와 메모리/하위단계 시간만 확인, (c) 이후 root가 승인한 **한 번의** 통제 GPU 비교에서 stage·worker 시간과 예측/판정 동등성 함께 검사다. 이번 작업에서는 a–c 변경이나 GPU 비교를 실행하지 않았다. 같은 입력에서도 CPU4 비교가 수치적으로 달랐다는 기존 증거 때문에 속도만 확인하고 동등성 검사를 생략할 수 없다. fp16/모델 축소/flip 제거/프레임 감소/배치 변경은 이 correctness-preserving 제안에 포함하지 않는다.

추적 함수의 docstring은 longest track이라고 하지만 upstream sort_track_length는 실제 bbox 면적 합으로 정렬한다. 이는 메인 인물 선택의 의미 확인 항목이지 속도를 위해 바꿀 부분이 아니다. 이번에는 정렬·출력·기준을 변경하지 않았다.

## 4. 폰 전체 앱 경계는 무엇이 남았는가

실제 인증 API 업로드→완료→L4→서명 report/video GET 및 거절/멱등성 검사는 완료됐다. native source770b2a0의 일반/local_capture/existing_report signed Release 빌드는 기록돼 있다. 이것을 실행 완료와 혼동하지 않는다. 최신 b0904bb의 C3 수집 완료 기록도 아래 deep 하니스의 완료 증거를 대신하지 않는다. 이번 작업은 폰·CoreDevice·파일 서비스·빌드에 접근하지 않았다.

실제 검증용 소스는 `a05848a`에서 들어온 `integration_test/deep_local_capture_test.dart`와 `deep_existing_report_test.dart`를 읽었으며, device review worktree에서770b2a0 대비 두 파일 변경 없음도 확인했다.

| 준비된 경로 | 코드가 검사하는 것 | 아직 입증하지 못한 것 |
|---|---|---|
| local_capture | 기존 로그인 복원, 단일 로컬 clip/1회 loop, 녹화 파일20개 미만 사전조건, 실제 native rep→setEnd→video_ms manifest, 단조·비중첩·≤60초 경계, 파일크기/영상길이/720×1280, 메모리 queue 및 deep API 시도0 | 실기기 실행 자체, 실제 카메라30/60초·가로/세로·발열/FPS·무음 메타·프레임별 경계 정렬, 반복/자세 정확도 |
| existing_report | 기존 동의 IMG9900 완료 job 정상 계정 GET, VideoPlayer 초기화, 중간 seek(500ms 허용), provider identity null 뒤 플레이어 폐기·안내, 저장 로그인 유지 | 실기기 실행 자체, 실제 로그아웃/계정전환, 전체 UI 문구/타임라인 의미, 50분 URL 갱신, 공유·사진 저장·권한 분기 |

local_capture는 canUpload=false와 모든 deep 전송 메서드의 강제 거절, loadQueue=[]/saveQueue=no-op으로 데이터셋 전송을 막는다. auth 복원은 별개다. report 하니스는 새 업로드 없이 기존 동의 job만 사용한다. 두 결과를 합쳐 실제 운동 녹화→업로드→정확한 운동 리포트 전체 E2E 성공으로 표시하지 않는다. 현 local harness는 barbell-row/목표3회를 명시하므로 담당자가 그 운동의 유효한 단일 clip을 선택해야 한다. EOF만으로 setEnd가 생기지 않고 실제 evaluator 목표 또는 정상 종료 UI가 필요하다.

native recorder는 PTS 기준60초 상한·H.264 2.5Mbps·rotation transform을 코드에 갖는다. CameraPosePreview는 lookahead tail flush 뒤 저장된 frame→video_ms와 실제 녹화 duration에 들어온 반복만 manifest에 넣는다. 기존 WorkoutSessionBridgeTests의 합성128×96/15프레임 H.264 검사·파일명/prune 검사는 실제 iPhone 720p30/60초 경계 검증을 대신하지 않는다. local harness의 duration 허용100ms·seek 허용500ms도 픽셀 단위 동기화 정확도 보장이 아니다.

따라서 기기 담당이 연결/파일 서비스를 복구한 뒤 source·앱 hash를 재확인하고 위 두 준비 하니스를 각각 실행·증거 회수해야 한다. 이후 실제 운동 전체 E2E는 별도 동의 입력과 정상 인증 경로가 필요하다. 이번에는 실행을 시작하거나 완료로 기록하지 않았다.

## 5. 재현성과 다음 최소 작업

새 분석기는 [`attribute_gvhmr_boundaries.py`](../../scripts/deep_analysis/attribute_gvhmr_boundaries.py)다. `--expected-videos=20`을 검사하고 frozen KEYS/BOUNDARY/상대 기준 정의를 그대로 호출한다. Home에서 stdin으로 실행해 aggregate JSON만 받았다. 점수 SHA256 `fd84c4971a601fa2fe5b23260f55bb73bed172a8cce0642017775fc619061f5f`, frozen evaluator SHA256 `87bbcbba75f880882741ec191cec9a10a0bd919c1034d0cc73109453c881e8c3`를 결과에 보존했다. runtime runner SHA256은 `007fb78348ee8558f1223ff860ddfb2c4fc34ae0c416e161c088f4156590cbff`다. runtime502d9ef와 현재 runner는 동일하며 deep_worker의 후속 panel 표시 변경은 구분했다. 보존 stage 숫자를 현재 panel 코드의 새 벤치처럼 표현하지 않는다.

검증은 `python3 -m unittest discover -s scripts/deep_analysis/tests -p test_boundary_attribution.py` **3개 통과**다. strict threshold/±5° 포함, 불일치 방향, A 대비 교차, camera/world 민감도, baseline NaN, 빈 집계, 길이 불일치 거절, no-lockout 성분 항등식, 식별자 미반출을 검사한다. 원 결과 기준·출력·점수 파일은 덮어쓰지 않았다.

남은 원인 검증의 최소 단위는 GPU 재실행이 아니라 **Home의 기존 숫자 배열에서 실패 반복의 GT/예측 극값 시점·지속시간과 정의 차이를 집계하는 CPU 검사**다. row range 손실이 단발 극값인지 지속적인 범위 압축인지 분리한 뒤에만 필터·불확실성 보류 같은 새 가설을 사전 고정해 평가한다. 그 전에 문턱을 맞춰 통과시키지 않는다. latency는 crop 공유/하위단계 계측 설계를 검토한 다음 root가 GPU 사용을 결정한다. 폰 경로는 기기 담당 실행 증거를 기다리며 서버/API 증거와 분리해 유지한다.

## 2026-10-29 정확도 후속

사용자 “속도 신경쓰지말고해” 지시에 따라 향후 속도 중심 작업은 중단했으며 과거 측정은 기록으로 보존한다. 남아 있던 실제 프레임 극값/지속시간/기준 반복 진단은 [후속 정확도 보고서](quality_extrema_results_20261029.md)와 [집계](quality_extrema_20261029.json)에 있다. 20개 원 배열의 반복 점수4,632개가 정확 재현됐고, row 진폭 압축과 pushup 기준 반복 선택 차이를 추가 분리했다. 원 정확도 FAIL은 유지하며 threshold·모델·생산 경로는 변경하지 않았다.
