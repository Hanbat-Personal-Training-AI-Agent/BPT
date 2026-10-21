import XCTest
@testable import CalibrationEngineKit

final class ExerciseMotionLiveTests: XCTestCase {
    private let pose: [SIMD3<Double>] = [
        [0,0,0], [0.08,0.02,0], [0.10,0.25,0.01], [0.12,0.48,0], [-0.08,0.02,0],
        [-0.10,0.25,0.01], [-0.12,0.48,0], [0,-0.2,0], [0,-0.4,0], [0,-0.45,0], [0,-0.52,0],
        [-0.20,-0.36,0], [-0.35,-0.15,0], [-0.45,0.05,0], [0.20,-0.36,0], [0.35,-0.15,0], [0.45,0.05,0],
    ]
    private var person: [PoseKeypoint] {
        let xy: [(Double, Double)] = [
            (360,200),(345,180),(375,180),(330,200),(390,200),(280,300),(440,300),
            (240,440),(480,440),(220,580),(500,580),(310,550),(410,550),(300,750),(420,750),(290,950),(430,950),
        ]
        return xy.map { PoseKeypoint(x: $0.0, y: $0.1, confidence: 0.95) }
    }
    private func live(_ variant: ExerciseMotionVariant? = nil) -> MotionAGFormerLive<Int> {
        let row = pose.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        var live = MotionAGFormerLive<Int>(predict: { _ in Array(repeating: row, count: 27).flatMap { $0 } })
        live.constraints.enabled = false
        if let variant { live.motionEstimator = ExerciseMotionEstimator(exercise: "squat", variant: variant) }
        return live
    }

