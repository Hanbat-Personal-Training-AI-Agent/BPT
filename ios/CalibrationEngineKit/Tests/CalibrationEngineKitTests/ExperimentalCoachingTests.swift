import Foundation
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
    private let rowProfile = ExperimentalCoaching.Profile(exercise: "barbell_row", variant: "strict_row", approved: true,
        upperArmRange: nil, legExtensionDegrees: 15, elbowFlexionDegrees: 15, sustainSeconds: 0.2)
    private let deadProfile = ExperimentalCoaching.Profile(exercise: "deadlift", variant: "double_overhand_deadlift", approved: true,
        upperArmRange: nil, legExtensionDegrees: 15, elbowFlexionDegrees: 15, sustainSeconds: 0.2)

    func testProfileEqualityRevisionAndApprovalResetPersistence() {
        var e = ExperimentalCoaching(); let p = pose()
        _ = e.update(frame(0,p),profile:pushProfile)
        _ = e.update(frame(0.1,p),profile:pushProfile)
        XCTAssertEqual(e.update(frame(0.21,p),profile:pushProfile).candidates.first?.assessment,"candidate", "equal profile preserves a valid interval")
        var revised = pushProfile; revised.revision = "approval-2"
        XCTAssertEqual(e.update(frame(0.3,p),profile:revised).candidates.first?.assessment,"not_triggered")
        _ = e.update(frame(0.4,p),profile:revised)
        XCTAssertEqual(e.update(frame(0.51,p),profile:revised).candidates.first?.assessment,"candidate")
        let revoked = ExperimentalCoaching.Profile(exercise:"pushup",variant:"approved_pushup",approved:false,
            upperArmRange:20...45,legExtensionDegrees:15,elbowFlexionDegrees:15,sustainSeconds:0.2)
        XCTAssertEqual(e.update(frame(0.6,p),profile:revoked).candidates.first?.assessment,"withheld")
        XCTAssertEqual(e.update(frame(0.7,p),profile:revised).candidates.first?.assessment,"not_triggered")
        let changed = ExperimentalCoaching.Profile(exercise:"pushup",variant:"approved_pushup",approved:true,
            upperArmRange:20...50,legExtensionDegrees:20,elbowFlexionDegrees:20,sustainSeconds:0.1)
        XCTAssertEqual(e.update(frame(0.81,p),profile:changed).candidates.first?.assessment,"not_triggered", "changed threshold/duration cannot inherit previous time")
    }

    func testProfileChangeDiscardsMovementBaseline() {
        var e = ExperimentalCoaching()
        _ = e.update(frame(0,pose(knee:140,elbow:170),exercise:"barbell_row",phase:"pulling"),profile:rowProfile)
        var revised = rowProfile; revised.revision = "new"
        let moved = pose(knee:170,elbow:140)
        XCTAssertEqual(e.update(frame(0.1,moved,exercise:"barbell_row",phase:"pulling"),profile:revised).candidates.first?.assessment,"withheld")
        for t in [0.2,0.3,0.4] {
            XCTAssertEqual(e.update(frame(t,moved,exercise:"barbell_row",phase:"pulling"),profile:revised).candidates.first?.assessment,"not_triggered", "movement before revised approval is not evidence")
        }
    }

    func testRowLocalOcclusionDiscardsBaselineAndRecovers() {
        var e = ExperimentalCoaching()
        _ = e.update(frame(0,pose(knee:110,elbow:170),exercise:"barbell_row",phase:"pulling"),profile:rowProfile)
        _ = e.update(frame(0.1,pose(knee:140,elbow:140),exercise:"barbell_row",phase:"pulling"),profile:rowProfile)
        let obscured = e.update(frame(0.2,pose(knee:145,elbow:140),exercise:"barbell_row",phase:"pulling",invalid:[2]),profile:rowProfile)
        XCTAssertTrue(obscured.metrics["leftElbowDeg"]!.available, "unrelated support does not preserve the baseline")
        XCTAssertEqual(obscured.candidates.first?.assessment,"withheld")
        let restored = pose(knee:145,elbow:140)
        XCTAssertEqual(e.update(frame(0.3,restored,exercise:"barbell_row",phase:"pulling"),profile:rowProfile).candidates.first?.assessment,"withheld")
        XCTAssertEqual(e.update(frame(0.4,restored,exercise:"barbell_row",phase:"pulling"),profile:rowProfile).candidates.first?.assessment,"not_triggered")
        let further = pose(knee:175,elbow:110)
        _ = e.update(frame(0.5,further,exercise:"barbell_row",phase:"pulling"),profile:rowProfile)
        _ = e.update(frame(0.6,further,exercise:"barbell_row",phase:"pulling"),profile:rowProfile)
        XCTAssertEqual(e.update(frame(0.71,further,exercise:"barbell_row",phase:"pulling"),profile:rowProfile).candidates.first?.assessment,"candidate", "new fully observed movement can be judged after recovery")
    }

    func testBadFirstPhaseFrameDoesNotPoisonRecovery() {
        var e = ExperimentalCoaching()
        _ = e.update(frame(0,pose(knee:110,elbow:170),exercise:"barbell_row",phase:"pulling",invalid:[2]),profile:rowProfile)
        XCTAssertEqual(e.update(frame(0.1,pose(knee:140,elbow:150),exercise:"barbell_row",phase:"pulling"),profile:rowProfile).candidates.first?.assessment,"withheld")
        let moved = pose(knee:175,elbow:110)
        _ = e.update(frame(0.2,moved,exercise:"barbell_row",phase:"pulling"),profile:rowProfile)
        _ = e.update(frame(0.3,moved,exercise:"barbell_row",phase:"pulling"),profile:rowProfile)
        XCTAssertEqual(e.update(frame(0.41,moved,exercise:"barbell_row",phase:"pulling"),profile:rowProfile).candidates.first?.assessment,"candidate")
    }

    func testNonFiniteTimeWithholdsAndFiniteRecoveryRestarts() throws {
        for time in [Double.nan, Double.infinity, -Double.infinity] {
            var e = ExperimentalCoaching(); let p = pose()
            _ = e.update(frame(0,p),profile:pushProfile)
            _ = e.update(frame(0.1,p),profile:pushProfile)
            let invalid = e.update(frame(time,p),profile:pushProfile)
            XCTAssertNil(invalid.time)
            XCTAssertEqual(invalid.candidates.first?.assessment,"withheld")
            XCTAssertTrue(invalid.candidates.first!.reasons.contains("invalid_timestamp"))
            XCTAssertNoThrow(try JSONEncoder().encode(invalid))
            XCTAssertEqual(e.update(frame(0.21,p),profile:pushProfile).candidates.first?.assessment,"not_triggered")
            _ = e.update(frame(0.31,p),profile:pushProfile)
            XCTAssertEqual(e.update(frame(0.42,p),profile:pushProfile).candidates.first?.assessment,"candidate")
            var row = ExperimentalCoaching()
            _ = row.update(frame(0,pose(knee:140,elbow:170),exercise:"barbell_row",phase:"pulling"),profile:rowProfile)
            _ = row.update(frame(time,pose(knee:175,elbow:110),exercise:"barbell_row",phase:"pulling"),profile:rowProfile)
            XCTAssertEqual(row.update(frame(0.1,pose(knee:175,elbow:110),exercise:"barbell_row",phase:"pulling"),profile:rowProfile).candidates.first?.assessment,"withheld", "invalid time removes the movement baseline too")
        }
    }

    func testNarrowUpperArmIsNeverExcessiveFlare() {
        var e = ExperimentalCoaching()
        for t in [0.0,0.1,0.2,0.3,0.4] {
            XCTAssertEqual(e.update(frame(t,pose(flare:10)),profile:pushProfile).candidates.first?.assessment,"not_triggered")
        }
    }

    func testDeadliftNormalFlexionPhaseAndOcclusion() {
        var e = ExperimentalCoaching()
        _ = e.update(frame(0,pose(elbow:170),exercise:"deadlift",phase:"rising"),profile:deadProfile)
        XCTAssertEqual(e.update(frame(0.1,pose(elbow:170),exercise:"deadlift",phase:"rising"),profile:deadProfile).candidates.first?.assessment,"not_triggered")
        _ = e.update(frame(0.2,pose(elbow:140),exercise:"deadlift",phase:"rising"),profile:deadProfile)
        XCTAssertEqual(e.update(frame(0.41,pose(elbow:140),exercise:"deadlift",phase:"rising"),profile:deadProfile).candidates.first?.assessment,"candidate")
        XCTAssertEqual(e.update(frame(0.5,pose(elbow:120),exercise:"deadlift",phase:"lowering"),profile:deadProfile).candidates.first?.assessment,"withheld")
        XCTAssertEqual(e.update(frame(0.6,pose(elbow:140),exercise:"deadlift",phase:"rising"),profile:deadProfile).candidates.first?.assessment,"withheld")
        XCTAssertEqual(e.update(frame(0.7,pose(elbow:140),exercise:"deadlift",phase:"rising"),profile:deadProfile).candidates.first?.assessment,"not_triggered")
        let hidden = e.update(frame(0.8,pose(elbow:100),exercise:"deadlift",phase:"rising",invalid:[13]),profile:deadProfile)
        XCTAssertTrue(hidden.metrics["rightElbowDeg"]!.available)
        XCTAssertEqual(hidden.candidates.first?.assessment,"withheld")
        XCTAssertEqual(e.update(frame(0.9,pose(elbow:100),exercise:"deadlift",phase:"rising"),profile:deadProfile).candidates.first?.assessment,"withheld")
        XCTAssertEqual(e.update(frame(1.0,pose(elbow:100),exercise:"deadlift",phase:"rising"),profile:deadProfile).candidates.first?.assessment,"not_triggered")
        _ = e.update(frame(1.1,pose(elbow:70),exercise:"deadlift",phase:"rising"),profile:deadProfile)
        XCTAssertEqual(e.update(frame(1.31,pose(elbow:70),exercise:"deadlift",phase:"rising"),profile:deadProfile).candidates.first?.assessment,"candidate")
    }

}
