# Nine-policy metric supplement — 2026-11-04

**The supplemental metrics do not support adoption.** Angular changes are mixed, temporal-error/jerk changes vary by condition, and adding the edge policy lowers nominal interval coverage. Mechanical synthetic fixes do not establish better exercise assessment.

This is a descriptive supplement declared **after** the first paired-agreement results were known and **before** the nine-policy outcomes were viewed. It is not an independent preregistered validation. The [frozen supplement protocol](motion_edge_supplement_protocol_20261104.md), [pooled results](motion_edge_supplement_results_20261104.json), [execution receipt](motion_edge_supplement_execution_20261104.json), and [main nine-policy comparison](motion_edge_alignment_results_20261104.md) retain the full evidence.

## Execution and denominators

All 72 streams × nine policies were scored from the closed saved outputs in 7.10 seconds on one CPU/BLAS thread. The main manifest and aggregate identity were verified, and all 1,484 source/input/prediction hashes were checked before and after. No estimator was initialized, no model inference or training ran, and no phone action occurred. The original frozen `pose_angles` and `derivative` functions were reused; GT camera scale and up direction were used only in scoring.

Every scalar mean/quantile is conditional on finite samples. Exact pooled samples produce p50/p90/p95; sequence quantiles and percentages are never averaged. The raw counts and sums remain in JSON for every scenario × exercise × policy. In this run **all expected scalar samples were finite, with zero predicted/reference degenerate-angle events**; all expected coordinates had finite positive sigma and finite prediction/reference values. No missing-value exclusion explains policy differences.

| Scenario | Expected frames per angle/policy | Expected joint-frames per temporal metric/policy | Expected / eligible interval coordinates | Candidate support joint-frames | Observed-still eligible support samples |
| --- | ---: | ---: | ---: | ---: | ---: |
| Clean | 33,412 | 568,004 | 1,704,012 / 1,704,012 | 83,704 | 44,489 |
| Keypoint stress | 1,080 | 18,360 | 55,080 / 55,080 | 2,880 | 1,132 |
| RGB stress | 1,080 | 18,360 | 55,080 / 55,080 | 2,880 | 1,168 |

Temporal metrics include all 17 joints, including the root-relative zero pelvis, matching the original scorer. “Expected samples” for support speed means **observed-still eligible samples**; `candidate_support_joint_frames` is the larger outer denominator. This is an image-plane observation proxy, not verified contact.

## Seven angular errors

Primary rows 90:end, pooled angular MAE in degrees. Left/right hip and torso angles are **not lumbar-flexion ground truth**. They do not establish clinical accuracy or actual bad-form false positives/negatives.

