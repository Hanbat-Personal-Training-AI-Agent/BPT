# Calibration combined-feature lifecycle — 2026-11-02

Base `6835d3c`. Both experimental flags remain OFF by default. No native/model/backend/deployment changes.

The combined `BPT_EXERCISE_SETUP=true` and `BPT_MESH_REVEAL=true` run reproduced two observers for each accepted job: setup's background `CalibrationResultStore.track` and the analyzing screen's mesh preparation loop. The screen constructed its own store without disposing its3-second delayed background polling. This was a real ownership/lifetime problem, not merely a widget harness timing assumption.

The account provider now owns the setup store and cancels its local request/wait when the provider is disposed or replaced. The analyzing screen captures that store only for a current owned capture; stale/unowned captures cannot adopt the current account store. Setup-only background polling survives normal result-route navigation under the same account. Accepted remote jobs and capture files are not deleted/cancelled. This patch does not add a job receipt queue or pretend that an existing server job must be resubmitted after local observer cancellation.

With mesh enabled, the existing screen poll is the sole observer and also saves validated setup measurements when enabled, before an optional model download. A failed preview download therefore does not discard usable measurements. Its wait/deadline timers are explicitly cancelled on screen disposal or account invalidation, including during an in-flight response. A late result cannot prepare or deliver an obsolete mesh. The existing accepted upload can complete after navigation; ownership checks still apply. Store terminal `done` without a usable result now stops observation without saving, rather than polling an already-terminal job until timeout.

Tests exercise store disposal during both an active request and inter-poll wait, ignoring late done output, a fresh observer using the same accepted job id, screen disposal without pumping timers away, setup-only accepted-job persistence after navigation, one combined observer, and validated result persistence even if the optional preview fails. The setup-only mesh-off test now explicitly distinguishes enabled background setup observation from absent mesh downloads; its previous unconditional zero-poll expectation conflated the two independent flags.

Final checks:

- Both flags, owner/auth/analyzing/capture/mesh suite: **62 passed, 1 skipped** (the setup-only route test is intentionally inapplicable).
- Setup-only owner/analyzing: **35 passed**.
- Default owner/analyzing: **31 passed, 4 skipped** (feature-specific tests).
- Mesh-only analyzing: **18 passed, 1 skipped**.
- Targeted analyzer: no issues. `git diff --check` clean.

Logs: `/Users/6_month/bpt-runs/calibration-{combined,setup-only,default,mesh-only}-final-20261102.log`, analyzer `calibration-combined-analyze-20261102.log`. These synthetic tests do not validate actual body accuracy, remote worker behavior or camera operation.
