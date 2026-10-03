import XCTest

@testable import CalibrationEngineKit

/// Synthetic-input tests for the calibration judging engine.
///
/// The builder produces a body that passes framing and A-pose, so each test only varies
/// what it is about: width (r), nose swing (δ), the face detection result, stance, motion.
final class CalibrationEngineTests: XCTestCase {
    // Portrait 1080x1920 buffer.
    private let aspect = 1080.0 / 1920.0

    private struct Body {
        var shoulderY = 0.30
        var hipY = 0.55
        var midX = 0.5
        var ankleY = 0.85
        /// Shoulder and hip widths in height units; shrinking them is what turning looks like.
        var shoulderWidth = 0.40 * 0.25
        var hipWidth = 0.32 * 0.25
        var wristDrop = 0.75
        var elbowRatio = 0.5
        /// Nose offset from the shoulder midpoint, in torso lengths.
        var noseOffset = 0.0
    }

    private func keypoints(_ b: Body) -> [CalibrationKeypoint] {
        let torso = b.hipY - b.shoulderY
        let toX = { (heightUnits: Double) in heightUnits / self.aspect }
        var kps = Array(repeating: CalibrationKeypoint(x: b.midX, y: b.shoulderY, score: 0.9), count: 17)

        func set(_ joint: CocoJoint, _ x: Double, _ y: Double) {
            kps[joint.rawValue] = CalibrationKeypoint(x: x, y: y, score: 0.9)
        }

        // RTMPose scores the face and ears high from every side, so they stay 0.9 throughout.
        let noseX = b.midX + toX(b.noseOffset * torso)
        set(.nose, noseX, b.shoulderY - 0.5 * torso)
        set(.leftEye, noseX + toX(0.02), b.shoulderY - 0.55 * torso)
        set(.rightEye, noseX - toX(0.02), b.shoulderY - 0.55 * torso)
        set(.leftEar, noseX + toX(0.05), b.shoulderY - 0.5 * torso)
        set(.rightEar, noseX - toX(0.05), b.shoulderY - 0.5 * torso)

        // Unmirrored image: the user's left side sits on the image right.
        let shoulderDX = toX(b.shoulderWidth) / 2
        let hipDX = toX(b.hipWidth) / 2
        set(.leftShoulder, b.midX + shoulderDX, b.shoulderY)
        set(.rightShoulder, b.midX - shoulderDX, b.shoulderY)
        set(.leftHip, b.midX + hipDX, b.hipY)
        set(.rightHip, b.midX - hipDX, b.hipY)

        let wristDX = toX(0.9 * torso)
        let elbowY = b.shoulderY + b.elbowRatio * b.wristDrop * torso
        let wristY = b.shoulderY + b.wristDrop * torso
        set(.leftElbow, b.midX + wristDX * 0.6, elbowY)
        set(.rightElbow, b.midX - wristDX * 0.6, elbowY)
        set(.leftWrist, b.midX + wristDX, wristY)
        set(.rightWrist, b.midX - wristDX, wristY)

        let ankleDX = toX(1.5 * b.hipWidth) / 2
        set(.leftKnee, b.midX + ankleDX, (b.hipY + b.ankleY) / 2)
        set(.rightKnee, b.midX - ankleDX, (b.hipY + b.ankleY) / 2)
        set(.leftAnkle, b.midX + ankleDX, b.ankleY)
        set(.rightAnkle, b.midX - ankleDX, b.ankleY)
        return kps
    }

    private func frame(_ b: Body, _ face: CalibrationFace, at t: TimeInterval) -> CalibrationFrame {
        CalibrationFrame(keypoints: keypoints(b), aspect: aspect, timestamp: t, device: .still, face: face)
    }

    /// Feeds the same pose for `duration` seconds at 10 fps.
    @discardableResult
    private func run(_ engine: CalibrationEngine,
                     body: Body,
                     face: CalibrationFace,
                     from start: TimeInterval,
                     duration: TimeInterval = 1.2) -> [CalibrationEngineOutput] {
        stride(from: start, through: start + duration, by: 0.1).map {
            engine.process(frame(body, face, at: $0))
        }
    }

    private func captureFront(_ engine: CalibrationEngine) {
        run(engine, body: Body(), face: .frontal, from: 0)
        XCTAssertEqual(engine.capturedViews, [.front], "front capture is the precondition")
    }

    /// A turned body: widths shrink by |cos yaw| and the nose swings off the shoulder midline.
    private func turned(r: Double, delta: Double) -> Body {
        var b = Body()
        b.shoulderWidth *= r
        b.hipWidth *= r
        b.noseOffset = delta
        return b
    }

    private func face(yaw: Double) -> CalibrationFace { CalibrationFace(isDetected: true, yawDeg: yaw) }

    // MARK: - Front

    func testFrontCapturesAndStoresReference() {
        let engine = CalibrationEngine()
        let outputs = run(engine, body: Body(), face: .frontal, from: 0)

        let captured = outputs.compactMap(\.capture)
        XCTAssertEqual(captured.map(\.view), [.front])
        XCTAssertNotNil(engine.reference)
        XCTAssertEqual(outputs.first?.guidance, .holdStill)  // nothing fires before the hold
        // The recommended turn is to the user's left, so the right-front side comes next.
        XCTAssertEqual(engine.targetView, .rightfront)
        XCTAssertEqual(CalibrationGuidance.captured(.front).message, "정면 찍었어! 이제 왼쪽으로 천천히 돌아 줘")
    }

