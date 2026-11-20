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
    /// D-T3-13: frames with no evidence (in-between depth while moving slowly, or briefly unconfident legs)
    /// keep the current status instead of forcing `unknown` after forceTransitionFrames.
    var holdStatusThroughUnknown = true
    var maxLowConfidenceHoldFrames = 30
    /// D-T3-13: when only one leg's hip/knee/ankle are all confident (side view), measure that leg alone.
    var nearLegFallback = true
    /// D-T3-13: legs straight this many frames in a row while not `top` → reset the standing hip baseline (0 = off).
    var rebaselineStraightLegFrames = 30
    /// D-T3-13: second rep signal = hip height above the ankles ÷ standing leg length (longest leg in the
    /// last 90 frames, so a foreshortened thigh does not shrink it), counted by PushUpHeightCounter (range
    /// of the last 90 frames). Reps = max(state-machine reps, height reps), like push-up D-T3-11.
    var heightRepSignal = true
    var heightCounter: PushUpHeightCounter = { var c = PushUpHeightCounter(); c.minRange = 0.25; return c }()
    /// Ready pose: frames the start pose must be held still before the first rep (0 = off) and the
    /// allowed drift of the motion signal meanwhile. OFF: on Exercise3D (sets start within ~1 s)
    /// 30 frames lost reps in every exercise; 15 frames with 2× tolerance kept squat/row but still
    /// lost push-ups (outputs/rep_validation/G_ready_pose.md). 임시값 — 테스트 영상으로 조정
    var readyPoseHoldFrames = 0
    var readyPoseTolerance = 0.03  // squat depth (leg lengths)

    /// Ready-pose preset (evaluation only; the app default stays off): hold 0.5 s at `fps` with 2×
    /// tolerance, which kept every Exercise3D side-camera rep. Push-up has no preset (it lost reps).
    mutating func applyReadyPosePreset(fps: Double = 30) {
        readyPoseHoldFrames = max(1, Int((fps * 0.5).rounded()))
        readyPoseTolerance *= 2
    }
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
        var legLength: Double? = nil
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
    private var straightLegFrames = 0
    private var lowConfidenceFrames = 0
    private lazy var heightCounter = config.heightCounter
    private var recentLegLengths: [Double] = []
    /// Reps the depth/knee state machine finished; `completedRepCount` = max(this, height reps).
    private var stateRepCount = 0
    private var formRepOpen = false
    private lazy var readyPose = ReadyPoseGate(holdFrames: config.readyPoseHoldFrames, tolerance: config.readyPoseTolerance)

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
        straightLegFrames = 0
        lowConfidenceFrames = 0
        heightCounter.reset()
        recentLegLengths = []
        stateRepCount = 0
        formRepOpen = false
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
        readyPose = ReadyPoseGate(holdFrames: config.readyPoseHoldFrames, tolerance: config.readyPoseTolerance)
    }

    /// `pose3D` / `pose3DState`: MotionAGFormerLive 3D and state of this frame (form judgement; FormWarningTracker).
    /// `feet`: Halpe26 toes/heels (squat_heel_rise only; nil with the COCO17 model).
    func evaluate(frameIndex: Int, coco17: [PoseKeypoint], pose3D: [SIMD3<Double>]? = nil,
                  pose3DState: Pose3DState? = nil, feet: FootKeypoints? = nil) -> SquatFrameResult {
        let measurements = computeMeasurements(coco17: coco17)
        let rawCandidate = classifyRawStatusCandidate(measurements)
        let previousStatus = stableStatus
        let status = updateStableStatus(
            rawCandidate: rawCandidate,
            squatDepthNorm: measurements.squatDepthNorm,
            avgKneeAngleDegrees: measurements.avgKneeAngleDegrees
        )

        updateTopBaselineIfNeeded(status: status, measurements: measurements)
        formTracker.observe(frameIndex: frameIndex, coco17: coco17, pose3D: pose3D, pose3DState: pose3DState, feet: feet, phase: status.rawValue)
        readyPose.update(atStartPose: status == .top, value: measurements.squatDepthNorm)
        var done = updateRepState(
            frameIndex: frameIndex,
            previousStatus: previousStatus,
            status: status,
            measurements: measurements
        )
        if config.heightRepSignal, readyPose.armed {
            switch heightCounter.update(frame: frameIndex, height: heightSample(measurements)) {
            case .down?:
                if !formRepOpen {
                    formTracker.beginRep()
                    formRepOpen = true
                }
            case .rep?:
                if heightCounter.reps > completedRepCount {
                    emitRep(frameIndex: frameIndex, startFrame: currentRepStartFrame ?? heightCounter.downFrame ?? frameIndex,
                            maxDepth: currentRepMaxDepthNorm ?? measurements.squatDepthNorm ?? 0)
                    done = true
                }
            case nil:
                break
            }
        }
        if repStarted || formRepOpen { formTracker.recordCurrentFrame() }

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
        let invalid = Measurements(
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
        guard coco17.count == 17 else { return invalid }
        let left = (hip: coco17[COCO17.leftHip], knee: coco17[COCO17.leftKnee], ankle: coco17[COCO17.leftAnkle])
        let right = (hip: coco17[COCO17.rightHip], knee: coco17[COCO17.rightKnee], ankle: coco17[COCO17.rightAnkle])
        // Both legs (old rule), or — nearLegFallback — the one leg whose three joints are all confident
        // (side view: the far leg is hidden behind the near one).
        let legs: [(hip: PoseKeypoint, knee: PoseKeypoint, ankle: PoseKeypoint)]
        let useLeft: Bool, useRight: Bool
        if jointsAreConfident(coco17) {
            legs = [left, right]; useLeft = true; useRight = true
        } else if config.nearLegFallback, legConfident(left) || legConfident(right) {
            // Not both legs, so exactly one is confident.
            useLeft = legConfident(left); useRight = !useLeft
            legs = [useLeft ? left : right]
        } else {
            return invalid
        }

        let hipCenter = average(legs.map(\.hip))
        let kneeCenter = average(legs.map(\.knee))
        let ankleCenter = average(legs.map(\.ankle))
        let legLength = max(legs.map { distance($0.hip, $0.knee) + distance($0.knee, $0.ankle) }.reduce(0, +) / Double(legs.count), 1.0)
        if topHipYBaseline == nil {
            topHipYBaseline = hipCenter.y
        }

        let leftKneeAngle = useLeft ? Self.angle2D(a: left.hip, b: left.knee, c: left.ankle) : nil
        let rightKneeAngle = useRight ? Self.angle2D(a: right.hip, b: right.knee, c: right.ankle) : nil
        let avgKneeAngle = averageValid(leftKneeAngle, rightKneeAngle)
        rebaselineIfStanding(hipY: hipCenter.y, kneeAngle: avgKneeAngle)

        let depthNorm = (hipCenter.y - (topHipYBaseline ?? hipCenter.y)) / legLength
        let depthDeltaNorm = optionalDiff(depthNorm, previousSquatDepthNorm)

        return Measurements(
            squatDepthNorm: depthNorm,
            squatDepthDeltaNorm: depthDeltaNorm,
            leftKneeAngleDegrees: leftKneeAngle,
            rightKneeAngleDegrees: rightKneeAngle,
            avgKneeAngleDegrees: avgKneeAngle,
            hipCenterY: hipCenter.y,
            kneeCenterY: kneeCenter.y,
            ankleCenterY: ankleCenter.y,
            legLength: legLength,
            validDepth: true
        )
    }

    /// rebaselineStraightLegFrames: legs straight (knee > topKneeAngleThreshold) for that many frames in a
    /// row but not `top` → the standing hip height is stale (first confident frame was a false detection,
    /// or the person moved closer/further); take the current hip height as the standing baseline.
    private func rebaselineIfStanding(hipY: Double, kneeAngle: Double?) {
        guard config.rebaselineStraightLegFrames > 0 else { return }
        guard let kneeAngle, kneeAngle > config.topKneeAngleThreshold, stableStatus != .top else {
            straightLegFrames = 0
            return
        }
        straightLegFrames += 1
        if straightLegFrames >= config.rebaselineStraightLegFrames {
            topHipYBaseline = hipY
            straightLegFrames = 0
        }
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

        // holdStatusThroughUnknown: a frame that says nothing (between the top/bottom thresholds while moving
        // slower than the delta thresholds, or — up to maxLowConfidenceHoldFrames in a row — legs not
        // confident) votes for the current status, so 8 such frames can no longer force the stable status to
        // `unknown` mid-rep (unknown → top does not finish a rep). It still breaks another candidate's streak
        // (not voting at all let standing bob build descending streaks: +1 false rep on the sway synth).
        if squatDepthNorm == nil { lowConfidenceFrames += 1 } else { lowConfidenceFrames = 0 }
        let holds = config.holdStatusThroughUnknown && rawCandidate == .unknown && stableStatus != .unknown
            && (squatDepthNorm != nil || lowConfidenceFrames <= config.maxLowConfidenceHoldFrames)
        let vote = holds ? stableStatus : rawCandidate
        if vote == candidateStatus {
            candidateStatusCount += 1
        } else {
            candidateStatus = vote
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

        // A fast descent can reach `bottom` straight from `top` (forced transition) without a
        // stable `descending`; it still starts the rep.
        if !repStarted,
           readyPose.armed,
           status == .descending || status == .bottom,
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

        // Likewise a fast ascent goes `bottom` -> `top` without a stable `ascending`.
        if repStarted && previousStatus == .bottom && status == .top {
            sawAscending = true
        }
        if repStarted,
           previousStatus == .ascending || previousStatus == .bottom,
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
        if !formRepOpen { formTracker.beginRep() }
        formRepOpen = true
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

        stateRepCount += 1
        // The height signal already counted this rep.
        guard stateRepCount > completedRepCount else { return false }
        emitRep(frameIndex: frameIndex, startFrame: startFrame, maxDepth: maxDepth)
        return true
    }

    /// Counts a rep (either signal): summary from the current state-machine rep, form report.
    private func emitRep(frameIndex: Int, startFrame: Int, maxDepth: Double) {
        let minKneeAngle = currentRepMinKneeAngleDegrees
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
        formRepOpen = false
        completedRepSummaries.append(summary)
        trimCompletedRepSummaries()
        let maxDepthText = String(format: "%.3f", maxDepth)
        let minKneeText = minKneeAngle.map { String(format: "%.1f", $0) } ?? "-"
        print("Squat rep completed: rep=\(completedRepCount) frame=\(frameIndex) maxDepth=\(maxDepthText) minKnee=\(minKneeText) done=true")
    }

    /// Hip height above the ankles in standing leg lengths (nil without confident legs).
    private func heightSample(_ m: Measurements) -> Double? {
        guard let hipY = m.hipCenterY, let ankleY = m.ankleCenterY, let leg = m.legLength else { return nil }
        recentLegLengths.append(leg)
        if recentLegLengths.count > heightCounter.windowFrames { recentLegLengths.removeFirst() }
        return (ankleY - hipY) / max(recentLegLengths.max() ?? leg, 1.0)
    }

    private func trimCompletedRepSummaries() {
        if completedRepSummaries.count > config.maxStoredRepSummaries {
            completedRepSummaries.removeFirst(completedRepSummaries.count - config.maxStoredRepSummaries)
        }
    }

    private func resetCurrentRep() {
        if heightCounter.downFrame == nil || !config.heightRepSignal { formRepOpen = false }
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

    private func legConfident(_ leg: (hip: PoseKeypoint, knee: PoseKeypoint, ankle: PoseKeypoint)) -> Bool {
        min(leg.hip.confidence, leg.knee.confidence, leg.ankle.confidence) >= config.squatMinJointConfidence
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

    private func average(_ points: [PoseKeypoint]) -> PoseKeypoint {
        let n = Double(points.count)
        return PoseKeypoint(
            x: points.map(\.x).reduce(0, +) / n,
            y: points.map(\.y).reduce(0, +) / n,
            confidence: points.map(\.confidence).reduce(0, +) / n
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
