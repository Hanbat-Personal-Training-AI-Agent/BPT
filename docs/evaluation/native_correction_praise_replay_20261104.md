# Correction-praise video regression — 2026-11-04

The correction-praise runtime at **03aa9d0fe7f0175f79cc314bd7aaf5542badf0fe** passed fresh, headless replays of the three original local videos against frozen runtime **94a72a5ffae86011a87af93eb246eb8a7a58f4fe**. All comparisons used exact equality with zero numeric tolerance. See the [machine summary](native_correction_praise_replay_20261104.json), [native change and targeted regressions](native_correction_praise_20261104.md), and [original capture provenance](native_fault_cli_validation_20261104.md).

| Video | Source frames | Native reps | Wall time |
| --- | ---: | ---: | ---: |
| Squat | 1,267 | 10 | 32.70 s |
| Barbell row | 590 | 10 | 14.56 s |
| Push-up | 551 | 10 | 16.86 s |

All 30 rep boundaries, sources, selected sides, grades, raw and selected warning lists, delivery snapshots, and all 60 separate 2D/3D metric dictionaries were unchanged. All 2,408 status rows, transitions, and event lists matched. The six legacy keypoint/raw-and-constrained-3D CSV files were byte-identical, including their existing four-decimal quantization. JSON runtime timing fields were excluded from semantic equality because every process measured its own runtime; all other existing JSON fields matched.

Squat retained two hips-first, five knee-valgus, and three no-lockout warning reps; row retained no warnings; push-up retained one no-lockout warning rep. Row's three generic praise events and push-up's two generic praise events remained at exactly the same frames. Neither baseline nor candidate emitted `praise_fixed` on these videos, so these clips establish unchanged behavior for the preserved inputs, not coverage of the new correction-withholding branches. Those branches are covered by the native targeted regressions linked above. This is a behavioral regression check without independent ground truth or an accuracy claim.

The release CLI was built from the approved native commit with two build jobs and the shared heavy-work lock. Its SHA256 is `ad41becf25a5ba1253a4483bcc2a12c8375832b338e38a69cf9ddb5499f5eb93`. A fresh build manifest binds all 28 build source files; their hashes remained unchanged after replay. The existing RTMPose-m Halpe26 and MotionAGFormer XS model paths and the same three video paths were reused without copying/replacing model assets. Full model bundle digests and source-video hashes matched the original trace bindings. Before/after hashes of all 87 tracked input, model, and frozen baseline files were identical.

This run used the ordinary video CLI without fault-trace or fault-binding arguments. All other original inference and evaluator flags were retained: lookahead 5, cadence 1, constraints on, adaptive off, wrist anchor off, form source 3D, ready-pose off, person crop and crop-edge refit on. It does not create or relabel source-bound fault evidence. Runtime includes decoding, loading/compilation, inference, evaluation, and output writes on this Mac; it is not phone performance.

New artifacts are separate from the immutable original capture under `~/bpt-data/native-fault-evidence-20261104-private/run-03aa9d0-praise-regression/`: per-video exact command arrays, execution receipts, logs and legacy outputs; a new source/executable build manifest and durable executable; before/after input/model/baseline hashes; exact comparison and verification receipts. Reproduction helpers and their baseline self-check remain in the sibling `praise-regression-tools/` directory. No UI, phone, signing, network, model download, training, or deployment was used.
