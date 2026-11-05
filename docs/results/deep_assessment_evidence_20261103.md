# Deep assessment evidence, saved-array validation

The server now adds optional `assessmentEvidence` (`bpt.deep-assessment-evidence.v1`) to the existing report. It binds exercise, FPS, video-ms time basis, rep index, side and exact declared interval. Fifteen metric families carry the actual formula, unit, coordinate/reference type, baseline rep indices and the existing metric-specific support status/reasons. A geometry measurement can be available while posture assessment remains withheld (`validated_posture_target_missing`). These are model estimates, not ground truth or proof of correct form. Existing detection support is not a correctness probability.

Coordinates are metric-specific: interior joint angles use the existing H36M triplets (hip angle uses shoulder–hip–knee); torso inclination is unsigned relative to gravity-aligned world +Y; pelvis displacement uses world Y; hand trajectory uses wrists relative to pelvis, not a detected barbell. Drift references the median of the first up to three declared reps; the first three remain withheld as comparative assessments. Tempo retains the existing extrema/3-degree pause heuristic, not independently labeled motion phases.

The legacy native comparison had accepted a shared device warning alias as evidence of equal definitions. This is false without a native contract covering geometry, window, threshold, baseline and sampling. The server keeps legacy numbers, warnings and faults but now withholds that comparison, leaving device warnings unassessed. In particular, torso range is not torso standard deviation, and knee gap is not bilateral joint-angle difference. The new comparison evidence explicitly lists unassessed aliases. It does not invent synchronization, native source identity or posture targets. Geometry support remains per metric; an invalid elbow does not erase valid knee measurements.

Validation used the **existing actual recovered row arrays**, not new inference, media upload or a new GPU task. `rescore_saved_assessment_evidence.py` gates the original report, arrays, manifest and archived rule SHA, reproduces the original `deep_rules.csv`-only rule environment, and verifies exact equality of every legacy scorer field before adding evidence. Original worker runtime metadata is retained, not represented as newly measured. Current repository catalog evaluation is not substituted for the archived rules.

- 10 actual intervals, 150 metric entries: 141 measurement-available, 9 withheld for baseline prerequisites; 0 posture assessments available.
- All original legacy report fields remain exactly equal on this actual row, including its 10 placeholder symmetry warning events and `not_comparable` comparisons. No accuracy claim follows from those warnings.
- Selected report SHA256: `1d713aad203739b413575c844c258a7d9e96d882f4bcd8853a70845c26326b67`.
- Arrays SHA256: `620022c1f057114be510186db1495e01b0ffaef3ccefaa39eeb07a1c4e7e27ce`.
- Original report SHA256: `f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa`.
- Manifest SHA256: `70a1e8d88b83acb13b9d2d322fa2675625e4060e0346b3d12f2204ed8118ec09`.
- Archived rule SHA256: `ce95348cf2324cbe7818d894e1c18f8d1a9586bdd7f7012b41be96e32f518a32`, independently recorded in recovered `evidence.json` for both frozen scorers.

Reproduce locally with the existing environment and a fresh private output path:

```sh
/opt/homebrew/Caskroom/miniconda/base/envs/bpt-eval/bin/python scripts/deep_analysis/rescore_saved_assessment_evidence.py --out ~/bpt-data/deep-assessment-rerun-private
/opt/homebrew/Caskroom/miniconda/base/envs/bpt-eval/bin/python scripts/deep_analysis/verify_local_storage_http_contract.py --out ~/bpt-data/deep-assessment-http-rerun-private --replay-report ~/bpt-data/deep-assessment-rerun-private/rescored-worker-report.json --replay-report-sha256 1d713aad203739b413575c844c258a7d9e96d882f4bcd8853a70845c26326b67
```

The production service/Bucket/BucketState HTTP harness passed 21 assertions with the selected report, including persistence, report download and restart recovery. It also passed 21 assertions using its unchanged default original-report replay. The selected-report option requires an explicit private-path hash, immutable original hash gates, exact legacy equality and interval binding; it cannot accept an arbitrary replacement report. Network activity was restricted to owned loopback ports and emulated S3 with synthetic credentials; this is not deployed cloud validation or new model execution. Both runs cleaned up their servers, emulated objects and worker temporary directories.

Private selected report and source/input proof: `~/bpt-data/deep-assessment-repro-final-20261103-private/`. Real local HTTP response: `~/bpt-data/deep-assessment-http-20261103-private/actual-local-api-job-response.json`. Legacy-default HTTP proof: `~/bpt-data/deep-assessment-legacy-http-20261103-private/`. Raw arrays, media and full reports remain private. The reproducible helper records current scorer, rule and helper source hashes.

Full server suite: **173 passed, 1 skipped**. The skip is pre-existing optional infrastructure coverage. Server regression coverage includes missing support, partial invalid geometry, exact formula/reference metadata, nonsequential baseline indices, and shared-warning-alias rejection. Frozen historical full-report hashes remain retained; separately frozen noncomparison hashes verified against the same historical scorer ensure that all fields except the intentional comparison correction and new evidence remain unchanged across ten exercise/side cases. The older partial-geometry Flutter fixture remains a legacy compatibility fixture.

Historical hash derivation receipt: `~/bpt-data/deep-assessment-repro-final-20261103-private/historical-hash-derivation.json`. All ten original canonical hashes were independently verified against `e00a8ab` before deriving the additional hashes. Only per-rep `comparison`, `evaluatedKeys` and `unassessedDeviceWarnings` were removed from that historical output. Current tests additionally exclude the new top-level `assessmentEvidence`; all legacy numbers, warning/fault fields, notes and support remain in the canonical comparison.
