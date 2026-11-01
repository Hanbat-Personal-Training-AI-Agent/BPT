# Terminal repetition boundary audit — 2026-11-02

Read-only source/evidence audit of `6835d3c`; no retiming, thresholds, default, model or native behavior changed.

## Verified source limitation

`SquatEvaluator.swift:162–178` and `PushUpEvaluator.swift:280–297` count height-counter `.rep` events and immediately call `emitRep`. Their `emitRep` calls `formTracker.finishRep` (`SquatEvaluator.swift:537`, `PushUpEvaluator.swift:758`). The alternative angle state machine reaches the same immediate function. `FormWarnings.swift:710–746` only aggregates beginRep through finishRep (including the current frame). It does not retain later extension observations for the finished repetition.

The directly affected rules are `squat_no_lockout` (knee_max OR hip_angle_max) and `pushup_no_lockout` (elbow_max): `FormWarnings.swift:1120,1135–1136`. Their self-relative set-max reference can therefore compare truncated ranges, rather than completed terminal extension. Other whole-rep extrema/change metrics also exclude later frames, but that fact alone does not establish an additional false positive/negative; bottom/depth measurements do not automatically need terminal extension. Absolute lockout labels in historical analysis are not additional active native judge rules.

`BenchPressEvaluator.swift:171–175,637–650` already retains pendingFormRep and normally records15 more frames before judgement; it also flushes before a new repetition. This is an existing bounded sampling pattern, not proof that15 frames establish complete extension in squat/pushup or even every bench repetition.

The673 observation patch marks lockout overlay rules `selfRelative` and restricts missing-view/reference semantics (`FormWarnings.swift:1282–1303`). Both squat/pushup no_lockout remain quietByDefault (`504–507`): judged/logged but not delivered by default. This limits communication; it does **not** check terminal-window completeness, change the report's original sampling boundary, or prove correct full extension. The current completeReference check only requires the relevant metric quantities, not completed terminal observation. This timing limitation remains unresolved.

## Preserved evidence and precise replay blocker

Home `~/bpt-runs/ex3d-form-labels/20261023-blind-reps/manifest.json` SHA256:
`8387c771dfa0f6c034c8c46e9a43ab60ea938a1accce2765959ef6ff16dd1e6b`.

A read-only scan of every JSONL input referenced by this manifest found **37 files; all37 original hashes matched**,27,318 judged records and364 repetition records. The39-view extraction includes missing device runs, so it must not be described as39 complete native logs. Judged records provide2D `kp` (flat51 COCO17 x/y/conf), source frame mapping/status, correction/state diagnostics; rep records provide aggregated metrics_2d/metrics_3d, states and boundaries. No per-frame raw3D arrays are stored. Arrays/media remained Home; only key names, counts and hashes were inspected/exported.

The prior AI-labelled report at `ai-ex3d-labels/docs/results/ex3d_form_labels.md:A7` documents median end-to-top gaps20.5 frames squat and7 pushup, with2D end-vs-top differences37° and27°. These are historical AI/2D diagnostics, **not independent expert GT**, not current673 measurements, and not a causal3D correction score. Its own A7 caveat notes source-frame alignment error in timing gaps. We did not view images or reuse AI-selected top anchors as a correction input.

Existing logs permit source-frame/boundary and2D diagnostic audits, and verification of original aggregated reports. They cannot reconstruct later per-frame3D extrema, reapply current formTracker to extended3D windows, or isolate the causal effect of a new terminal window. Missing source: original per-frame predicted3D joint coordinates/state and matching source PTS/frame index across each rep boundary through actual subsequent observation; set-end/disposal completeness and side/view support must accompany them. Existing aggregate metrics cannot recover those samples. A future collection/replay must preserve original boundaries and predeclare a prediction-only observation protocol, with incomplete windows withheld, before accuracy claims. This audit intentionally stops at that blocker; no invented numerical improvement or automatic retiming is reported.
