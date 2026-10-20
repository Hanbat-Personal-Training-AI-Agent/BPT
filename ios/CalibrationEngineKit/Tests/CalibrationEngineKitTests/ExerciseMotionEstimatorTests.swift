import XCTest
#if canImport(CalibrationEngineKit)
@testable import CalibrationEngineKit
#endif

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
            "ground_truth_used": false,
        ]
        XCTAssertEqual(try ExerciseMotionCalibrationProfile.load(JSONSerialization.data(withJSONObject: profile)).boneRatios["12-13"], 0.4)
        profile["uses_evaluation_sequence"] = true
        XCTAssertThrowsError(try ExerciseMotionCalibrationProfile.load(JSONSerialization.data(withJSONObject: profile)))
        profile["uses_evaluation_sequence"] = false
        profile["source_type"] = "mocap_ground_truth"
        XCTAssertThrowsError(try ExerciseMotionCalibrationProfile.load(JSONSerialization.data(withJSONObject: profile)))
    }

    func testExistingAppCalibrationMapsAnatomicalSidesAndRejectsAmbiguousInputs() throws {
        var bone: [String: Any] = [
            "unit": "cm", "skeleton": "h36m17", "pose": "rest",
            "segments": [
                "right_hip-right_knee": 40, "right_knee-right_ankle": 40,
                "left_hip-left_knee": 50, "left_knee-left_ankle": 50,
                "left_shoulder-left_elbow": 27, "left_elbow-left_wrist": 18,
                "right_shoulder-right_elbow": 36, "right_elbow-right_wrist": 27,
                "thorax-left_shoulder": 20, "pelvis-left_hip": 12,
            ],
            "appDefinitionDiffers": ["thorax-left_shoulder"],
        ]
        var calibration: [String: Any] = [
            "schemaVersion": 1, "stub": false, "bodyModel": "smpl_neutral_v1.1.0",
            "smplBeta": Array(repeating: 0.0, count: 10), "boneLengthData": bone,
        ]
        var envelope: [String: Any] = [
            "source_type": "rgb_smpl_calibration", "source_id": "actual-result",
            "ground_truth_used": false, "uses_evaluation_sequence": false,
            "calibration_confidence": 0.6, "calibration_result": calibration,
        ]
        func load() throws -> ExerciseMotionCalibrationProfile {
            try ExerciseMotionCalibrationProfile.load(JSONSerialization.data(withJSONObject: envelope))
        }
        let profile = try load()
        XCTAssertEqual(profile.boneRatios.count, 8)
        XCTAssertEqual(profile.boneRatios["11-12"]!, 0.3, accuracy: 1e-12)
        XCTAssertEqual(profile.boneRatios["12-13"]!, 0.2, accuracy: 1e-12)
        XCTAssertEqual(profile.boneRatios["14-15"]!, 0.4, accuracy: 1e-12)
        XCTAssertEqual(profile.boneRatios["15-16"]!, 0.3, accuracy: 1e-12)
        XCTAssertNil(profile.boneRatios["0-4"])
        XCTAssertNil(profile.provenance["calibration_result"], "do not log beta/body data as provenance")
        envelope.removeValue(forKey: "calibration_confidence")
        XCTAssertThrowsError(try load(), "pixel residuals cannot supply an invented reliability")
        envelope["calibration_confidence"] = 0.6
        envelope.removeValue(forKey: "ground_truth_used")
        XCTAssertThrowsError(try load(), "an absent GT declaration is not proof of estimated provenance")
        envelope["ground_truth_used"] = false
        bone["unit"] = "m"
        calibration["boneLengthData"] = bone
        envelope["calibration_result"] = calibration
        XCTAssertThrowsError(try load())
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
