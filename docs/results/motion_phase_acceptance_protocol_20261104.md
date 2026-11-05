# Accepted-observation phase policy — frozen pre-outcome protocol

Base: `9cfe92b`. Frozen after root/Astra design approval on 2026-11-04, before candidate implementation or saved-data outcomes. This protocol follows an actual Swift reproduction of the documented legacy H ordering limitation. No candidate runtime implementation or saved-data outcome has been run. The production/app path and default H behavior remain unchanged. The previous paired-agreement and coherent-edge experiments remain separate, frozen results.

## Exact candidate boundary

Add an explicit `ExerciseMotionPhasePolicy` with `legacyRaw` as the initializer default and an opt-in `acceptedObservation` policy. Only H uses phase; A–G/HOLD retain their existing behavior. No environment flag or app activation is included. Do not change thresholds, noise, support/confidence gates, contacts, bones, expiry, persistence or model inputs.

Legacy mode executes the current ordering verbatim. The candidate H ordering is:

1. Apply the existing resets, confidence preparation and initial scale logic. Compute the usual constant-velocity prediction **without current-frame phase damping**, using the same horizon and previous state.
2. Run the existing innovation/geometry/agreement/persistence gate once on that prediction. Preserve its exact thresholds and accepted-relocation covariance/velocity resets. Record which joints took the relocation reset.
3. Call the existing phase calculation with current raw coordinates and confidence masked to zero unless the joint is both accepted and reliable under the existing gate **and its original `screen.z` is finite**. This is a phase-input rule only; the legacy confidence-clipping behavior elsewhere is unchanged. Use the same previous trusted body scale as legacy phase calculation, before the current scale update.
4. Missing/rejected phase inputs take the existing missing-input path: clear that elbow's phase position/velocity; if any required shoulder/wrist distance input is unavailable, clear distance/speed history. Do not bridge an acceptance gap using a single-frame `dt` or keep rejected raw as a phase anchor. No new time threshold is introduced.
5. Apply the existing optional caller-supplied `trustedPhase` override, separately identified in diagnostics. Its accepted strings and transition behavior are unchanged; the candidate ordering applies it after acceptance. The saved-data comparison supplies no override and no GT phase.
6. If turning is true, multiply velocities of joints 12, 13, 15 and 16 by the existing 0.3 factor. Recompute the prediction from the damped velocity for subsequent filtering, **except that accepted relocations retain their exact `pred=raw` relocation and covariance reset**. Do not rerun the acceptance gate.
7. Continue the current trusted-scale, filtering, contact/kinematic, expiry and assessment logic.

This is an ordering and phase-input package, not merely a phase-label change. Legacy acceptance itself used a phase-damped prediction, so the candidate can change accepted/rejected decisions. Report those changes and motion-suppression tradeoffs. A finite accepted observation is not ground truth; no accuracy/adoption guarantee follows from this fix.

## API and diagnostics

The independent Python module will be `scripts/motion_phase_acceptance/phase_policy.py`, exposing `transformed_source(path, policy='legacy'|'accepted_phase')` and `load_estimator(...)` returning the estimator class. It starts from exact frozen v4 Python bytes (SHA-256 `c58740a36791962c9196f2c0443c9d5ae9ad71b343d6688f55614abaea57c40d`). The legacy loader returns the unmodified source; the candidate transformation is hash bound and matches the Swift ordering.

Candidate-only diagnostics will identify policy; disjoint eligible/rejected/unavailable sets among phase joints 11–16; internal/final turning; explicit external override; the prior scale; final phase distance/speed; and preserved relocation IDs. The phase-source sets are eligibility facts, not claims that every available joint contributed to every branch. If elbow-versus-distance turning cause is not emitted at its source, report it as unavailable rather than reconstructing it.

## Required synthetic and parity gates

Before any saved-data scoring: retain original 720-checkpoint parity, show default mode unchanged, and compare Python/Swift candidate frames/phase/decisions/numerical state on the same frozen synthetic inputs. Cover the demonstrated rejected-wrist cross-joint effect, accepted turning, missing inputs, all resets/gaps, original NaN/+infinite confidence, accepted relocation preservation during turning, irregular timestamps, and explicit external phase override. Include a case proving the gate uses the undamped proposal and is not rerun after damping.

Bind source/fixture/generator/transformed-Python hashes in the passing receipt, including defaults. The replay must reject a stale receipt. Save every prediction before reading that stream's GT. No inference, training, phone or UI operation is included.

## Frozen saved-data comparison (not yet run)

Reuse the exact frozen 72 streams (60 clean plus 6 keypoint and 6 RGB stress), 42,052 frames, original source hashes and causal online profile schedule. Compare A/raw, legacy G, legacy H and accepted-phase H only; agreement and edge policies remain legacy. Reproduce complete non-timing legacy arrays against the existing results before candidate scoring. No old prediction or result file is overwritten.

Keep clean full lengths, stressed limit 270, calibration rows 21–80, activation 81 and primary score window 90:end. Reuse the same full/target errors, coverage, true-reference-motion gain/suppression, recovery/censoring and scenario/exercise partitions; report changed acceptance/phase/prediction decisions and conditional phase eligibility counts. Preserve whole-sequence and original-denominator results. Private arrays stay on Home; export aggregates/hashes only. Original protocols: `motion_anchor_alignment_protocol_20261104.md` SHA `308c8988d6f40d0bd200a13453e3b591f9146d35f00f5f3d00f56f6d9ef09766`, and `motion_edge_alignment_protocol_20261104.md` SHA `474a00f975485718e1e65c4dcef97e3a6eea9f6902eea69b30965597e6c96946`.

These are reused development streams. Even favorable results would not constitute independent validation or justify activating the candidate.

Protocol diagnostic field names: `phase_policy`, `phase_input_eligible`, `phase_input_rejected`, `phase_input_unavailable`, `phase_turning_internal`, `phase_turning`, `phase_external_override`, `phase_prior_scale`, `phase_state_speed`, `phase_state_distance`, `phase_relocated_preserved`. Each phase input set is restricted to IDs 11–16. Finite rejected reliable inputs belong to rejected; all other noneligible inputs belong to unavailable. `phase_relocated_preserved` lists relocation assignments protected from recomputation when turning.
