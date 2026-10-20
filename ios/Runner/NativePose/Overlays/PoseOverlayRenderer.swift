import QuartzCore
import simd
import SwiftUI

/// Camera overlay: the body skeleton (COCO17 in frame pixels) as soft glowing lime lines with round caps, joints below
/// `minConfidence` hidden (no gray low-confidence clutter, no face lines), and the edges behind the posture warnings of
/// the last judged rep (FormGeometry.causeEdges of FormWarningTracker's own judgement, whether or not the key is enabled
/// for Flutter) glowing red, fading out over `highlightSeconds`. Hands are never drawn: the hand branch still runs, for
/// the XS input wrists only.
enum PoseOverlayRenderer {
    static let lime = Color(red: 0xBF / 255, green: 0xED / 255, blue: 0x5F / 255)  // #BFED5F, AppColors.green
    static let limeGlow = Color(red: 0x9B / 255, green: 0xE1 / 255, blue: 0x5D / 255)  // #9BE15D
    static let red = Color(red: 1.0, green: 0.36, blue: 0.33)
    static let minConfidence = 0.3
    static let highlightSeconds = 1.3

    /// `point` maps frame pixels to the view. `warning`: cause edges and when their rep was judged (CACurrentMediaTime).
    static func draw(_ k: [PoseKeypoint], warning: (edges: [[Int]], at: CFTimeInterval)?, in context: inout GraphicsContext,
                     point: (PoseKeypoint) -> CGPoint) {
        guard k.count == 17 else { return }
        let seen = k.map { $0.confidence >= minConfidence }
        let shown = FormGeometry.overlayEdges.filter { seen[$0[0]] && seen[$0[1]] }
        glow(path(shown, k, point), color: limeGlow, core: lime, opacity: 1, in: &context)

        var dots = Path()
        for i in Set(shown.flatMap { $0 }) where i > 4 {  // ears end the neck lines, no dot
            let p = point(k[i])
            dots.addEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
        }
        if seen[0] {  // head: one ring at the nose instead of the face lines
            let p = point(k[0])
            context.stroke(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)),
                           with: .color(lime.opacity(0.9)), lineWidth: 2.5)
        }
        context.fill(dots, with: .color(.white.opacity(0.92)))

        guard let warning else { return }
        let age = CACurrentMediaTime() - warning.at
        let fade = age < 0.3 ? 1 : max(0, 1 - (age - 0.3) / (highlightSeconds - 0.3))
        guard fade > 0 else { return }
        glow(path(warning.edges.filter { seen[$0[0]] && seen[$0[1]] }, k, point), color: red, core: red, opacity: fade, in: &context)
    }

    private static func path(_ edges: [[Int]], _ k: [PoseKeypoint], _ point: (PoseKeypoint) -> CGPoint) -> Path {
        var p = Path()
        for e in edges {
            p.move(to: point(k[e[0]]))
            p.addLine(to: point(k[e[1]]))
        }
        return p
    }

    /// Neon look without blur filters (cheap at 30 fps): two wide faint strokes, the core line, a thin bright centre.
    private static func glow(_ path: Path, color: Color, core: Color, opacity: Double, in context: inout GraphicsContext) {
        for (width, alpha) in [(16.0, 0.10), (9.0, 0.22)] {
            context.stroke(path, with: .color(color.opacity(alpha * opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        context.stroke(path, with: .color(core.opacity(opacity)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(.white.opacity(0.5 * opacity)),
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
