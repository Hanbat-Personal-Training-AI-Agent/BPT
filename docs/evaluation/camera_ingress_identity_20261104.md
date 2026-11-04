# Camera ingress identity and stale-session isolation

This is a separate Camera-only follow-up to native fault capture. It is absent from the frozen CLI `94a72a5` run; that CLI already uses its own exact input ledger. No frozen replay, rule thresholds, model, or default is changed.

The old camera path reconstructed original video indexes from a process-global, append-only `VideoRunLog.clipFrame` map using a camera manager's restartable frame index. A new manager's frame zero could therefore inherit an earlier manager's clip index. Separately, external delivery queued work that read mutable `onFrame` later, and fault capture read the current run token inside `processFrame`. Queued old input could acquire a replacement setup's identity.

The fix creates immutable setup bindings and stamps the original video index/clip occurrence before enqueue. External feeders retain their setup handler; queued work never fetches a replacement handler. Physical camera callbacks resolve a handler by their own capture-output identity; obsolete outputs have no route. `CameraProcessingResult` carries the original source index through lifting, and every same-payload camera diagnostic uses it rather than the global map. Source clocks retain the original rational PTS/epoch/flags unchanged.

A generation gate prevents obsolete work from updating the current setup. New setup first invalidates the old generation, drains the processing queue, then drains the lift queue before replacing shared state. The order matters because the synchronous 3D mode can wait from processing onto lifting. Neither queue synchronously waits for the main actor. Later old callbacks are rejected before processing; stale lifted/2D results and visual updates are rejected before their shared consumers. Stale handlers also return false before recorder append or processed counters; dequeued attempts still advance the processing index and are counted as dropped.

Stopping input is distinct from replacing identity: `stopIngress()` rejects new ingress but retains the current identity for valid already-produced/tail results. A new setup rejects the old identity entirely. End-set flush entry, delayed end-set completion, recording completion, queued adaptive seeding/reset and video EOF callbacks are generation bound. The existing calibration `deliver`/`deliverOverride` path is preserved; indexed delivery is optional.

Validation:

- Eight pure Swift lifecycle tests passed: restart frame zero, queued-handler snapshot, late old feeder/lift rejection, repeated clip identity, stop-versus-replacement drain, obsolete camera-output routing, unbound identity, and a second EOF callback hop with coincident terminal epoch.
- Cached all-Runner iOS typecheck passed, **66 Swift sources**, 5.71 seconds. Existing CoreMedia sendability and AVFoundation deprecation warnings remain; no new dependency build, signing or device execution occurred.
- `git diff --check` passed. The coordinated combined branch will run its broader suite/build separately.

Logs, exact commands, typecheck receipt and SHA-256 of every checked Runner source are preserved under `~/bpt-data/completion-20261104-private/native-fault-evidence/camera-ingress/`. The typecheck was performed on the working source before this commit, so its inherited `candidateId` is the preceding test-only commit; `runner_source_sha256.json` records the actual checked source bytes. This is a lifecycle/provenance fix, not an accuracy claim. No phone/UI or new model inference was used for this work.

The EOF review follow-up captures the generation again inside `videoFinished` and rechecks it after the processing-queue fence, before ending a set. Matching terminal epochs alone cannot authorize an old source to finish a replacement setup. The final passing typecheck is `typecheck-v3`; earlier receipts remain preserved.
