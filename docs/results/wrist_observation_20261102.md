# Actual native wrist observations — 2026-11-02

Read-only description of three reused development video-as-camera captures, native source `1a35d3f`. No new inference, labels, threshold/default changes, uploads or phone commands. This is not accuracy, clinical ROM, bad-form false-negative, or ground-contact movement evaluation. Actual exercise, occlusion and model error cannot be separated without corresponding GT. No synthetic A–H measurements are presented as phone results.

## Provenance and signal path

The three private `owned-capture-config.json` environments matched the corresponding actual `launch.json` environment arguments. Confirmed settings: mhalpe26 RTMPose, motion calibration bridge0/profile empty, XS lookahead 5/cadence 1/async 1, gravity 0, video mirror 1, rotate 0, `BPT_MOTION_ESTIMATOR=OFF`, terminal evidence/candidate/EOF flush 1; recording 0/0/1 for squat/pushup/row. Adaptive3D, support corridor and wrist anchor enables were absent (default OFF); hand wrists and same-hand dedupe disables were absent (default ON). Direct capture creation parameters supplied only exerciseId; the Flutter anchor static default was false. These are the legacy XS pipeline, **not activated G/H experiments**. No calibration target environment was supplied: constraints use the population prior then the session running median (minimum 30, window 300).

Source audit at the pinned commit:

- [CameraPosePreview.swift](../../ios/Runner/NativePose/Camera/CameraPosePreview.swift):31–56,705–733,829–927,1017–1065: RTMPose raw COCO17 and synchronous MediaPipe crops come from the **same current analysis image/timestamp**. Hand crop 256px, existing score gate 0.3. Raw frame 2D and input 2D are retained with their exact delayed XS payload; lookahead 5 is output delay, not a current-2D/future-3D pairing. Hand detection reasons/timing are not individually logged, so rejected vs missing vs deduped hands cannot be counted retrospectively.
- [MotionAGFormerLive.swift](../../ios/Runner/NativePose/PosePipeline/MotionAGFormerLive.swift):272–330: same-hand box IoU>0.5 rejects both; a proposed hand must be closer to its own raw wrist than the opposite wrist and shift less than 0.25 times the raw forearm. Accepted XY keeps **the original RTMPose score**. It is not a fresh measurement of the substituted MediaPipe location's accuracy. Selection is not based on high score alone.
- [PoseCoordinateTransforms.swift](../../ios/Runner/NativePose/PosePipeline/PoseCoordinateTransforms.swift): COCO wrists L9/R10 map to H36M L13/R16 (elbows 7/8→12/15, shoulders 5/6→11/14). `raw_2d`, `input_2d`, `assessment_2d` are the same analysis-image pixel COCO17 coordinates. The separate XS adapter square-crop normalizes to H36M17. Intervention below compares same-joint pixel arrays **before** that adapter; crop normalization is not counted as correction.
- [SimCCDecoder.swift](../../ios/Runner/NativePose/PosePipeline/SimCCDecoder.swift):179: score=min(x/y argmax values), not normalized or clipped to [0,1]. Nonpositive values preserve the score but have invalid coordinate sentinels. All measured wrist scores here are positive; scores above one occur in 80 squat-left and 20 pushup-left observations.
- XS `raw_3d` is already the result of this **hybrid RTMPose/accepted MediaPipe input**, not RTMPose-only lifting. [MotionAGFormerLive.swift](../../ios/Runner/NativePose/PosePipeline/MotionAGFormerLive.swift):233–241 applies constraints, optional adaptation, then invalid masking; Camera selects optional corridor assessment. Here adapted is absent, corridor OFF, assessment equals constrained on every usable frame. Assessment2D equals original RTMPose raw2D, not the hand-substituted input. H36M wrist confidence equals the retained RTMPose wrist score in every available frame (zero differences).

