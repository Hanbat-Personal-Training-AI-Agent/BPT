// calibration-replay: feeds a recorded video through the app's own calibration code
// (CalibrationFrameAnalyzer + CalibrationEngine, symlinked from ios/Runner) on macOS.
//
//   swift run -c release --package-path ios/CalibrationEngineKit calibration-replay [--lenient-pose] [--overlay]
//       [--output-dir PATH] [--user-height-cm CM] [--intrinsics fx,fy,cx,cy] <video.mp4>...
//
// Captures are written exactly as the app writes them (CalibrationStore, same best-of-hold frame
// choice as CalibrationSession) to session_<name>/: view_*.jpg + manifest.json, ready to upload.
// A file has no user height or camera: --user-height-cm (default 170) is a test value, and
// --intrinsics sets the pinhole camera of the video in pixels (source "attachment"); without it
// the manifest gets the app's no-camera fallback (fx = fy = 0, centre, "fov_estimate").
//
// --overlay also writes overlay_<name>.mp4: keypoints, the RTMPose crop, the face box, every gate
// with its value and limits, and the engine's final decision drawn on each frame.
//
// --lenient-pose widens only the A-pose and stance-width gates, for footage of people who were
// not following BPT's pose instructions; view classification and everything else stay as shipped.
//
// Only the camera and CoreMotion are replaced: frames come from the file in order and the
// phone is assumed upright and still. For every video it prints what the user would be told
// over time and which views got captured, writes a per-frame CSV and the captured frames to
// outputs/calibration_replay/. The CSV also carries the raw measurements, the analysis time and,
// for comparison, the keypoint confidence of the old full-frame stretch preprocessing.
import AVFoundation
import CoreImage
import CoreML
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
var outputDir = repoRoot.appendingPathComponent("outputs/calibration_replay")
var lenientPose = false
var drawOverlayVideo = false
var userHeightCm = 170.0
var videoIntrinsics: CalibrationStore.Intrinsics?
var videos: [URL] = []
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--lenient-pose": lenientPose = true
    case "--overlay": drawOverlayVideo = true
    case "--output-dir":
        guard let path = arguments.next(), !path.hasPrefix("--") else {
            print("--output-dir requires a directory path")
            exit(2)
        }
        outputDir = URL(fileURLWithPath: path, isDirectory: true)
    case "--user-height-cm":
        guard let value = arguments.next().flatMap(Double.init), value > 0 else {
            print("--user-height-cm requires a positive number")
            exit(2)
        }
        userHeightCm = value
    case "--intrinsics":
        let values = (arguments.next() ?? "").split(separator: ",").compactMap { Double($0) }
        guard values.count == 4, values[0] > 0, values[1] > 0 else {
            print("--intrinsics requires fx,fy,cx,cy in pixels")
            exit(2)
        }
        videoIntrinsics = CalibrationStore.Intrinsics(fx: values[0], fy: values[1], cx: values[2], cy: values[3],
                                                      source: "attachment")
    default:
        guard !argument.hasPrefix("--") else {
            print("unknown option: \(argument)")
            exit(2)
        }
        videos.append(URL(fileURLWithPath: argument))
    }
}
guard !videos.isEmpty else {
    print("usage: calibration-replay [--lenient-pose] [--overlay] [--output-dir PATH] <video.mp4>...")
    exit(2)
}
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

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

/// UIImage.jpegData(compressionQuality:) as the app calls it, via ImageIO.
func jpegData(_ image: CGImage, quality: Double) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
}

/// CalibrationSession.SelectedFrame: the best-confidence frame of the current hold.
struct SelectedFrame {
    let image: CGImage
    let snapshot: CalibrationStore.Snapshot
    let holdStartedAt: TimeInterval
}

func f(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "" }

