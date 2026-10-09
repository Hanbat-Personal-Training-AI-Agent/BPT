import Foundation

struct SquatEvaluatorConfig {
    var squatMinJointConfidence = 0.30
    var descendDeltaThreshold = 0.012
    var ascendDeltaThreshold = -0.012
    var topDepthThreshold = 0.10
    var bottomDepthThreshold = 0.22
    var topKneeAngleThreshold = 145.0
    var bottomKneeAngleThreshold = 110.0
    var statusConfirmationFrames = 3
    var minStatusDurationFrames = 4
    var forceTransitionFrames = 8
    var maxUnknownFramesWithValidDepth = 10
    var minRepDepthNorm = 0.16
    var validRepBottomKneeAngleThreshold = 130.0
    var maxStoredRepSummaries = 100
}

final class SquatEvaluator {
    private enum COCO17 {
        static let leftShoulder = 5
        static let rightShoulder = 6
        static let leftHip = 11
        static let rightHip = 12
        static let leftKnee = 13
        static let rightKnee = 14
        static let leftAnkle = 15
        static let rightAnkle = 16
    }

    private struct Measurements {
        let squatDepthNorm: Double?
        let squatDepthDeltaNorm: Double?
        let leftKneeAngleDegrees: Double?
        let rightKneeAngleDegrees: Double?
        let avgKneeAngleDegrees: Double?
        let hipCenterY: Double?
        let kneeCenterY: Double?
        let ankleCenterY: Double?
        let validDepth: Bool
    }

    private let config: SquatEvaluatorConfig
    private var stableStatus: SquatStatus = .unknown
    private var candidateStatus: SquatStatus = .unknown
    private var candidateStatusCount = 0
    private var statusFrameCount = 0
    private var previousSquatDepthNorm: Double?
    private var didInitializeStableStatus = false
    private var unknownFramesWithValidDepth = 0
    private var topHipYBaseline: Double?

    private var repStarted = false
    private var sawDescending = false
    private var sawAscending = false
    private var activeRepIndex = 0
    private var completedRepCount = 0
    private var currentRepStartFrame: Int?
    private var currentRepBottomFrame: Int?
    private var currentRepMaxDepthNorm: Double?
    private var currentRepMinKneeAngleDegrees: Double?
    private(set) var completedRepSummaries: [SquatRepSummary] = []
    /// Form warnings (rep summary `warnings`); judged only between startRep and the counted rep end.
    let formTracker = FormWarningTracker(exercise: .squat)

    var sessionSummary: SquatSessionSummary {
        makeSessionSummary()
    }

    init(config: SquatEvaluatorConfig = SquatEvaluatorConfig()) {
        self.config = config
    }

    func reset() {
        stableStatus = .unknown
        candidateStatus = .unknown
        candidateStatusCount = 0
        statusFrameCount = 0
        previousSquatDepthNorm = nil
        didInitializeStableStatus = false
        unknownFramesWithValidDepth = 0
        topHipYBaseline = nil
        repStarted = false
        sawDescending = false
        sawAscending = false
        activeRepIndex = 0
        completedRepCount = 0
        currentRepStartFrame = nil
        currentRepBottomFrame = nil
        currentRepMaxDepthNorm = nil
        currentRepMinKneeAngleDegrees = nil
        completedRepSummaries = []
        formTracker.reset()
    }

