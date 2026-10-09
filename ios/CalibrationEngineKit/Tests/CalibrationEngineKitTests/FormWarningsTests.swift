import simd
import XCTest
@testable import CalibrationEngineKit

final class FormWarningsTests: XCTestCase {
    private func kp(_ x: Double, _ y: Double, _ c: Double = 0.9) -> PoseKeypoint { PoseKeypoint(x: x, y: y, confidence: c) }

    func testSignedTorsoAngle2D() throws {
        let hip = kp(0, 0)
        XCTAssertEqual(try XCTUnwrap(FormGeometry.signedTorsoAngle2D(shoulder: kp(0, -100), hip: hip, facing: 1)), 0, accuracy: 1e-9)
        // Shoulder ahead of the hip in the facing direction = forward lean, either facing.
        XCTAssertEqual(try XCTUnwrap(FormGeometry.signedTorsoAngle2D(shoulder: kp(100, -100), hip: hip, facing: 1)), 45, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(FormGeometry.signedTorsoAngle2D(shoulder: kp(-100, -100), hip: hip, facing: -1)), 45, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(FormGeometry.signedTorsoAngle2D(shoulder: kp(-50, -100), hip: hip, facing: 1)), -26.565, accuracy: 1e-3)
    }

    func testSignedLineDeviation2D() throws {
        // Shoulder–ankle line, either direction; image y is down.
        for (a, b) in [(kp(0, 0), kp(400, 0)), (kp(400, 0), kp(0, 0))] {
            XCTAssertEqual(try XCTUnwrap(FormGeometry.signedLineDeviation2D(point: kp(200, 40), a: a, b: b)), 0.1, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(FormGeometry.signedLineDeviation2D(point: kp(200, -40), a: a, b: b)), -0.1, accuracy: 1e-9)
        }
        XCTAssertNil(FormGeometry.signedLineDeviation2D(point: kp(10, 50), a: kp(0, 0), b: kp(0, 100)))
    }

    /// H36M17, y down, subject's left hip at +x: forward = -z (towards the camera).
    private func standing3D(lean: Double = 0, kneeTheta: Double = 5) -> [SIMD3<Double>] {
        var j = [SIMD3<Double>](repeating: .zero, count: 17)
        j[1] = [-0.1, 0, 0]
        j[4] = [0.1, 0, 0]
        let t = kneeTheta * .pi / 180
        for (hip, knee, ankle) in [(1, 2, 3), (4, 5, 6)] {
            j[knee] = j[hip] + [0, 0.45, 0]
            // Flexion moves the ankle backwards (+z).
            j[ankle] = j[knee] + [0, 0.4 * cos(t), 0.4 * sin(t)]
        }
        let l = lean * .pi / 180
        j[8] = [0, -0.5 * cos(l), -0.5 * sin(l)]
        j[7] = j[8] * 0.5
        j[11] = j[8] + [0.18, 0, 0]
        j[14] = j[8] - [0.18, 0, 0]
        return j
    }

    func testSigned3DMetrics() throws {
        XCTAssertEqual(try XCTUnwrap(FormGeometry.signedTorsoAngle3D(standing3D(lean: 30))), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(FormGeometry.signedTorsoAngle3D(standing3D(lean: -10))), -10, accuracy: 1e-9)
        // Push-up plank along +z, face down (+y): pelvis 0.05 below the thorax–ankle line.
        var plank = [SIMD3<Double>](repeating: .zero, count: 17)
        plank[1] = [-0.1, 0, 0]; plank[4] = [0.1, 0, 0]
        plank[8] = [0, -0.05, -0.5]
        plank[3] = [-0.1, -0.05, 1.0]; plank[6] = [0.1, -0.05, 1.0]
        XCTAssertEqual(try XCTUnwrap(FormGeometry.signedHipDeviation3D(plank)), 0.05 / 1.5, accuracy: 1e-9)
    }

    func testBad3DFramesSkipped3DAndCounted() {
        let tracker = FormWarningTracker(exercise: .squat)
        let coco = sidePushUp(hipDrop: 0)
        tracker.observe(frameIndex: 0, coco17: coco, pose3D: standing3D(lean: 20, kneeTheta: 5), phase: "descending")
        tracker.beginRep()
        tracker.observe(frameIndex: 1, coco17: coco, pose3D: standing3D(lean: 25, kneeTheta: -20), phase: "bottom")
        tracker.recordCurrentFrame()
        let report = tracker.finishRep(repIndex: 1)
        XCTAssertEqual(tracker.sessionFrames3D, 2)
        XCTAssertEqual(tracker.sessionBad3DFrames, 1)
        XCTAssertEqual(report.bad3DFrames, 1)
        XCTAssertEqual(report.frames3D, 2)
        XCTAssertEqual(try XCTUnwrap(report.metrics3D["torso_max"]), 20, accuracy: 1e-9)  // bad frame's 25 skipped
    }

