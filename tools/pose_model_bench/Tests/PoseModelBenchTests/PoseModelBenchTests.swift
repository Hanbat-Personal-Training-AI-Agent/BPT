import CoreML
import Vision
import XCTest

/// Latency of the Models/*.mlpackage candidates (and Apple Vision as a reference) on one real 720x1280 frame.
/// Env (from xcodebuild: TEST_RUNNER_<NAME>=...): BENCH_SUSTAIN_MODEL=<package name> runs only testSustained
/// for BENCH_SECONDS (default 150) with BENCH_UNITS=all|cpune, after BENCH_COOLDOWN idle seconds (default 0) spent
/// inside the foreground host app so the phone cannot auto-lock between runs.
final class PoseModelBenchTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var models: URL { Bundle(for: Self.self).resourceURL!.appendingPathComponent("Models") }

    private func frame() throws -> CGImage {
        let data = try Data(contentsOf: models.appendingPathComponent("frame.jpg"))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// The whole frame resized to 192x256, ImageNet-normalized NCHW (latency does not depend on the crop).
    private func input(_ image: CGImage) throws -> MLFeatureProvider {
        let (w, h) = (192, 256)
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: h), NSNumber(value: w)], dataType: .float32)
        let mean: [Float] = [123.675, 116.28, 103.53], std: [Float] = [58.395, 57.12, 57.375]
        for c in 0..<3 { for p in 0..<(w * h) { array[c * w * h + p] = NSNumber(value: (Float(rgba[p * 4 + c]) - mean[c]) / std[c]) } }
        return try MLDictionaryFeatureProvider(dictionary: ["input_image": array])
    }

    private func report(_ name: String, _ extra: String, _ times: [Double]) {
        let t = times.sorted()
        print(String(format: "BENCH %@ %@ mean=%.2f p50=%.2f p95=%.2f max=%.2f", name, extra,
                     t.reduce(0, +) / Double(t.count), t[t.count / 2], t[t.count * 95 / 100], t.last!))
    }

    private func ms(_ body: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    private func load(_ name: String, _ units: MLComputeUnits) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units
        let compiled = try MLModel.compileModel(at: models.appendingPathComponent("\(name).mlpackage"))
        return try MLModel(contentsOf: compiled, configuration: configuration)
    }

    func testLatency() throws {
        try XCTSkipIf(env["BENCH_SUSTAIN_MODEL"] != nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: models.path)
            .filter { $0.hasSuffix(".mlpackage") }.map { String($0.dropLast(10)) }.sorted()
        XCTAssertFalse(names.isEmpty, "copy candidate .mlpackage files into Models/")
        let features = try input(frame())
        for units in [MLComputeUnits.all, .cpuAndNeuralEngine, .cpuAndGPU] {
            for name in names {
                var model: MLModel!
                let loadMs = try ms { model = try load(name, units) }
                for _ in 0..<20 { _ = try model.prediction(from: features) }
                let times = try (0..<300).map { _ in try ms { _ = try model.prediction(from: features) } }
                report(name, String(format: "units=%d load=%.0fms", units.rawValue, loadMs), times)
            }
        }
    }

    /// Apple Vision 2D body pose on the same frame, one handler per frame like a camera pipeline.
    func testVision() throws {
        try XCTSkipIf(env["BENCH_SUSTAIN_MODEL"] != nil)
        let image = try frame()
        func run() throws -> Int {
            let request = VNDetectHumanBodyPoseRequest()
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            return request.results?.count ?? 0
        }
        XCTAssertEqual(try run(), 1)
        for _ in 0..<20 { _ = try run() }
        report("vision_body_pose", "units=vision", try (0..<300).map { _ in try ms { _ = try run() } })
    }

    /// Back-to-back inference for BENCH_SECONDS; one line per 10 s window with FPS and thermal state
    /// (0 nominal, 1 fair, 2 serious, 3 critical).
    func testSustained() throws {
        guard let name = env["BENCH_SUSTAIN_MODEL"] else { throw XCTSkip("set TEST_RUNNER_BENCH_SUSTAIN_MODEL") }
        let seconds = Double(env["BENCH_SECONDS"] ?? "") ?? 150
        let units: MLComputeUnits = env["BENCH_UNITS"] == "cpune" ? .cpuAndNeuralEngine : .all
        Thread.sleep(forTimeInterval: Double(env["BENCH_COOLDOWN"] ?? "") ?? 0)
        let model = try load(name, units)
        let features = try input(frame())
        for _ in 0..<20 { _ = try model.prediction(from: features) }
        let start = Date()
        var window: [Double] = []
        var windowStart = start
        while Date().timeIntervalSince(start) < seconds {
            window.append(try ms { _ = try model.prediction(from: features) })
            let elapsed = Date().timeIntervalSince(windowStart)
            if elapsed >= 10 {
                report(name, String(format: "units=%d t=%.0fs fps=%.1f thermal=%d", units.rawValue,
                                    Date().timeIntervalSince(start), Double(window.count) / elapsed,
                                    ProcessInfo.processInfo.thermalState.rawValue), window)
                window = []
                windowStart = Date()
            }
        }
    }
}
