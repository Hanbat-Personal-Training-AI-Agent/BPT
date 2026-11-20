# Native constraint contribution — 2026-11-02

Follow-up to [actual wrist observations](wrist_observation_20261102.md), same three immutable development captures and source1a35d3f. This ranks **assessment/constrained**, not only raw, wrist changes. Assessment equals constrained here; no adaptation/corridor is active. No inference, GT, runtime/default/threshold changes, uploads or device commands. Results concern model-space coordinate processing, not physical movement, actual error, posture normalization or accuracy improvement.

## Reconstruction gate

The unchanged production `Pose3DConstraints.swift`, `BoneLengthConstraint.swift`, `KneeHingeLimit.swift` were compiled together with `constraints_replay.swift`. The sole dependency shim is `FormWarningTracker.median`, extracted verbatim from its pinned source rather than reimplemented. Source SHA256 values and helper hash appear in the aggregate receipt. No model or perception code is linked.

Input is each original already-predicted raw3D array in native emitted order, including explicit flush rows to preserve state/history. Source setting is population/session target fallback, no supplied calibration profile; squat reflection flag matches production. Pose3DConstraints consumes raw joints and prior history only: confidence/source timestamps are not inputs to this class, and adaptive/corridor are OFF. We do not supply a new profile, GT, target angle or replacement confidence. Warmup has no raw array and never invokes apply. No tracking resets occurred. This reconstruction is validated, rather than assumed from the missing detailed original per-stage log.

**All119,085 constrained coordinate components (1,242/527/566 emitted rows ×51, including flush) reproduce exactly: max absolute difference0.0. Every invalid mask also agrees.** No ablation is summarized unless this full-array parity gate passes. Genuine nonflush usable rows remain1,237/522/561. Same contiguous actual-source-time intervals and pelvis-relative definition as the prior audit; gaps are excluded. Private row-level replay arrays stay outside the repository.

Independent counterfactuals on identical stored raw arrays:

- Full: unchanged production stateful constraints.
- Bone-only: unchanged bone stage/history; remove reflection, knee clamp and interior angle rotations. Knee detection does not change coordinates.
- Angle-only: remove bone stage; keep original angular settings/reflection. This is independent, not a subtraction from full.
- Fixed-prior full: retain all angular stages but hold bone target **ratios** at the original population prior. Per-frame scale still changes. This is a diagnostic, not a proposed correct profile.
- Target-step isolation: same **current** raw input through the bone stage using current targets versus the previous frame's targets, with scale recomputed by the unchanged algorithm in each. This isolates the effect of changing the target shape, including its resulting scale change; it is not a temporal wrist displacement or an additive scalar error share.

Speed norms and nonlinear stage interactions are not additive. No ablation is adopted as an accuracy fix.

## Assessment-ranked worst intervals

Speed units are pelvis-relative model units/s; same interval for all columns. All these endpoints remain native state ok, masks empty. The aggregate retains top3 per side, raw2D/input2D changes, scores, adjacent-joint observations, bone/angle reports and normalized target ratios.

| Capture/side | Highest assessment interval(s) | Raw speed | Full / bone-only | Angle-only | Fixed-prior full | Target-step same-current-input displacement |
|---|---|---:|---:|---:|---:|---:|
| squat/left | 36.633333–36.666667 | 0.934848 | 1.067418 / 1.067418 | 0.934848 | 0.892810 | 0.00025070 |
| squat/right | 38.233333–38.266667 | 0.866300 | 9.728887 / 9.728887 | 0.866300 | 7.956561 | 0.00011256 |
| pushUp/left | 1.700000–1.733333 | 0.239853 | 1.930285 / 1.930285 | 0.239853 | 0.205893 | 0.06220123 |
| pushUp/right | 1.700000–1.733333 | 0.042328 | 2.060051 / 2.060051 | 0.042328 | 0.041874 | 0.06992560 |
| barbellRow/left | 0.900000–0.933333 | 2.309571 | 1.981456 / 1.981456 | 2.309571 | 1.981456 | 0.00000000 |
| barbellRow/right | 1.700000–1.733333 | 0.299166 | 1.855524 / 1.855524 | 0.299166 | 0.278176 | 0.05632587 |

## Prior-to-session transition

All three first use the running-median target on pipelineframe51/sourcePTS1.733333s, following30 previously applied raw frames. `sessionTargets()` is read **before** recording the current raw array. Thus the first30 usable rows use prior and later1,207/492/531 genuine rows use session; history is capped at300 raw observations. Session target values are per-segment medians averaged across sides; targets can update each frame after entry. Comparing raw dictionary target values or prior-scale versus session-scale directly would be misleading because their arbitrary target units differ: only proportions with recomputed scale determine output.

Both pushup maxima (left1.930285/right2.060051) occur exactly across1.700000→1.733333. The same-interval raw speeds are0.239853/0.042328, and fixed-prior full yields0.205893/0.041874. Replacing current session targets with previous prior targets on the **same current raw input** changes bone-only wrist position by0.062201/0.069926 model units. Corresponding bone-only temporal speed with previous targets held at the current frame is0.205893/0.041874. No angular limits, knee reflections or clamps fire. This establishes a numerical contribution of the discrete target-shape transition to those amplified changes in these arrays, without claiming an actual motion error.

