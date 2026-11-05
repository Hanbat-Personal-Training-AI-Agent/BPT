# Coherent edge reference: frozen nine-policy results — 2026-11-04

**Keep both candidate policies opt-in.** The edge package raises coverage, but its error effects conflict across joints, exercises and scenarios. In particular, better pooled RGB full-joint error coexists with worse preselected target error and more GT-motion suppression. It does not establish target-wrist improvement, general form/contact accuracy, or an adoption case. No outcome-based tuning was performed.

“Edge-only” means the whole coherent-edge package with legacy agreement: a same-frame normalized reference, current endpoint/parent eligibility, and neutral handling of unavailable geometry. It is not an ablation isolating the timestamp change alone. “Paired+edge” combines that package with the previously frozen paired-agreement package. The existing ratio bounds, confidence threshold, persistence count and default policies are unchanged.

Frozen [protocol](motion_edge_alignment_protocol_20261104.md), [synthetic parity](motion_edge_alignment_parity_20261104.json), [complete main microaggregates](motion_edge_alignment_results_20261104.json), [execution receipt](motion_edge_alignment_execution_20261104.json), and [input-score audit](motion_edge_input_score_audit_20261104.json). The first paired experiment (results commit `f1c10e8`, aggregate `89bb38131ccc96bbd527036c1973579c42679d27b37bd3b49697a55a76cdf3f0`) remains separate and unchanged.

## Execution and comparability

Home CPU/BLAS single-threaded replay completed **72/72 streams, nine policies, 42,052 frames and 648 saved outputs in 356.10 seconds**. It used no model inference, new video decoding, GPU, training, SMPL profiles, fresh labels or phone. All nine predictions were saved before parsing each sequence’s GT. GT bytes were prehashed against the historical manifest, then the parsed reference hashes were checked against those same expected hashes.

The original 60 clean streams retain their full saved lengths; each of six keypoint and six RGB stress streams retains exactly 270 frames. Online profile rows 21–80, activation at 81, and primary rows 90:end remain fixed. These are reused development streams, including historically named heldout material, not a new holdout.

| Scenario | Streams | Whole frames / joint-frames per policy | Primary frames / joint-frames per policy |
| --- | ---: | ---: | ---: |
| Clean | 60 | 38,812 / 659,804 | 33,412 / 568,004 |
| Keypoint stress | 6 | 1,620 / 27,540 | 1,080 / 18,360 |
| RGB stress | 6 | 1,620 / 27,540 | 1,080 / 18,360 |

All error denominators include invalid predictions. Coverage means the fraction without the existing invalid flag, not correctness. The full metric includes the root-relative pelvis zero for every policy. Means are weighted by joint-frame counts, not averaged across sequence means.

Every non-timing array of the original five policies matched its frozen first-experiment output exactly for all 72 sequences, including diagnostics and app-pose arrays. Historical G/H arrays were independently checked again. The explicitly permitted v3 raw-A extension remains only `expired_prediction_fallback`, verified all-false; no other missing field was allowed. First-five MPJPE, gain/suppression and recovery aggregate rows also match the first experiment exactly.

Final checks rehashed **832 input/source files** (including all 360 prior outputs) and **648 new output files** unchanged. All 1,080 scope/partition rows passed count/error-sum checks. The policy gate passed 33 focused Swift tests, original 720 outputs, prior 616 synthetic paired outputs and 1,388 new synthetic outputs across 19 cases; full Swift package: 338 tests, 4 skipped, 0 failures. Three separate harness tests cover the nine-policy matrix, diagnostic populations and exact-array rejection.

## Primary and whole-sequence errors

Errors are millimetres. The primary columns use rows 90:end; whole MPJPE retains every saved frame. Target/all covers every frame of the original prefix-selected lower-confidence target joints. It must not be confused with damaged targets.

