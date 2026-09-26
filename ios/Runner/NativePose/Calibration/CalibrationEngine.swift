import Foundation

/// Decides, frame by frame, what to tell the user and when to take a picture.
///
/// Pure logic: no UIKit, no AVFoundation, no clock of its own. Input is keypoints,
/// aspect, a timestamp and the device state; output is guidance, a view classification
/// and a capture decision. That keeps it unit-testable with synthetic keypoints.
final class CalibrationEngine {
    let config: CalibrationConfig

    private(set) var capturedViews: [CalibrationView] = []
    private(set) var reference: CalibrationReference?

    private var holdStartedAt: TimeInterval?
    private var holdView: CalibrationView?
    private var holdSamples: [CalibrationMeasurement] = []
    private var lastCaptureAt: TimeInterval?
    private var previousJoints: [Int: (x: Double, y: Double)] = [:]
    private var previousTimestamp: TimeInterval?
    private var targetStartedAt: TimeInterval?
    private var lastTarget: CalibrationView?

    init(config: CalibrationConfig = .default) {
        self.config = config
    }

    func reset() {
        capturedViews = []
        reference = nil
        resetHold()
        lastCaptureAt = nil
        previousJoints = [:]
        previousTimestamp = nil
        targetStartedAt = nil
        lastTarget = nil
    }

    var isFinished: Bool { capturedViews.count == CalibrationView.allCases.count }

    /// Next view to steer towards: the first uncaptured one along the recommended turn.
    var targetView: CalibrationView? {
        CalibrationView.recommendedOrder.first { !capturedViews.contains($0) }
    }

    func process(_ frame: CalibrationFrame) -> CalibrationEngineOutput {
        let target = targetView
        let didTimeOut = updateTimeout(target: target, now: frame.timestamp)

        if isFinished {
            return output(.finished, target: nil, measurement: nil, didTimeOut: false)
        }

        // 1. Device
        if frame.device.isAvailable {
            if abs(frame.device.rollDeg) > config.device.maxRollDeg
                || abs(frame.device.pitchDeg) > config.device.maxPitchDeg {
                return fail(.holdPhoneUpright, target: target, measurement: nil, didTimeOut: didTimeOut)
            }
            if frame.device.userAccelerationG > config.device.maxUserAccelerationG
                || frame.device.rotationRateRadPerSec > config.device.maxRotationRateRadPerSec {
                return fail(.holdPhoneStill, target: target, measurement: nil, didTimeOut: didTimeOut)
            }
        }

        // 2. Person and full body
        guard hasPerson(frame) else {
            previousJoints = [:]
            return fail(.stepIntoFrame, target: target, measurement: nil, didTimeOut: didTimeOut)
        }
        guard let measurement = measure(frame) else {
            previousJoints = [:]
            return fail(.showFullBody, target: target, measurement: nil, didTimeOut: didTimeOut)
        }
        let motion = motionSince(frame)

        // 3. Framing
        if let guidance = framingGuidance(measurement, frontCaptured: reference != nil) {
            return fail(guidance, target: target, measurement: measurement, didTimeOut: didTimeOut)
        }

        // 4. Stance, once the front reference exists
        if let reference {
            if abs(measurement.feet - reference.feet) > config.stance.maxFeetDrift
                || abs(measurement.midX - reference.midX) > config.stance.maxCentreDrift {
                return fail(.returnToStart, target: target, measurement: measurement, didTimeOut: didTimeOut)
            }
        }

        // 5. A-pose
        if let guidance = aPoseGuidance(measurement, isFrontStage: reference == nil) {
            return fail(guidance, target: target, measurement: measurement, didTimeOut: didTimeOut)
        }

        // 6. View classification
        let classification = classify(measurement)
        guard let classified = classification.view, !capturedViews.contains(classified) else {
            let guidance = classification.guidance ?? rotationGuidance(measurement, target: target)
            return fail(guidance, target: target, measurement: measurement, didTimeOut: didTimeOut)
        }

        // 7. Stillness
        if motion > config.capture.maxMotion {
            return fail(.holdStill, target: classified, measurement: measurement, didTimeOut: didTimeOut)
        }
        if holdView != classified {
            holdView = classified
            holdStartedAt = frame.timestamp
            holdSamples = []
        }
        holdSamples.append(measurement)
        let heldFor = frame.timestamp - (holdStartedAt ?? frame.timestamp)
        let progress = min(1, heldFor / config.capture.holdDuration)

        let inCooldown = lastCaptureAt.map { frame.timestamp - $0 < config.capture.cooldown } ?? false
        guard heldFor >= config.capture.holdDuration, !inCooldown else {
            var out = output(.holdStill, target: classified, measurement: measurement, didTimeOut: didTimeOut)
            out.classifiedView = classified
            out.holdProgress = progress
            out.isPassing = true
            return out
        }

        // 8. Capture
        return capture(view: classified, measurement: measurement, frame: frame, didTimeOut: didTimeOut)
    }

