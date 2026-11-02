# Local deep-analysis HTTP/storage contract — PASS

Test-only branch `test/local-deep-storage-contract-20261102`, production base `2aed537ca3f4e01e6c6943631d03a80d2aecac5b`. Production Dart/native/server sources and dependency locks are unchanged.

The frozen execution passed 21 actual HTTP request/status contracts through Uvicorn and production `service.create_app`, `Bucket` and `BucketState` backed by a private localhost Moto S3 emulator. Requests covered missing/expired authentication, owner isolation (synthetic users 42/43), missing uploads, manifest MIME rejection, actual presigned PUT of the original 6,534,978-byte video and manifest, completion/reprepare idempotency, queued/done reads, done-retry conflict, and fresh API/Bucket/BucketState recovery from the same persisted emulated object store. Conditional state creation preserves the first writer. Exactly one spawn and one analysis callback occurred **per execution**.

`deep_worker.run` executed its production storage/output path. Its injected analysis callback verified the exact video/manifest and `beta=None`, then returned a deep copy of the previously recovered genuine worker report and copied its genuine overlay. Model execution, normalization, rendering, Modal imports and cloud fallback are prohibited. Every original report field except the production wrapper's `runtime` and `bodyShape` remains equal. These runtime values describe this local replay, not GPU/model speed. Original report timing/resource fields remain unchanged.

The exact response bytes returned by the local API were consumed by production `DeepAnalysisJob.fromJson` and `DeepAnalysisReport` in a Flutter host widget test: done/progress100, ten repetitions, 21 timeline entries, first repetition expanded, no visible `null°`/`NaN`, no Flutter exception, zero Dart network attempts. The video was a placeholder. This envelope is an actual **LOCAL** API response, not a manually constructed wrapper.

## Frozen evidence

Private directory (0700, files0600): `/Users/6_month/bpt-data/local-deep-storage-contract-20261102-frozen/`.

- `summary.json`, `contract-observations.json`, `input-receipt.json`, `source-hashes.json`
- `actual-local-api-job-response.json` and `actual-local-api-after-restart.json` (raw HTTP response bytes)
- `host-parser-widget-proof.json`, `flutter-host-result.json`, `flutter-host-test.log`
- `cleanup.json`, `cli.log`

Frozen HTTP response SHA256: `f110acab4ad0d2bf552fef3bdbeea4b5025ff15b7e576d12bf368a130423c4c6`.
Python harness SHA256: `0e7d0d730865d061e4484263b8502ae71621b9a299bfa60f21ed91c80053595f`.
Original report core SHA256 (excluding only runtime/bodyShape): `48f0acf30639ee196b505cb623bc8e471c64d59ca1c512e1efc7648df167edbe`.

Immutable inputs: video `53658c052b52bde1285b3e3ee6a1951f201419831e9ce776af094f31749c44d8`; canonical manifest `2cc367da42da9c2b218990a730e0e5e1310645ef043392ec2d1d53dfb147c66f`; report `f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa`; overlay `b1630a93c243911bb154f8daad6dd489f2581f037cb9b2dd4bd9099fd6728113`. All four original byte hashes remained unchanged.

Earlier development executions are preserved in sibling `local-deep-storage-contract-20261102-{attempt1,final,guarded}` directories. Initial actual execution preceded the explicit Python optimization guard; the final frozen code includes it. `python -O` was separately rejected before output-directory/server mutation. Frozen source hashes match executed files. The test refuses ambient credentials, uses explicit synthetic keys/JWTs, HTTPX `trust_env=False`, and permits socket destinations/presigned hosts only on owned 127.0.0.1 ports.

## Cleanup and scope

All owned API threads and Moto stopped, all three ports closed, nine owned emulator objects and their bucket removed, worker temporary directory empty/removed, cleanup errors zero. Cleanup attempts each owned service independently even if another step fails. No physical device calls, native build, new inference/GPU, external upload/request, production deployment, model/default changes, or original-data mutations occurred.

Moto is an emulator: this does not establish production R2 availability, provider IAM/signature/expiry behavior, capacity, durability across emulator restart, or deployed-service correctness. Synthetic JWT validation is not real Spring login. Host response parsing/rendering does not test Dart HTTP/TLS/upload networking, phone video initialization, seeking, sustained playback, audibility, or model accuracy. Prior physical-phone results remain separate.

## Reproduction

Use the existing `bpt-eval` Python environment; no dependency installation is required. Run `scripts/deep_analysis/verify_local_storage_http_contract.py --out <fresh-directory-under-~/bpt-data>`. Actual private inputs are mandatory and SHA-gated before any server starts. Run `flutter test --no-pub test/local_deep_http_response_test.dart` with explicit `BPT_LOCAL_API_RESPONSE_FILE`, `BPT_LOCAL_API_RESPONSE_SHA256`, `BPT_ORIGINAL_WORKER_FILE`, and `BPT_LOCAL_WIDGET_PROOF_FILE`. The host test has no synthetic fallback. Run only on the private Mac with the preserved inputs; do not publish raw responses/media.