| Scenario | Policy | Whole full MPJPE | Primary full MPJPE | Primary target/all MPJPE | Primary wrist MPJPE | Primary ankle MPJPE | Primary full coverage % |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Clean | Raw A | 141.375470 | 146.838965 | 248.669399 | 180.157684 | 258.068838 | 99.774 |
| Clean | Legacy G | 141.272229 | 146.757525 | 249.220295 | 180.095205 | 258.222102 | 96.783 |
| Clean | Paired G | 141.245791 | 146.732556 | 249.193596 | 180.099627 | 258.201791 | 96.615 |
| Clean | Edge G | 141.279684 | 146.746465 | 249.263690 | 180.104922 | 258.296247 | 98.209 |
| Clean | Paired+edge G | 141.250459 | 146.721246 | 249.239574 | 180.109881 | 258.241961 | 98.142 |
| Clean | Legacy H | 141.267784 | 146.749914 | 249.111975 | 180.023432 | 258.222102 | 96.786 |
| Clean | Paired H | 141.241377 | 146.724988 | 249.085276 | 180.028220 | 258.201791 | 96.618 |
| Clean | Edge H | 141.275117 | 146.738717 | 249.153520 | 180.031991 | 258.296247 | 98.211 |
| Clean | Paired+edge H | 141.245929 | 146.713542 | 249.129404 | 180.037316 | 258.241961 | 98.143 |
| Keypoint stress | Raw A | 154.093344 | 170.580420 | 308.355621 | 208.251725 | 355.998926 | 98.568 |
| Keypoint stress | Legacy G | 154.772153 | 171.539738 | 321.685665 | 213.697699 | 359.020172 | 91.236 |
| Keypoint stress | Paired G | 154.779773 | 171.625741 | 321.962760 | 213.631975 | 359.207083 | 90.076 |
| Keypoint stress | Edge G | 154.945298 | 171.620529 | 321.878271 | 213.776242 | 359.161903 | 94.020 |
| Keypoint stress | Paired+edge G | 155.026330 | 171.759750 | 321.962116 | 213.773703 | 359.217682 | 93.829 |
| Keypoint stress | Legacy H | 154.680812 | 171.391121 | 319.773911 | 212.423196 | 359.020172 | 91.258 |
| Keypoint stress | Paired H | 154.688432 | 171.477124 | 320.051006 | 212.357472 | 359.207083 | 90.098 |
| Keypoint stress | Edge H | 154.853958 | 171.471912 | 319.966517 | 212.501739 | 359.161903 | 94.041 |
| Keypoint stress | Paired+edge H | 154.934989 | 171.611133 | 320.050362 | 212.499200 | 359.217682 | 93.851 |
| RGB stress | Raw A | 155.285559 | 172.368741 | 304.051409 | 207.611331 | 356.881271 | 99.194 |
| RGB stress | Legacy G | 155.192471 | 172.170215 | 301.639890 | 207.318312 | 352.482529 | 93.306 |
| RGB stress | Paired G | 155.153092 | 172.185720 | 301.607293 | 207.216952 | 352.519072 | 92.320 |
| RGB stress | Edge G | 155.159830 | 171.942327 | 303.073426 | 207.410108 | 353.308308 | 96.383 |
| RGB stress | Paired+edge G | 155.176381 | 171.984826 | 303.040829 | 207.388334 | 353.341532 | 96.383 |
| RGB stress | Legacy H | 155.186190 | 172.149188 | 301.355776 | 207.128903 | 352.482529 | 93.312 |
| RGB stress | Paired H | 155.146811 | 172.164693 | 301.323179 | 207.027543 | 352.519072 | 92.326 |
| RGB stress | Edge H | 155.153550 | 171.921300 | 302.789312 | 207.220699 | 353.308308 | 96.389 |
| RGB stress | Paired+edge H | 155.170100 | 171.963799 | 302.756715 | 207.198925 | 353.341532 | 96.389 |

Edge-only versus legacy gains about 1.425–1.426 percentage points of clean coverage, 2.783 points in keypoint stress and 3.077 points in RGB stress. Primary full-joint MPJPE falls only about 0.011 mm clean, rises 0.081 mm in keypoint stress, and falls 0.228 mm in RGB stress. Target/all error rises in all three. Coverage gain is not evidence that newly accepted outputs are correct.

## Explicit package contrasts

Negative error deltas mean lower error; positive coverage deltas mean fewer invalid flags. “Add edge to paired” compares Paired+edge to Paired, not to legacy.

