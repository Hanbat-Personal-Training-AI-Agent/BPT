import XCTest

@testable import CalibrationEngineKit

/// Synthetic-input tests for the calibration judging engine.
///
/// The builder produces a body that passes framing and A-pose, so each test only varies
/// what it is about: width (r), nose swing (δ), the face detection result, stance, motion.
final class CalibrationEngineTests: XCTestCase {
    // Portrait 1080x1920 buffer.
    private let aspect = 1080.0 / 1920.0

    /// Torso 0.20 tall: head top 0.21, feet 0.872, so the body is 0.66 of the frame,
    /// inside the guide's 0.62 ± 0.07.
    private struct Body {
        var shoulderY = 0.36
        var hipY = 0.56
        var midX = 0.5
        var ankleY = 0.86
        /// Shoulder and hip widths in height units; shrinking them is what turning looks like.
        var shoulderWidth = 0.40 * 0.25
        var hipWidth = 0.32 * 0.25
        var wristDrop = 0.75
        var elbowRatio = 0.5
        /// Nose offset from the shoulder midpoint, in torso lengths.
        var noseOffset = 0.0
        /// Seen from behind, every left joint sits on the image left.
        var facingAway = false
    }

    private func keypoints(_ b: Body) -> [CalibrationKeypoint] {
        let torso = b.hipY - b.shoulderY
        let side = b.facingAway ? -1.0 : 1.0
        let toX = { (heightUnits: Double) in side * heightUnits / self.aspect }
        var kps = Array(repeating: CalibrationKeypoint(x: b.midX, y: b.shoulderY, score: 0.9), count: 17)

        func set(_ joint: CocoJoint, _ x: Double, _ y: Double) {
            kps[joint.rawValue] = CalibrationKeypoint(x: x, y: y, score: 0.9)
        }

        // RTMPose scores the face and ears high from every side, so they stay 0.9 throughout.
        let noseX = b.midX + side * toX(b.noseOffset * torso)
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
            let output = engine.process(frame(body, face, at: $0))
            if let request = output.capture {
                return engine.resolveCapture(id: request.id, saved: true)!
            }
            return output
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

    /// Past 90°: the back half of the turn, shoulders reversed in the image.
    private func turnedAway(r: Double, delta: Double) -> Body {
        var b = turned(r: r, delta: delta)
        b.facingAway = true
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
        let outputs = run(engine, body: turnedAway(r: 0.5, delta: 0.3), face: .none, from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertEqual(engine.capturedViews, [.front])
    }

    func testBackObliqueWithHeadStillTowardsTheCameraIsNotOblique() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // Body at 120° (same r as 60°), head lagging behind so Vision still finds the face.
        let outputs = run(engine, body: turnedAway(r: 0.5, delta: 0.3), face: face(yaw: 60), from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
        XCTAssertEqual(engine.capturedViews, [.front])
    }

    // MARK: - Back

    func testBackIsCaptured() {
        let engine = CalibrationEngine()
        captureFront(engine)
        let outputs = run(engine, body: turnedAway(r: 1.0, delta: 0), face: .none, from: 10)
        XCTAssertEqual(outputs.compactMap(\.capture).first?.view, .back)
    }

    func testFacingTheCameraAgainIsNotBack() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // Full width with a face: still the front, which is already captured.
        let outputs = run(engine, body: turned(r: 1.0, delta: 0), face: .frontal, from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.capture == nil })
    }

    func testFrontWithMissedFaceIsNotBack() {
        let engine = CalibrationEngine()
        captureFront(engine)
        // Vision misses the face, but the shoulders still face the camera.
        let outputs = run(engine, body: turned(r: 1.0, delta: 0), face: .none, from: 10)
        XCTAssertFalse(engine.capturedViews.contains(.back))
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
        run(fromBack, body: turnedAway(r: 1.0, delta: 0), face: .none, from: 20)
        XCTAssertEqual(fromBack.capturedViews, [.front, .rightfront, .back])
        XCTAssertEqual(run(fromBack, body: turnedAway(r: 0.15, delta: -0.1), face: .none, from: 30).last?.guidance,
                       .keepTurning)
    }

