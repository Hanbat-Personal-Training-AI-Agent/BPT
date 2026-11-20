# Causal terminal-window candidate — 2026-11-02

Base `4eea822`. Independent opt-in experiment, OFF unless `BPT_TERMINAL_CANDIDATE=1`. It uses the existing numeric VideoRunLog stream and enables terminal evidence explicitly. MotionAGFormer-XS, native counts, original rep start/end, original reports, thresholds, feedback, models and normal defaults remain unchanged. Candidate reports are separate; no candidate warning/praise reaches the user.

## Implemented behavior

An original squat/pushup report opens a pending candidate after its existing endFrame. The actual end source frame anchors timing but is not a new follow-up observation. Flushed end frames cannot anchor. The read-only FormWarningTracker snapshot supplies actual side, phase, required2D, known per-frame side view and native assessment3D elbow/knee/hip values; raw model angles are separate diagnostics and never substitute for unavailable assessment. Existing masks/state and missing-dependent quantities therefore withhold the candidate even with high raw scores.

The candidate waits for causal top observations and a final continuous stable plateau. Stability is provisional: later real extension remains observable until actual next-rep begin, top phase exit or real set end. Next begin is checked before the new rep's geometry/support; clocks/deadlines are checked first so a delayed begin cannot bypass timeout. No future/GT frame, anchor, retiming or corrected coordinate is injected.

Untuned observation parameters are250ms stable duration, at least5 distinct sources, angular speed at most10°/s, source gap at most150ms, operational/source timeout1.5s and3 prior candidate-reference windows. These are experimental parameters, not accepted physiological thresholds or speed criteria. A normal long top pause or slow/stalled pipeline can be withheld. Source time and operational host watchdog time remain separate; captured host timing is replayed rather than replaced by replay execution speed.

Original maxima, all-followup assessment maxima, raw-followup maxima, all-top maxima and final plateau maxima have distinct names and are retained. The candidate compares only final plateau maxima with **earlier completed windows from this same candidate contract**, same side and coordinate context, using the existing native relative threshold (currently10°). Current/future samples cannot update a closed report. Initial reference shortage is withheld; covered measurements may seed later references. Tracking loss, implicit flush, coordinate reset or new set invalidate reference identity. No old truncated native set-max is reused.

A stable140° terminal window following three covered170° references preserves a30° relative-deficit candidate. Four consistently low140° windows produce only `relative_deficit_not_observed`, never correct-form/full-extension approval. A brief higher extension outside the last plateau remains in all-observation maxima; if it conflicts with the final plateau by more than the existing threshold, the result is ambiguous/withheld, rather than confidently bad. Short, interrupted, unknown-view, missing-support, invalid-chain, changed-side, duplicate/regressing clock, long-gap and timeout windows remain explicit withheld results.

## End and queue ownership

The existing production endSet/lifter flush/assessor/bridge callbacks keep their behavior. Only diagnostic finalization waits for the epoch's **already admitted payloads** to deliver or be abandoned. The collector tracks source frame identities admitted at processFrame entry, not a guessed frame count. The explicit video EOF fence additionally admits the last feeder-accepted frame still waiting on that processing queue; ordinary live endSet retains its original call-time admission boundary and does not request additional camera frames. Duplicate/stale delivery cannot release another frame or close a new epoch. No new inference or future input is requested. Genuine pending nonflush deliveries can contribute; explicit set-end clamped tail is recorded but excluded from candidate observations. Implicit reset/rotation flush remains invalidating.

After source drain, candidate reports precede the single terminal_end footer. Processing failure, missing drain or the2s bounded diagnostic-drain timeout gives an incomplete footer and withheld candidate. Camera stop/reset cannot claim completeness. Candidate operational watchdog can close first during drain, yielding explicit timeout withholding. A log of reordered/invalid source records is rejected by strict replay rather than silently sorted into an invented assessor history.

`BPT_TERMINAL_EOF_FLUSH=1` plus terminal evidence is a separate explicit capture-test hook. Video EOF first fences already accepted work on the serial camera processing queue, rechecks the captured epoch, then calls the **existing real endSet(currentIndex)** and records `processing_queue_drained:true`; the genuine lifter flush and finalization generate the footer. Without this flag the previous EOF/incomplete behavior remains. Recording and onSetEnd use their existing paths; the capture harness owns any recording option.

## Reproduction and integrity

```sh
swiftc ios/Runner/NativePose/Evaluators/TerminalObservationCandidate.swift scripts/replay_terminal_candidate.swift -o /tmp/bpt-terminal-candidate-replay
python scripts/terminal_evidence/replay_candidate.py /local/capture.jsonl --engine /tmp/bpt-terminal-candidate-replay
python -m pytest scripts/terminal_evidence/tests -q
swift test --package-path ios/CalibrationEngineKit --jobs 2
```

The original v1 strict geometry reader explicitly recognizes candidate/config/report and genuine EOF-hook records while preserving sequence and raw frame/rep order. Candidate input source/index/phase/side/state/flush and original boundaries bind to the same rich capture; captured native angle snapshots are checked against the assessment geometry. Raw/host clock substitution, fabricated geometry and modified reports are rejected. The compiled production candidate replays captured inputs/ticks and verifies exact logged report parity; output is aggregate coverage/assessment/closure counts and file hash. Candidate encoding or I/O failure cannot be hidden by a completed footer.

## Validation at native source freeze

- Swift: **244 executed,241 passed,3 skipped**, including21 candidate state/negative tests and the payload-drain/stale-release race. Existing native parity/regression tests remain included.
- Python: **33 passed**, including production-module synthetic live-log/offline replay parity, modified-output rejection, source/geometry binding and mixed v1/candidate/EOF stream preservation.
- Synthetic4-rep replay:3 reference-shortage withholds, then one30° relative-deficit result; all4 have observed stable windows. This proves state/math/replay behavior, not form accuracy.
- **Unsigned iOS compiler/link passed**,3-target project build, frozen source hashes unchanged. Existing exact673 Pods products were cloned into a new DD. As previously documented, compilation used the actual donor-matching temporary dependency lock520ca391…; original tracked lock79c96ff… was restored. This is not a fresh original-lock dependency rebuild. GeneratedPluginRegistrant m/h were hashed; IntegrationTestPlugin registration/link symbol is present. No install was performed by this source task.

Private compile receipt, source manifest, unsigned app and logs: `~/bpt-runs/terminal-candidate-20261102/`. Phone capture and actual measured coverage/live-offline parity are pending the separate authorized capture harness at this source freeze. They must be appended after actual evidence, not inferred from synthetic passes. No expert-labelled accuracy improvement, A7 resolution, adoption or deployment is claimed.
