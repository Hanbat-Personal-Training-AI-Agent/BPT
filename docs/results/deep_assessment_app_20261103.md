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

## Follow-up: retired capture protection

Final review identified a stale-packet gap after the new source was accepted: a delayed old capture could replace it because source counters were checked only within the current capture. The exact native packet replay now checks old packets **after** accepting the new source, including a higher old epoch/index. The regression first failed (`expected false`, `actual true`). The inbox now retires previous capture IDs on an accepted source transition, preserves current-source updates and legitimate distinct new captures, and rejects delayed packets from retired captures. Clear semantics and the channel generation guard are unchanged.

Focused follow-up: **4 tests passed**, analyzer **no issues**. No whole-stack suite was repeated. The native fixture remains byte-identical. `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/retired-capture-test-receipt.json` records matching source hashes taken immediately before and after those checks. This receipt is stronger than the retrospective snapshots for the earlier report runs; the distinction is intentional.

## Receipts and scope

Private final snapshot receipt: `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/final-source-snapshot.json`. These final snapshot hashes were captured **after** testing. The earlier report runs have no before/after-test source hash receipt and must not be described as independently bound to exact tested source bytes. The follow-up inbox test/analyzer does have its separate matching before/after receipt. Logs and the emitted widget proof document the completed executions; the final nine-test report run followed the post-batch wording correction. The subsequent inbox retirement change was checked by the focused four-test run.

| Final source path | SHA-256 |
|---|---|
| `lib/features/workout/data/deep_assessment_evidence.dart` | `7db6f586c5bded1ba04e3ed5f3f3d90b9de5b2a5d7c7f1b5476afaa13e61d4b1` |
| `lib/features/workout/screens/deep_analysis_report_screen.dart` | `d2b6e0bc8d77d7fdc93d6238319c839c29054204cd1e4adff4e3808ac1cf8046` |
| `lib/features/workout/data/experimental_coaching_candidate.dart` | `078ad5ef67318a1cd81126ea5bd4a8973a3859b905965187fff7afb792db6791` |
| `test/deep_assessment_evidence_test.dart` | `d1168e3d45fa208406664139f2a3ac7794471b607ab6113cd0e7c7a3d0c6db49` |
| `test/local_deep_http_response_test.dart` | `88788bc43bbdcff2e20bf071609cb7793a7d461435dfd9850865c67dbdb6c9bf` |
| `test/features/workout/experimental_coaching_candidate_test.dart` | `f53dce1d39fc0b112fdef502d71883ccc98f4a456a305b8845f60c26622a4e04` |
| `test/fixtures/native_source_transition_20261103.json` | `d81af335d40b12df6cf03cb12eb2677a7ffc070bd36d68c03e054c50235faa0c` |

| Saved test/proof artifact | SHA-256 |
|---|---|
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/full-45-tests.log` | `7c6e5b9102552ae6c2760f3524f01519bd7a5b503e9c82924a58dec8df5bda5a` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/final-9-tests.log` | `f845451c79a4ce11b576ab5f43538a23367e3cbfad97de2e07fbd7faf6b38f1c` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/analyze.log` | `8e13ce38fc3a5de167c7c71dbeb2ad54ca87c4a685af1d01de8c37477c44d129` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/flutter-widget-proof.json` | `40573d23161d85e2df50af830465bab3f69504fb9adec4a1696c20d7958c9b29` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/retired-capture-reproduced-failure.log` | `ce917fde056fe995052b249ef00ba06decb4fc3983bcc767f7207eae9a5b48b5` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/retired-capture-tests.log` | `ea36e2fe55093579b310fa9c3382fbecd3bac84ba6c130f9c363f5659fd0c144` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/retired-capture-analyze.log` | `590807ac9f73713a7cde89a364411090262b446c9cc58b4a936d6a94b7571fde` |
| `/Users/6_month/bpt-data/deep-assessment-app-20261103-private/retired-capture-test-receipt.json` | `d55779dcc710c327bf6b5f5fd6ff538050cd3ef122742d3622ab56d6a43c3514` |

The widget proof binds the genuine HTTP response SHA-256 `0127fe07e8818a4d9fe193fe1ecb0f19d6a00c1a0af5d202948bea0452c026bd`, current re-score `1d713aad203739b413575c844c258a7d9e96d882f4bcd8853a70845c26326b67`, and immutable original worker `f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa`. This verifies host parsing/rendering, not phone capture, video playback, TLS/authentication, new inference, model accuracy, or validated coaching thresholds.