At that transition pushup upper-arm output length changes0.198165→0.250850 and forearm0.178673→0.227632 on both sides, while raw right upper arm0.266772→0.265852 and forearm0.249940→0.249590 change much less. The maximum raw2D changes over the same interval are3.757px(left)/2.656px(right); input2D changes3.757/0.476px. The score pairs are0.269→0.268 and0.820→0.817, respectively: retained scores do not diagnose the target-step effect.

Row-right's assessment maximum1.855524 also occurs at this transition (raw0.299166, fixed-prior0.278176, target-step displacement0.056326). Row-left's second-ranked interval is the transition: full1.766633 versus raw0.474112/fixed-prior0.368043. Row-left's actual maximum is earlier0.900000→0.933333, where full1.981456 is smaller than raw2.309571 and no target update occurs. The transition is therefore one concrete contributor, not an explanation of every worst event.

## Squat-right maximum is a different mechanism

Assessment maximum9.728887 occurs at38.233333→38.266667, well after transition. Its same-interval raw wrist speed is0.866300 (the raw maximum7.171714 occurred much earlier). Full and bone-only coincide; angle-only equals raw; both endpoint angular reports are empty. The raw upper arm is short,0.016650→0.015025 model units, and its direction changes150.978°. The bone stage preserves that per-frame direction while imposing lengths0.175031→0.174362: output/raw length multipliers10.512→11.605. Raw forearm0.049954→0.047797 is similarly lengthened to0.124218→0.123823 (direction change11.546°). The subtree walk carries the resulting elbow relocation into the wrist. This is direct numerical amplification of an unstable raw limb direction by length enforcement, not evidence about true limb location or why the raw direction changed.

The same-current-raw target update effect is only0.00011256 model units at this event; prior/session source stays session. Fixed-prior full still yields7.956561, so holding the original prior would not remove this mechanism. Both frames have raw wrist score0.463→0.401, raw2D displacement1.560px and hybrid input2D displacement3.063px. No original invalid mask is set because default bone-only correction does not trigger the bad-angle gate. `boneMaxCorrection`9.512→10.605 is a relative length correction, not a probability or error distance.

Squat-left's maximum is also shared raw/assessment interval36.633333→36.666667 (raw0.934848, full1.067418). Its same-current target update displacement is0.00025070. These remain distinct from the pushup/row transition.

## Whole-set tradeoffs and angular participation

Full vs bone-only wrist coordinates differ only where squat right elbow angular clamp fires (16frames). No knee reflection/clamp fired in any of the three captures; no other interior limit fired. Thus the worst assessment-ranked top3 per side all have empty angular reports. This confirms the earlier raw-to-constrained angle observation with the actual per-stage report. It does not imply angular constraints are universally harmless or that turning off bone constraints improves accuracy.

| Capture/side | Full speed median / p95 / max | Bone-only max | Angle-only max | Fixed-prior full median / p95 / max |
|---|---:|---:|---:|---:|
| squat/left | 0.143 / 0.380 / 1.067 | 1.067 | 0.935 | 0.139 / 0.347 / 0.893 |
| squat/right | 0.214 / 1.454 / 9.729 | 9.729 | 7.172 | 0.209 / 1.477 / 7.957 |
| pushUp/left | 0.185 / 0.442 / 1.930 | 1.930 | 0.830 | 0.148 / 0.320 / 0.747 |
| pushUp/right | 0.130 / 0.254 / 2.060 | 2.060 | 0.459 | 0.118 / 0.282 / 0.484 |
| barbellRow/left | 0.365 / 0.588 / 1.981 | 1.981 | 2.310 | 0.317 / 0.529 / 1.981 |
| barbellRow/right | 0.309 / 0.565 / 1.856 | 1.856 | 1.036 | 0.273 / 0.510 / 1.100 |

## Reproduce and stop point

`python scripts/wrist_observation/run_constraints.py <three private originals> --scratch <outside-repo-dir>` compiles the unchanged Swift sources under `/tmp/bpt-heavy.lock` (flock, nonblocking) and writes private arrays there. Then run `python scripts/wrist_observation/constraint_attribution.py <same originals> --replay <scratch/output.json> --receipt <scratch/receipt.json>` for the public derived aggregate. It rejects incomplete/capped sources and aborts before ablation output on missing/wrong-shape coordinates, invalid-mask mismatch or max coordinate error>1e−12. That tolerance is numerical validation, not an exercise/error criterion. Production source hashes are recorded; preserve pinned1a35d3f sources for reproduction.

`python -m pytest scripts/wrist_observation -q`: **15passed** (the prior8 plus7 parity/shape/mask/missing-frame/nonfinite/source-dt checks). Native postprocessing compilation and actual full-array parity also passed. Original individual input SHA256 values remain unchanged from capture receipts. No original aggregate/report was overwritten. No video/raw arrays/individual capture hashes committed; no additional native/package/inference run is necessary to establish these bounded contributions.

The findings identify the target-switch and direction-preserving length-enforcement contributions in fixed observed arrays. They do not decide whether raw, constrained or any ablation is closer to true movement, nor justify profile tuning, a new validity threshold, automatic adoption or changes to coaching. Causal perception/occlusion/error labels still require matched independent evidence. This analysis stops here.
