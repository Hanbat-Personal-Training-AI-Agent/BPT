# Native SMPL-X joint-center ablation — 2026-10-30

**The fixed native-joint alternative does not support replacing the surface-regressed joints.** It improves selected-side pushup elbow MAE and peak extension, but increases row torso-range compression, worsens the opposite pushup elbow, and worsens relative-lockout decisions. The result is a completed training-free numerical experiment, with no model inference, training, image inspection or product change. It is an alternative anatomical definition with uncertain compatibility to the Fit3D target, not a correction to a proven implementation bug.

The [protocol](joint_definition_protocol_20261030.md) was written and copied to Home before computation. The [runnable helper](../../scripts/deep_analysis/ablate_smplx_joint_centers.py), [tests](../../scripts/deep_analysis/tests/test_joint_center_ablation.py), and [aggregate JSON](joint_definition_20261030.json) accompany this report. This is the same already examined 20-video diagnostic set, **not independent new validation**.

## Definition and reconstruction

Original B/C joints are SMPL-X posed mesh→fixed SMPL vertex map→H36M surface regressor, unchanged. The sole alternative uses the installed SMPL-X kinematic centers: pelvis 0; left/right hip 1/2, knee 4/5, ankle 7/8, shoulder 16/17, elbow 18/19 and wrist 20/21. Names were checked against installed `smplx.joint_names.JOINT_NAMES`. The left/right mapping is fixed globally; no case, side, GT-selected mapping or best result selection is used.

Knee is hip–knee–ankle; elbow is shoulder–elbow–wrist; hip is shoulder–hip–knee. Torso is midpoint(hips)→midpoint(shoulders) versus the original up axis. No head/spine surrogate is inserted: unneeded H36M slots are NaN and never evaluated.

Reconstruction uses stored **predicted** per-frame global orientation, body pose, betas and translation, with GVHMR's existing `BodyModelSMPLX.get_skeleton` and the installed `smplx.lbs.batch_rodrigues`/`batch_rigid_transform`. The first 22 joints form a closed parent tree; descendant hand/face rotations cannot affect them. Expression defaults to zero as in the original prediction reconstruction; the first 66 pose-mean components are asserted zero. No GT parameters, body-shape optimization or handwritten FK are used.

Before alternative scoring, first/middle/last frames of all 40 B/C result were checked in **both camera and world coordinates**: 80 coordinate checks/240 frame samples. Native FK versus full standard body-model joints differed by at most **4.77e-7m**; regenerated surface joints versus cached H36M differed by **9.54e-7m**, both within the predeclared 1e-4m reconstruction tolerance. This tests computational equivalence to that body model, not anatomical accuracy against humans.

Primary installed sources are GVHMR `ee960bb6e2ea2d381aa97f08e9b71ef320b624b1`'s `hmr4d/utils/body_model/body_model_smplx.py` and the installed SMPL-X `joint_names.py`/`lbs.py`. Their source hashes and the local licensed model hash are in the JSON; model files remain Home. Native joints are the transformed shape-dependent rest skeleton; the H36M regressor acts on a posed surface including pose blend shapes and skinning. Their difference is expected to change both geometry and target definition.

## Fixed data and denominators

All 20 original jobs were used: five each squat, row, pushup and deadlift. There are **103 inclusive rep intervals**:25/27/25/26, and 7,241 unique inside-rep frames: 1,927/1,624/1,231/2,459. Both B/default focal and C/oracle focal were evaluated on the same frames. Original GT, camera transforms, 50→30fps picks, inclusive endpoints, truncation, image-up and selected-side rules remain frozen. Selected-side means use the original replay-confidence side (or the frozen job side where replay is unavailable). L/R diagnostics never alter that selection.

All **4,632** saved original GT/A/A2D/B/C/world/floor rep values reproduced, maximum numerical difference **2.84e-14°**. All 125 hashed input files were unchanged before/after, including jobs, original score, all 40 result arrays, numeric GT, cameras, annotations, available A/floor arrays and frozen scorer sources. The original score hash is `fd84c4971a601fa2fe5b23260f55bb73bed172a8cce0642017775fc619061f5f`; the full input-cohort hash is in the aggregate. Original arrays and scores were never overwritten. A full per-source hash manifest remains Home as `input_hashes_private.json`; only the pooled hash is exported.

Every scored limb coordinate and angle was finite; the aggregate pooling asserts finite values. Angle masks are the same union of inclusive rep intervals for both definitions. Frame distributions weight frames; **tables below use per-video MAE macro means**, five videos per exercise. Each L/R bilateral entry averages the two side macro means equally; torso is identical on both sides. Rep-error tables weight intervals, so shared endpoints remain in both adjacent intervals as in the frozen evaluator. The JSON includes frame-weighted values, signed biases, paired absolute-error changes, extrema, phase timing, and improvement/worsening fractions for every bilateral angle, exercise and variant. None of these denominators imply independent observations or confidence intervals.

