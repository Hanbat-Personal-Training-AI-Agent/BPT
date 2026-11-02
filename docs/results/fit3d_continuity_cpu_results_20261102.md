# Fixed target continuity: cached Fit3D accuracy result — 2026-11-02

**Do not adopt this candidate.** On all60 reused Fit3D validation streams, the fixed0.2s target-shape filter is slightly better than the native-equivalent full constraint baseline in mean position error, but remains worse than raw XS. It worsens early transition-region accuracy relative to full constraints and preserves more GT-motion suppression than raw. The earlier phone numerical jump reduction does not establish accuracy. No further candidate or parameter setting was tried.

Primary all17joint MPJPE: **raw146.838965mm → full146.893640mm → candidate146.858303mm**. Candidate−full is−0.035337mm but candidate−raw is+0.019338mm. Early region full134.861047→candidate135.086621mm (+0.225574mm). Motion suppression proxy raw25.0574%→candidate25.8115%, an increase. These small dataset means are descriptive, without uncertainty/significance or independent-person performance claims.

## Frozen scope, parity gate and GT boundary

Protocol5a38764 clarified existing strict `GT displacement>20mm` proxy in ea0692a before scoring; implementation/scorerb08f647 was frozen before actual outputs. Candidate e376f90 remains half-life0.2s/gap-reset>1.0s, no sweep. All60 original validation streams were processed once on existing Home CPU1/nice19, wall37.2s descriptively. No model import/inference, GPU, training, phone command, data upload, new personal profile, app/runtime/default change or automatic adoption. Only source code and synthetic parity data were sent to Home; actual raw/GT arrays remained there. Original input/source/model files were preserved.

Swift fixture uses unchanged native Pose3DConstraints/BoneLengthConstraint/KneeHingeLimit plus frozen BoneTargetContinuity and the verbatim native median shim. Python reference/filter passed **213,894coordinate comparisons on2,097synthetic pose rows,14explicit filter cases,24invalid-full rows**: maximum coordinate error4.44e−16 and Home target/shape error1.11e−16 (tolerance1e−10), exact target source/filter status/invalid masks. Cases cover history>300, prior/session switch, epoch/key resets, long gap, invalid targets/times, tracking reset, raw near-zero0.002upper-arm direction reversals, and spine rotations exceeding20° invalidation.

The initial synthetic fixture failed its **coverage assertion**, having zero invalid rows; its numeric/mask comparisons had passed but it did not exercise the invalid branch. We preserved that fixture/failure receipt and added an explicit spine>20° case before any real stream run. This was fixture coverage repair, not candidate tuning or a waived gate. Mac and Home passed the corrected fixture before real processing. [Provenance](fit3d_continuity_provenance_20261102.json) retains both results and source hashes.

`produce(raw,timestamps,exercise)` is the GT-free runtime boundary. It runs full and candidate from original raw21 onward, independently obtains original raw-only prior/session targets, filters only target shape, checks raw input bytes unchanged, then saves both arrays/masks/targets. **Only after those outputs are complete and saved does `load_score_reference` read GT joint/camera/rep files for that stream. The existing completed results JSON is read upfront to select the fixed stream list and check historical A scores; it contains prior GT-derived score summaries, but none is passed to `produce` or used to choose targets/state/parameters. Thus the strict executed boundary concerns GT joint/camera/rep arrays, not the mere presence of historical score summaries in process memory.** GT root depth/focal conversion, camera geometry, true up, angle references and motion direction enter final scoring only. No GT target/initial pose/anchor/phase/trajectory or later output seeds state.

These caches are RTMDet/RTMPose Halpe→pretrained XS L5, not phone MediaPipe-hybrid input or device queue timing. Time is stored Fit3D pick/50Hz (0.02/0.04s increments), not guessed30fps or native sensor PTS. Full baseline is new offline native-equivalent postprocessing, not historical A. Original A recomputed146.838964553mm/568,004joint-frames and matched old per-stream means within2.84e−14mm. Original60 were historically held out from tuning36 but have already been examined for A–H/v4; **they are not a fresh holdout for this follow-up**.

## Main/early/tail denominators and exercise tradeoffs

