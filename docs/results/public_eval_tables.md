# 공개 데이터 평가 (pose-replay, RTMPose-m COCO17 기본, crop, ready-pose off, 3D 없음)

라벨 행 571, 렙 평가 세트 386, 자세 평가 세트 429, replay 없음 0


### 렙 정확도 — mendeley_mv7 (모든 자세)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 18 | 190 | 48 | 1 | 74.3% | 8/18 | 74.7% | 9/18 |
| pushup | side | tuning | 14 | 147 | 75 | 3 | 48.0% | 3/14 | 48.3% | 4/14 |
| pushup | diag | heldout | 20 | 234 | 31 | 3 | 85.7% | 10/20 | 86.8% | 13/20 |
| pushup | diag | tuning | 16 | 165 | 12 | 2 | 91.6% | 11/16 | 92.7% | 13/16 |
| pushup | front | heldout | 12 | 143 | 90 | 0 | 37.1% | 1/12 | 37.1% | 1/12 |
| pushup | front | tuning | 15 | 168 | 79 | 0 | 53.0% | 3/15 | 53.0% | 3/15 |
| pushup | 전체 | heldout | 50 | 567 | 169 | 4 | 69.7% | 19/50 | 70.2% | 23/50 |
| pushup | 전체 | tuning | 45 | 480 | 166 | 5 | 64.7% | 17/45 | 65.1% | 20/45 |
| row | side | heldout | 9 | 131 | 124 | 0 | 5.3% | 1/9 | 5.3% | 1/9 |
| row | side | tuning | 15 | 220 | 211 | 0 | 4.1% | 0/15 | 4.1% | 0/15 |
| row | diag | heldout | 11 | 176 | 164 | 0 | 6.8% | 0/11 | 6.8% | 0/11 |
| row | diag | tuning | 16 | 227 | 220 | 0 | 3.1% | 0/16 | 3.1% | 0/16 |
| row | front | heldout | 13 | 227 | 204 | 0 | 10.1% | 0/13 | 10.1% | 0/13 |
| row | front | tuning | 17 | 255 | 228 | 0 | 10.6% | 0/17 | 10.6% | 0/17 |
| row | 전체 | heldout | 33 | 534 | 492 | 0 | 7.9% | 1/33 | 7.9% | 1/33 |
| row | 전체 | tuning | 48 | 702 | 659 | 0 | 6.1% | 0/48 | 6.1% | 0/48 |
| squat | side | heldout | 16 | 208 | 107 | 2 | 48.1% | 0/16 | 48.6% | 2/16 |
| squat | side | tuning | 19 | 234 | 135 | 1 | 42.1% | 1/19 | 42.3% | 2/19 |
| squat | diag | heldout | 18 | 242 | 81 | 2 | 66.0% | 4/18 | 66.5% | 6/18 |
| squat | diag | tuning | 19 | 233 | 52 | 4 | 76.4% | 5/19 | 77.7% | 9/19 |
| squat | front | heldout | 20 | 287 | 84 | 1 | 70.5% | 2/20 | 70.7% | 3/20 |
| squat | front | tuning | 22 | 291 | 144 | 0 | 50.5% | 3/22 | 50.5% | 3/22 |
| squat | 전체 | heldout | 54 | 737 | 272 | 5 | 62.7% | 6/54 | 63.1% | 11/54 |
| squat | 전체 | tuning | 60 | 758 | 331 | 5 | 56.0% | 9/60 | 56.3% | 14/60 |

### 렙 정확도 — mendeley_mv7 (정상 자세만)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 9 | 110 | 29 | 0 | 73.6% | 4/9 | 73.6% | 4/9 |
| pushup | side | tuning | 7 | 86 | 43 | 3 | 48.3% | 1/7 | 48.9% | 2/7 |
| pushup | diag | heldout | 12 | 162 | 20 | 2 | 86.6% | 5/12 | 87.7% | 7/12 |
| pushup | diag | tuning | 9 | 108 | 9 | 1 | 90.8% | 6/9 | 91.7% | 7/9 |
| pushup | front | heldout | 6 | 84 | 65 | 0 | 22.6% | 0/6 | 22.6% | 0/6 |
| pushup | front | tuning | 7 | 92 | 54 | 0 | 41.3% | 1/7 | 41.3% | 1/7 |
| pushup | 전체 | heldout | 27 | 356 | 114 | 2 | 67.6% | 9/27 | 68.0% | 11/27 |
| pushup | 전체 | tuning | 23 | 286 | 106 | 4 | 62.1% | 8/23 | 62.5% | 10/23 |
| row | side | heldout | 4 | 46 | 46 | 0 | 0.0% | 1/4 | 0.0% | 1/4 |
| row | side | tuning | 5 | 68 | 67 | 0 | 1.5% | 0/5 | 1.5% | 0/5 |
| row | diag | heldout | 5 | 74 | 71 | 0 | 4.1% | 0/5 | 4.1% | 0/5 |
| row | diag | tuning | 8 | 111 | 107 | 0 | 3.6% | 0/8 | 3.6% | 0/8 |
| row | front | heldout | 4 | 69 | 67 | 0 | 2.9% | 0/4 | 2.9% | 0/4 |
| row | front | tuning | 6 | 83 | 74 | 0 | 10.8% | 0/6 | 10.8% | 0/6 |
| row | 전체 | heldout | 13 | 189 | 184 | 0 | 2.6% | 1/13 | 2.6% | 1/13 |
| row | 전체 | tuning | 19 | 262 | 248 | 0 | 5.3% | 0/19 | 5.3% | 0/19 |
| squat | side | heldout | 8 | 107 | 51 | 2 | 51.4% | 0/8 | 52.3% | 2/8 |
| squat | side | tuning | 9 | 102 | 55 | 1 | 45.6% | 1/9 | 46.1% | 2/9 |
| squat | diag | heldout | 9 | 113 | 48 | 0 | 57.5% | 2/9 | 57.5% | 2/9 |
| squat | diag | tuning | 10 | 122 | 25 | 1 | 78.9% | 3/10 | 79.5% | 4/10 |
| squat | front | heldout | 10 | 139 | 44 | 1 | 67.9% | 0/10 | 68.3% | 1/10 |
| squat | front | tuning | 12 | 151 | 70 | 0 | 53.6% | 2/12 | 53.6% | 2/12 |
| squat | 전체 | heldout | 27 | 359 | 143 | 3 | 59.7% | 2/27 | 60.2% | 5/27 |
| squat | 전체 | tuning | 31 | 375 | 150 | 2 | 59.7% | 6/31 | 60.0% | 8/31 |

### 렙 정확도 — youtube_cc (모든 자세)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 4 | 16 | 0 | 0 | 100.0% | 4/4 | 100.0% | 4/4 |
| pushup | side | tuning | 6 | 12 | 2 | 1 | 76.9% | 4/6 | 83.3% | 5/6 |
| pushup | diag | heldout | 15 | 34 | 2 | 3 | 86.5% | 11/15 | 88.9% | 12/15 |
| pushup | diag | tuning | 2 | 3 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| pushup | front | heldout | 2 | 22 | 2 | 0 | 90.9% | 1/2 | 90.9% | 1/2 |
| pushup | front | tuning | 4 | 12 | 4 | 0 | 66.7% | 2/4 | 66.7% | 2/4 |
| pushup | 전체 | heldout | 21 | 72 | 4 | 3 | 90.7% | 16/21 | 91.9% | 17/21 |
| pushup | 전체 | tuning | 12 | 27 | 6 | 1 | 75.0% | 8/12 | 77.8% | 9/12 |
| row | side | heldout | 4 | 9 | 0 | 0 | 100.0% | 4/4 | 100.0% | 4/4 |
| row | side | tuning | 10 | 23 | 4 | 0 | 82.6% | 8/10 | 82.6% | 8/10 |
| row | diag | heldout | 3 | 18 | 2 | 0 | 88.9% | 1/3 | 88.9% | 1/3 |
| row | diag | tuning | 4 | 22 | 18 | 0 | 18.2% | 1/4 | 18.2% | 1/4 |
| row | front | tuning | 3 | 14 | 3 | 0 | 78.6% | 1/3 | 78.6% | 1/3 |
| row | 전체 | heldout | 7 | 27 | 2 | 0 | 92.6% | 5/7 | 92.6% | 5/7 |
| row | 전체 | tuning | 17 | 59 | 25 | 0 | 57.6% | 10/17 | 57.6% | 10/17 |
| squat | side | heldout | 9 | 17 | 6 | 0 | 64.7% | 6/9 | 64.7% | 6/9 |
| squat | side | tuning | 5 | 8 | 3 | 0 | 62.5% | 3/5 | 62.5% | 3/5 |
| squat | diag | heldout | 6 | 11 | 3 | 1 | 66.7% | 3/6 | 72.7% | 4/6 |
| squat | diag | tuning | 3 | 10 | 1 | 0 | 90.0% | 2/3 | 90.0% | 2/3 |
| squat | front | heldout | 8 | 14 | 10 | 0 | 28.6% | 1/8 | 28.6% | 1/8 |
| squat | front | tuning | 3 | 6 | 5 | 0 | 16.7% | 1/3 | 16.7% | 1/3 |
| squat | back | heldout | 4 | 19 | 7 | 0 | 63.2% | 1/4 | 63.2% | 1/4 |
| squat | back | tuning | 1 | 3 | 0 | 0 | 100.0% | 1/1 | 100.0% | 1/1 |
| squat | 전체 | heldout | 27 | 61 | 26 | 1 | 56.5% | 11/27 | 57.4% | 12/27 |
| squat | 전체 | tuning | 12 | 27 | 9 | 0 | 66.7% | 7/12 | 66.7% | 7/12 |

### 렙 정확도 — youtube_cc (정상 자세만)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 2 | 9 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| pushup | side | tuning | 3 | 5 | 0 | 1 | 83.3% | 2/3 | 100.0% | 3/3 |
| pushup | diag | heldout | 8 | 21 | 0 | 3 | 87.5% | 5/8 | 91.3% | 6/8 |
| pushup | diag | tuning | 2 | 3 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| pushup | front | heldout | 2 | 22 | 2 | 0 | 90.9% | 1/2 | 90.9% | 1/2 |
| pushup | front | tuning | 3 | 8 | 4 | 0 | 50.0% | 1/3 | 50.0% | 1/3 |
| pushup | 전체 | heldout | 12 | 52 | 2 | 3 | 90.9% | 8/12 | 92.6% | 9/12 |
| pushup | 전체 | tuning | 8 | 16 | 4 | 1 | 70.6% | 5/8 | 75.0% | 6/8 |
| row | side | heldout | 3 | 6 | 0 | 0 | 100.0% | 3/3 | 100.0% | 3/3 |
| row | side | tuning | 9 | 21 | 4 | 0 | 81.0% | 7/9 | 81.0% | 7/9 |
| row | diag | heldout | 1 | 5 | 1 | 0 | 80.0% | 0/1 | 80.0% | 0/1 |
| row | diag | tuning | 2 | 8 | 6 | 0 | 25.0% | 1/2 | 25.0% | 1/2 |
| row | front | tuning | 3 | 14 | 3 | 0 | 78.6% | 1/3 | 78.6% | 1/3 |
| row | 전체 | heldout | 4 | 11 | 1 | 0 | 90.9% | 3/4 | 90.9% | 3/4 |
| row | 전체 | tuning | 14 | 43 | 13 | 0 | 69.8% | 9/14 | 69.8% | 9/14 |
| squat | side | heldout | 7 | 13 | 4 | 0 | 69.2% | 5/7 | 69.2% | 5/7 |
| squat | side | tuning | 2 | 2 | 0 | 0 | 100.0% | 2/2 | 100.0% | 2/2 |
| squat | diag | heldout | 5 | 10 | 2 | 1 | 72.7% | 3/5 | 80.0% | 4/5 |
| squat | diag | tuning | 3 | 10 | 1 | 0 | 90.0% | 2/3 | 90.0% | 2/3 |
| squat | front | heldout | 6 | 9 | 8 | 0 | 11.1% | 1/6 | 11.1% | 1/6 |
| squat | front | tuning | 2 | 4 | 3 | 0 | 25.0% | 1/2 | 25.0% | 1/2 |
| squat | back | heldout | 4 | 19 | 7 | 0 | 63.2% | 1/4 | 63.2% | 1/4 |
| squat | back | tuning | 1 | 3 | 0 | 0 | 100.0% | 1/1 | 100.0% | 1/1 |
| squat | 전체 | heldout | 22 | 51 | 21 | 1 | 57.7% | 10/22 | 58.8% | 11/22 |
| squat | 전체 | tuning | 8 | 19 | 4 | 0 | 78.9% | 6/8 | 78.9% | 6/8 |