## All exercises and both sides

Selected-side angle MAE in degrees, **original→native**:

| Exercise | Variant | Knee | Hip | Elbow | Torso |
|---|---|---:|---:|---:|---:|
| Squat | B | 7.76→11.40 | 4.79→11.27 | 3.25→4.20 | 11.55→14.17 |
| Squat | C | 7.64→11.19 | 4.89→11.06 | 3.18→4.22 | 11.74→14.32 |
| Row | B | 5.56→6.25 | 3.09→5.22 | 6.43→14.29 | 14.76→18.52 |
| Row | C | 5.48→6.08 | 3.21→5.07 | 6.52→14.36 | 15.13→18.86 |
| Pushup | B | 7.55→3.89 | 5.69→12.75 | 11.64→9.74 | 12.44→12.77 |
| Pushup | C | 7.82→4.06 | 5.60→13.00 | 12.33→10.40 | 11.71→12.07 |
| Deadlift | B | 7.11→10.25 | 4.64→7.22 | 9.08→12.34 | 13.61→17.19 |
| Deadlift | C | 7.31→10.43 | 4.67→7.22 | 9.01→12.22 | 13.85→17.43 |

Bilateral angle MAE in degrees, **original→native**, same five videos per exercise:

| Exercise | Variant | Knee | Hip | Elbow | Torso |
|---|---|---:|---:|---:|---:|
| Squat | B | 7.25→12.06 | 4.46→11.05 | 7.59→7.18 | 11.55→14.17 |
| Squat | C | 7.11→11.86 | 4.61→10.76 | 7.59→7.12 | 11.74→14.32 |
| Row | B | 4.48→6.30 | 4.69→5.59 | 10.13→15.17 | 14.76→18.52 |
| Row | C | 4.45→6.12 | 4.83→5.50 | 10.12→15.14 | 15.13→18.86 |
| Pushup | B | 7.82→6.25 | 5.54→12.73 | 13.61→15.52 | 12.44→12.77 |
| Pushup | C | 8.06→6.44 | 5.45→12.69 | 14.55→16.50 | 11.71→12.07 |
| Deadlift | B | 6.56→10.35 | 5.06→7.19 | 15.89→16.67 | 13.61→17.19 |
| Deadlift | C | 6.73→10.54 | 5.11→7.16 | 15.77→16.51 | 13.85→17.43 |

Pushup selected side is right in these fixed jobs. Right elbow improves B 11.64→9.74°/C12.33→10.40°, while **left elbow worsens B 15.58→21.30°/C16.78→22.60°**. The bilateral elbow result therefore regresses, despite the selected-side improvement. No side is replaced to obtain a better result.

Root-relative camera-coordinate MPJPE across all 12 anatomically mapped limb joints, frame/joint weighted, millimeters:

| Exercise | B original→native | Paired Δ | C original→native | Paired Δ |
|---|---:|---:|---:|---:|
| Squat | 73.11→90.31 | +17.20 | 72.97→90.64 | +17.67 |
| Row | 59.77→90.00 | +30.23 | 60.02→90.38 | +30.36 |
| Pushup | 74.15→93.15 | +19.00 | 72.86→91.79 | +18.93 |
| Deadlift | 62.91→90.42 | +27.50 | 63.53→90.83 | +27.31 |

Each representation subtracts its own pelvis. GT root-relative world joints use the existing camera rotation `R.T`; no scale, yaw, Procrustes or GT fitting is applied. Per-joint values and native-minus-surface displacements are retained in the JSON. This comparison includes joint-definition and skeleton-root differences; it is not a clean decomposition of prediction error or proof that one joint center is more anatomically correct.

## Same failed cohort and all other reps

The cohort remains the original B/C failure union near the original thresholds: two row reps and one pushup rep. It was not recomputed using native outputs. The complements are 25 row reps and 24 pushup reps; squat and deadlift have no members in this specific failure union, but all their reps were evaluated above and in the JSON.

Mean absolute **row torso** errors in degrees, original→native, with mean paired Δ:

| Cohort | Variant | Raw range error | Δ | P95−P05 range error | Δ |
|---|---|---:|---:|---:|---:|
| Same failed 2 | B | 10.712→14.594 | +3.882 | 9.063→12.501 | +3.439 |
| Same failed 2 | C | 10.510→14.449 | +3.939 | 8.903→12.394 | +3.491 |
| Other 25 | B | 5.128→7.175 | +2.048 | 4.630→6.529 | +1.899 |
| Other 25 | C | 5.041→7.122 | +2.081 | 4.548→6.480 | +1.932 |

**All 27 row range errors worsen** for each B/C. Signed errors are negative throughout, so this is greater compression, not harmless sign crossing. At the two failed reps' exact GT extreme frames, signed-range error changes B−10.959→−14.900° and C−10.753→−14.750°. Mean worst frame error worsens B19.859→27.650°/C20.089→27.883°. Peak times stay exactly at the GT peaks; mean minimum timing error stays83ms for both representations. The stronger range compression is therefore not explained by shifting the maximum to a different phase.

