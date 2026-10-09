import simd
import XCTest
@testable import CalibrationEngineKit

/// Same cases and expected outputs as tests/test_bone_lengths.py (Python reference).
final class BoneLengthConstraintTests: XCTestCase {
    private func loadFixture() throws -> [String: Any] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("tests/fixtures/bone_length_cases.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func vec(_ any: Any?) throws -> [SIMD3<Double>] {
        try XCTUnwrap(any as? [[Double]]).map { SIMD3($0[0], $0[1], $0[2]) }
    }

    func testApplyMatchesPythonFixture() throws {
        let cases = try XCTUnwrap(loadFixture()["apply"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for c in cases {
            let name = try XCTUnwrap(c["name"] as? String)
            let input = try vec(c["joints"])
            let config = BoneLengthConstraint.Config(
                enabled: try XCTUnwrap(c["enabled"] as? Bool),
                segments: Set(try XCTUnwrap(c["segments"] as? [String])),
                blend: try XCTUnwrap(c["blend"] as? Double))
            let targets = try XCTUnwrap(c["targets_cm"] as? [String: Double])
            let result = BoneLengthConstraint.apply(input, targetsCm: targets, config: config)

            let expected = try vec(c["expected_joints"])
            for i in 0..<17 {
                XCTAssertLessThan(simd_length(result.joints[i] - expected[i]), 1e-12, "\(name) joint \(i)")
            }
            let report = try XCTUnwrap(c["expected_report"] as? [String: Any])
            if let scale = report["scale"] as? Double {
                XCTAssertEqual(try XCTUnwrap(result.scale), scale, accuracy: 1e-12, name)
            } else {
                XCTAssertNil(result.scale, name)
                XCTAssertEqual(result.joints, input, "\(name): unconstrained input must come back unchanged")
            }
            let segments = try XCTUnwrap(report["segments"] as? [String: [String: Any]])
            XCTAssertEqual(Set(segments.keys), Set(result.segments.keys), name)
            for (seg, e) in segments {
                let r = try XCTUnwrap(result.segments[seg])
                XCTAssertEqual(r.observed, try XCTUnwrap(e["observed"] as? Double), accuracy: 1e-12, "\(name) \(seg)")
                XCTAssertEqual(r.output, try XCTUnwrap(e["output"] as? Double), accuracy: 1e-12, "\(name) \(seg)")
                XCTAssertEqual(r.targetCm, e["target_cm"] as? Double, "\(name) \(seg)")
                XCTAssertEqual(r.constrained, e["constrained"] as? Bool, "\(name) \(seg)")
                XCTAssertEqual(r.degenerate, e["degenerate"] as? Bool, "\(name) \(seg)")
            }
        }
    }

    func testLoaderMatchesPythonFixture() throws {
        let cases = try XCTUnwrap(loadFixture()["load"] as? [[String: Any]])
        for c in cases {
            let input = try JSONSerialization.data(withJSONObject: try XCTUnwrap(c["input"]))
            let expected = try XCTUnwrap(c["expected"] as? [String: Double])
            XCTAssertEqual(try BoneLengthConstraint.loadTargets(json: input), expected, c["name"] as? String ?? "")
        }
    }
}