3D is XS **model-space**, without verified metre/world scale. `unit_px` is input crop pixels per normalization unit, not a 3D metre conversion. We explicitly subtract H36M pelvis0 separately in each layer for temporal 3D motion; this measures pelvis-relative changes, not hand translation on the floor. Anatomical L/R follows the model labels under mirrored input, not an independently verified physical-side label.

## Sampling and calculation

Pinned strict reader validates complete footer, sequence, layer schema, rational source CMTime versus source_pts, monotonic frame/index/PTS, source kind and stable image geometry. No arrival-host time substitutes for source time. All three are source video frames, mirrored, rotation0; image sizes squat/row720×1280, pushup1280×720. Each has five explicit set-end flush rows, excluded from all distributions. No duplicate source or tracking_lost rows and no warmup restart were found. Each starts with 21 warmup rows; no 3D is imputed for them. Zero invalid wrist/elbow/shoulder masks does not establish trustworthy angles.

Intervals use actual positive source dt. Contiguous means both pipeline frame and source index increment by one; gap endpoint averages are separate and never differentiated across. Acceleration is the difference of adjacent velocity vectors divided by their midpoint-time separation, using only three contiguous valid observations. No smoothing or invented motion/error cutoff is applied. Percentile95 is linear interpolation; median is conventional. Top decile/top three are rankings, not correctness thresholds. Complete capture does not mean every interval is eligible for a native coaching rule.

| Capture | Genuine rows | Usable3D / state ok | Source gaps (66.7ms) | Contiguous3D intervals / accelerations |
|---|---:|---:|---:|---:|
| squat | 1258 | 1237 | 4 | 1233 / 1229 |
| pushUp | 543 | 522 | 3 | 519 / 516 |
| barbellRow | 582 | 561 | 3 | 558 / 555 |

## Same-coordinate 2D substitution and 3D changes

No non-wrist XY changed, no wrist score changed. All observed changed wrist shifts satisfy the existing <0.25 forearm gate (maximum ratio0.249708); this verifies signal-path consistency, not location correctness. The unchanged counts cannot distinguish absent hands from rejected hands.

| Capture/side | Changed wrist2D / genuine | Shift when changed median / p95 / max (px) | RTMPose score median | Raw→constrained3D wrist shift median / max (model units) |
|---|---:|---:|---:|---:|
| squat/left | 1257/1258 | 5.918 / 9.435 / 13.339 | 0.908 | 0.03075 / 0.05760 |
| squat/right | 106/1258 | 13.803 / 25.752 / 28.151 | 0.360 | 0.02887 / 0.20194 |
| pushUp/left | 468/543 | 7.829 / 17.561 / 27.949 | 0.898 | 0.05239 / 0.08408 |
| pushUp/right | 543/543 | 8.107 / 14.398 / 17.010 | 0.867 | 0.06285 / 0.15699 |
| barbellRow/left | 80/582 | 5.696 / 10.458 / 17.484 | 0.890 | 0.02716 / 0.09733 |
| barbellRow/right | 59/582 | 6.076 / 9.475 / 10.856 | 0.817 | 0.02254 / 0.08000 |

Every usable raw wrist changes numerically after constraints. These are direct model-space coordinate shifts; translation/chain bone-length adjustment must not be mistaken for wrist-specific position repair. Constrained→assessment shifts are exactly zero, adapted arrays absent: that is an inactive/pass-through path, not successful adaptive correction. Assessment wrist unavailability is exactly the 21 warmup rows per capture; no subsequent withholding is signalled by this mask/state. Native requiredOK/view/side/phase/reference gates remain separate and are not reconstructed as a final coaching verdict here.

## Actual active constraints and coaching interaction

[Pose3DConstraints.swift](../../ios/Runner/NativePose/PosePipeline/Pose3DConstraints.swift):40–170 enables bone lengths, no smoothing; population/session targets as above. Knee depth reflection is enabled for squat only; detection threshold −30°, knee hyperextension clamp −15°. Interior limits: knee41–180°, elbow22–180°, hip32–180°, shoulder0–172°, spine120–180°. Angle correction >20° invalidates the child subtree; bone-only changes have no default bad-fraction gate. These are current implementation parameters, not newly validated clinical limits.

