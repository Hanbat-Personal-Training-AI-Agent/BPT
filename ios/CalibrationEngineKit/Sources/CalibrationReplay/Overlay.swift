import AppKit
import AVFoundation
import CoreImage

/// Writes the replayed frames back out as an MP4 with everything the engine looked at drawn on top.
final class OverlayVideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let context: CIContext
    let size: CGSize

    init(url: URL, size: CGSize, context: CIContext) throws {
        try? FileManager.default.removeItem(at: url)
        self.size = size
        self.context = context
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    /// Renders `image`, then lets `draw` paint on it in top-left pixel coordinates.
    func append(_ image: CIImage, at time: CMTime, draw: (CGContext) -> Void) {
        guard let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let pixelBuffer = buffer else { return }
        context.render(image, to: pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let cg = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                              width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
            draw(cg)
            NSGraphicsContext.restoreGraphicsState()
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        while !input.isReadyForMoreMediaData { usleep(1000) }
        adaptor.append(pixelBuffer, withPresentationTime: time)
    }

    func finish() {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
    }
}

/// Everything one overlay frame shows.
struct OverlayState {
    var t: Double
    var size: CGSize
    var keypoints: [PoseKeypoint]
    var crop: CGRect
    var faceBox: CGRect?
    var face: CalibrationFace
    var result: CalibrationEngineOutput
    var reference: CalibrationReference?
    var motion: Double?
    var candidate: CalibrationView?
    var r: Double?
    var delta: Double?
    var config: CalibrationConfig
    var lenient: Bool
    /// Shown for a moment after a capture.
    var flash: CalibrationView?
}

private let skeleton: [(Int, Int)] = [
    (5, 6), (5, 7), (7, 9), (6, 8), (8, 10), (5, 11), (6, 12), (11, 12),
    (11, 13), (13, 15), (12, 14), (14, 16), (0, 1), (0, 2), (1, 3), (2, 4),
]

private let green = NSColor(calibratedRed: 0.42, green: 0.90, blue: 0.40, alpha: 1)
private let red = NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.35, alpha: 1)
private let amber = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.25, alpha: 1)
private let grey = NSColor(white: 0.62, alpha: 1)

private func label(_ view: CalibrationView?) -> String {
    guard let view else { return "없음" }
    return "\(view.koreanName)(\(view.rawValue))"
}

private func text(_ string: String, _ point: CGPoint, size: CGFloat, color: NSColor = .white, bold: Bool = false) {
    let font = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .medium)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.9)
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = .zero
    (string as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color, .shadow: shadow])
}

private func stroke(_ cg: CGContext, _ points: [CGPoint], _ color: NSColor, width: CGFloat, dash: [CGFloat] = []) {
    guard points.count > 1 else { return }
    cg.saveGState()
    cg.setStrokeColor(color.cgColor)
    cg.setLineWidth(width)
    cg.setLineDash(phase: 0, lengths: dash)
    cg.addLines(between: points)
    cg.strokePath()
    cg.restoreGState()
}

private func fill(_ cg: CGContext, _ rect: CGRect, _ color: NSColor) {
    cg.setFillColor(color.cgColor)
    cg.fill(rect)
}

private enum Mark { case pass, fail, skip }

private func mark(_ ok: Bool?) -> Mark { ok.map { $0 ? .pass : .fail } ?? .skip }

private func row(_ cg: CGContext, _ x: CGFloat, _ y: CGFloat, _ state: Mark, _ name: String, _ value: String) {
    let (symbol, color): (String, NSColor) = switch state {
    case .pass: ("✓", green)
    case .fail: ("✗", red)
    case .skip: ("–", grey)
    }
    text(symbol, CGPoint(x: x, y: y), size: 16, color: color, bold: true)
    text(name, CGPoint(x: x + 18, y: y), size: 15, color: state == .skip ? grey : .white, bold: true)
    text(value, CGPoint(x: x + 128, y: y), size: 15, color: state == .skip ? grey : color)
}

