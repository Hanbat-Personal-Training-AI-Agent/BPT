import SwiftUI

/// Host so the latency test can run on a physical device (device tests need a host app).
/// Keeps the screen awake so a long sustained run is not cut by auto-lock.
/// Launched with BENCH_PIPELINE=1 it runs PipelineBench (BENCH_MP=latency|sustain: MediaPipeBench) in the foreground and exits.
@main
struct BenchHostApp: App {
    init() {
        guard ProcessInfo.processInfo.environment["BENCH_PIPELINE"] == "1" else { return }
        Thread.detachNewThread {
            Thread.current.qualityOfService = .userInitiated
            do {
                if ProcessInfo.processInfo.environment["BENCH_MP"] != nil { try MediaPipeBench.run() } else { try PipelineBench().run() }
                print("BENCH DONE")
            } catch { print("BENCH ERROR \(error)") }
            fflush(stdout)
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup { Text("PoseModelBench host").onAppear { UIApplication.shared.isIdleTimerDisabled = true } }
    }
}