    func testLeavingTheSpotAsksTheUserToComeBack() {
        let engine = CalibrationEngine()
        captureFront(engine)
        var moved = turnedAway(r: 1.0, delta: 0)
        // A step towards the camera: same size and centre, so framing still passes, but the
        // feet sit 0.04 lower than at the front capture (maxFeetDrift 0.03).
        moved.shoulderY += 0.04
        moved.hipY += 0.04
        moved.ankleY += 0.04

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

    private func request(_ engine: CalibrationEngine, body: Body = Body(),
                         face: CalibrationFace = .frontal, from start: Double = 0) throws -> CalibrationCaptureRequest {
        for t in stride(from: start, through: start + 1.5, by: 0.1) {
            if let request = engine.process(frame(body, face, at: t)).capture { return request }
        }
        throw NSError(domain: "No capture request", code: 1)
    }

    func testCaptureWaitsForPersistenceAndIgnoresDuplicateOrStaleACKs() throws {
        let engine = CalibrationEngine()
        let pending = try request(engine)
        XCTAssertEqual(engine.capturedViews, [])
        XCTAssertNil(engine.reference)
        XCTAssertFalse(engine.isFinished)
        XCTAssertNil(engine.process(frame(Body(), .frontal, at: 2)).capture)
        XCTAssertNil(engine.resolveCapture(id: UUID(), saved: true))
        let saved = try XCTUnwrap(engine.resolveCapture(id: pending.id, saved: true))
        XCTAssertEqual(saved.guidance, .captured(.front))
        XCTAssertEqual(engine.capturedViews, [.front])
        XCTAssertNotNil(engine.reference)
        XCTAssertNil(engine.resolveCapture(id: pending.id, saved: true))
        engine.reset()
        XCTAssertNil(engine.resolveCapture(id: pending.id, saved: true))
        XCTAssertNil(engine.reference)
    }

    func testFailedSaveCanRetakeSameViewWithoutCommittingReference() throws {
        let engine = CalibrationEngine()
        let first = try request(engine)
        let failed = engine.resolveCapture(id: first.id, saved: false)
        XCTAssertEqual(failed?.guidance, .saveFailed)
        XCTAssertEqual(engine.capturedViews, [])
        XCTAssertEqual(engine.targetView, .front)
        XCTAssertNil(engine.reference)
        let retry = try request(engine, from: 2)
        XCTAssertNotEqual(first.id, retry.id)
        XCTAssertNil(engine.resolveCapture(id: first.id, saved: true))
        engine.resolveCapture(id: retry.id, saved: true)
        XCTAssertEqual(engine.capturedViews, [.front])
    }

    func testLastViewIsNotFinishedUntilItsSaveSucceeds() throws {
        let engine = CalibrationEngine()
        captureFront(engine)
        run(engine, body: turned(r: 0.5, delta: 0.3), face: face(yaw: 60), from: 10)
        run(engine, body: turnedAway(r: 1, delta: 0), face: .none, from: 20)
        let pending = try request(engine, body: turned(r: 0.5, delta: -0.3), face: face(yaw: -60), from: 30)
        XCTAssertTrue(pending.isLastView)
        XCTAssertFalse(engine.isFinished)
        engine.resolveCapture(id: pending.id, saved: false)
        XCTAssertFalse(engine.isFinished)
        XCTAssertEqual(engine.capturedViews.count, 3)
        let retry = try request(engine, body: turned(r: 0.5, delta: -0.3), face: face(yaw: -60), from: 40)
        XCTAssertEqual(engine.resolveCapture(id: retry.id, saved: true)?.guidance, .finished)
        XCTAssertTrue(engine.isFinished)
    }

    func testSpeedAndCaptureTimeAgreeAtTenFifteenAndThirtyFPS() throws {
        for fps in [10.0, 15.0, 30.0] {
            let engine = CalibrationEngine()
            var captureTime: Double?
            for index in 0...Int(fps) {
                let t = Double(index) / fps
                var body = Body()
                // Exactly 0.1 torso lengths / second, independent of sample rate.
                body.midX += 0.1 * (body.hipY - body.shoulderY) * t / aspect
                let output = engine.process(frame(body, .frontal, at: t))
                if index > 0 { XCTAssertEqual(try XCTUnwrap(engine.lastMotion), 0.1, accuracy: 1e-10) }
                if output.capture != nil { captureTime = t; break }
            }
            XCTAssertEqual(try XCTUnwrap(captureTime), 0.8, accuracy: 1e-8)

            let fast = CalibrationEngine()
            _ = fast.process(frame(Body(), .frontal, at: 0))
            var moved = Body()
            moved.midX += 0.6 * (moved.hipY - moved.shoulderY) / fps / aspect
            let output = fast.process(frame(moved, .frontal, at: 1 / fps))
            XCTAssertEqual(try XCTUnwrap(fast.lastMotion), 0.6, accuracy: 1e-10)
            XCTAssertEqual(output.holdProgress, 0)
            XCTAssertFalse(output.isPassing)
        }
    }

    func testIrregularValidSamplingKeepsAContinuousHold() {
        let engine = CalibrationEngine()
        let times = [0.0, 0.05, 0.16, 0.24, 0.35, 0.49, 0.59, 0.73, 0.85]
        var output: CalibrationEngineOutput?
        for time in times { output = engine.process(frame(Body(), .frontal, at: time)) }
        XCTAssertNotNil(output?.capture)
    }

    func testDroppedIntervalDoesNotCountTowardsHold() {
        let engine = CalibrationEngine()
        for i in 0...7 { _ = engine.process(frame(Body(), .frontal, at: Double(i) / 10)) }
        let afterGap = engine.process(frame(Body(), .frontal, at: 2))
        XCTAssertNil(afterGap.capture)
        XCTAssertEqual(afterGap.holdProgress, 0)
        XCTAssertEqual(afterGap.holdStartedAt, 2)
        XCTAssertNotNil(run(engine, body: Body(), face: .frontal, from: 2.1).compactMap(\.capture).first)
    }

    func testInferenceFailureAndNonmonotonicTimestampsBreakHold() {
        for invalidTime in [Double.nan, 0.5, 0.4] {
            let engine = CalibrationEngine()
            for i in 0...5 { _ = engine.process(frame(Body(), .frontal, at: Double(i) / 10)) }
            let invalid = engine.process(frame(Body(), .frontal, at: invalidTime))
            XCTAssertEqual(invalid.guidance, .trackingUnavailable)
            let next = engine.process(frame(Body(), .frontal, at: 0.7))
            XCTAssertEqual(next.holdProgress, 0)
            XCTAssertNil(next.capture)
        }
        let engine = CalibrationEngine()
        for i in 0...5 { _ = engine.process(frame(Body(), .frontal, at: Double(i) / 10)) }
        engine.invalidateFrame()
        XCTAssertEqual(engine.process(frame(Body(), .frontal, at: 0.6)).holdProgress, 0)
    }

    func testMinimumSamplesAndUnknownFaceCannotCapture() {
        var config = CalibrationConfig.default
        config.capture.maxFrameGap = 1
        let sparse = CalibrationEngine(config: config)
        for t in [0.0, 0.4, 0.8] { XCTAssertNil(sparse.process(frame(Body(), .frontal, at: t)).capture) }

        let back = CalibrationEngine()
        captureFront(back)
        let outputs = run(back, body: turnedAway(r: 1, delta: 0), face: .unknown, from: 10)
        XCTAssertTrue(outputs.allSatisfy { $0.guidance == .trackingUnavailable && $0.capture == nil })
        XCTAssertEqual(back.capturedViews, [.front])
    }

    func testShortAndNonfiniteKeypointsAreRejectedWithoutIndexing() {
        let engine = CalibrationEngine()
        var input = frame(Body(), .frontal, at: 0)
        input.keypoints = []
        XCTAssertEqual(engine.process(input).guidance, .trackingUnavailable)
        input = frame(Body(), .frontal, at: 0.1)
        input.keypoints[0].x = .nan
        XCTAssertEqual(engine.process(input).guidance, .trackingUnavailable)
    }

    func testStoreFailurePreservesManifestAndSelectedFrameMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var failManifest = false
        var failJPEG = true
        let store = try CalibrationStore(sessionId: "test-session", rootDirectory: root) { data, url in
            if (failManifest && url.lastPathComponent == "manifest.json") ||
                (failJPEG && url.pathExtension == "jpg") { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        let engine = CalibrationEngine()
        let pending = try request(engine)
        var selected = frame(Body(), .frontal, at: 0.2)
        selected.device.gravity = [0.01, -0.99, 0.02]
        selected.device.timestamp = 123.4
        selected.keypoints = selected.keypoints.map { CalibrationKeypoint(x: $0.x, y: $0.y, score: 0.8) }
        let measurement = try XCTUnwrap(CalibrationEngine().process(selected).measurement)
        let snapshot = CalibrationStore.Snapshot(frame: selected, measurement: measurement,
            imageWidth: 1000, imageHeight: 2000,
            intrinsics: .init(fx: 1111, fy: 1112, cx: 499, cy: 999, source: "attachment"))
        let record = CalibrationStore.ViewRecord(label: .front, snapshot: snapshot, r: 1, delta: 0)
        let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
        let manifestURL = store.directory.appendingPathComponent("manifest.json")
        XCTAssertThrowsError(try store.writeCapture(jpeg: jpeg, record: record, userHeightCm: 175, reference: pending.reference))
        XCTAssertEqual(store.capturedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestURL.path))
        failJPEG = false
        failManifest = true
        XCTAssertThrowsError(try store.writeCapture(jpeg: jpeg, record: record, userHeightCm: 175, reference: pending.reference))
        XCTAssertEqual(store.capturedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestURL.path))
        failManifest = false
        try store.writeCapture(jpeg: jpeg, record: record, userHeightCm: 175, reference: pending.reference)
        engine.resolveCapture(id: pending.id, saved: true)
        let committed = try Data(contentsOf: manifestURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: committed) as? [String: Any])
        let view = try XCTUnwrap((json["views"] as? [[String: Any]])?.first)
        XCTAssertEqual(view["timestamp"] as? Double, 0.2) // not capture-request time 0.8
        XCTAssertEqual(view["deviceTimestamp"] as? Double, 123.4)
        XCTAssertEqual(view["gravity"] as? [Double], selected.device.gravity)
        XCTAssertEqual(view["face"] as? Double, measurement.face)
        XCTAssertEqual((view["intrinsics"] as? [String: Any])?["fx"] as? Double, 1111)
        XCTAssertEqual((view["keypoints"] as? [[Double]])?[0], [selected.keypoints[0].x * 1000, selected.keypoints[0].y * 2000, 0.8])
        XCTAssertEqual(json["isComplete"] as? Bool, false)
        XCTAssertThrowsError(try store.writeCapture(jpeg: jpeg, record: record, userHeightCm: 175, reference: pending.reference))
        let next = CalibrationStore.ViewRecord(label: .rightfront, snapshot: snapshot, r: 0.5, delta: 0.3)
        failManifest = true
        XCTAssertThrowsError(try store.writeCapture(jpeg: jpeg, record: next, userHeightCm: 175, reference: pending.reference))
        XCTAssertEqual(try Data(contentsOf: manifestURL), committed)
        XCTAssertEqual(store.capturedCount, 1)
        failManifest = false
        for view in [CalibrationView.rightfront, .back, .leftfront] {
            try store.writeCapture(jpeg: jpeg, record: .init(label: view, snapshot: snapshot, r: nil, delta: nil),
                                   userHeightCm: 175, reference: pending.reference)
        }
        let complete = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        XCTAssertEqual(complete["isComplete"] as? Bool, true)
        XCTAssertEqual(store.capturedCount, 4)
    }

    func testGateAllowsOnlyOneInFlightFrameAcrossQueues() {
        let gate = CalibrationFrameGate()
        let counterLock = NSLock()
        var running = 0
        var maximum = 0
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            guard gate.acquire() else { return }
            counterLock.lock()
            running += 1
            maximum = max(maximum, running)
            counterLock.unlock()
            Thread.sleep(forTimeInterval: 0.0001)
            counterLock.lock()
            running -= 1
            counterLock.unlock()
            gate.release()
        }
        XCTAssertEqual(maximum, 1)
        XCTAssertTrue(gate.acquire())
        XCTAssertFalse(gate.acquire())
        let released = expectation(description: "released on another queue")
        DispatchQueue.global().async { gate.release(); released.fulfill() }
        wait(for: [released], timeout: 2)
        XCTAssertTrue(gate.acquire())
        gate.release()
    }

    func testHandsAreOptionalForSquatAndExplicitlyOverridable() {
        XCTAssertFalse(NativePoseExercise.squat.handBranchEnabled())
        XCTAssertTrue(NativePoseExercise.squat.handBranchEnabled(override: true))
        for exercise in NativePoseExercise.allCases where exercise != .squat {
            XCTAssertTrue(exercise.handBranchEnabled())
            XCTAssertFalse(exercise.handBranchEnabled(override: false))
        }
    }
}
