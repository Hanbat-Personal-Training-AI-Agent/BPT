# Workout result attribution — 2026-11-04

The result and share screen now uses recorded sets rather than allocating total repetitions across the planned set count. Real set counts, repetitions, entered weights and warning-event counts remain available; missing distribution, weight or recording information is shown as unavailable. Genuine legacy set details and recording references survive storage and reopening.

Base: `58e36ec`, isolated branch `fix/coaching-evidence-semantics-20261104`. This is a Dart result/persistence correction. No native evaluator, model, threshold, default, phone, window, deployment or integration-branch operation was performed.

## Existing correctness protections were already present

The previous [workout evidence correction](workout_evidence_semantics_20261030.md) was verified rather than repeated. Native completion writes `correctReps: 0`, `incorrectReps: 0`, a null posture score and a `workoutEvidence` envelope with `formAssessment: not_available`. `WorkoutRecordModel.accuracy` and `assessedPostureScore` remain null. Legacy raw counters and scores are retained for compatibility, not interpreted as certified form.

The native bridge delivers `{key, n, scope}`. Dart's per-rep warning handler counts delivered events; multiple warnings can occur on one repetition. Set-scope summaries update another count map. Neither count is a number of bad or good repetitions. These native event rules and counters are unchanged.

## Concrete defects corrected

- When set data were absent, `_buildSetRecords` divided total repetitions across `targetSets`. The statistics also used planned sets as completed sets. The same fabricated rows appeared in the shared screenshot.
- Missing weights fell back to an exercise demo weight, which could be displayed and saved as a real record. Missing and explicitly entered zero could not reliably remain distinct.
- The result replay substituted a remote sample video and a duration calculated from repetition count when a recording was absent.
- `WorkoutRecordModel.fromDto` discarded `setsDetail`; local JSON, `toDto`, and Home/Calendar navigation could therefore lose genuine mixed-set records and recording references.

## Current data flow

| Stage | Behavior |
| --- | --- |
| Native result | Existing validated envelope remains authoritative for actual sets and scoped warning counts. |
| Result interpretation | `WorkoutResultEvidence` accepts recorded lists, validates identity/counts, retains partial rows, and distinguishes complete breakdown from unknown distribution. Goals never fill missing rows. |
| Save / DTO | Actual set data are retained. `toJson` remains the lightweight API body; local presence flags and recording references use `toStorageJson`. No recording path or URL was added to network serialization. |
| Local queue / model | Set data, media references, `weightRecorded`, and `setsDetailValid` survive serialization and ID-renumber copies. Malformed lists cannot become valid merely through numeric normalization. |
| Same-record GET | Existing account/client/server identity guards remain. Omitted local metadata is preserved; explicit replacements are respected. Unmarked zero echoes do not turn known missing weights into observations. An equivalent normalized/reordered echo cannot validate a locally invalid list. |
| Home / Calendar | Both use `resultEvidenceFields` to reopen actual metadata rather than only aggregate values. |
| View / share | Known total reps remain visible. Missing completed sets or set volume are `—`; missing breakdown and warning evidence are stated explicitly. The shared screenshot uses that same view. |

Set identity accepts the native one-based `setIndex` and the stored `setNumber`; conflicting aliases or duplicate explicit IDs invalidate attribution. Equal-valued sets with distinct identities remain separate records. Native-envelope media attach by set identity, repetitions and known weight, so reordered equal-shaped sets cannot swap recordings. Explicit local or remote recording references are retained; a missing local file never causes a sample video substitution. Duration is displayed only from an initialized real player.

Known zero weight is valid, including bodyweight exercise. An old unmarked zero may be a historical missing-value placeholder, so old-cache/remote-only zero is not promoted to a measured value. New local explicit zero and native-envelope zero retain their known status. Raw legacy numeric fields remain unchanged, including the compatibility wire fallback; those fallbacks are not adopted as observed set count or volume. Unversioned `totalVolume` is not sufficient to prove actual per-set volume.

## Verification

**All 51 Dart test files passed: 282 tests passed, 8 conditional tests skipped, no failures.** The explicit private-artifact consumer test ran with the existing hash-bound local HTTP response and original/rescored reports; it made **zero network attempts**. No synthetic replacement or new API/inference run was used. Targeted analysis of the changed sources/tests reports **No issues found**.

There are 12 new result-attribution tests and seven repository scenarios. They cover:

- legacy total/goal records without a set breakdown, including the content inside the shared screenshot;
- explicit zero versus absent weights through DTO, queue, model and reopening;
- genuine mixed sets and actual local/remote media surviving roundtrips;
- warning events exceeding repetition count, and set-scope counts not being allocated to repetitions;
- partial, malformed, fractional, duplicate-ID and conflicting-alias lists remaining untrusted, including normalized server echoes;
- omitted, changed and explicitly cleared metadata; no attachment across conflicting record identity;
- missing recordings remaining unavailable and no invented duration.

The initial unrestricted suite invocation lacked the environment required by an existing host-only private-artifact test. Its failure log was preserved; the final complete run supplied the existing verified artifacts and passed that test. Earlier expected-assertion failures from implementation are also retained. Dependencies were resolved from the offline cache; no lockfile or native build changes were made.

Durable logs and the hash receipt are under `~/bpt-data/completion-20261104-private/workout-result-attribution/`. [Machine-readable receipt](workout_result_attribution_20261104.json) records source and log hashes.

These checks establish attribution and persistence behavior. They do not establish expert posture accuracy, a false-negative rate, phone visual/playback behavior, or deployed backend semantics. Historical unversioned data cannot retroactively acquire observation provenance.