| Scenario | Policy | Knee L | Knee R | Elbow L | Elbow R | Hip L | Hip R | Torso |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Clean | Raw A | 15.876 | 15.564 | 13.021 | 12.398 | 16.482 | 15.679 | 12.435 |
| Clean | Legacy G | 15.974 | 15.718 | 13.231 | 12.619 | 16.440 | 15.651 | 12.407 |
| Clean | Legacy H | 15.974 | 15.718 | 13.226 | 12.608 | 16.440 | 15.651 | 12.407 |
| Clean | Paired G | 15.962 | 15.708 | 13.231 | 12.620 | 16.432 | 15.686 | 12.407 |
| Clean | Paired H | 15.962 | 15.708 | 13.225 | 12.609 | 16.432 | 15.686 | 12.407 |
| Clean | Edge G | 15.970 | 15.749 | 13.201 | 12.585 | 16.437 | 15.649 | 12.407 |
| Clean | Edge H | 15.970 | 15.749 | 13.195 | 12.574 | 16.437 | 15.649 | 12.407 |
| Clean | Paired+edge G | 15.957 | 15.735 | 13.196 | 12.579 | 16.430 | 15.678 | 12.406 |
| Clean | Paired+edge H | 15.957 | 15.735 | 13.190 | 12.568 | 16.430 | 15.678 | 12.406 |
| Keypoint stress | Raw A | 14.726 | 13.050 | 11.762 | 14.542 | 16.375 | 21.311 | 11.565 |
| Keypoint stress | Legacy G | 15.037 | 15.131 | 12.786 | 15.897 | 16.237 | 21.251 | 11.569 |
| Keypoint stress | Legacy H | 15.037 | 15.131 | 12.475 | 15.600 | 16.237 | 21.251 | 11.569 |
| Keypoint stress | Paired G | 14.979 | 15.080 | 12.814 | 15.878 | 16.289 | 21.251 | 11.597 |
| Keypoint stress | Paired H | 14.979 | 15.080 | 12.503 | 15.581 | 16.289 | 21.251 | 11.597 |
| Keypoint stress | Edge G | 15.010 | 15.145 | 12.787 | 15.904 | 16.237 | 21.251 | 11.569 |
| Keypoint stress | Edge H | 15.010 | 15.145 | 12.476 | 15.606 | 16.237 | 21.251 | 11.569 |
| Keypoint stress | Paired+edge G | 14.982 | 15.078 | 12.809 | 15.884 | 16.289 | 21.251 | 11.597 |
| Keypoint stress | Paired+edge H | 14.982 | 15.078 | 12.497 | 15.587 | 16.289 | 21.251 | 11.597 |
| RGB stress | Raw A | 15.160 | 14.392 | 9.866 | 13.737 | 15.709 | 21.510 | 12.003 |
| RGB stress | Legacy G | 15.143 | 14.987 | 9.957 | 14.660 | 15.625 | 21.431 | 12.033 |
| RGB stress | Legacy H | 15.143 | 14.987 | 9.952 | 14.615 | 15.625 | 21.431 | 12.033 |
| RGB stress | Paired G | 15.143 | 14.958 | 9.980 | 14.625 | 15.679 | 21.404 | 12.072 |
| RGB stress | Paired H | 15.143 | 14.958 | 9.976 | 14.581 | 15.679 | 21.404 | 12.072 |
| RGB stress | Edge G | 14.979 | 14.876 | 9.951 | 14.660 | 15.624 | 21.740 | 12.034 |
| RGB stress | Edge H | 14.979 | 14.876 | 9.947 | 14.616 | 15.624 | 21.740 | 12.034 |
| RGB stress | Paired+edge G | 14.979 | 14.848 | 9.969 | 14.626 | 15.679 | 21.713 | 12.073 |
| RGB stress | Paired+edge H | 14.979 | 14.848 | 9.965 | 14.581 | 15.679 | 21.713 | 12.073 |

No policy improves every angular measure. The complete per-exercise angle means, pooled quantiles and finite/expected counts are in JSON; improvements in one joint or pooled mean must not conceal deterioration elsewhere.

## Time derivatives, support motion, and nominal intervals

Cells for velocity, acceleration, jerk and support speed show **pooled finite mean / pooled p95**. Velocity/acceleration are errors relative to the reference; jerk is the magnitude of the third derivative of the prediction, not an error to reference jerk. A lower jerk can come from suppressed true motion, so interpret it with the [main displacement-gain/suppression results](motion_edge_alignment_results_20261104.md).

**Raw A sigma is not an uncertainty/probability output of XS.** It is the experimental estimator’s confidence/body-scale heuristic attached to raw pose (base form `(0.015 + 0.10 × (1 − confidence)) × body scale`, with the existing state/fallback handling). G/H sigma also does not include a calibrated model-bias guarantee. The reported 1.96×sigma coordinate interval is nominal only: observed coverage around 38–58% is not a valid 95% guarantee and must not be described as calibrated probability.

