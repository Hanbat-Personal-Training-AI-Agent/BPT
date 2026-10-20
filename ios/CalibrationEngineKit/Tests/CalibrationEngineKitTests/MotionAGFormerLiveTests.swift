import CoreML
import XCTest
@testable import CalibrationEngineKit

/// Swift MotionAGFormerLive + Pose3DConstraints vs the Python reference (pose_feedback/body/live_motionagformer.py
/// LiveMotionAGFormer), tests/fixtures/live3d_parity.json from scripts/make_live3d_parity_fixture.py.
final class MotionAGFormerLiveTests: XCTestCase {
    struct Fixture: Decodable {
        struct Frame: Decodable {
            let frame: Int
            let state: String
            let filled: Int
            let row: Int?
            let raw: [[Double]]?
            let pose3d: [[Double]]?
            let bone_max_correction: Double?
            let angle_corrections: [String: Double]?
            let knees_reflected: Int?
            let invalid_joints: [Int]?
        }
        struct Run: Decodable {
            let lookahead: Int
            let cadence: Int
            let inferences: Int
            let frames: [Frame]
        }
        let image_size: [Int]
        let coco17: [[[Double]]]
        let fake: [Run]
        struct WristCase: Decodable {
            let raw: [[Double]]
            let mediapipe: [String: [Double]]
            let same_hand: Bool?
            let input: [[Double]]
        }
        let coreml: Run?
        let wrist: [WristCase]
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func fixture() throws -> Fixture {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("tests/fixtures/live3d_parity.json"))
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    /// Same closed form as fake_predict in the fixture script.
    static func fakePredict(_ x: [Float]) -> [Float] {
        var out = x
        for t in 0..<27 {
            for j in 0..<17 {
                let i = (t * 17 + j) * 3
                out[i + 2] = 0.3 * x[i] * x[i + 1] + 0.01 * Float(t)
            }
        }
        return out
    }

    func run(_ f: Fixture, lookahead: Int, cadence: Int, predict: @escaping ([Float]) throws -> [Float])
        throws -> (frames: [Lifted3DFrame], inferences: Int) {
        var live = MotionAGFormerLive<Int>(lookahead: lookahead, cadence: cadence, predict: predict)
        var out: [Lifted3DFrame] = []
        for (i, k) in f.coco17.enumerated() {
            let kp = k.map { PoseKeypoint(x: $0[0], y: $0[1], confidence: $0[2]) }
            out += try live.push(frameIndex: i, coco17: kp, imageWidth: f.image_size[0], imageHeight: f.image_size[1],
                                 payload: i).map { payload, frame in
                XCTAssertEqual(payload, frame.frameIndex, "2D payload travels with its own 3D frame")
                return frame
            }
        }
        out += try live.flush().map(\.1)
        return (out, live.inferences)
    }

    func compare(_ got: [Lifted3DFrame], _ want: Fixture.Run, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.map(\.frameIndex), want.frames.map(\.frame), file: file, line: line)
        for (g, w) in zip(got, want.frames) {
            XCTAssertEqual(g.state.rawValue, w.state, "frame \(w.frame)", file: file, line: line)
            XCTAssertEqual(g.row, w.row, "frame \(w.frame)", file: file, line: line)
            XCTAssertEqual(g.filled, w.filled, "frame \(w.frame)", file: file, line: line)
            for (name, a, b) in [("raw", g.raw, w.raw), ("pose3d", g.pose3D, w.pose3d)] {
                XCTAssertEqual(a == nil, b == nil, "\(name) frame \(w.frame)", file: file, line: line)
                guard let a, let b else { continue }
                let diff = zip(a, b).map { p, q in max(abs(p.x - q[0]), abs(p.y - q[1]), abs(p.z - q[2])) }.max() ?? 0
                XCTAssertLessThan(diff, accuracy, "\(name) frame \(w.frame)", file: file, line: line)
            }
            if let c = g.constraints, let bone = w.bone_max_correction {
                XCTAssertEqual(c.boneMaxCorrection, bone, accuracy: accuracy * 10, "frame \(w.frame)", file: file, line: line)
                XCTAssertEqual(Set(c.angleCorrections.keys), Set((w.angle_corrections ?? [:]).keys), "frame \(w.frame)", file: file, line: line)
                XCTAssertEqual(c.invalidJoints, Set(w.invalid_joints ?? []), "frame \(w.frame)", file: file, line: line)
                XCTAssertEqual(c.kneesReflected, w.knees_reflected ?? 0, "frame \(w.frame)", file: file, line: line)
            }
        }
    }

