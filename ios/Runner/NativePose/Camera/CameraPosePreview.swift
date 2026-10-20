import AVFoundation
internal import Combine
import CoreImage
import CoreML
import SwiftUI
import UIKit

// MARK: - Options

private enum CameraPreviewOptions {
    /// Xcode scheme environment: BPT_CAMERA_HANDS=1 (all on), 0 (all off), unset (exercise policy).
    static let handBranchOverride: Bool? = {
        switch ProcessInfo.processInfo.environment["BPT_CAMERA_HANDS"] {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }()
    /// MotionAGFormer-XS live 3D (MotionAGFormerLive → Pose3DConstraints → 3D posture judgement).
    /// ai/lift-app ONLY: true here, with motionagformer_xs.mlpackage bundled. integration/ai keeps false until the user
    /// approves the flip (docs/results/lift_app.md). BPT_CAMERA_3D=0 in the Xcode scheme turns it off for A/B profiling;
    /// then the evaluators judge in 2D (form3DRequired off) and the HUD gets no pose3d state.
    static let enableMotion3DForCamera = ProcessInfo.processInfo.environment["BPT_CAMERA_3D"] != "0"
    /// Output row 26 − lookahead (5 = 167 ms at 30 fps; see lift_app.md lookahead study).
    static let motion3DLookahead = Int(ProcessInfo.processInfo.environment["BPT_3D_LOOKAHEAD"] ?? "") ?? 5
    /// One XS inference per N frames, N rows read from it (every frame still gets its own 3D).
    static let motion3DCadence = Int(ProcessInfo.processInfo.environment["BPT_3D_CADENCE"] ?? "") ?? 1
    /// XS on its own serial queue (2D capture queue is free for the next frame); "0" = inline on the capture queue.
    static let motion3DAsync = ProcessInfo.processInfo.environment["BPT_3D_ASYNC"] != "0"
    /// MediaPipe wrists into the XS input (MotionAGFormerWristSource); the hand branch then runs for every exercise.
    static let motion3DWristFromHands = ProcessInfo.processInfo.environment["BPT_3D_HAND_WRISTS"] != "0"
    /// CoreMotion gravity as "up" for the 3D trunk/hip metrics (D-D-07: oblique trunk needs gravity). Off until the
    /// XS-frame axis mapping (FormGeometry.cameraUp) is checked on a device; BPT_3D_GRAVITY=1 turns it on.
    static let motion3DGravity = ProcessInfo.processInfo.environment["BPT_3D_GRAVITY"] == "1"
    /// EXPERIMENTAL confidence-aware relation constraint after Pose3DConstraints (AdaptiveRelationConstraint, ai/setup-constraint).
    /// Off unless BPT_ADAPTIVE_3D=1: not validated as a default (docs/results/setup_constraint_prereg.md).
    static let adaptive3D = ProcessInfo.processInfo.environment["BPT_ADAPTIVE_3D"] == "1"
    /// RTMPose input: 3:4 person crop from the previous frame's keypoints (RTMPoseCropTracker).
    /// false = old input, whole frame stretched to 192×256 every frame.
    static let personCropInput = true
    static let handCropSize = 256.0
    static let wristConfidenceThreshold = 0.3
    static let useMediaPipeWristFor2DBodyOverlay = true
    static let debugLogEveryNFrames = 60
}

// MARK: - Frame data (lightweight, no arrays)

struct CameraFrameData: Identifiable {
    let id: Int
    let frameIndex: Int
    let imageWidth: Double
    let imageHeight: Double
    let coco17: [PoseKeypoint]
    let rawCoco17: [PoseKeypoint]
    let handResults: [HandLandmarkResult]
    let exerciseTitle: String
    let statusText: String
    let rep: Int
    let done: Bool
}

struct CameraProcessingResult {
    let frameIndex: Int
    let imageWidth: Double
    let imageHeight: Double
    let visualCoco17: [PoseKeypoint]
    let rawCoco17: [PoseKeypoint]
    let feet: FootKeypoints?
    let handResults: [HandLandmarkResult]
    /// CACurrentMediaTime when the frame reached processFrame (input → judgement latency).
    var arrivedAt: CFTimeInterval = 0
    /// XS input wrists replaced by MediaPipe (left, right); raw wrists stay in rawCoco17.
    var wristsReplaced = (left: false, right: false)
}

// MARK: - Camera capture manager

private final class CameraCaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    let session = AVCaptureSession()
    private(set) var isFrontCamera = false
    private let processingQueue = DispatchQueue(label: "com.coremlpose.camera.processing", qos: .userInitiated)
    nonisolated(unsafe) private var isProcessingFrame = false
    nonisolated(unsafe) private var frameIndex = 0
    /// (frame, index, arrival time). Arrival = when the frame reached the app (camera: captureOutput entry; video
    /// mode: its pacing slot), the start of the input → judgement latency.
    nonisolated(unsafe) var onFrame: (@Sendable (CMSampleBuffer, Int, CFTimeInterval) -> Void)?
    /// Video-as-camera: the processing queue is busy with a frame (drop rule of alwaysDiscardsLateVideoFrames).
    private let busyLock = NSLock()
    nonisolated(unsafe) private var externalBusy = false
    // Per-set recording of the processed frames + perf counters (WorkoutSessionBridge.swift). Processing queue.
    nonisolated(unsafe) private var recorder: WorkoutSetRecorder?
    nonisolated(unsafe) var perfLog: WorkoutPerfLog?

