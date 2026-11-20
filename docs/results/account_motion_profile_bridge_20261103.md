# Account-bound calibration → motion observer bridge — 2026-11-03

This opt-in bridge reuses the original validated SMPL result and anatomical bone segments from `CalibrationResultStore.load()`. It never uses the averaged display-only `bodyProfileFrom()` values. Applying a profile means **the logged-in account's saved calibration is assumed to belong to the person doing the live workout**; it is not biometric identity verification or a statement that the calibrated posture was correct.

## Independent opt-ins and explicit per-profile policy

Both gates must be enabled:

- Dart build: `--dart-define=BPT_MOTION_OBSERVER_ACCOUNT_PROFILE=true`.
- Native `DemoConfig`: `BPT_MOTION_OBSERVER_ACCOUNT_PROFILE=1`, plus a selected `BPT_MOTION_OBSERVER` variant.

The Dart build also requires `BPT_MOTION_PROFILE_JOB_ID` to exactly match the saved calibration job, `BPT_MOTION_PROFILE_WEIGHT` in `(0,1]`, and nonempty `BPT_MOTION_PROFILE_WEIGHT_SOURCE`. These declare an engineering weight for that particular profile. There is no default strength and no conversion from reprojection pixels/height error to an accuracy probability. Missing declarations withhold the profile. Ordinary app defaults and PT output remain unchanged.

The stored result must carry schema 1, explicit `stub:false`, `smpl_neutral_v1.1.0`, ten finite beta values, cm/H36M/rest anatomical segments and finite quality evidence. The store now preserves explicit false provenance rather than dropping it. Legacy missing-stub records remain unknown; they are not upgraded. Unknown provenance, quality, job association or bone definitions are withheld. Native independently validates types and excludes all `appDefinitionDiffers` segments, width/display-only fields and unsupported edges before converting lengths to thigh-plus-shank ratios.

## Ownership, async and lifecycle

Each native view receives an opaque binding token before loading. The Dart path checks the captured authenticated store/lease after each await; a different account, a new session for the same account, a replaced view, an ended set or a disposed bridge cannot commit stale data. A delayed start acknowledgment retains its original store, view generation, set and boundary ticket. The native binding is single-use and rejects stale packets independently.

An immutable profile snapshot travels with its own source frame through L5. Account/session changes, background, set boundaries and tracker/reset changes clear it. Foreground rebind waits for a genuine new native update under the same current authenticated lease. Tracker/person changes intentionally remain withheld until a new set or explicit owner binding. Recorded-video input is always rejected before loading/applying current-account calibration.

The profile affects only observer candidates; original XS, current constraints, assessment coordinates, warning/rep results, display and speech do not consume it. Diagnostics distinguish a **bound** profile from a variant that uses it, and retain calibration job, declared weight/source and finite-safe quality evidence. A/B/C/D/F/HOLD binding is not reported as a kinematic calibration application.

## Available real artifacts and validation boundary

No eligible current-account calibration result was found in the preserved test-app preferences. Preserved calibration upload folders contain manifests/receipts, not a complete result. The actual legacy RGB-SMPL files `device-finish-20261026/ex3d_targets/P1.json`, `P2.json`, and `P3.json` contain bone metadata but lack current-account ownership, job ID, schema/non-stub evidence, beta and quality; the negative fixture check rejects them without manufacturing an envelope or association. Successful ownership/application tests use explicitly synthetic metadata.

Headless validation and source hashes are recorded at `/Users/6_month/bpt-runs/motion-profile-adapter-20261103/final-checks.json`. This is not a phone runtime test, new calibration, model inference, accuracy gain or production profile activation. The frozen phone branch was not changed.

## Completed checks

- Default-feature Flutter suite: **267 passed, four setup-feature tests skipped**. Existing private HTTP/JVM/native artifacts were explicitly supplied; no backend was contacted.
- Account-profile + setup enabled targeted Flutter suite: **35 passed, no skips**, including stale async A→B/A→A rejection, delayed start completion after end/replacement/account change, actual legacy metadata rejection and existing workout behavior.
- Focused Swift suite: **28 passed**, including the archived 720-checkpoint parity and current-pose/constraint preservation plus strict native profile validation and source-bound application tests.
- Flutter analyzer: no issues. Whole current Runner iOS arm64 typecheck: passed against cached iPhoneOS 27.1 frameworks; existing sendability and deprecation warnings remain. This is not a link/install/device result.
- All final checks have matching before/after source hashes; the three actual legacy metadata files are byte-unchanged. Commands, source hashes and log hashes are in the private receipt above.

The subsequent [final v5 iPhone build and six tests](current_phone_validation_20261103.md) include this code with account-profile gates OFF. They verify integration and the unchanged default path, not application of an actual current-account calibration. The original phone app and data were restored afterward.
