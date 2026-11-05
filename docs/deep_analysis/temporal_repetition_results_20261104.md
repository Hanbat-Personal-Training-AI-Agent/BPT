# Saved Fit3D temporal repetition evaluation — 2026-11-04

**The old net-count proxy hides unmatched events, but these overlap results are not validated repetition-boundary accuracy.** The frozen IoU≥0.50 comparison found one missed and one extra interval for B/C row even though both counts were exactly 27. On the three exercises with A available, A and B/C each matched 74/77 dataset intervals; A had 3 unmatched predictions and B/C had 5. Deadlift overlap is much lower, including for the mocap control. A separate post-result diagnostic identified a major phase mismatch there: 21/26 dataset intervals run between low hip-angle phases, whereas the instrumented counter interval runs high→low→high.

The [protocol](temporal_repetition_protocol_20261104.md) was committed as `8676a8c` before reading temporal outcomes. The [machine-readable aggregate](temporal_repetition_20261104.json) preserves every predeclared threshold and all denominators. This is a **dataset-reference temporal agreement** analysis of the unchanged legacy signal counter, not the application's live repetition state machine, form correctness, expert labels, or a new adoption test.

## Definition and annotation audit

The original `count()` emits a number, not intervals. The new instrumentation preserves its signal processing and every count decision, and gives each counted dip a new operational interval: the last sample above 0.65 before entering below 0.35 through the first subsequent sample above 0.65. This is an **excursion window**, which excludes the adjacent high plateaus. Its endpoints must not be described as legacy emitted repetition boundaries. The existing end-of-clip partial rule is retained and tagged.

Sample times are original `pick[i]/50`, with the original numpy rounding, rather than uniformly assuming `i/30`. Dataset boundaries are used directly as source-frame timestamps. Intervals are half-open; an instant shared by adjacent intervals adds no overlap. Pair eligibility is inclusive IoU≥0.50. Exact rational min-cost maximum matching first maximizes match count, then summed IoU, then minimizes summed endpoint absolute error; fixed graph iteration resolves ties. Augmentation reassigns earlier pairs when needed. It cannot reuse either interval.

All 20 jobs' annotations exactly matched current `rep_ann.json`. Boundaries were strictly increasing finite integers within source-frame bounds. The [official dataset description](https://fit3d.imar.ro/fit3d) confirms repetition time intervals and synchronized 50fps data, but does not establish frame-index origin, endpoint inclusion or anatomical phase for these arrays. Those structural checks do not prove semantic equivalence to the new excursion definition. The phase diagnostic below makes this limitation measurable.

## Frozen results

Each cell is **matched / missed / extra** at IoU≥0.50. Each exercise has five videos; row has 27 references, deadlift 26, and squat/pushup 25 each. “Extra” means unmatched against these reference intervals, not necessarily a false physical repetition.

| Exercise | A2D | A | B | C (oracle focal) | Mocap control |
|---|---:|---:|---:|---:|---:|
| Squat | 20 / 5 / 6 | 25 / 0 / 2 | 23 / 2 / 4 | 23 / 2 / 4 | 25 / 0 / 2 |
| Row | 21 / 6 / 4 | 24 / 3 / 1 | 26 / 1 / 1 | 26 / 1 / 1 | 26 / 1 / 1 |
| Pushup | 25 / 0 / 0 | 25 / 0 / 0 | 25 / 0 / 0 | 25 / 0 / 0 | 23 / 2 / 2 |
| Deadlift | unavailable | unavailable | 5 / 21 / 27 | 5 / 21 / 27 | 4 / 22 / 28 |

The pooled 15-video comparison uses the same squat/row/pushup videos and 77 references for every variant:

| Variant | Predicted | Matched | Missed | Extra | Precision | Recall | F1 | Matched/(reference+extra) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A2D | 76 | 66 | 11 | 10 | 86.84% | 85.71% | 86.27% | 75.86% |
| A | 77 | 74 | 3 | 3 | 96.10% | 96.10% | 96.10% | 92.50% |
| B | 79 | 74 | 3 | 5 | 93.67% | 96.10% | 94.87% | 90.24% |
| C | 79 | 74 | 3 | 5 | 93.67% | 96.10% | 94.87% | 90.24% |
| Mocap control | 79 | 74 | 3 | 5 | 93.67% | 96.10% | 94.87% | 90.24% |

For all 20 videos, B/C each have 111 predictions, 79 matches, 24 misses and 32 extras against 103 references (precision 71.17%, recall 76.70%, F1 73.83%, overlap score 58.52%). Their legacy net-count proxy is 92.79%; the difference demonstrates why a count proxy cannot substitute for interval correspondence. A/A2D's all-available aggregate covers only 15 videos, so it must not be directly compared with that 20-video total.

