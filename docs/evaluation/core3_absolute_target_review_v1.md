# Core-three absolute-target review worksheet v1

Prepared 2026-11-04 for source `9eb7e28`; registry `20261103-r1`. This is a blank rubric for review, not an approved posture standard or runtime configuration. It covers five currently unset rules and **six scalar target parameters**. Barbell row has no absolute-target rule in this worksheet. The [JSON worksheet](core3_absolute_target_review_template_v1.json) copies exact rule IDs, comparators and versioned metric contracts from the registry; all proposed values remain null.

## Complete before reviewing candidate outcomes

Use the existing [independent review protocol](independent_form_protocol_v1.md): a qualified human reviewer and different human adjudicator, blinded to candidate predictions and angle-proxy outcomes. Keep uncertain labels unknown. This worksheet adds no credential requirement. Freeze the rubric, candidate, source-clip and boundary hashes and participant/duplicate-group split before review. The previously explored 20 Fit3D clips are development data, not a new holdout.

For each rule, fill the JSON `targetReview` and `rubricReview` sections: selected supported variant; source and rationale; exact geometry correspondence; visible positive/negative definitions; acceptable views and visibility; phase boundaries; side policy; duration/aggregation; boundary tolerance and measurement-uncertainty policy. A proposed target is an explicit scoped goal, not evidence that the sensor measures it accurately. If the desired visual target cannot be translated into this metric, retain null and record the mismatch. An incomplete worksheet must not be imported as a configuration.

Review full local clips with context around each interval. Record the actual visible phase and anatomical side independently of the model's phase/side estimate. Label each physical repetition × rule × side under the frozen rubric; an absent top phase is not evidence of failed extension. For mixed evidence, retain the known component and leave unsupported components unknown. Preserve disagreement in the private ledger and adjudicate independently. The JSON annotation example is a worksheet only: it is **not** an input row for `independent_form_eval.py`. Map candidate IDs to the existing form catalog explicitly before constructing that tool's manifest; similar names do not establish identical rules.

## Exact geometry used by the candidate

All metrics below have unit `degrees`, version `1`, coordinate `XS_H36M17_model_space_body_relative`. Let `J[i]` denote an H36M17 joint. Define `A(a,b,c)` as the angle between `J[a]−J[b]` and `J[c]−J[b]`, computed by the clamped normalized dot product and expressed in degrees. Degenerate/nonfinite inputs are unavailable; a straight line is 180°, not 0° flexion.

| Metric IDs | Exact construction | What visual review must establish independently |
|---|---|---|
| `leftElbowDeg`, `rightElbowDeg` | `A(11,12,13)`, `A(14,15,16)` | Corresponding shoulder/elbow/wrist and the relevant phase are visible. A projected image angle is not automatically this 3D interior angle. |
| `leftKneeDeg`, `rightKneeDeg` | `A(4,5,6)`, `A(1,2,3)` | Corresponding hip/knee/ankle and the relevant phase are visible. |
| `leftHipDeg`, `rightHipDeg` | `A(8,4,5)`, `A(8,1,2)` | Thorax-centre–hip–knee geometry is the requested target. This is not shoulder–hip–knee or a lumbar segment angle. |
| `leftUpperArmDeg`, `rightUpperArmDeg` | `d=unit(J[0]−J[8])`, `l=unit(J[11]−J[14])`, `n=unit(d×l)`. Project the corresponding elbow-minus-shoulder vector `u` as `p=u−(u·n)n`; result is `angle(d,p)`. | Chosen view and visible landmarks support the requested arm–trunk relationship. This body-frontal projection is not anatomical shoulder elevation. |
| `{side}ElbowCompletedBottomMinimumDeg`, `{side}KneeCompletedBottomMinimumDeg` | Minimum corresponding interior angle over all supported samples in the completed observed bottom-phase membership. | Descending entry, full bottom interval and ascending exit are present; an arbitrary clip minimum is not this metric. |

Left/right are model anatomical labels; display mirroring or a selected-side flag does not independently verify them. Exact definition hashes are included in the JSON for both expansions of `{side}`.

## Five rules to resolve

