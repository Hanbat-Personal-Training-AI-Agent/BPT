import simd
import XCTest
@testable import CalibrationEngineKit

/// Swift AdaptiveRelationConstraint vs pose_feedback/geometry/adaptive_relations.py, tests/fixtures/
/// adaptive_relations_cases.json (scripts/make_setup_constraint_fixtures.py; values rounded to 1e-7).
final class AdaptiveRelationConstraintTests: XCTestCase {
    struct Fixture: Decodable {
        struct Frame: Decodable {
            let pose: [[Double]]
            let conf: [Double]
            let frame: Int
            let unit: Double
        }
        struct Fill: Decodable {
            let w: Double
            let sigma: Double
            let gap: Int
        }
        struct Expected: Decodable {
            let pose: [[Double]]?
            let filled: [String: Fill]
            let invalid: [Int]
            let events: [String: String]
            let established: [String]
        }
        struct Seed: Decodable {
            let name: String
            let ref: [Double]
            let spread: Double
        }
        struct Case: Decodable {
            let exercise: String
            let params: [String: Double]
            let frames: [Frame]
            let expected: [Expected]
            let seed: Seed?
        }
        let relations: [String: [[AnyCodableInt]]]
        let cases: [Case]
    }

    /// The fixture's relation table mixes names and indices.
    enum AnyCodableInt: Decodable, Equatable {
        case int(Int), string(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { self = .int(i) } else { self = .string(try c.decode(String.self)) }
        }
    }

