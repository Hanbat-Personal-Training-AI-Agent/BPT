# Motion/contact A–H evaluation protocol

Frozen before any new held-out scores on 2026-10-20. Estimator reference: `40e5edc` and the accompanying [contract](motion_contact_contract.md). Exact source, parameters, protocol, input and output SHA256s are recorded per run. Results do not select parameters. No new training, model adoption, default change, or acceptance change.

## Inputs, split, calibration

- Primary source: original pretrained XS, Halpe26 experiment-A 2D, L=5 raw caches `Home:~/bpt-runs/rules-calib/_cache/orig_halpeA`. The corresponding observed 2D is `~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d`. This uses RTMDet boxes + mmpose RTMPose; it is not the phone crop/Core ML path.
- Clean evaluation: all 96 cached streams = 8 subjects × squat/pushup/barbell_row × 4 cameras. Tuning s03/s04/s05; held-out s07/s08/s09/s10/s11. No parameter choices from held-out. Timing pilot uses only s03/50591643/barbell_row.
- Cache producer used the common original CSV/label duration. All 96 Halpe NPZ streams have the exact same 30fps prefix, with 0–3 additional trailing video frames. Trim only those extra 2D tail frames to the cached output length. Preserve every source file.
- Runtime data contains only raw XS, observed 2D/confidence/crop, timestamps and explicitly sourced personal estimates. GT poses, camera depth, true gravity, reps and viewpoint are scorer-only. GT is loaded **after all variants produce that sequence's output**. In particular, metric unit conversion uses GT root depth only in scoring and recomputes scale from the actual Halpe crop.
- Raw XS output is retained exactly. The estimator receives pelvis-relative output multiplied by `crop.side/(2*imageHeight)` and H36M image coordinates divided by image height. Invert the conversion at output. No extra lookahead: all variants use the same L5 timestamp. Camera-fixed evidence is supplied for these recorded fixed cameras; grip is never assumed.
- First usable output is t21. Every variant starts then. Online lengths use t21…80 only, both endpoints confidence≥.45, at least 30 eligible frames per edge; median edge lengths normalized by median leg length. Activate the profile at t81 with reliability .4; score from t90. Initial pose is never labelled good or used as a posture target.
- Actual RGB-derived SAM3DB→MHR→SMPL estimates already exist in `lift-refine/20261020-shapes-fit3d-{tuning,val}/subjects.json`, source code `195c0f4575d2739906c437fad3e1d925b554b760`. Input photos were selected from observed detections; no GT lengths were used. Verify source manifests and profile hashes. Confidence .7, same t81 activation.
- Those profiles combine up to eight photos, including the evaluated sequence. Only combined subject beta/lengths are saved, so cross-fitting without new SAM inference is unavailable. Treat E-SMPL/G-SMPL/H-SMPL as a **separate prior calibration assumption**, `uses_evaluation_sequence=true`. Do not claim strictly causal independent-photo validation. Main E-online/G-online/H-online use the causal initial observations. Report both.
- `~/bpt-smpl/shapes.json` is **prohibited runtime input**: its beta was fitted to mocap segment lengths. Official Fit3D SMPL-X beta is also prohibited. Personal profiles and per-frame arrays remain on Home; only aggregates leave Home.

## Variants and frozen mechanics

A raw; B causal EMA tau .08s; C constant velocity during missing observations; D fixed-noise position/velocity Kalman; E D+soft uncertain bone intervals; F contact/verified relation logic; G adaptive-confidence D+E+F; H G+causal turning evidence; HOLD last reliable position during missing observations. All mechanical constants are exactly the contract's fixed values. E/G/H online and RGB-SMPL results are distinct. Other variants are calculated once.

Primary metrics measure estimator output before existing hard constraints, preserving A as raw XS. A separate existing-gate/legacy-warning diagnostic applies the existing constraints afterward. E/G/H disable a second hard bone projection; other variants retain existing bone handling. Predicted joints remain invalid for assessment even when drawn. A withheld warning is an abstention, never a true negative.

## Controlled robustness experiments

