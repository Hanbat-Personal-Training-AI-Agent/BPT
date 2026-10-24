# 데드리프트

조사일: 2026-10-23. 기본 프로필은 컨벤셔널 바벨 데드리프트다. 스모·RDL·트랩바·블록 풀은 시작 높이와 동작을 따로 지정한다. [공통 계약](team.md), [CSV](fault_catalog.csv)를 적용한다.

## 셋업과 단계별 기준

| 단계 | 체크포인트 | 큐 | 근거 |
| --- | --- | --- | --- |
| 셋업 | 바는 몸 앞 좌우 방향, 발 중간 부근에서 정강이에 가깝게 둔다. 선택한 스탠스·그립으로 잡고 몸통 긴장 유지 | 바를 몸 가까이 둬! | [D1], [D2] |
| 이륙 | 팔로 컬하지 않고 바닥을 밀며 골반과 어깨를 함께 올린다 | 가슴과 엉덩이 같이 올려! | [D1], [D3] |
| 무릎 통과 | 바를 다리에 가깝게 유지하며 고관절을 편다. 피부를 긁는 접촉을 목표로 삼지 않음 | 바를 몸 가까이 당겨! | [D1]; 접촉 강제 금지는 제품 적용 |
| 락아웃 | 엉덩이·무릎을 펴고 편하게 선다. 뒤로 과하게 젖혀 끝점을 만들지 않음 | 뒤로 젖히지 마! | [D2], [D3] |
| 하강 | 힙힌지로 내려가며 바가 무릎을 지나도록 조율. 선택한 바닥/블록 높이로 복귀 | 엉덩이 뒤로 보내! | [D2], [D4] |

그립은 오버·혼합·훅 등 선택에 따라 기록한다. 혼합그립의 손 방향 차이를 좌우 기술 오류로 자동 분류하지 않는다. RDL은 위에서 시작해 약간 굽힌 무릎을 유지하며 힌지하므로 바닥 접촉을 요구하지 않는다. [D3], [D4]

## 결함과 측정

| ID | 심각도·단계 | 신호·한계 | 큐 | 근거 |
| --- | --- | --- | --- | --- |
| `deadlift_hips_first` | 안전주의·이륙 | 0.3초 내 몸통 전경 증가와 골반/어깨 상승 속도 차. 바가 실제로 뜨는 시점은 물체 검출 필요 | 가슴과 엉덩이 같이 올려! | [D1], [D3] |
| `deadlift_no_lockout` | 효율·상단 | 승인된 무릎·고관절 내각 대비 부족 | 편하게 끝까지 일어서! | [D2] |
| `deadlift_lean_back` | 안전주의·상단 | 중력 수직 대비 몸통 뒤 기울임. 요추 과신전 확정 아님 | 뒤로 젖히지 마! | [D2] |
| `deadlift_bar_drift` | 안전주의·이륙/상승 | 실제 바–정강이 거리 증가; 손목 높이는 수평 바 이격을 증명하지 못함 | 바를 몸 가까이 당겨! | [D1] |
| `deadlift_spinal_control` | 안전주의·전 단계 | 요추 분절 정렬·통제 변화. 어깨–골반선만으로 측정 불가 | 중량 낮추고 다시 해! | [D3], [D5] |
| `deadlift_arm_pull` | 효율·이륙 | 팔꿈치 굽힘 증가가 다리 신전과 동반. 그립/가림 구분 필요 | 팔을 길게 유지해! | [D4]; 컨벤셔널 적용은 제품 제안 |
| `deadlift_knee_bar_collision` | 안전주의·하강 | 바와 무릎의 실제 간섭·급격한 회피. 신체점만으로 불가 | 멈추고 경로 다시 맞춰! | [D1], [D2] |

## 문헌 수치와 적용 한계

- NSCA의 재개 운동 지침에는 시작 높이에 따라 고관절 굴곡 약 110°·80°·50° 등의 예시가 있다. 지침의 각도 정의와 앱의 `S–H–K` 내각은 동일하다고 가정하지 않는다. 높이·체형·변형에 따라 시작각을 조정하며 단일 정답각은 두지 않는다. [D6]
- 요추 굴곡과 요통의 체계적 검토는 근거 질이 낮았고 굴곡 하나를 위험 인자로 확정하지 못했다. 이 결과를 “어떤 하중·굴곡도 안전”으로 확대하지도 않는다. 앱은 통증 응답·부하·통제 변화와 함께 검토하며 진단을 하지 않는다. [D5]
- `P:` 이륙 때 몸통 전경 >8°와 골반 선행, 상단 뒤 기울임 >15°는 모든 모드의 검토 후보다. 문헌상 부상 임계값이 아니며 후자는 현재 코드값과 같아도 검증되었다는 뜻이 아니다. `no_lockout`의 기준 대비 부족 >5°/10°/15°만 효율 모드에 따라 달리 제안한다. [D1], [D2], [현재 코드](../../ios/Runner/NativePose/Evaluators/FormWarnings.swift)

Halpe26/3D는 고관절·무릎 신전과 큰 몸통 움직임을 보완한다. 바 경로·바닥 접촉·원판 높이는 물체/바닥 검출, 훅그립·혼합그립은 손 감지가 필요하다. 중량·지면반력·근활성·복압은 현재 키포인트로 측정할 수 없다. [D1], [G]

## 출처

[D1]: https://www.acefitness.org/continuing-education/prosource/september-2015/5579/technique-series-how-to-deadlift/
[D2]: https://www.acefitness.org/resources/everyone/exercise-library/6/deadlift/
[D3]: https://www.nsca.com/globalassets/education/tsac-report/tsac-report-54.pdf
[D4]: https://dxpprod.nsca.com/education/articles/kinetic-select/romanian-deadlift-rdl/
[D5]: https://pubmed.ncbi.nlm.nih.gov/31775556/
[D6]: https://www.nsca.com/education/articles/nsca-coach/exercise-progressions-for-resuming-strength-training-following-posterior-chain-muscle-injury/
[G]: https://arxiv.org/abs/2409.06662

D1–D4·D6은 기술 지침이며 D5는 체계적 검토다. RDL이나 재활 진행의 숫자를 일반 컨벤셔널 경고값으로 그대로 가져오지 않는다.
