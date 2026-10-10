// swift-tools-version:5.9
// On-device Core ML latency of RTMPose candidates without a camera or a person in front of it:
// copy *.mlpackage into Tests/PoseModelBenchTests/Models/ (git-ignored), then
//   xcodebuild test -scheme PoseModelBench -destination 'platform=iOS,id=<device>' DEVELOPMENT_TEAM=<team> -allowProvisioningUpdates
// and grep "BENCH" in the log.
import PackageDescription

let package = Package(
    name: "PoseModelBench",
    platforms: [.iOS(.v16), .macOS(.v13)],
    targets: [
        .testTarget(name: "PoseModelBenchTests", resources: [.copy("Models")]),
    ]
)
