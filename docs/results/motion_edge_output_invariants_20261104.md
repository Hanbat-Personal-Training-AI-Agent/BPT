# Saved-output observation and withholding audit — 2026-11-04

This separate read-only audit checks the completed nine-policy run’s saved arrays. It does not change the main/supplemental results, rerun an estimator, use GT, or establish real exercise-form false negatives. NumPy/CPU only; no new inference, algorithm change or threshold tuning.

All **648 prediction NPZ hashes** match the closed manifest. The saved `raw_model` arrays exactly match the original immutable sources for **648/648 policy-sequences**, drawn from 72 raw sources: clean cache `L5`, or the saved stress scenario’s `raw`. Those 72 source NPZ hashes are unchanged too.

## Coordinate semantics

The frozen v4 runner subtracts the current raw pelvis, converts root-relative coordinates into image-height units for the estimator, then divides back into crop/model units. Thus equality to the uncentered `raw_model` is not the intended passthrough contract. Original-array preservation and root-relative normalization are separate claims.

For the runtime window, the measured global maximum direct passthrough difference **0.23887377977371216** exactly equals the saved raw pelvis’s maximum absolute component **0.23887377977371216**. The larger direct difference is the retained uncentered-to-pelvis-centered translation, not a changed original file. The maximum centered-raw difference is **1.1102230246251565e-16** for both passthrough and expired fallback, consistent with the runner’s multiply/divide floating-point roundtrip. Differences are in **crop/model units**, not metres or millimetres. No physical-accuracy or numerical pass threshold was introduced.

Exact nonzero centered differences are reported, not rounded to zero: runtime passthrough has **1,105,886** such joint-frames and fallback has **15,808**. All selected comparison coordinates are finite.

## Measured masks and differences

The following counts sum **all nine policies** across all 72 streams, so they are policy-joint-frame counts, not unique physical observations. Windows overlap and must not be added. Runtime excludes warmup rows 0–20; primary is rows 90:end. Full policy × scenario × exercise × window rows are in [the JSON receipt](motion_edge_output_invariants_20261104.json).

| Window | Joint-policy frames | Passthrough frames | Passthrough ∩ prediction | Prediction-used / valid prediction | Expired fallback / valid fallback | Centered nonzero: passthrough / fallback |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 21:end | 6,202,620 | 5,264,716 | 0 | 145,402 / 0 | 80,726 / 0 | 1,105,886 / 15,808 |
| 90:end | 5,442,516 | 4,616,306 | 0 | 129,620 / 0 | 78,458 / 0 | 963,594 / 15,400 |

| Window | Direct-raw passthrough max | Centered-raw passthrough max | Direct-raw fallback max | Centered-raw fallback max |
| --- | ---: | ---: | ---: | ---: |
| 21:end | 0.23887377977371216 | 1.1102230246251565e-16 | 0.23353508114814758 | 1.1102230246251565e-16 |
| 90:end | 0.23887377977371216 | 1.1102230246251565e-16 | 0.23353508114814758 | 1.1102230246251565e-16 |

Per-policy runtime counts, summed across scenarios/exercises without double counting the exercise subtables:

| Policy | Passthrough frames | Prediction-used frames | Prediction ∩ valid | Expired fallback frames | Fallback ∩ valid |
| --- | ---: | ---: | ---: | ---: | ---: |
| A | 0 | 0 | 0 | 0 | 0 |
| legacy_G | 654,227 | 22,746 | 0 | 14,554 | 0 |
| legacy_H | 654,244 | 22,727 | 0 | 14,542 | 0 |
| paired_G | 653,129 | 24,113 | 0 | 15,919 | 0 |
| paired_H | 653,146 | 24,094 | 0 | 15,907 | 0 |
| edge_G | 662,579 | 12,716 | 0 | 4,672 | 0 |
| edge_H | 662,589 | 12,704 | 0 | 4,667 | 0 |
| paired_edge_G | 662,396 | 13,157 | 0 | 5,235 | 0 |
| paired_edge_H | 662,406 | 13,145 | 0 | 5,230 | 0 |

Every prediction-used frame is invalid in the saved estimator output; every expired fallback is invalid and still marked prediction-used. `passthrough ∩ used_prediction` and `fallback without used_prediction` are zero in both windows. Raw A has no adaptive-passthrough mask; its zero in that column is not a claim that its raw array was lost. Its raw source equality was checked separately.

## What the flags mean

The inspected historical estimator marks `used_prediction` for rejected/missing observations and applicable contact/kinematic corrections. Expired prediction explicitly falls back to the current raw coordinates but retains `used_prediction=true` and invalidation. Therefore `used_prediction` does not mean coordinates must differ from raw. The final invalid mask explicitly includes the prediction-used mask. The source’s observation-passthrough mask applies to accepted reliable adaptive G/H observations.

This confirms the saved observation-preservation/withholding behavior for these arrays and coordinate conventions. It is not a proof that every downstream consumer gates correctly, nor an independent human form label, clinical error rate or real-form FN result. No exception was converted to zero: direct-raw translation, centered roundoff counts and nullable empty-mask maxima are all retained.

Frozen manifest SHA256: `9a8c32a150c7a42ab0f43310a6b01f9618cfa340e1ac4c8c58ef78717c2c80a3`. Main aggregate SHA256: `06e432973dada120c5bb3b09fcbc234d1b39ed7a4405cfc981d2426160825849`. Audit source SHA256: `f3275587382f6319d3bbc948d6b7fb7f526de11b4bd6e6742be007779839c580`. Audit receipt SHA256: `e0b88a7fb49c48f4dd887214fe3cd7caeb7212cf715553f096ef0b1e1628103f`.

Home-only receipt: `~/bpt-runs/motion-edge-alignment-20261104-nine-policy/output-invariants.json`; script in that root’s `audit-code/`. Original NPZ files and main/supplemental results were not modified.
