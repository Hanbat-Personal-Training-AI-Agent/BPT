import Foundation
import simd

/// Display-only One-Euro filter (Casiez et al. 2012) on the overlay keypoints: still joints stop shimmering, fast moves
/// keep little lag. Its output is drawn and nothing else — the evaluators and the XS input get the unsmoothed keypoints.
struct OverlaySmoother {
    var minCutoffHz = 1.2
    /// Cutoff gain per px/s of joint speed.
    var beta = 0.01
    var derivativeCutoffHz = 1.0
    private var x: [SIMD2<Double>?] = []
    private var dx: [SIMD2<Double>] = []
    private var last: CFTimeInterval?

    mutating func smooth(_ k: [PoseKeypoint], at now: CFTimeInterval) -> [PoseKeypoint] {
        defer { last = now }
        guard let last, now > last, now - last < 0.5, x.count == k.count else {
            x = k.map { $0.confidence >= 0.3 ? SIMD2($0.x, $0.y) : nil }
            dx = Array(repeating: .zero, count: k.count)
            return k
        }
        let dt = now - last
        let alpha = { (hz: Double) in 1 / (1 + 1 / (2 * Double.pi * hz * dt)) }
        var out = k
        for i in k.indices {
            let p = SIMD2(k[i].x, k[i].y)
            guard k[i].confidence >= 0.3, let prev = x[i] else {
                x[i] = k[i].confidence >= 0.3 ? p : nil
                dx[i] = .zero
                continue
            }
            dx[i] += alpha(derivativeCutoffHz) * ((p - prev) / dt - dx[i])
            let q = prev + alpha(minCutoffHz + beta * simd_length(dx[i])) * (p - prev)
            x[i] = q
            out[i] = PoseKeypoint(x: q.x, y: q.y, confidence: k[i].confidence)
        }
        return out
    }
}
