# Per-segment bone-correction reliability — 2026-11-02

**All-error MPJPE stays146.893640mm on the unchanged568,004joint-frame denominator.** Implemented and evaluated **one scripts-only, OFF-runtime uncertainty diagnostic**. It preserves all raw/full coordinates and adds only affected-joint invalidity when the original bone stage expands a segment by **more than4×** or its required evidence is unsupported. This is an uncalibrated numerical engineering flag, not an anatomical/medical/error threshold. It is not activated in the app and does not improve MPJPE by changing poses.

Native3: it marks the collapsed-right-arm full-speed worst interval uncertain, adding32joint-frames over18squat frames. It does not mark the raw-speed maximum, pushup/row target-transition jumps, or other finite within-bound errors. Fit3D60:102additional joint-frames (pushup ankles in3streams), with full-denominator error **unchanged146.893640mm**. Nongated errors still reach1,015.746mm. These results do not establish an accurate general error detector, true form-error FN, safety success or adoption readiness.

## Protocol, API and source isolation

[Protocol](bone_correction_reliability_protocol_20261102.md) and Swift module frozeneacdece, mirror/numerical overflow guard ec4909c, input-boundary clarification4cd98ff, numerical verification addendumfa95e71; scorer frozen c314739 before actual statistics. Expansion4 was fixed once and never swept/tuned. New files are under `scripts/bone_reliability`; no Runner/Xcode source registration, camera callsite, assessor/count/threshold/default/model/target/history change. No smoothing or position correction. Previous failed continuity code/results remain unchanged.

Inputs: current raw H36M17, original `BoneLengthConstraint` segment report/scale, existing invalid mask. All8original constrained limb edges are visited in deterministic joint order. The output contains per-segment observed/output lengths, absolute length correction, expansion ratio, status/reasons and forensic-existing/additional/union invalid masks. **No coordinates are returned.** A flagged upper arm affects elbow+wrist only; a shin affects ankle only. Raw nonfinite joints affect their own subtree; other legs/arms remain available unless separately unsupported. Existing valid-index invalidity is never cleared.

Supported finite expansion≤4 is `within_candidate_bound`, **not normal/correct/confident**. Missing/invalid target/scale, absent/malformed/unprojected segment evidence, degenerate/nonfinite raw or output and inconsistent observed lengths are separate unsupported reasons. Existing numerical minimum length1e−6 matches the production bone solver; raw/report length agreement uses1e−10×(1+length) only as an integrity tolerance. Ratio division overflow is unsupported. No 2Dscore is an API input or can override these states.

Malformed pose or mask yields global uncertainty on indices0…16. Original malformed mask evidence (e.g.99) stays forensic, but operational masks never contain99. Python guards None/nonsequence rows, nonhashable/mixed masks and missing report fields rather than raising accidental TypeError or claiming normal. Swift typed inputs and Python's extra malformed-input guards are explicit. Unsupported target/scale ordinarily affects the known constrained limb subtrees, not an arbitrary whole-body bone-fraction switch. The existing `badBoneFraction=nil` behavior is not enabled or duplicated.

## Verification failure preserved; complete gates before statistics

The initial exact-zero native **recomputation** gate stopped at squat frame21:8.67e−19 coordinate difference, identical empty invalid masks. The first assertion failures and later explicit failure receipt are retained privately. After this failure and before reliability statistics, root approved and we froze the existing numerical tolerance **finite max≤1e−12**, exact existing masks and original-array/file hashes. This changes verification tolerance after observing a numerical failure, not the candidate4bound. Optimizer/call-context rounding is a hypothesis, not a proven cause. No bitwise-native-recomputation claim is made.

Final native baseline:119,085components, max4.1633e−17,4,522nonzero differences; original existing masks exact. Original3Swift source hashes match earlier pinned1a35 sources, original3capture file hashes match their receipts, original stored raw/full input file unchanged, Swift raw arrays unchanged. **Scoring/descriptive kinematics always use the original stored coordinates**, never these re-evaluated floating-point variants.

