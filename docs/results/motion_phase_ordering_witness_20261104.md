# Legacy H rejected-observation phase witness

The current Swift H estimator calls `updatePhase(raw, confidence)` and damps arm velocity before the adaptive acceptance gate. The archived `docs/experiments/motion_contact_swift.md` already identifies this limitation; this test makes its cross-joint effect reproducible.

`ExerciseMotionPhaseOrderingTests` warms two identical H states with 20 finite, confident frames and a unit leg scale. At the next frame only wrist 13's rejected outlier differs: one moves toward the shoulder and the other farther away. Both are rejected by the real gate. Elbow 15 has identical raw input in both branches and is marked unobserved.

Actual results:

- Wrist 13 is rejected in both branches and absent from observation passthrough.
- The inward branch reports `transition`; the outward branch reports `lowering`.
- The other arm's unobserved elbow 15 differs by **0.0031216645330939263 image-height units**. This is not a millimeter error estimate.
- Its pre-update velocity was `[0, 0.1337856228468828, 0]`; the turning branch retains exactly 0.3 times the other branch's velocity.

The four witness/control tests pass: rejected-wrist cross-joint effect; fully accepted small turning with expected damping; missing phase inputs clearing phase history; and explicit reset, timestamp gap/reversal, person change and camera-motion clearing. The existing **720 Python/Swift checkpoints also pass unchanged**. Combined focused run: five tests, zero failures; build 19.03 seconds.

No estimator source was modified. This proves a concrete dependency on rejected phase input, not an accuracy improvement. The accepted-observation candidate is proposed separately and has not been implemented or scored here. All original app builds, default behavior and prior experiments remain untouched.

Original synthetic input/output JSON, test log, source/test hashes and reproduction command are retained under `~/bpt-data/completion-20261104-private/motion-phase-acceptance/witness-v1/`. The Swift test optionally writes them with `BPT_PHASE_WITNESS_DIR` into a fresh directory; writes are exclusive. No model inference, phone, UI, training or deployment occurred.
