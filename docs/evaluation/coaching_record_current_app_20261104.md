# Current coaching and workout-record test app — 2026-11-04

A fresh **unsigned** iPhone Release test app was built from `33b88e898637f2775c52e64f072c2f08c4f9548f`, including the observed-joint correction-praise fix and workout-record attribution changes. The new app is preserved at:

`/Users/6_month/Documents/bpt-handoff/coaching-record-current-20261104/app_coaching_record_current_33b88e8_20261104.app`

It has **not been installed or launched**. Device runtime and visual behavior remain untested. The prior `39b0e28` handoff remains preserved. No phone operation, UI/window interaction, signing identity or private-key access, package download, training, deployment, or default configuration change occurred.

The cached offline build used the existing Pods/framework products, a three-target graph, two jobs, disabled package updates, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, and `FLUTTER_TARGET=integration_test/coaching_candidate_capture_test.dart`. It completed in 62.45 seconds. Source inputs remained unchanged and the temporary Podfile.lock was restored. The original 3 GiB start guard was retained; minimum observed free space was 3,224,154,112 bytes. Only the replay owner's completed regenerable build cache was removed, after its final binary and evidence were durably verified; the cleanup ledger is preserved with this attempt.

All 221 app files and all copied entry modes match the build product. All five compiled models' weights and MIL match the earlier handoff. Read-only `codesign -d` inspection confirms the app is unsigned.

- Runner SHA256: `228f688c33dcaf0c3e9fe8f0d8ed155f89e9e3d891688fc09ff4499008856c50`
- Flutter AOT SHA256: `664457f68e5747221fc011d3ce68c6ed06ddbeff932f83c86176fa2daae168ad`

Unchanged full suites were not rerun: all tracked `ios/Runner` bytes match tested native commit `17fa752`; all tracked `lib` and `integration_test` bytes match tested Dart commit `f681cc2`. The native fix and Dart attribution source hashes also match their preserved evidence receipts. Those validations were **364 Swift tests, four skipped, zero failures**, cached iOS typecheck for **67 Swift sources**, and **282 Dart tests passed, eight skipped**. These source comparisons do not constitute executing the new app.

The adjacent [machine report](coaching_record_current_app_20261104.json) pins the handoff receipt, build log and source-comparison hashes. Complete file hashes and modes, source freeze, test-source comparison, build command and read-only signing inspection are beside the app. Reproduction scripts and logs remain in `/Users/6_month/bpt-runs/coaching-record-current-app-20261104`. No signing, installation, launch or later action is scheduled.
