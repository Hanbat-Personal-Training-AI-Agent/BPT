# Motion prediction / adaptive contact experiment contract

2026-10-20. Separate experimental branch based on lift-app a8b29f1. Defaults remain off. No new training, model replacement, integration merge, or acceptance-rule changes.

## User requirements snapshot

Implement and quantitatively evaluate a training-free state estimator after MotionAGFormer-XS. Preserve XS and its raw output. This is for 3D posture assessment, not just rep counting or a visually smoother skeleton.

- Push-up: hands/feet support and pair spacing may be stable; distinguish support proxies from actual hand contact. Wrist articulation is allowed. Release on reliable hand/foot repositioning.
- Squat: feet support/stance/direction may be stable. Knees and pelvis move; never pin root-relative ankles. Shoulder/wrist relations depend on squat style and must not be assumed.
- Row: feet and verified grip width may be stable; wrists/elbows are dynamic. An occluded wrist must use its causal trajectory, visible elbow and uncertain forearm length, not an indefinite last-position hold. Do not assume a barbell/grip from the exercise name.
- Per-joint roles: contact anchor, relative anchor, dynamic, temporarily occluded, uncertain. Roles may change.
- Contact states: UNINITIALIZED, CONTACT, OCCLUDED, MOVING, REACQUIRE. Require stable observations to initialize; reject single-frame jumps even at high confidence; release/reacquire on coherent real motion; grow uncertainty and expire stale anchors.
- Evidence combines 2D confidence, actual image-coordinate motion, 3D continuity, adjacent-joint plausibility and causal exercise phase. Confidence alone is insufficient.
- Compare position-only hold as an additional baseline, CV, Kalman, soft personalized kinematics, contact/relative constraints and causal phase. No future phase labels or GT anchors.
- Use personal SMPL calibration estimates and reliability, not exact bone lengths. Reuse preparation evidence as candidates, never declare an initial bad pose to be normal.
- Keep raw/corrected pose, correction magnitude, uncertainty, role, state and per-metric invalidation available. Do not normalize away valgus, wrist relocation, torso lean or other genuine form errors.
- Keep ground support, body-relative relationships, bone lengths and trajectories in their appropriate coordinate systems. Without camera/root evidence, abstain from 3D ground locking.
- New corrective functionality stays disabled by default until separately approved.

Required evaluation: occluded/visible/moving segments separately; wrist/limb MPJPE, per-joint error, angle error, jitter, support stability, true relocation detection/reacquisition, false movement suppression, recovery time, uncertainty calibration, added latency, 3D warning false positives/false negatives/abstention and iPhone cost.

Include short/long occlusion, motion during occlusion, disocclusion, real support changes, sudden erroneous jumps, row wrists behind torso, far push-up limbs, and squat ankles. Keypoint corruption followed by XS and RGB masking followed by RTMPose+XS are separate experiments. GT is scorer-only. Existing natural occlusion must be described with its annotation limitations.

Final report answers: causes of XS errors; predictive range of wrist velocity; Kalman vs smoothing; SMPL benefit; phase at reversals; actual support stability; valid/invalid contact regimes; relocation success; jump reduction; true-error suppression; PT reliability; iPhone overhead. Separate facts, hypotheses, implementation limits and adoption advice.

## Variants and timing

All consume the same original XS output at its current L=5 timestamp, with the same matched 2D frame. Estimator has no extra lookahead. Ground-truth segmentation is used only by the scorer.

| Variant | Algorithm |
|---|---|
| A | unchanged raw XS |
| B | causal exponential smoothing, tau 0.08 seconds |
| C | constant-velocity prediction during low-confidence/missing observation |
| D | position/velocity Kalman filter, fixed measurement noise |
| E | D plus soft bone-length intervals from an explicitly sourced calibration profile |
| F | exercise contact/verified relative relationships, without temporal Kalman |
| G | confidence/innovation-aware Kalman + soft kinematics + adaptive contact |
| H | G + causal phase/turning evidence |
| HOLD | extra diagnostic: last reliable position during occlusion |

Do not silently redefine variants. Missing calibration or fixed-camera evidence disables only that component and is logged. A missing component is not evidence that the component fails.

## Shared API

Python: `pose_feedback.geometry.exercise_motion.ExerciseMotionEstimator`

Constructor:
`ExerciseMotionEstimator(exercise, variant="G", bone_profile=None, calibration_confidence=0.0)`

Exercises: `"pushup"`, `"squat"`, `"barbell_row"`. Variants as above.

Update:
`update(raw, screen2d, timestamp, *, fixed_camera=False, camera_motion=False, person_id=0, phase=None, grip_confirmed=False)`

