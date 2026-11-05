# Phase candidate: unchanged-arithmetic angle/time/interval supplement

This supplement gives no basis for adopting the candidate. Mean velocity/acceleration error and jerk decrease slightly, while elbow-angle changes are mixed, nominal interval coverage slightly worsens in keypoint stress, and observed-still support speed is unchanged. Only row streams differ. The main replay's full position error worsens slightly and recovery is unchanged; lower jerk alone does not establish better motion reconstruction.

The collector is the exact earlier edge-supplement implementation (`d649a232…73c0b4`). Protocol and adapter were frozen before viewing these phase outcomes: protocol/source commit `580e172`, after an identity-only correction from the obsolete pre-binding main protocol hash to the actual closed `234f0a77…187afb` protocol. No metric arithmetic, thresholds, selection or denominator changed. This is a supplemental analysis using a previously frozen scorer, not an original study preregistration.

The single saved-output run completed 72/72 streams, four policies, with **1,054 source/input/prediction/phase snapshots unchanged before and after**. There were zero estimator calls and zero model inference calls. Scoring plus final rehash took 4.43 seconds on single-threaded Home CPU; initial hash preflight is outside that timer. [Exact aggregate](motion_phase_supplement_results_20261104.json), [sanitized execution receipt](motion_phase_supplement_execution_20261104.json), [preflight](motion_phase_supplement_preflight_20261104.json), and [frozen protocol](motion_phase_supplement_protocol_20261104.md) preserve the details.

## Original scope and denominator

All quantities below use primary rows **90:end**. Derivatives are taken over the full sequence before that mask. There are no new full/target supplemental partitions: the separate main replay supplies whole/primary full/target position errors. Every scalar mean and percentile is computed from the pooled finite samples, never averaged sequence means/quantiles. Assessment-invalid predictions remain in these metrics.

| Scenario | Frames per angle | Joint-frames per derivative | Still-eligible / candidate support | Expected coordinates |
|---|---|---|---|---|
| clean | 33412 | 568004 | 44489 / 83704 | 1704012 |
| keypoint_stress | 1080 | 18360 | 1132 / 2880 | 55080 |
| rgb_stress | 1080 | 18360 | 1168 / 2880 | 55080 |

All 528 scalar metric rows have finite count equal to expected count; prediction/reference nonfinite-coordinate and finite-degenerate-angle counts are zero. The 48 interval rows have eligible count equal to expected coordinates. These are data-availability facts, not correctness certificates. The JSON retains all scenario/exercise groups and exact sums/counts/pooled p50/p90/p95.

## Seven angles: all-exercise pooled MAE in degrees

Hip angles are shoulder–hip–knee angles. Hip/torso errors are not lumbar-flexion ground truth; GT camera-up is used only for scoring.

| Scenario | Policy | Knee R | Knee L | Elbow R | Elbow L | Hip R | Hip L | Torso |
|---|---|---|---|---|---|---|---|---|
| clean | Raw A | 15.56405 | 15.87617 | 12.39778 | 13.02088 | 15.67903 | 16.48239 | 12.43453 |
| clean | Legacy G | 15.71801 | 15.97444 | 12.61903 | 13.23146 | 15.65085 | 16.44022 | 12.40669 |
| clean | Legacy H | 15.71801 | 15.97444 | 12.60784 | 13.22556 | 15.65085 | 16.44022 | 12.40669 |
| clean | Accepted-phase H | 15.71801 | 15.97444 | 12.60785 | 13.22469 | 15.65085 | 16.44022 | 12.40669 |
| keypoint_stress | Raw A | 13.05024 | 14.72557 | 14.54158 | 11.76169 | 21.31118 | 16.37480 | 11.56506 |
| keypoint_stress | Legacy G | 15.13061 | 15.03749 | 15.89719 | 12.78622 | 21.25065 | 16.23685 | 11.56863 |
| keypoint_stress | Legacy H | 15.13061 | 15.03749 | 15.59984 | 12.47503 | 21.25065 | 16.23685 | 11.56863 |
| keypoint_stress | Accepted-phase H | 15.13061 | 15.03749 | 15.59984 | 12.47287 | 21.25065 | 16.23685 | 11.56863 |
| rgb_stress | Raw A | 14.39242 | 15.15992 | 13.73721 | 9.86628 | 21.50956 | 15.70940 | 12.00306 |
| rgb_stress | Legacy G | 14.98651 | 15.14300 | 14.65964 | 9.95669 | 21.43111 | 15.62464 | 12.03305 |
| rgb_stress | Legacy H | 14.98651 | 15.14300 | 14.61515 | 9.95227 | 21.43111 | 15.62464 | 12.03305 |
| rgb_stress | Accepted-phase H | 14.98651 | 15.14300 | 14.61515 | 9.95367 | 21.43111 | 15.62464 | 12.03305 |

Candidate-minus-legacy-H changes below isolate the row group, where phase behavior can differ. All knee/hip/torso angle rows and both non-row exercises are exactly unchanged. Tiny differences are retained rather than interpreted as significance.

| Scenario | Δ elbow L ° | Δ elbow R ° | Δ velocity mm/s | Δ acceleration mm/s² | Δ jerk mm/s³ |
|---|---|---|---|---|---|
| clean | -0.002819 | +0.000055 | -0.013201 | -0.180935 | -4.148162 |
| keypoint_stress | -0.006471 | +0.000000 | -0.153631 | -3.885541 | -131.817797 |
| rgb_stress | +0.004189 | +0.000000 | -0.075009 | -1.878115 | -66.574410 |

## Time-domain and support proxy: all-exercise means