    func testRawAndMatchedFrameSurviveEstimatorBoundary() throws {
        var baseline = live(), experimental = live(.A)
        var a: [Lifted3DFrame] = [], b: [Lifted3DFrame] = []
        for i in 0..<40 {
            a += try baseline.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280, payload: i).map(\.1)
            b += try experimental.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280,
                                      motionContext: .init(timestamp: Double(i) * 0.04), payload: i).map(\.1)
        }
        a += try baseline.flush().map(\.1)
        b += try experimental.flush().map(\.1)
        XCTAssertEqual(a.map(\.frameIndex), b.map(\.frameIndex))
        for (plain, motion) in zip(a, b) {
            XCTAssertEqual(plain.raw, motion.raw, "the XS output must remain exact")
            guard let report = motion.motion else { continue }
            XCTAssertEqual(report.diagnostics["timestamp"] as? Double, Double(motion.frameIndex) * 0.04)
            for (p, q) in zip(plain.pose3D!, motion.pose3D!) {
                XCTAssertEqual(p.x, q.x, accuracy: 1e-12)
                XCTAssertEqual(p.y, q.y, accuracy: 1e-12)
                XCTAssertEqual(p.z, q.z, accuracy: 1e-12)
            }
        }
    }

    func testOnlineProfileAppliesAtRow81AndResetsOnPersonChange() throws {
        var live = live(.E)
        live.motionOnlineCalibration = true
        var outputs: [Lifted3DFrame] = []
        for i in 0..<95 {
            outputs += try live.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280,
                                     motionContext: .init(timestamp: Double(i) / 30, personID: "one"), payload: i).map(\.1)
        }
        let before = outputs.first { $0.frameIndex == 80 }!.motion!
        let after = outputs.first { $0.frameIndex == 81 }!.motion!
        XCTAssertEqual(before.diagnostics["online_calibration_frames"] as? Int, 60)
        XCTAssertEqual(before.diagnostics["online_calibration_applied"] as? Bool, false)
        XCTAssertEqual(after.diagnostics["online_calibration_applied"] as? Bool, true)
        XCTAssertEqual(after.diagnostics["calibration_used"] as? Bool, true)
        var next: [Lifted3DFrame] = []
        for i in 95..<130 {
            next += try live.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280,
                                  motionContext: .init(timestamp: Double(i) / 30, personID: "two"), payload: i).map(\.1)
        }
        let firstNew = next.first { $0.frameIndex >= 95 && $0.motion != nil }!
        XCTAssertEqual(firstNew.frameIndex, 116)
        XCTAssertEqual(firstNew.motion!.diagnostics["online_calibration_applied"] as? Bool, false)
        XCTAssertEqual(firstNew.motion!.diagnostics["calibration_used"] as? Bool, false)
    }

    func testTrustedObservationsPassThroughExactlyAcrossChangingCrop() throws {
        for variant in [ExerciseMotionVariant.G, .H] {
            var pipeline = live(variant)
            var checked = 0
            for i in 0..<45 {
                // Non-binary normalization factors change, exercising both image and XS units.
                let scale = 1 + Double(i) * 0.0013
                let moving = person.map { PoseKeypoint(x: $0.x * scale, y: $0.y * scale, confidence: $0.confidence) }
                let frames = try pipeline.push(frameIndex: i, coco17: moving, imageWidth: 720,
                                               imageHeight: 1280, payload: i)
                for (_, frame) in frames {
                    guard let raw = frame.raw, let result = frame.motion else { continue }
                    let joints = result.diagnostics["observation_passthrough"] as! [Int]
                    XCTAssertEqual(joints.count, 17)
                    for j in joints {
                        XCTAssertEqual(result.corrected[j], raw[j], "no floating-point roundtrip drift")
                        XCTAssertEqual(result.correctionMagnitude[j], 0)
                        XCTAssertEqual(frame.pose3D![j], raw[j])
                    }
                    checked += 1
                }
            }
            XCTAssertGreaterThan(checked, 0)
        }
    }

    func testDeliveredProfileReplacesOnlineOwnershipAndClearsOnIdentityReset() throws {
        var pipeline = live(.H)
        pipeline.motionOnlineCalibration = true
        for i in 0..<95 {
            _ = try pipeline.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280, payload: i)
        }
        let profile = ExerciseMotionCalibrationProfile(boneRatios: ["12-13": 0.3],
                                                       confidence: 0.6, provenance: ["source_id": "independent"])
        XCTAssertTrue(pipeline.applyMotionCalibration(profile))
        pipeline.reset(reason: "set_boundary")
        XCTAssertEqual(pipeline.motionEstimator?.boneProfile, ["12-13": 0.3])
        pipeline.reset(reason: "person_change")
        XCTAssertTrue(pipeline.motionEstimator!.boneProfile.isEmpty)
    }

    func testTrustedTorsoAndKneeRemainObservedWhileLegacyGatesStayInvalid() throws {
        var observed = pose
        observed[3] = [0.09, 0.03, 0.01]  // Deeply flexed observed knee, below the legacy angle limit.
        observed[8] = [0.05, -0.05, 0]   // Bent observed torso, below the legacy spine limit.
        let row = observed.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        for variant in [ExerciseMotionVariant.G, .H] {
            var pipeline = MotionAGFormerLive<Int>(predict: { _ in Array(repeating: row, count: 27).flatMap { $0 } })
            pipeline.motionEstimator = ExerciseMotionEstimator(exercise: "squat", variant: variant)
            pipeline.constraints.boneLengths = false
            pipeline.constraints.kneeClampDegrees = nil
            pipeline.constraints.angleLimits = Pose3DConstraints.defaultAngleLimits.filter {
                ["right_knee_flexion", "spine"].contains($0.name)
            }
            var checked = 0
            for i in 0..<35 {
                for (_, frame) in try pipeline.push(frameIndex: i, coco17: person, imageWidth: 720,
                                                    imageHeight: 1280, payload: i) {
                    guard let raw = frame.raw, let result = frame.motion else { continue }
                    XCTAssertEqual(frame.pose3D!, raw, "legacy proposals must not hide trusted observed posture")
                    XCTAssertTrue(frame.constraints!.invalidJoints.isSuperset(of: [3, 8]))
                    XCTAssertTrue(frame.invalidForAssessment.isSuperset(of: [3, 8]))
                    XCTAssertTrue(frame.masked3D![3].x.isNaN)
                    XCTAssertTrue(frame.masked3D![8].x.isNaN)
                    let restored = result.diagnostics["legacy_constraint_restored_joints"] as! [Int]
                    XCTAssertTrue(restored.contains(3))
                    XCTAssertTrue(restored.contains(8))
                    XCTAssertGreaterThan(frame.constraints!.maxAngleCorrection, 20)
                    checked += 1
                }
            }
            XCTAssertGreaterThan(checked, 0)
        }
    }

    func testChangingModelRootOffsetDoesNotChangeUncertainRelativeMotion() throws {
        // Binary-representable coordinates isolate coordinate-basis correctness from Float
        // quantization. Real XS residual root offsets can be much larger than roundoff.
        let base = pose.map { p in SIMD3<Double>((p.x * 64).rounded() / 64,
                                                 (p.y * 64).rounded() / 64,
                                                 (p.z * 64).rounded() / 64) }
        func make(shifted: Bool) -> MotionAGFormerLive<Int> {
            var selected = 21
            var pipeline = MotionAGFormerLive<Int>(predict: { _ in
                let offset = shifted ? SIMD3<Double>(Double(selected % 7) / 32,
                                                     Double(selected % 5) / 64,
                                                     -Double(selected % 11) / 32) : .zero
                selected += 1
                let row = base.flatMap { p in [Float(p.x + offset.x), Float(p.y + offset.y), Float(p.z + offset.z)] }
                return Array(repeating: row, count: 27).flatMap { $0 }
            })
            pipeline.constraints.enabled = false
            pipeline.motionEstimator = ExerciseMotionEstimator(exercise: "barbell_row", variant: .H)
            return pipeline
        }
        var centered = make(shifted: false), shifted = make(shifted: true)
        var uncertainChecked = 0
        for i in 0..<50 {
            var observed = person
            if (30..<38).contains(i) {
                observed[9] = PoseKeypoint(x: observed[9].x, y: observed[9].y, confidence: 0.05)
            }
            let plain = try centered.push(frameIndex: i, coco17: observed, imageWidth: 720,
                                          imageHeight: 1280, payload: i).map(\.1)
            let translated = try shifted.push(frameIndex: i, coco17: observed, imageWidth: 720,
                                               imageHeight: 1280, payload: i).map(\.1)
            XCTAssertEqual(plain.map(\.frameIndex), translated.map(\.frameIndex))
            for (a, b) in zip(plain, translated) {
                guard let expected = a.motion, let result = b.motion, let raw = b.raw else { continue }
                let offset = raw[0]
                XCTAssertEqual(result.raw, raw)
                XCTAssertEqual(result.invalidForAssessment, expected.invalidForAssessment)
                XCTAssertEqual(result.usedPrediction, expected.usedPrediction)
                for j in 0..<17 {
                    let relative = result.corrected[j] - offset
                    XCTAssertEqual(relative.x, expected.corrected[j].x, accuracy: 1e-12)
                    XCTAssertEqual(relative.y, expected.corrected[j].y, accuracy: 1e-12)
                    XCTAssertEqual(relative.z, expected.corrected[j].z, accuracy: 1e-12)
                    XCTAssertEqual(result.correctionMagnitude[j], expected.correctionMagnitude[j], accuracy: 1e-12)
                }
                XCTAssertNotNil(result.diagnostics["original_model_root_offset"])
                if result.invalidForAssessment.contains(13) { uncertainChecked += 1 }
            }
        }
        XCTAssertGreaterThan(uncertainChecked, 0, "compare actual low-confidence wrist predictions")
    }

    func testExpiredFallbackRemainsExactRawAndInvalidAfterLegacyConstraints() throws {
        for variant in [ExerciseMotionVariant.G, .H] {
            var selected = 21
            let base = pose
            var pipeline = MotionAGFormerLive<Int>(predict: { _ in
                var raw = base
                if selected >= 40 { raw[3] = [0.09, 0.03, 0.01] }
                selected += 1
                let root = SIMD3<Double>(0.17, -0.11, 0.09)
                let row = raw.flatMap { p in [Float(p.x + root.x), Float(p.y + root.y), Float(p.z + root.z)] }
                return Array(repeating: row, count: 27).flatMap { $0 }
            })
            pipeline.motionEstimator = ExerciseMotionEstimator(exercise: "squat", variant: variant)
            pipeline.constraints.boneLengths = false
            pipeline.constraints.kneeClampDegrees = nil
            pipeline.constraints.angleLimits = Pose3DConstraints.defaultAngleLimits.filter { $0.name == "right_knee_flexion" }
            var checked = 0
            for i in 0..<90 {
                var observed = person
                if i >= 40 { observed[16] = PoseKeypoint(x: observed[16].x, y: observed[16].y, confidence: 0.05) }
                let frames = try pipeline.push(frameIndex: i, coco17: observed, imageWidth: 720,
                    imageHeight: 1280, motionContext: .init(timestamp: Double(i) / 30), payload: i)
                for (_, frame) in frames {
                    guard let raw = frame.raw, let result = frame.motion,
                          (result.diagnostics["expired_prediction_fallback"] as! [Int]).contains(3) else { continue }
                    XCTAssertEqual(result.corrected[3], raw[3], "fallback must avoid conversion roundoff")
                    XCTAssertEqual(frame.pose3D![3], raw[3], "legacy correction must not normalize an expired joint")
                    XCTAssertEqual(result.correctionMagnitude[3], 0)
                    XCTAssertTrue(result.usedPrediction[3])
                    XCTAssertEqual(result.roles[3], "uncertain_joint")
                    XCTAssertFalse((result.diagnostics["observation_passthrough"] as! [Int]).contains(3))
                    XCTAssertTrue(frame.invalidForAssessment.contains(3))
                    XCTAssertTrue(frame.constraints!.invalidJoints.contains(3), "keep the legacy proposal gate too")
                    XCTAssertTrue(frame.masked3D![3].x.isNaN)
                    XCTAssertTrue((result.diagnostics["legacy_constraint_restored_expired_joints"] as! [Int]).contains(3))
                    checked += 1
                }
            }
            XCTAssertGreaterThan(checked, 0, "exercise actual expiry and a legacy proposal")
        }
    }

    func testExistingGateAndEstimatorInvalidationAreBothPreserved() {
        var report = Pose3DConstraints.Report()
        report.invalidJoints = [2]
        let motion = ExerciseMotionResult(raw: pose, corrected: pose,
                                         correctionMagnitude: Array(repeating: 0, count: 17),
                                         uncertainty: Array(repeating: 0, count: 17),
                                         invalidForAssessment: [13], roles: [], contacts: [:],
                                         usedPrediction: [], phase: nil, diagnostics: [:])
        let frame = Lifted3DFrame(frameIndex: 0, state: .partial3D, filled: 27, raw: pose,
                                  pose3D: pose, constraints: report, row: 21, motion: motion)
        XCTAssertEqual(frame.invalidForAssessment, [2, 13])
        XCTAssertEqual(frame.constraints?.invalidJoints, [2], "preserve the original constraint report")
        XCTAssertTrue(frame.masked3D![2].x.isNaN)
        XCTAssertTrue(frame.masked3D![13].x.isNaN)
        XCTAssertEqual(frame.masked3D![3], pose[3])
    }

    func testGateOnlyBonesDoNotProjectPoseTwice() {
        var constraints = Pose3DConstraints()
        constraints.angleLimits = []
        constraints.kneeClampDegrees = nil
        constraints.knee = .init(enabled: false, limitDegrees: 180)
        constraints.badBoneFraction = 0.01
        let (got, report) = constraints.apply(pose, projectBoneLengths: false)
        XCTAssertEqual(got, pose)
        XCTAssertGreaterThan(report.boneMaxCorrection, 0.01)
        XCTAssertEqual(report.invalidJoints.count, 17, "the existing bone gate remains active")
    }
}
