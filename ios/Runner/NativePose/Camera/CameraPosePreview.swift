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
    /// Explicit experiment only. Live camera/contact anchoring is NOT implemented: both are unknown.
    /// Assertions below are a controlled harness, never detected conditions or GT-seeded wrist locations.
    static let supportCorridor = ProcessInfo.processInfo.environment["BPT_PUSHUP_SUPPORT_CORRIDOR"] == "1"
    static let fixedSupportReplay = ProcessInfo.processInfo.environment["BPT_SUPPORT_FIXED_REPLAY"] == "1"
    static func controlledSupport(at pts: Double) -> Bool {
        guard VideoCameraOptions.isActive, fixedSupportReplay,
              let value = ProcessInfo.processInfo.environment["BPT_SUPPORT_CONTACT_PTS"] else { return false }
        let bounds = value.split(separator: ":", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Double(bounds[0]), let end = Double(bounds[1]),
              start.isFinite, end.isFinite, start < end else { return false }
        return pts.isFinite && pts >= start && pts <= end
    }
    /// Old independent experiment, OFF unless explicitly requested; never activated by supportCorridor.
    static let wristAnchor = ProcessInfo.processInfo.environment["BPT_WRIST_ANCHOR"] == "1"
    /// RTMPose input: 3:4 person crop from the previous frame's keypoints (RTMPoseCropTracker).
    /// false = old input, whole frame stretched to 192×256 every frame.
    static let personCropInput = true
    static let handCropSize = 256.0
    static let wristConfidenceThreshold = 0.3
    /// Both wrist crops returned the same hand (landmark-box IoU > 0.5): neither MediaPipe wrist is used
    /// (MotionAGFormerWristSource.sameHand). ai/lift-refine only; BPT_HAND_DEDUPE=0 = old behaviour.
    static let handDedupe = ProcessInfo.processInfo.environment["BPT_HAND_DEDUPE"] != "0"
    static let debugLogEveryNFrames = 60
}

// MARK: - Frame data (lightweight, no arrays)

struct CameraFrameData: Identifiable {
    let id: Int
    let frameIndex: Int
    /// The keypoints, hands and image size here are in the analysis frame; the overlay maps them onto the preview with
    /// this (`.up` in portrait).
    let rotation: CaptureRotation
    let imageWidth: Double
    let imageHeight: Double
    /// What the overlay draws: the XS input 2D (accepted wrists only), display-smoothed.
    let coco17: [PoseKeypoint]
    let rawCoco17: [PoseKeypoint]
    let handResults: [HandLandmarkResult]
    let exerciseTitle: String
    let statusText: String
    let rep: Int
    let done: Bool
    /// Inferred wrist endpoints/segments are dashed, without confident joint dots.
    var supportUncertainJoints: Set<Int> = []
    /// Typed scoped shades: neutral withholding, relative-only consistency, or measured rule geometry/deviation.
    var shade: [OverlaySegment: OverlayShade] = [:]
}

struct CameraProcessingResult {
    let frameIndex: Int
    /// Quarter turn from the camera buffer to the analysis frame everything below is in (gravity down the image).
    let rotation: CaptureRotation
    let imageWidth: Double
    let imageHeight: Double
    /// The XS input 2D (RTMPose + accepted MediaPipe wrists): drawn by the overlay, so a drawn wrist never sits on a
    /// hand the XS input refused.
    let visualCoco17: [PoseKeypoint]
    let rawCoco17: [PoseKeypoint]
    let feet: FootKeypoints?
    let handResults: [HandLandmarkResult]
    /// CACurrentMediaTime when the frame reached processFrame (input → judgement latency).
    var arrivedAt: CFTimeInterval = 0
    /// Original capture/video sample PTS, carried with this frame through XS lookahead. Never a latency clock.
    var sourcePTS: Double?
    var sourceTimeValue: Int64?
    var sourceTimeScale: Int32?
    var terminalEpoch: Int?
    var terminalDetector2D: [PoseKeypoint]?
    /// XS input wrists replaced by MediaPipe (left, right); raw wrists stay in rawCoco17.
    var wristsReplaced = (left: false, right: false)
    /// Both wrist crops returned the same hand and neither MediaPipe wrist was used (CameraPreviewOptions.handDedupe).
    var sameHandDropped = false
    /// WristFloorAnchor states (left, right) when that experiment is on; then visualCoco17 = rawCoco17 = XS input.
    var wristAnchor: [String]?
    var supportCorridor: PushUpSupportEvidence2D.Output?
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
    nonisolated(unsafe) var recordingRotation = 0
    nonisolated(unsafe) var perfLog: WorkoutPerfLog?

    func afterPendingExternalFrames(_ completion: @escaping @Sendable () -> Void) {
        TerminalEvidenceIngressFence.afterPending(on: processingQueue, completion: completion)
    }

    func startRecording(to url: URL) {
        processingQueue.async { [weak self] in self?.recorder = WorkoutSetRecorder(url: url) }
    }

    /// Closes the current set file; completion (any thread) gets its URL or nil.
    func finishRecording(_ completion: @escaping @Sendable (URL?, [Int: Double], Double) -> Void) {
        processingQueue.async { [weak self] in
            guard let recorder = self?.recorder else { return completion(nil, [:], 0) }
            self?.recorder = nil
            let times = recorder.frameTimesMs, duration = recorder.durationMs
            recorder.finish { completion($0, times, duration) }
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
        recorder?.append(sampleBuffer, frameIndex: idx, rotationDegrees: recordingRotation)
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
    /// Test mode only (video mode, BPT_CAMERA_VIDEO): the last rep's real judgement as a small caption; nil otherwise.
    @Published var debugCaption: String?

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
    nonisolated private let terminalCapture = TerminalEvidenceCapture()
    private var terminalFlushing = false
    private var terminalJudgingEpoch: Int?
    private var terminalSetIndex: Int?
    private var terminalEndRequest: (epoch: Int, flush: Bool, host: Double)?
    private var terminalDrainTimer: Timer?

    private func finalizeTerminalDrain(forceIncomplete: Bool = false) {
        guard let request = terminalEndRequest, let status = terminalCapture.drainStatus(request.epoch),
              status.pending == 0 || forceIncomplete else { return }
        terminalEndRequest = nil
        terminalDrainTimer?.invalidate(); terminalDrainTimer = nil
        let complete = request.flush && !status.failed && !forceIncomplete
        candidateEnd(epoch: request.epoch, reason: complete ? "set_end" : "incomplete_source_drain", hostTime: request.host)
        VideoRunLog.shared?.write("terminal_end", ["epoch": request.epoch, "reason": "set_end", "flush_complete": request.flush,
            "incomplete": !complete, "source_drain_pending": status.pending, "source_drain_failed": status.failed,
            "active_rep_start": formTracker?.diagnosticActiveRepStart as Any? ?? NSNull()])
        terminalCapture.finish(request.epoch)
    }

    private func requestTerminalDrain(epoch: Int, flushSucceeded: Bool, hostTime: Double) {
        guard terminalCapture.accepts(epoch) else { return }
        terminalEndRequest = (epoch, flushSucceeded, hostTime)
        finalizeTerminalDrain()
        if terminalEndRequest != nil {
            terminalDrainTimer?.invalidate()
            // Diagnostic bounded shutdown, not a form/extension threshold.
            terminalDrainTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.terminalEndRequest?.epoch == epoch else { return }
                    self.finalizeTerminalDrain(forceIncomplete: true)
                }
            }
        }
    }
    private var terminalCandidate = TerminalObservationCandidate()
    private var terminalCandidateTimer: Timer?

