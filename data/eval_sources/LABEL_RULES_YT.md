# Hand-labelling rules (rep counts + wrong-form keys) — read fully before starting

You label exercise clips by LOOKING at contact sheets (JPG). Each sheet = one video sampled at 3 frames/s,
tiles left->right, top->bottom, each tile stamped with its time in seconds (yellow, top-left).
There may be small captions or logos; ignore them. If the clip is not the expected exercise or the performer is not fully visible, say so in notes and use rep_conf low.
Videos are on Home: `ssh Home` ~/datasets/yt_cc/segments/<name>.mp4 (30 fps; YouTube CC-BY segments, one continuous shot each). If a sheet is ambiguous you may
make a finer sheet of a time window, e.g.
`ssh Home 'E=~/miniconda3/envs/bpt-data/bin; FFMPEG=$E/ffmpeg FFPROBE=$E/ffprobe sh ~/data-collect/contact_sheet.sh ~/datasets/yt_cc/segments/<name>.mp4 /tmp/<you>_<name>_z.jpg 6 <start_s> <dur_s>'`
then `scp Home:/tmp/<you>_<name>_z.jpg <your scratch dir>/` and Read it. Delete your extra files afterwards. Never copy videos to the Mac.
Work independently: do NOT read any other labels file in the labels directory.

## Rep count
- `reps` = number of FULL repetitions in the clip: start at the top (standing / arms extended / arms hanging),
  go down (or pull), reach the end position, and return to the top — all inside the clip.
- A movement already in progress at the very start (clip starts at/near the bottom) or cut off at the end
  is NOT counted in `reps`; count it in `partial` (0, 1 or 2) instead.
- Dumbbell row (file contains `back`): one rep = one pull up and lower. If the two arms alternate, count each arm's pull as one rep and note "alternating". If both arms pull together, one pull = one rep.
- Count bottom positions carefully; time stamps between tiles are 0.33 s, fast reps may show only 1–2 tiles at the bottom.
- `rep_conf`: high (sure), medium (±1 possible), low (could be off by 2+ or the person is not doing the exercise clearly).
- `rep_times`: the times (s) of each counted rep's bottom / peak-pull tile, space separated (e.g. `2.3 4.6 7.0`).

## Form
Segments come from YouTube tutorials and training videos; some show deliberately wrong reps, some correct reps. Several segments from the same channel may show the same person doing it right and wrong — compare them.
your job is to name WHAT is wrong, mapped to the app's warning keys below. Judge only what is visible in this view.
- `form`: normal | wrong (what you see, not the file name; a `bad` clip can look normal → say normal; a `good` clip can show an error).
- `wrong_keys`: semicolon-separated items `key:reps:conf`, where reps = `all` or rep indices `1,2,5` (1-based over the counted reps), conf = high|medium|low.
  Use `other:<short text>` for visible errors that have no key. Empty if normal.

Keys (use exactly these names):
- squat: `squat_shallow` (does not go down to about thigh-parallel / clearly shallower than the good clip), `squat_hips_first` (on the way up the hips rise faster than the shoulders, chest tips forward), `squat_lean_drift` (torso lean grows rep by rep), `squat_no_lockout` (does not stand fully up between reps), `squat_depth_fade` (depth gets shallower over the set), `squat_heel_rise` (heels lift), `squat_knee_valgus` (knees cave inward — only judge from front or diagonal view). Excessive forward lean in itself, knees-past-toes and rounded back are NOT keys → `other:`.
- push-up: `pushup_hip_sag` (hips drop below the shoulder–ankle line), `pushup_hip_pike` (hips up above the line), `pushup_shallow` (elbows bend little / chest stays far from floor), `pushup_no_lockout` (arms not straightened at the top), `pushup_head_drop` (head hangs toward the floor), `pushup_head_up` (head cranes up), `pushup_hand_position` (hands far ahead of or behind the shoulders), `pushup_depth_fade` (depth fades over the set), knee push-up → `other:knees down`.
- row (barbell or dumbbell bent-over row, Pendlay row): `row_torso_swing` (torso angle swings up and down within each rep / body english), `row_standing_up` (torso much more upright than the good clip), `row_short_pull` (elbow does not travel past the torso line / tiny range), `row_head_up` (head cranes up), `row_shrug` (shoulders shrug to the ears). Rounded back → `other:rounded back`.
- `form_conf`: high | medium | low for the overall form judgement.
- `view_check`: what you actually see: side | diagonal | front | back (camera relative to the person's body), plus `+mirror` not needed.
- `people`: number of people performing in frame (others standing far in the background don't count; note them in notes).

## Output
Write ONE CSV to the path you were given, header exactly:
`file,reps,partial,rep_conf,rep_times,form,wrong_keys,form_conf,view_check,people,notes`
`file` = sheet name without .jpg (e.g. subject_001_squat_bad_side). Quote fields containing commas. One row per sheet in your list. Be careful and honest — when unsure say low.

## YouTube note
Your list has two tab-separated columns: segment name and exercise (squat | pushup | row). Images are at scratchpad/dc/ytsheets/<name>.jpg. For row, one pull = one rep (barbell: both arms together).
