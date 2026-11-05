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

    func testCameraUpFromGravity() {
        let upright = FormGeometry.cameraUp(gravity: [0, -1, 0], frontCamera: false)
        XCTAssertEqual(simd_length(upright - FormGeometry.up3D), 0, accuracy: 1e-12)
        XCTAssertEqual(simd_length(FormGeometry.cameraUp(gravity: [0, -1, 0], frontCamera: true) - FormGeometry.up3D), 0, accuracy: 1e-12)
        // Back camera, top of the phone tilted away from the user by 20 deg: gravity gains -z (into the screen).
        let t = 20.0 * .pi / 180
        let tilted = FormGeometry.cameraUp(gravity: [0, -cos(t), -sin(t)], frontCamera: false)
        XCTAssertEqual(tilted.y, -cos(t), accuracy: 1e-12)
        XCTAssertEqual(tilted.z, -sin(t), accuracy: 1e-12)
        // Phone rolled: image x flips with the front camera mirror.
        XCTAssertEqual(FormGeometry.cameraUp(gravity: [0.5, -0.866, 0], frontCamera: false).x,
                       -FormGeometry.cameraUp(gravity: [0.5, -0.866, 0], frontCamera: true).x, accuracy: 1e-12)
    }

    /// partial3D: a NaN (untrusted) knee drops only the knee-dependent metrics; trunk metrics stay.
    func testPartial3DDropsOnlyMetricsOfInvalidJoints() throws {
        let tracker = FormWarningTracker(exercise: .squat)
        let coco = sidePushUp(hipDrop: 0)
        var pose = standing3D(lean: 20, kneeTheta: 30)
        pose[5] = SIMD3(repeating: .nan)  // left knee untrusted
        pose[2] = SIMD3(repeating: .nan)
        tracker.observe(frameIndex: 0, coco17: coco, pose3D: pose, pose3DState: .partial3D, phase: "descending")
        tracker.beginRep()
        tracker.observe(frameIndex: 1, coco17: coco, pose3D: pose, pose3DState: .partial3D, phase: "bottom")
        tracker.recordCurrentFrame()
        let report = tracker.finishRep(repIndex: 1)
        XCTAssertEqual(try XCTUnwrap(report.metrics3D["torso_max"]), 20, accuracy: 1e-9)
        XCTAssertNil(report.metrics3D["knee_min"])
        XCTAssertNil(report.metrics3D["hip_angle_max"])
        XCTAssertEqual(report.formSource, "2d")
        XCTAssertEqual(report.states3D, ["partial_3d": 2])
        XCTAssertEqual(tracker.sessionBad3DFrames, 0)
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

    func testFeedbackDefaultAndPerKeyFlag() {
        XCTAssertEqual(RTMPoseModel.active, .coco17)
        // Default: every key with a Flutter line is sent (bench press / deadlift keys wait for theirs),
        // except the high-false-alarm keys (D-M-04).
        let delivered = FormWarningTracker.allKeys.subtracting(FormWarningTracker.keysWithoutFlutterLines)
            .subtracting(FormWarningTracker.quietByDefault)
        XCTAssertEqual(FormWarningTracker.quietByDefault.subtracting(FormWarningTracker.allKeys), [], "real key names")
        XCTAssertTrue(delivered.isDisjoint(with: ["squat_no_lockout", "squat_knee_valgus", "pushup_no_lockout",
                                                  "pushup_hip_pike", "pushup_shallow", "pushup_head_up"]))
        XCTAssertEqual(FormWarningTracker(exercise: .squat).common.enabledFeedbackKeys, delivered)
        XCTAssertEqual(FormWarningTracker(exercise: .barbellRow).common.enabledFeedbackKeys,
                       delivered.union(["setup_side_view"]))
        let defaultTracker = FormWarningTracker(exercise: .pushUp)
        XCTAssertEqual(defaultTracker.common.enabledFeedbackKeys, delivered)
        _ = pushUpRep(defaultTracker, hipDrop: 0, frame: 0)
        _ = pushUpRep(defaultTracker, hipDrop: 70, frame: 2)
        XCTAssertEqual(defaultTracker.drainEvents().map(\.key), ["praise_good", "pushup_hip_sag"],
                       "sent by default (the clean first rep is praised)")
        // A quiet key (D-M-04) is judged and logged but not sent by default.
        let pikes = [pushUpRep(defaultTracker, hipDrop: -50, frame: 4), pushUpRep(defaultTracker, hipDrop: -50, frame: 6)]
        XCTAssertEqual(pikes.map(\.warnings), [["pushup_hip_pike"], ["pushup_hip_pike"]])
        XCTAssertFalse(defaultTracker.drainEvents().map(\.key).contains("pushup_hip_pike"))

        // A key left out is still judged and logged, just not sent.
        let tracker = FormWarningTracker(exercise: .pushUp)
        tracker.common.enabledFeedbackKeys = ["setup_full_body", "tracking_lost"]
        _ = pushUpRep(tracker, hipDrop: 0, frame: 0)
        let sag = pushUpRep(tracker, hipDrop: 70, frame: 2)
        XCTAssertEqual(sag.warnings, ["pushup_hip_sag"], "still judged and logged")
        XCTAssertNil(sag.spoken)
        XCTAssertEqual(tracker.drainEvents(), [])
        // Only the enabled key is sent; pike stays log-only.
        tracker.common.enabledFeedbackKeys = ["pushup_hip_sag"]
        _ = pushUpRep(tracker, hipDrop: 70, frame: 4)
        XCTAssertEqual(tracker.drainEvents(), [FormFeedbackEvent(key: "pushup_hip_sag", n: nil)])
        let pike = pushUpRep(tracker, hipDrop: -50, frame: 6)
        XCTAssertEqual(pike.warnings, ["pushup_hip_pike"])
        XCTAssertEqual(tracker.drainEvents(), [], "praise_fixed and pike not enabled")
    }

    /// form3DRequired: keys come from the 3D judgement; a rep without usable 3D says nothing (never the 2D result),
    /// the 2D judgement stays in warnings2D for comparison.
    func testForm3DRequiredUses3DAndNeverFallsBackTo2D() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        tracker.common.enabledFeedbackKeys = FormWarningTracker.allKeys
        tracker.common.form3DRequired = true
        // Plank along +z, face down (+y is the floor side); pelvis `sag` below the thorax–ankle line.
        func plank(_ sag: Double) -> [SIMD3<Double>] {
            var j = [SIMD3<Double>](repeating: .zero, count: 17)
            j[1] = [-0.1, sag, 0]; j[4] = [0.1, sag, 0]; j[0] = [0, sag, 0]
            j[8] = [0, 0, -0.5]; j[7] = [0, sag / 2, -0.25]; j[10] = [0, 0.05, -0.75]
            j[3] = [-0.1, 0, 1.0]; j[6] = [0.1, 0, 1.0]
            j[2] = [-0.1, sag / 2, 0.5]; j[5] = [0.1, sag / 2, 0.5]
            j[11] = [0.15, 0, -0.5]; j[12] = [0.15, 0.25, -0.5]; j[13] = [0.15, 0.5, -0.5]
            j[14] = [-0.15, 0, -0.5]; j[15] = [-0.15, 0.25, -0.5]; j[16] = [-0.15, 0.5, -0.5]
            return j
        }
        func rep(_ frame: Int, hipDrop2D: Double, pose3D: [SIMD3<Double>]?, state: Pose3DState) -> FormRepReport {
            tracker.observe(frameIndex: frame, coco17: sidePushUp(hipDrop: hipDrop2D), pose3D: pose3D, pose3DState: state, phase: "descending")
            tracker.beginRep()
            tracker.observe(frameIndex: frame + 1, coco17: sidePushUp(hipDrop: hipDrop2D, elbowBend: 60), pose3D: pose3D,
                            pose3DState: state, phase: "bottom")
            tracker.recordCurrentFrame()
            return tracker.finishRep(repIndex: frame / 2 + 1)
        }
        let warming = rep(0, hipDrop2D: 70, pose3D: nil, state: .warmingUp)
        XCTAssertEqual(warming.formSource, "3d_unavailable")
        XCTAssertEqual(warming.warnings, [])
        XCTAssertNil(warming.warnings3D)
        XCTAssertEqual(warming.warnings2D, ["pushup_hip_sag"], "2D still judged for comparison")
        XCTAssertEqual(warming.states3D, ["warming_up": 2])
        XCTAssertEqual(tracker.drainEvents(), [], "no posture key from 2D")

        let sag3D = rep(2, hipDrop2D: 0, pose3D: plank(0.3), state: .ok)
        XCTAssertEqual(sag3D.formSource, "3d")
        XCTAssertEqual(sag3D.warnings, ["pushup_hip_sag"], "\(sag3D.metrics3D)")
        XCTAssertEqual(sag3D.warnings2D, [])
        XCTAssertEqual(try XCTUnwrap(sag3D.metrics3D["hip_dev_max"]), 0.2, accuracy: 1e-9)

        let bad = rep(4, hipDrop2D: 0, pose3D: plank(0.3), state: .bad3D)
        XCTAssertEqual(bad.formSource, "3d_unavailable")
        XCTAssertEqual(bad.bad3DFrames, 2)
    }

    func testPushUpHipSagPikeAndDelivery() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        tracker.common.enabledFeedbackKeys = FormWarningTracker.allKeys
        let clean = pushUpRep(tracker, hipDrop: 0, frame: 0)
        XCTAssertEqual(clean.warnings, [])
        XCTAssertEqual(clean.side, "left")
        _ = tracker.drainEvents()

        // 우선: spoken right away.
        let sag = pushUpRep(tracker, hipDrop: 70, frame: 2)
        XCTAssertEqual(sag.warnings, ["pushup_hip_sag"], "\(sag.metrics2D)")
        XCTAssertEqual(sag.spoken, "pushup_hip_sag")
        XCTAssertEqual(tracker.drainEvents(), [FormFeedbackEvent(key: "pushup_hip_sag", n: nil)])

        // A different fault remains: delayed delivery must not turn it into correction praise.
        let pike1 = pushUpRep(tracker, hipDrop: -50, frame: 4)
        XCTAssertEqual(pike1.warnings, ["pushup_hip_pike"], "\(pike1.metrics2D)")
        XCTAssertNil(pike1.spoken)
        XCTAssertEqual(tracker.drainEvents(), [], "a remaining fault prevents praise even before its delivery")
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
        XCTAssertEqual(fade.warnings, ["pushup_shallow", "pushup_depth_fade"])  // 참고: set end only
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
        // Front view: only valgus (+ heel rise when enabled) run.
        XCTAssertEqual(squat.judge(["knee_min": 150, "front_view_fraction": 1, "knee_ankle_gap_ratio_min": 0.8],
                                   history: [], repIndex: 1), ["squat_knee_valgus"])
        XCTAssertEqual(squat.judge(["heel_rise_max": 0.1], history: [], repIndex: 1), [], "heel rise off by default")
        squat.squat.heelRiseEnabled = true
        XCTAssertEqual(squat.judge(["heel_rise_max": 0.1], history: [], repIndex: 1), ["squat_heel_rise"])
        XCTAssertEqual(FormWarningTracker.median([3, 1, 2]), 2)

        let row = FormWarningTracker(exercise: .barbellRow)
        let rowBase: [String: Double] = ["torso_mean": 60, "elbow_behind_max": 0.3]
        XCTAssertEqual(row.judge(["torso_min": 10, "torso_max": 60, "torso_mean": 45, "elbow_behind_max": 0.1,
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
        XCTAssertFalse(report.warnings.contains("squat_heel_rise"), "off by default; metric still logged")
    }

    func testTrackingEvents() {
        let tracker = FormWarningTracker(exercise: .squat)
        tracker.common.enabledFeedbackKeys = FormWarningTracker.allKeys
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

        // Never inside a rep: a loss during an open rep waits for the rep to end, and only if it lasts.
        tracker.observe(frameIndex: 300, coco17: sidePushUp(hipDrop: 0), phase: "top")
        tracker.beginRep()
        for f in 301..<(301 + tracker.common.trackingLostFrames + 10) {
            tracker.observe(frameIndex: f, coco17: missing, phase: "bottom")
            tracker.recordCurrentFrame()
        }
        XCTAssertEqual(tracker.drainEvents().map(\.key), [], "mid-rep: deferred")
        tracker.finishRep(repIndex: 2)
        _ = tracker.drainEvents()
        tracker.observe(frameIndex: 400, coco17: missing, phase: "top")
        XCTAssertEqual(tracker.drainEvents().map(\.key), ["tracking_lost"], "said right after the rep")
        // A short loss (< trackingLostFrames) says nothing.
        tracker.observe(frameIndex: 401, coco17: sidePushUp(hipDrop: 0), phase: "top")
        for f in 402..<(402 + tracker.common.trackingLostFrames - 1) { tracker.observe(frameIndex: f, coco17: missing, phase: "top") }
        tracker.observe(frameIndex: 500, coco17: sidePushUp(hipDrop: 0), phase: "top")
        XCTAssertEqual(tracker.drainEvents().map(\.key), [])
    }

    /// 참고 keys go out once at set end (scope "set", n = reps in the set); per-set counts reset.
    func testSetEndSummaryScope() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        tracker.common.enabledFeedbackKeys = FormWarningTracker.allKeys
        func rep(_ frame: Int, topBend: Double) {
            tracker.observe(frameIndex: frame, coco17: sidePushUp(hipDrop: 0, elbowBend: topBend), phase: "top")
            tracker.beginRep()
            tracker.observe(frameIndex: frame + 1, coco17: sidePushUp(hipDrop: 0, elbowBend: 60), phase: "bottom")
            tracker.recordCurrentFrame()
            tracker.finishRep(repIndex: frame / 2 + 1)
        }
        for i in 0..<3 { rep(i * 2, topBend: 0) }
        rep(6, topBend: 30)  // top elbow ≈139° vs set max 180°: no lockout
        rep(8, topBend: 30)
        XCTAssertEqual(tracker.reports.last?.warnings, ["pushup_no_lockout"])
        XCTAssertEqual(tracker.drainEvents().map(\.key), ["praise_good"], "참고 is not sent per rep; the clean first rep is praised")
        let counts = tracker.endSet()
        XCTAssertEqual(counts, ["pushup_no_lockout": 2])
        XCTAssertEqual(tracker.drainEvents(), [FormFeedbackEvent(key: "pushup_no_lockout", n: 2, scope: .set)])
        XCTAssertEqual(tracker.endSet(), [:], "counts are per set")
        XCTAssertEqual(tracker.drainEvents(), [])
        XCTAssertEqual(tracker.warningRepCounts["pushup_no_lockout"], 2, "session counts stay")
        // Keys turned off: judged and counted, but nothing is sent.
        let quiet = FormWarningTracker(exercise: .pushUp)
        quiet.common.enabledFeedbackKeys = ["setup_full_body", "tracking_lost"]
        for i in 0..<3 { _ = pushUpRep(quiet, hipDrop: 0, frame: i * 2) }
        quiet.observe(frameIndex: 6, coco17: sidePushUp(hipDrop: 0, elbowBend: 30), phase: "top")
        quiet.beginRep()
        quiet.observe(frameIndex: 7, coco17: sidePushUp(hipDrop: 0, elbowBend: 60), phase: "bottom")
        quiet.recordCurrentFrame()
        quiet.finishRep(repIndex: 4)
        XCTAssertEqual(quiet.endSet(), ["pushup_no_lockout": 1])
        XCTAssertEqual(quiet.drainEvents(), [])
    }

    func testAngleWrap() {
        XCTAssertEqual(FormGeometry.wrapDegrees(358), -2, accuracy: 1e-9)
        XCTAssertEqual(FormGeometry.wrapDegrees(-181), 179, accuracy: 1e-9)
        XCTAssertEqual(FormGeometry.wrapDegrees(-180), 180)
        XCTAssertEqual(FormGeometry.wrapDegrees(180), 180)
        XCTAssertEqual(FormGeometry.unwrapDegrees([170, 179, -179, -170]), [170, 179, 181, 190])
        XCTAssertEqual(FormGeometry.unwrapDegrees([-170, -179, 179]), [-170, -179, -181])
    }

    func testTorsoSwingAcrossPlusMinus180() throws {
        // Trunk pointing almost straight down crosses ±180 frame to frame: a 20° swing, not ~359°.
        let tracker = FormWarningTracker(exercise: .barbellRow)
        let frames = [170.0, 179, -179, -170].enumerated().map { i, t in
            var f = FormFrameSample(frame: i, phase: "", side: .left)
            f.torso = t
            return f
        }
        let m = tracker.metrics2D(frames, isFirstRep: false)
        XCTAssertEqual(try XCTUnwrap(m["torso_max"]) - (try XCTUnwrap(m["torso_min"])), 20, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m["torso_mean"]), 180, accuracy: 1e-9)
        XCTAssertFalse(tracker.judge(m, history: [], repIndex: 1).contains("row_torso_swing"))
    }
}

