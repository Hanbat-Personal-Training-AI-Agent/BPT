# Relative coaching shadow evidence v1

This offline module implements **only** pushup_shallow ↔ pushup_depth_drift and squat_shallow ↔ squat_depth_drift. It does not run a production judge, classify correct form, activate a catalog, deliver coaching, or consume the separate explicit-target criteria engine.

`engine.evaluate(stream)` accepts `bpt.coaching-shadow-evidence.v1` and returns `bpt.coaching-shadow-result.v1`. `engine.compare(left_result, right_result)` preserves both results and emits descriptive comparisons. Callers must supply honest evidence; structural validation cannot independently authenticate caller provenance. Actual replay adapters additionally bind the input file bytes and use the existing strict terminal reader.

The contract separates:

- `common_scalar`: selected-side knee/elbow minimum minus the median of **observed set reps 1–3**, degrees, `>15`. This is an observed-subset numeric predicate, not an original runtime verdict. The first three do not have a causal drift verdict. Future reps never change an earlier verdict.
- `qualified_shadow`: warning / no_warning / withheld; requires known joint definition and coordinates, assessment layer, stable actual per-frame side, same current/reference side, finite supported dependent chain across the interval, known view, known phase with a bottom observation, uncertainty provenance, complete selection without source gaps, and hash/set-bound first-three identity. These are conservative shadow gates, not a claim that the original native positive-evidence policy is wrong. Other missing joints do not erase a supported chain's positive result.
- `runtime`: warning / no_warning / withheld / missing from original explicit recorded evidence only. A positive original decision is retained when the common comparison is withheld. `delivery`: delivered / not_delivered / missing. Silence, disabled speech and quiet defaults are not evidence of a negative judge result. Native terminal reps do not contain these judge/delivery fields, so they remain missing.

`criterion_scope=relative_drift`, `reference_kind=observed_first3`, `reference_correctness=not_established`, `absolute_normality=not_assessed`, and `target_used=false` are invariant outputs. `target_profile` metadata is preserved but never evaluated or approved. Explicit targets are deliberately rejected by this version. First-three consistency cannot certify a uniformly limited baseline.

Original intervals include unit and closure: native frame-index intervals are closed; deep video_ms intervals are half-open. Membership must match the interval; complete selections cannot omit available interval frames. video_ms requires an explicit seconds→milliseconds clock mapping. No interval or side history is retimed or replaced with GT. Full native source clocks, phase/view/side histories, masks/confidence, assessment points, original rep records, and raw/constrained/adapted/assessment layer hashes are retained privately. Raw layer values remain in the original hash-bound JSONL; raw scores are never clamped. Source index gaps are retained, not interpolated.

Coordinate/joint/layer/units/source identity are kept separate from scalar values. Descriptive numeric deltas never assert same pose, GT or semantic parity. Missing or different media identity, unbound clocks/intervals, unsupported exercises and source conventions cause comparison withholding. Native playback and deep's reencoded native recording are not silently treated as identical model inputs.

## Run

From repo root (stdlib Python 3.9+):

```sh
python3 -m unittest discover -s test/python -p 'test_coaching_contract*.py'
python3 -m scripts.coaching_contract.replay --native /private/original.jsonl EXPECTED_SHA256 --output /private/new-output-directory
```

Add `--deep-report`, `--deep-sha256`, `--deep-evidence`, `--deep-verification` together for a previously verified worker report. `evaluatedKeys` and `serverWarnings` contain native **device keys**, not deep catalog fault IDs; generic `faults` remain separately preserved. This adapter does not reconstruct per-frame phase, view, side or support from report summaries. The existing real row report is an unsupported negative control for these two rules.

`BPT_COACHING_REAL_ROOT=/private/terminal-device-capture-root` enables one test that reads and hash-checks the three original authorized captures. No media is read, no model runs, and there is no phone/network access.

Output directory must not exist. It is mode 0700, files 0600. Input receipt precedes evaluation; incomplete output retains an `INCOMPLETE` marker and failure receipt and must not be consumed as complete evidence. Successful output contains private stream/results/comparisons and a nonidentifying count/hash aggregate; only the aggregate is suitable for repository export. Original inputs are hash-checked after replay. No existing output or historical record is rewritten.
