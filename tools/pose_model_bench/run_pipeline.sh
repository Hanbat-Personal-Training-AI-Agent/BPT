#!/bin/zsh
# Video-fed live pipeline on the iPhone (Host/PipelineBench.swift), no person in front of the camera.
#   ./run_pipeline.sh setup <clips dir> <rtmpose_m_forward.mlpackage> <motionagformer_xs.mlpackage>
#       copies 720x1280 30 fps clips (<exercise>_<seq>.mp4) + models into Host/PipelineAssets (git-ignored), builds, installs
#   ./run_pipeline.sh <a|b|c|d> <paced|unpaced> [seconds=180] [cooldown=60]
#       a default (RTMPose-s COCO17), b + per-set recording, c + MotionAGFormer-XS every frame, d RTMPose-m COCO17
# Env: BPT_DEVICE (devicectl id), BPT_DEVICE_UDID (xcodebuild id), BPT_TEAM, BPT_DD (DerivedData).
set -e
cd ${0:a:h}
DEV=${BPT_DEVICE:-6886E076-24C5-54CD-BE2A-7B4276775949}
DD=${BPT_DD:-/private/tmp/bpt-derived-data}
if [[ $1 == setup ]]; then
  A=Host/PipelineAssets; rm -rf $A; mkdir -p $A/clips
  cp $2/*.mp4 $A/clips/
  cp -R ../../ios/Runner/NativePose/Models/rtmpose_s_forward.mlpackage $3 $4 $A/
  xcodegen generate -q
  UDID=${BPT_DEVICE_UDID:-$(xcrun xctrace list devices 2>/dev/null | grep -m1 -oE '\(000[0-9A-F-]+\)' | tr -d '()')}
  xcodebuild build -project PoseModelBench.xcodeproj -scheme PoseModelBenchHost -configuration Release \
    -destination "id=$UDID" -derivedDataPath $DD DEVELOPMENT_TEAM=${BPT_TEAM:-7W525J2XTN} -allowProvisioningUpdates -quiet
  xcrun devicectl device install app --device $DEV $DD/Build/Products/Release-iphoneos/PoseModelBenchHost.app
  exit
fi
case $1 in
  a) V='{}' ;;
  b) V='{"BENCH_RECORD":"1"}' ;;
  c) V='{"BENCH_3D":"1"}' ;;
  d) V='{"BENCH_MODEL":"rtmpose_m_forward"}' ;;
  *) echo "variant a|b|c|d"; exit 2 ;;
esac
ENV=$(python3 -c "import json,sys; v=json.loads(sys.argv[1]); v.update(BENCH_PIPELINE='1', BENCH_PACED='1' if sys.argv[2]=='paced' else '0', BENCH_SECONDS=sys.argv[3], BENCH_COOLDOWN=sys.argv[4]); print(json.dumps(v))" "$V" $2 ${3:-180} ${4:-60})
xcrun devicectl device process launch --console --terminate-existing --environment-variables "$ENV" \
  --device $DEV com.bpt.posebench.PoseModelBenchHost 2>&1 | grep --line-buffered BENCH
