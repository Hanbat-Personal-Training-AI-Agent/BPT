# Strict observation evidence replay

No production wiring/profile approval. Native ExperimentalCoaching is compiled directly; FormGeometry proxy methods are copied verbatim with per-function hashes. Default/current actual profile is nil. This tool never converts available geometry, no warning, or missing profile into normal posture.

```sh
python -m pytest scripts/coaching_observation_replay/tests -q
python scripts/coaching_observation_replay/replay.py <three-original-terminal-jsonl> --scratch <fresh-outside-repo-dir> > <aggregate.json>
# Derived-export-only rebuild from already executed identical native source/input:
python scripts/coaching_observation_replay/replay.py <same-originals> --scratch <fresh-dir> --reuse-native <old-native-scratch>
```

Scratch includes private `evidence.jsonl`, `native_outputs.json`, per-exercise `*_intervals.json`, catalog.json and receipt.json. It contains source-linked metric values and no photos/video, but is still private numerical evidence; do not commit per-frame artifacts. Public catalog records exact definitions, source version hashes, units and coordinate/scope. Profile-free consumers must preserve numbers with reasons/availability and report unknown approval, never coerce to zero. Metrics with value but `available=false` remain observations, not eligible evidence. Extra interval values with unavailable context are endpoint arithmetic only, not certified continuous movement. Flush/missing geometry never supplies an eligible rate.

Frame schema `coaching_observation_evidence.v1`: source epoch/frame/index/PTS+rational, context actual phase/side/view/rotation/mirror/layer/gravity provenance, metrics map (`value`, `rawValue`, `available`, `reasons`, `qualifiers`, `definitionId`, `unit`, `coordinateSpace`, `scope`, `requiredJoints`, `sourceDefinitionSha256`), original native candidates and `profile:null`. The current nine native metrics and two camera-reference proxies have separate IDs. `left/rightHipDeg` uses thorax8–hip–knee, not shoulder–hip–knee. `UpperArmDeg` is projected body-frontal abduction from caudal axis, not proven equivalent to research shoulder elevation or angle-to-plane. No research45/60degree limits are copied.

`trunkInclineDeg` needs source-synchronized gravity; `cameraTorsoSignedDeg`/`cameraHipLineDeviationRatio` deliberately use camera-up `(0,-1,0)` and retain limitations, never masquerade as synchronized ground/lumbar values. Source2Dhip/shoulder timing is pixel-image motion, not3Droot height/force. All original rep boundaries remain inclusive and unchanged. Strict range requires complete support/context; physical completion is not established by a report endpoint. No phase/reference/profile is inferred from GT, future reps, score, majority side or normal-looking values.