/// Scoped overlay table (display only): inactive/withheld evidence never defaults to assessed normal.
extension FormWarningsTests {
    func testOverlayTableMatchesTheRulesAndDrawnSegments() {
        let drawn = Set(OverlaySegment.edges)
        for (exercise, rules) in OverlayRule.table {
            let keys = (FormWarningTracker.rules[exercise] ?? []).map(\.key)
            let tracker = FormWarningTracker(exercise: exercise)
            for rule in rules {
                XCTAssertTrue(keys.contains(rule.key), "\(rule.key) is not a \(exercise) rule")
                XCTAssertFalse(rule.key.contains("head"), "no head is drawn: \(rule.key) has nothing to colour")
                XCTAssertNotEqual(rule.threshold(tracker), rule.normal, "\(rule.key): normal == threshold")
                for side in [FormSide.left, .right] {
                    let segs = rule.segments(side)
                    XCTAssertFalse(segs.isEmpty, rule.key)
                    XCTAssertTrue(Set(segs).isSubset(of: drawn), "\(rule.key) colours a segment the overlay does not draw")
                }
            }
        }
        // Body only: no face / ear / nose joint in any drawn segment.
        XCTAssertTrue(OverlaySegment.edges.allSatisfy { if case let .edge(a, b) = $0 { a > 4 && b > 4 } else { false } })
        // The request's examples: hip sag/pike = shoulder–hip–knee–ankle, valgus = both legs, swing = shoulder–hip.
        let rule = { (e: FormExercise, k: String) in OverlayRule.table[e]!.first { $0.key == k }! }
        XCTAssertEqual(Set(rule(.pushUp, "pushup_hip_pike").segments(.left)), [.edge(5, 11), .edge(11, 13), .edge(13, 15)])
        XCTAssertEqual(Set(rule(.squat, "squat_knee_valgus").segments(.right)), [.edge(11, 13), .edge(13, 15), .edge(12, 14), .edge(14, 16)])
        XCTAssertEqual(rule(.barbellRow, "row_torso_swing").segments(.right), [.edge(6, 12)])
        XCTAssertEqual(Set(rule(.pushUp, "pushup_no_lockout").segments(.right)), [.edge(6, 8), .edge(8, 10)])
    }