| Scenario | G/H | Contrast | Primary full Δ mm | Target/all Δ mm | Coverage Δ percentage points |
| --- | --- | --- | ---: | ---: | ---: |
| Clean | G | Edge vs legacy | -0.011060 | 0.043395 | 1.426046 |
| Clean | G | Add edge to paired | -0.011310 | 0.045978 | 1.526398 |
| Clean | G | Combined vs legacy | -0.036279 | 0.019280 | 1.358265 |
| Clean | H | Edge vs legacy | -0.011196 | 0.041546 | 1.424814 |
| Clean | H | Add edge to paired | -0.011446 | 0.044128 | 1.525165 |
| Clean | H | Combined vs legacy | -0.036372 | 0.017429 | 1.357033 |
| Keypoint stress | G | Edge vs legacy | 0.080791 | 0.192606 | 2.783224 |
| Keypoint stress | G | Add edge to paired | 0.134009 | -0.000644 | 3.752723 |
| Keypoint stress | G | Combined vs legacy | 0.220012 | 0.276451 | 2.592593 |
| Keypoint stress | H | Edge vs legacy | 0.080791 | 0.192606 | 2.783224 |
| Keypoint stress | H | Add edge to paired | 0.134009 | -0.000644 | 3.752723 |
| Keypoint stress | H | Combined vs legacy | 0.220012 | 0.276451 | 2.592593 |
| RGB stress | G | Edge vs legacy | -0.227887 | 1.433536 | 3.077342 |
| RGB stress | G | Add edge to paired | -0.200894 | 1.433536 | 4.063181 |
| RGB stress | G | Combined vs legacy | -0.185389 | 1.400939 | 3.077342 |
| RGB stress | H | Edge vs legacy | -0.227887 | 1.433536 | 3.077342 |
| RGB stress | H | Add edge to paired | -0.200894 | 1.433536 | 4.063181 |
| RGB stress | H | Combined vs legacy | -0.185389 | 1.400939 | 3.077342 |

## Actual damage, recovery and remaining targets

Partitions use actual saved joint-specific damage runs: first three damaged frames = onset, subsequent damaged frames = ongoing, first six undamaged frames after the run = recovery, truncated by the next damage, and all other frames = remaining. A one-frame outlier remains an onset. They are disjoint and exhaustive. Damaged-target means below combine **onset + ongoing sums/counts**, matching the historical denominator.

| Scenario | Policy | Damaged target joint-frames | Damaged target MPJPE | Damaged target coverage % | Recovery target MPJPE | Remaining target MPJPE |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Keypoint stress | Raw A | 544 | 336.019843 | 63.051 | 294.144973 | 290.613577 |
| Keypoint stress | Legacy G | 544 | 365.075126 | 1.103 | 301.765233 | 292.992124 |
| Keypoint stress | Paired G | 544 | 365.013504 | 1.103 | 303.567559 | 292.992096 |
| Keypoint stress | Edge G | 544 | 365.090019 | 1.103 | 302.887111 | 292.992124 |
| Keypoint stress | Paired+edge G | 544 | 365.011800 | 1.103 | 303.567559 | 292.992096 |
| Keypoint stress | Legacy H | 544 | 361.263959 | 1.103 | 299.529098 | 292.774168 |
| Keypoint stress | Paired H | 544 | 361.202338 | 1.103 | 301.331424 | 292.774140 |
| Keypoint stress | Edge H | 544 | 361.278852 | 1.103 | 300.650976 | 292.774168 |
| Keypoint stress | Paired+edge H | 544 | 361.200633 | 1.103 | 301.331424 | 292.774140 |
| RGB stress | Raw A | 536 | 319.747020 | 95.522 | 296.936689 | 294.154189 |
| RGB stress | Legacy G | 536 | 318.150181 | 83.396 | 290.966454 | 292.089024 |
| RGB stress | Paired G | 536 | 318.062606 | 83.396 | 290.966454 | 292.089024 |
| RGB stress | Edge G | 536 | 318.153215 | 83.396 | 295.865136 | 293.665034 |
| RGB stress | Paired+edge G | 536 | 318.065640 | 83.396 | 295.865136 | 293.665034 |
| RGB stress | Legacy H | 536 | 317.701306 | 83.396 | 290.547371 | 291.965340 |
| RGB stress | Paired H | 536 | 317.613732 | 83.396 | 290.547371 | 291.965340 |
| RGB stress | Edge H | 536 | 317.704340 | 83.396 | 295.446052 | 293.541350 |
| RGB stress | Paired+edge H | 536 | 317.616765 | 83.396 | 295.446052 | 293.541350 |

