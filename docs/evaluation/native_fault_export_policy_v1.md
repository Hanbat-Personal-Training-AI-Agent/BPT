# Native fault export support policy v1 (pre-outcome)

This exporter consumes `bpt-native-fault-trace-v1` facts from the real native judge. It does not reconstruct decisions from warning lists, delivery-assessed sets, or quiet-key settings. All 20 existing core-three rule IDs are handled below. Missing required facts yield an explicit withholding reason; an unknown rule/trace contract is rejected. This is an execution/evidence contract, not a validated biomechanical or human-label rubric.

A trace starts intentionally unbound to an annotation task because its actual native rep boundaries do not exist yet. Candidate/build/source/executable/full-clip identity and the declared input ledger are bound before judging. `prepare` creates a NEW development-only task containing every native rep × every native rule, unknown labels and missing predictions. Its boundary manifest records the exact trace hash, run/rep trace IDs and source endpoints (`ai_windows`). `export` then binds that frozen manifest/protocol/boundary to the original immutable trace. The old 588-row task is neither accepted as an automatic matching target nor modified.

## Common checks

- Clean writer closure is required. Truncated JSONL, missing footer, cap/write failure, duplicate sequence or source identities, inconsistent counts, or unsupported schema reject the trace. Clean writer closure does not imply complete source coverage.
- The exact header candidate, every declared runtime source hash and build manifest, actual executable bytes and actual full source clip bytes must match. Filename similarity is not identity. Current source hashes must agree with the frozen candidate's Git blobs.
- The final CLI receipt must bind the same trace bytes/run, stable full source bytes before/after execution, and stable model artifacts. The exporter rehashes the actual executable, models, source clips and trace inputs before and after processing. These are local execution attestations, not externally signed records or an independent rerun of geometry.
- The full expected ingress manifest and actual frame/source records establish per-window coverage. A missing unrelated source elsewhere in the clip does not erase a sufficient positive witness. A negative requires the entire target window and every relevant search/reference scope to be covered. Failed ingress, unknown rational time, flush-derived output, missing 3D or side changes are never healed by bounding endpoints.
- Every nonmissing export refers to the exact selected native source (`2d` or `3d`), called rule, exact operands, aggregation contributors/selectors and pre-append history. Execution-enabled and delivery-enabled remain separate. An uncalled/disabled rule is never a negative.
- Positive evidence requires the actual predicate to have fired. Its actual support/witness must lie wholly inside the frozen target window; the exporter never clips an overhanging native witness into a new one. A false predicate requires complete relevant support. `nil`, insufficient support and known failed eligibility gates remain withheld; absent rep/rule evidence remains missing.
- Every consumed history entry must resolve to its earlier trace ID, same source/side contract and recorded metric value. Missing history IDs are not repaired from values or rep numbers. Prefix/baseline/trend order and multiplicity are preserved.
- Historical reference quantities carry their own view/input support checks; current-rep eligibility cannot stand in for a reference rep. A true branch attempt which fails support leaves no witnesses in a later successful OR/max-reference attempt.
- Finite 2D facing state alone is insufficient. The recorded establish/confirm/candidate/flip observations must have finite, confident nose/ear dependencies, starting from a captured initial state or explicit reset. Cached orientation may continue without a face observation; a finite confirming observation can re-establish support. A finite 3D up vector proves the native numeric camera-reference contract only, not verified physical gravity.
- Exact native phases are used, not overlay phase aliases. `bottom`/`top` requirements below require that observed phase with the relevant finite quantity inside the aggregation search scope. `any` means the native rule has no phase-specific selector, not that a phase was guessed.

## All-rule support table

“Complete search” means all ledger frames in the actual native selector scope are present and have the relevant finite quantities, including the required phase. “Witness” uses the actual selected extrema/reference contributors, not a newly recomputed favorable subset. Negative exports additionally require full target-window coverage and known eligible view throughout. The positive side may use only the relevant eligible witness where its predicate is monotone under missing unrelated samples.

