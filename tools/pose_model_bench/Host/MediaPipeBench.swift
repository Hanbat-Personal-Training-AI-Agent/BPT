import CoreImage
import MediaPipeTasksVision
import UIKit

/// MediaPipe Pose Landmarker on the iPhone (launch env BENCH_MP=latency|sustain), same 720x1280 frame as the Core ML
/// tests (PipelineAssets/frame.jpg, BGRA pixel buffer like the camera). Only `detect` is timed.
///   latency: lite/full/heavy x CPU/GPU x VIDEO/IMAGE mode, 20 warm-up + 300 timed calls each.
///   all:     one launch, back-to-back (the app stays in front, so the phone cannot auto-lock): latency, then sustain
///            for each model on its faster VIDEO-mode delegate, then the paced 30 fps pipeline (PipelineBench) with
///            pose_landmarker_full and with rtmpose_m_forward; BENCH_COOLDOWN idle seconds before each run.
///   sustain: BENCH_MP_MODEL (pose_landmarker_full) on BENCH_MP_DELEGATE (gpu|cpu) in VIDEO mode, back-to-back for
///            BENCH_SECONDS (150) after BENCH_COOLDOWN idle seconds; one line per 10 s with FPS and thermal state
///            (0 nominal, 1 fair, 2 serious, 3 critical).
/// Models: pose_landmarker_{lite,full,heavy}.task from storage.googleapis.com/mediapipe-models (Apache-2.0).
enum MediaPipeBench {
    static let assets = Bundle.main.resourceURL!.appendingPathComponent("PipelineAssets")

    static func run() throws {
        let env = ProcessInfo.processInfo.environment
        let buffer = try pixelBuffer(UIImage(contentsOfFile: assets.appendingPathComponent("frame.jpg").path)!.cgImage!)
        let image = try MPImage(pixelBuffer: buffer)
        let cooldown = Double(env["BENCH_COOLDOWN"] ?? "") ?? 0
        Thread.sleep(forTimeInterval: cooldown)
        switch env["BENCH_MP"] {
        case "sustain":
            try sustain(image, model: env["BENCH_MP_MODEL"] ?? "pose_landmarker_full", gpu: env["BENCH_MP_DELEGATE"] != "cpu",
                        seconds: Double(env["BENCH_SECONDS"] ?? "") ?? 150)
        case "all":
            let fasterGPU = try latency(image)
            for (model, gpu) in fasterGPU.sorted(by: { $0.key < $1.key }) {
                Thread.sleep(forTimeInterval: cooldown)
                try sustain(image, model: model, gpu: gpu, seconds: 150)
            }
            for model in ["pose_landmarker_full", "rtmpose_m_forward"] {
                print("BENCH paced \(model)")
                try PipelineBench(overrides: ["BENCH_MODEL": model, "BENCH_PACED": "1", "BENCH_SECONDS": "180",
                                              "BENCH_MP_DELEGATE": fasterGPU["pose_landmarker_full"]! ? "gpu" : "cpu"]).run()
            }
        default:
            _ = try latency(image)
        }
    }

    static func sustain(_ image: MPImage, model: String, gpu: Bool, seconds: Double) throws {
        let pose = try MediaPipePose(model: model, gpu: gpu, video: true)
        for _ in 0..<20 { _ = try pose.detect(image) }
        let start = CACurrentMediaTime()
        var window: [Double] = [], windowStart = start
        while CACurrentMediaTime() - start < seconds {
            window.append(try ms { _ = try pose.detect(image) })
            let elapsed = CACurrentMediaTime() - windowStart
            if elapsed >= 10 {
                report(model, String(format: "delegate=%@ t=%.0fs fps=%.1f thermal=%d", gpu ? "gpu" : "cpu",
                                     CACurrentMediaTime() - start, Double(window.count) / elapsed,
                                     ProcessInfo.processInfo.thermalState.rawValue), window)
                window = []
                windowStart = CACurrentMediaTime()
            }
        }
    }

