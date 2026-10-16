import AVFoundation
import CoreImage
import CoreML
import CoreMedia
import Foundation
import UIKit

/// Drives one body-calibration run: camera → RTMPose-s + Vision face → `CalibrationEngine` → files.
///
/// Threading: everything that holds run state (engine, analyzer, store, log, best frame)
/// lives on `processingQueue` and only there. The main thread gets immutable `Update`
/// values to show and speak. Teardown is queued behind any frame still in flight, so a
/// cancel or the final capture never races a frame mid-judgement.
final class CalibrationSession: NSObject {
    struct Update {
        var guidance: CalibrationGuidance
        var classifiedView: String?
        var targetView: String?
        var capturedViews: [String]
        var holdProgress: Double
        var isPassing: Bool
        var isFinished: Bool
        var sessionPath: String?
        var didTimeOut: Bool
        var beepProgress: Double?
        /// Where the user is (normalized, unmirrored buffer) and the outline they should fill;
        /// the capture screen draws the guide from these, so it agrees with the gates.
        var person: [String: Double]?
        var guide: [String: Double]
        var debug: [String: Double]
    }

    private let config: CalibrationConfig
    private let engine: CalibrationEngine
    private let motion = DeviceMotionMonitor()
    private let voice: CalibrationVoice
    private let captureManager = CalibrationCaptureManager()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let processingQueue = DispatchQueue(label: "com.bpt.calibration.processing", qos: .userInitiated)

    // processingQueue only
    private var analyzer: CalibrationFrameAnalyzer?
    private var store: CalibrationStore?
    private var debugLog: CalibrationDebugLog?
    private var userHeightCm: Double = 0
    private var isRunning = false
    private var startRequestID: UUID?
    private var lastBufferAspect = 9.0 / 16.0
    /// Highest-confidence frame (not a sharpness score), with all of its own metadata.
    private struct SelectedFrame {
        let image: CGImage
        let snapshot: CalibrationStore.Snapshot
        let holdStartedAt: TimeInterval
    }
    private var bestHoldFrame: SelectedFrame?

    // main thread only
    private var announcedCaptures = 0

    private let onUpdate: (Update) -> Void
    private let onError: (String) -> Void

    var captureSession: AVCaptureSession { captureManager.session }

    init(config: CalibrationConfig = .default,
         onUpdate: @escaping (Update) -> Void,
         onError: @escaping (String) -> Void) {
        self.config = config
        self.engine = CalibrationEngine(config: config)
        self.voice = CalibrationVoice(config: config.voice)
        self.onUpdate = onUpdate
        self.onError = onError
        super.init()
    }

    // MARK: - Lifecycle (callable from main)

