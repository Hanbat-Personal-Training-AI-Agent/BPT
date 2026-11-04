# Opt-in native fault trace and source ledger — implementation protocol

Base `a22c5c4`. Scope is the 20 existing core-three fault IDs (8 push-up, 7 squat, 5 barbell-row), with unchanged judge arithmetic, thresholds, ordering, delivery and defaults. This trace is evidence for a future strict exporter, not itself `bpt-native-fault-decisions-v1`. No old task, label or prediction is changed; the 588-row task remains frozen. No phone, UI, model call, training or deployment.

## Source contract and stable integration API

Add `FormFaultEvidence.swift` beside the existing evaluator code and optional `FormWarningTracker.faultEvidence` / `faultSource` properties. Both default to nil. `FormFaultSource` carries the original processing frame, optional original source index, rational source PTS, source kind, source/session identity and flush provenance. It must not manufacture a clock from a frame counter. A headless retained-input driver sets the source before invoking the real evaluator; the camera hook does the same only under `BPT_NATIVE_FAULT_EVIDENCE=1`.

`FormFaultEvidence` accepts a record callback (for headless tests/export) or an owned bounded JSONL destination (for opt-in capture). Its records have `contract: bpt-native-fault-trace-v1`, monotonically increasing sequence and a run identity:

- `header`: caller/build/source bindings, explicit expected-source scope (`declared_input_manifest` or `observed_judgements_only`). Unavailable bindings remain null, never invented.
- `frame`: original source stamp, exact stored evaluator phase and selected side, 2D/3D source/state, required-input gate, finite/missing measured fields and input support. A missing source clock, failed observation, duplicate, gap or flush is explicit. The stored phase is the value passed to `FormWarningTracker.observe`, before later evaluator/UI overrides; it is not an overlay-phase mapping.
- `rep`: native rep index plus independent trace ordinal, actual recorded frame span/sources, selected source (`2d`, `3d`, `3d_unavailable`), immutable config/delivery snapshot, frame/metric provenance, exact prior-history IDs/values, and one trace entry per core-three rule. A 3D judge not run is null, distinct from a called judge that fires nothing.
- `footer`: close reason, record counts, cap/error status and expected/observed/delivered source accounting. Writer closure is distinct from complete source coverage. Observed-only runtime capture cannot claim complete input coverage without a declared ingress manifest.

The recorder can accept a declared source manifest before execution; duplicate/missing/discontinuous observations and capped/failed output prohibit complete-coverage claims. Every output file is new and bounded; no append to an old run. The default-off hook has no authority to alter pose, warning, delivery or workout state.

## Judge/aggregation instrumentation

Capture rule evaluation **at** `judge` and its helper calls. Preserve called `true`, `false`, and `nil`, and distinguish `not_called` due to view/config/branch from called false. Record direct metrics, exact operands and thresholds, and the actual baseline/set-max/trend reference entries before history append/truncation. Quiet delivery keys still execute: `executionEnabled` means the rule's judging/config switch; `deliveryEnabled` is separate. No schema field silently substitutes the delivery mask for rule execution.

Record aggregation support at the existing aggregation source: expected frames, finite/available contributors, selected extrema frames, first-available reference frames (not relabeled rep-start), and actual filtered windows. Include per-frame phases and side changes; a majority report side and compactMap count are not complete support. 3D `enough3D` is a judge-entry gate, not full rule exposure. The current selected assessment pose/mask is the input; raw or predicted joints are not silently promoted to assessment support.

For compound no-lockout ORs, preserve each helper result before the `== true || ...` expression erases nil. A supported true knee branch can establish a positive OR even with an unavailable hip; an OR false with a missing operand cannot establish a supported negative. Baseline/trend support keeps the exact consumed references, separately for 2D/3D. No fault condition is recomputed from a finished warning list.

## Export boundary reserved for Stage 2

Stage 1 records facts, not guessed complete decisions. Stage 2 must bind a **new** candidate/task/clip/boundary identity and apply the existing strict importer contract. It may emit a warning only from an actual fired predicate with sufficient relevant positive support and a witness interval wholly inside the frozen opportunity; the complete actual native rep may be that witness. It may not clip an overhanging witness or heal holes by using the bounding interval.

A no-warning needs called false plus complete relevant source/metric/view/reference/required-phase support over the entire frozen window. Required-phase proof must use the exact observed evaluator phases and aggregation selector, not an overlay label or a guessed anatomical phase. Current short/early-close spans may therefore remain withheld. Known failed gates produce explicit withholding; genuinely absent observations remain missing. Unknown/unsupported rule-phase contracts remain withheld/missing, not a fabricated green result.

Actual source capture and headless retained-input execution are separate provenance scopes. A valid headless replay proves execution of the frozen native rule code on retained inputs, not an original end-to-end camera run. Old partial reports cannot be retrofilled. Core-three IDs only; no renaming newer motion rules into old faults, no new biomechanics, and no human-label/accuracy claim.

## Validation gates

Tests must prove unchanged legacy dictionaries, metrics, fired keys and delivery events with tracing off/on; called true/false/nil/not-called; compound partial-positive and missing-negative OR; quiet executed keys; disabled rule/view branches; missing and partial selected 3D; mixed sides; source clock/gaps/flush/caps/errors; exact reference contributors and history before cap; real first-available reference versus rep-start; and new-task provenance rejection. Source files and trace schema/API are published before the separate exporter implementation begins.


## Implemented API details and bounded runtime scope

`FormFaultSource` additionally stores exact CMTime epoch/flags. Flush is a delivery flag;
source matching compares session/key, processing frame, source index, rational PTS,
epoch/flags and source kind. The header contains the full declared source manifest when
one exists. `ingressFailure(source:reason:)` is distinct from an evaluated frame.
`nextRepID()` allocates recorder-lifetime IDs across tracker reset/replacement; history
resets independently. Attempted and successfully written frame/rep counts are separate.
A reserved, bounded footer reports counts rather than unbounded failed-source ID arrays.
Any missing footer, failed write, cap, invalid observation, duplicate or source mismatch
prevents complete source coverage. File writes truncate a failed partial record back to
the last successfully written byte before trying an incomplete footer.

The camera hook is OFF unless `BPT_NATIVE_FAULT_EVIDENCE=1`. It creates a new UUID file
and captures actual assessment inputs and frame-bound PTS. Capture/session identity is
carried through asynchronous lifting. Stop, interruption, background and stale-session
output close the capture as incomplete. The live hook has no declared expected manifest
and therefore cannot certify complete input coverage even if every emitted record is valid.
The headless CLI may supply a manifest, source hashes and build bindings separately.

Metric support records actual selected extrema, first-available references, contributor
sets restricted to each aggregation window, and multistage selection dependencies (e.g.
whole-rep knee minimum selecting the hips-first window). Per-frame input metadata records
joint/feet finite support and measurement dependencies; facing is a stateful quantity whose
state can precede capture. `stateMayPrecedeCapture=true` is not a complete provenance claim.
Manual predicates record their actual finite constants separately from scalar helper
thresholds. None of this metadata changes the original calculations or decisions.
