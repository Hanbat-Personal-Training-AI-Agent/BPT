# Actual saved-input replay of the new observer port

The current optional observer was replayed on all three original native terminal captures, using existing saved XS output rather than new inference. This is an integration check on reused development data, not another historical model benchmark or an accuracy/adoption result. The original input files and all compiled source hashes remained unchanged.

The production COCO-to-H36M conversion consumed each row's actual `input_2d` (including its retained confidence). The adapter consumed that same row's saved `unit_px / imageHeight`, raw XS, rotation, index, PTS and rational timestamp. It did not derive crop scale from another frame, use corrected coordinates as raw, inject a native phase, supply identity, or assert fixed-camera/contact evidence. Personal and online profiles stayed off. The 63 original warmup rows have no raw XS and remain withheld; the 15 flush rows remain withheld. There are no invented samples.

| Original capture | All frame rows | Saved raw available | Flush rows |
| --- | ---: | ---: | ---: |
| Squat | 1,263 | 1,242 | 5 |
| Pushup | 548 | 527 | 5 |
| Barbell row | 587 | 566 | 5 |
| Total | 2,398 | 2,335 | 15 |

Each of A–H and HOLD evaluated the same 2,320 genuine rows, or 39,440 joint opportunities. All 21,015 variant rows with raw data preserved that decoded raw array exactly; Swift additionally checked bit-pattern equality before serialization. Every advertised observation passthrough and expired fallback was exact. Every prediction-used or expired-fallback joint remained invalid for assessment. Converted input confidence matched the saved H36M confidence exactly (maximum difference 0).

| Variant | Invalid joint opportunities | Prediction-used | Exact observation passthrough | Expired fallback |
| --- | ---: | ---: | ---: | ---: |
| A | 161 | 0 | 0 | 0 |
| B | 807 | 0 | 0 | 0 |
| C | 421 | 408 | 0 | 0 |
| D | 841 | 408 | 0 | 0 |
| E | 841 | 408 | 0 | 0 |
| F | 161 | 0 | 0 | 0 |
| G | 747 | 691 | 37,736 | 377 |
| H | 745 | 691 | 37,736 | 377 |
| HOLD | 421 | 408 | 0 | 0 |

G/H's 377 expired fallbacks all occurred in squat; these are withheld raw fallbacks, not recovered trustworthy joints. Contact states remained `UNINITIALIZED` throughout, as expected without fixed-camera evidence. E matches D because no personal profile was supplied; F matches A because contact evidence was not asserted. These similarities do not evaluate the disabled branches. A/F candidate reconstruction has at most 7.85e−17 XS-unit roundoff; the separately retained original raw array is exact. Differences between G/H invalid counts do not establish which output is anatomically correct.

The private trace has 21,582 variant rows: 20,880 evaluated, 567 withheld warmup and 135 withheld flush. It includes actual source binding, roles, uncertainty, masks, prediction use and candidate arrays. Only aggregate counts/hashes are committed in the adjacent JSON. Private files: `~/bpt-data/motion-observer-actual-replay-20261103-final-private/{freeze.json,aggregate.json,observations.jsonl}`. Initial compilation lacked the existing SimCC type definitions and stopped before replay; the retained first-attempt directory is not a successful run. Adding the original `SimCCDecoder.swift` dependency changed no algorithm.

Reproduce with the existing environment and a fresh private output directory:

```sh
/opt/homebrew/Caskroom/miniconda/base/envs/bpt-eval/bin/python scripts/motion_observer_replay/replay.py --out ~/bpt-data/motion-observer-rerun-private
```

The tool pins the three original input hashes, validates the terminal schema, freezes input/source hashes before execution, and uses the shared `/tmp/bpt-heavy.lock` for local compilation/replay. It never imports a model runner or makes network requests. Missing raw/source/coordinate context is withheld rather than fabricated. The output remains comparison-only; no pose, coaching, default, model, phone state or deployed service is changed.