- raw: H36M 17x3, canonical root-relative `(XS - XS[0]) * crop.side / (2 * imageHeight)` in image-height units. XS can retain a nonzero pelvis residual; explicitly subtract it before temporal processing. This boundary conversion prevents changing XS crop scale or root residual from becoming apparent motion. It supplies no global root or metric depth. The app separately retains the exact original XS output, divides corrected values by the same scale, and adds the current original XS root to restore the output basis. Uncertainty and correction magnitude are translation invariant and use the scale conversion only.
- screen2d: matching H36M 17x3 (x/imageHeight, y/imageHeight, confidence), original camera frame before XS crop normalization; not pixels or crop coordinates. Relative anatomical labels follow the existing H36M mapping.
- timestamp: seconds for this emitted pose, monotonically increasing; no wall-clock processing duration.
- bone_profile: optional dict `"a-b": ratio` where ratios are bone length divided by sum of median thigh + shank lengths from the same calibration estimate. Actual runtime scale is estimated only from observed pose. Include calibration provenance externally; confidence 0 disables the component.
- fixed_camera: explicit fixed-camera/tripod evidence. IMU stillness alone does not prove camera translation is zero. Recorded fixed-camera video can explicitly supply true.
- camera_motion/person change/reset/nonmonotonic time: clear temporal/contact state.
- phase: optional trusted causal phase; normally None. H may infer turning evidence from past/current reliable joint motion only. Unknown phase does not impose a trajectory.
- grip_confirmed: explicit evidence, default false. Exercise name is not confirmation.

Return a dict:
`raw`, `corrected` (17x3), `correction_magnitude`, `uncertainty` (17 standard deviations in the supplied normalized units), `invalid` (17 bool), `roles` (17 strings), `contacts` (joint-index strings -> state strings), `used_prediction` (17 bool), `phase`, `diagnostics`.

Swift mirrors these fields with SIMD values. Keep the old constraint report and raw output. The new estimator runs once before existing constraints. E/G/H use existing constraint gates without a second hard bone projection; other variants keep the prior constraints. Do not project inferred joints into a canonical good posture.

## Initial fixed parameters / mechanics

These are engineering starting values, not validated physiological thresholds. Freeze them before the first held-out run. Report failures rather than changing parameters against held-out results.

- Joint body scale: median of accepted, reliable, finite thigh+shank lengths (edges 1–2–3, 4–5–6), falling back to the last trusted scale. Innovation testing uses the previous trusted scale before accepted observations update it. Image-space contact scale separately retains trusted 2D leg evidence. All body-distance limits below are multiples of this model-unit leg length. The original v1/v2 behavior is preserved in its source snapshots; this evidence restriction is the v3 correction described below.
- Reliable confidence threshold .45; missing/low threshold .30.
- Smoothing tau .08s. CV maximum useful horizon .35s; hard assessment expiry .50s.
- Kalman: independent xyz constant-velocity filters with shared 2x2 covariance per joint; acceleration std 1.5 leg-length/s²; fixed observation std .03 leg-length (D/E). G/H observation std `(0.015 + 0.10*(1-confidence))*leg-length`.
- F=[[1,dt],[0,1]], Q=acc²[[dt⁴/4,dt³/2],[dt³/2,dt²]]. Joseph-equivalent symmetric scalar update; keep covariance nonnegative. No observations after the current timestamp.
- Preserve initialized state during a single missing frame; grow uncertainty with time. Reject a one-frame large 3D innovation (> .25 leg length) without corroborating 2D/adjacent-joint continuity. Three coherent reliable observations can establish actual relocation; confidence alone never suffices.
- Contact proxies: push-up H36M wrists13/16 and ankles3/6; squat/row ankles3/6. Wrist proxies permit an articulation radius. No actual palm-contact claim without palm evidence.
- Contact coordinates are the original normalized image plane. Stable initialization 8 reliable frames; motion confirmation 3 coherent observations; reacquisition 5 stable frames; expire useful anchor after .5s without reliable support. Contact radius .035 of visible 2D leg length; release radius .10. Low-confidence single jumps never reset anchors.
- Contact is not an absolute root-relative 3D lock. Only low-confidence screen-plane estimates may be reconciled with an image anchor using a reliable current 2D root and a robust observed model-units/image-units scale; retain depth uncertainty. If either is absent, keep the 2D state for diagnostics and abstain from 3D contact correction.
- Bone intervals tolerate ±15%, widened by low calibration confidence. Soft correction is confined to uncertain dynamic distal joints, uses a reliable adjacent joint, and is capped at .10 leg length. Reliable real joint motion is never forced back to an anatomical target. Profile missing => no personalized correction.
- Verified grip may constrain only a relative separation interval and only on unreliable observations; otherwise disabled. Do not fix shoulders/wrists in a generic squat.
- H: detect a directional reversal only from reliable observed motion/adjacent-joint evidence; damp extrapolated velocity at uncertain transition, never use GT phase or a future rep boundary.
- Assessment invalid if missing/nonfinite, stale >.5s, prediction is unsupported, uncertainty >.15 leg length, or correction >.08 leg length. Preserve previously invalid joints from existing gates. Report abstention and coverage rather than treating a withheld warning as a true negative.

