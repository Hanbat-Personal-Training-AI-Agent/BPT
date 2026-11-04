# Four-policy phase replay supplement — frozen pre-outcome scope

Frozen on 2026-11-04 before inspecting any new phase replay outcomes. This is a supplemental scorer for already-saved predictions, not a new estimator experiment. It reuses the exact arithmetic and original scope of the earlier edge supplement; no metric tuning, new data selection, model calls or candidate changes are authorized.

## Closed-run gate and source reuse

The adapter may run only after the main phase replay has a closed PASS manifest/aggregate for 72 streams, 42,052 frames and exactly `A`, `legacy_G`, `legacy_H`, `accepted_phase_H`. Require matching externally supplied main manifest/aggregate hashes, main protocol SHA `234f0a77436bd699b2455194fb2f8adbf4d5bda142084743f552bfd285187afb`, and true legacy parity, non-row H/G controls, input/prediction preservation and save-before-GT flags. Require all 288 saved prediction and phase sidecar paths/hashes and exact stream-policy completeness. The closed input manifest must also contain native phase protocol SHA `0c7f7c18138287827f66e61f7914c767da79f6ac3e644d1e4927fbade65b85c9`.

Import only `collect`, `PooledSamples` and the fixed angle-index table from the unchanged prior `supplemental_score.py`, SHA-256 `d649a2325b3484135693e7e3216421fce591e77f0059b5fe6a7e002c8573c0b4`. Do not call its old nine-policy `execute` entrypoint. The adapter changes only manifest/policy routing and result metadata. The shared `collect` implementation remains unmodified. Historical metric source SHA is `baf5827535651854918be66ab569ff3113df7d6e126ce5504dac8de16b775f89`; data loader SHA is `79fdfa4bf49a2c5c656f1e0b8e62dd1d0895a3b57a0a6d6f8306a26a3c3f1711`. Verify these and the closed main input manifest before loading observations/reference data.

Rehash all source/input/prediction/phase files before and after scoring. Use the already-saved raw/corrected/uncertainty/invalid arrays and the same frozen observation/crop/timestamp and GT-score reference files. GT and camera-up are scorer-only; no estimator is constructed or invoked. Keep all arrays and pooled scalar samples on Home; transfer only aggregates and hash receipts. CPU/BLAS threads remain one.

## Unchanged supplemental arithmetic and scope

The scope remains **primary rows 90:end**, scenario × exercise (plus all exercises), with no new full/target supplemental partitions. The main replay already supplies whole/primary full/target position errors and assessment-mask coverage; refer to its exact closed aggregate rather than redefine them here. Derivatives are computed on the full original sequence before applying the primary-row mask.

- Seven angular MAEs: left/right knee, elbow and hip, plus torso, in degrees, using the original `pose_angles` function and coordinate conversion. Hip/torso are not lumbar-flexion ground truth. Separate expected frames, finite errors, nonfinite prediction/reference coordinates, and finite-coordinate-but-degenerate angles.
- Velocity and acceleration error against GT (mm/s and mm/s²), plus predicted jerk magnitude (mm/s³), using the original repeated `derivative` calls. Jerk is a derivative proxy and can decrease when motion is suppressed; it is not form correctness.
- Nominal 95% coordinate coverage uses exactly `1.96 × sigma`, with finite positive sigma eligibility. Retain expected, eligible, finite-eligible and covered coordinate counts, and both covered/eligible and finite-conditional ratios. Raw A sigma is the existing confidence/body-scale heuristic, not an XS posterior. None of the policies' intervals are assumed calibrated.
- Observed-still support-screen speed uses the original image reconstruction/projection, speed <0.02 image-height/s, score ≥0.45, wrists+ankles for pushup and ankles otherwise. `expected_samples` counts observed-still eligible samples; `candidate_support_joint_frames` is the outer support denominator. This is not verified physical contact.

Reuse original scalar sum/count accumulation and exact pooled p50/p90/p95 across actual finite samples. Never average per-sequence means or quantiles. Means are conditional on finite samples. Assessment-mask valid/invalid counts may be summed directly for the same primary joint-frame denominator as an explicit audit; masks must not filter the scalar metrics or be labeled correctness.

## Reporting and preservation

Report all four policies by scenario/exercise, numerical differences with denominators and limitations, and the main full/target position-error context. Preserve positive and negative findings; do not tune or activate the candidate from this reused development data. Record the adapter/protocol/source hashes, closed-run hashes, rehash counts, environment and elapsed time. The earlier paired/edge results, existing raw data and main replay artifacts remain untouched. Save to a new uniquely named supplemental directory only.

Pre-execution identity clarification: the initially supplied `205958…` main-protocol hash was the pre-binding revision. The closed run uses final source/receipt-binding commit `4861796` and protocol SHA `234f0a77436bd699b2455194fb2f8adbf4d5bda142084743f552bfd285187afb`. The runner owner confirmed this before this supplement read any outcome values. This correction changes only run identity; the frozen arithmetic, scope, source selection and denominators above are unchanged.
