# Fixed diagnostic protocol: native SMPL-X joint centers, 2026-10-30

Before computing alternative outputs, fix **one** training-free alternative to the posed-mesh SMPL-X→SMPL→H36M surface regressor. Use the installed GVHMR `BodyModelSMPLX.get_skeleton` with **stored predicted** per-frame betas, then installed `smplx.lbs.batch_rodrigues` and `batch_rigid_transform` with the first22 SMPL-X parent tree, global orientation, body pose and translation. No fit, smoothing, optimization, new inference, training, calibration beta, GT pose input, or hand-written FK. Body rotations have zero pose mean; assert this. Descendant hand/face rotations cannot affect ancestors. Validate against the full standard model before evaluating.

Fixed anatomical names from installed `smplx.joint_names.JOINT_NAMES`:

| Joint | Left index | Right index |
|---|---:|---:|
| hip | 1 | 2 |
| knee | 4 | 5 |
| ankle | 7 | 8 |
| shoulder | 16 | 17 |
| elbow | 18 | 19 |
| wrist | 20 | 21 |

Pelvis is index0. Knee=hip–knee–ankle, elbow=shoulder–elbow–wrist, hip=shoulder–hip–knee, torso=midpoint(shoulders)−midpoint(hips) versus the frozen up vector. No head/spine surrogate or side substitution. Undefined H36M slots are NaN and never scored. No subject, camera, side, frame, GT-selected mapping or best result selection.

Use all20 already examined frozen Fit3D diagnostic videos, five per exercise, and both B/default-focal and C/oracle-focal stored predictions. Primary angles use camera coordinates and the unchanged image-up, same 50→30fps pick, inclusive rep intervals, truncation and near-side selection as frozen code54cd739. Score both L/R knee, hip and elbow and torso; report frozen selected side separately. All original frozen rep metrics must reproduce at1e-8 absolute tolerance (NaNs equal). Validate FK against standard joints and surface reconstructions against cached H36M for first/middle/last frames of **all40 files in both camera/world** coordinates at1e-4m absolute tolerance; reject mismatch. CPU threads2, batches32, validation batches3, no GPU use. Synthetic tests also check rigid-motion equivariance, shape dependence, bilateral mapping and angle geometry.

Coordinate diagnostic: compare all12 anatomically mapped limb joints, root relative to each representation's own pelvis, in camera coordinates. GT root-relative world coordinates are multiplied by camera `R.T`, consistent with existing Fit3D helpers. Units are meters. Report per-joint and pooled MPJPE millimeters; no scale/rotation/Procrustes fitting. This is **target compatibility** of different joint definitions, not isolated pose accuracy. Also report native-minus-surface displacement under the same predicted parameters.

For each bilateral angle and torso: framewise MAE inside union of rep windows, per-video macro MAE, signed bias; per-rep raw min/max/range errors, P95−P05 range error, maximum absolute frame error, errors at exact GT min/max frames, own peak timing errors. Matched-phase range uses alternative values at GT max/min. Phase extrema are numerical GT extrema, not independently labeled exercise phases. Compare paired alternative−original absolute error deltas, with counts improved/worsened/tied. Summaries are descriptive; no significance/acceptance claims or resampling tuned after inspection.

Freeze the previous failure cohort as the union of original B/C disagreements with GT within±5° of the original row torso-range39.9° and pushup running elbow-extension deficit10° thresholds. Report that same cohort and all other reps, never redefine it after reconstruction. Include selected-side row range/sustained range and pushup current/reference maxima and running deficit; original running-reference algorithm remains unchanged. Compute original fixed-threshold agreements/FP/FN on all eligible and boundary reps as diagnostics only. No score/GT/output overwrite or adoption verdict. Reused20 is not independent new validation, no medical/normal-form correctness claim.

All raw arrays, SMPL-X parameters, licensed models, paths/identifiers and private per-case records remain Home. Export code, this protocol, pooled aggregate and SHA-256 hashes only. Hash jobs, scores, raw result files and numeric GT/rep/camera sources before and after; preserve them. Inspect resources before execution, take a dedicated CPU diagnostic lock, cap native threads, and do not interfere with unrelated jobs. No images/video viewing, cloud/Modal uploads, product/default/backend/threshold changes.
