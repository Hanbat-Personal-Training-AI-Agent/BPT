# Correction praise: finite 3D also needs observed joint support

A follow-up audit of `03aa9d0` found that finite 3D coordinates and state `.ok` did not prove the corresponding joint was observed in the current 2D input. The existing pipeline can retain finite model output when a 2D elbow or wrist is occluded. This document and change are separate from the frozen `03aa9d0` intermediate replay.

Two actual-tracker regressions reproduced the error with finite `.ok` 3D throughout: `row_short_pull` with a missing 2D elbow, and `pushup_shallow` with a missing 2D wrist. Both missing-current and missing-baseline cases emitted `praise_fixed`; the before-run had **four failing assertions across two tests**. Fully supported corrections and unrelated-missing-joint controls passed before the fix.

The correction-only support check now maps each relevant H36M joint to its actual COCO input constituents. Every constituent must have finite coordinates, finite confidence and confidence at least the existing `FormCommonConfig.minJointConfidence` (default **0.30**). Averaged root/thorax confidence cannot hide an unsupported constituent. The existing finite 3D and exact source-frame coverage requirements still apply.

The mapping is checked against `PoseCoordinateTransforms.coco17ToH36M17`: perturbing each of the 17 COCO inputs identifies the converter's dependent H36M coordinates, and tests require the same support dependency under confidence 0.29, NaN confidence and the inclusive 0.30 boundary. Additional checks cover nonfinite coordinates and confidence. No new threshold was introduced.

Only the joint dependencies actually consumed by the 3D quantity are required. Missing an unrelated wrist still permits a supported row short-pull correction; missing 2D face/facing evidence still permits a supported 3D elbow-angle correction. The fix does not require 2D-derived facing for 3D geometry. Warning calculations, 3D state, models, generic encouragement and default flags remain unchanged.

Final validation: **364 Swift tests, four skipped, zero failures**; all **67 Runner Swift sources** passed cached iOS typecheck in 7.50 seconds. Scoped source review approved helper SHA-256 `0471170329c4928fe0a353399b20008cee9acd1ba9e82ac3864a11eec73c7588` and FormWarnings SHA-256 `fdafe9ac6fb290b58918f238d94c3d2a84a8e7e30a81b0ac9cd772f07e9875bb`.

Before/after logs, source/test hashes, exact commands and typecheck receipt are preserved under `~/bpt-data/completion-20261104-private/native-praise-evidence/3d-support/`. Typecheck ran on the working source before commit, so its recorded Git ID is the preceding `03aa9d0`; the accompanying source hashes bind the checked bytes. No phone, window interaction, UI, model inference, training or deployment was performed by this task. A separate final replay must not be conflated with the prior intermediate replay.