    func testFrontNeedsAFaceLookingAtTheCamera() {
        let noFace = CalibrationEngine()
        let outputs = run(noFace, body: Body(), face: .none, from: 0)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertEqual(outputs.last?.guidance, .faceCamera)

        let lookingAway = CalibrationEngine()
        XCTAssertTrue(run(lookingAway, body: Body(), face: face(yaw: 45), from: 0).allSatisfy { $0.capture == nil })
    }

    // MARK: - Obliques

    func testObliqueSignDecidesLeftOrRight() {
        let right = CalibrationEngine()
        captureFront(right)
        // Nose swung to the image right (positive δ): the user turned to their own left.
        let rightOutputs = run(right, body: turned(r: 0.5, delta: 0.3), face: face(yaw: 60), from: 10)
        XCTAssertEqual(rightOutputs.compactMap(\.capture).first?.view, .rightfront)

        let left = CalibrationEngine()
        captureFront(left)
        let leftOutputs = run(left, body: turned(r: 0.5, delta: -0.3), face: face(yaw: -60), from: 10)
        XCTAssertEqual(leftOutputs.compactMap(\.capture).first?.view, .leftfront)
    }

    func testTurnedHeadIsRejected() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // Body at 60°, but the face looks straight at the camera.
        let outputs = run(engine, body: turned(r: 0.5, delta: 0.3), face: face(yaw: 5), from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertEqual(outputs.last?.guidance, .faceForwardWithBody)
    }

    func testBackObliqueIsNotMistakenForOblique() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // Same width as 60°, but at 120° the face is gone.
        let outputs = run(engine, body: turned(r: 0.5, delta: 0.3), face: .none, from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertEqual(engine.capturedViews, [.front])
    }

    // MARK: - Back

    func testBackIsCaptured() {
        let engine = CalibrationEngine()
        captureFront(engine)
        let outputs = run(engine, body: turned(r: 1.0, delta: 0), face: .none, from: 10)
        XCTAssertEqual(outputs.compactMap(\.capture).first?.view, .back)
    }

    func testFacingTheCameraAgainIsNotBack() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // Full width with a face: still the front, which is already captured.
        let outputs = run(engine, body: turned(r: 1.0, delta: 0), face: .frontal, from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
    }

    func testObliqueIsNotMistakenForBack() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // No face and side-on: r is far below the back gate.
        let outputs = run(engine, body: turned(r: 0.4, delta: 0), face: .none, from: 10)
        XCTAssertFalse(engine.capturedViews.contains(.back))
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
    }

    // MARK: - Guidance, stance, stillness, timeout

    func testRotationGuidanceDependsOnWhereTheUserComesFrom() {
        // Leaving the front: a profile (r below the band) is overshoot.
        let fromFront = CalibrationEngine()
        captureFront(fromFront)
        XCTAssertEqual(run(fromFront, body: turned(r: 0.15, delta: 0.3), face: face(yaw: 85), from: 10).last?.guidance,
                       .turnedTooFar)

        // Coming round from the back: the same profile is on the way, so keep turning.
        let fromBack = CalibrationEngine()
        captureFront(fromBack)
        run(fromBack, body: turned(r: 0.5, delta: 0.3), face: face(yaw: 60), from: 10)
        run(fromBack, body: turned(r: 1.0, delta: 0), face: .none, from: 20)
        XCTAssertEqual(fromBack.capturedViews, [.front, .rightfront, .back])
        XCTAssertEqual(run(fromBack, body: turned(r: 0.15, delta: -0.1), face: .none, from: 30).last?.guidance,
                       .keepTurning)
    }

    func testLeavingTheSpotAsksTheUserToComeBack() {
        let engine = CalibrationEngine()
        captureFront(engine)
        var moved = turned(r: 1.0, delta: 0)
        // Past maxCentreDrift (0.08) but inside the framing window (0.10), so the stance
        // check fires rather than the framing guidance above it.
        moved.midX = 0.5 + 0.09

        let outputs = run(engine, body: moved, face: .none, from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertEqual(outputs.last?.guidance, .returnToStart)
    }

    func testMovementResetsTheHoldTimer() {
        let engine = CalibrationEngine()
        var body = Body()
        var t = 0.0
        while t < 0.5 {  // 0.5 s still: not enough on its own
            XCTAssertNil(engine.process(frame(body, .frontal, at: t)).capture)
            t += 0.1
        }
        body.midX += 0.05  // one jump restarts the timer
        let jump = engine.process(frame(body, .frontal, at: t))
        XCTAssertNil(jump.capture)
        XCTAssertEqual(jump.guidance, .holdStill)
        XCTAssertEqual(jump.holdProgress, 0)
        t += 0.1

        var outputs: [CalibrationEngineOutput] = []
        while t < 1.1 {  // 0.5 s more is still short of 0.8 s counted from the jump
            outputs.append(engine.process(frame(body, .frontal, at: t)))
            t += 0.1
        }
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertNotNil(run(engine, body: body, face: .frontal, from: t).compactMap(\.capture).first)
    }

    func testTimeoutFiresOncePerStalledView() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // 31 s stuck facing the camera while the left turn is due.
        let outputs = run(engine, body: turned(r: 1.0, delta: 0), face: .frontal, from: 10, duration: 31)
        XCTAssertEqual(outputs.filter(\.didTimeOut).count, 1)
    }
}
