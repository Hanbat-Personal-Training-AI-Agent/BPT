// pose-replay: feeds a recorded workout video through the app's workout pose path on macOS
// (whole frame stretched to 192×256 like PosePreprocess.preprocessFullImageFast, RTMPose-s,
// SimCCDecoder, then SquatEvaluator / PushUpEvaluator / BarbellRowEvaluator with their
// FormWarningTracker — all symlinked from ios/Runner) to tune the form-warning thresholds.
//
//   swift run -c release --package-path ios/CalibrationEngineKit pose-replay \
//       [--exercise squat|pushup|row] [--model coco17|halpe26] [--motion3d PATH|none] [--lookahead N] \
//       [--row-shrug] [--output-dir PATH] <video.mp4>...
//
// halpe26 also feeds the decoded toes/heels to SquatEvaluator (squat_heel_rise). --row-shrug turns on
// the experimental row_shrug rule (off in the app).
//
// --motion3d: MotionAGFormer-XS Core ML package (default <repo>/assets/coreml/motionagformer_xs.mlpackage
// if present). With it every frame also gets selected3D (27-frame window, `lookahead` future frames,
// person_crop input like the app); 3D metrics are logged and "3D 불량" frames counted, warnings stay 2D.
//
// Writes <video>_<exercise>_<model>.json (per rep: index, start/end frame and time, 2D/3D metrics,
// warnings with grades, the spoken key, bad-3D frames; every onFeedback event; session totals) and <video>_<exercise>_<model>.csv (status, rep and
// every decoded keypoint per frame).
import AVFoundation
import CoreImage
import CoreML
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
var outputDir = repoRoot.appendingPathComponent("outputs/pose_replay")
var poseModel = RTMPoseModel.active
var exercise = FormExercise.squat
var motion3DPath: String? = {
    let path = repoRoot.appendingPathComponent("assets/coreml/motionagformer_xs.mlpackage").path
    return FileManager.default.fileExists(atPath: path) ? path : nil
}()
var lookahead = 5
var rowShrug = false
var videos: [URL] = []
var arguments = CommandLine.arguments.dropFirst().makeIterator()
let usage = "usage: pose-replay [--exercise squat|pushup|row] [--model coco17|halpe26] [--motion3d PATH|none] [--lookahead N] [--row-shrug] [--output-dir PATH] <video.mp4>..."
while let argument = arguments.next() {
    switch argument {
    case "--model":
        guard let name = arguments.next(),
              let picked = RTMPoseModel.allCases.first(where: { "\($0)" == name }) else {
            print("--model requires coco17 or halpe26")
            exit(2)
        }
        poseModel = picked
    case "--exercise":
        switch arguments.next() {
        case "squat": exercise = .squat
        case "pushup": exercise = .pushUp
        case "row": exercise = .barbellRow
        default:
            print("--exercise requires squat, pushup or row")
            exit(2)
        }
    case "--motion3d":
        guard let path = arguments.next() else { exit(2) }
        motion3DPath = path == "none" ? nil : path
    case "--lookahead":
        guard let value = arguments.next().flatMap(Int.init), (0..<27).contains(value) else { exit(2) }
        lookahead = value
    case "--row-shrug":
        rowShrug = true
    case "--output-dir":
        guard let path = arguments.next() else { exit(2) }
        outputDir = URL(fileURLWithPath: path, isDirectory: true)
    default:
        videos.append(URL(fileURLWithPath: argument))
    }
}
guard !videos.isEmpty else {
    print(usage)
    exit(2)
}
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func loadModel(_ url: URL) throws -> MLModel {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    return try MLModel(contentsOf: try MLModel.compileModel(at: url), configuration: configuration)
}

let model = try loadModel(repoRoot.appendingPathComponent("ios/Runner/NativePose/Models/\(poseModel.rawValue).mlpackage"))
let motion3D = try motion3DPath.map { try loadModel(URL(fileURLWithPath: $0)) }
let context = CIContext(options: [.cacheIntermediates: false])
let workspace = try RTMPoseInputWorkspace()
let inputWidth = PoseCoordinateTransforms.rtmposeInputWidth
let inputHeight = PoseCoordinateTransforms.rtmposeInputHeight
let window = 27

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

