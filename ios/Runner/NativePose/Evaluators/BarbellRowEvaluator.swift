import Foundation

struct BarbellRowEvaluatorConfig {
    var minJointConfidence = 0.30
    var rowPullDeltaThreshold = 0.010
    var rowLowerDeltaThreshold = -0.010
    var bottomRowDepthThreshold = 0.06
    var topRowDepthThreshold = 0.45
    var bottomElbowAngleThreshold = 145.0
    var topElbowAngleThreshold = 130.0
    var statusConfirmationFrames = 3
    var minStatusDurationFrames = 4
    var forceTransitionFrames = 8
    var maxUnknownFramesWithValidDepth = 10
    var minRepRowDepthNorm = 0.06
    var validRepTopElbowAngleThreshold = 130.0
    var maxStoredRepSummaries = 100
}

final class BarbellRowEvaluator {
    private enum COCO17 {
        static let leftShoulder = 5
        static let rightShoulder = 6
        static let leftElbow = 7
        static let rightElbow = 8
        static let leftWrist = 9
        static let rightWrist = 10
        static let leftHip = 11
        static let rightHip = 12
    }

    private struct Measurements {
        let rowDepthNorm: Double?
        let rowDepthDeltaNorm: Double?
        let leftElbowAngleDegrees: Double?
        let rightElbowAngleDegrees: Double?
        let avgElbowAngleDegrees: Double?
        let torsoLeanAngleDegrees: Double?
        let wristToTorsoDistNorm: Double?
        let validDepth: Bool
    }

    private let config: BarbellRowEvaluatorConfig
    private var stableStatus: BarbellRowStatus = .unknown
    private var candidateStatus: BarbellRowStatus = .unknown
    private var candidateStatusCount = 0
    private var statusFrameCount = 0
    private var previousRowDepthNorm: Double?
    private var didInitializeStableStatus = false
    private var unknownFramesWithValidDepth = 0
    private var bottomWristDistanceBaseline: Double?

    private var repStarted = false
    private var sawPulling = false
    private var sawLowering = false
    private var currentRepStartFrame: Int?
    private var currentRepTopFrame: Int?
    private var currentRepMaxRowDepthNorm: Double?
    private var currentRepMinElbowAngleDegrees: Double?
    private var completedRepCount = 0
    private(set) var completedRepSummaries: [BarbellRowRepSummary] = []

    var sessionSummary: BarbellRowSessionSummary {
        makeSessionSummary()
    }

    init(config: BarbellRowEvaluatorConfig = BarbellRowEvaluatorConfig()) {
        self.config = config
    }

    /// Form warnings (rep summary `warnings`); judged only between startRep and the counted rep end.
    let formTracker = FormWarningTracker(exercise: .barbellRow)

    func reset() {
        stableStatus = .unknown
        candidateStatus = .unknown
        candidateStatusCount = 0
        statusFrameCount = 0
        previousRowDepthNorm = nil
        didInitializeStableStatus = false
        unknownFramesWithValidDepth = 0
        bottomWristDistanceBaseline = nil
        repStarted = false
        sawPulling = false
        sawLowering = false
        currentRepStartFrame = nil
        currentRepTopFrame = nil
        currentRepMaxRowDepthNorm = nil
        currentRepMinElbowAngleDegrees = nil
        completedRepCount = 0
        completedRepSummaries = []
        formTracker.reset()
    }

