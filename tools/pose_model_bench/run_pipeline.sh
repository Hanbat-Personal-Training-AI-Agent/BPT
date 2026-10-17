#!/bin/zsh
# Video-fed live pipeline on the iPhone (Host/PipelineBench.swift), no person in front of the camera.
#   ./run_pipeline.sh setup <clips dir> [rtmpose_m_forward.mlpackage] [motionagformer_xs.mlpackage]
#       copies 720x1280 30 fps clips (<exercise>_<seq>.mp4) + models into Host/PipelineAssets (git-ignored), builds, installs.
#       BPT_MP_DIR=<dir with pose_landmarker_{lite,full,heavy}.task + frame.jpg> also bundles the MediaPipe assets.
#   ./run_pipeline.sh <a|b|c|d|e|f> <paced|unpaced> [seconds=180] [cooldown=60]
#       a default (RTMPose-s COCO17), b + per-set recording, c + MotionAGFormer-XS every frame, d RTMPose-m COCO17,
#       e MediaPipe pose_landmarker_full (BPT_MP_DELEGATE=gpu|cpu, default gpu), f RTMPose-m Halpe26
#       (setup with rtmpose_m_halpe26_forward.mlpackage among the extra models)
#   ./run_pipeline.sh mp <latency|sustain|all> [model=pose_landmarker_full] [delegate=gpu] [seconds=150] [cooldown=0]
#       Host/MediaPipeBench.swift on PipelineAssets/frame.jpg
# Env: BENCH_EXTRA (JSON of extra launch env, e.g. '{"BENCH_LOST_SEARCH":"10"}' — re-acquisition knobs, PipelineBench.swift),
#   BPT_DEVICE (devicectl id), BPT_DEVICE_UDID (xcodebuild id), BPT_TEAM, BPT_DD (DerivedData).
set -e
cd ${0:a:h}
DEV=${BPT_DEVICE:-6886E076-24C5-54CD-BE2A-7B4276775949}
DD=${BPT_DD:-/private/tmp/bpt-derived-data}
if [[ $1 == setup ]]; then
  A=Host/PipelineAssets; rm -rf $A; mkdir -p $A/clips
  cp $2/*.mp4 $A/clips/
  cp -R ../../ios/Runner/NativePose/Models/rtmpose_s_forward.mlpackage ${@:3} $A/
  [[ -n $BPT_MP_DIR ]] && cp $BPT_MP_DIR/pose_landmarker_*.task $BPT_MP_DIR/frame.jpg $A/
  xcodegen generate -q
  pod install --silent
  UDID=${BPT_DEVICE_UDID:-$(xcrun xctrace list devices 2>/dev/null | grep -m1 -oE '\(000[0-9A-F-]+\)' | tr -d '()')}
  xcodebuild build -workspace PoseModelBench.xcworkspace -scheme PoseModelBenchHost -configuration Release \
    -destination "id=$UDID" -derivedDataPath $DD DEVELOPMENT_TEAM=${BPT_TEAM:-7W525J2XTN} -allowProvisioningUpdates -quiet
  xcrun devicectl device install app --device $DEV $DD/Build/Products/Release-iphoneos/PoseModelBenchHost.app
  exit
fi
if [[ $1 == mp ]]; then
  ENV=$(python3 -c "import json,sys; print(json.dumps(dict(zip(['BENCH_MP','BENCH_MP_MODEL','BENCH_MP_DELEGATE','BENCH_SECONDS','BENCH_COOLDOWN'], sys.argv[1:]), BENCH_PIPELINE='1')))" \
    $2 ${3:-pose_landmarker_full} ${4:-gpu} ${5:-150} ${6:-0})
  xcrun devicectl device process launch --console --terminate-existing --environment-variables "$ENV" \
    --device $DEV com.bpt.posebench.PoseModelBenchHost 2>&1 | grep --line-buffered BENCH
  exit
fi
case $1 in
  a) V='{}' ;;
  b) V='{"BENCH_RECORD":"1"}' ;;
  c) V='{"BENCH_3D":"1"}' ;;
  d) V='{"BENCH_MODEL":"rtmpose_m_forward"}' ;;
  f) V='{"BENCH_MODEL":"rtmpose_m_halpe26_forward"}' ;;
  e) V="{\"BENCH_MODEL\":\"pose_landmarker_full\",\"BENCH_MP_DELEGATE\":\"${BPT_MP_DELEGATE:-gpu}\"}" ;;
  *) echo "variant a|b|c|d|e|f"; exit 2 ;;
esac
ENV=$(python3 -c "import json,os,sys; v=json.loads(sys.argv[1]); v.update(json.loads(os.environ.get('BENCH_EXTRA','{}'))); v.update(BENCH_PIPELINE='1', BENCH_PACED='1' if sys.argv[2]=='paced' else '0', BENCH_SECONDS=sys.argv[3], BENCH_COOLDOWN=sys.argv[4]); print(json.dumps(v))" "$V" $2 ${3:-180} ${4:-60})
xcrun devicectl device process launch --console --terminate-existing --environment-variables "$ENV" \
  --device $DEV com.bpt.posebench.PoseModelBenchHost 2>&1 | grep --line-buffered BENCH
