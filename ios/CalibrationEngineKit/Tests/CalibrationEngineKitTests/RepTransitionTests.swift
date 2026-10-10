import XCTest
@testable import CalibrationEngineKit

/// Rep-state transitions found with outputs/rep_validation (Exercise3D replay).
final class RepTransitionTests: XCTestCase {
    private func kp(_ x: Double, _ y: Double, _ c: Double = 0.9) -> PoseKeypoint { PoseKeypoint(x: x, y: y, confidence: c) }

    /// Side-view squat, both legs on top of each other.
    private func squatPose(hip: PoseKeypoint, knee: PoseKeypoint) -> [PoseKeypoint] {
        var k = [PoseKeypoint](repeating: kp(0, -300), count: 17)
        k[11] = hip; k[12] = hip; k[13] = knee; k[14] = knee; k[15] = kp(0, 400); k[16] = kp(0, 400)
        return k
    }

    private func squatReps(_ poses: [[PoseKeypoint]]) -> Int {
        let evaluator = SquatEvaluator()
        var rep = 0
        for (i, pose) in poses.enumerated() { rep = evaluator.evaluate(frameIndex: i, coco17: pose).rep }
        return rep
    }

    func testSquatFastRepWithoutDescendingOrAscendingCounts() {
        // top → bottom → top with no in-between frames: stable status goes top → bottom → top by
        // forced transitions and never shows descending/ascending.
        let top = squatPose(hip: kp(0, 0), knee: kp(0, 200))
        let bottom = squatPose(hip: kp(-150, 220), knee: kp(50, 250))
        let rep = Array(repeating: top, count: 10) + Array(repeating: bottom, count: 20) + Array(repeating: top, count: 20)
        XCTAssertEqual(squatReps(rep + rep), 2)
    }

    func testSquatStandingSwayCountsNothing() {
        // 20 s of standing: ±20 px sideways sway and a 20 px (5% of the leg) vertical bob.
        let poses = (0..<600).map { i -> [PoseKeypoint] in
            let t = Double(i) / 30
            let dx = 20 * sin(2 * .pi * 0.5 * t), dy = 20 * (1 - cos(2 * .pi * 0.7 * t)) / 2
            return squatPose(hip: kp(dx, dy), knee: kp(dx, 200 + dy / 2))
        }
        XCTAssertEqual(squatReps(poses), 0)
    }

    /// Bent-over row facing +x. `spread` = shoulder/hip/arm half-width in x (0 = pure side view,
    /// large = rear view). `pull` 0 = arms hanging, 1 = bar at the lower chest. `farArmConfidence`
    /// for the right elbow/wrist (side view hides it).
    private func rowPose(pull: Double, spread: Double, farArmConfidence: Double = 0.9) -> [PoseKeypoint] {
        func lerp(_ a: (Double, Double), _ b: (Double, Double)) -> (Double, Double) {
            (a.0 + (b.0 - a.0) * pull, a.1 + (b.1 - a.1) * pull)
        }
        let elbow = lerp((200, 80), (130, 40)), wrist = lerp((200, 220), (190, 50))
        var k = [PoseKeypoint](repeating: kp(260, -90), count: 17)
        for (sign, ids) in [(-1.0, (5, 7, 9, 11)), (1.0, (6, 8, 10, 12))] {
            let dx = sign * spread
            let armC = sign > 0 ? farArmConfidence : 0.9
            k[ids.0] = kp(200 + dx, -60)
            k[ids.1] = kp(elbow.0 + dx, elbow.1, armC)
            k[ids.2] = kp(wrist.0 + dx, wrist.1, armC)
            k[ids.3] = kp(dx, 0)
        }
        return k
    }

    private func rowRun(spread: Double, farArmConfidence: Double = 0.9) -> (reps: Int, tracker: FormWarningTracker) {
        let evaluator = BarbellRowEvaluator()
        let ramp = (0...12).map { Double($0) / 12 }
        let pulls = Array(repeating: 0.0, count: 40)
            + Array(repeating: Array(repeating: 0.0, count: 20) + ramp + Array(repeating: 1.0, count: 10) + ramp.reversed(), count: 3).flatMap { $0 }
            + Array(repeating: 0.0, count: 20)
        var rep = 0
        for (i, p) in pulls.enumerated() {
            rep = evaluator.evaluate(frameIndex: i, coco17: rowPose(pull: p, spread: spread, farArmConfidence: farArmConfidence)).rep
        }
        return (rep, evaluator.formTracker)
    }

    func testRowSideViewCountsWithOneConfidentArm() {
        let run = rowRun(spread: 5, farArmConfidence: 0.1)
        XCTAssertEqual(run.tracker.sideView, true)
        XCTAssertEqual(run.reps, 3)
        XCTAssertEqual(run.tracker.drainEvents(), [])
    }

    func testRowRearViewIsGatedWithSetupGuidance() {
        // Shoulder width / torso length ≈ 0.8 (Exercise3D rear cams: 0.66–0.84).
        let run = rowRun(spread: 85)
        XCTAssertEqual(run.tracker.sideView, false)
        XCTAssertEqual(run.reps, 0)
        XCTAssertTrue(run.tracker.reports.isEmpty)
        XCTAssertEqual(run.tracker.drainEvents().map(\.key), ["setup_side_view"])
    }

