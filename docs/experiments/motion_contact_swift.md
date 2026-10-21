# Experimental Swift motion/contact integration

2026-10-21. Worktree `ai-motion-contact`, based on lift-app `a8b29f1`. See [the shared contract](motion_contact_contract.md) for the frozen experiment variants and coordinate definitions. This feature is disabled unless `BPT_MOTION_ESTIMATOR` explicitly selects `A`–`H` or `HOLD`. Invalid or absent values retain the previous pipeline. XS remains the lifter; its original selected output is preserved.

## Runtime path and coordinates

`MotionAGFormerLive` stores each input frame's acquisition timestamp, H36M 2D coordinates, person crop scale, orientation and optional identity/evidence with that frame's payload. The estimator receives the same row selected by the existing 27-frame, lookahead-5 path. It adds no lookahead.

The estimator receives original image coordinates divided by image height, plus `(XS output - XS pelvis)` multiplied by `crop.side / (2 * imageHeight)`. This matches the Python evaluation boundary and removes both the model's arbitrary root residual and person-crop scale changes from temporal state. These remain root-relative coordinates with unknown global depth. After converting corrected positions back to XS crop units, the current original model-root offset is added to every joint to restore the existing XS basis. Standard deviations and correction magnitudes are translation invariant. `Lifted3DFrame.raw` and the logged raw array retain the exact original XS values; trusted joints are restored from that exact array. Diagnostics include `original_model_root_offset` and its norm, both in original crop units. This is not an estimate of global camera/world root position.

A read-only check of three original Home caches established that XS pelvis output is not always zero. For `s07_65906101_pushup`, from t90 onward the largest absolute root coordinate was `0.233535` crop units, median root norm `0.013405`, and maximum frame-to-frame root change `0.140428`; the sampled squat/row streams had maximum coordinates around `0.00017`. Passing uncentered XS directly to the estimator would therefore differ materially from the centered Home evaluation on some frames. This runtime-boundary repair leaves the frozen v3 estimator and Home inputs unchanged. A live regression test varies a common root offset while the wrist is low-confidence and requires identical relative corrections, invalid masks and prediction masks, with exact original raw preservation.

The estimator runs once, then `Pose3DConstraints` runs once. E/G/H keep the existing bone report/gate and knee/angle processing, while suppressing the second hard bone-length projection. For G/H, any trusted joint moved by the legacy constraint proposal is restored to exact raw XS afterward; the proposal's quality gates remain active. Diagnostics record `legacy_constraint_proposals_only_for_trusted`, restored joint indices and proposed displacement magnitudes in XS crop units. The original constraint report remains separate. Assessment invalidation is the union of the estimator's invalid joints and the existing gate's invalid joints.

Version 2 implements `trusted_passthrough_v2`: G/H return accepted reliable current observations exactly, without Kalman position smoothing. The covariance and velocity still update for later uncertain frames. Confidence alone does not bypass the adaptive outlier gate. Rejected observations cannot act as reliable contact, parent, grip or image-scale evidence. The live boundary restores each passthrough joint from the original XS array after unit conversion, so its estimator correction is exactly zero. D/E retain all-frame Kalman smoothing as comparison variants. The experimental camera sets `requireObservedPraise=true`, so a deferred/unobserved assessment cannot become praise for a fixed warning.

Version 3, `trusted_passthrough_v3`, fixes two independently reproduced boundary errors. Innovation rejection uses the previous trusted body scale; only accepted reliable leg observations update the next scale. Image-plane contact scale likewise uses accepted reliable legs and otherwise keeps the last trusted value. Thus a huge low-confidence ankle cannot enlarge another joint's outlier tolerance. Contact candidate history also expires after more than 0.5 s without a reliable observation, including initial/reacquisition states with no anchor. Old samples cannot combine with one new observation to assert contact after a long gap. Numeric thresholds were not tuned. Version 2 source, fixture, failure inputs and outputs remain preserved in the local `v2` artifact directory; its results must not be relabeled as v3.

