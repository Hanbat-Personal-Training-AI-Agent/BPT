# Paired-anchor motion agreement: saved-stream results — 2026-11-04

**Do not adopt on this evidence.** The predeclared paired-anchor package slightly reduces clean-stream error, but increases full-joint error in the predeclared primary window on both stress sets and reduces coverage. Small damaged-target gains do not offset those tradeoffs. No thresholds were tuned and the default remains the historical policy.

The package changes the agreement reference to a paired last-accepted 2D/3D timestamp and root-relative units, with finite/reliable joint and bilateral-hip support and observed-scale availability. These results estimate the **combined package effect**, not the isolated causal contribution of time alignment, root subtraction or any one eligibility gate. Parent/child historical plausibility anchors remain outside scope.

Protocol: [predeclared comparison](motion_anchor_alignment_protocol_20261104.md). Machine-readable [complete microaggregates](motion_anchor_alignment_results_20261104.json), [execution receipt](motion_anchor_alignment_execution_20261104.json), and [synthetic parity](motion_anchor_alignment_parity_20261104.json).

## Execution and frozen denominators

Home-only CPU/BLAS single-threaded replay completed **72/72 streams, 42,052 frames, 360 saved policy outputs**, in 185.59 seconds. All five outputs were saved before parsing each sequence’s GT/score reference; GT files were only byte-hashed beforehand against their historical v4 manifest. No model inference, video decoding, new labels, SMPL profiles, training, GPU, phone action, model/default change or adoption occurred. Online observed-length profiles still use rows 21–80 and activate at 81 with confidence 0.4.

The 60 clean streams retain their full saved length. The six keypoint and six RGB stress streams each retain the frozen first 270 frames. These are reused development streams, including historically named “heldout” data, not a fresh holdout.

| Scenario | Streams | Whole frames | Whole joint-frames per policy | Primary frames (90:end) | Primary joint-frames per policy |
| --- | ---: | ---: | ---: | ---: | ---: |
| Clean | 60 | 38,812 | 659,804 | 33,412 | 568,004 |
| Keypoint stress | 6 | 1,620 | 27,540 | 1,080 | 18,360 |
| RGB stress | 6 | 1,620 | 27,540 | 1,080 | 18,360 |

Every invalid prediction remains in the error denominator. Coverage is the fraction not marked invalid, not a correctness rate. Pelvis/root is included in all 17 joints and is root-relative zero for all policies. Means are joint-frame weighted microaggregates; correlated joints/frames/streams are not independent samples.

All 144 legacy G/H replays matched every historical non-timing saved array exactly, including app-pose/invalid arrays; raw-A’s shared arrays also matched exactly. The older v3 raw-A schema has no `expired_prediction_fallback`; the new array was explicitly checked all-false. No other absent field was allowed. The first attempt stopped on that schema difference before completing/scoring any sequence and is preserved; only the harness compatibility check changed for the second attempt.

Final checks rehashed **465 inputs/source files** and **360 prediction files** unchanged. Four replay arithmetic/schema tests passed in addition to the synthetic gate’s 22 focused tests, 720 historical parity outputs and 616 cross-language synthetic frame outputs. The owner’s full Swift package passed 327 tests with 4 skipped and no failures. Aggregate partition sums are exhaustive for every metric/window, and the exported aggregate hash matches Home exactly.

## Primary errors and coverage

All errors below are millimetres over rows 90:end. “Target/all” includes **every frame of the preselected target joints**, including undamaged and recovery frames. It is not the historical damaged-target metric. Targets follow the original lower-confidence-side selection from the observed calibration prefix, without GT.

