# Source-bound headless replay validation — 2026-11-04

The actual runtime candidate is **94a72a5ffae86011a87af93eb246eb8a7a58f4fe**, executable SHA256 `75c81e36070400a5015400fa1f641c25e5bb1d89ecb750fe9f31667173c9015e`. Later documentation commits do not relabel this run. The machine summary is [native_fault_cli_validation_20261104.json](native_fault_cli_validation_20261104.json).

The combined source passed 337 Swift tests (4 skipped, 0 failures), all 7 focused CLI checks, and a cached iOS typecheck of all 65 current Runner Swift sources. The first typecheck attempt failed because an isolated worktree lacks the generated plugin header; retaining the existing cached generated-header include path resolved that tooling issue. Both attempts and the passing receipts remain preserved. No signed app build, phone operation, UI, cloud inference, or training occurred.

The three original videos were each processed once by the existing RTMPose-m Halpe26 and XS bundles, explicitly addressed in the worktree. Full bundle hashes, the compiled executable, actual source files, and original video bytes were bound before execution. Source and model hashes matched after execution; each closed trace has a checksum receipt. No input or model was replaced. The push-up video's bytes differ from the older capture catalog and identify a new source; its filename is not evidence of a historical match.

| Exercise | Source frames | XS inferences | Native reps | Process wall time |
| --- | ---: | ---: | ---: | ---: |
| Squat | 1,267 | 1,246 | 10 | 30.36 s |
| Barbell row | 590 | 569 | 10 | 14.73 s |
| Push-up | 551 | 526 | 10 | 15.23 s |

Timing includes CoreML compilation/loading, video decoding, 2D/3D inference, native evaluation, and output writes on this Mac. It is not an iPhone frame-rate measurement. Options were lookahead 5, cadence 1, constraints on, adaptive and wrist anchoring off, 3D form source required, ready-pose off, person crop and crop-edge refit on. Other thresholds retained their existing defaults. Lookahead 5 is the existing delayed path, not a zero-future timing claim. The legacy CLI enables all feedback keys; this does not describe phone delivery defaults.

Every trace accounts for its full declared source manifest with zero failed, missing, duplicate, or mismatched sources. Each contains five explicitly marked flush frames. Actual CMSampleBuffer timestamps use both timescales 1000 and 15360 (the initial zero timestamp uses 1000). The exact per-sample numerators, denominators, flags, epochs, and source indices are preserved; FPS and container metadata were not used to manufacture a clock.

Squat native outputs included `squat_hips_first` on 2 reps, `squat_knee_valgus` on 5, and `squat_no_lockout` on 3. Row emitted no warning. Push-up emitted `pushup_no_lockout` on 1 rep. These are recorded native behaviors, not correctness or accuracy results. Push-up states included 16 partial-3D and 4 tracking-lost frames; its 21 warm-up frames, like the other clips' 21 warm-up frames, are explicit rather than promoted to full 3D support.

The preserved legacy outputs contain all 26 keypoint columns, separate raw and constrained 17-joint XYZ arrays, contiguous frame indices, and one row per source frame. Their existing four-decimal CSV formatting is quantized; this is structural preservation, not lossless full-float archival. Trace evidence remains the precise native operands and source clock recorded during judging. Source-bound arrays and missing-value masks must not be inferred from a warning list.

Private artifacts remain under `~/bpt-data/native-fault-evidence-20261104-private/`: `cli-verification/` holds source/binary freeze manifests, commands, checks, suite/typecheck logs and receipts; `run-94a72a5/` holds per-clip original commands, bindings, JSONL traces, checksum receipts, untouched legacy JSON/CSVs, execution logs, `summary.json`, and the original `export-bundle.json`. A mode-preserving durable executable copy in `artifacts/pose-replay` has the same frozen SHA256; `durable-export-bundle.json` points to that copy, leaving the original execution bundle unchanged. These are new unbound development captures. Export must create a new trace-derived task/boundary manifest with unknown human labels and apply the strict exporter; no old task or historical capture is retrofilled.