Version 4, `trusted_passthrough_v4`, repairs two later failures without changing experiment defaults or tuning thresholds. A relocated G/H joint now resets the complete position/velocity covariance to the existing initialization values, including a zero cross term. The v3 partial reset could produce a negative covariance eigenvalue after a long loss; the independent 240-frame synthetic reproduction is preserved under `~/bpt-runs/motion-contact/20261021-covariance-audit`, with the original v3 code and fixture in its `v3-reference` directory.

G/H prediction now advances only within the existing CV baseline's 0.35 s horizon since the last accepted observation. Covariance still propagates over the full elapsed step, so stopping position extrapolation does not reset uncertainty. After the existing 0.5 s assessment expiry, a still-unaccepted initialized joint abandons correction and returns the current raw XS value after all soft constraints. Missing raw remains missing. This fallback stays invalid, uses the prediction/uncertainty flag, and has role `uncertain_joint`; it is never relabeled trusted or normal. `expired_prediction_fallback` records the joints. The live unit conversion and legacy constraint boundary restore their exact original raw XS values, with separate `legacy_constraint_restored_expired_joints` and proposal magnitudes; both estimator and legacy invalid masks remain active.

The expiry repair addresses independently observed v3 long-loss extrapolation, including rejected observations lasting over 17 s and outputs reaching metre-scale errors. It does not establish improved quality on assessable joints. The frozen v3 results remain a failed reference, and v4 requires a separate evaluation. An old bone/plausibility reference can still delay reacquisition after real relocation; that remaining limitation is not fixed by covariance reset or prediction expiry.

Video-as-camera traces add `motion_estimator` and `pose3d_final` to each judged frame. Real-camera experiments write numeric JSONL files under `Documents/motion_estimator_runs`; no images are written by this feature. Records include raw/corrected poses, correction magnitudes, uncertainty, roles, contact states, prediction flags, phase and diagnostics. Final assessment invalid joints are recorded separately. Estimator time is included in the performance samples.

## Explicit experiment inputs

| Environment variable | Meaning |
|---|---|
| `BPT_MOTION_ESTIMATOR=A…H` or `HOLD` | Selects a shared-contract variant; default off |
| `BPT_MOTION_FIXED_CAMERA=1` | Explicit fixed-camera/tripod evidence; never inferred from joint stillness or IMU stillness |
| `BPT_MOTION_GRIP_CONFIRMED=1` | Explicit grip evidence; exercise name alone does not enable a grip constraint |
| `BPT_MOTION_PROFILE=<path>` | Absolute or Documents-relative profile JSON |
| `BPT_MOTION_CALIBRATION_BRIDGE=1` | Accept explicit native-channel calibration delivery when the estimator is enabled; default off |
| `BPT_MOTION_ONLINE_CALIBRATION=1` | Collect uncertain proportions from the first 60 usable selected XS rows; default off |
| `BPT_MOTION_LOG_DETAIL=0` or `1` | Logging only: 0 keeps estimator milliseconds, variant, invalid count and online-profile scalars; 1 also writes full numerical arrays (default 1 when enabled) |

For an actual camera, recent CoreMotion acceleration above `0.03 g` or angular rate above `0.08 rad/s` vetoes contact evidence and resets temporal state. Freshness tolerance is `0.5 s`. These are engineering experiment settings. Low IMU motion does not prove absence of camera translation. Video playback does not use the phone IMU as evidence about the recorded camera.

Device overhead comparisons should use the same build and input in three launches: estimator unset, estimator enabled with `BPT_MOTION_LOG_DETAIL=0`, and the same estimator with `BPT_MOTION_LOG_DETAIL=1`. The last comparison isolates the added numerical trace cost. Detail 0 does not construct the large estimator serialization dictionary or final-pose arrays; it does not change estimation or assessment.

Both detail levels record `motion_online_calibration_applied`, `motion_online_calibration_frames` and `motion_available_bones`. Device analysis can therefore split cost by actual profile availability instead of assuming availability from the frame index.