| Scenario | Policy | Full 17-joint MPJPE | Target/all MPJPE | Wrist MPJPE | Ankle MPJPE | Full coverage % |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Clean | Raw A | 146.838965 | 248.669399 | 180.157684 | 258.068838 | 99.774 |
| Clean | Legacy G | 146.757525 | 249.220295 | 180.095205 | 258.222102 | 96.783 |
| Clean | Paired G | 146.732556 | 249.193596 | 180.099627 | 258.201791 | 96.615 |
| Clean | Legacy H | 146.749914 | 249.111975 | 180.023432 | 258.222102 | 96.786 |
| Clean | Paired H | 146.724988 | 249.085276 | 180.028220 | 258.201791 | 96.618 |
| Keypoint stress | Raw A | 170.580420 | 308.355621 | 208.251725 | 355.998926 | 98.568 |
| Keypoint stress | Legacy G | 171.539738 | 321.685665 | 213.697699 | 359.020172 | 91.236 |
| Keypoint stress | Paired G | 171.625741 | 321.962760 | 213.631975 | 359.207083 | 90.076 |
| Keypoint stress | Legacy H | 171.391121 | 319.773911 | 212.423196 | 359.020172 | 91.258 |
| Keypoint stress | Paired H | 171.477124 | 320.051006 | 212.357472 | 359.207083 | 90.098 |
| RGB stress | Raw A | 172.368741 | 304.051409 | 207.611331 | 356.881271 | 99.194 |
| RGB stress | Legacy G | 172.170215 | 301.639890 | 207.318312 | 352.482529 | 93.306 |
| RGB stress | Paired G | 172.185720 | 301.607293 | 207.216952 | 352.519072 | 92.320 |
| RGB stress | Legacy H | 172.149188 | 301.355776 | 207.128903 | 352.482529 | 93.312 |
| RGB stress | Paired H | 172.164693 | 301.323179 | 207.027543 | 352.519072 | 92.326 |

Paired versus legacy full-joint changes are about **−0.025 mm clean**, **+0.086 mm keypoint stress**, and **+0.016 mm RGB stress**. Coverage drops about **0.168, 1.160 and 0.986 percentage points**, respectively. These tiny means are descriptive, not a clinically meaningful improvement claim.

Whole-sequence full-joint MPJPE, retaining the initial 90 frames too:

| Scenario | Raw A | Legacy G | Paired G | Legacy H | Paired H |
| --- | ---: | ---: | ---: | ---: | ---: |
| Clean | 141.375470 | 141.272229 | 141.245791 | 141.267784 | 141.241377 |
| Keypoint stress | 154.093344 | 154.772153 | 154.779773 | 154.680812 | 154.688432 |
| RGB stress | 155.285559 | 155.192471 | 155.153092 | 155.186190 | 155.146811 |

## Actual damage and recovery partitions

Partitions use each joint’s actual saved damage-mask runs: onset is its first three damaged frames (or the whole run when shorter), ongoing is the remainder, recovery is the first six undamaged frames after its end, cut off by the next damage, and remaining is everything else. The one-frame confident outlier remains its own onset. Partitions are disjoint and exhaustive.

Historical “damaged targets” are reconstructed by **summing onset + ongoing target error sums and counts**, not averaging their means. The historical primary values reproduce to rounding: clean Raw A/G/H = 146.838965/146.757525/146.749914; damaged-target keypoint Raw A/G/H = 336.019843/365.075126/361.263959; RGB = 319.747020/318.150181/317.701306.

| Scenario | Policy | Damaged target joint-frames | Damaged target MPJPE | Damaged target coverage % | Recovery target MPJPE | Remaining target MPJPE |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Keypoint stress | Raw A | 544 | 336.019843 | 63.051 | 294.144973 | 290.613577 |
| Keypoint stress | Legacy G | 544 | 365.075126 | 1.103 | 301.765233 | 292.992124 |
| Keypoint stress | Paired G | 544 | 365.013504 | 1.103 | 303.567559 | 292.992096 |
| Keypoint stress | Legacy H | 544 | 361.263959 | 1.103 | 299.529098 | 292.774168 |
| Keypoint stress | Paired H | 544 | 361.202338 | 1.103 | 301.331424 | 292.774140 |
| RGB stress | Raw A | 536 | 319.747020 | 95.522 | 296.936689 | 294.154189 |
| RGB stress | Legacy G | 536 | 318.150181 | 83.396 | 290.966454 | 292.089024 |
| RGB stress | Paired G | 536 | 318.062606 | 83.396 | 290.966454 | 292.089024 |
| RGB stress | Legacy H | 536 | 317.701306 | 83.396 | 290.547371 | 291.965340 |
| RGB stress | Paired H | 536 | 317.613732 | 83.396 | 290.547371 | 291.965340 |

