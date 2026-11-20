# Shadow contract follow-up: explicit confidence policy and typed metadata

This follow-up supersedes the **engine eligibility policy** of `06ff5bb`, while preserving its original report, aggregate, source receipt and private outputs unchanged. It does not change production native/deep judgement.

Native source review resolved a policy distinction: `FormWarnings.swift:658` sets 3D `requiredOK=true` and derives finite masked-chain geometry; the 3D measurement does not apply the 2D per-joint threshold. `FormWarnings.swift:33,892–906` uses the existing **0.30** threshold for 2D measurement; `MotionAGFormerLive.swift:121` separately uses a global count of at least six supported joints. `MotionAGFormerLive.swift:226` retains input H36M detector confidence, and `PoseCoordinateTransforms.swift:170–194` directly maps the elbow/knee dependent joints from COCO. Source `1a35d3f` and base `654fab2` have identical FormWarnings SHA `b4161e2b386f46ab1db2f14075ef11e0ab9c709962ef6f7cfcf4a2ec74758449`.

The shadow contract now names an additional conservative policy:

`shadow_required_chain_2d_support_native_config_0.30`, `original_3d_judge_gate=false`.

To qualify its **shadow** relative result, each current/reference selected-chain joint must have an actual finite detector score at least 0.30, in addition to the previous finite/mask/state/span/view/phase/side requirements. Missing or low dependent-chain scores withhold qualification, including the zero-score sentinel counterexample. This reuses an existing source value without claiming it was the original native 3D rule. Missing or low unrelated joint scores do not suppress a supported chain positive. Scores above one remain unchanged; there is no clamp. High detector scores still do not establish visibility or 3D correctness. The unqualified observed scalar and any original warning remain independent and preserved.

Optional target metadata is now structurally typed: exactly `id`, `revision`, `source_provenance`, `review_status` (unreviewed/reviewed), with nonempty string identity/revision/provenance. It is still **unused**, cannot add approval/validated flags, and never authorizes absolute-form evaluation. Hash-bound first-three IDs reject booleans masquerading as integer 1.

**35 tests PASS**, including both private actual-input tests; default discovery is 33 PASS + 2 skips. Tests add zero/missing/nonfinite detector confidence, exact 0.30 boundary, unrelated low confidence, unverified confidence policy, malformed target profiles and boolean reference IDs. `git diff --check` passes.

The same three original native streams and verified genuine row report were replayed with the stricter shadow policy, with every input SHA unchanged. Counts are unchanged: squat 10 withheld (view missing); pushup 5 relative no_warning + 5 withheld (3 first-three collection, 2 source gaps); native row and worker row each 10 unsupported. There are still zero actual paired pushup/squat deep comparisons and no expert/absolute-form accuracy claim. Original runtime/delivery remain missing; the worker's 10 generic symmetry faults remain separate.

New private complete output:

`/Users/6_month/bpt-data/coaching-shadow-replay-20261103-confidence-private/`

New repository artifacts: [aggregate](coaching_shadow_replay_confidence_20261103.json), [source/input/output hash receipt](coaching_shadow_source_receipt_confidence_20261103.json). The previous `coaching-shadow-replay-20261103-reviewed-private` output and `coaching_shadow_{replay,source_receipt}_20261103.json` are historical, immutable receipts of the earlier mask/geometry-only shadow candidate. No production behaviour, data, threshold, model, voice or setting was changed.
