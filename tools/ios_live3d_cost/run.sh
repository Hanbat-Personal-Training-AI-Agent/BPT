#!/bin/zsh
# On-device live-pose cost without a person: RTMPose-s (30 fps pacing) with and without MotionAGFormer-XS.
# usage: tools/ios_live3d_cost/run.sh [seconds_per_mode=180]   (iPhone connected, unlocked, developer certificate trusted)
# Prints BENCH lines (latency mean/p50/p90/p99, achieved fps, process CPU %, thermal state at start/end).
set -e
REPO=$(git -C ${0:a:h} rev-parse --show-toplevel); MAIN=$(git -C $REPO worktree list | head -1 | awk '{print $1}')
DEV=${BPT_DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/available/ {print $3; exit}')}
UDID=${BPT_DEVICE_UDID:-$(xcrun xctrace list devices 2>/dev/null | grep -m1 -oE '\(000[0-9A-F-]+\)' | tr -d '()')}
W=$(mktemp -d); cp ${0:a:h}/{project.yml,Bench.swift} $W/; mkdir $W/Sources; mv $W/Bench.swift $W/Sources/
cp -R $REPO/ios/Runner/NativePose/Models/rtmpose_s_forward.mlpackage $W/Sources/
cp -R ${BPT_MAG_MLPACKAGE:-$MAIN/assets/coreml/motionagformer_xs.mlpackage} $W/Sources/
cd $W && xcodegen generate -q
xcodebuild build -project BPTDevBench.xcodeproj -scheme BPTDevBench -configuration Release -destination "id=$UDID" \
  -derivedDataPath ${BPT_DD:-$W/dd} -allowProvisioningUpdates -quiet
xcrun devicectl device install app --device $DEV ${BPT_DD:-$W/dd}/Build/Products/Release-iphoneos/BPTDevBench.app
xcrun devicectl device process launch --console --terminate-existing --environment-variables "{\"BENCH_SECONDS\":\"${1:-180}\"}" \
  --device $DEV com.bpt.posebench.D3LiveCost | grep BENCH
rm -rf $W