    /// Per model: true when the GPU delegate has the lower VIDEO-mode p50.
    static func latency(_ image: MPImage) throws -> [String: Bool] {
        var p50: [String: Double] = [:]
        for model in ["pose_landmarker_lite", "pose_landmarker_full", "pose_landmarker_heavy"] {
            for gpu in [true, false] {
                for video in [true, false] {
                    var pose: MediaPipePose!
                    let loadMs = try ms { pose = try MediaPipePose(model: model, gpu: gpu, video: video) }
                    var found = 0
                    for _ in 0..<20 { found += try pose.detect(image) }
                    let times = try (0..<300).map { _ in try ms { _ = try pose.detect(image) } }
                    if video { p50["\(model) \(gpu)"] = times.sorted()[150] }
                    report(model, String(format: "delegate=%@ mode=%@ load=%.0fms found=%d/20 thermal=%d", gpu ? "gpu" : "cpu",
                                         video ? "video" : "image", loadMs, found,
                                         ProcessInfo.processInfo.thermalState.rawValue), times)
                }
            }
        }
        return Dictionary(uniqueKeysWithValues: ["pose_landmarker_lite", "pose_landmarker_full", "pose_landmarker_heavy"].map {
            ($0, p50["\($0) true"]! <= p50["\($0) false"]!)
        })
    }

    static func report(_ name: String, _ extra: String, _ times: [Double]) {
        let t = times.sorted()
        print(String(format: "BENCH %@ %@ mean=%.2f p50=%.2f p95=%.2f max=%.2f", name, extra,
                     t.reduce(0, +) / Double(t.count), t[t.count / 2], t[t.count * 95 / 100], t.last!))
        fflush(stdout)
    }

    static func ms(_ body: () throws -> Void) rethrows -> Double {
        let start = CACurrentMediaTime()
        try body()
        return (CACurrentMediaTime() - start) * 1000
    }

    /// IOSurface-backed BGRA buffer (what AVCaptureVideoDataOutput hands the app).
    static func pixelBuffer(_ image: CGImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        CIContext().render(CIImage(cgImage: image), to: buffer!)
        return buffer!
    }
}

/// One PoseLandmarker (one person, default 0.5 thresholds) and the COCO-17 subset of its 33 landmarks in pixels.
final class MediaPipePose {
    /// BlazePose index of each COCO-17 joint (nose, eyes, ears, shoulders, elbows, wrists, hips, knees, ankles).
    static let coco17Index = [0, 2, 5, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
    private let landmarker: PoseLandmarker
    private let video: Bool
    private var lastTimestamp = -1

    init(model: String, gpu: Bool, video: Bool) throws {
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = MediaPipeBench.assets.appendingPathComponent("\(model).task").path
        options.baseOptions.delegate = gpu ? .GPU : .CPU
        options.runningMode = video ? .video : .image
        options.numPoses = 1
        landmarker = try PoseLandmarker(options: options)
        self.video = video
    }

    /// Number of poses found.
    func detect(_ image: MPImage) throws -> Int { try result(image).landmarks.count }

    func coco17(_ image: MPImage, width: Int, height: Int) throws -> [PoseKeypoint]? {
        guard let landmarks = try result(image).landmarks.first else { return nil }
        return Self.coco17Index.map {
            let l = landmarks[$0]
            return PoseKeypoint(x: Double(l.x) * Double(width), y: Double(l.y) * Double(height),
                                confidence: Double(truncating: l.visibility ?? 0))
        }
    }

    private func result(_ image: MPImage) throws -> PoseLandmarkerResult {
        guard video else { return try landmarker.detect(image: image) }
        lastTimestamp = max(lastTimestamp + 1, Int(CACurrentMediaTime() * 1000))
        return try landmarker.detect(videoFrame: image, timestampInMilliseconds: lastTimestamp)
    }
}
