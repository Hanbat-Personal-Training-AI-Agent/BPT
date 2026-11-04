# Accepted-observation phase replay — 2026-11-04

The frozen phase-input/ordering candidate changes row phase state and a small number of decisions on these reused streams. It does not demonstrate an accuracy improvement: primary row full MPJPE increases by 0.000135 mm (clean), 0.003120 mm (keypoint stress), and 0.000480 mm (RGB stress) versus legacy H. Recovery is exactly unchanged. The result supports a narrow execution/provenance comparison, not adoption, biomechanical validity or contact accuracy.

Protocol: [frozen replay scope](motion_phase_replay_protocol_20261104.md). Complete [aggregate](motion_phase_replay_results_20261104.json), [execution closure](motion_phase_replay_execution_20261104.json), and [preflight](motion_phase_replay_preflight_20261104.json). The independent native policy/source is frozen at `83f1a93c9d4c36405730776486b65dd9c33bf8d3`, with parity receipt `bab621d962afb67ef62a5c8c5bda9ab8eb5a0fa5daa467de4645f7e20ec30d3a`. The runner is `4861796`.

## Scope and closure

Completed 72/72 streams, 42,052 frames and 288 four-policy prediction files plus 288 diagnostic sidecars. A/raw, legacy G/H and accepted-phase H share identical saved raw arrays. The historical A/G/H non-timing arrays reproduce exactly, including dtype/schema/NaN positions and the explicitly checked all-false raw-A expiry extension. Candidate H remains array-exact to legacy H on every pushup and squat stream. All four predictions are saved before parsing that stream’s score reference; no GT phase, side, geometry or future samples enter an estimator.

Profiles use observations 21–80, activate at 81, and the primary window starts at 90. Whole-sequence and primary-window denominators, all damage partitions, wrist/ankle scopes, and every scenario/exercise remain in the aggregate. Coverage here means the fraction not marked invalid by the existing output mask; it is not validated-form coverage. Error includes all declared joint-frames, including invalid outputs.

Preflight rehashed all 832 original input/source files and 648 previous prediction files. Closure rehashed the current run’s 473 input/source entries and all 576 new prediction/sidecar files. The before/after input snapshot digest is identical: `203bfa6f1f08917cd12827ab482dbe6957bca0086de07c458c83875c33492fe2`. The prior edge manifest remains `9a8c32a150c7a42ab0f43310a6b01f9618cfa340e1ac4c8c58ef78717c2c80a3`.

Final aggregate SHA: `64f8aee540927c439824cc1192e172fd129a1d57fe5cc929daa98a84863fd723`. Home-only final manifest SHA: `13f835733dbe9f02db0d6b8e16160eb5988e6f3493f43185a26fa45a7291b409`. No inference, training, model/default change, phone or UI action occurred. Native validation recorded 374 Swift tests including four skipped, zero failures; its strict parity covered 864 outputs, including 216 candidate-H outputs, and 720 historical checkpoints. The independent replay harness passed eight local tests.

## Primary error and coverage by scenario/exercise

Error cells are full / declared-target MPJPE in mm; coverage cells are full / target percentages. The JSON retains more precision and raw sums/counts.

| Scenario | Exercise | A/raw error | G error | H error | Candidate H error | H coverage % | Candidate coverage % |
|---|---|---:|---:|---:|---:|---:|---:|
| clean | barbell_row | 123.673 / 173.968 | 123.546 / 174.031 | 123.521 / 173.588 | 123.521 / 173.588 | 98.9169 / 95.3162 | 98.9157 / 95.3162 |
| clean | pushup | 233.041 / 350.515 | 233.001 / 351.199 | 233.001 / 351.199 | 233.001 / 351.199 | 91.0440 / 81.1434 | 91.0440 / 81.1434 |
| clean | squat | 113.550 / 183.903 | 113.477 / 184.642 | 113.477 / 184.642 | 113.477 / 184.642 | 98.5953 / 99.6672 | 98.5953 / 99.6672 |
| keypoint_stress | barbell_row | 125.475 / 202.975 | 126.326 / 221.720 | 125.880 / 214.073 | 125.884 / 214.115 | 96.4216 / 57.2222 | 96.4216 / 57.2222 |
| keypoint_stress | pushup | 260.599 / 418.548 | 261.141 / 421.339 | 261.141 / 421.339 | 261.141 / 421.339 | 82.9575 / 49.3056 | 82.9575 / 49.3056 |
| keypoint_stress | squat | 125.667 / 193.351 | 127.152 / 222.344 | 127.152 / 222.344 | 127.152 / 222.344 | 94.3954 / 61.3889 | 94.3954 / 61.3889 |
| rgb_stress | barbell_row | 129.380 / 186.312 | 128.965 / 186.787 | 128.902 / 185.651 | 128.903 / 185.651 | 96.3072 / 93.3333 | 96.3072 / 93.3333 |
| rgb_stress | pushup | 262.015 / 417.851 | 262.011 / 412.032 | 262.011 / 412.032 | 262.011 / 412.032 | 86.9608 / 77.0833 | 86.9608 / 77.0833 |
| rgb_stress | squat | 125.711 / 194.193 | 125.534 / 195.708 | 125.534 / 195.708 | 125.534 / 195.708 | 96.6667 / 99.1667 | 96.6667 / 99.1667 |

