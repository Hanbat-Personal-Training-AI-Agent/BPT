# Actual localhost HTTP/PostgreSQL contract — 2026-11-02

This is distinct from the earlier Mockito repository/Jackson test. `WorkoutHttpPostgresContractTest` starts the candidate Spring application on **127.0.0.1, random HTTP port**, uses real security filters, password hashing, login/JWT, HTTP controllers, service transactions and PostgreSQL16.14. Only the root-owned disposable container `bpt-review-pg-20261102` (verified ID prefix `2cbb848a1d87`, owner label `project-completion-20261102`, localhost port51066/database `bpt_contract`) is eligible. No deployed endpoints or real accounts are used. Mail transport is mocked and verified unused; startup's five exercise seeds remain in that disposable DB.

## Guards and reproduction

The class is skipped unless `BPT_TEST_JDBC_URL` is explicitly set. Before constructing a datasource, it requires **exactly** `jdbc:postgresql://127.0.0.1:51066/bpt_contract` and the explicit synthetic `BPT_TEST_JDBC_USER` / `BPT_TEST_JDBC_PASSWORD` values documented in the test source. There is no application-default DB or credential fallback. The guarded context uses create/drop schema exclusively there. Never point this test at a user database. Container ownership/lifetime is managed by the parent review agent; the test does not create/stop containers.

Using JDK17 and the pinned cached Gradle8.14, run `gradle -p backend cleanTest test --tests '*WorkoutHttpPostgresContractTest' --offline --no-daemon` with those three explicit test environment values. `cleanTest` forces execution rather than reusing Gradle's prior environment-dependent test result. Unset all three and run the ordinary backend suite to verify default skip.

## Evidence

The final actual opt-in run executed **1 test, zero failures/errors/skips**. It verifies synthetic A/B login, A's native-v1 POST, a separate committed DB transaction with entity-manager clear and query, fresh GET metadata, one actual versus three planned sets, unknown form score/correctness placeholders, same-owner same-ID idempotent sync, empty B history, cross-owner same-ID403, malformed-v1 400 with no insert, versioned dashboard actual-set count, and legacy raw correctness1 with no manufactured envelope and a mixed-unknown dashboard. A deliberately different database URL is rejected by the guard before pool startup.

The real GET body is exported separately to `backend/build/contract-fixtures/workout-evidence-v1-postgres-response.json`. It keeps the shared synthetic fixture's reps1/targetReps10, volume5 and scoped warning-events4; clientID/date and planned targetSets3 differ. The existing Flutter fresh-cache/history contract accepts this shape via `--dart-define=BPT_BACKEND_CONTRACT_RESPONSE=backend/build/contract-fixtures/workout-evidence-v1-postgres-response.json`.

Final export rerun: **1 actual HTTP/PG test passed**, zero skips. Existing Flutter fresh-cache/history contract with that real GET artifact: **5 passed**, zero skips. Unset-environment ordinary JVM suite: **35 passed + 1 explicitly skipped PG test**, zero failures/errors. Wrong-DB-name negative run failed with the exact guard message before Hikari startup, as intended. `git diff --check` passed.

Witness GET SHA256: `130dab9f10e26e2bd6d70ea4c13c3bdb5df13a31be652228edcd481775ea2776`. This is a run witness, not a golden hash; generated server timestamps may change. Production-source base: `198686d`; this patch adds only the guarded test and this report.

## Limits

This verifies the candidate locally, not the deployed schema/API, production concurrency or iPhone behavior. No migrations, production data, deployment/default/model changes, or expert form-accuracy claim are included. The artifact contains synthetic IDs/numeric metadata only; build output is not committed.