### 렙 정확도 — 전체 (모든 자세)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 22 | 206 | 48 | 1 | 76.3% | 12/22 | 76.7% | 13/22 |
| pushup | side | tuning | 20 | 159 | 77 | 4 | 50.3% | 7/20 | 50.9% | 9/20 |
| pushup | diag | heldout | 35 | 268 | 33 | 6 | 85.8% | 21/35 | 87.0% | 25/35 |
| pushup | diag | tuning | 18 | 168 | 12 | 2 | 91.8% | 13/18 | 92.9% | 15/18 |
| pushup | front | heldout | 14 | 165 | 92 | 0 | 44.2% | 2/14 | 44.2% | 2/14 |
| pushup | front | tuning | 19 | 180 | 83 | 0 | 53.9% | 5/19 | 53.9% | 5/19 |
| pushup | 전체 | heldout | 71 | 639 | 173 | 7 | 72.1% | 35/71 | 72.7% | 40/71 |
| pushup | 전체 | tuning | 57 | 507 | 172 | 6 | 65.3% | 25/57 | 65.8% | 29/57 |
| row | side | heldout | 13 | 140 | 124 | 0 | 11.4% | 5/13 | 11.4% | 5/13 |
| row | side | tuning | 25 | 243 | 215 | 0 | 11.5% | 8/25 | 11.5% | 8/25 |
| row | diag | heldout | 14 | 194 | 166 | 0 | 14.4% | 1/14 | 14.4% | 1/14 |
| row | diag | tuning | 20 | 249 | 238 | 0 | 4.4% | 1/20 | 4.4% | 1/20 |
| row | front | heldout | 13 | 227 | 204 | 0 | 10.1% | 0/13 | 10.1% | 0/13 |
| row | front | tuning | 20 | 269 | 231 | 0 | 14.1% | 1/20 | 14.1% | 1/20 |
| row | 전체 | heldout | 40 | 561 | 494 | 0 | 11.9% | 6/40 | 11.9% | 6/40 |
| row | 전체 | tuning | 65 | 761 | 684 | 0 | 10.1% | 10/65 | 10.1% | 10/65 |
| squat | side | heldout | 25 | 225 | 113 | 2 | 49.3% | 6/25 | 49.8% | 8/25 |
| squat | side | tuning | 24 | 242 | 138 | 1 | 42.8% | 4/24 | 43.0% | 5/24 |
| squat | diag | heldout | 24 | 253 | 84 | 3 | 66.0% | 7/24 | 66.8% | 10/24 |
| squat | diag | tuning | 22 | 243 | 53 | 4 | 76.9% | 7/22 | 78.2% | 11/22 |
| squat | front | heldout | 28 | 301 | 94 | 1 | 68.5% | 3/28 | 68.8% | 4/28 |
| squat | front | tuning | 25 | 297 | 149 | 0 | 49.8% | 4/25 | 49.8% | 4/25 |
| squat | back | heldout | 4 | 19 | 7 | 0 | 63.2% | 1/4 | 63.2% | 1/4 |
| squat | back | tuning | 1 | 3 | 0 | 0 | 100.0% | 1/1 | 100.0% | 1/1 |
| squat | 전체 | heldout | 81 | 798 | 298 | 6 | 62.2% | 17/81 | 62.7% | 23/81 |
| squat | 전체 | tuning | 72 | 785 | 340 | 5 | 56.3% | 16/72 | 56.7% | 21/72 |

### 렙 정확도 — 전체 (정상 자세만)

| 운동 | 시점 | 분할 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 | 정확 일치 | 관대(부분렙 허용) 정확도 | 관대 정확 일치 |
|---|---|---|---|---|---|---|---|---|---|---|
| pushup | side | heldout | 11 | 119 | 29 | 0 | 75.6% | 6/11 | 75.6% | 6/11 |
| pushup | side | tuning | 10 | 91 | 43 | 4 | 50.5% | 3/10 | 51.6% | 5/10 |
| pushup | diag | heldout | 20 | 183 | 20 | 5 | 86.7% | 10/20 | 88.1% | 13/20 |
| pushup | diag | tuning | 11 | 111 | 9 | 1 | 91.1% | 8/11 | 91.9% | 9/11 |
| pushup | front | heldout | 8 | 106 | 67 | 0 | 36.8% | 1/8 | 36.8% | 1/8 |
| pushup | front | tuning | 10 | 100 | 58 | 0 | 42.0% | 2/10 | 42.0% | 2/10 |
| pushup | 전체 | heldout | 39 | 408 | 116 | 5 | 70.7% | 17/39 | 71.2% | 20/39 |
| pushup | 전체 | tuning | 31 | 302 | 110 | 5 | 62.5% | 13/31 | 63.2% | 16/31 |
| row | side | heldout | 7 | 52 | 46 | 0 | 11.5% | 4/7 | 11.5% | 4/7 |
| row | side | tuning | 14 | 89 | 71 | 0 | 20.2% | 7/14 | 20.2% | 7/14 |
| row | diag | heldout | 6 | 79 | 72 | 0 | 8.9% | 0/6 | 8.9% | 0/6 |
| row | diag | tuning | 10 | 119 | 113 | 0 | 5.0% | 1/10 | 5.0% | 1/10 |
| row | front | heldout | 4 | 69 | 67 | 0 | 2.9% | 0/4 | 2.9% | 0/4 |
| row | front | tuning | 9 | 97 | 77 | 0 | 20.6% | 1/9 | 20.6% | 1/9 |
| row | 전체 | heldout | 17 | 200 | 185 | 0 | 7.5% | 4/17 | 7.5% | 4/17 |
| row | 전체 | tuning | 33 | 305 | 261 | 0 | 14.4% | 9/33 | 14.4% | 9/33 |
| squat | side | heldout | 15 | 120 | 55 | 2 | 53.3% | 5/15 | 54.2% | 7/15 |
| squat | side | tuning | 11 | 104 | 55 | 1 | 46.7% | 3/11 | 47.1% | 4/11 |
| squat | diag | heldout | 14 | 123 | 50 | 1 | 58.9% | 5/14 | 59.3% | 6/14 |
| squat | diag | tuning | 13 | 132 | 26 | 1 | 79.7% | 5/13 | 80.3% | 6/13 |
| squat | front | heldout | 16 | 148 | 52 | 1 | 64.4% | 1/16 | 64.9% | 2/16 |
| squat | front | tuning | 14 | 155 | 73 | 0 | 52.9% | 3/14 | 52.9% | 3/14 |
| squat | back | heldout | 4 | 19 | 7 | 0 | 63.2% | 1/4 | 63.2% | 1/4 |
| squat | back | tuning | 1 | 3 | 0 | 0 | 100.0% | 1/1 | 100.0% | 1/1 |
| squat | 전체 | heldout | 49 | 410 | 164 | 4 | 59.4% | 12/49 | 60.0% | 16/49 |
| squat | 전체 | tuning | 39 | 394 | 154 | 2 | 60.6% | 12/39 | 60.9% | 14/39 |

### 렙 정확도 × 추적 품질 (unknown = 관절 신뢰도가 낮아 상태를 못 정한 프레임 비율)

| 운동 | 분할 | unknown 비율 | 세트 | 정답 렙 | 놓침 | 추가 | 렙 정확도 |
|---|---|---|---|---|---|---|---|
| pushup | heldout | < 10% | 71 | 639 | 173 | 7 | 72.1% |
| pushup | tuning | < 10% | 57 | 507 | 172 | 6 | 65.3% |
| row | heldout | < 10% | 39 | 546 | 480 | 0 | 12.1% |
| row | heldout | ≥ 10% | 1 | 15 | 14 | 0 | 6.7% |
| row | tuning | < 10% | 64 | 759 | 682 | 0 | 10.1% |
| row | tuning | ≥ 10% | 1 | 2 | 2 | 0 | 0.0% |
| squat | heldout | < 10% | 61 | 664 | 219 | 5 | 66.5% |
| squat | heldout | ≥ 10% | 20 | 134 | 79 | 1 | 40.7% |
| squat | tuning | < 10% | 47 | 506 | 147 | 4 | 70.4% |
| squat | tuning | ≥ 10% | 25 | 279 | 193 | 1 | 30.7% |

### 셋업 키 (세트당 발생, 괄호 = 센 렙 안에서)

| 운동 | 시점 | 분할 | 세트 | setup_full_body | tracking_lost | setup_side_view | 앱에서 켜진 키 알람 세트 |
|---|---|---|---|---|---|---|---|
| pushup | diag | heldout | 38 | 1 (0) | 31 (0) | 9 (9) | 10/38 |
| pushup | diag | tuning | 23 | 1 (0) | 16 (0) | 11 (11) | 7/23 |
| pushup | front | heldout | 22 | 20 (0) | 103 (1) | 19 (19) | 21/22 |
| pushup | front | tuning | 25 | 12 (0) | 84 (0) | 22 (22) | 22/25 |
| pushup | side | heldout | 24 | 0 (0) | 3 (1) | 0 (0) | 1/24 |
| pushup | side | tuning | 30 | 1 (0) | 7 (0) | 0 (0) | 4/30 |
| row | diag | heldout | 32 | 0 (0) | 0 (0) | 12 (0) | 12/32 |
| row | diag | tuning | 27 | 0 (0) | 0 (0) | 16 (1) | 16/27 |
| row | front | heldout | 22 | 0 (0) | 0 (0) | 21 (2) | 21/22 |
| row | front | tuning | 26 | 0 (0) | 0 (0) | 26 (1) | 26/26 |
| row | side | heldout | 27 | 0 (0) | 0 (0) | 0 (0) | 0/27 |
| row | side | tuning | 34 | 0 (0) | 0 (0) | 0 (0) | 0/34 |
| squat | back | heldout | 4 | 0 (0) | 0 (0) | 0 (0) | 0/4 |
| squat | back | tuning | 1 | 0 (0) | 0 (0) | 0 (0) | 0/1 |
| squat | diag | heldout | 30 | 0 (0) | 0 (0) | 0 (0) | 0/30 |
| squat | diag | tuning | 26 | 0 (0) | 0 (0) | 0 (0) | 0/26 |
| squat | front | heldout | 31 | 0 (0) | 0 (0) | 0 (0) | 0/31 |
| squat | front | tuning | 28 | 0 (0) | 0 (0) | 0 (0) | 0/28 |
| squat | side | heldout | 29 | 0 (0) | 0 (0) | 0 (0) | 0/29 |
| squat | side | tuning | 26 | 0 (0) | 0 (0) | 0 (0) | 0/26 |

### 자세 키 (앱에서 꺼짐 — pose-replay 판정 로그)

검출 = 그 키 라벨(두 패스 합의)이 붙은 잘못된 세트 중 키가 1렙 이상(또는 세트 이벤트) 나온 비율. 렙 비율 = 그 세트들의 센 렙 중 키가 나온 비율. 오경보 = 합의된 정상 세트의 센 렙 중 키가 나온 비율.

