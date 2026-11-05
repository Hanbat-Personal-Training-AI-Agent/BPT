# Partial geometry validity — 2026-11-02

This fixes availability and measurement integrity, not model accuracy. A finite collapsed chain on an unused side or outside a declared repetition previously rejected the whole job. The whole-pose zero/NaN rejection test did not require that behavior. Frozen Home20/Fit3D inputs, results, scores, rules, thresholds and model outputs remain untouched; no inference, training, media viewing or deployment occurred.

## Behavior

Malformed and globally nonfinite skeletons remain rejected, including a single NaN outside the repetition. Entirely unusable skeletons remain rejected. Finite zero-length chains instead invalidate their dependent measurements over the **entire declared repetition**. No bad sample is silently dropped to obtain finite extrema, ranges, means or standard deviations.

An unused opposite wrist outside the repetition leaves the full selected report unchanged. An opposite wrist inside it preserves selected angles/primary measures but withholds bilateral hand path and the affected symmetry. A used wrist withholds elbow and bilateral hand path while knee, hip, shoulder and torso remain usable. A corrupt primary chain withholds primary extrema, phase, ROM and tempo; independent joints retain min/max but have no substituted primary-selected top/bottom. A corrupted initial baseline withholds dependent later drift and set consistency, without poisoning unrelated metrics or later raw angles. The catalog baseline mean also refuses a finite subset. No withheld metric emits a fault or evaluated-key claim.

Strict JSON uses null for unavailable scalars and an empty unavailable hand path. Raw input joints and video coordinates remain unchanged. Video panels say judgement withheld rather than formatting NaN/null. Flutter renders unavailable values as `확인 불가`, distinguishes independently valid min/max from unavailable top/bottom phases, and disables missing/nonfinite evidence seeks. Valid evidence keeps its original seek time. Existing low-detection-support estimates retain their separate uncertainty wording.

## Validation

- Ten deterministic fully valid reports (five exercises × left/right, with detection/tracking support) match pre-change canonical JSON SHA256 **byte for byte**. The fixture records base `17583f3` and source hash, and includes complete report/support metadata in each digest.
- Ten focused Python tests cover span/side dependencies, invalid baseline propagation, strict JSON, renderer null handling, canonical parity and the exact scorer-produced Flutter fixture.
- Full Python suite: **158 passed, 3 skipped**, with existing Starlette deprecation and short synthetic JWT-key warnings. No dependency installation was needed.
- Flutter: **13 passed**, covering the two new partial-validity tests plus existing report/queue/navigation behavior. Targeted analyzer: no issues.
- Initial Flutter evidence test missed an offscreen button; allowing scroll animation to settle fixed the test harness. It then exercised both disabled and valid callbacks successfully.

`test/fixtures/deep_partial_primary.json` is a small deterministic synthetic report from the real scorer, with one collapsed primary lower-leg sample and no personal data, video or GT. A Python test regenerates and compares it structurally. It may also be rendered by the production report widget for an offline phone check.

Commands (from this worktree):

```sh
/opt/homebrew/Caskroom/miniconda/base/envs/bpt-eval/bin/python -m pytest server/calibration_modal/tests scripts/deep_analysis/tests -q
flutter test --no-pub test/deep_partial_validity_test.dart test/deep_analysis_test.dart
flutter analyze --no-pub lib/features/workout/screens/deep_analysis_report_screen.dart test/deep_partial_validity_test.dart test/deep_analysis_test.dart
```

This synthetic reliability validation does not establish expert-labelled form accuracy, improve the rejected native-joint/side ablations, or complete independent clinical/exercise validation. It introduces no defaults, backend selection, rules or deployment change.
