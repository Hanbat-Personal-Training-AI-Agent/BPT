# Core-three actual coaching observation export — 2026-11-02

Implemented and ran the source-defined evidence replay on all three existing phone video-as-camera captures. It preserves **usable measured values and unavailable reasons separately**; it does not approve posture, invent a profile, retime reps or activate a rule. Actual numeric observations now have definition/version/unit/layer/source-clock provenance suitable for a future explicit criteria binding. The current lack of an approved profile remains visible.

Source base654fab2, codee0600da; independent scripts-only scope. Existing `ExperimentalCoaching.swift` compiled directly. Its defaults minConfidence0.5/maxCorrectionDegrees10/maxGapSeconds0.25 are unchanged experimental observation gates, not clinical/proper-form norms. Current app caller supplies profile=nil and no source-synchronized gravity. This replay mirrors that exactly. No model/inference/training/server/media upload/device call, production/default/quiet/pose change or added bone-reliability mask. Original confidence/invalid/state and raw vs **assessment3D** layers are used; source capture constraints/adaptation provenance remains the prior audit's legacy/hybrid path.

## Actual observed versus withheld

2,398source frames,2,383genuine nonflush;5flush rows per capture excluded. Each has21warmup/no3D rows, retained as unavailable rather than zero. No source-clock substitution: PTS+rational/source index/epoch/rotation/mirror are validated by the existing strict terminal reader. All original raw files remain byte-hash identical. No actual images or joint arrays are committed.

| Capture | Genuine frames | Original candidate output | Profile status |
|---|---:|---|---|
| squat | 1,258 | No squat candidate implemented in ExperimentalCoaching | nil; no invented pass |
| pushup | 543 | 543withheld | approved_profile_required543; approved_upper_arm_range_required543 |
| barbell row | 582 | 582withheld | approved_profile_required582; phase_baseline_required582 |

Metric availability is **not** criterion approval or calibrated accuracy. A metric may retain a numeric raw/corrected value with `available=false` and explicit support reasons. Candidate absence is not a negative finding. Native candidate states/reasons are exported unchanged; no range/profile was synthesized from these sets.

| Capture / metric | Available / genuine frames | Mean supported corrected observation | Largest absolute raw−corrected difference |
|---|---:|---:|---:|
| squat/leftKneeDeg | 1237 / 1258 | 129.762155 | 5.11591e-13 |
| squat/rightKneeDeg | 1237 / 1258 | 116.080195 | 2.87059e-12 |
| squat/leftHipDeg | 1237 / 1258 | 118.984367 | 8.52651e-14 |
| squat/rightHipDeg | 1237 / 1258 | 111.934293 | 3.97904e-13 |
| squat/cameraTorsoSignedDeg | 1237 / 1258 | 24.821365 | 0 |
| squat/trunkInclineDeg | 0 / 1258 | unavailable | unavailable |
| pushup/leftUpperArmDeg | 296 / 543 | 58.081677 | 8.52651e-14 |
| pushup/rightUpperArmDeg | 326 / 543 | 25.513047 | 7.4607e-14 |
| pushup/cameraHipLineDeviationRatio | 295 / 543 | 0.034867 | 0.00827087 |
| pushup/trunkInclineDeg | 0 / 543 | unavailable | unavailable |
| barbell_row/leftKneeDeg | 561 / 582 | 151.020264 | 5.68434e-14 |
| barbell_row/rightKneeDeg | 552 / 582 | 152.708140 | 5.68434e-14 |
| barbell_row/leftElbowDeg | 561 / 582 | 117.594987 | 8.52651e-14 |
| barbell_row/rightElbowDeg | 438 / 582 | 95.853610 | 4.26326e-14 |
| barbell_row/cameraTorsoSignedDeg | 560 / 582 | 49.719259 | 0 |
| barbell_row/trunkInclineDeg | 0 / 582 | unavailable | unavailable |

Angles are degrees; cameraHipLineDeviationRatio is dimensionless. Supported means use only eligible observations and are not universal target values. The aggregate separately retains numeric-but-withheld distributions; raw/corrected difference includes all finite paired values, not just available frames. Reason counts overlap and must not be summed as independent missing frames.

