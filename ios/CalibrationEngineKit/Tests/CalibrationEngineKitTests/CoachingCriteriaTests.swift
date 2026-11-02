import Foundation
import XCTest
@testable import CalibrationEngineKit

final class CoachingCriteriaTests: XCTestCase {
    private func fixture() throws -> [[String: Any]] {
        let root = String(#filePath.components(separatedBy: "/ios/CalibrationEngineKit/Tests/")[0])
        let url = URL(fileURLWithPath: root).appendingPathComponent("scripts/coaching_criteria/fixtures/parity_v1.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(json["cases"] as? [[String: Any]])
    }
    private func compare(_ expected: Any, _ actual: Any, path: String) {
        if let a = expected as? [String: Any], let b = actual as? [String: Any] {
            XCTAssertEqual(Set(a.keys), Set(b.keys), path)
            for key in a.keys.sorted() { if let other = b[key] { compare(a[key]!, other, path: path + "." + key) } }
        } else if let a = expected as? [Any], let b = actual as? [Any] {
            XCTAssertEqual(a.count, b.count, path)
            for (i, pair) in zip(a, b).enumerated() { compare(pair.0, pair.1, path: path + "[\(i)]") }
        } else if let a = expected as? NSNumber, let b = actual as? NSNumber {
            XCTAssertEqual(CFGetTypeID(a) == CFBooleanGetTypeID(), CFGetTypeID(b) == CFBooleanGetTypeID(), path)
            XCTAssertEqual(a.doubleValue, b.doubleValue, accuracy: 1e-10, path)
        } else if let a = expected as? String {
            XCTAssertEqual(a, actual as? String, path)
        } else if expected is NSNull {
            XCTAssertTrue(actual is NSNull, path)
        } else {
            XCTFail("JSON type mismatch at " + path)
        }
    }
    func testCompletePythonSwiftParity() throws {
        let cases = try fixture()
        XCTAssertGreaterThanOrEqual(cases.count, 77)
        for (i, test) in cases.enumerated() {
            let result = try CoachingCriteria.evaluate(try XCTUnwrap(test["request"] as? [String: Any]))
            compare(test["expected"]!, result, path: "case[\(i)]")
        }
    }
    func testRejectsNonfiniteMalformedAndUnboundedRequests() throws {
        var request = try XCTUnwrap(try fixture().first?["request"] as? [String: Any])
        for value in [Double.nan, .infinity, -.infinity] {
            var r = request; r["extra"] = ["nested": value]
            XCTAssertThrowsError(try CoachingCriteria.evaluate(r))
        }
        request["observations"] = [1, 2]
        XCTAssertThrowsError(try CoachingCriteria.evaluate(request))
        request["observations"] = [:]
        var node: [String: Any] = ["type": "atom", "id": "a", "observation": "absent"]
        for i in 0..<18 { node = ["type": "group", "id": "g\(i)", "op": "OR", "children": [node]] }
        request["criterion"] = node
        XCTAssertThrowsError(try CoachingCriteria.evaluate(request))
        request["criterion"] = ["type": "group", "id": "g", "op": "AND", "children": (0..<128).map { ["type": "atom", "id": "a\($0)", "observation": "absent"] }]
        XCTAssertThrowsError(try CoachingCriteria.evaluate(request))
        request["criterion"] = ["type": "atom", "id": "a", "observation": "absent"]
        var nested: Any = 0
        for _ in 0..<66 { nested = [nested] }
        request["extra"] = nested
        XCTAssertThrowsError(try CoachingCriteria.evaluate(request))
    }
}
