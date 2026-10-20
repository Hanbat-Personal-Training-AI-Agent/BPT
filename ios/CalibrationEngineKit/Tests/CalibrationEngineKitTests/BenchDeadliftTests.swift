import XCTest
@testable import CalibrationEngineKit

/// Bench press / deadlift: rep counting on synthetic side-view poses, the form tracker hook-up
/// (setup keys only by default) and the bench_* / deadlift_* rules (all off in the app).
final class BenchDeadliftTests: XCTestCase {
    private func kp(_ x: Double, _ y: Double, _ c: Double = 0.9) -> PoseKeypoint { PoseKeypoint(x: x, y: y, confidence: c) }

    /// Lying on a bench, head towards +x, camera beside the bench (both sides overlap).
    /// `press` 0 = bar on the chest, 1 = arms locked out; `hipLift` raises the hip (px, image y up).
    private func benchPose(press: Double, hipLift: Double = 0) -> [PoseKeypoint] {
        // Upper arm 100 px, forearm 100 px from the shoulder at (0, 0); elbow angle 70° → 180°.
        let elbowAngle = (70 + 110 * press) * .pi / 180
        let elbow = kp(-100 * cos(elbowAngle / 2), -100 * sin(elbowAngle / 2))
        let wrist = kp(0, -200 * sin(elbowAngle / 2))
        var k = [PoseKeypoint](repeating: kp(60, -10), count: 17)
        for (s, e, w, h, n, a) in [(5, 7, 9, 11, 13, 15), (6, 8, 10, 12, 14, 16)] {
            k[s] = kp(0, 0); k[e] = elbow; k[w] = wrist
            k[h] = kp(-220, -hipLift); k[n] = kp(-380, -40); k[a] = kp(-420, 120)
        }
        return k
    }

    /// Side view, facing +x. `lift` 0 = bar on the floor (hips back, knees bent), 1 = lockout.
    /// Torso 250 px at `theta` from vertical (65° → 0°). `hipsFirst`: the hip rises three times as fast in
    /// the first half while the torso tips further forward (65° → 85°), then straightens.
    private func deadliftPose(lift: Double, hipsFirst: Bool = false) -> [PoseKeypoint] {
        let hipLift = hipsFirst ? min(1, lift * 3) : lift
        let theta = (hipsFirst ? (lift < 1.0 / 3 ? 65 + 60 * lift : 127.5 * (1 - lift)) : 65 * (1 - lift)) * .pi / 180
        let hip = kp(-60 * (1 - hipLift), -200 - 150 * hipLift)
        let knee = kp(30 * (1 - lift), -200)
        let ankle = kp(0, 0)
        let shoulder = kp(hip.x + 250 * sin(theta), hip.y - 250 * cos(theta))
        let wrist = kp(shoulder.x, shoulder.y + 260)
        var k = [PoseKeypoint](repeating: kp(shoulder.x + 30, shoulder.y - 40), count: 17)
        k[3] = kp(shoulder.x + 10, shoulder.y - 40); k[4] = k[3]
        k[0] = kp(shoulder.x + 40, shoulder.y - 40)
        for (s, e, w, h, n, a) in [(5, 7, 9, 11, 13, 15), (6, 8, 10, 12, 14, 16)] {
            k[s] = shoulder; k[e] = kp(shoulder.x, shoulder.y + 130); k[w] = wrist
            k[h] = hip; k[n] = knee; k[a] = ankle
        }
        return k
    }

    private func ramp(_ n: Int) -> [Double] { (0...n).map { Double($0) / Double(n) } }

    func testBenchCountsSideViewRepsWithTrackerReports() {
        let evaluator = BenchPressEvaluator()
        let rep = Array(repeating: 1.0, count: 15) + ramp(20).reversed() + Array(repeating: 0.0, count: 8) + ramp(20)
        let presses = Array(repeating: rep, count: 4).flatMap { $0 } + Array(repeating: 1.0, count: 20)
        var count = 0
        for (i, p) in presses.enumerated() { count = evaluator.evaluate(frameIndex: i, coco17: benchPose(press: p)).rep }
        XCTAssertEqual(count, 4)
        XCTAssertEqual(evaluator.formTracker.reports.count, 4)
        XCTAssertEqual(evaluator.formTracker.reports.flatMap(\.warnings), [])
        // Default delivery: nothing (setup keys only, joints all visible).
        XCTAssertEqual(evaluator.formTracker.drainEvents(), [])
    }

