// pose-replay: feeds a recorded squat video through the app's workout pose path on macOS
// (whole frame stretched to 192×256 like PosePreprocess.preprocessFullImageFast, RTMPose-s,
// SimCCDecoder, SquatEvaluator — all symlinked from ios/Runner) so two RTMPose models can be
// compared on the same footage.
//
//   swift run -c release --package-path ios/CalibrationEngineKit pose-replay [--model coco17|halpe26] [--output-dir PATH] <video.mp4>...
//
// Prints the squat reps and stable-status transitions and writes <name>_<model>.csv with the
// evaluator state and every decoded keypoint (17, or 26 for Halpe26) per frame.
import AVFoundation
import CoreImage
import CoreML
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
var outputDir = repoRoot.appendingPathComponent("outputs/pose_replay")
var poseModel = RTMPoseModel.active
var videos: [URL] = []
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--model":
        guard let name = arguments.next(),
              let picked = RTMPoseModel.allCases.first(where: { "\($0)" == name }) else {
            print("--model requires coco17 or halpe26")
            exit(2)
        }
        poseModel = picked
    case "--output-dir":
        guard let path = arguments.next() else { exit(2) }
        outputDir = URL(fileURLWithPath: path, isDirectory: true)
    default:
        videos.append(URL(fileURLWithPath: argument))
    }
}
guard !videos.isEmpty else {
    print("usage: pose-replay [--model coco17|halpe26] [--output-dir PATH] <video.mp4>...")
    exit(2)
}
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let modelURL = repoRoot.appendingPathComponent("ios/Runner/NativePose/Models/\(poseModel.rawValue).mlpackage")
let configuration = MLModelConfiguration()
configuration.computeUnits = .all
let model = try MLModel(contentsOf: try MLModel.compileModel(at: modelURL), configuration: configuration)
let context = CIContext(options: [.cacheIntermediates: false])
let workspace = try RTMPoseInputWorkspace()
let inputWidth = PoseCoordinateTransforms.rtmposeInputWidth
let inputHeight = PoseCoordinateTransforms.rtmposeInputHeight

/// Same bitmap draw as PosePreprocess.drawResizedRGBA (UIKit-free copy).
func drawResized(_ image: CGImage) {
    workspace.pixels.withUnsafeMutableBytes { buffer in
        let bitmap = CGContext(data: buffer.baseAddress, width: inputWidth, height: inputHeight,
                               bitsPerComponent: 8, bytesPerRow: inputWidth * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        bitmap.interpolationQuality = .high
        bitmap.setBlendMode(.copy)
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight))
    }
}

func f(_ value: Double?) -> String { value.map { String(format: "%.4f", $0) } ?? "" }

for video in videos {
    let name = video.deletingPathExtension().lastPathComponent
    let asset = AVURLAsset(url: video)
    guard let track = asset.tracks(withMediaType: .video).first else { continue }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    reader.add(output)
    reader.startReading()

    let evaluator = SquatEvaluator()
    var csv = ""
    var transitions: [String] = []
    var lastStatus: SquatStatus?
    var frameIndex = -1
    var lastResult: SquatFrameResult?
    while let sampleBuffer = output.copyNextSampleBuffer() {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { continue }
        frameIndex += 1
        drawResized(cgImage)
        try PosePreprocess.normalizeRGBAIntoRTMPoseInput(workspace.pixels, input: workspace.input,
                                                          width: inputWidth, height: inputHeight)
        let prediction = try model.prediction(from: workspace.provider)
        let decoded = try SimCCDecoder.decodeToInputCoordinates(
            simccX: prediction.featureValue(for: "simcc_x")!.multiArrayValue!,
            simccY: prediction.featureValue(for: "simcc_y")!.multiArrayValue!)
        let back = Affine2x3(a: Double(cgImage.width) / Double(inputWidth), b: 0, c: 0,
                             d: 0, e: Double(cgImage.height) / Double(inputHeight), f: 0)
        let coco17 = PoseCoordinateTransforms.applyInverseAffine(decoded: decoded, inverseAffine: back)
        let extra = zip(decoded.extraInputCoordinates, decoded.extraConfidences).map { point, confidence in
            let p = back.apply(point)
            return PoseKeypoint(x: p.x, y: p.y, confidence: confidence)
        }
        let result = evaluator.evaluate(frameIndex: frameIndex, coco17: coco17)
        lastResult = result
        if result.status != lastStatus {
            transitions.append("\(frameIndex):\(result.status.rawValue)")
            lastStatus = result.status
        }
        if csv.isEmpty {
            csv = "frame,status,rep,depth,knee_angle," + (0..<(coco17.count + extra.count))
                .map { "j\($0)_x,j\($0)_y,j\($0)_c" }.joined(separator: ",") + "\n"
        }
        csv += ([String(frameIndex), result.status.rawValue, String(result.rep),
                 f(result.squatDepthNorm), f(result.avgKneeAngleDegrees)]
                + (coco17 + extra).flatMap { [f($0.x), f($0.y), f($0.confidence)] })
            .joined(separator: ",") + "\n"
    }
    try csv.write(to: outputDir.appendingPathComponent("\(name)_\(poseModel).csv"), atomically: true, encoding: .utf8)
    print("== \(name) model=\(poseModel) frames=\(frameIndex + 1) reps=\(lastResult?.rep ?? 0)")
    print("  transitions: " + transitions.joined(separator: " "))
    for rep in evaluator.completedRepSummaries {
        print("  rep \(rep.repIndex): frames \(rep.startFrame)–\(rep.endFrame ?? -1) bottom=\(rep.bottomFrame ?? -1) "
              + "maxDepth=\(f(rep.maxDepthNorm)) minKnee=\(f(rep.minKneeAngleDegrees)) warnings=\(rep.warnings)")
    }
}
