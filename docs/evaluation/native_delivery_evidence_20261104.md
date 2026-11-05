# Native delivery-decision evidence snapshot — 2026-11-04

`FormRepReport.dictionary` now adds `delivery_decision_evidence` under contract `bpt-form-delivery-evidence-v1`. It preserves the exact `assessed2D`/`assessed3D` sets that `finishRep` already received from `judge` and supplied to delivery qualification. Previously those sets were discarded after delivery. No judgement, threshold, gate, order, count, spoken feedback, or legacy report field changes.

The snapshot contains:

- Delivery-assessed key sets for 2D and 3D, serialized in sorted order. A missing 3D judge call is `null`; an executed judge with no qualifying keys is `[]`.
- Condition-fired key arrays in their original rule order for both sources.
- The selected source (`2d`, `3d`, or `3d_unavailable`) and its separate assessed/fired collections. Unavailable selected 3D stays `null`, even if comparison-only 2D fired.
- A value snapshot of enabled feedback keys at report creation, selected condition-fired keys enabled for delivery, and the separate actual `spoken_key`. Enabled does not imply spoken: grade, repetition, cooldown, and selection still apply.

Manually constructed or legacy reports default to `deliveryDecisionEvidence == nil`, encoded as `null`. They do not imply that an empty set of rules was evaluated. The diagnostic object's captured key sets and arrays are immutable values; later tracker configuration does not change a prior snapshot.

The scope is explicitly `delivery_qualification_not_complete_rule_coverage`. `assessed` means the existing delivery/praise qualification accepted a condition with its current view/reference/finite checks. It does **not** establish complete phase exposure, full-window visibility, absolute form correctness, or a human label. Some historic conditions can fire with partial positive support while not entering the delivery-assessed set. An unknown view can likewise preserve an existing fired condition while qualifying no delivery-assessed keys. The additive diagnostic preserves these distinctions instead of changing historical behavior.

This contract is deliberately distinct from the stricter `bpt-native-fault-decisions-v1` importer contract. Do not fill that importer's coverage/phase/reference flags from these sets or automatically interpret all nonfired keys as `no_warning`. Candidate/clip/time/source provenance and rule-specific sufficiency still need independently supported evidence. No current historical task was retroactively populated.

Validation on the isolated source worktree:

- **44 FormWarningsTests passed**, including five new regressions: quiet fired key and immutable enabled state; unknown-view fired/assessed separation; actual partial 3D knee-positive with missing hip preserving exact judge sets; unavailable selected 3D retaining comparison-only 2D; and byte-identical legacy JSON fields with null defaults for manual reports.
- **305 full-package tests, 4 skipped, 0 failures.** The existing terminal failure-injection tests emitted their expected `write_failed`/`serialization_failed` messages and passed.
- No iOS build or phone action. The source change can join the separately coordinated final app build.

Local logs: `/private/tmp/bpt-form-evidence-swift-20261104.log` and `/private/tmp/bpt-form-evidence-full-swift-20261104.log`. The isolated cache at `/private/tmp/bpt-form-evidence-build-20261104` was removed after validation to recover disk space; both logs are retained.