    // MARK: - Measurement

    private func hasPerson(_ frame: CalibrationFrame) -> Bool {
        frame.keypoints.contains { $0.score >= config.framing.minKeypointConfidence }
    }

    private func joint(_ frame: CalibrationFrame, _ j: CocoJoint) -> CalibrationKeypoint? {
        guard j.rawValue < frame.keypoints.count else { return nil }
        let kp = frame.keypoints[j.rawValue]
        return kp.score >= config.framing.minKeypointConfidence ? kp : nil
    }

    private func measure(_ frame: CalibrationFrame) -> CalibrationMeasurement? {
        var required: [CocoJoint: CalibrationKeypoint] = [:]
        for j in CocoJoint.required {
            guard let kp = joint(frame, j) else { return nil }
            required[j] = kp
        }
        let aspect = frame.aspect
        let ls = required[.leftShoulder]!, rs = required[.rightShoulder]!
        let lh = required[.leftHip]!, rh = required[.rightHip]!
        let shoulderX = (ls.x + rs.x) / 2, shoulderY = (ls.y + rs.y) / 2
        let hipX = (lh.x + rh.x) / 2, hipY = (lh.y + rh.y) / 2
        let torso = hipY - shoulderY
        guard torso > 1e-6 else { return nil }

        let headTop = shoulderY - config.framing.headTopTorsoFactor * torso
        let feet = max(required[.leftAnkle]!.y, required[.rightAnkle]!.y)
            + config.framing.feetTorsoFactor * torso

        func drop(_ wrist: CalibrationKeypoint) -> Double { (wrist.y - shoulderY) / torso }
        func elbowRatio(_ elbow: CalibrationKeypoint, _ wrist: CalibrationKeypoint) -> Double {
            let span = wrist.y - shoulderY
            return abs(span) < 1e-6 ? .infinity : (elbow.y - shoulderY) / span
        }

        let nose = frame.keypoints[CocoJoint.nose.rawValue]
        let faceScores = [nose.score,
                          frame.keypoints[CocoJoint.leftEye.rawValue].score,
                          frame.keypoints[CocoJoint.rightEye.rawValue].score]
        let midX = (shoulderX + hipX) / 2
        let wristReach = min(abs(required[.leftWrist]!.x - midX), abs(required[.rightWrist]!.x - midX))
            * aspect / torso
        let hipWidth = abs(lh.x - rh.x) * aspect
        let ankleGap = abs(required[.leftAnkle]!.x - required[.rightAnkle]!.x) * aspect

        return CalibrationMeasurement(
            torso: torso,
            shoulderWidth: abs(ls.x - rs.x) * aspect,
            hipWidth: hipWidth,
            headTop: headTop,
            feet: feet,
            bodyHeight: feet - headTop,
            midX: midX,
            leftWristDrop: drop(required[.leftWrist]!),
            rightWristDrop: drop(required[.rightWrist]!),
            leftElbowRatio: elbowRatio(required[.leftElbow]!, required[.leftWrist]!),
            rightElbowRatio: elbowRatio(required[.rightElbow]!, required[.rightWrist]!),
            face: faceScores.reduce(0, +) / Double(faceScores.count),
            noseOffset: (nose.x - shoulderX) * aspect / torso,
            earLeft: frame.keypoints[CocoJoint.leftEar.rawValue].score,
            earRight: frame.keypoints[CocoJoint.rightEar.rawValue].score,
            wristReach: wristReach,
            ankleGapOverHipWidth: hipWidth < 1e-6 ? .infinity : ankleGap / hipWidth,
            meanRequiredConfidence: CocoJoint.required.map { required[$0]!.score }.reduce(0, +)
                / Double(CocoJoint.required.count)
        )
    }