    func testReadyPoseGate() {
        var gate = ReadyPoseGate(holdFrames: 3, tolerance: 0.1)
        for v in [0.0, 0.5, 0.55] { gate.update(atStartPose: true, value: v) }
        XCTAssertFalse(gate.armed, "moved at frame 2: run restarts")
        gate.update(atStartPose: false, value: 0.5)
        for _ in 0..<2 { gate.update(atStartPose: true, value: 0.5) }
        XCTAssertFalse(gate.armed)
        gate.update(atStartPose: true, value: 0.52)
        XCTAssertTrue(gate.armed)
        XCTAssertTrue(ReadyPoseGate(holdFrames: 0, tolerance: 0).armed, "0 = off")
        var squat = SquatEvaluatorConfig(), row = BarbellRowEvaluatorConfig()
        squat.applyReadyPosePreset(fps: 30)
        row.applyReadyPosePreset(fps: 50)
        XCTAssertEqual(squat.readyPoseHoldFrames, 15)
        XCTAssertEqual(squat.readyPoseTolerance, 0.06, accuracy: 1e-12)
        XCTAssertEqual(row.readyPoseHoldFrames, 25)
        XCTAssertEqual(row.readyPoseTolerance, 0.10, accuracy: 1e-12)
    }

    func testSquatReadyPoseSkipsPreSetMotion() {
        let top = squatPose(hip: kp(0, 0), knee: kp(0, 200))
        let bottom = squatPose(hip: kp(-150, 220), knee: kp(50, 250))
        // Pick up the bar (down and straight back up, no pause), then hold 1 s, then one rep.
        let poses = Array(repeating: top, count: 10) + Array(repeating: bottom, count: 20) + Array(repeating: top, count: 40)
            + Array(repeating: bottom, count: 20) + Array(repeating: top, count: 20)
        var config = SquatEvaluatorConfig()
        XCTAssertEqual(config.readyPoseHoldFrames, 0, "off by default")
        XCTAssertEqual(squatReps(poses), 2)
        config.readyPoseHoldFrames = 30
        let evaluator = SquatEvaluator(config: config)
        var rep = 0
        for (i, pose) in poses.enumerated() { rep = evaluator.evaluate(frameIndex: i, coco17: pose).rep }
        XCTAssertEqual(rep, 1)
    }

    /// Side-view push-up facing +x; `bend` moves both elbows down (0 = locked out ~180°).
    /// The far (right) arm is less confident.
    private func pushUpPose(bend: Double) -> [PoseKeypoint] {
        var k = [PoseKeypoint](repeating: kp(0, 0, 0.5), count: 17)
        let pts: [(Int, Double, Double)] = [(0, 580, 395 + bend / 2), (3, 560, 390 + bend / 2), (5, 500, 400 + bend / 2),
                                            (7, 500 - bend, 480), (9, 500, 560), (11, 300, 450 + bend / 3), (13, 200, 475), (15, 100, 500)]
        for (i, x, y) in pts {
            k[i] = kp(x, y)
            if i != 0 { k[i + 1] = kp(x, y, [7, 9].contains(i) ? 0.6 : 0.9) }
        }
        return k
    }

    private func pushUpReps(_ bends: [Double], fixes: Bool) -> Int {
        var config = PushUpEvaluatorConfig()
        config.sideViewRepFixes = fixes
        let evaluator = PushUpEvaluator(config: config)
        var rep = 0
        for (i, b) in bends.enumerated() { rep = evaluator.evaluate(frameIndex: i, coco17: pushUpPose(bend: b)).rep }
        return rep
    }

    func testPushUpSideViewFixesKeepNormalRepsAndCountFastDescent() {
        XCTAssertTrue(PushUpEvaluatorConfig().sideViewRepFixes, "on by default (side view only)")
        // Slow reps (gradual down/up): every rep still counted with the side-view fixes.
        let ramp = (0...15).map { Double($0) * 6 }
        let slow = Array(repeating: 0.0, count: 40)
            + Array(repeating: Array(repeating: 0.0, count: 10) + ramp + ramp.reversed(), count: 4).flatMap { $0 } + Array(repeating: 0.0, count: 20)
        // Without the fixes the first rep (still on the fixed fallback thresholds) is missed.
        XCTAssertEqual(pushUpReps(slow, fixes: false), 3)
        XCTAssertEqual(pushUpReps(slow, fixes: true), 4, "no correct-rep loss")
        // Fast descent: top straight to bottom (no descending frames), slow way up.
        let fast = Array(repeating: 0.0, count: 40)
            + Array(repeating: Array(repeating: 0.0, count: 12) + Array(repeating: 90.0, count: 12) + ramp.reversed(), count: 4).flatMap { $0 }
            + Array(repeating: 0.0, count: 20)
        let fastOn = pushUpReps(fast, fixes: true)
        XCTAssertEqual(fastOn, 4)
        XCTAssertLessThan(pushUpReps(fast, fixes: false), fastOn)
    }
}
