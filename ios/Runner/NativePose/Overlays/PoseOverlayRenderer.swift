import QuartzCore
import simd
import SwiftUI

/// Camera overlay: the body only (shoulders, arms, torso, hips, legs; COCO17 in frame pixels) as soft glowing lines with
/// round caps. No face, head or neck, no hands (the hand branch still runs, for the XS input wrists only); joints below
/// `minConfidence` hidden. Colour per segment (FormWarningTracker.liveSeverity, smoothed by OverlaySeverityTrack): green
/// #9BE15D by default (no issue, or no rule applies in this phase / view, or no baseline yet), through amber to red
/// #FF5A4E as a rule's quantity moves towards and past its threshold; dimmed green when the 3D is uncertain (warming
/// up, tracking lost, bad or partial 3D, low confidence) — never red then. Display only.
enum PoseOverlayRenderer {
    static let green = SIMD3<Double>(0x9B, 0xE1, 0x5D) / 255  // #9BE15D
    static let amber = SIMD3<Double>(0xFF, 0xB0, 0x3B) / 255
    static let red = SIMD3<Double>(0xFF, 0x5A, 0x4E) / 255  // #FF5A4E
    static let minConfidence = 0.3

    /// Severity 0 … 1 → green … amber … red.
    static func color(_ severity: Double) -> Color {
        let s = min(max(severity, 0), 1)
        let c = s < 0.5 ? green + (amber - green) * (s / 0.5) : amber + (red - amber) * ((s - 0.5) / 0.5)
        return Color(red: c.x, green: c.y, blue: c.z)
    }

    /// `point` maps frame pixels to the view; `shade` = (severity, opacity) per segment (missing = plain green).
    static func draw(_ k: [PoseKeypoint], shade: [OverlaySegment: (severity: Double, opacity: Double)],
                     in context: inout GraphicsContext, point: (PoseKeypoint) -> CGPoint) {
        guard k.count == 17 else { return }
        let seen = k.map { $0.confidence >= minConfidence }
        var joints: [Int: Double] = [:]  // joint → brightest opacity of its drawn segments
        for seg in OverlaySegment.edges {
            guard case let .edge(a, b) = seg, seen[a], seen[b] else { continue }
            var p = Path()
            p.move(to: point(k[a]))
            p.addLine(to: point(k[b]))
            let (severity, opacity) = shade[seg] ?? (severity: 0.0, opacity: 1.0)
            glow(p, color: color(severity), opacity: opacity, in: &context)
            for j in [a, b] { joints[j] = max(joints[j] ?? 0, opacity) }
        }
        for (i, opacity) in joints {
            let p = point(k[i])
            context.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                         with: .color(.white.opacity(0.92 * opacity)))
        }
    }

    /// Neon look without blur filters (cheap at 30 fps): two wide faint strokes, the core line, a thin bright centre.
    private static func glow(_ path: Path, color: Color, opacity: Double, in context: inout GraphicsContext) {
        for (width, alpha) in [(16.0, 0.10), (9.0, 0.22)] {
            context.stroke(path, with: .color(color.opacity(alpha * opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(.white.opacity(0.45 * opacity)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}

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
            x = k.map { $0.confidence >= PoseOverlayRenderer.minConfidence ? SIMD2($0.x, $0.y) : nil }
            dx = Array(repeating: .zero, count: k.count)
            return k
        }
        let dt = now - last
        let alpha = { (hz: Double) in 1 / (1 + 1 / (2 * Double.pi * hz * dt)) }
        var out = k
        for i in k.indices {
            let p = SIMD2(k[i].x, k[i].y)
            guard k[i].confidence >= PoseOverlayRenderer.minConfidence, let prev = x[i] else {
                x[i] = k[i].confidence >= PoseOverlayRenderer.minConfidence ? p : nil
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