The profile loader requires `source_type` equal to `rgb_smpl_calibration` or `rgb_smpl_crossfit`, a nonempty `source_id`, finite `calibration_confidence` in `[0,1]`, explicit `ground_truth_used=false` and `uses_evaluation_sequence=false`, and positive finite `bone_ratios` keyed by H36M parent-child index such as `"12-13"`. Ratios use thigh-plus-shank normalization. Missing provenance does not imply valid estimated data. Exact mocap targets and the historical `BPT_BONE_TARGETS` input are not personal calibration inputs for this experiment. The legacy target file is ignored whenever a motion experiment is selected.

Example profile shape:

```json
{
  "schema_version": 1,
  "source_type": "rgb_smpl_calibration",
  "source_id": "independent-calibration-session",
  "calibration_confidence": 0.7,
  "ground_truth_used": false,
  "uses_evaluation_sequence": false,
  "bone_ratios": {"12-13": 0.4, "15-16": 0.4}
}
```

### Existing SMPL calibration adapter

`server/calibration_modal/worker.py:build_result` produces `smplBeta[10]` and `boneLengthData` with `unit: "cm"`, `skeleton: "h36m17"`, `pose: "rest"`, named `segments`, and `appDefinitionDiffers`. The adapter accepts this unchanged result under `calibration_result` in the same provenance envelope, replacing `bone_ratios`. It validates `schemaVersion: 1`, `stub: false`, `bodyModel: "smpl_neutral_v1.1.0"` and ten finite beta values, then reuses the fitted lengths; it neither re-fits beta nor treats beta as lengths.

Only the eight limb edges are eligible. Thorax/spine/head-derived segments, pelvis-to-hip offsets and entries marked `appDefinitionDiffers` are excluded. H36M indices are anatomical: right leg 1–2–3, left leg 4–5–6, left arm 11–12–13, right arm 14–15–16. The ratio denominator is the average of complete left/right thigh-plus-shank lengths in cm; at least one complete side is required. No metre-valued table is silently treated as cm, and no image mirroring swaps the anatomical sides.

For file delivery, set `BPT_MOTION_PROFILE` to the envelope JSON. For explicit app delivery, enable both the estimator and `BPT_MOTION_CALIBRATION_BRIDGE=1`, then invoke `setMotionCalibrationProfile` on the existing per-view workout MethodChannel with that same envelope. The callback reports `applied`, `available_bones`, and `calibration_confidence`. A successful delivery resets the live window and temporal/contact state before installing the profile, replacing online-profile ownership; a later person reset discards it. The trace records provenance/confidence and available-edge count, without repeating beta or the full body result.

The existing server quality fields are height residual in cm and reprojection residual in pixels, not a calibrated confidence. The backend `UserCalibration` stores `smplBeta` and `boneLengthData` strings but no source/reliability fields. `CalibrationUploadService.fetchJob` can read the actual result; the current onboarding analyzing screen uploads the capture and does not call `fetchJob` or persist/deliver the fitted result to workout. Consequently this adapter is an explicit experimental connection, not an assertion that the current onboarding UI already loads a valid profile. An integrating caller must supply documented provenance and reliability; missing fields are rejected, not guessed. No new automatic app-wide storage or UI flow is enabled.

Online calibration is a separate, explicitly selected fallback. It uses finite edges whose endpoint confidence is at least `0.45`, requires 30 observations per retained edge, and freezes after 60 usable XS rows. The denominator is the mean of the available left/right sums of median thigh and median shank lengths. With uninterrupted input, rows 21 through 80 provide the estimates; row 81 is the first that can use them. Confidence is `0.4`. E/G/H use this profile only when no explicit profile was provided. Other variants retain the same startup timing. Missing or insufficient profile data disable only personalized correction and are recorded. These estimates do not establish that the preparation posture was good.

## Boundaries and limits