| Scenario | Policy | Velocity error mm/s | Acceleration error mm/s² | Predicted jerk mm/s³ | Still-support image-height/s | Nominal 95% coordinate coverage % |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Clean | Raw A | 217.21 / 710.68 | 3148.2 / 10673.1 | 94747 / 336573 | 0.03128 / 0.08225 | 57.534 |
| Clean | Legacy G | 219.68 / 709.86 | 3209.3 / 10873.1 | 97019 / 342905 | 0.03150 / 0.08251 | 39.324 |
| Clean | Legacy H | 219.64 / 709.73 | 3208.8 / 10870.8 | 97006 / 342815 | 0.03150 / 0.08251 | 39.324 |
| Clean | Paired G | 219.65 / 710.59 | 3209.5 / 10873.1 | 96990 / 342665 | 0.03153 / 0.08249 | 39.466 |
| Clean | Paired H | 219.62 / 710.30 | 3209.0 / 10870.8 | 96977 / 342609 | 0.03153 / 0.08249 | 39.466 |
| Clean | Edge G | 219.33 / 708.70 | 3201.4 / 10891.2 | 96731 / 341944 | 0.03128 / 0.08247 | 38.210 |
| Clean | Edge H | 219.29 / 708.49 | 3200.9 / 10886.2 | 96719 / 341900 | 0.03128 / 0.08247 | 38.211 |
| Clean | Paired+edge G | 219.19 / 708.73 | 3199.2 / 10876.8 | 96632 / 341588 | 0.03130 / 0.08243 | 38.264 |
| Clean | Paired+edge H | 219.15 / 708.59 | 3198.7 / 10873.0 | 96619 / 341511 | 0.03130 / 0.08243 | 38.264 |
| Keypoint stress | Raw A | 264.24 / 951.88 | 4141.5 / 16654.2 | 114059 / 446434 | 0.03787 / 0.10558 | 55.822 |
| Keypoint stress | Legacy G | 285.27 / 979.27 | 4562.5 / 17698.8 | 131490 / 510970 | 0.04012 / 0.11108 | 41.897 |
| Keypoint stress | Legacy H | 284.64 / 971.47 | 4550.7 / 17692.4 | 131194 / 504769 | 0.04012 / 0.11108 | 41.894 |
| Keypoint stress | Paired G | 282.64 / 972.28 | 4535.0 / 17679.7 | 129869 / 503895 | 0.04015 / 0.11108 | 42.259 |
| Keypoint stress | Paired H | 282.00 / 963.84 | 4523.2 / 17672.0 | 129572 / 500218 | 0.04015 / 0.11108 | 42.255 |
| Keypoint stress | Edge G | 285.62 / 969.15 | 4576.7 / 17692.4 | 132298 / 513323 | 0.04020 / 0.11122 | 40.238 |
| Keypoint stress | Edge H | 284.99 / 959.89 | 4564.9 / 17689.7 | 132001 / 507970 | 0.04020 / 0.11122 | 40.234 |
| Keypoint stress | Paired+edge G | 283.06 / 959.43 | 4538.1 / 17657.0 | 130687 / 505330 | 0.04015 / 0.11122 | 40.209 |
| Keypoint stress | Paired+edge H | 282.42 / 952.71 | 4526.3 / 17653.9 | 130390 / 500596 | 0.04015 / 0.11122 | 40.205 |
| RGB stress | Raw A | 272.55 / 963.59 | 4164.1 / 17413.8 | 116512 / 437084 | 0.04251 / 0.11094 | 54.061 |
| RGB stress | Legacy G | 278.28 / 952.69 | 4318.3 / 17664.6 | 124870 / 485503 | 0.04395 / 0.11298 | 39.782 |
| RGB stress | Legacy H | 278.19 / 952.69 | 4316.5 / 17646.3 | 124831 / 484872 | 0.04395 / 0.11298 | 39.788 |
| RGB stress | Paired G | 279.11 / 953.36 | 4352.2 / 17747.0 | 125838 / 494909 | 0.04467 / 0.11456 | 40.198 |
| RGB stress | Paired H | 279.02 / 953.36 | 4350.4 / 17695.2 | 125799 / 494596 | 0.04467 / 0.11456 | 40.203 |
| RGB stress | Edge G | 279.31 / 948.67 | 4348.7 / 17692.6 | 126092 / 494624 | 0.04423 / 0.11623 | 37.743 |
| RGB stress | Edge H | 279.22 / 948.67 | 4346.8 / 17657.4 | 126053 / 492662 | 0.04423 / 0.11623 | 37.749 |
| RGB stress | Paired+edge G | 279.41 / 948.67 | 4358.4 / 17664.6 | 126371 / 498127 | 0.04494 / 0.11785 | 37.736 |
| RGB stress | Paired+edge H | 279.33 / 948.67 | 4356.5 / 17646.3 | 126331 / 497908 | 0.04494 / 0.11785 | 37.741 |

Adding the edge package lowers H interval coverage from 39.324% to 38.211% clean, 41.894% to 40.234% in keypoint stress, and 39.788% to 37.749% in RGB stress. Combined paired+edge coverage is similarly low. The raw-A interval coverage of roughly 54–58% also falls far short of the nominal label. These are empirical coverage observations of heuristic intervals, not probability estimates.

## Exercise-specific edge-package contrasts

The next table compares edge-only H with legacy H, and combined H with paired H. “Largest angle Δ” selects the largest absolute MAE change among the seven angles **within that exercise** and preserves its sign; it is descriptive, not a selected success endpoint. Other columns show signed mean changes and coverage percentage-point changes. Every angle and both G/H variants remain in JSON.