    static func fixture() throws -> Fixture {
        let url = MotionAGFormerLiveTests.root.appendingPathComponent("tests/fixtures/adaptive_relations_cases.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    static func params(_ p: [String: Double]) -> AdaptiveRelationConstraint.Params {
        var out = AdaptiveRelationConstraint.Params()
        if let v = p["max_gap_frames"] { out.maxGapFrames = Int(v) }
        if let v = p["init_frames"] { out.initFrames = Int(v) }
        return out
    }

    func testRelationTableMatchesPython() throws {
        let f = try Self.fixture()
        for (name, rows) in f.relations {
            let exercise = try XCTUnwrap(FormExercise(rawValue: name))
            let want = rows.map { row -> AdaptiveRelationConstraint.Relation in
                guard case .string(let n) = row[0], case .int(let a) = row[1], case .int(let b) = row[2] else { fatalError("bad row") }
                return AdaptiveRelationConstraint.Relation(name: n, a: a, b: b)
            }
            XCTAssertEqual(AdaptiveRelationConstraint.relations(for: exercise), want, name)
        }
        XCTAssertTrue(AdaptiveRelationConstraint.relations(for: .benchPress).isEmpty)
    }

    func testFixtureParity() throws {
        for c in try Self.fixture().cases {
            let exercise = try XCTUnwrap(FormExercise(rawValue: c.exercise))
            var m = AdaptiveRelationConstraint(exercise: exercise, params: Self.params(c.params))
            if let seed = c.seed {
                m.seedReference(name: seed.name, refPx: SIMD3(seed.ref[0], seed.ref[1], seed.ref[2]), spreadPx: seed.spread)
            }
            for (i, (frame, want)) in zip(c.frames, c.expected).enumerated() {
                let pose = frame.pose.map { SIMD3($0[0], $0[1], $0[2]) }
                let (got, report) = m.update(pose, confidence: frame.conf, frame: frame.frame, unit: frame.unit)
                let tag = "\(c.exercise)\(c.seed == nil ? "" : " seeded") frame \(i)"
                let wantPose = want.pose.map { $0.map { SIMD3($0[0], $0[1], $0[2]) } } ?? pose
                for j in 0..<17 {
                    XCTAssertLessThan(simd_length(got[j] - wantPose[j]), 1e-6, "\(tag) joint \(j)")
                    if report.filled[j] == nil { XCTAssertEqual(got[j], pose[j], "\(tag) joint \(j): only filled joints change") }
                }
                XCTAssertEqual(Set(report.filled.keys), Set(want.filled.keys.compactMap(Int.init)), tag)
                for (key, fill) in want.filled {
                    let g = try XCTUnwrap(report.filled[Int(key)!])
                    XCTAssertEqual(g.w, fill.w, accuracy: 1e-6, tag)
                    XCTAssertEqual(g.sigma, fill.sigma, accuracy: 1e-6, tag)
                    XCTAssertEqual(g.gap, fill.gap, tag)
                }
                XCTAssertEqual(report.invalid, want.invalid, tag)
                XCTAssertEqual(report.relations.compactMapValues(\.event), want.events, tag)
                XCTAssertEqual(report.relations.filter { $0.value.state == "established" }.keys.sorted(), want.established, tag)
            }
        }
    }

    /// Standing H36M17, crop units: legs 0.9, ankles 0.4 apart (left ankle x = `leftAnkleX`).
    static func standing(leftAnkleX: Double = 0.2) -> [SIMD3<Double>] {
        var p = [SIMD3<Double>](repeating: .zero, count: 17)
        p[1] = SIMD3(-0.1, 0, 0); p[4] = SIMD3(0.1, 0, 0)
        p[2] = SIMD3(-0.15, 0.45, 0); p[5] = SIMD3(0.15, 0.45, 0)
        p[3] = SIMD3(-0.2, 0.9, 0); p[6] = SIMD3(leftAnkleX, 0.9, 0)
        p[8] = SIMD3(0, -0.5, 0)
        return p
    }

    /// Ball mode: a plausible XS guess inside the ball is kept, a far one is pulled back onto the ball.
    func testBallModeKeepsPlausibleXSAndBoundsFarOnes() {
        var params = AdaptiveRelationConstraint.Params()
        params.ballBase = 0.1
        params.decayFrames = 1e12  // w = 1 while the joint is unobserved: the output is the bounded target itself
        var m = AdaptiveRelationConstraint(exercise: .squat, params: params)
        let observed = [Double](repeating: 0.9, count: 17)
        for t in 0..<20 { _ = m.update(Self.standing(), confidence: observed, frame: t, unit: 1) }
        let scale = m.scale ?? 0  // leg 0.9
        var low = observed
        low[6] = 0.0
        let near = Self.standing(leftAnkleX: 0.25)  // 0.05 from anchor + reference: inside the 0.09 ball
        let (keep, r1) = m.update(near, confidence: low, frame: 20, unit: 1)
        XCTAssertNotNil(r1.filled[6])
        XCTAssertLessThan(simd_length(keep[6] - near[6]), 1e-12, "plausible XS position kept")
        let far = Self.standing(leftAnkleX: 0.8)
        let (bounded, _) = m.update(far, confidence: low, frame: 21, unit: 1)
        let center = SIMD3<Double>(0.2, 0.9, 0)
        XCTAssertEqual(simd_length(bounded[6] - center), 0.1 * scale, accuracy: 1e-9, "far XS pulled onto the ball")
        XCTAssertEqual(bounded[6].y, 0.9, accuracy: 1e-12)
    }

    /// MotionAGFormerLive: adaptive off = bit-identical to before; on = raw / pose3D kept, `adapted` + report added.
    func testLiveHookKeepsRawAndConstrained() throws {
        let person = (0..<17).map { PoseKeypoint(x: 300 + Double($0) * 5, y: 200 + Double($0) * 40, confidence: 0.9) }
        func run(adaptive: Bool) throws -> [Lifted3DFrame] {
            var live = MotionAGFormerLive<Int>(lookahead: 5, cadence: 1, predict: MotionAGFormerLiveTests.fakePredict)
            if adaptive { live.adaptive = AdaptiveRelationConstraint(exercise: .squat) }
            var out: [Lifted3DFrame] = []
            for i in 0..<60 {
                var k = person
                if (40..<50).contains(i) { k[15] = PoseKeypoint(x: 900, y: 1200, confidence: 0.1) }  // left ankle lost
                out += try live.push(frameIndex: i, coco17: k, imageWidth: 720, imageHeight: 1280, payload: i).map(\.1)
            }
            return out + (try live.flush().map(\.1))
        }
        let off = try run(adaptive: false), on = try run(adaptive: true)
        XCTAssertEqual(off.map(\.frameIndex), on.map(\.frameIndex))
        for (a, b) in zip(off, on) {
            XCTAssertNil(a.adapted)
            XCTAssertEqual(a.raw, b.raw)
            XCTAssertEqual(a.pose3D, b.pose3D, "constrained 3D is not touched by the adaptive step")
            if a.pose3D != nil {
                XCTAssertEqual(a.masked3D?.count, 17)
                XCTAssertNotNil(b.adapted)
                XCTAssertEqual(b.confidence?.count, 17)
                XCTAssertGreaterThan(b.unit ?? 0, 0)
            }
        }
        // The lost ankle (H36M 6) is filled from the other foot once the relation exists.
        XCTAssertTrue(on.contains { $0.adaptive?.filled[6] != nil })
        let filled = try XCTUnwrap(on.first { $0.adaptive?.filled[6] != nil })
        XCTAssertNotEqual(filled.adapted?[6], filled.pose3D?[6])
        XCTAssertEqual(filled.masked3D?[6], filled.adapted?[6])
    }
}
