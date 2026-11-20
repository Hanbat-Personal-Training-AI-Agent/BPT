# Numeric support-corridor replay, 2026-10-26

This is a metadata-only behavior/coverage report, not pose accuracy or device success. The automatic live-camera/contact solution remains unimplemented. No RGB, GT labels, future contact labels, model loading, training or device access was used.

The available-evidence variant supplies unknown camera/contact and therefore acquires no anchor. The asserted variant supplies fixed camera and support for the entire clip solely as a harness condition; it is not detected or GT-selected contact. Both use the same causal keypoint evidence proxy and unchanged core. Native also requires readiness eligibility, an explicit contact source interval and exact crop-change resets; those are not faithfully replayable because these logs do not contain crop/tracker IDs or full readiness provenance. Asserted results must not be counted as deployable gains.

| Log suffix | Judged | Available hidden / inferred | Asserted hidden / inferred | Asserted inferred episodes / expiries | Passed observed wrists | Max correction px |
|---|---:|---:|---:|---:|---:|---:|
| r0_pushup_0003_cam1 | 520 | 486 / 0 | 434 / 52 | 7 / 4 | 554 | 10.87 |
| r0_pushup_0003_cam2 | 545 | 160 / 0 | 69 / 91 | 10 / 9 | 930 | 59.06 |
| r90_pushup_0003_cam1 | 540 | 494 / 0 | 447 / 47 | 6 / 4 | 586 | 11.19 |
| r270_pushup_0003_cam1 | 537 | 492 / 0 | 445 / 47 | 6 / 4 | 582 | 11.19 |

Counts are wrist samples (two per judged frame), not independently verified occlusions. Every eligible observed wrist passed with exactly unchanged x/y coordinates in both variants; assertions in the harness check this. No inferred arm was assessment-eligible. Maximum inferred age was 0.33334s (configured cap .35s); expiry hides rather than returning uncertain raw. Corrections are raw-to-display distances, not localization error.

The r0 cam1 sequence had a 146.52px maximum raw wrist step. A reconstruction of the existing One-Euro overlay from judged raw points/arrival times had mean wrist correction 1.196px. The r0 cam2 sequence had a 287.40px maximum raw step and reconstructed overlay mean correction 2.299px. Actual display coordinates and all immediate 2D frames were not logged; accepted MediaPipe source selection and missing display samples make this an incomplete reconstruction of current UI behavior. Guard maximum visible steps are recorded in JSON but exclude intervals where a wrist was hidden, so lower values are not a comparable accuracy/smoothness win.

The nominally clean r0 cam2 still loses 160/1090 wrist samples in the available-evidence proxy (69/1090 even with asserted conditions). The deliberately conservative .7 raw-score/evidence gate has a substantial coverage cost and is uncalibrated. These proxies cannot distinguish mistaken high-score detections from actual visible bad posture or genuine hidden motion. No claim that the original user issue is solved follows from bounded coordinates or reduced visible jumps.

The full JSON includes reason episodes, reset counts, corrections, source-timed hold ages and reconstructed baseline summaries. r90/r270 cam2 logs were absent; only the four named files were used. Their log SHA-256 values:

- `run_d26_xs_r0_pushup_0003_cam1.jsonl`: `3952f994dfdf021f413675a940e0373e2ffd32067f2ee1ee2b3b5d1a024facba`
- `run_d26_xs_r0_pushup_0003_cam2.jsonl`: `9e9e6e729d320322cf729039fe60146a23f176f1469bc9e529073ba105c77305`
- `run_d26_xs_r90_pushup_0003_cam1.jsonl`: `7ab7466fbd2a1431fd90cba15e90ee5bd88cbb67825fbcd9c199644866f8386f`
- `run_d26_xs_r270_pushup_0003_cam1.jsonl`: `833e06c9c369a38b7b761bf7c1de5bbfb02c21c2f18b38460e15641cb7b8a007`

Reproduce (output path is explicit; input logs are read-only):

```sh
BPT_SUPPORT_NUMERIC_LOG_DIR=/path/to/runs_xs \
BPT_SUPPORT_NUMERIC_REPORT="$PWD/docs/results/pushup_support_corridor_numeric_20261026.json" \
swift test --package-path ios/CalibrationEngineKit --filter 'PushUpSupport(Corridor|Evidence|NumericReplay).*Tests'
```

Final CPU validation: 28 selected tests passed, including 16 pure-core regressions, 11 adapter/display/assessment/control regressions and the four-log metadata replay. Camera/renderer Swift syntax parse, project plist lint and git diff whitespace checks passed. No Xcode build, native runtime check, device benchmark or deployment occurred.