    func testOverlaySeverityRamp() {
        XCTAssertEqual(OverlayRule.severity(0, normal: 0, threshold: 0.14), 0)
        XCTAssertEqual(OverlayRule.severity(0.07, normal: 0, threshold: 0.14), 0.5, accuracy: 1e-12)
        XCTAssertEqual(OverlayRule.severity(0.3, normal: 0, threshold: 0.14), 1, "past the threshold stays red")
        XCTAssertEqual(OverlayRule.severity(-0.2, normal: 0, threshold: 0.14), 0, "the other direction is not this rule")
        XCTAssertEqual(OverlayRule.severity(-0.04, normal: 0, threshold: -0.08), 0.5, accuracy: 1e-12, "pike: negative threshold")
        XCTAssertEqual(OverlayRule.severity(1.125, normal: 1.25, threshold: 1.0), 0.5, accuracy: 1e-12, "valgus: smaller ratio = worse")
    }

    func testLiveSeverityFollowsTheHipLineAndDimsWithoutEvidence() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        func state(hipDrop: Double) -> OverlayState {
            tracker.observe(frameIndex: 0, coco17: sidePushUp(hipDrop: hipDrop), phase: "top")
            return tracker.liveSeverity()
        }
        let chain: [OverlaySegment] = [.edge(5, 11), .edge(11, 13), .edge(13, 15)]
        for seg in chain { XCTAssertEqual(try XCTUnwrap(state(hipDrop: 0).severity[seg]), 0, accuracy: 1e-9) }
        // hipDrop 30 px ≈ 0.07 of the shoulder–ankle line (half of the 0.14 sag threshold); 70 px is past it.
        XCTAssertEqual(try XCTUnwrap(state(hipDrop: 30).severity[.edge(5, 11)]), 0.504, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(state(hipDrop: 70).severity[.edge(11, 13)]), 1)
        XCTAssertEqual(try XCTUnwrap(state(hipDrop: -17).severity[.edge(13, 15)]), 0.5, accuracy: 0.02, "pike half way")
        XCTAssertTrue(state(hipDrop: 0).uncertain.isEmpty)

