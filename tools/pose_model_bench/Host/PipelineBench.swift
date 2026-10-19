import AVFoundation
import CoreImage
import CoreML
import MediaPipeTasksVision
import UIKit

/// Device "video-fed live" run (launch env BENCH_PIPELINE=1): Exercise3D clips decoded with AVAssetReader stand
/// in for the camera, and every frame goes through the live camera path's per-frame code from ios/Runner/NativePose:
/// on a serial processing queue `RTMPoseCropTracker.estimate` (person crop, RTMPose, decode, reacquire recheck)
/// [+ MotionAGFormer-XS] [+ WorkoutSetRecorder.append], then on the main thread the evaluator, its
/// FormWarningTracker and the bridge's change detection (CameraPoseViewModel.handleProcessingResult minus Flutter).
/// One clip = one set (new evaluator, tracker reset, recorder per set, endSet at the clip end).
/// Not included: camera capture, preview rendering, the hand branch (push-up/row overlay, MediaPipe).
///
/// Env: BENCH_MODEL=rtmpose_s_forward|rtmpose_m_forward|pose_landmarker_{lite,full,heavy} (MediaPipe VIDEO mode on the
/// BGRA pixel buffer in place of crop+RTMPose, its COCO-17 subset into the evaluator; BENCH_MP_DELEGATE=gpu|cpu), BENCH_RECORD=1, BENCH_3D=1, BENCH_PACED=1 (30 fps camera
/// clock; a frame is dropped when the next one is already due, like alwaysDiscardsLateVideoFrames) or unpaced,
/// BENCH_SECONDS (180; unpaced also finishes the first pass over all clips, up to 270 s), BENCH_COOLDOWN (idle
/// seconds first, inside the foreground app), BENCH_DUMP=1 (Documents/pipeline_csv/<clip>.csv: per-frame COCO-17 in
/// pose-replay's CSV format, so `pose-replay --keypoints-csv` replays the device keypoints on the Mac). Prints BENCH lines.
final class PipelineBench {
    private let env: [String: String]

    /// `overrides` replace launch env keys (MediaPipeBench's back-to-back session).
    init(overrides: [String: String] = [:]) {
        env = ProcessInfo.processInfo.environment.merging(overrides) { $1 }
    }
    private let processing = DispatchQueue(label: "bench.processing", qos: .userInitiated)
    private let assets = Bundle.main.resourceURL!.appendingPathComponent("PipelineAssets")
    private let context = CIContext(options: nil)

    // Main thread only.
    private var latencies: [Double] = []
    private var lastRep = 0
    private var lastStatus: String?
    private var bridgeUpdates = 0
    private var feedbackEvents = 0

