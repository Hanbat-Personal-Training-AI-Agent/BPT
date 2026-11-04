// pose-replay: feeds a recorded workout video through the app's workout pose path on macOS
// (RTMPose input like CameraPosePreview: a 3:4 person crop from the previous frame's keypoints,
// whole frame stretched to 192×256 when the person is lost — `--input full` = always whole frame, the
// old input; RTMPose-s, SimCCDecoder, then SquatEvaluator / PushUpEvaluator / BarbellRowEvaluator with their
// FormWarningTracker — all symlinked from ios/Runner) to tune the form-warning thresholds.
//
//   swift run -c release --package-path ios/CalibrationEngineKit pose-replay \
//       [--exercise squat|pushup|row|bench|deadlift] [--model coco17|halpe26|mcoco17|mhalpe26] [--model-path PATH] [--motion3d PATH|none] [--lookahead N] [--cadence K] [--constraints on|off] [--form-source 3d|2d] [--image-size WxH] \
//       [--row-shrug] [--side-cutoff R] [--row-offside off] [--pushup-ankle on|off] [--pushup-wrist-conf C] [--pushup-min-frames N] [--pushup-height on|off] [--squat-hold on|off] [--squat-near-leg on|off] [--squat-rebaseline N] [--squat-height on|off] [--squat-height-range R] [--ready-pose off|preset] [--input crop|full] [--crop-edge on|off] [--keypoints-csv PATH] [--keypoints-dir DIR] [--output-dir PATH] <video.mp4>...
//
// --crop-edge off: keep a crop whose border pins confident joints (RTMPoseCropTracker.refitAtCropEdge = false, old).
// --model-path: another RTMPose .mlpackage with the same 256x192 input and SimCC outputs (17 or 26 joints;
// pass --model halpe26 for 26) — candidate models are compared on the same videos without replacing the bundled one.
// --rotate 90|180|270: every frame turned clockwise first, like a phone held in landscape (the device video mode's
// BPT_CAMERA_VIDEO_ROTATE). --capture-rotation 0|90|180|270: the app's analysis turn (CaptureRotation, as
// BPT_FORCE_CAPTURE_ROTATION); N undoes --rotate N. Both off = the frames as recorded. docs/results/orientation.md
//
// halpe26 also feeds the decoded toes/heels to SquatEvaluator (heel_rise_max; squat_heel_rise is off). --row-shrug turns on
// the experimental row_shrug rule (off in the app). --side-cutoff: row/push-up side-view gate cutoff (shoulder width ÷
// torso length) instead of the app's value, to measure counting with the gate moved (e.g. 99 = gate off).
// --pushup-ankle / --pushup-wrist-conf / --pushup-min-frames / --pushup-height: PushUpEvaluatorConfig.requireAnkleForRep / wristMinJointConfidence / minRepFrames / heightRepSignal.
// --squat-hold / --squat-near-leg / --squat-rebaseline / --squat-height / --squat-height-range: SquatEvaluatorConfig.holdStatusThroughUnknown /
// nearLegFallback / rebaselineStraightLegFrames / heightRepSignal / heightCounter.minRange.
// --row-offside off: no row reps off the side view (old gate behaviour; BarbellRowEvaluatorConfig.countOffSideView).
//
// --keypoints-csv: skip decoding and RTMPose, read the 2D keypoints (j0..j16 x/y/c, plus the nine Halpe26 extras j17..j25
// (including six toe/heel points) when present) from a CSV in the format this tool writes; the video path then only names the outputs (no 3D).
// --keypoints-dir: the same, per video from DIR/<video>_<exercise>_<model>.csv (many clips in one run, no model load).
// bench/deadlift: BenchPressEvaluator / DeadliftEvaluator (2D only; their bench_* / deadlift_* keys are off in the app).
//
// --motion3d: MotionAGFormer-XS Core ML package (default <repo>/assets/coreml/motionagformer_xs.mlpackage
// if present; `none` = 2D only). 3D runs through MotionAGFormerLive exactly like the lift-app camera: past frames
// only, frame t evaluated `lookahead` frames late with its own 2D, states warming_up / tracking_lost / bad_3d / ok,
// anatomical constraints (--constraints off = raw XS), --cadence K = one inference per K frames. Posture keys come
// from the 3D judgement (--form-source 2d = old 2D judgement); every rep also logs warnings_2d / warnings_3d.
// Works with --keypoints-csv/-dir too (image size from --image-size WxH or the JSON next to the CSV).
// Also writes <base>_3d.csv: per frame state, window row, constraint sizes, raw and constrained H36M17.
// --bone-targets PATH: the person's bone lengths for Pose3DConstraints (calibration result / boneLengthData JSON, as
// BoneLengthConstraint.loadTargets), or {"byClip": {"<video name prefix>": <that JSON>}} — the longest prefix of the video
// name picks the entry (one run over clips of several people). Without it: session median / population prior (the app).
//
// Writes <video>_<exercise>_<model>.json (per rep: index, start/end frame and time, 2D/3D metrics,
// warnings with grades, the spoken key, bad-3D frames; every onFeedback event; session totals) and <video>_<exercise>_<model>.csv (status, rep and
// every decoded keypoint per frame).
import AVFoundation
import CoreImage
import CoreML
import CryptoKit
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
var cadence = 1
var constraintsOn = true
/// --adaptive on: experimental AdaptiveRelationConstraint after the constraints (as BPT_ADAPTIVE_3D=1 in the camera);
/// <base>_3d.csv then also has the adapted H36M17 (a*_x…) and the filled joints.
var adaptiveOn = false
/// --wrist-anchor on: experimental push-up WristFloorAnchor on the 2D (as BPT_WRIST_ANCHOR=1 in the camera).
var wristAnchorOn = false
var formSource3D = true
var imageSizeOverride: (Int, Int)?
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
var sceneRotation = 0
var captureRotation = CaptureRotation.up
var personCrop = true
var cropEdgeRefit = true
var boneTargetsPath: String?
var faultTraceDirectory: URL?
var faultBindingPath: String?
var videos: [URL] = []
var arguments = CommandLine.arguments.dropFirst().makeIterator()
let usage = "usage: pose-replay [--fault-trace-dir DIR --fault-binding JSON] [--bone-targets PATH] [--exercise squat|pushup|row|bench|deadlift] [--model coco17|halpe26|mcoco17|mhalpe26] [--model-path PATH] [--motion3d PATH|none] [--lookahead N] [--cadence K] [--constraints on|off] [--form-source 3d|2d] [--image-size WxH] [--row-shrug] [--side-cutoff R] [--row-offside off] [--pushup-ankle on|off] [--pushup-wrist-conf C] [--pushup-min-frames N] [--pushup-height on|off] [--squat-hold on|off] [--squat-near-leg on|off] [--squat-rebaseline N] [--squat-height on|off] [--squat-height-range R] [--ready-pose off|preset] [--input crop|full] [--crop-edge on|off] [--keypoints-csv PATH] [--keypoints-dir DIR] [--output-dir PATH] <video.mp4>..."
while let argument = arguments.next() {
    switch argument {
    case "--fault-trace-dir":
        guard let path = arguments.next() else { exit(2) }
        faultTraceDirectory = URL(fileURLWithPath: path, isDirectory: true)
    case "--fault-binding":
        guard let path = arguments.next() else { exit(2) }
        faultBindingPath = path
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
    case "--cadence":
        guard let value = arguments.next().flatMap(Int.init), value >= 1 else { exit(2) }
        cadence = value
    case "--constraints":
        constraintsOn = arguments.next() != "off"
    case "--adaptive":
        adaptiveOn = arguments.next() == "on"
    case "--wrist-anchor":
        wristAnchorOn = arguments.next() == "on"
    case "--form-source":
        formSource3D = arguments.next() != "2d"
    case "--image-size":
        let parts = (arguments.next() ?? "").split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { exit(2) }
        imageSizeOverride = (parts[0], parts[1])
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
    case "--rotate":
        guard let value = arguments.next().flatMap(Int.init), CaptureRotation(rawValue: value) != nil else { exit(2) }
        sceneRotation = value
    case "--capture-rotation":
        guard let value = arguments.next().flatMap(Int.init).flatMap(CaptureRotation.init(rawValue:)) else { exit(2) }
        captureRotation = value
    case "--keypoints-csv":
        guard let path = arguments.next() else { exit(2) }
        keypointsCSV = path
    case "--keypoints-dir":
        guard let path = arguments.next() else { exit(2) }
        keypointsDir = path
    case "--bone-targets":
        guard let path = arguments.next() else { exit(2) }
        boneTargetsPath = path
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
// Evidence mode is deliberately stricter than ordinary CSV replay: CSV time is rounded and
// cannot establish an original media clock. Validate before loading or compiling any model.
if (faultTraceDirectory == nil) != (faultBindingPath == nil) {
    fputs("--fault-trace-dir and --fault-binding must be supplied together\n", stderr); exit(2)
}
if faultTraceDirectory != nil && (keypointsCSV != nil || keypointsDir != nil) {
    fputs("fault tracing requires original video; rounded CSV timestamps are not a rational source ledger\n", stderr); exit(2)
}
if faultTraceDirectory != nil && ![FormExercise.squat, .pushUp, .barbellRow].contains(exercise) {
    fputs("fault tracing supports only squat, pushup and row\n", stderr); exit(2)
}

func sha256File(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

// Bundle digest binds every regular file by relative name and content, including model metadata.
func sha256Artifact(_ url: URL) throws -> String {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "missing model artifact: \(url.path)"])
    }
    guard isDirectory.boolValue else { return try sha256File(url) }
    let files = (FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])?
        .allObjects as? [URL] ?? []).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        .sorted { $0.path < $1.path }
    var hash = SHA256()
    for file in files {
        let relative = String(file.path.dropFirst(url.path.count + 1))
        hash.update(data: Data(relative.utf8)); hash.update(data: Data([0]))
        hash.update(data: Data(try sha256File(file).utf8)); hash.update(data: Data([10]))
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

// A binding names this new candidate/task and the full source bytes, not a reused filename.
// Preserve caller fields for the exporter, but reserve runtime facts for the actual execution.
var faultBuildManifest: [String: Any]?
let faultBindings: [[String: Any]] = try {
    guard let path = faultBindingPath else { return [] }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let clips = document["clips"] as? [[String: Any]], clips.count == videos.count else {
        throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "binding requires one ordered clips entry per video"])
    }
    guard let build = document["buildManifest"] as? [String: Any],
          build["contract"] as? String == "bpt-pose-replay-build-v1",
          let binaryHash = build["executableSHA256"] as? String,
          binaryHash == (try sha256File(URL(fileURLWithPath: CommandLine.arguments[0]))),
          let sources = build["sourceSHA256"] as? [String: String], !sources.isEmpty else {
        throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "binding requires matching frozen buildManifest"])
    }
    for (path, expected) in sources {
        let source = repoRoot.appendingPathComponent(path).standardizedFileURL
        guard source.path.hasPrefix(repoRoot.standardizedFileURL.path + "/"),
              expected == (try sha256File(source)) else {
            throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "build source SHA256 mismatch: \(path)"])
        }
    }
    faultBuildManifest = build
    for (clip, video) in zip(clips, videos) {
        for field in ["candidateId", "clipId", "sourceSHA256"] {
            guard let value = clip[field] as? String, !value.isEmpty else {
                throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "missing binding field: \(field)"])
            }
        }
        let candidate = clip["candidateId"] as! String
        guard candidate.count == 40, candidate.allSatisfy({ $0.isHexDigit }),
              build["candidateId"] as? String == candidate,
              clip["taskId"] == nil, clip["boundaryId"] == nil else {
            throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "candidateId requires a frozen 40-hex commit; source capture must remain task/boundary unbound"])
        }
        if clip["require3D"] as? Bool == true && (motion3DPath == nil || !formSource3D) {
            throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "binding requires an active 3D lifter and 3D form source"])
        }
        let expected = clip["sourceSHA256"] as! String
        guard expected.count == 64, expected.allSatisfy({ $0.isHexDigit }),
              try sha256File(video) == expected.lowercased() else {
            throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "full source SHA256 mismatch: \(video.lastPathComponent)"])
        }
    }
    return clips
}()
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func loadModel(_ url: URL) throws -> MLModel {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    return try MLModel(contentsOf: try MLModel.compileModel(at: url), configuration: configuration)
}

