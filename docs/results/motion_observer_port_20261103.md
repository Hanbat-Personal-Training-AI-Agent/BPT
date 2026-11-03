# Motion/contact comparison observer port — 2026-11-03

The archived v4 `ExerciseMotionEstimator.swift` from `ai/motion-contact-20261020` is now available as an explicitly enabled, side-by-side observer in the current XS pipeline. Its algorithm is unchanged. This ports the experiment; it does not adopt G/H as a pose correction or establish that the failed accuracy results improved.

`BPT_MOTION_OBSERVER=A|B|C|D|E|F|G|H|HOLD` selects the observer. Absent/invalid values leave it off. The legacy `BPT_MOTION_ESTIMATOR` setting does not activate this new observer. XS inference, existing constraints/adaptive correction, assessment masks, warning/rep outputs, display and speech never consume the observer candidate.

Each selected L5 output receives its own stored H36M 2D observations/confidences, crop-to-image scale and exact source PTS/rational timestamp. Raw XS is centered on its original root for the archived estimator, then the candidate is converted back to the original XS coordinate basis. Output labels that basis explicitly; it is not metres or a world-ground contact position. Original raw arrays remain exact.

Source sessions are captured before asynchronous perception work. Stop, end-set, background and supersession reject late output; a tracker switch rotates only a still-active generation. Missing source evidence resets at its position in delayed emission order. Invalid source identity/geometry, nonmonotonic index/time and flushed tail rows cannot become a fresh observation. No current/future native phase is passed as a past phase: H's internal heuristic remains explicitly labelled unverified.

The observer writes inspectable JSONL to a new UUID file under `Documents/motion_observer_runs/`, including raw/candidate coordinates, correction magnitude, uncertainty, invalid masks, source stamps and `adopted_for_feedback=false`. This sink also works when ordinary `VideoRunLog` is absent. Each log is bounded to 10,000 rows, 16 MiB, and 24,576 bytes per record; reaching a cap closes it. Do not treat a capped or interrupted log as complete-run coverage. It never opens an existing run for overwrite.

Optional `BPT_MOTION_OBSERVER_FIXED_CAMERA=1` is accepted only for video-as-camera and labelled an operator assertion. Unknown live-camera contact, grip and person identity are not invented. `BPT_MOTION_OBSERVER_ONLINE_CALIBRATION=1` enables the archived initial-observation proportion collector; it resets across source sessions and is labelled an observed prior, not correct posture. A requested `BPT_MOTION_OBSERVER_PROFILE` is explicitly withheld in the current camera path because no verified profile-to-person/source association exists. The archived provenance-aware offline profile loader and its tests remain available; this is not completed runtime SMPL personalization.

## Validation and remaining scope

- 21 focused Swift tests passed, including all 720 archived Python/Swift checkpoints, stale-prediction/covariance regressions, exact baseline raw/constrained/masked coordinates and complete `FormRepReport` equality across three exercises and nine variants, delayed 2D/scale/time alignment, source/lifecycle rejection, missing-source emission ordering, online-prior reset, and bounded owned logging.
- Whole current Runner iOS arm64 typecheck passed using existing framework caches (iPhoneOS 27.1 SDK, iOS 16 target). Existing sendability and AVFoundation deprecation warnings remain. Xcode project plist lint passed.
- Before/after source hashes match for those tests and the typecheck. Receipt and logs: `/Users/6_month/bpt-runs/motion-observer-port-20261103/final-checks.json`.

This is a headless integration check, not a new phone run, model inference, natural-occlusion evaluation, clinical false-negative study or accuracy improvement. The existing [A–H/12-question status](motion_contact_status_20261102.md) and archived negative results remain applicable. Current phone validation was not modified by this separate branch. A full package regression is recorded separately after the source freeze.
