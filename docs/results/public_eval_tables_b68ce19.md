# 공개 데이터 평가 (pose-replay, RTMPose-m COCO17 기본, crop, ready-pose off, 3D 없음)

라벨 행 571, 렙 평가 세트 212, 자세 평가 세트 240, replay 없음 242


### 렙 정확도 — mendeley_mv7 (모든 자세)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 18 | 190 | 21 | 1 | 88.5% | 12/18 | 88.9% | 13/18 |
| pushup | side | tuning | 14 | 147 | 18 | 2 | 86.6% | 7/14 | 87.8% | 9/14 |
| pushup | diag | heldout | 20 | 234 | 19 | 3 | 90.7% | 12/20 | 91.9% | 15/20 |
| pushup | diag | tuning | 16 | 165 | 15 | 4 | 88.8% | 9/16 | 90.9% | 13/16 |
| pushup | front | heldout | 12 | 143 | 86 | 0 | 39.9% | 1/12 | 39.9% | 1/12 |
| pushup | front | tuning | 15 | 168 | 89 | 0 | 47.0% | 2/15 | 47.0% | 2/15 |
| pushup | 전체 | heldout | 50 | 567 | 126 | 4 | 77.2% | 25/50 | 77.8% | 29/50 |
| pushup | 전체 | tuning | 45 | 480 | 122 | 6 | 73.7% | 18/45 | 74.6% | 24/45 |
| row | side | heldout | 9 | 131 | 124 | 0 | 5.3% | 1/9 | 5.3% | 1/9 |
| row | side | tuning | 15 | 220 | 210 | 0 | 4.5% | 0/15 | 4.5% | 0/15 |
| row | diag | heldout | 1 | 8 | 8 | 0 | 0.0% | 0/1 | 0.0% | 0/1 |
| row | 전체 | heldout | 10 | 139 | 132 | 0 | 5.0% | 1/10 | 5.0% | 1/10 |
| row | 전체 | tuning | 15 | 220 | 210 | 0 | 4.5% | 0/15 | 4.5% | 0/15 |
| squat | side | heldout | 16 | 208 | 111 | 2 | 46.2% | 0/16 | 46.6% | 2/16 |
| squat | side | tuning | 19 | 234 | 133 | 1 | 43.0% | 1/19 | 43.2% | 2/19 |
| squat | 전체 | heldout | 16 | 208 | 111 | 2 | 46.2% | 0/16 | 46.6% | 2/16 |
| squat | 전체 | tuning | 19 | 234 | 133 | 1 | 43.0% | 1/19 | 43.2% | 2/19 |

### 렙 정확도 — mendeley_mv7 (정상 자세만)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 9 | 110 | 12 | 0 | 89.1% | 6/9 | 89.1% | 6/9 |
| pushup | side | tuning | 7 | 86 | 14 | 2 | 81.8% | 2/7 | 83.7% | 4/7 |
| pushup | diag | heldout | 12 | 162 | 12 | 3 | 90.9% | 5/12 | 92.6% | 8/12 |
| pushup | diag | tuning | 9 | 108 | 11 | 2 | 88.2% | 5/9 | 89.8% | 7/9 |
| pushup | front | heldout | 6 | 84 | 63 | 0 | 25.0% | 0/6 | 25.0% | 0/6 |
| pushup | front | tuning | 7 | 92 | 56 | 0 | 39.1% | 0/7 | 39.1% | 0/7 |
| pushup | 전체 | heldout | 27 | 356 | 87 | 3 | 74.9% | 11/27 | 75.6% | 14/27 |
| pushup | 전체 | tuning | 23 | 286 | 81 | 4 | 70.7% | 7/23 | 71.7% | 11/23 |
| row | side | heldout | 4 | 46 | 46 | 0 | 0.0% | 1/4 | 0.0% | 1/4 |
| row | side | tuning | 5 | 68 | 66 | 0 | 2.9% | 0/5 | 2.9% | 0/5 |
| row | 전체 | heldout | 4 | 46 | 46 | 0 | 0.0% | 1/4 | 0.0% | 1/4 |
| row | 전체 | tuning | 5 | 68 | 66 | 0 | 2.9% | 0/5 | 2.9% | 0/5 |
| squat | side | heldout | 8 | 107 | 53 | 2 | 49.5% | 0/8 | 50.5% | 2/8 |
| squat | side | tuning | 9 | 102 | 54 | 1 | 46.6% | 1/9 | 47.1% | 2/9 |
| squat | 전체 | heldout | 8 | 107 | 53 | 2 | 49.5% | 0/8 | 50.5% | 2/8 |
| squat | 전체 | tuning | 9 | 102 | 54 | 1 | 46.6% | 1/9 | 47.1% | 2/9 |

### 렙 정확도 — youtube_cc (모든 자세)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 4 | 16 | 0 | 0 | 100.0% | 4/4 | 100.0% | 4/4 |
| pushup | side | tuning | 6 | 12 | 0 | 2 | 85.7% | 4/6 | 92.3% | 5/6 |
| pushup | diag | heldout | 15 | 34 | 0 | 5 | 87.2% | 11/15 | 87.2% | 11/15 |
| pushup | diag | tuning | 2 | 3 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| pushup | front | heldout | 2 | 22 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| pushup | front | tuning | 4 | 12 | 4 | 0 | 66.7% | 2/4 | 66.7% | 2/4 |
| pushup | 전체 | heldout | 21 | 72 | 0 | 5 | 93.5% | 17/21 | 93.5% | 17/21 |
| pushup | 전체 | tuning | 12 | 27 | 4 | 2 | 79.3% | 8/12 | 82.1% | 9/12 |
| row | side | heldout | 4 | 9 | 0 | 0 | 100.0% | 4/4 | 100.0% | 4/4 |
| row | side | tuning | 5 | 13 | 4 | 0 | 69.2% | 3/5 | 69.2% | 3/5 |
| row | diag | heldout | 1 | 5 | 1 | 0 | 80.0% | 0/1 | 80.0% | 0/1 |
| row | diag | tuning | 1 | 2 | 0 | 0 | 100.0% | 1/1 | 100.0% | 1/1 |
| row | 전체 | heldout | 5 | 14 | 1 | 0 | 92.9% | 4/5 | 92.9% | 4/5 |
| row | 전체 | tuning | 6 | 15 | 4 | 0 | 73.3% | 4/6 | 73.3% | 4/6 |
| squat | side | heldout | 8 | 15 | 5 | 0 | 66.7% | 6/8 | 66.7% | 6/8 |
| squat | side | tuning | 5 | 8 | 3 | 0 | 62.5% | 3/5 | 62.5% | 3/5 |
| squat | 전체 | heldout | 8 | 15 | 5 | 0 | 66.7% | 6/8 | 66.7% | 6/8 |
| squat | 전체 | tuning | 5 | 8 | 3 | 0 | 62.5% | 3/5 | 62.5% | 3/5 |

### 렙 정확도 — youtube_cc (정상 자세만)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 2 | 9 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| pushup | side | tuning | 3 | 5 | 0 | 1 | 83.3% | 2/3 | 100.0% | 3/3 |
| pushup | diag | heldout | 8 | 21 | 0 | 4 | 84.0% | 5/8 | 84.0% | 5/8 |
| pushup | diag | tuning | 2 | 3 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| pushup | front | heldout | 2 | 22 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| pushup | front | tuning | 3 | 8 | 4 | 0 | 50.0% | 1/3 | 50.0% | 1/3 |
| pushup | 전체 | heldout | 12 | 52 | 0 | 4 | 92.9% | 9/12 | 92.9% | 9/12 |
| pushup | 전체 | tuning | 8 | 16 | 4 | 1 | 70.6% | 5/8 | 75.0% | 6/8 |
| row | side | heldout | 3 | 6 | 0 | 0 | 100.0% | 3/3 | 100.0% | 3/3 |
| row | side | tuning | 5 | 13 | 4 | 0 | 69.2% | 3/5 | 69.2% | 3/5 |
| row | diag | heldout | 1 | 5 | 1 | 0 | 80.0% | 0/1 | 80.0% | 0/1 |
| row | diag | tuning | 1 | 2 | 0 | 0 | 100.0% | 1/1 | 100.0% | 1/1 |
| row | 전체 | heldout | 4 | 11 | 1 | 0 | 90.9% | 3/4 | 90.9% | 3/4 |
| row | 전체 | tuning | 6 | 15 | 4 | 0 | 73.3% | 4/6 | 73.3% | 4/6 |
| squat | side | heldout | 7 | 13 | 5 | 0 | 61.5% | 5/7 | 61.5% | 5/7 |
| squat | side | tuning | 2 | 2 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| squat | 전체 | heldout | 7 | 13 | 5 | 0 | 61.5% | 5/7 | 61.5% | 5/7 |
| squat | 전체 | tuning | 2 | 2 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |

### 렙 정확도 — 전체 (모든 자세)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 22 | 206 | 21 | 1 | 89.4% | 16/22 | 89.8% | 17/22 |
| pushup | side | tuning | 20 | 159 | 18 | 4 | 86.5% | 11/20 | 88.1% | 14/20 |
| pushup | diag | heldout | 35 | 268 | 19 | 8 | 90.2% | 23/35 | 91.2% | 26/35 |
| pushup | diag | tuning | 18 | 168 | 15 | 4 | 89.0% | 11/18 | 91.1% | 15/18 |
| pushup | front | heldout | 14 | 165 | 86 | 0 | 47.9% | 3/14 | 47.9% | 3/14 |
| pushup | front | tuning | 19 | 180 | 93 | 0 | 48.3% | 4/19 | 48.3% | 4/19 |
| pushup | 전체 | heldout | 71 | 639 | 126 | 9 | 79.2% | 42/71 | 79.7% | 46/71 |
| pushup | 전체 | tuning | 57 | 507 | 126 | 8 | 74.0% | 26/57 | 75.0% | 33/57 |
| row | side | heldout | 13 | 140 | 124 | 0 | 11.4% | 5/13 | 11.4% | 5/13 |
| row | side | tuning | 20 | 233 | 214 | 0 | 8.2% | 3/20 | 8.2% | 3/20 |
| row | diag | heldout | 2 | 13 | 9 | 0 | 30.8% | 0/2 | 30.8% | 0/2 |
| row | diag | tuning | 1 | 2 | 0 | 0 | 100.0% | 1/1 | 100.0% | 1/1 |
| row | 전체 | heldout | 15 | 153 | 133 | 0 | 13.1% | 5/15 | 13.1% | 5/15 |
| row | 전체 | tuning | 21 | 235 | 214 | 0 | 8.9% | 4/21 | 8.9% | 4/21 |
| squat | side | heldout | 24 | 223 | 116 | 2 | 47.6% | 6/24 | 48.0% | 8/24 |
| squat | side | tuning | 24 | 242 | 136 | 1 | 43.6% | 4/24 | 43.8% | 5/24 |
| squat | 전체 | heldout | 24 | 223 | 116 | 2 | 47.6% | 6/24 | 48.0% | 8/24 |
| squat | 전체 | tuning | 24 | 242 | 136 | 1 | 43.6% | 4/24 | 43.8% | 5/24 |