    func startRecording(to url: URL) {
        processingQueue.async { [weak self] in self?.recorder = WorkoutSetRecorder(url: url) }
    }

    /// Closes the current set file; completion (any thread) gets its URL or nil.
    func finishRecording(_ completion: @escaping @Sendable (URL?) -> Void) {
        processingQueue.async { [weak self] in
            guard let recorder = self?.recorder else { return completion(nil) }
            self?.recorder = nil
            recorder.finish(completion)
        }
    }

    func configure() throws {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        let preferredDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

        guard let device = preferredDevice else {
            session.commitConfiguration()
            throw NSError(domain: "CameraCaptureManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera device found (neither front nor back wide angle)."])
        }
        isFrontCamera = (device.position == .front)

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw NSError(domain: "CameraCaptureManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input to session."])
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            throw error
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: processingQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw NSError(domain: "CameraCaptureManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output to session."])
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = isFrontCamera
            }
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        session.commitConfiguration()
    }

    func start() {
        processingQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        processingQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isProcessingFrame else { perfLog?.frameDropped(); return }
        isProcessingFrame = true
        handleFrame(sampleBuffer, arrival: CACurrentMediaTime())
        isProcessingFrame = false
    }

    /// The per-frame entry both sources share (processing queue).
    nonisolated private func handleFrame(_ sampleBuffer: CMSampleBuffer, arrival: CFTimeInterval) {
        let idx = frameIndex
        frameIndex += 1
        onFrame?(sampleBuffer, idx, arrival)
        recorder?.append(sampleBuffer)
        perfLog?.frameProcessed()
        VideoRunLog.shared?.count("processed")
    }

    /// Video-as-camera (VideoCameraSource): same queue and entry as captureOutput. A frame that arrives while the
    /// previous one is still being processed is dropped, as AVCaptureVideoDataOutput does with
    /// alwaysDiscardsLateVideoFrames. Returns false when dropped.
    nonisolated func deliverExternal(_ sampleBuffer: CMSampleBuffer, arrival: CFTimeInterval) -> Bool {
        busyLock.lock()
        if externalBusy {
            busyLock.unlock()
            perfLog?.frameDropped()
            VideoRunLog.shared?.count("dropped")
            return false
        }
        externalBusy = true
        busyLock.unlock()
        VideoRunLog.shared?.count("arrived")
        processingQueue.async { [self] in
            handleFrame(sampleBuffer, arrival: arrival)
            busyLock.lock()
            externalBusy = false
            busyLock.unlock()
        }
        return true
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        perfLog?.frameDropped()
    }
}

// MARK: - ViewModel

@MainActor
final class CameraPoseViewModel: ObservableObject {
    @Published var currentFrame: CameraFrameData?
    @Published var statusText = "Initializing..."
    @Published var cameraPermissionDenied = false

    private let exercise: NativePoseExercise
    private let captureManager = CameraCaptureManager()
    private let ciContext = CIContext(options: nil)

    var captureSession: AVCaptureSession {
        captureManager.session
    }

    var isFrontCamera: Bool {
        captureManager.isFrontCamera
    }

    // Flutter channel: rep/status (HUD is rendered on the Flutter side), onFeedback {key, n?, scope}
    // (kori_feedback_lines.dart), onSetEnd; startSet / endSet / setVoiceMuted come back.
    private let bridge: WorkoutChannel?
    private var lastReportedRep: Int?
    private var lastReportedStatus: String?
    private var lastReportedDone: Bool?
    private var formLog: WorkoutFormLog?
    private var lastLoggedRep = 0
    private var betweenSets = false
    private var recording = false
    private var perfTimer: Timer?

    // Models (loaded once)
    private var rtmpose: MLModel?
    private var handLandmarkers: MediaPipeHandLandmarkerPair?

    // Evaluators (only one active)
    private var deadliftEvaluator: DeadliftEvaluator?
    private var benchPressEvaluator: BenchPressEvaluator?
    private var squatEvaluator: SquatEvaluator?
    private var barbellRowEvaluator: BarbellRowEvaluator?
    private var pushUpEvaluator: PushUpEvaluator?

    /// Only touched on the capture processing queue (one frame at a time), like the workspace.
    nonisolated(unsafe) private var cropTracker = RTMPoseCropTracker()
    /// Live 3D. Only touched on `liftQueue` (serial, frame order kept).
    nonisolated(unsafe) private var lifter: MotionAGFormerLive<CameraProcessingResult>?
    private let liftQueue = DispatchQueue(label: "com.bpt.camera.lift3d", qos: .userInitiated)
    private var lastReportedPose3D: String?
    private var motion: DeviceMotionMonitor?
    nonisolated private var perfLog: WorkoutPerfLog? { captureManager.perfLog }
    /// Video-as-camera (test-only, BPT_CAMERA_VIDEO); nil with the real camera.
    private var videoSource: VideoCameraSource?
    @Published var videoDisplayLayer: AVSampleBufferDisplayLayer?
    /// Frame being judged (handleLifted), for the run log's Flutter reply latencies.
    private var judgingFrame: (index: Int, arrival: CFTimeInterval)?
    /// Personalized exercise setup (experimental): only when Flutter sent `exerciseSetup: true`.
    private let setupOptions: ExerciseSetup.Options?
    private var exerciseSetup: ExerciseSetup?
    private var setupVariant: String?
    private var setupSeeded = false
    private var lastSetupSignature: String?
    private var lastSetupSent: CFTimeInterval = 0

