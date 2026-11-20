# Opt-in terminal evidence and geometry replay — 2026-11-02

Base `8006baf`, isolated `feat/terminal-evidence-optin-20261103` worktree. This makes future same-capture raw geometry comparisons possible. It does **not** fix A7 repetition timing or demonstrate accuracy improvement. Native thresholds, counts, original reports, assessor inputs, defaults, models and deployment remain unchanged. No phone install, camera capture, new model inference or media viewing occurred.

## Existing paths reused

The handoff name WorkoutDebugLog resolves in this source to `VideoRunLog`, with separate `DemoPoseLog` and `WorkoutFormLog`. The new `BPT_TERMINAL_EVIDENCE=1` launch/config flag is OFF when absent and uses the existing VideoRunLog directory/file ownership, delivery-to-source index mapping and write entry point. It enables a numeric-only versioned mode rather than a second parallel camera/logger. Legacy video logging and `scripts/replay_experimental_coaching.swift` remain unchanged when the flag is absent. New strict replay never interprets legacy `arrival_host` as source time or substitutes corrected geometry for absent raw geometry. Do not also enable the separate legacy pose log if duplicate diagnostic output is unwanted.

The new pure Foundation `TerminalEvidenceStream` handles bounded encoding/write admission for that existing logger; it is compiled by both the explicit Xcode Sources list and the package symlink. It is not a second perception, judgement or media pipeline.

## Versioned capture contract

`bpt.terminal-evidence.v1` records header → set start → frames/original rep reports → end, with a contiguous **record sequence** distinct from camera source gaps. Each frame carries its original sample CMTime value/timescale and seconds, pipeline frame index, actual video source index or processed camera capture index, analysis image dimensions/rotation and camera/mirror metadata. The timestamp travels in the same payload through the existing XS lookahead. No FPS-derived time or arrival clock replaces it.

Layers are explicit: untouched detector COCO17 x/y/score, XS input COCO17, actual assessment COCO17; unconstrained XS raw H36M17, constrained, optional adapted and actual masked/assessment H36M17. State, invalid-joint union, assessment H36M scores, phase, recorded side/session view, actual XS row/filled count, lookahead/cadence and input crop unit_px accompany them. Scores are finite native SimCC values, **not bounded probabilities**: values over1 or below0 are preserved. Raw2D is captured before wrist/anchor substitution. Null raw/mask/state/support are never silently replaced to make replay eligible.

3D units are **XS model space, with no guaranteed metric/world scale**. unit_px describes the input2D crop scale, not a3D meter conversion. The actual judgement-time up vector is recorded with an explicit unsynchronized-source-gravity limitation; it is not claimed to be a source-frame sensor snapshot. Header metadata includes bundled model hashes and explicit iOS live-camera/video-as-camera provenance. It includes no environment dump, file/media paths, tokens, subject/account/device identifiers, images or audio.

Original FormRepReport start/end/side are preserved verbatim. A read-only tracker getter records `active_rep_start` so a subsequent rep that begins but never finishes cannot be mistaken for previous terminal observation. This changes no tracker transitions or aggregation. Epoch leases apply **only to diagnostics**: pending old-set callbacks cannot be assigned to a new set, and a late old endSet cannot close the new diagnostic epoch. Existing assessor lifecycle behavior is not redesigned.

EndSet stops admitting new source payloads to the closing epoch, records the existing lookahead flush, then writes flush/incomplete status. Stop, superseded set or video end without set flush is explicitly incomplete. Both explicit set-end and implicit orientation/tracking-loss flush outputs carry diagnostic flush provenance; they cannot count as new follow-up sources. A clean set flush is capture status, **not** proof of completed anatomical extension. Open-rep state and later geometry coverage are separate.

## Bounded preservation and failure behavior

Files live under the existing `Documents/video_runs/terminal_<anonymous UUID>.jsonl` namespace. Existing evidence is never overwritten or automatically deleted. At3 existing terminal files a new log is refused with `capture_refused:file_limit; incomplete`; extracting/archiving files is a separate operator action. Each admitted file is bounded to6000 records,64MiB and64KiB per encoded row, with reserved space for an explicit `terminal_capped` incomplete marker. Encoding happens before enqueue, bounding pending bytes too.