All complete numeric predictions remain in error scores even if masked: no attractive valid subset. MPJPE includes pelvis root (zero relative error for every frame); this lowers all three absolute means consistently. Primary568,004joint-frames =33,412frames×17joints. All60first session targets start at raw index51. Prior[21:51), early[51:90), late/main[90:N); early is outside the historical A main score. The last5L5 rows are edge-clamped: preserve them in primary, separate tail-excluded sensitivity. All source/array alignment follows the original frozen loader.

| Partition / exercise | Joint-frames | Raw / full / candidate MPJPE(mm) | Candidate−full(mm) |
|---|---:|---:|---:|
| primary/all | 568,004 | 146.838965 / 146.893640 / 146.858303 | -0.035337 |
| primary/barbell_row | 174,216 | 123.672675 / 123.805470 / 123.802260 | -0.003210 |
| primary/pushup | 143,480 | 233.041273 / 233.522428 / 233.366122 | -0.156306 |
| primary/squat | 250,308 | 113.550500 / 113.306339 / 113.317983 | +0.011644 |
| prior/all | 30,600 | 85.667336 / 85.616273 / 85.616273 | -0.000000 |
| early/all | 39,780 | 135.720304 / 134.861047 / 135.086621 | +0.225574 |
| early/barbell_row | 13,260 | 124.528765 / 123.699859 / 124.042308 | +0.342449 |
| early/pushup | 13,260 | 151.016056 / 150.067492 / 150.148981 | +0.081489 |
| early/squat | 13,260 | 131.616092 / 130.815792 / 131.068574 | +0.252782 |
| primary_no_tail5/all | 562,904 | 147.352224 / 147.389908 / 147.352737 | -0.037171 |
| primary_no_tail5/barbell_row | 172,516 | 124.015993 / 124.150281 / 124.146760 | -0.003521 |
| primary_no_tail5/pushup | 141,780 | 234.739899 / 235.163550 / 235.002400 | -0.161150 |
| primary_no_tail5/squat | 248,608 | 113.709093 / 113.459626 / 113.469810 | +0.010184 |

Late is exactly the primary region, not a separately pooled repeat. Early candidate error worsens relative to full in **all three exercises**. Tail-excluded candidate is147.352737mm versus raw147.352224mm; this sensitivity does not replace the original primary denominator. No favorable side, exercise, time partition or tail treatment was selected as a success result.

Paired primary **streams**:35have lower candidate error,25higher,0equal; unweighted mean stream difference−0.050103mm differs from joint-frame-weighted−0.035337mm because stream lengths vary. Paired **joint-frames**:132,498lower error,129,714higher,305,792equal within numerical1e−9mm. These are temporally/multi-camera correlated measurements, not independent people. Largest joint-frame changes are−57.030mm and+48.885mm; pooled median0 and p95signed change+0.685945mm. Masks remain566joint-frames in both full/candidate (all in pushup), mask changes0. This mask equality does not establish full native requiredOK/view/reference/phase eligibility or correct posture.

## All joints, bilateral errors retained

Each row uses33,412frames. Lower numbers are positional closeness to the dataset joint reference after the fixed scorer conversion, not clinical form correctness.

| Joint | Raw / full / candidate MPJPE(mm) | Candidate−full(mm) |
|---|---:|---:|
| pelvis | 0.000000 / 0.000000 / 0.000000 | +0.000000 |
| right_hip | 45.273019 / 45.273019 / 45.273019 | +0.000000 |
| right_knee | 137.110888 / 137.763182 / 137.674316 | -0.088867 |
| right_ankle | 250.174629 / 251.109119 / 250.865935 | -0.243185 |
| left_hip | 44.688479 / 44.688479 / 44.688479 | +0.000000 |
| left_knee | 156.779957 / 155.355753 / 155.277108 | -0.078645 |
| left_ankle | 265.963048 / 263.206994 / 263.012355 | -0.194639 |
| spine | 103.073239 / 103.073239 / 103.073239 | +0.000000 |
| thorax | 137.795222 / 138.245960 / 138.245960 | +0.000000 |
| neck | 164.075492 / 164.630819 / 164.630819 | +0.000000 |
| head | 200.761473 / 201.200677 / 201.200677 | +0.000000 |
| left_shoulder | 156.389795 / 156.627404 / 156.627404 | +0.000000 |
| left_elbow | 165.344929 / 166.321870 / 166.383221 | +0.061350 |
| left_wrist | 180.581693 / 180.860229 / 180.866894 | +0.006665 |
| right_shoulder | 148.122497 / 148.545102 / 148.545102 | +0.000000 |
| right_elbow | 160.394362 / 161.359379 / 161.357940 | -0.001439 |
| right_wrist | 179.733675 / 178.930647 / 178.868677 | -0.061970 |

