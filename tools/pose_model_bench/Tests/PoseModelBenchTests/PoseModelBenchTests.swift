import CoreML
import XCTest

final class PoseModelBenchTests: XCTestCase {
    func testLatency() throws {
        let dir = Bundle.module.resourceURL!.appendingPathComponent("Models")
        let packages = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mlpackage" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(packages.isEmpty, "copy candidate .mlpackage files into Models/")
        let input = try MLMultiArray(shape: [1, 3, 256, 192], dataType: .float32)
        for i in 0..<input.count { input[i] = NSNumber(value: Float.random(in: -2...2)) }
        let features = try MLDictionaryFeatureProvider(dictionary: ["input_image": input])
        let compiled = try packages.map { try MLModel.compileModel(at: $0) }
        for units in [MLComputeUnits.all, .cpuAndNeuralEngine, .cpuAndGPU] {
            for (package, url) in zip(packages, compiled) {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = units
                let loadStart = Date()
                let model = try MLModel(contentsOf: url, configuration: configuration)
                let load = Date().timeIntervalSince(loadStart) * 1000
                for _ in 0..<20 { _ = try model.prediction(from: features) }
                var times: [Double] = []
                for _ in 0..<300 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    _ = try model.prediction(from: features)
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                }
                times.sort()
                let mean = times.reduce(0, +) / Double(times.count)
                print(String(format: "BENCH %@ units=%d load=%.0fms mean=%.2f p50=%.2f p95=%.2f max=%.2f",
                             package.deletingPathExtension().lastPathComponent, units.rawValue, load, mean,
                             times[times.count / 2], times[times.count * 95 / 100], times.last!))
            }
        }
    }
}