Pushup upper-arm support failures: left226/right196low_joint_support plus21warmup each; camera hip-line proxy227low-support+21warmup. Squat knee/hip lose only21warmup, while right elbow has1,060low-support and3correction_disagreement occurrences (available177); its largest raw/corrected angle change18.397731°matches the existing constraint provenance. Most other angle changes are rounding-scale, which does not establish accurate pose. Camera hip-line proxy raw/corrected differences reach0.008271inpushup/0.007864inrow, with no newly invented ratio-disagreement bound.

## Exact definitions and meaningful limits

- `left/rightUpperArmDeg`: existing ExperimentalCoaching projects shoulder→elbow into the plane spanned by pelvis–thorax down and shoulder lateral axes, then measures absolute abduction from caudal trunk. It is **not proven identical** to research shoulder-elevation or angle-to-plane definitions; no45°/60°proper-form limit is copied. Variants, hand placement and intended technique remain unapproved.
- `left/rightHipDeg`: existing experimental thorax8–hip–knee definition, **not** FormWarnings' same-side shoulder–hip–knee definition. Do not alias merely because both are named hip. Knee/elbow IDs are explicit in the catalog.
- `trunkInclineDeg`: source-synchronized gravity required, unavailable on **all2,383genuine frames**. Latest device/judgment-time gravity is not the delayed/replayed source frame's physical up. It is never inferred from a normal-looking pose.
- Separate `cameraTorsoSignedDeg` and `cameraHipLineDeviationRatio`: FormGeometry functions copied **verbatim** with per-function source SHA256 and compiled natively. Fixed camera-image up=(0,−1,0), not synchronized ground up. Hip proxy is signed pelvis offset from thorax–ankle-centre line divided by line length; not lumbar curvature or force/ground-contact truth. These limited proxies cannot silently replace trunkInclineDeg. Their support/state/mask is explicit; no new ratio-correction threshold is fitted.
- Native3D is model space/pelvis relative; image hip/shoulder y is the original COCO2D pixel coordinate. Image rise velocity is not absolute3Dheight, ground travel, lifting force, lumbar diagnosis or normal-form confirmation. RTMPose scores remain unclipped and are not correctness probabilities.

The current FormWarnings observer updates its `sideView` state only for pushup/row. **Squat's logged side_view is None for all1,258frames by that source contract**, not proof the camera was physically a bad view. This missing retained view evidence blocks strict criterion-qualified timing/ranges. The adapter does not manufacture a side-view label from majority/GT or replace it with true.

## Phase-linked timing, simultaneous motion and strict ranges

Intervals require distinct contiguous source frame/index, positive actualdt, same known phase/selected side/view, usable state and required support. Gap/phase/side/view breaks are retained. Unqualified numeric endpoint arithmetic remains provided with `available=false`; it cannot become approved continuous motion. Flush never supplies eligible terminal evidence. Row/squat temporal observations use actual pulling/ascending phase metadata, not GT phase or a desired trajectory.

Squat:64observed ascending endpoint intervals, **0criterion-qualified** due unknownview. Both sides retain64numeric image hip-rise endpoint rates as unavailable contextual observations. Within original rep windows,3have finite retrospective image peak-timing differences (0.033333s/0/0) but remain unqualified;7have no internal same-ascending interval before their original report ends. No hips-first fault is inferred. Source knee/hip/camera-torso measurements remain available despite this missing timing context; unknown is not coerced to zero.

Row:169pulling endpoint intervals; bilateral knee+elbow rates simultaneously supported in83.19of83show coincident bilateral knee-angle increase and elbow-angle decrease in both raw/corrected data. This is a **signed change pattern**, without magnitude/sustain approval, force/contact/bar travel or intentional cheating evidence. It is not the existing candidate baseline: that baseline correctly stays absent without profile approval.

Row camera-torso range is available in8of10**original inclusive**rep windows:2.388–5.906°;2windows withheld for source gaps, not calculated from a favorable finite subset. Camera proxy range is not ground-referenced torso correctness. Pushup ranges are all withheld for incomplete support (2alsohavegaps); squat ranges are all withheld for missingview. Original end phases: squat5ascending/5bottom, pushup4top/6ascending, row10bottom. Therefore a counted/report endpoint does not establish a complete physical cycle or full extension. No boundary retiming/extra terminal inference was performed.

## Export contract and approval connection still missing