    init(exercise: NativePoseExercise, bridge: WorkoutChannel? = nil, setupOptions: ExerciseSetup.Options? = nil) {
        self.exercise = exercise
        self.bridge = bridge
        self.setupOptions = setupOptions
        self.setupVariant = setupOptions?.variant
    }

    func requestCameraAndStart() {
        if VideoCameraOptions.isActive { return setup() }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.setup()
                } else {
                    self.cameraPermissionDenied = true
                    self.statusText = "Camera permission denied"
                }
            }
        }
    }

    func stopCamera() {
        videoSource?.stop()
        captureManager.stop()
        motion?.stop()
        captureManager.finishRecording { _ in }
        if let tracker = formTracker { formLog?.close(tracker) }
        formLog = nil
        perfTimer?.invalidate()
        perfTimer = nil
        captureManager.perfLog?.close()
        captureManager.perfLog = nil
        bridge?.voice.stop()
    }

    private var formTracker: FormWarningTracker? {
        squatEvaluator?.formTracker ?? pushUpEvaluator?.formTracker ?? barbellRowEvaluator?.formTracker
            ?? benchPressEvaluator?.formTracker ?? deadliftEvaluator?.formTracker
    }

    /// Every frame: forward the tracker's feedback events and log each newly closed rep report.
    private func reportForm() {
        guard let tracker = formTracker else { return }
        // Bench press closes a rep's report 0.5 s after the count (lockout window), so log by rep index.
        for report in tracker.reports where report.repIndex > lastLoggedRep {
            formLog?.append(report)
            lastLoggedRep = report.repIndex
            if let log = VideoRunLog.shared {
                var line = report.dictionary
                line["judged_frame"] = judgingFrame?.index ?? -1
                log.write("rep", line)
            }
        }
        for event in tracker.drainEvents() {
            guard let log = VideoRunLog.shared else { bridge?.sendFeedback(event); continue }
            let frame = judgingFrame
            var line: [String: Any] = ["key": event.key, "scope": event.scope.rawValue, "frame": frame?.index ?? -1]
            if let n = event.n { line["n"] = n }
            log.write("feedback_sent", line)
            bridge?.sendFeedback(event) { reply in
                var done = line
                done["reply"] = reply.map { "\($0)" } ?? NSNull()
                if let arrival = frame?.arrival { done["e2e_ms"] = (CACurrentMediaTime() - arrival) * 1000 }
                log.write("feedback_reply", done)
            }
        }
    }

    // MARK: Sets (Flutter startSet / endSet)

    private func startSet(_ index: Int) {
        betweenSets = false
        guard WorkoutDebugFlags.setRecording, let directory = WorkoutSetRecorder.directory() else { return }
        recording = true
        WorkoutSetRecorder.prune(directory: directory, keep: WorkoutSetRecorder.keepFiles - 1)
        let name = WorkoutSetRecorder.fileName(exercise: exercise.rawValue, setIndex: index)
        captureManager.startRecording(to: directory.appendingPathComponent(name))
    }

    /// Set-scope feedback (참고 keys, n = reps in the set), then onSetEnd once the file is closed.
    private func endSet(_ index: Int) {
        guard !betweenSets else { return }
        betweenSets = true
        recording = false
        // The last `lookahead` frames are still in the 3D window: judge them (window clamped at the newest frame)
        // before the set summary.
        guard lifter != nil else { return finishEndSet(index) }
        liftQueue.async { [weak self] in
            guard let self else { return }
            let tail = (try? self.lifter?.flush()) ?? []
            Task { @MainActor in
                for (result, frame3D) in tail { self.handleLifted(result, frame3D) }
                self.finishEndSet(index)
            }
        }
    }

    private func finishEndSet(_ index: Int) {
        let tracker = formTracker
        let worstJoint = tracker.flatMap {
            FeedbackJoint.worst(setCounts: $0.endSet(), enabled: $0.common.enabledFeedbackKeys,
                                ruleOrder: (FormWarningTracker.rules[$0.exercise] ?? []).map(\.key))
        }
        for event in tracker?.drainEvents() ?? [] { bridge?.sendFeedback(event) }
        captureManager.finishRecording { [weak self] url in
            Task { @MainActor in
                self?.bridge?.sendSetEnd(setIndex: index, videoLocalPath: url?.path, worstJoint: worstJoint)
            }
        }
    }

    private func startPerfLog() {
        guard WorkoutDebugFlags.perfLog, let log = WorkoutPerfLog(exercise: exercise.rawValue) else { return }
        captureManager.perfLog = log
        UIDevice.current.isBatteryMonitoringEnabled = true
        perfTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                log.flush(battery: UIDevice.current.batteryLevel, recording: self.recording)
            }
        }
    }

    private func setup() {
        let workspace: RTMPoseInputWorkspace
        do {
            rtmpose = try loadModel(named: RTMPoseModel.workout.rawValue)
            workspace = try RTMPoseInputWorkspace()
        } catch {
            statusText = "Failed to load RTMPose: \(error.localizedDescription)"
            return
        }

        switch exercise {
        case .deadlift: deadliftEvaluator = DeadliftEvaluator()
        case .benchPress: benchPressEvaluator = BenchPressEvaluator()
        case .squat: squatEvaluator = SquatEvaluator()
        case .barbellRow: barbellRowEvaluator = BarbellRowEvaluator()
        case .pushUp: pushUpEvaluator = PushUpEvaluator()
        }
        if let tracker = formTracker { formLog = WorkoutFormLog(exercise: tracker.exercise) }

        if CameraPreviewOptions.enableMotion3DForCamera {
            // 3D is part of the analysis: no silent 2D-only fallback when the model is missing.
            do {
                let xs = try loadModel(named: "motionagformer_xs")
                lifter = MotionAGFormerLive(lookahead: CameraPreviewOptions.motion3DLookahead,
                                            cadence: CameraPreviewOptions.motion3DCadence,
                                            predict: MotionAGFormerCoreML.predictor(xs))
                lifter?.constraints.reflectFlippedKnee = exercise == .squat  // Fit3D S6: squat only
                if CameraPreviewOptions.adaptive3D, let formExercise = formTracker?.exercise {
                    lifter?.adaptive = AdaptiveRelationConstraint(exercise: formExercise)
                }
                formTracker?.common.form3DRequired = true
                if VideoCameraOptions.allFeedbackKeys {
                    // NON-DEFAULT test flag: show what every warning key WOULD send to the user.
                    formTracker?.common.enabledFeedbackKeys = FormWarningTracker.allKeys
                }
                if CameraPreviewOptions.motion3DGravity {
                    motion = DeviceMotionMonitor()
                    motion?.start()
                }
            } catch {
                statusText = "Failed to load MotionAGFormer-XS: \(error.localizedDescription)"
                return
            }
        }

        let handEnabled = (CameraPreviewOptions.enableMotion3DForCamera && CameraPreviewOptions.motion3DWristFromHands)
            || exercise.handBranchEnabled(override: CameraPreviewOptions.handBranchOverride)
        if handEnabled {
            handLandmarkers = MediaPipeHandLandmarkerPair()
            print("CameraPosePreview hand landmarkers initialized: \(handLandmarkers?.statusDescription ?? "nil")")
        }

        if VideoCameraOptions.isActive {
            let manager = captureManager
            let source = VideoCameraSource(
                urls: VideoCameraOptions.clips, loops: VideoCameraOptions.loops,
                deliver: { sampleBuffer, arrival in manager.deliverExternal(sampleBuffer, arrival: arrival) },
                onFinish: { [weak self] in Task { @MainActor in self?.videoFinished() } })
            videoSource = source
            videoDisplayLayer = source.displayLayer
        } else {
            do {
                try captureManager.configure()
            } catch {
                statusText = "Failed to configure camera: \(error.localizedDescription)"
                return
            }
        }

        let rtmposeModel = self.rtmpose
        let handLandmarkRunner = self.handLandmarkers
        let context = self.ciContext

        captureManager.onFrame = { [weak self, context] sampleBuffer, frameIdx, arrival in
            guard let self, let rtmposeModel else { return }
            self.processFrame(
                sampleBuffer,
                frameIdx: frameIdx,
                arrival: arrival,
                rtmpose: rtmposeModel,
                workspace: workspace,
                handLandmarkers: handLandmarkRunner,
                ciContext: context
            )
        }

        bridge?.onStartSet = { [weak self] in self?.startSet($0) }
        bridge?.onEndSet = { [weak self] in self?.endSet($0) }
        if let options = setupOptions, lifter != nil, let formExercise = formTracker?.exercise {
            exerciseSetup = ExerciseSetup(exercise: formExercise, reference: options.reference)
            bridge?.onResetSetup = { [weak self] in self?.resetSetup() }
            bridge?.onSetSetupVariant = { [weak self] variant, reference in
                self?.setupVariant = variant
                if let reference { self?.exerciseSetup?.reference = reference }
                self?.lastSetupSignature = nil
            }
        }
        startSet(1)
        startPerfLog()
        if let videoSource { videoSource.start() } else { captureManager.start() }
        statusText = "Running"
        VideoRunLog.shared?.write("camera_started", [
            "exercise": exercise.rawValue, "hands": handEnabled, "xs": lifter != nil,
            "lookahead": CameraPreviewOptions.motion3DLookahead, "cadence": CameraPreviewOptions.motion3DCadence,
            "async": CameraPreviewOptions.motion3DAsync, "wrists_from_hands": CameraPreviewOptions.motion3DWristFromHands,
            "gravity": CameraPreviewOptions.motion3DGravity,
            "enabled_feedback_keys": Array(formTracker?.common.enabledFeedbackKeys ?? []).sorted(),
            "form3d_required": formTracker?.common.form3DRequired ?? false,
            "reflect_flipped_knee": lifter?.constraints.reflectFlippedKnee ?? false,
            "adaptive_3d": CameraPreviewOptions.adaptive3D, "exercise_setup": exerciseSetup != nil,
            "rtmpose": RTMPoseModel.workout.rawValue,
        ])
        print("CameraPosePreview started exercise=\(exercise.rawValue) hand=\(handEnabled) 3d=\(lifter != nil) lookahead=\(CameraPreviewOptions.motion3DLookahead) cadence=\(CameraPreviewOptions.motion3DCadence) async=\(CameraPreviewOptions.motion3DAsync)")
    }

    private nonisolated func processFrame(
        _ sampleBuffer: CMSampleBuffer,
        frameIdx: Int,
        arrival: CFTimeInterval,
        rtmpose: MLModel,
        workspace: RTMPoseInputWorkspace,
        handLandmarkers: MediaPipeHandLandmarkerPair?,
        ciContext: CIContext
    ) {
        autoreleasepool {
            do {
                let arrivedAt = arrival
                let timestampMs = Self.timestampMs(sampleBuffer, fallback: frameIdx)
                let cgImage = try Self.cgImageFromSampleBuffer(sampleBuffer, ciContext: ciContext)
                guard let estimate = try cropTracker.estimate(cgImage, model: rtmpose, workspace: workspace,
                                                              personCrop: CameraPreviewOptions.personCropInput) else {
                    return
                }
                let decoded = estimate.decoded, inverseAffine = estimate.inverseAffine
                let rawCoco17 = estimate.coco17

                // Hand branch
                let handResults: [HandLandmarkResult]
                let leftHand: HandLandmarkResult?
                let rightHand: HandLandmarkResult?
                if let handLandmarkers = handLandmarkers {
                    let handImage = UIImage(cgImage: cgImage)
                    let handFrame = BundledVideoHandFrameProcessor.runWristCropHands(
                        image: handImage,
                        rawCoco17: rawCoco17,
                        imageWidth: Double(cgImage.width),
                        imageHeight: Double(cgImage.height),
                        timestampMs: timestampMs,
                        handLandmarkers: handLandmarkers,
                        cropSize: CameraPreviewOptions.handCropSize,
                        confidenceThreshold: CameraPreviewOptions.wristConfidenceThreshold
                    )
                    handResults = handFrame.handResults
                    leftHand = handFrame.leftHand
                    rightHand = handFrame.rightHand
                } else {
                    handResults = []
                    leftHand = nil
                    rightHand = nil
                }

                let visualCoco17 = HandCropBuilder.visualBodyKeypoints(
                    rawBodyKeypoints: rawCoco17,
                    leftHand: leftHand,
                    rightHand: rightHand,
                    useMediaPipeWrist: CameraPreviewOptions.useMediaPipeWristFor2DBodyOverlay
                )

                var result = CameraProcessingResult(
                    frameIndex: frameIdx,
                    imageWidth: Double(cgImage.width),
                    imageHeight: Double(cgImage.height),
                    visualCoco17: visualCoco17,
                    rawCoco17: rawCoco17,
                    feet: PoseCoordinateTransforms.applyInverseAffineToFeet(
                        decoded: decoded,
                        inverseAffine: inverseAffine
                    ),
                    handResults: handResults
                )
                result.arrivedAt = arrivedAt

                guard lifter != nil else {
                    Task { @MainActor [weak self] in
                        self?.handleProcessingResult(result)
                    }
                    return
                }
                // 3D path: the XS input gets the MediaPipe wrists (same frame, computed above); the overlay shows the
                // 2D at once, the evaluators get frame t with its own 3D `lookahead` frames later.
                let point = { (hand: HandLandmarkResult?) in hand?.wristFramePoint.map { PosePoint(x: $0.x, y: $0.y) } }
                let wrists = CameraPreviewOptions.motion3DWristFromHands
                    ? MotionAGFormerWristSource.input(raw: rawCoco17, left: point(leftHand), right: point(rightHand))
                    : MotionAGFormerWristSource.Result(input: rawCoco17)
                result.wristsReplaced = (wrists.replacedLeft, wrists.replacedRight)
                perfLog?.sample("pose2d_hands", ms: (CACurrentMediaTime() - arrivedAt) * 1000)
                let shown = result
                Task { @MainActor [weak self] in self?.showFrame(shown) }
                let lift = { [weak self] in
                    guard let self else { return }
                    let t0 = CACurrentMediaTime()
                    do {
                        let before = self.lifter?.inferences ?? 0
                        let ready = try self.lifter?.push(frameIndex: frameIdx, coco17: wrists.input, imageWidth: cgImage.width,
                                                          imageHeight: cgImage.height, payload: shown) ?? []
                        let liftMs = (CACurrentMediaTime() - t0) * 1000
                        self.perfLog?.sample("lift3d", ms: liftMs)
                        if let log = VideoRunLog.shared {
                            log.count("xs_inferences", (self.lifter?.inferences ?? 0) - before)
                            log.count("lift_us", Int(liftMs * 1000))
                        }
                        Task { @MainActor [weak self] in
                            for (r, frame3D) in ready { self?.handleLifted(r, frame3D) }
                        }
                    } catch {
                        print("CameraPosePreview 3D error frame=\(frameIdx): \(error)")
                    }
                }
                if CameraPreviewOptions.motion3DAsync { liftQueue.async(execute: lift) } else { liftQueue.sync(execute: lift) }
            } catch {
                if frameIdx % CameraPreviewOptions.debugLogEveryNFrames == 0 {
                    print("CameraPosePreview frame processing error: \(error)")
                }
            }
        }
    }

    /// Overlay only (3D path): the newest 2D right away, status/rep from the last judged frame.
    @MainActor
    private func showFrame(_ result: CameraProcessingResult) {
        currentFrame = CameraFrameData(
            id: result.frameIndex, frameIndex: result.frameIndex, imageWidth: result.imageWidth,
            imageHeight: result.imageHeight, coco17: result.visualCoco17, rawCoco17: result.rawCoco17,
            handResults: result.handResults, exerciseTitle: exercise.displayName,
            statusText: lastReportedStatus ?? "", rep: lastReportedRep ?? 0, done: lastReportedDone ?? false)
    }

    /// 3D path: frame t with its own 2D and 3D (state never hidden: it goes to the evaluators and to Flutter).
    @MainActor
    private func handleLifted(_ result: CameraProcessingResult, _ frame3D: Lifted3DFrame) {
        if let state = motion?.state, state.isAvailable, state.gravity.count == 3 {
            formTracker?.up3D = FormGeometry.cameraUp(gravity: SIMD3(state.gravity[0], state.gravity[1], state.gravity[2]),
                                                      frontCamera: isFrontCamera)
        }
        let t0 = CACurrentMediaTime()
        judgingFrame = (result.frameIndex, result.arrivedAt)
        let (statusText, rep, done) = runEvaluator(frameIndex: result.frameIndex, rawCoco17: result.rawCoco17,
                                                   feet: result.feet, pose3D: frame3D.masked3D, pose3DState: frame3D.state)
        let now = CACurrentMediaTime()
        perfLog?.sample("evaluate", ms: (now - t0) * 1000)
        perfLog?.sample("latency_input_to_judgement", ms: (now - result.arrivedAt) * 1000)
        perfLog?.judged()
        let pose3D = Pose3DBridge.payload(frame3D)
        let pose3DKey = "\(frame3D.state.rawValue)/\(frame3D.state == .warmingUp ? frame3D.filled : 0)"
        let setup = rep == 0 ? updateSetup(frame3D, now: now) : nil  // the setup panel lives before the first rep
        if rep != lastReportedRep || statusText != lastReportedStatus || done != lastReportedDone || pose3DKey != lastReportedPose3D
            || setup != nil {
            lastReportedRep = rep
            lastReportedStatus = statusText
            lastReportedDone = done
            lastReportedPose3D = pose3DKey
            if let log = VideoRunLog.shared {
                let arrival = result.arrivedAt, frame = result.frameIndex
                bridge?.sendUpdate(rep: rep, status: statusText, done: done, pose3d: pose3D, setup: setup) { _ in
                    log.write("update_reply", ["frame": frame, "rep": rep, "status": statusText,
                                               "state3d": frame3D.state.rawValue,
                                               "e2e_ms": (CACurrentMediaTime() - arrival) * 1000])
                }
            } else {
                bridge?.sendUpdate(rep: rep, status: statusText, done: done, pose3d: pose3D, setup: setup)
            }
        }
        if let log = VideoRunLog.shared {
            log.count("judged")
            var line: [String: Any] = [
                "frame": result.frameIndex, "arrival": log.rel(result.arrivedAt), "state": frame3D.state.rawValue,
                "status": statusText, "rep": rep, "judge_ms": (now - result.arrivedAt) * 1000,
                "eval_ms": (now - t0) * 1000, "wrists": [result.wristsReplaced.left, result.wristsReplaced.right],
            ]
            if let row = frame3D.row { line["row"] = row }
            if frame3D.state == .warmingUp { line["filled"] = frame3D.filled }
            if let a = frame3D.adaptive {
                if !a.filled.isEmpty { line["adaptive_filled"] = a.filled.keys.sorted() }
                if !a.invalid.isEmpty { line["adaptive_invalid"] = a.invalid }
                let events = a.relations.compactMapValues(\.event)
                if !events.isEmpty { line["adaptive_events"] = events }
            }
            if let c = frame3D.constraints {
                line["invalid"] = Array(c.invalidJoints).sorted()
                if c.kneesReflected > 0 { line["knees_reflected"] = c.kneesReflected }
                if c.kneeHyperextended { line["knee_flip"] = true }
                if !c.angleCorrections.isEmpty { line["angle_corr"] = c.angleCorrections }
                line["bone_corr"] = (c.boneMaxCorrection * 1000).rounded() / 1000
            }
            log.write("judged", line)
        }
        if result.frameIndex % CameraPreviewOptions.debugLogEveryNFrames == 0 {
            print("CameraPosePreview frame=\(result.frameIndex) status=\(statusText) rep=\(rep) 3d=\(frame3D.state.rawValue) row=\(frame3D.row.map(String.init) ?? "-") wrists=\(result.wristsReplaced)")
        }
    }

    /// Experimental exercise setup for this judged frame; the payload when it changed meaningfully (≤ 5 Hz), else nil.
    /// On the first ready it seeds the adaptive relations (only when that constraint is on).
    @MainActor
    private func updateSetup(_ frame3D: Lifted3DFrame, now: CFTimeInterval) -> [String: Any]? {
        guard exerciseSetup != nil else { return nil }
        let up = formTracker?.up3D ?? FormGeometry.up3D
        guard let state = exerciseSetup?.update(frame3D.usable3D, confidence: frame3D.confidence ?? [],
                                                usable: frame3D.usable3D != nil, up: up, unit: frame3D.unit ?? 1),
              let setup = exerciseSetup else { return nil }
        if state.phase == .ready && !setupSeeded {
            setupSeeded = true
            let seeds = setup.seeds(AdaptiveRelationConstraint.relations(for: setup.exercise))
            liftQueue.async { [weak self] in
                for (name, seed) in seeds { self?.lifter?.adaptive?.seedReference(name: name, refPx: seed.ref, spreadPx: seed.spread) }
            }
            VideoRunLog.shared?.write("setup_ready", ["snapshot": setup.ready ?? [:], "seeds": Array(seeds.keys).sorted()])
        }
        let signature = ExerciseSetupBridge.signature(state)
        guard signature != lastSetupSignature, now - lastSetupSent >= 0.2 else { return nil }
        lastSetupSignature = signature
        lastSetupSent = now
        return ExerciseSetupBridge.payload(state, exercise: setup.exercise, variant: setupVariant, snapshot: setup.ready)
    }

    /// Flutter "다시 설정": measure the setup again and drop the relations it seeded.
    private func resetSetup() {
        exerciseSetup?.reset()
        setupSeeded = false
        lastSetupSignature = nil
        liftQueue.async { [weak self] in self?.lifter?.adaptive?.reset() }
    }

    @MainActor
    private func handleProcessingResult(_ result: CameraProcessingResult) {
        let (statusText, rep, done) = self.runEvaluator(frameIndex: result.frameIndex, rawCoco17: result.rawCoco17,
                                                        feet: result.feet, pose3D: nil, pose3DState: nil)

        let frameData = CameraFrameData(
            id: result.frameIndex,
            frameIndex: result.frameIndex,
            imageWidth: result.imageWidth,
            imageHeight: result.imageHeight,
            coco17: result.visualCoco17,
            rawCoco17: result.rawCoco17,
            handResults: result.handResults,
            exerciseTitle: self.exercise.displayName,
            statusText: statusText,
            rep: rep,
            done: done
        )

        self.currentFrame = frameData

        // Only notify Flutter when the meaningful state actually changes.
        if rep != lastReportedRep || statusText != lastReportedStatus || done != lastReportedDone {
            lastReportedRep = rep
            lastReportedStatus = statusText
            lastReportedDone = done
            bridge?.sendUpdate(rep: rep, status: statusText, done: done)
        }

        if result.frameIndex % CameraPreviewOptions.debugLogEveryNFrames == 0 {
            print("CameraPosePreview frame=\(result.frameIndex) exercise=\(self.exercise.rawValue) status=\(statusText) rep=\(rep) done=\(done) hands=\(result.handResults.count)")
        }
    }

    private func runEvaluator(frameIndex: Int, rawCoco17: [PoseKeypoint], feet: FootKeypoints?,
                              pose3D: [SIMD3<Double>]?, pose3DState: Pose3DState?) -> (status: String, rep: Int, done: Bool) {
        switch exercise {
        case .deadlift:
            if let eval = deadliftEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17, pose3D: pose3D, pose3DState: pose3DState)
                reportForm()
                return (r.status.rawValue, r.rep, r.done)
            }
        case .benchPress:
            if let eval = benchPressEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17, pose3D: pose3D, pose3DState: pose3DState)
                reportForm()
                return (r.status.rawValue, r.rep, r.done)
            }
        case .squat:
            if let eval = squatEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17, pose3D: pose3D, pose3DState: pose3DState, feet: feet)
                reportForm()
                return (r.status.rawValue, r.rep, r.done)
            }
        case .barbellRow:
            if let eval = barbellRowEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17, pose3D: pose3D, pose3DState: pose3DState)
                reportForm()
                return (r.status.rawValue, r.rep, r.done)
            }
        case .pushUp:
            if let eval = pushUpEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17, pose3D: pose3D, pose3DState: pose3DState)
                reportForm()
                return (r.status.rawValue, r.rep, r.done)
            }
        }
        return ("inactive", 0, false)
    }

    /// Video-as-camera: the clip list ended. Like the real app with main's workout screen, no endSet arrives, so the
    /// frames still in the 3D window are not flushed and no set-scope keys / onSetEnd are produced.
    private func videoFinished() {
        guard let log = VideoRunLog.shared else { return }
        let tracker = formTracker
        log.write("session_end", [
            "reps": tracker?.reports.count ?? 0,
            "frames_3d": tracker?.sessionFrames3D ?? 0,
            "bad_3d_frames": tracker?.sessionBad3DFrames ?? 0,
            "warning_rep_counts": tracker?.warningRepCounts ?? [:],
            "set_warning_rep_counts": tracker?.setWarningRepCounts ?? [:],
            "last_rep": lastReportedRep ?? 0,
            "last_status": lastReportedStatus ?? "",
            "end_set_received": betweenSets,
        ])
    }

    private func loadModel(named name: String) throws -> MLModel {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: name, withExtension: "mlpackage") else {
            throw NSError(domain: "CameraPosePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing model: \(name)"])
        }
        return try MLModel(contentsOf: url, configuration: config)
    }

    private nonisolated static func cgImageFromSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        ciContext: CIContext
    ) throws -> CGImage {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw NSError(domain: "CameraPosePreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing pixel buffer"])
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw NSError(domain: "CameraPosePreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "CGImage creation failed"])
        }
        return cgImage
    }

    private nonisolated static func timestampMs(_ sampleBuffer: CMSampleBuffer, fallback: Int) -> Int {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let seconds = CMTimeGetSeconds(timestamp)
        if seconds.isFinite && seconds >= 0.0 {
            return Int((seconds * 1000.0).rounded())
        }
        return fallback * 33
    }
}

