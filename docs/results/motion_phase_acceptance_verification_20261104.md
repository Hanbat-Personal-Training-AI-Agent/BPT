# Accepted-observation phase candidate: implementation verification

Experimental source commit: `83f1a93c9d4c36405730776486b65dd9c33bf8d3`, branch `experiment/motion-phase-acceptance-20261104`, based on `9cfe92b`. Pre-outcome protocol commit: `48c78b7`. The candidate is not integrated into the app and is never selected by default; `legacyRaw` remains the initializer default.

The implementation follows the frozen order: undamped proposal → one acceptance/relocation pass → accepted, reliable, original-finite-score phase inputs → optional explicit external phase → damping/recomputation excluding accepted relocations. Rejected/missing phase inputs clear the corresponding existing phase history. The accepted set is not recomputed after damping. This is an ordering/input-eligibility package and can alter acceptance decisions; it is not merely a label change.

Verification completed before saved-data outcomes:

- **374 Swift tests, four skipped, zero failures**.
- Original **720** Python/Swift checkpoints pass with the default legacy policy.
- **864** additional full output/state comparisons across 36 synthetic policy/variant cases pass, including **216 accepted-phase H** frames, accepted-policy G controls and both legacy variants. Maximum absolute difference: **2.7755575615628914e-17**, tolerance `1e-8`.
- Explicit witnesses cover rejected-input cross-joint influence, accepted turning, original nonfinite confidence, missing input, reset/gaps/person/camera changes, irregular timestamps, external phase override, protected relocation reset, and acceptance that must remain frozen even when the later damped prediction would cross the innovation threshold.
- The parity comparator rejects unexpected NaN/infinity and extra/missing state keys. Source pins and output counts must pass before a PASS receipt can be written. The old 720 verifier was also hardened against nonfinite numerical comparisons.

The final receipt is [motion_phase_acceptance_parity_20261104.json](motion_phase_acceptance_parity_20261104.json), SHA-256 `bab621d962afb67ef62a5c8c5bda9ab8eb5a0fa5daa467de4645f7e20ec30d3a`. It binds the Swift estimator, Python patch/generator, both test sources, old verifier/fixture, new fixture, frozen protocol and transformed Python sources. The original Python source remains SHA-256 `c58740a36791962c9196f2c0443c9d5ae9ad71b343d6688f55614abaea57c40d`; the legacy loader returns it unchanged.

Loader API: `scripts/motion_phase_acceptance/phase_policy.py`, `load_estimator(path, policy='legacy'|'accepted_phase')`. It returns the estimator class. Candidate diagnostics use `phase_policy='accepted_observation'`. The saved-data runner independently checks the receipt and generated source hashes before evaluating the fixed four policies. It will preserve all prior input/output files and export aggregates only.

Durable logs, commands, fixture and receipt copies are under `~/bpt-data/completion-20261104-private/motion-phase-acceptance/candidate-v1/`. The original rejected-input witness is separately preserved under `witness-v1/`. Earlier provisional parity receipts are retained for audit and are not authorization for the final replay.

No phone, UI, model inference, training, deployment, app-default change or saved-data scoring was performed by this implementation task. Synthetic cross-language parity does not prove accuracy or exhaustive equivalence on arbitrary data. The separate 72-stream replay is a reused-development-data experiment; its results must be reported independently, with acceptance changes and motion-suppression costs, before any adoption discussion.
