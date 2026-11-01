# One isolated L4 replay — prepared, transfer NOT approved

Actual date2026-11-02 KST. Adapter6204700 verifies historical770 actual bytes/manifests locally. The execution script now requires explicit expected video SHA256, canonical native-manifest SHA256 and native source commit, so the phone owner's upcoming **current-native full recording** can become the final input without manufacturing GT boundaries. Its exact final input/plan digest must be frozen after read-only recovery and adapter verification. The770 dry preparation is a contract rehearsal, not authorization to send that video instead.

## Destination and existing assets, read-only verified

Existing `bpt-calibration.deep_analysis_job` metadata: L4×1, timeout900s, retries0; image `im-4SiTgQLfJqcNflEuz14dR3`. Existing `bpt-gvhmr` volume `vo-PaJI2oGtteoNeTikv2DP3O`: all7 declared model/body/regressor assets present with expected sizes. This was a metadata-only query, GPU invocations0/media transfers0. Deployed application source commit is not exposed by that metadata and is not assumed to equal latest source.

Reuse exactly that image ID via Image.from_id and existing volume create_if_missing=False/read_only. No image build, pip/git/HF/model download or new secret. Runtime mounts only public verification source; source mounting avoids cross-version Python code pickling (local3.12, existing image3.10). Network is blocked inside the GPU container. Existing Modal account authentication is used normally; no secret values are printed or attached to inference. No production deployment/configuration/API job/account/history is changed.

HomeGTX1060 has3,072MiB total, current observed used1,296MiB/free1,776MiB. Existing40 historical runs are half mode; historical stage delta peaks reach2,056.2MiB ViTPose and2,354.2MiB features before headroom. This does not justify an OOM trial now. Current production worker uses runner default **fp32/half=False**; the isolated L4 run preserves that. No claim of half/Home↔fp32/L4 equivalence is made.

## Exact transfer and one invocation

Only after explicit approval matching the final plan/video digest: send **one recovered native H264 video**, its **unchanged native reps manifest**, small source/hash/resource metadata and public frozen Python/CSV source snapshots. No GT, original research rep/side metadata, credentials or personal calibration beta is sent. The known historical source clip name is Exercise3D-family `barbellrow_0000_cam2.mp4`; public redistribution/same-person calibration provenance is unproven, so treat the recording as **private**. Existing local-only restrictions are not waived by preparation. Final recording source/size/digests may differ and must be explicitly reviewed.

The GPU call uses latest worker/scorer source snapshot4eea822 (including partial geometry validity) and current runner, plus old scorer17583f3. It stages and verifies exact source hashes and actual imported module paths/hashes, rejecting the old bundled worker import. Remote and staged canonical native manifest digest and original video digest must match the approved plan. Call **deep_worker.analyze**, including its actual normalization; do not call runner directly on original VFR bytes. Record original→worker-normalized→runner-prepared actual decoded-frame/PTS metadata/hashes, never re-label resampled/duplicated frames as new independent observations or retime native video_ms boundaries.

Exactly **one inference**, fp32, beta=None/model-estimated GVHMR shape. No final1602 or other person's calibration/approved profile. Missing existing assets or actual saved tracking mask stops the attempt; no invented all-tracked mask. Same saved world/confidence/tracking inputs feed both scorers, no second inference. Old/new canonical core report hashes/content parity, actual validity/reason/null counts or old whole-job error are recorded. `bodyShape=gvhmr_fallback` is the standard fallback metadata for this explicit beta=None path, not an authenticated API job or independently correct body-shape claim.

## Resources and costs (operational guard, not speed acceptance)

One L4; CPU request2/max4; RAM request8/max16GiB; function timeout900s, startup timeout120s; idle2s; min0/max1container; max1input; retries0. No automatic extra invocation/precision alternative/OOM retry. Tentative operating expectation60–600s is not a guarantee or adoption gate. Failure/timeout returns available private diagnostics, then stops for review.

[Modal official pricing](https://modal.com/pricing) checked2026-11-02: L4$0.000222/GPU-second, CPU$0.0000131/physical-core-second, RAM$0.00000222/GiB-second.900s GPU alone is$0.1998; CPU/RAM/load/idle are additional. At4cores/16GiB, the stated1022s function+startup+idle planning envelope is about$0.317 before any separately billed platform overhead; this is **not a total-invoice guarantee**. Proposed operator budget is$1 for this one attempt, no retry. No new image-build operation is requested.

## Retention, results and proof limits

Remote source video/normalized/prepared/crops/results live only in a dedicated TemporaryDirectory removed in finally. Weights volume is read-only. No R2 input/job/history/profile is created. Provider invocation/blob/log retention is not erased or controlled by this filesystem cleanup and must not be represented as instantaneous cloud erasure. Source video itself is **not** returned; it already remains preserved Mac/phone. Private archive back to Mac contains result.npz/world+actual support/tracking, timing, current worker/core report, old report/error, overlay, provenance and a private run log. No raw arrays/media/individual metrics go to git; only aggregates/hashes are public. Predicted personal shape inside raw model artifacts remains private.

This verifies an **isolated latest worker invocation**, not the deployed authenticated upload API/version, personal beta binding, expert posture accuracy or historical/native timing correction. A normal API job is a separate additional permission/identity concern, not automatically run. Current Flutter parse/render must be tested on the actual returned report without attaching the unrelated20s squat job.

## Prepared-code checks and execution guard

Six local tests pass without remote execution: wrong video scope; remote changed video/canonical manifest rejection before model access; embedded current/old program compile+actual worker signature; missing/wrong approval and changed plan rejection before Modal import. Adapter9Python and actual private Flutter3tests pass separately. py_compile/diff-check pass. Normal invocation without `--execute` only writes a new local plan. Execution also requires both the matching `--approved-plan-sha` and `BPT_NATIVE_VIDEO_TRANSFER_APPROVED=<exact final video SHA>`; it rejects changed deployed image/volume identity and existing output paths.

Prepare final input (placeholders must be replaced only with owner-proven actual values):

```sh
python native_deep_isolated_l4.py --root REVIEW --package VERIFIED_PRIVATE_PACKAGE --video RECOVERED_PRIVATE_VIDEO --expected-video-sha ACTUAL_SHA --expected-native-manifest-sha ACTUAL_CANONICAL_SHA --capture-source-commit ACTUAL_NATIVE_COMMIT --output-dir NEW_PRIVATE_PLAN
```

No transfer or paid GPU invocation has happened in this preparation. Final approval belongs after final concrete input/plan review.
