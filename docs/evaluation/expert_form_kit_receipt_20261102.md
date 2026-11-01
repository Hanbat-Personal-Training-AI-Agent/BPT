# Independent form evaluation kit receipt — 2026-11-02

Delivered a runnable stdlib CLI, input JSON Schema, independent human review protocol, and a Home-private Fit3D window adapter. Search found `merge_labels.py` / `eval_public_sets.py` for the older AI-pass/clip proxy, not this independent per-rep/rule contract. Existing author clip good/bad labels and AI per-fault labels remain distinct provenance; none were copied into expert truth.

`template` writes only unknown/unreviewed labels and missing predictions. `score` requires matching manifest/protocol/boundary hashes, candidate and exact opportunity identities; rejects duplicate/missing/unknown-rule/side/unit/time/split conflicts and existing output paths. Primary binary metrics require attested human adjudication with distinct observer/adjudicator IDs. Strict FN includes withheld/missing positives; selective metrics, unresolved negatives, decision coverage and correct coverage have explicit denominators. Zero denominators are null. A declared human source is an attestation, not machine verification of credentials.

## Actual private task

Final workspace **on Home only**: `~/bpt-runs/expert-form-eval-20261102/task-v2/`. It contains `manifest.json`, blank `labels.json`, missing-only `predictions.json`, `review_index_PRIVATE.json` (local clip locator) and `readiness_report.json`. Nothing individual from these files was exported. The committed readiness JSON contains aggregate counts and hashes only.

| Item | Result |
|---|---:|
| Existing source clips / groups | 20 / 5 |
| Source clock (metadata verified, no frame display) | 50 fps on all 20 |
| Physical rep windows / rule opportunities | 103 / 588 |
| Unknown labels / missing predictions | 588 / 588 |
| Human-adjudicated binary labels | 0 |
| Development / holdout opportunities | 588 / 0 |

Windows come from existing dataset-reference `jobs.json` intervals, converted by the verified 50fps clock. No arrays, GT angles, model inference, expert fault labels or automatic visibility/contact/window-completeness claims were used. Source video bytes were hashed locally using a bounded buffer; existing cached `bpt-ffmpeg/bin/ffprobe` supplied metadata. All individual media/IDs/hashes/annotations remain Home-private. Output directories use0700 and the remote run used umask077.

Task candidate: **8001f4f6955877fbf82f087f77e840fa2486bb6e**, deliberately retained as historical. Later product freeze6835d3c changes null/UI semantics and is not relabeled as having predictions here. All observations are still missing. Explored frozen20 data is development only; this is annotation readiness, **no new expert accuracy or held-out result**.

- Boundary manifest SHA256: `bb354a201824681ba1e78ac9c1b1c47cdb4f85ed160b4212db7b8ddb26c5e7f8`.
- Task manifest SHA256: `30c4667c1b916ad7683270d84eea2d64aa5fc60ff8c86de525054a17e039627e`.
- Unknown-label SHA256: `f28e688e6e90d95d2fb4f86f4c70baa8a25627ebb17fbe79295886f25610f226`.
- Missing-prediction SHA256: `b2dbba1143fcb74320d409d93d0966018d219fe303d31c6bfbc37dcaed9d4da2`.
- Protocol/code hashes are in `expert_form_readiness_20261102.json`; all four local files match the executed Home copies.

## Verification and next evidence

`python3 -m unittest discover -s test/python -p 'test_independent_form_eval.py'`: **15 passed**. Synthetic fixtures cover strict/selective math, abstentions/unknowns, duplicate/missing and identity mismatches, rule/split/time/provenance gates, overwrite refusal, unchanged inputs, schema/catalog parity with native fault IDs, and the private50fps adapter. `py_compile` and `git diff --check` passed. The JSON Schema is parsed/parity-tested; runtime semantic validation is the stdlib CLI, without an external schema dependency. Synthetic fixture rates are not real performance estimates. Real Home unknown-only scoring succeeded with0 adjudicated labels and null accuracy/coverage denominators.

Next: qualified blinded humans must freeze a rule-specific rubric and independently review/adjudicate the private development task, including whether intervals include the relevant final top/extension phase. Keep uncertain observations unknown; change any bad boundaries only in a new frozen task revision. Then separately prespecify participant/duplicate-group holdout, sample size and decision gate; import actual scoped candidate predictions including withheld/missing states. Do not select thresholds against holdout, promote AI/GT proxies, or call no-warning/relative consistency correct form. The historical deep-analysis failures remain unchanged. No production/default/model changes, deployment, downloads or media uploads occurred.
