import XCTest
@testable import CalibrationEngineKit

final class ExerciseMotionLiveTests: XCTestCase {
    private let pose: [SIMD3<Double>] = [
        [0,0,0], [0.08,0.02,0], [0.10,0.25,0.01], [0.12,0.48,0], [-0.08,0.02,0],
        [-0.10,0.25,0.01], [-0.12,0.48,0], [0,-0.2,0], [0,-0.4,0], [0,-0.45,0], [0,-0.52,0],
        [-0.20,-0.36,0], [-0.35,-0.15,0], [-0.45,0.05,0], [0.20,-0.36,0], [0.35,-0.15,0], [0.45,0.05,0],
    ]
    private var person: [PoseKeypoint] {
        let xy: [(Double, Double)] = [
            (360,200),(345,180),(375,180),(330,200),(390,200),(280,300),(440,300),
            (240,440),(480,440),(220,580),(500,580),(310,550),(410,550),(300,750),(420,750),(290,950),(430,950),
        ]
        return xy.map { PoseKeypoint(x: $0.0, y: $0.1, confidence: 0.95) }
    }
    private func live(_ variant: ExerciseMotionVariant? = nil) -> MotionAGFormerLive<Int> {
        let row = pose.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        var live = MotionAGFormerLive<Int>(predict: { _ in Array(repeating: row, count: 27).flatMap { $0 } })
        live.constraints.enabled = false
        if let variant { live.motionEstimator = ExerciseMotionEstimator(exercise: "squat", variant: variant) }
        return live
    }

    func testRawAndMatchedFrameSurviveEstimatorBoundary() throws {
        var baseline = live(), experimental = live(.A)
        var a: [Lifted3DFrame] = [], b: [Lifted3DFrame] = []
        for i in 0..<40 {
            a += try baseline.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280, payload: i).map(\.1)
            b += try experimental.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280,
                                      motionContext: .init(timestamp: Double(i) * 0.04), payload: i).map(\.1)
        }
        a += try baseline.flush().map(\.1)
        b += try experimental.flush().map(\.1)
        XCTAssertEqual(a.map(\.frameIndex), b.map(\.frameIndex))
        for (plain, motion) in zip(a, b) {
            XCTAssertEqual(plain.raw, motion.raw, "the XS output must remain exact")
            guard let report = motion.motion else { continue }
            XCTAssertEqual(report.diagnostics["timestamp"] as? Double, Double(motion.frameIndex) * 0.04)
            for (p, q) in zip(plain.pose3D!, motion.pose3D!) {
                XCTAssertEqual(p.x, q.x, accuracy: 1e-12)
                XCTAssertEqual(p.y, q.y, accuracy: 1e-12)
                XCTAssertEqual(p.z, q.z, accuracy: 1e-12)
            }
        }
    }

    func testOnlineProfileAppliesAtRow81AndResetsOnPersonChange() throws {
        var live = live(.E)
        live.motionOnlineCalibration = true
        var outputs: [Lifted3DFrame] = []
        for i in 0..<95 {
            outputs += try live.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280,
                                     motionContext: .init(timestamp: Double(i) / 30, personID: "one"), payload: i).map(\.1)
        }
        let before = outputs.first { $0.frameIndex == 80 }!.motion!
        let after = outputs.first { $0.frameIndex == 81 }!.motion!
        XCTAssertEqual(before.diagnostics["online_calibration_frames"] as? Int, 60)
        XCTAssertEqual(before.diagnostics["online_calibration_applied"] as? Bool, false)
        XCTAssertEqual(after.diagnostics["online_calibration_applied"] as? Bool, true)
        XCTAssertEqual(after.diagnostics["calibration_used"] as? Bool, true)
        var next: [Lifted3DFrame] = []
        for i in 95..<130 {
            next += try live.push(frameIndex: i, coco17: person, imageWidth: 720, imageHeight: 1280,
                                  motionContext: .init(timestamp: Double(i) / 30, personID: "two"), payload: i).map(\.1)
        }
        let firstNew = next.first { $0.frameIndex >= 95 && $0.motion != nil }!
        XCTAssertEqual(firstNew.frameIndex, 116)
        XCTAssertEqual(firstNew.motion!.diagnostics["online_calibration_applied"] as? Bool, false)
        XCTAssertEqual(firstNew.motion!.diagnostics["calibration_used"] as? Bool, false)
    }

    func testExistingGateAndEstimatorInvalidationAreBothPreserved() {
        var report = Pose3DConstraints.Report()
        report.invalidJoints = [2]
        let motion = ExerciseMotionResult(raw: pose, corrected: pose,
                                         correctionMagnitude: Array(repeating: 0, count: 17),
                                         uncertainty: Array(repeating: 0, count: 17),
                                         invalidForAssessment: [13], roles: [], contacts: [:],
                                         usedPrediction: [], phase: nil, diagnostics: [:])
        let frame = Lifted3DFrame(frameIndex: 0, state: .partial3D, filled: 27, raw: pose,
                                  pose3D: pose, constraints: report, row: 21, motion: motion)
        XCTAssertEqual(frame.invalidForAssessment, [2, 13])
        XCTAssertEqual(frame.constraints?.invalidJoints, [2], "preserve the original constraint report")
        XCTAssertTrue(frame.masked3D![2].x.isNaN)
        XCTAssertTrue(frame.masked3D![13].x.isNaN)
        XCTAssertEqual(frame.masked3D![3], pose[3])
    }

    func testGateOnlyBonesDoNotProjectPoseTwice() {
        var constraints = Pose3DConstraints()
        constraints.angleLimits = []
        constraints.kneeClampDegrees = nil
        constraints.knee = .init(enabled: false, limitDegrees: 180)
        constraints.badBoneFraction = 0.01
        let (got, report) = constraints.apply(pose, projectBoneLengths: false)
        XCTAssertEqual(got, pose)
        XCTAssertGreaterThan(report.boneMaxCorrection, 0.01)
        XCTAssertEqual(report.invalidJoints.count, 17, "the existing bone gate remains active")
    }
}