// MARK: - SwiftUI View

struct CameraPosePreview: View {
    let exercise: NativePoseExercise
    @StateObject private var model: CameraPoseViewModel

    init(exercise: NativePoseExercise, bridge: WorkoutChannel? = nil, setupOptions: ExerciseSetup.Options? = nil) {
        self.exercise = exercise
        _model = StateObject(wrappedValue: CameraPoseViewModel(exercise: exercise, bridge: bridge, setupOptions: setupOptions))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.cameraPermissionDenied {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Camera Access Required")
                        .font(.title3.bold())
                    Text("Enable camera access in Settings to use live pose analysis.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                CameraLiveView(
                    session: model.captureSession,
                    videoLayer: model.videoDisplayLayer,
                    isMirrored: model.isFrontCamera,
                    frame: model.currentFrame,
                    statusText: model.statusText
                )
            }
        }
        .ignoresSafeArea()
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.requestCameraAndStart()
        }
        .onDisappear {
            model.stopCamera()
        }
    }
}

// MARK: - Live camera preview with overlays

private struct CameraLiveView: View {
    let session: AVCaptureSession
    /// Video-as-camera preview (test-only); nil = the camera preview.
    let videoLayer: AVSampleBufferDisplayLayer?
    let isMirrored: Bool
    let frame: CameraFrameData?
    let statusText: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Group {
                    if let videoLayer {
                        VideoPreviewLayerView(layer: videoLayer)
                    } else {
                        CameraPreviewLayerView(session: session, isMirrored: isMirrored)
                    }
                }
                    .frame(width: proxy.size.width, height: proxy.size.height)

