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

    private func squatReps(_ poses: [[PoseKeypoint]], config: SquatEvaluatorConfig = SquatEvaluatorConfig()) -> Int {
        let evaluator = SquatEvaluator(config: config)
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

    /// One D-T3-13 change at a time (all off = the rules before it).
    private func squatConfig(hold: Bool = false, nearLeg: Bool = false, rebaseline: Int = 0, height: Bool = false) -> SquatEvaluatorConfig {
        var config = SquatEvaluatorConfig()
        config.heightRepSignal = height
        config.holdStatusThroughUnknown = hold
        config.nearLegFallback = nearLeg
        config.rebaselineStraightLegFrames = rebaseline
        return config
    }

    func testSquatPauseBetweenThresholdsKeepsTheRep() {
        // D-T3-13: a 15-frame pause half way up (depth 0.17, knee 142°: neither top nor bottom, no motion)
        // used to force `unknown`, and unknown → top does not finish a rep.
        let top = squatPose(hip: kp(0, 0), knee: kp(0, 200))
        let bottom = squatPose(hip: kp(-150, 220), knee: kp(50, 250))
        let pause = squatPose(hip: kp(-40, 60), knee: kp(40, 230))
        let rep = Array(repeating: bottom, count: 20) + Array(repeating: pause, count: 15) + Array(repeating: top, count: 20)
        let poses = Array(repeating: top, count: 10) + rep + rep
        XCTAssertEqual(squatReps(poses, config: squatConfig(hold: false)), 0)
        XCTAssertEqual(squatReps(poses, config: squatConfig(hold: true)), 2)
    }

    func testSquatNearLegAloneCounts() {
        // D-T3-13: side view, far (right) leg hidden (confidence 0.1) — the near leg alone is enough.
        func hideRight(_ k: [PoseKeypoint]) -> [PoseKeypoint] {
            var k = k
            for i in [12, 14, 16] { k[i].confidence = 0.1 }
            return k
        }
        let top = hideRight(squatPose(hip: kp(0, 0), knee: kp(0, 200)))
        let bottom = hideRight(squatPose(hip: kp(-150, 220), knee: kp(50, 250)))
        let rep = Array(repeating: top, count: 10) + Array(repeating: bottom, count: 20) + Array(repeating: top, count: 20)
        XCTAssertEqual(squatReps(rep + rep, config: squatConfig(nearLeg: false)), 0)
        XCTAssertEqual(squatReps(rep + rep, config: squatConfig(nearLeg: true)), 2)
    }

    func testSquatStaleStandingBaselineIsReset() {
        // D-T3-13: the first confident frames are a false detection with the hip 100 px too high, so the
        // real standing pose reads as depth 0.25 (bottom) forever; straight legs for 30 frames reset it.
        let glitch = squatPose(hip: kp(0, -100), knee: kp(0, 150))
        let top = squatPose(hip: kp(0, 0), knee: kp(0, 200))
        let bottom = squatPose(hip: kp(-150, 220), knee: kp(50, 250))
        let rep = Array(repeating: bottom, count: 20) + Array(repeating: top, count: 40)
        let poses = Array(repeating: glitch, count: 3) + Array(repeating: top, count: 40) + rep + rep
        XCTAssertEqual(squatReps(poses, config: squatConfig(rebaseline: 0)), 0)
        XCTAssertEqual(squatReps(poses, config: squatConfig(rebaseline: 30)), 2)
    }

    func testSquatHeightSignalCountsRepsWithoutKneeLockout() {
        // D-T3-13: the knees never open past 145° at the top (141°), so the state machine never sees
        // `top`; the hip still rises 0.5 leg lengths each rep, which the height signal counts.
        let high = squatPose(hip: kp(0, 0), knee: kp(70, 190))
        let low = squatPose(hip: kp(-150, 220), knee: kp(50, 250))
        let rep = Array(repeating: low, count: 20) + Array(repeating: high, count: 30)
        let poses = Array(repeating: high, count: 30) + rep + rep + rep
        XCTAssertEqual(squatReps(poses, config: squatConfig(hold: true, nearLeg: true, rebaseline: 30, height: false)), 0)
        XCTAssertEqual(squatReps(poses, config: squatConfig(hold: true, nearLeg: true, rebaseline: 30, height: true)), 3)
        XCTAssertEqual(squatReps(poses), 3)  // app default
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

    private func rowRun(spread: Double, farArmConfidence: Double = 0.9,
                        config: BarbellRowEvaluatorConfig = BarbellRowEvaluatorConfig()) -> (reps: Int, tracker: FormWarningTracker) {
        let evaluator = BarbellRowEvaluator(config: config)
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
        // Shoulder width / torso length ≈ 0.8 (Exercise3D rear cams: 0.66–0.84). Old behaviour
        // (countOffSideView = false): no reps, setup_side_view once.
        var config = BarbellRowEvaluatorConfig()
        config.countOffSideView = false
        let run = rowRun(spread: 85, config: config)
        XCTAssertEqual(run.tracker.sideView, false)
        XCTAssertEqual(run.reps, 0)
        XCTAssertTrue(run.tracker.reports.isEmpty)
        XCTAssertEqual(run.tracker.drainEvents().map(\.key), ["setup_side_view"])
    }

    func testRowFastLoweringStillEndsTheRep() {
        // Pull up gradually, then drop straight to the hang (no lowering frames): each rep still ends at
        // `bottom` instead of merging with the next one.
        let evaluator = BarbellRowEvaluator()
        let ramp = (0...12).map { Double($0) / 12 }
        let pulls = Array(repeating: 0.0, count: 40)
            + Array(repeating: ramp + Array(repeating: 1.0, count: 10) + Array(repeating: 0.0, count: 25), count: 3).flatMap { $0 }
        var rep = 0
        for (i, p) in pulls.enumerated() { rep = evaluator.evaluate(frameIndex: i, coco17: rowPose(pull: p, spread: 5)).rep }
        XCTAssertEqual(rep, 3)
    }

    func testRowOffSideViewStillCountsWithoutFormWarningsOrRepeatedGuidance() {
        // Default: a diagonal/rear camera (gate "not side") still counts with the side-view rules,
        // says setup_side_view once (not again on the first rep) and judges no form warnings.
        XCTAssertTrue(BarbellRowEvaluatorConfig().countOffSideView)
        let run = rowRun(spread: 85)
        XCTAssertEqual(run.tracker.sideView, false)
        XCTAssertEqual(run.reps, 3)
        XCTAssertEqual(run.tracker.drainEvents().map(\.key), ["setup_side_view"])
        XCTAssertTrue(run.tracker.reports.allSatisfy { $0.warnings.isEmpty })
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

    private func pushUpReps(_ bends: [Double], config: PushUpEvaluatorConfig, pose: (Double) -> [PoseKeypoint]) -> Int {
        let evaluator = PushUpEvaluator(config: config)
        var rep = 0
        for (i, b) in bends.enumerated() { rep = evaluator.evaluate(frameIndex: i, coco17: pose(b)).rep }
        return rep
    }

    func testPushUpFlickerRepShorterThanMinRepFramesIsDropped() {
        // Two real reps calibrate the elbow range, then a 6-frame flicker (0.2 s at 30 fps) to the bottom.
        let ramp = (0...15).map { Double($0) * 6 }
        let real = Array(repeating: 0.0, count: 10) + ramp + ramp.reversed()
        let flicker = Array(repeating: 0.0, count: 20) + [90, 90, 90, 90, 0, 0] + Array(repeating: 0.0, count: 20)
        let bends = Array(repeating: 0.0, count: 40) + real + real + flicker
        var config = PushUpEvaluatorConfig()
        XCTAssertEqual(config.minRepFrames, 15)
        XCTAssertEqual(pushUpReps(bends, config: config, pose: pushUpPose), 2)
        config.minRepFrames = 0
        XCTAssertEqual(pushUpReps(bends, config: config, pose: pushUpPose), 3, "the flicker counts without the minimum")
    }

    func testPushUpCountsWithAnklesLostOnlyWhenAnkleNotRequired() {
        // Off-side cameras lose the ankles first; the elbow angle alone drives the rep.
        let ramp = (0...15).map { Double($0) * 6 }
        let bends = Array(repeating: 0.0, count: 40)
            + Array(repeating: Array(repeating: 0.0, count: 10) + ramp + ramp.reversed(), count: 3).flatMap { $0 } + Array(repeating: 0.0, count: 20)
        let noAnkles = { (b: Double) -> [PoseKeypoint] in
            var k = self.pushUpPose(bend: b)
            k[15].confidence = 0.1; k[16].confidence = 0.1
            return k
        }
        var config = PushUpEvaluatorConfig()
        XCTAssertFalse(config.requireAnkleForRep, "default")
        XCTAssertEqual(pushUpReps(bends, config: config, pose: noAnkles), 3)
        config.requireAnkleForRep = true
        XCTAssertEqual(pushUpReps(bends, config: config, pose: noAnkles), 0)
    }

    /// Side-view plank whose shoulders drop by `drop` px while the 2D elbow stays ~straight (elbows flared toward
    /// the camera: the bend is along the line of sight). `tilt` raises the shoulders (torso off horizontal).
    private func flaredPushUpPose(drop: Double, tilt: Double = 0) -> [PoseKeypoint] {
        var k = [PoseKeypoint](repeating: kp(0, 0, 0.5), count: 17)
        let sy = 400 + drop - tilt
        let pts: [(Int, Double, Double)] = [(0, 580, sy - 5), (3, 560, sy - 10), (5, 500, sy), (7, 502, (sy + 560) / 2), (9, 500, 560),
                                            (11, 300, 450), (13, 200, 475), (15, 100, 500)]
        for (i, x, y) in pts {
            k[i] = kp(x, y)
            if i != 0 { k[i + 1] = kp(x, y, [7, 9].contains(i) ? 0.6 : 0.9) }
        }
        return k
    }

    func testPushUpHeightSignalCountsFlaredElbowReps() {
        // 4 reps: shoulders drop 120 px (≈ 0.6 torso) and come back; the 2D elbow angle stays ≥ 170°.
        let ramp = (0...15).map { Double($0) * 8 }
        let bends = Array(repeating: 0.0, count: 40)
            + Array(repeating: Array(repeating: 0.0, count: 10) + ramp + ramp.reversed(), count: 4).flatMap { $0 } + Array(repeating: 0.0, count: 20)
        var config = PushUpEvaluatorConfig()
        XCTAssertTrue(config.heightRepSignal, "on by default")
        XCTAssertEqual(pushUpReps(bends, config: config, pose: { self.flaredPushUpPose(drop: $0) }), 4)
        config.heightRepSignal = false
        XCTAssertEqual(pushUpReps(bends, config: config, pose: { self.flaredPushUpPose(drop: $0) }), 0, "the elbow angle alone sees nothing")
    }

    func testPushUpHeightSignalIgnoresUprightTorsoAndKeepsElbowReps() {
        let ramp = (0...15).map { Double($0) * 8 }
        let bends = Array(repeating: 0.0, count: 40)
            + Array(repeating: Array(repeating: 0.0, count: 10) + ramp + ramp.reversed(), count: 4).flatMap { $0 } + Array(repeating: 0.0, count: 20)
        // Shoulders 400 px above the hips (torso ~63° from horizontal, e.g. standing up / kneeling): no height reps.
        XCTAssertEqual(pushUpReps(bends, config: PushUpEvaluatorConfig(), pose: { self.flaredPushUpPose(drop: $0, tilt: 450) }), 0)
        // Normal elbow reps are not double counted when both signals see them.
        let elbow = (0...15).map { Double($0) * 6 }
        let normal = Array(repeating: 0.0, count: 40)
            + Array(repeating: Array(repeating: 0.0, count: 10) + elbow + elbow.reversed(), count: 4).flatMap { $0 } + Array(repeating: 0.0, count: 20)
        let deeper = { (b: Double) -> [PoseKeypoint] in
            var k = self.pushUpPose(bend: b)
            for i in [0, 1, 2, 3, 4, 5, 6] { k[i].y += b * 1.2 }  // shoulders and head drop too (height range ≥ 0.3 torso)
            return k
        }
        XCTAssertEqual(pushUpReps(normal, config: PushUpEvaluatorConfig(), pose: deeper), 4)
    }

    func testHeightCounterNeedsRangeAndMinimumRepLength() {
        var counter = PushUpHeightCounter()
        var events: [PushUpHeightCounter.Event] = []
        // Sway of 0.1 torso: below minRange, nothing.
        for i in 0..<120 { if let e = counter.update(frame: i, height: 0.8 + 0.1 * sin(Double(i) / 5)) { events.append(e) } }
        XCTAssertTrue(events.isEmpty)
        // Two slow reps 0.8 → 0.1 → 0.8 (40 frames each), then a 6-frame dip that is too short.
        let rep = (0..<40).map { 0.45 + 0.35 * cos(Double($0) / 40 * 2 * .pi) }
        let dip = [0.8, 0.1, 0.1, 0.1, 0.1, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8]
        for (j, v) in (rep + rep + dip + Array(repeating: 0.8, count: 10)).enumerated() { _ = counter.update(frame: 120 + j, height: v) }
        XCTAssertEqual(counter.reps, 2)
        _ = counter.update(frame: 300, height: nil)
        XCTAssertEqual(counter.reps, 2, "missing samples are skipped")
    }

    func testWorkoutUsesMediumModelCalibrationKeepsSmall() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BPT_POSE_MODEL"] != nil, "overridden by BPT_POSE_MODEL")
        XCTAssertEqual(RTMPoseModel.workout, .mcoco17)
        XCTAssertEqual(RTMPoseModel.workout.rawValue, "rtmpose_m_forward")
        XCTAssertEqual(RTMPoseModel.active, .coco17, "calibration capture unchanged")
    }

    /// Every selectable model (BPT_POSE_MODEL / pose-replay --model) is a package the app bundles.
    func testEverySelectableModelIsBundled() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let project = try String(contentsOf: root.appendingPathComponent("ios/Runner.xcodeproj/project.pbxproj"), encoding: .utf8)
        for model in RTMPoseModel.allCases {
            let package = "ios/Runner/NativePose/Models/\(model.rawValue).mlpackage/Manifest.json"
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(package).path), package)
            XCTAssertTrue(project.contains("\(model.rawValue).mlpackage in Resources"), "\(model) not in Runner resources")
        }
    }
}