### 렙 정확도 — 전체 (정상 자세만)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 11 | 119 | 12 | 0 | 89.9% | 8/11 | 89.9% | 8/11 |
| pushup | side | tuning | 10 | 91 | 14 | 3 | 81.9% | 4/10 | 84.6% | 7/10 |
| pushup | diag | heldout | 20 | 183 | 12 | 7 | 90.0% | 10/20 | 91.4% | 13/20 |
| pushup | diag | tuning | 11 | 111 | 11 | 2 | 88.5% | 7/11 | 90.1% | 9/11 |
| pushup | front | heldout | 8 | 106 | 63 | 0 | 40.6% | 2/8 | 40.6% | 2/8 |
| pushup | front | tuning | 10 | 100 | 60 | 0 | 40.0% | 1/10 | 40.0% | 1/10 |
| pushup | 전체 | heldout | 39 | 408 | 87 | 7 | 77.3% | 20/39 | 77.9% | 23/39 |
| pushup | 전체 | tuning | 31 | 302 | 85 | 5 | 70.7% | 12/31 | 71.9% | 17/31 |
| row | side | heldout | 7 | 52 | 46 | 0 | 11.5% | 4/7 | 11.5% | 4/7 |
| row | side | tuning | 10 | 81 | 70 | 0 | 13.6% | 3/10 | 13.6% | 3/10 |
| row | diag | heldout | 1 | 5 | 1 | 0 | 80.0% | 0/1 | 80.0% | 0/1 |
| row | diag | tuning | 1 | 2 | 0 | 0 | 100.0% | 1/1 | 100.0% | 1/1 |
| row | 전체 | heldout | 8 | 57 | 47 | 0 | 17.5% | 4/8 | 17.5% | 4/8 |
| row | 전체 | tuning | 11 | 83 | 70 | 0 | 15.7% | 4/11 | 15.7% | 4/11 |
| squat | side | heldout | 15 | 120 | 58 | 2 | 50.8% | 5/15 | 51.7% | 7/15 |
| squat | side | tuning | 11 | 104 | 54 | 1 | 47.6% | 3/11 | 48.1% | 4/11 |
| squat | 전체 | heldout | 15 | 120 | 58 | 2 | 50.8% | 5/15 | 51.7% | 7/15 |
| squat | 전체 | tuning | 11 | 104 | 54 | 1 | 47.6% | 3/11 | 48.1% | 4/11 |

### 렙 정확도 × 추적 품질 (unknown = 관절 신뢰도가 낮아 상태를 못 정한 프레임 비율)

| 운동 | 분할 | unknown 비율 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 |
|---|---|---|---|---|---|---|---|
| pushup | heldout | < 10% | 71 | 639 | 126 | 9 | 79.2% |
| pushup | tuning | < 10% | 57 | 507 | 126 | 8 | 74.0% |
| row | heldout | < 10% | 15 | 153 | 133 | 0 | 13.1% |
| row | tuning | < 10% | 20 | 233 | 212 | 0 | 9.0% |
| row | tuning | ≥ 10% | 1 | 2 | 2 | 0 | 0.0% |
| squat | heldout | < 10% | 15 | 161 | 71 | 2 | 55.2% |
| squat | heldout | ≥ 10% | 9 | 62 | 45 | 0 | 27.4% |
| squat | tuning | < 10% | 11 | 114 | 41 | 0 | 64.0% |
| squat | tuning | ≥ 10% | 13 | 128 | 95 | 1 | 25.6% |

### 셋업 키 (세트당 발생, 괄호 = 센 렙 안에서)

| 운동 | 시점 | 분할 | 세트 | setup_full_body | tracking_lost | setup_side_view | 앱에서 켜진 키 알람 세트 |
|---|---|---|---|---|---|---|---|
| pushup | diag | heldout | 38 | 0 (0) | 12 (0) | 9 (9) | 5/38 |
| pushup | diag | tuning | 23 | 0 (0) | 4 (0) | 11 (11) | 3/23 |
| pushup | front | heldout | 22 | 13 (0) | 101 (0) | 19 (19) | 20/22 |
| pushup | front | tuning | 25 | 10 (0) | 75 (0) | 23 (23) | 20/25 |
| pushup | side | heldout | 24 | 0 (0) | 1 (0) | 0 (0) | 1/24 |
| pushup | side | tuning | 30 | 0 (0) | 2 (0) | 0 (0) | 2/30 |
| row | diag | heldout | 5 | 0 (0) | 0 (0) | 1 (0) | 1/5 |
| row | diag | tuning | 2 | 0 (0) | 0 (0) | 1 (0) | 1/2 |
| row | side | heldout | 27 | 0 (0) | 0 (0) | 0 (0) | 0/27 |
| row | side | tuning | 28 | 0 (0) | 0 (0) | 0 (0) | 0/28 |
| squat | side | heldout | 28 | 0 (0) | 0 (0) | 0 (0) | 0/28 |
| squat | side | tuning | 26 | 0 (0) | 0 (0) | 0 (0) | 0/26 |

### 자세 키 (앱에서 꺼짐 — pose-replay 판정 로그)

검출 = 그 키 라벨(두 패스 합의)이 붙은 잘못된 세트 중 키가 1렙 이상(또는 세트 이벤트) 나온 비율. 렙 비율 = 그 세트들의 센 렙 중 키가 나온 비율. 오경보 = 합의된 정상 세트의 센 렙 중 키가 나온 비율.

