# Native fault trace export: 2026-11-04

The real three-clip run produced **200 per-repetition/rule opportunities from 30 native repetitions**. The frozen exporter supported **3 warnings and 66 no-warning decisions**, and explicitly withheld **131**. All 200 labels remain unknown; independent accuracy, precision, recall and false-warning rate are undefined. The 69 supported decisions are **not 69 correct decisions**.

Candidate `94a72a5ffae86011a87af93eb246eb8a7a58f4fe` ran the actual native evaluator with the existing local pose models. All selected form sources were 3D. The task uses `ai_windows`, one development group, and no holdout. Full original clip bytes, exact source-index/rational-CMTime ledger, runtime/build sources, executable, models, trace closure and final execution receipts were verified. The old 588-opportunity task was not opened for modification or reused.

## Actual source-bound decisions

| Exercise | Native reps | Opportunities | Warning | No warning | Withheld |
| --- | --- | --- | --- | --- | --- |
| barbell_row | 10 | 50 | 0 | 34 | 16 |
| pushup | 10 | 80 | 0 | 32 | 48 |
| squat | 10 | 70 | 3 | 0 | 67 |

All-row supported-decision fraction is 69/200 (34.5%). This describes evidence availability; the scorer's adjudicated decision-coverage denominator is zero and its value is null. No human correctness claim follows from either warning or no-warning.

## Native fired conditions and withheld evidence

The selected native judge fired 11 conditions. Three were supported: `squat_knee_valgus` at native task repetitions **6, 8 and 10**. Eight fired conditions were withheld as follows. These eight are **not identified false warnings**.

| Exercise / rule | Rep(s) | Frozen export disposition |
| --- | --- | --- |
| Squat / hips_first | 1, 3 | Ascending phase not observed in the required support scope |
| Squat / no_lockout | 2, 4 | Top phase not observed in current maximum support |
| Squat / no_lockout | 5 | Top phase not observed in the maximal historical reference support |
| Squat / knee_valgus | 7 | Witness frame view ineligible |
| Squat / knee_valgus | 9 | Ascending phase not observed in the required support scope |
| Push-up / no_lockout | 3 | Witness frame view ineligible |

The explicit bottom/top/ascending requirements are additional conservative criteria frozen before real outcomes. In particular, the native hips-first and valgus predicates can fire from their selected frame windows without an `ascending` token. A missing token limits export coverage; it does not establish missing geometry, an incorrect native predicate, or a false warning. No phase requirements or thresholds were relaxed after seeing these results.

| First withholding reason | Count |
| --- | --- |
| Execution disabled: squat heel_rise and row_shrug | 20 |
| Native nil: insufficient first-N/last-N baseline or trend history | 21 |
| Native not called: other view branch | 30 |
| Native not called: nonfirst-rep hand-position setup | 9 |
| Native not called: row baseline history unavailable | 6 |
| Incomplete whole-rep current/reference 3D search | 20 |
| View ineligible at current/reference witness | 8 |
| Required phase absent from current/reference support | 11 |
| Required selected-source sample unavailable | 6 |
| Total | 131 |

These are first-failure counts, not mutually independent causal effects. The 20 incomplete searches concern push-up shallow (7), no-lockout (8), and depth-fade (5). Six additional push-up opportunities lack a required selected-source sample. Neither category was converted to a negative from silence, a raw warning list, or a delivery-assessed set. Execution enablement and delivery enablement remain separate; quiet delivery keys can still contribute valid native evidence.

## All 20 rule contracts tested separately

All 20 old rule IDs have at least one supported positive emitted from actual Swift tracker execution on synthetic fixtures. The coverage-v2 fixtures use native default numeric thresholds, baseline/trend windows of one, and explicit heel/shrug enablement to exercise their paths. These are test configurations, not changes to runtime defaults or evidence of media accuracy. Original fixtures also retain incomplete support and negative cases. No rule is silently mapped to a new rule ID or left with an unfinished unsupported-contract fallback.

| Rule | Synthetic supported + | Synthetic supported − | Synthetic withheld | Real + / − / withheld |
| --- | --- | --- | --- | --- |
| pushup_depth_fade | 3 | 3 | 6 | 0 / 0 / 10 |
| pushup_hand_position | 1 | 0 | 11 | 0 / 0 / 10 |
| pushup_head_drop | 4 | 7 | 1 | 0 / 8 / 2 |
| pushup_head_up | 4 | 7 | 1 | 0 / 8 / 2 |
| pushup_hip_pike | 4 | 8 | 0 | 0 / 8 / 2 |
| pushup_hip_sag | 8 | 4 | 0 | 0 / 8 / 2 |
| pushup_no_lockout | 6 | 2 | 4 | 0 / 0 / 10 |
| pushup_shallow | 6 | 1 | 5 | 0 / 0 / 10 |
| row_head_up | 1 | 3 | 4 | 0 / 10 / 0 |
| row_short_pull | 3 | 0 | 5 | 0 / 7 / 3 |
| row_shrug | 8 | 0 | 0 | 0 / 0 / 10 |
| row_standing_up | 3 | 0 | 5 | 0 / 7 / 3 |
| row_torso_swing | 6 | 1 | 1 | 0 / 10 / 0 |
| squat_depth_fade | 3 | 3 | 6 | 0 / 0 / 10 |
| squat_heel_rise | 8 | 0 | 4 | 0 / 0 / 10 |
| squat_hips_first | 7 | 0 | 5 | 0 / 0 / 10 |
| squat_knee_valgus | 4 | 0 | 8 | 3 / 0 / 7 |
| squat_lean_drift | 3 | 0 | 9 | 0 / 0 / 10 |
| squat_no_lockout | 7 | 1 | 4 | 0 / 0 / 10 |
| squat_shallow | 3 | 3 | 6 | 0 / 0 / 10 |

