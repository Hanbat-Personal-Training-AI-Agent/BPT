# Provenance-strict local prediction import

`import_predictions.py` creates a **new** task from an existing independent-form task and an explicit native fault-decision export. It does not execute a model, reconstruct a rule decision, generate labels, or change the frozen protocol. Existing manifests and labels are copied byte-for-byte. A base task containing any nonmissing prediction is rejected to avoid replacing decisions. Outputs must not exist, including symlinks.

## Accepted evidence

The importer accepts one JSON export with exactly these top-level fields:

- `schemaVersion`: integer `1`.
- `contract`: `bpt-native-fault-decisions-v1`.
- `candidateCommit`, `manifestSha256`, `protocolId`, `protocolSha256`, `boundaryManifestSha256`: exact frozen task bindings.
- `ruleSourceSha256`: SHA256 of `ios/Runner/NativePose/Evaluators/FormWarnings.swift` at that exact candidate commit, retrieved by `git show` from `--candidate-repo` (not the working copy).
- `observations`: zero or more explicit per-opportunity records.

Each observation repeats **every** identity field from its frozen manifest sample, with identical JSON types, and includes:

```json
{
  "state": "no_warning",
  "reason": null,
  "ruleId": "pushup_no_lockout",
  "decisionSemantic": "fault_presence",
  "positiveEvidenceSufficient": false,
  "exposureStartSeconds": 0,
  "exposureEndSeconds": 2,
  "checks": {
    "ruleEnabled": true,
    "ruleEvaluated": true,
    "requiredPhaseObserved": true,
    "viewEligible": true,
    "referenceReady": true,
    "finiteInputs": true
  }
}
```

The fragment omits identity fields for readability; it is not a complete import record. The source exporter must record actual evaluator decisions and effective eligibility/configuration, including required phase and reference availability. `no_warning` requires all six checks and exposure covering the whole frozen window. `warning` requires enabled and evaluated rule, finite relevant inputs, a positive witness interval wholly inside the frozen rep window, and an explicit `positiveEvidenceSufficient: true` attestation from the source evaluator. A partial interval may supply sufficient positive rule evidence; absent unrelated frames do not erase it. For warnings, the exposure fields describe that bounded positive witness, not earlier baseline/reference support. Crossing a rep boundary is rejected. The importer does not infer sufficiency. Whole-phase/view/reference checks may be false for a warning whose specific positive evidence remains sufficient. `withheld` requires a local nonidentifying reason code and gate exposure overlapping the target rep (boundary-only contact is insufficient); uncertainty may cause withholding even when all six checks are true. Source `missing` rows are rejected: omit unavailable opportunities and the importer emits `missing/not_in_evidence`. Duplicate rows, duplicate JSON keys, extra fields, nonfinite values and any identity/provenance mismatch reject the whole import before output creation.

These checks validate an export's provenance declarations, not the truth of a fabricated export. There is no cryptographic execution attestation. Do not hand-fill check booleans to make old logs pass. The repository does **not** currently contain a runtime exporter emitting this full contract. An old warning-event list cannot establish which silent rules actually ran or had a valid phase/view/reference. A disabled rule, incomplete phase, or absent warning never becomes `no_warning`. Withholding requires positive gate evidence; absent evidence remains missing.

This is the **old native fault-ID contract**, exactly matching the manifest's rule IDs. The nine newer motion-rule IDs and their desired-match `positive`/`negative`/`unknown` semantics are a separate contract. No equivalence or sign inversion is provided. New rule evidence requires a separately frozen manifest/rubric and importer; do not rename its IDs into old faults.

## Local use

```sh
python3 scripts/form_eval/import_predictions.py \
  --task-dir PRIVATE/task-v2 \
  --evidence PRIVATE/native-fault-decisions.json \
  --protocol PRIVATE/frozen-independent-form-protocol.md \
  --boundary-manifest PRIVATE/original-boundaries.json \
  --clip-index PRIVATE/task-v2/review_index_PRIVATE.json \
  --candidate-repo /path/to/BPT \
  --output-dir PRIVATE/task-v3-imported
```

The clip index uses the existing adapter's list of `clipSha256` and `localClipPath` records. Every manifest clip must appear exactly once, with no extra clip hashes. Actual full source bytes are hashed twice around validation. Neither clip paths nor participant identities are printed or copied to the result. The input export, task, index, protocol and boundary bytes are also hashed and rechecked. The receipt records those hashes, frozen rule-source hash, source-clip hashes, prediction-state counts and `inferenceRun: false`.

Score the new task with the existing `independent_form_eval.py score` command and the same frozen protocol/boundaries. Keep the receipt with the task: the scorer's generic prediction schema alone does not validate this import contract. Unknown labels stay unknown; importing decisions does not create independent expert labels or a holdout.

## Verified 2026-11-04

The local synthetic roundtrip produced one warning, one no-warning, one explicit withholding and one missing opportunity; all four labels remained unknown. An actual saved core3 replay aggregate was rejected against the Home task-v2 manifest, before any output task was created. That aggregate contains new motion-rule semantics and lacks this per-opportunity fault export contract. Read-only inspection found the existing task-v2 still has 588 missing predictions and 588 unknown labels (103 physical reps; development only), with the recorded manifest/label/prediction hashes unchanged. No compatible explicit per-rule export was found in the inspected task directory and nearby saved artifacts. This is a scoped availability finding, not an exhaustive search of all machines.

Proof artifacts are local at `/private/tmp/bpt-prediction-import-proof-20261104/`; no media or participant data is committed. The old candidate `8001f4f6955877fbf82f087f77e840fa2486bb6e`, original Home task and protocol remain unchanged. No actual prediction coverage or accuracy improvement is claimed.