    /// `pose3D`: MotionAGFormer H36M17 selected3D when available (form metrics only; nil in the live app).
    func evaluate(frameIndex: Int, coco17: [PoseKeypoint], pose3D: [SIMD3<Double>]? = nil) -> BarbellRowFrameResult {
        let measurements = computeMeasurements(coco17: coco17)
        let rawCandidate = classifyRawStatusCandidate(measurements)
        let previousStatus = stableStatus
        let status = updateStableStatus(
            rawCandidate: rawCandidate,
            rowDepthNorm: measurements.rowDepthNorm,
            avgElbowAngleDegrees: measurements.avgElbowAngleDegrees
        )

        updateBottomBaselineIfNeeded(status: status, measurements: measurements)
        formTracker.observe(frameIndex: frameIndex, coco17: coco17, pose3D: pose3D, phase: status.rawValue)
        let done = updateRepState(
            frameIndex: frameIndex,
            previousStatus: previousStatus,
            status: status,
            measurements: measurements
        )
        if repStarted { formTracker.recordCurrentFrame() }

        previousRowDepthNorm = measurements.rowDepthNorm

        return BarbellRowFrameResult(
            frameIndex: frameIndex,
            status: status,
            rawStatusCandidate: rawCandidate,
            candidateStatus: candidateStatus,
            candidateStatusCount: candidateStatusCount,
            statusFrameCount: statusFrameCount,
            rep: completedRepCount,
            done: done,
            rowDepthNorm: measurements.rowDepthNorm,
            rowDepthDeltaNorm: measurements.rowDepthDeltaNorm,
            leftElbowAngleDegrees: measurements.leftElbowAngleDegrees,
            rightElbowAngleDegrees: measurements.rightElbowAngleDegrees,
            avgElbowAngleDegrees: measurements.avgElbowAngleDegrees,
            torsoLeanAngleDegrees: measurements.torsoLeanAngleDegrees,
            currentRepMaxRowDepthNorm: currentRepMaxRowDepthNorm,
            currentRepMinElbowAngleDegrees: currentRepMinElbowAngleDegrees,
            repStarted: repStarted,
            sawPulling: sawPulling,
            sawLowering: sawLowering,
            lastCompletedRepSummary: completedRepSummaries.last
        )
    }

    private func computeMeasurements(coco17: [PoseKeypoint]) -> Measurements {
        guard coco17.count == 17,
              jointsAreConfident(coco17) else {
            return Measurements(
                rowDepthNorm: nil,
                rowDepthDeltaNorm: nil,
                leftElbowAngleDegrees: nil,
                rightElbowAngleDegrees: nil,
                avgElbowAngleDegrees: nil,
                torsoLeanAngleDegrees: nil,
                wristToTorsoDistNorm: nil,
                validDepth: false
            )
        }

        let leftShoulder = coco17[COCO17.leftShoulder]
        let rightShoulder = coco17[COCO17.rightShoulder]
        let leftElbow = coco17[COCO17.leftElbow]
        let rightElbow = coco17[COCO17.rightElbow]
        let leftWrist = coco17[COCO17.leftWrist]
        let rightWrist = coco17[COCO17.rightWrist]
        let leftHip = coco17[COCO17.leftHip]
        let rightHip = coco17[COCO17.rightHip]

        let shoulderCenter = average(leftShoulder, rightShoulder)
        let hipCenter = average(leftHip, rightHip)
        let wristCenter = average(leftWrist, rightWrist)
        let lowerChestProxy = weightedAverage(shoulderCenter, hipCenter, shoulderWeight: 0.65)
        let torsoLength = max(distance(shoulderCenter, hipCenter), 1.0)
        let wristToTorsoDistNorm = distance(wristCenter, lowerChestProxy) / torsoLength
        if bottomWristDistanceBaseline == nil {
            bottomWristDistanceBaseline = wristToTorsoDistNorm
        }

        let depthNorm = (bottomWristDistanceBaseline ?? wristToTorsoDistNorm) - wristToTorsoDistNorm
        let depthDeltaNorm = optionalDiff(depthNorm, previousRowDepthNorm)
        let leftElbowAngle = Self.angle2D(a: leftShoulder, b: leftElbow, c: leftWrist)
        let rightElbowAngle = Self.angle2D(a: rightShoulder, b: rightElbow, c: rightWrist)
        let avgElbowAngle = averageValid(leftElbowAngle, rightElbowAngle)
        let torsoLean = torsoLeanAngleDegrees(shoulderCenter: shoulderCenter, hipCenter: hipCenter)

        return Measurements(
            rowDepthNorm: depthNorm,
            rowDepthDeltaNorm: depthDeltaNorm,
            leftElbowAngleDegrees: leftElbowAngle,
            rightElbowAngleDegrees: rightElbowAngle,
            avgElbowAngleDegrees: avgElbowAngle,
            torsoLeanAngleDegrees: torsoLean,
            wristToTorsoDistNorm: wristToTorsoDistNorm,
            validDepth: true
        )
    }

