# Mac raw terminal geometry results — actual run2026-11-02 KST

Completed the bounded Mac-only replay with **real existing inputs**, not synthetic substitution. Source/video/model hashes and the pre-inference protocol are committed separately. No image/video viewing, new data/model download, training, threshold/default change, native capture, install or deployment occurred. The historical fixed15 **device-source** comparison remains unavailable; these are two different declared Mac sources with15 extra **observations** per window.

## What ran and when

Historical frozen8006baf source, actual RTMPose-m Halpe26 + MotionAGFormer-XS; original50fps/900×900 clips selected by exercise metadata only, no GT side/angle/repetition or fault-label input. Source decoded-frame totals979 squat +772 pushup equal the metadata counts. The new worktree's default XS path is absent, so the actual command used its explicit existing NativePose model path; both saved reports confirm actual3D execution. Native symlink/source/model hashes stayed unchanged.

First protocol6b24b44; before-inference timestamp correction/operational-guard revisionfd956b2 at UTC2026-11-01T21:48:57.656767. Actual build+inference lease UTC21:49:23.234524–21:50:17.788714 (KST Nov2). Later source-only flush guards5d4eb12/8616a8d were fixed **after inference, before real diagnostic angle computation/viewing**. Original protocols and each hash remain in Git/execution receipt; no claim that all guards preceded inference. Synthetic regression tests ran before real diagnostic computation.

The source proves row21 can also represent padded/clamped windows; it is not an observed clamp flag. Both runs have complete1:1 processed2D/3D rows, L5/C1/default rotations and no tracking_lost record. With this frozen constant-orientation successful replay, only explicit EOF flush remains reachable; every compared interval excludes its last5 processed rows. Last/open-next-report and known next-start crossings remain withheld. No missing invalid mask or active-rep/epoch/clamp field was invented.

## Aggregate observations

All additional15-observation spans were **0.300 seconds** (floating arithmetic range within2e-15s). This is50fps Mac footage, not500ms at nominal30fps phone capture.

| Scope | Original observed reports | Complete future-closed windows | Withheld last/open unknown |
|---|---:|---:|---:|
| Squat | 7 | 6 | 1 |
| Pushup | 6 | 5 | 1 |

These report counts are predictions, not independently known true reps. Both runs have21 warming-up rows; remaining958/751 rows are source state `ok`. No geometry rows were silently dropped from an eligible interval; each measured chain is finite/nondegenerate over the original inclusive window plus all15 observations.

| Geometric maximum, reported side | Raw increase median (range), degrees | Constrained increase median (range), degrees | Raw positive difference | Raw earliest extended-max offset median |
|---|---:|---:|---:|---:|
| Squat knee |16.819 (7.766–20.074)|16.829 (7.751–20.062)|6/6|+14.5 observations /0.290s|
| Squat hip |13.253 (8.923–37.822)|13.257 (8.942–37.826)|6/6|+14 observations /0.280s|
| Pushup elbow |16.243 (0–19.078)|16.264 (0–19.122)|4/5|+9 observations /0.180s|

The max of an extended set cannot decrease mathematically. These nonzero differences show that, for these particular Mac observations, later geometry exceeds the original reported window's maximum. They do **not** show improved form or corrected assessment. Some maxima fall at the15th added observation, so this fixed window does not establish the true terminal maximum or an optimal extension. One pushup maximum remains inside the original window (earliest offset−2); no beneficial peak was substituted.

All26 raw SimCC score columns are preserved, including843 values above1 (squat685/pushup158; maxima1.125/1.1494). They are not calibrated probabilities; no0–1 score clamp was applied. CSV coordinates/times retain stock4-decimal precision. The actual report/CSV files and per-rep results stay private.

## Resources, preservation and limits

Shared heavy lock held exclusively; Swift release build jobs2 then two sequential inferences, all return0, no operational stop. Wrapper wall times18.48s build,20.55s squat,15.42s pushup. BSD maximum resident bytes603,504,640 /120,061,952 /123,420,672 respectively; sampled1s process-tree RSS is separately recorded. These RSS figures do not measure all Metal/ANE/device-wide allocations; wall times include Mac model compilation/decode and are neither phone costs nor acceptance gates.

Eight meaningful synthetic tests pass: exact15/time mapping, next-start exclusion, last/open withholding, strict all-row geometry, score non-clamping, implicit-reset protection, EOF exclusion and malformed clock/config fallback. `py_compile` and `git diff --check` pass. Receipts record raw input/output hashes and protocol chronology. Per `docs/data/sources.md:4`, only the two owned SHA-verified batch movie copies were removed after analysis, with Home sources rehashed unchanged. Private original replay JSON/CSV, logs and diagnostic per-rep numbers remain at `~/bpt-data/terminal-mac-20261102/private/run2/` under0700. No donor/protected model/source write occurred.

Current device processing additionally uses MediaPipe wrist input and support-corridor assessment guards; Mac stock PoseReplay directly uses masked3D and lacks exact invalid masks, corridor assessment, source rational PTS/original packet index, active-rep/epoch/end-disposal and clamped flags. Therefore **native assessment eligibility remains false** for these numeric comparisons. No strict device-schema conversion, rule rejudgement, human fault label, FN/FP, native parity, timing-gate adoption or posture-accuracy improvement is claimed. Next required evidence is the new opt-in native capture with actual begin/clock/mask/flush provenance on a reachable phone, followed by independent human-labelled quality validation.
