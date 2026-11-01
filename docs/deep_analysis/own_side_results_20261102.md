# Own-detector side readout: completed negative ablation — 2026-11-02

**B/C's own detector selected exactly the same side as the frozen evaluator in all 20 videos and all 103 reps.** The candidate therefore changed no retained angle, extremum, phase, reference or threshold decision, including the two row failures and one pushup boundary failure. This rejects the proposed side-selection explanation on this already examined diagnostic set; it does not solve the remaining accuracy failures or establish expert/normal-form correctness.

[Predeclared protocol](own_side_protocol_20261102.md), [helper](../../scripts/deep_analysis/ablate_own_detector_side.py), [tests](../../scripts/deep_analysis/tests/test_own_detector_side.py), [aggregate](own_side_20261102.json). Work is isolated from `2db10ec`; no production/model/default/threshold/deployment change. The previous native-joint approach was not rerun.

The single candidate applies the **unchanged frozen `near_side` confidence rule** to each B/C result's own retained ViTPose COCO17 detections, instead of borrowing A replay's side or the frozen job fallback. Selection uses only confidence, globally per truncated video, never GT, angles, errors, cases or reference peaks. Original H36M arrays and up axes remain unchanged. The primary GT target stays on the original side; changing it along with the prediction is explicitly a separate changed-target diagnostic. A regression test demonstrates how a perfect opposite-side prediction can have zero matched-side error but 30° error against the fixed target.

## Actual full-cache result

| Exercise | Videos / reps | B side changed | C side changed | Original / candidate selected-side elbow macro MAE |
|---|---:|---:|---:|---|
| Squat | 5 / 25 | 0 / 5 | 0 / 5 | B 3.249° / 3.249°; C 3.180° / 3.180° |
| Row | 5 / 27 | 0 / 5 | 0 / 5 | B 6.434° / 6.434°; C 6.520° / 6.520° |
| Pushup | 5 / 25 | 0 / 5 | 0 / 5 | B 11.638° / 11.638°; C 12.328° / 12.328° |
| Deadlift | 5 / 26 | 0 / 5 | 0 / 5 | B 9.085° / 9.085°; C 9.010° / 9.010° |

Macro MAE averages the five video MAEs equally; frame distributions in the aggregate weight inside-rep frames. Unique inside-rep frames remain 1,927 / 1,624 / 1,231 / 2,459 (7,241 total). All knee/hip/elbow/torso metrics, same-side GT diagnostics and immutable bilateral errors are included in the aggregate. **Every original→candidate paired change is zero**, including extrema and reference errors on the same original failed union versus its complements (row 2 vs 25; pushup 1 vs 24). The bilateral torso vector is side independent and was checked for exact equality as a negative control. There is no possible row-ROM benefit from this side-only candidate.

Retained threshold diagnostics remain:

| Rule | B all / boundary agreement | C all / boundary agreement |
|---|---|---|
| Row torso range | 25/27; 1/3 | 25/27; 1/3 |
| Pushup relative lockout | 19/25; 0/1 | 17/25; 0/1 |

Row has two FN per variant; pushup has six/eight FP over all 25 reps and one FP per variant in the original one-rep boundary cohort. These are disagreements with GT-angle proxies, not expert bad-form labels. All original thresholds and running-reference computations remain frozen. No PASS/adoption claim is made.

## Confidence support and controlled perturbations

Every evaluated retained knee/hip/elbow/torso chain has minimum own-detector confidence ≥.35 within its rep. The low-support stratum therefore has **zero reps**, not a successful noisy-data result. The 40 result files contain **no observed tracking masks**. Missing masks were not fabricated. The selector's absolute mean-confidence gap ranges .008–.024 for squat, .017–.057 for row, .059–.090 for pushup and .038–.055 for deadlift. Small gaps do not prove the selected side is correct.

Two predeclared synthetic sensitivity probes were evaluated on all 20/103 for both B/C, separate from retained outputs:

- Gaussian confidence noise σ=.05, clipped 0…1: zero side flips for either variant and no metric/decision changes.
- Gaussian 3D joint noise σ=10mm: both compared readouts receive the same noisy coordinates, so candidate-versus-original changes remain zero. Row agreements stay 25/27 and 1/3. Pushup B stays 19/25 and 0/1; C becomes 19/25 and 1/1. **Adding noise happened to remove the C boundary FP**, which is extrema/reference sensitivity, not accuracy evidence or a recommended correction. No noise was added to preserved arrays or GT.

