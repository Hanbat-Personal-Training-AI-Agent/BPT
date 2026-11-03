# Deep assessment app integration — 2026-11-03

Code commits: `6958dbc` (report) and `c1dcf74` (native packet consumer). Root imports: `212b226`, `f0ab518`.

The actual `DeepAnalysisReport` now consumes typed `bpt.deep-assessment-evidence.v1` evidence. It checks exercise, frame rate, video time basis, repetition span/side, per-metric units and coordinate types, support agreement, duplicate identities and exact baseline repetition indices. Finite fractional millisecond bounds are preserved and matched exactly; rounding them to integers incorrectly rejected the recovered row report. Malformed or missing optional evidence stays unverified while unrelated valid observations remain visible.

Expanded repetition details explain estimation, partial support, anatomical angles versus shoulder/hand-path proxies, measurement definitions, actual baseline indices, and withheld posture/native-comparison judgments. Account/video lifecycle and seek guards remain unchanged.

## Completed headless checks

- Seven test files: **45 passed**. After the last comparison-wording correction, two report files: **9 passed**.
- Analyzer: **no issues** across the five changed Dart files. The analyzer run preceded the final wording-only correction.
- Hash-bound recovered worker re-score: 10 repetitions, 150 typed metrics; 141 available observations, 9 baseline-withheld measurements; all posture assessments withheld.
- Genuine saved local API response → production job parser → report widget: first repetition expanded at **390×844**, no overflow or null/NaN display, zero Dart URL requests. Video was a placeholder.
- Native Processor synthetic proposal → old-source clear → new-source proposal replay passed through the real Dart inbox. Stale old proposals/clears were rejected. Fixture bytes exactly match the native export; SHA-256 `d81af335d40b12df6cf03cb12eb2677a7ffc070bd36d68c03e054c50235faa0c`.

No app, browser, simulator, or phone UI was launched. An initial missing package-graph cache caused Flutter’s automatic crash diagnostic to inventory connected devices; no device operation was deliberately invoked. Cache recovery used file copies and subsequent commands used process-local CI/analytics/version-check flags.

## Receipts and scope

Private final snapshot receipt: `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/final-source-snapshot.json`. These source hashes were captured **after** testing. There was no before/after-test source hash receipt, so they must not be described as independent proof of the exact source bytes executing during a test. Logs and the emitted widget proof document the completed executions; the final nine-test run followed the sole post-batch wording correction.

| Final source path | SHA-256 |
|---|---|
| `lib/features/workout/data/deep_assessment_evidence.dart` | `7db6f586c5bded1ba04e3ed5f3f3d90b9de5b2a5d7c7f1b5476afaa13e61d4b1` |
| `lib/features/workout/screens/deep_analysis_report_screen.dart` | `d2b6e0bc8d77d7fdc93d6238319c839c29054204cd1e4adff4e3808ac1cf8046` |
| `test/deep_assessment_evidence_test.dart` | `d1168e3d45fa208406664139f2a3ac7794471b607ab6113cd0e7c7a3d0c6db49` |
| `test/local_deep_http_response_test.dart` | `88788bc43bbdcff2e20bf071609cb7793a7d461435dfd9850865c67dbdb6c9bf` |
| `test/features/workout/experimental_coaching_candidate_test.dart` | `01d62e4c089af28579ac10580619ee65108bbbe6a8973912bef58eb3cbbf2abd` |
| `test/fixtures/native_source_transition_20261103.json` | `d81af335d40b12df6cf03cb12eb2677a7ffc070bd36d68c03e054c50235faa0c` |

| Saved test/proof artifact | SHA-256 |
|---|---|
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/full-45-tests.log` | `7c6e5b9102552ae6c2760f3524f01519bd7a5b503e9c82924a58dec8df5bda5a` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/final-9-tests.log` | `f845451c79a4ce11b576ab5f43538a23367e3cbfad97de2e07fbd7faf6b38f1c` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/analyze.log` | `8e13ce38fc3a5de167c7c71dbeb2ad54ca87c4a685af1d01de8c37477c44d129` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/flutter-widget-proof.json` | `40573d23161d85e2df50af830465bab3f69504fb9adec4a1696c20d7958c9b29` |

The widget proof binds the genuine HTTP response SHA-256 `0127fe07e8818a4d9fe193fe1ecb0f19d6a00c1a0af5d202948bea0452c026bd`, current re-score `1d713aad203739b413575c844c258a7d9e96d882f4bcd8853a70845c26326b67`, and immutable original worker `f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa`. This verifies host parsing/rendering, not phone capture, video playback, TLS/authentication, new inference, model accuracy, or validated coaching thresholds.