| 운동 | 키 | 시점 | 분할 | 잘못 세트 | 검출 | 렙 비율 | 정상 세트 | 정상 렙 | 오경보(렙) | 오경보(세트) |
|---|---|---|---|---|---|---|---|---|---|---|
| squat | squat_shallow | diag | heldout | 6 | 0/6 (0%) | 0/37 (0%) | 17 | 78 | 0/78 (0%) | 0/17 (0%) |
| squat | squat_shallow | diag | tuning | 4 | 1/4 (25%) | 1/36 (3%) | 16 | 140 | 0/140 (0%) | 0/16 (0%) |
| squat | squat_shallow | front | heldout | 7 | 0/7 (0%) | 0/78 (0%) | 17 | 101 | 0/101 (0%) | 0/17 (0%) |
| squat | squat_shallow | front | tuning | 4 | 0/4 (0%) | 0/35 (0%) | 17 | 97 | 0/97 (0%) | 0/17 (0%) |
| squat | squat_shallow | side | heldout | 6 | 0/6 (0%) | 0/31 (0%) | 16 | 67 | 0/67 (0%) | 0/16 (0%) |
| squat | squat_shallow | side | tuning | 5 | 0/5 (0%) | 0/26 (0%) | 13 | 64 | 0/64 (0%) | 0/13 (0%) |
| squat | squat_shallow | 전체 | heldout | 19 | 0/19 (0%) | 0/146 (0%) | 54 | 258 | 0/258 (0%) | 0/54 (0%) |
| squat | squat_shallow | 전체 | tuning | 13 | 1/13 (8%) | 1/97 (1%) | 47 | 304 | 0/304 (0%) | 0/47 (0%) |
| squat | squat_hips_first | diag | heldout | 1 | 0/1 (0%) | 0/8 (0%) | 17 | 78 | 2/78 (3%) | 1/17 (6%) |
| squat | squat_hips_first | side | heldout | 1 | 0/1 (0%) | 0/3 (0%) | 16 | 67 | 0/67 (0%) | 0/16 (0%) |
| squat | squat_hips_first | side | tuning | 3 | 0/3 (0%) | 0/3 (0%) | 13 | 64 | 0/64 (0%) | 0/13 (0%) |
| squat | squat_hips_first | 전체 | heldout | 2 | 0/2 (0%) | 0/11 (0%) | 54 | 258 | 2/258 (1%) | 1/54 (2%) |
| squat | squat_hips_first | 전체 | tuning | 3 | 0/3 (0%) | 0/3 (0%) | 47 | 304 | 0/304 (0%) | 0/47 (0%) |
| squat | squat_no_lockout | back | heldout | 0 | - | - | 4 | 12 | 1/12 (8%) | 1/4 (25%) |
| squat | squat_no_lockout | diag | heldout | 0 | - | - | 17 | 78 | 1/78 (1%) | 1/17 (6%) |
| squat | squat_no_lockout | diag | tuning | 0 | - | - | 16 | 140 | 2/140 (1%) | 1/16 (6%) |
| squat | squat_no_lockout | side | heldout | 0 | - | - | 16 | 67 | 6/67 (9%) | 5/16 (31%) |
| squat | squat_no_lockout | side | tuning | 0 | - | - | 13 | 64 | 10/64 (16%) | 7/13 (54%) |
| squat | squat_no_lockout | 전체 | heldout | 0 | - | - | 54 | 258 | 8/258 (3%) | 7/54 (13%) |
| squat | squat_no_lockout | 전체 | tuning | 0 | - | - | 47 | 304 | 12/304 (4%) | 8/47 (17%) |
| squat | squat_knee_valgus | back | heldout | 0 | - | - | 4 | 12 | 3/12 (25%) | 3/4 (75%) |
| squat | squat_knee_valgus | back | tuning | 0 | - | - | 1 | 3 | 3/3 (100%) | 1/1 (100%) |
| squat | squat_knee_valgus | diag | heldout | 0 | - | - | 17 | 78 | 37/78 (47%) | 7/17 (41%) |
| squat | squat_knee_valgus | diag | tuning | 0 | - | - | 16 | 140 | 86/140 (61%) | 14/16 (88%) |
| squat | squat_knee_valgus | front | heldout | 3 | 2/3 (67%) | 15/33 (45%) | 17 | 101 | 99/101 (98%) | 12/17 (71%) |
| squat | squat_knee_valgus | front | tuning | 3 | 2/3 (67%) | 4/8 (50%) | 17 | 97 | 93/97 (96%) | 14/17 (82%) |
| squat | squat_knee_valgus | 전체 | heldout | 3 | 2/3 (67%) | 15/33 (45%) | 54 | 258 | 139/258 (54%) | 22/54 (41%) |
| squat | squat_knee_valgus | 전체 | tuning | 3 | 2/3 (67%) | 4/8 (50%) | 47 | 304 | 182/304 (60%) | 29/47 (62%) |
| squat | squat_heel_rise | diag | tuning | 2 | 0/2 (0%) | 0/22 (0%) | 16 | 140 | 0/140 (0%) | 0/16 (0%) |
| squat | squat_heel_rise | side | tuning | 2 | 0/2 (0%) | 0/10 (0%) | 13 | 64 | 0/64 (0%) | 0/13 (0%) |
| squat | squat_heel_rise | 전체 | tuning | 4 | 0/4 (0%) | 0/32 (0%) | 47 | 304 | 0/304 (0%) | 0/47 (0%) |
| pushup | pushup_hip_sag | diag | heldout | 3 | 0/3 (0%) | 0/23 (0%) | 20 | 168 | 0/168 (0%) | 0/20 (0%) |
| pushup | pushup_hip_sag | diag | tuning | 1 | 0/1 (0%) | 0/4 (0%) | 14 | 143 | 6/143 (4%) | 1/14 (7%) |
| pushup | pushup_hip_sag | front | heldout | 2 | 0/2 (0%) | 0/17 (0%) | 13 | 82 | 0/82 (0%) | 0/13 (0%) |
| pushup | pushup_hip_sag | front | tuning | 0 | - | - | 15 | 69 | 1/69 (1%) | 1/15 (7%) |
| pushup | pushup_hip_sag | side | heldout | 4 | 1/4 (25%) | 2/21 (10%) | 12 | 106 | 0/106 (0%) | 0/12 (0%) |
| pushup | pushup_hip_sag | side | tuning | 3 | 1/3 (33%) | 2/12 (17%) | 17 | 105 | 0/105 (0%) | 0/17 (0%) |
| pushup | pushup_hip_sag | 전체 | heldout | 9 | 1/9 (11%) | 2/61 (3%) | 45 | 356 | 0/356 (0%) | 0/45 (0%) |
| pushup | pushup_hip_sag | 전체 | tuning | 4 | 1/4 (25%) | 2/16 (12%) | 46 | 317 | 7/317 (2%) | 2/46 (4%) |
| pushup | pushup_hip_pike | diag | heldout | 4 | 3/4 (75%) | 16/25 (64%) | 20 | 168 | 36/168 (21%) | 11/20 (55%) |
| pushup | pushup_hip_pike | diag | tuning | 3 | 2/3 (67%) | 10/30 (33%) | 14 | 143 | 15/143 (10%) | 6/14 (43%) |
| pushup | pushup_hip_pike | front | heldout | 2 | 0/2 (0%) | 0/11 (0%) | 13 | 82 | 0/82 (0%) | 0/13 (0%) |
| pushup | pushup_hip_pike | front | tuning | 0 | - | - | 15 | 69 | 1/69 (1%) | 1/15 (7%) |
| pushup | pushup_hip_pike | side | heldout | 3 | 2/3 (67%) | 16/20 (80%) | 12 | 106 | 0/106 (0%) | 0/12 (0%) |
| pushup | pushup_hip_pike | side | tuning | 3 | 1/3 (33%) | 1/13 (8%) | 17 | 105 | 2/105 (2%) | 2/17 (12%) |
| pushup | pushup_hip_pike | 전체 | heldout | 9 | 5/9 (56%) | 32/56 (57%) | 45 | 356 | 36/356 (10%) | 11/45 (24%) |
| pushup | pushup_hip_pike | 전체 | tuning | 6 | 3/6 (50%) | 11/43 (26%) | 46 | 317 | 18/317 (6%) | 9/46 (20%) |
| pushup | pushup_shallow | diag | heldout | 2 | 0/2 (0%) | 0/14 (0%) | 20 | 168 | 3/168 (2%) | 1/20 (5%) |
| pushup | pushup_shallow | diag | tuning | 2 | 1/2 (50%) | 4/26 (15%) | 14 | 143 | 1/143 (1%) | 1/14 (7%) |
| pushup | pushup_shallow | front | heldout | 2 | 0/2 (0%) | 0/6 (0%) | 13 | 82 | 0/82 (0%) | 0/13 (0%) |
| pushup | pushup_shallow | front | tuning | 2 | 0/2 (0%) | 0/13 (0%) | 15 | 69 | 0/69 (0%) | 0/15 (0%) |
| pushup | pushup_shallow | side | heldout | 2 | 0/2 (0%) | 0/6 (0%) | 12 | 106 | 7/106 (7%) | 3/12 (25%) |
| pushup | pushup_shallow | side | tuning | 3 | 0/3 (0%) | 0/4 (0%) | 17 | 105 | 7/105 (7%) | 3/17 (18%) |
| pushup | pushup_shallow | 전체 | heldout | 6 | 0/6 (0%) | 0/26 (0%) | 45 | 356 | 10/356 (3%) | 4/45 (9%) |
| pushup | pushup_shallow | 전체 | tuning | 7 | 1/7 (14%) | 4/43 (9%) | 46 | 317 | 8/317 (3%) | 4/46 (9%) |
| pushup | pushup_no_lockout | diag | heldout | 0 | - | - | 20 | 168 | 27/168 (16%) | 6/20 (30%) |
| pushup | pushup_no_lockout | diag | tuning | 0 | - | - | 14 | 143 | 21/143 (15%) | 8/14 (57%) |
| pushup | pushup_no_lockout | side | heldout | 0 | - | - | 12 | 106 | 22/106 (21%) | 4/12 (33%) |
| pushup | pushup_no_lockout | side | tuning | 1 | 0/1 (0%) | 0/14 (0%) | 17 | 105 | 12/105 (11%) | 3/17 (18%) |
| pushup | pushup_no_lockout | 전체 | heldout | 0 | - | - | 45 | 356 | 49/356 (14%) | 10/45 (22%) |
| pushup | pushup_no_lockout | 전체 | tuning | 1 | 0/1 (0%) | 0/14 (0%) | 46 | 317 | 33/317 (10%) | 11/46 (24%) |
| pushup | pushup_head_drop | diag | heldout | 3 | 0/3 (0%) | 0/23 (0%) | 20 | 168 | 9/168 (5%) | 4/20 (20%) |
| pushup | pushup_head_drop | diag | tuning | 1 | 0/1 (0%) | 0/9 (0%) | 14 | 143 | 2/143 (1%) | 2/14 (14%) |
| pushup | pushup_head_drop | front | heldout | 2 | 0/2 (0%) | 0/9 (0%) | 13 | 82 | 0/82 (0%) | 0/13 (0%) |
| pushup | pushup_head_drop | front | tuning | 1 | 0/1 (0%) | 0/4 (0%) | 15 | 69 | 1/69 (1%) | 1/15 (7%) |
| pushup | pushup_head_drop | side | heldout | 2 | 0/2 (0%) | 0/18 (0%) | 12 | 106 | 0/106 (0%) | 0/12 (0%) |
| pushup | pushup_head_drop | side | tuning | 1 | 0/1 (0%) | 0/13 (0%) | 17 | 105 | 1/105 (1%) | 1/17 (6%) |
| pushup | pushup_head_drop | 전체 | heldout | 7 | 0/7 (0%) | 0/50 (0%) | 45 | 356 | 9/356 (3%) | 4/45 (9%) |
| pushup | pushup_head_drop | 전체 | tuning | 3 | 0/3 (0%) | 0/26 (0%) | 46 | 317 | 4/317 (1%) | 4/46 (9%) |
| pushup | pushup_head_up | diag | heldout | 0 | - | - | 20 | 168 | 75/168 (45%) | 10/20 (50%) |
| pushup | pushup_head_up | diag | tuning | 0 | - | - | 14 | 143 | 35/143 (24%) | 9/14 (64%) |
| pushup | pushup_head_up | front | tuning | 0 | - | - | 15 | 69 | 1/69 (1%) | 1/15 (7%) |
| pushup | pushup_head_up | side | heldout | 1 | 0/1 (0%) | 0/2 (0%) | 12 | 106 | 16/106 (15%) | 5/12 (42%) |
| pushup | pushup_head_up | side | tuning | 0 | - | - | 17 | 105 | 18/105 (17%) | 6/17 (35%) |
| pushup | pushup_head_up | 전체 | heldout | 1 | 0/1 (0%) | 0/2 (0%) | 45 | 356 | 91/356 (26%) | 15/45 (33%) |
| pushup | pushup_head_up | 전체 | tuning | 0 | - | - | 46 | 317 | 54/317 (17%) | 16/46 (35%) |
| pushup | pushup_hand_position | diag | heldout | 0 | - | - | 20 | 168 | 3/168 (2%) | 3/20 (15%) |
| pushup | pushup_hand_position | diag | tuning | 0 | - | - | 14 | 143 | 1/143 (1%) | 1/14 (7%) |
| pushup | pushup_hand_position | side | tuning | 0 | - | - | 17 | 105 | 2/105 (2%) | 2/17 (12%) |
| pushup | pushup_hand_position | 전체 | heldout | 0 | - | - | 45 | 356 | 3/356 (1%) | 3/45 (7%) |
| pushup | pushup_hand_position | 전체 | tuning | 0 | - | - | 46 | 317 | 3/317 (1%) | 3/46 (7%) |
| pushup | pushup_depth_fade | side | heldout | 0 | - | - | 12 | 106 | 6/106 (6%) | 2/12 (17%) |
| pushup | pushup_depth_fade | side | tuning | 0 | - | - | 17 | 105 | 4/105 (4%) | 2/17 (12%) |
| pushup | pushup_depth_fade | 전체 | heldout | 0 | - | - | 45 | 356 | 6/356 (2%) | 2/45 (4%) |
| pushup | pushup_depth_fade | 전체 | tuning | 0 | - | - | 46 | 317 | 4/317 (1%) | 2/46 (4%) |
| row | row_torso_swing | diag | heldout | 5 | 4/5 (80%) | 8/10 (80%) | 18 | 37 | 5/37 (14%) | 5/18 (28%) |
| row | row_torso_swing | diag | tuning | 4 | 0/4 (0%) | 0/2 (0%) | 14 | 14 | 0/14 (0%) | 0/14 (0%) |
| row | row_torso_swing | front | heldout | 5 | 0/5 (0%) | 0/17 (0%) | 11 | 15 | 0/15 (0%) | 0/11 (0%) |
| row | row_torso_swing | front | tuning | 2 | 0/2 (0%) | 0/3 (0%) | 14 | 23 | 0/23 (0%) | 0/14 (0%) |
| row | row_torso_swing | side | heldout | 7 | 3/7 (43%) | 6/9 (67%) | 15 | 7 | 1/7 (14%) | 1/15 (7%) |
| row | row_torso_swing | side | tuning | 2 | 0/2 (0%) | - | 19 | 20 | 3/20 (15%) | 2/19 (11%) |
| row | row_torso_swing | 전체 | heldout | 17 | 7/17 (41%) | 14/36 (39%) | 44 | 59 | 6/59 (10%) | 6/44 (14%) |
| row | row_torso_swing | 전체 | tuning | 8 | 0/8 (0%) | 0/5 (0%) | 47 | 57 | 3/57 (5%) | 2/47 (4%) |
| row | row_standing_up | diag | heldout | 3 | 0/3 (0%) | 0/3 (0%) | 18 | 37 | 1/37 (3%) | 1/18 (6%) |
| row | row_standing_up | diag | tuning | 4 | 0/4 (0%) | - | 14 | 14 | 0/14 (0%) | 0/14 (0%) |
| row | row_standing_up | front | heldout | 3 | 0/3 (0%) | - | 11 | 15 | 0/15 (0%) | 0/11 (0%) |
| row | row_standing_up | front | tuning | 2 | 0/2 (0%) | 0/1 (0%) | 14 | 23 | 0/23 (0%) | 0/14 (0%) |
| row | row_standing_up | side | heldout | 4 | 0/4 (0%) | 0/5 (0%) | 15 | 7 | 0/7 (0%) | 0/15 (0%) |
| row | row_standing_up | side | tuning | 2 | 0/2 (0%) | 0/1 (0%) | 19 | 20 | 1/20 (5%) | 1/19 (5%) |
| row | row_standing_up | 전체 | heldout | 10 | 0/10 (0%) | 0/8 (0%) | 44 | 59 | 1/59 (2%) | 1/44 (2%) |
| row | row_standing_up | 전체 | tuning | 8 | 0/8 (0%) | 0/2 (0%) | 47 | 57 | 1/57 (2%) | 1/47 (2%) |
| row | row_short_pull | diag | heldout | 3 | 0/3 (0%) | 0/1 (0%) | 18 | 37 | 0/37 (0%) | 0/18 (0%) |
| row | row_short_pull | diag | tuning | 1 | 0/1 (0%) | 0/4 (0%) | 14 | 14 | 0/14 (0%) | 0/14 (0%) |
| row | row_short_pull | front | heldout | 1 | 0/1 (0%) | - | 11 | 15 | 0/15 (0%) | 0/11 (0%) |
| row | row_short_pull | front | tuning | 2 | 0/2 (0%) | 0/3 (0%) | 14 | 23 | 0/23 (0%) | 0/14 (0%) |
| row | row_short_pull | side | heldout | 2 | 0/2 (0%) | 0/1 (0%) | 15 | 7 | 0/7 (0%) | 0/15 (0%) |
| row | row_short_pull | side | tuning | 3 | 0/3 (0%) | 0/1 (0%) | 19 | 20 | 2/20 (10%) | 1/19 (5%) |
| row | row_short_pull | 전체 | heldout | 6 | 0/6 (0%) | 0/2 (0%) | 44 | 59 | 0/59 (0%) | 0/44 (0%) |
| row | row_short_pull | 전체 | tuning | 6 | 0/6 (0%) | 0/8 (0%) | 47 | 57 | 2/57 (4%) | 1/47 (2%) |
| row | row_head_up | diag | heldout | 0 | - | - | 18 | 37 | 1/37 (3%) | 1/18 (6%) |
| row | row_head_up | side | heldout | 0 | - | - | 15 | 7 | 1/7 (14%) | 1/15 (7%) |
| row | row_head_up | side | tuning | 0 | - | - | 19 | 20 | 2/20 (10%) | 2/19 (11%) |
| row | row_head_up | 전체 | heldout | 0 | - | - | 44 | 59 | 2/59 (3%) | 2/44 (5%) |
| row | row_head_up | 전체 | tuning | 0 | - | - | 47 | 57 | 2/57 (4%) | 2/47 (4%) |

