# Withhold live adaptive fills from definitive posture assessment — 2026-11-04

The optional older `BPT_ADAPTIVE_3D=1` path could pass an inferred joint into posture assessment as a finite, usable observation before its expiry. This fix masks every current adaptive fill immediately for assessment while preserving the raw, constrained and adapted coordinates for their existing purposes. The flag remains off by default.

This is distinct from `ExerciseMotionObserver`: that comparison-only observer still feeds only diagnostics and does not replace the live pose or assessment mask. No observer output is newly adopted.

## Reproduced defect

On base `a22c5c4`, the new regression establishes an adaptive foot relation, removes the left ankle's original 2D support, and supplies a synthetic bad XS ankle. The relation changes that ankle, but its index was absent from `Lifted3DFrame.invalidJoints` because only expired adaptive joints were included. The same frame was classified `ok`; `FormWarningTracker` measured a finite **178.347322° knee minimum**, considered the no-lockout rule delivery-assessed, and emitted **`praise_good`**.

The regression was committed before the fix as `3df45b9448cf5beb96af1819b8e70b7ca19d20d8`. It failed six assertions on the old production code. This is a synthetic consumer-contract witness, not a measured human form error.

Source chain:

1. `AdaptiveRelationConstraint` retains an inferred position and fill diagnostics, but its own `invalid` field describes expired fills.
2. `MotionAGFormerLive` formerly used only that expired set when computing frame state; `Lifted3DFrame.masked3D` selected the adapted coordinates without masking current fills.
3. The camera passes `masked3D` and state into the exercise evaluator, then `FormWarningTracker`. Finite knee metrics could therefore come from the inferred ankle.
4. The normal native feedback bridge forwards selected keys to Dart; Dart does not independently inspect per-joint validity.

## Minimal change

Only the live frame's assessment boundary changes: both `Lifted3DFrame.invalidJoints` and the emitted state calculation now union `adaptive.filled.keys` with the existing constraint/expiry masks. The filled coordinates remain in `adapted`; `masked3D` substitutes NaN for assessment. The frame becomes `partial_3d` while independently observed joints remain available. A reliable reacquired joint leaves `filled` and immediately becomes assessable again.

No estimator, adaptive relation arithmetic, sigma, confidence threshold, expiry, model asset, default flag, FormWarnings rule, or observer implementation changes. A zero-displacement or zero-sigma fill is still withheld because numerical agreement does not turn missing observation evidence into a measurement.

## Validation

- **Before fix:** one new regression, six expected failures, including the finite knee metric and `praise_good` leak.
- **After fix:** 63 focused tests passed, including five new consumer regressions and existing adaptive numerical parity, observer non-adoption and form-warning tests.
- **Full package:** 321 tests, four skipped, zero failures.
- New regressions cover immediate knee-metric withholding, independent hip availability, raw/constrained/off-path invariance, reliable reacquisition, partial-state bridge propagation, and masking even when an estimate equals raw with zero sigma.
- The older test that explicitly expected a filled ankle to remain in `masked3D` now expects NaN there while continuing to require the adapted coordinate to remain available.

No phone/UI action, new model inference, signed app build, integration merge or deployment. Existing saved replay results and the signed artifact are unchanged. The receipt records source and log hashes; preserved local logs include the initial test-helper compilation error separately from the meaningful red/green runs.