Tracking loss, camera motion, nonmonotonic/gapped time, set boundaries and capture rotation clear temporal/contact state. Online profile collection resets at pipeline boundaries. A person change also discards the previous person's explicit profile. An identity-aware caller can supply `personID` in frame context, or call the native channel method `resetMotionTracking`. The existing camera pipeline does not provide automatic person reidentification; this feature does not claim to detect an undetected person swap.

Contacts are image-plane wrist/ankle proxies. They are not palm contacts, Halpe heel/toe orientation estimates, or absolute root-relative 3D locks. Reliable motion is not pulled back to an anchor. Contact correction only affects uncertain XY when the current 2D root and observation-derived scale support it; depth remains estimated. Predicted joints remain invalid for definitive posture assessment in this initial implementation. Unknown phase imposes no future trajectory.

H's phase calculation still precedes adaptive joint acceptance and uses confidence/finite observations. A subsequently rejected high-confidence observation can therefore influence inferred turning and the velocity used during occlusion. This is a remaining algorithm limitation, distinct from numerical parity and from the two v3 boundary fixes; no phase-performance improvement is established by the port.

## Verified checks and reproduction

The independent optimized Swift executable passed all 720 v4 expected checkpoints (eight sequences, nine variants, ten selected outputs). The fixture contains 800 temporal frames per variant, including a 240-frame loss/relocation/covariance sequence. Maximum numeric error against Python was `1.1188966420050406e-16`, below the fixture tolerance `1e-8`; roles, states, prediction masks, invalid masks and phase also matched. The v4 Mac harness, including fixture parsing/comparison, took `0.2617 s` during concurrent phone control. This is not an iPhone latency measurement or a benchmark comparison with earlier runs. Earlier v2 (360 checkpoints) and v3 (630 checkpoints) results remain preserved separately.

Run from the repository root:

```sh
nice -n 10 xcrun swiftc -O -j1 \
  ios/Runner/NativePose/PosePipeline/BoneLengthConstraint.swift \
  ios/Runner/NativePose/PosePipeline/ExerciseMotionEstimator.swift \
  ios/CalibrationEngineKit/Tests/CalibrationEngineKitTests/ExerciseMotionParitySupport.swift \
  ios/CalibrationEngineKit/Tools/ExerciseMotionVerify.swift \
  -o /tmp/bpt-motion-verify
nice -n 10 /tmp/bpt-motion-verify tests/fixtures/exercise_motion_cases.json
```

The fixture is loaded relative to the repository by the XCTest parity test, matching the existing package's fixture convention. The production estimator is linked into both SwiftPM targets with symlinks and explicitly listed in the Runner Xcode target. `project.pbxproj` parsing and syntax parsing of the modified live/camera/bridge files passed.

Twenty XCTest cases are prepared in `ExerciseMotionEstimatorTests.swift` and `ExerciseMotionLiveTests.swift`. Eleven core tests passed in the standalone XCTest executable with zero failures, including G/H covariance PSD and bounded stale-velocity/untrusted-raw regressions, Python parity, calibration provenance/adapter, online observation requirements, scale poisoning, contact expiry, and unobserved initialization. Nine live tests cover frame/root alignment, trusted observations, expired raw fallback after legacy constraints, calibration ownership/reset, and invalid gates; these and the full package suite have **not** been executed at this checkpoint. Full SwiftPM and signed iOS builds wait for the existing phone experiment to release the heavy-work lock. Run the entire package suite to include `FormWarningsTests.testMotionExperimentNeverPraisesWithheldPostureAsFixed` as well:

```sh
lockf -k /tmp/bpt-heavy.lock swift test --package-path ios/CalibrationEngineKit
```

Local reproduction records, source hashes, and the standalone XCTest entry point are preserved under `~/bpt-runs/motion-contact/20261020-swift-core/v4`; the previous `v2` and `v3` directories retain their snapshots and checks. Direct XCTest compilation needs the Xcode Mac platform's `Developer/usr/lib` import/library paths and `Developer/Library/Frameworks` framework path; no model inference or full app build was performed by that harness.

No iPhone overhead, posture-quality improvement, warning accuracy, or adoption conclusion is established by numeric parity. The experimental app has not yet been built or measured on the phone.