The rich log contains raw and final constrained arrays, not per-stage `Report.angleCorrections`/bone source. Consequently exact per-stage firings cannot all be recovered from wrist shifts. Directly measured elbow/shoulder angles (same definitions as those limit entries) show one substantive exception: **squat right elbow has 16 raw angles below22°, raw minimum3.602°, constrained minimum22°, maximum net correction18.398°**. All remain state ok/unmasked; this is below the configured >20° invalidation boundary. Other elbow/shoulder raw angles lie within their configured intervals; maximum raw→constrained angle differences ≤1.14e−13° (floating error). Thus most observed wrist displacement is not elbow/shoulder angular correction. Other-chain clamps may affect positions and are not attributed without stage telemetry.

An angle clamp can alter the same geometry later consumed by coaching. A sub-20° angular correction or bone-only correction can remain assessable under current defaults; this deserves explicit original/constrained provenance when interpreting warnings. It does **not** establish that actual bad posture was normalized or hidden. Raw arrays remain available and unchanged; no new gating policy is proposed here.

## Temporal distributions

All speeds and accelerations below are pelvis-relative model units/s and units/s². The aggregate also contains every layer's displacement, speed, acceleration, gap-only statistics, score distributions and changed-vs-unchanged score distributions.

| Capture/side | Raw speed median / p95 / max | Raw acceleration median / p95 / max | Assessment speed median / max |
|---|---:|---:|---:|
| squat/left | 0.144 / 0.350 / 0.935 | 2.425 / 10.583 / 32.889 | 0.143 / 1.067 |
| squat/right | 0.170 / 1.096 / 7.172 | 6.173 / 39.927 / 216.503 | 0.214 / 9.729 |
| pushUp/left | 0.174 / 0.347 / 0.830 | 2.599 / 8.252 / 36.743 | 0.185 / 1.930 |
| pushUp/right | 0.137 / 0.275 / 0.459 | 1.719 / 4.231 / 10.071 | 0.130 / 2.060 |
| barbellRow/left | 0.355 / 0.572 / 2.310 | 3.013 / 7.548 / 52.827 | 0.365 / 1.981 |
| barbellRow/right | 0.315 / 0.558 / 1.036 | 3.487 / 10.098 / 33.828 | 0.309 / 1.856 |

## Ranked source evidence

Largest contiguous raw3D speed per side, not a selected error label. Every listed endpoint has raw/assessment state ok and wrist/elbow/shoulder mask clear. Individual source rows and hashes are retained privately outside the repository; no video or coordinate arrays are committed. The aggregate includes the next two ranked events and adjacent joint displacement/score data.

| Capture/side | Source PTS interval(s) | Raw3D displacement / speed | RTMPose endpoint scores | Raw2D / XSinput2D displacement(px) |
|---|---|---:|---|---:|
| squat/left | 36.633333–36.666667 | 0.03116 / 0.935 | 0.928→0.914 | 7.004 / 9.722 |
| squat/right | 0.866667–0.900000 | 0.23906 / 7.172 | 0.385→0.388 | 1.720 / 1.720 |
| pushUp/left | 16.666667–16.700000 | 0.02766 / 0.830 | 0.231→0.183 | 86.425 / 86.425 |
| pushUp/right | 18.133333–18.166667 | 0.01529 / 0.459 | 0.875→0.884 | 0.000 / 0.178 |
| barbellRow/left | 0.900000–0.933333 | 0.07699 / 2.310 | 0.887→0.859 | 1.277 / 1.277 |
| barbellRow/right | 3.733333–3.766667 | 0.03454 / 1.036 | 0.415→0.414 | 1.277 / 1.277 |