let replayOnly = keypointsCSV != nil || keypointsDir != nil
let resolvedPoseModelURL = poseModelPath.map { URL(fileURLWithPath: $0) }
    ?? repoRoot.appendingPathComponent("ios/Runner/NativePose/Models/\(poseModel.rawValue).mlpackage")
var faultModelHashes: [String: String] = [:]
if faultTraceDirectory != nil {
    faultModelHashes[resolvedPoseModelURL.path] = try sha256Artifact(resolvedPoseModelURL)
    if let motion3DPath { faultModelHashes[motion3DPath] = try sha256Artifact(URL(fileURLWithPath: motion3DPath)) }
}
let model = replayOnly ? nil : try loadModel(resolvedPoseModelURL)
let motion3D = try motion3DPath.map { try loadModel(URL(fileURLWithPath: $0)) }
let context = CIContext(options: [.cacheIntermediates: false])
let workspace = try RTMPoseInputWorkspace()
let window = 27

func f(_ value: Double?) -> String { value.map { String(format: "%.4f", $0) } ?? "" }

/// 3D: MotionAGFormerLive (past frames only, like the app camera), one per video.
let predict3D = motion3D.map { MotionAGFormerCoreML.predictor($0) }

/// --bone-targets for one video: the whole file, or the byClip entry whose key is the longest prefix of the name.
func boneTargets(for name: String) throws -> [String: Double]? {
    guard let boneTargetsPath else { return nil }
    let data = try Data(contentsOf: URL(fileURLWithPath: boneTargetsPath))
    guard let byClip = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["byClip"] as? [String: Any] else {
        return try BoneLengthConstraint.loadTargets(json: data)
    }
    guard let key = byClip.keys.filter({ name.hasPrefix($0) }).max(by: { $0.count < $1.count }) else { return nil }
    return try BoneLengthConstraint.loadTargets(json: JSONSerialization.data(withJSONObject: byClip[key]!))
}