For the **selected pushup elbow**, the same failed rep's range error improves B18.820→9.754°/C18.629→9.463°, sustained-range error18.092→8.890°/17.688→8.480°, and worst frame error23.588→20.595°/22.411→20.117°. Peak timing error remains33ms; minimum timing error improves67→0ms. These numerical phases are GT extrema, not independently labeled extension/flexion phases.

The other 24 selected-side pushup reps also improve mean range error B10.370→7.724°/C10.001→7.976°, but **8/24 worsen** for each variant. Sustained-range error improves10.413→8.083°/10.070→7.991°. Mean peak timing changes599→557ms for B but421→547ms for C. Absolute peak/range improvements do not establish relative-decision improvement.

For the same failed pushup rep, the frozen running-reference calculation gives:

| Quantity, degrees | B original→native | C original→native |
|---|---:|---:|
| Current elbow maximum signed error | −14.261→−7.956 | −13.830→−7.368 |
| Own running maximum minus GT running maximum | −10.277→+0.248 | −10.487→−0.034 |
| Running deficit signed error | +3.984→+8.205 | +3.343→+7.334 |

The identity remains reference-peak error minus current-peak error. The reference peak improves **more** than the current peak, increasing the deficit error by B4.221°/C3.991°. Both original and native running-reference reps still differ from the GT reference. No GT reference was substituted into estimation. The effect is a direct counterexample to choosing this alternative from current-extension MAE alone.

## Original thresholds, diagnostics only

Same original eligible reps, selected side and strict `>` thresholds; original→native agreement counts:

| Rule | B all eligible | C all eligible | B/C original boundary cohort |
|---|---:|---:|---|
| Squat shallow | 10/10→10/10 | 10/10→10/10 | No boundary reps |
| Squat lockout | 25/25→25/25 | 25/25→25/25 | No boundary reps |
| Row torso swing | 25/27→25/27 | 25/27→25/27 | 1/3→1/3, two FN each |
| Pushup shallow | 10/10→10/10 | 10/10→10/10 | No boundary reps |
| Pushup lockout | 19/25→15/25 | 17/25→15/25 | 0/1→0/1, one FP each |

Pushup all-rep FP counts increase B6→10 and C8→10; no FN occurs for that rule. These are disagreements against GT-angle-derived thresholds, **not expert bad-form false alarms or clinical accuracy**. First-three shallow exclusions and own running maxima are unchanged. No original criterion was rescored into PASS, no new acceptance threshold was introduced, and no alternative was adopted.

## Reproduction and limits

Home was idle before execution (no GPU job, load 0, about 30 GiB available RAM). Only CPU was exposed; native thread counts were 2, batch 32, validation batch 3, process niceness 10 and a dedicated advisory CPU lock. The successful helper took 5.70s on that existing cache, a descriptive local measurement with no service-speed claim or adoption gate. An initial owned run was stopped after discovering GVHMR's import changes cwd; path arguments were resolved before that import and the same protocol was rerun. Its validation also passed; no original inputs were changed.

Example, on Home after copying only helper, tests and protocol into an isolated run folder:

```sh
export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2 CUDA_VISIBLE_DEVICES=""
flock -n ~/.bpt-joint-definition-cpu.lock nice -n 10 \
  ~/miniconda3/envs/bpt-gvhmr/bin/python code/ablate_smplx_joint_centers.py \
  --run ~/bpt-runs/gvhmr-eval-20261026 --root ~/datasets/fit3d \
  --protocol joint_definition_protocol_20261030.md \
  --output aggregate.json --validation validation.json
```

Five new tests passed on Home, including actual licensed-model full-LBS parity, batch invariance, shape dependence and rigid translation/global-rotation equivariance. Locally the entire deep-analysis test discovery ran 13 tests: 11 passed and the two licensed-Home-only tests skipped; Python compile and `git diff --check` passed. The all 80-coordinate and 4,632-score checks are additional actual-data checks, not substitutes for independent accuracy validation.

Raw arrays, predicted parameters, models, profiles, identifiers and media remain Home. Exports contain only code, protocol, aggregate statistics and hashes. No GPU inference, training, video decoding, image viewing, Modal/data upload, backend integration, default/threshold change or phone job occurred.

The evidence rejects the specific hypothesis that switching wholesale to these native kinematic centers resolves the observed failures. It does not show that the surface regressor is anatomically correct, that joint definition explains no error, or that another fitted skeleton would improve general accuracy. Fit3D's target definition differs from both representations; the camera-up versus GT-up contract also remains unchanged. Further accuracy work needs an independently specified anatomical target and new held-out/expert-labeled evidence, rather than side selection or threshold tuning on these 20 cases. No medical, injury-risk or normal-form accuracy is claimed.
