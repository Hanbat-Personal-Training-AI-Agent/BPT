# Relative coaching shadow contract — implementation and actual replay

Executed **2026-11-02 03:23:50 UTC / 12:23:50 KST**. The filename suffix is a task identifier, not the run date. Base: `654fab2b62affee52fb4cb3eb313dbbe784b3f08`. Scope is an offline, shadow-only comparison of two relative rules; production judge, thresholds, settings, models, catalog discovery and delivery remain untouched.

## Delivered code

`scripts/coaching_contract/{contract,engine,adapters,replay}.py` implements a versioned numeric evidence contract, causal observed-first-three scalar, qualified shadow verdict, independent original runtime/delivery states, descriptive cross-source comparison, strict existing-input adapters, and an immutable private replay CLI. See its [contract/run guide](../../scripts/coaching_contract/README.md). `target_profile` is retained unused; explicit-target evaluation is outside this engine. Outputs always state relative drift, observed-first-three reference, correctness not established and absolute normality not assessed.

The native mappings are `pushup_shallow` / elbow minimum and `squat_shallow` / knee minimum. The deep fault IDs are `pushup_depth_drift` and `squat_depth_drift`. Common descriptive scalar: current selected-side minimum minus median of observed reps 1–3; threshold is strictly greater than 15°. Native source `FormWarnings.swift:1099,1131,1146`; thresholds `:86,114`; deep baseline/drift and original device-key output in `server/calibration_modal/deep_metrics.py:275–346`. The original native and deep decisions are not rerun or replaced. In particular, deep `evaluatedKeys` / `serverWarnings` use **native device keys**, while generic faults use separate catalog IDs.

Closed native frame-index boundaries and half-open deep video_ms intervals remain original. Frames outside an interval or complete selections with omitted interval frames are rejected. A video_ms mapping must be explicit. Per-frame actual side, source rational clock/index, phase, view, finite assessment geometry, invalid joints, raw confidence values and layer hashes remain private. Different sides within a rep or across current/reference reps withhold the qualified comparison. Unknown phase/view/required support, incomplete spans, source gaps or unbound first-three identity also withhold it. Original known positives and observed numeric predicates remain visible. Missing unrelated joints do not erase a fully supported dependent-chain positive.

These gates are conservative **shadow** eligibility requirements. They do not establish a defect in the original native policy that can accept partial positive evidence, and they do not assert production parity. First-three limited motion can produce no relative drift; the output explicitly cannot approve it as correct form.

## Existing real-data replay

No media decoding, new inference, phone, GPU, Home, upload or GT was used. The existing strict terminal reader verified original clocks, layers, epoch/sequence, masks, source binding and original rep bounds. All source files were hash-checked again after replay. Numeric private outputs are under:

`/Users/6_month/bpt-data/coaching-shadow-replay-20261103-reviewed-private/`

`stream-00..03.json`, `result-00..03.json`, `comparison-02-03.json`, `input-receipt.json`, `aggregate.json`. No original file or earlier output was overwritten. Directory/files are 0700/0600. Only counts and hashes are exported in [aggregate JSON](coaching_shadow_replay_20261103.json); [source receipt](coaching_shadow_source_receipt_20261103.json) pins implementation/test hashes and every private JSON output hash.

| Actual existing input | Original reps | Common scalar available | Qualified relative result | Original runtime / delivery |
|---|---:|---:|---|---|
| Native squat, XS assessment | 10 | 7 | 10 withheld: view absent (first 3 also collect reference) | 10 missing / 10 missing |
| Native pushup, XS assessment | 10 | 7 | 5 no_warning; 5 withheld (3 collect reference, 2 source-observation gaps) | 10 missing / 10 missing |
| Native row, XS assessment | 10 | 0 | 10 withheld: exercise unsupported by these 2 rules | 10 missing / 10 missing |
| Genuine isolated GVHMR row worker report | 10 native-manifest intervals | 0 | 10 withheld: exercise unsupported | 10 missing for these 2 rules / 10 missing |

No observed-subset drift exceeded 15° in the 14 available native scalar observations. This is a descriptive result from existing development clips, **not** expert correctness, sensitivity, specificity or posture accuracy. The five pushup `no_warning` entries mean only qualified relative consistency under this shadow definition. Native terminal_rep records do not contain shallow-rule judged state or actual delivery, so neither silence nor the capture harness supplies an invented negative result. The original worker's **10 symmetry faults** are preserved independently; they do not become 10 shallow faults or device-key warnings.

Native source revision is `1a35d3fef5cd4b5b5bc49ac003a4584306cce344`, recorded as caller-bound published-capture provenance, not falsely inferred from a JSONL header. The genuine worker source revision is `8e00f543a70dd85b93b6ed716c1377a70586dffd`, with actual imported source hashes and verified report/input bindings retained. Source hashes:

- squat JSONL: `c783990a63bb3aa05afd30bd122b3c9b2e513a53a3e7430a86dddc4e83db5039`
- pushup JSONL: `508cf87e31740b20e17b6b44775b3ab28cdc9fc94fbbcd5af69acfa031dbe3fa`
- row JSONL: `20f8daf37800599513bdafba20e0e4b312a66cbf593fca68aad031143bf8921a`
- genuine worker report: `f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa`
- worker recorded-video SHA: `53658c052b52bde1285b3e3ee6a1951f201419831e9ce776af094f31749c44d8`; service manifest SHA: `2cc367da42da9c2b218990a730e0e5e1310645ef043392ec2d1d53dfb147c66f`

The terminal JSONLs do not retain verified original media byte hashes; their artifact SHA is **not** relabeled a video SHA. Playback source observations and the reencoded native recorded movie are also different inputs/clocks. Thus the existing row pair produces 10 explicit withheld comparisons, zero numeric pairs, with unsupported exercise, missing media identity, clock/interval and coordinate/units/side-policy differences preserved. There is no paired real pushup/squat deep input in this replay and no claimed same-pose or GT parity.

## Verification and next boundary

**31 tests PASS**, including both opt-in actual-input tests, using system Python 3.9 stdlib; `git diff --check` passes. Default test discovery gives 29 PASS + 2 private-input skips. Reproduce:

```sh
BPT_COACHING_REAL_ROOT=/Users/6_month/bpt-data/terminal-device-capture-20261102 \
BPT_COACHING_WORKER_ROOT=/Users/6_month/bpt-data/native-deep-inline-l4-20261103-verified-private \
python3 -m unittest discover -s test/python -p 'test_coaching_contract*.py' -v
```

Tests cover uniformly limited first-three references, causal/future independence, partial known positives, missing required chain, silence/quiet separation, side changes, unknown view/phase, explicit invalid masks, first-three set/artifact identity, closed/half-open boundaries, malformed input, duplicate JSON keys, finite extreme-value arithmetic, source/clock/media mismatch, right-only positives, verified worker tampering and immutable private outputs. Parent review's mixed-side false qualification and finite-overflow false zero counterexamples now have regression tests. Independent Sol review is a separate pending gate; these implementation tests are not an independent accuracy study.

Next feasible integration target: feed actual matched pushup/squat evidence through these contracts with original judge/delivery records and explicit source-clock mapping, or consume the separate reviewed explicit-target criteria contract. Missing native view, missing runtime/delivery logs and absent paired pushup/squat deep evidence cannot be repaired by relabeling row data, borrowing GT, approving first-three references, or changing thresholds. This deliverable makes those boundaries executable; it does not complete absolute posture criteria or validate expert accuracy.