Jerk is the predicted third-derivative magnitude, not error against a jerk label. Reduced jerk can result from suppressing motion. Observed-still speed uses the unchanged image-speed/confidence proxy; it is not measured contact or support success.

| Scenario | Policy | Velocity error mm/s | Acceleration error mm/s² | Jerk mm/s³ | Still-support speed height/s |
|---|---|---|---|---|---|
| clean | Raw A | 217.210 | 3148.181 | 94747.391 | 0.031276 |
| clean | Legacy G | 219.676 | 3209.260 | 97019.016 | 0.031497 |
| clean | Legacy H | 219.641 | 3208.820 | 97006.464 | 0.031497 |
| clean | Accepted-phase H | 219.637 | 3208.764 | 97005.192 | 0.031497 |
| keypoint_stress | Raw A | 264.237 | 4141.484 | 114058.774 | 0.037866 |
| keypoint_stress | Legacy G | 285.273 | 4562.495 | 131490.485 | 0.040119 |
| keypoint_stress | Legacy H | 284.640 | 4550.720 | 131193.616 | 0.040119 |
| keypoint_stress | Accepted-phase H | 284.589 | 4549.425 | 131149.676 | 0.040119 |
| rgb_stress | Raw A | 272.554 | 4164.111 | 116511.676 | 0.042513 |
| rgb_stress | Legacy G | 278.282 | 4318.334 | 124870.275 | 0.043955 |
| rgb_stress | Legacy H | 278.194 | 4316.476 | 124830.813 | 0.043955 |
| rgb_stress | Accepted-phase H | 278.169 | 4315.850 | 124808.621 | 0.043955 |

Observed-still support speed is exactly unchanged for every exercise/scenario between the two H policies. Mean derivative errors decline slightly, but tails are not uniformly better: clean all-exercise jerk p95 rises from **342,815.245421** to **342,849.279885 mm/s³**, while its mean falls. Row jerk p95 similarly rises from **232,481.478421** to **232,498.646254 mm/s³**. Stress jerk p95 values are unchanged. These are pooled sample quantiles, not averages of per-video percentiles.

## Nominal 95% coordinate interval coverage and assessment masks

Raw A sigma starts from the frozen estimator's heuristic `(0.015 + 0.10 × (1 − confidence)) × body scale`, with its existing uninitialized/unavailable and fallback handling; it is not uncertainty emitted by XS. G/H covariance/heuristic intervals are also not calibrated model posteriors or guarantees that include model bias. The nominal coverage denominator includes every finite-positive-sigma coordinate even if a prediction/reference coordinate were nonfinite; no such coordinate is missing in this run.

| Scenario | Policy | Nominal coverage % | Covered / eligible coordinates | Invalid / expected joint-frames |
|---|---|---|---|---|
| clean | Raw A | 57.533867 | 980384 / 1704012 | 1283 / 568004 |
| clean | Legacy G | 39.324019 | 670086 / 1704012 | 18271 / 568004 |
| clean | Legacy H | 39.323901 | 670084 / 1704012 | 18253 / 568004 |
| clean | Accepted-phase H | 39.323901 | 670084 / 1704012 | 18255 / 568004 |
| keypoint_stress | Raw A | 55.822440 | 30747 / 55080 | 263 / 18360 |
| keypoint_stress | Legacy G | 41.897240 | 23077 / 55080 | 1609 / 18360 |
| keypoint_stress | Legacy H | 41.893609 | 23075 / 55080 | 1605 / 18360 |
| keypoint_stress | Accepted-phase H | 41.888163 | 23072 / 55080 | 1605 / 18360 |
| rgb_stress | Raw A | 54.061365 | 29777 / 55080 | 148 / 18360 |
| rgb_stress | Legacy G | 39.782135 | 21912 / 55080 | 1229 / 18360 |
| rgb_stress | Legacy H | 39.787582 | 21915 / 55080 | 1228 / 18360 |
| rgb_stress | Accepted-phase H | 39.787582 | 21915 / 55080 | 1228 / 18360 |

Candidate H loses exactly **3 covered coordinates out of 55,080** in keypoint stress (−0.005447 percentage points overall; −0.016340 points within row). Clean and RGB nominal coverage are exactly unchanged. Clean assessment-invalid count rises by two; stress mask counts are unchanged. Neither nominal-interval coverage nor the separate assessment mask is a validated-form probability.

## Main-result context and limits

The closed main aggregate (`64f8aee5…3fd723`, manifest `13f83573…1b409`) reports primary row full MPJPE increases of **0.000135 / 0.003120 / 0.000480 mm** for clean/keypoint/RGB, and keypoint-row target MPJPE increases by **0.041894 mm**. Recovery aggregates are exactly unchanged. Those full/target position metrics use their own declared denominators and are not replaced by this supplement's all-joint derivative or angle denominators.

Astra/root audits confirmed baseline A/G/H supplemental rows exactly reproduce the earlier edge-supplement values, all current sums/counts and interval ratios are consistent, and candidate non-row metrics/masks are unchanged. The phase candidate remains an experimental ordering/input-eligibility package on reused development data. These tiny mixed changes do not establish accuracy improvement, clinical usefulness, form-error recall, contact accuracy or adoption readiness.

Private predictions and source arrays remain on Home. Scalar samples were pooled in memory there; the aggregate and hash receipts were retained under `~/bpt-runs/motion-phase-acceptance-20261104-replay/supplement-v1/`, with frozen adapter/protocol in `supplement-code-v1/`. Only aggregate metrics and a sanitized receipt were transferred. No phone, UI, training, inference, default change or additional experiment occurred.