    func testSideHysteresis() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        func frame(left: Double, right: Double) {
            var coco = sidePushUp(hipDrop: 0)
            for i in [3, 5, 7, 9, 11, 13, 15] { coco[i].confidence = left }
            for i in [4, 6, 8, 10, 12, 14, 16] { coco[i].confidence = right }
            tracker.observe(frameIndex: 0, coco17: coco, phase: "top")
        }
        frame(left: 0.9, right: 0.85)
        XCTAssertEqual(tracker.side, .left)
        frame(left: 0.9, right: 0.95)
        XCTAssertEqual(tracker.side, .left, "within the margin: no flip")
        frame(left: 0.9, right: 1.0)
        XCTAssertEqual(tracker.side, .right)
        frame(left: 0.95, right: 0.9)
        XCTAssertEqual(tracker.side, .right)
    }

    /// Side-view push-up facing +x, left side nearer. `hipDrop` pushes the hip below the line (px).
    private func sidePushUp(hipDrop: Double, elbowBend: Double = 0) -> [PoseKeypoint] {
        var k = [PoseKeypoint](repeating: kp(0, 0, 0.5), count: 17)
        let pts: [(Int, Double, Double)] = [
            (0, 580, 395), (3, 560, 390), (5, 500, 400), (7, 500 - elbowBend, 480), (9, 500, 560),
            (11, 300, 450 + hipDrop), (13, 200, 475), (15, 100, 500),
        ]
        for (i, x, y) in pts {
            k[i] = kp(x, y)
            k[i + (i == 0 ? 0 : 1)] = kp(x, y, i == 0 ? 0.9 : 0.6)
        }
        return k
    }

    private func pushUpRep(_ tracker: FormWarningTracker, hipDrop: Double, frame: Int, bend: Double = 60) -> FormRepReport {
        tracker.observe(frameIndex: frame, coco17: sidePushUp(hipDrop: hipDrop), phase: "descending")
        tracker.beginRep()
        tracker.observe(frameIndex: frame + 1, coco17: sidePushUp(hipDrop: hipDrop, elbowBend: bend), phase: "bottom")
        tracker.recordCurrentFrame()
        return tracker.finishRep(repIndex: frame / 2 + 1)
    }

    func testPushUpHipSagPikeAndDelivery() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        let clean = pushUpRep(tracker, hipDrop: 0, frame: 0)
        XCTAssertEqual(clean.warnings, [])
        XCTAssertEqual(clean.side, "left")
        _ = tracker.drainEvents()

        // 우선: spoken right away.
        let sag = pushUpRep(tracker, hipDrop: 40, frame: 2)
        XCTAssertEqual(sag.warnings, ["pushup_hip_sag"], "\(sag.metrics2D)")
        XCTAssertEqual(sag.spoken, "pushup_hip_sag")
        XCTAssertEqual(tracker.drainEvents(), [FormFeedbackEvent(key: "pushup_hip_sag", n: 1, silent: false)])

        // 개선 (pike): silent the first time, and praise_fixed because the sag is gone.
        let pike1 = pushUpRep(tracker, hipDrop: -50, frame: 4)
        XCTAssertEqual(pike1.warnings, ["pushup_hip_pike"], "\(pike1.metrics2D)")
        XCTAssertEqual(pike1.spoken, "praise_fixed")
        XCTAssertEqual(tracker.drainEvents(), [FormFeedbackEvent(key: "praise_fixed", n: nil, silent: false),
                                               FormFeedbackEvent(key: "pushup_hip_pike", n: 1, silent: true)])
        // Second rep in a row: spoken.
        let pike2 = pushUpRep(tracker, hipDrop: -50, frame: 6)
        XCTAssertEqual(pike2.spoken, "pushup_hip_pike")
        // Cooldown: the next 3 reps stay quiet even though it still fires.
        for i in 4..<7 {
            let r = pushUpRep(tracker, hipDrop: -50, frame: i * 2)
            XCTAssertEqual(r.warnings, ["pushup_hip_pike"])
            XCTAssertNil(r.spoken, "rep \(i + 1)")
        }
        XCTAssertEqual(pushUpRep(tracker, hipDrop: -50, frame: 14).spoken, "pushup_hip_pike")
        XCTAssertEqual(tracker.warningRepCounts["pushup_hip_pike"], 6)
    }

    func testBaselineAndTrendRules() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        // Baseline elbow_min ≈106° (60 px bend); a 15 px bend (≈159°) is shallow vs the baseline.
        for i in 0..<3 { _ = pushUpRep(tracker, hipDrop: 0, frame: i * 2) }
        XCTAssertFalse(tracker.reports.contains { !$0.warnings.isEmpty })
        let shallow = pushUpRep(tracker, hipDrop: 0, frame: 6, bend: 15)
        XCTAssertEqual(shallow.warnings, ["pushup_shallow"], "\(shallow.metrics2D)")
        _ = pushUpRep(tracker, hipDrop: 0, frame: 8, bend: 15)
        let fade = pushUpRep(tracker, hipDrop: 0, frame: 10, bend: 15)
        XCTAssertEqual(fade.warnings, ["pushup_shallow", "pushup_depth_fade"])  // 참고: silent
        XCTAssertNotEqual(fade.spoken, "pushup_depth_fade")
    }

    func testJudgeViewGatingAndRow() {
        let squat = FormWarningTracker(exercise: .squat)
        let base: [String: Double] = ["knee_min": 90, "torso_at_bottom": 30, "knee_max": 170, "hip_angle_max": 170]
        let history = Array(repeating: base, count: 3)
        var rep = base
        rep["knee_min"] = 120
        rep["torso_at_bottom"] = 45
        rep["knee_max"] = 150
        XCTAssertEqual(squat.judge(rep, history: history, repIndex: 4), ["squat_shallow", "squat_no_lockout"])
        XCTAssertEqual(squat.judge(rep, history: history + [rep, rep], repIndex: 6),
                       ["squat_shallow", "squat_no_lockout", "squat_lean_drift", "squat_depth_fade"])
        // Front view: only valgus (+ heel rise) run.
        XCTAssertEqual(squat.judge(["knee_min": 150, "front_view_fraction": 1, "knee_ankle_gap_ratio_min": 0.8],
                                   history: [], repIndex: 1), ["squat_knee_valgus"])
        XCTAssertEqual(squat.judge(["heel_rise_max": 0.1], history: [], repIndex: 1), ["squat_heel_rise"])
        XCTAssertEqual(FormWarningTracker.median([3, 1, 2]), 2)

        let row = FormWarningTracker(exercise: .barbellRow)
        let rowBase: [String: Double] = ["torso_mean": 60, "elbow_behind_max": 0.3]
        XCTAssertEqual(row.judge(["torso_min": 40, "torso_max": 60, "torso_mean": 45, "elbow_behind_max": 0.1,
                                  "ear_shoulder_drop": 0.5],
                                 history: Array(repeating: rowBase, count: 3), repIndex: 4),
                       ["row_torso_swing", "row_standing_up", "row_short_pull"])  // shrug off by default
        row.row.shrugEnabled = true
        XCTAssertEqual(row.judge(["ear_shoulder_drop": 0.5], history: [], repIndex: 1), ["row_shrug"])
        XCTAssertEqual(row.judge(["front_view_fraction": 1], history: [], repIndex: 1), ["setup_side_view"])
    }

    func testDistanceBehindTorso() throws {
        // Hinged 45°, facing +x: an elbow up-and-back of the trunk line is behind (> 0).
        let hip = kp(0, 0), shoulder = kp(100, -100)
        XCTAssertGreaterThan(try XCTUnwrap(FormGeometry.distanceBehindTorso2D(point: kp(0, -100), shoulder: shoulder, hip: hip, facing: 1)), 0)
        XCTAssertLessThan(try XCTUnwrap(FormGeometry.distanceBehindTorso2D(point: kp(100, 0), shoulder: shoulder, hip: hip, facing: 1)), 0)
        XCTAssertLessThan(try XCTUnwrap(FormGeometry.distanceBehindTorso2D(point: kp(0, -100), shoulder: shoulder, hip: hip, facing: -1)), 0)
    }

    func testHeelRiseFromFeet() throws {
        let tracker = FormWarningTracker(exercise: .squat)
        func feet(heelY: Double) -> FootKeypoints {
            FootKeypoints(leftBigToe: kp(150, 520), rightBigToe: kp(150, 520, 0.5), leftSmallToe: kp(140, 520),
                          rightSmallToe: kp(140, 520, 0.5), leftHeel: kp(90, heelY), rightHeel: kp(90, heelY, 0.5))
        }
        let coco = sidePushUp(hipDrop: 0)  // left side confident; knee (200,475) – ankle (100,500)
        tracker.observe(frameIndex: 0, coco17: coco, feet: feet(heelY: 520), phase: "descending")
        tracker.beginRep()
        tracker.observe(frameIndex: 1, coco17: coco, feet: feet(heelY: 500), phase: "bottom")
        let report = tracker.finishRep(repIndex: 1)
        XCTAssertEqual(try XCTUnwrap(report.metrics2D["heel_rise_max"]), 20 / hypot(100, 25), accuracy: 1e-9)
        XCTAssertTrue(report.warnings.contains("squat_heel_rise"))
    }

    func testTrackingEvents() {
        let tracker = FormWarningTracker(exercise: .squat)
        var missing = sidePushUp(hipDrop: 0)
        for i in 5...16 { missing[i].confidence = 0.1 }
        for f in 0..<tracker.common.setupFullBodyFrames {
            tracker.observe(frameIndex: f, coco17: missing, phase: "unknown")
        }
        XCTAssertEqual(tracker.drainEvents().map(\.key), ["setup_full_body"])
        _ = pushUpRep(tracker, hipDrop: 0, frame: 100)
        _ = tracker.drainEvents()
        for f in 200..<(200 + tracker.common.trackingLostFrames + 5) {
            tracker.observe(frameIndex: f, coco17: missing, phase: "unknown")
        }
        XCTAssertEqual(tracker.drainEvents().map(\.key), ["tracking_lost"])
    }
}