Paired damaged-target gains are only **0.061622 mm** in keypoint stress and **0.087575 mm** in RGB stress. Damaged-target coverage is unchanged versus legacy. Keypoint stress still has about 1.103% damaged-target coverage for G/H versus 63.051% for Raw A, and higher damaged-target errors than Raw A. RGB has about 83.396% versus Raw A’s 95.522%.

## Motion preservation and recovery

Gain uses the original five-frame root-relative GT displacement, only where GT displacement exceeds 20 mm and both endpoints are in the score window. Suppression means gain <0.5. Invalid predictions remain included. This is a scoring proxy, not verified contact or exercise-form accuracy. Recovery retains the original three consecutive valid frames within `max(50 mm, clean raw XS error +20 mm)`, before the next damage/clip end/one-second horizon. Mean recovery time conditions on recovered events, so counts and censoring remain visible.

| Scenario | Policy | Mean displacement gain | Suppressed % | Recovered / eligible | Mean recovered time ms | Full-1s unresolved / next-damage / clip-end censored |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Clean | Raw A | 0.778603 | 25.057 | 0/0 | — | 0/0/0 |
| Clean | Legacy G | 0.778166 | 25.624 | 0/0 | — | 0/0/0 |
| Clean | Paired G | 0.778496 | 25.596 | 0/0 | — | 0/0/0 |
| Clean | Legacy H | 0.778263 | 25.605 | 0/0 | — | 0/0/0 |
| Clean | Paired H | 0.778593 | 25.577 | 0/0 | — | 0/0/0 |
| Keypoint stress | Raw A | 0.799930 | 27.645 | 38/40 | 39.473684 | 2/0/0 |
| Keypoint stress | Legacy G | 0.783862 | 29.650 | 35/40 | 70.857143 | 2/2/1 |
| Keypoint stress | Paired G | 0.782928 | 29.707 | 35/40 | 74.285714 | 2/2/1 |
| Keypoint stress | Legacy H | 0.784525 | 29.615 | 35/40 | 67.428571 | 2/2/1 |
| Keypoint stress | Paired H | 0.783592 | 29.673 | 35/40 | 70.857143 | 2/2/1 |
| RGB stress | Raw A | 0.791064 | 28.751 | 30/32 | 41.333333 | 2/0/0 |
| RGB stress | Legacy G | 0.779865 | 30.260 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Paired G | 0.780477 | 30.260 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Legacy H | 0.780118 | 30.249 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Paired H | 0.780729 | 30.249 | 29/32 | 61.379310 | 2/1/0 |

Paired G/H do not recover more events. In keypoint stress the conditional recovery mean becomes about 3.43 ms slower; RGB recovery and censoring are unchanged. Clean suppression slightly decreases, keypoint suppression slightly increases, and RGB suppression is unchanged. The combined evidence is a tradeoff, not consistent motion preservation.

## Exercise and mechanism concentrations

Paired minus legacy primary errors below use each exercise’s own fixed denominator; negative is lower error. Both G and H are shown.

