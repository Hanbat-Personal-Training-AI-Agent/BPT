# Native fault supported-negative fixtures v1

These four new **synthetic, actual-tracker** fixtures close the remaining source-contract negative paths. They do not replace the original fixtures, coverage-v2 positive fixtures, frozen exporter policy, real three-clip outputs, or old tasks.

`FormFaultNegativeFixtureTests.testAllTwentyRulesHaveActualSupportedNegativeWitnesses` supplies fully observed finite geometry and real toe/heel inputs, then calls the existing tracker through four repetitions per case. It requires an actual called-false native predicate, `rawFired=false`, and `negativeOperandEvidence=true` for every one of the 20 core-three rule IDs. It does not author decision JSON or interpret silence as a negative.

The cases specifically supply:

- Push-up: a fully supported first-rep maximum-elbow hand-position witness inside the native bounds.
- Row: complete first-rep reference history, unchanged torso/pull quantities, and a stable finite head/ear reference for enabled shrug.
- Side squat: an actual bottom-to-ascent window with no torso/relative-speed excess, unchanged bottom-torso history, and stable toe/heel values.
- Front squat: a real frontal view and a knee/ankle ratio above the native cutoff throughout the required suffix, with finite foot support.

All fault thresholds remain native defaults. Only the test baseline/trend windows are one repetition and the existing heel/shrug switches are enabled. These settings and synthetic provenance are in the emitted header. They are not application defaults, normal-person labels, or accuracy evidence.

The focused test passed: **1 test, 0 failures**. All 20 native negative paths have witnesses; their per-case/per-rule counts, exact JSONL hashes and generator hash are in [native_fault_negative_fixtures_v1.json](native_fault_negative_fixtures_v1.json). The separate Stage 2 tests validate complete source/view/phase/reference support rather than trusting native proof flags alone; they preserve the frozen exporter policy.

Reproduce with a fresh output directory:

```sh
BPT_FAULT_NEGATIVE_FIXTURE_DIR=/private/tmp/new-fault-negative-fixtures \
  swift test --package-path ios/CalibrationEngineKit \
  --scratch-path /private/tmp/new-fault-negative-build \
  --filter FormFaultNegativeFixtureTests
```

The run acquired `/tmp/bpt-heavy.lock`. Durable original JSONL, test log, command and receipt are under `~/bpt-data/completion-20261104-private/native-fault-evidence/negative-v1/`. Runtime source remains byte-identical to `260fbd3ade9d0cbfc611f7f77888a0f37664dc01`; this commit changes only tests/docs. No model inference, phone, UI, training, default change or real-result rerun was performed.
