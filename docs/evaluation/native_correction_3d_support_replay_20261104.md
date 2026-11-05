# 3D source-support correction-praise replay — 2026-11-04

The corrected native runtime **17fa75292fe77393c59df87076e9e606853e7980** passed a new replay of all three original local videos against frozen runtime **94a72a5ffae86011a87af93eb246eb8a7a58f4fe**. This verifies the later [3D source-support correction](native_correction_3d_support_20261104.md) and remains separate from the [intermediate 03aa9d0 replay](native_correction_praise_replay_20261104.md). See the [machine summary](native_correction_3d_support_replay_20261104.json).

| Video | Source frames | Native reps | Wall time |
| --- | ---: | ---: | ---: |
| Squat | 1,267 | 10 | 30.71 s |
| Barbell row | 590 | 10 | 14.45 s |
| Push-up | 551 | 10 | 15.29 s |

Comparison used exact equality and zero numeric tolerance. All 30 rep boundaries, sources, sides, grades, warning lists and delivery snapshots matched; all 60 separate 2D/3D metric dictionaries matched. All 2,408 frame status rows, transitions and events matched. All six legacy CSV files were byte-identical, including the raw/constrained 3D arrays and existing four-decimal quantization. Only measured JSON runtime timing fields were excluded; all other existing JSON fields matched.

Squat retained two hips-first, five knee-valgus and three no-lockout warning reps. Row retained no warning; push-up retained one no-lockout warning rep. The three row and two push-up generic praise events remained at the exact same frames. Neither runtime emitted `praise_fixed` in these clips. The replay therefore checks unchanged behavior on these specific videos; the targeted native regressions cover correction withholding with missing source support. This has no independent ground truth and makes no accuracy claim.

The release executable SHA256 is `c764700aead732d7a1f7255a75eaaccd22fad2526ce7c3f758d8b4d1eb7e02bb`. A fresh build manifest binds the approved commit and 28 build source files; their hashes remained stable after execution. All 87 tracked input, model and original baseline files had identical before/after hashes. The original video hashes and full RTMPose-m Halpe26/XS model bundle digests also matched the frozen original trace bindings.

The CLI used the original options and paths with only the executable and output directories replaced, and fault-trace/fault-binding arguments omitted. Lookahead 5, cadence 1, constraints on, adaptive off, wrist anchor off, form source 3D, ready-pose off, crop input and crop-edge refit on were retained. This ordinary CLI regression produced no new source-bound fault trace and did not relabel earlier evidence. Timings cover the complete Mac CLI process, not phone performance.

Fresh artifacts are under `~/bpt-data/native-fault-evidence-20261104-private/run-17fa752-praise-regression/`: exact commands, logs, execution receipts, legacy outputs, source/executable manifest, durable executable, before/after hashes, comparison and provenance receipts. Both the frozen original and intermediate replay remain untouched. Scripts in the sibling `praise-regression-tools/` directory reproduce the execution, exact comparison and provenance checks. Work used two build jobs and the shared heavy-work lock, with no UI, phone, signing, network, new model, training or deployment.