Swift/Python evidence parity:18synthetic cases and2,335actual emitted rows, maximum evidence/ratio/status/mask difference0. Synthetic cases cover normal, strict4boundary, collapsed/mirrored arm, current direction reversal, zero/nonfinite joint, target/scale/report failure, missing projection, prior-mask union, out-of-bounds forensic mask and malformed pose. Python23tests passed, including malformed/nonhashable inputs, missing fields, raw/report immutability and preserved current direction; module has no confidence override or coordinate-output interface. No GT enters these checks.

Home full-cache gate:1,915,152recomputed baseline components, max0/nonzero0, exact masks. Full-cache hashes unchanged before/after; original raw/GT used input hashes unchanged after processing. Reference22source/dependency files match exact gitfe0bc62, including bone_lengths/hinge_limit/package initializers. Current-root Python code is not silently substituted. Home synthetic parity is required before data processing.

## Native3 coverage and original worst events

These are the same three development video-as-camera captures, not independent new exercise trials. Original layer/mode/source clocks and hybrid RTMPose/MediaPipe input provenance remain as prior audit. Source PTS, rotation, mirror and distinct-source checks come from the strict reader. Each has21warmup/no3D rows and5explicit flush rows; reliability statistics use only genuine nonflush usable rows. Source gaps4/3/3 remain separated, not turned into new terminal observations. Original reps, reports, state labels and coordinates remain unchanged. No GT exists for these captures.

| Capture | Usable genuine frames | Additional joint-frames / affected frames | Partial / whole union frames | Whole-pose-if-any additional valid joint-frames lost |
|---|---:|---:|---:|---:|
| squat | 1237 | 32 / 18 | 18 / 0 | 306 |
| pushUp | 522 | 0 / 0 | 0 / 0 | 0 |
| barbellRow | 561 | 0 / 0 | 0 / 0 | 0 |

Only squat right elbow14/right wrist18joint-frames are newly uncertain; every other joint count is0. There are20flagged segment instances across18frames; no unsupported-input cases in these actual logs. All originally usable masks were empty. Counterfactual whole-pose withholding on any new flag would discard306joint-frames versus partial32; this is a coverage comparison, not another runtime candidate or a change to legacy badBoneFraction.

Each original raw/full maximum remains visible, with the proposed wrist mask at **both endpoints**. Units are pelvis-relative XS model units/s, not mm/metres or floor travel. All ranked top3per side/layer are preserved in the native aggregate.

| Capture/side | Original raw maximum interval/speed | New wrist invalid endpoints | Original full maximum interval/speed | New wrist invalid endpoints |
|---|---|---|---|---|
| squat/left | 36.633333–36.666667 / 0.934848 | [False, False] | 36.633333–36.666667 / 1.067418 | [False, False] |
| squat/right | 0.866667–0.900000 / 7.171714 | [False, False] | 38.233333–38.266667 / 9.728887 | [True, True] |
| pushUp/left | 16.666667–16.700000 / 0.829899 | [False, False] | 1.700000–1.733333 / 1.930285 | [False, False] |
| pushUp/right | 18.133333–18.166667 / 0.458804 | [False, False] | 1.700000–1.733333 / 2.060051 | [False, False] |
| barbellRow/left | 0.900000–0.933333 / 2.309571 | [False, False] | 0.900000–0.933333 / 1.981456 | [False, False] |
| barbellRow/right | 3.733333–3.766667 / 1.036214 | [False, False] | 1.700000–1.733333 / 1.855524 | [False, False] |

Squat-right full maximum38.233333→38.266667s is newly uncertain on both samples: the already measured upper-arm expansion10.512×/11.605× exceeds4 and affects elbow/wrist. This flags **structural amplification**, not a GT error/form label. Its raw maximum0.866667→0.900000s is not flagged. Pushup full maxima1.700000→1.733333 and row-right maximum at the same target-source transition remain unflagged: the diagnostic cannot certify target-transition continuity, raw direction quality or arbitrary bias. Scores are retained RTMPose outputs, not probabilities or fresh MediaPipe position accuracy; they do not override the structural masks.