    /// `pose3D`: MotionAGFormer H36M17 selected3D when available (form metrics only; nil in the live app).
    /// `feet`: Halpe26 toes/heels (squat_heel_rise only; nil with the COCO17 model).
    func evaluate(frameIndex: Int, coco17: [PoseKeypoint], pose3D: [SIMD3<Double>]? = nil,
                  feet: FootKeypoints? = nil) -> SquatFrameResult {
        let measurements = computeMeasurements(coco17: coco17)
        let rawCandidate = classifyRawStatusCandidate(measurements)
        let previousStatus = stableStatus
        let status = updateStableStatus(
            rawCandidate: rawCandidate,
            squatDepthNorm: measurements.squatDepthNorm,
            avgKneeAngleDegrees: measurements.avgKneeAngleDegrees
        )

        updateTopBaselineIfNeeded(status: status, measurements: measurements)
        formTracker.observe(frameIndex: frameIndex, coco17: coco17, pose3D: pose3D, feet: feet, phase: status.rawValue)
        let done = updateRepState(
            frameIndex: frameIndex,
            previousStatus: previousStatus,
            status: status,
            measurements: measurements
        )
        if repStarted { formTracker.recordCurrentFrame() }

        if frameIndex % 30 == 0 {
            let depthText = measurements.squatDepthNorm.map { String(format: "%.3f", $0) } ?? "nil"
            let deltaText = measurements.squatDepthDeltaNorm.map { String(format: "%.3f", $0) } ?? "nil"
            let angleText = measurements.avgKneeAngleDegrees.map { String(format: "%.1f", $0) } ?? "nil"
            print("Squat frame=\(frameIndex) stable=\(status.rawValue) raw=\(rawCandidate.rawValue) candidate=\(candidateStatus.rawValue)/\(candidateStatusCount) depth=\(depthText) delta=\(deltaText) kneeAngle=\(angleText) rep=\(completedRepCount) done=\(done)")
        }

        previousSquatDepthNorm = measurements.squatDepthNorm

        return SquatFrameResult(
            frameIndex: frameIndex,
            status: status,
            rawStatusCandidate: rawCandidate,
            candidateStatus: candidateStatus,
            candidateStatusCount: candidateStatusCount,
            statusFrameCount: statusFrameCount,
            rep: completedRepCount,
            done: done,
            squatDepthNorm: measurements.squatDepthNorm,
            squatDepthDeltaNorm: measurements.squatDepthDeltaNorm,
            leftKneeAngleDegrees: measurements.leftKneeAngleDegrees,
            rightKneeAngleDegrees: measurements.rightKneeAngleDegrees,
            avgKneeAngleDegrees: measurements.avgKneeAngleDegrees,
            hipCenterY: measurements.hipCenterY,
            kneeCenterY: measurements.kneeCenterY,
            ankleCenterY: measurements.ankleCenterY,
            currentRepMaxDepthNorm: currentRepMaxDepthNorm,
            currentRepMinKneeAngleDegrees: currentRepMinKneeAngleDegrees,
            lastCompletedRepSummary: completedRepSummaries.last
        )
    }

    private func computeMeasurements(coco17: [PoseKeypoint]) -> Measurements {
        guard coco17.count == 17,
              jointsAreConfident(coco17) else {
            return Measurements(
                squatDepthNorm: nil,
                squatDepthDeltaNorm: nil,
                leftKneeAngleDegrees: nil,
                rightKneeAngleDegrees: nil,
                avgKneeAngleDegrees: nil,
                hipCenterY: nil,
                kneeCenterY: nil,
                ankleCenterY: nil,
                validDepth: false
            )
        }

        let leftHip = coco17[COCO17.leftHip]
        let rightHip = coco17[COCO17.rightHip]
        let leftKnee = coco17[COCO17.leftKnee]
        let rightKnee = coco17[COCO17.rightKnee]
        let leftAnkle = coco17[COCO17.leftAnkle]
        let rightAnkle = coco17[COCO17.rightAnkle]

        let hipCenter = average(leftHip, rightHip)
        let kneeCenter = average(leftKnee, rightKnee)
        let ankleCenter = average(leftAnkle, rightAnkle)
        let legLength = max(averageLegLength(coco17), 1.0)
        if topHipYBaseline == nil {
            topHipYBaseline = hipCenter.y
        }

        let depthNorm = (hipCenter.y - (topHipYBaseline ?? hipCenter.y)) / legLength
        let depthDeltaNorm = optionalDiff(depthNorm, previousSquatDepthNorm)
        let leftKneeAngle = Self.angle2D(a: leftHip, b: leftKnee, c: leftAnkle)
        let rightKneeAngle = Self.angle2D(a: rightHip, b: rightKnee, c: rightAnkle)
        let avgKneeAngle = averageValid(leftKneeAngle, rightKneeAngle)

        return Measurements(
            squatDepthNorm: depthNorm,
            squatDepthDeltaNorm: depthDeltaNorm,
            leftKneeAngleDegrees: leftKneeAngle,
            rightKneeAngleDegrees: rightKneeAngle,
            avgKneeAngleDegrees: avgKneeAngle,
            hipCenterY: hipCenter.y,
            kneeCenterY: kneeCenter.y,
            ankleCenterY: ankleCenter.y,
            validDepth: true
        )
    }