Left elbow and left wrist mean errors increase relative to full; right wrist and leg-joint means decrease. Many torso/root/hip joints are unchanged. A single pooled or selected-side mean would hide these tradeoffs; no position improvement is claimed across joints.

## Worst worsening from existing saved outputs

The maximum+48.885054mm is a **single joint/frame error change**, not a velocity interval: squat, left wrist, source index112/time3.74s, main/late,61frames after the first session target, not clamped tail. Raw/full/candidate errors are312.168765/300.651823/349.536877mm. Neither full nor candidate marks that joint invalid. Full→candidate wrist position differs52.276114mm under scorer-only scale; original-vs-filtered target-shape L1lag is0.073185. This is later ongoing target tracking, so it must not be attributed solely to the initial discrete switch. No subject/camera/stream identity or raw coordinate is exported. The [derived worst-case record](fit3d_continuity_worst_20261102.json) was read from immutable saved outputs with the combined output hash gate; no postprocessor/model was rerun. It does not supply a GT posture/occlusion cause label.

## GT angle accuracy, distinct from phone model-angle invariance

The frozen accuracy scorer measures bilateral knee/elbow/hip interior angles and unsigned torso-vs-score-up angle against Fit3D GT. True up is **scorer-only**; runtime never sees it. Signed error below means predicted unsigned angle minus GT angle, not a signed anatomical flexion or backward/forward form label. All7metrics have33,412paired main frames. The earlier12model-angle phone comparisons measured candidate-vs-full geometry on different hybrid-input captures, without GT; they are not these accuracy errors.

| Metric | MAE degrees: raw / full / candidate | Mean signed error degrees: raw / full / candidate |
|---|---:|---:|
| knee_right | 15.564054 / 15.537472 / 15.537472 | -7.651081 / -7.607094 / -7.607094 |
| elbow_right | 12.397780 / 12.392039 / 12.392039 | +5.483652 / +5.489394 / +5.489394 |
| hip_right | 15.679031 / 15.644642 / 15.644691 | -1.490966 / -1.451642 / -1.451593 |
| knee_left | 15.876172 / 15.788069 / 15.788069 | -8.529434 / -8.439745 / -8.439745 |
| elbow_left | 13.020881 / 13.000953 / 13.000953 | +5.440495 / +5.460423 / +5.460423 |
| hip_left | 16.482391 / 16.455353 / 16.455353 | -1.215354 / -1.186665 / -1.186665 |
| torso | 12.434532 / 12.456599 / 12.456599 | -8.355448 / -8.377604 / -8.377604 |

Candidate/full mean angle error is essentially unchanged except right-hip MAE increases0.0000487°; its worst paired absolute-error increase is0.188479°. Other main angular paired changes are floating-point-scale and torso exactly unchanged. These are **nonzero GT angle errors** (roughly12–16°MAE), not evidence of accurate angles because the candidate preserves most full geometry. The signed/MAE supplement contains every predeclared partition/exercise and all7metrics, read from completed outputs only; no new candidate or threshold was evaluated.

## Motion preservation and stationary proxy limitations

Existing frozen5-index GT-displacement proxy, >20mmeligible movement and projected prediction displacement <half GT movement. No GT direction enters runtime; both endpoints must remain in the scored partition. Root-relative pelvis never qualifies as moving, and5indices span variable dataset time rather than a fixed millisecond interval. Actual incorrect-form labels/contact truth are unavailable; these counts are not form-error FN or exercise success.