## Fit3D60: unchanged coordinates/errors and extra coverage selection

Same previously evaluated validation60streams, not fresh holdout, original RTMDet/RTMPose Halpe→XS L5. No new model inference/GPU/training/media upload/phone. CPU1/nice19,28sdescriptive processing. Source times retain pick/50Hz. The original full targets/report state was reconstructed from raw only before history update, with minimum30/window300 and squat reflection only; old full predictions/masks are exact-gated. The diagnostic is stateless. GT joint/camera/rep files are opened only after the entire stream's new masks/evidence are saved. Historical results metadata, including old score summaries, is read upfront only for fixed-list/source compatibility and is never fed into the diagnostic.

All17joint/time error denominators are unchanged, including root-relative pelvis zero and masked predictions. The full all-error MPJPE is146.893640mm before and after. No filtered/corrected pose is generated. GT root-depth/focal conversion is scoring-only; it does not make runtime model-space correction lengths physical units. Existing source/GT mappings match the prior A compatibility gate. Main[90:N), prior[21:51), early[51:90), tail5-excluded sensitivity remain predeclared. Last5edge-clamped rows stay in primary; they are not new terminal evidence.

| Partition/exercise | Joint-frames | Additional withheld joint-frames | Unchanged all-error mean(mm) |
|---|---:|---:|---:|
| main/all | 568,004 | 102 | 146.893640 |
| main/barbell_row | 174,216 | 0 | 123.805470 |
| main/pushup | 143,480 | 102 | 233.522428 |
| main/squat | 250,308 | 0 | 113.306339 |
| prior/all | 30,600 | 0 | 85.616273 |
| early/all | 39,780 | 0 | 134.861047 |
| tail5_excluded/all | 562,904 | 102 | 147.389908 |
| tail5_excluded/barbell_row | 172,516 | 0 | 124.150281 |
| tail5_excluded/pushup | 141,780 | 102 | 235.163550 |
| tail5_excluded/squat | 248,608 | 0 | 113.459626 |

Additional102joint-frames =right ankle38/left ankle64, all pushup,102frames across3of60streams. They are correlated observations, not102independent events/people. Additional share102/568,004=0.01796%; existing566plus102=668union invalid joint-frames. There are209partial union frames and0whole-pose union frames. A whole-pose-if-any-new-flag fallback would remove1,715previously valid joint-frames versus102with subtree invalidity (19old-invalid joint-frames already overlap those affected frames). This hypothetical coverage count does not apply a second algorithm or alter coordinates.

There are102`expansion_above_4` segment instances over all usable raw rows;300,314within-bound instances; actual unsupported-input count0. Unsupported behavior is tested synthetically, not assumed validated by these observed data.

Matched errors use **the identical original full coordinates** within each subset. The old-mask-valid subset before this diagnostic is567,438joint-frames with mean146.578869mm. Removing102more yields567,336with mean146.502336mm. This conditional decrease is **selection/withholding**, not an MPJPE improvement. The all568,004mean remains unchanged.

| Main subset | Joint-frames | Full error mean / p95 / max(mm) |
|---|---:|---:|
| all | 568,004 | 146.893640 / 385.358927 / 1015.745975 |
| existing_invalid | 566 | 462.464190 / 737.624712 / 951.383384 |
| additional_withheld | 102 | 572.263319 / 783.197032 / 839.315993 |
| union_invalid | 668 | 479.229925 / 755.944735 / 951.383384 |
| remaining_not_invalid | 567,336 | 146.502336 / 382.603459 / 1015.745975 |

Additional-withheld error spans339.073–839.316mm; raw RTMPose scores there span0.098–0.544(mean0.311). Remaining scores span0.055–1.188(mean0.746), unclipped and not calibrated correctness probabilities. These associations do not establish detector precision, false positives, clinical wrong-form thresholds or justify substituting a confidence gate.

## Nongated errors and fixed worst cases remain