    private func classifyRawStatusCandidate(_ measurements: Measurements) -> BarbellRowStatus {
        guard let depth = measurements.rowDepthNorm else { return .unknown }
        if let delta = measurements.rowDepthDeltaNorm {
            if delta > config.rowPullDeltaThreshold {
                return .pulling
            }
            if delta < config.rowLowerDeltaThreshold {
                return .lowering
            }
        }
        if depth < config.bottomRowDepthThreshold ||
            (measurements.avgElbowAngleDegrees.map { $0 > config.bottomElbowAngleThreshold } ?? false) {
            return .bottom
        }
        if depth > config.topRowDepthThreshold ||
            (measurements.avgElbowAngleDegrees.map { $0 < config.topElbowAngleThreshold } ?? false) {
            return .top
        }
        return .unknown
    }

    private func updateStableStatus(
        rawCandidate: BarbellRowStatus,
        rowDepthNorm: Double?,
        avgElbowAngleDegrees: Double?
    ) -> BarbellRowStatus {
        if !didInitializeStableStatus {
            didInitializeStableStatus = true
            let initialStatus = initialStableStatus(
                rowDepthNorm: rowDepthNorm,
                avgElbowAngleDegrees: avgElbowAngleDegrees
            )
            if initialStatus != .unknown {
                stableStatus = initialStatus
                candidateStatus = initialStatus
                candidateStatusCount = 1
                statusFrameCount = 0
                unknownFramesWithValidDepth = 0
                return stableStatus
            }
        }

        if rawCandidate == candidateStatus {
            candidateStatusCount += 1
        } else {
            candidateStatus = rawCandidate
            candidateStatusCount = 1
        }

        if stableStatus == .unknown, let depth = rowDepthNorm {
            unknownFramesWithValidDepth += 1
            if unknownFramesWithValidDepth > config.maxUnknownFramesWithValidDepth {
                let fallback = unknownFallbackStatus(depth: depth, rawCandidate: rawCandidate)
                if fallback != .unknown {
                    stableStatus = fallback
                    candidateStatus = fallback
                    candidateStatusCount = 1
                    statusFrameCount = 0
                    unknownFramesWithValidDepth = 0
                    return stableStatus
                }
            }
        } else if stableStatus != .unknown {
            unknownFramesWithValidDepth = 0
        }

        let candidateReady = candidateStatus != stableStatus
            && candidateStatusCount >= config.statusConfirmationFrames
            && statusFrameCount >= config.minStatusDurationFrames
        if candidateReady {
            let transitionAllowed = isAllowedTransition(from: stableStatus, to: candidateStatus)
            let forceTransition = candidateStatusCount >= config.forceTransitionFrames
            if transitionAllowed || forceTransition {
                stableStatus = candidateStatus
                statusFrameCount = 0
                return stableStatus
            }
        }

        statusFrameCount += 1
        return stableStatus
    }

    private func initialStableStatus(
        rowDepthNorm: Double?,
        avgElbowAngleDegrees: Double?
    ) -> BarbellRowStatus {
        guard let depth = rowDepthNorm,
              let elbowAngle = avgElbowAngleDegrees else { return .unknown }
        if depth < config.bottomRowDepthThreshold || elbowAngle > config.bottomElbowAngleThreshold {
            return .bottom
        }
        if depth > config.topRowDepthThreshold || elbowAngle < config.topElbowAngleThreshold {
            return .top
        }
        return .unknown
    }

    private func unknownFallbackStatus(depth: Double, rawCandidate: BarbellRowStatus) -> BarbellRowStatus {
        if rawCandidate == .pulling || rawCandidate == .lowering {
            return rawCandidate
        }
        let bottomDistance = abs(depth - config.bottomRowDepthThreshold)
        let topDistance = abs(config.topRowDepthThreshold - depth)
        return bottomDistance <= topDistance ? .bottom : .top
    }

