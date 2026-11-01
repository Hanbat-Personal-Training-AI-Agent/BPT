# Workout aggregate ownership and actual sets — 2026-11-02

A focused regression reproduced the original dashboard defect: after A's value loaded, signing into B left A's `valueOrNull` visible while B's request waited. Dashboard, monthly-calendar and report aggregates now use separate async families keyed by the Auth notifier and login lifetime. Their synchronous public adapters immediately expose B's loading state (or signed-out null), while same-session reload may retain that same owner's prior value. Each GET carries the ApiClient local session predicate; late responses and old-token 401 retries cannot publish or retry across accounts. No Auth/transport sources are modified by this commit.

The candidate backend also summed `targetSets` as `todayCompletedSets`. The dashboard now publishes `completedSetsEvidenceVersion: 1` and a nullable actual count. Empty days are known zero. Valid native-v1 envelopes supply actual set-list length, including zero. Explicit legacy saved set rows supply a count only with unique positive set numbers and nonnegative reps summing to the record's total. Any unknown contributor makes the aggregate unknown. Planned targets and legacy `totalSets` are never observation evidence; historical rows are not rewritten.

Flutter accepts the server count only with that version marker. Older deployed numeric fields fall back to local supported evidence; mixed unknown local records remain unknown. The home tile shows a dash instead of coercing unknown to zero. Completion/goal and form assessment remain distinct. Repository merges and notifier outputs now sort descending by recorded date, so an older concurrently acknowledged protected row cannot displace newer history at the front.

## Verification

- Original dashboard regression failed before the adapter (`Expected null`, actual A summary); the corrected account-switch and same-uid notifier-replacement cases pass.
- `flutter test --no-pub --concurrency=1 test/workout_aggregate_session_test.dart`: **11 passed**, including dashboard/calendar/report stale 200/401, same-session reload, old-server/offline/versioned/mixed-legacy counts and real Home widget unknown versus zero.
- The preceding broader run on the same production Flutter sources passed **27 tests**: its then-eight aggregate cases plus **19 surrounding** reconciliation/sync/submit/account/history-presenter regressions. Chronology includes an older protected acknowledged record with a newer server record.
- Offline pinned Gradle/JDK17 full backend suite: **35 passed**, zero failures/errors/skips; real Jackson/service with mocked repositories. Dashboard tests include planned3/actual1, valid native zero, empty day, mixed legacy unknown, saved rows, corrupt envelope and JSON marker.
- `flutter analyze --no-pub lib test`: no issues. `git diff --check`: passed.

## Limits

These are local synthetic HTTP adapters and JVM repository mocks, not deployed API/database or phone execution. The new response marker is additive; old clients can still parse its nullable count according to their own behavior. Server recent-workout DTO `sets` remains a planned field; the active Flutter home history uses the separate actual-evidence presenter. No posture quality, warning thresholds, model/default activation, or live records were changed. Actual local PostgreSQL/HTTP verification is a separate next task.
