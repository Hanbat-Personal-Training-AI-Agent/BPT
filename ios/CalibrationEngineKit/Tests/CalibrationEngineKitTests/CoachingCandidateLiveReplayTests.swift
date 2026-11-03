import Foundation
import CryptoKit
import XCTest
@testable import CalibrationEngineKit

/// Optional original-capture integration proof. No model, media decoder or UI is invoked.
final class CoachingCandidateLiveReplayTests: XCTestCase {
    func testOriginalCapturesThroughLiveProcessorAgainstFrozenV3() throws {
        let env = ProcessInfo.processInfo.environment
        guard let captureRoot = env["BPT_CANDIDATE_CAPTURE_ROOT"], let frozenRoot = env["BPT_CANDIDATE_FROZEN_ROOT"] else {
            throw XCTSkip("Set BPT_CANDIDATE_CAPTURE_ROOT and BPT_CANDIDATE_FROZEN_ROOT for retained-capture replay")
        }
        typealias JSON = [String: Any]
        func read(_ path: String) throws -> JSON { try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! JSON }
        func canonical(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
        func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let experiment = try read(frozenRoot + "/experiment-declared.json")
        let frozen = try read(frozenRoot + "/aggregate.json")
        let variants = experiment["variants"] as! [String: String]
        var total = 0, fullParity = 0, proposals = 0, times: [Double] = [], hashes: [String: String] = [:]
        var aggregates: [JSON] = []
        for (directory, exercise) in [("squat", "squat"), ("pushup", "pushup"), ("barbellrow", "barbell-row")] {
            let path = captureRoot + "/" + directory + "/terminal-original.jsonl"
            let data = try Data(contentsOf: URL(fileURLWithPath: path)); hashes[directory] = sha(data)
            let overrides = experiment["parameters"] as! JSON
            let config = try CoachingCandidateEngine.Configuration(experimentID: experiment["id"] as! String,
                source: experiment["source"] as! String, experimentDeclaredAt: experiment["experimentDeclaredAt"] as! String,
                evaluationMode: "offline_declared", variant: variants[exercise]!, overrides: overrides,
                provenance: Dictionary(uniqueKeysWithValues: overrides.keys.map { ($0, "declared offline engineering experiment " + (experiment["id"] as! String) + "/base") }))
            var processor = CoachingCandidateRuntime.Processor(), baseline = CoachingCandidateEngine()
            var counts: [String: [String: [String: Int]]] = [:]
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! JSON
                guard row["type"] as? String == "terminal_frame" else { continue }
                let decoded = CoachingCandidateEngine.Frame.terminal(row, exercise: exercise, captureID: "terminal-jsonl:" + hashes[directory]!)
                // Exactly the typed adapter used by handleLifted; no logger object exists here.
                let live = CoachingCandidateEngine.Frame.live(source: decoded.source, context: decoded.context,
                    raw3D: decoded.raw3D, assessment3D: decoded.assessment3D, raw2D: decoded.raw2D,
                    confidence: decoded.confidence, invalid: decoded.invalid, state: decoded.state, captureID: decoded.captureID)
                let started = ProcessInfo.processInfo.systemUptime
                let output = processor.process(live, configuration: .success(config), includeRequests: true)
                times.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
                let actual = try XCTUnwrap(output.candidate)
                let expected = try baseline.update(decoded, configuration: config, includeRequests: true)
                XCTAssertEqual(try canonical(actual), try canonical(expected))
                XCTAssertNil(output.error)
                XCTAssertEqual(live.raw3D, decoded.raw3D)
                fullParity += 1; total += 1; proposals += output.proposal == nil ? 0 : 1
                let kind = decoded.flush ? "flush" : "genuine"
                for rule in actual["rules"] as! [JSON] {
                    let id = rule["id"] as! String, state = rule["state"] as! String
                    counts[id, default: [:]][kind, default: [:]][state, default: 0] += 1
                }
            }
            for (rule, kinds) in counts {
                let original = try XCTUnwrap((frozen["results"] as! [JSON]).first {
                    $0["exercise"] as? String == exercise && $0["setting"] as? String == "base" &&
                    $0["mode"] as? String == "assessment_checked" && $0["rule"] as? String == rule
                })
                for kind in ["genuine", "flush"] { XCTAssertEqual(try canonical(kinds[kind] ?? [:]), try canonical(original[kind] ?? [:])) }
                aggregates.append(["exercise": exercise, "rule": rule, "genuine": kinds["genuine"] ?? [:], "flush": kinds["flush"] ?? [:]])
            }
            XCTAssertEqual(sha(try Data(contentsOf: URL(fileURLWithPath: path))), hashes[directory])
        }
        XCTAssertEqual(total, 2398); XCTAssertEqual(fullParity, total); XCTAssertEqual(proposals, 0)
        times.sort()
        let proof: JSON = ["schema": "bpt.live-candidate-host-replay.v1", "frames": total, "fullOutputParityFrames": fullParity,
            "frozenV3RuleCountsEqual": true, "originalSHA256": hashes, "proposals": proposals,
            "processorMilliseconds": ["median": times[times.count / 2], "p95": times[Int(Double(times.count - 1) * 0.95)], "max": times.last!],
            "timingScope": "host CPU, typed adapter plus full requests and compact validation; no inference; not device latency",
            "results": aggregates.sorted { String(describing: $0["exercise"]!) + String(describing: $0["rule"]!) < String(describing: $1["exercise"]!) + String(describing: $1["rule"]!) }]
        if let output = env["BPT_CANDIDATE_PROOF_OUTPUT"] { try canonical(proof).write(to: URL(fileURLWithPath: output)) }
    }
}
