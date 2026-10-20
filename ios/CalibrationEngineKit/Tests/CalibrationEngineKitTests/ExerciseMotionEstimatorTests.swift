import XCTest
#if canImport(CalibrationEngineKit)
@testable import CalibrationEngineKit
#endif

final class ExerciseMotionEstimatorTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testPythonNumericalAndStateParity() throws {
        let result = try ExerciseMotionParity.verify(Self.root.appendingPathComponent("tests/fixtures/exercise_motion_cases.json"))
        XCTAssertEqual(result.checked, 630)
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

    private func firstFixturePose() throws -> ([SIMD3<Double>], [SIMD3<Double>]) {
        let url = Self.root.appendingPathComponent("tests/fixtures/exercise_motion_cases.json")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let sequence = (root["cases"] as! [[String: Any]])[0]
        let frame = (sequence["frames"] as! [[String: Any]])[0]
        return ((frame["raw"] as! [[Double]]).map { SIMD3($0) },
                (frame["screen2d"] as! [[Double]]).map { SIMD3($0[0], $0[1], 0.95) })
    }

    func testUnobservedLegCannotCertifyAnotherJointsOutlier() throws {
        let (pose, screen) = try firstFixturePose()
        for variant in [ExerciseMotionVariant.G, .H] {
            for corruptLeg in [false, true] {
                var estimator = ExerciseMotionEstimator(exercise: "pushup", variant: variant)
                for t in 0..<10 { _ = estimator.update(raw: pose, screen2D: screen, timestamp: Double(t) / 30) }
                var jumped = pose, uncertain = screen
                jumped[13].x += 1
                if corruptLeg {
                    jumped[3] = [0, 100, 0]
                    uncertain[3].z = 0
                }
                let result = estimator.update(raw: jumped, screen2D: uncertain, timestamp: 10.0 / 30)
                XCTAssertTrue((result.diagnostics["rejected_joints"] as! [Int]).contains(13))
                XCTAssertFalse((result.diagnostics["observation_passthrough"] as! [Int]).contains(13))
                XCTAssertTrue(result.invalidForAssessment.contains(13))
                XCTAssertLessThan(result.diagnostics["scale"] as! Double, 1)
            }
        }
    }

    func testContactCandidatesExpireAcrossLongMissingIntervals() throws {
        let (pose, screen) = try firstFixturePose()
        var initial = ExerciseMotionEstimator(exercise: "pushup", variant: .F)
        for t in 0..<7 {
            _ = initial.update(raw: pose, screen2D: screen, timestamp: Double(t) / 30, fixedCamera: true)
        }
        var missing = screen
        missing[13].z = 0
        for t in 7..<68 {
            _ = initial.update(raw: pose, screen2D: missing, timestamp: Double(t) / 30, fixedCamera: true)
        }
        let recovered = initial.update(raw: pose, screen2D: screen, timestamp: 68.0 / 30, fixedCamera: true)
        XCTAssertEqual(recovered.contacts[13], "UNINITIALIZED")

        var relocation = ExerciseMotionEstimator(exercise: "pushup", variant: .F)
        for t in 0..<8 {
            _ = relocation.update(raw: pose, screen2D: screen, timestamp: Double(t) / 30, fixedCamera: true)
        }
        var moved = screen
        moved[13].x += 0.2
        var result: ExerciseMotionResult?
        for t in 8..<11 {
            result = relocation.update(raw: pose, screen2D: moved, timestamp: Double(t) / 30, fixedCamera: true)
        }
        XCTAssertEqual(result?.contacts[13], "MOVING")
        for t in 11..<15 {
            result = relocation.update(raw: pose, screen2D: moved, timestamp: Double(t) / 30, fixedCamera: true)
        }
        XCTAssertEqual(result?.contacts[13], "REACQUIRE")
        var hiddenMoved = moved
        hiddenMoved[13].z = 0
        for t in 15..<76 {
            _ = relocation.update(raw: pose, screen2D: hiddenMoved, timestamp: Double(t) / 30, fixedCamera: true)
        }
        result = relocation.update(raw: pose, screen2D: moved, timestamp: 76.0 / 30, fixedCamera: true)
        XCTAssertEqual(result?.contacts[13], "UNINITIALIZED")
    }

    func testFirstUnobservedFrameStaysInvalidWithFiniteUncertainty() throws {
        let (pose, screen) = try firstFixturePose()
        let missing = screen.map { SIMD3($0.x, $0.y, 0.0) }
        for raw in [pose, Array(repeating: SIMD3<Double>(repeating: .nan), count: 17)] {
            var estimator = ExerciseMotionEstimator(exercise: "barbell_row", variant: .H)
            let result = estimator.update(raw: raw, screen2D: missing, timestamp: 0)
            XCTAssertEqual(result.invalidForAssessment, Set(0..<17))
            XCTAssertTrue(result.uncertainty.allSatisfy(\.isFinite))
            XCTAssertEqual(result.phase, "unknown")
        }
    }
}
