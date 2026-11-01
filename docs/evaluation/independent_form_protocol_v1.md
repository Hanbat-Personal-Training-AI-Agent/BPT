# Independent per-rep/rule annotation protocol v1

Protocol ID: `bpt-independent-form-v1`. This is an annotation/evaluation contract, not a clinical diagnostic rubric or an acceptance result. Freeze this file's SHA256, candidate commit, full clip bytes' SHA256, boundary-source manifest SHA256 and participant-group split plan before review. Every decision opportunity is one clip × physical rep × rule × side; it is not a warning event count and not a whole-rep correctness grade.

## Provenance and blinding

A qualified human reviewer and a different human adjudicator must agree on each binary fault label using a separately documented exercise/rule rubric, including observation phase, side and tolerances. Record pseudonymous reviewer IDs; qualifications, rubric rationale and disagreements stay in a private review ledger. `human_adjudicated` is a provenance attestation, not a credential the CLI can independently verify. Do not invent expert identity, auto-fill labels from model output, Fit3D angles/threshold proxies, first poor reps/running baselines, AI labels, file names, or dataset good/bad tags. Reviewers should be blinded to candidate predictions and angle-proxy outcomes. Resolve disagreement independently; uncertain cases stay `unknown`.

Current source distinctions: Mendeley MV7 already has dataset-author **clip-level** good/bad labels (26 participants, duplicate cross-subject files excluded; see `docs/data/sources.md`). The two-pass per-fault labels described in `docs/results/public_eval_data.md` and `docs/results/lift_app.md`, and the separate Ex3D 132-rep/2940-row first pass (1064 strict rows, different rubric), are AI visual labels without human adjudication. They cannot be promoted to this primary expert metric. `merge_labels.py` merges those passes; `eval_public_sets.py` scores that different clip/rep-count proxy. The missing evidence is independent human-adjudicated **per-rep/per-rule** labels for the frozen candidate, not the absence of all form labels everywhere.

## Windows and strata

Use existing permitted clips locally; never upload videos, images, arrays or participant profiles. The tool processes only IDs, hashes, times and categorical observations. Hash actual full source clip bytes, not a file path or a fabricated digest. Record exact seconds and the original boundary manifest hash. Dataset/AI boundaries may seed **windows only** (`boundarySource` declares that origin); they are not fault labels and do not prove a complete rep. Inspect context before and after each interval, including final extension/top phase for no-lockout rules. Existing AI no-lockout windows may end before top; an absent phase is not evidence of failure. Revise boundaries only as a separately frozen manifest/review task before scoring, never to improve a test result.

Declare `windowCoverage`, per-rule visibility, side and contact-change strata explicitly, including unknowns. If the relevant joint/phase/contact or suitable view is unobservable, keep the human label unknown unless the rule-specific rubric supports an independent certain judgment. Preserve such opportunities in coverage/unlabeled counts. Relative consistency, no drift from a poor baseline, and no delivered warning do not certify acceptable absolute form. Do not train, tune thresholds or select fixes against held-out adjudications.

Assign `splitGroup` to a stable, nonidentifying participant/source-duplicate group before annotation. One clip hash and one group cannot cross development/holdout. Group identity and duplicate-source audit require external provenance; the CLI cannot discover hidden shared people or transformed duplicate videos. Exclude uncertain identity duplicates or document them outside primary holdout results. Holdout results stay separate from development; the report also shows an explicitly pooled overall count, not a substitute for holdout performance.

## Prediction import

Freeze a candidate commit. Import one candidate observation per manifest opportunity: `warning`, `no_warning`, `withheld`, or `missing`. `no_warning` requires an actually evaluated rule/phase/view/reference with finite inputs; silence, quiet/default-disabled delivery, another normal rule on the same segment, and an unobserved prior warning are not negative evidence. Choose `withheld` for a known eligibility/uncertainty gate with a reason code; `missing` for absent/unimported observations. Template predictions default to missing. Repeated warning events within one rep do not create repeated opportunities. No new inference is run by the CLI.

## Denominators fixed before labels

Only positive/negative labels attested `human_adjudicated` enter primary label denominators. Unknown labels are excluded from accuracy and reported explicitly, with all-row prediction-state counts. TP/FP/FN/TN in `selectiveConfusion` use only binary labels **and** warning/no-warning predictions. Withheld/missing negative cases are unresolved, never true negatives.

- Strict FN = selected no-warning positives + withheld positives + missing positives. Strict recall = TP / **all adjudicated positives**.
- Selective recall/specificity/accuracy condition on actually decided eligible observations; each output carries numerator and denominator.
- Decision coverage = warning/no-warning adjudicated opportunities / **all adjudicated opportunities**.
- Correct coverage = (TP + TN) / **all adjudicated opportunities**. This does not pretend unresolved negatives were correctly classified.
- Precision = TP / delivered warning opportunities with binary labels. Zero denominators produce null, never 0 or 100%.

Inspect split/exercise/rule/side/visibility/contact-change/window strata and physical-rep counts. Samples on different rules of the same rep are correlated; no independence or population accuracy claim follows from row count alone. Coverage and label selection can bias selective rates. Prespecify sample size/holdout gate and independent rubric before any release decision. Synthetic math fixtures prove implementation only.

## Local commands and immutability

Use Python3 stdlib only. Prepare a metadata-only manifest matching `scripts/form_eval/input.schema.json`; the CLI additionally enforces semantic identity, split and count constraints. Then:

```
python3 scripts/form_eval/independent_form_eval.py template --manifest PRIVATE/manifest.json --protocol docs/evaluation/independent_form_protocol_v1.md --boundary-manifest PRIVATE/original-boundaries.json --output-dir PRIVATE/new-annotation-task
python3 scripts/form_eval/independent_form_eval.py score --manifest PRIVATE/manifest.json --protocol docs/evaluation/independent_form_protocol_v1.md --boundary-manifest PRIVATE/original-boundaries.json --labels PRIVATE/new-annotation-task/labels.json --predictions PRIVATE/new-annotation-task/predictions.json --output PRIVATE/new-report.json
```

Templates start unknown/unreviewed with null observers; predictions start missing. Fill human annotations and import real scoped predictions in a private working copy, freeze input hashes, then score. Inputs are never changed; hashes are checked again before writing. Existing output paths/annotation directories are rejected. Preserve prior manifests/reports and create new revisions. The scorer rejects duplicate/missing rows, unknown keys/rules, conflicting clip/group splits, identity/hash/side/unit/time/candidate/protocol mismatches and nonfinite numbers. JSON Schema describes shapes; CLI validation remains required. Do not publish small identifiable strata; export only permitted aggregate counts/hashes.
