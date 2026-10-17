# 사람 다시 잡기(re-acquisition) 실험: RTMPose-m COCO17 · m Halpe26 (트랙 reacquire, D-T3-20)

실험만 한다. 모델 채택·기각, 앱 기본값, 번들, 병합은 다루지 않는다. 모든 새 동작은 옵션 뒤에 있고 기본값은 현재 경로다.

## 0. 결과를 보기 전에 정한 규칙 (2026-10-18, 내 제안 — 사용자 승인 아님)
- **후보**(pose-replay 옵션, `RTMPoseCropTracker` 필드, 기본 꺼짐):
  - (a) `lb` `--lost-input letterbox`: 잃었을 때 전체 프레임을 비율 유지(검은 띠) 3:4로 넣음.
  - (b) `a<K>[+h<N>]` `--acquire-joints K`(추적 시작에 필요한 관절 수, 유지는 6 그대로) `--lost-hold N`(관절이 6 아래로 떨어져도 N프레임 crop 유지).
  - (c) `s<N>` `--lost-search N`: 잃은 첫 프레임과 그 뒤 N프레임마다 레터박스 전체 + 긴 변 3:4 타일 3개에서 RTMPose를 더 돌려 가장 많이 보인 후보로 추적 시작(추가 추론 4회).
  - (d) `det`/`det<N>` `--acquire-boxes`: 잃었을 때 그 프레임의 RTMDet-m 사람 상자(점수×넓이 최대, 미래 정보 없음)로 crop 시작, `det<N>`은 N프레임마다만 검출. `detoff`(영상 전체 사용자 트랙, 미래 사용)와 `detall`(매 프레임 검출 crop)은 참고용 상한.
- **선택 규칙**: 후보마다 매개변수는 조정 데이터(MM-Fit 조정 9명 47세트, 공개 tuning, Exercise3D P1)만 보고 고른다. 두 모델 합산 조정 렙 정확도가 가장 높은 값, 단 (1) 조정 셋업 알람(setup_full_body + tracking_lost + 로우 setup_side_view) 증가 없음, (2) 조정 스쿼트·로우 렙 정확도 하락 없음. 같으면 추가 비용이 적은 쪽. 검증 데이터는 선택이 끝난 뒤 한 번만 본다.
- **데이터 역할**: 독립 검증 = 공개 heldout, Exercise3D P2·P3. MM-Fit 검증 18세트는 D-T3-19 분석에서 이미 봤으므로 **개발·진단용**(독립 검증 아님). MM-Fit 정답은 세트 렙 수뿐(구간 미검증, eval-reliability 트랙 감사 중). Fit3D는 Home에만 두라는 지시로 Mac pose-replay를 돌리지 못함(아래).
