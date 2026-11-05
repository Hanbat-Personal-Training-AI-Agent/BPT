import XCTest
@testable import CalibrationEngineKit

/// Swift WristFloorAnchor vs pose_feedback/geometry/wrist_anchor.py, tests/fixtures/wrist_anchor_cases.json
/// (scripts/make_setup_constraint_fixtures.py; inputs rounded to 1e-7).
final class WristFloorAnchorTests: XCTestCase {
    struct Fixture: Decodable {
        struct Params: Decodable {
            let radius: Double?
            let conf: Double?
            let reanchor_frames: Int?
            let init_frames: Int?
        }
        struct Expected: Decodable {
            let out: [[Double]]
            let states: [String]
        }
        struct Case: Decodable {
            let params: Params
            let frames: [[[Double]]]
            let active: [Bool]
            let expected: [Expected]
        }
        let cases: [Case]
    }

    func testFixtureParity() throws {
        let url = MotionAGFormerLiveTests.root.appendingPathComponent("tests/fixtures/wrist_anchor_cases.json")
        let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(f.cases.count, 2)
        for (ci, c) in f.cases.enumerated() {
            var p = WristFloorAnchor.Params()
            if let v = c.params.radius { p.radius = v }
            if let v = c.params.conf { p.conf = v }
            if let v = c.params.reanchor_frames { p.reanchorFrames = v }
            if let v = c.params.init_frames { p.initFrames = v }
            var anchor = WristFloorAnchor(params: p)
            for (t, (frame, want)) in zip(c.frames, c.expected).enumerated() {
                let got = anchor.update(frame.map { PoseKeypoint(x: $0[0], y: $0[1], confidence: $0[2]) }, active: c.active[t])
                let tag = "case \(ci) frame \(t)"
                XCTAssertEqual([got.states[9]?.rawValue, got.states[10]?.rawValue], want.states, tag)
                for (j, w) in [9, 10].enumerated() {
                    XCTAssertEqual(got.keypoints[w].x, want.out[j][0], accuracy: 1e-6, tag)
                    XCTAssertEqual(got.keypoints[w].y, want.out[j][1], accuracy: 1e-6, tag)
                    XCTAssertEqual(got.keypoints[w].confidence, want.out[j][2], accuracy: 1e-9, tag)
                }
            }
        }
    }
}