Edge-only slightly worsens damaged-target error in both stress scenarios (about +0.014893 mm keypoint, +0.003034 mm RGB). Its larger pooled RGB full-joint benefit is outside the desired target effect. Adding edge to the paired policy changes damaged-target errors by only about −0.001704 mm keypoint and +0.003034 mm RGB. Do not substitute target/all or pooled full-joint means for the damaged-target denominator.

## True-reference-motion proxy and recovery

Five-frame root-relative GT displacement >20 mm defines eligible motion pairs; gain <0.5 defines suppression. Invalid predictions remain included, and both endpoints must lie in the scoring window. These are scoring proxies, not contact/form labels. Recovery uses the unchanged requirement of three valid frames within `max(50 mm, clean raw XS error +20 mm)` before next damage, clip end or one second. Conditional mean recovery times are shown with event and censoring counts.

| Scenario | Policy | Mean gain | Suppressed % | Recovered / eligible | Mean recovered time ms | Full-1s unresolved / next-damage / clip-end censored |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Clean | Raw A | 0.778603 | 25.057 | 0/0 | — | 0/0/0 |
| Clean | Legacy G | 0.778166 | 25.624 | 0/0 | — | 0/0/0 |
| Clean | Paired G | 0.778496 | 25.596 | 0/0 | — | 0/0/0 |
| Clean | Edge G | 0.778058 | 25.662 | 0/0 | — | 0/0/0 |
| Clean | Paired+edge G | 0.778423 | 25.629 | 0/0 | — | 0/0/0 |
| Clean | Legacy H | 0.778263 | 25.605 | 0/0 | — | 0/0/0 |
| Clean | Paired H | 0.778593 | 25.577 | 0/0 | — | 0/0/0 |
| Clean | Edge H | 0.778163 | 25.643 | 0/0 | — | 0/0/0 |
| Clean | Paired+edge H | 0.778527 | 25.610 | 0/0 | — | 0/0/0 |
| Keypoint stress | Raw A | 0.799930 | 27.645 | 38/40 | 39.473684 | 2/0/0 |
| Keypoint stress | Legacy G | 0.783862 | 29.650 | 35/40 | 70.857143 | 2/2/1 |
| Keypoint stress | Paired G | 0.782928 | 29.707 | 35/40 | 74.285714 | 2/2/1 |
| Keypoint stress | Edge G | 0.782157 | 29.707 | 35/40 | 70.857143 | 2/2/1 |
| Keypoint stress | Paired+edge G | 0.779085 | 29.846 | 35/40 | 74.285714 | 2/2/1 |
| Keypoint stress | Legacy H | 0.784525 | 29.615 | 35/40 | 67.428571 | 2/2/1 |
| Keypoint stress | Paired H | 0.783592 | 29.673 | 35/40 | 70.857143 | 2/2/1 |
| Keypoint stress | Edge H | 0.782821 | 29.673 | 35/40 | 67.428571 | 2/2/1 |
| Keypoint stress | Paired+edge H | 0.779749 | 29.811 | 35/40 | 70.857143 | 2/2/1 |
| RGB stress | Raw A | 0.791064 | 28.751 | 30/32 | 41.333333 | 2/0/0 |
| RGB stress | Legacy G | 0.779865 | 30.260 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Paired G | 0.780477 | 30.260 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Edge G | 0.776136 | 30.410 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Paired+edge G | 0.776208 | 30.456 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Legacy H | 0.780118 | 30.249 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Paired H | 0.780729 | 30.249 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Edge H | 0.776388 | 30.399 | 29/32 | 61.379310 | 2/1/0 |
| RGB stress | Paired+edge H | 0.776461 | 30.445 | 29/32 | 61.379310 | 2/1/0 |

Adding edge to either agreement policy does not recover additional events or change their conditional recovery times/censoring. Mean gain decreases and suppression increases in all three scenario groups for both additions. The paired package’s slower keypoint recovery remains in the combined policy. Higher coverage therefore does not imply better recovery or preserved true motion.

## Exercise-specific contrasts

These primary deltas use each exercise’s unchanged denominator. “Edge” is versus legacy; “Add edge” is combined versus paired. Both G and H are retained.