                if let frame {
                    Canvas { context, size in
                        drawSkeleton(frame: frame, context: &context, size: size)
                        drawHands(frame: frame, context: &context, size: size)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(statusText)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }

                // HUD (rep/status) is rendered by Flutter at the bottom of the
                // screen — intentionally no native top-left overlay here.
            }
            .background(Color.black)
            .clipped()
        }
    }

    private func drawSkeleton(frame: CameraFrameData, context: inout GraphicsContext, size: CGSize) {
        let rect = aspectFillRect(imageWidth: frame.imageWidth, imageHeight: frame.imageHeight, in: size)
        for edge in coco17Edges {
            guard edge.0 < frame.coco17.count, edge.1 < frame.coco17.count else { continue }
            let a = frame.coco17[edge.0]
            let b = frame.coco17[edge.1]
            let minConfidence = min(a.confidence, b.confidence)
            let color = minConfidence >= 0.3 ? Color.green : Color.gray.opacity(0.35)
            var path = Path()
            path.move(to: viewPoint(a, frame: frame, rect: rect))
            path.addLine(to: viewPoint(b, frame: frame, rect: rect))
            context.stroke(path, with: .color(color), lineWidth: minConfidence >= 0.3 ? 4.0 : 2.0)
        }

        for keypoint in frame.coco17 {
            let point = viewPoint(keypoint, frame: frame, rect: rect)
            let radius = keypoint.confidence >= 0.3 ? 5.0 : 3.0
            let color = keypoint.confidence >= 0.3 ? Color.yellow : Color.gray.opacity(0.35)
            let circle = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2.0, height: radius * 2.0)
            context.fill(Path(ellipseIn: circle), with: .color(color))
        }
    }

    private func drawHands(frame: CameraFrameData, context: inout GraphicsContext, size: CGSize) {
        let rect = aspectFillRect(imageWidth: frame.imageWidth, imageHeight: frame.imageHeight, in: size)
        HandOverlayRenderer.drawHands(
            frame.handResults,
            context: &context,
            imageWidth: frame.imageWidth,
            imageHeight: frame.imageHeight,
            rect: rect
        )
    }

    private func viewPoint(_ keypoint: PoseKeypoint, frame: CameraFrameData, rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + CGFloat(keypoint.x / frame.imageWidth) * rect.width,
            y: rect.minY + CGFloat(keypoint.y / frame.imageHeight) * rect.height
        )
    }

    private func aspectFillRect(imageWidth: Double, imageHeight: Double, in size: CGSize) -> CGRect {
        guard imageWidth > 0, imageHeight > 0, size.width > 0, size.height > 0 else {
            return .zero
        }
        let scale = max(size.width / CGFloat(imageWidth), size.height / CGFloat(imageHeight))
        let width = CGFloat(imageWidth) * scale
        let height = CGFloat(imageHeight) * scale
        return CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.5,
            width: width,
            height: height
        )
    }

    private var coco17Edges: [(Int, Int)] {
        [
            (0, 1), (0, 2), (1, 3), (2, 4),
            (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),
            (5, 11), (6, 12), (11, 12),
            (11, 13), (13, 15), (12, 14), (14, 16),
        ]
    }
}

private struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.configure(session: session, isMirrored: isMirrored)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.configure(session: session, isMirrored: isMirrored)
    }
}

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func configure(session: AVCaptureSession, isMirrored: Bool) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        previewLayer.videoGravity = .resizeAspectFill

        guard let connection = previewLayer.connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
    }
}

// MARK: - HUD

private struct CameraHUD: View {
    let frame: CameraFrameData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(frame.exerciseTitle.capitalized)
                .font(.caption.bold())
                .foregroundStyle(.white)

            Text("Status: \(frame.statusText)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))

            Text("Rep: \(frame.rep)  Done: \(frame.done ? "yes" : "no")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))

            Text("Hands: \(frame.handResults.count)  Frame: \(frame.frameIndex)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(8)
        .background(Color.black.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
