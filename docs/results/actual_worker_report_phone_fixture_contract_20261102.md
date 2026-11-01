# Actual worker-report offline phone fixture contract

The isolated GPU producer's `worker_report.json` is an actual inference report. It is not an authenticated/deployed HTTP `DeepAnalysisJob` response. The phone test keeps the original worker file and SHA256 separately and constructs an explicitly synthetic local wrapper for the existing production parser:

```text
localTestWrapper: true
syntheticLocalMetadataOnly: true
sourceWorkerReportSHA256: SHA256(original worker bytes)
status: done                    # synthetic local test metadata
progress: 100                   # synthetic local test metadata
result.report: original worker report object, unchanged
result.videoUrl: file:///__local_fixture_original_video__
```

The marker URL is synthetic metadata and is never fetched. The video component initializes the original local native recording directly, after its SHA256 matches both the captured original and actual GPU-input receipt. The test checks the wrapper hash, original-worker byte hash and deep equality between the parsed report object and original-worker JSON. No rep observation, metric, null, zero, timeline or report field is synthesized or normalized by this mapping.

Only initial render and opening the first rep are tested. Seeking is deliberately outside scope; an unexpected seek request fails this fixture. No sustained playback, authenticated API job/response, saved-account, queue or user-record flow is claimed. Network attempts must be zero, real preferences use a memory backend, native video volume is zero, and no TTS/model inference is requested.

The original worker report, GPU receipt, copied video and exact hashes remain preserved privately on the Mac. Only hash-verified owned copies of the worker report, local wrapper and binding may be deleted from the phone during teardown. The user's original video, raw captures, logs, settings and prior files remain untouched; verified motion restoration follows the test. Actual inference data and approval remain mandatory before the physical run. Preparation with a synthetic self-check fixture is labelled as preparation only, not GPU execution or real-report validation.
