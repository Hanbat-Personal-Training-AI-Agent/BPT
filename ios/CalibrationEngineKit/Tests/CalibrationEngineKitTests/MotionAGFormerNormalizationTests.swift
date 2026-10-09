import XCTest
@testable import CalibrationEngineKit

/// Same cases and expected outputs as tests/test_motionagformer_normalization.py (Python reference).
final class MotionAGFormerNormalizationTests: XCTestCase {
    private struct Fixture: Decodable {
        struct ImageCase: Decodable {
            let width: Int
            let height: Int
            let points: [[Double]]
            let screen: [[Double]]
            let long_side: [[Double]]
        }
        struct Frame: Decodable {
            let joints: [[Double]]
            let crop: [Double]
            let normalized: [[Double]]
        }
        struct Track: Decodable {
            let width: Int
            let height: Int
            let frames: [Frame]
        }
        let image_cases: [ImageCase]
        let track: Track
    }

    private func loadFixture() throws -> Fixture {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("tests/fixtures/motionagformer_normalization_cases.json"))
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    private func assertClose(_ got: [[Float]], _ want: [[Double]], _ message: String) {
        XCTAssertEqual(got.count, want.count, message)
        for (g, w) in zip(got, want) {
            XCTAssertEqual(Double(g[0]), w[0], accuracy: 1e-4, message)
            XCTAssertEqual(Double(g[1]), w[1], accuracy: 1e-4, message)
        }
    }

    func testDefaultIsPersonCrop() {
        XCTAssertEqual(MotionAGFormerNormalization.default3D, .personCrop)
    }

    func testImageCropsMatchPython() throws {
        for c in try loadFixture().image_cases {
            let points = c.points.map { PoseKeypoint(x: $0[0], y: $0[1], confidence: 1) }
            for (method, want) in [(MotionAGFormerNormalization.screen, c.screen), (.longSide, c.long_side)] {
                var normalizer = MotionAGFormerInputNormalizer(normalization: method)
                let got = normalizer.normalize(points, imageWidth: c.width, imageHeight: c.height)
                assertClose(got, want, "\(c.width)x\(c.height) \(method)")
            }
        }
    }

    func testPersonCropTrackMatchesPython() throws {
        let track = try loadFixture().track
        var normalizer = MotionAGFormerInputNormalizer(normalization: .personCrop)
        for (i, frame) in track.frames.enumerated() {
            let joints = frame.joints.map { PoseKeypoint(x: $0[0], y: $0[1], confidence: $0[2]) }
            let got = normalizer.normalize(joints, imageWidth: track.width, imageHeight: track.height)
            let crop = try XCTUnwrap(normalizer.tracker.crop)
            XCTAssertEqual(crop.centerX, frame.crop[0], accuracy: 1e-3, "frame \(i)")
            XCTAssertEqual(crop.centerY, frame.crop[1], accuracy: 1e-3, "frame \(i)")
            XCTAssertEqual(crop.side, frame.crop[2], accuracy: 1e-3, "frame \(i)")
            assertClose(got, frame.normalized, "frame \(i)")
        }
    }

    func testConfidencePassesThroughAndCOCOEntryPoint() throws {
        var coco = (0..<17).map { PoseKeypoint(x: 300 + Double($0) * 5, y: 200 + Double($0) * 50, confidence: 0.9) }
        coco[0].confidence = 0.4
        var normalizer = MotionAGFormerInputNormalizer()
        let frame = try PoseCoordinateTransforms.normalizedMotionAGFormerFrame(
            fromCOCO17: coco, imageWidth: 720, imageHeight: 1280, normalizer: &normalizer)
        XCTAssertEqual(frame.count, 17)
        XCTAssertEqual(frame[1][2], 0.9, accuracy: 1e-6)
        XCTAssertNotNil(normalizer.tracker.crop)
        XCTAssertTrue(frame.allSatisfy { abs($0[0]) <= 1 && abs($0[1]) <= 1 })
    }
}