Serialization failure stops further admissions; I/O failure stops later writes, including any completed footer. Strict replay therefore rejects a missing footer or broken JSON/sequence, rather than treating a camera drop as a lost log row or claiming complete data. No retry overwrites prior evidence. A process killed before footer is unsupported. The flag does not automatically upload or export anything.

## Strict offline comparison

```sh
python scripts/terminal_evidence/replay.py /local/terminal_capture.jsonl > /local/aggregate.json
python -m pytest scripts/terminal_evidence/tests -q
swift test --package-path ios/CalibrationEngineKit --jobs 2
```

The reader rejects legacy/mixed schemas/clocks, duplicate JSON keys, missing footers, malformed/bool/nonfinite numeric fields, inconsistent rational/seconds PTS, regressing/duplicate source indices/PTS, stale epochs, changed coordinate systems, missing raw/native layers, invalid masks and unavailable original boundary frames. Explicit cap/incomplete status is retained. Legitimate source gaps remain observable and are separate from record-sequence loss.

The fixed diagnostic takes at most15 distinct non-flush follow-up source observations before the next **actual begun** rep, including unfinished reps. Short/capped spans get no extended extrema; invalid samples invalidate the whole corresponding metric span, with no finite-subset extrema. Selected side is fixed to the original report side and the opposite side is also compared. Raw and assessment geometry are separate. Only aggregate input hash, counts, coverage and paired max-angle/range changes leave the local capture host.

These are geometrical extrema over the same recorded window. They do **not** reproduce all native2D requiredOK/view/reference/phase gates or final warnings. Comparison counts are geometry windows, not assessable or correct reps. Fifteen observations are a predeclared diagnostic horizon, not a terminal-completion criterion. No GT/top anchors, thresholds, automatic retiming or form-pass decision are introduced.

## Evidence feasibility and validation

The previously verified37 Home JSONL files contained27,318 judged records/364 rep aggregates but no raw per-frame3D. A bounded metadata inventory of the newer mixed-signing directory found18 logs; the first3 files' first200 records do contain `pose3d_final`. The separate `deda231` motion-detail source writes final3D, not original raw3D/source CMTime. These files cannot be promoted into this strict contract. Individual log/clip hashes remain private. No arrays, clips or models were copied from Home.

Mac PoseReplay already exposes raw/constrained CSV but differs from the current camera assessment/corridor path and lacks this complete source/epoch/disposal contract. The parallel inventory/replay task owns any future Mac-only diagnostic; it must identify its provenance separately and cannot be labelled device parity. Future actual native collection still requires a build containing this opt-in path, locally available licensed models, a connected device, explicit flag, original per-source samples/boundaries and complete recording evidence. The currently prepared frozen phone app was not modified.

- **28 Python tests passed**, including unfinished-next-rep, exact clock, schema/key/sequence rejection, source gaps vs missing records, no raw fallback, native scores outside0–1, fixed side/bilateral layers, short/flush/capped coverage and one-sample invalidity. The synthetic elbow90°→150° follow-up produces a60° max/range difference; that is a math/replay example, not an accuracy result.
- **221 Swift tests executed:218 passed,3 skipped,0 failed**. Eight new tests exercise epoch races, budgets, actual encoded sequence/cap, forced I/O/serialization failure with no false footer, strict JSON nulls, native angle definitions, the real unfinished tracker boundary and implicit lifter flush provenance. Existing raw/output parity tests remain included; existing model-dependent skips remain skips.
- **Actual unsigned iOS native compiler/link passed**, using a separate DD and APFS-cloned existing exact673 Pods products. This is explicitly a temporary **donor-matching dependency environment**, not a fresh app build from the original tracked lock. Original lock SHA79c96ff… was temporarily replaced by the actual cached manifest520ca391… (integration_test entry and Flutter podspec checksum differences), then restored with no tracked diff. No pod install/download occurred. A first compiler attempt exposed a file-private options reference; the final source removes that duplicate header access and compiles. Source hashes stayed fixed during the successful build.

The compile receipt is `terminal_evidence_compile_20261102.json`; private full logs, exact dependency diff and compiled-source hash manifest are under `~/bpt-runs/terminal-evidence-20261102/` and adjacent test logs. Protected donor outputs and frozen apps were not written. Phone capture/run and measured recording overhead are **UNRUN** because the device connection is unavailable. Synthetic tests and compilation do not establish capture performance, independent expert-labelled form accuracy, terminal completion or A7 resolution.
