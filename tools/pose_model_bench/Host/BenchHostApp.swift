import SwiftUI

/// Empty host so the latency test can run on a physical device (device tests need a host app).
/// Keeps the screen awake so a long sustained run is not cut by auto-lock.
@main
struct BenchHostApp: App {
    var body: some Scene {
        WindowGroup { Text("PoseModelBench host").onAppear { UIApplication.shared.isIdleTimerDisabled = true } }
    }
}
