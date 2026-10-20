import XCTest
@testable import CalibrationEngineKit

final class ExerciseMotionEstimatorTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testPythonNumericalAndStateParity() throws {
        let result = try ExerciseMotionParity.verify(Self.root.appendingPathComponent("tests/fixtures/exercise_motion_cases.json"))
        XCTAssertEqual(result.checked, 360)
        XCTAssertTrue(result.errors.isEmpty, result.errors.prefix(10).joined(separator: "\n"))
    }

    func testExplicitVariantAndProfileProvenance() throws {
        XCTAssertNil(ExerciseMotionVariant.environment(nil))
        XCTAssertNil(ExerciseMotionVariant.environment("enabled"))
        XCTAssertEqual(ExerciseMotionVariant.environment(" g "), .G)
        XCTAssertEqual(ExerciseMotionVariant.environment("HOLD"), .HOLD)
        var profile: [String: Any] = [
            "schema_version": 1, "source_type": "rgb_smpl_calibration", "source_id": "calibration-session",
            "calibration_confidence": 0.7, "bone_ratios": ["12-13": 0.4], "uses_evaluation_sequence": false,
        ]
        XCTAssertEqual(try ExerciseMotionCalibrationProfile.load(JSONSerialization.data(withJSONObject: profile)).boneRatios["12-13"], 0.4)
        profile["uses_evaluation_sequence"] = true
        XCTAssertThrowsError(try ExerciseMotionCalibrationProfile.load(JSONSerialization.data(withJSONObject: profile)))
        profile["uses_evaluation_sequence"] = false
        profile["source_type"] = "mocap_ground_truth"
        XCTAssertThrowsError(try ExerciseMotionCalibrationProfile.load(JSONSerialization.data(withJSONObject: profile)))
    }

    func testOnlineCalibrationRequiresSixtyFramesAndThirtyObservationsPerEdge() {
        let p: [SIMD3<Double>] = [
            [0,0,0], [0.08,0.02,0], [0.10,0.25,0.01], [0.12,0.48,0], [-0.08,0.02,0], [-0.10,0.25,0.01], [-0.12,0.48,0],
            [0,-0.2,0], [0,-0.4,0], [0,-0.45,0], [0,-0.52,0], [-0.20,-0.36,0], [-0.35,-0.15,0], [-0.45,0.05,0],
            [0.20,-0.36,0], [0.35,-0.15,0], [0.45,0.05,0],
        ]
        var collector = ExerciseMotionOnlineCalibration()
        var screen = p.map { SIMD3($0.x + 0.5, $0.y + 0.55, 0.9) }
        screen[13].z = 0.1
        for _ in 0..<59 { collector.observe(p, screen: screen) }
        XCTAssertTrue(collector.boneRatios.isEmpty)
        collector.observe(p, screen: screen)
        XCTAssertEqual(collector.samples, 60)
        XCTAssertNil(collector.boneRatios["12-13"])
        XCTAssertEqual(collector.boneRatios["1-2"]!, 0.5, accuracy: 1e-12)
        XCTAssertEqual(collector.boneRatios["2-3"]!, 0.5, accuracy: 1e-12)
    }
}
