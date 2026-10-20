#!/bin/zsh
# Mac chain for ai/setup-constraint while Home is offline. Each step takes the heavy lock separately.
W=/Users/6_month/github/06-month/hanbat/repositories/BPT/.claude/worktrees/ai-setup-constraint
S=${S:?set S to a scratch dir holding ex3d/ (csv, labels, gt.json) and mag/MotionAGFormer}
PY=/opt/homebrew/Caskroom/miniconda/base/envs/bpt-ft/bin/python
E="$PY $W/scripts/eval_setup_constraint.py"
COMMON="--dataset ex3d --ex3d $S/ex3d --mag-repo $S/mag/MotionAGFormer --device mps --cache $S/cache_ex3d"
cd $W
# A waiting or running phone run (device agent) goes first: wait until none is queued, then take the lock.
phone_busy() { ps -axo command= | grep "device_video_runs.py run" | grep -v -e "^/bin/zsh" -e "^zsh" -e "^bash" -e "grep" >/dev/null; }
L() { while phone_busy; do sleep 30; done; lockf -k /tmp/bpt-heavy.lock "$@"; }
echo "== swift test $(date)"; L swift test --package-path ios/CalibrationEngineKit 2>&1 | grep -E "Executed|error:" | tail -3
echo "== E6 cost $(date)"; L env BPT_COST=1 swift test -c release --package-path ios/CalibrationEngineKit --filter AdaptiveSetupCostTests 2>&1 | grep -E "E6 cost|passed|failed|error" | head -10
echo "== replay parity $(date)"; L swift build -c release --package-path ios/CalibrationEngineKit --product pose-replay 2>&1 | tail -1
PR=ios/CalibrationEngineKit/.build/release/pose-replay; RP=$S/runs/20261020-replay-parity; mkdir -p $RP
for job in squat_0000:cam1:squat:squat pushup_0002:cam3:pushup:pushup barbellrow_0000:cam2:row:barbell_row; do
  seq=${job%%:*}; rest=${job#*:}; cam=${rest%%:*}; rest=${rest#*:}; prx=${rest%%:*}; ex=${rest#*:}
  K=$(ls $S/ex3d/csv/$seq/${cam}_*_mcoco17.csv | head -1)
  L $PR --exercise $prx --keypoints-csv $K --motion3d ios/Runner/NativePose/Models/motionagformer_xs.mlpackage --adaptive on --image-size 1080x1920 --output-dir $RP $RP/${seq}_${cam}.mp4 2>&1 | tail -1
  T=$(ls -t $RP/*${seq}_${cam}*_3d.csv | head -1); $PY $W/scripts/check_adaptive_parity_replay.py --keypoints $K --replay-3d $T --exercise $ex
done
echo "== E1b $(date)"; L $E setup-ex3d $COMMON --run-dir $S/runs/20261020-e1b-setup-ex3d 2>&1 | grep -v -i warn | tail -80
echo "== cache-clean side1 $(date)"; L $E cache-clean $COMMON --ex3d-view side1 --run-dir $S/runs/20261020-ex3d-cache-clean 2>&1 | grep -v -i warn | tail -3
echo "== occlude side1 $(date)"; L $E occlude $COMMON --ex3d-view side1 --run-dir $S/runs/20261020-ex3d-occlude 2>&1 | grep -v -i warn | tail -12
echo "== foot-shift side1 $(date)"; L $E foot-shift $COMMON --ex3d-view side1 --run-dir $S/runs/20261020-ex3d-foot-shift --tag default 2>&1 | grep -v -i warn | tail -3
echo "== done $(date)"
