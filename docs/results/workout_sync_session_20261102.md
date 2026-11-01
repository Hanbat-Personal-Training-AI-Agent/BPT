# Owner-scoped workout sync — 2026-11-02

Scope: client queue, repository and record-state handling only. No real API mutations, deployment, schema/default changes, or historical-record migration.

## Contract

- Each provider captures an Auth session lease; account A→B→A cannot revive an old owner. Repository GET/POST and sync POST pass the local ApiClient request guard, including token-refresh retries. Dependencies: Auth lease `65adb75` and transport guard `049e433` (cherry-picked here as `1ad091e` / `2e7060e`). This patch does not edit those owned sources.
- Submit stages the owner-scoped queue/cache before POST. A lost acknowledgement retains the same client ID rather than assuming the server did not commit. The fake idempotent-server regression accepts the first request, switches accounts before its response, then retries in a new A session: one server row and one local row remain.
- Concurrent sync triggers share one drain. Ownership is checked after awaits and before external retry, including ID renumbering. Local bookkeeping already started may finish only in its captured owner namespace; it cannot use another account's token.
- 400/422 rows remain queued with persisted per-record errors while healthy later rows continue. Network/auth/server failures stop the drain and retain following rows. Failure storage uses a separate key namespace, not another user's possible queue key.
- A pending GET enriches metadata from the latest local snapshot. Pending and concurrently added/changed identities survive an older server response, including a new submit already acknowledged as synced. Unchanged synced history absent from the response is not resurrected. Explicit conflicting client/server identities do not borrow local evidence.
- Disposed record-state providers ignore late completion/error callbacks.

## Verification

`flutter test --no-pub --concurrency=1` on `workout_sync_session_test`, `workout_submit_session_test`, `workout_get_reconcile_test`, `account_workout_records_test`, `record_id_conflict_test`, `auth_session_transport_test`, and `token_refresh_test`: **33 passed**. These use synthetic in-memory preferences and HTTP adapters, including renumber suspension, pending acknowledgement, A→B→A, old-token retry, duplicate triggers, permanent/network failures, metadata omission and concurrent GET/ACK scenarios.

`flutter analyze --no-pub lib test`: no issues after two brace-style fixes. `git diff --check`: passed.

## Limits

The idempotent retry is a local contract test, not proof of deployed server behavior. No actual API/DB or iPhone execution was performed for this patch. Permanent-row errors are exposed in sync state and persisted; a new repair UI is outside scope. Dashboard/calendar aggregate ownership and actual-set fallback are the next separate audit, not included here. This change does not establish expert form accuracy or alter warning thresholds.