## Standalone Mac v4 cost measurement

On 2026-10-21 at 10:41 KST, the optimized standalone harness compiled and ran successfully on an Apple M4, 16 GiB RAM, 10 CPU cores. Source commit was `5f3b5dc`; runtime files matched `deda231`. The parent/device owners allowed this short independent run before the full SwiftPM/iOS build. It acquired `/tmp/bpt-heavy.lock` after the phone controller naturally released it, then handed the slot to the build owner. No phone interaction occurred in this measurement.

All 720 parity checkpoints passed first. Three warmup passes exercised 21,600 updates; ten measured passes exercised **72,000 updates**, 8,000 for each variant, preserving every frame of all eight fixture sequences (800 frames per variant/pass). Variant order rotated across passes. Estimator update and summary/detail JSON dictionary construction plus encoding were timed separately, with JSON performed after each complete estimator pass. The measured harness loop took 12.748 s.

Every table cell is **p50 / p95 / maximum, in milliseconds**, pooled across 8,000 measurements per variant:

| Variant | Estimator update | Summary JSON | Detail JSON |
|---|---:|---:|---:|
| A | 0.003958 / 0.004792 / 0.075167 | 0.005104 / 0.007541 / 0.078750 | 0.097583 / 0.122335 / 3.284042 |
| B | 0.004084 / 0.004750 / 0.046208 | 0.005000 / 0.008500 / 0.172959 | 0.105020 / 0.139186 / 1.056583 |
| C | 0.004292 / 0.005208 / 0.117542 | 0.005125 / 0.009250 / 15.629042 | 0.106167 / 0.156271 / 58.698667 |
| D | 0.004583 / 0.008375 / 20.419542 | 0.004875 / 0.012211 / 2.481792 | 0.099416 / 0.193293 / 11.864750 |
| E | 0.005041 / 0.007125 / 0.077875 | 0.004917 / 0.008416 / 0.422500 | 0.100000 / 0.148500 / 1.943959 |
| F | 0.004292 / 0.005708 / 0.528958 | 0.005416 / 0.008084 / 2.937084 | 0.099375 / 0.123044 / 16.070458 |
| G | 0.005750 / 0.009584 / 15.489500 | 0.005209 / 0.008333 / 0.245542 | 0.108292 / 0.127792 / 4.382208 |
| H | 0.005792 / 0.007083 / 0.090166 | 0.005041 / 0.007875 / 0.098625 | 0.101916 / 0.123167 / 0.409125 |
| HOLD | 0.004041 / 0.005208 / 0.054125 | 0.004917 / 0.007584 / 0.302083 | 0.097125 / 0.123333 / 6.220375 |

E/G/H each used the fixture's synthetic profile on 7,800 updates. Each variant included 3,460 updates with at least one low-confidence input joint. G/H each recorded 2,470 expired fallback joint-frames. Profile-active and occluded subgroup statistics, ten individual passes, output byte counts and invalid/prediction counts remain in the JSON artifact. This verifies that the timing denominator includes those paths; it does not validate a real person's calibration.

The one-minute system load was 7.25 before and 8.24 after, with Spotlight and other desktop processes active. The BPT lock prevented competing BPT heavy jobs, not operating-system scheduling. The large observed maxima are retained; their cause is not established and they are not stable algorithm bounds. This measurement excludes camera capture, XS inference, live root/crop conversion, online calibration collection, legacy constraints, disk/logger I/O, UI and device execution. It is neither an iPhone overhead result nor an end-to-end latency estimate.

The complete harness, result, hashes, compiler/machine/load metadata and verification record are in `~/bpt-runs/motion-contact/20261020-swift-core/benchmark/`. Reproduction is `lockf -k /tmp/bpt-heavy.lock /bin/zsh ~/bpt-runs/motion-contact/20261020-swift-core/benchmark/reproduce.sh`. The unexecuted v3 preparation is preserved separately in `prepared-v3/`.