    func start(userHeightCm: Double) {
        processingQueue.async { [weak self] in
            guard let self, !self.isRunning, self.store == nil, self.startRequestID == nil else { return }
            let requestID = UUID()
            self.startRequestID = requestID
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.processingQueue.async {
                    // A permission dialog may outlive this screen/capture run.
                    guard self.startRequestID == requestID else { return }
                    self.startRequestID = nil
                    guard granted else {
                        DispatchQueue.main.async { self.onError("camera_permission_denied") }
                        return
                    }
                    self.begin(userHeightCm: userHeightCm)
                }
            }
        }
    }

    /// Stops the run. A finished session keeps its folder; an unfinished one is deleted.
    func cancel() {
        processingQueue.async {
            self.startRequestID = nil
            self.teardown(discardUnfinished: true)
        }
    }

    /// Stops the camera but keeps whatever was captured.
    func stop() {
        processingQueue.async {
            self.startRequestID = nil
            self.teardown(discardUnfinished: false)
        }
    }

    private func begin(userHeightCm: Double) {
        guard !isRunning, store == nil else { return }
        do {
            let model = try loadModel(named: "rtmpose_s_forward")
            analyzer = try CalibrationFrameAnalyzer(model: model, context: ciContext,
                                                minConfidence: config.framing.minKeypointConfidence)
            let store = try CalibrationStore()
            self.store = store
            debugLog = CalibrationDebugLog(directory: store.directory)
            try captureManager.configure { [weak self] sampleBuffer in
                guard let self else { return }
                // Bind the latest IMU snapshot when the camera frame arrives, before inference.
                let device = self.motion.state
                self.processingQueue.async {
                    defer { self.captureManager.markIdle() }
                    self.handle(sampleBuffer, device: device)
                }
            }
        } catch {
            teardown(discardUnfinished: true)
            let message = "setup_failed: \(error.localizedDescription)"
            DispatchQueue.main.async { self.onError(message) }
            return
        }
        self.userHeightCm = userHeightCm
        isRunning = true
        motion.start()
        captureManager.start()
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
            self.voice.activate()
        }
    }

    /// processingQueue only.
    private func teardown(discardUnfinished: Bool) {
        isRunning = false
        captureManager.stop()
        motion.stop()
        debugLog?.close()
        debugLog = nil
        bestHoldFrame = nil
        analyzer = nil
        let finished = engine.isFinished
        if discardUnfinished, !finished {
            store?.discard()
            store = nil
            engine.reset()
        }
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
            // Let the closing line finish on success; cut it short when the user backs out.
            finished ? self.voice.deactivateWhenDone() : self.voice.stop()
        }
    }

    // MARK: - Per-frame pipeline (processingQueue)

    private func handle(_ sampleBuffer: CMSampleBuffer, device: CalibrationDeviceState) {
        guard isRunning, let analyzer else { return }
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                reportTrackingInterruption(device: device)
                return
            }
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            guard let analysis = try? analyzer.analyze(image) else {
                analyzer.reset()
                reportTrackingInterruption(device: device)
                return
            }
            let width = Double(analysis.imageSize.width), height = Double(analysis.imageSize.height)
            lastBufferAspect = width / height

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let frame = CalibrationFrame(
                keypoints: analysis.keypoints.map {
                    CalibrationKeypoint(x: $0.x / width, y: $0.y / height, score: $0.confidence)
                },
                aspect: width / height,
                timestamp: pts,
                device: device,
                face: analysis.face
            )
            var result = engine.process(frame)
            trackBestFrame(result, image: image, frame: frame, sampleBuffer: sampleBuffer)

            if let request = result.capture {
                let saved = writeCapture(request)
                if let resolved = engine.resolveCapture(id: request.id, saved: saved) { result = resolved }
            }
            let r = result.measurement.flatMap { engine.rValue($0) }
            let delta = result.measurement.flatMap { engine.delta($0) }
            debugLog?.append(timestamp: frame.timestamp, output: result, r: r, delta: delta,
                             device: frame.device, face: frame.face)

            let update = makeUpdate(result, r: r, delta: delta, device: frame.device, face: frame.face)
            DispatchQueue.main.async { self.deliver(update) }
            if update.isFinished { teardown(discardUnfinished: false) }
        }
    }

    private func reportTrackingInterruption(device: CalibrationDeviceState) {
        bestHoldFrame = nil
        let update = makeUpdate(engine.invalidateFrame(), r: nil, delta: nil, device: device, face: .unknown)
        DispatchQueue.main.async { self.deliver(update) }
    }

    private func trackBestFrame(_ result: CalibrationEngineOutput,
                                image: CIImage,
                                frame: CalibrationFrame,
                                sampleBuffer: CMSampleBuffer) {
        guard result.isPassing, let measurement = result.measurement,
              let holdStartedAt = result.holdStartedAt else {
            bestHoldFrame = nil
            return
        }
        if let best = bestHoldFrame, best.holdStartedAt == holdStartedAt,
           best.snapshot.measurement.meanRequiredConfidence >= measurement.meanRequiredConfidence { return }
        // A full-resolution copy only when this frame is the best of the hold so far.
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        bestHoldFrame = SelectedFrame(image: cgImage, snapshot: CalibrationStore.Snapshot(
            frame: frame, measurement: measurement, imageWidth: cgImage.width, imageHeight: cgImage.height,
            intrinsics: intrinsics(from: sampleBuffer, width: Double(cgImage.width), height: Double(cgImage.height))
        ), holdStartedAt: holdStartedAt)
    }

    private func writeCapture(_ request: CalibrationCaptureRequest) -> Bool {
        defer { bestHoldFrame = nil }
        guard let store, let chosen = bestHoldFrame,
              chosen.holdStartedAt == request.holdStartedAt,
              chosen.snapshot.frame.timestamp >= request.holdStartedAt,
              let jpeg = UIImage(cgImage: chosen.image).jpegData(compressionQuality: CGFloat(config.capture.jpegQuality))
        else { return false }

        do {
            let record = CalibrationStore.ViewRecord(
                label: request.view, snapshot: chosen.snapshot,
                r: engine.rValue(chosen.snapshot.measurement, relativeTo: request.reference),
                delta: engine.delta(chosen.snapshot.measurement, relativeTo: request.reference))
            try store.writeCapture(jpeg: jpeg, record: record, userHeightCm: userHeightCm, reference: request.reference)
            return true
        } catch {
            // Recoverable guidance is sent by resolveCapture; don't leave Dart's fatal camera error set.
            print("Calibration capture persistence failed: \(type(of: error))")
            return false
        }
    }

    private func makeUpdate(_ result: CalibrationEngineOutput,
                            r: Double?,
                            delta: Double?,
                            device: CalibrationDeviceState,
                            face: CalibrationFace) -> Update {
        var debug: [String: Double] = [
            "roll": device.rollDeg, "pitch": device.pitchDeg,
            "faceDetected": face.isDetected ? 1 : 0,
            "faceReliable": face.isReliable ? 1 : 0,
        ]
        if let yaw = face.yawDeg { debug["faceYaw"] = yaw }
        if let r { debug["r"] = r }
        if let delta { debug["delta"] = delta }
        if let m = result.measurement {
            debug["bodyH"] = m.bodyHeight
            debug["midX"] = m.midX
            debug["feet"] = m.feet
            debug["wristDropL"] = m.leftWristDrop
            debug["wristDropR"] = m.rightWristDrop
            debug["conf"] = m.meanRequiredConfidence
        }
        let finished = engine.isFinished
        return Update(
            guidance: result.guidance,
            classifiedView: result.classifiedView?.rawValue,
            targetView: result.targetView?.rawValue,
            capturedViews: result.capturedViews.map(\.rawValue),
            holdProgress: result.holdProgress,
            isPassing: result.isPassing,
            isFinished: finished,
            sessionPath: finished ? store?.directory.path : nil,
            didTimeOut: result.didTimeOut,
            beepProgress: beepProgress(result, r: r, face: face),
            person: result.measurement.map { ["midX": $0.midX, "feet": $0.feet, "bodyHeight": $0.bodyHeight] },
            guide: [
                "bodyHeight": config.framing.guideBodyHeight,
                "minBodyHeight": config.framing.minBodyHeight,
                "maxBodyHeight": config.framing.maxBodyHeight,
                "maxCentreOffset": config.framing.maxCentreOffset,
                "bufferAspect": lastBufferAspect,
            ],
            debug: debug
        )
    }

    /// 0 = far from the target yaw, 1 = there. Only while turning towards an oblique or the back.
    private func beepProgress(_ result: CalibrationEngineOutput, r: Double?, face: CalibrationFace) -> Double? {
        guard !result.isPassing, let r, let target = result.targetView else { return nil }
        switch target {
        case .leftfront, .rightfront:
            let centre = (config.view.obliqueMinR + config.view.obliqueMaxR) / 2
            return max(0, 1 - abs(r - centre) / centre)
        case .back:
            return face.isDetected ? 0.2 * r : r
        case .front:
            return nil
        }
    }

    // MARK: - Main thread

    private func deliver(_ update: Update) {
        let now = CACurrentMediaTime()
        // Count-based: the last view's frame says "finished", not "captured", but still took a picture.
        if update.capturedViews.count > announcedCaptures {
            announcedCaptures = update.capturedViews.count
            voice.playCaptureChime()
        }
        voice.speak(update.didTimeOut ? .timeoutSummary : update.guidance, now: now)
        if let progress = update.beepProgress {
            voice.beep(progress: progress, now: now)
        }
        onUpdate(update)
    }

    // MARK: - Helpers

    /// Reads the per-frame intrinsics attachment; falls back to the field of view.
    ///
    /// The attachment may describe the sensor (landscape) frame; on the portrait buffer its
    /// principal point then lands far off centre, which is how the rotated case is detected.
    private func intrinsics(from sampleBuffer: CMSampleBuffer,
                            width: Double,
                            height: Double) -> CalibrationStore.Intrinsics {
        if let attachment = CMGetAttachment(sampleBuffer,
                                            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                            attachmentModeOut: nil) as? Data,
           attachment.count >= MemoryLayout<matrix_float3x3>.size {
            let matrix: matrix_float3x3 = attachment.withUnsafeBytes { $0.load(as: matrix_float3x3.self) }
            let fx = Double(matrix.columns.0.x), fy = Double(matrix.columns.1.y)
            let cx = Double(matrix.columns.2.x), cy = Double(matrix.columns.2.y)
            let looksRotated = abs(2 * cx - width) > 0.25 * width || abs(2 * cy - height) > 0.25 * height
            if looksRotated {
                return CalibrationStore.Intrinsics(fx: fy, fy: fx, cx: width / 2, cy: height / 2,
                                                   source: "attachment_rotated")
            }
            return CalibrationStore.Intrinsics(fx: fx, fy: fy, cx: cx, cy: cy, source: "attachment")
        }
        let fovDeg = Double(captureManager.horizontalFieldOfView)
        guard fovDeg > 0 else { return CalibrationStore.Intrinsics(cx: width / 2, cy: height / 2) }
        // The sensor's horizontal field of view spans what is now the portrait buffer's height.
        let focal = (max(width, height) / 2) / tan(fovDeg * .pi / 180 / 2)
        return CalibrationStore.Intrinsics(fx: focal, fy: focal, cx: width / 2, cy: height / 2,
                                           source: "fov_estimate")
    }

    private func loadModel(named name: String) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: name, withExtension: "mlpackage") else {
            throw CalibrationSessionError.missingModel(name)
        }
        return try MLModel(contentsOf: url, configuration: configuration)
    }
}