| Scenario | Exercise | Contrast | Largest angle Δ deg | Velocity error Δ mm/s | Accel error Δ mm/s² | Jerk Δ mm/s³ | Coverage Δ pp |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| Clean | barbell_row | Edge H − legacy H | elbow_right: -0.0045 | -0.10 | -5.89 | -93.31 | -0.407 |
| Clean | barbell_row | Combined H − paired H | elbow_right: -0.0045 | -0.12 | -6.82 | -111.47 | -0.706 |
| Clean | pushup | Edge H − legacy H | elbow_right: -0.1292 | -0.75 | -11.45 | -752.23 | -2.722 |
| Clean | pushup | Combined H − paired H | elbow_right: -0.1561 | -1.28 | -21.22 | -1074.24 | -2.710 |
| Clean | squat | Edge H − legacy H | elbow_left: -0.0040 | -0.29 | -7.21 | -157.13 | -0.683 |
| Clean | squat | Combined H − paired H | elbow_left: -0.0046 | -0.24 | -6.46 | -118.57 | -0.682 |
| Keypoint stress | barbell_row | Edge H − legacy H | knee_left: +0.0000 | 1.22 | 18.68 | 1133.53 | -0.414 |
| Keypoint stress | barbell_row | Combined H − paired H | knee_left: +0.0000 | 1.24 | 18.95 | 1143.96 | -0.414 |
| Keypoint stress | pushup | Edge H − legacy H | knee_left: -0.0839 | -1.70 | 1.56 | 137.13 | -2.462 |
| Keypoint stress | pushup | Combined H − paired H | elbow_right: +0.0185 | -1.52 | -33.01 | 111.10 | -3.617 |
| Keypoint stress | squat | Edge H − legacy H | elbow_left: -0.0146 | 1.52 | 22.35 | 1152.43 | -2.102 |
| Keypoint stress | squat | Combined H − paired H | elbow_left: -0.0339 | 1.54 | 23.47 | 1196.92 | -2.119 |
| RGB stress | barbell_row | Edge H − legacy H | knee_left: +0.0004 | 1.51 | 21.35 | 1379.96 | -1.874 |
| RGB stress | barbell_row | Combined H − paired H | knee_left: +0.0000 | 1.52 | 21.50 | 1390.77 | -1.874 |
| RGB stress | pushup | Edge H − legacy H | hip_right: +0.9270 | 0.17 | 48.13 | 1133.65 | -2.119 |
| RGB stress | pushup | Combined H − paired H | hip_right: +0.9270 | -2.03 | -25.66 | -987.36 | -3.371 |
| RGB stress | squat | Edge H − legacy H | elbow_left: -0.0161 | 1.40 | 21.54 | 1152.51 | -2.124 |
| RGB stress | squat | Combined H − paired H | elbow_left: -0.0333 | 1.42 | 22.68 | 1194.50 | -2.141 |

These are the effects of the declared **packages**: edge-only includes coherent same-frame ratios, scale normalization and availability checks with legacy agreement; combined includes both agreement and edge packages. They are not isolated single-line ablations. Increased assessment coverage in the main replay does not imply more correct assessments or better uncertainty coverage.

## Limits and retained artifacts

The data are reused development streams with correlated frames/joints and proxy damage, not a new holdout. No thresholds or runtime policy were changed after seeing these measurements. The inherited nonfinite leg-score clipping and conditional edge-reference-age denominator remain as declared; the independent input audit found no nonfinite detector/leg scores in these streams. Abrupt scale-jump invariance remains unsupported by the synthetic witness.

Scalar samples were pooled in memory on Home. Aggregate counts/sums and hash receipts were retained under `~/bpt-runs/motion-edge-alignment-20261104-nine-policy/supplement-v1/`; the underlying saved predictions remain in the main run, and the supplement source/protocol are in `supplement-code-v1/`. Only the aggregate and nonidentifying execution receipt were exported. Six synthetic pooling/denominator/identity checks passed before execution.

Aggregate SHA256: `477e94043a6730b2e8b3e5114fa2df5330952934f5ef8269366987dd3afb03f0`. Closed main aggregate SHA256: `06e432973dada120c5bb3b09fcbc234d1b39ed7a4405cfc981d2426160825849`. The default remains legacy and the signed `6c932d2` phone artifact is unchanged.
