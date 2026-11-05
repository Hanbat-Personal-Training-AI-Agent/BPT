# Separate H policy sensitivity on saved inputs

This is a separate, explicitly declared sensitivity: H with `fixedCameraAssertion=true` and `onlineCalibration=true` on the same three retained video-as-camera inputs. The fixed-camera flag is an operator assertion for this experiment, not a measured contact label. The online prior is estimated from initial observations; it is not personal SMPL calibration, ground truth, or proof of correct initial posture. No new video, model inference, phone execution or default change was made.

The unknown-camera/no-profile 27-row baseline and its private files remain unchanged. This run adds only three H rows. Source/input freezes prove the production observer, estimator and coordinate conversion sources are identical between the two runs. There are again 2,320 evaluated rows, 63 warmup rows without raw XS and 15 withheld flush rows. All 2,335 raw-present arrays and retained confidence values match their sources exactly. Prediction-used and expired-fallback joints remain invalid.

| Capture | Online-prior-applied frames | Internal CONTACT states | Contact-corrected joint opportunities | Candidate-changed frames vs baseline H |
| --- | ---: | ---: | ---: | ---: |
| Barbell row | 502 | 1,108 | 0 | 0 |
| Pushup | 463 | 1,929 | 17 | 17 |
| Squat | 1,178 | 2,459 | 0 | 0 |

Counts of CONTACT are internal anchor opportunities (two feet for row/squat, hands and feet for pushup), not confirmed real contacts. Across all three clips the state machine also emitted 46 OCCLUDED, 70 REACQUIRE, 15 MOVING and 57 UNINITIALIZED opportunities. Online priors applied in 2,143 frames after each clip's initial 59 observations. This demonstrates execution of those branches, not their accuracy.

Exact per-row comparison found **zero changed invalid masks, prediction-use masks or phase labels**. Seventeen pushup rows had a changed candidate, maximum difference 0.049979 original-XS units. No changed row or lower correction magnitude is called an improvement. Raw output, observation evidence, withholding and source identity stayed exact; the phase still comes only from the internal heuristic.

[Aggregate and comparison hashes](motion_observer_fixed_online_h_20261103.json) exclude raw coordinates. Private outputs are under `~/bpt-data/motion-observer-fixed-online-h-20261103-private/`, including `freeze.json`, `aggregate.json`, `observations.jsonl` and `comparison-final.json`.

```sh
/opt/homebrew/Caskroom/miniconda/base/envs/bpt-eval/bin/python scripts/motion_observer_replay/replay.py --fixed-camera-online-h --out ~/bpt-data/motion-observer-h-sensitivity-rerun-private
/opt/homebrew/Caskroom/miniconda/base/envs/bpt-eval/bin/python scripts/motion_observer_replay/compare.py --baseline ~/bpt-data/motion-observer-actual-replay-20261103-final-private --sensitivity ~/bpt-data/motion-observer-h-sensitivity-rerun-private --out ~/bpt-data/motion-observer-h-sensitivity-rerun-private/comparison.json
```

This sensitivity does not complete verified profile-to-person binding, natural contact validation, device runtime or deployment acceptance.
