import Foundation
import XCTest
@testable import CalibrationEngineKit

final class CoachingCriteriaBridgeTests: XCTestCase {
    private let source: [String: Any] = ["frame": 7, "source_index": 9, "source_pts": 0.3, "source_time_value": 3, "source_time_scale": 10, "epoch": 2, "time_basis": "sample_pts_seconds"]
    private let context: [String: Any] = ["exercise": "pushup", "phase": "descending", "side": "left", "side_view": true, "source_kind": "video_frame", "flush_tail": false, "gravitySynchronized": false]
    func testCodableMetricsPreservedWithoutInventedTargetsOrSourceProof() throws {
        let output = ExperimentalCoaching.Output(time: 0.3, metrics: ["leftElbowDeg": .init(value: 100, rawValue: 99, reasons: [])], candidates: [])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(output)) as! [String: Any]
        let metrics = encoded["metrics"] as! [String: Any]
        let request = try CoachingCriteriaBridge.request(metrics: metrics, source: source, context: context)
        XCTAssertTrue((request["profiles"] as! [String: Any]).isEmpty)
        let observation = (request["observations"] as! [String: [String: Any]])["leftElbowDeg"]!
        XCTAssertEqual(observation["available"] as? Bool, true)
        let summary = try CoachingCriteriaBridge.summary(metrics: metrics, source: source, context: context)
        let metric = (summary["metrics"] as! [String: [String: Any]])["leftElbowDeg"]!
        XCTAssertEqual(metric["state"] as? String, "unknown")
        XCTAssertEqual(metric["available"] as? Bool, true)
        XCTAssertEqual(metric["value"] as? Double, 100)
        XCTAssertTrue((metric["criterionReasons"] as! [String]).contains("profile_required"))
        XCTAssertTrue((metric["criterionReasons"] as! [String]).contains("complete_source_identity_required"))
        XCTAssertTrue((summary["unsuppliedCatalogMetrics"] as! [String]).contains("cameraTorsoSignedDeg"))
        XCTAssertTrue(NSDictionary(dictionary: summary["source"] as! [String: Any]).isEqual(to: source))
        XCTAssertLessThan(try JSONSerialization.data(withJSONObject: summary).count, 32768)
    }
    func testFlushUnknownViewAndUnmappedMetricNeverBecomePositive() throws {
        let metrics: [String: Any] = ["leftElbowDeg": ["value": 100, "rawValue": 99, "available": true, "reasons": []], "cameraTorsoSignedDeg": ["value": 0, "rawValue": 0, "available": true, "reasons": []]]
        var context = self.context; context["flush_tail"] = true; context["side_view"] = 0
        let summary = try CoachingCriteriaBridge.summary(metrics: metrics, source: source, context: context)
        XCTAssertEqual(summary["state"] as? String, "unknown")
        let results = summary["metrics"] as! [String: [String: Any]]
        XCTAssertTrue((results["leftElbowDeg"]!["criterionReasons"] as! [String]).contains("flush_sample_not_observation"))
        XCTAssertTrue((results["leftElbowDeg"]!["criterionReasons"] as! [String]).contains("unknown_observation_context"))
        XCTAssertEqual(summary["unmappedMetrics"] as? [String], ["cameraTorsoSignedDeg"])
    }
    func testAnatomicalSideDistinctFromSelectedSideAndNotSideIsUnknown() throws {
        var c = context; c["side_view"] = false
        let request = try CoachingCriteriaBridge.request(metrics: ["rightElbowDeg": ["value": 90, "rawValue": 90, "reasons": []]], source: source, context: c)
        let observation = (request["observations"] as! [String: [String: Any]])["rightElbowDeg"]!
        let scope = observation["scope"] as! [String: Any]
        XCTAssertEqual(scope["side"] as? String, "right")
        XCTAssertEqual(scope["selectedSide"] as? String, "left")
        XCTAssertEqual(scope["view"] as? String, "unknown")
        XCTAssertEqual((observation["samples"] as! [[String: Any]])[0]["side"] as? String, "right")
    }
    func testExplicitFailureAndStrictFlushType() throws {
        let failure = CoachingCriteriaBridge.failure(source: source, context: context, reason: "observation_encoding_failed")
        XCTAssertEqual(failure["status"] as? String, "withheld_error")
        XCTAssertEqual(failure["errorReason"] as? String, "observation_encoding_failed")
        XCTAssertTrue((failure["metrics"] as! [String: Any]).isEmpty)
        XCTAssertEqual((failure["unsuppliedCatalogMetrics"] as! [String]).count, 11)
        let malformed: [Any] = ["true", 1, NSNull()]
        for flag in malformed {
            var c = context; c["flush_tail"] = flag
            XCTAssertThrowsError(try CoachingCriteriaBridge.request(metrics: ["leftElbowDeg": ["value": 90, "reasons": []]], source: source, context: c))
        }
    }
    func testBridgeRejectsUnboundedMalformedAndNonfinitePayloads() throws {
        XCTAssertThrowsError(try CoachingCriteriaBridge.summary(metrics: [:], source: source, context: context))
        XCTAssertThrowsError(try CoachingCriteriaBridge.summary(metrics: ["bad": 1], source: source, context: context))
        let reasons = [String(repeating: "x", count: 129)]
        XCTAssertThrowsError(try CoachingCriteriaBridge.summary(metrics: ["leftElbowDeg": ["value": 1, "reasons": reasons]], source: source, context: context))
        XCTAssertThrowsError(try CoachingCriteriaBridge.summary(metrics: ["leftElbowDeg": ["value": Double.infinity, "reasons": []]], source: source, context: context))
    }
}