    private func candidateLog<T: Encodable>(_ type: String, _ value: T) {
        guard VideoRunLog.terminalCandidate else { return }
        guard let data = try? JSONEncoder().encode(value), let payload = try? JSONSerialization.jsonObject(with: data) else {
            VideoRunLog.shared?.invalidateTerminalEvidence()
            return
        }
        VideoRunLog.shared?.write(type, ["payload": payload, "candidate_protocol": "bpt.terminal-candidate.v1"])
    }
    private func candidateReports() {
        for report in terminalCandidate.drain() { candidateLog("terminal_candidate_report", report) }
        if terminalCandidate.pendingRep == nil { terminalCandidateTimer?.invalidate(); terminalCandidateTimer = nil }
    }
    private func candidateEnd(epoch: Int, reason: String, hostTime: Double? = nil) {
        guard VideoRunLog.terminalCandidate else { return }
        let now = hostTime ?? CACurrentMediaTime()
        VideoRunLog.shared?.write("terminal_candidate_end", ["epoch": epoch, "reason": reason, "host_time": now])
        terminalCandidate.end(epoch: epoch, reason: reason, hostTime: now)
        candidateReports()
    }
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
    /// Phone held in landscape (CaptureRotation): CoreMotion gravity through the hysteresis tracker, which is only
    /// touched on the capture processing queue. The BPT_FORCE_CAPTURE_ROTATION launch override needs no CoreMotion.
    nonisolated(unsafe) private var rotationTracker = CaptureRotationTracker(rotation: CaptureRotation.forced ?? .up)
    nonisolated(unsafe) private let rotationMotion = CaptureRotation.forced == nil ? DeviceMotionMonitor() : nil