- Fixed subset, chosen without GT: held-out s07, all three exercises, cameras 50591643 and 65906101. First 270 output frames per stream; input still includes subsequent observed frames required by L5. Six streams per condition.
- Target side is the lower mean confidence side over t21…80. Row: that wrist. Push-up: that wrist and same-side ankle. Squat: lower-confidence ankle. No GT defines target or mask location.
- Occlusion intervals are [100,103), [130,140), [170,194), [215,245): approximately .10/.33/.80/1.00 seconds. Calibration is complete first. Natural movement continues while the observation is hidden. Report recovery after each interval.
- **Keypoint experiment:** replace selected observed 2D coordinates during those intervals by the last pre-interval observation and confidence .05; additionally one erroneous x jump at frame255 of .25 observed detector-box height, confidence .95. Run actual XS on every changed 27-frame input window; unchanged windows reuse immutable raw cache. No fabricated 3D output noise substitutes for this.
- **RGB experiment:** in memory on Home, cover selected observed joint positions with gray rectangles of radius .08 observed detector-box height (minimum8px). Run actual RTMPose-m Halpe26 on the RGB, then actual XS. Use existing observed detector boxes to isolate RTMPose robustness; this is not detector robustness. No images are viewed, saved, or exported. Keep the experiment separate from keypoint perturbation.
- Synthetic estimator stress is a separate, labelled behavior-preservation check, never a replacement for these two real-inference paths: bounded/long missing wrist, visible-neighbor turning, single high-confidence erroneous jump, coherent support relocation, high-confidence sustained torso lean/valgus/hip sag. Use fixed observation-based/synthetic signals; do not use Fit3D GT as estimator input.
- Existing naturally low-confidence intervals are a **visibility proxy**, not manually verified occlusion labels. Real contact/relocation labels are absent; motion-capture support-joint movement can only provide a scorer proxy. If no natural relocation events occur, report zero events rather than a success rate.

## Metrics and interpretation

- All-frame and assessable MPJPE; limb/wrist/ankle and every joint separately; PA-MPJPE secondary only.
- Visible, naturally low-confidence proxy, artificially masked, observed-moving and observed-still strata. Visible threshold .45; low confidence .30. Image movement thresholds .10 and .02 image-height/second are fixed engineering proxies.
- Additional scorer-only root-relative GT moving stratum: speed>.10m/s, including artificially masked joints separately. Over a fixed five-output-frame interval, GT displacement>.020m is eligible; report predicted displacement projected onto GT direction divided by GT displacement, and fraction below .5 with its denominator. A stationary proxy is GT displacement<.005m but predicted displacement>.020m. These are motion-preservation/error proxies, not proof of real contact or human error detection. Future GT direction is never estimator input.
- Knee/hip/elbow and midpoint-shoulder–midpoint-hip torso angle errors; rep extreme and ROM errors. Reps and true up are scorer-only, never phase inputs.
- Velocity/acceleration error, jerk, limb length CV. Use true frame timestamps from 50fps source picks.
- Image-plane support proxy drift, observed reprojection disagreement, contact states/release/reacquisition diagnostics. No absolute world-ground lock is inferred from root-relative XS.
- Recovery: first three valid frames after occlusion with error≤max(50mm, same-frame clean original XS error+20mm), censored after one second. This is return-to-baseline measurement quality, not clinical recovery.
- Empirical uncertainty calibration: coordinate coverage within 1.96 reported sigma and radial-error/sigma. Kalman covariance does not cover all model bias by construction; show failed calibration.
- Runtime p50/p95 and zero added lookahead; existing-gate cost separately. iPhone measurements are a separate device task.
- Existing frozen `judge_py` e05f1ac side-view mirror: nominal-normal-demo fire counts and predicted-vs-GT-rule disagreements, with ≥80% valid critical-joint coverage per fully contained rep. It predates current app gates and does not constitute complete current product validation. GT-rule disagreements are **FP/FN proxies**, not human form-error labels. Report abstentions separately; no withheld-warning true negatives.
- Synthetic real-error preservation is reported as suppression/retention of known inserted signals. Fit3D normal demonstrations do not supply human incorrect-form labels, so true clinical warning false negatives and PT reliability remain unvalidated.