### 세트별

| 파일 | 분할 | 시점 | 자세 | wrong_key | 정답 | 셈 | unknown | 경고(렙별) |
|---|---|---|---|---|---|---|---|---|
| subject_001_back_bad_diagonal | tuning | diag | wrong | row_standing_up | 16 | 0 | 0% |  |
| subject_001_back_bad_front | tuning | front | wrong | row_standing_up | 15 | 1 | 0% | - |
| subject_001_back_bad_side | tuning | side | wrong | row_standing_up | 17 | 1 | 2% | row_head_up |
| subject_001_back_good_diagonal | tuning | diag | normal |  | 16|17 | 0 | 7% |  |
| subject_001_back_good_front | tuning | front | normal |  | 16 | 7 | 0% | -,-,-,-,-,-,- |
| subject_001_back_good_side | tuning | side | normal |  | 17 | 0 | 1% |  |
| subject_001_push_up_bad_diagonal | tuning | diag | wrong | pushup_hip_pike | 12 | 9 | 0% | setup_side_view,-,-,-,-,-,-,-,- |
| subject_001_push_up_bad_front | tuning | front | uncertain |  | 13 | 10 | 0% | setup_side_view,-,-,-,-,-,-,-,-,- |
| subject_001_push_up_bad_side | tuning | side | uncertain |  | 18 | 1 | 0% | - |
| subject_001_push_up_good_diagonal | tuning | diag | normal |  | 30 | 22 | 2% | setup_side_view,-,-,pushup_head_up,-,-,pushup_hip_pike+pushup_head_up,-,-,-,-,-,-,-,-,-,pushup_no_lockout+pushup_head_drop,-,pushup_hip_pike,-,-,- |
| subject_001_push_up_good_front | tuning | front | normal |  | 27 | 6 | 0% | setup_side_view,-,-,-,-,- |
| subject_001_push_up_good_side | tuning | side | normal |  | 12 | 1 | 0% | - |
| subject_001_squat_bad_diagonal | tuning | diag | normal |  | 15 | 7 | 12% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_001_squat_bad_front | tuning | front | uncertain |  | 15 | 15 | 0% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_001_squat_bad_side | tuning | side | uncertain |  | 15 | 5 | 18% | -,-,-,squat_no_lockout,squat_shallow |
| subject_001_squat_good_diagonal | tuning | diag | normal |  | 15|16 | 6 | 28% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_001_squat_good_front | tuning | front | normal |  | 17 | 17 | 0% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_001_squat_good_side | tuning | side | normal |  | 18|14 | 3 | 29% | -,squat_no_lockout,- |
| subject_002_back_bad_diagonal | tuning | diag | wrong | row_short_pull | 19|20 | 4 | 0% | -,-,-,- |
| subject_002_back_bad_front | tuning | front | wrong | row_short_pull | 19 | 3 | 0% | -,-,- |
| subject_002_back_bad_side | tuning | side | wrong | row_short_pull | 20 | 1 | 0% | - |
| subject_002_back_good_diagonal | tuning | diag | normal |  | 13 | 2 | 0% | -,- |
| subject_002_back_good_front | tuning | front | normal |  | 13|14 | 1 | 1% | - |
| subject_002_back_good_side | tuning | side | normal |  | 13|14 | 1 | 3% | row_torso_swing+row_head_up |
| subject_002_push_up_bad_diagonal | tuning | diag | uncertain |  | 13 | 13 | 1% | setup_side_view,-,pushup_head_up,pushup_hip_sag,pushup_hip_sag+pushup_head_up,-,pushup_hip_sag,-,-,-,-,-,- |
| subject_002_push_up_bad_front | tuning | front | uncertain |  | 13 | 12 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,- |
| subject_002_push_up_bad_side | tuning | side | wrong | pushup_head_drop | 14|13 | 13 | 3% | -,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_002_push_up_good_diagonal | tuning | diag | normal |  | 12 | 12 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,- |
| subject_002_push_up_good_front | tuning | front | normal |  | 11 | 6 | 0% | setup_side_view,-,-,-,-,- |
| subject_002_push_up_good_side | tuning | side | normal |  | 12 | 12 | 0% | pushup_hand_position,pushup_head_up,pushup_head_up,-,-,-,-,-,-,-,-,- |
| subject_002_squat_bad_diagonal | tuning | diag | uncertain |  | 9 | 10 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,-,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_val |
| subject_002_squat_bad_front | tuning | front | uncertain |  | 9 | 8 | 4% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_002_squat_bad_side | tuning | side | wrong | squat_hips_first | 9 | 0 | 30% |  |
| subject_002_squat_good_diagonal | tuning | diag | normal |  | 13 | 14 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_002_squat_good_front | tuning | front | normal |  | 13 | 13 | 2% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_002_squat_good_side | tuning | side | normal |  | 13 | 3 | 24% | -,-,squat_no_lockout |
| subject_003_back_bad_diagonal | heldout | diag | wrong | row_short_pull;row_torso_swing | 29|27 | 1 | 11% | row_torso_swing+row_head_up |
| subject_003_back_bad_front | heldout | front | wrong | row_torso_swing | 26 | 5 | 0% | -,-,-,-,- |
| subject_003_back_good_diagonal | heldout | diag | uncertain |  | 21 | 1 | 0% | row_torso_swing+row_head_up |
| subject_003_back_good_front | heldout | front | uncertain |  | 18 | 1 | 0% | - |
| subject_003_back_good_side | heldout | side | normal |  | 19 | 0 | 0% |  |
| subject_003_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_sag | 15 | 5 | 1% | setup_side_view,-,-,-,- |
| subject_003_push_up_bad_front | heldout | front | wrong | pushup_hip_sag | 15 | 14 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_003_push_up_bad_side | heldout | side | wrong | pushup_hip_sag | 15|14 | 1 | 0% | - |
| subject_003_push_up_good_diagonal | heldout | diag | normal |  | 19 | 6 | 0% | setup_side_view,-,-,-,-,- |
| subject_003_push_up_good_front | heldout | front | normal |  | 19|18 | 15 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_003_push_up_good_side | heldout | side | normal |  | 18 | 9 | 0% | pushup_head_up,pushup_no_lockout,pushup_no_lockout+pushup_head_up,pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_no_lockout,pushup_shallow+pushup_head_u |
| subject_003_squat_bad_front | heldout | front | wrong | squat_shallow | 22 | 19 | 4% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_003_squat_bad_side | heldout | side | wrong | squat_shallow | 22|21 | 12 | 8% | -,-,-,-,-,squat_no_lockout,-,-,squat_no_lockout,squat_no_lockout,squat_no_lockout,- |
| subject_003_squat_good_front | heldout | front | normal |  | 20 | 16 | 0% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_003_squat_good_side | heldout | side | normal |  | 19 | 0 | 40% |  |
| subject_004_back_bad_diagonal | tuning | diag | wrong | row_standing_up | 14 | 0 | 0% |  |
| subject_004_back_bad_front | tuning | front | uncertain |  | 12 | 0 | 1% |  |
| subject_004_back_bad_side | tuning | side | uncertain |  | 13 | 0 | 0% |  |
| subject_004_back_good_diagonal | tuning | diag | normal |  | 14 | 1 | 0% | - |
| subject_004_back_good_front | tuning | front | normal |  | 13 | 0 | 0% |  |
| subject_004_back_good_side | tuning | side | uncertain |  | 13 | 2 | 0% | -,row_head_up |
| subject_004_push_up_bad_diagonal | tuning | diag | uncertain |  | 7 | 8 | 0% | pushup_hip_sag,-,pushup_hip_sag+pushup_head_up,pushup_hip_sag,pushup_hip_sag,pushup_hip_sag+pushup_no_lockout,pushup_hip_sag+pushup_head_up,pushup_hip_sag+pushu |
| subject_004_push_up_bad_front | tuning | front | uncertain |  | 7 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_004_push_up_bad_side | tuning | side | wrong | pushup_hip_sag | 7 | 5 | 0% | -,-,-,-,- |
| subject_004_push_up_good_diagonal | tuning | diag | normal |  | 6 | 7 | 0% | pushup_hip_sag,-,pushup_hip_sag,pushup_hip_sag+pushup_head_up,pushup_hip_sag+pushup_no_lockout+pushup_head_up,pushup_hip_sag+pushup_no_lockout,pushup_hip_sag+pu |
| subject_004_push_up_good_front | tuning | front | normal |  | 6|7 | 6 | 3% | setup_side_view,-,-,-,-,- |
| subject_004_push_up_good_side | tuning | side | normal |  | 6 | 7 | 0% | -,-,-,-,-,-,- |
| subject_004_squat_bad_diagonal | tuning | diag | wrong | squat_shallow | 12 | 12 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,-,-,squat_knee_v |
| subject_004_squat_bad_front | tuning | front | wrong | squat_shallow | 11 | 4 | 9% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_004_squat_bad_side | tuning | side | wrong | squat_shallow | 12 | 1 | 17% | - |
| subject_004_squat_good_diagonal | tuning | diag | normal |  | 12 | 12 | 0% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_004_squat_good_front | tuning | front | normal |  | 10 | 9 | 2% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_004_squat_good_side | tuning | side | normal |  | 10|11 | 11 | 2% | -,-,squat_no_lockout,squat_no_lockout,-,-,-,squat_no_lockout,-,squat_no_lockout,- |
| subject_005_back_bad_diagonal | tuning | diag | uncertain |  | 17 | 2 | 5% | -,- |
| subject_005_back_bad_front | tuning | front | uncertain |  | 16 | 5 | 0% | -,-,-,-,- |
| subject_005_back_bad_side | tuning | side | wrong | row_short_pull | 16|17 | 0 | 0% |  |
| subject_005_back_good_diagonal | tuning | diag | normal |  | 15 | 0 | 1% |  |
| subject_005_back_good_front | tuning | front | normal |  | 14 | 1 | 1% | - |
| subject_005_back_good_side | tuning | side | normal |  | 14 | 1 | 0% | - |
| subject_005_push_up_bad_diagonal | tuning | diag | wrong | pushup_shallow | 8|9 | 9 | 0% | -,-,pushup_hip_pike+pushup_head_up,pushup_hip_pike,pushup_hip_pike+pushup_shallow,pushup_hip_pike+pushup_shallow,pushup_hip_pike+pushup_shallow+pushup_depth_fad |
| subject_005_push_up_bad_front | tuning | front | wrong | pushup_shallow | 8|9 | 4 | 0% | setup_side_view,-,-,- |
| subject_005_push_up_bad_side | tuning | side | wrong | pushup_shallow | 8 | 3 | 0% | pushup_hip_pike,pushup_hip_pike,pushup_hip_sag+pushup_hip_pike+pushup_no_lockout |
| subject_005_push_up_good_diagonal | tuning | diag | normal |  | 7 | 7 | 0% | pushup_hip_pike,pushup_hip_pike+pushup_no_lockout+pushup_head_up,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_shallow,pushup_hip_pike+pushup_no_lockou |
| subject_005_push_up_good_front | tuning | front | normal |  | 7 | 5 | 0% | setup_side_view,-,-,-,- |
| subject_005_push_up_good_side | tuning | side | normal |  | 7|6 | 8 | 1% | -,-,-,pushup_shallow,-,pushup_shallow+pushup_depth_fade,-,pushup_hip_pike |
| subject_005_squat_bad_diagonal | tuning | diag | uncertain |  | 12 | 12 | 1% | -,-,-,-,-,-,-,-,-,-,-,squat_knee_valgus |
| subject_005_squat_bad_front | tuning | front | normal |  | 12|11 | 3 | 11% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_005_squat_good_diagonal | tuning | diag | normal |  | 13|12 | 13 | 0% | squat_knee_valgus,squat_knee_valgus,-,-,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,-,-,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_kn |
| subject_005_squat_good_front | tuning | front | normal |  | 13|10 | 12 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_006_back_bad_diagonal | heldout | diag | wrong | row_short_pull | 22 | 0 | 0% |  |
| subject_006_back_bad_front | heldout | front | uncertain |  | 22 | 2 | 2% | -,- |
| subject_006_back_bad_side | heldout | side | wrong | row_short_pull | 22 | 1 | 0% | row_head_up |
| subject_006_back_good_diagonal | heldout | diag | normal |  | 22 | 0 | 0% |  |
| subject_006_back_good_front | heldout | front | normal |  | 22 | 2 | 0% | -,- |
| subject_006_back_good_side | heldout | side | normal |  | 23|24 | 0 | 1% |  |
| subject_006_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_pike | 8 | 9 | 0% | setup_side_view,pushup_hip_pike+pushup_head_up,-,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_shallow,pushup_hip_pike+pushup_head_up,pushup_hip_pike,pu |
| subject_006_push_up_bad_front | heldout | front | wrong | pushup_hip_pike | 8 | 8 | 0% | setup_side_view,-,-,-,-,-,-,- |
| subject_006_push_up_bad_side | heldout | side | wrong | pushup_hip_pike | 8 | 8 | 1% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike |
| subject_006_push_up_good_diagonal | heldout | diag | normal |  | 16 | 16 | 0% | pushup_hand_position,-,-,-,-,-,-,-,pushup_head_drop,pushup_no_lockout+pushup_head_up,-,pushup_head_up,-,pushup_head_up,-,- |
| subject_006_push_up_good_front | heldout | front | normal |  | 17|16 | 5 | 0% | setup_side_view,-,-,-,- |
| subject_006_push_up_good_side | heldout | side | normal |  | 15|16 | 16 | 1% | -,-,-,-,-,-,-,-,-,-,-,-,pushup_no_lockout,-,-,pushup_no_lockout |
| subject_006_squat_bad_diagonal | heldout | diag | uncertain |  | 17 | 18 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_006_squat_bad_front | heldout | front | uncertain |  | 17 | 7 | 12% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_006_squat_good_diagonal | heldout | diag | normal |  | 18 | 17 | 0% | squat_knee_valgus,-,-,-,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,-,squat_knee_valgus,-,squat_knee_valgus,-,-,squat_knee_valgus,-, |
| subject_006_squat_good_front | heldout | front | normal |  | 17 | 14 | 4% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_007_back_bad_front | tuning | front | wrong | row_torso_swing | 18 | 3 | 0% | -,-,- |
| subject_007_back_bad_side | tuning | side | wrong | row_torso_swing | 18|17 | 0 | 1% |  |
| subject_007_back_good_diagonal | tuning | diag | normal |  | 17 | 1 | 0% | - |
| subject_007_back_good_front | tuning | front | uncertain |  | 16 | 0 | 3% |  |
| subject_007_back_good_side | tuning | side | uncertain |  | 17 | 1 | 0% | row_head_up |
| subject_007_push_up_good_diagonal | tuning | diag | normal |  | 19 | 19 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_007_push_up_good_front | tuning | front | normal |  | 18 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_007_push_up_good_side | tuning | side | normal |  | 19 | 5 | 4% | -,pushup_head_drop+pushup_head_up,pushup_head_up,pushup_head_up,pushup_shallow+pushup_no_lockout |
| subject_007_squat_bad_diagonal | tuning | diag | uncertain |  | 14 | 12 | 8% | -,-,-,-,squat_shallow,-,-,squat_knee_valgus,squat_knee_valgus,-,-,- |
| subject_007_squat_bad_front | tuning | front | wrong | squat_knee_valgus | 17 | 3 | 20% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_007_squat_bad_side | tuning | side | uncertain |  | 17 | 3 | 21% | -,-,- |
| subject_007_squat_good_front | tuning | front | normal |  | 15 | 5 | 6% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_007_squat_good_side | tuning | side | normal |  | 15 | 7 | 12% | -,squat_no_lockout,-,-,-,-,- |
| subject_008_back_bad_diagonal | tuning | diag | uncertain |  | 14 | 1 | 0% | - |
| subject_008_back_bad_front | tuning | front | uncertain |  | 14 | 6 | 0% | -,-,-,-,-,- |
| subject_008_back_bad_side | tuning | side | uncertain |  | 14 | 2 | 7% | row_torso_swing,row_torso_swing+row_head_up |
| subject_008_back_good_diagonal | tuning | diag | uncertain |  | 13 | 0 | 0% |  |
| subject_008_back_good_front | tuning | front | uncertain |  | 12 | 0 | 0% |  |
| subject_008_back_good_side | tuning | side | uncertain |  | 13 | 1 | 0% | row_head_up |
| subject_008_push_up_bad_diagonal | tuning | diag | wrong | pushup_head_drop;pushup_hip_pike | 9 | 9 | 0% | setup_side_view,-,-,pushup_hip_pike+pushup_head_up,-,-,-,-,- |
| subject_008_push_up_bad_front | tuning | front | uncertain |  | 8 | 1 | 2% | setup_side_view |
| subject_008_push_up_bad_side | tuning | side | wrong | pushup_hip_pike | 7 | 7 | 4% | -,-,-,-,pushup_head_up,-,pushup_head_up |
| subject_008_push_up_good_diagonal | tuning | diag | normal |  | 7 | 7 | 1% | setup_side_view,-,-,-,-,-,- |
| subject_008_push_up_good_front | tuning | front | normal |  | 8 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_008_push_up_good_side | tuning | side | normal |  | 8 | 6 | 2% | pushup_head_up,-,pushup_head_up,-,pushup_head_up,pushup_head_up |
| subject_008_squat_bad_diagonal | tuning | diag | wrong | squat_shallow | 21 | 2 | 0% | squat_knee_valgus,squat_knee_valgus |
| subject_008_squat_bad_front | tuning | front | wrong | squat_shallow | 21 | 17 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_008_squat_bad_side | tuning | side | wrong | squat_shallow | 22 | 20 | 0% | -,-,-,-,-,-,-,-,-,squat_lean_drift,squat_lean_drift,-,squat_no_lockout+squat_lean_drift,squat_lean_drift,squat_lean_drift,squat_lean_drift,squat_lean_drift,-,-, |
| subject_008_squat_good_diagonal | tuning | diag | normal |  | 14 | 12 | 2% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_008_squat_good_front | tuning | front | normal |  | 14 | 7 | 8% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_008_squat_good_side | tuning | side | normal |  | 14 | 13 | 1% | -,-,-,squat_no_lockout,-,-,-,-,-,-,-,-,- |
| subject_009_back_bad_diagonal | heldout | diag | wrong | row_torso_swing | 18 | 4 | 0% | row_torso_swing+row_head_up,row_torso_swing,row_torso_swing,row_torso_swing |
| subject_009_back_bad_front | heldout | front | wrong | row_torso_swing | 18 | 4 | 3% | -,-,-,- |
| subject_009_back_bad_side | heldout | side | wrong | row_torso_swing | 17 | 1 | 3% | row_torso_swing+row_head_up |
| subject_009_back_good_diagonal | heldout | diag | normal |  | 13 | 0 | 0% |  |
| subject_009_back_good_front | heldout | front | normal |  | 13|12 | 0 | 0% |  |
| subject_009_back_good_side | heldout | side | normal |  | 12 | 0 | 2% |  |
| subject_009_push_up_bad_diagonal | heldout | diag | wrong | pushup_shallow | 7 | 7 | 2% | -,pushup_head_up,-,pushup_head_up,pushup_head_up,-,pushup_head_up |
| subject_009_push_up_bad_front | heldout | front | wrong | pushup_shallow | 7 | 2 | 4% | setup_side_view,- |
| subject_009_push_up_bad_side | heldout | side | wrong | pushup_shallow | 7 | 2 | 6% | pushup_head_up,pushup_head_up |
| subject_009_push_up_good_diagonal | heldout | diag | normal |  | 7 | 7 | 0% | pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_head_up,pushup_head_drop+pushup_head_up,pushup_head_up,pushup_head_up,-,pushup_head_up |
| subject_009_push_up_good_front | heldout | front | normal |  | 7|8 | 1 | 0% | setup_side_view |
| subject_009_push_up_good_side | heldout | side | normal |  | 6 | 5 | 8% | -,-,pushup_head_up,pushup_head_up,pushup_head_up |
| subject_009_squat_bad_diagonal | heldout | diag | wrong | squat_shallow | 20|19 | 8 | 8% | squat_knee_valgus,-,-,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_009_squat_bad_front | heldout | front | wrong | squat_shallow | 19 | 15 | 0% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_009_squat_bad_side | heldout | side | wrong | squat_shallow | 17|18 | 7 | 4% | -,-,-,-,-,-,- |
| subject_009_squat_good_diagonal | heldout | diag | normal |  | 9 | 9 | 4% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_009_squat_good_front | heldout | front | normal |  | 10 | 2 | 10% | squat_knee_valgus,- |
| subject_009_squat_good_side | heldout | side | normal |  | 9 | 7 | 9% | -,-,-,-,-,-,squat_no_lockout |
| subject_010_back_bad_diagonal | heldout | diag | wrong | row_torso_swing | 17 | 3 | 0% | row_torso_swing+row_head_up,row_torso_swing+row_head_up,- |
| subject_010_back_bad_front | heldout | front | wrong | row_torso_swing | 16 | 7 | 0% | -,-,-,-,-,-,- |
| subject_010_back_bad_side | heldout | side | wrong | row_torso_swing | 17 | 4 | 0% | row_torso_swing+row_head_up,row_torso_swing+row_head_up,row_torso_swing+row_head_up,row_torso_swing+row_head_up |
| subject_010_back_good_diagonal | heldout | diag | normal |  | 18|19 | 0 | 0% |  |
| subject_010_back_good_front | heldout | front | normal |  | 19 | 0 | 0% |  |
| subject_010_back_good_side | heldout | side | normal |  | 17|20 | 0 | 0% |  |
| subject_010_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_sag | 8 | 8 | 0% | setup_side_view,-,pushup_head_up,-,-,-,-,- |
| subject_010_push_up_bad_side | heldout | side | wrong | pushup_hip_sag | 8 | 8 | 2% | pushup_head_up,-,pushup_head_up,pushup_head_up,-,-,-,- |
| subject_010_push_up_good_diagonal | heldout | diag | normal |  | 19 | 20 | 0% | pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,-,pushup_head_up,pushup_head_up,pushup_head_up,pushup_h |
| subject_010_push_up_good_front | heldout | front | normal |  | 19 | 9 | 0% | setup_side_view,-,-,-,-,-,-,-,- |
| subject_010_squat_bad_diagonal | heldout | diag | uncertain |  | 15 | 15 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_010_squat_bad_front | heldout | front | uncertain |  | 15 | 4 | 8% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_010_squat_bad_side | heldout | side | uncertain |  | 15 | 4 | 11% | -,-,-,- |
| subject_010_squat_good_diagonal | heldout | diag | normal |  | 16 | 1 | 3% | squat_knee_valgus |
| subject_010_squat_good_front | heldout | front | normal |  | 16 | 7 | 6% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_010_squat_good_side | heldout | side | normal |  | 16 | 2 | 7% | -,- |
| subject_011_back_bad_diagonal | tuning | diag | wrong | row_torso_swing | 15|14 | 0 | 0% |  |
| subject_011_back_bad_front | tuning | front | wrong | row_torso_swing | 14 | 0 | 0% |  |
| subject_011_back_bad_side | tuning | side | wrong | row_torso_swing | 14 | 0 | 9% |  |
| subject_011_back_good_diagonal | tuning | diag | normal |  | 15 | 0 | 4% |  |
| subject_011_back_good_front | tuning | front | normal |  | 14 | 0 | 0% |  |
| subject_011_back_good_side | tuning | side | normal |  | 16|15 | 0 | 14% |  |
| subject_011_push_up_bad_side | tuning | side | uncertain |  | 5 | 4 | 3% | -,pushup_head_up,pushup_head_up,pushup_no_lockout |
| subject_011_push_up_good_diagonal | tuning | diag | normal |  | 7|8 | 7 | 1% | -,pushup_head_up,pushup_hip_pike,pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_no_lockout,pushup_hip_pike+pushup_no_lockout+pushup_head_up |
| subject_011_push_up_good_front | tuning | front | normal |  | 7|8 | 8 | 0% | setup_side_view,-,-,-,-,-,-,- |
| subject_011_push_up_good_side | tuning | side | normal |  | 7|8 | 7 | 0% | -,-,-,-,-,-,- |
| subject_011_squat_bad_diagonal | tuning | diag | uncertain |  | 14 | 9 | 5% | -,-,-,-,-,-,-,-,- |
| subject_011_squat_bad_front | tuning | front | uncertain |  | 15 | 0 | 12% |  |
| subject_011_squat_good_diagonal | tuning | diag | normal |  | 13 | 9 | 2% | -,-,-,-,-,squat_no_lockout,squat_no_lockout,-,- |
| subject_011_squat_good_front | tuning | front | normal |  | 13 | 2 | 0% | squat_knee_valgus,squat_knee_valgus |
| subject_011_squat_good_side | tuning | side | normal |  | 13 | 3 | 10% | -,-,- |
| subject_012_back_bad_front | heldout | front | uncertain |  | 14 | 1 | 0% | - |
| subject_012_back_bad_side | heldout | side | wrong | row_torso_swing | 13 | 0 | 0% |  |
| subject_012_back_good_diagonal | heldout | diag | normal |  | 13 | 2 | 0% | -,- |
| subject_012_back_good_front | heldout | front | normal |  | 13 | 0 | 0% |  |
| subject_012_back_good_side | heldout | side | normal |  | 15|13 | 0 | 0% |  |
| subject_012_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_pike | 9 | 9 | 3% | setup_side_view,-,pushup_hip_pike+pushup_head_drop+pushup_head_up,-,pushup_head_up,pushup_shallow+pushup_head_up,pushup_head_up,pushup_hip_pike+pushup_head_drop |
| subject_012_push_up_bad_front | heldout | front | wrong | pushup_hip_pike | 8|9 | 3 | 2% | setup_side_view,-,- |
| subject_012_push_up_bad_side | heldout | side | wrong | pushup_hip_pike | 9 | 4 | 1% | pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_no_lockout,pushup_shallow+pushup_no_lockout |
| subject_012_push_up_good_diagonal | heldout | diag | normal |  | 18 | 16 | 1% | setup_side_view,pushup_head_up,-,pushup_head_up,-,-,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_shallow+pushup_head_up,pushup_hip_p |
| subject_012_push_up_good_front | heldout | front | normal |  | 19 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_012_push_up_good_side | heldout | side | normal |  | 18 | 18 | 0% | -,-,-,pushup_no_lockout,pushup_head_up,-,pushup_shallow+pushup_no_lockout,-,pushup_shallow+pushup_no_lockout+pushup_depth_fade,pushup_depth_fade,pushup_no_locko |
| subject_012_squat_bad_diagonal | heldout | diag | wrong | squat_shallow | 13|15 | 5 | 3% | squat_knee_valgus,-,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_012_squat_bad_front | heldout | front | wrong | squat_shallow | 11|15 | 5 | 16% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_012_squat_bad_side | heldout | side | wrong | squat_shallow | 14|15 | 3 | 2% | -,squat_no_lockout,- |
| subject_012_squat_good_diagonal | heldout | diag | normal |  | 12 | 9 | 7% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_012_squat_good_front | heldout | front | normal |  | 13 | 11 | 2% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_012_squat_good_side | heldout | side | normal |  | 12 | 7 | 4% | -,-,-,-,-,squat_no_lockout,- |
| subject_013_back_bad_diagonal | heldout | diag | wrong | row_torso_swing | 15|16 | 1 | 0% | - |
| subject_013_back_bad_front | heldout | front | wrong | row_torso_swing | 15 | 1 | 12% | - |
| subject_013_back_bad_side | heldout | side | wrong | row_torso_swing | 15|16 | 0 | 1% |  |
| subject_013_back_good_diagonal | heldout | diag | normal |  | 13 | 0 | 0% |  |
| subject_013_back_good_front | heldout | front | normal |  | 13|14 | 3 | 0% | -,-,- |
| subject_013_back_good_side | heldout | side | normal |  | 0 | 0 | 0% |  |
| subject_013_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_sag | 11 | 10 | 2% | pushup_hip_pike+pushup_head_drop,pushup_head_up,pushup_hip_pike+pushup_no_lockout+pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_hip_pike+pu |
| subject_013_push_up_bad_front | heldout | front | wrong | pushup_hip_sag | 11|10 | 3 | 0% | setup_side_view,-,- |
| subject_013_push_up_bad_side | heldout | side | wrong | pushup_hip_sag | 11 | 10 | 0% | -,pushup_head_up,-,-,pushup_shallow,pushup_depth_fade,pushup_depth_fade,pushup_head_up,-,pushup_depth_fade |
| subject_013_push_up_good_diagonal | heldout | diag | normal |  | 16 | 14 | 1% | pushup_head_up,pushup_head_up,pushup_no_lockout+pushup_head_drop,pushup_hip_pike+pushup_no_lockout+pushup_head_drop+pushup_head_up,pushup_no_lockout+pushup_head |
| subject_013_push_up_good_front | heldout | front | normal |  | 16|15 | 9 | 3% | setup_side_view,-,-,-,-,-,-,-,- |
| subject_013_squat_bad_diagonal | heldout | diag | wrong | squat_shallow | 13 | 3 | 5% | squat_knee_valgus,squat_knee_valgus,- |
| subject_013_squat_bad_front | heldout | front | wrong | squat_shallow | 14 | 13 | 0% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_013_squat_bad_side | heldout | side | wrong | squat_shallow | 14 | 2 | 9% | -,- |
| subject_013_squat_good_diagonal | heldout | diag | normal |  | 13 | 3 | 7% | -,-,- |
| subject_013_squat_good_front | heldout | front | normal |  | 12 | 5 | 5% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_013_squat_good_side | heldout | side | normal |  | 13 | 4 | 2% | -,-,-,- |
| subject_014_back_bad_diagonal | heldout | diag | wrong | row_torso_swing | 16 | 1 | 0% | row_torso_swing+row_head_up |
| subject_014_back_bad_front | heldout | front | wrong | row_torso_swing | 16 | 0 | 0% |  |
| subject_014_back_bad_side | heldout | side | wrong | row_torso_swing | 16 | 1 | 0% | row_torso_swing+row_head_up |
| subject_014_back_good_diagonal | heldout | diag | normal |  | 15|16 | 0 | 0% |  |
| subject_014_back_good_front | heldout | front | normal |  | 15 | 0 | 3% |  |
| subject_014_back_good_side | heldout | side | normal |  | 15 | 0 | 2% |  |
| subject_014_push_up_bad_diagonal | heldout | diag | wrong | pushup_head_drop | 9|11 | 9 | 0% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike |
| subject_014_push_up_bad_front | heldout | front | wrong | pushup_head_drop | 11|12 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_014_push_up_good_diagonal | heldout | diag | normal |  | 16 | 15 | 1% | pushup_hip_pike+pushup_head_up+pushup_hand_position,-,pushup_hip_pike,-,pushup_head_up,pushup_no_lockout,pushup_no_lockout,pushup_hip_pike+pushup_no_lockout+pus |
| subject_014_push_up_good_front | heldout | front | normal |  | 17 | 0 | 2% |  |
| subject_014_push_up_good_side | heldout | side | normal |  | 16 | 16 | 0% | -,-,-,pushup_shallow,pushup_head_up,-,pushup_no_lockout,pushup_no_lockout,-,-,-,pushup_no_lockout,pushup_no_lockout,-,pushup_no_lockout,pushup_head_up |
| subject_014_squat_bad_diagonal | heldout | diag | wrong | squat_shallow | 15 | 11 | 5% | -,-,-,-,-,-,-,-,squat_no_lockout,-,- |
| subject_014_squat_bad_front | heldout | front | wrong | squat_shallow | 15|14 | 11 | 3% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_014_squat_bad_side | heldout | side | wrong | squat_shallow | 14 | 7 | 7% | -,-,-,-,-,-,- |
| subject_015_back_bad_diagonal | tuning | diag | uncertain |  | 5 | 0 | 1% |  |
| subject_015_back_bad_front | tuning | front | wrong | row_short_pull | 6|5 | 0 | 0% |  |
| subject_015_back_bad_side | tuning | side | wrong | row_short_pull | 5|4 | 0 | 8% |  |
| subject_015_back_good_diagonal | tuning | diag | normal |  | 11 | 0 | 0% |  |
| subject_015_back_good_front | tuning | front | normal |  | 11|12 | 0 | 0% |  |
| subject_015_back_good_side | tuning | side | normal |  | 12 | 0 | 2% |  |
| subject_015_push_up_bad_diagonal | tuning | diag | wrong | pushup_hip_sag | 4 | 4 | 0% | pushup_head_up,pushup_hip_pike+pushup_no_lockout+pushup_head_up,pushup_head_up,pushup_hip_pike+pushup_head_up |
| subject_015_push_up_bad_front | tuning | front | uncertain |  | 4 | 1 | 0% | setup_side_view |
| subject_015_push_up_bad_side | tuning | side | wrong | pushup_hip_sag | 4 | 4 | 0% | pushup_head_up,-,-,pushup_no_lockout |
| subject_015_push_up_good_diagonal | tuning | diag | normal |  | 13 | 13 | 0% | pushup_hip_pike+pushup_hand_position,-,pushup_no_lockout,pushup_hip_pike+pushup_no_lockout,pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pus |
| subject_015_push_up_good_front | tuning | front | normal |  | 13|12 | 1 | 6% | setup_side_view |
| subject_015_push_up_good_side | tuning | side | normal |  | 12 | 14 | 0% | pushup_head_up+pushup_hand_position,-,pushup_no_lockout,-,pushup_hip_pike+pushup_head_up,-,pushup_head_up,pushup_shallow+pushup_no_lockout,pushup_no_lockout,-,p |
| subject_015_squat_bad_side | tuning | side | uncertain |  | 7 | 2 | 21% | -,- |
| subject_015_squat_good_diagonal | tuning | diag | normal |  | 11 | 8 | 6% | -,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,- |
| subject_015_squat_good_front | tuning | front | normal |  | 11 | 3 | 0% | squat_knee_valgus,squat_knee_valgus,- |
| subject_016_back_bad_diagonal | tuning | diag | uncertain |  | 18 | 0 | 0% |  |
| subject_016_back_bad_side | tuning | side | uncertain |  | 18 | 0 | 0% |  |
| subject_016_back_good_diagonal | tuning | diag | normal |  | 13 | 0 | 0% |  |
| subject_016_back_good_front | tuning | front | normal |  | 13|14 | 0 | 0% |  |
| subject_016_back_good_side | tuning | side | normal |  | 13 | 0 | 0% |  |
| subject_016_push_up_bad_diagonal | tuning | diag | wrong | pushup_shallow | 16|17 | 17 | 1% | -,-,-,-,-,-,-,-,-,-,pushup_no_lockout,-,pushup_head_up,-,-,-,- |
| subject_016_push_up_bad_front | tuning | front | wrong | pushup_shallow | 18 | 9 | 0% | setup_side_view,-,-,-,-,-,-,-,- |
| subject_016_push_up_bad_side | tuning | side | wrong | pushup_shallow | 18|17 | 0 | 0% |  |
| subject_016_push_up_good_diagonal | tuning | diag | normal |  | 12 | 11 | 4% | -,pushup_head_up,-,-,pushup_no_lockout+pushup_head_up,-,-,-,pushup_head_up,pushup_no_lockout,pushup_head_up |
| subject_016_push_up_good_front | tuning | front | normal |  | 19 | 5 | 0% | setup_side_view,-,-,-,- |
| subject_016_push_up_good_side | tuning | side | normal |  | 17 | 1 | 0% | - |
| subject_016_squat_bad_diagonal | tuning | diag | wrong | squat_heel_rise;squat_shallow | 12 | 13 | 1% | squat_knee_valgus,-,squat_knee_valgus,-,-,-,-,squat_knee_valgus,-,-,-,squat_knee_valgus,squat_knee_valgus |
| subject_016_squat_bad_front | tuning | front | wrong | squat_shallow | 13 | 9 | 10% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_016_squat_bad_side | tuning | side | wrong | squat_heel_rise;squat_shallow | 12 | 2 | 23% | -,- |
| subject_016_squat_good_diagonal | tuning | diag | normal |  | 11 | 6 | 11% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_016_squat_good_front | tuning | front | normal |  | 11 | 0 | 0% |  |
| subject_016_squat_good_side | tuning | side | normal |  | 11 | 6 | 12% | -,squat_no_lockout,-,-,-,- |
| subject_017_back_bad_diagonal | heldout | diag | wrong | row_standing_up | 20|18 | 0 | 1% |  |
| subject_017_back_bad_front | heldout | front | wrong | row_standing_up | 21|9 | 0 | 1% |  |
| subject_017_back_bad_side | heldout | side | wrong | row_standing_up | 21|16 | 1 | 0% | - |
| subject_017_back_good_diagonal | heldout | diag | normal |  | 18|17 | 1 | 0% | row_torso_swing |
| subject_017_back_good_front | heldout | front | normal |  | 20|17 | 1 | 3% | - |
| subject_017_back_good_side | heldout | side | normal |  | 20|16 | 1 | 0% | row_torso_swing+row_head_up |
| subject_017_push_up_bad_diagonal | heldout | diag | wrong | pushup_head_drop | 6|7 | 7 | 0% | pushup_head_up,pushup_head_up,-,-,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pushup_head_up |
| subject_017_push_up_bad_front | heldout | front | wrong | pushup_head_drop | 8 | 2 | 0% | setup_side_view,- |
| subject_017_push_up_bad_side | heldout | side | wrong | pushup_head_drop | 10 | 10 | 0% | -,-,-,-,-,pushup_no_lockout,-,-,pushup_no_lockout+pushup_head_up,- |
| subject_017_push_up_good_diagonal | heldout | diag | normal |  | 8 | 9 | 0% | pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,-,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pushup_head_up,pushup_no_lockout+pushup_head_up |
| subject_017_push_up_good_front | heldout | front | normal |  | 9 | 0 | 5% |  |
| subject_017_push_up_good_side | heldout | side | normal |  | 7 | 3 | 0% | -,-,- |
| subject_017_squat_bad_diagonal | heldout | diag | wrong | squat_shallow | 13|12 | 10 | 4% | -,-,-,-,-,squat_knee_valgus,-,-,-,squat_knee_valgus |
| subject_017_squat_bad_front | heldout | front | wrong | squat_shallow | 13 | 13 | 0% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_017_squat_bad_side | heldout | side | uncertain |  | 12 | 5 | 20% | -,-,-,-,- |
| subject_017_squat_good_diagonal | heldout | diag | normal |  | 11 | 11 | 2% | -,squat_knee_valgus,-,squat_knee_valgus,-,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,- |
| subject_017_squat_good_front | heldout | front | normal |  | 11 | 4 | 8% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_017_squat_good_side | heldout | side | uncertain |  | 13 | 11 | 4% | -,-,-,-,-,-,-,-,-,-,- |
| subject_018_back_bad_diagonal | heldout | diag | wrong | row_standing_up | 14|13 | 0 | 0% |  |
| subject_018_back_bad_front | heldout | front | wrong | row_standing_up | 13 | 0 | 0% |  |
| subject_018_back_bad_side | heldout | side | wrong | row_standing_up | 14|13 | 0 | 0% |  |
| subject_018_back_good_diagonal | heldout | diag | normal |  | 16|14 | 0 | 0% |  |
| subject_018_back_good_front | heldout | front | normal |  | 18|16 | 0 | 1% |  |
| subject_018_back_good_side | heldout | side | normal |  | 17|15 | 0 | 0% |  |
| subject_018_push_up_bad_diagonal | heldout | diag | wrong | pushup_hip_pike | 7 | 7 | 0% | pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_head_up,pushup_hip_pike,pushup_hip_pike+pushup_no_lockout+pushup_head_up,pu |
| subject_018_push_up_bad_front | heldout | front | uncertain |  | 8 | 4 | 8% | setup_side_view,-,-,- |
| subject_018_push_up_bad_side | heldout | side | wrong | pushup_hip_pike | 8 | 8 | 0% | pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_head_up,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike |
| subject_018_push_up_good_diagonal | heldout | diag | normal |  | 8 | 8 | 0% | pushup_hip_pike+pushup_head_up,pushup_head_up,pushup_head_up,pushup_hip_pike+pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_hip_pike+pushup_ |
| subject_018_push_up_good_front | heldout | front | normal |  | 10 | 0 | 0% |  |
| subject_018_push_up_good_side | heldout | side | normal |  | 8 | 8 | 0% | -,-,-,-,-,-,-,- |
| subject_018_squat_bad_diagonal | heldout | diag | uncertain |  | 11 | 3 | 0% | -,-,- |
| subject_018_squat_bad_front | heldout | front | wrong | squat_knee_valgus | 11 | 8 | 4% | -,squat_knee_valgus,-,-,-,-,-,- |
| subject_018_squat_bad_side | heldout | side | uncertain |  | 11 | 5 | 10% | -,-,-,squat_no_lockout,- |
| subject_018_squat_good_diagonal | heldout | diag | normal |  | 13 | 7 | 8% | -,-,-,squat_knee_valgus,squat_knee_valgus,-,- |
| subject_018_squat_good_front | heldout | front | normal |  | 15 | 13 | 3% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,-,squat_knee_valgus,squat_knee_valgus,squat_knee_val |
| subject_018_squat_good_side | heldout | side | normal |  | 14 | 12 | 3% | -,squat_no_lockout,-,-,-,-,-,-,-,-,-,- |
| subject_019_back_bad_front | tuning | front | uncertain |  | 13 | 0 | 0% |  |
| subject_019_back_good_diagonal | tuning | diag | normal |  | 12|11 | 1 | 0% | - |
| subject_019_back_good_front | tuning | front | normal |  | 13 | 1 | 0% | - |
| subject_019_back_good_side | tuning | side | normal |  | 12|11 | 0 | 0% |  |
| subject_019_push_up_bad_diagonal | tuning | diag | uncertain |  | 0 | 0 | 3% |  |
| subject_019_push_up_bad_front | tuning | front | uncertain |  | 0 | 0 | 0% |  |
| subject_019_push_up_good_diagonal | tuning | diag | normal |  | 2 | 2 | 2% | pushup_hip_pike,pushup_hip_pike+pushup_head_up |
| subject_019_push_up_good_front | tuning | front | normal |  | 2 | 2 | 0% | pushup_hip_sag+pushup_hip_pike+pushup_head_drop+pushup_head_up,- |
| subject_019_squat_bad_diagonal | tuning | diag | uncertain |  | 3 | 4 | 0% | -,-,-,squat_knee_valgus |
| subject_019_squat_bad_front | tuning | front | normal |  | 10 | 7 | 3% | squat_knee_valgus,-,squat_knee_valgus,-,-,squat_knee_valgus,squat_knee_valgus |
| subject_019_squat_bad_side | tuning | side | wrong | squat_hips_first | 7 | 3 | 8% | -,-,squat_no_lockout |
| subject_019_squat_good_diagonal | tuning | diag | normal |  | 10 | 10 | 2% | -,-,-,-,-,-,-,-,-,squat_knee_valgus |
| subject_019_squat_good_front | tuning | front | uncertain |  | 8 | 0 | 20% |  |
| subject_019_squat_good_side | tuning | side | normal |  | 10 | 10 | 2% | -,-,-,-,-,-,-,-,squat_no_lockout,- |
| subject_020_back_bad_side | heldout | side | wrong | row_torso_swing | 13|12 | 0 | 0% |  |
| subject_020_back_good_diagonal | heldout | diag | normal |  | 13|12 | 1 | 0% | row_torso_swing+row_head_up |
| subject_020_back_good_front | heldout | front | normal |  | 15|13 | 0 | 0% |  |
| subject_020_back_good_side | heldout | side | normal |  | 15|13 | 0 | 0% |  |
| subject_020_push_up_good_diagonal | heldout | diag | normal |  | 14 | 12 | 0% | -,-,-,pushup_head_up,pushup_head_up,-,-,-,-,-,-,- |
| subject_020_push_up_good_front | heldout | front | normal |  | 16|17 | 13 | 4% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,- |
| subject_020_push_up_good_side | heldout | side | normal |  | 16 | 4 | 1% | -,-,-,- |
| subject_020_squat_bad_diagonal | heldout | diag | uncertain |  | 15 | 15 | 1% | -,-,squat_knee_valgus,-,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee |
| subject_020_squat_bad_front | heldout | front | wrong | squat_knee_valgus | 14 | 14 | 0% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_020_squat_bad_side | heldout | side | uncertain |  | 11 | 8 | 5% | -,-,-,-,-,-,-,squat_shallow |
| subject_020_squat_good_diagonal | heldout | diag | normal |  | 13 | 2 | 0% | -,squat_knee_valgus |
| subject_020_squat_good_front | heldout | front | normal |  | 15|16 | 4 | 13% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_020_squat_good_side | heldout | side | normal |  | 15 | 16 | 2% | -,-,-,-,-,-,-,-,-,-,-,-,squat_no_lockout,-,-,- |
| subject_021_back_bad_side | tuning | side | uncertain |  | 13 | 0 | 0% |  |
| subject_021_back_good_diagonal | tuning | diag | normal |  | 14|11 | 0 | 0% |  |
| subject_021_back_good_front | tuning | front | normal |  | 15|12 | 0 | 0% |  |
| subject_021_back_good_side | tuning | side | normal |  | 14|13 | 0 | 0% |  |
| subject_021_push_up_bad_side | tuning | side | wrong | pushup_no_lockout | 14|15 | 14 | 2% | pushup_hand_position,-,-,-,-,-,-,-,-,-,-,-,-,pushup_head_up |
| subject_021_push_up_good_diagonal | tuning | diag | normal |  | 13|16 | 16 | 0% | pushup_head_up,pushup_head_up,-,-,-,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,pushup_head_up,push |
| subject_021_push_up_good_front | tuning | front | normal |  | 14|17 | 5 | 0% | setup_side_view,-,-,-,- |
| subject_021_push_up_good_side | tuning | side | normal |  | 15|16 | 13 | 0% | -,-,-,pushup_no_lockout,-,-,pushup_no_lockout,pushup_no_lockout,-,pushup_no_lockout,pushup_no_lockout,-,- |
| subject_021_squat_bad_diagonal | tuning | diag | wrong | squat_heel_rise;squat_shallow | 13|14 | 9 | 5% | -,-,-,-,-,-,-,squat_shallow,- |
| subject_021_squat_bad_front | tuning | front | wrong | squat_shallow | 15 | 5 | 10% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_021_squat_bad_side | tuning | side | wrong | squat_heel_rise | 15 | 8 | 8% | -,-,-,-,squat_shallow,-,-,squat_shallow+squat_no_lockout |
| subject_021_squat_good_diagonal | tuning | diag | normal |  | 11 | 11 | 1% | -,-,-,-,-,-,-,-,-,-,- |
| subject_021_squat_good_front | tuning | front | normal |  | 12 | 7 | 8% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_021_squat_good_side | tuning | side | normal |  | 0 | 1 | 28% | - |
| subject_022_back_bad_diagonal | tuning | diag | wrong | row_standing_up | 19 | 0 | 0% |  |
| subject_022_back_bad_front | tuning | front | wrong | row_standing_up | 23 | 0 | 0% |  |
| subject_022_back_bad_side | tuning | side | wrong | row_standing_up | 20|21 | 0 | 0% |  |
| subject_022_back_good_diagonal | tuning | diag | normal |  | 13 | 0 | 0% |  |
| subject_022_back_good_front | tuning | front | normal |  | 13 | 0 | 2% |  |
| subject_022_back_good_side | tuning | side | normal |  | 12 | 0 | 2% |  |
| subject_022_push_up_bad_diagonal | tuning | diag | wrong | pushup_hip_pike | 12 | 12 | 0% | setup_side_view,-,-,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_head_up,pushup_hip_pike,pushup_hip_pike+pushup_head_up, |
| subject_022_push_up_bad_front | tuning | front | uncertain |  | 13 | 11 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,- |
| subject_022_push_up_bad_side | tuning | side | wrong | pushup_hip_pike | 12 | 5 | 0% | -,-,pushup_head_up,pushup_head_up,- |
| subject_022_push_up_good_diagonal | tuning | diag | normal |  | 15|17 | 17 | 0% | setup_side_view,-,-,-,-,-,-,pushup_hip_pike+pushup_no_lockout+pushup_head_up,-,-,-,-,-,-,-,-,- |
| subject_022_push_up_good_front | tuning | front | normal |  | 16|18 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_022_push_up_good_side | tuning | side | normal |  | 16|18 | 16 | 0% | -,-,-,-,pushup_head_up,pushup_head_up,-,-,-,-,-,-,pushup_head_up,-,pushup_head_up,- |
| subject_022_squat_bad_front | tuning | front | wrong | squat_knee_valgus | 16 | 5 | 14% | -,-,-,squat_knee_valgus,- |
| subject_022_squat_bad_side | tuning | side | uncertain |  | 16 | 8 | 12% | -,-,-,-,-,-,-,- |
| subject_022_squat_good_diagonal | tuning | diag | normal |  | 13|14 | 14 | 0% | -,-,-,-,-,-,-,-,squat_knee_valgus,-,-,-,-,- |
| subject_022_squat_good_front | tuning | front | normal |  | 14 | 5 | 13% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_022_squat_good_side | tuning | side | normal |  | 14 | 3 | 3% | -,-,- |
| subject_023_back_good_side | heldout | diag | uncertain |  | 8 | 0 | 0% |  |
| subject_023_push_up_bad_diagonal | heldout | diag | wrong | pushup_head_drop | 7 | 7 | 0% | setup_side_view,-,-,-,-,-,- |
| subject_023_push_up_bad_side | heldout | side | wrong | pushup_head_drop | 7 | 8 | 0% | pushup_hip_pike+pushup_hand_position,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike,-,pushup_hip_pike+pushup_no_lockout,pushup_hip_pike+pushup_ |
| subject_023_push_up_good_diagonal | heldout | diag | normal |  | 11 | 11 | 1% | pushup_hip_pike+pushup_head_up,pushup_hip_pike,pushup_hip_pike,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_head_up,pushup_hip_pike+pushup_no_lockout+p |
| subject_023_push_up_good_side | heldout | side | normal |  | 11 | 8 | 0% | -,-,-,-,-,-,-,- |
| subject_023_squat_bad_diagonal | heldout | diag | uncertain |  | 16 | 17 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_023_squat_bad_front | heldout | front | wrong | squat_knee_valgus | 12 | 11 | 2% | -,-,-,-,-,-,-,-,-,-,- |
| subject_023_squat_good_diagonal | heldout | diag | uncertain |  | 14 | 8 | 6% | -,-,-,-,-,squat_hips_first,-,squat_knee_valgus |
| subject_023_squat_good_front | heldout | front | normal |  | 13 | 14 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_024_back_bad_diagonal | heldout | diag | wrong | row_short_pull | 12|17 | 0 | 1% |  |
| subject_024_back_bad_front | heldout | front | wrong | row_short_pull;row_standing_up | 13|17 | 0 | 0% |  |
| subject_024_back_bad_side | heldout | side | wrong | row_short_pull | 12|17 | 0 | 1% |  |
| subject_024_back_good_diagonal | heldout | diag | normal |  | 13 | 1 | 0% | - |
| subject_024_back_good_front | heldout | front | normal |  | 14|13 | 0 | 0% |  |
| subject_024_back_good_side | heldout | side | normal |  | 13|14 | 0 | 0% |  |
| subject_024_push_up_bad_diagonal | heldout | diag | wrong | pushup_shallow | 12|14 | 7 | 0% | setup_side_view,-,-,-,-,pushup_head_up,- |
| subject_024_push_up_bad_front | heldout | front | wrong | pushup_shallow | 13 | 4 | 0% | setup_side_view,-,-,- |
| subject_024_push_up_bad_side | heldout | side | wrong | pushup_shallow | 12 | 4 | 2% | -,pushup_head_up,-,- |
| subject_024_push_up_good_diagonal | heldout | diag | normal |  | 10 | 10 | 0% | setup_side_view,-,-,-,-,-,-,-,-,- |
| subject_024_push_up_good_front | heldout | front | normal |  | 10 | 3 | 0% | setup_side_view,-,- |
| subject_024_push_up_good_side | heldout | side | normal |  | 10 | 10 | 0% | -,-,-,pushup_head_up,-,-,-,pushup_head_up,-,- |
| subject_024_squat_bad_diagonal | heldout | diag | wrong | squat_hips_first | 13 | 8 | 13% | -,-,-,-,squat_knee_valgus,-,-,- |
| subject_024_squat_bad_front | heldout | front | uncertain |  | 11 | 4 | 23% | -,squat_knee_valgus,squat_knee_valgus,- |
| subject_024_squat_bad_side | heldout | side | wrong | squat_hips_first | 11 | 3 | 26% | -,-,squat_no_lockout |
| subject_024_squat_good_diagonal | heldout | diag | normal |  | 8 | 6 | 8% | -,-,-,-,-,- |
| subject_024_squat_good_front | heldout | front | normal |  | 12 | 10 | 3% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgu |
| subject_024_squat_good_side | heldout | side | normal |  | 9 | 10 | 2% | -,-,-,-,-,squat_no_lockout,-,-,squat_no_lockout,- |
| subject_026_squat_bad_diagonal | tuning | diag | uncertain |  | 14 | 13 | 4% | -,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_val |
| subject_026_squat_good_diagonal | tuning | diag | normal |  | 12 | 9 | 13% | -,squat_knee_valgus,-,-,squat_knee_valgus,-,-,squat_knee_valgus,- |
| subject_026_squat_good_front | tuning | front | normal |  | 11 | 6 | 11% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| subject_026_squat_good_side | tuning | side | normal |  | 12 | 2 | 29% | -,- |
| yt_0KtrNQre5rQ_1 | heldout | front | normal |  | 1 | 0 | 5% |  |
| yt_0KtrNQre5rQ_2 | heldout | front | normal |  | 2 | 0 | 26% |  |
| yt_0KtrNQre5rQ_3 | heldout | front | normal |  | 1 | 0 | 0% |  |
| yt_0KtrNQre5rQ_4 | heldout | side | normal |  | 2 | 2 | 3% | -,- |
| yt_0KtrNQre5rQ_5 | heldout | side | normal |  | 1 | 1 | 15% | - |
| yt_0_c1I7GatDw_1 | heldout | diag | normal |  | 3 | 3 | 34% | squat_hips_first,-,squat_hips_first |
| yt_0_c1I7GatDw_2 | heldout | front | normal |  | 1 | 1 | 2% | squat_knee_valgus |
| yt_29-XfdGXqjw_1 | heldout | diag | normal |  | 3 | 4 | 0% | -,-,-,- |
| yt_2YCCekX2Umo_1 | tuning | side | normal |  | 2 | 0 | 0% |  |
| yt_3nnzOvAAbP8_1 | tuning | front | normal |  | 3 | 0 | 0% |  |
| yt_3nnzOvAAbP8_2 | tuning | side | normal |  | 2 | 2 | 1% | -,- |
| yt_4ALA64JLQoE_2 | heldout | side | uncertain |  | 5 | 5 | 0% | -,-,pushup_no_lockout,-,pushup_no_lockout |
| yt_4FV_oEgDkX0_1 | tuning | diag | normal |  | 3 | 2 | 2% | squat_knee_valgus,squat_knee_valgus |
| yt_4FV_oEgDkX0_2 | tuning | diag | normal |  | 4 | 4 | 0% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| yt_4FV_oEgDkX0_3 | tuning | front | wrong | squat_knee_valgus | 2 | 0 | 22% |  |
| yt_4FV_oEgDkX0_4 | tuning | front | normal |  | 4|5 | 0 | 25% |  |
| yt_98J9aiV69p8_1 | heldout | side | wrong | pushup_head_up;pushup_hip_sag | 2 | 2 | 3% | pushup_hip_sag,pushup_hip_sag |
| yt_98J9aiV69p8_2 | heldout | side | normal |  | 5 | 5 | 0% | -,-,-,-,- |
| yt_9Qc45eJQQTE_1 | heldout | diag | uncertain |  | 5 | 4 | 0% | row_head_up,-,row_head_up,row_head_up |
| yt_A1XZcaFRrBo_1 | heldout | side | normal |  | 0 | 0 | 7% |  |
| yt_A1XZcaFRrBo_2 | heldout | side | normal |  | 0|2 | 0 | 0% |  |
| yt_A1XZcaFRrBo_3 | heldout | side | wrong | row_standing_up | 3|4 | 1 | 2% | - |
| yt_APNV5mki_V8_1 | heldout | diag | normal |  | 10|12 | 9 | 0% | -,-,-,-,-,-,-,-,- |
| yt_APNV5mki_V8_2 | heldout | diag | normal |  | 5 | 4 | 1% | -,-,-,- |
| yt_DCnDjdobuLk_1 | tuning | side | normal |  | 5 | 5 | 1% | -,-,-,row_short_pull,row_short_pull |
| yt_DCnDjdobuLk_2 | tuning | side | normal |  | 1|0 | 1 | 0% | - |
| yt_DCnDjdobuLk_3 | tuning | side | normal |  | 0 | 0 | 0% |  |
| yt_DCnDjdobuLk_4 | tuning | side | normal |  | 0 | 0 | 0% |  |
| yt_DCnDjdobuLk_5 | tuning | side | uncertain |  | 2 | 2 | 0% | row_torso_swing,row_head_up |
| yt_DCnDjdobuLk_6 | tuning | side | normal |  | 3 | 3 | 4% | -,-,- |
| yt_DVGi7h0lL3A_1 | tuning | side | normal |  | 2 | 2 | 0% | -,- |
| yt_DVGi7h0lL3A_2 | tuning | side | normal |  | 1 | 2 | 0% | -,- |
| yt_DVGi7h0lL3A_3 | tuning | side | wrong | pushup_shallow | 3 | 1 | 1% | pushup_hip_pike |
| yt_DVGi7h0lL3A_4 | tuning | side | wrong | pushup_hip_pike | 1 | 1 | 2% | pushup_hip_pike |
| yt_DVGi7h0lL3A_5 | tuning | side | wrong | pushup_hip_sag | 3 | 3 | 0% | -,pushup_hip_sag,pushup_hip_sag |
| yt_Ds9yTAPwv00_1 | heldout | side | uncertain |  | 2 | 2 | 15% | -,squat_no_lockout |
| yt_Ds9yTAPwv00_2 | heldout | side | normal |  | 2 | 1 | 24% | - |
| yt_Ds9yTAPwv00_3 | heldout | front | normal |  | 2 | 0 | 8% |  |
| yt_Ds9yTAPwv00_4 | heldout | side | normal |  | 1 | 1 | 0% | - |
| yt_Ds9yTAPwv00_5 | heldout | front | uncertain |  | 2 | 1 | 5% | squat_knee_valgus |
| yt_Ds9yTAPwv00_6 | heldout | front | normal |  | 2 | 0 | 7% |  |
| yt_EyAC8jSJIYQ_1 | tuning | diag | wrong | row_torso_swing | 11 | 0 | 1% |  |
| yt_F7umlBUzKVU_1 | tuning | diag | normal |  | 4|8 | 7 | 1% | -,-,-,-,-,-,- |
| yt_F7umlBUzKVU_2 | tuning | front | normal |  | 6 | 4 | 0% | -,-,-,- |
| yt_HG542yssLsc_1 | tuning | side | wrong | squat_shallow | 3 | 1 | 22% | - |
| yt_HG542yssLsc_2 | tuning | side | normal |  | 1 | 1 | 0% | - |
| yt_HG542yssLsc_3 | tuning | side | wrong | squat_shallow | 2 | 2 | 2% | -,squat_no_lockout |
| yt_HG542yssLsc_4 | tuning | side | normal |  | 1 | 1 | 6% | - |
| yt_JklNoB4eyhw_1 | heldout | diag | normal |  | 3 | 3 | 1% | -,-,- |
| yt_JklNoB4eyhw_2 | heldout | diag | normal |  | 1 | 2 | 0% | pushup_hip_pike,pushup_hip_pike |
| yt_JnwWdvwGmAU_3 | heldout | diag | normal |  | 6 | 6 | 0% | pushup_hand_position,-,-,-,-,- |
| yt_Ka-yi9zHp2Q_1 | tuning | front | normal |  | 2|0 | 2 | 1% | -,- |
| yt_Ka-yi9zHp2Q_2 | tuning | side | normal |  | 2 | 2 | 2% | -,row_head_up |
| yt_LCBEioFGYq8_1 | heldout | side | normal |  | 3 | 3 | 0% | -,-,- |
| yt_M2fI9s51Q0E_1 | heldout | back | normal |  | 5 | 2 | 30% | -,squat_knee_valgus |
| yt_M2fI9s51Q0E_2 | heldout | back | normal |  | 2 | 2 | 13% | squat_knee_valgus,- |
| yt_M2fI9s51Q0E_3 | heldout | back | normal |  | 6 | 3 | 3% | -,squat_no_lockout,- |
| yt_R1q-_wqz4sA_1 | heldout | side | normal |  | 4 | 4 | 0% | -,-,-,- |
| yt_R1q-_wqz4sA_2 | heldout | front | normal |  | 4 | 4 | 0% | setup_side_view,-,-,- |
| yt_SwIUivmPrQ8_1 | tuning | front | normal |  | 4 | 4 | 1% | -,-,-,- |
| yt_SwIUivmPrQ8_2 | tuning | front | normal |  | 4 | 3 | 1% | -,-,- |
| yt_T5J-Ao3DXE0_1 | heldout | diag | normal |  | 2|1 | 1 | 16% | - |
| yt_T5J-Ao3DXE0_2 | heldout | diag | normal |  | 0 | 0 | 4% |  |
| yt_T5J-Ao3DXE0_3 | heldout | diag | wrong | squat_shallow | 1 | 0 | 7% |  |
| yt_TBNtGrr-owU_1 | heldout | diag | normal |  | 1 | 2 | 0% | pushup_hip_pike,- |
| yt_TBNtGrr-owU_2 | heldout | diag | normal |  | 2 | 2 | 1% | pushup_hip_pike,pushup_hip_pike |
| yt_U267qtP0NSo_1 | heldout | diag | normal |  | 7|8 | 7 | 1% | row_torso_swing,-,-,-,-,-,- |
| yt_V9y7P9vbcME_1 | heldout | diag | normal |  | 6|11 | 4 | 0% | -,-,-,row_torso_swing+row_standing_up |
| yt_WysdJhfVL3E_1 | tuning | side | wrong | squat_hips_first | 1 | 0 | 83% |  |
| yt_WysdJhfVL3E_2 | tuning | back | normal |  | 3 | 3 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| yt_WysdJhfVL3E_3 | tuning | diag | normal |  | 3 | 3 | 1% | squat_knee_valgus,squat_knee_valgus,squat_knee_valgus |
| yt_WysdJhfVL3E_4 | tuning | front | normal |  | 3 | 0 | 3% |  |
| yt_WysdJhfVL3E_5 | tuning | front | normal |  | 1 | 1 | 4% | squat_knee_valgus |
| yt_XOg81X0Tckw_1 | tuning | side | normal |  | 2|1 | 2 | 30% | -,- |
| yt_XOg81X0Tckw_2 | tuning | side | normal |  | 4|5 | 4 | 3% | -,pushup_head_up,-,- |
| yt_YvXXlKVmMaw_1 | heldout | diag | normal |  | 0 | 1 | 11% | - |
| yt_YvXXlKVmMaw_2 | heldout | side | normal |  | 1 | 1 | 9% | - |
| yt_d4l1BF0cY4U_1 | tuning | diag | normal |  | 1 | 1 | 1% | setup_side_view |
| yt_d4l1BF0cY4U_2 | tuning | diag | normal |  | 2 | 2 | 0% | setup_side_view,- |
| yt_dyLMJUOP3R4_1 | tuning | diag | normal |  | 2 | 2 | 0% | -,- |
| yt_fW6-ykp1cjk_1 | tuning | side | normal |  | 3 | 3 | 1% | -,-,- |
| yt_fY0jKtdVvzA_1 | tuning | side | normal |  | 2 | 0 | 11% |  |
| yt_fv2PvU6Xzwk_1 | heldout | diag | uncertain |  | 8 | 8 | 0% | -,-,-,-,-,-,-,- |
| yt_gMJe6yeacsk_1 | heldout | side | wrong | row_standing_up;row_torso_swing | 3 | 3 | 2% | -,-,- |
| yt_gMJe6yeacsk_2 | heldout | side | normal |  | 3 | 3 | 0% | -,-,- |
| yt_gm4ln6PO4rc_1 | heldout | diag | normal |  | 5 | 3 | 14% | -,-,squat_no_lockout |
| yt_gm4ln6PO4rc_2 | heldout | side | wrong | squat_shallow | 2 | 0 | 7% |  |
| yt_gm4ln6PO4rc_3 | heldout | front | wrong | squat_shallow | 3 | 2 | 0% | squat_knee_valgus,squat_knee_valgus |
| yt_gm4ln6PO4rc_4 | heldout | diag | normal |  | 5|4 | 2 | 21% | -,- |
| yt_h-TqBZlxszM_1 | tuning | diag | normal |  | 6 | 0 | 0% |  |
| yt_h5jTRrFQzJs_1 | heldout | diag | uncertain |  | 6 | 4 | 0% | pushup_hip_pike,pushup_hip_pike+pushup_no_lockout,pushup_hip_pike+pushup_no_lockout,pushup_hip_pike+pushup_no_lockout |
| yt_h5jTRrFQzJs_2 | heldout | diag | uncertain |  | 3 | 3 | 0% | pushup_hip_pike+pushup_head_up,pushup_no_lockout,- |
| yt_hO27xMs4wns_1 | tuning | diag | wrong | row_torso_swing | 3 | 2 | 0% | -,row_head_up |
| yt_hjNQPke32ww_1 | tuning | front | wrong | pushup_head_drop | 4 | 4 | 1% | setup_side_view,-,-,- |
| yt_hjNQPke32ww_2 | tuning | front | normal |  | 4 | 3 | 0% | setup_side_view,-,- |
| yt_jxUoaZJxkVM_1 | heldout | front | normal |  | 9|8 | 9 | 0% | -,-,-,-,-,-,-,-,- |
| yt_ktKsQYqJthw_1 | heldout | diag | normal |  | 4|3 | 0 | 0% |  |
| yt_ktKsQYqJthw_2 | heldout | diag | normal |  | 4|3 | 3 | 1% | -,-,- |
| yt_m12ycyzTr5c_1 | heldout | side | normal |  | 4 | 1 | 16% | - |
| yt_m12ycyzTr5c_2 | heldout | side | normal |  | 1|2 | 0 | 8% |  |
| yt_m12ycyzTr5c_3 | heldout | side | normal |  | 2 | 2 | 12% | -,- |
| yt_m16KdkLHyrA_1 | heldout | diag | normal |  | 5|6 | 1 | 8% | - |
| yt_m16KdkLHyrA_2 | heldout | diag | normal |  | 2 | 2 | 18% | -,- |
| yt_m16KdkLHyrA_3 | heldout | back | normal |  | 6 | 5 | 21% | -,-,-,-,squat_knee_valgus |
| yt_mIG9SsVEvJg_1 | heldout | front | normal |  | 18 | 16 | 0% | setup_side_view,-,-,-,-,-,-,-,-,-,-,-,-,-,-,- |
| yt_p3a6iG_9kC0_1 | heldout | diag | uncertain |  | 0 | 0 | 0% |  |
| yt_p3a6iG_9kC0_2 | heldout | diag | wrong | pushup_hip_pike | 0 | 0 | 0% |  |
| yt_p3a6iG_9kC0_3 | heldout | diag | normal |  | 2 | 2 | 0% | pushup_hip_pike,- |
| yt_p3a6iG_9kC0_4 | heldout | diag | uncertain |  | 2 | 2 | 0% | pushup_hip_pike,- |
| yt_p3a6iG_9kC0_5 | heldout | diag | uncertain |  | 1 | 1 | 0% | pushup_head_up |
| yt_pVJ_2lspIzA_1 | heldout | diag | normal |  | 3|2 | 3 | 1% | -,-,- |
| yt_qZYOjVzRHhc_1 | tuning | side | normal |  | 4|3 | 3 | 0% | -,-,- |
| yt_qZYOjVzRHhc_2 | tuning | front | normal |  | 1 | 1 | 0% | setup_side_view |
| yt_s1EeH4nExEw_1 | heldout | diag | normal |  | 2|4 | 2 | 0% | -,row_torso_swing |
| yt_sO4dzMOmp5U_1 | tuning | side | normal |  | 4 | 4 | 0% | row_torso_swing,row_torso_swing,-,row_standing_up |
| yt_uPU2rgRtzLE_1 | heldout | diag | normal |  | 3 | 3 | 0% | -,pushup_hip_pike,pushup_hip_pike |
| yt_uPU2rgRtzLE_2 | heldout | diag | uncertain |  | 1 | 1 | 1% | pushup_hip_pike |
| yt_uVlVESedmU0_1 | tuning | diag | wrong | row_standing_up;row_torso_swing | 2|1 | 0 | 0% |  |
| yt_zOztB9_kpXA_1 | heldout | diag | wrong | row_standing_up | 2|3 | 3 | 0% | -,-,- |