    private func loadModel(_ name: String) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let compiled = try MLModel.compileModel(at: assets.appendingPathComponent("\(name).mlpackage"))
        return try MLModel(contentsOf: compiled, configuration: configuration)
    }

    private static func now() -> Double { CACurrentMediaTime() }
    private static func thermal() -> String { WorkoutPerfLog.thermalName(ProcessInfo.processInfo.thermalState) }
    private static func battery() -> (Float, Int) {
        DispatchQueue.main.sync { (UIDevice.current.batteryLevel, UIDevice.current.batteryState.rawValue) }
    }

    func run() throws {
        let model = env["BENCH_MODEL"] ?? "rtmpose_s_forward"
        let record = env["BENCH_RECORD"] == "1", lift3D = env["BENCH_3D"] == "1", paced = env["BENCH_PACED"] == "1"
        // lift-app pipeline: BENCH_3D=1 runs MotionAGFormerLive (lookahead BENCH_3D_LOOKAHEAD=5, one inference per
        // BENCH_3D_CADENCE=1 frames, BENCH_3D_ASYNC=1 on its own queue) + Pose3DConstraints + 3D posture judgement;
        // BENCH_HANDS=1 adds the wrist-crop MediaPipe hands (CameraPosePreview hand branch) and their wrists in the XS input.
        let hands = env["BENCH_HANDS"] == "1", async3D = env["BENCH_3D_ASYNC"] == "1"
        let lookahead = Int(env["BENCH_3D_LOOKAHEAD"] ?? "") ?? 5, cadence = Int(env["BENCH_3D_CADENCE"] ?? "") ?? 1
        let seconds = Double(env["BENCH_SECONDS"] ?? "") ?? 180
        let dumpDir: URL? = env["BENCH_DUMP"] == "1"
            ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pipeline_csv") : nil
        if let dumpDir {
            try? FileManager.default.removeItem(at: dumpDir)
            try FileManager.default.createDirectory(at: dumpDir, withIntermediateDirectories: true)
        }
        let label = "model=\(model) record=\(record) 3d=\(lift3D) lookahead=\(lookahead) cadence=\(cadence) async=\(async3D) hands=\(hands) paced=\(paced)"
        DispatchQueue.main.sync { UIDevice.current.isBatteryMonitoringEnabled = true }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for dir in ["workout_videos", "workout_form_logs"] { try? FileManager.default.removeItem(at: documents.appendingPathComponent(dir)) }
        Thread.sleep(forTimeInterval: Double(env["BENCH_COOLDOWN"] ?? "") ?? 0)

        let mediaPipe = model.hasPrefix("pose_landmarker")
            ? try MediaPipePose(model: model, gpu: env["BENCH_MP_DELEGATE"] != "cpu", video: true) : nil
        let rtmpose = mediaPipe == nil ? try loadModel(model) : nil
        let motion3D = lift3D ? try loadModel("motionagformer_xs") : nil
        let handPair = hands ? MediaPipeHandLandmarkerPair() : nil
        let liftQueue = DispatchQueue(label: "bench.lift3d", qos: .userInitiated)
        var handsMs: [Double] = [], liftMs: [Double] = []  // processing / lift queue only
        let workspace = try RTMPoseInputWorkspace()
        let clips = try FileManager.default.contentsOfDirectory(at: assets.appendingPathComponent("clips"),
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let perfLog = WorkoutPerfLog(exercise: "bench")
        let (battery0, batteryState) = Self.battery()
        print("BENCH start \(label) clips=\(clips.count) thermal=\(Self.thermal()) battery=\(battery0) battery_state=\(batteryState)")

        // Warm-up (not measured): first predictions load the model onto the ANE.
        if let first = clips.first, let image = try firstImage(first) {
            var tracker = RTMPoseCropTracker()
            let mpImage = try MPImage(pixelBuffer: MediaPipeBench.pixelBuffer(image))
            for _ in 0..<20 {
                if let mediaPipe { _ = try mediaPipe.detect(mpImage) } else { _ = try tracker.estimate(image, model: rtmpose!, workspace: workspace) }
            }
        }

        let start = Self.now()
        var cameraFrame = 0, processed = 0, dropped = 0
        var processingMs: [Double] = [], convertMs: [Double] = [], estimateMs: [Double] = []
        var lastLog = start, logProcessed = 0, logDropped = 0
        var completedFirstPass = false
        var thermalTrace: [String] = []
        var clipIndex = 0
        func timeUp() -> Bool {
            let elapsed = Self.now() - start
            return paced ? elapsed >= seconds : (elapsed >= seconds && completedFirstPass) || elapsed >= seconds * 1.5
        }

        while !timeUp() {
            let clip = clips[clipIndex % clips.count]
            let name = clip.deletingPathExtension().lastPathComponent
            let session = SetSession(exercise: name.hasPrefix("squat") ? .squat : name.hasPrefix("pushup") ? .pushUp : .barbellRow)
            DispatchQueue.main.sync { lastRep = 0; lastStatus = nil }
            var cropTracker = RTMPoseCropTracker()
            typealias Payload = (idx: Int, coco17: [PoseKeypoint], feet: FootKeypoints?, arrival: Double)
            var lifter = motion3D.map { MotionAGFormerLive<Payload>(lookahead: lookahead, cadence: cadence, predict: MotionAGFormerCoreML.predictor($0)) }
            if lifter != nil { session.tracker.common.form3DRequired = true }
            /// Main thread: evaluator + tracker + bridge change detection for one judged frame.
            func judge(_ p: Payload, _ frame3D: Lifted3DFrame?) {
                DispatchQueue.main.async { [self] in
                    let (status, rep) = session.evaluate(frameIndex: p.idx, coco17: p.coco17, feet: p.feet, pose3D: frame3D?.pose3D, state: frame3D?.state)
                    feedbackEvents += session.tracker.drainEvents().count
                    if rep != lastRep || status != lastStatus { bridgeUpdates += 1 }
                    lastRep = rep
                    lastStatus = status
                    latencies.append((Self.now() - p.arrival) * 1000)
                }
            }
            let recorder = record ? WorkoutSetRecorder.directory().map {
                WorkoutSetRecorder.prune(directory: $0, keep: WorkoutSetRecorder.keepFiles - 1)
                return WorkoutSetRecorder(url: $0.appendingPathComponent(
                    WorkoutSetRecorder.fileName(exercise: session.exercise.rawValue, setIndex: clipIndex + 1)))
            } : nil
            let asset = AVURLAsset(url: clip)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: asset.tracks(withMediaType: .video)[0], outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            reader.startReading()
            var frameIndex = 0, clipFrames = 0, clipDrops = 0
            var csv = "frame,time,status,rep," + (0..<17).map { "j\($0)_x,j\($0)_y,j\($0)_c" }.joined(separator: ",") + "\n"
            var finished = true
            while let sampleBuffer = output.copyNextSampleBuffer() {
                if timeUp() { finished = false; break }
                cameraFrame += 1
                clipFrames += 1
                var arrival = Self.now()
                if paced {
                    let due = start + Double(cameraFrame) / 30
                    if arrival >= due + 1.0 / 30 {
                        dropped += 1; clipDrops += 1; perfLog?.frameDropped()
                        continue
                    }
                    if due > arrival { Thread.sleep(forTimeInterval: due - arrival) }
                    arrival = due
                }
                let idx = frameIndex
                frameIndex += 1
                // CameraCaptureManager.captureOutput → CameraPoseViewModel.processFrame (processing queue).
                let step: (coco17: [PoseKeypoint], feet: FootKeypoints?, pose3D: [SIMD3<Double>]?)? = try processing.sync {
                    try autoreleasepool {
                        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
                        let t0 = Self.now()
                        if let mediaPipe {
                            let coco17 = try mediaPipe.coco17(try MPImage(pixelBuffer: pixelBuffer), width: CVPixelBufferGetWidth(pixelBuffer),
                                                              height: CVPixelBufferGetHeight(pixelBuffer))
                            estimateMs.append((Self.now() - t0) * 1000)
                            perfLog?.frameProcessed()
                            return coco17.map { ($0, nil, nil) }
                        }
                        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
                        let t1 = Self.now()
                        guard let estimate = try cropTracker.estimate(cgImage, model: rtmpose!, workspace: workspace) else { return nil }
                        convertMs.append((t1 - t0) * 1000)
                        estimateMs.append((Self.now() - t1) * 1000)
                        var liftInput = estimate.coco17
                        if let handPair {
                            let h0 = Self.now()
                            let frame = BundledVideoHandFrameProcessor.runWristCropHands(
                                image: UIImage(cgImage: cgImage), rawCoco17: estimate.coco17, imageWidth: Double(cgImage.width),
                                imageHeight: Double(cgImage.height), timestampMs: idx * 33, handLandmarkers: handPair)
                            let point = { (h: HandLandmarkResult?) in h?.wristFramePoint.map { PosePoint(x: $0.x, y: $0.y) } }
                            liftInput = MotionAGFormerWristSource.input(raw: estimate.coco17, left: point(frame.leftHand), right: point(frame.rightHand)).input
                            handsMs.append((Self.now() - h0) * 1000)
                        }
                        let feet = PoseCoordinateTransforms.applyInverseAffineToFeet(decoded: estimate.decoded, inverseAffine: estimate.inverseAffine)
                        if lifter != nil {
                            let payload: Payload = (idx, estimate.coco17, feet, arrival)
                            let (w, hgt) = (cgImage.width, cgImage.height)
                            let lift = {
                                let l0 = Self.now()
                                let ready = (try? lifter!.push(frameIndex: idx, coco17: liftInput, imageWidth: w, imageHeight: hgt, payload: payload)) ?? []
                                liftMs.append((Self.now() - l0) * 1000)
                                for (p, f) in ready { judge(p, f) }
                            }
                            if async3D { liftQueue.async(execute: lift) } else { liftQueue.sync(execute: lift) }
                        }
                        recorder?.append(sampleBuffer)
                        perfLog?.frameProcessed()
                        if dumpDir != nil {
                            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                            csv += (["\(idx)", String(format: "%.4f", t), "", ""] + estimate.coco17.flatMap {
                                [String(format: "%.4f", $0.x), String(format: "%.4f", $0.y), String(format: "%.4f", $0.confidence)]
                            }).joined(separator: ",") + "\n"
                        }
                        return lifter == nil ? (estimate.coco17, feet, nil) : nil
                    }
                }
                processed += 1
                processingMs.append((Self.now() - arrival) * 1000)
                if let step { judge((idx, step.coco17, step.feet, arrival), nil) }
                if Self.now() - lastLog >= 10 {
                    let (level, _) = Self.battery()
                    let line = String(format: "t=%.0f fps=%.1f drops=%d thermal=%@ battery=%.2f", Self.now() - start,
                                      Double(processed - logProcessed) / (Self.now() - lastLog), dropped - logDropped,
                                      Self.thermal(), level)
                    print("BENCH window \(line)")
                    thermalTrace.append("\(Int(Self.now() - start)):\(Self.thermal())")
                    perfLog?.flush(battery: level, recording: record)
                    lastLog = Self.now(); logProcessed = processed; logDropped = dropped
                }
            }
            reader.cancelReading()
            // Set end: judge the frames still in the 3D window (CameraPosePreview.endSet).
            if lifter != nil { liftQueue.sync { for (p, f) in (try? lifter!.flush()) ?? [] { judge(p, f) } } }
            if let dumpDir, finished { try csv.write(to: dumpDir.appendingPathComponent("\(name).csv"), atomically: true, encoding: .utf8) }
            // endSet: set-scope feedback, close the set file (processing queue, like finishRecording).
            let reps = DispatchQueue.main.sync { () -> Int in
                session.tracker.endSet()
                feedbackEvents += session.tracker.drainEvents().count
                return lastRep
            }
            if let recorder { processing.sync { recorder.finish { _ in } } }
            print("BENCH clip \(name) reps=\(reps) frames=\(clipFrames) drops=\(clipDrops) complete=\(finished)")
            clipIndex += 1
            if clipIndex == clips.count { completedFirstPass = true }
        }
        let wall = Self.now() - start
        liftQueue.sync {}
        DispatchQueue.main.sync {}  // drain the evaluator steps
        let (battery1, _) = Self.battery()
        let lat = DispatchQueue.main.sync { latencies.sorted() }
        func pct(_ s: [Double], _ q: Double) -> Double { s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * q))] }
        let proc = processingMs.sorted()
        print(String(format: "BENCH result %@ wall=%.1f camera_frames=%d processed=%d fps=%.2f drops=%d drop_pct=%.2f "
                     + "e2e_p50=%.2f e2e_p95=%.2f e2e_max=%.2f proc_p50=%.2f proc_p95=%.2f battery0=%.2f battery1=%.2f "
                     + "battery_pct_per_min=%.3f thermal_end=%@ bridge_updates=%d feedback_events=%d convert_p50=%.2f estimate_p50=%.2f estimate_p95=%.2f",
                     label, wall, cameraFrame, processed, Double(processed) / wall, dropped,
                     cameraFrame == 0 ? 0 : 100 * Double(dropped) / Double(cameraFrame),
                     pct(lat, 0.5), pct(lat, 0.95), lat.last ?? 0, pct(proc, 0.5), pct(proc, 0.95),
                     battery0, battery1, Double(battery0 - battery1) * 100 / (wall / 60), Self.thermal(),
                     DispatchQueue.main.sync { bridgeUpdates }, DispatchQueue.main.sync { feedbackEvents },
                     pct(convertMs.sorted(), 0.5), pct(estimateMs.sorted(), 0.5), pct(estimateMs.sorted(), 0.95)))
        let hs = handsMs.sorted(), ls = liftQueue.sync { liftMs.sorted() }
        print(String(format: "BENCH stages hands_p50=%.2f hands_p95=%.2f lift3d_p50=%.2f lift3d_p95=%.2f delay_frames=%d",
                     pct(hs, 0.5), pct(hs, 0.95), pct(ls, 0.5), pct(ls, 0.95), lift3D ? lookahead + cadence - 1 : 0))
        print("BENCH thermal_trace " + thermalTrace.joined(separator: " "))
        perfLog?.close()
        let documents2 = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for dir in ["workout_videos", "workout_form_logs"] { try? FileManager.default.removeItem(at: documents2.appendingPathComponent(dir)) }
    }

    private func firstImage(_ clip: URL) throws -> CGImage? {
        let asset = AVURLAsset(url: clip)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: asset.tracks(withMediaType: .video)[0], outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()
        defer { reader.cancelReading() }
        guard let sample = output.copyNextSampleBuffer(), let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return context.createCGImage(image, from: image.extent)
    }

}

