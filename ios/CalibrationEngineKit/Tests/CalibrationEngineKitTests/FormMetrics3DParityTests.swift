import XCTest
@testable import CalibrationEngineKit

/// FormWarningTracker 3D rep metrics (measure3D + metrics2D on the 3D samples) vs the Python mirror
/// pose_feedback/body/form_metrics_3d.py, tests/fixtures/form_metrics_3d_cases.json (scripts/make_form_metrics_3d_fixture.py).
final class FormMetrics3DParityTests: XCTestCase {
    struct Case: Decodable {
        let exercise: String
        let poses: [[[Double]]]
        let intervals: [[Int]]
        let reps: [[String: Double]]
    }

    func testRepMetricsMatchPython() throws {
        let url = MotionAGFormerLiveTests.root.appendingPathComponent("tests/fixtures/form_metrics_3d_cases.json")
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        // Any 2D with the left side more confident (the tracker takes the camera-near side from 2D).
        let coco = (0..<17).map { i in
            PoseKeypoint(x: 300 + Double(i) * 7, y: 100 + Double(i) * 30, confidence: [3, 5, 7, 9, 11, 13, 15].contains(i) ? 0.9 : 0.5)
        }
        for c in cases {
            let tracker = FormWarningTracker(exercise: c.exercise == "squat" ? .squat : .pushUp)
            for (r, interval) in c.intervals.enumerated() {
                for t in interval[0]...interval[1] {
                    let pose = c.poses[t].map { SIMD3<Double>($0[0], $0[1], $0[2]) }
                    tracker.observe(frameIndex: t, coco17: coco, pose3D: pose, pose3DState: .ok, phase: "x")
                    if t == interval[0] { tracker.beginRep() } else { tracker.recordCurrentFrame() }
                }
                let got = tracker.finishRep(repIndex: r + 1).metrics3D.filter { $0.key != "front_view_fraction" }
                let want = c.reps[r]
                XCTAssertEqual(Set(got.keys), Set(want.keys), "\(c.exercise) rep \(r)")
                for (k, v) in want { XCTAssertEqual(got[k] ?? .nan, v, accuracy: 1e-6, "\(c.exercise) rep \(r) \(k)") }
            }
        }
    }
}