    /// Mean per-joint travel since the previous frame, in torso lengths.
    private func motionSince(_ frame: CalibrationFrame) -> Double {
        var current: [Int: (x: Double, y: Double)] = [:]
        for j in CocoJoint.required {
            guard let kp = joint(frame, j) else { continue }
            current[j.rawValue] = (kp.x * frame.aspect, kp.y)
        }
        defer {
            previousJoints = current
            previousTimestamp = frame.timestamp
        }
        guard !previousJoints.isEmpty,
              let torso = measure(frame)?.torso, torso > 1e-6 else { return 0 }
        var total = 0.0
        var count = 0
        for (index, point) in current {
            guard let previous = previousJoints[index] else { continue }
            total += hypot(point.x - previous.x, point.y - previous.y)
            count += 1
        }
        return count == 0 ? 0 : (total / Double(count)) / torso
    }

    // MARK: - Checks

    private func framingGuidance(_ m: CalibrationMeasurement, frontCaptured: Bool) -> CalibrationGuidance? {
        if m.bodyHeight > config.framing.maxBodyHeight { return .stepBack }
        if m.headTop < config.framing.minHeadTop || m.feet > config.framing.maxFeet { return .showFullBody }
        if m.bodyHeight < config.framing.minBodyHeight { return .stepForward }
        if abs(m.midX - 0.5) > config.framing.maxCentreOffset {
            guard !frontCaptured else { return .moveToCentre }
            // Unmirrored buffer: a body left of centre has to move further left in the user's own frame.
            return m.midX < 0.5 ? .moveLeft : .moveRight
        }
        return nil
    }

    private func aPoseGuidance(_ m: CalibrationMeasurement, isFrontStage: Bool) -> CalibrationGuidance? {
        if m.leftWristDrop > config.aPose.maxWristDrop || m.rightWristDrop > config.aPose.maxWristDrop {
            return .openArmsWider
        }
        if m.leftWristDrop < config.aPose.minWristDrop || m.rightWristDrop < config.aPose.minWristDrop {
            return .lowerArms
        }
        for ratio in [m.leftElbowRatio, m.rightElbowRatio] {
            if ratio < config.aPose.minElbowRatio || ratio > config.aPose.maxElbowRatio {
                return .straightenElbows
            }
        }
        if isFrontStage {
            if m.wristReach < config.aPose.minWristReach { return .openArmsWider }
            if m.ankleGapOverHipWidth < config.aPose.minAnkleGapOverHipWidth
                || m.ankleGapOverHipWidth > config.aPose.maxAnkleGapOverHipWidth {
                return .widenFeet
            }
        }
        return nil
    }

    // MARK: - View classification

    /// `|cos yaw|`, from how much the shoulders and hips have narrowed against the front reference.
    func rValue(_ m: CalibrationMeasurement) -> Double? {
        guard let reference, reference.shoulderRatio > 1e-6, reference.hipRatio > 1e-6 else { return nil }
        let w = config.view.shoulderWeight
        let value = w * (m.shoulderWidth / m.torso) / reference.shoulderRatio
            + (1 - w) * (m.hipWidth / m.torso) / reference.hipRatio
        return min(max(value, 0), 1)
    }

    func delta(_ m: CalibrationMeasurement) -> Double? {
        guard let reference else { return nil }
        return m.noseOffset - reference.noseOffset
    }

