# Native terminal candidate: actual capture and failure attribution — 2026-11-02

**The frozen candidate is not adopted: it withheld all20 squat/pushup reports.** Three actual native captures did close completely and replay exactly. A separate, explicitly DEVELOPMENT observed-peak diagnostic demonstrates missing later angle evidence without making correct-form or accuracy claims. No threshold, native candidate/default/model, original boundary/report or inference was changed after seeing these results.

Native freeze: `0a9ea01` + `1a35d3f`, based on `4eea822`. Captures use the authorized existing videos through the real iOS pipeline; source CMTime/index, raw/assessment geometry, actual native sample support/side/phase, original boundaries and genuine EOF/endSet flush are recorded. Models and coordinates remain unchanged. The video recording/service-binding follow-up is separate.

## Integrity and frozen result

| Actual capture | Source frames | Original reps | Candidate reports | Candidate result | Collector |
|---|---:|---:|---:|---|---|
| Squat |1,263|10|10|10 withheld|complete|
| Pushup |548|10|10|10 withheld|complete|
| Barbell row |587|10|0|unsupported by this candidate|complete|
| Total |2,398|30|20|20 withheld|3 complete epochs|

All three files pass the strict rich-stream validator, source/native-angle/boundary bindings and exact same-production-module live/offline report parity. Footers have pending0, no source-drain failure and no incomplete flag. Row's zero candidate reports are expected scope exclusion, **not** normal-form approval. Both exercise captures have zero mixed-side original intervals. Direct reconstruction of the original native maxima matches30 joint/rep values, maximum absolute difference2.84e-14°.

The first squat run lacked the Dart fixture's success.json because an early native-created header conflicted with its prelaunch-file ownership assumption. Its separately recovered closed raw stream passes the checks above; it is not represented as a complete Dart fixture PASS. The capture agent fixed only that test ownership check before pushup/row, which have fresh fixture success/cleanup evidence. Native code remained1a35d3f and the squat inference was not repeated. Private context/video/callback/individual-hash receipts remain in the authorized local capture archive; repo artifacts contain only aggregates and a combined hash manifest.

## Why the plateau candidate failed

The source intervals contain native `top` observations, but these angles keep moving. The requirement is **250ms of continuous low angular speed**, not just250ms in a phase called top. That native phase is an algorithmic bucket; it does not prove a physiologically static or correct top posture.

| Frozen attribution | Squat | Pushup |
|---|---:|---:|
| Continuous native top duration |0.767–1.267s|0.200–0.633s|
| Reps with top duration at least250ms |10/10|9/10|
| Longest low-speed stable run anywhere in pending span |166.7ms|100.0ms|
| Reps reaching required250ms stable run |0/10|0/10|
| Speed-condition resets / consecutive top transitions |299/337|129/141|
| Knee speed median / hip speed median |20.92 /36.97°/s|—|
| Elbow speed median |—|49.49°/s|
| Frozen closure |5 source-time deadline;4 operational watchdog;1 set end|9 actual next begins;1 set end|

Squat resets exceed the10°/s bound on knee223 times and hip276 times (both can reset the same transition). Pushup elbow exceeds it129 times. These measured angle changes can include actual movement and model variation; without GT they cannot be attributed solely to jitter or incorrect form. Frozen top-sample counters reproduce the native reports exactly. The250ms stability criterion rejects these continuously changing native-top trajectories even with usable native support; all reference counts remain0. The1.5s source/host cutoff also prevents waiting to the next squat begin in9 cases. This is a concrete coverage failure of the untuned candidate, not an accuracy improvement or a reason to relabel the movements bad.

The largest `stableSeconds` recorded at closure is166.7ms squat and66.7ms pushup; the100ms pushup value above is the longest run **earlier anywhere** in the pending span. This distinguishes final-run state from best historical run. Operational timing affects coverage and is replayed from the capture, not substituted by fast offline execution.

## Same-source observed-angle comparison

The native interval, a fixed15-source extension and a causal observed peak are different measurements. They are not GT errors or normality scores. Values below are macro means of one maximum per rep/joint; framewise speed summaries above have their own transition denominators.