| Scenario | Exercise | G/H | Contrast | Full Δ mm | Target/all Δ mm | Coverage Δ percentage points |
| --- | --- | --- | --- | ---: | ---: | ---: |
| Clean | barbell_row | G | Edge | -0.012349 | 0.028521 | 0.555058 |
| Clean | barbell_row | G | Add edge | -0.000773 | 0.028521 | 0.927584 |
| Clean | barbell_row | H | Edge | -0.012793 | 0.020967 | 0.551040 |
| Clean | barbell_row | H | Add edge | -0.001217 | 0.020967 | 0.923566 |
| Clean | pushup | G | Edge | 0.025306 | 0.088655 | 3.380959 |
| Clean | pushup | G | Add edge | 0.009998 | 0.095589 | 3.325899 |
| Clean | pushup | H | Edge | 0.025306 | 0.088655 | 3.380959 |
| Clean | pushup | H | Add edge | 0.009998 | 0.095589 | 3.325899 |
| Clean | squat | G | Edge | -0.031009 | 0.001861 | 0.911677 |
| Clean | squat | G | Add edge | -0.030858 | 0.001253 | 0.911677 |
| Clean | squat | H | Edge | -0.031009 | 0.001861 | 0.911677 |
| Clean | squat | H | Add edge | -0.030858 | 0.001253 | 0.911677 |
| Keypoint stress | barbell_row | G | Edge | 0.001240 | 0.000000 | 0.767974 |
| Keypoint stress | barbell_row | G | Add edge | 0.001139 | 0.000000 | 0.767974 |
| Keypoint stress | barbell_row | H | Edge | 0.001240 | 0.000000 | 0.767974 |
| Keypoint stress | barbell_row | H | Add edge | 0.001139 | 0.000000 | 0.767974 |
| Keypoint stress | pushup | G | Edge | 0.317416 | 0.375604 | 4.689542 |
| Keypoint stress | pushup | G | Add edge | 0.448797 | -0.010897 | 7.581699 |
| Keypoint stress | pushup | H | Edge | 0.317416 | 0.375604 | 4.689542 |
| Keypoint stress | pushup | H | Add edge | 0.448797 | -0.010897 | 7.581699 |
| Keypoint stress | squat | G | Edge | -0.076283 | 0.019216 | 2.892157 |
| Keypoint stress | squat | G | Add edge | -0.047910 | 0.019218 | 2.908497 |
| Keypoint stress | squat | H | Edge | -0.076283 | 0.019216 | 2.892157 |
| Keypoint stress | squat | H | Add edge | -0.047910 | 0.019218 | 2.908497 |
| RGB stress | barbell_row | G | Edge | -0.006483 | 0.000000 | 2.908497 |
| RGB stress | barbell_row | G | Add edge | -0.007763 | 0.000000 | 2.908497 |
| RGB stress | barbell_row | H | Edge | -0.006483 | 0.000000 | 2.908497 |
| RGB stress | barbell_row | H | Add edge | -0.007763 | 0.000000 | 2.908497 |
| RGB stress | pushup | G | Edge | -0.604002 | 2.867072 | 3.431373 |
| RGB stress | pushup | G | Add edge | -0.549864 | 2.867072 | 6.372549 |
| RGB stress | pushup | H | Edge | -0.604002 | 2.867072 | 3.431373 |
| RGB stress | pushup | H | Add edge | -0.549864 | 2.867072 | 6.372549 |
| RGB stress | squat | G | Edge | -0.073178 | 0.000000 | 2.892157 |
| RGB stress | squat | G | Add edge | -0.045054 | 0.000000 | 2.908497 |
| RGB stress | squat | H | Edge | -0.073178 | 0.000000 | 2.892157 |
| RGB stress | squat | H | Add edge | -0.045054 | 0.000000 | 2.908497 |

**Do not call the RGB pushup full-joint reduction target-wrist improvement:** edge-only full MPJPE falls 0.604002 mm while target/all rises 2.867072 mm. Combined versus legacy target/all rises 2.801575 mm. Keypoint pushup combined versus legacy full error rises 0.775858 mm. Pooled means obscure those conflicts. Targets retain the historical wrist/ankle selection; none are independently labeled form faults.

## Edge evidence and its limitations

