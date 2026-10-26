import simd
import XCTest
@testable import CalibrationEngineKit

final class ExperimentalCoachingTests: XCTestCase {
    private func pose(flare: Double = 60, knee: Double = 150, elbow: Double = 170) -> [SIMD3<Double>] {
        var j = [SIMD3<Double>](repeating: .zero, count: 17)
        j[8] = [0, -0.5, 0]; j[11] = [0.2, -0.5, 0]; j[14] = [-0.2, -0.5, 0]
        let f = flare * .pi / 180
        for (hip, kn, ankle, shoulder, el, wrist, sign) in [(4,5,6,11,12,13,1.0),(1,2,3,14,15,16,-1.0)] {
            j[hip] = [0.1 * sign, 0, 0]; j[kn] = j[hip] + [0,0.4,0]
            let k = (180-knee) * .pi / 180
            j[ankle] = j[kn] + [0,0.4*cos(k),0.4*sin(k)]
            let upper = SIMD3<Double>(sign*sin(f),cos(f),0)
            j[el] = j[shoulder] + 0.3 * upper
            let e = (180-elbow) * .pi / 180
            j[wrist] = j[el] + 0.3 * (cos(e)*upper + SIMD3(0,0,sin(e)))
        }
        return j
    }
    private func frame(_ t: Double, _ p: [SIMD3<Double>], raw: [SIMD3<Double>]? = nil,
                       exercise: String = "pushup", phase: String? = "bottom", invalid: Set<Int>? = [],
                       confidence: [Double]? = Array(repeating: 0.9, count: 17)) -> ExperimentalCoaching.Frame {
        .init(time: t, exercise: exercise, phase: phase, state: "ok", raw: raw ?? p,
              corrected: p, confidence: confidence, invalid: invalid, up: [0,-1,0])
    }
    private let pushProfile = ExperimentalCoaching.Profile(exercise: "pushup", variant: "approved_pushup", approved: true,
        upperArmRange: 20...45, legExtensionDegrees: 15, elbowFlexionDegrees: 15, sustainSeconds: 0.2)

    func testFrontalProjectionAndRigidRotation() throws {
        let p = pose()
        var engine = ExperimentalCoaching()
        let a = engine.update(frame(0,p))
        XCTAssertEqual(try XCTUnwrap(a.metrics["leftUpperArmDeg"]?.value), 60, accuracy: 1e-8)
        let q = simd_quatd(angle: .pi/3, axis: simd_normalize(SIMD3<Double>(1,2,3)))
        let rotated = p.map { q.act($0) }
        let f = ExperimentalCoaching.Frame(time: 0.1, exercise: "pushup", phase: "bottom", state: "ok", raw: rotated,
            corrected: rotated, confidence: Array(repeating: 0.9,count:17), invalid: [], up: q.act([0,-1,0]))
        let b = engine.update(f)
        XCTAssertEqual(try XCTUnwrap(b.metrics["leftUpperArmDeg"]?.value), 60, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(b.metrics["trunkInclineDeg"]?.value), 0, accuracy: 1e-6)
    }
    func testProfileAndSustainedObservationRequired() {
        var e = ExperimentalCoaching(); let p = pose()
        XCTAssertEqual(e.update(frame(0,p)).candidates.first?.assessment, "withheld")
        XCTAssertEqual(e.update(frame(0.1,p),profile:pushProfile).candidates.first?.assessment,"not_triggered")
        XCTAssertEqual(e.update(frame(0.2,p),profile:pushProfile).candidates.first?.assessment,"not_triggered")
        XCTAssertEqual(e.update(frame(0.31,p),profile:pushProfile).candidates.first?.assessment,"candidate")
        XCTAssertEqual(e.update(frame(1,p),profile:pushProfile).candidates.first?.assessment,"not_triggered", "gap resets persistence")
        XCTAssertEqual(e.update(frame(0.5,p),profile:pushProfile).candidates.first?.assessment,"not_triggered", "time reversal resets")
    }
    func testLocalInvalidMaskAndCorrectionDisagreement() {
        var e = ExperimentalCoaching(); let p = pose()
        let invalid = e.update(frame(0,p,invalid:[12]),profile:pushProfile)
        XCTAssertEqual(invalid.candidates.first?.assessment,"withheld")
        XCTAssertTrue(invalid.metrics["rightUpperArmDeg"]?.available == true)
        XCTAssertTrue(invalid.metrics["leftUpperArmDeg"]?.reasons.contains("invalid_joint") == true)
        let changed = e.update(frame(0.1,p,raw:pose(flare:20)),profile:pushProfile)
        XCTAssertTrue(changed.metrics["leftUpperArmDeg"]?.reasons.contains("correction_disagreement") == true)
        XCTAssertEqual(changed.candidates.first?.assessment,"withheld")
        let missing = e.update(frame(0.2,p,invalid:nil,confidence:nil),profile:pushProfile)
        XCTAssertEqual(missing.candidates.first?.assessment,"withheld")
    }
    func testLegacyLogMissingRawNeverJudged() {
        var e = ExperimentalCoaching()
        let f = ExperimentalCoaching.Frame(time:0,exercise:"pushup",phase:nil,state:"ok",raw:nil,
            corrected:pose(),confidence:nil,invalid:nil,up:nil)
        let result = e.update(f,profile:pushProfile)
        XCTAssertNotNil(result.metrics["leftElbowDeg"]?.value)
        XCTAssertFalse(result.metrics["leftElbowDeg"]!.available)
        XCTAssertEqual(result.candidates.first?.assessment,"withheld")
    }
    func testRowNeedsCoincidentBilateralLegExtensionAndPull() {
        let profile = ExperimentalCoaching.Profile(exercise:"barbell_row",variant:"strict_row",approved:true,
            upperArmRange:nil,legExtensionDegrees:15,elbowFlexionDegrees:15,sustainSeconds:0.2)
        var e = ExperimentalCoaching()
        _ = e.update(frame(0,pose(knee:140,elbow:170),exercise:"barbell_row",phase:"pulling"),profile:profile)
        let moved = pose(knee:170,elbow:140)
        XCTAssertEqual(e.update(frame(0.1,moved,exercise:"barbell_row",phase:"pulling"),profile:profile).candidates.first?.assessment,"not_triggered")
        XCTAssertEqual(e.update(frame(0.31,moved,exercise:"barbell_row",phase:"pulling"),profile:profile).candidates.first?.assessment,"candidate")
        XCTAssertEqual(e.update(frame(0.4,moved,exercise:"barbell_row",phase:"lowering"),profile:profile).candidates.first?.assessment,"withheld")
        var armOnly = ExperimentalCoaching()
        _ = armOnly.update(frame(0,pose(knee:140,elbow:170),exercise:"barbell_row",phase:"pulling"),profile:profile)
        for t in [0.1,0.2,0.3,0.4] {
            XCTAssertEqual(armOnly.update(frame(t,pose(knee:140,elbow:140),exercise:"barbell_row",phase:"pulling"),profile:profile).candidates.first?.assessment,"not_triggered")
        }
    }
}
