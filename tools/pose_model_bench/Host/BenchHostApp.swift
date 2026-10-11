import SwiftUI

/// Empty host so the latency test can run on a physical device (device tests need a host app).
@main
struct BenchHostApp: App {
    var body: some Scene { WindowGroup { Text("PoseModelBench host") } }
}