Squat-right's largest event includes wrist-relative-to-elbow vector change0.22110 model units while the elbow moves0.02196 and shoulder0.00695; raw/input2D coincide at both endpoints. Row-left's largest event has raw2D displacement1.277px, elbow displacement0.02933, shoulder0.00844 and forearm-vector change0.04797. Pushup-left's maximum instead includes86.425px raw2D change and low scores0.231→0.183. Pushup-right's maximum has unchanged raw2D XY but elbow/shoulder movement close to wrist movement, illustrating why root-relative wrist speed alone cannot isolate a wrist tracking failure. High raw score neither rules out a large 3D change nor measures the accepted MP coordinate's correctness. No causal error source is assigned from these associations.

## Reproduction and limits

Run `python scripts/wrist_observation/analyze.py <squat.jsonl> <pushup.jsonl> <row.jsonl>` using the private immutable original captures. `--private-evidence <outside-repo.json>` optionally preserves ranked source rows/hashes locally. Public output contains only derived statistics and a combined input-manifest hash. Strict reader hash is embedded; native source is pinned1a35d3f. All three original individual SHA256 values remained unchanged from their capture receipts after this read.

`python -m pytest scripts/wrist_observation/test_analyze.py -q`: **8 passed**. Tests cover nonuniform source-time acceleration, explicit pelvis subtraction/mapping, raw scores>1, absent adapted layer, same-coordinate residual, flush/gap/reset exclusion and angle definition. Existing unchanged DEV51 tests/native builds were not rerun. These synthetic checks validate arithmetic and data handling, not exercise accuracy. No runtime code/default/model was changed.

Remaining unmeasurable here: physical/world wrist travel or floor contact, true 3D joint position, side correctness, occlusion labels, hand rejection reasons, per-stage constraint telemetry, counterfactual RTMPose-only XS output, expert form labels and clinical/accuracy improvement. These three development sets support a description of actual numeric instability and current state propagation only.

## November 3: original RGB spot-check, separate from the numerical audit

The original authorized pushup clip was decoded at source indices500/501 (16.666667/16.700000s), matching the ranked left-wrist event above. Both unmodified1280×720 RGB frames were visually inspected. The far hand is largely behind the torso/head and its wrist joint is not directly visible; the near hand is visible on the floor. The logged model-left wrist score drops0.230591→0.183472 while its raw2D point moves86.425px. This is a concrete example in which the low score coincides with poor direct wrist visibility, not proof that every low score means occlusion or that the unseen hand stayed fixed.

The source clip is unmirrored; the numerical analysis image is mirrored. No physical anatomical side, hidden joint position, contact change, or posture correctness label was inferred from this two-frame inspection. No model/correction rerun or threshold change was made. Clip/capture/frame hashes, exact coordinates, extraction method, and these limits are retained locally at `~/bpt-data/wrist-visual-observability-20261103-private/observation.json`; private images are not committed. This spot-check does not replace the missing independent motion/contact ground truth or increase any accuracy denominator.

### Matching the separate observer replay to that interval

The later [H fixed-camera/online-prior sensitivity](motion_observer_fixed_online_h_20261103.md) used the same stored raw XS and source times, with an explicit fixed-camera assumption and no new model inference. Its seventeen contact-altered joint opportunities all affect model-left wrist13: indices50–53,334–337,499–507. Each is marked prediction-used and invalid for assessment; these are candidate states, not independently labelled contact observations.

At the visually inspected transition500→501, pelvis-relative wrist displacement is0.0276633 original-XS units in the raw result and0.0017154 in the H candidate. The raw coordinates remain exact and separate. At index510 (score0.524902), the observer reports trusted passthrough and its candidate again equals the raw wrist exactly; it does not keep the old support position indefinitely. This demonstrates the intended suppression/release mechanics on this particular recorded interval. It does **not** establish the hidden wrist's true position, overall error reduction or safe suppression of real hand movement, and it does not override the negative A–H accuracy results. Detail traces are `contact-sensitivity-events.json` and `matched-contact-candidate.json` beside the private RGB observation receipt.
