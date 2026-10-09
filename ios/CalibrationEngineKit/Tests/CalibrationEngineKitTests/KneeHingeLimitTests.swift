import simd
import XCTest
@testable import CalibrationEngineKit

/// Same cases and expected outputs as tests/test_hinge_limit.py (Python reference).
final class KneeHingeLimitTests: XCTestCase {
    private struct Case: Decodable {
        struct Leg: Decodable {
            let theta_deg: Double?
            let corrected: Bool
            let correction_deg: Double
            let degenerate: Bool
        }
        let name: String
        let limit_deg: Double
        let enabled: Bool
        let joints: [[Double]]
        let expected_joints: [[Double]]
        let expected_report: [String: Leg]
    }

    private func loadCases() throws -> [Case] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("tests/fixtures/knee_hinge_limit_cases.json"))
        return try JSONDecoder().decode([Case].self, from: data)
    }

    private func vec(_ rows: [[Double]]) -> [SIMD3<Double>] { rows.map { SIMD3($0[0], $0[1], $0[2]) } }

    func testMatchesPythonFixture() throws {
        let cases = try loadCases()
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for c in cases {
            let input = vec(c.joints)
            let result = KneeHingeLimit.apply(input, config: .init(enabled: c.enabled, limitDegrees: c.limit_deg))
            let expected = vec(c.expected_joints)
            for i in 0..<17 {
                XCTAssertLessThan(simd_length(result.joints[i] - expected[i]), 1e-12, "\(c.name) joint \(i)")
            }
            for (leg, report) in [("right", result.right), ("left", result.left)] {
                let e = try XCTUnwrap(c.expected_report[leg])
                XCTAssertEqual(report.corrected, e.corrected, "\(c.name) \(leg)")
                XCTAssertEqual(report.degenerate, e.degenerate, "\(c.name) \(leg)")
                XCTAssertEqual(report.correctionDegrees, e.correction_deg, accuracy: 1e-9, "\(c.name) \(leg)")
                if let theta = e.theta_deg {
                    XCTAssertEqual(try XCTUnwrap(report.thetaDegrees), theta, accuracy: 1e-9, "\(c.name) \(leg)")
                } else {
                    XCTAssertNil(report.thetaDegrees, "\(c.name) \(leg)")
                }
            }
            if !result.right.corrected && !result.left.corrected {
                XCTAssertEqual(result.joints, input, "\(c.name): in-range input must come back unchanged")
            }
            for (leg, report, idx) in [("right", result.right, (1, 2, 3)), ("left", result.left, (4, 5, 6))] where report.corrected {
                let (theta, _) = try XCTUnwrap(KneeHingeLimit.kneeTheta(result.joints, hip: idx.0, knee: idx.1, ankle: idx.2))
                XCTAssertEqual(theta, -c.limit_deg, accuracy: 1e-4, "\(c.name) \(leg)")
                XCTAssertEqual(simd_length(result.joints[idx.2] - result.joints[idx.1]),
                               simd_length(input[idx.2] - input[idx.1]), accuracy: 1e-12)
            }
        }
    }
}
