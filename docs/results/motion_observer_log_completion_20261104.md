# Observer diagnostic completion robustness — 2026-11-04

Base: `c715d745b8f840cc9d7cbbad6ea671733cd13305`. Isolated branch/worktree; no phone writes, deployment, training, merge, or changes to observer defaults or feedback adoption.

## Contract

`ExerciseMotionObserverLog` keeps the `bpt.motion-observer-log.v1` header and `bpt.motion-observer.v1` observation records. The header adds `completion_requires_footer` and `completion_schema`. A final `type: footer`, `schema: bpt.motion-observer-completion.v1` record reports completion, reason, close reason, drain status, pending frames, data-record counts, observation-record count, and suppression counts. A missing or invalid footer is incomplete. Consumers should select observation records by their schema; a line count now includes the final control record.

The existing maximum rows and bytes include the header and footer. One row and 2,048 bytes are reserved for the footer; invalid limits fail before file creation. UUID names plus exclusive creation preserve prior runs. Serialization failure, oversized records, byte/row caps, explicit stop, deinitialization, background/capture interruption, processing/flush failure, missing expected observation, superseded drain, and unflushed tail cannot become complete through a later normal finish. Failed data writes recover the last known line boundary before a best-effort incomplete footer. A failed success-footer write is removed before retrying an incomplete footer.

`CameraPosePreview` preserves stopped-generation rejection. It now counts that rejection, distinguishes legitimate no-raw-model-output and synthetic flush-tail exclusions from a missing expected observation, and fences capture processing, lift work, and the produced main-actor logging tasks before EOF closure. The read-only pending-frame count does not flush or change XS computation. A new source revision during a pending close prevents that close and permanently marks the run incomplete. Asynchronous processing-error marks are bound to the captured revision.

The historical v5 H one-row difference was already explained as `stopped_generation` in the existing validation receipt. This change adds prospective completion evidence and accounting; it does not reinterpret that row as a mysterious error or claim to repair model accuracy.

## Validation

- `swift test --package-path ios/CalibrationEngineKit`: **311 tests executed, 4 skipped, 0 failures**. Includes 12 logger/drain-accounting tests and the existing 10 observer tests. Logger cases cover normal completion, no-overwrite, row/byte caps, oversized/invalid JSON, partial writes, persistent write failure, failure after a complete footer write, stop/deinit/interruption, missing observation, superseded drain, invalid pending count, and actual XS pending/flush behavior.
- Existing every-variant test compares raw, constrained/masked pose, validity, constraint values, rep/warning output, and flushed outputs bit-for-bit against the observer-disabled pipeline. It passes; the observer remains off by default.
- iOS arm64 Runner typecheck: passed using the cached v5 Runner framework/search-path arguments, the 65-file Runner source list redirected to this worktree, `-typecheck -whole-module-optimization -j 1`, and an isolated module cache. No signing/link/install step; command recorded at `/private/tmp/bpt-observer-typecheck/command.json` and compiler output at `/private/tmp/bpt-observer-typecheck/typecheck.log`. Existing AVFoundation/concurrency warnings remain. An initial fresh workspace build was stopped during dependency compilation in favor of this cached check.
- `swiftc -frontend -parse ios/Runner/NativePose/Camera/CameraPosePreview.swift`: passed.
- `git diff --check`: passed.

## Limits and follow-up

This is host validation, not a new on-device capture. Main-actor delivery fencing still needs an instrumented device EOF/set-end/interruption run. Counts are explicitly scoped through the footer: an already closed capped/stopped log does not append later callbacks. A permanent storage failure or process kill can prevent any footer, which consumers must treat as incomplete. The logger is per camera run, so a marked interruption keeps later resumed activity in the same log incomplete. Legacy readers that assume every post-header line is a pose must filter by observation schema.