    func testBenchCountsWithTheFarArmHidden() {
        func reps(_ config: BenchPressEvaluatorConfig) -> Int {
            let evaluator = BenchPressEvaluator(config: config)
            let rep = Array(repeating: 1.0, count: 15) + ramp(20).reversed() + Array(repeating: 0.0, count: 8) + ramp(20)
            var count = 0
            for (i, p) in (Array(repeating: rep, count: 3).flatMap { $0 } + Array(repeating: 1.0, count: 20)).enumerated() {
                var k = benchPose(press: p)
                for j in [6, 8, 10] { k[j] = kp(k[j].x, k[j].y, 0.1) }  // right arm behind the body/bar
                count = evaluator.evaluate(frameIndex: i, coco17: k).rep
            }
            return count
        }
        XCTAssertEqual(reps(BenchPressEvaluatorConfig()), 3)
        var bothArms = BenchPressEvaluatorConfig()
        bothArms.allowOneArm = false
        XCTAssertEqual(reps(bothArms), 0)
    }

    func testBenchHipsUpRuleFiresButStaysOffByDefault() {
        let evaluator = BenchPressEvaluator()
        let rep = Array(repeating: 1.0, count: 15) + ramp(20).reversed() + Array(repeating: 0.0, count: 8) + ramp(20)
        var i = 0
        for r in 0..<4 {
            for (j, p) in rep.enumerated() {
                // Rep 4: hips come off the bench while pressing (60 px = 0.27 torso).
                let lift = r == 3 && j > 35 ? 60.0 : 0
                _ = evaluator.evaluate(frameIndex: i, coco17: benchPose(press: p, hipLift: lift))
                i += 1
            }
        }
        for _ in 0..<20 { _ = evaluator.evaluate(frameIndex: i, coco17: benchPose(press: 1)); i += 1 }
        XCTAssertEqual(evaluator.formTracker.reports.map(\.warnings), [[], [], [], ["bench_hips_up"]])
        XCTAssertEqual(evaluator.formTracker.drainEvents(), [])
    }

    func testDeadliftCountsSideViewReps() {
        let evaluator = DeadliftEvaluator()
        let rep = Array(repeating: 0.0, count: 20) + ramp(25) + Array(repeating: 1.0, count: 15) + ramp(25).reversed()
        let lifts = Array(repeating: rep, count: 3).flatMap { $0 } + Array(repeating: 0.0, count: 20)
        var count = 0
        for (i, l) in lifts.enumerated() { count = evaluator.evaluate(frameIndex: i, coco17: deadliftPose(lift: l)).rep }
        XCTAssertEqual(count, 3)
        XCTAssertEqual(evaluator.formTracker.reports.count, 3)
        XCTAssertEqual(evaluator.formTracker.reports.flatMap(\.warnings), [])
        XCTAssertEqual(evaluator.formTracker.drainEvents(), [])
    }

