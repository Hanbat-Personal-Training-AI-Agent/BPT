# Mixed-time edge reference: synthetic reproduction only

Base `cbcdc18`, separate branch `experiment/motion-edge-alignment-20261104`. The frozen 72-stream paired-anchor replay is unchanged. No estimator fix, model inference, new dataset evaluation, phone action, or default change was made here.

The present parent plausibility test forms its old length from `lastObserved[child] - lastObserved[parent]`, although those positions can come from different timestamps. Correcting the 2D/3D agreement anchors does not correct this separate reference.

## Witness construction and result

The shoulder-to-elbow link is a nondegenerate unit-radius circular trajectory with fixed shoulder. The initial elbow x is 0 and wrist x is 1. Legs have unit combined length and every skeleton edge initially has positive length. The visible elbow moves in 20 small accepted steps; the wrist has score 0.05 during those steps. At return both endpoint scores are 0.95. No profile, contact, or trusted phase is supplied.

| Case | Last same-frame forearm | Mixed-time “old length” after gap | Current forearm | Result for legacy G/H and paired G/H |
|---|---:|---:|---:|---|
| Elbow ends at +1; valid wrist returns at +2 | 1 | 0 | 1 | All 10 reliable return frames rejected and invalid |
| Elbow ends at −1; wrong wrist jumps to +2 | 1 | 2 | 3 | Accepted on third reliable return frame, index 32; exact wrong raw passthrough |

Both Python and Swift reproduce all eight policy/variant/case combinations. The first case remains rejected throughout the observed 10-frame return window; this is not a proof about every possible future trajectory. The second case demonstrates acceptance of a tripled forearm relative to its actual same-frame reference. These are constructed counterexamples, not prevalence or accuracy estimates.

Validation:

- `python3 scripts/motion_anchor_alignment/reproduce_edge_mismatch.py <SHA-pinned v4 exercise_motion.py> <new-output.json>`: all eight assertions pass. Historical Python SHA256 remains `c58740a36791962c9196f2c0443c9d5ae9ad71b343d6688f55614abaea57c40d`.
- `swift test --package-path ios/CalibrationEngineKit --filter MotionEdgeAlignmentWitnessTests`: 2 tests, 0 failures, each covering G/H and both policies.
- Exact synthetic rows are in `motion_edge_mismatch_synthetic_20261104.json`; the generator and Swift tests retain the full geometric construction.

## Minimal candidate design to freeze before implementation

Use a distinct opt-in edge-reference policy, leaving both current algorithms reproducible. Keep the existing 0.4–1.8 ratio bounds and three-frame persistence threshold. Store each edge from **one frame** only when parent and child are both accepted, finite, and at least 0.45 supported. Store its timestamp, endpoints, and same-frame observed body scale; never combine independently updated per-joint positions into an edge. Clear all references on every existing estimator/source reset.

For a large-innovation child, a missing/unsupported current parent or an unknown edge reference must be explicit “plausibility unavailable,” not default `true` and not a fabricated observation. Do not globally discard otherwise valid current raw output merely because this optional relocation evidence is unavailable. A future protocol must define the conservative relocation/bootstrap behavior for this case before code or scoring.

Scale must be comparable: either retain both edge and trustworthy body scale from the same frame and compare dimensionless ratios against a current trustworthy scale, or explicitly require unchanged coordinate-scale evidence. Never substitute the default 0.3 scale as measured evidence. This normalization choice belongs in the frozen candidate package and needs its own varying-scale witness.

Reference age must also be declared before implementation. Record it and clear on discontinuities. The existing 0.5-second prediction-validity bound is not automatically evidence that an anatomical length prior expires at the same rate: applying it without a defined bootstrap would prevent the valid-return witness from recovering. An age-limited reference plus independently specified reacquisition policy, or retention within a continuous source session, are distinct candidates; this reproduction does not silently choose one.

Required follow-up witnesses before any saved-data run: the two cases above, both-endpoint support loss, nonfinite parent/child, unknown edge at initialization, changed scale, long gap/reacquisition, and every reset route. No production adoption is proposed from this synthetic evidence.
