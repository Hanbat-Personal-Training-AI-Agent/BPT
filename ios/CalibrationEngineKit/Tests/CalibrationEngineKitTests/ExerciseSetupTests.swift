import simd
import XCTest
@testable import CalibrationEngineKit

/// Swift ExerciseSetup vs pose_feedback/body/exercise_setup.py, tests/fixtures/exercise_setup_cases.json
/// (scripts/make_setup_constraint_fixtures.py; values rounded to 1e-7).
final class ExerciseSetupTests: XCTestCase {
    struct Fixture: Decodable {
        struct Frame: Decodable {
            let pose: [[Double]]
            let conf: [Double]
            let usable: Bool
            let unit: Double
        }
        struct Item: Decodable {
            let key: String
            let value: Double?
            let quality: String
            let required: Bool
            let depth: Double
            let ref: Double?
            let cue: String?
        }
        struct Expected: Decodable {
            let phase: String
            let progress: Double
            let moving: Bool
            let items: [Item]
        }
        struct Case: Decodable {
            let exercise: String
            let reference: [String: Double]
            let frames: [Frame]
            let expected: [Expected]
            let ready: [String: Double]?
            let seeds: [String: [SeedPart]]
        }
        enum SeedPart: Decodable {
            case vector([Double]), number(Double)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let v = try? c.decode([Double].self) { self = .vector(v) } else { self = .number(try c.decode(Double.self)) }
            }
        }
        let cases: [Case]
    }

    func testFixtureParity() throws {
        let url = MotionAGFormerLiveTests.root.appendingPathComponent("tests/fixtures/exercise_setup_cases.json")
        let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertFalse(f.cases.isEmpty)
        for c in f.cases {
            let exercise = try XCTUnwrap(FormExercise(rawValue: c.exercise))
            var s = ExerciseSetup(exercise: exercise, reference: c.reference)
            for (i, (frame, want)) in zip(c.frames, c.expected).enumerated() {
                let pose = frame.pose.map { SIMD3($0[0], $0[1], $0[2]) }
                let got = s.update(frame.usable ? pose : nil, confidence: frame.conf, usable: frame.usable, unit: frame.unit)
                let tag = "\(c.exercise) frame \(i)"
                XCTAssertEqual(got.phase.rawValue, want.phase, tag)
                XCTAssertEqual(got.progress, want.progress, accuracy: 1e-6, tag)
                XCTAssertEqual(got.moving, want.moving, tag)
                XCTAssertEqual(got.items.map(\.key), want.items.map(\.key), tag)
                for (g, w) in zip(got.items, want.items) {
                    XCTAssertEqual(g.quality.rawValue, w.quality, "\(tag) \(w.key)")
                    XCTAssertEqual(g.required, w.required, "\(tag) \(w.key)")
                    XCTAssertEqual(g.depth, w.depth, accuracy: 1e-6, "\(tag) \(w.key)")
                    XCTAssertEqual(g.value == nil, w.value == nil, "\(tag) \(w.key)")
                    if let a = g.value, let b = w.value { XCTAssertEqual(a, b, accuracy: 1e-6, "\(tag) \(w.key)") }
                    XCTAssertEqual(g.ref, w.ref, "\(tag) \(w.key)")
                    XCTAssertEqual(g.cue, w.cue, "\(tag) \(w.key)")
                }
            }
            XCTAssertEqual(s.ready == nil, c.ready == nil, c.exercise)
            for (k, v) in c.ready ?? [:] { XCTAssertEqual(try XCTUnwrap(s.ready?[k]), v, accuracy: 1e-6, "\(c.exercise) ready \(k)") }
            XCTAssertEqual(s.ready?.count, c.ready?.count)
            let seeds = s.seeds(AdaptiveRelationConstraint.relations(for: exercise))
            XCTAssertEqual(Set(seeds.keys), Set(c.seeds.keys), c.exercise)
            for (name, parts) in c.seeds {
                guard case .vector(let ref) = parts[0], case .number(let spread) = parts[1] else { return XCTFail("bad seed") }
                let g = try XCTUnwrap(seeds[name])
                XCTAssertLessThan(simd_length(g.ref - SIMD3(ref[0], ref[1], ref[2])), 1e-5, "\(c.exercise) seed \(name)")
                XCTAssertEqual(g.spread, spread, accuracy: 1e-5, "\(c.exercise) seed \(name)")
            }
        }
    }

    func testOptionsAreOffUnlessFlutterAsks() {
        XCTAssertNil(ExerciseSetup.Options(creationParams: ["exerciseId": "squat"]))
        XCTAssertNil(ExerciseSetup.Options(creationParams: nil))
        let o = ExerciseSetup.Options(creationParams: [
            "exerciseId": "squat", "exerciseSetup": true, "setupVariant": "back_squat",
            "setupReference": ["feet_width": NSNumber(value: 1.4)], "bodyProfile": ["hipWidthCm": NSNumber(value: 28)],
        ])
        XCTAssertEqual(o?.variant, "back_squat")
        XCTAssertEqual(o?.reference["feet_width"], 1.4)
        XCTAssertEqual(o?.bodyProfile["hipWidthCm"], 28)
    }

    func testBridgePayloadAndSignature() throws {
        let item = ExerciseSetup.Item(key: "grip_width", value: 1.52, quality: .good, required: true, depth: 0.1, ref: 1.3, cue: "decrease")
        let missing = ExerciseSetup.Item(key: "feet_width", value: nil, quality: .missing, required: true, depth: 0, ref: nil, cue: nil)
        let state = ExerciseSetup.State(phase: .holding, progress: 0.43, moving: false, items: [item, missing])
        let p = ExerciseSetupBridge.payload(state, exercise: .barbellRow, variant: nil, snapshot: nil)
        XCTAssertEqual(p["exercise"] as? String, "barbell_row")
        XCTAssertEqual(p["phase"] as? String, "holding")
        XCTAssertNil(p["variant"])
        XCTAssertNil(p["snapshot"])
        let items = try XCTUnwrap(p["items"] as? [[String: Any]])
        XCTAssertEqual(items[0]["approx"] as? Bool, true, "grip = wrist centres, flagged as an approximation")
        XCTAssertEqual(items[0]["cue"] as? String, "decrease")
        XCTAssertNil(items[1]["value"], "no number for a joint that is not observed")
        XCTAssertNil(items[1]["ref"])
        // Small changes do not resend; a quality change or a 10% progress step does.
        let nudged = ExerciseSetup.State(phase: .holding, progress: 0.46, moving: false,
                                         items: [ExerciseSetup.Item(key: "grip_width", value: 1.51, quality: .good, required: true,
                                                                    depth: 0.1, ref: 1.3, cue: "decrease"), missing])
        XCTAssertEqual(ExerciseSetupBridge.signature(state), ExerciseSetupBridge.signature(nudged))
        let stepped = ExerciseSetup.State(phase: .holding, progress: 0.51, moving: false, items: [item, missing])
        XCTAssertNotEqual(ExerciseSetupBridge.signature(state), ExerciseSetupBridge.signature(stepped))
    }
}
