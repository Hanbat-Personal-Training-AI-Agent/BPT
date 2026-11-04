# Same-frame edge reference — proposal for review, not implemented

Base `cbcdc18`; synthetic reproduction commit `9690bd3`. This proposal does not modify the frozen paired-agreement replay or the signed `6c932d2` artifact. No edge-policy implementation or dataset outcomes exist for this proposal.

## One explicit comparison policy

Add a separate opt-in edge policy on top of the paired-agreement candidate; every existing caller/default remains historical. Replace only the mixed-time parent/child plausibility reference. Preserve the present 0.4–1.8 length-ratio bounds, reliable-joint threshold 0.45, innovation threshold, agreement/persistence logic, three-frame relocation count, correction, validity, and prediction expiry.

Store an edge reference only when its parent and child are both accepted in the **same source frame**, finite, and at least 0.45 supported with finite scores. Store its length, the actual same-frame trusted leg scale, normalized edge ratio, and timestamp. Do not synthesize a reference from separately updated `lastObserved` positions. If no trusted same-frame leg scale is available, do not update the reference. A one-endpoint update leaves the earlier coherent edge reference intact. Clear references on all existing explicit, timestamp reversal/gap, person, camera, source/session, and coordinate resets.

For a large innovation, use a tri-state result:

- **Known-consistent:** a valid reference and actual prior trusted body scale exist, current parent is finite, accepted and at least 0.45 supported, and current child is finite and reliably supported. Compare current length against reference ratio × the existing previous trusted body scale `s`; apply the unchanged ratio bounds.
- **Known-inconsistent:** those prerequisites exist and the current edge is outside the unchanged bounds. Veto relocation, as the present `plausible == false` path does.
- **Unavailable:** reference/scale missing or invalid, or the current parent is unsupported/rejected/nonfinite. Do not apply a geometric hard veto. Continue through the unchanged agreement-or-persistence rule and count threshold. Record unavailability explicitly; passing without this veto is not a claim that bone geometry was validated.

This neutral treatment preserves the existing no-history behavior and avoids a bootstrap deadlock. In particular, a persistent erroneous child can still be accepted while its parent stays unsupported; this is an existing evidence limitation, not proof of geometry correctness. Never fall back to the stale mixed-time expression when the coherent reference is unavailable.

## Age and scale boundaries

Retain the last coherent reference within one continuous source/person/coordinate segment, and expose its age. Introduce no new elapsed-time threshold: the existing 0.5-second timestamp discontinuity resets the segment, while continuous low-support frames do not by themselves prove that body proportions changed. This makes the intended prior lifetime explicit rather than borrowing the separate 0.5-second prediction-validity horizon. Do not claim an old reference is a current observation.

The reference ratio uses an actually observed scale from its own frame. Its current expected length uses the pre-update trusted scale already used by the innovation gate. Never use the default 0.3 as observed scale. This removes crop-unit ambiguity and follows gradual accepted body-scale changes, but a sudden coherent scale change can be vetoed before that scale is accepted. Test and report this lag explicitly; do not claim arbitrary scale invariance or loosen thresholds to hide it.

## Required pre-outcome witnesses

Before any implementation is evaluated on saved data, freeze tests for both reproduced failures, both-endpoint support, nonfinite scores/coordinates, rejected parent, no-reference initialization and later bootstrap, unavailable-evidence neutrality, continuous long occlusion, timestamp/person/camera/explicit resets, varying per-entry crop conversion, gradual actual body-scale change, and abrupt coherent scale change. Run the original 720 parity outputs, paired-policy synthetic parity, and a same-policy Swift/Python fixture for the edge policy. Retain old policies unchanged for direct comparison.

This is a reviewable design boundary, not an adoption request or an implementation authorization.