Matched-only mean absolute start/end differences in seconds are below. Their denominator is the matched count in the first table; unmatched intervals do not receive zero error.

| Exercise | A start / end | B start / end | C start / end | Mocap start / end |
|---|---:|---:|---:|---:|
| Squat | .566 / .383 | .561 / .411 | .561 / .410 | .587 / .415 |
| Row | .298 / .373 | .305 / .352 | .306 / .354 | .305 / .365 |
| Pushup | .290 / .226 | .271 / .184 | .266 / .189 | .262 / .230 |
| Deadlift | unavailable | .552 / .444 | .560 / .444 | .590 / .440 |

All-20 B signed start/end means are +.383/−.310s (start later, end earlier than the paired reference), with absolute-error p95 .868/.562s. C is +.382/−.309s, p95 .868/.560s. This reflects both signal differences and the chosen excursion convention; it is not an inference-latency measurement or validated boundary error. The JSON includes median/p95 and A2D statistics as well.

Predeclared IoU sensitivity, total matched intervals (not a new criterion):

| Available cohort | Variant | ≥.25 | ≥.50 primary | ≥.75 |
|---|---|---:|---:|---:|
| 15 videos / 77 references | A2D | 75 | 66 | 11 |
| 15 videos / 77 references | A | 75 | 74 | 11 |
| 20 videos / 103 references | B | 92 | 79 | 15 |
| 20 videos / 103 references | C | 92 | 79 | 16 |
| 20 videos / 103 references | Mocap control | 91 | 78 | 8 |

## Post-result phase/dwell diagnosis, without rescoring

After the frozen results, a [separate diagnostic protocol](temporal_phase_diagnostic_protocol_20261104.md) specified angle-phase and dwell measurements. Its [original aggregate](temporal_phase_diagnostic_20261104.json), supplemented by [paired endpoint/run counts](temporal_phase_paired_diagnostic_20261104.json) during review, uses mocap joints only; no reference input was fed to a prediction model, and no original interval, threshold or score was altered.

| Exercise | Reference endpoints high/high | Low/low | Middle/middle | High→middle / middle→high | One low run / two low runs |
|---|---:|---:|---:|---:|---:|
| Squat | 25/25 | 0 | 0 | 0 / 0 | 25 / 0 |
| Row | 27/27 | 0 | 0 | 0 / 0 | 27 / 0 |
| Pushup | 20/25 | 0 | 1/25 | 2 / 2 | 25 / 0 |
| Deadlift | 5/26 | 21/26 | 0 | 0 / 0 | 5 / 21 |

“High” is strictly >.65 and “low” strictly <.35 on the very same smoothed, clip-normalized angle signal. Deadlift uses hip interior angle; squat knee and row/pushup elbow. In deadlift, the 21 low/low intervals also contain two separated low runs. This is direct evidence that most dataset deadlift intervals cross the opposite cycle phase to the newly instrumented high→low→high excursions. The pattern is absent in squat/row, and mixed within deadlift, so assuming one universal annotation phase would be unsound. It explains why low overlap of both model and mocap control cannot be attributed solely to model error.

For squat/row/pushup, the instrumented window also omits high-angle dwell: mean reference durations are 2.562/1.999/1.634s, while mean emitted excursion durations are 1.551/1.307/1.191s. For each reference's best-overlap mocap excursion, mean duration/reference ratios are .611/.662/.797; mean start shifts +.587/+.320/+.207s, end shifts −.415/−.372/−.171s. Thus the narrower operational window contributes directly to endpoint and high-IoU differences even in the expected cycle phase.

For deadlift, mean reference duration is 3.145s, mean emitted excursion 2.024s, and mean best-overlap ratio .596 with mean IoU .299. Adjacent contiguous high plateaus omitted from its emitted windows average 1.532s before and 1.448s after. These plateau spans can include setup and pauses or cross neighboring reference boundaries; simply adding them is not a validated repair. They were measured for explanation only and were never rematched. The full diagnostic JSON retains analogous dwell measurements for every exercise.

## Coverage, provenance and reproduction

