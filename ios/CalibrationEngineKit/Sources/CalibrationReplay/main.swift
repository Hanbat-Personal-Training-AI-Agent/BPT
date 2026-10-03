// calibration-replay: feeds a recorded video through the app's own calibration code
// (CalibrationFrameAnalyzer + CalibrationEngine, symlinked from ios/Runner) on macOS.
//
//   swift run -c release --package-path ios/CalibrationEngineKit calibration-replay [--lenient-pose] <video.mp4>...
//
// --lenient-pose widens only the A-pose and stance-width gates, for footage of people who were
// not following BPT's pose instructions; view classification and everything else stay as shipped.
//
// Only the camera and CoreMotion are replaced: frames come from the file in order and the
// phone is assumed upright and still. For every video it prints what the user would be told
// over time and which views got captured, writes a per-frame CSV and the captured frames to
// outputs/calibration_replay/.
import AVFoundation
import CoreImage
import CoreML
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let outputDir = repoRoot.appendingPathComponent("outputs/calibration_replay")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let arguments = CommandLine.arguments.dropFirst()
let lenientPose = arguments.contains("--lenient-pose")
let videos = arguments.filter { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
guard !videos.isEmpty else {
    print("usage: calibration-replay [--lenient-pose] <video.mp4>...")
    exit(2)
}

let modelURL = repoRoot.appendingPathComponent("ios/Runner/NativePose/Models/rtmpose_s_forward.mlpackage")
let configuration = MLModelConfiguration()
configuration.computeUnits = .all
let model = try MLModel(contentsOf: try MLModel.compileModel(at: modelURL), configuration: configuration)
let context = CIContext(options: [.cacheIntermediates: false])
var config = CalibrationConfig.default
if lenientPose {
    config.aPose.minWristDrop = 0.5
    config.aPose.maxWristDrop = 1.15
    config.aPose.minWristReach = 0.2
    config.aPose.minAnkleGapOverHipWidth = 0.5
}

func writeJPEG(_ image: CIImage, to url: URL) {
    guard let cgImage = context.createCGImage(image, from: image.extent),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, cgImage, nil)
    CGImageDestinationFinalize(destination)
}

func f(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "" }

for video in videos {
    let name = video.deletingPathExtension().lastPathComponent
    let asset = AVURLAsset(url: video)
    guard let track = asset.tracks(withMediaType: .video).first else {
        print("\(name): no video track")
        continue
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    reader.add(output)
    reader.startReading()

    let analyzer = CalibrationFrameAnalyzer(model: model, context: context,
                                            minConfidence: config.framing.minKeypointConfidence)
    let engine = CalibrationEngine(config: config)
    var csv = "t,guidance,classified,target,hold,pass,faceDetected,faceYaw,r,delta,bodyH,midX,feet,"
        + "wristDropL,wristDropR,elbowL,elbowR,wristReach,ankleGap,meanConf\n"
    var timeline: [(start: Double, end: Double, guidance: String)] = []
    var captures: [(view: CalibrationView, t: Double)] = []

    while let sampleBuffer = output.copyNextSampleBuffer() {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let analysis = try? analyzer.analyze(image) else { continue }
        let width = Double(analysis.imageSize.width), height = Double(analysis.imageSize.height)
        let result = engine.process(CalibrationFrame(
            keypoints: analysis.keypoints.map { CalibrationKeypoint(x: $0.x / width, y: $0.y / height, score: $0.confidence) },
            aspect: width / height, timestamp: t, device: .still, face: analysis.face))

        if let capture = result.capture {
            captures.append((capture.view, t))
            writeJPEG(image, to: outputDir.appendingPathComponent("\(name)_\(capture.view.rawValue).jpg"))
        }
        let message = result.guidance.message
        if let last = timeline.last, last.guidance == message {
            timeline[timeline.count - 1].end = t
        } else {
            timeline.append((t, t, message))
        }
        let m = result.measurement
        let r = m.flatMap { engine.rValue($0) }, delta = m.flatMap { engine.delta($0) }
        csv += [f(t), "\"\(message)\"", result.classifiedView?.rawValue ?? "", result.targetView?.rawValue ?? "",
                f(result.holdProgress), result.isPassing ? "1" : "0", analysis.face.isDetected ? "1" : "0",
                f(analysis.face.yawDeg), f(r), f(delta), f(m?.bodyHeight), f(m?.midX), f(m?.feet),
                f(m?.leftWristDrop), f(m?.rightWristDrop), f(m?.leftElbowRatio), f(m?.rightElbowRatio),
                f(m?.wristReach), f(m?.ankleGapOverHipWidth), f(m?.meanRequiredConfidence)]
            .joined(separator: ",") + "\n"
    }
    try csv.write(to: outputDir.appendingPathComponent("\(name).csv"), atomically: true, encoding: .utf8)

    print("== \(name)")
    for span in timeline where span.end - span.start >= 0.3 || timeline.count < 40 {
        print(String(format: "  %5.2f–%5.2fs  %@", span.start, span.end, span.guidance))
    }
    print("  captured: " + (captures.isEmpty ? "none"
        : captures.map { String(format: "%@ @%.2fs", $0.view.rawValue, $0.t) }.joined(separator: ", ")))
    print("  finished: \(engine.isFinished)")
}