        // 3D required but unavailable: every segment withheld/neutral, no measured severity.
        let required = FormWarningTracker(exercise: .pushUp)
        required.common.form3DRequired = true
        required.observe(frameIndex: 0, coco17: sidePushUp(hipDrop: 70), pose3DState: .warmingUp, phase: "top")
        let dim = required.liveSeverity()
        XCTAssertTrue(dim.severity.isEmpty)
        XCTAssertEqual(dim.uncertain, Set(OverlaySegment.edges))
    }

    func testOverlayTrackSmoothsOnlyWithinTheSameObservationStatus() {
        var track = OverlaySeverityTrack()
        let seg = OverlaySegment.edge(5, 11)
        let known = [seg: OverlayObservation(measured: ["geometry": .frameGeometry])]
        XCTAssertEqual(track.update(OverlayState(severity: [seg: 0], observations: known), at: 0)[seg]?.severity, 0)
        let mid = track.update(OverlayState(severity: [seg: 1], observations: known), at: 0.2)[seg]
        XCTAssertEqual(mid?.severity ?? -1, 1 - exp(-1), accuracy: 1e-9)
        let empty = track.update(OverlayState(), at: 0.4)[seg]
        XCTAssertEqual(empty?.severity, 0, "old issue must not leak across lost evidence")
        XCTAssertEqual(empty?.status, .unassessed)
        XCTAssertEqual(empty?.style(rawJointUncertain: false), .withheld)
        XCTAssertEqual(empty?.opacity, 0.4)
        let relative = [seg: OverlayObservation(measured: ["lockout": .selfRelative])]
        let noDrift = track.update(OverlayState(severity: [seg: 0], observations: relative), at: 0.6)[seg]
        XCTAssertEqual(noDrift?.status, .relativeConsistency)
        XCTAssertEqual(noDrift?.style(rawJointUncertain: false), .relative)
    }

}

/// praise_good: positive feedback from the real judgement — only for reps judged on usable data with nothing fired.
extension FormWarningsTests {
    func testPraiseGoodOnACleanJudgedRep() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        let report = pushUpRep(tracker, hipDrop: 0, frame: 0)
        XCTAssertEqual(report.warnings, [])
        XCTAssertEqual(report.spoken, "praise_good")
        XCTAssertEqual(tracker.drainEvents(), [FormFeedbackEvent(key: "praise_good", n: nil)])
        // A rep with a warning says the warning, not praise.
        _ = pushUpRep(tracker, hipDrop: 70, frame: 2)
        XCTAssertEqual(tracker.drainEvents().map(\.key), ["pushup_hip_sag"])
    }

    func testNoPraiseWhenTheRepCouldNotBeJudged() {
        // 3D required but the rep had no usable 3D (warming up): no posture keys and no praise.
        let required = FormWarningTracker(exercise: .pushUp)
        required.common.form3DRequired = true
        required.observe(frameIndex: 0, coco17: sidePushUp(hipDrop: 0), pose3DState: .warmingUp, phase: "descending")
        required.beginRep()
        required.observe(frameIndex: 1, coco17: sidePushUp(hipDrop: 0, elbowBend: 60), pose3DState: .warmingUp, phase: "bottom")
        required.recordCurrentFrame()
        let r = required.finishRep(repIndex: 1)
        XCTAssertEqual(r.formSource, "3d_unavailable")
        XCTAssertNil(r.spoken)
        XCTAssertTrue(required.drainEvents().filter { $0.key == "praise_good" }.isEmpty)

        // 2D: the ankles (needed for the hip line) are not visible → the hip rules cannot run → no praise.
        let hidden = FormWarningTracker(exercise: .pushUp)
        var k = sidePushUp(hipDrop: 0)
        k[15].confidence = 0.05; k[16].confidence = 0.05
        hidden.observe(frameIndex: 0, coco17: k, phase: "descending")
        hidden.beginRep()
        hidden.observe(frameIndex: 1, coco17: k, phase: "bottom")
        hidden.recordCurrentFrame()
        XCTAssertNil(hidden.finishRep(repIndex: 1).spoken)
        XCTAssertTrue(hidden.drainEvents().filter { $0.key == "praise_good" }.isEmpty)
    }

    func testCorrectionPraiseRequiresFullyObservedClean3D() {
        for state: Pose3DState in [.bad3D, .partial3D, .warmingUp, .trackingLost, .ok] {
            let tracker = FormWarningTracker(exercise: .pushUp)
            // Establish the same real warning history through the public evaluator path.
            _ = pushUpRep(tracker, hipDrop: 70, frame: 0)
            XCTAssertEqual(tracker.drainEvents().map(\.key), ["pushup_hip_sag"])
            tracker.common.form3DRequired = true
            var j = [SIMD3<Double>](repeating: .zero, count: 17)
            j[1] = [-0.1, 0, 0]; j[4] = [0.1, 0, 0]
            j[8] = [0, 0, -0.5]; j[7] = [0, 0, -0.25]; j[10] = [0, 0, -0.75]
            j[3] = [-0.1, 0, 1]; j[6] = [0.1, 0, 1]
            j[2] = [-0.1, 0, 0.5]; j[5] = [0.1, 0, 0.5]
            j[11] = [0.15, 0, -0.5]; j[12] = [0.15, 0.25, -0.5]; j[13] = [0.15, 0.5, -0.5]
            j[14] = [-0.15, 0, -0.5]; j[15] = [-0.15, 0.25, -0.5]; j[16] = [-0.15, 0.5, -0.5]
            let pose: [SIMD3<Double>]? = state == .warmingUp || state == .trackingLost ? nil : j
            tracker.observe(frameIndex: 2, coco17: sidePushUp(hipDrop: 0), pose3D: pose, pose3DState: state, phase: "descending")
            tracker.beginRep()
            tracker.observe(frameIndex: 3, coco17: sidePushUp(hipDrop: 0, elbowBend: 60), pose3D: pose, pose3DState: state, phase: "bottom")
            tracker.recordCurrentFrame()
            let report = tracker.finishRep(repIndex: 2)
            XCTAssertEqual(report.warnings, [], "\(state)")
            XCTAssertEqual(report.spoken, state == .ok ? "praise_good" : nil, "\(state)")
            XCTAssertEqual(tracker.drainEvents().map(\.key), state == .ok ? ["praise_good"] : [], "\(state)")
        }
    }

    func testPraiseGoodCooldown() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        var praised: [Int] = []
        for rep in 1...9 {
            let report = pushUpRep(tracker, hipDrop: 0, frame: (rep - 1) * 2)
            if report.spoken == "praise_good" { praised.append(rep) }
        }
        XCTAssertEqual(praised, [1, 5, 9], "at most once per cooldownReps (3) + 1 reps")
    }
}

