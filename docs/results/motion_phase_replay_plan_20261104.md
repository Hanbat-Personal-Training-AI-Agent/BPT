# Accepted-phase H saved-array replay: preparation

Status: inventory preparation only. The native accepted-phase policy and its Python/Swift parity must be frozen before outcome computation. This file is not authorization to tune the policy or execute an unfinished candidate.

The separate worktree starts at `9cfe92b`. Native source, the Python policy transform, synthetic witnesses and parity receipt belong to the separate `experiment/motion-phase-acceptance-20261104` branch. This worktree owns only the independent replay and reporting. No production integration, default activation, model change, training, new inference, phone or UI work is included.

## Fixed input and comparison scope

Reuse the exact existing 72 saved streams: 60 clean, six keypoint stress and six RGB stress, totaling 42,052 frames. Reuse the original units, corruption records and online observation-only profile schedule: rows 21–80 build the profile, row 81 activates it, and 90:end is the primary window. Also report the whole sequence. Freeze each source file by its historical manifest SHA before reading it. The frozen v4 estimator SHA is `c58740a36791962c9196f2c0443c9d5ae9ad71b343d6688f55614abaea57c40d`.

Compare A/raw, legacy G, legacy H, and accepted-phase H with legacy agreement and legacy edge policy. A/raw provides the unchanged observation reference; G/H reproduce every saved historical non-timing array, dtype and shape, not only aggregate scores. A's known schema extension is permitted only if `expired_prediction_fallback` is entirely false. The candidate changes only phase-input provenance/order, as defined by the native policy freeze; it does not include paired-agreement or coherent-edge candidates. Never feed GT, GT phase/side, score references or future samples into any estimator. Save all four predictions before parsing that stream's GT for scoring.

## Fixed measurements, before outcomes

Reuse the edge replay's exact scoring arithmetic and partitions. Report all-joint, declared target-joint, wrist and ankle MPJPE and coverage with explicit joint-frame sums/counts. The stress partitions are actual damage onset (first three damaged observations), ongoing damage, recovery (first six post-damage observations, clipped at next event), and remaining. Report by scenario and exercise; the same whole/primary masks apply to each denominator.

Preserve its true-reference-motion proxy: five-frame displacement, reference displacement greater than 20 mm, projected displacement gain, and suppression below 0.5. This uses GT only after saving predictions. Reuse recovery scoring, including eligible/recovered/full-one-second-unrecovered/limited-followup/clip-end-censored/next-damage-censored counts. Summaries must keep the complete denominator, including invalid joints, and must not convert missing data to successful recovery.

Additionally report phase states, phase-state changes against legacy H, turning flags, turning-flag changes, accepted/rejected phase inputs and turning causes that the frozen policy actually exposes. Distinguish derived phase from the explicit external trusted-phase override. Report changed rejection, invalidity, prediction-use, observation-passthrough, expired-fallback and corrected-position joint-frames. If a requested cause is not present in recorded diagnostics, say unavailable; do not reverse-engineer a causal label from a phase value. Exact cause fields and semantics are bound to the native freeze before execution.

Angle and jitter diagnostics may reuse the already frozen edge supplement arithmetic after all outputs exist. Such diagnostics remain estimated geometry/stability summaries and must carry unavailable/degenerate counts; do not interpret lower jitter as preserved motion, or a joint-angle estimate as validated form/contact. Any addition beyond the frozen supplement requires a separate pre-outcome specification.

## Execution gate and artifacts

Before outcomes: (1) pass the read-only inventory; (2) obtain native policy/protocol source hashes and a zero-failure cross-language parity receipt; (3) bind the candidate Python transform and generated source SHA to that receipt; (4) freeze the final replay protocol and runner SHA; (5) ensure a new, exclusively owned Home output directory and single-thread CPU/BLAS environment. Refuse execution on hash/schema/parity mismatch. Candidate or diagnostic changes after outcomes require a separately labeled experiment, never overwrite this one.

`scripts/motion_phase_replay/inventory.py` reads only frozen manifests/results metadata and byte-hashes existing inputs/predictions. It never calls an estimator or parses GT. Home raw arrays, per-stream records and manifests remain on Home. Only aggregate receipts/results cross back to the Mac. Existing edge artifacts are read-only. No decision to adopt H follows from this reused development sample.