Whole-stream gate counts follow. “Unavailable” sums the explicit missing-parent, missing-child, missing-reference, missing-scale and no-parent reasons. Neutral unavailable geometry is not a known-consistent edge. The change preserves the existing agreement-or-persistence path when this optional veto lacks evidence, so it can still accept an erroneous persistent observation.

| Scenario | Policy | Evaluated large-innovation gates | Known consistent | Known inconsistent | Missing child / parent / reference / scale / no-parent | Conditional age count | Conditional mean age s | Conditional max age s |
| --- | --- | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| Clean | Edge G | 5374 | 1863 | 213 | 2086/1212/0/0/0 | 2076 | 0.625896 | 13.920000 |
| Clean | Paired+edge G | 5834 | 1832 | 405 | 2387/1210/0/0/0 | 2237 | 1.070076 | 13.920000 |
| Clean | Edge H | 5363 | 1857 | 213 | 2085/1208/0/0/0 | 2070 | 0.626802 | 13.920000 |
| Clean | Paired+edge H | 5823 | 1826 | 405 | 2386/1206/0/0/0 | 2231 | 1.072111 | 13.920000 |
| Keypoint stress | Edge G | 364 | 201 | 0 | 72/91/0/0/0 | 201 | 0.244577 | 1.200000 |
| Keypoint stress | Paired+edge G | 396 | 201 | 0 | 78/117/0/0/0 | 201 | 0.243184 | 1.200000 |
| Keypoint stress | Edge H | 360 | 199 | 0 | 70/91/0/0/0 | 199 | 0.241508 | 1.200000 |
| Keypoint stress | Paired+edge H | 392 | 199 | 0 | 76/117/0/0/0 | 199 | 0.240101 | 1.200000 |
| RGB stress | Edge G | 355 | 172 | 1 | 70/112/0/0/0 | 173 | 0.132832 | 1.200000 |
| RGB stress | Paired+edge G | 359 | 174 | 1 | 70/114/0/0/0 | 175 | 0.134971 | 1.200000 |
| RGB stress | Edge H | 355 | 172 | 1 | 70/112/0/0/0 | 173 | 0.132832 | 1.200000 |
| RGB stress | Paired+edge H | 359 | 174 | 1 | 70/114/0/0/0 | 175 | 0.134971 | 1.200000 |

Age statistics condition **only on known-consistent/inconsistent geometric comparisons at evaluated large-innovation gates**. They are not ages of every stored reference or every evaluated gate. The observed maximum 13.92 seconds is consistent with the predeclared continuous-session lifetime: no new age cutoff was introduced. It does not make an old reference a current observation.

Known parent/child eligibility and scale availability do not establish correct anatomy. The inherited scale calculation retains its original confidence clipping, including the documented positive-infinity leg-score behavior. A separate, read-only audit found zero NaN or ±infinity values among **1,093,352 saved detector scores** and **252,312 mapped H36M leg scores** across these exact 72 whole streams. The same audit is broken down by scenario, exercise and scoring window in its JSON and rechecks the run’s input hashes. Absence of such scores here does not fix or validate that inherited behavior for future inputs.

Agreement counters remain unknown/null when the unmodified legacy policy does not record them; edge counters are unknown/null for non-edge policies. Full scenario × exercise mechanism counts, decision changes, conditional reference-age statistics and both scoring windows remain in the main JSON. Angle, jitter and uncertainty diagnostics are handled by the separate predeclared saved-output supplement, not by altering this main run.

## Boundary and retained evidence

The coherent-edge synthetic witnesses fix a documented mixed-time reference failure under their defined conditions. This saved-data comparison shows a coverage/error/motion tradeoff, not universal improvement. Keep edge and agreement candidates optional, and do not merge, deploy, change models/defaults or claim independent holdout/form/contact accuracy from this experiment. No outcome-driven parameter change or rerun was used.

Private Home root: `~/bpt-runs/motion-edge-alignment-20261104-nine-policy/`. Frozen `code/`, `results/predictions_HOME_ONLY/`, `results/sequences_HOME_ONLY/`, `results/manifest_HOME_ONLY.json` and `run.log` remain there. Only the aggregate main report, a nonidentifying execution receipt and confidence-count audit were exported. Prior paired-experiment Home files were read and rehashed unchanged.

Aggregate SHA256: `06e432973dada120c5bb3b09fcbc234d1b39ed7a4405cfc981d2426160825849`.
