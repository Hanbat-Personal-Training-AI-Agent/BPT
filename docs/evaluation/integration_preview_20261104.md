# Review-based prospective integration compatibility tree — 2026-11-04

This is **preparation only**, based on tested review `d9f681aad386070ec21cc4d1f6ca2723eca62538`. It is **not an approved integration configuration**, adoption, deployment, or the separately built review app. `integration/ai` and the active review were not updated. No push, phone operation, or iOS build occurred.

The separate branch `review/bpt-integration-preview-20261104` starts at that review commit. `git merge-tree --write-tree --name-only` with integration `3cef41d5f18bbd62a66249bb50ac7bb6fc7f1600` produced tree `9b6ab7f3e0830ca7860426005151eda984ebf118` with five conflicts. That tree was loaded only in the new clean preview using `git read-tree --reset -u`, then resolved as below. The preview commit has one parent, the review commit; this does not create an integration merge commit. The exact inputs, three merge bases, pre-report resolved tree and verification hashes are in [the receipt](integration_preview_20261104.json).

The live input refs were 22 integration-only and 368 review-only commits apart at inspection. Multiple merge bases make a blanket “take one side” resolution unsafe.

## Resolution decisions

| Conflict | Source changes and resolution |
| --- | --- |
| `docs/decisions.md` | Retain integration's historical D-M-03 model decision (`f715c3b`, removal `24d0466`, merged by `bbda5da`) alongside review's D-D-10 and D-S setup/constraint history. Historical decisions remain history; they do not enact a change in this preview. |
| `PoseReplay/main.swift` | Preserve review's model choices and cadence/constraints/form-source/image-size/bone-target CLI. Import integration's `5edbb26` Halpe CSV extra-joint/foot preservation. Harden its column-count heuristic: only exact positional `j17_x,j17_y,j17_c` through `j25_c` headers enable extras. Unrelated, incomplete, or reordered trailing columns retain the old COCO17 behavior. |
| `project.pbxproj` | Preserve the review file byte-for-byte: both RTMPose-m packages, XS and later source registrations remain. Integration's `24d0466` mCOCO removal is not adopted. |
| `CameraPosePreview.swift` | Preserve review byte-for-byte. Integration `79996f0` adapts the earlier landscape-orientation work; review already has `cb6dcf1`'s `videoLayer == nil` distinction, `ebcfb38`'s rotation handling, and later scoped rendering (`bd05d40`, `911d26f`) and source-bound diagnostics. Retain recording rotation and setup hooks; the older all-joints/hands overlay would discard newer scoped rendering and mis-map video replay. |
| `SimCCDecoder.swift` | Preserve review byte-for-byte: keep mCOCO enum availability as well as mHalpe (`50194eb`), with existing defaults. Both input tips already use **s COCO17 for calibration and m Halpe26 for workout**; there is no model-default conflict. |

The three mCOCO package files that the automatic tree deleted are restored exactly from review. The four automatically changed Python evaluation-script defaults are also restored exactly from review, rather than silently changing benchmark selection from `mcoco17` to `mhalpe26`. Their legacy “app default” comments are not evidence of the current runtime model.

Relative to review, the only executable-code change is the bounded CSV replay improvement. Everything under `ios/Runner`, `lib` and `assets` is byte-identical to review. Added integration result documents and the historical quiet-key cherry-pick reference are retained. The model packages, calibration values, feedback defaults, experiment gates and camera runtime behavior are unchanged **relative to review**.

## Material adoption decisions still open

These are differences from actual `integration/ai`, not changes introduced by the preview:

- Review enables camera XS 3D by default unless `BPT_CAMERA_3D=0`; integration keeps it off. The preview preserves review's setting for compatibility testing, which is not permission to enable it in integration.
- Review retains the mCOCO model enum/package and XS package. Integration previously removed mCOCO. Choosing the eventual shipped resources and 3D policy still requires adoption approval.
- Review's calibration proposal (`c4557c5`) broadens roll 3°→10°, centre offset 0.06→0.10, feet/centre drift 0.03/0.08→0.08/0.15, maximum wrist drop 0.97→1.05 and minimum wrist reach 0.8→0.5, and adds cut-body guidance. This preview does not decide whether integration should adopt those gates.
- Review contains the newer overlay, hand/3D path and optional observer/source-binding/evidence code. Their existing experiment gates remain as in review. Desktop tests do not establish phone capture/lifecycle behavior or exercise-form accuracy.
- Benchmark scripts retain review's `mcoco17` defaults while runtime workout already uses mHalpe26. Select an explicit model when reproducing a benchmark; adoption may reconcile those defaults separately.

There is no global “unchanged defaults” claim relative to integration. Future integration adoption needs a concrete configuration decision and validation of that configuration. The user's current no-phone/no-merge instruction remains in effect.

## Verification

- **101 focused Swift tests passed, zero failures:** calibration, capture rotation, form warnings, RTMPose workspace and crop input. Tests built in an isolated scratch directory without fetching dependencies or running model inference.
- **Five executable CSV regressions passed:** plain COCO17, full named Halpe26, unrelated trailing metrics, incomplete Halpe extras and reordered Halpe extras. Each uses six synthetic rows, verifies coordinate preservation and unchanged input bytes, runs with `--motion3d none`, and opens no video or model. Run again with `BPT_POSE_REPLAY=/path/to/pose-replay python3 -m unittest discover -s test/python -p 'test_pose_replay_csv.py' -v`.
- `plutil -lint ios/Runner.xcodeproj/project.pbxproj`, camera Swift syntax parsing, preserved-review source/hash checks and `git diff --check` passed.

Local logs: `/private/tmp/bpt-integration-preview-{swift,model-tests,csv-tests}-20261104.log`. Synthetic proof files are under `/private/tmp/bpt-integration-preview-proof-20261104/`. These checks are separate from the root agent's iOS review build and do not claim a prospective integration app was built or installed.