| Rule and parameter(s) | Current predicate and phase | Reviewer decision still needed |
|---|---|---|
| `pushup.projected_arm_range`; `pushup.projectedUpperArmUpper` | Floor push-up; descending/bottom/ascending. Left **OR** right `UpperArmDeg > target`. | Define acceptable arm relationship for this variant, observable evidence, side policy and duration. One supported exceedance supports the OR; declaring neither exceeded requires both sides. |
| `pushup.bottom_target`; `pushup.bottomElbowUpper` | Floor push-up; left **OR** right completed bottom elbow minimum `> target`. | Specify elbow interior-angle target, tolerance and complete bottom interval. This does not measure chest-to-floor distance or contact. |
| `pushup.top_extension_target`; `pushup.topElbowLower` | Floor push-up, top; left **AND** right elbow angle `>= target`. Meaning is **desired match**. | Specify bilateral top target and sufficient observed top duration/coverage. A positive predicate means the supplied match, not a fault. A partial top observation cannot establish whole-rep failure. |
| `squat.bottom_target`; `squat.bottomKneeUpper` | Bodyweight or barbell-back squat; left **OR** right completed bottom knee minimum `> target`. | Select variant and knee-angle target; define full bottom observation. This does not measure thigh-to-ground orientation or absolute squat depth. |
| `squat.top_extension_target`; `squat.topKneeLower` **and** `squat.topHipLower` | Bodyweight or barbell-back squat, top; selected anatomical side knee **AND** thorax8–hip–knee angle `>=` their respective targets. Meaning is **desired match**. | Specify both targets, selected-side policy and top coverage. Preserve each component; one visible knee does not establish hip extension or bilateral extension. |

The current registry evaluates top and arm predicates at samples. It does not supply a human per-repetition duration/aggregation rubric. Complete that policy before comparing frame predicates with human labels. Desired-match-negative may be used as a scoped deviation proposal by the current display path; a matching predicate must never be counted as a positive fault label.

## Support and view limits to retain in the review record

The existing engineering support settings are score ≥0.5 on every required joint and absolute raw-versus-assessment angle difference ≤10°. These are **existing computational gates, not human tolerances or calibrated accuracy bounds**. Metrics also require finite geometry, a present invalid mask with no required joint invalid, usable `ok`/`partial_3d` state and non-flush samples. Upper-arm support includes pelvis0, thorax8, both shoulders11/14 and the measured elbow. A high detector score does not verify occlusion, physical side or 3D accuracy.

Bottom membership requires observed descending→bottom→ascending transitions. The result becomes available on the ascending transition and refers to the preceding bottom samples. Source indices must be consecutive and source PTS strictly increasing with gaps ≤0.25s; context/side/epoch changes reset membership, and storage is capped at512 bottom samples. These are implementation conditions, not proof that the model's phase boundaries match the actual movement. Use the recorded membership and a separately reviewed full interval when evaluating coverage.

The candidate's engineering policy permits an unknown view (`view: not_required`). `side_view=true` is only a model-side estimate; false does not identify front/oblique. Therefore the reviewer must supply acceptable views and visibility for the rubric; do not describe a computationally available measurement as visually verified. No rule here directly observes lumbar/cervical curvature, muscle force, hand/foot surface contact, heel lift or chest contact. Record those as outside this metric, rather than inferring them from its angle.

## Numerical target provenance

No numerical target is proposed in this worksheet. The primary push-up study already cited by the project measured humeral elevation using digitized anatomical segment coordinate systems and segment rotations. It did not measure this XS body-frontal projected upper-arm angle; its numerical recommendations do not transfer directly. [Suprak et al., methods](https://pmc.ncbi.nlm.nih.gov/articles/PMC3867095/) (checked 2026-11-04).

For all six scalar values, either document a source supporting the **same** measured geometry and applicable variant, or explicitly record a reviewer-supplied scoped target with its rationale and validation needs. This is not a claim that no useful literature exists. Do not substitute first-three-repetition values, rep-counter thresholds, Fit3D angle distributions, the10° computational disagreement gate or general “full extension” wording for a reviewed numerical target. Sensor error, human boundary ambiguity and target choice need separate entries.

Source references: [registry](../../scripts/coaching_criteria/candidates/registry_v1.json), [metric catalog](../../scripts/coaching_criteria/catalog.py), [native measurements and membership](../../ios/Runner/NativePose/Evaluators/CoachingCandidateEngine.swift), [posture contract](core3_posture_criteria_v1.md). Filling this worksheet does not alter those files, activate a candidate or produce human-adjudicated labels.