    /// Only touched on the capture processing queue (one frame at a time), like the workspace.
    nonisolated(unsafe) private var cropTracker = RTMPoseCropTracker()
    /// Live 3D. Only touched on `liftQueue` (serial, frame order kept).
    nonisolated(unsafe) private var lifter: MotionAGFormerLive<CameraProcessingResult>?
    /// Push-up support experiment; capture queue only. Immutable result accompanies each source frame.
    nonisolated(unsafe) private var supportEvidence = PushUpSupportEvidence2D(enabled: CameraPreviewOptions.supportCorridor)
    nonisolated(unsafe) private var supportEpoch = 0
    nonisolated private let supportControl = PushUpSupportExperimentControl()
    nonisolated(unsafe) private var wristAnchor: WristFloorAnchor?
    nonisolated(unsafe) private var wristAnchorLastFrame = Int.min / 2
    nonisolated(unsafe) private var wristAnchorResetPending = false
    /// The push-up set is underway (a rep counted, or the setup became ready): the wrist anchor may take its reference.
    nonisolated(unsafe) private var wristAnchorActive = false
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
    /// This judged frame's setup state for VideoRunLog (debug only: why "ready" did or did not come).
    private var setupLog: [String: Any]?
    private var lastSetupSignature: String?
    private var lastSetupSent: CFTimeInterval = 0
    /// Scoped overlay evidence from the last judged frame (display only); only severity is smoothed.
    private var liveSeverity = OverlayState()
    private var severityTrack = OverlaySeverityTrack()
    private var overlaySmoother = OverlaySmoother()
    /// Screen auto-lock while the workout camera runs (a set has no touches): the value before we disabled it, nil when
    /// we hold nothing. Restored when the camera stops or the app goes to the background, set again on return.
    private var idleTimerBefore: Bool?
    private var cameraRunning = false
    private var lifecycleObservers: [NSObjectProtocol] = []

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
        if VideoRunLog.terminalEvidence, let epoch = terminalCapture.beginFlush() {
            candidateEnd(epoch: epoch, reason: "camera_stop")
            VideoRunLog.shared?.write("terminal_end", ["epoch": epoch, "reason": "camera_stop", "flush_complete": false, "incomplete": true])
            terminalCapture.finish(epoch)
        }
        terminalDrainTimer?.invalidate(); terminalDrainTimer = nil; terminalEndRequest = nil
        cameraRunning = false
        keepScreenAwake(false, reason: "camera_stop")
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers = []
        videoSource?.stop()
        captureManager.stop()
        motion?.stop()
        captureManager.finishRecording { _, _, _ in }
        if let tracker = formTracker { formLog?.close(tracker) }
        formLog = nil
        perfTimer?.invalidate()
        perfTimer = nil
        captureManager.perfLog?.close()
        captureManager.perfLog = nil
        bridge?.voice.stop()
        rotationMotion?.stop()
    }

    private func keepScreenAwake(_ on: Bool, reason: String) {
        let app = UIApplication.shared
        if on, idleTimerBefore == nil {
            idleTimerBefore = app.isIdleTimerDisabled
            app.isIdleTimerDisabled = true
        } else if !on, let before = idleTimerBefore {
            app.isIdleTimerDisabled = before
            idleTimerBefore = nil
        } else {
            return
        }
        print("[Workout] idle timer disabled=\(app.isIdleTimerDisabled) (\(reason))")
        VideoRunLog.shared?.write("idle_timer", ["disabled": app.isIdleTimerDisabled, "reason": reason])
    }

    private func observeAppLifecycle() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.keepScreenAwake(false, reason: "background") }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.cameraRunning else { return }
                    self.keepScreenAwake(true, reason: "foreground")
                }
            },
        ]
    }

    private var experimentalCoaching = ExperimentalCoaching()
    private let experimentalCoachingEnabled = DemoConfig.environment["BPT_EXPERIMENTAL_COACHING"] == "1"

    private var formTracker: FormWarningTracker? {
        squatEvaluator?.formTracker ?? pushUpEvaluator?.formTracker ?? barbellRowEvaluator?.formTracker
            ?? benchPressEvaluator?.formTracker ?? deadliftEvaluator?.formTracker
    }

    /// Every frame: forward the tracker's feedback events and log each newly closed rep report.
    private func reportForm() {
        guard let tracker = formTracker else { return }
        liveSeverity = tracker.liveSeverity()
        let newReport = tracker.reports.last.flatMap { $0.repIndex > lastLoggedRep ? $0 : nil }
        // Bench press closes a rep's report 0.5 s after the count (lockout window), so log by rep index.
        for report in tracker.reports where report.repIndex > lastLoggedRep {
            formLog?.append(report)
            if VideoRunLog.terminalEvidence, let epoch = terminalJudgingEpoch, terminalCapture.accepts(epoch) {
                if VideoRunLog.terminalCandidate, [.squat, .pushUp].contains(tracker.exercise) {
                    let metrics = tracker.exercise == .squat ? ["knee": "knee_max", "hip": "hip_angle_max"] : ["elbow": "elbow_max"]
                    let original = TerminalObservationCandidate.Original(epoch: epoch, exercise: tracker.exercise.rawValue,
                        rep: report.repIndex, startFrame: report.startFrame, endFrame: report.endFrame, side: report.side,
                        threshold: tracker.exercise == .squat ? tracker.squat.noLockoutBelowSetMaxDegrees : tracker.pushUp.noLockoutBelowSetMaxDegrees,
                        originalMaxima: Dictionary(uniqueKeysWithValues: metrics.compactMap { k, v in report.metrics3D[v].map { (k, $0) } }))
                    let host = CACurrentMediaTime()
                    candidateLog("terminal_candidate_begin", TerminalObservationCandidate.Begin(original: original, hostTime: host))
                    terminalCandidate.begin(original, hostTime: host)
                    candidateReports()
                    terminalCandidateTimer?.invalidate()
                    terminalCandidateTimer = Timer.scheduledTimer(withTimeInterval: terminalCandidate.config.timeoutSeconds, repeats: false) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self, self.terminalCapture.accepts(epoch), self.terminalCandidate.pendingRep == original.rep else { return }
                            let now = CACurrentMediaTime()
                            VideoRunLog.shared?.write("terminal_candidate_tick", ["epoch": epoch, "rep": original.rep, "host_time": now])
                            self.terminalCandidate.expire(epoch: epoch, rep: original.rep, hostTime: now)
                            self.candidateReports()
                        }
                    }
                }
                VideoRunLog.shared?.write("terminal_rep", ["epoch": epoch, "rep": report.repIndex,
                    "start_frame": report.startFrame, "end_frame": report.endFrame,
                    "side": report.side, "form_source": report.formSource])
            }
            lastLoggedRep = report.repIndex
            DemoPoseLog.shared?.write("rep", ["rep": report.repIndex, "warnings": report.warnings,
                                              "warnings_3d": report.warnings3D ?? [], "form_source": report.formSource])
            if let log = VideoRunLog.shared {
                var line = report.dictionary
                line["judged_frame"] = judgingFrame?.index ?? -1
                log.write("rep", line)
            }
        }
        let events = tracker.drainEvents()
        // TRIAL BRANCH ONLY: BPT_DEBUG_CAPTION=0 (bpt_demo.json) hides the test-mode caption for demo recordings.
        if VideoCameraOptions.isActive, DemoConfig.environment["BPT_DEBUG_CAPTION"] != "0", let report = newReport {
            debugCaption = report.debugCaption(sent: events.map(\.key), enabled: tracker.common.enabledFeedbackKeys)
        }
        for event in events {
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
        if VideoRunLog.terminalEvidence {
            if let old = terminalCapture.beginFlush() {
                candidateEnd(epoch: old, reason: "superseded_set")
                VideoRunLog.shared?.write("terminal_end", ["epoch": old, "reason": "superseded_set", "flush_complete": false, "incomplete": true])
            }
            terminalDrainTimer?.invalidate(); terminalDrainTimer = nil; terminalEndRequest = nil
            let epoch = terminalCapture.begin()
            terminalSetIndex = index
            VideoRunLog.shared?.write("terminal_start", ["epoch": epoch, "exercise": exercise.rawValue,
                "set": index, "time_basis": "sample_pts_seconds", "lookahead": CameraPreviewOptions.motion3DLookahead,
                "cadence": CameraPreviewOptions.motion3DCadence, "raw_source": "xs_output_before_constraints"])
            if VideoRunLog.terminalCandidate {
                candidateLog("terminal_candidate_config", terminalCandidate.config)
                terminalCandidate.start(epoch: epoch)
                VideoRunLog.shared?.write("terminal_candidate_start", ["epoch": epoch])
            }
        }
        VideoRunLog.shared?.write("start_set", ["set": index])
        betweenSets = false
        guard WorkoutDebugFlags.setRecording, let directory = WorkoutSetRecorder.directory() else { return }
        recording = true
        WorkoutSetRecorder.prune(directory: directory, keep: WorkoutSetRecorder.keepFiles - 1)
        let name = WorkoutSetRecorder.fileName(exercise: exercise.rawValue, setIndex: index)
        captureManager.startRecording(to: directory.appendingPathComponent(name))
    }

    /// Set-scope feedback (참고 keys, n = reps in the set), then onSetEnd once the file is closed.
    private func endSet(_ index: Int) {
        VideoRunLog.shared?.write("end_set_received", ["set": index, "between_sets": betweenSets])
        guard !betweenSets else { return }
        betweenSets = true
        let evidenceEpoch = VideoRunLog.terminalEvidence ? terminalCapture.beginFlush() : nil
        let evidenceEndHost = CACurrentMediaTime()
        recording = false
        // The last `lookahead` frames are still in the 3D window: judge them (window clamped at the newest frame)
        // before the set summary.
        guard lifter != nil else { return finishEndSet(index, evidenceEpoch: evidenceEpoch, evidenceEndHost: evidenceEndHost) }
        liftQueue.async { [weak self] in
            guard let self else { return }
            let flushed = try? self.lifter?.flush()
            let tail = flushed ?? []
            let flushSucceeded = flushed != nil
            VideoRunLog.shared?.write("end_set_flush", ["set": index, "tail_frames": tail.count,
                                                        "tail_states": tail.map { $0.1.state.rawValue },
                                                        "tail_frame_index": tail.map { $0.1.frameIndex }])
            Task { @MainActor in
                let currentEvidence = self.terminalCapture.accepts(evidenceEpoch)
                if currentEvidence { self.terminalFlushing = true }
                for (result, frame3D) in tail { self.handleLifted(result, frame3D) }
                if currentEvidence { self.terminalFlushing = false }
                self.finishEndSet(index, evidenceEpoch: evidenceEpoch, flushSucceeded: flushSucceeded, evidenceEndHost: evidenceEndHost)
            }
        }
    }

    private func finishEndSet(_ index: Int, evidenceEpoch: Int? = nil, flushSucceeded: Bool = false, evidenceEndHost: Double? = nil) {
        defer {
            if VideoRunLog.terminalEvidence, let epoch = evidenceEpoch, terminalCapture.accepts(epoch) {
                requestTerminalDrain(epoch: epoch, flushSucceeded: flushSucceeded, hostTime: evidenceEndHost ?? CACurrentMediaTime())
            }
        }
        // 심층분석용 반복 목록에 마지막 벤치 반복까지 넣는다. 녹화가 꺼진 기본 동작은 그대로 둔다.
        if WorkoutDebugFlags.setRecording {
            benchPressEvaluator?.finishPendingFormRep()
            reportForm()
        }
        let tracker = formTracker
        let worstJoint = tracker.flatMap {
            FeedbackJoint.worst(setCounts: $0.endSet(), enabled: $0.common.enabledFeedbackKeys,
                                ruleOrder: (FormWarningTracker.rules[$0.exercise] ?? []).map(\.key))
        }
        for event in tracker?.drainEvents() ?? [] {
            guard let log = VideoRunLog.shared else { bridge?.sendFeedback(event); continue }
            var line: [String: Any] = ["key": event.key, "scope": event.scope.rawValue, "frame": -1, "set": index]
            if let n = event.n { line["n"] = n }
            log.write("feedback_sent", line)
            bridge?.sendFeedback(event) { reply in
                var done = line
                done["reply"] = reply.map { "\($0)" } ?? NSNull()
                log.write("feedback_reply", done)
            }
        }
        VideoRunLog.shared?.write("set_end_sent", ["set": index, "worst_joint": worstJoint ?? NSNull()])
        let reports = tracker?.reports ?? []
        captureManager.finishRecording { [weak self] url, times, duration in
            Task { @MainActor in
                var reps: [[String: Any]] = []
                var previousEnd = 0.0
                for report in reports {
                    guard let first = times[report.startFrame], let last = times[report.endFrame] else { continue }
                    // 앞 반복의 마지막 관측 프레임을 공유해도 다음 반복을 통째로 버리지 않는다.
                    let start = max(first, previousEnd)
                    let end = min(duration, last + 1000 / 30)
                    guard end - start >= 100 else { continue }
                    reps.append(["repIndex": reps.count + 1, "startMs": start, "endMs": end,
                                 "side": report.side, "onDeviceWarnings": report.warnings,
                                 "onDeviceRepIndex": report.repIndex,
                                 "onDeviceMetrics2D": report.metrics2D.filter { $0.value.isFinite },
                                 "onDeviceMetrics3D": report.metrics3D.filter { $0.value.isFinite }])
                    previousEnd = end
                }
                let metadata: [String: Any] = ["schemaVersion": 1, "sessionId": UUID().uuidString,
                                               "timebase": "video_ms", "reps": reps]
                self?.bridge?.sendSetEnd(setIndex: index, videoLocalPath: url?.path, worstJoint: worstJoint,
                                         deepAnalysis: url == nil || reps.isEmpty ? nil : metadata)
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
                // Test-only (video mode driver): the clip subject's calibration bone lengths, as a calibration result would give.
                lifter?.constraints.calibrationTargetsCm = VideoCameraOptions.boneTargetsCm
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

        if !CameraPreviewOptions.supportCorridor && (CameraPreviewOptions.wristAnchor || WristFloorAnchor.enabledByFlutter) && exercise == .pushUp { wristAnchor = WristFloorAnchor() }
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
        rotationMotion?.start()
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
        cameraRunning = true
        keepScreenAwake(true, reason: "camera_start")
        observeAppLifecycle()
        statusText = "Running"
        VideoRunLog.shared?.write("camera_started", [
            "exercise": exercise.rawValue, "hands": handEnabled, "xs": lifter != nil,
            "lookahead": CameraPreviewOptions.motion3DLookahead, "cadence": CameraPreviewOptions.motion3DCadence,
            "async": CameraPreviewOptions.motion3DAsync, "wrists_from_hands": CameraPreviewOptions.motion3DWristFromHands,
            "gravity": CameraPreviewOptions.motion3DGravity,
            "forced_capture_rotation": CaptureRotation.forced.map { $0.rawValue as Any } ?? NSNull(),
            "enabled_feedback_keys": Array(formTracker?.common.enabledFeedbackKeys ?? []).sorted(),
            "form3d_required": formTracker?.common.form3DRequired ?? false,
            "reflect_flipped_knee": lifter?.constraints.reflectFlippedKnee ?? false,
            "adaptive_3d": CameraPreviewOptions.adaptive3D, "exercise_setup": exerciseSetup != nil, "wrist_anchor": wristAnchor != nil,
            "bone_targets": VideoCameraOptions.boneTargetsCm.map { ["file": VideoCameraOptions.environment["BPT_BONE_TARGETS"] ?? "",
                                                                     "segments": $0.count] as Any } ?? NSNull(),
            "hand_dedupe": CameraPreviewOptions.handDedupe,
            "idle_timer_disabled": UIApplication.shared.isIdleTimerDisabled,
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
        let terminalEpoch = VideoRunLog.terminalEvidence ? terminalCapture.capture(frame: frameIdx) : nil
        var terminalHandedOff = false
        defer {
            if !terminalHandedOff { terminalCapture.delivered(epoch: terminalEpoch, frame: frameIdx, failed: true) }
        }
        autoreleasepool {
            do {
                let arrivedAt = arrival
                let timestampMs = Self.timestampMs(sampleBuffer, fallback: frameIdx)
                // From here on everything (crop, RTMPose, hands, evaluators, 3D input) is in the analysis frame.
                let rotation = updateCaptureRotation()
                captureManager.recordingRotation = -rotation.rawValue
                let cgImage = try Self.cgImageFromSampleBuffer(sampleBuffer, ciContext: ciContext, rotation: rotation)
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

                // XS input wrists: MediaPipe where accepted (same-hand dedupe, reject crossed, forearm gate), else RTMPose.
                // The overlay draws the same 2D, so its wrist never jumps to the other hand (lift-refine).
                let point = { (hand: HandLandmarkResult?) in hand?.wristFramePoint.map { PosePoint(x: $0.x, y: $0.y) } }
                let landmarks = { (hand: HandLandmarkResult?) in hand?.frameLandmarks.map { PosePoint(x: $0.x, y: $0.y) } ?? [] }
                let sameHand = CameraPreviewOptions.handDedupe
                    && MotionAGFormerWristSource.sameHand(landmarks(leftHand), landmarks(rightHand))
                let wrists = (lifter == nil || CameraPreviewOptions.motion3DWristFromHands)
                    ? MotionAGFormerWristSource.input(raw: rawCoco17, left: point(leftHand), right: point(rightHand), sameHand: sameHand)
                    : MotionAGFormerWristSource.Result(input: rawCoco17)
                // Push-up wrist floor anchor (experimental): one wrist value for the overlay, the XS input and the
                // evaluators; a gap of 0.5 s without a person starts it over (as the 3D window).
                var anchoredInput = wrists.input
                var anchorStates: [String]?
                if wristAnchor != nil {
                    if wristAnchorResetPending || frameIdx - wristAnchorLastFrame > 15 {
                        wristAnchor?.reset()
                        wristAnchorResetPending = false
                    }
                    wristAnchorLastFrame = frameIdx
                    if let anchored = wristAnchor?.update(anchoredInput, active: wristAnchorActive) {
                        anchoredInput = anchored.keypoints
                        anchorStates = WristFloorAnchor.wrists.map { anchored.states[$0.0]?.rawValue ?? "none" }
                    }
                }
                let input2D = anchoredInput
                let visualCoco17 = input2D
                let sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let sourcePTS = CMTimeGetSeconds(sourceTime)
                var supportOutput: PushUpSupportEvidence2D.Output?
                if CameraPreviewOptions.supportCorridor && exercise == .pushUp {
                    let control = supportControl.snapshot()
                    if estimate.recheckSwitched == true { supportEpoch += 1; supportEvidence.reset() }
                    // Inverse-affine crop region changes are conservative reset boundaries, even though coordinates
                    // have been transformed back into the analysis image. No old crop identity is assumed stable.
                    let crop = "\(inverseAffine.a),\(inverseAffine.b),\(inverseAffine.c),\(inverseAffine.d),\(inverseAffine.e),\(inverseAffine.f)"
                    supportOutput = supportEvidence.update(.init(keypoints: input2D, sourcePTS: sourcePTS,
                        width: Double(cgImage.width), height: Double(cgImage.height), rotation: rotation.rawValue,
                        epoch: "\(control.generation)/\(supportEpoch)/\(crop)", supportActive: control.eligible && CameraPreviewOptions.controlledSupport(at: sourcePTS),
                        cameraEvidence: VideoCameraOptions.isActive && CameraPreviewOptions.fixedSupportReplay
                            ? .controlledReplayAssertion : .unknown, sameHandRejected: sameHand))
                }

                var result = CameraProcessingResult(
                    frameIndex: frameIdx,
                    rotation: rotation,
                    imageWidth: Double(cgImage.width),
                    imageHeight: Double(cgImage.height),
                    visualCoco17: visualCoco17,
                    rawCoco17: CameraPreviewOptions.supportCorridor ? rawCoco17 : (anchorStates != nil ? input2D : rawCoco17),
                    feet: PoseCoordinateTransforms.applyInverseAffineToFeet(
                        decoded: decoded,
                        inverseAffine: inverseAffine
                    ),
                    handResults: handResults
                )
                result.arrivedAt = arrivedAt
                result.supportCorridor = supportOutput
                result.sourcePTS = sourcePTS.isFinite ? sourcePTS : nil
                result.sourceTimeValue = sourceTime.isValid ? sourceTime.value : nil
                result.sourceTimeScale = sourceTime.isValid ? sourceTime.timescale : nil
                result.terminalEpoch = terminalEpoch
                if terminalEpoch != nil { result.terminalDetector2D = rawCoco17 }
                result.wristAnchor = anchorStates

                guard lifter != nil else {
                    terminalCapture.delivered(epoch: terminalEpoch, frame: frameIdx, failed: true)
                    terminalHandedOff = true
                    Task { @MainActor [weak self] in
                        self?.handleProcessingResult(result)
                    }
                    return
                }
                // 3D path: the XS input gets the MediaPipe wrists (same frame, computed above); the overlay shows the
                // 2D at once, the evaluators get frame t with its own 3D `lookahead` frames later.
                result.wristsReplaced = (wrists.replacedLeft, wrists.replacedRight)
                result.sameHandDropped = sameHand && leftHand != nil && rightHand != nil
                perfLog?.sample("pose2d_hands", ms: (CACurrentMediaTime() - arrivedAt) * 1000)
                let shown = result
                terminalHandedOff = true
                Task { @MainActor [weak self] in self?.showFrame(shown) }
                let bookkeeping = terminalCapture
                let lift = { [weak self] in
                    guard let self else {
                        bookkeeping.delivered(epoch: shown.terminalEpoch, frame: frameIdx, failed: true)
                        return
                    }
                    let t0 = CACurrentMediaTime()
                    do {
                        let before = self.lifter?.inferences ?? 0
                        let ready = try self.lifter?.push(frameIndex: frameIdx, coco17: input2D, imageWidth: cgImage.width,
                                                          imageHeight: cgImage.height, captureRotation: shown.rotation,
                                                          payload: shown) ?? []
                        let liftMs = (CACurrentMediaTime() - t0) * 1000
                        self.perfLog?.sample("lift3d", ms: liftMs)
                        if let log = VideoRunLog.shared {
                            log.count("xs_inferences", (self.lifter?.inferences ?? 0) - before)
                            log.count("lift_us", Int(liftMs * 1000))
                        }
                        Task { @MainActor [weak self] in
                            for (r, frame3D) in ready {
                                if let self { self.handleLifted(r, frame3D) }
                                else { bookkeeping.delivered(epoch: r.terminalEpoch, frame: r.frameIndex, failed: true) }
                            }
                        }
                    } catch {
                        self.terminalCapture.delivered(epoch: shown.terminalEpoch, frame: frameIdx, failed: true)
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

    @MainActor
    private func displayKeypoints(_ result: CameraProcessingResult) -> [PoseKeypoint] {
        let smoothed = overlaySmoother.smooth(result.visualCoco17, at: CACurrentMediaTime())
        return result.supportCorridor?.display(over: smoothed) ?? smoothed
    }

    /// Overlay only (3D path): the newest 2D right away, status/rep from the last judged frame.
    @MainActor
    private func showFrame(_ result: CameraProcessingResult) {
        if currentFrame?.rotation != result.rotation { overlaySmoother = OverlaySmoother() }
        currentFrame = CameraFrameData(
            id: result.frameIndex, frameIndex: result.frameIndex, rotation: result.rotation, imageWidth: result.imageWidth,
            imageHeight: result.imageHeight, coco17: displayKeypoints(result),
            rawCoco17: result.rawCoco17, handResults: result.handResults, exerciseTitle: exercise.displayName,
            statusText: lastReportedStatus ?? "", rep: lastReportedRep ?? 0, done: lastReportedDone ?? false,
            supportUncertainJoints: result.supportCorridor?.uncertainJoints ?? [],
            shade: severityTrack.update(liveSeverity, at: CACurrentMediaTime()))
    }

    /// 3D path: frame t with its own 2D and 3D (state never hidden: it goes to the evaluators and to Flutter).
    @MainActor
    private func handleLifted(_ result: CameraProcessingResult, _ frame3D: Lifted3DFrame) {
        defer {
            terminalCapture.delivered(epoch: result.terminalEpoch, frame: result.frameIndex)
            finalizeTerminalDrain()
        }
        if let state = motion?.state, state.isAvailable, state.gravity.count == 3 {
            formTracker?.up3D = FormGeometry.cameraUp(gravity: SIMD3(state.gravity[0], state.gravity[1], state.gravity[2]),
                                                      frontCamera: isFrontCamera)
        }
        let t0 = CACurrentMediaTime()
        terminalJudgingEpoch = result.terminalEpoch
        judgingFrame = (result.frameIndex, result.arrivedAt)
        let (statusText, rep, done) = runEvaluator(frameIndex: result.frameIndex, rawCoco17: result.supportCorridor?.assessment2D(result.rawCoco17) ?? result.rawCoco17,
                                                   feet: result.feet, pose3D: result.supportCorridor?.assessment3D(frame3D.masked3D) ?? frame3D.masked3D, pose3DState: result.supportCorridor?.assessmentState(frame3D.state) ?? frame3D.state)
        if VideoRunLog.terminalEvidence, terminalCapture.accepts(result.terminalEpoch), let epoch = result.terminalEpoch {
            if VideoRunLog.terminalCandidate {
                let snapshot = formTracker?.terminalCandidateSnapshot
                let side = snapshot?.side
                var rawAngles: [String: Double] = [:]
                if let side, let raw = frame3D.raw, raw.count == 17 {
                    let ids = FormGeometry.h36mSide(side == "left" ? .left : .right)
                    for (name, points) in [("elbow", (ids.shoulder, ids.elbow, ids.wrist)), ("knee", (ids.hip, ids.knee, ids.ankle)), ("hip", (ids.shoulder, ids.hip, ids.knee))] {
                        if let value = FormGeometry.angle3D(raw[points.0], raw[points.1], raw[points.2]), value.isFinite { rawAngles[name] = value }
                    }
                }
                let input = TerminalObservationCandidate.Frame(epoch: epoch, frame: result.frameIndex,
                    sourceIndex: VideoCameraOptions.isActive ? VideoRunLog.shared?.clipFrame(result.frameIndex) : result.frameIndex,
                    sourceTime: result.sourcePTS, hostTime: CACurrentMediaTime(), activeRepStart: formTracker?.diagnosticActiveRepStart,
                    side: side, phase: snapshot?.phase, required2D: snapshot?.required2D ?? false, sideView: snapshot?.sideView,
                    state: (result.supportCorridor?.assessmentState(frame3D.state) ?? frame3D.state).rawValue,
                    flushed: terminalFlushing || frame3D.diagnosticFlushed,
                    coordinateKey: "\(result.imageWidth)/\(result.imageHeight)/\(result.rotation.rawValue)/\(isFrontCamera)",
                    assessmentAngles: snapshot?.angles ?? [:], rawAngles: rawAngles)
                var capturedInput = input
                capturedInput.setEndFlushTail = terminalFlushing
                candidateLog("terminal_candidate_frame", capturedInput)
                terminalCandidate.observe(capturedInput)
                candidateReports()
            }
            func flat(_ p: [SIMD3<Double>]?) -> Any {
                TerminalEvidence.vector(p?.flatMap { [$0.x, $0.y, $0.z] })
            }
            func kp(_ p: [PoseKeypoint]) -> Any {
                TerminalEvidence.vector(p.flatMap { [$0.x, $0.y, $0.confidence] })
            }
            let assessment = result.supportCorridor?.assessment3D(frame3D.masked3D) ?? frame3D.masked3D
            let confidence = result.supportCorridor?.assessmentConfidence(frame3D.confidence) ?? frame3D.confidence
            let up = formTracker?.up3D
            VideoRunLog.shared?.write("terminal_frame", ["epoch": epoch, "frame": result.frameIndex,
                "source_index": VideoCameraOptions.isActive ? (VideoRunLog.shared?.clipFrame(result.frameIndex) as Any? ?? NSNull()) : result.frameIndex,
                "source_kind": VideoCameraOptions.isActive ? "video_frame" : "camera_capture_index",
                "source_pts": TerminalEvidence.number(result.sourcePTS),
                "source_time_value": result.sourceTimeValue as Any? ?? NSNull(),
                "source_time_scale": result.sourceTimeScale as Any? ?? NSNull(), "time_basis": "sample_pts_seconds",
                "size": [result.imageWidth, result.imageHeight], "rotation": result.rotation.rawValue,
                "front_camera": isFrontCamera, "source_mirrored": VideoCameraOptions.isActive ? VideoCameraOptions.mirror : isFrontCamera,
                "raw_2d": result.terminalDetector2D.map(kp) ?? NSNull(), "input_2d": kp(result.visualCoco17),
                "assessment_2d": kp(result.supportCorridor?.assessment2D(result.rawCoco17) ?? result.rawCoco17),
                "raw_3d": flat(frame3D.raw), "constrained_3d": flat(frame3D.pose3D), "adapted_3d": flat(frame3D.adapted),
                "assessment_3d": flat(assessment), "confidence_h36m": TerminalEvidence.vector(confidence),
                "invalid": frame3D.invalidJoints.union(result.supportCorridor?.invalid3DJoints ?? []).sorted(),
                "raw_state": frame3D.state.rawValue,
                "assessment_state": (result.supportCorridor?.assessmentState(frame3D.state) ?? frame3D.state).rawValue,
                "phase": formTracker?.observationPhase as Any? ?? NSNull(),
                "active_rep_start": formTracker?.diagnosticActiveRepStart as Any? ?? NSNull(), "side": formTracker?.side?.rawValue as Any? ?? NSNull(),
                "side_view": formTracker?.sideView as Any? ?? NSNull(), "status": statusText, "rep": rep,
                "filled": frame3D.filled, "row": frame3D.row as Any? ?? NSNull(), "flush_tail": terminalFlushing || frame3D.diagnosticFlushed,
                "unit_px": TerminalEvidence.number(frame3D.unit),
                "judgement_up": TerminalEvidence.vector(up.map { [$0.x, $0.y, $0.z] }),
                "up_time_basis": "judgement_time_not_source_sensor", "source_gravity_available": false])
        }
        let now = CACurrentMediaTime()
        if experimentalCoachingEnabled {
            // Latest device gravity is not synchronized to this delayed XS source frame. It is also not
            // the camera gravity of a replayed clip. Keep the experimental metric withheld until a source
            // snapshot + sensor age or explicit clip calibration is carried in this same payload.
            let observation = ExperimentalCoaching.Frame(time: result.sourcePTS ?? .nan, exercise: formTracker?.exercise.rawValue ?? exercise.rawValue,
                phase: formTracker?.observationPhase,
                state: (result.supportCorridor?.assessmentState(frame3D.state) ?? frame3D.state).rawValue, raw: frame3D.raw,
                corrected: result.supportCorridor?.assessment3D(frame3D.masked3D) ?? frame3D.masked3D,
                confidence: result.supportCorridor?.assessmentConfidence(frame3D.confidence) ?? frame3D.confidence,
                invalid: frame3D.invalidJoints.union(result.supportCorridor?.invalid3DJoints ?? []), up: nil)
            // There is no approved variant/ROM profile in the current UI. Measurements are logged, candidates
            // explicitly withheld. These diagnostics cannot emit a warning, speech, or modify the existing pose.
            let output = experimentalCoaching.update(observation)
            if let data = try? JSONEncoder().encode(output),
               var line = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                line["frame"] = result.frameIndex
                line["time_basis"] = "sample_pts"
                line["arrival_host"] = result.arrivedAt
                line["exercise"] = exercise.rawValue
                line["phase"] = formTracker?.observationPhase ?? NSNull()
                line["state"] = observation.state
                line["raw_model_state"] = frame3D.state.rawValue
                DemoPoseLog.shared?.write("experimental_coaching", line)
                VideoRunLog.shared?.write("experimental_coaching", line)
            }
        }
        if let demo = DemoPoseLog.shared {
            let round = { (v: Double, k: Double) -> Double in (v * k).rounded() / k }
            var kp2d: [Double] = []
            for p in result.rawCoco17 { kp2d += [round(p.x, 10), round(p.y, 10), round(p.confidence, 1000)] }
            var line: [String: Any] = ["frame": result.frameIndex, "arrival_host": result.arrivedAt,
                                       "state": frame3D.state.rawValue, "rep": rep, "exercise": exercise.rawValue]
            line["size"] = [result.imageWidth, result.imageHeight]
            line["rotation"] = result.rotation.rawValue
            line["kp2d"] = kp2d
            if let joints = frame3D.pose3D {
                var flat: [Double] = []
                for j in joints { flat += [round(j.x, 1e4), round(j.y, 1e4), round(j.z, 1e4)] }
                line["pose3d"] = flat
            }
            if let unit = frame3D.unit { line["unit_px"] = unit }
            demo.write("frame", line)
        }
        perfLog?.sample("evaluate", ms: (now - t0) * 1000)
        perfLog?.sample("latency_input_to_judgement", ms: (now - result.arrivedAt) * 1000)
        perfLog?.judged()
        var pose3D = Pose3DBridge.payload(frame3D)
        var pose3DKey = Pose3DBridge.key(frame3D)
        if let support = result.supportCorridor {
            // Preserve the raw model state; the independent assessment veto has explicit provenance.
            pose3D["assessment_state"] = (support.assessmentState(frame3D.state) ?? frame3D.state).rawValue
            pose3D["support_invalid"] = support.invalid3DJoints.sorted()
            pose3DKey += "/support:" + support.invalid3DJoints.sorted().map(String.init).joined(separator: ",")
        }
        // the setup panel lives before the first rep; foot items only when the active 2D model gives Halpe26 feet
        let setup = rep == 0 ? updateSetup(frame3D, feet: result.feet, coco17: result.rawCoco17, now: now) : nil
        if rep >= 1 || setupSeeded { wristAnchorActive = true; supportControl.markReady() }
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
                "capture_rotation": result.rotation.rawValue,
                "status": statusText, "rep": rep, "judge_ms": (now - result.arrivedAt) * 1000,
                "eval_ms": (now - t0) * 1000, "wrists": [result.wristsReplaced.left, result.wristsReplaced.right],
            ]
            if result.sameHandDropped { line["same_hand"] = true }
            if let row = frame3D.row { line["row"] = row }
            if rep == 0, let s = setupLog { line["setup"] = s }
            if let support = result.supportCorridor {
                var diagnostic = support.diagnostics
                diagnostic["assessment_state"] = (support.assessmentState(frame3D.state) ?? frame3D.state).rawValue
                diagnostic["assessment_invalid"] = support.invalid3DJoints.sorted()
                diagnostic["camera_evidence"] = VideoCameraOptions.isActive && CameraPreviewOptions.fixedSupportReplay
                    ? "controlled_replay_assertion" : "unknown"
                diagnostic["contact_source"] = "explicit_controlled_replay_interval_and_readiness_eligibility"
                line["support_corridor"] = diagnostic
            }
            if let a = result.wristAnchor { line["wrist_anchor"] = a }
            if let src = log.clipFrame(result.frameIndex) { line["src"] = src }
            // RTMPose keypoints the evaluators used (frame px, 1 decimal) and the raw MediaPipe wrist per crop side, for
            // the left/right analysis against the Exercise3D labels (scripts/ex3d_lr_swap_device.py).
            line["kp"] = result.rawCoco17.flatMap { [($0.x * 10).rounded() / 10, ($0.y * 10).rounded() / 10,
                                                     ($0.confidence * 1000).rounded() / 1000] }
            var hands: [String: [Double]] = [:]
            for hand in result.handResults {
                if let w = hand.wristFramePoint { hands[hand.side.rawValue] = [(w.x * 10).rounded() / 10, (w.y * 10).rounded() / 10] }
            }
            if !hands.isEmpty { line["hands"] = hands }
            line["size"] = [Int(result.imageWidth), Int(result.imageHeight)]
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
    private func updateSetup(_ frame3D: Lifted3DFrame, feet: FootKeypoints?, coco17: [PoseKeypoint], now: CFTimeInterval) -> [String: Any]? {
        guard exerciseSetup != nil else { return nil }
        let up = formTracker?.up3D ?? FormGeometry.up3D
        guard let state = exerciseSetup?.update(frame3D.usable3D, confidence: frame3D.confidence ?? [],
                                                usable: frame3D.usable3D != nil, up: up, unit: frame3D.unit ?? 1,
                                                feet: feet, coco17: coco17),
              let setup = exerciseSetup else { return nil }
        setupLog = ["phase": state.phase.rawValue, "progress": state.progress, "moving": state.moving,
                    "motion_2d": state.motion2D.map { ($0 * 1000).rounded() / 1000 } ?? NSNull()]
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
        supportControl.reset()
        wristAnchorResetPending = true
        wristAnchorActive = false
        exerciseSetup?.reset()
        setupSeeded = false
        lastSetupSignature = nil
        liftQueue.async { [weak self] in self?.lifter?.adaptive?.reset() }
    }

    @MainActor
    private func handleProcessingResult(_ result: CameraProcessingResult) {
        if currentFrame?.rotation != result.rotation { overlaySmoother = OverlaySmoother() }
        let (statusText, rep, done) = self.runEvaluator(frameIndex: result.frameIndex, rawCoco17: result.supportCorridor?.assessment2D(result.rawCoco17) ?? result.rawCoco17,
                                                        feet: result.feet, pose3D: nil, pose3DState: nil)
        if rep >= 1 { wristAnchorActive = true; supportControl.markReady() }

        let frameData = CameraFrameData(
            id: result.frameIndex,
            frameIndex: result.frameIndex,
            rotation: result.rotation,
            imageWidth: result.imageWidth,
            imageHeight: result.imageHeight,
            coco17: displayKeypoints(result),
            rawCoco17: result.rawCoco17,
            handResults: result.handResults,
            exerciseTitle: self.exercise.displayName,
            statusText: statusText,
            rep: rep,
            done: done,
            supportUncertainJoints: result.supportCorridor?.uncertainJoints ?? [],
            shade: severityTrack.update(liveSeverity, at: CACurrentMediaTime())
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
        // Explicit capture-harness hook only: close through the real production flush lifecycle.
        if VideoRunLog.terminalEvidence, DemoConfig.environment["BPT_TERMINAL_EOF_FLUSH"] == "1", !betweenSets,
           let index = terminalSetIndex, let epoch = terminalCapture.snapshot() {
            captureManager.afterPendingExternalFrames { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, !self.betweenSets, self.terminalCapture.snapshot() == epoch else { return }
                    VideoRunLog.shared?.write("terminal_eof_flush", ["epoch": epoch, "set": index,
                        "trigger": "video_eof_test_hook", "processing_queue_drained": true])
                    self.endSet(index)
                }
            }
            return
        }
        if VideoRunLog.terminalEvidence, let epoch = terminalCapture.beginFlush() {
            candidateEnd(epoch: epoch, reason: "video_end_without_set_flush")
            VideoRunLog.shared?.write("terminal_end", ["epoch": epoch, "reason": "video_end_without_set_flush", "flush_complete": false, "incomplete": true])
            terminalCapture.finish(epoch)
        }
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

    /// The frame in the analysis frame: the turn rides on the render this needs anyway (no extra pass).
    private nonisolated static func cgImageFromSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        ciContext: CIContext,
        rotation: CaptureRotation
    ) throws -> CGImage {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw NSError(domain: "CameraPosePreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing pixel buffer"])
        }
        let ciImage = rotation.analysisImage(CIImage(cvPixelBuffer: pixelBuffer))
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw NSError(domain: "CameraPosePreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "CGImage creation failed"])
        }
        return cgImage
    }

    /// Processing queue: this frame's rotation (the launch override, else the latest gravity sample). A new rotation
    /// drops the person crop, which is in the old frame's pixels; the next frame searches the whole frame again.
    private nonisolated func updateCaptureRotation() -> CaptureRotation {
        let before = rotationTracker.rotation
        guard let state = rotationMotion?.state, state.isAvailable else { return before }
        let rotation = rotationTracker.update(gravityX: state.gravity[0], gravityY: state.gravity[1])
        if rotation != before {
            cropTracker.reset()
            print("CameraPosePreview capture rotation \(before.rawValue) -> \(rotation.rawValue)")
        }
        return rotation
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
                    statusText: model.statusText,
                    debugCaption: model.debugCaption
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
    /// Test mode only (video mode): the last rep's judgement.
    let debugCaption: String?

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

                // HUD (rep/status) is rendered by Flutter at the bottom of the screen — no native HUD. Test mode only
                // (video mode): the last rep's judgement, small, under the status bar.
                if let debugCaption {
                    Text(debugCaption)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 54)
                        .padding(.leading, 8)
                }
            }
            .background(Color.black)
            .clipped()
        }
    }

    /// The camera preview follows the interface orientation (CameraPreviewUIView), so in a landscape UI (push-up, #67) it
    /// shows the scene upright, like the analysis frame. The video-as-camera layer always shows the buffer.
    private func previewShowsAnalysisFrame(_ size: CGSize) -> Bool {
        videoLayer == nil && size.width > size.height
    }

    /// Scoped body observations: neutral when withheld/relative-only; known issues retain their limited scope. No head/hands.
    private func drawSkeleton(frame: CameraFrameData, context: inout GraphicsContext, size: CGSize) {
        let upright = previewShowsAnalysisFrame(size)
        let shown = upright ? (width: frame.imageWidth, height: frame.imageHeight)
            : frame.rotation.bufferSize(width: frame.imageWidth, height: frame.imageHeight)
        let rect = aspectFillRect(imageWidth: shown.width, imageHeight: shown.height, in: size)
        PoseOverlayRenderer.draw(frame.coco17, shade: frame.shade, uncertainJoints: frame.supportUncertainJoints, in: &context) {
            viewPoint($0, frame: frame, rect: rect, upright: upright)
        }
    }

    /// Analysis-frame keypoint → view point over the preview (the buffer, or the upright scene in a landscape UI).
    private func viewPoint(_ keypoint: PoseKeypoint, frame: CameraFrameData, rect: CGRect, upright: Bool) -> CGPoint {
        if upright {
            return CGPoint(x: rect.minX + CGFloat(keypoint.x / frame.imageWidth) * rect.width,
                           y: rect.minY + CGFloat(keypoint.y / frame.imageHeight) * rect.height)
        }
        let buffer = frame.rotation.bufferSize(width: frame.imageWidth, height: frame.imageHeight)
        let p = frame.rotation.bufferPoint(x: keypoint.x, y: keypoint.y, bufferWidth: buffer.width, bufferHeight: buffer.height)
        return CGPoint(
            x: rect.minX + CGFloat(p.x / buffer.width) * rect.width,
            y: rect.minY + CGFloat(p.y / buffer.height) * rect.height
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

    /// The preview follows the interface orientation (push-up runs in a landscape UI, #67); the capture buffer stays
    /// portrait and the analysis turns it upright from gravity (CaptureRotation).
    private var previewOrientation: AVCaptureVideoOrientation {
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        case .portraitUpsideDown: .portraitUpsideDown
        default: .portrait
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported,
           connection.videoOrientation != previewOrientation {
            connection.videoOrientation = previewOrientation
        }
    }

    func configure(session: AVCaptureSession, isMirrored: Bool) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        previewLayer.videoGravity = .resizeAspectFill

        guard let connection = previewLayer.connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = previewOrientation
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
