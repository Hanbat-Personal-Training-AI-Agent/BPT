# Coherent edge reference: predeclared nine-policy comparison

Frozen before implementation outcomes on 2026-11-04, on the separate edge branch after proposal `4861a62`. The first 72-stream paired-agreement experiment is a completed, separately frozen experiment and will not be altered. No phone, model inference, training, or production/default change is authorized by this protocol.

## Single edge-reference policy

Add `edgePolicy = legacy` by default, independent of the existing agreement policy. The candidate stores an edge ratio only from one frame where both endpoints are accepted, their 3D/2D values and scores are finite, both scores are at least the existing 0.45 support threshold, and the same frame has an actual trusted leg-scale observation. Store the edge length, the trusted scale derived from that observation (with the existing scale floor unchanged), their ratio and one timestamp. Length/ratio must be strictly positive; zero/negative/nonfinite values do not become references. Do not add a new epsilon. A one-endpoint update leaves the last coherent reference intact. Every existing reset clears all edge references.

For a large-innovation joint, geometry has three states. It is **known-consistent** or **known-inconsistent** only when a positive finite reference and actual previously observed trusted scale exist, the current parent is accepted, and both current endpoints have finite coordinates/scores and at least 0.45 support. Compare current edge length with reference ratio × the existing previous trusted body scale, retaining the exact existing 0.4–1.8 bounds and existing numerical floor. Only known-inconsistent vetoes the unchanged reliable && (agreement || persistence) relocation path; its three-frame count is unchanged.

All other cases are **unavailable** and neutralize only the geometric veto. They do not assert validated bone geometry and do not silently revert to mixed-time `lastObserved` endpoints. In particular, unsupported/rejected/nonfinite current parent, unsupported/nonfinite child, unknown/degenerate reference, and unknown scale are explicit unavailable reasons. No global validity, correction, confidence, expiry, or candidate threshold changes are included.

A coherent ratio remains available within one continuous source/person/coordinate segment. Record its age; introduce no new elapsed-time cutoff. Continuous occlusion is distinct from the existing timestamp-gap >0.5-second reset, and all existing reset routes end the reference scope. A persistent bad observation while geometry is unavailable may still be accepted by the unchanged evidence path; this is not proof of correctness.

The finite-score requirement above applies to edge endpoints. Scale retains the existing leg estimator's `trusted` eligibility, including its confidence clipping: finite leg coordinates with +infinite scores can therefore contribute to that inherited scale calculation. This is an explicit unmodified limitation, not normal finite support or a new calibration guarantee. The synthetic suite records it without expanding this candidate into a confidence-ingestion change. Reference-age diagnostics summarize only fully evaluable, known-consistent/inconsistent large-innovation comparisons, not every stored reference or frame.

Scale drift uses the existing **previous** trusted scale, not an unaccepted current pose. Gradual accepted scale changes can update references. Abrupt coherent scale changes may be vetoed before the scale updates, so arbitrary scale-jump invariance is not claimed. Capture this limitation in tests and results rather than tuning it away.

## Validation before dataset replay

Preserve original 720 legacy outputs and all 616 paired-agreement synthetic policy/variant outputs. Add same-policy Python/Swift parity and focused witnesses for: the two mixed-time edge failures; bootstrap with no reference; neutral unavailability for unsupported/rejected/nonfinite parent and child; degenerate reference refusal; every reset route; continuous long occlusion; changing crop-unit conversion; gradual body-scale changes; and abrupt coherent body-scale changes. The latter is a documented limitation, not a target for threshold adjustment. Hash-bind source, generated Python policies, fixtures and parity receipts before replay.

## Fixed replay and reporting

Reuse the exact 60 clean and 12 stress streams and unchanged input hashes, units, causal profile schedule, 270-frame stress limit, 90:end primary window, whole-sequence denominator, actual-damage partitions and scoring definitions from `motion_anchor_alignment_protocol_20261104.md`. No new model calls, inference, data selection, profiles, GT in estimators, or post-outcome policy edits.

Run **nine policies**: A/raw, legacy G/H, paired-agreement G/H, edge-only G/H (legacy agreement), and paired-agreement-plus-edge G/H. First reproduce every non-timing array for the existing five policies against their frozen historical/first-experiment outputs, including explicit raw-A schema compatibility. Save all nine predictions before parsing that sequence's GT. Keep arrays and per-sequence records on Home; export aggregates and receipts only.

Report the same full/target/wrist/ankle MPJPE, coverage, true-reference-motion gain/suppression proxy, recovery/censoring, whole and primary denominators, scenario/exercise partitions and mechanism counts. Add known-consistent/inconsistent/unavailable edge counts and reasons, reference ages, and changed decisions. Separate the isolated edge-only effect from the combined policy and do not infer general accuracy/adoption from reused development data.
