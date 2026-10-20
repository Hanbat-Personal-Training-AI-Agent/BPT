import Accelerate
import CoreImage
import CoreVideo
import XCTest
@testable import CalibrationEngineKit

/// CaptureRotation (phone held in landscape): the image turn, the overlay's point mapping and the gravity hysteresis.
final class CaptureRotationTests: XCTestCase {
    private let context = CIContext(options: nil)

    /// BGRA buffer, every pixel distinct (or one bright marker pixel when `marker` is set).
    private func buffer(width: Int, height: Int, marker: (x: Int, y: Int)? = nil) -> CVPixelBuffer {
        var out: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()] as CFDictionary, &out)
        let pixels = out!
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(pixels)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x, o = y * row + x * 4
                let on = marker.map { $0.x == x && $0.y == y }
                base[o] = on.map { $0 ? 255 : 0 } ?? UInt8(i * 7 % 256)
                base[o + 1] = on.map { $0 ? 255 : 0 } ?? UInt8(i * 13 % 256)
                base[o + 2] = on.map { $0 ? 255 : 0 } ?? UInt8(i * 29 % 256)
                base[o + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    /// The device video mode's landscape emulation (VideoCameraSource.rotated, BPT_CAMERA_VIDEO_ROTATE): vImage clockwise.
    private func videoModeRotated(_ source: CVPixelBuffer, degrees: Int) -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
        let quarter = degrees / 90
        let (outW, outH) = quarter % 2 == 1 ? (height, width) : (width, height)
        var out: CVPixelBuffer?
        CVPixelBufferCreate(nil, outW, outH, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()] as CFDictionary, &out)
        let target = out!
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(target, [])
        var src = vImage_Buffer(data: CVPixelBufferGetBaseAddress(source), height: vImagePixelCount(height),
                                width: vImagePixelCount(width), rowBytes: CVPixelBufferGetBytesPerRow(source))
        var dst = vImage_Buffer(data: CVPixelBufferGetBaseAddress(target), height: vImagePixelCount(outH),
                                width: vImagePixelCount(outW), rowBytes: CVPixelBufferGetBytesPerRow(target))
        var black: [UInt8] = [0, 0, 0, 255]
        let constant = UInt8([kRotate0DegreesClockwise, kRotate90DegreesClockwise, kRotate180DegreesClockwise,
                              kRotate270DegreesClockwise][quarter])
        XCTAssertEqual(vImageRotate90_ARGB8888(&src, &dst, constant, &black, vImage_Flags(kvImageNoFlags)), kvImageNoError)
        CVPixelBufferUnlockBaseAddress(target, [])
        CVPixelBufferUnlockBaseAddress(source, .readOnly)
        return target
    }

    /// What the app hands to the pose step (CameraPosePreview.cgImageFromSampleBuffer): its pixels, rows unpadded.
    private func render(_ image: CIImage) -> (width: Int, height: Int, pixelBytes: Int, bytes: [UInt8]) {
        let cg = context.createCGImage(image, from: image.extent)!
        let data = [UInt8](cg.dataProvider!.data! as Data)
        let pixelBytes = cg.bitsPerPixel / 8
        let bytes = (0..<cg.height).flatMap { y in data[(y * cg.bytesPerRow)..<(y * cg.bytesPerRow + cg.width * pixelBytes)] }
        return (cg.width, cg.height, pixelBytes, bytes)
    }

    func testAnalysisTurnUndoesTheVideoModeRotation() {
        let original = buffer(width: 5, height: 3)
        let reference = render(CIImage(cvPixelBuffer: original))
        for degrees in [90, 180, 270] {
            let held = videoModeRotated(original, degrees: degrees)
            let rotation = CaptureRotation(rawValue: degrees)!
            let restored = render(rotation.analysisImage(CIImage(cvPixelBuffer: held)))
            XCTAssertEqual(restored.width, 5)
            XCTAssertEqual(restored.height, 3)
            XCTAssertEqual(restored.bytes, reference.bytes, "BPT_FORCE_CAPTURE_ROTATION=\(degrees) undoes BPT_CAMERA_VIDEO_ROTATE=\(degrees)")
        }
    }

    func testOverlayMappingFollowsTheImageTurn() {
        let (w, h) = (6, 4)
        for rotation in [CaptureRotation.up, .cw90, .cw180, .cw270] {
            for marker in [(x: 0, y: 0), (x: 5, y: 1), (x: 2, y: 3)] {
                let analysis = render(rotation.analysisImage(CIImage(cvPixelBuffer: buffer(width: w, height: h, marker: marker))))
                let size = rotation.bufferSize(width: Double(analysis.width), height: Double(analysis.height))
                XCTAssertEqual(size.width, Double(w))
                XCTAssertEqual(size.height, Double(h))
                // The marker is the one white pixel (every channel 255); the rest is opaque black.
                var found: [(x: Int, y: Int)] = []
                for y in 0..<analysis.height {
                    for x in 0..<analysis.width {
                        let o = (y * analysis.width + x) * analysis.pixelBytes
                        if analysis.bytes[o..<(o + analysis.pixelBytes)].allSatisfy({ $0 == 255 }) { found.append((x, y)) }
                    }
                }
                XCTAssertEqual(found.count, 1, "\(rotation) \(marker)")
                guard let at = found.first else { continue }
                // Pixel centre in the analysis frame → the same pixel's centre in the buffer.
                let p = rotation.bufferPoint(x: Double(at.x) + 0.5, y: Double(at.y) + 0.5, bufferWidth: size.width,
                                             bufferHeight: size.height)
                XCTAssertEqual(p.x, Double(marker.x) + 0.5, "\(rotation) \(marker)")
                XCTAssertEqual(p.y, Double(marker.y) + 0.5, "\(rotation) \(marker)")
            }
        }
    }

    func testPortraitTouchesNothing() {
        let image = CIImage(cvPixelBuffer: buffer(width: 4, height: 3))
        XCTAssertTrue(CaptureRotation.up.analysisImage(image) === image)
        let p = CaptureRotation.up.bufferPoint(x: 1.25, y: 2.5, bufferWidth: 720, bufferHeight: 1280)
        XCTAssertEqual(p.x, 1.25)
        XCTAssertEqual(p.y, 2.5)
        XCTAssertEqual(CaptureRotation.up.bufferSize(width: 720, height: 1280).width, 720)
        XCTAssertEqual(CaptureRotation.cw90.bufferSize(width: 1280, height: 720).width, 720)
    }

    func testNearestQuarter() {
        let cases: [(Double, CaptureRotation)] = [(0, .up), (44, .up), (46, .cw90), (-46, .cw270), (-90, .cw270),
                                                   (135.5, .cw180), (180, .cw180), (-180, .cw180), (-270, .cw90),
                                                   (359, .up), (720, .up)]
        for (degrees, want) in cases { XCTAssertEqual(CaptureRotation(nearestTo: degrees), want, "\(degrees)") }
    }

    /// Gravity of a phone whose world-up shows `upDegrees` clockwise from buffer-up, tilted back so only `screen` of
    /// gravity lies in the screen plane.
    private func gravity(_ upDegrees: Double, screen: Double = 1) -> (x: Double, y: Double) {
        let a = upDegrees * .pi / 180
        return (-sin(a) * screen, -cos(a) * screen)
    }

    func testGravityPicksTheQuarterWithHysteresis() {
        var tracker = CaptureRotationTracker()
        func feed(_ upDegrees: Double, screen: Double = 1) -> CaptureRotation {
            let g = gravity(upDegrees, screen: screen)
            return tracker.update(gravityX: g.x, gravityY: g.y)
        }
        XCTAssertEqual(feed(0), .up, "portrait upright")
        XCTAssertEqual(tracker.update(gravityX: 0, gravityY: -1), .up)
        XCTAssertEqual(feed(60), .up, "past 45° but inside the band")
        XCTAssertEqual(feed(70), .cw90, "landscape: scene shows turned clockwise")
        XCTAssertEqual(feed(30), .cw90, "coming back: held until past the band")
        XCTAssertEqual(feed(20), .up)
        XCTAssertEqual(feed(-80), .cw270, "the other landscape (device right side down: gravity x = +1)")
        XCTAssertEqual(tracker.update(gravityX: 1, gravityY: 0), .cw270)
        XCTAssertEqual(feed(90, screen: 0.3), .cw270, "lying flat: roll ignored")
        XCTAssertEqual(feed(90, screen: 0.6), .cw90, "propped up again")
        XCTAssertEqual(feed(180), .cw180, "upside down")
        XCTAssertEqual(feed(-135), .cw180, "diagonal between 180 and 270 keeps 180")
    }

    func testGravityNoiseAroundADiagonalDoesNotFlicker() {
        var tracker = CaptureRotationTracker(rotation: .cw90)
        var seen = Set<CaptureRotation>()
        for i in 0..<300 {
            let g = gravity(45 + 15 * sin(Double(i) * 0.7))  // ±15° around the 45° boundary
            seen.insert(tracker.update(gravityX: g.x, gravityY: g.y))
        }
        XCTAssertEqual(seen, [.cw90])
    }
}