The remaining maximum is still1,015.746mm, exceeding every newly withheld error. Absence of this specific expansion flag must **never** be promoted to normal/confident/correct or native rule eligibility. Existing view/requiredOK/reference/phase rules were not replayed. Example derived source cases, no subject/camera/stream identities:

| Exercise/joint | Source index/time(s) | Full error(mm) | RTMPose raw score | Proposed invalid |
|---|---|---:|---:|---|
| pushup/left_ankle | 182 / 6.06 | 1015.745975 | 0.677307 | False |
| pushup/left_ankle | 178 / 5.94 | 1015.657381 | 0.674100 | False |
| pushup/left_ankle | 180 / 6.00 | 1014.964227 | 0.668357 | False |
| pushup/right_ankle | 146 / 4.86 | 1002.927149 | 0.695927 | False |
| pushup/right_ankle | 144 / 4.80 | 1000.752505 | 0.693305 | False |

All listed errors are on non-tail main rows and are already unmasked in the old full baseline. Finite2Dscore does not establish3D correctness, and no true posture/occlusion cause is assigned.

The previously frozen continuity worst-worsening case (squat left wrist index112/time3.74s, full300.651823mm) is **also not flagged**: original upper-arm expansion0.9193 and forearm1.0289 are within the fixed bound. The old continuity candidate's later error349.536877mm belongs to that separate rejected experiment; it is not a coordinate output from this reliability diagnostic. This module does not solve target lag, every large error, or the missed raw wrist jumps shown above.

## Reproduction, source integrity and closure

[Native aggregate](bone_reliability_native_aggregate_20261102.json), [Fit3D aggregate](bone_reliability_fit3d_aggregate_20261102.json) and [provenance](bone_reliability_provenance_20261102.json) contain derived coverage/evidence/error statistics, source/hash gates and failure metadata only. No actual raw/full arrays, image/video or individual subject/input hashes are committed. Native3original file hashes match receipts at closure; Home200used raw/GTinputs and old full-cache files remain unchanged, reference22files match gitfe0bc62, experiment source hashes match the executed files. Public Home aggregate byte hash matches Home.

Private Mac: `~/bpt-runs/bone-reliability-native-final-20261102/{input.json,native_result.json,synthetic.json,parity.json,receipt.json,replay,main.swift,median.swift}`. Initial strict-zero attempts remain in `bone-reliability-native-20261102`, `bone-reliability-native-v2-20261102`, `bone-reliability-native-v3-20261102`; v3hasexplicit`native_result.json.failure.json`. Previous continuity/native raw artifacts are preserved.

Private Home: `~/bpt-runs/bone-reliability-20261102/{code/,results/aggregate.json,results/diagnostics/stream_*.npz}`. Existing full outputs remain in `~/bpt-runs/target-continuity-20261102/results/predictions/`; original frozen Python reference `~/bpt-runs/motion-contact/_code/fe0bc62`. No new dependency/compiler was installed on Home.

Reproduce only into fresh outside-repo/private destinations:

```sh
python -m pytest scripts/bone_reliability -q
python scripts/bone_reliability/run_native_audit.py <three-original-captures> --scratch <fresh-outside-repo-dir>
python scripts/bone_reliability/check_parity.py <scratch/synthetic.json> --input <scratch/input.json> --result <scratch/native_result.json>
python scripts/bone_reliability/summarize_native.py <three-original-captures> --scratch <scratch>
# On existing Home CPU environment, code and synthetic-only fixture already present:
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 PYTHONHASHSEED=0 nice -n19 <bpt-home-python> <code>/evaluate_home.py --synthetic <code>/synthetic.json --out <fresh-private-results>
```

Swift compilation uses the advisory heavy lock and unchanged native sources; no iOS build/device/inference is needed or claimed for this scripts-only module. Core gates and original-error identity must pass; no malformed/unsupported input is silently normalized or scored as correct. Fixed4hasnotbeenretuned after seeing these distributions. This completes the bounded uncertainty engineering experiment, **not a general accuracy/safety/FN validation or an app-adoption recommendation**.