    private func isAllowedTransition(from current: BarbellRowStatus, to next: BarbellRowStatus) -> Bool {
        guard current != next else { return false }
        switch current {
        case .unknown:
            return next == .bottom || next == .pulling
        case .bottom:
            return next == .pulling
        case .pulling:
            return next == .top || next == .lowering
        case .top:
            return next == .lowering || next == .pulling
        case .lowering:
            return next == .bottom || next == .pulling
        }
    }

    private func updateBottomBaselineIfNeeded(status: BarbellRowStatus, measurements: Measurements) {
        guard status == .bottom,
              let distanceNorm = measurements.wristToTorsoDistNorm,
              let elbowAngle = measurements.avgElbowAngleDegrees,
              elbowAngle > config.bottomElbowAngleThreshold else { return }
        bottomWristDistanceBaseline = max(bottomWristDistanceBaseline ?? distanceNorm, distanceNorm)
    }

    private func updateRepState(
        frameIndex: Int,
        previousStatus: BarbellRowStatus,
        status: BarbellRowStatus,
        measurements: Measurements
    ) -> Bool {
        var done = false

        if !repStarted,
           status == .pulling,
           previousStatus == .bottom || previousStatus == .unknown {
            startRep(frameIndex: frameIndex)
        }

        if repStarted && status == .pulling {
            sawPulling = true
        }
        if repStarted && status == .lowering {
            sawLowering = true
        }

        if repStarted && (status == .pulling || status == .top) {
            updateCurrentRep(measurements)
        }

        if repStarted,
           currentRepTopFrame == nil,
           previousStatus == .pulling,
           status == .top || status == .lowering {
            currentRepTopFrame = frameIndex
        }

        if repStarted,
           previousStatus == .lowering,
           status == .bottom {
            done = finalizeRepIfValid(frameIndex: frameIndex)
            resetCurrentRep()
        } else if status == .bottom && !repStarted {
            resetCurrentRep()
        }

        return done
    }

    private func startRep(frameIndex: Int) {
        repStarted = true
        sawPulling = true
        sawLowering = false
        currentRepStartFrame = frameIndex
        currentRepTopFrame = nil
        currentRepMaxRowDepthNorm = nil
        currentRepMinElbowAngleDegrees = nil
        formTracker.beginRep()
    }

    private func updateCurrentRep(_ measurements: Measurements) {
        if let depth = measurements.rowDepthNorm {
            currentRepMaxRowDepthNorm = max(currentRepMaxRowDepthNorm ?? depth, depth)
        }
        if let elbowAngle = measurements.avgElbowAngleDegrees {
            currentRepMinElbowAngleDegrees = min(currentRepMinElbowAngleDegrees ?? elbowAngle, elbowAngle)
        }
    }

    private func finalizeRepIfValid(frameIndex: Int) -> Bool {
        guard repStarted,
              sawPulling,
              sawLowering,
              let startFrame = currentRepStartFrame,
              let maxDepth = currentRepMaxRowDepthNorm else {
            return false
        }
        let minElbowAngle = currentRepMinElbowAngleDegrees
        let depthValid = maxDepth >= config.minRepRowDepthNorm
        let elbowValid = minElbowAngle.map { $0 <= config.validRepTopElbowAngleThreshold } ?? false
        guard depthValid || elbowValid else { return false }

        completedRepCount += 1
        let summary = BarbellRowRepSummary(
            repIndex: completedRepCount,
            startFrame: startFrame,
            topFrame: currentRepTopFrame,
            endFrame: frameIndex,
            maxRowDepthNorm: maxDepth,
            minElbowAngleDegrees: minElbowAngle,
            warnings: formTracker.finishRep(repIndex: completedRepCount).warnings
        )
        completedRepSummaries.append(summary)
        trimCompletedRepSummaries()
        let maxDepthText = String(format: "%.3f", maxDepth)
        let minElbowText = minElbowAngle.map { String(format: "%.1f", $0) } ?? "-"
        print("Barbell row rep completed: rep=\(completedRepCount) frame=\(frameIndex) maxDepth=\(maxDepthText) minElbow=\(minElbowText) done=true")
        return true
    }