    private func classifyRawStatusCandidate(_ measurements: Measurements) -> SquatStatus {
        guard let depth = measurements.squatDepthNorm else { return .unknown }

        let kneeAngle = measurements.avgKneeAngleDegrees

        // 1. TOP position first
        if depth < config.topDepthThreshold,
           let kneeAngle,
           kneeAngle > config.topKneeAngleThreshold {
            return .top
        }

        // 2. BOTTOM position second
        if depth > config.bottomDepthThreshold ||
            (kneeAngle.map { $0 < config.bottomKneeAngleThreshold } ?? false) {
            return .bottom
        }

        // 3. Direction after position
        if let delta = measurements.squatDepthDeltaNorm {
            if delta > config.descendDeltaThreshold {
                return .descending
            }
            if delta < config.ascendDeltaThreshold {
                return .ascending
            }
        }

        return .unknown
    }

    private func updateStableStatus(
        rawCandidate: SquatStatus,
        squatDepthNorm: Double?,
        avgKneeAngleDegrees: Double?
    ) -> SquatStatus {
        if !didInitializeStableStatus {
            didInitializeStableStatus = true
            let initialStatus = initialStableStatus(
                squatDepthNorm: squatDepthNorm,
                avgKneeAngleDegrees: avgKneeAngleDegrees
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

        let nextCandidate = rawCandidate
        if nextCandidate == candidateStatus {
            candidateStatusCount += 1
        } else {
            candidateStatus = nextCandidate
            candidateStatusCount = 1
        }

        if stableStatus == .unknown, let depth = squatDepthNorm {
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
        squatDepthNorm: Double?,
        avgKneeAngleDegrees: Double?
    ) -> SquatStatus {
        guard let depth = squatDepthNorm,
              let kneeAngle = avgKneeAngleDegrees else { return .unknown }
        if depth < config.topDepthThreshold && kneeAngle > config.topKneeAngleThreshold {
            return .top
        }
        return .unknown
    }

    private func unknownFallbackStatus(depth: Double, rawCandidate: SquatStatus) -> SquatStatus {
        if rawCandidate == .descending || rawCandidate == .ascending {
            return rawCandidate
        }
        let topDistance = abs(depth - config.topDepthThreshold)
        let bottomDistance = abs(config.bottomDepthThreshold - depth)
        return topDistance <= bottomDistance ? .top : .bottom
    }

    private func isAllowedTransition(from current: SquatStatus, to next: SquatStatus) -> Bool {
        guard current != next else { return false }
        switch current {
        case .unknown:
            return next == .top || next == .descending
        case .top:
            return next == .descending
        case .descending:
            return next == .bottom || next == .ascending
        case .bottom:
            return next == .ascending || next == .descending
        case .ascending:
            return next == .top || next == .descending
        }
    }

    private func updateTopBaselineIfNeeded(status: SquatStatus, measurements: Measurements) {
        guard status == .top,
              let hipY = measurements.hipCenterY,
              let kneeAngle = measurements.avgKneeAngleDegrees,
              kneeAngle > config.topKneeAngleThreshold else { return }
        topHipYBaseline = min(topHipYBaseline ?? hipY, hipY)
    }

    private func updateRepState(
        frameIndex: Int,
        previousStatus: SquatStatus,
        status: SquatStatus,
        measurements: Measurements
    ) -> Bool {
        var done = false

        if !repStarted,
           status == .descending,
           previousStatus == .top || previousStatus == .unknown {
            startRep(frameIndex: frameIndex)
        }

        if repStarted && status == .descending {
            sawDescending = true
        }
        if repStarted && status == .ascending {
            sawAscending = true
        }

        if repStarted && (status == .descending || status == .bottom) {
            updateCurrentRep(measurements)
        }

        if repStarted,
           currentRepBottomFrame == nil,
           (previousStatus == .descending && (status == .ascending || status == .bottom)) {
            currentRepBottomFrame = frameIndex
        }

        if repStarted,
           previousStatus == .ascending,
           status == .top {
            done = finalizeRepIfValid(frameIndex: frameIndex)
            resetCurrentRep()
        } else if status == .top && !repStarted {
            resetCurrentRep()
        }

        return done
    }

    private func startRep(frameIndex: Int) {
        repStarted = true
        sawDescending = true
        sawAscending = false
        activeRepIndex = completedRepCount + 1
        currentRepStartFrame = frameIndex
        currentRepBottomFrame = nil
        currentRepMaxDepthNorm = nil
        currentRepMinKneeAngleDegrees = nil
        formTracker.beginRep()
    }

    private func updateCurrentRep(_ measurements: Measurements) {
        if let depth = measurements.squatDepthNorm {
            currentRepMaxDepthNorm = max(currentRepMaxDepthNorm ?? depth, depth)
        }
        if let kneeAngle = measurements.avgKneeAngleDegrees {
            currentRepMinKneeAngleDegrees = min(currentRepMinKneeAngleDegrees ?? kneeAngle, kneeAngle)
        }
    }

    private func finalizeRepIfValid(frameIndex: Int) -> Bool {
        guard repStarted,
              sawDescending,
              sawAscending,
              let startFrame = currentRepStartFrame,
              let maxDepth = currentRepMaxDepthNorm else {
            return false
        }
        let minKneeAngle = currentRepMinKneeAngleDegrees
        let depthValid = maxDepth >= config.minRepDepthNorm
        let kneeValid = minKneeAngle.map { $0 <= config.validRepBottomKneeAngleThreshold } ?? false
        guard depthValid || kneeValid else { return false }

        completedRepCount += 1
        let summary = SquatRepSummary(
            repIndex: completedRepCount,
            startFrame: startFrame,
            bottomFrame: currentRepBottomFrame,
            endFrame: frameIndex,
            maxDepthNorm: maxDepth,
            minKneeAngleDegrees: minKneeAngle,
            warnings: formTracker.finishRep(repIndex: completedRepCount).warnings
        )
        completedRepSummaries.append(summary)
        trimCompletedRepSummaries()
        let maxDepthText = String(format: "%.3f", maxDepth)
        let minKneeText = minKneeAngle.map { String(format: "%.1f", $0) } ?? "-"
        print("Squat rep completed: rep=\(completedRepCount) frame=\(frameIndex) maxDepth=\(maxDepthText) minKnee=\(minKneeText) done=true")
        return true
    }

    private func trimCompletedRepSummaries() {
        if completedRepSummaries.count > config.maxStoredRepSummaries {
            completedRepSummaries.removeFirst(completedRepSummaries.count - config.maxStoredRepSummaries)
        }
    }

    private func resetCurrentRep() {
        repStarted = false
        sawDescending = false
        sawAscending = false
        currentRepStartFrame = nil
        currentRepBottomFrame = nil
        currentRepMaxDepthNorm = nil
        currentRepMinKneeAngleDegrees = nil
    }

    private func makeSessionSummary() -> SquatSessionSummary {
        let maxDepths = completedRepSummaries.map { $0.maxDepthNorm }
        return SquatSessionSummary(
            completedRepCount: completedRepCount,
            repCount: completedRepCount,
            avgMaxDepthNorm: average(maxDepths),
            minKneeAngleDegrees: completedRepSummaries.compactMap { $0.minKneeAngleDegrees }.min(),
            maxDepthNorm: maxDepths.max()
        )
    }

    private func jointsAreConfident(_ coco17: [PoseKeypoint]) -> Bool {
        [
            COCO17.leftHip,
            COCO17.rightHip,
            COCO17.leftKnee,
            COCO17.rightKnee,
            COCO17.leftAnkle,
            COCO17.rightAnkle,
        ].allSatisfy { index in
            coco17.indices.contains(index) && coco17[index].confidence >= config.squatMinJointConfidence
        }
    }

    private func averageLegLength(_ coco17: [PoseKeypoint]) -> Double {
        let left = distance(coco17[COCO17.leftHip], coco17[COCO17.leftKnee])
            + distance(coco17[COCO17.leftKnee], coco17[COCO17.leftAnkle])
        let right = distance(coco17[COCO17.rightHip], coco17[COCO17.rightKnee])
            + distance(coco17[COCO17.rightKnee], coco17[COCO17.rightAnkle])
        return max((left + right) * 0.5, 1.0)
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

    private func distance(_ a: PoseKeypoint, _ b: PoseKeypoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
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