| Joint | Original native max | Existing fixed15 geometry extended max | DEVELOPMENT supported-followup observed max |
|---|---:|---:|---:|
| Squat knee |122.47° (n10)|159.14° (n10)|176.28° observed (n10); support/boundary-qualified176.46° (n8)|
| Squat hip |119.21° (n10)|170.56° (n10)|176.59° observed (n10); qualified176.28° (n8)|
| Pushup elbow |151.04° (n10)|164.62° (n7)|164.29° observed (n10); qualified163.12° (n9)|

For the pushup fixed15 subset, the paired original mean is150.52° (n7), giving+14.10°; it must not be subtracted from the n10 original mean. Three reps have fewer than15 eligible subsequent sources before the next actual begin. Squat fixed15 paired changes are+36.66° knee and+51.35° hip (n10). The existing fixed15 baseline remains geometry-only and does not reproduce all native support gates. Its opposite-side/raw groups and explicit denominators remain in the aggregate artifact.

The DEVELOPMENT protocol was declared **after inspecting the frozen squat failure and before receiving pushup**, and therefore is development analysis on reused diagnostic data. It takes same-reported-side sources with actual native2D/view/state/dependent-angle support, ending before the actual next begin or after an entered top phase exits. It stops on missing support, clock gap, changed context or lifter flush; no1.5s/plateau requirement or GT anchor is added. Squat has8 supported actual-next-begin boundaries,1 support/side stop and1 clamped boundary; pushup has9 actual-next-begin boundaries and1 clamped boundary. Finite maxima before an unsupported boundary remain visible but are not counted as qualified windows. All raw/original/all-followup/top/last-plateau values remain preserved; no attractive value replaces the frozen assessment.

This demonstrates the native sampling limitation: larger same-joint estimates genuinely occur after original completion. It does not establish full anatomical extension, label the exercises correct, fix model angle accuracy, validate a replacement warning or qualify these videos as independent expert-labelled validation.

## Reproduction and artifacts

- [Frozen native capture aggregates](terminal_candidate_device_aggregate_20261102.json)
- [Separate DEVELOPMENT attribution/observed-peak aggregates](terminal_candidate_development_20261102.json)
- Helper: `scripts/terminal_evidence/development_diagnostic.py`; same-code replay remains `replay_candidate.py` plus the compiled production candidate module.

```sh
python scripts/terminal_evidence/replay_candidate.py /local/capture.jsonl --engine /local/compiled-production-replay
python scripts/terminal_evidence/development_diagnostic.py /local/squat.jsonl /local/pushup.jsonl /local/row.jsonl
python -m pytest scripts/terminal_evidence/tests -q
```

Final analysis tests after the fail-closed correction: **51 passed**. They include causal next-begin/top-exit boundaries, support loss/short spans, continuous moving-top speed resets and fixed15 denominator preservation, alongside existing strict/mixed-stream/live-offline tests. Native source validation remains244 Swift tests (241 passed,3 skipped) and actual unsigned iOS compile/link in the documented existing-donor dependency environment. No native source was changed for this analysis, no additional inference was run, and no automatic tuning, adoption, merge or deployment occurred.

## Diagnostic fail-closed correction

Root review found that the DEVELOPMENT helper could previously classify any non-top sample as an exit before checking whether it was unknown, unsupported, clamped or in a changed coordinate context. It now validates those conditions first and accepts only the actual native squat/pushup phases (`descending`, `bottom`, `ascending`) as a supported phase exit. An actual next-begin event remains a distinct causal boundary checked before consuming the new rep's geometry; negative tests make that exception explicit. Prior measured maxima remain visible on an invalid stop, but the window is not qualified.

All three preserved captures were revalidated and replayed after this helper-only correction. The frozen aggregate is exactly unchanged, including20/20 withheld. DEVELOPMENT qualified counts remain8 squat and9 pushup, with the same stop reasons and means; these captures did not use a phase-exit boundary. Summary medians now use the conventional middle-two average for even counts (`statistics.median`);22 aggregate median fields changed. Speed medians in the table have odd transition counts and are unchanged. Native code, thresholds, models and captured files were not modified and no inference or device operation was run.