| Scenario | Exercise | Policy pair | Full error Δ mm | Target/all error Δ mm | Changed corrected joint-frames (whole stream) |
| --- | --- | --- | ---: | ---: | ---: |
| Clean | barbell_row | G | -0.016092 | 0.006088 | 111 |
| Clean | barbell_row | H | -0.015951 | 0.006086 | 111 |
| Clean | pushup | G | -0.045544 | 0.036405 | 2469 |
| Clean | pushup | H | -0.045544 | 0.036405 | 2469 |
| Clean | squat | G | -0.019353 | -0.121861 | 482 |
| Clean | squat | H | -0.019353 | -0.121861 | 482 |
| Keypoint stress | barbell_row | G | -0.000656 | 0.000000 | 3 |
| Keypoint stress | barbell_row | H | -0.000656 | 0.000000 | 3 |
| Keypoint stress | pushup | G | 0.327061 | 0.547904 | 270 |
| Keypoint stress | pushup | H | 0.327061 | 0.547904 | 270 |
| Keypoint stress | squat | G | -0.068396 | 0.012573 | 43 |
| Keypoint stress | squat | H | -0.068396 | 0.012573 | 43 |
| RGB stress | barbell_row | G | 0.057364 | 0.000000 | 6 |
| RGB stress | barbell_row | H | 0.057364 | 0.000000 | 6 |
| RGB stress | pushup | G | 0.057940 | -0.065497 | 65 |
| RGB stress | pushup | H | 0.057940 | -0.065497 | 65 |
| RGB stress | squat | G | -0.068789 | 0.000606 | 28 |
| RGB stress | squat | H | -0.068789 | 0.000606 | 28 |

Changed corrected joint-frames concentrate in pushups: 2,469/3,062 clean, 270/316 keypoint stress, and 65/99 RGB stress, for either policy. Clean pushup target/all error increases despite its lower full-joint mean. Keypoint pushup full/target error increases are larger than the pooled means; pooling must not hide them.

Whole-stream paired diagnostics (G and H have the same changed-output counts, but slightly different eligibility counts):

| Scenario | Policy | Evaluated gates | Agreement available | Positive agreement | Missing joint / root / anchor / scale | Rejected joint-frames: legacy → paired |
| --- | --- | ---: | ---: | ---: | --- | ---: |
| Clean | G | 15236 | 7992 | 7043 | 4011/367/2866/0 | 13482 → 14496 |
| Clean | H | 15218 | 7985 | 7038 | 4010/367/2856/0 | 13466 → 14480 |
| Keypoint stress | G | 1159 | 527 | 464 | 172/130/330/0 | 887 → 1102 |
| Keypoint stress | H | 1155 | 525 | 462 | 170/130/330/0 | 883 → 1098 |
| RGB stress | G | 1164 | 618 | 553 | 120/86/340/0 | 916 → 1103 |
| RGB stress | H | 1164 | 618 | 553 | 120/86/340/0 | 916 → 1103 |

Legacy agreement counters were not recorded by the frozen estimator and remain null, not invented zeros. Original rejection and pass-through/prediction arrays are available on both sides. Paired counters for every scenario × exercise, all changed-decision counts, full/target/wrist/ankle partition errors and both score windows remain in the JSON. No scale-exclusion event occurred in these reused streams; that does not validate the rule on missing-scale data.

## Interpretation and retained evidence

The candidate is more conservative overall: it rejects more joint-frames and lowers coverage. Some clean and damaged-target error means decrease, while primary whole-pose stress error, keypoint recovery and several exercise-specific target means worsen. The fixed synthetic tests establish coordinate/state consistency, not safety or real-world performance. These reused streams, proxy damage masks and correlated observations do not establish generalization or human form/contact accuracy. Keep the historical policy as default.

Private Home artifacts are under `~/bpt-runs/motion-anchor-alignment-20261104-paired-replay/`: failed first `code/`, `results/`, `run.log`; successful frozen `code-v2/`, `results-v2/predictions_HOME_ONLY/`, `results-v2/sequences_HOME_ONLY/`, `results-v2/manifest_HOME_ONLY.json` and `run-v2.log`. Only aggregate results and a nonidentifying execution receipt were exported.

Aggregate SHA256: `89bb38131ccc96bbd527036c1973579c42679d27b37bd3b49697a55a76cdf3f0`. The signed phone artifact remains separate and unchanged; this experiment authorizes no deployment, merge, model/default change or new phone test.
