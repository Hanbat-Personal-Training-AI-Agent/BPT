# Demo recording (trial branch `ai/trial-mf953336` only)

The app runs the whole flow on its own: sign-up → onboarding → body scan (from a video) → upload and analysis →
3D body reveal → barbell row 3 sets → result → calendar. The screen is recorded with ReplayKit. Every sound is off.
The recording (it shows the user's face) and the logs stay in Mac `~/bpt-data/demo/`. They are never put in git or uploaded.

## How it runs

- Build: `build_liftdev_at.sh` (com.bpt.liftdev) with `--dart-define=BPT_EXERCISE_SETUP=true BPT_WRIST_ANCHOR=true
  BPT_MESH_REVEAL=true CALIBRATION_API_BASE_URL=https://hqbfgym--bpt-calibration-api.modal.run/v1
  CALIBRATION_STORAGE_HOSTS=1de0e5ab10d7233b02491befb246f0ff.r2.cloudflarestorage.com` (public settings).
- Settings come from `Documents/bpt_demo.json` on the phone. Its values sit on top of the process environment
  (`DemoConfig`), because a run without Xcode cannot pass launch environment variables.
  | key | value |
  |---|---|
  | `BPT_DEMO_AUTOPILOT` | `1` = run the flow once; the app sets it back to `0` |
  | `DEMO_ID` / `DEMO_PW` | account to sign up. The app deletes `DEMO_PW` from the file as soon as it reads it. The password is never logged. |
  | `DEMO_START_DELAY` | seconds before the first tap (time to accept the screen-recording prompt), default 4 |
  | `BPT_VOICE_MUTE` | `1`: Kori voice, workout voice and calibration beeps are skipped, not just set to volume 0 |
  | `BPT_SCREEN_RECORD` | `1`: ReplayKit records from first app-active until resign-active (microphone off) |
  | `BPT_CALIB_VIDEO` | body-scan input clip (Documents path) instead of the camera |
  | `BPT_CAMERA_VIDEO`, `BPT_CAMERA_VIDEO_LOOPS` | workout input clip and how many times it plays |
  | `BPT_BONE_TARGETS` | bone lengths in cm for the workout's 3D constraint |
  | `BPT_POSE3D_LOG` | `1`: joint log for the composite video (below) |
- Why an in-app autopilot (`lib/demo/demo_autopilot.dart`): `flutter test` cannot start an app on an iPhone that is
  connected over Wi-Fi, and a release build of `integration_test` did not run its steps. The autopilot taps through
  Flutter's normal gesture path (`LiveWidgetController`) and writes `Documents/demo/flow_steps.log`.

## Inputs used

- Account: final `abc1234`. The password is in a private Mac file only. Onboarding: male, 177 cm, 95 kg, goal 체형 교정.
- Sign-up form rule (f953336): the password needs 8+ characters with a letter and a digit, and the ID must match
  `^[a-z0-9]{4,20}$`. The first password the user gave had digits only and could not pass, so the user gave a new one.
- Body scan: `IMG_9900_slowdiag.mov`, made from the user's `IMG_9900.MOV` (1080×1920, 21.9 s, 658 frames).
  **Only the diagonal (side-front) parts are slowed to 0.25×.** In original-clip time those are 4.40–5.25 s,
  12.85–13.50 s, 16.10–16.50 s and 20.10–20.50 s; everything else plays at 1×. The new file is 28.8 s long and keeps
  all 658 frames: timestamps are stretched with ffmpeg `setpts` (variable frame rate), and no frame is repeated or
  held. It was re-encoded with libx264 at crf 14 and has no audio. Script: scratchpad `make_slowdiag.sh`.
  Why: the side-front poses pass in 0.3–0.6 s, but the capture hold needs 0.8 s
  (`minimumHoldSamples` 5). The segments are the replay's side-front candidate windows (`calib_rca`, IMG_9900),
  padded by about 0.1 s.
  - Mac replay (`scripts/calib_rca`, same engine code):
    - original as recorded: front, back;
    - slowdiag as recorded: all 4;
    - slowdiag flipped, the way the app now feeds it: all 4 (front 2.97 s, leftfront 6.00 s, rightfront 16.80 s,
      back 24.63 s).
  - Demo caption: "사선 구간 0.25배 느리게".
- Left/right: the calibration data buffer of the real camera is unmirrored, and only the preview is mirrored.
  Uploads use `coco17_pixel_unmirrored`. The selfie clip was saved mirrored, so the app now flips the clip before
  analysis (`BPT_CALIB_VIDEO_MIRROR=0` turns this off) and flips the preview layer back. The preview then looks like
  the real mirrored preview.
- **The turning order in the video differs from the app's guide.** The video goes front → right → left → back by the
  real turn; the app guides front → 왼쪽 → 뒷면 → 오른쪽. The engine captures views in any order, so all 4 are taken,
  but at a capture the on-screen caption can name a different turn from the one shown.
- Workout: Exercise3D P2 (the user) `barbellrow_0003_cam2` (20°; on the device it counted 11 reps, matching the
  11 in the ground truth). The clip plays continuously across the sets (it does not restart per set), 4 times in all. The target is set to the clip: the autopilot taps reps −1
  (12 → 11), so the run is 3 sets × 11.
- Bone lengths: `targets/P2.json` (lift-refine `20261020-shapes-ex3d-all`, sha256 `04a79c94…`). It is on the phone
  only (Fit3D-derived rule: no Mac copy, no git). The lengths from the demo's own body-scan result were not used
  (see below if that changes).

## Joint log (`BPT_POSE3D_LOG=1`) and clock

The log is `Documents/demo/pose_<yyyyMMdd_HHmmss>.jsonl`, one JSON object per line. Every line has:
- `type`;
- `t_host` = `CACurrentMediaTime()` in seconds (mach host time, monotonic, the same clock as the camera
  arrival times);
- `t_unix` = wall clock.

| type | fields |
|---|---|
| `start` | unit descriptions |
| `screen_record_start` | written in ReplayKit's start callback. Video time 0 is taken as this `t_host`; the first video frame follows within about one frame. `error` is null on success. |
| `screen_record_stop` | `reason`, `file` |
| `calib` | `pts` (clip time, s), `kp2d` (COCO-17 as x, y, score; x and y normalized 0–1 in the unmirrored analysis image), and engine state `guidance`, `classified`, `target`, `hold` (0–1), `captured` (views so far) |
| `frame` | workout frame:<br>• `frame`, `arrival_host` (camera arrival, same clock), `state` (3D state), `rep`, `exercise`;<br>• `size` and `rotation` of the analysis frame, `kp2d` (COCO-17 px, x, y, score);<br>• `pose3d`: 17 H36M joints × (x, y, z) after `Pose3DConstraints`, in normalized crop units (1 = half the person-crop side), y down, z away from the camera;<br>• `unit_px`: px per crop unit. |
| `rep` | `rep`, `warnings` (2D keys), `warnings_3d`, `form_source` |

The body scan logs 2D only. `scripts/demo_composite.py screen.mp4 pose.jsonl out.mp4` puts the recording next to
front (x-y), side (z-y) and top (x-z) views of `pose3d`, centred on the pelvis. It shows each pose frame at
`t_host − t(screen_record_start)` and also prints rep, state and the judged keys.

## Rehearsal accounts (throwaway, real team server; passwords not recorded)

| ID | result |
|---|---|
| bptdemo_20261023_0950 | integration_test try; never reached sign-up |
| bptdemo_20261023_1018 | integration_test try; never reached sign-up |
| bptdemo_20261023_1054 | autopilot; stopped on the login screen (sign-up link finder); never signed up. The ID also has an underscore, which the form does not allow |
| bptdemo10231115 | signed up and onboarded; the body scan stayed on front for 6 min (original IMG_9900, clip not flipped) |
| bptdemo10231149 | slowdiag clip, not flipped; the user saw 왼쪽 captured on a right turn, so left/right was swapped |
| bptdemo10231313 | full flow with the real server: upload, analysis and mesh screen reached in about 65 s from capture start. Set 3 stopped at 9/11 because the clip plays continuously across sets and 3 plays were used up, so it now plays 4 times (`BPT_CAMERA_VIDEO_LOOPS=4`) |
| bptdemo10231320 | passed to the result screen (3 × 11 = 33 reps, "허리 1회"); the calendar tab is not on the result screen, so the autopilot now taps '기록 보기'. The user reports the 3D body was not visible on the mesh screen (diagnosis pending, build f22ddbe writes `Documents/demo/mesh_diag.json`) |
| bptdemo10231331 | not used (phone locked, CoreDeviceError 4016) |
| bptdemo10231418 | stopped at the ID check: the server answered "중복확인에 실패했어" (network); no account made |
| bptdemo10231420 | new '신체분석 완료!' screen build (1e2a180 + diag): whole flow to the calendar passed, but no mesh. `mesh_diag.json` was never written, so no GLB reached `prepare`. Capture start to the done screen took about 4 min, so the app's 3-minute wait for the job ran out (job `job-c902ff4b5c7b4d67ac2e4532ed750b6c`; the server-side status is not yet checked) |