    func testDeadliftHipsFirstAndNoLockoutRules() {
        let evaluator = DeadliftEvaluator()
        func run(_ lifts: [Double], hipsFirst: Bool, from start: Int) -> Int {
            for (j, l) in lifts.enumerated() {
                _ = evaluator.evaluate(frameIndex: start + j, coco17: deadliftPose(lift: l, hipsFirst: hipsFirst))
            }
            return start + lifts.count
        }
        let full = Array(repeating: 0.0, count: 20) + ramp(25) + Array(repeating: 1.0, count: 15) + ramp(25).reversed()
        // Stops at 85% of the lockout (hip angle ~20° short).
        let short = Array(repeating: 0.0, count: 20) + ramp(25).map { $0 * 0.85 } + Array(repeating: 0.85, count: 15)
            + ramp(25).reversed().map { $0 * 0.85 }
        // Hips-first pull over 2 s (the rule looks at the first 10 frames after the lowest hip).
        let slow = Array(repeating: 0.0, count: 20) + ramp(60) + Array(repeating: 1.0, count: 15) + ramp(25).reversed()
        var i = run(full, hipsFirst: false, from: 0)
        i = run(slow, hipsFirst: true, from: i)
        i = run(short, hipsFirst: false, from: i)
        _ = run(Array(repeating: 0.0, count: 20), hipsFirst: false, from: i)
        let warnings = evaluator.formTracker.reports.map(\.warnings)
        XCTAssertEqual(warnings.count, 3)
        XCTAssertFalse(warnings[0].contains("deadlift_hips_first"))
        XCTAssertTrue(warnings[1].contains("deadlift_hips_first"))
        XCTAssertTrue(warnings[2].contains("deadlift_no_lockout"))
        XCTAssertEqual(evaluator.formTracker.drainEvents(), [])
    }

    func testNewKeysAreKnownButNotDelivered() {
        let keys = ["bench_hips_up", "bench_shallow", "bench_no_lockout",
                    "deadlift_hips_first", "deadlift_no_lockout", "deadlift_lean_back"]
        for exercise in [FormExercise.benchPress, .deadlift] {
            let tracker = FormWarningTracker(exercise: exercise)
            XCTAssertTrue(tracker.common.enabledFeedbackKeys.isDisjoint(with: keys))
            XCTAssertTrue(tracker.common.enabledFeedbackKeys.isSuperset(of: ["setup_full_body", "tracking_lost"]))
        }
        XCTAssertEqual(FormWarningTracker.keysWithoutFlutterLines, Set(keys))
        XCTAssertTrue(Set(keys).isSubset(of: FormWarningTracker.allKeys))
        XCTAssertEqual(FormWarningTracker.grade(of: "bench_hips_up"), .priority)
        XCTAssertEqual(FormWarningTracker.grade(of: "deadlift_lean_back"), .reference)
    }

    func testDeadliftSetupFullBodyWithoutLegsAndTrackingLostAfterTheRep() {
        let evaluator = DeadliftEvaluator()
        var noLegs = deadliftPose(lift: 0)
        for j in 13...16 { noLegs[j] = kp(noLegs[j].x, noLegs[j].y, 0.1) }
        var i = 0
        for _ in 0..<evaluator.formTracker.common.setupFullBodyFrames { _ = evaluator.evaluate(frameIndex: i, coco17: noLegs); i += 1 }
        XCTAssertEqual(evaluator.formTracker.drainEvents().map(\.key), ["setup_full_body"])
        // One rep, then the lower body drops out for 1.5 s: tracking_lost once.
        for l in Array(repeating: 0.0, count: 20) + ramp(25) + Array(repeating: 1.0, count: 15) + ramp(25).reversed() + Array(repeating: 0.0, count: 20) {
            _ = evaluator.evaluate(frameIndex: i, coco17: deadliftPose(lift: l)); i += 1
        }
        XCTAssertEqual(evaluator.formTracker.reports.count, 1)
        for _ in 0..<45 { _ = evaluator.evaluate(frameIndex: i, coco17: noLegs); i += 1 }
        XCTAssertEqual(evaluator.formTracker.drainEvents().map(\.key), ["tracking_lost"])
    }

    func testBenchSetupFullBodyWhenArmsHidden() {
        let evaluator = BenchPressEvaluator()
        var hidden = benchPose(press: 1)
        for j in [7, 8, 9, 10] { hidden[j] = kp(hidden[j].x, hidden[j].y, 0.1) }
        for i in 0..<60 { _ = evaluator.evaluate(frameIndex: i, coco17: hidden) }
        XCTAssertEqual(evaluator.formTracker.drainEvents(), [FormFeedbackEvent(key: "setup_full_body", n: nil)])
    }
}