`coaching_observation_evidence.v1` private frame JSONL preserves source epoch/frame/index/PTS+rational, actual exercise/phase/side/view/rotation/mirror/flush/layer/gravity metadata; metrics with `value`, `rawValue`, `available`, `reasons`, `qualifiers`, exact definition/version hash/unit/coordinate/scope/required joints; original native candidates and `profile:null`. The [catalog](../../scripts/coaching_observation_replay/catalog.json) and [README/CLI](../../scripts/coaching_observation_replay/README.md) are the source binding contract. This enables a typed profile-free criteria consumer to retain provided numbers while returning unknown/no_profile. It does not authorize that consumer to compare an unrelated metric to a research limit.

Required future profile/bridge fields, not an approved profile supplied here:

- `profileId`, immutable`revision`, explicit`approvalState`, authorized approval/evidence references and exercise/variant/applicability. Initial reps are not an approval source; an `approved:true` boolean alone does not prove definition or evidence validity.
- Per criterion/atom: exact`metricId`, `definitionId`, `sourceDefinitionSha256`, joint convention, unit, raw/corrected layer, coordinate/reference-up definition, and validated mapping to the intended technique criterion. Projected abduction, shoulder elevation, camera proxy and synchronized trunk cannot be interchangeable by name.
- Explicit phase/view/side policy, bilateral quantifier, actual-window membership/inclusive semantics, comparison/operator and approved bounds/duration, complete-coverage/missing-data policy. AND must preserve known components when another is unknown; OR must preserve known-positive partial evidence. A missing constituent cannot be0or a normal pass.
- Source-linked gravity/calibration provenance where required, clock/source epoch/frame alignment, capture/profile ownership lease, and reset rules for source/epoch/profile revision/phase/side/view/gap/invalidity changes. Relative motion and retrospective range cannot masquerade as an approved absolute form standard.

No approved values/evidence mapping, synchronized gravity, reliable complete-view timing for squat, expert wrong-form labels, ground contact/force or clinical lumbar observations were added. These three reused development sets cannot validate general accuracy or real form-error FN. The next native bridge may carry this evidence and explicit unknown state, but must not manufacture approval/default activation.

## Validation, provenance and reproducibility

Native source reuse and synthetic tests passed (projected60°fixture is a synthetic math case **not** a chosen normal limit; profile=nil withheld, gravity unavailable, native±180unwrap). Python**12tests passed**: zero-vs-missing/support semantics, source time versus arrival host, phase/side/view/gap/flush/reset exclusions, strict complete-window range, side stability, exact extraction and cached-output hash rejection. Original native binary was re-executed on the identical original prepared input to resolve cache-integrity uncertainty; output bytes are **identical** to preserved native_outputs.json. Later export refinements reused that exact native source/input/output; no model inference or new native formula was run.

[Aggregate](coaching_observation_replay_aggregate_20261102.json) and [provenance](coaching_observation_replay_provenance_20261102.json) are public derived-only artifacts. Original3capture hashes unchanged; actual input arrays file unchanged. Verbatim source function hashes and compiled-extraction hash are recorded, separately from capture/input hashes; an identical formula does not imply equivalent capture/coordinate semantics. Cache reuse now requires native-output SHA256 in its manifest and rejects missing/tampered outputs. Engine/adapter/source/input hashes must also match. Original ExperimentalCoaching, production/logging/quiet/model/default/pose code are unchanged.

Private final artifacts: `~/bpt-runs/coaching-observation-replay-final-20261102/{evidence.jsonl,catalog.json,receipt.json,native_outputs.json,independent_native_recheck.json,*_intervals.json,input.json,SourceGeometry.swift,main.swift}`. Original compiled binary and selftest are `~/bpt-runs/coaching-observation-replay-20261102/{observe,self-test.txt}`. Source and binary hashes are in provenance. No media/actual coordinate arrays are committed. Read-only consumers can use final evidence/catalog directly; exclude flush for genuine-frame summaries and preserve unavailable numeric values.

Reproduce into a fresh outside-repo directory with `python scripts/coaching_observation_replay/replay.py <three-original-terminal-jsonl> --scratch <fresh-dir>`; it compiles current unchanged native ExperimentalCoaching and verbatim extracted geometry under the advisory heavy lock. For a derived-only rebuild use `--reuse-native <final-scratch>` with verified receipt; no legacy arrival-host replay contract is substituted. Run `python -m pytest scripts/coaching_observation_replay/tests -q`. This completes the actual numeric evidence export, while criterion approval and validated proper-form assessment remain explicitly missing.
