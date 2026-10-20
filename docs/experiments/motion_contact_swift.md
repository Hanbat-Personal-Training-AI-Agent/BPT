# Experimental Swift motion/contact integration

2026-10-20. Worktree `ai-motion-contact`, based on lift-app `a8b29f1`. See [the shared contract](motion_contact_contract.md) for the frozen experiment variants and coordinate definitions. This feature is disabled unless `BPT_MOTION_ESTIMATOR` explicitly selects `A`–`H` or `HOLD`. Invalid or absent values retain the previous pipeline. XS remains the lifter; its original selected output is preserved.

## Runtime path and coordinates

`MotionAGFormerLive` stores each input frame's acquisition timestamp, H36M 2D coordinates, person crop scale, orientation and optional identity/evidence with that frame's payload. The estimator receives the same row selected by the existing 27-frame, lookahead-5 path. It adds no lookahead.

The estimator receives original image coordinates divided by image height, plus XS output multiplied by `crop.side / (2 * imageHeight)`. The latter removes person-crop scale changes from the state. These remain root-relative coordinates with unknown global depth. Results and standard deviations are converted back to the existing XS crop units before evaluation. `Lifted3DFrame.raw` and the logged raw array retain the exact original XS values.

The estimator runs once, then `Pose3DConstraints` runs once. E/G/H keep the existing bone report/gate and knee/angle processing, while suppressing the second hard bone-length projection. The original constraint report remains separate. Assessment invalidation is the union of the estimator's invalid joints and the existing gate's invalid joints.

Video-as-camera traces add `motion_estimator` and `pose3d_final` to each judged frame. Real-camera experiments write numeric JSONL files under `Documents/motion_estimator_runs`; no images are written by this feature. Records include raw/corrected poses, correction magnitudes, uncertainty, roles, contact states, prediction flags, phase and diagnostics. Final assessment invalid joints are recorded separately. Estimator time is included in the performance samples.

## Explicit experiment inputs

| Environment variable | Meaning |
|---|---|
| `BPT_MOTION_ESTIMATOR=A…H` or `HOLD` | Selects a shared-contract variant; default off |
| `BPT_MOTION_FIXED_CAMERA=1` | Explicit fixed-camera/tripod evidence; never inferred from joint stillness or IMU stillness |
| `BPT_MOTION_GRIP_CONFIRMED=1` | Explicit grip evidence; exercise name alone does not enable a grip constraint |
| `BPT_MOTION_PROFILE=<path>` | Absolute or Documents-relative profile JSON |
| `BPT_MOTION_ONLINE_CALIBRATION=1` | Collect uncertain proportions from the first 60 usable selected XS rows; default off |
| `BPT_MOTION_LOG_DETAIL=0` or `1` | Logging only: 0 keeps estimator milliseconds, variant and invalid count; 1 also writes full numerical arrays (default 1 when enabled) |

For an actual camera, recent CoreMotion acceleration above `0.03 g` or angular rate above `0.08 rad/s` vetoes contact evidence and resets temporal state. Freshness tolerance is `0.5 s`. These are engineering experiment settings. Low IMU motion does not prove absence of camera translation. Video playback does not use the phone IMU as evidence about the recorded camera.

Device overhead comparisons should use the same build and input in three launches: estimator unset, estimator enabled with `BPT_MOTION_LOG_DETAIL=0`, and the same estimator with `BPT_MOTION_LOG_DETAIL=1`. The last comparison isolates the added numerical trace cost. Detail 0 does not construct the large estimator serialization dictionary or final-pose arrays; it does not change estimation or assessment.

The profile loader requires `source_type` equal to `rgb_smpl_calibration` or `rgb_smpl_crossfit`, a nonempty `source_id`, finite `calibration_confidence` in `[0,1]`, and positive finite `bone_ratios` keyed by H36M parent-child index such as `"12-13"`. Ratios use thigh-plus-shank normalization. It rejects declared GT usage and `uses_evaluation_sequence=true`. Exact mocap targets and the historical `BPT_BONE_TARGETS` input are not personal calibration inputs for this experiment. The legacy target file is ignored whenever a motion experiment is selected.

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

Online calibration is a separate, explicitly selected fallback. It uses finite edges whose endpoint confidence is at least `0.45`, requires 30 observations per retained edge, and freezes after 60 usable XS rows. The denominator is the mean of the available left/right sums of median thigh and median shank lengths. With uninterrupted input, rows 21 through 80 provide the estimates; row 81 is the first that can use them. Confidence is `0.4`. E/G/H use this profile only when no explicit profile was provided. Other variants retain the same startup timing. Missing or insufficient profile data disable only personalized correction and are recorded. These estimates do not establish that the preparation posture was good.

## Boundaries and limits

Tracking loss, camera motion, nonmonotonic/gapped time, set boundaries and capture rotation clear temporal/contact state. Online profile collection resets at pipeline boundaries. A person change also discards the previous person's explicit profile. An identity-aware caller can supply `personID` in frame context, or call the native channel method `resetMotionTracking`. The existing camera pipeline does not provide automatic person reidentification; this feature does not claim to detect an undetected person swap.

Contacts are image-plane wrist/ankle proxies. They are not palm contacts, Halpe heel/toe orientation estimates, or absolute root-relative 3D locks. Reliable motion is not pulled back to an anchor. Contact correction only affects uncertain XY when the current 2D root and observation-derived scale support it; depth remains estimated. Predicted joints remain invalid for definitive posture assessment in this initial implementation. Unknown phase imposes no future trajectory.

## Verified checks and reproduction

The independent optimized Swift executable passed all 360 expected checkpoints (four sequences, nine variants, ten selected outputs). It executed 2,880 causal updates. Maximum numeric error against Python was `1.1188966420050406e-16`, below the fixture tolerance `1e-8`; roles, states, prediction masks, invalid masks and phase also matched. The Mac harness, including fixture parsing/comparison, took `0.1734 s`. This is not an iPhone latency measurement.

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

Seven XCTest cases are prepared in `ExerciseMotionEstimatorTests.swift` and `ExerciseMotionLiveTests.swift`: Python parity, profile provenance, online observation requirements, raw/frame alignment, row-81 activation and identity reset, invalid-mask union, and gate-only bone behavior. At this checkpoint these package tests have **not** been executed. Full SwiftPM and signed iOS builds wait for the existing phone experiment to release the heavy-work lock:

```sh
lockf -k /tmp/bpt-heavy.lock swift test --package-path ios/CalibrationEngineKit \
  --filter 'ExerciseMotion|MotionAGFormerLiveTests'
```

No iPhone overhead, posture-quality improvement, warning accuracy, or adoption conclusion is established by numeric parity. The experimental app has not yet been built or measured on the phone.