The primary clean-row full coverage changes from 98.916862% to 98.915714% (−0.001148 percentage points; two changed invalid joint-frames). Target coverage and all stress coverage are unchanged. The primary keypoint-row target MPJPE increases by 0.041894 mm. Rounded table cells can conceal these tiny differences; no significance or generalization claim is made.

### Damaged target joints use a different denominator

The full primary target error above includes all declared target joints across 90:end. The following microaverages include only actual damaged target joint-frames in onset + ongoing partitions. They are not interchangeable: keypoint-row full-primary target changes by +0.041894 mm, whereas its damaged-target subset changes by +0.110897 mm; the all-exercise damaged-target microaverage changes by +0.027724 mm.

| Scenario | Exercise | Damaged target joint-frames | H error mm | Candidate error mm | Delta mm | Coverage H = candidate % |
|---|---|---:|---:|---:|---:|---:|
| keypoint_stress | all_exercises | 544 | 361.263959 | 361.291683 | +0.027724 | 1.102941 |
| keypoint_stress | barbell_row | 136 | 292.796123 | 292.907020 | +0.110897 | 1.470588 |
| keypoint_stress | pushup | 272 | 442.982310 | 442.982310 | +0.000000 | 0.735294 |
| keypoint_stress | squat | 136 | 266.295093 | 266.295093 | +0.000000 | 1.470588 |
| rgb_stress | all_exercises | 536 | 317.701306 | 317.701306 | +0.000000 | 83.395522 |
| rgb_stress | barbell_row | 134 | 218.444713 | 218.444713 | +0.000000 | 93.283582 |
| rgb_stress | pushup | 268 | 428.893943 | 428.893943 | +0.000000 | 71.268657 |
| rgb_stress | squat | 134 | 194.572626 | 194.572626 | +0.000000 | 97.761194 |

No affected-joint sample is dropped from the error denominator when its output is invalid. In particular, the keypoint damaged subset has very low mask coverage; this does not convert it into a high-confidence error estimate.

## Motion preservation and recovery

The motion proxy uses the frozen five-frame displacement and reference motion >20 mm. Suppression means projected gain <0.5; it does not label a real movement incorrect. Values below compare H → candidate H. Recovery cells are recovered/eligible, followed by mean recovered time in seconds; a missing mean is unavailable, not zero.

| Scenario | Exercise | Mean gain H → candidate | Suppressed pairs H → candidate / eligible | Recovery H = candidate | Full-1s unrecovered | Limited follow-up | Clip / next-damage censored |
|---|---|---:|---:|---:|---:|---:|---:|
| clean | barbell_row | 0.80415896 → 0.80415226 | 8331 → 8330 / 47988 | 0/0; unavailable | 0 | 0 | 0 / 0 |
| clean | pushup | 0.70035747 → 0.70035747 | 27065 → 27065 / 78488 | 0/0; unavailable | 0 | 0 | 0 / 0 |
| clean | squat | 0.81916734 → 0.81916734 | 27486 → 27486 / 119108 | 0/0; unavailable | 0 | 0 | 0 / 0 |
| keypoint_stress | barbell_row | 0.66041799 → 0.66042543 | 627 → 626 / 2356 | 10/10; 0.072000s | 0 | 0 | 0 / 0 |
| keypoint_stress | pushup | 0.78772996 → 0.78772996 | 1060 → 1060 / 2960 | 15/20; 0.094667s | 2 | 3 | 1 / 2 |
| keypoint_stress | squat | 0.86867541 → 0.86867541 | 883 → 883 / 3362 | 10/10; 0.022000s | 0 | 0 | 0 / 0 |
| rgb_stress | barbell_row | 0.63648488 → 0.63648706 | 700 → 700 / 2356 | 8/8; 0.060000s | 0 | 0 | 0 / 0 |
| rgb_stress | pushup | 0.80886356 → 0.80886356 | 1091 → 1091 / 2960 | 13/16; 0.089231s | 2 | 1 | 0 / 1 |
| rgb_stress | squat | 0.85546310 → 0.85546310 | 834 → 834 / 3362 | 8/8; 0.017500s | 0 | 0 | 0 / 0 |

