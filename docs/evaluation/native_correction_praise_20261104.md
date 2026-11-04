# Correction praise requires comparable observations

A real synthetic regression was reproduced against `58e36ec`: `praise_fixed` could describe an issue as improved when a relevant observation disappeared. This was not observed in the frozen three-clip run; it is a source-level defect demonstrated by controlled tracker inputs.

The default `row_torso_swing` path reproduced it without enabling a new rule. A measured swing produced the warning, followed by a rep whose middle trunk was degenerate while the other frames remained usable. The aggregator omitted the missing torso value, returned a finite zero range, and the delivery path emitted `praise_fixed`. An enabled `row_shrug` case likewise lost the offending ear/head sample and reported improvement. The generic main-chain check and delivery-assessed set did not prove complete observation of the specific issue.

The Flutter lines are unchanged: `praise_fixed` says “That measured issue improved!” / “관찰한 항목이 나아졌어!”; `praise_good` says “Nice, keep it up!” / “좋아, 잘하고 있어!”. Generic encouragement retains its existing eligibility and cooldown. The fix applies only to the specific correction claim.

## Bounded change

`FormCorrectionEvidence` records correction-only evidence beside each rep's existing metrics. It checks finite source support, homogeneous actual side and trusted view, the rule's actual search/selector dependencies, and the relevant threshold/reference signature. First-N reference identities are retained in lockstep with the existing 100-entry 2D/3D metric histories. A capped baseline replacement, changed threshold, changed side, or unavailable reference cannot masquerade as observed improvement.

Both the previously spoken positive and current false predicate must have complete, comparable evidence. Current source coverage does not repair missing historical 3D frames: the 3D frame IDs must exactly match the original rep's observed frame IDs. Facing-dependent correction evidence requires a trusted finite establishing/confirming observation; ambiguous opposite-direction candidates invalidate correction evidence without changing the warning algorithm's hysteresis. Up-dependent 3D quantities require a consistent finite measurement reference.

The existing warning calculations, thresholds, fired keys, delivery-assessed sets, model inputs and default flags are unchanged. No exporter phase policy is imported: the helper follows actual aggregation dependencies without requiring extra `top`/`bottom` tokens. It deliberately withholds correction praise when support is incomplete; generic encouragement remains available under its prior rules.

Eleven core-three rules can currently be spoken per rep and then trigger correction praise: three push-up, four squat and four row rules. The other nine core IDs have setup/reference grades; head-drop/head-up warnings are reference-only and cannot be the previous per-rep spoken rule. Bench/deadlift already fail the pre-existing `praiseMetrics` guard, so this helper does not remove an existing correction-praise path there.

## Validation

- The initial missing-ear regression failed before the change and its complete-observation and generic-encouragement controls passed.
- Expanded tests against exact baseline `58e36ec` had eight failing cases (nine assertions), including default torso omission, side/view/config changes, rolling baseline replacement and facing provenance.
- The final source passes **360 Swift tests, four skipped, zero failures**. Thirteen focused correction tests include reliable corrections, partial previous observations, omitted historical 3D frames, unchanged warning behavior, generic encouragement, and head-rule grade scope.
- Cached all-Runner iOS typecheck passed for **67 Swift sources** in 6.02 seconds. Existing SDK deprecation/sendability warnings remain.

Durable before/after logs, baseline source/test hashes, commands and final source hashes are under `~/bpt-data/completion-20261104-private/native-praise-evidence/`. The typecheck's recorded Git ID is the pre-commit base because it checked the working source; its accompanying source hashes identify the actual checked bytes. The separate replay owner will compare the same frozen clips after source freeze. No phone, UI, window interaction, new model inference, training or deployment was used in this implementation task.