extension FormWarningsTests {
    /// Test-mode caption: every fired key (reference / log-only marked), what was sent, validity and a key metric.
    func testDebugCaptionShowsTheRealJudgement() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        tracker.common.enabledFeedbackKeys = ["pushup_hip_sag"]
        let report = pushUpRep(tracker, hipDrop: 70, frame: 0)
        let caption = report.debugCaption(sent: tracker.drainEvents().map(\.key), enabled: tracker.common.enabledFeedbackKeys)
        XCTAssertTrue(caption.hasPrefix("#1 2D"), caption)
        XCTAssertTrue(caption.contains("울림: pushup_hip_sag"), caption)
        XCTAssertTrue(caption.contains("보냄: pushup_hip_sag"), caption)
        XCTAssertTrue(caption.contains("엉덩이 선 최소"), caption)
        let clean = pushUpRep(tracker, hipDrop: 0, frame: 2)
        XCTAssertTrue(clean.debugCaption(sent: [], enabled: []).contains("울림: 없음"))
    }
}


/// Assessment semantics only: synthetic geometry exercises the actual tracker/display path, not posture accuracy.
extension FormWarningsTests {
    func testOverlayUniformlyBentInitialRepsAreOnlySelfRelativeConsistency() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        for rep in 0..<3 {
            tracker.observe(frameIndex: rep*2, coco17: sidePushUp(hipDrop: 0, elbowBend: 60), phase: "top")
            tracker.beginRep()
            tracker.observe(frameIndex: rep*2+1, coco17: sidePushUp(hipDrop: 0, elbowBend: 60), phase: "bottom")
            tracker.recordCurrentFrame()
            _ = tracker.finishRep(repIndex: rep+1)
        }
        XCTAssertLessThan(try XCTUnwrap(tracker.reports.last?.metrics2D["elbow_max"]), 150)
        tracker.observe(frameIndex: 7, coco17: sidePushUp(hipDrop: 0, elbowBend: 60), phase: "top")
        let state = tracker.liveSeverity(), seg = OverlaySegment.edge(5, 7)
        XCTAssertEqual(state.severity[seg], 0, "unchanged arithmetic: no decrease from this bent set's own best")
        XCTAssertEqual(state.observations[seg]?.measured["pushup_no_lockout"], .selfRelative)
        var track = OverlaySeverityTrack()
        XCTAssertEqual(state.observations[seg]?.displayStatus, .relativeConsistency)
        XCTAssertEqual(track.update(state, at: 0)[seg]?.style(rawJointUncertain: false), .relative,
                       "uniformly poor initialization cannot certify extension or correct form")
        tracker.observe(frameIndex: 8, coco17: sidePushUp(hipDrop: 0, elbowBend: 60), phase: "bottom")
        let bottom = tracker.liveSeverity()
        XCTAssertEqual(bottom.observations[seg]?.measured["pushup_shallow"], .selfRelative)
        XCTAssertEqual(bottom.observations[seg]?.displayStatus, .relativeConsistency)
        XCTAssertEqual(track.update(bottom, at: 1)[seg]?.style(rawJointUncertain: false), .relative)
    }

    func testOverlayMissingBaselineAndWrongPhaseOrViewAreWithheld() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        let arm = OverlaySegment.edge(5, 7)
        tracker.observe(frameIndex: 0, coco17: sidePushUp(hipDrop: 0), phase: "bottom")
        let state = tracker.liveSeverity()
        XCTAssertEqual(state.observations[arm]?.withheld["pushup_shallow"], [.baseline])
        XCTAssertEqual(state.observations[arm]?.inactive["pushup_no_lockout"], .phase)
        XCTAssertNil(state.severity[arm])
        tracker.observe(frameIndex: 1, coco17: sidePushUp(hipDrop: 0), phase: "descending")
        XCTAssertEqual(tracker.liveSeverity().observations[arm]?.displayStatus, .unassessed,
                       "both arm rules are deliberately out of phase")
        var front = sidePushUp(hipDrop: 0)
        front[6].x += 300
        tracker.observe(frameIndex: 1, coco17: front, phase: "top")
        let view = tracker.liveSeverity()
        XCTAssertEqual(view.observations[arm]?.inactive["pushup_no_lockout"], .view)
        XCTAssertTrue(view.severity.isEmpty)
        var track = OverlaySeverityTrack()
        XCTAssertEqual(track.update(view, at: 0)[arm]?.style(rawJointUncertain: false), .withheld)
    }

    func testOverlayMissingHipCannotBeErasedByMeasuredNormalKnee() throws {
        let tracker = FormWarningTracker(exercise: .squat)
        tracker.common.form3DRequired = true
        var pose = standing3D(kneeTheta: 5)
        pose[11] = SIMD3(repeating: .nan)  // selected hip angle requires this shoulder, knee does not
        tracker.observe(frameIndex: 0, coco17: sidePushUp(hipDrop: 0), pose3D: pose, pose3DState: .partial3D, phase: "top")
        let state = tracker.liveSeverity(), seg = OverlaySegment.edge(11, 13)
        XCTAssertEqual(state.severity[seg], 0)
        XCTAssertEqual(state.observations[seg]?.measured["squat_no_lockout"], .selfRelative)
        XCTAssertEqual(state.observations[seg]?.withheld["squat_no_lockout"], [.missingQuantity])
        XCTAssertTrue(state.uncertain.contains(seg))
        var track = OverlaySeverityTrack()
        XCTAssertEqual(track.update(state, at: 0)[seg]?.style(rawJointUncertain: false), .withheld)
    }

    func testOverlayKnownKneeIssueSurvivesMissingHipWithPartialEvidence() throws {
        let tracker = FormWarningTracker(exercise: .squat)
        tracker.common.form3DRequired = true
        tracker.observe(frameIndex: 0, coco17: sidePushUp(hipDrop: 0), pose3D: standing3D(kneeTheta: 5), pose3DState: .ok, phase: "top")
        tracker.beginRep()
        var pose = standing3D(kneeTheta: 40)
        pose[11] = SIMD3(repeating: .nan)
        tracker.observe(frameIndex: 1, coco17: sidePushUp(hipDrop: 0), pose3D: pose, pose3DState: .partial3D, phase: "top")
        let state = tracker.liveSeverity(), seg = OverlaySegment.edge(11, 13)
        XCTAssertEqual(state.severity[seg], 1)
        XCTAssertTrue(state.uncertain.contains(seg))
        XCTAssertEqual(state.observations[seg]?.displayStatus, .partial)
        var track = OverlaySeverityTrack()
        let shade = try XCTUnwrap(track.update(state, at: 0)[seg])
        XCTAssertEqual(shade.severity, 1)
        XCTAssertEqual(shade.style(rawJointUncertain: false), .limitedIssue)
        XCTAssertEqual(shade.style(rawJointUncertain: true), .withheld, "raw wrist/source guard wins even over red")
    }

    func testOverlayDifferentRulesKeepTheirOwnEvidenceAndMissingSegmentsStayNeutral() throws {
        let tracker = FormWarningTracker(exercise: .barbellRow)
        let rules = try XCTUnwrap(OverlayRule.table[.barbellRow])
        let swing = try XCTUnwrap(rules.first { $0.key == "row_torso_swing" })
        let standing = try XCTUnwrap(rules.first { $0.key == "row_standing_up" })
        var state = OverlayState()
        state.record(swing, side: .left, value: .measured(0), threshold: swing.threshold(tracker))
        state.record(standing, side: .left, value: .unavailable(.missingQuantity), threshold: standing.threshold(tracker))
        let seg = OverlaySegment.edge(5, 11)
        XCTAssertEqual(state.severity[seg], 0)
        XCTAssertTrue(state.uncertain.contains(seg))
        XCTAssertEqual(state.observations[seg]?.withheld[standing.key], [.missingQuantity])
        XCTAssertEqual(state.observations[seg]?.measured[swing.key], .withinRepChange)
        var track = OverlaySeverityTrack()
        let shade = track.update(state, at: 0)
        XCTAssertEqual(shade[seg]?.style(rawJointUncertain: false), .withheld)
        XCTAssertEqual(shade[.edge(6, 12)]?.status, .unassessed)
    }

    func testOverlayValidFrameGeometryIsScopedAndQuietDeliveryIsUnchanged() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        tracker.common.enabledFeedbackKeys = []
        tracker.observe(frameIndex: 0, coco17: sidePushUp(hipDrop: 0), phase: "top")
        let seg = OverlaySegment.edge(5, 11), state = tracker.liveSeverity()
        XCTAssertEqual(state.observations[seg]?.displayStatus, .observed)
        XCTAssertEqual(Set(state.observations[seg]?.measured.keys ?? Dictionary<String, OverlayObservationScope>().keys),
                       ["pushup_hip_sag", "pushup_hip_pike"])
        XCTAssertTrue(state.observations[seg]?.measured.values.allSatisfy { $0 == .frameGeometry } == true)
        var track = OverlaySeverityTrack()
        XCTAssertEqual(track.update(state, at: 0)[seg]?.style(rawJointUncertain: false), .observed)
        tracker.observe(frameIndex: 1, coco17: sidePushUp(hipDrop: 70), phase: "top")
        XCTAssertEqual(tracker.liveSeverity().severity[seg], 1, "quiet delivery never silently drops measurement")
        XCTAssertTrue(tracker.drainEvents().isEmpty)
        XCTAssertTrue(tracker.common.enabledFeedbackKeys.isEmpty)
    }
}


