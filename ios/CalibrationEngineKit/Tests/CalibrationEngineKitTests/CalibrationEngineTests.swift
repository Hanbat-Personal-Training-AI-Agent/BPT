import XCTest

@testable import CalibrationEngineKit

/// Synthetic-keypoint tests for the calibration judging engine.
///
/// The builder below produces a body that passes framing and A-pose, so each test
/// only varies what it is about (yaw cues, stance drift, motion).
final class CalibrationEngineTests: XCTestCase {
    // Portrait 1080x1920 buffer.
    private let aspect = 1080.0 / 1920.0

    private struct Body {
        var shoulderY = 0.30
        var hipY = 0.55
        var midX = 0.5
        var ankleY = 0.90
        /// Shoulder and hip widths in height units; shrinking them is what turning looks like.
        var shoulderWidth = 0.40 * 0.25
        var hipWidth = 0.32 * 0.25
        var wristDrop = 0.75
        var elbowRatio = 0.5
        var face = 0.9
        var earLeft = 0.8
        var earRight = 0.8
        /// Nose offset from the shoulder midpoint, in torso lengths.
        var noseOffset = 0.0
    }

    private func keypoints(_ b: Body) -> [CalibrationKeypoint] {
        let torso = b.hipY - b.shoulderY
        let toX = { (heightUnits: Double) in heightUnits / self.aspect }
        var kps = Array(repeating: CalibrationKeypoint(x: b.midX, y: b.shoulderY, score: 0.9), count: 17)

        func set(_ joint: CocoJoint, _ x: Double, _ y: Double, _ score: Double = 0.9) {
            kps[joint.rawValue] = CalibrationKeypoint(x: x, y: y, score: score)
        }

        let noseX = b.midX + toX(b.noseOffset * torso)
        set(.nose, noseX, b.shoulderY - 0.5 * torso, b.face)
        set(.leftEye, noseX + toX(0.02), b.shoulderY - 0.55 * torso, b.face)
        set(.rightEye, noseX - toX(0.02), b.shoulderY - 0.55 * torso, b.face)
        set(.leftEar, noseX + toX(0.05), b.shoulderY - 0.5 * torso, b.earLeft)
        set(.rightEar, noseX - toX(0.05), b.shoulderY - 0.5 * torso, b.earRight)

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

    private func frame(_ b: Body, at t: TimeInterval) -> CalibrationFrame {
        CalibrationFrame(keypoints: keypoints(b), aspect: aspect, timestamp: t, device: .still)
    }

    /// Feeds frames until the engine captures, or the window runs out.
    @discardableResult
    private func run(_ engine: CalibrationEngine,
                     body: Body,
                     from start: TimeInterval,
                     duration: TimeInterval = 1.2,
                     step: TimeInterval = 0.1) -> [CalibrationEngineOutput] {
        var outputs: [CalibrationEngineOutput] = []
        var t = start
        while t <= start + duration {
            outputs.append(engine.process(frame(body, at: t)))
            t += step
        }
        return outputs
    }

    private func captureFront(_ engine: CalibrationEngine) -> CalibrationEngineOutput {
        let outputs = run(engine, body: Body(), from: 0)
        return outputs.first { $0.capture != nil } ?? outputs.last!
    }

    /// A turned body: widths shrink by |cos yaw|, the nose swings, one ear disappears.
    private func turned(r: Double, delta: Double, earLeft: Double, earRight: Double, face: Double = 0.6) -> Body {
        var b = Body()
        b.shoulderWidth *= r
        b.hipWidth *= r
        b.noseOffset = delta
        b.earLeft = earLeft
        b.earRight = earRight
        b.face = face
        return b
    }

    func testFrontCapturesAndStoresReference() {
        let engine = CalibrationEngine()
        let outputs = run(engine, body: Body(), from: 0)

        let captured = outputs.compactMap(\.capture)
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.view, .front)
        XCTAssertEqual(engine.capturedViews, [.front])
        XCTAssertNotNil(engine.reference)
        // Nothing fires before the hold is satisfied.
        XCTAssertNil(outputs.first?.capture)
        XCTAssertEqual(outputs.first?.guidance, .holdStill)
    }

    func testObliqueSignDecidesLeftOrRight() {
        let right = CalibrationEngine()
        captureFront(right)
        // Nose swung towards the image right (positive delta) with the right ear visible.
        let rightOutputs = run(right, body: turned(r: 0.5, delta: 0.3, earLeft: 0.1, earRight: 0.8), from: 10)
        XCTAssertEqual(rightOutputs.compactMap(\.capture).first?.view, .rightfront)

        let left = CalibrationEngine()
        captureFront(left)
        let leftOutputs = run(left, body: turned(r: 0.5, delta: -0.3, earLeft: 0.8, earRight: 0.1), from: 10)
        XCTAssertEqual(leftOutputs.compactMap(\.capture).first?.view, .leftfront)
    }

    func testMismatchedEarAndSignIsNotClassified() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // Nose says "turned right", ears say "turned left".
        let outputs = run(engine, body: turned(r: 0.5, delta: 0.3, earLeft: 0.8, earRight: 0.1), from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertEqual(engine.capturedViews, [.front])
    }

    func testTurnedHeadIsRejected() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // Body oblique, but both ears and the face are still fully visible.
        let outputs = run(engine, body: turned(r: 0.5, delta: 0.3, earLeft: 0.6, earRight: 0.6, face: 0.9), from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertEqual(outputs.last?.guidance, .faceForwardWithBody)
    }

    func testBackIsCaptured() {
        let engine = CalibrationEngine()
        captureFront(engine)
        let outputs = run(engine, body: turned(r: 1.0, delta: 0, earLeft: 0.1, earRight: 0.1, face: 0.1), from: 10)
        XCTAssertEqual(outputs.compactMap(\.capture).first?.view, .back)
    }

    func testObliqueIsNotMistakenForBack() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // Hidden face and ears, but the body is still side-on: r is far below the back gate.
        let outputs = run(engine, body: turned(r: 0.5, delta: 0.3, earLeft: 0.1, earRight: 0.1, face: 0.1), from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertFalse(engine.capturedViews.contains(.back))
    }

    func testLeavingTheSpotAsksTheUserToComeBack() {
        let engine = CalibrationEngine()
        captureFront(engine)
        var moved = turned(r: 1.0, delta: 0, earLeft: 0.1, earRight: 0.1, face: 0.1)
        // Past maxCentreDrift (0.08) but still inside the framing window (0.10), so the
        // stance check is what fires rather than the framing guidance above it.
        moved.midX = 0.5 + 0.09

        let outputs = run(engine, body: moved, from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertEqual(outputs.last?.guidance, .returnToStart)
    }

    func testMovementResetsTheHoldTimer() {
        let engine = CalibrationEngine()
        var t = 0.0
        var body = Body()
        // Hold still for 0.5 s: not enough on its own.
        while t < 0.5 {
            XCTAssertNil(engine.process(frame(body, at: t)).capture)
            t += 0.1
        }
        // One jump: motion exceeds the threshold and the timer restarts.
        body.midX += 0.05
        let jump = engine.process(frame(body, at: t))
        XCTAssertNil(jump.capture)
        XCTAssertEqual(jump.guidance, .holdStill)
        XCTAssertEqual(jump.holdProgress, 0)
        t += 0.1

        // 0.5 s more is still short of the 0.8 s hold measured from the jump.
        var outputs: [CalibrationEngineOutput] = []
        while t < 1.1 {
            outputs.append(engine.process(frame(body, at: t)))
            t += 0.1
        }
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertNotNil(run(engine, body: body, from: t).compactMap(\.capture).first)
    }
}
