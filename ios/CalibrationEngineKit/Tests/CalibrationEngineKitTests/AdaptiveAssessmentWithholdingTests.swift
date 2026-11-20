import simd
import XCTest
@testable import CalibrationEngineKit

/// Synthetic consumer-boundary checks, not form-accuracy or model-inference tests.
final class AdaptiveAssessmentWithholdingTests: XCTestCase {
    private func keypoints(frame: Int) -> [PoseKeypoint] {
        return (0..<17).map { joint -> PoseKeypoint in
            let x = 300.0 + Double(joint) * 5.0
            let y = 200.0 + Double(joint) * 40.0
            let lost = joint == 15 && (40..<50).contains(frame)
            let confidence: Double = lost ? 0.1 : (joint % 2 == 1 ? 0.95 : 0.6)
            return PoseKeypoint(x: x, y: y, confidence: confidence)
        }
    }

    private func frames(adaptive: Bool) throws -> [Lifted3DFrame] {
        var live = MotionAGFormerLive<Int>(lookahead: 5, cadence: 1, predict: { input in
            var output: [Float] = []
            for t in 0..<27 {
                var pose = AdaptiveRelationConstraintTests.standing()
                // A synthetic wrong XS ankle while its original 2D observation is lost.
                if input[(t * 17 + 6) * 3 + 2] < 0.3 { pose[6].x = 0.8 }
                output += pose.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
            }
            return output
        })
        live.constraints.enabled = false  // Isolate the independent adaptive consumer boundary.
        if adaptive { live.adaptive = AdaptiveRelationConstraint(exercise: .squat) }
        var result: [Lifted3DFrame] = []
        for frame in 0..<70 {
            result += try live.push(frameIndex: frame, coco17: keypoints(frame: frame),
                                    imageWidth: 720, imageHeight: 1280, payload: frame).map(\.1)
        }
        return result + (try live.flush().map(\.1))
    }

    private func report(_ frame: Lifted3DFrame) -> FormRepReport {
        let tracker = FormWarningTracker(exercise: .squat)
        tracker.common.form3DRequired = true
        tracker.observe(frameIndex: frame.frameIndex, coco17: keypoints(frame: frame.frameIndex),
                        pose3D: frame.masked3D, pose3DState: frame.state, phase: "top")
        tracker.beginRep()
        return tracker.finishRep(repIndex: 1)
    }

    func testFilledAnkleCannotBecomeDefinitiveKneeMetric() throws {
        let frame = try XCTUnwrap(frames(adaptive: true).first { $0.adaptive?.filled[6] != nil })
        XCTAssertNotEqual(frame.adapted?[6], frame.pose3D?[6], "synthetic fill really changed the lost joint")
        XCTAssertTrue(frame.invalidJoints.contains(6), "inferred ankle needs an immediate assessment veto")
        XCTAssertTrue(try XCTUnwrap(frame.masked3D)[6].x.isNaN)
        XCTAssertEqual(frame.state, .partial3D)
        let judged = report(frame)
        XCTAssertNil(judged.metrics3D["knee_min"], "an inferred ankle must not become an observed knee metric")
        XCTAssertNotNil(judged.metrics3D["hip_angle_max"], "observed independent joints remain assessable")
        XCTAssertFalse(judged.deliveryDecisionEvidence?.deliveryAssessedKeys3D?.contains("squat_no_lockout") ?? true)
        XCTAssertNotEqual(judged.spoken, "praise_good")
    }

    func testReacquiredReliableJointIsImmediatelyAssessableAgain() throws {
        let all = try frames(adaptive: true)
        let inferred = try XCTUnwrap(all.first { $0.adaptive?.filled[6] != nil })
        let reacquired = try XCTUnwrap(all.first {
            $0.frameIndex >= 50 && $0.adapted != nil && $0.adaptive?.filled[6] == nil
        })
        XCTAssertLessThan(inferred.frameIndex, reacquired.frameIndex)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(reacquired.confidence?[6]), 0.5)
        XCTAssertFalse(reacquired.invalidJoints.contains(6))
        XCTAssertEqual(reacquired.state, .ok)
        XCTAssertEqual(reacquired.masked3D?[6], reacquired.pose3D?[6])
        XCTAssertNotNil(report(reacquired).metrics3D["knee_min"])
    }

    func testRawConstrainedAndObservedJointsStayUnchanged() throws {
        let baseline = try frames(adaptive: false), adapted = try frames(adaptive: true)
        XCTAssertEqual(baseline.map(\.frameIndex), adapted.map(\.frameIndex))
        for (before, after) in zip(baseline, adapted) {
            XCTAssertEqual(before.raw, after.raw)
            XCTAssertEqual(before.pose3D, after.pose3D)
            XCTAssertEqual(after.adapted?[4], after.pose3D?[4], "observed hip is never estimated")
            if after.adaptive?.filled.isEmpty != false {
                XCTAssertEqual(before.state, after.state)
                XCTAssertEqual(before.masked3D, after.masked3D)
            }
        }
    }

    func testPartialStateReachesBridgeAndKeepsOtherMetricsAvailable() throws {
        let frame = try XCTUnwrap(frames(adaptive: true).first { $0.adaptive?.filled[6] != nil })
        let payload = Pose3DBridge.payload(frame)
        XCTAssertEqual(payload["state"] as? String, "partial_3d")
        XCTAssertEqual(payload["usable"] as? Bool, true, "independent observed metrics remain usable")
        XCTAssertTrue((payload["occluded"] as? [Int] ?? []).contains(6))
        XCTAssertTrue(try XCTUnwrap(frame.usable3D)[6].x.isNaN)
        XCTAssertTrue(try XCTUnwrap(frame.usable3D)[4].x.isFinite)
        XCTAssertNotNil(report(frame).metrics3D["hip_angle_max"])
    }

    func testFillIsWithheldEvenWhenEstimateEqualsRawAndSigmaIsZero() throws {
        let pose = AdaptiveRelationConstraintTests.standing()
        var evidence = AdaptiveRelationConstraint.Report()
        evidence.filled[6] = .init(w: 0, sigma: 0, gap: 1)
        evidence.invalid = [3]
        let frame = Lifted3DFrame(frameIndex: 1, state: .partial3D, filled: 27,
                                 raw: pose, pose3D: pose, constraints: nil, row: 21,
                                 adapted: pose, adaptive: evidence)
        XCTAssertEqual(frame.adapted, pose)
        XCTAssertEqual(frame.invalidJoints, [3, 6])
        XCTAssertTrue(try XCTUnwrap(frame.masked3D)[3].x.isNaN)
        XCTAssertTrue(try XCTUnwrap(frame.masked3D)[6].x.isNaN)
        XCTAssertEqual(frame.masked3D?[4], pose[4])
    }

}
