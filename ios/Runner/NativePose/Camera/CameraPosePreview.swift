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
    static let enableMotion3DForCamera = false
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
}

// MARK: - Camera capture manager

private final class CameraCaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    let session = AVCaptureSession()
    private(set) var isFrontCamera = false
    private let processingQueue = DispatchQueue(label: "com.coremlpose.camera.processing", qos: .userInitiated)
    nonisolated(unsafe) private var isProcessingFrame = false
    nonisolated(unsafe) private var frameIndex = 0
    nonisolated(unsafe) var onFrame: (@Sendable (CMSampleBuffer, Int) -> Void)?

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
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        let idx = frameIndex
        frameIndex += 1
        onFrame?(sampleBuffer, idx)
        isProcessingFrame = false
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

    // Reports rep/status changes to Flutter (HUD is rendered on the Flutter side).
    private let onUpdate: ((Int, String, Bool) -> Void)?
    private var lastReportedRep: Int?
    private var lastReportedStatus: String?
    private var lastReportedDone: Bool?
    // Form feedback → Flutter `onFeedback` {key, n?, silent?} (kori_feedback_lines.dart).
    private let onFeedback: ((String, Int?, Bool) -> Void)?
    private var formLog: WorkoutFormLog?

    // Models (loaded once)
    private var rtmpose: MLModel?
    private var handLandmarkers: MediaPipeHandLandmarkerPair?

    // Evaluators (only one active)
    private var deadliftEvaluator: DeadliftEvaluator?
    private var benchPressEvaluator: BenchPressEvaluator?
    private var squatEvaluator: SquatEvaluator?
    private var barbellRowEvaluator: BarbellRowEvaluator?
    private var pushUpEvaluator: PushUpEvaluator?

    init(exercise: NativePoseExercise,
         onUpdate: ((Int, String, Bool) -> Void)? = nil,
         onFeedback: ((String, Int?, Bool) -> Void)? = nil) {
        self.exercise = exercise
        self.onUpdate = onUpdate
        self.onFeedback = onFeedback
    }

    func requestCameraAndStart() {
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
        captureManager.stop()
        if let tracker = formTracker { formLog?.close(tracker) }
        formLog = nil
    }

    private var formTracker: FormWarningTracker? {
        squatEvaluator?.formTracker ?? pushUpEvaluator?.formTracker ?? barbellRowEvaluator?.formTracker
    }

    /// Every frame: forward the tracker's feedback events; after a counted rep also log its report.
    private func reportForm(done: Bool) {
        guard let tracker = formTracker else { return }
        if done, let report = tracker.reports.last { formLog?.append(report) }
        for event in tracker.drainEvents() { onFeedback?(event.key, event.n, event.silent) }
    }

    private func setup() {
        let workspace: RTMPoseInputWorkspace
        do {
            rtmpose = try loadModel(named: RTMPoseModel.active.rawValue)
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

        let handEnabled = exercise.handBranchEnabled(override: CameraPreviewOptions.handBranchOverride)
        if handEnabled {
            handLandmarkers = MediaPipeHandLandmarkerPair()
            print("CameraPosePreview hand landmarkers initialized: \(handLandmarkers?.statusDescription ?? "nil")")
        }

        do {
            try captureManager.configure()
        } catch {
            statusText = "Failed to configure camera: \(error.localizedDescription)"
            return
        }

        let rtmposeModel = self.rtmpose
        let handLandmarkRunner = self.handLandmarkers
        let context = self.ciContext

        captureManager.onFrame = { [weak self, context] sampleBuffer, frameIdx in
            guard let self, let rtmposeModel else { return }
            self.processFrame(
                sampleBuffer,
                frameIdx: frameIdx,
                rtmpose: rtmposeModel,
                workspace: workspace,
                handLandmarkers: handLandmarkRunner,
                ciContext: context
            )
        }

        captureManager.start()
        statusText = "Running"
        print("CameraPosePreview started exercise=\(exercise.rawValue) hand=\(handEnabled) 3d=\(CameraPreviewOptions.enableMotion3DForCamera)")
    }

    private nonisolated func processFrame(
        _ sampleBuffer: CMSampleBuffer,
        frameIdx: Int,
        rtmpose: MLModel,
        workspace: RTMPoseInputWorkspace,
        handLandmarkers: MediaPipeHandLandmarkerPair?,
        ciContext: CIContext
    ) {
        autoreleasepool {
            do {
                let timestampMs = Self.timestampMs(sampleBuffer, fallback: frameIdx)
                let cgImage = try Self.cgImageFromSampleBuffer(sampleBuffer, ciContext: ciContext)
                let preprocess = try PosePreprocess.preprocessFullImage(cgImage, workspace: workspace)
                let rtmposeOutput = try rtmpose.prediction(from: workspace.provider)

                guard let simccX = rtmposeOutput.featureValue(for: "simcc_x")?.multiArrayValue,
                      let simccY = rtmposeOutput.featureValue(for: "simcc_y")?.multiArrayValue else {
                    return
                }

                let decoded = try SimCCDecoder.decodeToInputCoordinates(simccX: simccX, simccY: simccY)
                let rawCoco17 = PoseCoordinateTransforms.applyInverseAffine(
                    decoded: decoded,
                    inverseAffine: preprocess.inverseAffine
                )

                // Hand branch
                let handResults: [HandLandmarkResult]
                let leftHand: HandLandmarkResult?
                let rightHand: HandLandmarkResult?
                if let handLandmarkers = handLandmarkers {
                    let handImage = UIImage(cgImage: cgImage)
                    let handFrame = BundledVideoHandFrameProcessor.runWristCropHands(
                        image: handImage,
                        rawCoco17: rawCoco17,
                        imageWidth: Double(preprocess.imageWidth),
                        imageHeight: Double(preprocess.imageHeight),
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

                let result = CameraProcessingResult(
                    frameIndex: frameIdx,
                    imageWidth: Double(preprocess.imageWidth),
                    imageHeight: Double(preprocess.imageHeight),
                    visualCoco17: visualCoco17,
                    rawCoco17: rawCoco17,
                    feet: PoseCoordinateTransforms.applyInverseAffineToFeet(
                        decoded: decoded,
                        inverseAffine: preprocess.inverseAffine
                    ),
                    handResults: handResults
                )

                Task { @MainActor [weak self] in
                    self?.handleProcessingResult(result)
                }
            } catch {
                if frameIdx % CameraPreviewOptions.debugLogEveryNFrames == 0 {
                    print("CameraPosePreview frame processing error: \(error)")
                }
            }
        }
    }

    @MainActor
    private func handleProcessingResult(_ result: CameraProcessingResult) {
        let (statusText, rep, done) = self.runEvaluator(frameIndex: result.frameIndex, rawCoco17: result.rawCoco17,
                                                        feet: result.feet)

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
            onUpdate?(rep, statusText, done)
        }

        if result.frameIndex % CameraPreviewOptions.debugLogEveryNFrames == 0 {
            print("CameraPosePreview frame=\(result.frameIndex) exercise=\(self.exercise.rawValue) status=\(statusText) rep=\(rep) done=\(done) hands=\(result.handResults.count)")
        }
    }

    private func runEvaluator(frameIndex: Int, rawCoco17: [PoseKeypoint],
                              feet: FootKeypoints?) -> (status: String, rep: Int, done: Bool) {
        switch exercise {
        case .deadlift:
            if let eval = deadliftEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17)
                return (r.status.rawValue, r.rep, r.done)
            }
        case .benchPress:
            if let eval = benchPressEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17)
                return (r.status.rawValue, r.rep, r.done)
            }
        case .squat:
            if let eval = squatEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17, feet: feet)
                reportForm(done: r.done)
                return (r.status.rawValue, r.rep, r.done)
            }
        case .barbellRow:
            if let eval = barbellRowEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17)
                reportForm(done: r.done)
                return (r.status.rawValue, r.rep, r.done)
            }
        case .pushUp:
            if let eval = pushUpEvaluator {
                let r = eval.evaluate(frameIndex: frameIndex, coco17: rawCoco17)
                reportForm(done: r.done)
                return (r.status.rawValue, r.rep, r.done)
            }
        }
        return ("inactive", 0, false)
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

    init(exercise: NativePoseExercise,
         onUpdate: ((Int, String, Bool) -> Void)? = nil,
         onFeedback: ((String, Int?, Bool) -> Void)? = nil) {
        self.exercise = exercise
        _model = StateObject(wrappedValue: CameraPoseViewModel(exercise: exercise, onUpdate: onUpdate,
                                                               onFeedback: onFeedback))
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
    let isMirrored: Bool
    let frame: CameraFrameData?
    let statusText: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                CameraPreviewLayerView(session: session, isMirrored: isMirrored)
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
