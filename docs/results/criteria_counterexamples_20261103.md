# Core3 criteria counterexamples: independent preparation

Base `654fab2`; test-only worktree/branch `criteria-counterexamples-20261103` / `test/criteria-counterexamples-20261103`. No AGENTS.md was found. No product/default/model changes, device operations, media access, HTTP/storage replay, or new inference are part of this task.

## Current source requirements, not approved exercise standards

Authority here is current executable source, not a claim of expert-adjudicated exercise correctness. `ios/Runner/NativePose/Evaluators/FormWarnings.swift` is also compiled by CalibrationEngineKit through its tracked symlink. `server/calibration_modal/deep_metrics.py` and `deep_rules.csv` define the distinct deep contracts. Full source definitions and delivery-layer crosswalk remain in `coaching_rule_crosswalk_20261103.md/json`.

| Exercise | Actual current source requirements | Important distinction |
|---|---|---|
| Pushup | Side-view hip sag/pike line-deviation; initial3-relative elbow depth; previous-set-best elbow extension; head displacement; first-top wrist geometry; late-vs-first depth trend | Relative elbow depth cannot certify sufficient absolute depth; head/wrist proxies do not establish neck injury, hand contact or floor anchorage. Quiet depth warning remains judged. |
| Squat | Side-view hips-first requires torso rise >8° **and** hip rise speed > shoulder speed; relative knee depth; knee-or-hip set-best extension deficit; depth/lean trends. Front-view knee/ankle gap ratio. Heel-rise rule disabled. | Torso-rise-only color is not the hips-first conjunction. Available knee deficit can remain positive while missing hip prevents complete correction approval. Valgus gap is not bilateral knee-angle asymmetry. |
| Barbell row | Side-view torso range >39.9°, mean torso upright drift from first3, behind-torso elbow pull shortfall from first3, head/shrug proxies | Row range is not deep trunk standard deviation >8°. Pelvis-relative wrists are not tracked barbell position or force. Baseline equality does not establish strict-row form. |

Several thresholds are explicitly provisional in source. Deep fallback uses relative ROM/depth/tempo, primary-joint bilateral difference and unsigned world-up trunk standard deviation. Neither native nor deep first3 reference is an approved-correct profile. Only two conditional shallow-depth comparisons have an existing algebraic relationship, with matched intervals, side, geometry and evidence prerequisites; generic key parity is not established.

## Counterexamples the new criteria contract must distinguish

1. **First3 all wrong:** a fourth equally limited repetition has zero relative drift. Keep reference provenance and absence of absolute approval; do not label normal/correct from baseline conformity.
2. **Partial observation:** preserve a supported positive fault on one quantity; independently withhold absent quantities and whole-rule correction/negative conclusions. Missing primary phase must not erase unrelated valid elbow angle, nor manufacture a phase angle.
3. **Side switch:** native selected side can change within a rep; exported majority is not the same signal as deep's fixed manifest side. Temporal comparisons must split/reset on side change, not splice extrema or sustain time across limbs.
4. **Boundary/clock:** native begin/finish explicitly record the current sample and can share a boundary sample; deep uses `ceil(ms*fps/1000−1e−6)` and half-open `[start:end)` indices. Fractional milliseconds matter. Require explicit video_ms/PTS mapping; host/inference-arrival time must not silently substitute. Clock origin and interval inclusion must be carried, not inferred from similar counts.
5. **Coordinate transforms:** scalar joint angles are reflection/rotation invariant, but anatomical labels and gravity orientation are not implicit. Mirroring pixels does not itself swap H36M labels. Rotating coordinates without rotating the up vector changes torso inclination. Root-relative joints preserve angles but erase world vertical translation; they cannot measure physical hip rise/contact.
6. **Causality:** future repetitions must not alter an earlier evaluation's criteria/baseline. Initial reference evidence is not available at the first repetition; explicitly preserve withheld state rather than backfill a live judgement from future reps. Offline annotations may reference later context only if explicitly identified as offline.
7. **Missing versus zero:** valid gravity-aligned torso0° is data; collapsed/unsupported geometry is unavailable, not 0°. No warning could mean unsupported, inactive, quiet delivery, cooldown, not applicable, or evaluated negative—these are distinct.
8. **Quiet versus negative:** `quietByDefault`/enabled delivery/cooldown control speech; they do not negate a judged issue. `praise_fixed` requires the same previous rule and source to be actually assessed; generic praise cannot certify all complex posture requirements.
9. **Profile and temporal eligibility:** initial repetitions never create approved profiles. Reference requires exercise/variant, approval revision, phase, side/view/source, required joints, stable clock and no unsupported/duplicate/flush gap. Loss of one prerequisite must not accrue sustained-positive or negative time.

## Executable checks and limits

`python -m unittest discover -s scripts/audit/tests -p test_criteria_counterexamples.py -v` independently constructs synthetic H36M sequences and calls production deep metrics. Ten tests cover all3 relative-reference cases, exact/fractional interval boundaries, fixed selected side, independent partial geometry, valid0 versus missing, future suffix invariance, mirror, rotation/gravity and root translation. All10 passed. Fixtures deliberately represent limited excursions; they are counterexamples to certification by relative equality, not medically labelled samples.

`CriteriaCounterexamplesTests.swift` calls the actual native judge for quiet-positive retention, partial known-positive versus correction qualification, identical limited first3 references for core3, and the hips-first speed conjunction. All4 targeted native tests passed (0 failures). Log: `/Users/6_month/bpt-runs/criteria-counterexamples-swift.log`. No camera/phone/inference is involved.

The new `scripts/coaching_contract` and `scripts/coaching_observation_replay` engines were still being developed when these source-contract cases were prepared. Their planned APIs are not treated as implemented or passed. Independent end-to-end tests against their concrete source require their freeze/entrypoint; their files are not modified here. Current-production numeric behavior passing these tests does not establish human-labelled form accuracy or a finished composite posture policy.