extension FormWarningsTests {
    func testOverlayUnknownViewIsWithheldUntilRowSessionGateIsVerified() throws {
        var missingFarShoulder = sidePushUp(hipDrop: 0)
        missingFarShoulder[6].confidence = 0
        let push = FormWarningTracker(exercise: .pushUp)
        push.observe(frameIndex: 0, coco17: missingFarShoulder, phase: "top")
        XCTAssertEqual(push.liveSeverity().observations[.edge(5, 7)]?.withheld["pushup_no_lockout"], [.viewUnknown])
        let squat = FormWarningTracker(exercise: .squat)
        squat.observe(frameIndex: 0, coco17: missingFarShoulder, phase: "top")
        XCTAssertEqual(squat.liveSeverity().observations[.edge(11, 13)]?.withheld["squat_no_lockout"], [.viewUnknown])
        let row = FormWarningTracker(exercise: .barbellRow)
        row.observe(frameIndex: 0, coco17: missingFarShoulder, phase: "ascending")
        row.beginRep()
        XCTAssertNil(row.sideView)
        XCTAssertEqual(row.liveSeverity().observations[.edge(5, 11)]?.withheld["row_torso_swing"], [.viewUnknown])
        row.common.sideViewMinFrames = 1
        row.common.sideViewWindowFrames = 1
        row.observe(frameIndex: 1, coco17: sidePushUp(hipDrop: 0), phase: "ascending")
        XCTAssertEqual(row.sideView, true)
        row.observe(frameIndex: 2, coco17: missingFarShoulder, phase: "ascending")
        XCTAssertEqual(row.sideView, true)
        XCTAssertEqual(row.liveSeverity().observations[.edge(5, 11)]?.measured["row_torso_swing"], .withinRepChange,
                       "an established row session gate remains available when this frame's view is missing")
    }
}