/// selected3D per frame: window of frames [i + lookahead - 26, i + lookahead] (edge-clamped), output
/// row 26 - lookahead; mirrors pose_feedback/body/live_motionagformer.py.
func lift3D(_ coco17: [[PoseKeypoint]], width: Int, height: Int, model: MLModel) throws -> [[SIMD3<Double>]] {
    var normalizer = MotionAGFormerInputNormalizer()
    let frames = try coco17.map {
        try PoseCoordinateTransforms.normalizedMotionAGFormerFrame(fromCOCO17: $0, imageWidth: width,
                                                                   imageHeight: height, normalizer: &normalizer)
    }
    let input = try MLMultiArray(shape: [1, NSNumber(value: window), 17, 3], dataType: .float32)
    let pointer = input.dataPointer.bindMemory(to: Float.self, capacity: window * 17 * 3)
    return try frames.indices.map { i in
        for t in 0..<window {
            let source = frames[min(max(i + lookahead - (window - 1) + t, 0), frames.count - 1)]
            for j in 0..<17 { for c in 0..<3 { pointer[(t * 17 + j) * 3 + c] = source[j][c] } }
        }
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_2d_sequence": input]))
        let pred = output.featureValue(for: "pred_3d_sequence")!.multiArrayValue!
        let row = NSNumber(value: window - 1 - lookahead)
        return (0..<17).map { j in
            SIMD3((0..<3).map { pred[[0, row, NSNumber(value: j), NSNumber(value: $0)]].doubleValue })
        }
    }
}

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

    // Pass 1: 2D keypoints for every frame.
    var coco17Frames: [[PoseKeypoint]] = []
    var extraFrames: [[PoseKeypoint]] = []
    var feetFrames: [FootKeypoints?] = []
    var times: [Double] = []
    var imageWidth = 0, imageHeight = 0
    while let sampleBuffer = output.copyNextSampleBuffer() {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { continue }
        imageWidth = cgImage.width
        imageHeight = cgImage.height
        drawResized(cgImage)
        try PosePreprocess.normalizeRGBAIntoRTMPoseInput(workspace.pixels, input: workspace.input,
                                                          width: inputWidth, height: inputHeight)
        let prediction = try model.prediction(from: workspace.provider)
        let decoded = try SimCCDecoder.decodeToInputCoordinates(
            simccX: prediction.featureValue(for: "simcc_x")!.multiArrayValue!,
            simccY: prediction.featureValue(for: "simcc_y")!.multiArrayValue!)
        let back = Affine2x3(a: Double(cgImage.width) / Double(inputWidth), b: 0, c: 0,
                             d: 0, e: Double(cgImage.height) / Double(inputHeight), f: 0)
        coco17Frames.append(PoseCoordinateTransforms.applyInverseAffine(decoded: decoded, inverseAffine: back))
        extraFrames.append(zip(decoded.extraInputCoordinates, decoded.extraConfidences).map { point, confidence in
            let p = back.apply(point)
            return PoseKeypoint(x: p.x, y: p.y, confidence: confidence)
        })
        feetFrames.append(PoseCoordinateTransforms.applyInverseAffineToFeet(decoded: decoded, inverseAffine: back))
        times.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
    }

    // Pass 2: 3D (optional).
    let pose3D = try motion3D.map { try lift3D(coco17Frames, width: imageWidth, height: imageHeight, model: $0) }

    // Pass 3: evaluator + form tracker, frame by frame like the app.
    let tracker: FormWarningTracker
    let step: (Int, [PoseKeypoint], [SIMD3<Double>]?, FootKeypoints?) -> (status: String, rep: Int)
    switch exercise {
    case .squat:
        let evaluator = SquatEvaluator()
        tracker = evaluator.formTracker
        step = { let r = evaluator.evaluate(frameIndex: $0, coco17: $1, pose3D: $2, feet: $3); return (r.status.rawValue, r.rep) }
    case .pushUp:
        let evaluator = PushUpEvaluator()
        tracker = evaluator.formTracker
        step = { i, k, p, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k, pose3D: p); return (r.status.rawValue, r.rep) }
    case .barbellRow:
        let evaluator = BarbellRowEvaluator()
        tracker = evaluator.formTracker
        tracker.row.shrugEnabled = rowShrug
        step = { i, k, p, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k, pose3D: p); return (r.status.rawValue, r.rep) }
    }
    var csv = "frame,time,status,rep," + (0..<(17 + (extraFrames.first?.count ?? 0)))
        .map { "j\($0)_x,j\($0)_y,j\($0)_c" }.joined(separator: ",") + "\n"
    var transitions: [String] = []
    var lastStatus: String?
    var events: [[String: Any]] = []
    var rep = 0
    for i in coco17Frames.indices {
        let result = step(i, coco17Frames[i], pose3D?[i], feetFrames[i])
        rep = result.rep
        for event in tracker.drainEvents() {
            var entry: [String: Any] = ["frame": i, "time": times[i], "key": event.key, "silent": event.silent]
            if let n = event.n { entry["n"] = n }
            events.append(entry)
        }
        if result.status != lastStatus {
            transitions.append("\(i):\(result.status)")
            lastStatus = result.status
        }
        csv += ([String(i), f(times[i]), result.status, String(result.rep)]
                + (coco17Frames[i] + extraFrames[i]).flatMap { [f($0.x), f($0.y), f($0.confidence)] })
            .joined(separator: ",") + "\n"
    }

    let reps: [[String: Any]] = tracker.reports.map { report in
        var entry = report.dictionary
        entry["start_time"] = times.indices.contains(report.startFrame) ? times[report.startFrame] : NSNull()
        entry["end_time"] = times.indices.contains(report.endFrame) ? times[report.endFrame] : NSNull()
        return entry
    }
    let json: [String: Any] = [
        "video": video.path,
        "exercise": exercise.rawValue,
        "model": "\(poseModel)",
        "motion3d": motion3DPath.map { $0 as Any } ?? NSNull(),
        "lookahead": lookahead,
        "frames": coco17Frames.count,
        "image_size": [imageWidth, imageHeight],
        "reps": reps,
        "session": [
            "rep_count": rep,
            "frames_3d": tracker.sessionFrames3D,
            "bad_3d_frames": tracker.sessionBad3DFrames,
            "warning_rep_counts": tracker.warningRepCounts,
        ],
        "transitions": transitions,
        "events": events,
    ]
    let base = "\(name)_\(exercise.rawValue)_\(poseModel)"
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        .write(to: outputDir.appendingPathComponent("\(base).json"))
    try csv.write(to: outputDir.appendingPathComponent("\(base).csv"), atomically: true, encoding: .utf8)

    print("== \(name) exercise=\(exercise.rawValue) model=\(poseModel) frames=\(coco17Frames.count) reps=\(rep) "
          + "3d=\(motion3D != nil) bad3d=\(tracker.sessionBad3DFrames)/\(tracker.sessionFrames3D)")
    print("  transitions: " + transitions.joined(separator: " "))
    for report in tracker.reports {
        let m2 = report.metrics2D.sorted { $0.key < $1.key }.map { "\($0.key)=\(f($0.value))" }.joined(separator: " ")
        let m3 = report.metrics3D.sorted { $0.key < $1.key }.map { "\($0.key)=\(f($0.value))" }.joined(separator: " ")
        print("  rep \(report.repIndex): frames \(report.startFrame)–\(report.endFrame) side=\(report.side) "
              + "bad3d=\(report.bad3DFrames)/\(report.frames3D) warnings=\(report.warnings) spoken=\(report.spoken ?? "-")")
        print("    2d: \(m2)")
        print("    3d: \(m3)")
    }
    print("  -> \(outputDir.appendingPathComponent(base).path).json")
}
