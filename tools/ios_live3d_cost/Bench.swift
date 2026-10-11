import SwiftUI

import CoreML
import QuartzCore

/// On-device cost of the live pose path without a camera/person: RTMPose-s every frame (30 fps pacing),
/// optionally + MotionAGFormer-XS (27-frame window) every frame. Synthetic inputs (latency does not depend on content).
final class Bench {
    func load(_ name: String) throws -> MLModel {
        let src = Bundle.main.url(forResource: name, withExtension: "mlmodelc")!
        let c = MLModelConfiguration(); c.computeUnits = .all
        let t = CACurrentMediaTime()
        let m = try MLModel(contentsOf: src, configuration: c)
        print("BENCH load \(name) \(String(format: "%.0f", (CACurrentMediaTime() - t) * 1000)) ms")
        return m
    }
    func randomInput(_ name: String, _ shape: [Int]) throws -> MLDictionaryFeatureProvider {
        let a = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        let p = a.dataPointer.bindMemory(to: Float.self, capacity: a.count)
        for i in 0..<a.count { p[i] = Float.random(in: -1...1) }
        return try MLDictionaryFeatureProvider(dictionary: [name: a])
    }
    func cpuSeconds() -> Double { var t = timespec(); clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t); return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9 }
    func pct(_ a: [Double], _ q: Double) -> Double { let s = a.sorted(); return s[min(s.count - 1, Int(Double(s.count) * q))] }
    func thermal() -> String { ["nominal", "fair", "serious", "critical"][ProcessInfo.processInfo.thermalState.rawValue] }

    func run(_ label: String, seconds: Double, rtm: MLModel, mag: MLModel?, fps: Double) throws {
        let rIn = try randomInput("input_image", [1, 3, 256, 192])
        let mIn = try randomInput("input_2d_sequence", [1, 27, 17, 3])
        var r = [Double](), m = [Double](), tot = [Double](), late = 0
        let start = CACurrentMediaTime(), cpu0 = cpuSeconds(); var next = start; var lastLog = start
        print("BENCH \(label) start thermal=\(thermal())")
        while CACurrentMediaTime() - start < seconds {
            let t0 = CACurrentMediaTime()
            _ = try rtm.prediction(from: rIn); let t1 = CACurrentMediaTime()
            if let mag { _ = try mag.prediction(from: mIn) }; let t2 = CACurrentMediaTime()
            r.append((t1 - t0) * 1000); if mag != nil { m.append((t2 - t1) * 1000) }; tot.append((t2 - t0) * 1000)
            if fps > 0 {
                next += 1 / fps
                let wait = next - CACurrentMediaTime()
                if wait > 0 { Thread.sleep(forTimeInterval: wait) } else { late += 1; next = CACurrentMediaTime() }
            }
            if t2 - lastLog > 30 { lastLog = t2; print("BENCH \(label) t=\(Int(t2 - start))s thermal=\(thermal()) total_p50=\(String(format: "%.2f", pct(tot.suffix(900).map { $0 }, 0.5)))") }
        }
        let wall = CACurrentMediaTime() - start, cpu = cpuSeconds() - cpu0
        func s(_ a: [Double]) -> String { a.isEmpty ? "-" : String(format: "mean=%.2f p50=%.2f p90=%.2f p99=%.2f max=%.2f", a.reduce(0, +) / Double(a.count), pct(a, 0.5), pct(a, 0.9), pct(a, 0.99), a.max()!) }
        print("BENCH \(label) frames=\(tot.count) wall=\(String(format: "%.1f", wall))s achieved_fps=\(String(format: "%.1f", Double(tot.count) / wall)) late=\(late) cpu=\(String(format: "%.0f", cpu / wall * 100))% thermal_end=\(thermal())")
        print("BENCH \(label) rtmpose_ms \(s(r))"); print("BENCH \(label) mag_ms \(s(m))"); print("BENCH \(label) total_ms \(s(tot))")
    }

    func testLiveCost() throws {
        let secs = Double(ProcessInfo.processInfo.environment["BENCH_SECONDS"] ?? "") ?? 180
        let rtm = try load("rtmpose_s_forward"), mag = try load("motionagformer_xs")
        print("BENCH device=\(ProcessInfo.processInfo.operatingSystemVersionString) thermal=\(thermal())")
        try run("warmup", seconds: 5, rtm: rtm, mag: mag, fps: 0)
        try run("max_2d", seconds: 15, rtm: rtm, mag: nil, fps: 0)
        try run("max_2d3d", seconds: 15, rtm: rtm, mag: mag, fps: 0)
        try run("live30_2d", seconds: secs, rtm: rtm, mag: nil, fps: 30)
        try run("live30_2d3d", seconds: secs, rtm: rtm, mag: mag, fps: 30)
    }
}
@main struct BenchApp: App {
    init() {
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true }
            do { try Bench().testLiveCost(); print("BENCH DONE") } catch { print("BENCH ERROR \(error)") }
            fflush(stdout); exit(0)
        }
    }
    var body: some Scene { WindowGroup { Text("BPT bench running") } }
}
