// swift-tools-version: 5.9
import PackageDescription

// The calibration judging engine is pure Foundation, so it can be compiled and tested
// without the app. The sources here are symlinks to the files the Runner target builds:
// one copy of the code, two ways to build it.
//
// Run the tests with:  swift test --package-path ios/CalibrationEngineKit
// Replay a recorded video through the app's perception + engine (camera and CoreMotion aside):
//   swift run -c release --package-path ios/CalibrationEngineKit calibration-replay <video.mp4>...
// Replay a workout video through the workout pose path + evaluator + form warnings (JSON per rep):
//   swift run -c release --package-path ios/CalibrationEngineKit pose-replay [--exercise squat|pushup|row] [--model coco17|halpe26] [--motion3d PATH|none] <video.mp4>...
//
// (The Xcode RunnerTests target cannot run them: injecting a test bundle into the Flutter
// host app aborts inside MediaPipe's calculator registry, which also happens with the
// stock template test and is unrelated to this code.)
let package = Package(
    name: "CalibrationEngineKit",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CalibrationEngineKit"),
        .executableTarget(name: "calibration-replay", path: "Sources/CalibrationReplay"),
        .executableTarget(name: "pose-replay", path: "Sources/PoseReplay"),
        .testTarget(name: "CalibrationEngineKitTests", dependencies: ["CalibrationEngineKit"]),
    ]
)