    func testFakeModelParity() throws {
        let f = try fixture()
        for want in f.fake {
            let (got, inferences) = try run(f, lookahead: want.lookahead, cadence: want.cadence, predict: Self.fakePredict)
            XCTAssertEqual(inferences, want.inferences, "lookahead \(want.lookahead) cadence \(want.cadence)")
            compare(got, want, accuracy: 1e-4)
        }
    }

    /// Real XS: the same Core ML package the fixture script ran (fp16 output). Skipped when the gitignored
    /// asset is absent.
    func testCoreMLParity() throws {
        let f = try fixture()
        let url = Self.root.appendingPathComponent("assets/coreml/motionagformer_xs.mlpackage")
        guard let want = f.coreml, FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("no assets/coreml/motionagformer_xs.mlpackage or no coreml section")
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: try MLModel.compileModel(at: url), configuration: config)
        let (got, _) = try run(f, lookahead: 5, cadence: 1, predict: MotionAGFormerCoreML.predictor(model))
        // fp16 output + float32 (Python) vs double (Swift) input normalisation: max seen 0.0076 crop units (~0.8% of body height).
        compare(got, want, accuracy: 1e-2)
    }

    func testWristSourceParity() throws {
        for c in try fixture().wrist {
            let raw = c.raw.map { PoseKeypoint(x: $0[0], y: $0[1], confidence: $0[2]) }
            let point = { (side: String) in c.mediapipe[side].map { PosePoint(x: $0[0], y: $0[1]) } }
            let got = MotionAGFormerWristSource.input(raw: raw, left: point("left"), right: point("right"),
                                                      sameHand: c.same_hand ?? false)
            for (g, w) in zip(got.input, c.input) {
                XCTAssertEqual(g.x, w[0], accuracy: 1e-3)
                XCTAssertEqual(g.y, w[1], accuracy: 1e-3)
                XCTAssertEqual(g.confidence, w[2], accuracy: 1e-6, "RTMPose confidence kept")
            }
        }
    }

    /// Same-hand test (Python same_hand): overlapping landmark boxes are one hand, side-by-side hands are not.
    func testSameHandIoU() {
        let hand = (0..<21).map { PosePoint(x: 100 + Double($0 % 5) * 10, y: 200 + Double($0 / 5) * 10) }
        XCTAssertTrue(MotionAGFormerWristSource.sameHand(hand, hand.map { PosePoint(x: $0.x + 3, y: $0.y - 2) }))
        XCTAssertFalse(MotionAGFormerWristSource.sameHand(hand, hand.map { PosePoint(x: $0.x + 30, y: $0.y) }))
        XCTAssertFalse(MotionAGFormerWristSource.sameHand(hand, []))
    }

    /// Flutter gets the state in every case; `usable` only when the evaluators judge with that 3D.
    func testBridgePayloadPerState() {
        let pose = [SIMD3<Double>](repeating: .zero, count: 17)
        for (state, filled, has3D, usable) in [(Pose3DState.warmingUp, 12, false, false), (.trackingLost, 0, false, false),
                                               (.bad3D, 27, true, false), (.partial3D, 27, true, true), (.ok, 27, true, true)] {
            let frame = Lifted3DFrame(frameIndex: 0, state: state, filled: filled, raw: has3D ? pose : nil,
                                      pose3D: has3D ? pose : nil, constraints: nil, row: has3D ? 21 : nil)
            let p = Pose3DBridge.payload(frame)
            XCTAssertEqual(p["state"] as? String, state.rawValue)
            XCTAssertEqual(p["filled"] as? Int, filled)
            XCTAssertEqual(p["window"] as? Int, 27)
            XCTAssertEqual(p["usable"] as? Bool, usable)
            XCTAssertEqual(frame.usable3D != nil, usable)
        }
    }

    func testStatesAndTimeAlignment() throws {
        var live = MotionAGFormerLive<Int>(lookahead: 5, cadence: 1, predict: Self.fakePredict)
        let person = (0..<17).map { PoseKeypoint(x: 300 + Double($0) * 5, y: 200 + Double($0) * 40, confidence: 0.9) }
        var emitted: [Lifted3DFrame] = []
        for i in 0..<40 {
            emitted += try live.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280, payload: i).map(\.1)
        }
        // Frame t is emitted when frame t + 5 arrives; the first 3D comes with the 27th real frame (frame 26 → t = 21).
        XCTAssertEqual(emitted.map(\.frameIndex), Array(0..<35))
        XCTAssertTrue(emitted[..<21].allSatisfy { $0.state == .warmingUp && $0.usable3D == nil })
        XCTAssertNotNil(emitted[21].raw)
        XCTAssertEqual(emitted[21].row, 21)
        XCTAssertEqual(live.delayFrames, 5)
        // Person gone 15 frames: window reset (pending frames flushed with 3D), then tracking_lost without 3D.
        let gone = person.map { PoseKeypoint(x: $0.x, y: $0.y, confidence: 0.01) }
        var lost: [Lifted3DFrame] = []
        for i in 40..<60 {
            lost += try live.push(frameIndex: i, coco17: gone, imageWidth: 720, imageHeight: 1280, payload: i).map(\.1)
        }
        XCTAssertEqual(lost.map(\.frameIndex), Array(35..<60))
        XCTAssertTrue(lost.filter { $0.frameIndex >= 40 }.allSatisfy { $0.state == .trackingLost && $0.usable3D == nil })
        // Back: warm-up again.
        let back = try live.push(frameIndex: 60, coco17: person, imageWidth: 720, imageHeight: 1280, payload: 60)
        XCTAssertTrue(back.isEmpty)
        let rest = try live.flush().map(\.1)
        XCTAssertEqual(rest.map(\.frameIndex), [60])
        XCTAssertEqual(rest.first?.state, .warmingUp)
    }

    func testRotationChangeFlushesOldFramesAndRestartsWarmup() throws {
        let person = (0..<17).map { PoseKeypoint(x: 300 + Double($0) * 5, y: 200 + Double($0) * 40, confidence: 0.9) }
        // Unique confidence tags expose any mixed input window, independent of crop normalization.
        for cadence in [1, 3] {
            var windows: [Set<Float>] = []
            var live = MotionAGFormerLive<Int>(lookahead: 5, cadence: cadence, predict: { input in
                windows.append(Set(stride(from: 2, to: input.count, by: 3).map { input[$0] }))
                return Self.fakePredict(input)
            })
            var emitted: [(Int, Lifted3DFrame)] = []
            for (segment, rotation) in [CaptureRotation.up, .cw90, .cw270, .cw180].enumerated() {
                let tagged = person.map {
                    PoseKeypoint(x: $0.x, y: $0.y, confidence: 0.6 + Double(segment) * 0.1)
                }
                for offset in 0..<40 {
                    let index = segment * 40 + offset
                    let batch = try live.push(frameIndex: index, coco17: tagged, imageWidth: 720,
                                              imageHeight: 1280, captureRotation: rotation, payload: index)
                    if offset == 0 && segment > 0 {
                        XCTAssertEqual(batch.last?.0, index - 1, "old tail emitted before new rotation")
                    }
                    emitted += batch
                }
            }
            emitted += try live.flush()
            XCTAssertEqual(emitted.map(\.0), Array(0..<160), "every payload emitted once, in order")
            XCTAssertTrue(windows.allSatisfy { $0.count == 1 }, "XS windows must contain only one orientation")
            for (payload, frame) in emitted {
                XCTAssertEqual(payload, frame.frameIndex)
                if payload % 40 < 21 {
                    XCTAssertEqual(frame.state, .warmingUp, "every rotation restarts the 27-frame warmup")
                }
            }
        }
    }

    func testFailedRotationFlushStillClearsTheOldWindow() throws {
        enum Failure: Error { case prediction }
        let person = (0..<17).map { PoseKeypoint(x: 300 + Double($0) * 5, y: 200 + Double($0) * 40, confidence: 0.9) }
        var fail = false
        var live = MotionAGFormerLive<Int>(predict: { input in
            if fail { throw Failure.prediction }
            return Self.fakePredict(input)
        })
        for index in 0..<30 {
            _ = try live.push(frameIndex: index, coco17: person, imageWidth: 720, imageHeight: 1280, payload: index)
        }
        fail = true
        XCTAssertThrowsError(try live.push(frameIndex: 30, coco17: person, imageWidth: 720, imageHeight: 1280,
                                           captureRotation: .cw90, payload: 30))
        fail = false
        let next = try live.push(frameIndex: 31, coco17: person, imageWidth: 720, imageHeight: 1280,
                                 captureRotation: .cw90, payload: 31)
        XCTAssertTrue(next.isEmpty)
        let tail = try live.flush()
        XCTAssertEqual(tail.map(\.0), [31], "failed old tail cannot leak into the new window")
        XCTAssertEqual(tail.first?.1.state, .warmingUp)
        XCTAssertEqual(tail.first?.1.filled, 1)
    }
}