These single seeded perturbations are not realistic noisy-video validation or clean/noisy expert labels. They cannot establish performance under occlusion, camera motion or detector failure. Selected-vs-bilateral and same-target-vs-changed-target results remain separately exported even though this candidate selects the same side everywhere.

## Scorer source audit: distinguish contracts from defects

| Aspect | Frozen Fit3D scorer | Current server source at `2db10ec` |
|---|---|---|
| Side | One A replay-confidence side, or fixed job fallback | Manifest side for each rep |
| Frames | Frozen 50→30fps pick; inclusive rep endpoints | `ceil(ms*fps/1000−1e-6)` half-open `[start:end]` video windows |
| Coordinates | B/C camera image-up; GT frozen world-up; stored world sensitivity separate | `deep_worker.analyze` passes gravity-aligned `h36m17_world`; +Y up |
| Row target | Raw torso max−min; 39.9° threshold | `trunkStability.rangeDeg` reported, but fallback rule uses **trunk standard deviation >8°**, a different quantity |
| Lockout/reference | Each model's running maximum minus current elbow peak; 10° | No equivalent relative-lockout rule in fallback CSV; ROM/depth drift uses first-three medians and distinct semantics |
| Validity | Historical scorer lacks tracking-support gates | Required joints and all used frames have per-metric gates; first-three baseline support propagates to drift |
| Catalog | Frozen rule dictionary | Tracked tree lacks `docs/coaching/fault_catalog.csv`, so fallback `deep_rules.csv` is explicitly marked placeholder. If a team catalog is supplied, unimplemented metric contracts are explicitly unassessed |

The endpoint, axis and rule differences are observable contract differences, **not evidence that an indexing/threshold bug caused the fixed row/pushup errors**. Existing extrema attribution already reproduced the original metrics and found persistent row compression and differential pushup peak/reference errors. This experiment found no new selector mismatch.

The server computes and validates both-side angle arrays before per-rep slicing; a degenerate segment anywhere can reject the video, including an unused side/frame. Existing `test_world_metrics_ignore_translation_and_reject_degenerate_input` explicitly requires invalid-skeleton rejection, while metric support tests separately cover occluded wrists and interpolated tracking. This is a conservative input contract/availability limitation, not a demonstrated explanation of finite, nondegenerate cached failures. It was not weakened to keep an attractive score. No ad hoc threshold, GT-selected side, reference or unsupported “accuracy improvement” was implemented.

## Reproduction and checks

Home was idle before execution. CPU threads were capped at two, GPU visibility disabled, niceness 10 and a dedicated advisory CPU lock used. All arrays, profiles, models, paths/IDs and media remain Home; only aggregate statistics, hashes, code and protocol were exported. No video decoding, image viewing, training, inference, upload or cloud/Modal call occurred.

All **4,632 original values** reproduced with maximum difference **2.84e-14°**. All **124 input file hashes** were unchanged, including original jobs/score, all40 B/C results, numeric GT/camera/rep sources, available A/floor caches and frozen evaluation sources. Home retains the full private per-source manifest; exported score SHA is `fd84c4971a601fa2fe5b23260f55bb73bed172a8cce0642017775fc619061f5f`. Helper, numeric dependency and protocol SHA values match the exported aggregate.

Four new tests passed locally and on Home: own-confidence selector/ties, explicit fixed-vs-changed GT contract, deterministic non-mutating noise, strict-threshold/nonfinite denominators. Full deep-analysis local discovery: 15 pass, two licensed-Home-only tests skipped. Python compile and `git diff --check` passed.

```sh
export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2 CUDA_VISIBLE_DEVICES=""
flock -n ~/.bpt-own-side-cpu.lock nice -n 10 \
  ~/miniconda3/envs/bpt-gvhmr/bin/python code/ablate_own_detector_side.py \
  --run ~/bpt-runs/gvhmr-eval-20261026 --root ~/datasets/fit3d \
  --protocol own_side_protocol_20261102.md --output aggregate.json
```

The helper uses the existing `ablate_smplx_joint_centers.py` **numeric utilities only**, without invoking or reconstructing any body model. Copy that dependency next to it. No experiment/default is enabled. Remaining row ROM compression and pushup relative-lockout errors are unresolved; new independent anatomical/expert validation is still required before claiming overall posture-analysis completion.