    private func classify(_ m: CalibrationMeasurement) -> (view: CalibrationView?, guidance: CalibrationGuidance?) {
        guard reference != nil else {
            let isFront = m.face >= config.view.frontMinFace
                && abs(m.noseOffset) <= config.view.frontMaxNoseOffset
                && abs(m.earLeft - m.earRight) <= config.view.frontMaxEarDifference
            return (isFront ? .front : nil, nil)
        }
        guard let r = rValue(m), let d = delta(m) else { return (nil, nil) }

        let inObliqueBand = r >= config.view.obliqueMinR && r <= config.view.obliqueMaxR
        if inObliqueBand,
           m.earLeft >= config.view.turnedHeadEarMin,
           m.earRight >= config.view.turnedHeadEarMin,
           m.face >= config.view.frontMinFace {
            // Body is oblique but the head swivelled back to the camera: the shot would not match the yaw.
            return (nil, .faceForwardWithBody)
        }

        if inObliqueBand, m.face >= config.view.obliqueMinFace, abs(d) >= config.view.obliqueMinDelta {
            let rightEarNear = m.earRight >= config.view.obliqueNearEarMin
                && m.earLeft <= config.view.obliqueFarEarMax
            let leftEarNear = m.earLeft >= config.view.obliqueNearEarMin
                && m.earRight <= config.view.obliqueFarEarMax
            if d > 0, rightEarNear { return (.rightfront, nil) }
            if d < 0, leftEarNear { return (.leftfront, nil) }
            return (nil, nil)  // sign and ears disagree: do not classify
        }

        let faceGate = min(config.view.backMaxFace, config.view.backFaceRefFactor * (reference?.face ?? 1))
        if m.face <= faceGate,
           m.earLeft <= config.view.backMaxEar,
           m.earRight <= config.view.backMaxEar,
           r >= config.view.backMinR {
            return (.back, nil)
        }
        return (nil, nil)
    }

    private func rotationGuidance(_ m: CalibrationMeasurement,
                                  target: CalibrationView?) -> CalibrationGuidance {
        guard let target, let r = rValue(m) else { return .keepTurning }
        switch target {
        case .leftfront, .rightfront:
            if r > config.view.obliqueMaxR { return .keepTurning }
            if r < config.view.obliqueMinR, m.face >= config.view.obliqueMinFace { return .turnedTooFar }
            return .keepTurning
        case .back, .front:
            return .keepTurning
        }
    }

    // MARK: - Capture

    private func capture(view: CalibrationView,
                         measurement: CalibrationMeasurement,
                         frame: CalibrationFrame,
                         didTimeOut: Bool) -> CalibrationEngineOutput {
        let samples = holdSamples
        if view == .front {
            reference = CalibrationReference(
                shoulderRatio: median(samples.map { $0.shoulderWidth / $0.torso }),
                hipRatio: median(samples.map { $0.hipWidth / $0.torso }),
                noseOffset: median(samples.map(\.noseOffset)),
                feet: median(samples.map(\.feet)),
                midX: median(samples.map(\.midX)),
                face: median(samples.map(\.face))
            )
        }
        let request = CalibrationCaptureRequest(
            view: view,
            holdStartedAt: holdStartedAt ?? frame.timestamp,
            measurement: measurement,
            reference: reference ?? CalibrationReference(shoulderRatio: 0, hipRatio: 0, noseOffset: 0,
                                                         feet: 0, midX: 0, face: 0),
            r: rValue(measurement),
            delta: delta(measurement),
            isLastView: capturedViews.count + 1 == CalibrationView.allCases.count
        )
        capturedViews.append(view)
        lastCaptureAt = frame.timestamp
        targetStartedAt = frame.timestamp
        resetHold()

        var out = output(isFinished ? .finished : .captured(view),
                         target: targetView, measurement: measurement, didTimeOut: didTimeOut)
        out.classifiedView = view
        out.capture = request
        out.holdProgress = 1
        out.isPassing = true
        return out
    }

    private func updateTimeout(target: CalibrationView?, now: TimeInterval) -> Bool {
        if target != lastTarget {
            lastTarget = target
            targetStartedAt = now
            return false
        }
        guard let started = targetStartedAt else {
            targetStartedAt = now
            return false
        }
        if now - started >= config.capture.viewTimeout {
            targetStartedAt = now
            return true
        }
        return false
    }

    private func resetHold() {
        holdStartedAt = nil
        holdView = nil
        holdSamples = []
    }

    private func fail(_ guidance: CalibrationGuidance,
                      target: CalibrationView?,
                      measurement: CalibrationMeasurement?,
                      didTimeOut: Bool) -> CalibrationEngineOutput {
        resetHold()
        return output(guidance, target: target, measurement: measurement, didTimeOut: didTimeOut)
    }

    private func output(_ guidance: CalibrationGuidance,
                        target: CalibrationView?,
                        measurement: CalibrationMeasurement?,
                        didTimeOut: Bool) -> CalibrationEngineOutput {
        CalibrationEngineOutput(
            guidance: guidance,
            classifiedView: nil,
            targetView: target,
            capturedViews: capturedViews,
            holdProgress: 0,
            isPassing: false,
            capture: nil,
            measurement: measurement,
            didTimeOut: didTimeOut
        )
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