enum CalibrationSessionError: LocalizedError {
    case missingModel(String)
    case noCamera

    var errorDescription: String? {
        switch self {
        case .missingModel(let name): return "Missing model: \(name)"
        case .noCamera: return "No usable front camera"
        }
    }
}

// MARK: - Capture manager

/// Front camera, highest resolution available, portrait, unmirrored, with intrinsics delivery.
final class CalibrationCaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.bpt.calibration.camera", qos: .userInitiated)
    private var rotationCoordinator: AnyObject?
    private(set) var horizontalFieldOfView: Float = 0

    // Handler/configuration are confined to queue; in-flight gate is locked across queues.
    nonisolated(unsafe) private var onFrame: ((CMSampleBuffer) -> Void)?
    private let frameGate = CalibrationFrameGate()
    private var isConfigured = false

    func configure(onFrame: @escaping (CMSampleBuffer) -> Void) throws {
        try queue.sync {
            try configureOnQueue()
            self.onFrame = onFrame
        }
    }

    private func configureOnQueue() throws {
        if isConfigured { return }
        // Speech and beeps run on our own audio session; the capture session must not reconfigure it.
        session.automaticallyConfiguresApplicationAudioSession = false

        // Center Stage pans and zooms to follow the user, which would move the frame under the
        // stance check and invalidate the intrinsics. Calibration needs a fixed camera.
        if #available(iOS 14.5, *) {
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = false
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Retry after a partially failed configuration without duplicate inputs/outputs.
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CalibrationSessionError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CalibrationSessionError.noCamera }
        session.addInput(input)
        // Presets are checked against the attached camera, so pick one after adding it.
        for preset in [AVCaptureSession.Preset.hd4K3840x2160, .hd1920x1080, .high] where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
            break
        }
        horizontalFieldOfView = device.activeFormat.videoFieldOfView

        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CalibrationSessionError.noCamera }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            connection.isCameraIntrinsicMatrixDeliveryEnabled = connection.isCameraIntrinsicMatrixDeliverySupported
            // Judging and saving use the unmirrored buffer; only the preview layer mirrors.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off  // stabilization crops and shifts the frame
            }
            applyPortraitRotation(to: connection, device: device)
        }
        isConfigured = true
    }

    /// Portrait buffer. The coordinator's angle is used when it reports portrait; if the phone is
    /// flat or sideways when the camera starts, fall back to plain portrait (90°).
    private func applyPortraitRotation(to connection: AVCaptureConnection, device: AVCaptureDevice) {
        if #available(iOS 17.0, *) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            rotationCoordinator = coordinator
            let suggested = coordinator.videoRotationAngleForHorizonLevelCapture
            let angle: CGFloat = suggested == 90 || suggested == 270 ? suggested : 90
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    func start() {
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            onFrame = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        // One frame in flight at a time; the camera outruns judging, so skip rather than queue up.
        guard let onFrame, frameGate.acquire() else { return }
        onFrame(sampleBuffer)
    }

    /// Called once the frame has been judged, so the next one can be picked up.
    func markIdle() {
        frameGate.release()
    }
}
