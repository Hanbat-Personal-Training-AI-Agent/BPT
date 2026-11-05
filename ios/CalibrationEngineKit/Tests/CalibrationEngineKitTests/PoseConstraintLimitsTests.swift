import simd
import XCTest
@testable import CalibrationEngineKit

/// Pose3DConstraints defaults == pose_feedback/geometry/anatomical_limits.json (the one config), and the knee
/// hyperextension clamp leaves no backwards-bent knee in the output.
final class PoseConstraintLimitsTests: XCTestCase {
    private struct Limits: Decodable {
        struct Angle: Decodable {
            let name: String
            let ref_from: Int, ref_to: Int, joint: Int, child: Int
            let min_deg: Double, max_deg: Double
        }
        let angle_limits: [Angle]
        let knee_hyperextension_max_deg: Double
        let knee_flip_deg: Double
        let bad_angle_deg: Double
        let prior_lengths: [String: Double]
    }

    func testDefaultsMatchTheConfig() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("pose_feedback/geometry/anatomical_limits.json"))
        let want = try JSONDecoder().decode(Limits.self, from: data)
        let c = Pose3DConstraints()
        XCTAssertEqual(c.angleLimits.count, want.angle_limits.count)
        for (got, w) in zip(c.angleLimits, want.angle_limits) {
            XCTAssertEqual(got.name, w.name)
            XCTAssertEqual([got.refFrom, got.refTo, got.joint, got.child], [w.ref_from, w.ref_to, w.joint, w.child], w.name)
            XCTAssertEqual(got.minDegrees, w.min_deg, w.name)
            XCTAssertEqual(got.maxDegrees, w.max_deg, w.name)
        }
        XCTAssertEqual(c.kneeClampDegrees, want.knee_hyperextension_max_deg)
        XCTAssertEqual(c.knee.limitDegrees, want.knee_flip_deg)
        XCTAssertEqual(c.badAngleDegrees, want.bad_angle_deg)
        XCTAssertEqual(c.priorLengths, want.prior_lengths)
    }

    func testHyperextendedKneeIsClampedNotLeftBackwards() throws {
        var j = [SIMD3<Double>](repeating: .zero, count: 17)
        j[1] = SIMD3(-0.1, 0, 0); j[4] = SIMD3(0.1, 0, 0); j[8] = SIMD3(0, -0.5, 0); j[7] = j[8] / 2
        for (hip, knee, ankle) in [(1, 2, 3), (4, 5, 6)] {
            j[knee] = j[hip] + SIMD3(0, 0.45, 0)
            j[ankle] = j[knee] + SIMD3(0, 0.4, 0)
        }
        // Right shin bent 25° the wrong way (θ = −25°: past the clamp, short of the −30° flip detection).
        let a = 25.0 * .pi / 180
        j[3] = j[2] + 0.4 * SIMD3(0, cos(a), -sin(a))
        let before = try XCTUnwrap(KneeHingeLimit.kneeTheta(j, hip: 1, knee: 2, ankle: 3)).0
        XCTAssertLessThan(before, -15)
        var c = Pose3DConstraints()
        c.boneLengths = false
        let (out, report) = c.apply(j)
        let after = try XCTUnwrap(KneeHingeLimit.kneeTheta(out, hip: 1, knee: 2, ankle: 3)).0
        XCTAssertEqual(after, -15, accuracy: 1e-9)
        XCTAssertEqual(report.kneeClampDegrees, -15 - before, accuracy: 1e-9)
        XCTAssertEqual(simd_length(out[3] - out[2]), 0.4, accuracy: 1e-12, "shin length kept")
        XCTAssertTrue(report.invalidJoints.isEmpty, "−25° is clamped, not a depth flip")
        XCTAssertFalse(report.kneeHyperextended)
    }
}