extension FormWarningsTests {
    func testOverlayBaselineNeedsTheRelevantMetricInEveryReferenceRep() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        for rep in 0..<3 {
            var coco = sidePushUp(hipDrop: 0, elbowBend: 60)
            if rep == 0 { coco[9].confidence = 0 }
            tracker.observe(frameIndex: rep*2, coco17: coco, phase: "top")
            tracker.beginRep()
            tracker.observe(frameIndex: rep*2+1, coco17: coco, phase: "bottom")
            tracker.recordCurrentFrame()
            _ = tracker.finishRep(repIndex: rep+1)
        }
        tracker.observe(frameIndex: 7, coco17: sidePushUp(hipDrop: 0, elbowBend: 60), phase: "bottom")
        let state = tracker.liveSeverity(), seg = OverlaySegment.edge(5, 7)
        XCTAssertEqual(state.observations[seg]?.withheld["pushup_shallow"], [.baseline],
                       "three completed reps do not imply three observed elbow references")
        XCTAssertNil(state.severity[seg])
    }
}


extension FormWarningsTests {
    func testCorrectionPraiseNeedsThePreviouslyWarnedRuleUnderCurrentGate() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        _ = pushUpRep(tracker, hipDrop: 70, frame: 0)
        XCTAssertEqual(tracker.drainEvents().map(\.key), ["pushup_hip_sag"])
        var front = sidePushUp(hipDrop: 0)
        front[6].x += 300
        tracker.observe(frameIndex: 2, coco17: front, phase: "top")
        tracker.beginRep()
        tracker.observe(frameIndex: 3, coco17: front, phase: "bottom")
        tracker.recordCurrentFrame()
        let r = tracker.finishRep(repIndex: 2)
        XCTAssertFalse(r.warnings.contains("pushup_hip_sag"))
        XCTAssertNotEqual(r.spoken, "praise_fixed", "view-gated absence of the prior issue is not observed correction")
    }

    func testCorrectionPraiseNeedsReferenceAndEnabledPriorRule() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        tracker.common.enabledFeedbackKeys = ["pushup_shallow", "praise_fixed"]
        for i in 0..<3 { _ = pushUpRep(tracker, hipDrop: 0, frame: i*2, bend: 60) }
        for i in 3..<5 { _ = pushUpRep(tracker, hipDrop: 0, frame: i*2, bend: 0) }
        XCTAssertEqual(tracker.drainEvents().last?.key, "pushup_shallow")
        tracker.common.baselineRepCount = 10
        XCTAssertNil(pushUpRep(tracker, hipDrop: 0, frame: 10, bend: 0).spoken,
                     "a missing new reference does not clear the old warned rule")
        let quiet = FormWarningTracker(exercise: .pushUp)
        _ = pushUpRep(quiet, hipDrop: 70, frame: 0)
        _ = quiet.drainEvents()
        quiet.common.enabledFeedbackKeys.remove("pushup_hip_sag")
        XCTAssertNotEqual(pushUpRep(quiet, hipDrop: 0, frame: 2).spoken, "praise_fixed")
    }

    func testCorrectionPraiseStillWorksForSameObservedRuleAndSource() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        _ = pushUpRep(tracker, hipDrop: 70, frame: 0)
        _ = tracker.drainEvents()
        XCTAssertEqual(pushUpRep(tracker, hipDrop: 0, frame: 2).spoken, "praise_fixed")
        var assessed: Set<String> = []
        _ = tracker.judge(["hip_dev_max": 0, "hip_dev_min": 0, "elbow_min": 90, "elbow_max": 170],
                          history: [], repIndex: 3, assessed: { assessed = $0 })
        XCTAssertFalse(assessed.contains("pushup_hip_sag"), "missing view evidence is not a verified branch")
    }
}


extension FormWarningsTests {
    func testCorrectionAssessmentRejectsNonfiniteCurrentReferenceAndView() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        let valid = ["hip_dev_max": 0.0, "hip_dev_min": 0.0, "elbow_min": 90.0, "elbow_max": 170.0, "front_view_fraction": 0.0]
        for key in ["hip_dev_max", "front_view_fraction"] {
            var m = valid; m[key] = .nan
            var assessed: Set<String> = []
            _ = tracker.judge(m, history: [], repIndex: 2, assessed: { assessed = $0 })
            XCTAssertFalse(assessed.contains("pushup_hip_sag"))
        }
        var assessed: Set<String> = []
        _ = tracker.judge(valid, history: [["elbow_min": .infinity]], repIndex: 2, assessed: { assessed = $0 })
        XCTAssertTrue(assessed.isEmpty)
    }
}