| 운동 | 키 | 시점 | 분할 | 잘못 세트 | 검출 | 렙 비율 | 정상 세트 | 정상 렙 | 오경보(렙) | 오경보(세트) |
|---|---|---|---|---|---|---|---|---|---|---|
| squat | squat_shallow | side | heldout | 5 | 0/5 (0%) | 0/31 (0%) | 16 | 64 | 0/64 (0%) | 0/16 (0%) |
| squat | squat_shallow | side | tuning | 5 | 0/5 (0%) | 0/26 (0%) | 13 | 65 | 0/65 (0%) | 0/13 (0%) |
| squat | squat_shallow | 전체 | heldout | 5 | 0/5 (0%) | 0/31 (0%) | 16 | 64 | 0/64 (0%) | 0/16 (0%) |
| squat | squat_shallow | 전체 | tuning | 5 | 0/5 (0%) | 0/26 (0%) | 13 | 65 | 0/65 (0%) | 0/13 (0%) |
| squat | squat_hips_first | side | heldout | 1 | 0/1 (0%) | 0/1 (0%) | 16 | 64 | 0/64 (0%) | 0/16 (0%) |
| squat | squat_hips_first | side | tuning | 3 | 0/3 (0%) | 0/4 (0%) | 13 | 65 | 0/65 (0%) | 0/13 (0%) |
| squat | squat_hips_first | 전체 | heldout | 1 | 0/1 (0%) | 0/1 (0%) | 16 | 64 | 0/64 (0%) | 0/16 (0%) |
| squat | squat_hips_first | 전체 | tuning | 3 | 0/3 (0%) | 0/4 (0%) | 13 | 65 | 0/65 (0%) | 0/13 (0%) |
| squat | squat_no_lockout | side | heldout | 0 | - | - | 16 | 64 | 5/64 (8%) | 4/16 (25%) |
| squat | squat_no_lockout | side | tuning | 0 | - | - | 13 | 65 | 10/65 (15%) | 7/13 (54%) |
| squat | squat_no_lockout | 전체 | heldout | 0 | - | - | 16 | 64 | 5/64 (8%) | 4/16 (25%) |
| squat | squat_no_lockout | 전체 | tuning | 0 | - | - | 13 | 65 | 10/65 (15%) | 7/13 (54%) |
| squat | squat_heel_rise | side | tuning | 2 | 0/2 (0%) | 0/10 (0%) | 13 | 65 | 0/65 (0%) | 0/13 (0%) |
| squat | squat_heel_rise | 전체 | tuning | 2 | 0/2 (0%) | 0/10 (0%) | 13 | 65 | 0/65 (0%) | 0/13 (0%) |
| pushup | pushup_hip_sag | diag | heldout | 3 | 0/3 (0%) | 0/27 (0%) | 20 | 178 | 2/178 (1%) | 2/20 (10%) |
| pushup | pushup_hip_sag | diag | tuning | 1 | 0/1 (0%) | 0/4 (0%) | 14 | 140 | 7/140 (5%) | 2/14 (14%) |
| pushup | pushup_hip_sag | front | heldout | 2 | 0/2 (0%) | 0/16 (0%) | 13 | 89 | 0/89 (0%) | 0/13 (0%) |
| pushup | pushup_hip_sag | side | heldout | 4 | 1/4 (25%) | 2/36 (6%) | 12 | 123 | 0/123 (0%) | 0/12 (0%) |
| pushup | pushup_hip_sag | side | tuning | 3 | 1/3 (33%) | 2/14 (14%) | 17 | 139 | 0/139 (0%) | 0/17 (0%) |
| pushup | pushup_hip_sag | 전체 | heldout | 9 | 1/9 (11%) | 2/79 (3%) | 45 | 390 | 2/390 (1%) | 2/45 (4%) |
| pushup | pushup_hip_sag | 전체 | tuning | 4 | 1/4 (25%) | 2/18 (11%) | 46 | 347 | 7/347 (2%) | 2/46 (4%) |
| pushup | pushup_hip_pike | diag | heldout | 4 | 2/4 (50%) | 11/24 (46%) | 20 | 178 | 49/178 (28%) | 12/20 (60%) |
| pushup | pushup_hip_pike | diag | tuning | 3 | 1/3 (33%) | 1/29 (3%) | 14 | 140 | 13/140 (9%) | 6/14 (43%) |
| pushup | pushup_hip_pike | front | heldout | 2 | 0/2 (0%) | 0/11 (0%) | 13 | 89 | 0/89 (0%) | 0/13 (0%) |
| pushup | pushup_hip_pike | side | heldout | 3 | 3/3 (100%) | 20/25 (80%) | 12 | 123 | 1/123 (1%) | 1/12 (8%) |
| pushup | pushup_hip_pike | side | tuning | 3 | 2/3 (67%) | 3/21 (14%) | 17 | 139 | 1/139 (1%) | 1/17 (6%) |
| pushup | pushup_hip_pike | 전체 | heldout | 9 | 5/9 (56%) | 31/60 (52%) | 45 | 390 | 50/390 (13%) | 13/45 (29%) |
| pushup | pushup_hip_pike | 전체 | tuning | 6 | 3/6 (50%) | 4/50 (8%) | 46 | 347 | 14/347 (4%) | 7/46 (15%) |
| pushup | pushup_shallow | diag | heldout | 2 | 0/2 (0%) | 0/16 (0%) | 20 | 178 | 3/178 (2%) | 2/20 (10%) |
| pushup | pushup_shallow | diag | tuning | 2 | 1/2 (50%) | 2/26 (8%) | 14 | 140 | 2/140 (1%) | 1/14 (7%) |
| pushup | pushup_shallow | front | heldout | 2 | 0/2 (0%) | 0/6 (0%) | 13 | 89 | 0/89 (0%) | 0/13 (0%) |
| pushup | pushup_shallow | front | tuning | 2 | 0/2 (0%) | 0/6 (0%) | 15 | 68 | 0/68 (0%) | 0/15 (0%) |
| pushup | pushup_shallow | side | heldout | 2 | 0/2 (0%) | 0/10 (0%) | 12 | 123 | 18/123 (15%) | 3/12 (25%) |
| pushup | pushup_shallow | side | tuning | 3 | 1/3 (33%) | 1/8 (12%) | 17 | 139 | 17/139 (12%) | 5/17 (29%) |
| pushup | pushup_shallow | 전체 | heldout | 6 | 0/6 (0%) | 0/32 (0%) | 45 | 390 | 21/390 (5%) | 5/45 (11%) |
| pushup | pushup_shallow | 전체 | tuning | 7 | 2/7 (29%) | 3/40 (8%) | 46 | 347 | 19/347 (5%) | 6/46 (13%) |
| pushup | pushup_no_lockout | diag | heldout | 0 | - | - | 20 | 178 | 46/178 (26%) | 10/20 (50%) |
| pushup | pushup_no_lockout | diag | tuning | 0 | - | - | 14 | 140 | 23/140 (16%) | 11/14 (79%) |
| pushup | pushup_no_lockout | side | heldout | 0 | - | - | 12 | 123 | 28/123 (23%) | 6/12 (50%) |
| pushup | pushup_no_lockout | side | tuning | 1 | 0/1 (0%) | 0/14 (0%) | 17 | 139 | 29/139 (21%) | 7/17 (41%) |
| pushup | pushup_no_lockout | 전체 | heldout | 0 | - | - | 45 | 390 | 74/390 (19%) | 16/45 (36%) |
| pushup | pushup_no_lockout | 전체 | tuning | 1 | 0/1 (0%) | 0/14 (0%) | 46 | 347 | 52/347 (15%) | 18/46 (39%) |
| pushup | pushup_head_drop | diag | heldout | 3 | 0/3 (0%) | 0/23 (0%) | 20 | 178 | 3/178 (2%) | 2/20 (10%) |
| pushup | pushup_head_drop | diag | tuning | 1 | 0/1 (0%) | 0/9 (0%) | 14 | 140 | 0/140 (0%) | 0/14 (0%) |
| pushup | pushup_head_drop | front | heldout | 2 | 0/2 (0%) | 0/11 (0%) | 13 | 89 | 0/89 (0%) | 0/13 (0%) |
| pushup | pushup_head_drop | front | tuning | 1 | 0/1 (0%) | 0/4 (0%) | 15 | 68 | 0/68 (0%) | 0/15 (0%) |
| pushup | pushup_head_drop | side | heldout | 2 | 0/2 (0%) | 0/18 (0%) | 12 | 123 | 0/123 (0%) | 0/12 (0%) |
| pushup | pushup_head_drop | side | tuning | 1 | 0/1 (0%) | 0/14 (0%) | 17 | 139 | 1/139 (1%) | 1/17 (6%) |
| pushup | pushup_head_drop | 전체 | heldout | 7 | 0/7 (0%) | 0/52 (0%) | 45 | 390 | 3/390 (1%) | 2/45 (4%) |
| pushup | pushup_head_drop | 전체 | tuning | 3 | 0/3 (0%) | 0/27 (0%) | 46 | 347 | 1/347 (0%) | 1/46 (2%) |
| pushup | pushup_head_up | diag | heldout | 0 | - | - | 20 | 178 | 73/178 (41%) | 12/20 (60%) |
| pushup | pushup_head_up | diag | tuning | 0 | - | - | 14 | 140 | 42/140 (30%) | 12/14 (86%) |
| pushup | pushup_head_up | side | heldout | 1 | 0/1 (0%) | 0/2 (0%) | 12 | 123 | 25/123 (20%) | 6/12 (50%) |
| pushup | pushup_head_up | side | tuning | 0 | - | - | 17 | 139 | 22/139 (16%) | 6/17 (35%) |
| pushup | pushup_head_up | 전체 | heldout | 1 | 0/1 (0%) | 0/2 (0%) | 45 | 390 | 98/390 (25%) | 18/45 (40%) |
| pushup | pushup_head_up | 전체 | tuning | 0 | - | - | 46 | 347 | 64/347 (18%) | 18/46 (39%) |
| pushup | pushup_hand_position | diag | heldout | 0 | - | - | 20 | 178 | 4/178 (2%) | 4/20 (20%) |
| pushup | pushup_hand_position | diag | tuning | 0 | - | - | 14 | 140 | 1/140 (1%) | 1/14 (7%) |
| pushup | pushup_hand_position | side | tuning | 0 | - | - | 17 | 139 | 1/139 (1%) | 1/17 (6%) |
| pushup | pushup_hand_position | 전체 | heldout | 0 | - | - | 45 | 390 | 4/390 (1%) | 4/45 (9%) |
| pushup | pushup_hand_position | 전체 | tuning | 0 | - | - | 46 | 347 | 2/347 (1%) | 2/46 (4%) |
| pushup | pushup_depth_fade | side | heldout | 0 | - | - | 12 | 123 | 18/123 (15%) | 4/12 (33%) |
| pushup | pushup_depth_fade | side | tuning | 0 | - | - | 17 | 139 | 11/139 (8%) | 4/17 (24%) |
| pushup | pushup_depth_fade | 전체 | heldout | 0 | - | - | 45 | 390 | 18/390 (5%) | 4/45 (9%) |
| pushup | pushup_depth_fade | 전체 | tuning | 0 | - | - | 46 | 347 | 11/347 (3%) | 4/46 (9%) |
| row | row_torso_swing | diag | heldout | 0 | - | - | 4 | 18 | 1/18 (6%) | 1/4 (25%) |
| row | row_torso_swing | side | heldout | 7 | 3/7 (43%) | 6/9 (67%) | 15 | 7 | 1/7 (14%) | 1/15 (7%) |
| row | row_torso_swing | side | tuning | 2 | 0/2 (0%) | - | 14 | 12 | 1/12 (8%) | 1/14 (7%) |
| row | row_torso_swing | 전체 | heldout | 7 | 3/7 (43%) | 6/9 (67%) | 19 | 25 | 2/25 (8%) | 2/19 (11%) |
| row | row_torso_swing | 전체 | tuning | 2 | 0/2 (0%) | - | 16 | 21 | 1/21 (5%) | 1/16 (6%) |
| row | row_standing_up | side | heldout | 4 | 0/4 (0%) | 0/5 (0%) | 15 | 7 | 0/7 (0%) | 0/15 (0%) |
| row | row_standing_up | side | tuning | 2 | 0/2 (0%) | 0/1 (0%) | 14 | 12 | 0/12 (0%) | 0/14 (0%) |
| row | row_standing_up | 전체 | heldout | 4 | 0/4 (0%) | 0/5 (0%) | 19 | 25 | 0/25 (0%) | 0/19 (0%) |
| row | row_standing_up | 전체 | tuning | 2 | 0/2 (0%) | 0/1 (0%) | 16 | 21 | 0/21 (0%) | 0/16 (0%) |
| row | row_short_pull | side | heldout | 2 | 0/2 (0%) | 0/1 (0%) | 15 | 7 | 0/7 (0%) | 0/15 (0%) |
| row | row_short_pull | side | tuning | 3 | 0/3 (0%) | 0/1 (0%) | 14 | 12 | 0/12 (0%) | 0/14 (0%) |
| row | row_short_pull | 전체 | heldout | 2 | 0/2 (0%) | 0/1 (0%) | 19 | 25 | 0/25 (0%) | 0/19 (0%) |
| row | row_short_pull | 전체 | tuning | 3 | 0/3 (0%) | 0/1 (0%) | 16 | 21 | 0/21 (0%) | 0/16 (0%) |
| row | row_head_up | side | heldout | 0 | - | - | 15 | 7 | 1/7 (14%) | 1/15 (7%) |
| row | row_head_up | side | tuning | 0 | - | - | 14 | 12 | 2/12 (17%) | 2/14 (14%) |
| row | row_head_up | 전체 | heldout | 0 | - | - | 19 | 25 | 1/25 (4%) | 1/19 (5%) |
| row | row_head_up | 전체 | tuning | 0 | - | - | 16 | 21 | 2/21 (10%) | 2/16 (12%) |

### 세트별

