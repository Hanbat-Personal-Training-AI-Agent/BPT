import QuartzCore
import simd
import SwiftUI

/// Display-only rule observations: neutral dashed = withheld, slate dotted = relative consistency only,
/// solid green = observed frame geometry within the displayed rules (not whole-form approval).
/// Known issues retain severity with dashed strokes when coverage/scope is limited. Raw wrist uncertainty wins.
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

    /// Missing shade is unassessed, never implicitly green.
    static func draw(_ k: [PoseKeypoint], shade: [OverlaySegment: OverlayShade],
                     uncertainJoints: Set<Int> = [], in context: inout GraphicsContext, point: (PoseKeypoint) -> CGPoint) {
        guard k.count == 17 else { return }
        let seen = k.map { $0.confidence >= minConfidence }
        var joints: [Int: Double] = [:]  // joint → brightest opacity of its drawn segments
        for seg in OverlaySegment.edges {
            guard case let .edge(a, b) = seg, seen[a], seen[b] else { continue }
            var p = Path()
            p.move(to: point(k[a]))
            p.addLine(to: point(k[b]))
            let sample = shade[seg] ?? OverlayShade()
            let severity = sample.severity, opacity = sample.opacity
            let style = sample.style(rawJointUncertain: uncertainJoints.contains(a) || uncertainJoints.contains(b))
            if style == .withheld {
                context.stroke(p, with: .color(.gray.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
                continue  // no solid glow/joint dot implying observation
            }
            if style == .relative {
                context.stroke(p, with: .color(Color(red: 0.55, green: 0.65, blue: 0.75).opacity(0.75)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 4]))
                continue
            }
            if style == .limitedIssue {
                context.stroke(p, with: .color(color(severity).opacity(opacity)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 3]))
                continue  // visible issue, no solid glow/dot implying complete assessment
            }
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