var readers: [AVAssetReader] = []
for (videoOrdinal, video) in videos.enumerated() {
    let name = video.deletingPathExtension().lastPathComponent
    let keypointsCSV = keypointsCSV ?? keypointsDir.map { "\($0)/\(name)_\(exercise.rawValue)_\(poseModel).csv" }

    // Pass 1: 2D keypoints for every frame.
    var coco17Frames: [[PoseKeypoint]] = []
    var extraFrames: [[PoseKeypoint]] = []
    var feetFrames: [FootKeypoints?] = []
    var times: [Double] = []
    let faultSession = UUID().uuidString
    var sourceStamps: [FormFaultSource] = []
    var expectedSourceStamps: [FormFaultSource] = []
    var ingressFailures: [(FormFaultSource, String)] = []
    var rawSourceIndex = 0
    var sourceDrained = false
    var poseFailure: String?
    var imageWidth = 0, imageHeight = 0
    var cropTracker = RTMPoseCropTracker()
    cropTracker.refitAtCropEdge = cropEdgeRefit
    var fullFrameInputs = 0
    var rechecks = 0, switches = 0
    var poseSeconds = 0.0
    if let keypointsCSV {
        guard FileManager.default.fileExists(atPath: keypointsCSV) else { print("no keypoints: \(keypointsCSV)"); continue }
        let lines = try String(contentsOfFile: keypointsCSV, encoding: .utf8).split(whereSeparator: \.isNewline)
        let header = lines.first?.split(separator: ",", omittingEmptySubsequences: false).map(String.init) ?? []
        let halpeHeader = (17..<Halpe26.jointCount).flatMap { j in ["j\(j)_x", "j\(j)_y", "j\(j)_c"] }
        // Legacy COCO17 CSVs may have unrelated trailing metrics. Only the writer's exact named,
        // positional j17..j25 columns declare Halpe extras; length alone is not evidence of feet.
        let hasHalpeHeader = header.count >= 4 + Halpe26.jointCount * 3
            && Array(header[(4 + 17 * 3)..<(4 + Halpe26.jointCount * 3)]) == halpeHeader
        for line in lines.dropFirst() {
            let cells = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cells.count >= 4 + 17 * 3 else { continue }
            let v = cells.map { Double($0) ?? 0 }
            let joint = { (j: Int) in PoseKeypoint(x: v[4 + j * 3], y: v[5 + j * 3], confidence: v[6 + j * 3]) }
            times.append(v[1])
            coco17Frames.append((0..<17).map(joint))
            // A Halpe26 CSV (j17..j25) also carries the toes/heels: the keypoint replay sees the feet like the video run.
            let halpe = hasHalpeHeader && cells.count >= 4 + Halpe26.jointCount * 3
            extraFrames.append(halpe ? (17..<Halpe26.jointCount).map(joint) : [])
            feetFrames.append(halpe ? FootKeypoints(leftBigToe: joint(Halpe26.leftBigToe), rightBigToe: joint(Halpe26.rightBigToe),
                                                    leftSmallToe: joint(Halpe26.leftSmallToe), rightSmallToe: joint(Halpe26.rightSmallToe),
                                                    leftHeel: joint(Halpe26.leftHeel), rightHeel: joint(Halpe26.rightHeel)) : nil)
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
    if keypointsCSV == nil && output == nil && faultTraceDirectory == nil { continue }
    while let sampleBuffer = output?.copyNextSampleBuffer() {
        let sourceIndex = rawSourceIndex
        rawSourceIndex += 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        func stamp(frame: Int) -> FormFaultSource {
            FormFaultSource(frame: frame, sourceIndex: sourceIndex,
                            timeValue: pts.value, timeScale: pts.timescale,
                            session: faultSession, kind: "original_video", flush: false,
                            timeEpoch: pts.epoch, timeFlags: pts.flags.rawValue)
        }
        func failIngress(_ reason: String) {
            let source = stamp(frame: -1 - sourceIndex)
            expectedSourceStamps.append(source)
            ingressFailures.append((source, reason))
        }
        if let poseFailure { failIngress("not_processed_after_\(poseFailure)"); continue }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            if faultTraceDirectory != nil { failIngress("missing_pixel_buffer") }; continue
        }
        // Turning clockwise by N is the analysis turn of 360 − N; both .up = the frame as recorded.
        let held = CaptureRotation(rawValue: (360 - sceneRotation) % 360)!.analysisImage(CIImage(cvPixelBuffer: pixelBuffer))
        let image = captureRotation.analysisImage(held)
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            if faultTraceDirectory != nil { failIngress("image_conversion_failed") }; continue
        }
        imageWidth = cgImage.width
        imageHeight = cgImage.height
        let poseStart = Date()
        if cropTracker.crop == nil { fullFrameInputs += 1 }
        // The live camera path's pose step (crop, RTMPose, decode, tracker, ~1 s whole-frame recheck).
        let estimate: RTMPoseFrameEstimate
        do {
            guard let model, let value = try cropTracker.estimate(cgImage, model: model, workspace: workspace, personCrop: personCrop) else {
                if faultTraceDirectory != nil {
                    poseFailure = "missing_simcc_outputs"; failIngress(poseFailure!); continue
                }
                fatalError("model has no simcc_x / simcc_y outputs")
            }
            estimate = value
        } catch {
            guard faultTraceDirectory != nil else { throw error }
            poseFailure = "pose_estimation_error"; failIngress(poseFailure!); continue
        }
        let decoded = estimate.decoded, back = estimate.inverseAffine, coco17 = estimate.coco17
        if let switched = estimate.recheckSwitched {
            rechecks += 1
            if switched { switches += 1 }
        }
        poseSeconds += Date().timeIntervalSince(poseStart)
        if faultTraceDirectory != nil {
            let source = stamp(frame: coco17Frames.count)
            sourceStamps.append(source)
            expectedSourceStamps.append(source)
        }
        coco17Frames.append(coco17)
        extraFrames.append(zip(decoded.extraInputCoordinates, decoded.extraConfidences).map { point, confidence in
            let p = back.apply(point)
            return PoseKeypoint(x: p.x, y: p.y, confidence: confidence)
        })
        feetFrames.append(PoseCoordinateTransforms.applyInverseAffineToFeet(decoded: decoded, inverseAffine: back))
        times.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
    }

    sourceDrained = keypointsCSV == nil && readers.last?.status == .completed

    var evidence: FormFaultEvidence?
    if let faultTraceDirectory {
        var binding = faultBindings[videoOrdinal]
        let sourceHashAfterDecode = try sha256File(video)
        guard sourceHashAfterDecode == (binding["sourceSHA256"] as? String)?.lowercased() else {
            throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "source changed during decode"])
        }
        binding["sourceSHA256"] = sourceHashAfterDecode
        binding["executableSHA256"] = try sha256File(URL(fileURLWithPath: CommandLine.arguments[0]))
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceFiles = try FileManager.default.contentsOfDirectory(at: sourceDirectory,
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var sourceHashes: [String: String] = [:]
        for file in sourceFiles {
            let resolved = file.resolvingSymlinksInPath().path
            let prefix = repoRoot.resolvingSymlinksInPath().path + "/"
            guard resolved.hasPrefix(prefix) else { fatalError("source outside repository") }
            sourceHashes[String(resolved.dropFirst(prefix.count))] = try sha256File(file)
        }
        guard sourceHashes.allSatisfy({ (faultBuildManifest?["sourceSHA256"] as? [String: String])?[$0.key] == $0.value }) else {
            throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "build manifest does not cover every compiled replay source"])
        }
        binding["buildManifest"] = faultBuildManifest
        binding["runtimeSourceSHA256"] = sourceHashes
        binding["executionScope"] = "headless_original_video_native_evaluator"
        binding["taskBinding"] = "unbound_native_windows"
        binding["arguments"] = Array(CommandLine.arguments.dropFirst())
        binding["exercise"] = exercise.rawValue
        binding["modelArtifactSHA256"] = faultModelHashes
        binding["runtimeSettings"] = ["poseModel": "\(poseModel)", "lookahead": lookahead, "cadence": cadence,
            "constraints": constraintsOn, "adaptive": adaptiveOn, "wristAnchor": wristAnchorOn,
            "formSource3D": formSource3D, "personCrop": personCrop, "cropEdgeRefit": cropEdgeRefit] as [String: Any]
        binding["sourceSampleCount"] = rawSourceIndex
        binding["sourceDecoderCompleted"] = sourceDrained
        evidence = try FormFaultEvidence.file(directory: faultTraceDirectory, runID: faultSession,
                                              binding: binding, expectedSources: expectedSourceStamps)
        for (source, reason) in ingressFailures { evidence?.ingressFailure(source: source, reason: reason) }
    }
    // Any thrown model/lifter/output error closes the trace as incomplete.
    defer { evidence?.finish(reason: "replay_interrupted", sourceDrained: false) }
    if keypointsCSV == nil && output == nil {
        evidence?.finish(reason: "no_video_track", sourceDrained: false)
        continue
    }

    // Pass 2 (streamed in pass 3): MotionAGFormerLive, past frames only, like the app camera. Keypoint CSVs carry
    // no image size: --image-size, else the image_size of the JSON written next to the CSV.
    if let (w, h) = imageSizeOverride { imageWidth = w; imageHeight = h }
    if imageWidth == 0, let keypointsCSV,
       let data = FileManager.default.contents(atPath: keypointsCSV.replacingOccurrences(of: ".csv", with: ".json")),
       let size = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["image_size"] as? [Int], size.count == 2 {
        imageWidth = size[0]; imageHeight = size[1]
    }
    var lifter = predict3D.map { p -> MotionAGFormerLive<Int> in
        var l = MotionAGFormerLive<Int>(lookahead: lookahead, cadence: cadence, predict: p)
        l.constraints.enabled = constraintsOn
        l.constraints.reflectFlippedKnee = exercise == .squat  // as the camera (Fit3D S6: squat only)
        if adaptiveOn { l.adaptive = AdaptiveRelationConstraint(exercise: exercise) }
        return l
    }
    if faultBindings.indices.contains(videoOrdinal), faultBindings[videoOrdinal]["require3D"] as? Bool == true,
       (lifter == nil || !formSource3D) {
        evidence?.finish(reason: "required_3d_unavailable", sourceDrained: false)
        throw NSError(domain: "PoseReplayFaultBinding", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "required 3D lifter unavailable"])
    }
    let targets = try boneTargets(for: name)
    lifter?.constraints.calibrationTargetsCm = targets
    if lifter != nil, imageWidth == 0 { print("no image size for 3D: \(name) (pass --image-size)"); continue }

    // Pass 3: evaluator + form tracker, frame by frame like the app.
    let tracker: FormWarningTracker
    let step: (Int, [PoseKeypoint], [SIMD3<Double>]?, Pose3DState?, FootKeypoints?) -> (status: String, rep: Int)
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
        step = { let r = evaluator.evaluate(frameIndex: $0, coco17: $1, pose3D: $2, pose3DState: $3, feet: $4); return (r.status.rawValue, r.rep) }
    case .pushUp:
        var config = PushUpEvaluatorConfig()
        if let pushUpAnkle { config.requireAnkleForRep = pushUpAnkle }
        if let pushUpWristConf { config.wristMinJointConfidence = pushUpWristConf }
        if let pushUpMinFrames { config.minRepFrames = pushUpMinFrames }
        if let pushUpHeight { config.heightRepSignal = pushUpHeight }
        let evaluator = PushUpEvaluator(config: config)
        tracker = evaluator.formTracker
        if let sideCutoff { tracker.pushUp.sideViewMaxShoulderRatio = sideCutoff }
        step = { i, k, p, s, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k, pose3D: p, pose3DState: s); return (r.status.rawValue, r.rep) }
    case .barbellRow:
        var config = BarbellRowEvaluatorConfig()
        if readyPosePreset { config.applyReadyPosePreset(fps: fps) }
        if rowNonSide == "off" { config.countOffSideView = false }
        let evaluator = BarbellRowEvaluator(config: config)
        tracker = evaluator.formTracker
        tracker.row.shrugEnabled = rowShrug
        if let sideCutoff { tracker.row.sideViewMaxShoulderRatio = sideCutoff }
        step = { i, k, p, s, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k, pose3D: p, pose3DState: s); return (r.status.rawValue, r.rep) }
    case .benchPress:
        let evaluator = BenchPressEvaluator()
        tracker = evaluator.formTracker
        step = { i, k, p, s, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k, pose3D: p, pose3DState: s); return (r.status.rawValue, r.rep) }
    case .deadlift:
        let evaluator = DeadliftEvaluator()
        tracker = evaluator.formTracker
        step = { i, k, p, s, _ in let r = evaluator.evaluate(frameIndex: i, coco17: k, pose3D: p, pose3DState: s); return (r.status.rawValue, r.rep) }
    }
    tracker.faultEvidence = evidence
    // Every key on (the app sends none by default) so `spoken` and `events` show what would be said.
    tracker.common.enabledFeedbackKeys = FormWarningTracker.allKeys
    var csv = "frame,time,status,rep," + (0..<(17 + (extraFrames.first?.count ?? 0)))
        .map { "j\($0)_x,j\($0)_y,j\($0)_c" }.joined(separator: ",") + "\n"
    var transitions: [String] = []
    var lastStatus: String?
    var events: [[String: Any]] = []
    var rep = 0
    var repEndFrames: [Int] = []
    tracker.common.form3DRequired = lifter != nil && formSource3D
    var states3D: [String: Int] = [:]
    var csv3D = "frame,state,row,filled,bone_corr,angle_corr," + (0..<17).map { "r\($0)_x,r\($0)_y,r\($0)_z" }.joined(separator: ",")
        + "," + (0..<17).map { "c\($0)_x,c\($0)_y,c\($0)_z" }.joined(separator: ",")
        + (adaptiveOn ? ",adaptive_filled,adaptive_invalid," + (0..<17).map { "a\($0)_x,a\($0)_y,a\($0)_z" }.joined(separator: ",") : "") + "\n"
    var seconds3D = 0.0
    func evaluateFrame(_ i: Int, _ frame3D: Lifted3DFrame?) {
        if let frame3D {
            states3D[frame3D.state.rawValue, default: 0] += 1
            let xyz = { (p: [SIMD3<Double>]?) in (p ?? Array(repeating: SIMD3<Double>(repeating: .nan), count: 17)).flatMap { [f($0.x), f($0.y), f($0.z)] } }
            csv3D += ([String(i), frame3D.state.rawValue, frame3D.row.map(String.init) ?? "", String(frame3D.filled),
                       f(frame3D.constraints?.boneMaxCorrection), f(frame3D.constraints?.maxAngleCorrection)]
                      + xyz(frame3D.raw) + xyz(frame3D.pose3D)
                      + (adaptiveOn ? [(frame3D.adaptive?.filled.keys.sorted() ?? []).map(String.init).joined(separator: " "),
                                       (frame3D.adaptive?.invalid ?? []).map(String.init).joined(separator: " ")] + xyz(frame3D.adapted) : []))
                .joined(separator: ",") + "\n"
        }
        if evidence != nil {
            let source = sourceStamps[i]
            tracker.faultSource = FormFaultSource(frame: source.frame, sourceIndex: source.sourceIndex,
                timeValue: source.timeValue, timeScale: source.timeScale, session: source.session,
                kind: source.kind, flush: frame3D?.diagnosticFlushed ?? false,
                timeEpoch: source.timeEpoch, timeFlags: source.timeFlags)
        }
        let result = step(i, coco17Frames[i], frame3D?.masked3D, frame3D?.state, feetFrames[i])
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
    // --wrist-anchor on (push-up, experimental): WristFloorAnchor on the 2D before the 3D and the evaluators, active once
    // a rep has been counted (the camera: rep >= 1 or setup ready; with no MediaPipe here it anchors the RTMPose 2D).
    var wristAnchor = wristAnchorOn && exercise == .pushUp ? WristFloorAnchor() : nil
    var wristAnchorStates: [String: Int] = [:]
    for i in coco17Frames.indices {
        if wristAnchor != nil, let r = wristAnchor?.update(coco17Frames[i], active: rep >= 1) {
            coco17Frames[i] = r.keypoints
            for (_, st) in r.states { wristAnchorStates[st.rawValue, default: 0] += 1 }
        }
        guard lifter != nil else { evaluateFrame(i, nil); continue }
        let start = Date()
        let ready = try lifter!.push(frameIndex: i, coco17: coco17Frames[i], imageWidth: imageWidth,
                                     imageHeight: imageHeight, payload: i)
        seconds3D += Date().timeIntervalSince(start)
        for (j, frame3D) in ready { evaluateFrame(j, frame3D) }
    }
    if lifter != nil { for (j, frame3D) in try lifter!.flush() { evaluateFrame(j, frame3D) } }

    // One video = one set: the app's set-end summary (scope "set") at the last frame.
    tracker.endSet()
    for event in tracker.drainEvents() {
        var entry: [String: Any] = ["frame": max(coco17Frames.count - 1, 0), "time": times.last ?? 0,
                                    "key": event.key, "scope": event.scope.rawValue]
        if let n = event.n { entry["n"] = n }
        events.append(entry)
    }
    var artifactsStable = true
    if let evidence, let faultTraceDirectory {
        let sourceAfter = try sha256File(video)
        var modelsAfter: [String: String] = [:]
        for path in faultModelHashes.keys { modelsAfter[path] = try sha256Artifact(URL(fileURLWithPath: path)) }
        artifactsStable = sourceAfter == (faultBindings[videoOrdinal]["sourceSHA256"] as? String)?.lowercased()
            && modelsAfter == faultModelHashes
        let receipt: [String: Any] = ["contract": "bpt-pose-replay-receipt-v1", "runID": faultSession,
            "tracePath": evidence.url?.path as Any? ?? NSNull(), "candidateId": faultBindings[videoOrdinal]["candidateId"]!,
            "sourceSHA256Before": faultBindings[videoOrdinal]["sourceSHA256"]!, "sourceSHA256After": sourceAfter,
            "modelArtifactSHA256Before": faultModelHashes, "modelArtifactSHA256After": modelsAfter,
            "artifactsStable": artifactsStable, "lifterActive": lifter != nil,
            "formSource3D": tracker.common.form3DRequired]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: faultTraceDirectory.appendingPathComponent("receipt_\(faultSession).json"), options: .withoutOverwriting)
    }
    evidence?.finish(reason: !artifactsStable ? "artifact_changed_during_execution" :
                        (poseFailure ?? (sourceDrained ? "replay_eof" : "source_decode_incomplete")),
                     sourceDrained: sourceDrained && poseFailure == nil && artifactsStable)
    let reps: [[String: Any]] = tracker.reports.map { report in
        var entry = report.dictionary
        entry["start_time"] = times.indices.contains(report.startFrame) ? times[report.startFrame] : NSNull()
        entry["end_time"] = times.indices.contains(report.endFrame) ? times[report.endFrame] : NSNull()
        return entry
    }
    var json: [String: Any] = [
        "video": video.path,
        "exercise": exercise.rawValue,
        "model": "\(poseModel)",
        "motion3d": motion3DPath.map { $0 as Any } ?? NSNull(),
        "lookahead": lookahead,
        "cadence": cadence,
        "constraints": constraintsOn,
        "adaptive": adaptiveOn,
        "wrist_anchor": wristAnchorOn ? wristAnchorStates as Any : NSNull(),
        "bone_targets": targets.map { $0 as Any } ?? NSNull(),
        "form_source": tracker.common.form3DRequired ? "3d" : "2d",
        "delay_frames_3d": lifter.map { $0.delayFrames as Any } ?? NSNull(),
        "inferences_3d": lifter.map { $0.inferences as Any } ?? NSNull(),
        "ms_3d_per_frame_mac": coco17Frames.isEmpty ? 0 : seconds3D * 1000 / Double(coco17Frames.count),
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
            "states_3d": states3D,
            "form_sources": Dictionary(grouping: tracker.reports, by: \.formSource).mapValues(\.count),
        ],
        "transitions": transitions,
        "events": events,
    ]
    if sceneRotation != 0 || captureRotation != .up {  // only then, so as-recorded outputs keep their bytes
        json["rotate"] = sceneRotation
        json["capture_rotation"] = captureRotation.rawValue
    }
    let base = "\(name)_\(exercise.rawValue)_\(poseModel)"
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        .write(to: outputDir.appendingPathComponent("\(base).json"))
    try csv.write(to: outputDir.appendingPathComponent("\(base).csv"), atomically: true, encoding: .utf8)
    if lifter != nil { try csv3D.write(to: outputDir.appendingPathComponent("\(base)_3d.csv"), atomically: true, encoding: .utf8) }

    print("== \(name) exercise=\(exercise.rawValue) model=\(poseModel) frames=\(coco17Frames.count) reps=\(rep) "
          + "input=\(personCrop ? "crop" : "full") full_frame_inputs=\(fullFrameInputs) switches=\(switches)/\(rechecks) "
          + "3d=\(lifter != nil) states3d=\(states3D) bad3d=\(tracker.sessionBad3DFrames)/\(tracker.sessionFrames3D)")
    print("  transitions: " + transitions.joined(separator: " "))
    for report in tracker.reports {
        let m2 = report.metrics2D.sorted { $0.key < $1.key }.map { "\($0.key)=\(f($0.value))" }.joined(separator: " ")
        let m3 = report.metrics3D.sorted { $0.key < $1.key }.map { "\($0.key)=\(f($0.value))" }.joined(separator: " ")
        print("  rep \(report.repIndex): frames \(report.startFrame)–\(report.endFrame) side=\(report.side) "
              + "bad3d=\(report.bad3DFrames)/\(report.frames3D) form=\(report.formSource) warnings=\(report.warnings) w2d=\(report.warnings2D) w3d=\(report.warnings3D.map { "\($0)" } ?? "-") spoken=\(report.spoken ?? "-")")
        print("    2d: \(m2)")
        print("    3d: \(m3)")
    }
    print("  -> \(outputDir.appendingPathComponent(base).path).json")
}