Absence of a negative in a synthetic row above is a fixture-coverage limitation, not an unsupported rule implementation. At this result freeze, explicit supported-negative fixtures remain missing for `pushup_hand_position`, `row_short_pull`, `row_shrug`, `row_standing_up`, `squat_heel_rise`, `squat_hips_first`, `squat_knee_valgus`, and `squat_lean_drift`; a separate test-only follow-up is requested. All-rule positive paths, partial OR support, failed-branch isolation, historical missing metrics, current minimum-search completeness, quiet keys, unknown views, partial-3D state spelling, facing establish/flip/reset/reacquisition, provenance mismatches, overwrite rejection, unchanged inputs and an end-to-end prepare/export/import roundtrip are covered by **28 new tests; 53 combined exporter/importer/evaluator tests pass**.

## Frozen artifacts and integrity

- Pre-outcome policy/implementation: `33976b7`; pre-outcome tied-extremum correction: `3efa046`.
- Policy SHA-256: `14515e585175c7e1a396dc9a6b5a73dc1a14639976ee0cc203c028f20fcbcccc`.
- Runtime rule source SHA-256: `1afc5663228d40cca71630f8587fd12501f36d66fea666e891dc08a4da3089c4`.
- Executable SHA-256: `75c81e36070400a5015400fa1f641c25e5bb1d89ecb750fe9f31667173c9015e`.
- Manifest SHA-256: `8e3f38ebd9bff883a32d697c233301562edd1a4ae30ea799354007535ee41ce2`.
- Boundary manifest SHA-256: `783b91070ac12e1ef18b8a87ea602c828874f290697183944978cc1d6ee125d4`.
- Final evidence SHA-256: `4348a50b28b4a1aa4593ab82513da49c1e036bf4018eac8354c2bedaf1d81f02`.

| Exercise | Full original clip SHA-256 | Closed trace SHA-256 |
| --- | --- | --- |
| squat | 7da9af0c13a9015fc2fc6b3591773e63c68c6f2d72a004f10b72dbed8d7e1004 | 8a089e38ca0b11f13a66b0dd87b991453ab16cc7d8ac47cd079cdf9bd92ae09c |
| barbell_row | 848d03a6103c25b814e15ce7f1ff47abfc0a7d8f5378d2ce1dc67fde644dc9ee | 19f3e81969cfb4d9f2ee8e4f5dc0a8b45bcb438d17db27fee47bc8e1a6187455 |
| pushup | b553b205ba4bdbcc88c445208813346b445f7b98b48cc60fc1ad1f77bc06d2d0 | 48364b2b24139185a13aae74d2cd7809282ae3479cb5672f82e9fdb16f4e0af8 |

Private artifacts are retained under `~/bpt-data/native-fault-evidence-20261104-private/run-94a72a5/native-export-attempt2/`: complete new task, evidence/audit, imported task, scorer output and attempt receipt. The supplied executable path points to a durable byte-identical copy; original runtime paths remain recorded in the trace/build receipt. The new push-up clip is bound by its actual full-byte hash and was never retrospectively equated to the older catalog file.

Attempt 1 is preserved. Its decision data were valid, but the export receipt hashed canonical JSON while the file used a different key order. Serialization-only commit `7247475` makes the emitted bytes exactly match the receipt. Attempt 2 has **identical parsed evidence and all 200 identical decisions**, byte-identical task manifest/boundaries/labels/base predictions, and a verified final evidence hash. No support policy, threshold, native algorithm or model changed. Independent read-only review confirmed the equality, hashes, preserved labels, and null accuracy/recall.

A residual conservative limit is retained: after selecting the first finite tied positive extremum, a later view failure does not cause the exporter to try another tied frame. This can withhold additional valid positives; it cannot manufacture a supported decision. The frozen three-clip outcomes were not tuned to remove it. The local trace/build/receipt chain is an execution attestation, not an externally signed measurement or independent human ground truth.

[Machine-readable results and per-rule matrix](native_fault_export_20261104.json). [Pre-outcome support contract](../evaluation/native_fault_export_policy_v1.md).