/// One set's evaluator (CameraPoseViewModel.setup / runEvaluator). Main thread only.
private final class SetSession {
    let exercise: FormExercise
    let tracker: FormWarningTracker
    let evaluate: (Int, [PoseKeypoint], FootKeypoints?, [SIMD3<Double>]?, Pose3DState?) -> (String, Int)

    init(exercise: FormExercise) {
        self.exercise = exercise
        switch exercise {
        case .squat:
            let e = SquatEvaluator()
            tracker = e.formTracker
            evaluate = { let r = e.evaluate(frameIndex: $0, coco17: $1, pose3D: $3, pose3DState: $4, feet: $2); return (r.status.rawValue, r.rep) }
        case .pushUp:
            let e = PushUpEvaluator()
            tracker = e.formTracker
            evaluate = { i, k, _, p, s in let r = e.evaluate(frameIndex: i, coco17: k, pose3D: p, pose3DState: s); return (r.status.rawValue, r.rep) }
        default:
            let e = BarbellRowEvaluator()
            tracker = e.formTracker
            evaluate = { i, k, _, p, s in let r = e.evaluate(frameIndex: i, coco17: k, pose3D: p, pose3DState: s); return (r.status.rawValue, r.rep) }
        }
    }

    func evaluate(frameIndex: Int, coco17: [PoseKeypoint], feet: FootKeypoints?, pose3D: [SIMD3<Double>]?, state: Pose3DState?) -> (String, Int) {
        evaluate(frameIndex, coco17, feet, pose3D, state)
    }
}
