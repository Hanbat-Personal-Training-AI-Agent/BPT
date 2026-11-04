# Headless native fault evidence CLI

`pose-replay` remains unchanged by default. Opt in with both `--fault-trace-dir DIR` and `--fault-binding JSON`. This captures evidence from the actual MotionAGFormerLive → native evaluator → FormWarningTracker path. It adds no model, label input, rule threshold, training, or delivery default. Rounded keypoint CSVs are deliberately rejected in evidence mode: they cannot establish the original rational source clock. Ordinary CSV replay remains supported.

First commit the complete source, then build without inference:

```
python3 scripts/build_native_fault_replay.py --scratch-path /tmp/bpt-native-fault-build --output /tmp/native-fault-build.json
```

The builder owns `/tmp/bpt-heavy.lock`, preserves a 1 GiB free-space floor, checks all actual resolved PoseReplay source files and Package.swift against the candidate git blobs, and compares their hashes before and after the build. The resulting manifest binds the exact executable SHA256 and candidate commit. Never edit compiled sources after freezing; the CLI rejects mismatched sources or executable.

Create the binding file using the exact build manifest object:

```json
{
  "buildManifest": {"contract": "bpt-pose-replay-build-v1", "...": "complete generated manifest"},
  "clips": [
    {"candidateId": "40-character-full-candidate-commit-sha", "clipId": "new-local-source-id", "sourceSHA256": "full-original-video-sha256", "require3D": true}
  ]
}
```

`clips` is ordered exactly like the command's video arguments. `require3D: true` asserts both an active lifter and the 3D form source; a missing default XS package cannot silently downgrade that run. Every source is hashed before model loading and again when evidence begins. The CLI records the executable hash, resolved repository source hashes, original zero-based sample index, and raw CMTime value/timescale/epoch/flags obtained directly from each CMSampleBuffer. It never derives a source clock from FPS. The header hashes every file in the actual model bundles and records runtime settings. A separate `receipt_<runID>.json` rehashes the full source and model artifacts after all native evaluation and flush work; any mismatch closes the trace incomplete. The bundle hash is SHA256 over sorted relative file names, NUL, each file's hex SHA256, and newline. Its existing processing-frame index remains distinct from the original sample index when ingress fails. Missing pixel buffers, image conversions and RTMPose failures are explicit. After a fatal pose observation failure, remaining decoded samples are recorded as unprocessed; coverage remains incomplete. Native lifter flush delivery is explicitly marked. Reader failure and thrown/early exit close evidence as incomplete; a close footer alone does not establish complete coverage.

Headers carry `taskBinding: unbound_native_windows`: no task or boundary ID is accepted before the actual native run. Stage 2 must create and freeze a new trace-derived task manifest, keep human labels unknown, bind the full source SHA and candidate code, then apply strict export/import. Existing tasks and historical terminal captures cannot inherit these results through matching filenames.

An inference run requires the separately authorized actual model paths, for example:

```
/path/from/build/pose-replay --exercise squat --model mhalpe26 --model-path /existing/rtmpose.mlpackage --motion3d /existing/motionagformer_xs.mlpackage --fault-trace-dir /private/new-traces --fault-binding /private/new-binding.json --output-dir /private/new-legacy-output /private/original-video.mp4
```

This command is illustrative, not an assertion that it was run. The existing CLI enables all spoken feedback keys for its legacy report; the trace records that actual delivery configuration. It does not claim the phone's delivery defaults.

Focused validation without decoding, model inference or UI:

```
python3 scripts/test_native_fault_cli.py --binary /path/from/build/pose-replay --build-manifest /tmp/native-fault-build.json
```