## Experiment data restrictions

Fit3D stays on Home; use existing conda environments. No image viewing/export/cloud transfer. RGB masks may be generated numerically on Home for the authorized experiment.

Separate actual RGB-derived personal calibration estimates from mocap-fitted/GT shape simulations. The latter must not enter estimator input. Calibration frames should be independent of the evaluated sequence; if existing profiles use that sequence, cross-fit/exclude those estimates or mark the separate-calibration assumption explicitly and do not claim strictly causal deployment validation.

Only scoring may read GT, camera depth, labels, exercise phase/rep bounds or validity annotations. Corruption schedules and mask placement use fixed frame counts, observed 2D, and seeded randomness. Keep raw input/cache hashes and per-variant manifests. Synthetic posture perturbations assess behavior preservation; without human error labels they are not clinical false-negative measurements.

## User clarification: trusted observations pass through (v2)

On 2026-10-20 the user explicitly clarified that genuinely observed joints must
follow current observations and that prediction/constraints are for uncertain
observations. The original `40e5edc` algorithm and `83b20fa` evaluation snapshot
remain the v1 ablation; do not overwrite or relabel those results.

The v2 G/H candidates return the current raw XS position **exactly** whenever
the joint is finite, confidence is at least `.45`, and the causal consistency
gate accepts it. Internal velocity and covariance are updated for possible
subsequent occlusion, but filtered position does not replace a trusted current
position. Recovery also returns directly to an accepted observation. Rejected
high-confidence jumps are not trusted merely because of their confidence.
Rejected adjacent joints cannot provide contact scale/root or bone/relative
constraint evidence. All numeric thresholds remain fixed.

This concerns the new estimator boundary. XS still estimates 3D from observed
2D, and the existing downstream quality gates remain separate. Raw XS,
estimator output, final constrained output and invalid masks are separately
observable. B and D/E remain smoothing/filter comparison arms. In G/H, visible
raw jitter can therefore remain; suppressing valid visible movement is not an
acceptable way to reduce it. Report v1 and v2 as distinct algorithms.

The experimental G/H live boundary also restores those same trusted joints
after existing constraints have calculated their proposals and quality gates.
The exact raw XS position survives to the final pose; existing invalidation
still withholds assessment where appropriate. Log proposed, restored and
actually applied corrections distinctly. The disabled/default path and other
variants retain their original downstream behavior.

Any experiment that withholds posture assessment also requires sufficient
observations before saying a previously reported problem was fixed. The
experimental `requireObservedPraise` setting prevents a missing warning due
to uncertainty from becoming a false improvement claim.

## Independent evidence-validity audit: v3

Before the final device build, independent synthetic probes reproduced two
logic defects in v2. A low-confidence, grossly wrong ankle inflated the body
scale and thereby widened the innovation gate enough to accept an unrelated
wrong wrist. Also, contact candidates without an initialized anchor survived
a long observation gap and could become CONTACT after only one new sample.
These are correctness fixes, not changes chosen from held-out accuracy.

V3 initializes scale only from finite, reliable leg chains. Innovation gates
use the previous trusted body scale. Accepted reliable leg chains may then
update the body scale; trusted image-space leg chains update a separately
retained image scale. Missing/untrusted chains retain the prior scale rather
than contributing huge or invented lengths. No numeric threshold changed.
All contact history, relocation candidates and established anchors expire
after the same existing `.5 s` gap, including UNINITIALIZED/REACQUIRE states.

Original v1/v2 sources/results remain distinct. Final A–H comparisons use the
same v3 scale evidence handling for every arm. The numerical fixture adds
three corresponding cases (seven cases × nine variants × ten checkpoints =
630 comparisons). Regression tests also cover a first frame with no trusted
observations, including nonfinite raw positions.

## Device availability update

The user instructed that from 2026-10-21 00:00 KST onward, work must proceed
without the iPhone. Device launches, installations, log retrieval and connection
retries stop before that boundary. Preserve partial runs and logs already on
the phone. Continue the Home experiments and laptop tests/builds. Any unfinished
rotation or estimator-cost measurement must be reported as unmeasured;
desktop timing cannot substitute for iPhone real-time validation.
