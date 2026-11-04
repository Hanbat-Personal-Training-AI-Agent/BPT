# Native fault source-contract fixtures v2

These four **synthetic, actual-tracker** fixtures supplement the original four fixtures without replacing them. They exercise positive source paths for all 20 existing core-three rules. They are execution/lineage tests, not media accuracy, biomechanical validation, or evidence for changing defaults.

`FormFaultCoverageFixtureTests.testAllTwentyRulesHaveActualSupportedPositiveWitnesses` creates finite 2D geometry, calls the real `observe → beginRep/recordCurrentFrame → finishRep` sequence, and writes the recorder's original JSONL. It never authors rule decisions or metric-support JSON. Each case has 20 source frames and four native reps. The test requires every core-three rule to have at least one actual `rawFired=true` and `positiveOperandEvidence=true` record; the separate exporter tests must still verify full support and provenance rather than trusting those flags alone.

All fault thresholds remain the native defaults. Test-only configuration uses `baselineRepCount=1`, `trendRepCount=1`, and enables the existing heel-rise and shrug rules. This gives a small deterministic fixture with real pre-append reference history; it does not change application configuration.

| Case | Positive paths exercised |
| --- | --- |
| pushup-side | All eight push-up IDs: sag/pike and head directions, first-rep hand position, shallow, lockout and depth trend |
| squat-side | Hips-first, shallow, lockout, lean/depth trends and actual foot-supported heel rise |
| squat-front | Actual frontal view, lowest-hip selector and narrow knee/ankle ratio; heel rise |
| row-side | Torso range, actual first-rep baseline followed by standing/short-pull differences, head up and enabled head-filtered shrug |

The first rep is fully observed. The hand witness comes from the real maximum-elbow selector. Baseline/trend witnesses resolve to actual earlier trace IDs. Squat cases include bottom and ascending observations, and foot inputs have finite toe/heel coordinates and confidence. All source ledgers close complete. The native rule-positive count and exact fixture/generator/runtime hashes are in [native_fault_fixture_coverage_v2.json](native_fault_fixture_coverage_v2.json).

The focused Swift test passed: **1 test, 0 failures**, build 18.11 seconds. Runtime files are byte-identical to `7dea736c994d68f0248ca82720878a7502fe4ce8`. This commit changes only tests and documentation; it is separate from the frozen runtime and final CLI artifacts.

Reproduce in a fresh output directory because fixture writing is exclusive:

```sh
BPT_FAULT_COVERAGE_FIXTURE_DIR=/private/tmp/new-fault-coverage-fixtures \
  swift test --package-path ios/CalibrationEngineKit \
  --scratch-path /private/tmp/new-fault-coverage-build \
  --filter FormFaultCoverageFixtureTests
```

The run acquired `/tmp/bpt-heavy.lock`; its original log, four JSONL files, exact command and hash receipt are preserved at `~/bpt-data/completion-20261104-private/native-fault-evidence/coverage-v2/`. Existing v1 fixture bytes remain unchanged. No model inference, phone, UI, training, deployment, old-task backfill, rule/default or frozen runtime change was performed.
