# Current offline test app — 2026-11-04

A new **unsigned** iOS Release test app was built from `39b0e28ea298721fbaf7904abf5e43567c3ef7ec`, including the reviewed adaptive withholding and Camera ingress/EOF identity changes. The previous signed `6c932d2` app remains preserved. This new app has **not been installed or launched on a device**; its device runtime remains untested. The earlier three-video native replay remains separately pinned to `94a72a5`.

App: `~/Documents/bpt-handoff/native-fault-current-20261104/app_native_fault_current_39b0e28_20261104.app`

The adjacent `handoff-receipt.json` records all file hashes; all 221 copied files matched the build product byte-for-byte with modes preserved. The compact [machine report](native_fault_current_app_20261104.json) pins the handoff/build receipts and executable hashes:

- Runner SHA256: `92d7ca1721c7c466fe5434686530c55c0fc5c2ef944273ffa0b0314f50963025`
- Flutter AOT SHA256: `833679fd84518933f0eac1dced3102c32f80d05ff1e7d15ef537f14f56275634`

The isolated source passed 346 Swift tests (4 skipped, 0 failures). The cached, offline three-target Release build completed in 61.13 seconds with source hashes unchanged and the temporary Podfile.lock restored. All five compiled CoreML models' weights and MIL matched the prior app. The initial 3 GiB storage guard remained unchanged; observed minimum free space during compilation was 3,062,525,952 bytes. Only completed, regenerable caches were removed to make room. Current and prior apps, models, sources, SourcePackages metadata, logs, and evidence were retained.

A read-only comparison against central commit `1798833feacb596456376a99f99e31cab596d02f` found all 208 tracked files under `ios/Runner`, `lib`, and `integration_test` identical to the built source, including resources and models. Generated ignored dependency metadata is outside that comparison. The detailed `current-source-comparison.json`, complete test/build logs, source freeze and hash manifest remain in `~/bpt-runs/native-fault-current-app-20261104/` and the comparison is also copied beside the handoff app.

Signing was not attempted: a cached identity and unexpired provisioning profile exist, but no-dialog private-key access was not proven. Read-only codesign inspection confirms the app is unsigned. Signing, installation, and device launch checks remain pending work requiring the corresponding authorized environment; nothing is scheduled or automatically executed. No phone operation, UI window, package download, new training, or deployment occurred during this preparation.

Independent root verification also passed: all 163 source-input files matched central review, all 221 app files matched their handoff hashes, and the executable and receipt checksums agreed. Its receipt is `~/Documents/bpt-handoff/native-fault-current-20261104/root-verification.json`; the machine report pins that receipt hash.