/// Diagnostic snapshots only: these assertions do not establish complete rule exposure or form labels.
extension FormWarningsTests {
    func testDeliveryEvidencePreservesQuietConditionAndImmutableEnabledSnapshot() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        let enabled = tracker.common.enabledFeedbackKeys
        let report = pushUpRep(tracker, hipDrop: -50, frame: 0)
        let evidence = try XCTUnwrap(report.deliveryDecisionEvidence)
        XCTAssertEqual(report.warnings, ["pushup_hip_pike"])
        XCTAssertNil(report.spoken)
        XCTAssertTrue(tracker.drainEvents().isEmpty)
        XCTAssertEqual(evidence.conditionFiredKeys2D, report.warnings2D)
        XCTAssertEqual(evidence.selectedConditionFiredKeys, report.warnings)
        XCTAssertTrue(evidence.deliveryAssessedKeys2D.contains("pushup_hip_pike"))
        XCTAssertFalse(evidence.enabledFeedbackKeys.contains("pushup_hip_pike"))
        XCTAssertEqual(evidence.enabledFeedbackKeys, enabled)
        XCTAssertEqual(evidence.dictionary["selected_condition_fired_enabled_keys"] as? [String], [])
        tracker.common.enabledFeedbackKeys = ["pushup_hip_pike"]
        XCTAssertEqual(evidence.enabledFeedbackKeys, enabled, "report cannot follow later delivery configuration")
        XCTAssertEqual(report.deliveryDecisionEvidence?.enabledFeedbackKeys, enabled)
    }

    func testDeliveryEvidenceUnknownViewKeepsFiredSeparateFromDeliveryAssessed() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        var frame = sidePushUp(hipDrop: 70)
        frame[6].confidence = 0 // selected near side is measurable; opposing shoulder/view is missing.
        tracker.observe(frameIndex: 0, coco17: frame, phase: "top")
        tracker.beginRep()
        tracker.observe(frameIndex: 1, coco17: frame, phase: "bottom")
        let report = tracker.finishRep(repIndex: 1)
        let evidence = try XCTUnwrap(report.deliveryDecisionEvidence)
        XCTAssertNil(report.metrics2D["front_view_fraction"])
        XCTAssertEqual(report.warnings, ["pushup_hip_sag"], "historical condition is preserved")
        XCTAssertEqual(report.spoken, "pushup_hip_sag", "diagnostics do not add a new delivery gate")
        XCTAssertTrue(evidence.deliveryAssessedKeys2D.isEmpty)
        XCTAssertEqual(evidence.conditionFiredKeys2D, ["pushup_hip_sag"])
        XCTAssertEqual(evidence.selectedSource, "2d")
        XCTAssertNil(evidence.deliveryAssessedKeys3D)
    }

    func testDeliveryEvidencePartialPositiveKeepsExistingJudgeSetsExactly() throws {
        let tracker = FormWarningTracker(exercise: .squat)
        tracker.common.form3DRequired = true
        tracker.observe(frameIndex: 0, coco17: sidePushUp(hipDrop: 0),
                        pose3D: standing3D(kneeTheta: 5), pose3DState: .ok, phase: "top")
        tracker.beginRep()
        let first = tracker.finishRep(repIndex: 1)
        var partial = standing3D(kneeTheta: 40)
        partial[11] = SIMD3(repeating: .nan) // selected hip angle missing, known knee flexion survives.
        tracker.observe(frameIndex: 1, coco17: sidePushUp(hipDrop: 0),
                        pose3D: partial, pose3DState: .partial3D, phase: "top")
        tracker.beginRep()
        let report = tracker.finishRep(repIndex: 2)
        XCTAssertNil(report.metrics3D["hip_angle_max"])
        XCTAssertTrue(report.warnings.contains("squat_no_lockout"))
        let evidence = try XCTUnwrap(report.deliveryDecisionEvidence)
        XCTAssertFalse(try XCTUnwrap(evidence.deliveryAssessedKeys3D).contains("squat_no_lockout"))
        XCTAssertTrue(try XCTUnwrap(evidence.conditionFiredKeys3D).contains("squat_no_lockout"))
        var assessed: Set<String> = []
        let fired = tracker.judge(report.metrics3D, history: [first.metrics3D], repIndex: 2,
                                  assessed: { assessed = $0 })
        XCTAssertEqual(evidence.conditionFiredKeys3D, fired)
        XCTAssertEqual(evidence.deliveryAssessedKeys3D, assessed, "retain EXACT existing delivery qualification")
        XCTAssertEqual(evidence.selectedDeliveryAssessedKeys, assessed)
    }

    func testDeliveryEvidenceUnavailable3DDoesNotTurnComparisonIntoSelectedDecision() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        tracker.common.form3DRequired = true
        tracker.observe(frameIndex: 0, coco17: sidePushUp(hipDrop: 70), pose3DState: .warmingUp, phase: "top")
        tracker.beginRep()
        let report = tracker.finishRep(repIndex: 1)
        let evidence = try XCTUnwrap(report.deliveryDecisionEvidence)
        XCTAssertEqual(report.formSource, "3d_unavailable")
        XCTAssertEqual(report.warnings, [])
        XCTAssertNil(report.spoken)
        XCTAssertEqual(report.warnings2D, ["pushup_hip_sag"])
        XCTAssertEqual(evidence.conditionFiredKeys2D, report.warnings2D)
        XCTAssertNil(evidence.conditionFiredKeys3D)
        XCTAssertNil(evidence.deliveryAssessedKeys3D)
        XCTAssertNil(evidence.selectedConditionFiredKeys)
        XCTAssertNil(evidence.selectedDeliveryAssessedKeys)
        XCTAssertTrue(evidence.dictionary["selected_condition_fired_keys"] is NSNull)
        XCTAssertTrue(tracker.drainEvents().isEmpty)
    }

    func testDeliveryEvidenceIsAdditiveJSONAndLegacyManualReportsRemainUnknown() throws {
        let tracker = FormWarningTracker(exercise: .pushUp)
        let report = pushUpRep(tracker, hipDrop: 70, frame: 0)
        let manual = FormRepReport(exercise: report.exercise, repIndex: report.repIndex,
            startFrame: report.startFrame, endFrame: report.endFrame, side: report.side,
            metrics2D: report.metrics2D, metrics3D: report.metrics3D, frames3D: report.frames3D,
            bad3DFrames: report.bad3DFrames, warnings: report.warnings, spoken: report.spoken,
            warnings2D: report.warnings2D, warnings3D: report.warnings3D,
            formSource: report.formSource, states3D: report.states3D)
        XCTAssertNil(manual.deliveryDecisionEvidence)
        XCTAssertTrue(manual.dictionary["delivery_decision_evidence"] is NSNull)
        var before = manual.dictionary, after = report.dictionary
        before.removeValue(forKey: "delivery_decision_evidence")
        after.removeValue(forKey: "delivery_decision_evidence")
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: before, options: [.sortedKeys]),
                       try JSONSerialization.data(withJSONObject: after, options: [.sortedKeys]),
                       "every legacy report field is unchanged")
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: report.dictionary)) as? [String: Any])
        let evidence = try XCTUnwrap(parsed["delivery_decision_evidence"] as? [String: Any])
        XCTAssertEqual(evidence["scope"] as? String, "delivery_qualification_not_complete_rule_coverage")
        XCTAssertEqual(evidence["spoken_key"] as? String, report.spoken)
        XCTAssertEqual(tracker.warningRepCounts, ["pushup_hip_sag": 1])
        XCTAssertEqual(tracker.drainEvents().map(\.key), ["pushup_hip_sag"])
    }
}
