import AVFoundation
import CoreImage
import CoreML
import CoreMedia
import Foundation
import UIKit

/// Drives one body-calibration run: camera → RTMPose-s → `CalibrationEngine` → files.
///
/// The judging engine is pure; everything device-shaped lives here. Frames are judged on a
/// background queue and the capture writes the *same* frame the keypoints came from, which is
/// why the sharpest frame of the stillness window is tracked as it goes instead of being
/// re-derived afterwards (a 4K ring buffer would not fit in memory).
final class CalibrationSession: NSObject {
    struct Update {
        var guidance: String
        var classifiedView: String?
        var targetView: String?
        var capturedViews: [String]
        var holdProgress: Double
        var isPassing: Bool
        var isFinished: Bool
        var sessionPath: String?
        var debug: [String: Double]
    }

    private let config: CalibrationConfig
    private let engine: CalibrationEngine
    private let motion = DeviceMotionMonitor()
    private let voice = CalibrationVoice()
    private let captureManager: CalibrationCaptureManager
    private let ciContext = CIContext(options: nil)
    private let processingQueue = DispatchQueue(label: "com.bpt.calibration.processing", qos: .userInitiated)

    private var store: CalibrationStore?
    private var debugLog: CalibrationDebugLog?
    private var rtmpose: MLModel?
    private var userHeightCm: Double = 0
    private var isRunning = false

    /// Sharpest frame seen so far in the current stillness hold.
    private var bestHoldFrame: (confidence: Double, image: CGImage, keypoints: [PoseKeypoint], timestamp: TimeInterval)?
    private var lastIntrinsics = CalibrationStore.Intrinsics()
    private var lastImageSize = CGSize.zero

    private let onUpdate: (Update) -> Void
    private let onError: (String) -> Void

    var captureSession: AVCaptureSession { captureManager.session }

    init(config: CalibrationConfig = .default,
         onUpdate: @escaping (Update) -> Void,
         onError: @escaping (String) -> Void) {
        self.config = config
        self.engine = CalibrationEngine(config: config)
        self.captureManager = CalibrationCaptureManager()
        self.onUpdate = onUpdate
        self.onError = onError
        super.init()
    }

    // MARK: - Lifecycle