    private func trimCompletedRepSummaries() {
        if completedRepSummaries.count > config.maxStoredRepSummaries {
            completedRepSummaries.removeFirst(completedRepSummaries.count - config.maxStoredRepSummaries)
        }
    }

    private func resetCurrentRep() {
        repStarted = false
        sawPulling = false
        sawLowering = false
        currentRepStartFrame = nil
        currentRepTopFrame = nil
        currentRepMaxRowDepthNorm = nil
        currentRepMinElbowAngleDegrees = nil
    }

    private func makeSessionSummary() -> BarbellRowSessionSummary {
        let maxDepths = completedRepSummaries.map { $0.maxRowDepthNorm }
        return BarbellRowSessionSummary(
            completedRepCount: completedRepCount,
            repCount: completedRepCount,
            avgMaxRowDepthNorm: average(maxDepths),
            minElbowAngleDegrees: completedRepSummaries.compactMap { $0.minElbowAngleDegrees }.min(),
            maxRowDepthNorm: maxDepths.max()
        )
    }

    private func jointsAreConfident(_ coco17: [PoseKeypoint]) -> Bool {
        [
            COCO17.leftShoulder,
            COCO17.rightShoulder,
            COCO17.leftElbow,
            COCO17.rightElbow,
            COCO17.leftWrist,
            COCO17.rightWrist,
            COCO17.leftHip,
            COCO17.rightHip,
        ].allSatisfy { index in
            coco17.indices.contains(index) && coco17[index].confidence >= config.minJointConfidence
        }
    }

    private func optionalDiff(_ value: Double?, _ previous: Double?) -> Double? {
        guard let value, let previous else { return nil }
        return value - previous
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0, +) / Double(values.count)
    }

    private func averageValid(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case let (.some(a), .some(b)):
            return (a + b) * 0.5
        case let (.some(a), .none):
            return a
        case let (.none, .some(b)):
            return b
        case (.none, .none):
            return nil
        }
    }

    private func average(_ a: PoseKeypoint, _ b: PoseKeypoint) -> PoseKeypoint {
        PoseKeypoint(
            x: (a.x + b.x) * 0.5,
            y: (a.y + b.y) * 0.5,
            confidence: (a.confidence + b.confidence) * 0.5
        )
    }

    private func weightedAverage(_ shoulder: PoseKeypoint, _ hip: PoseKeypoint, shoulderWeight: Double) -> PoseKeypoint {
        let hipWeight = 1.0 - shoulderWeight
        return PoseKeypoint(
            x: shoulder.x * shoulderWeight + hip.x * hipWeight,
            y: shoulder.y * shoulderWeight + hip.y * hipWeight,
            confidence: min(shoulder.confidence, hip.confidence)
        )
    }

    private func distance(_ a: PoseKeypoint, _ b: PoseKeypoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func torsoLeanAngleDegrees(shoulderCenter: PoseKeypoint, hipCenter: PoseKeypoint) -> Double? {
        let dx = shoulderCenter.x - hipCenter.x
        let dy = shoulderCenter.y - hipCenter.y
        let norm = sqrt(dx * dx + dy * dy)
        guard norm > 1e-8 else { return nil }
        return abs(atan2(dx, dy)) * 180.0 / .pi
    }

    private static func angle2D(a: PoseKeypoint, b: PoseKeypoint, c: PoseKeypoint) -> Double? {
        let ux = a.x - b.x
        let uy = a.y - b.y
        let vx = c.x - b.x
        let vy = c.y - b.y
        let uNorm = sqrt(ux * ux + uy * uy)
        let vNorm = sqrt(vx * vx + vy * vy)
        guard uNorm > 1e-8, vNorm > 1e-8 else { return nil }
        let cosine = min(max((ux * vx + uy * vy) / (uNorm * vNorm), -1.0), 1.0)
        return acos(cosine) * 180.0 / .pi
    }
}