| 파일 | 분할 | 시점 | 자세 | wrong_key | 정답 | 셈 | unknown | 경고(렙별) |
|---|---|---|---|---|---|---|---|---|
| subject_001_back_bad_side | tuning | side | wrong | row_standing_up | 17 | 1 | 2% | row_head_up |
| subject_001_back_good_side | tuning | side | normal |  | 17 | 1 | 1% | - |
| subject_001_push_up_bad_diagonal | tuning | diag | wrong | pushup_hip_pike | 12 | 8 | 0% | setup_side_view,-,-,-,-,-,-,- |
| subject_001_push_up_bad_front | tuning | front | uncertain |  | 13 | 11 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,- |
| subject_001_push_up_bad_side | tuning | side | uncertain |  | 18 | 17 | 0% | pushup_hip_pike,-,-,-,-,-,-,-,-,pushup_no_lockout,pushup_shallow,pushup_shallow+pushup_depth_fade,pushup_shallow+pushup_depth_fade,pushup_shallow+pushup_depth_f |
| subject_001_push_up_good_diagonal | tuning | diag | normal |  | 30 | 21 | 2% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,pushup_no_lockout+pushup_head_up |
| subject_001_push_up_good_front | tuning | front | normal |  | 27 | 4 | 0% | setup_side_view,-,-,- |
| subject_001_push_up_good_side | tuning | side | normal |  | 12 | 11 | 0% | pushup_head_up,-,pushup_head_up,pushup_shallow+pushup_head_up,pushup_shallow+pushup_head_up,pushup_shallow+pushup_depth_fade,pushup_shallow+pushup_depth_fade,pu |
| subject_001_squat_bad_side | tuning | side | uncertain |  | 15 | 5 | 18% | -,-,-,squat_no_lockout,squat_shallow |
| subject_001_squat_good_side | tuning | side | normal |  | 18|14 | 3 | 29% | -,squat_no_lockout,- |
| subject_002_back_bad_side | tuning | side | wrong | row_short_pull | 20 | 1 | 0% | - |
| subject_002_back_good_side | tuning | side | normal |  | 13|14 | 1 | 2% | row_torso_swing+row_head_up |
| subject_002_push_up_bad_diagonal | tuning | diag | uncertain |  | 13 | 13 | 1% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_002_push_up_bad_front | tuning | front | uncertain |  | 13 | 12 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,- |
| subject_002_push_up_bad_side | tuning | side | wrong | pushup_head_drop | 14|13 | 14 | 0% | -,-,-,pushup_shallow,-,pushup_shallow+pushup_depth_fade,pushup_shallow+pushup_depth_fade,pushup_shallow+pushup_no_lockout+pushup_depth_fade,pushup_shallow+pushu |
| subject_002_push_up_good_diagonal | tuning | diag | normal |  | 12 | 10 | 0% | setup_side_view,-,-,pushup_hip_sag+pushup_head_up,-,-,pushup_hip_sag+pushup_no_lockout+pushup_head_up,-,-,- |
| subject_002_push_up_good_front | tuning | front | normal |  | 11 | 6 | 0% | setup_side_view,-,-,-,-,- |
| subject_002_push_up_good_side | tuning | side | normal |  | 12 | 12 | 0% | -,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,pushup_no_lock |
| subject_002_squat_bad_side | tuning | side | wrong | squat_hips_first | 9 | 0 | 30% |  |
| subject_002_squat_good_side | tuning | side | normal |  | 13 | 3 | 24% | -,-,squat_no_lockout |
| subject_003_back_good_side | heldout | side | normal |  | 19 | 0 | 0% |  |
| subject_003_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_sag | 15 | 8 | 1% | setup_side_view,-,-,-,-,-,-,- |
| subject_003_push_up_bad_front | heldout | front | wrong | pushup_hip_sag | 15 | 14 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_003_push_up_bad_side | heldout | side | wrong | pushup_hip_sag | 15|14 | 15 | 0% | -,-,pushup_head_up,pushup_head_up,pushup_head_up,pushup_shallow,pushup_shallow+pushup_head_up+pushup_depth_fade,pushup_head_up+pushup_depth_fade,pushup_shallow+ |
| subject_003_push_up_good_diagonal | heldout | diag | normal |  | 19 | 11 | 0% | setup_side_view,-,-,-,-,pushup_hip_sag+pushup_no_lockout+pushup_head_up,-,-,-,-,- |
| subject_003_push_up_good_front | heldout | front | normal |  | 19|18 | 17 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_003_push_up_good_side | heldout | side | normal |  | 18 | 18 | 0% | pushup_head_up,pushup_head_up,pushup_no_lockout,pushup_shallow,pushup_shallow+pushup_head_up,pushup_shallow+pushup_head_up+pushup_depth_fade,pushup_shallow+push |
| subject_003_squat_bad_side | heldout | side | wrong | squat_shallow | 22|21 | 12 | 6% | -,-,-,-,-,squat_no_lockout,-,-,squat_no_lockout,squat_no_lockout,squat_no_lockout,- |
| subject_003_squat_good_side | heldout | side | normal |  | 19 | 0 | 40% |  |
| subject_004_back_bad_side | tuning | side | uncertain |  | 13 | 0 | 0% |  |
| subject_004_back_good_side | tuning | side | uncertain |  | 13 | 2 | 0% | -,row_head_up |
| subject_004_push_up_bad_diagonal | tuning | diag | uncertain |  | 7 | 8 | 0% | pushup_hip_sag,-,pushup_hip_sag,pushup_hip_sag,pushup_hip_sag,pushup_hip_sag,pushup_hip_sag+pushup_shallow,pushup_hip_sag+pushup_no_lockout+pushup_head_up |
| subject_004_push_up_bad_front | tuning | front | uncertain |  | 7 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_004_push_up_bad_side | tuning | side | wrong | pushup_hip_sag | 7 | 7 | 0% | -,-,-,-,-,pushup_shallow,pushup_hip_pike+pushup_shallow |
| subject_004_push_up_good_diagonal | tuning | diag | normal |  | 6 | 7 | 0% | pushup_hip_sag,-,-,pushup_hip_sag+pushup_no_lockout+pushup_head_up,pushup_hip_sag,pushup_hip_sag,pushup_hip_sag+pushup_no_lockout |
| subject_004_push_up_good_front | tuning | front | normal |  | 6|7 | 5 | 3% | setup_side_view,-,-,-,- |
| subject_004_push_up_good_side | tuning | side | normal |  | 6 | 7 | 0% | -,-,-,-,-,-,- |
| subject_004_squat_bad_side | tuning | side | wrong | squat_shallow | 12 | 1 | 17% | - |
| subject_004_squat_good_side | tuning | side | normal |  | 10|11 | 11 | 2% | -,-,squat_no_lockout,squat_no_lockout,-,-,-,squat_no_lockout,-,squat_no_lockout,- |
| subject_005_back_bad_side | tuning | side | wrong | row_short_pull | 16|17 | 0 | 0% |  |
| subject_005_back_good_side | tuning | side | normal |  | 14 | 1 | 0% | - |
| subject_005_push_up_bad_diagonal | tuning | diag | wrong | pushup_shallow | 8|9 | 9 | 0% | -,-,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_shallow,-,pushup_hip_pike+pushup_shallow+pushup_depth_fade,-,pushup_hip |
| subject_005_push_up_bad_front | tuning | front | wrong | pushup_shallow | 8|9 | 4 | 0% | setup_side_view,-,-,- |
| subject_005_push_up_bad_side | tuning | side | wrong | pushup_shallow | 8 | 5 | 0% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_shallow,pushup_hip_pike+pushup_head_up |
| subject_005_push_up_good_diagonal | tuning | diag | normal |  | 7 | 7 | 0% | pushup_hip_pike,pushup_hip_pike+pushup_no_lockout+pushup_head_up,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_shallow,pushup_hip_pike+pushup_shallow,p |
| subject_005_push_up_good_front | tuning | front | normal |  | 7 | 3 | 0% | setup_side_view,-,- |
| subject_005_push_up_good_side | tuning | side | normal |  | 7|6 | 8 | 1% | -,-,-,pushup_no_lockout,pushup_no_lockout,pushup_shallow,pushup_no_lockout,pushup_no_lockout |
| subject_006_back_bad_side | heldout | side | wrong | row_short_pull | 22 | 1 | 0% | row_torso_swing+row_head_up |
| subject_006_back_good_side | heldout | side | normal |  | 23|24 | 0 | 1% |  |
| subject_006_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_pike | 8 | 8 | 0% | setup_side_view,-,pushup_hip_pike+pushup_no_lockout+pushup_head_up,-,pushup_hip_pike+pushup_shallow+pushup_no_lockout+pushup_head_up,pushup_hip_pike+pushup_no_l |
| subject_006_push_up_bad_front | heldout | front | wrong | pushup_hip_pike | 8 | 8 | 0% | setup_side_view,-,-,-,-,-,-,- |
| subject_006_push_up_bad_side | heldout | side | wrong | pushup_hip_pike | 8 | 8 | 1% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_no_lockout,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_no_lock |
| subject_006_push_up_good_diagonal | heldout | diag | normal |  | 16 | 16 | 0% | pushup_hand_position,-,-,pushup_head_up,-,pushup_hip_pike,pushup_head_up,pushup_head_up,pushup_head_drop,pushup_head_up,pushup_head_up,-,pushup_head_up,-,-,push |
| subject_006_push_up_good_front | heldout | front | normal |  | 17|16 | 5 | 0% | setup_side_view,-,-,-,- |
| subject_006_push_up_good_side | heldout | side | normal |  | 15|16 | 16 | 1% | -,-,-,-,-,-,-,-,-,-,-,-,pushup_no_lockout,-,pushup_no_lockout,pushup_no_lockout |
| subject_007_back_bad_side | tuning | side | wrong | row_torso_swing | 18|17 | 0 | 1% |  |
| subject_007_back_good_side | tuning | side | uncertain |  | 17 | 1 | 0% | row_torso_swing+row_head_up |
| subject_007_push_up_good_diagonal | tuning | diag | normal |  | 19 | 19 | 0% | setup_side_view,-,-,-,-,-,-,pushup_no_lockout,pushup_hip_pike+pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,-,-,-,-,-,- |
| subject_007_push_up_good_front | tuning | front | normal |  | 18 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_007_push_up_good_side | tuning | side | normal |  | 19 | 7 | 4% | pushup_head_up,-,pushup_no_lockout+pushup_head_drop+pushup_head_up,-,pushup_head_up,pushup_shallow+pushup_no_lockout+pushup_head_up,pushup_shallow+pushup_no_loc |
| subject_007_squat_bad_side | tuning | side | uncertain |  | 17 | 3 | 21% | -,-,- |
| subject_007_squat_good_side | tuning | side | normal |  | 15 | 8 | 9% | -,-,squat_no_lockout,-,-,-,-,- |
| subject_008_back_bad_side | tuning | side | uncertain |  | 14 | 2 | 7% | row_torso_swing,row_torso_swing+row_head_up |
| subject_008_back_good_side | tuning | side | uncertain |  | 13 | 1 | 0% | row_head_up |
| subject_008_push_up_bad_diagonal | tuning | diag | wrong | pushup_head_drop;pushup_hip_pike | 9 | 9 | 0% | setup_side_view,-,-,-,-,-,-,-,- |
| subject_008_push_up_bad_front | tuning | front | uncertain |  | 8 | 1 | 2% | setup_side_view |
| subject_008_push_up_bad_side | tuning | side | wrong | pushup_hip_pike | 7 | 7 | 4% | -,-,-,-,pushup_head_up,-,pushup_head_up |
| subject_008_push_up_good_diagonal | tuning | diag | normal |  | 7 | 7 | 1% | setup_side_view,-,-,-,-,-,- |
| subject_008_push_up_good_front | tuning | front | normal |  | 8 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_008_push_up_good_side | tuning | side | normal |  | 8 | 8 | 2% | -,pushup_head_up,-,-,-,-,-,pushup_no_lockout+pushup_head_up |
| subject_008_squat_bad_side | tuning | side | wrong | squat_shallow | 22 | 20 | 0% | -,-,-,-,-,-,-,-,-,squat_lean_drift,squat_lean_drift,-,squat_no_lockout+squat_lean_drift,squat_lean_drift,squat_lean_drift,squat_lean_drift,squat_lean_drift,-,-, |
| subject_008_squat_good_side | tuning | side | normal |  | 14 | 13 | 1% | -,-,-,squat_no_lockout,-,-,-,-,-,-,-,-,- |
| subject_009_back_bad_side | heldout | side | wrong | row_torso_swing | 17 | 1 | 3% | row_torso_swing+row_head_up |
| subject_009_back_good_side | heldout | side | normal |  | 12 | 0 | 2% |  |
| subject_009_push_up_bad_diagonal | heldout | diag | wrong | pushup_shallow | 7 | 7 | 2% | pushup_hip_pike,pushup_hip_pike,-,pushup_head_up,pushup_hip_pike,-,pushup_head_up |
| subject_009_push_up_bad_front | heldout | front | wrong | pushup_shallow | 7 | 2 | 4% | setup_side_view,- |
| subject_009_push_up_bad_side | heldout | side | wrong | pushup_shallow | 7 | 4 | 6% | pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up |
| subject_009_push_up_good_diagonal | heldout | diag | normal |  | 7 | 7 | 0% | pushup_hip_pike+pushup_head_up,pushup_hip_pike,pushup_hip_pike+pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_hip_pike+pushup_head_up |
| subject_009_push_up_good_front | heldout | front | normal |  | 7|8 | 1 | 0% | setup_side_view |
| subject_009_push_up_good_side | heldout | side | normal |  | 6 | 5 | 8% | -,-,pushup_head_up,pushup_head_up,pushup_no_lockout+pushup_head_up |
| subject_009_squat_bad_side | heldout | side | wrong | squat_shallow | 17|18 | 7 | 4% | -,-,-,-,-,-,- |
| subject_009_squat_good_side | heldout | side | normal |  | 9 | 5 | 11% | -,-,-,-,- |
| subject_010_back_bad_side | heldout | side | wrong | row_torso_swing | 17 | 4 | 0% | row_torso_swing+row_head_up,row_torso_swing+row_head_up,row_torso_swing+row_head_up,row_torso_swing+row_head_up |
| subject_010_back_good_side | heldout | side | normal |  | 17|20 | 0 | 0% |  |
| subject_010_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_sag | 8 | 8 | 0% | setup_side_view,-,-,-,-,-,-,- |
| subject_010_push_up_bad_side | heldout | side | wrong | pushup_hip_sag | 8 | 8 | 2% | pushup_head_up,pushup_no_lockout,pushup_head_up,pushup_head_up,-,-,-,- |
| subject_010_push_up_good_diagonal | heldout | diag | normal |  | 19 | 20 | 0% | -,-,pushup_head_up,pushup_no_lockout,pushup_head_up,pushup_head_up,-,-,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_no_lockout+pushup_head |
| subject_010_push_up_good_front | heldout | front | normal |  | 19 | 11 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,- |
| subject_010_squat_bad_side | heldout | side | uncertain |  | 15 | 4 | 9% | -,-,-,- |
| subject_010_squat_good_side | heldout | side | normal |  | 16 | 2 | 7% | -,- |
| subject_011_back_bad_side | tuning | side | wrong | row_torso_swing | 14 | 0 | 9% |  |
| subject_011_back_good_side | tuning | side | normal |  | 16|15 | 0 | 14% |  |
| subject_011_push_up_bad_side | tuning | side | uncertain |  | 5 | 5 | 4% | pushup_hand_position,pushup_head_up,-,pushup_hip_pike,- |
| subject_011_push_up_good_diagonal | tuning | diag | normal |  | 7|8 | 7 | 7% | -,pushup_no_lockout+pushup_head_up,pushup_no_lockout,-,pushup_head_up,-,pushup_hip_pike+pushup_head_up |
| subject_011_push_up_good_front | tuning | front | normal |  | 7|8 | 8 | 0% | setup_side_view,-,-,-,-,-,-,- |
| subject_011_push_up_good_side | tuning | side | normal |  | 7|8 | 8 | 0% | -,-,-,pushup_shallow,-,pushup_no_lockout,-,pushup_no_lockout |
| subject_011_squat_good_side | tuning | side | normal |  | 13 | 3 | 10% | -,-,- |
| subject_012_back_bad_side | heldout | side | wrong | row_torso_swing | 13 | 0 | 0% |  |
| subject_012_back_good_side | heldout | side | normal |  | 15|13 | 0 | 0% |  |
| subject_012_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_pike | 9 | 9 | 3% | setup_side_view,pushup_head_up,-,-,pushup_head_up,pushup_head_up,pushup_head_up,-,- |
| subject_012_push_up_bad_front | heldout | front | wrong | pushup_hip_pike | 8|9 | 3 | 2% | setup_side_view,-,- |
| subject_012_push_up_bad_side | heldout | side | wrong | pushup_hip_pike | 9 | 9 | 1% | -,pushup_hip_pike,pushup_hip_pike+pushup_no_lockout+pushup_head_up,pushup_hip_pike,-,pushup_shallow+pushup_head_up,-,pushup_hip_pike+pushup_head_up,- |
| subject_012_push_up_good_diagonal | heldout | diag | normal |  | 18 | 17 | 1% | setup_side_view,-,pushup_hip_pike+pushup_head_up,-,-,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_head_up,pushup_no_lockout+pushup_head_up,-,pushup_hip |
| subject_012_push_up_good_front | heldout | front | normal |  | 19 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_012_push_up_good_side | heldout | side | normal |  | 18 | 18 | 0% | -,-,-,pushup_no_lockout,pushup_head_up,-,pushup_shallow+pushup_no_lockout,-,pushup_shallow+pushup_no_lockout+pushup_depth_fade,pushup_depth_fade,pushup_no_locko |
| subject_012_squat_bad_side | heldout | side | wrong | squat_shallow | 14|15 | 3 | 2% | -,squat_no_lockout,- |
| subject_012_squat_good_side | heldout | side | normal |  | 12 | 7 | 4% | -,-,-,-,-,squat_no_lockout,- |
| subject_013_back_bad_side | heldout | side | wrong | row_torso_swing | 15|16 | 0 | 1% |  |
| subject_013_back_good_side | heldout | side | normal |  | 0 | 0 | 0% |  |
| subject_013_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_sag | 11 | 11 | 2% | pushup_head_up+pushup_hand_position,pushup_head_drop,pushup_no_lockout,pushup_hip_pike+pushup_head_up,pushup_head_up,pushup_head_up,pushup_no_lockout+pushup_hea |
| subject_013_push_up_bad_front | heldout | front | wrong | pushup_hip_sag | 11|10 | 2 | 0% | setup_side_view,- |
| subject_013_push_up_bad_side | heldout | side | wrong | pushup_hip_sag | 11 | 11 | 0% | -,pushup_head_up,pushup_head_up,-,pushup_head_up,pushup_head_up+pushup_depth_fade,pushup_head_up+pushup_depth_fade,pushup_depth_fade,pushup_head_up+pushup_depth |
| subject_013_push_up_good_diagonal | heldout | diag | normal |  | 16 | 14 | 1% | pushup_hand_position,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pushup_head_drop+pushup_head_up,pushup_no_lockout+pushup_head_up,-,pushup_hip_pike+pushu |
| subject_013_push_up_good_front | heldout | front | normal |  | 16|15 | 10 | 3% | setup_side_view,-,-,-,-,-,-,-,-,- |
| subject_013_squat_bad_side | heldout | side | wrong | squat_shallow | 14 | 2 | 9% | -,- |
| subject_013_squat_good_side | heldout | side | normal |  | 13 | 4 | 2% | -,-,-,- |
| subject_014_back_bad_side | heldout | side | wrong | row_torso_swing | 16 | 1 | 0% | row_torso_swing+row_head_up |
| subject_014_back_good_side | heldout | side | normal |  | 15 | 0 | 2% |  |
| subject_014_push_up_bad_diagonal | heldout | diag | wrong | pushup_head_drop | 9|11 | 9 | 0% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_no_lockou |
| subject_014_push_up_bad_front | heldout | front | wrong | pushup_head_drop | 11|12 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_014_push_up_good_diagonal | heldout | diag | normal |  | 16 | 16 | 1% | pushup_hip_pike+pushup_head_up+pushup_hand_position,-,pushup_hip_pike,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_no_lockout,pushup_hip_pike+pushup_he |
| subject_014_push_up_good_front | heldout | front | normal |  | 17 | 0 | 2% |  |
| subject_014_push_up_good_side | heldout | side | normal |  | 16 | 16 | 0% | -,-,-,pushup_shallow,pushup_hip_pike+pushup_head_up,-,-,-,-,pushup_head_up,-,pushup_head_up+pushup_depth_fade,pushup_head_up,pushup_no_lockout,pushup_no_lockout |
| subject_014_squat_bad_side | heldout | side | wrong | squat_shallow | 14 | 7 | 7% | -,-,-,-,-,-,- |
| subject_015_back_bad_side | tuning | side | wrong | row_short_pull | 5|4 | 0 | 8% |  |
| subject_015_back_good_side | tuning | side | normal |  | 12 | 0 | 2% |  |
| subject_015_push_up_bad_diagonal | tuning | diag | wrong | pushup_hip_sag | 4 | 4 | 0% | pushup_head_up,-,-,pushup_head_up |
| subject_015_push_up_bad_front | tuning | front | uncertain |  | 4 | 1 | 0% | setup_side_view |
| subject_015_push_up_bad_side | tuning | side | wrong | pushup_hip_sag | 4 | 4 | 0% | pushup_head_up,-,-,- |
| subject_015_push_up_good_diagonal | tuning | diag | normal |  | 13 | 13 | 0% | pushup_hip_pike+pushup_hand_position,pushup_no_lockout,-,pushup_hip_pike+pushup_no_lockout,pushup_no_lockout+pushup_head_up,pushup_no_lockout,pushup_no_lockout+ |
| subject_015_push_up_good_front | tuning | front | normal |  | 13|12 | 1 | 6% | setup_side_view |
| subject_015_push_up_good_side | tuning | side | normal |  | 12 | 13 | 0% | pushup_head_up+pushup_hand_position,-,-,pushup_hip_pike+pushup_head_up,pushup_no_lockout,pushup_head_up,-,pushup_no_lockout,-,pushup_no_lockout+pushup_head_up,p |
| subject_015_squat_bad_side | tuning | side | uncertain |  | 7 | 2 | 21% | -,- |
| subject_016_back_bad_side | tuning | side | uncertain |  | 18 | 0 | 0% |  |
| subject_016_back_good_side | tuning | side | normal |  | 13 | 0 | 0% |  |
| subject_016_push_up_bad_diagonal | tuning | diag | wrong | pushup_shallow | 16|17 | 17 | 1% | -,-,pushup_no_lockout,pushup_no_lockout,-,pushup_no_lockout,-,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,-,pushup |
| subject_016_push_up_bad_front | tuning | front | wrong | pushup_shallow | 18 | 2 | 0% | setup_side_view,- |
| subject_016_push_up_bad_side | tuning | side | wrong | pushup_shallow | 18|17 | 0 | 0% |  |
| subject_016_push_up_good_diagonal | tuning | diag | normal |  | 12 | 12 | 4% | pushup_head_up,-,-,pushup_head_up,pushup_head_up,-,pushup_no_lockout+pushup_head_up,pushup_head_up,-,pushup_head_up,-,pushup_head_up |
| subject_016_push_up_good_front | tuning | front | normal |  | 19 | 8 | 0% | setup_side_view,-,-,-,-,-,-,- |
| subject_016_push_up_good_side | tuning | side | normal |  | 17 | 16 | 0% | -,-,-,pushup_shallow,pushup_shallow,pushup_shallow+pushup_depth_fade,pushup_shallow+pushup_depth_fade,-,pushup_shallow,-,-,-,-,-,-,- |
| subject_016_squat_bad_side | tuning | side | wrong | squat_heel_rise;squat_shallow | 12 | 2 | 23% | -,- |
| subject_016_squat_good_side | tuning | side | normal |  | 11 | 6 | 12% | -,squat_no_lockout,-,-,-,- |
| subject_017_back_bad_side | heldout | side | wrong | row_standing_up | 21|16 | 1 | 0% | - |
| subject_017_back_good_side | heldout | side | normal |  | 20|16 | 1 | 0% | row_torso_swing+row_head_up |
| subject_017_push_up_bad_diagonal | heldout | diag | wrong | pushup_head_drop | 6|7 | 7 | 0% | pushup_head_up,pushup_head_up,pushup_head_up,-,pushup_head_up,pushup_no_lockout+pushup_head_up,- |
| subject_017_push_up_bad_front | heldout | front | wrong | pushup_head_drop | 8 | 4 | 0% | setup_side_view,-,-,- |
| subject_017_push_up_bad_side | heldout | side | wrong | pushup_head_drop | 10 | 10 | 0% | -,-,pushup_head_up,-,-,-,pushup_head_up,-,pushup_head_up,pushup_no_lockout |
| subject_017_push_up_good_diagonal | heldout | diag | normal |  | 8 | 9 | 0% | pushup_head_up,pushup_head_up,pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_no_lockout,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pushup_head_u |
| subject_017_push_up_good_front | heldout | front | normal |  | 9 | 0 | 5% |  |
| subject_017_push_up_good_side | heldout | side | normal |  | 7 | 6 | 0% | -,-,-,-,-,- |
| subject_017_squat_bad_side | heldout | side | uncertain |  | 12 | 5 | 20% | -,-,-,-,- |
| subject_017_squat_good_side | heldout | side | uncertain |  | 13 | 11 | 4% | -,-,-,-,-,-,-,-,-,-,- |
| subject_018_back_bad_side | heldout | side | wrong | row_standing_up | 14|13 | 0 | 0% |  |
| subject_018_back_good_side | heldout | side | normal |  | 17|15 | 0 | 0% |  |
| subject_018_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_pike | 7 | 7 | 0% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_no_lockout+pushup_head_up,pushup_hip_pike,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_head_up,p |
| subject_018_push_up_bad_front | heldout | front | uncertain |  | 8 | 4 | 6% | setup_side_view,-,-,- |
| subject_018_push_up_bad_side | heldout | side | wrong | pushup_hip_pike | 8 | 8 | 0% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_no_lockout,pushup_hip_pike+pushup_head_up,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike |
| subject_018_push_up_good_diagonal | heldout | diag | normal |  | 8 | 8 | 0% | pushup_head_up,pushup_head_up,pushup_hip_pike+pushup_no_lockout+pushup_head_up,pushup_no_lockout,pushup_no_lockout+pushup_head_up,pushup_hip_pike+pushup_head_up |
| subject_018_push_up_good_front | heldout | front | normal |  | 10 | 0 | 0% |  |
| subject_018_push_up_good_side | heldout | side | normal |  | 8 | 8 | 0% | -,-,-,-,-,-,-,- |
| subject_018_squat_bad_side | heldout | side | uncertain |  | 11 | 5 | 10% | -,-,-,squat_no_lockout,- |
| subject_018_squat_good_side | heldout | side | normal |  | 14 | 12 | 3% | -,squat_no_lockout,-,-,-,-,-,-,-,-,-,- |
| subject_019_back_good_side | tuning | side | normal |  | 12|11 | 0 | 0% |  |
| subject_019_push_up_bad_diagonal | tuning | diag | uncertain |  | 0 | 1 | 3% | pushup_head_drop+pushup_hand_position |
| subject_019_push_up_bad_front | tuning | front | uncertain |  | 0 | 0 | 0% |  |
| subject_019_push_up_good_diagonal | tuning | diag | normal |  | 2 | 3 | 2% | pushup_hip_pike,-,pushup_no_lockout+pushup_head_up |
| subject_019_push_up_good_front | tuning | front | normal |  | 2 | 1 | 0% | setup_side_view |
| subject_019_squat_bad_side | tuning | side | wrong | squat_hips_first | 7 | 4 | 8% | -,-,squat_no_lockout,squat_no_lockout |
| subject_019_squat_good_side | tuning | side | normal |  | 10 | 10 | 2% | -,-,-,-,-,-,-,-,squat_no_lockout,- |
| subject_020_back_bad_side | heldout | side | wrong | row_torso_swing | 13|12 | 0 | 0% |  |
| subject_020_back_good_side | heldout | side | normal |  | 15|13 | 0 | 0% |  |
| subject_020_push_up_good_diagonal | heldout | diag | normal |  | 14 | 13 | 0% | -,pushup_head_up,-,-,-,-,-,-,-,-,-,-,- |
| subject_020_push_up_good_front | heldout | front | normal |  | 16|17 | 13 | 4% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_020_push_up_good_side | heldout | side | normal |  | 16 | 6 | 1% | -,-,-,-,-,- |
| subject_020_squat_bad_side | heldout | side | uncertain |  | 11 | 8 | 5% | -,-,-,-,-,-,-,squat_shallow |
| subject_020_squat_good_side | heldout | side | normal |  | 15 | 16 | 2% | -,-,-,-,-,-,-,-,-,-,-,-,squat_no_lockout,-,-,- |
| subject_021_back_bad_side | tuning | side | uncertain |  | 13 | 0 | 0% |  |
| subject_021_back_good_side | tuning | side | normal |  | 14|13 | 0 | 0% |  |
| subject_021_push_up_bad_side | tuning | side | wrong | pushup_no_lockout | 14|15 | 14 | 2% | pushup_hand_position,-,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_021_push_up_good_diagonal | tuning | diag | normal |  | 13|16 | 14 | 0% | pushup_head_up,-,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_head_up,pushup_head_up,pushu |
| subject_021_push_up_good_front | tuning | front | normal |  | 14|17 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_021_push_up_good_side | tuning | side | normal |  | 15|16 | 16 | 0% | -,-,-,pushup_no_lockout,-,-,-,pushup_no_lockout,-,-,-,-,-,-,-,- |
| subject_021_squat_bad_side | tuning | side | wrong | squat_heel_rise | 15 | 8 | 8% | -,-,-,-,squat_shallow,-,-,squat_shallow+squat_no_lockout |
| subject_021_squat_good_side | tuning | side | normal |  | 0 | 1 | 28% | - |
| subject_022_back_bad_side | tuning | side | wrong | row_standing_up | 20|21 | 0 | 0% |  |
| subject_022_back_good_side | tuning | side | normal |  | 12 | 0 | 2% |  |
| subject_022_push_up_bad_diagonal | tuning | diag | wrong | pushup_hip_pike | 12 | 12 | 0% | setup_side_view,-,pushup_hip_pike+pushup_head_up,-,-,-,-,-,-,-,-,- |
| subject_022_push_up_bad_front | tuning | front | uncertain |  | 13 | 9 | 0% | setup_side_view,-,-,-,-,-,-,-,- |
| subject_022_push_up_bad_side | tuning | side | wrong | pushup_hip_pike | 12 | 12 | 0% | -,-,pushup_head_up,pushup_head_up,pushup_no_lockout,-,pushup_no_lockout+pushup_head_up,pushup_hip_pike+pushup_no_lockout,pushup_no_lockout,pushup_no_lockout,pus |
| subject_022_push_up_good_diagonal | tuning | diag | normal |  | 15|17 | 17 | 0% | setup_side_view,-,-,-,-,-,-,pushup_hip_pike+pushup_head_up,-,-,-,-,-,-,-,-,- |
| subject_022_push_up_good_front | tuning | front | normal |  | 16|18 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_022_push_up_good_side | tuning | side | normal |  | 16|18 | 18 | 0% | -,-,-,-,pushup_head_up,pushup_head_up,-,-,-,-,pushup_head_up,-,-,-,pushup_head_up,pushup_head_up,pushup_head_up,- |
| subject_022_squat_bad_side | tuning | side | uncertain |  | 16 | 8 | 11% | -,-,-,-,-,-,-,- |
| subject_022_squat_good_side | tuning | side | normal |  | 14 | 3 | 3% | -,-,- |
| subject_023_back_good_side | heldout | diag | uncertain |  | 8 | 0 | 0% |  |
| subject_023_push_up_bad_diagonal | heldout | diag | wrong | pushup_head_drop | 7 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_023_push_up_bad_side | heldout | side | wrong | pushup_head_drop | 7 | 8 | 0% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,-,pushup_hip_pike,-,pushup_hip_pike,pushup_hip_pike+pushup_no_lockout |
| subject_023_push_up_good_diagonal | heldout | diag | normal |  | 11 | 12 | 1% | pushup_hip_pike+pushup_head_up,pushup_hip_pike,pushup_hip_pike+pushup_no_lockout,pushup_hip_pike+pushup_no_lockout,pushup_hip_pike+pushup_no_lockout+pushup_head |
| subject_023_push_up_good_side | heldout | side | normal |  | 11 | 11 | 0% | -,-,-,-,-,-,-,pushup_head_up,-,-,pushup_depth_fade |
| subject_024_back_bad_side | heldout | side | wrong | row_short_pull | 12|17 | 0 | 1% |  |
| subject_024_back_good_side | heldout | side | normal |  | 13|14 | 0 | 0% |  |
| subject_024_push_up_bad_diagonal | heldout | diag | wrong | pushup_shallow | 12|14 | 9 | 0% | setup_side_view,-,-,-,-,-,-,-,- |
| subject_024_push_up_bad_front | heldout | front | wrong | pushup_shallow | 13 | 4 | 0% | setup_side_view,-,-,- |
| subject_024_push_up_bad_side | heldout | side | wrong | pushup_shallow | 12 | 6 | 2% | pushup_head_up,pushup_head_up,pushup_head_up,-,pushup_head_up,pushup_hip_pike+pushup_head_up |
| subject_024_push_up_good_diagonal | heldout | diag | normal |  | 10 | 10 | 0% | setup_side_view,-,-,-,-,-,-,-,-,- |
| subject_024_push_up_good_front | heldout | front | normal |  | 10 | 3 | 0% | setup_side_view,-,- |
| subject_024_push_up_good_side | heldout | side | normal |  | 10 | 10 | 0% | -,-,-,pushup_no_lockout+pushup_head_up,-,-,pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pushup_head_up |
| subject_024_squat_bad_side | heldout | side | wrong | squat_hips_first | 11 | 1 | 30% | - |
| subject_024_squat_good_side | heldout | side | normal |  | 9 | 10 | 2% | -,-,-,-,-,squat_no_lockout,-,-,squat_no_lockout,- |
| subject_026_squat_good_side | tuning | side | normal |  | 12 | 2 | 29% | -,- |
| yt_0KtrNQre5rQ_4 | heldout | side | normal |  | 2 | 2 | 1% | -,- |
| yt_0KtrNQre5rQ_5 | heldout | side | normal |  | 1 | 1 | 15% | - |
| yt_29-XfdGXqjw_1 | heldout | diag | normal |  | 3 | 4 | 0% | -,-,-,- |
| yt_2YCCekX2Umo_1 | tuning | side | normal |  | 2 | 0 | 0% |  |
| yt_3nnzOvAAbP8_1 | tuning | front | normal |  | 3 | 0 | 0% |  |
| yt_3nnzOvAAbP8_2 | tuning | side | normal |  | 2 | 2 | 1% | -,- |
| yt_4ALA64JLQoE_2 | heldout | side | uncertain |  | 5 | 5 | 0% | -,-,-,-,- |
| yt_98J9aiV69p8_1 | heldout | side | wrong | pushup_head_up;pushup_hip_sag | 2 | 2 | 3% | pushup_hip_sag,pushup_hip_sag+pushup_no_lockout |
| yt_98J9aiV69p8_2 | heldout | side | normal |  | 5 | 5 | 0% | -,-,-,-,- |
| yt_A1XZcaFRrBo_1 | heldout | side | normal |  | 0 | 0 | 7% |  |
| yt_A1XZcaFRrBo_2 | heldout | side | normal |  | 0|2 | 0 | 0% |  |
| yt_A1XZcaFRrBo_3 | heldout | side | wrong | row_standing_up | 3|4 | 1 | 2% | - |
| yt_APNV5mki_V8_1 | heldout | diag | normal |  | 10|12 | 9 | 0% | -,-,-,-,-,-,-,-,- |
| yt_APNV5mki_V8_2 | heldout | diag | normal |  | 5 | 4 | 1% | -,-,-,- |
| yt_DVGi7h0lL3A_1 | tuning | side | normal |  | 2 | 2 | 0% | -,- |
| yt_DVGi7h0lL3A_2 | tuning | side | normal |  | 1 | 2 | 0% | -,- |
| yt_DVGi7h0lL3A_3 | tuning | side | wrong | pushup_shallow | 3 | 3 | 1% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike |
| yt_DVGi7h0lL3A_4 | tuning | side | wrong | pushup_hip_pike | 1 | 2 | 2% | pushup_hip_pike,pushup_hip_pike |
| yt_DVGi7h0lL3A_5 | tuning | side | wrong | pushup_hip_sag | 3 | 3 | 0% | -,pushup_hip_sag,pushup_hip_sag |
| yt_Ds9yTAPwv00_1 | heldout | side | uncertain |  | 2 | 2 | 15% | -,squat_no_lockout |
| yt_Ds9yTAPwv00_2 | heldout | side | normal |  | 2 | 1 | 24% | - |
| yt_Ds9yTAPwv00_4 | heldout | side | normal |  | 1 | 1 | 0% | - |
| yt_F7umlBUzKVU_1 | tuning | diag | normal |  | 4|8 | 7 | 1% | -,-,-,-,-,-,- |
| yt_HG542yssLsc_1 | tuning | side | wrong | squat_shallow | 3 | 1 | 22% | - |
| yt_HG542yssLsc_2 | tuning | side | normal |  | 1 | 1 | 0% | - |
| yt_HG542yssLsc_3 | tuning | side | wrong | squat_shallow | 2 | 2 | 2% | -,- |
| yt_HG542yssLsc_4 | tuning | side | normal |  | 1 | 1 | 6% | - |
| yt_JklNoB4eyhw_1 | heldout | diag | normal |  | 3 | 3 | 1% | -,-,- |
| yt_JklNoB4eyhw_2 | heldout | diag | normal |  | 1 | 3 | 0% | pushup_hip_pike,pushup_hip_pike+pushup_no_lockout,- |
| yt_JnwWdvwGmAU_3 | heldout | diag | normal |  | 6 | 6 | 0% | pushup_hand_position,-,-,-,-,pushup_no_lockout |
| yt_Ka-yi9zHp2Q_2 | tuning | side | normal |  | 2 | 2 | 2% | -,row_head_up |
| yt_LCBEioFGYq8_1 | heldout | side | normal |  | 3 | 3 | 0% | -,-,- |
| yt_R1q-_wqz4sA_1 | heldout | side | normal |  | 4 | 4 | 0% | -,-,-,- |
| yt_R1q-_wqz4sA_2 | heldout | front | normal |  | 4 | 4 | 0% | setup_side_view,-,-,- |
| yt_TBNtGrr-owU_1 | heldout | diag | normal |  | 1 | 2 | 0% | pushup_hip_pike,pushup_hip_pike |
| yt_TBNtGrr-owU_2 | heldout | diag | normal |  | 2 | 2 | 1% | pushup_hip_pike,pushup_hip_pike |
| yt_WysdJhfVL3E_1 | tuning | side | wrong | squat_hips_first | 1 | 0 | 83% |  |
| yt_XOg81X0Tckw_1 | tuning | side | normal |  | 2|1 | 2 | 30% | -,- |
| yt_XOg81X0Tckw_2 | tuning | side | normal |  | 4|5 | 4 | 3% | -,pushup_head_up,-,- |
| yt_YvXXlKVmMaw_2 | heldout | side | normal |  | 1 | 1 | 9% | - |
| yt_d4l1BF0cY4U_1 | tuning | diag | normal |  | 1 | 1 | 1% | setup_side_view |
| yt_d4l1BF0cY4U_2 | tuning | diag | normal |  | 2 | 2 | 0% | setup_side_view,pushup_no_lockout+pushup_head_up |
| yt_dyLMJUOP3R4_1 | tuning | diag | normal |  | 2 | 2 | 0% | -,- |
| yt_fW6-ykp1cjk_1 | tuning | side | normal |  | 3 | 3 | 1% | -,-,- |
| yt_fY0jKtdVvzA_1 | tuning | side | normal |  | 2 | 0 | 23% |  |
| yt_gMJe6yeacsk_1 | heldout | side | wrong | row_standing_up;row_torso_swing | 3 | 3 | 2% | -,-,- |
| yt_gMJe6yeacsk_2 | heldout | side | normal |  | 3 | 3 | 0% | -,-,- |
| yt_h5jTRrFQzJs_1 | heldout | diag | uncertain |  | 6 | 6 | 0% | pushup_hip_pike,pushup_hip_pike+pushup_no_lockout,pushup_hip_pike,pushup_no_lockout,pushup_no_lockout,pushup_no_lockout |
| yt_h5jTRrFQzJs_2 | heldout | diag | uncertain |  | 3 | 4 | 0% | pushup_hip_pike+pushup_head_up,pushup_no_lockout,pushup_no_lockout,- |
| yt_hjNQPke32ww_1 | tuning | front | wrong | pushup_head_drop | 4 | 4 | 1% | setup_side_view,-,-,- |
| yt_hjNQPke32ww_2 | tuning | front | normal |  | 4 | 3 | 0% | setup_side_view,-,- |
| yt_m12ycyzTr5c_1 | heldout | side | normal |  | 4 | 0 | 18% |  |
| yt_m12ycyzTr5c_2 | heldout | side | normal |  | 1|2 | 0 | 7% |  |
| yt_m12ycyzTr5c_3 | heldout | side | normal |  | 2 | 2 | 12% | -,- |
| yt_mIG9SsVEvJg_1 | heldout | front | normal |  | 18 | 18 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,- |
| yt_p3a6iG_9kC0_1 | heldout | diag | uncertain |  | 0 | 0 | 0% |  |
| yt_p3a6iG_9kC0_2 | heldout | diag | wrong | pushup_hip_pike | 0 | 0 | 0% |  |
| yt_p3a6iG_9kC0_3 | heldout | diag | normal |  | 2 | 2 | 0% | pushup_hip_pike,- |
| yt_p3a6iG_9kC0_4 | heldout | diag | uncertain |  | 2 | 2 | 0% | pushup_hip_pike,pushup_no_lockout |
| yt_p3a6iG_9kC0_5 | heldout | diag | uncertain |  | 1 | 1 | 0% | pushup_head_up |
| yt_pVJ_2lspIzA_1 | heldout | diag | normal |  | 3|2 | 3 | 1% | -,-,- |
| yt_qZYOjVzRHhc_1 | tuning | side | normal |  | 4|3 | 3 | 0% | -,-,- |
| yt_qZYOjVzRHhc_2 | tuning | front | normal |  | 1 | 1 | 0% | setup_side_view |
| yt_s1EeH4nExEw_1 | heldout | diag | normal |  | 2|4 | 2 | 0% | -,row_torso_swing |
| yt_sO4dzMOmp5U_1 | tuning | side | normal |  | 4 | 4 | 0% | -,-,-,- |
| yt_uPU2rgRtzLE_1 | heldout | diag | normal |  | 3 | 3 | 0% | pushup_head_up,pushup_hip_pike,pushup_hip_pike |
| yt_uPU2rgRtzLE_2 | heldout | diag | uncertain |  | 1 | 1 | 1% | pushup_hip_pike |