private func range(_ value: Double?, _ lo: Double, _ hi: Double) -> String {
    guard let value else { return "-" }
    return String(format: "%.2f  (%.2f–%.2f)", value, lo, hi)
}

func drawOverlay(_ cg: CGContext, _ s: OverlayState) {
    let w = s.size.width, h = s.size.height
    let m = s.result.measurement
    let c = s.config
    let px = { (x: Double, y: Double) in CGPoint(x: x * w, y: y * h) }

    // --- on the person -----------------------------------------------------------------
    stroke(cg, [CGPoint(x: s.crop.minX, y: s.crop.minY), CGPoint(x: s.crop.maxX, y: s.crop.minY),
                CGPoint(x: s.crop.maxX, y: s.crop.maxY), CGPoint(x: s.crop.minX, y: s.crop.maxY),
                CGPoint(x: s.crop.minX, y: s.crop.minY)], amber.withAlphaComponent(0.7), width: 2, dash: [10, 8])
    text("RTMPose 크롭", CGPoint(x: max(4, s.crop.minX + 6), y: max(164, s.crop.minY + 4)), size: 13, color: amber)

    if let m {
        // allowed centre band and measured centre line
        fill(cg, CGRect(x: (0.5 - c.framing.maxCentreOffset) * w, y: 160, width: 2 * c.framing.maxCentreOffset * w,
                        height: h - 320), NSColor(white: 1, alpha: 0.05))
        stroke(cg, [px(m.midX, 0.13), px(m.midX, 0.87)], NSColor(white: 1, alpha: 0.55), width: 1.5, dash: [4, 6])
        // head top / feet estimates
        stroke(cg, [px(m.midX - 0.22, m.headTop), px(m.midX + 0.22, m.headTop)], amber, width: 2)
        text(String(format: "머리 끝 추정 %.2f", m.headTop), CGPoint(x: (m.midX + 0.23) * w, y: m.headTop * h - 10), size: 13, color: amber)
        stroke(cg, [px(m.midX - 0.22, m.feet), px(m.midX + 0.22, m.feet)], amber, width: 2)
        text(String(format: "발 끝 추정 %.2f", m.feet), CGPoint(x: (m.midX + 0.23) * w, y: m.feet * h - 10), size: 13, color: amber)
        if let ref = s.reference {
            stroke(cg, [px(ref.midX, 0.13), px(ref.midX, 0.87)], green.withAlphaComponent(0.8), width: 1.5, dash: [12, 6])
            stroke(cg, [px(ref.midX - 0.25, ref.feet), px(ref.midX + 0.25, ref.feet)], green.withAlphaComponent(0.8),
                   width: 1.5, dash: [12, 6])
            text("정면 기준 위치", CGPoint(x: (ref.midX - 0.25) * w, y: ref.feet * h + 4), size: 13, color: green)
        }
    }

    for (a, b) in skeleton {
        let ka = s.keypoints[a], kb = s.keypoints[b]
        guard min(ka.confidence, kb.confidence) >= 0.3 else { continue }
        let side: NSColor = a % 2 == 1 && b % 2 == 1 ? NSColor(calibratedRed: 0.35, green: 0.70, blue: 1, alpha: 1)
            : a % 2 == 0 && b % 2 == 0 && a > 0 ? NSColor(calibratedRed: 1, green: 0.55, blue: 0.25, alpha: 1)
            : .white
        stroke(cg, [CGPoint(x: ka.x, y: ka.y), CGPoint(x: kb.x, y: kb.y)], side, width: 3)
    }
    for k in s.keypoints {
        let color = k.confidence >= 0.6 ? green : k.confidence >= 0.3 ? amber : red
        cg.setFillColor(color.cgColor)
        cg.fillEllipse(in: CGRect(x: k.x - 4, y: k.y - 4, width: 8, height: 8))
    }
    if let box = s.faceBox {
        stroke(cg, [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                    CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY),
                    CGPoint(x: box.minX, y: box.minY)], .cyan, width: 2)
        text(s.face.yawDeg.map { String(format: "얼굴 %.0f°", $0) } ?? "얼굴", CGPoint(x: box.minX, y: box.minY - 18),
             size: 14, color: .cyan, bold: true)
    }

    // --- top band: every gate with its value and limits ---------------------------------
    fill(cg, CGRect(x: 0, y: 0, width: w, height: 160), NSColor(white: 0, alpha: 0.82))
    let captured = CalibrationView.recommendedOrder
        .map { "\($0.koreanName)\(s.result.capturedViews.contains($0) ? "✓" : "·")" }.joined(separator: " ")
    text(String(format: "t %5.2fs   목표 %@   촬영 %@", s.t, label(s.result.targetView), captured),
         CGPoint(x: 10, y: 4), size: 15, color: .white, bold: true)

    let frontStage = s.reference == nil
    let required = CocoJoint.required.filter { s.keypoints[$0.rawValue].confidence >= c.framing.minKeypointConfidence }.count
    let x1: CGFloat = 10, x2: CGFloat = w / 2 + 4
    var y: CGFloat = 26
    let step: CGFloat = 19
    row(cg, x1, y, mark(required == 12), "전신 12관절", "\(required)/12 (≥\(c.framing.minKeypointConfidence))"); y += step
    row(cg, x1, y, mark(m.map { $0.bodyHeight >= c.framing.minBodyHeight && $0.bodyHeight <= c.framing.maxBodyHeight }),
        "몸 높이", range(m?.bodyHeight, c.framing.minBodyHeight, c.framing.maxBodyHeight)); y += step
    row(cg, x1, y, mark(m.map { $0.headTop >= c.framing.minHeadTop && $0.feet <= c.framing.maxFeet }),
        "머리·발 화면 안", m.map { String(format: "%.2f / %.2f", $0.headTop, $0.feet) } ?? "-"); y += step
    row(cg, x1, y, mark(m.map { abs($0.midX - 0.5) <= c.framing.maxCentreOffset }),
        "화면 가운데", m.map { String(format: "%.2f  (0.5±%.2f)", $0.midX, c.framing.maxCentreOffset) } ?? "-"); y += step
    if let ref = s.reference, let m {
        row(cg, x1, y, mark(abs(m.feet - ref.feet) <= c.stance.maxFeetDrift), "제자리 발",
            String(format: "%+.3f  (±%.2f)", m.feet - ref.feet, c.stance.maxFeetDrift)); y += step
        row(cg, x1, y, mark(abs(m.midX - ref.midX) <= c.stance.maxCentreDrift), "제자리 중심",
            String(format: "%+.3f  (±%.2f)", m.midX - ref.midX, c.stance.maxCentreDrift)); y += step
    } else {
        row(cg, x1, y, .skip, "제자리 발", "정면 촬영 후"); y += step
        row(cg, x1, y, .skip, "제자리 중심", "정면 촬영 후"); y += step
    }
    row(cg, x1, y, mark(s.motion.map { $0 <= c.capture.maxMotionPerSecond }), "정지 속도",
        s.motion.map { String(format: "%.3f/s  (≤%.3f/s)", $0, c.capture.maxMotionPerSecond) } ?? "-")

    y = 26
    let a = c.aPose
    let wristOK = m.map { [$0.leftWristDrop, $0.rightWristDrop].allSatisfy { $0 >= a.minWristDrop && $0 <= a.maxWristDrop } }
    row(cg, x2, y, mark(wristOK), "손목 높이 L/R",
        m.map { String(format: "%.2f/%.2f (%.2f–%.2f)", $0.leftWristDrop, $0.rightWristDrop, a.minWristDrop, a.maxWristDrop) } ?? "-"); y += step
    let elbowOK = m.map { [$0.leftElbowRatio, $0.rightElbowRatio].allSatisfy { $0 >= a.minElbowRatio && $0 <= a.maxElbowRatio } }
    row(cg, x2, y, mark(elbowOK), "팔꿈치 L/R",
        m.map { String(format: "%.2f/%.2f (%.2f–%.2f)", $0.leftElbowRatio, $0.rightElbowRatio, a.minElbowRatio, a.maxElbowRatio) } ?? "-"); y += step
    row(cg, x2, y, frontStage ? mark(m.map { $0.wristReach >= a.minWristReach }) : .skip, "팔 벌림(정면)",
        frontStage ? (m.map { String(format: "%.2f  (≥%.2f)", $0.wristReach, a.minWristReach) } ?? "-") : "정면에서만"); y += step
    row(cg, x2, y, frontStage ? mark(m.map { $0.ankleGapOverHipWidth >= a.minAnkleGapOverHipWidth
                                          && $0.ankleGapOverHipWidth <= a.maxAnkleGapOverHipWidth }) : .skip,
        "발 간격(정면)", frontStage ? range(m?.ankleGapOverHipWidth, a.minAnkleGapOverHipWidth, a.maxAnkleGapOverHipWidth) : "정면에서만"); y += step
    row(cg, x2, y, s.face.isDetected ? .pass : .skip, "얼굴 검출",
        s.face.isDetected ? (s.face.yawDeg.map { String(format: "있음, 고개 %.0f°", $0) } ?? "있음") : "없음"); y += step
    row(cg, x2, y, s.r == nil ? .skip : .pass, "r / δ",
        s.r.map { String(format: "%.2f / %+.2f", $0, s.delta ?? 0) } ?? "정면 촬영 후"); y += step
    row(cg, x2, y, s.candidate == nil ? .skip : .pass, "방향 후보", label(s.candidate))

    // --- bottom band: the engine's final decision ---------------------------------------
    let bottom = h - 160
    fill(cg, CGRect(x: 0, y: bottom, width: w, height: 160), NSColor(white: 0, alpha: 0.82))
    let result = s.result
    let headline: NSColor = result.capture != nil ? green : result.isPassing ? amber : .white
    text("최종 판정", CGPoint(x: 10, y: bottom + 8), size: 14, color: grey, bold: true)
    text(result.guidance.message, CGPoint(x: 10, y: bottom + 26), size: 26, color: headline, bold: true)
    text("엔진 분류: \(label(result.classifiedView))", CGPoint(x: 10, y: bottom + 70), size: 17, color: .white, bold: true)
    // stillness hold bar
    let barX: CGFloat = w / 2, barY = bottom + 74, barW = w / 2 - 20
    fill(cg, CGRect(x: barX, y: barY, width: barW, height: 14), NSColor(white: 1, alpha: 0.15))
    fill(cg, CGRect(x: barX, y: barY, width: barW * result.holdProgress, height: 14), result.isPassing ? green : grey)
    text(String(format: "정지 %.1f / %.1fs", result.holdProgress * c.capture.holdDuration, c.capture.holdDuration),
         CGPoint(x: barX, y: barY + 18), size: 13, color: grey)
    text(s.lenient ? "자세 기준 완화 모드 (손목 0.50–1.15, 팔 벌림 ≥0.20, 발 간격 ≥0.50)" : "앱 기준",
         CGPoint(x: 10, y: bottom + 130), size: 13, color: s.lenient ? amber : grey)

    // --- capture flash ---------------------------------------------------------------------
    if let view = s.flash {
        stroke(cg, [CGPoint(x: 3, y: 163), CGPoint(x: w - 3, y: 163), CGPoint(x: w - 3, y: bottom - 3),
                    CGPoint(x: 3, y: bottom - 3), CGPoint(x: 3, y: 163)], green, width: 6)
        text("● \(view.koreanName) 촬영", CGPoint(x: w / 2 - 90, y: 176), size: 30, color: green, bold: true)
    }
}
