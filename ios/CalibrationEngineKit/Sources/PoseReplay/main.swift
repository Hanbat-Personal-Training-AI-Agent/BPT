// pose-replay: feeds a recorded workout video through the app's workout pose path on macOS
// (RTMPose input like CameraPosePreview: a 3:4 person crop from the previous frame's keypoints,
// whole frame stretched to 192×256 when the person is lost — `--input full` = always whole frame, the
// old input; RTMPose-s, SimCCDecoder, then SquatEvaluator / PushUpEvaluator / BarbellRowEvaluator with their
// FormWarningTracker — all symlinked from ios/Runner) to tune the form-warning thresholds.
//
//   swift run -c release --package-path ios/CalibrationEngineKit pose-replay \
//       [--exercise squat|pushup|row|bench|deadlift] [--model coco17|halpe26|mcoco17|mhalpe26] [--model-path PATH] [--motion3d PATH|none] [--lookahead N] \
//       [--row-shrug] [--side-cutoff R] [--row-offside off] [--pushup-ankle on|off] [--pushup-wrist-conf C] [--pushup-min-frames N] [--pushup-height on|off] [--squat-hold on|off] [--squat-near-leg on|off] [--squat-rebaseline N] [--squat-height on|off] [--squat-height-range R] [--ready-pose off|preset] [--input crop|full] [--crop-edge on|off] [--keypoints-csv PATH] [--keypoints-dir DIR] [--output-dir PATH] <video.mp4>...
//
// --crop-edge off: keep a crop whose border pins confident joints (RTMPoseCropTracker.refitAtCropEdge = false, old).
// --model-path: another RTMPose .mlpackage with the same 256x192 input and SimCC outputs (17 or 26 joints;
// pass --model halpe26 for 26) — candidate models are compared on the same videos without replacing the bundled one.
//
// halpe26 also feeds the decoded toes/heels to SquatEvaluator (heel_rise_max; squat_heel_rise is off). --row-shrug turns on
// the experimental row_shrug rule (off in the app). --side-cutoff: row/push-up side-view gate cutoff (shoulder width ÷
// torso length) instead of the app's value, to measure counting with the gate moved (e.g. 99 = gate off).
// --pushup-ankle / --pushup-wrist-conf / --pushup-min-frames / --pushup-height: PushUpEvaluatorConfig.requireAnkleForRep / wristMinJointConfidence / minRepFrames / heightRepSignal.
// --squat-hold / --squat-near-leg / --squat-rebaseline / --squat-height / --squat-height-range: SquatEvaluatorConfig.holdStatusThroughUnknown /
// nearLegFallback / rebaselineStraightLegFrames / heightRepSignal / heightCounter.minRange.
// --row-offside off: no row reps off the side view (old gate behaviour; BarbellRowEvaluatorConfig.countOffSideView).
//
// --keypoints-csv: skip decoding and RTMPose, read the 2D keypoints (j0..j16 x/y/c, extra columns
// ignored) from a CSV in the format this tool writes; the video path then only names the outputs (no 3D).
// --keypoints-dir: the same, per video from DIR/<video>_<exercise>_<model>.csv (many clips in one run, no model load).
// bench/deadlift: BenchPressEvaluator / DeadliftEvaluator (2D only; their bench_* / deadlift_* keys are off in the app).
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
var poseModel = RTMPoseModel.workout
var poseModelPath: String?
var exercise = FormExercise.squat
var keypointsCSV: String?
var keypointsDir: String?
var motion3DPath: String? = {
    let path = repoRoot.appendingPathComponent("assets/coreml/motionagformer_xs.mlpackage").path
    return FileManager.default.fileExists(atPath: path) ? path : nil
}()
var lookahead = 5
var rowShrug = false
var sideCutoff: Double?
var rowNonSide: String?
var pushUpAnkle: Bool?
var pushUpWristConf: Double?
var pushUpMinFrames: Int?
var pushUpHeight: Bool?
var squatHold: Bool?
var squatNearLeg: Bool?
var squatRebaseline: Int?
var squatHeight: Bool?
var squatHeightRange: Double?
var readyPosePreset = false
var personCrop = true
var cropEdgeRefit = true
var videos: [URL] = []
var arguments = CommandLine.arguments.dropFirst().makeIterator()
let usage = "usage: pose-replay [--exercise squat|pushup|row|bench|deadlift] [--model coco17|halpe26|mcoco17|mhalpe26] [--model-path PATH] [--motion3d PATH|none] [--lookahead N] [--row-shrug] [--side-cutoff R] [--row-offside off] [--pushup-ankle on|off] [--pushup-wrist-conf C] [--pushup-min-frames N] [--pushup-height on|off] [--squat-hold on|off] [--squat-near-leg on|off] [--squat-rebaseline N] [--squat-height on|off] [--squat-height-range R] [--ready-pose off|preset] [--input crop|full] [--crop-edge on|off] [--keypoints-csv PATH] [--keypoints-dir DIR] [--output-dir PATH] <video.mp4>..."
while let argument = arguments.next() {
    switch argument {
    case "--model":
        guard let name = arguments.next(),
              let picked = RTMPoseModel.allCases.first(where: { "\($0)" == name }) else {
            print("--model requires coco17, halpe26, mcoco17 or mhalpe26 (other packages: --model-path)")
            exit(2)
        }
        poseModel = picked
    case "--model-path":
        guard let path = arguments.next() else { exit(2) }
        poseModelPath = path
    case "--exercise":
        switch arguments.next() {
        case "squat": exercise = .squat
        case "pushup": exercise = .pushUp
        case "row": exercise = .barbellRow
        case "bench": exercise = .benchPress
        case "deadlift": exercise = .deadlift
        default:
            print("--exercise requires squat, pushup, row, bench or deadlift")
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
    case "--pushup-ankle":
        pushUpAnkle = arguments.next() != "off"
    case "--pushup-min-frames":
        pushUpMinFrames = arguments.next().flatMap(Int.init)
    case "--pushup-height":
        pushUpHeight = arguments.next() != "off"
    case "--squat-hold":
        squatHold = arguments.next() != "off"
    case "--squat-near-leg":
        squatNearLeg = arguments.next() != "off"
    case "--squat-height":
        squatHeight = arguments.next() != "off"
    case "--squat-height-range":
        squatHeightRange = arguments.next().flatMap(Double.init)
    case "--squat-rebaseline":
        squatRebaseline = arguments.next().flatMap(Int.init)
    case "--pushup-wrist-conf":
        pushUpWristConf = arguments.next().flatMap(Double.init)
    case "--row-offside":
        rowNonSide = arguments.next()
    case "--side-cutoff":
        guard let value = arguments.next().flatMap(Double.init) else { exit(2) }
        sideCutoff = value
    case "--ready-pose":
        switch arguments.next() {
        case "off": readyPosePreset = false
        case "preset": readyPosePreset = true
        default:
            print("--ready-pose requires off or preset")
            exit(2)
        }
    case "--input":
        switch arguments.next() {
        case "crop": personCrop = true
        case "full": personCrop = false
        default:
            print("--input requires crop or full")
            exit(2)
        }
    case "--crop-edge":
        cropEdgeRefit = arguments.next() != "off"
    case "--keypoints-csv":
        guard let path = arguments.next() else { exit(2) }
        keypointsCSV = path
    case "--keypoints-dir":
        guard let path = arguments.next() else { exit(2) }
        keypointsDir = path
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

let replayOnly = keypointsCSV != nil || keypointsDir != nil
let model = replayOnly ? nil : try loadModel(poseModelPath.map { URL(fileURLWithPath: $0) }
    ?? repoRoot.appendingPathComponent("ios/Runner/NativePose/Models/\(poseModel.rawValue).mlpackage"))
let motion3D = replayOnly ? nil : try motion3DPath.map { try loadModel(URL(fileURLWithPath: $0)) }
let context = CIContext(options: [.cacheIntermediates: false])
let workspace = try RTMPoseInputWorkspace()
let window = 27

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

var readers: [AVAssetReader] = []
for video in videos {
    let name = video.deletingPathExtension().lastPathComponent
    let keypointsCSV = keypointsCSV ?? keypointsDir.map { "\($0)/\(name)_\(exercise.rawValue)_\(poseModel).csv" }

    // Pass 1: 2D keypoints for every frame.
    var coco17Frames: [[PoseKeypoint]] = []
    var extraFrames: [[PoseKeypoint]] = []
    var feetFrames: [FootKeypoints?] = []
    var times: [Double] = []
    var imageWidth = 0, imageHeight = 0
    var cropTracker = RTMPoseCropTracker()
    cropTracker.refitAtCropEdge = cropEdgeRefit
    var fullFrameInputs = 0
    var rechecks = 0, switches = 0
    var poseSeconds = 0.0
    if let keypointsCSV {
        guard FileManager.default.fileExists(atPath: keypointsCSV) else { print("no keypoints: \(keypointsCSV)"); continue }
        for line in try String(contentsOfFile: keypointsCSV, encoding: .utf8).split(whereSeparator: \.isNewline).dropFirst() {
            let cells = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cells.count >= 4 + 17 * 3 else { continue }
            let v = cells.map { Double($0) ?? 0 }
            times.append(v[1])
            coco17Frames.append((0..<17).map { PoseKeypoint(x: v[4 + $0 * 3], y: v[5 + $0 * 3], confidence: v[6 + $0 * 3]) })
            extraFrames.append([])
            feetFrames.append(nil)
        }
    }
    let output: AVAssetReaderTrackOutput? = try {
        guard keypointsCSV == nil else { return nil }
        let asset = AVURLAsset(url: video)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        reader.startReading()
        readers.append(reader)  // must outlive the loop below
        return output
    }()
    guard keypointsCSV != nil || output != nil else { continue }
    while let sampleBuffer = output?.copyNextSampleBuffer() {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { continue }
        imageWidth = cgImage.width
        imageHeight = cgImage.height
        let poseStart = Date()
        if cropTracker.crop == nil { fullFrameInputs += 1 }
        // The live camera path's pose step (crop, RTMPose, decode, tracker, ~1 s whole-frame recheck).
        guard let model, let estimate = try cropTracker.estimate(cgImage, model: model, workspace: workspace, personCrop: personCrop) else {
            fatalError("model has no simcc_x / simcc_y outputs")
        }
        let decoded = estimate.decoded, back = estimate.inverseAffine, coco17 = estimate.coco17
        if let switched = estimate.recheckSwitched {
            rechecks += 1
            if switched { switches += 1 }
        }
        poseSeconds += Date().timeIntervalSince(poseStart)
        coco17Frames.append(coco17)
        extraFrames.append(zip(decoded.extraInputCoordinates, decoded.extraConfidences).map { point, confidence in
            let p = back.apply(point)
            return PoseKeypoint(x: p.x, y: p.y, confidence: confidence)
        })
        feetFrames.append(PoseCoordinateTransforms.applyInverseAffineToFeet(decoded: decoded, inverseAffine: back))
        times.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
    }

    // Pass 2: 3D (optional).
    let pose3D = keypointsCSV != nil ? nil : try motion3D.map { try lift3D(coco17Frames, width: imageWidth, height: imageHeight, model: $0) }

    // Pass 3: evaluator + form tracker, frame by frame like the app.
    let tracker: FormWarningTracker
    let step: (Int, [PoseKeypoint], [SIMD3<Double>]?, FootKeypoints?) -> (status: String, rep: Int)
    // --ready-pose preset: squat/row hold the start pose 0.5 s (scaled to this video's fps) before
    // the first rep; push-up stays off.
    let fps = times.count > 1 && times.last! > times.first! ? Double(times.count - 1) / (times.last! - times.first!) : 30
    switch exercise {
    case .squat:
        var config = SquatEvaluatorConfig()
        if readyPosePreset { config.applyReadyPosePreset(fps: fps) }
        if let squatHold { config.holdStatusThroughUnknown = squatHold }
        if let squatNearLeg { config.nearLegFallback = squatNearLeg }
        if let squatRebaseline { config.rebaselineStraightLegFrames = squatRebaseline }
        if let squatHeight { config.heightRepSignal = squatHeight }
        if let squatHeightRange { config.heightCounter.minRange = squatHeightRange }
        let evaluator = SquatEvaluator(config: config)
        tracker = evaluator.formTracker
        step = { let r = evaluator.evaluate(frameIndex: $0, coco17: $1, pose3D: $2, feet: $3); return (r.status.rawValue, r.rep) }
    case .pushUp:
        var config = PushUpEvaluatorConfig()
        if let pushUpAnkle { config.requireAnkleForRep = pushUpAnkle }
        if let pushUpWristConf { config.wristMinJointConfidence = pushUpWristConf }
        if let pushUpMinFrames { config.minRepFrames = pushUpMinFrames }
        if let pushUpHeight { config.heightRepSignal = pushUpHeight }
        let evaluator = PushUpEvaluator(config: config)
        tracker = evaluator.formTracker
        if let sideCutoff { tracker.pushUp.sideViewMaxShoulderRatio = sideCutoff }
        step = { i, k, p, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k, pose3D: p); return (r.status.rawValue, r.rep) }
    case .barbellRow:
        var config = BarbellRowEvaluatorConfig()
        if readyPosePreset { config.applyReadyPosePreset(fps: fps) }
        if rowNonSide == "off" { config.countOffSideView = false }
        let evaluator = BarbellRowEvaluator(config: config)
        tracker = evaluator.formTracker
        tracker.row.shrugEnabled = rowShrug
        if let sideCutoff { tracker.row.sideViewMaxShoulderRatio = sideCutoff }
        step = { i, k, p, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k, pose3D: p); return (r.status.rawValue, r.rep) }
    case .benchPress:
        let evaluator = BenchPressEvaluator()
        tracker = evaluator.formTracker
        step = { i, k, _, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k); return (r.status.rawValue, r.rep) }
    case .deadlift:
        let evaluator = DeadliftEvaluator()
        tracker = evaluator.formTracker
        step = { i, k, _, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k); return (r.status.rawValue, r.rep) }
    }
    // Every key on (the app sends none by default) so `spoken` and `events` show what would be said.
    tracker.common.enabledFeedbackKeys = FormWarningTracker.allKeys
    var csv = "frame,time,status,rep," + (0..<(17 + (extraFrames.first?.count ?? 0)))
        .map { "j\($0)_x,j\($0)_y,j\($0)_c" }.joined(separator: ",") + "\n"
    var transitions: [String] = []
    var lastStatus: String?
    var events: [[String: Any]] = []
    var rep = 0
    var repEndFrames: [Int] = []
    for i in coco17Frames.indices {
        let result = step(i, coco17Frames[i], pose3D?[i], feetFrames[i])
        if result.rep > rep { repEndFrames.append(i) }
        rep = result.rep
        for event in tracker.drainEvents() {
            var entry: [String: Any] = ["frame": i, "time": times[i], "key": event.key, "scope": event.scope.rawValue]
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

    // One video = one set: the app's set-end summary (scope "set") at the last frame.
    tracker.endSet()
    for event in tracker.drainEvents() {
        var entry: [String: Any] = ["frame": max(coco17Frames.count - 1, 0), "time": times.last ?? 0,
                                    "key": event.key, "scope": event.scope.rawValue]
        if let n = event.n { entry["n"] = n }
        events.append(entry)
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
        "ready_pose": readyPosePreset ? "preset" : "off",
        "input": personCrop ? "crop" : "full",
        "full_frame_inputs": fullFrameInputs,
        "whole_frame_rechecks": rechecks,
        "person_switches": switches,
        "crop_edge_refits": cropTracker.edgeRefits,
        "pose_ms_per_frame": coco17Frames.isEmpty ? 0 : poseSeconds * 1000 / Double(coco17Frames.count),
        "frames": coco17Frames.count,
        "image_size": [imageWidth, imageHeight],
        "reps": reps,
        "session": [
            "rep_count": rep,
            "frames_3d": tracker.sessionFrames3D,
            "bad_3d_frames": tracker.sessionBad3DFrames,
            "warning_rep_counts": tracker.warningRepCounts,
            "rep_end_frames": repEndFrames,
        ],
        "transitions": transitions,
        "events": events,
    ]
    let base = "\(name)_\(exercise.rawValue)_\(poseModel)"
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        .write(to: outputDir.appendingPathComponent("\(base).json"))
    try csv.write(to: outputDir.appendingPathComponent("\(base).csv"), atomically: true, encoding: .utf8)

    print("== \(name) exercise=\(exercise.rawValue) model=\(poseModel) frames=\(coco17Frames.count) reps=\(rep) "
          + "input=\(personCrop ? "crop" : "full") full_frame_inputs=\(fullFrameInputs) switches=\(switches)/\(rechecks) "
          + "3d=\(pose3D != nil) bad3d=\(tracker.sessionBad3DFrames)/\(tracker.sessionFrames3D)")
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