    func start(userHeightCm: Double) {
        guard !isRunning else { return }
        self.userHeightCm = userHeightCm

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.onError("camera_permission_denied")
                    return
                }
                self.beginSession()
            }
        }
    }

    func cancel() {
        stop()
        store?.discard()
        store = nil
        engine.reset()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        captureManager.stop()
        motion.stop()
        voice.stop()
        debugLog?.close()
        debugLog = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func beginSession() {
        do {
            rtmpose = try loadModel(named: "rtmpose_s_forward")
            let store = try CalibrationStore()
            self.store = store
            debugLog = CalibrationDebugLog(directory: store.directory)
            try captureManager.configure()
        } catch {
            onError("setup_failed: \(error.localizedDescription)")
            return
        }

        captureManager.onFrame = { [weak self] sampleBuffer in
            guard let self else { return }
            processingQueue.async {
                self.handle(sampleBuffer)
                self.captureManager.markIdle()
            }
        }
        motion.start()
        captureManager.start()
        UIApplication.shared.isIdleTimerDisabled = true
        isRunning = true
    }

    // MARK: - Per-frame pipeline

    private func handle(_ sampleBuffer: CMSampleBuffer) {
        guard let rtmpose, isRunning else { return }
        autoreleasepool {
            do {
                let cgImage = try cgImage(from: sampleBuffer)
                let preprocess = try PosePreprocess.preprocessFullImage(cgImage)
                let provider = try MLDictionaryFeatureProvider(dictionary: [
                    "input_image": MLFeatureValue(multiArray: preprocess.inputTensor)
                ])
                let output = try rtmpose.prediction(from: provider)
                guard let simccX = output.featureValue(for: "simcc_x")?.multiArrayValue,
                      let simccY = output.featureValue(for: "simcc_y")?.multiArrayValue else { return }
                let decoded = try SimCCDecoder.decodeToInputCoordinates(simccX: simccX, simccY: simccY)
                let coco17 = PoseCoordinateTransforms.applyInverseAffine(
                    decoded: decoded,
                    inverseAffine: preprocess.inverseAffine
                )
                let width = Double(cgImage.width), height = Double(cgImage.height)
                lastImageSize = CGSize(width: width, height: height)
                lastIntrinsics = intrinsics(from: sampleBuffer, width: width, height: height)

                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                let frame = CalibrationFrame(
                    keypoints: coco17.map {
                        CalibrationKeypoint(x: $0.x / width, y: $0.y / height, score: $0.confidence)
                    },
                    aspect: width / height,
                    timestamp: timestamp.isFinite ? timestamp : CACurrentMediaTime(),
                    device: motion.state
                )
                let result = engine.process(frame)
                trackBestFrame(result, cgImage: cgImage, keypoints: coco17, timestamp: frame.timestamp)

                if let request = result.capture {
                    writeCapture(request, fallbackImage: cgImage, fallbackKeypoints: coco17,
                                 timestamp: frame.timestamp)
                }
                debugLog?.append(timestamp: frame.timestamp, output: result,
                                 r: result.measurement.flatMap { engine.rValue($0) },
                                 delta: result.measurement.flatMap { engine.delta($0) },
                                 device: frame.device)
                DispatchQueue.main.async { self.publish(result) }
            } catch {
                // Dropped frames are normal (motion blur, model hiccup); the next one will do.
            }
        }
    }

    /// Keeps the highest mean-confidence frame of the current hold so the saved image is the sharpest one.
    private func trackBestFrame(_ result: CalibrationEngineOutput,
                                cgImage: CGImage,
                                keypoints: [PoseKeypoint],
                                timestamp: TimeInterval) {
        guard result.isPassing, let confidence = result.measurement?.meanRequiredConfidence else {
            bestHoldFrame = nil
            return
        }
        if let best = bestHoldFrame, best.confidence >= confidence { return }
        bestHoldFrame = (confidence, cgImage, keypoints, timestamp)
    }

    private func writeCapture(_ request: CalibrationCaptureRequest,
                              fallbackImage: CGImage,
                              fallbackKeypoints: [PoseKeypoint],
                              timestamp: TimeInterval) {
        guard let store else { return }
        let chosen = bestHoldFrame.flatMap { $0.timestamp >= request.holdStartedAt ? $0 : nil }
        let image = chosen?.image ?? fallbackImage
        let keypoints = chosen?.keypoints ?? fallbackKeypoints
        let frameTimestamp = chosen?.timestamp ?? timestamp
        bestHoldFrame = nil

        do {
            try store.writeImage(UIImage(cgImage: image), for: request.view,
                                 quality: config.capture.jpegQuality)
            store.add(CalibrationStore.ViewRecord(
                label: request.view,
                r: request.r,
                delta: request.delta,
                earLeft: request.measurement.earLeft,
                earRight: request.measurement.earRight,
                face: request.measurement.face,
                keypoints: keypoints.map { [$0.x, $0.y, $0.confidence] },
                gravity: motion.state.gravity,
                timestamp: frameTimestamp
            ))
            if request.isLastView {
                try store.writeManifest(
                    userHeightCm: userHeightCm,
                    imageWidth: image.width,
                    imageHeight: image.height,
                    intrinsics: lastIntrinsics,
                    reference: engine.reference
                )
            }
        } catch {
            DispatchQueue.main.async { self.onError("write_failed: \(error.localizedDescription)") }
        }
        DispatchQueue.main.async { self.voice.playShutter() }
    }

    private func publish(_ result: CalibrationEngineOutput) {
        let now = CACurrentMediaTime()
        voice.speak(result.guidance, now: now)
        if let target = result.targetView, target == .back || target == .leftfront || target == .rightfront,
           !result.isPassing, let m = result.measurement {
            voice.beep(progress: beepProgress(target: target, measurement: m), now: now)
        }

        var debug: [String: Double] = [:]
        if let m = result.measurement {
            debug = [
                "face": m.face, "earL": m.earLeft, "earR": m.earRight,
                "bodyH": m.bodyHeight, "midX": m.midX, "feet": m.feet,
                "wristDropL": m.leftWristDrop, "wristDropR": m.rightWristDrop,
            ]
            if let r = engine.rValue(m) { debug["r"] = r }
            if let d = engine.delta(m) { debug["delta"] = d }
        }
        let device = motion.state
        debug["roll"] = device.rollDeg
        debug["pitch"] = device.pitchDeg

        let finished = engine.isFinished
        onUpdate(Update(
            guidance: result.guidance.message,
            classifiedView: result.classifiedView?.rawValue,
            targetView: result.targetView?.rawValue,
            capturedViews: result.capturedViews.map(\.rawValue),
            holdProgress: result.holdProgress,
            isPassing: result.isPassing,
            isFinished: finished,
            sessionPath: finished ? store?.directory.path : nil,
            debug: debug
        ))
        if finished { stop() }
    }

    /// 0 = far from the target yaw, 1 = there. Oblique targets aim at r = 0.5, the back at r = 1 with no face.
    private func beepProgress(target: CalibrationView, measurement: CalibrationMeasurement) -> Double {
        guard let r = engine.rValue(measurement) else { return 0 }
        switch target {
        case .leftfront, .rightfront:
            return max(0, 1 - abs(r - 0.5) / 0.5)
        case .back:
            return max(0, min(1, r)) * max(0, 1 - measurement.face)
        case .front:
            return 0
        }
    }

    // MARK: - Camera helpers

    private func cgImage(from sampleBuffer: CMSampleBuffer) throws -> CGImage {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw CalibrationSessionError.missingPixelBuffer
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw CalibrationSessionError.cgImageFailed
        }
        return image
    }

    /// Reads the per-frame intrinsics attachment; falls back to the field of view.
    ///
    /// The attachment describes the *sensor* frame, so on a portrait-rotated buffer the
    /// principal point lands outside the image — that is how the rotated case is detected.
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
        // The sensor's field of view spans what is now the portrait buffer's height.
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
    case missingPixelBuffer
    case cgImageFailed
    case missingModel(String)
    case noCamera

    var errorDescription: String? {
        switch self {
        case .missingPixelBuffer: return "Missing pixel buffer"
        case .cgImageFailed: return "CGImage creation failed"
        case .missingModel(let name): return "Missing model: \(name)"
        case .noCamera: return "No front camera available"
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

    nonisolated(unsafe) var onFrame: ((CMSampleBuffer) -> Void)?
    nonisolated(unsafe) private var isBusy = false

    func configure() throws {
        // The app plays speech and beeps; letting the capture session own the audio session would duck them.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CalibrationSessionError.noCamera
        }
        session.sessionPreset = session.canSetSessionPreset(.hd4K3840x2160) ? .hd4K3840x2160 : .hd1920x1080

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CalibrationSessionError.noCamera }
        session.addInput(input)
        horizontalFieldOfView = device.activeFormat.videoFieldOfView

        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CalibrationSessionError.noCamera }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            connection.isCameraIntrinsicMatrixDeliveryEnabled =
                connection.isCameraIntrinsicMatrixDeliverySupported
            // Judging and saving use the unmirrored buffer; only the preview layer mirrors.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            applyPortraitRotation(to: connection, device: device)
        }
    }

    private func applyPortraitRotation(to connection: AVCaptureConnection, device: AVCaptureDevice) {
        if #available(iOS 17.0, *) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            rotationCoordinator = coordinator
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
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
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        // Judging one 4K frame is slower than the camera produces them; skip rather than queue up.
        guard !isBusy else { return }
        isBusy = true
        onFrame?(sampleBuffer)
    }

    /// Called once the frame has been judged, so the next one can be picked up.
    func markIdle() {
        isBusy = false
    }
}
