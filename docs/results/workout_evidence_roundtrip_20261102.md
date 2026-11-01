# workoutEvidence roundtrip — 2026-11-02

Base `6734902`, isolated `fix/workout-evidence-roundtrip-20261102`; no main/frozen-app/backend deployment changes.

Read-only correction: the backend tracked in this candidate already exposes `poseMetricsSummary` (from `74e8cbc`). The older MAIN backend inspected Oct30 did not. This patch fixes the candidate's unsafe Object/string fallback and missing structural validation; it does not claim a deployed response was changed.

- Response metadata is now a JSON object or null. Corrupt/scalar/array stored JSON returns unknown; stored historical bytes and raw legacy correctness values are unchanged.
- New `workoutEvidence` v1 writes must match completed rep/set/event totals, source/scope/version, explicit unassessed null fields and 0/0 legacy placeholders. Contradictions/unsupported versions return INVALID_INPUT_VALUE before persistence. Events may exceed reps, and separate feedbackCounts scopes need not sum to rep events. Legacy summaries without this envelope remain opaque objects, not validated form evidence.
- v1 completed0 and missing rep goal no longer inflate to planned reps/sets or an invented target. Goal attainment is rep completion, not form accuracy. Legacy fallback semantics remain unchanged.
- Flutter safely ignores non-object/invalid/unsupported metadata instead of casting crashes. It interprets v1 set data only when structure/counts match the completion context. DTO/cache/queue/history preserve the valid object; accuracy and assessed posture score stay unknown.

## Local evidence

A shared synthetic request lives in `test/fixtures/workout_evidence_v1_request.json`. The JVM test executes the real WorkoutService/entity/response/ObjectMapper path with disposable mocked repositories (not a live DB), then writes its actual JSON response to `backend/build/contract-fixtures/workout-evidence-v1-response.json`. Flutter consumes that generated response through DTO/model and a fresh-cache read-only history widget. The sample has1 completed rep,4 delivered warning events, distinct key totals and unknown correctness: the UI shows10% rep-goal completion,4 recorded warnings and overall-form unassessed, without local metadata fallback.

- Full backend: **26 JUnit tests passed** (7 new contract tests, including12 rejection mutations;19 existing). Covers legacy preservation, explicit zero/no goal, malformed stored metadata, user-scoped query and same-ID cross-owner save refusal.
- Relevant Flutter contracts/widgets/account regressions: **21 tests passed, no skips**, including the actual JVM-response test and existing A→B late-response/reused-ID protections.
- `flutter analyze --no-pub lib test`: no issues. `git diff --check`: passed.
- Existing JDK17/cached Gradle8.14 used. Missing pinned SpringBoot/build dependencies were restored without version changes; final backend run passed offline. Flutter dependencies restored offline. No model/Pods/audio assets downloaded.

Reproduce from this worktree: run Gradle8.14 `-p backend --offline --no-daemon test`, then:

```sh
flutter test --no-pub \
  --dart-define=BPT_BACKEND_CONTRACT_RESPONSE=backend/build/contract-fixtures/workout-evidence-v1-response.json \
  test/workout_evidence_backend_contract_test.dart
```

Without that define, only the JVM-generated-response widget test is explicitly skipped; its shared-fixture/parser tests still run. The21-test result above supplied the define. No real media/personal data is in these fixtures.

No deployed HTTP writes or reads, user history mutation, DB migration, install, merge or default activation occurred. Live API/auth/DB integration and expert posture accuracy remain unverified. This completes the local client/server metadata contract, not the full project or clinical/expert validation. Next independent task: transport/session-guard blocker, then annotation-ready expert-label evaluation CLI/protocol; GT-angle proxies will not be copied into expert labels.

## Reviewer follow-up: actual volume and planned/actual sets

Native v1 alone now derives persisted set rows, completed set count, representative max kg and volume from the validated actual evidence sets. Stale DTO weight/volume/setsDetail cannot override them. Planned targetSets remains separate; native partial-exit payload preserves widget.targetSets, and no goals gives an unknown goal flag. The generic backend goal flag requires every provided positive rep/set goal; the UI completion percentage remains explicitly rep-goal completion, not form quality. Legacy calculation/storage behavior is unchanged.

The existing integer volume wire field rounds the **final kg×rep sum once** (nonnegative half-up), not each set:2.5+7.5→10;2.5+5×5=27.5→wire28. Original set weights/reps remain available; result UI preserves2.5kg and displays27.5 volume. This integer field is an approximation for fractional totals, not an exact decimal volume or posture score. No schema migration was made.

Home/calendar use a shared presenter: valid actual1/planned3/12reps shows1set and12total, never3×4. Mixed reps are never averaged into an invented equal-set history; legacy unknown actual sets show total reps and the goal separately. Empty v1 sets remain actual0. New tests cover nonzero weight with zero reps, planned3/actual1, stale negative volume/details, mixed fractional weights, final-sum rounding, fractional UI, actual partial-exit route payload and both history consumers.

Final follow-up validation: **29 backend JUnit tests and26 relevant Flutter tests pass**, including a freshly regenerated JVM response read by Flutter. Repository persistence remains mocked in these JVM tests; this is not actual DB/HTTP verification. Broad `flutter analyze --no-pub lib test`: no issues; `git diff --check`: passed. Current transport/session-retry races are a separate prioritized fix, not claimed solved here; expert-label tooling follows those blockers.
