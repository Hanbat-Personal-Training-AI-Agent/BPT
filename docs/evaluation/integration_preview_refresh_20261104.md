# Current integration compatibility refresh — 2026-11-04

This is a refresh of the [earlier compatibility preparation](integration_preview_20261104.md), using review `ce86ae64fbbdcaab3ca4921317fe39c28072b04a` and unchanged integration `3cef41d5f18bbd62a66249bb50ac7bb6fc7f1600`. No branch was merged, checked out, pushed, or deployed. No phone was used.

The fresh automatic merge still has five conflicts: decision history, the CSV/video replay entry point, the Xcode project, camera preview, and pose-model decoding. Its complete difference from the review is twelve paths, including three removed mCOCO asset files and four changed benchmark defaults. There are no newly changed paths outside that reviewed set.

The earlier resolution choices remain explicit:

- Keep the decision history already present in the review. The new decision-file difference consists of conflict markers around retained history.
- Keep the current replay implementation: named Halpe26 extra-column detection is already included, together with newer source-frame identity and failure recording. The older alternative would lose those checks.
- Keep the current camera, Xcode registrations, model enum and model assets. This preserves the source that was compiled in the `33b88e8` test app; it does not approve those settings for integration.
- Keep the current benchmark defaults. Changing benchmark model selection is not part of conflict resolution.

A separate temporary Git index applied only these twelve reviewed resolutions to the automatic tree. The resulting tree is **exactly the existing review tree**, `8e05ea539110426667f2ae9d8a884f330e76a491`. No new candidate checkout or duplicated model files were needed. This identity shows that the chosen compatibility result contains the latest review work; it is not a claim that an automatic merge succeeds or that all integration-side configuration choices have been adopted.

The five synthetic CSV cases were rerun with the preserved final `17fa752` executable: COCO17, named Halpe26, unrelated trailing columns, incomplete extra columns, and reordered extra columns. All five passed; the command explicitly disables 3D inference and reads synthetic CSV only. The check is not a new iPhone test. Current Runner/Dart bytes still match the [combined unsigned app](coaching_record_current_app_20261104.md).

The earlier open adoption decisions remain: camera-3D policy, retained model resources, calibration gates, experiment defaults, and release configuration. The actual integration ref is unchanged. This refresh does not substitute a compatibility result for user approval or for missing device/independent accuracy validation.

Private reproduction records are in `~/bpt-data/completion-20261104-private/integration-refresh/`: exact merge output, the entire review/automatic-tree diff, temporary index, tree receipt, and hash-bound CSV command/log. [Public receipt](integration_preview_refresh_20261104.json).