| Rule | Actual native decision | Positive support | Negative support / phase |
| --- | --- | --- | --- |
| pushup_hip_sag | hip_dev_max > threshold | Actual finite maximum witness; missing unrelated samples cannot erase an observed excess | Complete hipDeviation search; any phase |
| pushup_hip_pike | hip_dev_min < -threshold | Actual finite minimum witness | Complete hipDeviation search; any phase |
| pushup_shallow | current elbow_min − first-N median > threshold | Complete current elbow minimum search and exact first-N references, each complete | Same complete searches; bottom |
| pushup_no_lockout | historical/current elbow_max − current elbow_max > threshold | Complete current elbow maximum/top search; actual finite maximal reference witness can prove an excess even if another historical search is incomplete | Complete current and every offered historical maximum search, including rows compactMap omitted; top |
| pushup_head_drop | head_dev_change_max > threshold | Actual max and actual first-available headDeviation reference; source prefix proving the reference is first available | Complete headDeviation search; any phase |
| pushup_head_up | head_dev_change_min < -threshold | Actual min and actual first-available reference; source prefix complete | Complete headDeviation search; any phase |
| pushup_hand_position | first-rep max-elbow-selected wristAhead outside forward/backward bounds | Actual first-rep eligibility, complete elbow argmax search, actual selected wristAhead and thresholds | Same selector and selected quantity; top |
| pushup_depth_fade | last-N elbow minima mean − first-N mean > threshold | Exact first/last-N entries, every consumed minimum search complete | Same; bottom |
| squat_hips_first | selected early-ascent torso rise > threshold AND hip rise speed > shoulder rise speed | Complete knee argmin selector; exact post-bottom prefix; finite torso/hipY/shoulderY/torsoLength dependencies and selected endpoints | Same complete selector/dependencies; bottom and ascending within native used scope |
| squat_shallow | current knee_min − first-N median > threshold | Complete current knee minimum search and exact first-N references, each complete | Same; bottom |
| squat_no_lockout | belowSetMax(knee_max) OR belowSetMax(hip_angle_max) | One actually true branch with complete current maximum/top search and its supported maximal reference suffices; the other branch may be missing | Both actually false branches, both current/historical maximum searches complete; top |
| squat_lean_drift | last-N torso_at_bottom mean − first-N mean > threshold | Each exact consumed torso-at-bottom value has complete knee argmin selection and finite selected torso | Same; bottom |
| squat_depth_fade | last-N knee minima mean − first-N mean > threshold | Exact first/last-N entries, every consumed knee minimum search complete | Same; bottom |
| squat_knee_valgus | knee_ankle_gap_ratio_min in post-lowest-hip suffix < threshold | Complete hipY argmax selector and actual finite ratio witness in its suffix | Complete hipY selector and ratio suffix; bottom and ascending; front view |
| squat_heel_rise | first-available heelToe − minimum heelToe > threshold, only when enabled | Exact first-available reference with complete prefix and actual minimum witness | Complete heelToe search/reference; any phase; disabled is withheld |
| row_torso_swing | torso_max − torso_min > threshold | Complete torso/unwrapping dependency search and its actual max/min witnesses; missing intermediate angles can change unwrap branches | Complete torso search; any phase |
| row_standing_up | wrapped first-N torso_mean median − current torso_mean > threshold | Complete current mean and every exact first-N mean reference | Same; any phase |
| row_short_pull | first-N elbow_behind_max median − current elbow_behind_max > threshold | Complete current and exact first-N maximum searches | Same; top |
| row_head_up | head_dev_change_min < -threshold | Actual finite min and first-available reference; source prefix complete | Complete headDeviation search/reference; any phase |
| row_shrug | 1 − filtered minimum earShoulder / first eligible earShoulder > threshold, only when enabled | Exact first eligible headAngle+earShoulder reference with complete prefix, actual head-angle filter and selected minimum | Complete filter classification and all eligible earShoulder contributors; any phase; disabled is withheld |

For a negative below-set-max result, every offered prior history row is required, including rows whose metric is absent and was dropped by native compactMap; checking only surviving reference entries is insufficient. First-N and last-N membership remains positional, including duplicate current-entry membership where the native helper uses it.

For baseline/trend comparisons, no monotonic simplification of a missing mean/median reference is assumed. For first-available references, their real origin is retained; they are never relabeled rep-start. For min-above and max-below predicates, a single selected sample cannot prove a positive: an omitted more extreme sample could reverse the predicate. Native compound OR helper outcomes are checked separately before Boolean coercion.

All state/identity changes are written to new files. Labels remain unknown/unreviewed. A source-bound native result demonstrates the frozen evaluator's execution on those inputs; it does not supply independent form ground truth or justify adoption.

## Local commands

Create a private bundle with `schemaVersion: 1` and `traces`, each containing absolute or bundle-relative `tracePath`, `clipPath`, `executablePath`, and `receiptPath`. Use the original full clip and the exact built executable. Each trace must have the intentionally unbound native-window header and the corresponding final `bpt-pose-replay-receipt-v1` receipt.

```sh
python3 scripts/form_eval/export_native_faults.py prepare --bundle /private/run/bundle.json --repo /path/to/BPT --protocol docs/evaluation/independent_form_protocol_v1.md --output /private/run/new-task
python3 scripts/form_eval/export_native_faults.py export --task /private/run/new-task --repo /path/to/BPT --protocol docs/evaluation/independent_form_protocol_v1.md --output /private/run/new-export
python3 scripts/form_eval/import_predictions.py --help
```

`prepare` retains every completed native repetition and all its old rule IDs, never a favorable subset. `export` checks the task against that complete derivation again, writes `evidence.json` and detailed `export_audit.json`, and refuses overwrite. The existing importer then creates another NEW scored task from the evidence. Until independent annotations exist, its accuracy/recall are undefined; delivery coverage is not accuracy. Unsupported rule IDs or conflicting provenance reject; supported rules with insufficient actual observations are explicitly withheld. No clip, existing task, label, model or default is rewritten.

The checked-in fixtures under `test/python/fixtures/native_fault_trace` were emitted by actual `FormWarningTracker.observe/beginRep/finishRep` tests. Their overrides intentionally exercise branches and are synthetic geometry, not media accuracy evidence. Tests separately label adversarial JSON mutations and temporary identity envelopes; neither is presented as real clip execution.
