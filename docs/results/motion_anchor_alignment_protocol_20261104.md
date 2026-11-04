# Paired-anchor motion agreement: predeclared comparison

Declared before replay outcomes, 2026-11-04. Base `da497eb`; the signed phone artifact at `6c932d2` stays frozen. One optional initializer policy only; the default and all current call sites remain historical v4. No adoption, model, feedback, threshold, profile, or contact-rule change.

## Candidate

For G/H innovation agreement only, replace adjacent absolute 2D versus last-accepted root-relative 3D displacements with a paired last-accepted 2D/3D anchor and its single timestamp. Both positions use root-relative image-height units. The 2D root is the midpoint of H36M hips 1 and 4; both constituent hips and the joint must be finite with the existing 0.45 support threshold. If a 3D observation is accepted without those prerequisites, invalidate its paired anchor. Do not update it from rejected/low-support observations. Clear it on all existing estimator resets. Missing root/anchor disables agreement only; the original persistent-candidate path and observation retention still apply.

Keep innovation 0.25 × trusted body scale, 2D motion 0.01 × scale, persistence 0.12 × scale, and relocation count 3 exactly unchanged. No tuning after results. Existing parent plausibility, contact/grip behavior, confidence gates, expiry, and causal online profile remain unchanged. Parent and child historical anchors may have different timestamps; fixing that separate plausibility rule is out of scope.

## Before data scoring

Preserve all 720 historical numerical/state parity checks and add regressions for translation invariance, return motion after low-support observations, normal reliable acceptance, confident outlier rejection, missing/one-sided hip support, anchor invalidation, resets, and scale equivalence. Use a SHA-pinned v4 Python source with an explicit candidate patch and compare synthetic candidate outputs against Swift before full replay. Keep Python legacy source bytes unchanged. Record the patch, generated Python source hash, Swift source hash, and fixture hash.

## Saved-output evaluation

Home only; CPU and BLAS single-threaded. Read saved XS/2D arrays; no model inference, training, GPU, video decoding, or fresh labels. Freeze inputs by SHA256 and recheck them after the run. Predictions and per-sequence data stay on Home; export only aggregate results/receipts. Save every policy's prediction arrays before loading that sequence's score reference.

- Frozen v4 root: `/home/junjeon/bpt-runs/motion-contact/_code/0388fa8`. Historical estimator SHA256 `c58740a36791962c9196f2c0443c9d5ae9ad71b343d6688f55614abaea57c40d`; historical protocol SHA256 `e99f79b7019d7f298c6a06e242eff458a9bc18db82fc43ce3c2a9944fff16d71`.
- Clean 60: all cached streams for s07/s08/s09/s10/s11 × four cameras × squat/pushup/barbell_row, matched to existing v4 manifest and v3 raw-A records. Full saved length, no selection by result.
- Stress 12: all six saved `20261020-keypoint6-xs` and all six `20261020-rgb6-xs` streams (s07 × cameras 50591643/65906101 × three exercises), first 270 frames.
- Raw input cache: `~/bpt-runs/rules-calib/_cache/orig_halpeA`; 2D: `~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d`. Scenario arrays are read, never recomputed.
- Compare raw/A, unchanged G-online/H-online, and paired-anchor G-online/H-online. Online proportions use original rows 21–80, activate at 81 with confidence 0.4. No SMPL/profile photos. First usable 21; primary score rows 90:end; also report whole saved-sequence denominator explicitly.
- Require exact legacy G/H array equality with the existing v4 online outputs before scoring candidates. Runtime timing is excluded from byte/value parity.

## Metrics and interpretation

Report full and target-joint MPJPE, coverage, wrist/ankle errors, original recovery-to-clean-quality definition, and five-frame root-relative GT-motion displacement gain/suppression (GT displacement >20 mm, suppression gain <0.5) for every policy. Invalid predictions remain in all-frame error denominators. Target joints use the historical lower-confidence-side choice from the observed calibration prefix, without GT.

For mechanism counts report evaluated innovation gates, agreement availability/positive agreement, missing-root/anchor exclusions, rejected-joint frames, and changed rejection/pass-through/prediction decisions. From saved damage transitions define onset as first 3 damaged frames, ongoing damage as the remainder, recovery as first 6 undamaged frames after each damage end (cut off by next damage), and remaining frames separately. These partitions use actual saved damage masks, not only nominal block times. Report partition errors/coverage and recovery censoring; keep clean and both stress scenarios separate. Summaries include micro joint-frame weighted means and sequence counts, with per-exercise aggregates so effects cannot disappear in one average.

These streams are reused development evidence, including streams historically named heldout; this is not a fresh holdout or a proof of form/contact accuracy. A candidate may trade recovery/coverage against outlier acceptance and true-motion suppression. Results do not authorize adoption.