replay 없음: subject_001_back_bad_diagonal subject_001_back_bad_front subject_001_back_good_diagonal subject_001_back_good_front subject_001_squat_bad_diagonal subject_001_squat_bad_front subject_001_squat_good_diagonal subject_001_squat_good_front subject_002_back_bad_diagonal subject_002_back_bad_front subject_002_back_good_diagonal subject_002_back_good_front subject_002_squat_bad_diagonal subject_002_squat_bad_front subject_002_squat_good_diagonal subject_002_squat_good_front subject_003_back_bad_diagonal subject_003_back_bad_front subject_003_back_good_diagonal subject_003_back_good_front subject_003_squat_bad_front subject_003_squat_good_front subject_004_back_bad_diagonal subject_004_back_bad_front subject_004_back_good_diagonal subject_004_back_good_front subject_004_squat_bad_diagonal subject_004_squat_bad_front subject_004_squat_good_diagonal subject_004_squat_good_front subject_005_back_bad_diagonal subject_005_back_bad_front subject_005_back_good_diagonal subject_005_back_good_front subject_005_squat_bad_diagonal subject_005_squat_bad_front subject_005_squat_good_diagonal subject_005_squat_good_front subject_006_back_bad_diagonal subject_006_back_bad_front subject_006_back_good_diagonal subject_006_back_good_front subject_006_squat_bad_diagonal subject_006_squat_bad_front subject_006_squat_good_diagonal subject_006_squat_good_front subject_007_back_bad_front subject_007_back_good_diagonal subject_007_back_good_front subject_007_squat_bad_diagonal subject_007_squat_bad_front subject_007_squat_good_front subject_008_back_bad_diagonal subject_008_back_bad_front subject_008_back_good_diagonal subject_008_back_good_front subject_008_squat_bad_diagonal subject_008_squat_bad_front subject_008_squat_good_diagonal subject_008_squat_good_front subject_009_back_bad_diagonal subject_009_back_bad_front subject_009_back_good_diagonal subject_009_back_good_front subject_009_squat_bad_diagonal subject_009_squat_bad_front subject_009_squat_good_diagonal subject_009_squat_good_front subject_010_back_bad_diagonal subject_010_back_bad_front subject_010_back_good_diagonal subject_010_back_good_front subject_010_squat_bad_diagonal subject_010_squat_bad_front subject_010_squat_good_diagonal subject_010_squat_good_front subject_011_back_bad_diagonal subject_011_back_bad_front subject_011_back_good_diagonal subject_011_back_good_front subject_011_squat_bad_diagonal subject_011_squat_bad_front subject_011_squat_good_diagonal subject_011_squat_good_front subject_012_back_bad_diagonal subject_012_back_bad_front subject_012_back_good_diagonal subject_012_back_good_front subject_012_squat_bad_diagonal subject_012_squat_bad_front subject_012_squat_good_diagonal subject_012_squat_good_front subject_013_back_bad_diagonal subject_013_back_bad_front subject_013_back_good_diagonal subject_013_back_good_front subject_013_squat_bad_diagonal subject_013_squat_bad_front subject_013_squat_good_diagonal subject_013_squat_good_front subject_014_back_bad_diagonal subject_014_back_bad_front subject_014_back_good_diagonal subject_014_back_good_front subject_014_squat_bad_diagonal subject_014_squat_bad_front subject_014_squat_good_diagonal subject_014_squat_good_front subject_015_back_bad_diagonal subject_015_back_bad_front subject_015_back_good_diagonal subject_015_back_good_front subject_015_squat_bad_diagonal subject_015_squat_bad_front subject_015_squat_good_diagonal subject_015_squat_good_front subject_016_back_bad_diagonal subject_016_back_bad_front subject_016_back_good_diagonal subject_016_back_good_front subject_016_squat_bad_diagonal subject_016_squat_bad_front subject_016_squat_good_diagonal subject_016_squat_good_front subject_017_back_bad_diagonal subject_017_back_bad_front subject_017_back_good_diagonal subject_017_back_good_front subject_017_squat_bad_diagonal subject_017_squat_bad_front subject_017_squat_good_diagonal subject_017_squat_good_front subject_018_back_bad_diagonal subject_018_back_bad_front subject_018_back_good_diagonal subject_018_back_good_front subject_018_squat_bad_diagonal subject_018_squat_bad_front subject_018_squat_good_diagonal subject_018_squat_good_front subject_019_back_bad_front subject_019_back_good_diagonal subject_019_back_good_front subject_019_squat_bad_diagonal subject_019_squat_bad_front subject_019_squat_good_diagonal subject_019_squat_good_front subject_020_back_bad_front subject_020_back_good_diagonal subject_020_back_good_front subject_020_squat_bad_diagonal subject_020_squat_bad_front subject_020_squat_good_diagonal subject_020_squat_good_front subject_021_back_bad_diagonal subject_021_back_bad_front subject_021_back_good_diagonal subject_021_back_good_front subject_021_squat_bad_diagonal subject_021_squat_bad_front subject_021_squat_good_diagonal subject_021_squat_good_front subject_022_back_bad_diagonal subject_022_back_bad_front subject_022_back_good_diagonal subject_022_back_good_front subject_022_squat_bad_diagonal subject_022_squat_bad_front subject_022_squat_good_diagonal subject_022_squat_good_front subject_023_squat_bad_diagonal subject_023_squat_bad_front subject_023_squat_good_diagonal subject_023_squat_good_front subject_024_back_bad_diagonal subject_024_back_bad_front subject_024_back_good_diagonal subject_024_back_good_front subject_024_squat_bad_diagonal subject_024_squat_bad_front subject_024_squat_good_diagonal subject_024_squat_good_front subject_026_squat_bad_diagonal subject_026_squat_bad_front subject_026_squat_good_diagonal subject_026_squat_good_front yt_0KtrNQre5rQ_1 yt_0KtrNQre5rQ_2 yt_0KtrNQre5rQ_3 yt_0_c1I7GatDw_1 yt_0_c1I7GatDw_2 yt_0_c1I7GatDw_3 yt_0_c1I7GatDw_4 yt_4FV_oEgDkX0_1 yt_4FV_oEgDkX0_2 yt_4FV_oEgDkX0_3 yt_4FV_oEgDkX0_4 yt_9Qc45eJQQTE_1 yt_DCnDjdobuLk_1 yt_DCnDjdobuLk_2 yt_DCnDjdobuLk_3 yt_DCnDjdobuLk_4 yt_DCnDjdobuLk_5 yt_DCnDjdobuLk_6 yt_Ds9yTAPwv00_3 yt_Ds9yTAPwv00_5 yt_Ds9yTAPwv00_6 yt_EyAC8jSJIYQ_1 yt_F7umlBUzKVU_2 yt_Ka-yi9zHp2Q_1 yt_M2fI9s51Q0E_1 yt_M2fI9s51Q0E_2 yt_M2fI9s51Q0E_3 yt_SwIUivmPrQ8_1 yt_SwIUivmPrQ8_2 yt_T5J-Ao3DXE0_1 yt_T5J-Ao3DXE0_2 yt_T5J-Ao3DXE0_3 yt_U267qtP0NSo_1 yt_V9y7P9vbcME_1 yt_WysdJhfVL3E_2 yt_WysdJhfVL3E_3 yt_WysdJhfVL3E_4 yt_WysdJhfVL3E_5 yt_YvXXlKVmMaw_1 yt_fv2PvU6Xzwk_1 yt_gm4ln6PO4rc_1 yt_gm4ln6PO4rc_2 yt_gm4ln6PO4rc_3 yt_gm4ln6PO4rc_4 yt_h-TqBZlxszM_1 yt_hO27xMs4wns_1 yt_jxUoaZJxkVM_1 yt_ktKsQYqJthw_1 yt_ktKsQYqJthw_2 yt_m16KdkLHyrA_1 yt_m16KdkLHyrA_2 yt_m16KdkLHyrA_3 yt_o-872ZN3NHs_1 yt_uVlVESedmU0_1 yt_v-UQLV_aMEk_1 yt_zOztB9_kpXA_1