/// The pre-overhaul path for comparison: whole frame squeezed into 192×256 regardless of aspect.
func stretchedPoseScores(_ image: CIImage) throws -> [Double] {
    let size = image.extent.size
    let scaled = image.applyingFilter("CILanczosScaleTransform", parameters: [
        kCIInputScaleKey: 256 / size.height,
        kCIInputAspectRatioKey: (192 / size.width) / (256 / size.height),
    ])
    var pixels = [UInt8](repeating: 0, count: 192 * 256 * 4)
    pixels.withUnsafeMutableBytes { buffer in
        context.render(scaled, toBitmap: buffer.baseAddress!, rowBytes: 192 * 4,
                       bounds: CGRect(x: 0, y: 0, width: 192, height: 256), format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
    }
    let input = try PosePreprocess.makeRTMPoseInputArray()
    try PosePreprocess.normalizeRGBAIntoRTMPoseInput(pixels, input: input, width: 192, height: 256)
    let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_image": input]))
    let decoded = try SimCCDecoder.decodeToInputCoordinates(
        simccX: output.featureValue(for: "simcc_x")!.multiArrayValue!,
        simccY: output.featureValue(for: "simcc_y")!.multiArrayValue!)
    return decoded.confidences
}

func meanRequired(_ scores: [Double]) -> Double {
    CocoJoint.required.map { scores[$0.rawValue] }.reduce(0, +) / Double(CocoJoint.required.count)
}

func allRequired(_ scores: [Double]) -> Bool {
    CocoJoint.required.allSatisfy { scores[$0.rawValue] >= config.framing.minKeypointConfidence }
}

for video in videos {
    // v1 and v2 fixtures share file names, so keep the folder in the output name.
    let folder = video.deletingLastPathComponent().lastPathComponent
    let name = (folder == "calibration_dummy_videos" ? "" : folder + "__") + video.deletingPathExtension().lastPathComponent
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

    let analyzer = try CalibrationFrameAnalyzer(model: model, context: context,
                                            minConfidence: config.framing.minKeypointConfidence)
    let engine = CalibrationEngine(config: config)
    let sessionRoot = outputDir.appendingPathComponent("session_\(name)", isDirectory: true)
    try? FileManager.default.removeItem(at: sessionRoot)
    let store = try CalibrationStore(sessionId: "replay_" + name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-",
                                                                                      options: .regularExpression),
                                     rootDirectory: sessionRoot)
    var bestHoldFrame: SelectedFrame?
    var csv = "i,t,guidance,classified,target,hold,pass,faceDetected,faceYaw,r,delta,bodyH,midX,feet,"
        + "wristDropL,wristDropR,elbowL,elbowR,wristReach,ankleGap,meanConf,"
        + "swT,hwT,nose,rtmFace,earL,earR,analyzeMs,cropMeanReq,cropAllReq,stretchMeanReq,stretchAllReq,"
        + "lrShoulder,lrHip,captured,guideH,guideMinH,guideMaxH,guideCentreTol,aspect\n"
    var frameIndex = -1
    let overlay = drawOverlayVideo
        ? try OverlayVideoWriter(url: outputDir.appendingPathComponent("overlay_\(name).mp4"),
                                 size: track.naturalSize, context: context)
        : nil
    var flash: (view: CalibrationView, until: Double)?
    var timeline: [(start: Double, end: Double, guidance: String)] = []
    var captures: [(view: CalibrationView, t: Double)] = []

    while let sampleBuffer = output.copyNextSampleBuffer() {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        frameIndex += 1
        let started = CFAbsoluteTimeGetCurrent()
        guard let analysis = try? analyzer.analyze(image) else { engine.invalidateFrame(); continue }
        let analyzeMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
        let cropScores = analysis.keypoints.map(\.confidence)
        let stretchScores = try stretchedPoseScores(image)
        let width = Double(analysis.imageSize.width), height = Double(analysis.imageSize.height)
        let calibrationFrame = CalibrationFrame(
            keypoints: analysis.keypoints.map { CalibrationKeypoint(x: $0.x / width, y: $0.y / height, score: $0.confidence) },
            aspect: width / height, timestamp: t, device: .still, face: analysis.face)
        var result = engine.process(calibrationFrame)

        // CalibrationSession.trackBestFrame
        if result.isPassing, let measurement = result.measurement, let holdStartedAt = result.holdStartedAt {
            if !(bestHoldFrame.map { $0.holdStartedAt == holdStartedAt
                    && $0.snapshot.measurement.meanRequiredConfidence >= measurement.meanRequiredConfidence } ?? false),
               let cgImage = context.createCGImage(image, from: image.extent) {
                let w = Double(cgImage.width), h = Double(cgImage.height)
                bestHoldFrame = SelectedFrame(image: cgImage, snapshot: CalibrationStore.Snapshot(
                    frame: calibrationFrame, measurement: measurement, imageWidth: cgImage.width,
                    imageHeight: cgImage.height,
                    intrinsics: videoIntrinsics ?? CalibrationStore.Intrinsics(cx: w / 2, cy: h / 2)),
                    holdStartedAt: holdStartedAt)
            }
        } else if result.capture == nil {
            bestHoldFrame = nil
        }

        if let capture = result.capture {
            // CalibrationSession.writeCapture
            var saved = false
            if let chosen = bestHoldFrame, chosen.holdStartedAt == capture.holdStartedAt,
               chosen.snapshot.frame.timestamp >= capture.holdStartedAt,
               let jpeg = jpegData(chosen.image, quality: config.capture.jpegQuality) {
                let record = CalibrationStore.ViewRecord(
                    label: capture.view, snapshot: chosen.snapshot,
                    r: engine.rValue(chosen.snapshot.measurement, relativeTo: capture.reference),
                    delta: engine.delta(chosen.snapshot.measurement, relativeTo: capture.reference))
                do {
                    try store.writeCapture(jpeg: jpeg, record: record, userHeightCm: userHeightCm,
                                           reference: capture.reference)
                    saved = true
                } catch {
                    print("capture persistence failed: \(error)")
                }
            }
            bestHoldFrame = nil
            if let resolved = engine.resolveCapture(id: capture.id, saved: saved) { result = resolved }
            if saved { captures.append((capture.view, t)) }
        }
        let message = result.guidance.message
        if let last = timeline.last, last.guidance == message {
            timeline[timeline.count - 1].end = t
        } else {
            timeline.append((t, t, message))
        }
        let m = result.measurement
        let r = m.flatMap { engine.rValue($0) }, delta = m.flatMap { engine.delta($0) }
        if let overlay {
            if let capture = result.capture { flash = (capture.view, t + 1.0) }
            let state = OverlayState(
                t: t, size: overlay.size, keypoints: analysis.keypoints, crop: analysis.crop,
                faceBox: analysis.faceBox, face: analysis.face, result: result, reference: engine.reference,
                motion: engine.lastMotion, candidate: engine.viewCandidate(for: calibrationFrame),
                r: r, delta: delta, config: config, lenient: lenientPose,
                flash: flash.flatMap { t < $0.until ? $0.view : nil })
            overlay.append(image, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) { cg in
                drawOverlay(cg, state)
            }
        }
        csv += [String(frameIndex), f(t), "\"\(message)\"", result.classifiedView?.rawValue ?? "", result.targetView?.rawValue ?? "",
                f(result.holdProgress), result.isPassing ? "1" : "0", analysis.face.isDetected ? "1" : "0",
                f(analysis.face.yawDeg), f(r), f(delta), f(m?.bodyHeight), f(m?.midX), f(m?.feet),
                f(m?.leftWristDrop), f(m?.rightWristDrop), f(m?.leftElbowRatio), f(m?.rightElbowRatio),
                f(m?.wristReach), f(m?.ankleGapOverHipWidth), f(m?.meanRequiredConfidence),
                f(m.map { $0.shoulderWidth / $0.torso }), f(m.map { $0.hipWidth / $0.torso }), f(m?.noseOffset),
                f(m?.face), f(m?.earLeft), f(m?.earRight), f(analyzeMs),
                f(meanRequired(cropScores)), allRequired(cropScores) ? "1" : "0",
                f(meanRequired(stretchScores)), allRequired(stretchScores) ? "1" : "0",
                // anatomical left minus right, as a fraction of the frame width (sign = which side is where)
                f((analysis.keypoints[CocoJoint.leftShoulder.rawValue].x - analysis.keypoints[CocoJoint.rightShoulder.rawValue].x) / width),
                f((analysis.keypoints[CocoJoint.leftHip.rawValue].x - analysis.keypoints[CocoJoint.rightHip.rawValue].x) / width),
                result.capturedViews.map(\.rawValue).joined(separator: "|"),
                f(config.framing.guideBodyHeight), f(config.framing.minBodyHeight), f(config.framing.maxBodyHeight),
                f(config.framing.maxCentreOffset), f(width / height)]
            .joined(separator: ",") + "\n"
    }
    overlay?.finish()
    try csv.write(to: outputDir.appendingPathComponent("\(name).csv"), atomically: true, encoding: .utf8)

    print("== \(name)")
    for span in timeline where span.end - span.start >= 0.3 || timeline.count < 40 {
        print(String(format: "  %5.2f–%5.2fs  %@", span.start, span.end, span.guidance))
    }
    print("  captured: " + (captures.isEmpty ? "none"
        : captures.map { String(format: "%@ @%.2fs", $0.view.rawValue, $0.t) }.joined(separator: ", ")))
    print("  finished: \(engine.isFinished)")
    print("  bundle: \(store.directory.path)")
}