- Completed 20/20 saved jobs, 22,245 original frames, all 13,350 expected picked samples and all 103 reference intervals. No common-prefix truncation, censored reference/prediction, nonfinite angle interpolation, or terminal partial event occurred. A/A2D are absent for all five deadlift jobs.
- Ninety variant/video counts exactly matched both the unchanged counter and the saved legacy score. All inputs and source hashes remained unchanged before/after the evaluation. Four B/C predictions per variant were fully outside the annotated span (two squat, two deadlift); these remain in the declared extra denominator because the full clip was evaluated, but may represent unannotated activity.
- Private per-video/per-event data and named hash manifest remain on Home at `~/bpt-runs/temporal-repetition-20261104-sol/final/events_private.json`. Only aggregate JSON and anonymous input hashes were copied into this repository. The first attempt's serialization failure and partial newly-created output were preserved separately in the parent directory; the successful run used a distinct `final/` directory.
- Runtime: Python 3.11.15, NumPy 1.26.4. The source hash manifest, code hashes, protocol SHA256 and anonymous input hashes are embedded in the aggregate. Primary protocol SHA256: `5462abdf025c8d821d6a5b9411ba784a49b780d11c3815e6f0bbb9bc7ab4e6e4`; evaluated script SHA256: `84c7b99c211bce943fd35eb9541fad79ebcab3ae37c4c64d1c26661631eabfce`.
- Existing historical provenance limits still apply: some predictions were reused without original video-byte hashes; sampled array order was inferred from the frozen runner and lengths. No new inference, training, GPU job, paid cloud use, or dataset upload occurred. Existing arrays, jobs, score files and frozen sources were never changed.

Run on the machine holding the private inputs, using a new output path:

```sh
python eval_temporal_repetitions.py \
  --run "$HOME/bpt-runs/gvhmr-eval-20261026" --root "$HOME/datasets/fit3d" \
  --protocol temporal_repetition_protocol_20261104.md \
  --private-out events_private.json --out aggregate.json
```

The new evaluator imports the **saved run's** original angle code and counter, not current product code. The standalone phase script takes the same `--run`/`--root`, its separate `--protocol`, and `--out`. Both use exclusive output creation. Local verification: `python3 -m unittest discover -s scripts/deep_analysis/tests -p test_temporal_repetitions.py -v` — **8 passed**, including randomized legacy-count parity, exact cutoff/shared endpoint cases, duplicate prevention, a greedy-failure reassignment, cancellation at equal counts, and 80 independently exhaustively enumerated optimal matching comparisons. The actual private-data run additionally passed all 90 count/score parity checks and before/after hash checks.

These previously inspected recordings and tiny exercise cohorts are not independent validation. Camera selection used mocap; C uses oracle camera intrinsics; A and B/C have different future-context conditions. Count/timing agreement provides no posture-accuracy evidence. The previous [GVHMR rejection/limitations](gvhmr_fit3d_20261026.md) remain unchanged; this work resolves the missing temporal audit without asserting a new detector or a pass.


## Review corrections and additional provenance

Review found that the original private output stored the full `events` list while its matching `pairs` indexed the censor-filtered prediction list. The original run had zero censored events, so its pairs and numeric results are unaffected. The corrected evaluator now stores `scored_events`, an explicit `scored_event_original_indices` mapping, and a `pair_index_convention`; its output schema is 2. A regression removes the first of three events and verifies both matching-pair identity and mapping back to the original list. Nine tests now pass. The published primary aggregate remains the actual original schema-1 run and was not regenerated or relabeled.

Review also found that the initial phase table incorrectly inferred paired endpoint states from separate start/end marginals. A bounded rerun saves joint `(start state, end state, low-run count)` counts in `temporal_phase_paired_diagnostic_20261104.json`. It confirms exactly 21 deadlift low/low two-run intervals and five high/high one-run intervals; squat and row conclusions are unchanged. It **corrects pushup** from the initial unsupported 22 high/high and three middle/middle claim to **20 high/high, one middle/middle, two high→middle, two middle→high**, each with one low run. The table above uses these joint counts. All previous numeric diagnostic metrics and all previously saved marginal counts compare exactly equal on the rerun.

New output: Home `~/bpt-runs/temporal-repetition-20261104-sol/review-fix/phase_diagnostic_paired.json`. Existing source data, original scripts and outputs remain untouched. New diagnostic script SHA256: `99d9072d95272b0230330ebba96ac39e8e169c03e11626d6fad04613fc7b8ae4`; corrected evaluator/helper SHA256: `81355c040bd2a7c696ea14870af12370abe6ef749f74d24f1f2aa62bccd92a39`. Both are embedded in the paired aggregate, which uses the unchanged diagnostic protocol and before/after input hashes.

The original Home files' SHA256 values were checked before and after this rerun and were identical:

- Primary aggregate: `bb8c3424bf7291e621e3a40313d87aa4d431decf4cf37a79dd79aa5f83ee3b5a`.
- Original phase aggregate: `72ab03034666d88a87e3267f75dfc0e195abde37cee446f5ecc8495fc11bbcdf`.
- Private event output: `8331f077228d097e8a2ade60f66ed4e6082264a3d1b70320ebab8014098f233d`.