Every H-versus-candidate recovery aggregate is exactly equal in both whole and primary windows. In the primary window, suppression falls by one pair in clean row and one pair in keypoint-stress row; RGB row is unchanged. These very small changes do not establish preserved true motion or an improvement. A/G recovery and motion records remain in the complete JSON.

## Actual phase and decision differences

Counts below are candidate-versus-legacy-H changes. Every change occurs on row streams; pushup/squat counts are zero. Acceptance is represented by changed rejected joint-frame flags, independently from the invalid mask and phase label.

| Window | Scenario | Phase-label frames | Turning-flag frames | Rejected joint-frames | Invalid joint-frames | Corrected joint-frames |
|---|---|---:|---:|---:|---:|---:|
| whole | clean | 114 | 53 | 5 | 5 | 35 |
| whole | keypoint_stress | 8 | 3 | 0 | 0 | 30 |
| whole | rgb_stress | 6 | 4 | 0 | 0 | 2 |
| primary | clean | 75 | 27 | 2 | 2 | 15 |
| primary | keypoint_stress | 5 | 1 | 0 | 0 | 30 |
| primary | rgb_stress | 3 | 2 | 0 | 0 | 2 |

Primary totals are 83 changed phase-label frames, 30 changed turning flags, two changed rejection/invalid/prediction/passthrough joint-frames and 47 changed corrected joint-frames. Whole-sequence totals are 128, 60, five and 67 respectively. Expired-fallback flags never change. Phase changes are not assumed to improve phase correctness.

Candidate phase-input membership is disjoint and complete over IDs 11–16. The following primary row counts distinguish eligible observations, rejected finite/reliable observations and otherwise unavailable inputs. These are input eligibility facts, not evidence that each joint contributes to every phase branch.

| Scenario | Eligible / total joint-frames | Rejected | Unavailable | Internal = final turning frames | Preserved relocation joint-frames |
|---|---:|---:|---:|---:|---:|
| clean | 59258 / 61488 | 89 | 2141 | 575 | 20 |
| keypoint_stress | 1979 / 2160 | 8 | 173 | 31 | 0 |
| rgb_stress | 2065 / 2160 | 6 | 89 | 31 | 0 |

Actual internal `_phase` return values are captured for both H policies; candidate internal/final turning also comes directly from native-aligned diagnostics. No external phase override is used. Elbow-versus-distance turning cause subtypes are unavailable because the frozen source does not emit them; no cause is inferred from phase labels.

## Runtime and limits

The single live SSH process exited 0. Home CPU/BLAS was single-threaded, Python 3.11.15 and NumPy 1.26.4. GNU time records user 142.65 s, system 0.59 s, process wall 143.40 s and maximum RSS 118,660 KiB. The runner’s independent monotonic interval is 147.0875 s, which is 3.6875 s longer than the recorded GNU wall value. This clock discrepancy is retained without choosing one as calibrated elapsed time. Neither value measures iPhone latency, inference cost, or per-frame device overhead. Exact invocation is preserved in the execution receipt.

Private artifacts remain under `~/bpt-runs/motion-phase-acceptance-20261104-replay/`: `code-v1/`, `results-v1/predictions_HOME_ONLY/`, `results-v1/phase_HOME_ONLY/`, `results-v1/sequences_HOME_ONLY/`, before/after manifests, and `run-v1.log`. Only aggregate results and sanitized receipts were exported. The earlier edge/paired results are unchanged. A separately frozen angle/jitter/uncertainty supplement may consume these closed files read-only; this report does not yet claim supplement outcomes.

Aggregate arithmetic check: all 1,152 metric partition sum/count checks pass, and both-window H recovery records are exactly unchanged. These remain reused development data. No adoption, default switch, model replacement or independent form/contact validation follows from this result.