| Exercise | GT-moving joint-intervals | Suppressed count/fraction: raw / full / candidate |
|---|---:|---:|
| all | 245,584 | 61,537 (25.0574%) / 63,445 (25.8343%) / 63,389 (25.8115%) |
| barbell_row | 47,988 | 8,110 (16.9001%) / 8,277 (17.2481%) / 8,255 (17.2022%) |
| pushup | 78,488 | 26,093 (33.2446%) / 27,803 (35.4232%) / 27,774 (35.3863%) |
| squat | 119,108 | 27,334 (22.9489%) / 27,365 (22.9749%) / 27,360 (22.9707%) |

Candidate suppresses56fewer of these intervals than full, but1,852more than raw. All three exercises retain more suppression than raw. A small full→candidate difference cannot be presented as resolved motion suppression or improved bad-form detection.

The separate stationary proxy usesGT displacement<5mm and predicted displacement>20mm. Its main denominator159,448joint-intervals **includes33,112root/pelvis intervals**: GT and all root-relative predictions are exactly zero there, so they always contribute stationary/no-false-movement and lower the aggregate fraction. They do not represent observed hand/foot support. Counts/fractions are raw13,763/159,448=8.6317%, full14,469=9.0744%, candidate14,361=9.0067%. The candidate remains worse than raw on this proxy too. Masked predictions remain included; none are hidden as a correct stationary pose. Individual intervals/subjects are correlated and no significance claim is made.

## Reproducibility and freeze

Public artifacts: [main aggregate](fit3d_continuity_cpu_aggregate_20261102.json), [signed-angle scores](fit3d_continuity_signed_angles_20261102.json), [parity/source provenance](fit3d_continuity_provenance_20261102.json), and [worst joint/frame](fit3d_continuity_worst_20261102.json). These contain derived statistics/code hashes only; no actual joint arrays, video, photo, individual input hashes or personal calibration.

Home private completed artifacts: `~/bpt-runs/target-continuity-20261102/results/{aggregate.json,parity.json,predictions/stream_*.npz}`; code and synthetic fixture in adjacent`code/`. Existing original Python reference is `~/bpt-runs/motion-contact/_code/fe0bc62`; original raw/2D/GT paths remain as availability report. All200used observation/GT files were rehashed unchanged after the CPU run; original18source hashes, manifest/results and experiment source hashes were checked again at closure. Saved60output hashes were verified before derived signed-angle/worst scoring. The [public main aggregate](fit3d_continuity_cpu_aggregate_20261102.json) byte hash equals Home.

Mac native fixture/reference artifacts remain private at `~/bpt-runs/fit3d-continuity-parity-20261102/`: corrected`synthetic-complete.json`, native`fixture`binary, `main.swift`, verbatim`median.swift`, `gate-complete.json`; failed original`synthetic.json` and`initial-gate-failure.json` retained. The source generator is [continuity_parity_fixture.swift](../../scripts/wrist_observation/continuity_parity_fixture.swift), linked directly with the three pinned native constraint sources and frozen filter. No model is linked. Native reference Swift sources remain under`ios/Runner/NativePose/PosePipeline/`; provenance records every source hash.

Reproduction commands (fresh output only; do not overwrite completed originals):

```sh
# Synthetic numerical gate on the frozen reference; no actual data accessed.
python scripts/wrist_observation/check_continuity_parity.py <synthetic-complete.json> --reference <frozen-reference-root>
# Home, CPU1/nice19; requires copied frozen experiment code and synthetic-only fixture.
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 PYTHONHASHSEED=0 nice -n 19 <bpt-home-python> <code>/fit3d_continuity_cpu.py --fixture <code>/synthetic-complete.json --out <fresh-private-output>
```

The main command rechecks Home-native parity, frozen original source/inputs and original A metric gate, produces all streams, then verifies input integrity at completion. The scorer-only signed-angle and worst-case helpers read completed saved outputs; they do not rerun constraints or inference. Python tests23passed before actual execution, independently confirmed by root; native synthetic gate passed locally and on Home. The original fixture coverage failure remains documented. No repeated actual candidate run, parameter sweep, additional ablation or app activation followed this one completed experiment.

The numerical target-switch contribution is now accompanied by accuracy evidence showing mixed/worse tradeoffs. The candidate remains offline and **is not recommended for adoption**. Fresh independent validation and actual incorrect-form/contact labels remain absent; no project-wide coaching accuracy completion claim follows from this bounded result.