## Execution and completion

Home only, conda Python, CPU at most2 threads and `nice -n15`. Existing C2/2D/det/e2e/C3/rules processes and locks remain untouched. Clean comparison reuses cached XS. Benchmark before additional real inference; report actual scope and timing. Immutable source snapshot, input inventory, protocol hash, per-sequence result files, per-frame Home-only arrays and final manifest permit continuation without duplicate completed work.

This is an experiment. Failure, greater abstention or no improvement is a valid outcome; do not tune against held-out or silently enable a variant.

## Observation-priority v2 addendum

The user subsequently required trusted current observations to pass through unchanged. The v1 run remains frozen at source `83b20fa` / estimator `40e5edc` / protocol SHA256 `07a4addf5c3a3d6e827b92e888beb20300403e2d7c4163919ccd7c9231a6d222`. The v2 estimator is `b29e7c9`: G/H return current raw XS exactly for joints that pass reliability and coherence acceptance; prediction and soft corrections apply to uncertainty. A rejected joint cannot supply trusted relational evidence. Thresholds, pretrained weights, splits, damage schedules, scorers and calibration are unchanged.

Freeze this addendum and the v2 source before the additional G/H clean and damaged evaluations. Evaluate G/H online and RGB-SMPL only, reusing the exact same clean/keypoint/RGB inference caches. Report v1/v2 separately. This is a user-directed policy change, not a parameter choice based on held-out results. The v2 run cannot establish that phase handling generally improves tracking, that confidence alone guarantees truth, or that XS preserves a true pose when its reliable 2D input still produces a biased 3D estimate.

The v2 diagnostic gate wrapper also retains that priority: compute existing constraint proposals and invalid flags, then restore trusted G/H joints to their estimator output (equal to raw XS). Preserve the union of invalid flags. Save the passthrough mask, and report proposed, restored and actually applied constraint joint-frame counts separately. Primary estimator scores are unchanged by this diagnostic wrapper.

## Final correctness v3 addendum

Read-only code audits and synthetic reproductions found two correctness bugs before inspecting the new held-out scores: an unreliable leg could inflate body scale and thereby admit an unrelated gross wrist jump; contact-candidate history could survive a long observation gap and acquire contact from one returning sample. Estimator `dd6c703` uses trusted/reliable legs for body and image scale, evaluates innovations against the prior trusted scale, and clears expired anchor candidates/history. Numeric thresholds are unchanged. Observation priority and diagnostic restoration above remain in force.

V1 remains the original frozen comparison. V2 full-data evaluation had not started and is omitted to avoid unnecessary duplicate work. Freeze this addendum and the final source before v3 evaluation; rerun the complete A–H/HOLD comparison on the same clean96 and actual keypoint6/RGB6 inference caches, including online and secondary RGB-SMPL variants. This is a correctness repair with explicit failure reproductions, not held-out tuning. No further parameter selection is part of this run.

The final scorer corrects two independently reproduced accounting bugs. Warning eligibility now uses each rule's required finite metrics with the same 80% coverage threshold, including head joint10 for head rules; unsupported metrics are removed before they can seed a baseline/trend. Baseline rules require supported first-three history, trends supported first/last-three history, and previous-maximum rules supported preceding metrics. Warmup and first-rep-only non-applicability are separate from data abstention. FP/FN denominators are rule-specific.

Recovery follows each disappearance end only until the earliest of one second, the next disappearance, or clip end. Its three confirming frames must stay inside that window. Report recovered, full-one-second unrecovered and limited-follow-up events separately, with actual follow-up durations; a 0.42/0.80-second tail is not called a one-second failure. Preserve original v1 results and correct these two metric families in new scorer-only directories from the exact saved predictions, verifying original source/input/artifact hashes. Final v3 uses this scorer from its first run. Resume guards compare code, arguments and runtime input hashes. The estimator and numerical thresholds are unchanged by these scoring corrections.
