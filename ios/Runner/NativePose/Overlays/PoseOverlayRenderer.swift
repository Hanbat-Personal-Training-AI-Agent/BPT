import QuartzCore
import simd
import SwiftUI

/// Camera overlay: the body skeleton (COCO17 in frame pixels) as soft glowing lines with round caps, a neck from the
/// shoulder midpoint to the head centre and one head ring (no face lines), joints below `minConfidence` hidden, hands
/// never drawn (the hand branch still runs, for the XS input wrists only).
/// Colour per segment = the live posture severity of the rules measured on it (FormWarningTracker.liveSeverity, smoothed
/// by OverlaySeverityTrack): green #9BE15D → amber → red #FF5A4E as the quantity moves towards and past the rule
/// threshold. A segment with no rule in this phase or an unknown quantity (warming up, tracking lost, partial / bad 3D,
/// low confidence) is neutral white — never green, since green would claim "good" without evidence. Display only.
enum PoseOverlayRenderer {
    static let green = SIMD3<Double>(0x9B, 0xE1, 0x5D) / 255  // #9BE15D
    static let amber = SIMD3<Double>(0xFF, 0xB0, 0x3B) / 255
    static let red = SIMD3<Double>(0xFF, 0x5A, 0x4E) / 255  // #FF5A4E
    static let neutral = Color(white: 0.93)
    static let minConfidence = 0.3

    /// Severity 0 … 1 → green … amber … red.
    static func color(_ severity: Double) -> Color {
        let s = min(max(severity, 0), 1)
        let c = s < 0.5 ? green + (amber - green) * (s / 0.5) : amber + (red - amber) * ((s - 0.5) / 0.5)
        return Color(red: c.x, green: c.y, blue: c.z)
    }

    /// Head centre (robust: per-axis median of the confident nose, eyes and ears; at least two) or nil.
    static func headCentre(_ k: [PoseKeypoint]) -> CGPoint? {
        let face = (0...4).map { k[$0] }.filter { $0.confidence >= minConfidence }
        guard face.count >= 2 else { return nil }
        let med = { (v: [Double]) -> Double in let s = v.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }
        return CGPoint(x: med(face.map(\.x)), y: med(face.map(\.y)))
    }

    /// `point` maps frame pixels to the view; `scale` frame px → view px (for the head size).
    static func draw(_ k: [PoseKeypoint], severity: [OverlaySegment: Double], in context: inout GraphicsContext,
                     scale: Double, point: (PoseKeypoint) -> CGPoint) {
        guard k.count == 17 else { return }
        let seen = k.map { $0.confidence >= minConfidence }
        let style = { (s: OverlaySegment) -> (Color, Double) in severity[s].map { (color($0), 1.0) } ?? (neutral, 0.55) }
        var joints = Set<Int>()
        for seg in OverlaySegment.edges {
            guard case let .edge(a, b) = seg, seen[a], seen[b] else { continue }
            var p = Path()
            p.move(to: point(k[a]))
            p.addLine(to: point(k[b]))
            let (c, o) = style(seg)
            glow(p, color: c, opacity: o, in: &context)
            joints.formUnion([a, b])
        }
        // Neck + head ring: shoulder midpoint (the confident shoulders) to the head centre; hidden without a face.
        let shoulders = [5, 6].filter { seen[$0] }
        if !shoulders.isEmpty, let head = headCentre(k) {
            let neckBase = PoseKeypoint(x: shoulders.map { k[$0].x }.reduce(0, +) / Double(shoulders.count),
                                        y: shoulders.map { k[$0].y }.reduce(0, +) / Double(shoulders.count), confidence: 1)
            let headPoint = point(PoseKeypoint(x: head.x, y: head.y, confidence: 1))
            // Radius ≈ 0.22 × shoulder width, or 0.18 × torso length when the shoulders overlap (side view).
            let width = seen[5] && seen[6] ? hypot(k[5].x - k[6].x, k[5].y - k[6].y) : 0
            let hips = [11, 12].filter { seen[$0] }
            let torso = hips.isEmpty ? 0 : hypot(neckBase.x - hips.map { k[$0].x }.reduce(0, +) / Double(hips.count),
                                                 neckBase.y - hips.map { k[$0].y }.reduce(0, +) / Double(hips.count))
            let r = max(0.22 * width, 0.18 * torso, 6 / max(scale, 1e-6)) * scale
            let (c, o) = style(.neck)
            var neck = Path()
            neck.move(to: point(neckBase))
            // Stop at the ring so the line does not cross the face.
            let dx = headPoint.x - point(neckBase).x, dy = headPoint.y - point(neckBase).y, d = max(hypot(dx, dy), 1e-6)
            neck.addLine(to: CGPoint(x: headPoint.x - dx / d * r, y: headPoint.y - dy / d * r))
            glow(neck, color: c, opacity: o, in: &context)
            let ring = Path(ellipseIn: CGRect(x: headPoint.x - r, y: headPoint.y - r, width: 2 * r, height: 2 * r))
            context.fill(ring, with: .color(c.opacity(0.10 * o)))
            glow(ring, color: c, opacity: o, in: &context, core: 3)
        }
        var dots = Path()
        for i in joints {
            let p = point(k[i])
            dots.addEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
        }
        context.fill(dots, with: .color(.white.opacity(0.92)))
    }

    /// Neon look without blur filters (cheap at 30 fps): two wide faint strokes, the core line, a thin bright centre.
    private static func glow(_ path: Path, color: Color, opacity: Double, in context: inout GraphicsContext, core: Double = 4) {
        for (width, alpha) in [(16.0, 0.10), (9.0, 0.22)] {
            context.stroke(path, with: .color(color.opacity(alpha * opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: core, lineCap: .round, lineJoin: .round))
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
