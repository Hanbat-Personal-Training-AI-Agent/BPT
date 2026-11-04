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
}
