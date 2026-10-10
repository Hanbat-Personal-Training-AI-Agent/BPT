import Foundation

/// Which arm gives the elbow angle in a side view when both arms pass the confidence check.
enum PushUpSideArm {
    /// The arm whose shoulder+elbow+wrist confidence sum is higher, frame by frame.
    case confident
    /// The form tracker's camera-near side (whole-body confidence with hysteresis).
    case trackerSide
}

struct PushUpEvaluatorConfig {
    /// Side view only (formTracker.sideView, push-up cutoff): a fast descent may start the rep at
    /// top → bottom without a stable `descending`, and the elbow angle comes from one arm
    /// (`sideViewArm`) instead of the two-arm average the occluded far arm spoils.
    /// false = old behaviour everywhere. outputs/rep_validation/H_pushup_failures.md
    var sideViewRepFixes = true
    var sideViewArm = PushUpSideArm.trackerSide
    var pushUpMinJointConfidence = 0.30
    var descendDepthDeltaThreshold = 0.010
    var ascendDepthDeltaThreshold = -0.010
    var topDepthThreshold = 0.06
    var bottomDepthThreshold = 0.18
    // Fixed fallbacks, used until the observed elbow-angle range is wide enough
    // to calibrate. These were tuned on pushup_01 (top/downward-rear view, where the 2D
    // elbow angle is compressed, so a high fixed bottom threshold labelled every frame as
    // bottom); the camera is now assumed to be at the side (docs/research/form_feedback_spec.md)
    // and the values are unchanged until side-view footage exists.
    var topElbowAngleThreshold = 130.0
    var bottomElbowAngleThreshold = 105.0
    var validBottomElbowAngleThreshold = 130.0
    // Adaptive thresholds: once the observed range is at least this wide, derive
    // top/bottom from the observed min + fractions of the range.
    var minRequiredElbowRange = 20.0
    var adaptiveTopRangeFraction = 0.75
    var adaptiveBottomRangeFraction = 0.30
    // Bottom must not stick: a clear extension delta, or the elbow rising this
    // many degrees above the effective bottom, escapes to ascending.
    var bottomEscapeMarginDegrees = 10.0
    // A rep's deepest elbow angle counts as a valid bottom if within this margin
    // of the effective bottom threshold.
    var validRepBottomElbowMarginDegrees = 5.0
    var elbowAngleDeltaThreshold = 1.5
    var elbowAngleDeltaLookbackFrames = 3
    var topConfirmationFrames = 2
    var statusConfirmationFrames = 3
    var minStatusDurationFrames = 4
    var forceTransitionFrames = 8
    var maxUnknownFramesWithValidDepth = 10
    var minRepDepthNorm = 0.10
    var depthWindowSize = 30
    var depthRangeReliableThreshold = 0.04
    var maxStoredRepSummaries = 100
    /// Ready pose: frames the start pose must be held still before the first rep (0 = off) and the
    /// allowed drift of the motion signal meanwhile. OFF: on Exercise3D (sets start within ~1 s)
    /// 30 frames lost reps in every exercise; 15 frames with 2× tolerance kept squat/row but still
    /// lost push-ups (outputs/rep_validation/G_ready_pose.md). 임시값 — 테스트 영상으로 조정
    var readyPoseHoldFrames = 0
    var readyPoseTolerance = 5.0  // elbow angle (deg)
}

final class PushUpEvaluator {
    static let cameraViewEstimate = "side"
    static let selectedDepthSignal = "elbow_angle_primary_with_depth_debug"

    private enum COCO17 {
        static let leftShoulder = 5
        static let rightShoulder = 6
        static let leftElbow = 7
        static let rightElbow = 8
        static let leftWrist = 9
        static let rightWrist = 10
        static let leftHip = 11
        static let rightHip = 12
        static let leftAnkle = 15
        static let rightAnkle = 16
    }

    private struct Measurements {
        let pushDepthNorm: Double?
        let pushDepthDeltaNorm: Double?
        let elbowAngleDeltaDegrees: Double?
        let leftElbowAngleDegrees: Double?
        let rightElbowAngleDegrees: Double?
        let avgElbowAngleDegrees: Double?
        let bodyLineAngleDegrees: Double?
        let hipLineDeviationNorm: Double?
        let depthSignalReliable: Bool
        let shoulderWristDeltaY: Double?
        let armLength: Double?
        let valid: Bool
    }

    private let config: PushUpEvaluatorConfig
    private var stableStatus: PushUpStatus = .unknown
    private var candidateStatus: PushUpStatus = .unknown
    private var candidateStatusCount = 0
    private var statusFrameCount = 0
    private var didInitializeStableStatus = false
    private var unknownFramesWithValidDepth = 0
    private var topShoulderWristDeltaBaseline: Double?
    private var provisionalMinShoulderWristDeltaY: Double?
    private var previousPushDepthNorm: Double?
    private var previousAvgElbowAngleDegrees: Double?
    private var depthWindow: [Double] = []
    private var elbowAngleHistory: [Double] = []
    // Bounded scalar calibration of the observed elbow-angle range (no per-frame
    // history is stored). Used to build adaptive top/bottom thresholds.
    private var observedMinElbowAngle: Double?
    private var observedMaxElbowAngle: Double?
    private var calibrationFrameCount = 0
    // Effective thresholds in use this frame (adaptive when calibrated, else the
    // fixed fallbacks). Recomputed each valid frame inside computeMeasurements.
    private var effectiveTopThreshold = 130.0
    private var effectiveBottomThreshold = 105.0

    private var repStarted = false
    private var sawDescending = false
    private var sawAscending = false
    private var currentRepStartFrame: Int?
    private var currentRepBottomFrame: Int?
    private var currentRepMaxDepthNorm: Double?
    private var currentRepMinElbowAngleDegrees: Double?
    private var currentRepBodyLineAngleDegrees: Double?
    private var currentRepMaxHipLineDeviationNorm: Double?
    private var currentRepDepthSignalReliable = false
    private var completedRepCount = 0
    private(set) var completedRepSummaries: [PushUpRepSummary] = []
    /// `config.sideViewRepFixes` and the side-view gate (nil = undecided → side), set per frame.
    private var sideViewFixes = false
    private lazy var readyPose = ReadyPoseGate(holdFrames: config.readyPoseHoldFrames, tolerance: config.readyPoseTolerance)

    var sessionSummary: PushUpSessionSummary {
        makeSessionSummary()
    }

    init(config: PushUpEvaluatorConfig = PushUpEvaluatorConfig()) {
        self.config = config
    }

    /// Form warnings (rep summary `warnings`); judged only between startRep and the counted rep end.
    let formTracker = FormWarningTracker(exercise: .pushUp)

    func reset() {
        stableStatus = .unknown
        candidateStatus = .unknown
        candidateStatusCount = 0
        statusFrameCount = 0
        didInitializeStableStatus = false
        unknownFramesWithValidDepth = 0
        topShoulderWristDeltaBaseline = nil
        provisionalMinShoulderWristDeltaY = nil
        previousPushDepthNorm = nil
        previousAvgElbowAngleDegrees = nil
        depthWindow = []
        elbowAngleHistory = []
        observedMinElbowAngle = nil
        observedMaxElbowAngle = nil
        calibrationFrameCount = 0
        effectiveTopThreshold = config.topElbowAngleThreshold
        effectiveBottomThreshold = config.bottomElbowAngleThreshold
        repStarted = false
        sawDescending = false
        sawAscending = false
        currentRepStartFrame = nil
        currentRepBottomFrame = nil
        currentRepMaxDepthNorm = nil
        currentRepMinElbowAngleDegrees = nil
        currentRepBodyLineAngleDegrees = nil
        currentRepMaxHipLineDeviationNorm = nil
        currentRepDepthSignalReliable = false
        completedRepCount = 0
        completedRepSummaries = []
        formTracker.reset()
        readyPose = ReadyPoseGate(holdFrames: config.readyPoseHoldFrames, tolerance: config.readyPoseTolerance)
    }

    /// `pose3D`: MotionAGFormer H36M17 selected3D when available (form metrics only; nil in the live app).
    func evaluate(frameIndex: Int, coco17: [PoseKeypoint], pose3D: [SIMD3<Double>]? = nil) -> PushUpFrameResult {
        sideViewFixes = config.sideViewRepFixes && formTracker.sideView != false
        let measurements = computeMeasurements(coco17: coco17)
        let rawCandidate = classifyRawStatusCandidate(measurements)
        let previousStatus = stableStatus
        var status = updateStableStatus(rawCandidate: rawCandidate, measurements: measurements)
        updateTopBaselineIfNeeded(status: status, measurements: measurements)
        formTracker.observe(frameIndex: frameIndex, coco17: coco17, pose3D: pose3D, phase: status.rawValue)
        readyPose.update(atStartPose: status == .top, value: measurements.avgElbowAngleDegrees)
        let repUpdate = updateRepState(
            frameIndex: frameIndex,
            previousStatus: previousStatus,
            status: status,
            measurements: measurements
        )
        if repStarted { formTracker.recordCurrentFrame() }
        if let override = repUpdate.statusOverride {
            status = override
        }
        previousPushDepthNorm = measurements.pushDepthNorm
        previousAvgElbowAngleDegrees = measurements.avgElbowAngleDegrees

        if frameIndex % 30 == 0 {
            printDebugSample(frameIndex: frameIndex, rawCandidate: rawCandidate, status: status, done: repUpdate.done, measurements: measurements)
        }

        return PushUpFrameResult(
            frameIndex: frameIndex,
            status: status,
            rawStatusCandidate: rawCandidate,
            candidateStatus: candidateStatus,
            candidateStatusCount: candidateStatusCount,
            statusFrameCount: statusFrameCount,
            rep: completedRepCount,
            done: repUpdate.done,
            cameraViewEstimate: Self.cameraViewEstimate,
            selectedDepthSignal: Self.selectedDepthSignal,
            depthSignalReliable: measurements.depthSignalReliable,
            pushDepthNorm: measurements.pushDepthNorm,
            pushDepthDeltaNorm: measurements.pushDepthDeltaNorm,
            elbowAngleDeltaDegrees: measurements.elbowAngleDeltaDegrees,
            leftElbowAngleDegrees: measurements.leftElbowAngleDegrees,
            rightElbowAngleDegrees: measurements.rightElbowAngleDegrees,
            avgElbowAngleDegrees: measurements.avgElbowAngleDegrees,
            observedMinElbowAngleDegrees: observedMinElbowAngle,
            observedMaxElbowAngleDegrees: observedMaxElbowAngle,
            effectiveTopElbowThreshold: effectiveTopThreshold,
            effectiveBottomElbowThreshold: effectiveBottomThreshold,
            bodyLineAngleDegrees: measurements.bodyLineAngleDegrees,
            hipLineDeviationNorm: measurements.hipLineDeviationNorm,
            currentRepMaxDepthNorm: currentRepMaxDepthNorm,
            currentRepMinElbowAngleDegrees: currentRepMinElbowAngleDegrees,
            repStarted: repStarted,
            sawDescending: sawDescending,
            sawAscending: sawAscending,
            lastCompletedRepSummary: completedRepSummaries.last
        )
    }

    private func computeMeasurements(coco17: [PoseKeypoint]) -> Measurements {
        guard coco17.count == 17, jointsAreConfident(coco17) else {
            return Measurements(
                pushDepthNorm: nil,
                pushDepthDeltaNorm: nil,
                elbowAngleDeltaDegrees: nil,
                leftElbowAngleDegrees: nil,
                rightElbowAngleDegrees: nil,
                avgElbowAngleDegrees: nil,
                bodyLineAngleDegrees: nil,
                hipLineDeviationNorm: nil,
                depthSignalReliable: false,
                shoulderWristDeltaY: nil,
                armLength: nil,
                valid: false
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
        let leftAnkle = coco17[COCO17.leftAnkle]
        let rightAnkle = coco17[COCO17.rightAnkle]

        // Side view: the far arm/leg is often occluded. With both sides confident this is the
        // old two-side average; otherwise the confident (camera-near) side alone.
        var leftArm = sideConfident(coco17, [COCO17.leftShoulder, COCO17.leftElbow, COCO17.leftWrist])
        var rightArm = sideConfident(coco17, [COCO17.rightShoulder, COCO17.rightElbow, COCO17.rightWrist])
        if sideViewFixes && leftArm && rightArm {
            let useLeft: Bool
            switch (config.sideViewArm, formTracker.side) {
            case (.trackerSide, let side?):
                useLeft = side == .left
            default:
                let score = { (ids: [Int]) in ids.map { coco17[$0].confidence }.reduce(0, +) }
                useLeft = score([COCO17.leftShoulder, COCO17.leftElbow, COCO17.leftWrist])
                    >= score([COCO17.rightShoulder, COCO17.rightElbow, COCO17.rightWrist])
            }
            if useLeft { rightArm = false } else { leftArm = false }
        }
        let shoulderCenter = pair(leftShoulder, rightShoulder)
        let wristCenter = pair(leftWrist, rightWrist)
        let hipCenter = pair(leftHip, rightHip)
        let ankleCenter = pair(leftAnkle, rightAnkle)
        let armLength = max(averageArmLength(coco17, left: leftArm, right: rightArm), 1.0)
        let shoulderWristDeltaY = shoulderCenter.y - wristCenter.y
        provisionalMinShoulderWristDeltaY = min(provisionalMinShoulderWristDeltaY ?? shoulderWristDeltaY, shoulderWristDeltaY)
        let baseline = topShoulderWristDeltaBaseline ?? provisionalMinShoulderWristDeltaY ?? shoulderWristDeltaY
        let pushDepthNorm = max(0.0, (shoulderWristDeltaY - baseline) / armLength)
        let pushDepthDeltaNorm = optionalDiff(pushDepthNorm, previousPushDepthNorm)
        updateDepthWindow(pushDepthNorm)
        let depthSignalReliable = currentDepthRange() >= config.depthRangeReliableThreshold

        let leftElbowAngle = leftArm ? Self.angle2D(a: leftShoulder, b: leftElbow, c: leftWrist) : nil
        let rightElbowAngle = rightArm ? Self.angle2D(a: rightShoulder, b: rightElbow, c: rightWrist) : nil
        let avgElbowAngle = averageValid(leftElbowAngle, rightElbowAngle)
        updateElbowCalibrationAndEffectiveThresholds(avgElbowAngle)
        let elbowDelta = updateElbowAngleHistoryAndDelta(avgElbowAngle)
        let bodyLineAngle = Self.angle2D(a: shoulderCenter, b: hipCenter, c: ankleCenter)
        let bodyLength = max(distance(shoulderCenter, ankleCenter), 1.0)
        let hipLineDeviation = distancePointToLine(point: hipCenter, lineA: shoulderCenter, lineB: ankleCenter) / bodyLength

        return Measurements(
            pushDepthNorm: pushDepthNorm,
            pushDepthDeltaNorm: pushDepthDeltaNorm,
            elbowAngleDeltaDegrees: elbowDelta,
            leftElbowAngleDegrees: leftElbowAngle,
            rightElbowAngleDegrees: rightElbowAngle,
            avgElbowAngleDegrees: avgElbowAngle,
            bodyLineAngleDegrees: bodyLineAngle,
            hipLineDeviationNorm: hipLineDeviation,
            depthSignalReliable: depthSignalReliable,
            shoulderWristDeltaY: shoulderWristDeltaY,
            armLength: armLength,
            valid: true
        )
    }

    private func classifyRawStatusCandidate(_ measurements: Measurements) -> PushUpStatus {
        guard measurements.valid, let elbow = measurements.avgElbowAngleDegrees else { return .unknown }
        let elbowDelta = measurements.elbowAngleDeltaDegrees

        // 1. Strong TOP: elbow extended past the (adaptive) top threshold.
        if elbow >= effectiveTopThreshold {
            return .top
        }

        // 2. Strong BOTTOM: elbow flexed at/under the (adaptive) bottom
        //    threshold. BOTTOM is a position state, but if the elbow is clearly
        //    extending we prefer ascending so bottom can never stick.
        if elbow <= effectiveBottomThreshold {
            if elbowDelta.map({ $0 > config.elbowAngleDeltaThreshold }) ?? false {
                return .ascending
            }
            return .bottom
        }

        // 3. Direction from the elbow-angle finite difference (primary signal).
        if elbowDelta.map({ $0 < -config.elbowAngleDeltaThreshold }) ?? false {
            return .descending
        }
        if elbowDelta.map({ $0 > config.elbowAngleDeltaThreshold }) ?? false {
            return .ascending
        }

        // Depth is only a direction hint, and only when the depth signal is
        // reliable. When it is unreliable the depth condition is removed entirely
        // (no depth-based bottom), which previously helped pin the state at bottom.
        if measurements.depthSignalReliable {
            if measurements.pushDepthDeltaNorm.map({ $0 > config.descendDepthDeltaThreshold }) ?? false {
                return .descending
            }
            if measurements.pushDepthDeltaNorm.map({ $0 < config.ascendDepthDeltaThreshold }) ?? false {
                return .ascending
            }
        }

        // 4. Unknown.
        return .unknown
    }

    private func updateStableStatus(rawCandidate: PushUpStatus, measurements: Measurements) -> PushUpStatus {
        if !didInitializeStableStatus {
            didInitializeStableStatus = true
            let initial = initialStableStatus(measurements)
            if initial != .unknown {
                stableStatus = initial
                candidateStatus = initial
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

        if stableStatus == .unknown && measurements.valid {
            unknownFramesWithValidDepth += 1
            if unknownFramesWithValidDepth > config.maxUnknownFramesWithValidDepth {
                let fallback = unknownFallbackStatus(measurements)
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

        // D. Bottom sticky escape. While latched at bottom, a clear extension
        // delta OR the elbow rising well above the effective bottom must release
        // to ascending immediately (the margin gives hysteresis against flicker).
        if stableStatus == .bottom {
            let extending = measurements.elbowAngleDeltaDegrees.map { $0 > config.elbowAngleDeltaThreshold } ?? false
            let clearlyAboveBottom = measurements.avgElbowAngleDegrees
                .map { $0 > effectiveBottomThreshold + config.bottomEscapeMarginDegrees } ?? false
            if extending || clearlyAboveBottom {
                stableStatus = .ascending
                candidateStatus = .ascending
                candidateStatusCount = max(candidateStatusCount, 1)
                statusFrameCount = 0
                return stableStatus
            }
        }

        // E. Ascending reaching lockout becomes top immediately.
        if repStarted,
           stableStatus == .ascending,
           measurements.avgElbowAngleDegrees.map({ $0 >= effectiveTopThreshold }) ?? false {
            stableStatus = .top
            candidateStatus = .top
            candidateStatusCount = max(candidateStatusCount, 1)
            statusFrameCount = 0
            return stableStatus
        }

        if let fastPosition = fastPositionTransition(measurements) {
            stableStatus = fastPosition
            candidateStatus = fastPosition
            candidateStatusCount = max(candidateStatusCount, 1)
            statusFrameCount = 0
            return stableStatus
        }

        if candidateStatus == .top,
           candidateStatus != stableStatus,
           candidateStatusCount >= config.topConfirmationFrames,
           isAllowedTransition(from: stableStatus, to: .top) {
            stableStatus = .top
            statusFrameCount = 0
            return stableStatus
        }

        let candidateReady = candidateStatus != stableStatus
            && candidateStatus != .unknown
            && candidateStatusCount >= config.statusConfirmationFrames
            && statusFrameCount >= config.minStatusDurationFrames
        if candidateReady {
            let allowed = isAllowedTransition(from: stableStatus, to: candidateStatus)
            let forced = candidateStatusCount >= config.forceTransitionFrames
            if allowed || forced {
                stableStatus = candidateStatus
                statusFrameCount = 0
                return stableStatus
            }
        }

        statusFrameCount += 1
        return stableStatus
    }

    private func fastPositionTransition(_ measurements: Measurements) -> PushUpStatus? {
        if stableStatus == .ascending,
           candidateStatus == .top,
           measurements.avgElbowAngleDegrees.map({ $0 >= effectiveTopThreshold }) ?? false {
            return .top
        }
        if stableStatus == .descending,
           candidateStatus == .bottom,
           measurements.avgElbowAngleDegrees.map({ $0 <= effectiveBottomThreshold }) ?? false {
            return .bottom
        }
        return nil
    }

    private func initialStableStatus(_ measurements: Measurements) -> PushUpStatus {
        if let elbow = measurements.avgElbowAngleDegrees, elbow >= effectiveTopThreshold {
            return .top
        }
        if measurements.avgElbowAngleDegrees.map({ $0 <= effectiveBottomThreshold }) ?? false {
            return .bottom
        }
        return .unknown
    }

    private func unknownFallbackStatus(_ measurements: Measurements) -> PushUpStatus {
        if let elbow = measurements.avgElbowAngleDegrees {
            if elbow >= effectiveTopThreshold { return .top }
            if elbow <= effectiveBottomThreshold { return .bottom }
        }
        return .unknown
    }

    private func isAllowedTransition(from current: PushUpStatus, to next: PushUpStatus) -> Bool {
        guard current != next else { return false }
        switch current {
        case .unknown:
            return next == .top || next == .descending || next == .bottom
        case .top:
            return next == .descending || (sideViewFixes && next == .bottom)
        case .descending:
            return next == .bottom || next == .ascending
        case .bottom:
            return next == .ascending || next == .descending
        case .ascending:
            return next == .top || next == .descending
        }
    }

    private func updateTopBaselineIfNeeded(status: PushUpStatus, measurements: Measurements) {
        guard status == .top,
              let elbow = measurements.avgElbowAngleDegrees,
              elbow >= effectiveTopThreshold,
              let deltaY = measurements.shoulderWristDeltaY else { return }
        topShoulderWristDeltaBaseline = min(topShoulderWristDeltaBaseline ?? deltaY, deltaY)
    }

    private func updateRepState(
        frameIndex: Int,
        previousStatus: PushUpStatus,
        status: PushUpStatus,
        measurements: Measurements
    ) -> (done: Bool, statusOverride: PushUpStatus?) {
        let startsRep = status == .descending || (sideViewFixes && status == .bottom && previousStatus == .top)
        if readyPose.armed, startsRep && (previousStatus == .top || previousStatus == .unknown) {
            startRep(frameIndex: frameIndex)
        }

        if repStarted && (status == .descending || status == .bottom) {
            updateCurrentRep(measurements)
        }

        if repStarted,
           currentRepBottomFrame == nil,
           previousStatus == .descending,
           (status == .bottom || status == .ascending) {
            currentRepBottomFrame = frameIndex
        }

        if status == .ascending {
            sawAscending = true
        }

        if repStarted,
           (previousStatus == .ascending || status == .ascending),
           measurements.avgElbowAngleDegrees.map({ $0 >= effectiveTopThreshold }) ?? false,
           isCurrentRepValid() {
            stableStatus = .top
            candidateStatus = .top
            candidateStatusCount = 1
            statusFrameCount = 0
            return (completeRep(frameIndex: frameIndex, measurements: measurements), .top)
        }

        if repStarted, previousStatus == .ascending, status == .top {
            return (completeRep(frameIndex: frameIndex, measurements: measurements), nil)
        }

        if repStarted,
           previousStatus == .ascending,
           status == .unknown,
           let elbow = measurements.avgElbowAngleDegrees,
           elbow >= effectiveTopThreshold,
           isCurrentRepValid() {
            stableStatus = .top
            candidateStatus = .top
            candidateStatusCount = 1
            statusFrameCount = 0
            return (completeRep(frameIndex: frameIndex, measurements: measurements), .top)
        }

        if status == .top && previousStatus != .ascending && repStarted && !sawAscending {
            resetCurrentRep()
        }

        return (false, nil)
    }

    private func startRep(frameIndex: Int) {
        repStarted = true
        sawDescending = true
        sawAscending = false
        currentRepStartFrame = frameIndex
        currentRepBottomFrame = nil
        currentRepMaxDepthNorm = nil
        currentRepMinElbowAngleDegrees = nil
        currentRepBodyLineAngleDegrees = nil
        currentRepMaxHipLineDeviationNorm = nil
        currentRepDepthSignalReliable = false
        formTracker.beginRep()
    }

    private func updateCurrentRep(_ measurements: Measurements) {
        if let depth = measurements.pushDepthNorm {
            currentRepMaxDepthNorm = max(currentRepMaxDepthNorm ?? depth, depth)
        }
        if let elbow = measurements.avgElbowAngleDegrees {
            currentRepMinElbowAngleDegrees = min(currentRepMinElbowAngleDegrees ?? elbow, elbow)
        }
        if let bodyLine = measurements.bodyLineAngleDegrees {
            currentRepBodyLineAngleDegrees = bodyLine
        }
        if let hipDeviation = measurements.hipLineDeviationNorm {
            currentRepMaxHipLineDeviationNorm = max(currentRepMaxHipLineDeviationNorm ?? hipDeviation, hipDeviation)
        }
        currentRepDepthSignalReliable = currentRepDepthSignalReliable || measurements.depthSignalReliable
    }

    private func isCurrentRepValid() -> Bool {
        // Depth is NOT required (unreliable in this view). A rep is valid if the
        // deepest elbow reached the effective bottom (within a small margin) or
        // the fixed valid-bottom threshold.
        let elbowValid = currentRepMinElbowAngleDegrees.map {
            $0 <= effectiveBottomThreshold + config.validRepBottomElbowMarginDegrees
                || $0 <= config.validBottomElbowAngleThreshold
        } ?? false
        return repStarted && sawDescending && sawAscending && elbowValid
    }

    private func completeRep(frameIndex: Int, measurements: Measurements) -> Bool {
        updateCurrentRep(measurements)
        guard isCurrentRepValid(), let startFrame = currentRepStartFrame else { return false }
        let maxDepth = currentRepMaxDepthNorm ?? 0.0
        let minElbow = currentRepMinElbowAngleDegrees
        completedRepCount += 1
        let summary = PushUpRepSummary(
            repIndex: completedRepCount,
            startFrame: startFrame,
            bottomFrame: currentRepBottomFrame,
            endFrame: frameIndex,
            maxDepthNorm: maxDepth,
            minElbowAngleDegrees: minElbow,
            bodyLineAngleDegrees: currentRepBodyLineAngleDegrees,
            maxHipLineDeviationNorm: currentRepMaxHipLineDeviationNorm,
            warnings: formTracker.finishRep(repIndex: completedRepCount).warnings
        )
        completedRepSummaries.append(summary)
        trimCompletedRepSummaries()
        let maxDepthText = String(format: "%.3f", maxDepth)
        let minElbowText = minElbow.map { String(format: "%.1f", $0) } ?? "-"
        print("Push-up rep completed: rep=\(completedRepCount) frame=\(frameIndex) maxDepth=\(maxDepthText) minElbow=\(minElbowText) done=true")
        resetCurrentRep()
        return true
    }

    private func resetCurrentRep() {
        repStarted = false
        sawDescending = false
        sawAscending = false
        currentRepStartFrame = nil
        currentRepBottomFrame = nil
        currentRepMaxDepthNorm = nil
        currentRepMinElbowAngleDegrees = nil
        currentRepBodyLineAngleDegrees = nil
        currentRepMaxHipLineDeviationNorm = nil
        currentRepDepthSignalReliable = false
    }

    private func trimCompletedRepSummaries() {
        if completedRepSummaries.count > config.maxStoredRepSummaries {
            completedRepSummaries.removeFirst(completedRepSummaries.count - config.maxStoredRepSummaries)
        }
    }

    private func makeSessionSummary() -> PushUpSessionSummary {
        let depths = completedRepSummaries.map { $0.maxDepthNorm }
        return PushUpSessionSummary(
            completedRepCount: completedRepCount,
            repCount: completedRepCount,
            avgMaxDepthNorm: average(depths),
            maxDepthNorm: depths.max(),
            minElbowAngleDegrees: completedRepSummaries.compactMap { $0.minElbowAngleDegrees }.min()
        )
    }

    /// One whole side (shoulder, elbow, wrist, hip, ankle) is enough in a side view.
    private func jointsAreConfident(_ coco17: [PoseKeypoint]) -> Bool {
        sideConfident(coco17, [COCO17.leftShoulder, COCO17.leftElbow, COCO17.leftWrist, COCO17.leftHip, COCO17.leftAnkle])
            || sideConfident(coco17, [COCO17.rightShoulder, COCO17.rightElbow, COCO17.rightWrist, COCO17.rightHip, COCO17.rightAnkle])
    }

    private func sideConfident(_ coco17: [PoseKeypoint], _ indices: [Int]) -> Bool {
        indices.allSatisfy { coco17.indices.contains($0) && coco17[$0].confidence >= config.pushUpMinJointConfidence }
    }

    /// Two-side average when both are confident, else the confident one.
    private func pair(_ left: PoseKeypoint, _ right: PoseKeypoint) -> PoseKeypoint {
        let t = config.pushUpMinJointConfidence
        switch (left.confidence >= t, right.confidence >= t) {
        case (true, false): return left
        case (false, true): return right
        default: return average(left, right)
        }
    }

    private func updateDepthWindow(_ value: Double) {
        depthWindow.append(value)
        if depthWindow.count > config.depthWindowSize {
            depthWindow.removeFirst(depthWindow.count - config.depthWindowSize)
        }
    }

    private func currentDepthRange() -> Double {
        guard let minValue = depthWindow.min(), let maxValue = depthWindow.max() else { return 0.0 }
        return maxValue - minValue
    }

    private func averageArmLength(_ coco17: [PoseKeypoint], left useLeft: Bool, right useRight: Bool) -> Double {
        let left = distance(coco17[COCO17.leftShoulder], coco17[COCO17.leftElbow])
            + distance(coco17[COCO17.leftElbow], coco17[COCO17.leftWrist])
        let right = distance(coco17[COCO17.rightShoulder], coco17[COCO17.rightElbow])
            + distance(coco17[COCO17.rightElbow], coco17[COCO17.rightWrist])
        if useLeft != useRight { return max(useLeft ? left : right, 1.0) }
        return max((left + right) * 0.5, 1.0)
    }

    private func optionalDiff(_ current: Double?, _ previous: Double?) -> Double? {
        guard let current, let previous else { return nil }
        return current - previous
    }

    // Bounded scalar calibration: only min/max are retained (no frame history).
    // The effective thresholds become adaptive once the observed range is wide
    // enough, otherwise they stay on the fixed fallbacks.
    private func updateElbowCalibrationAndEffectiveThresholds(_ angle: Double?) {
        if let angle {
            observedMinElbowAngle = min(observedMinElbowAngle ?? angle, angle)
            observedMaxElbowAngle = max(observedMaxElbowAngle ?? angle, angle)
            calibrationFrameCount += 1
        }
        if let minA = observedMinElbowAngle, let maxA = observedMaxElbowAngle,
           maxA - minA >= config.minRequiredElbowRange {
            let range = maxA - minA
            effectiveTopThreshold = minA + config.adaptiveTopRangeFraction * range
            effectiveBottomThreshold = minA + config.adaptiveBottomRangeFraction * range
        } else {
            effectiveTopThreshold = config.topElbowAngleThreshold
            effectiveBottomThreshold = config.bottomElbowAngleThreshold
        }
    }

    private func observedElbowRange() -> Double? {
        guard let minA = observedMinElbowAngle, let maxA = observedMaxElbowAngle else { return nil }
        return maxA - minA
    }

    private func updateElbowAngleHistoryAndDelta(_ angle: Double?) -> Double? {
        guard let angle else { return nil }
        let delta: Double?
        if elbowAngleHistory.count >= config.elbowAngleDeltaLookbackFrames {
            let past = elbowAngleHistory[elbowAngleHistory.count - config.elbowAngleDeltaLookbackFrames]
            delta = angle - past
        } else {
            delta = nil
        }
        elbowAngleHistory.append(angle)
        let maxCount = max(config.elbowAngleDeltaLookbackFrames + 1, 2)
        if elbowAngleHistory.count > maxCount {
            elbowAngleHistory.removeFirst(elbowAngleHistory.count - maxCount)
        }
        return delta
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

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0, +) / Double(values.count)
    }

    private func average(_ a: PoseKeypoint, _ b: PoseKeypoint) -> PoseKeypoint {
        PoseKeypoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5, confidence: (a.confidence + b.confidence) * 0.5)
    }

    private func distance(_ a: PoseKeypoint, _ b: PoseKeypoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func distancePointToLine(point: PoseKeypoint, lineA: PoseKeypoint, lineB: PoseKeypoint) -> Double {
        let vx = lineB.x - lineA.x
        let vy = lineB.y - lineA.y
        let wx = point.x - lineA.x
        let wy = point.y - lineA.y
        let denom = sqrt(vx * vx + vy * vy)
        guard denom > 1e-8 else { return 0.0 }
        return abs(vx * wy - vy * wx) / denom
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

    private func printDebugSample(
        frameIndex: Int,
        rawCandidate: PushUpStatus,
        status: PushUpStatus,
        done: Bool,
        measurements: Measurements
    ) {
        print("PushUp debug frame=\(frameIndex) elbow=\(format(measurements.avgElbowAngleDegrees)) elbowDelta=\(format(measurements.elbowAngleDeltaDegrees)) obsMin=\(format(observedMinElbowAngle)) obsMax=\(format(observedMaxElbowAngle)) obsRange=\(format(observedElbowRange())) effTop=\(format(effectiveTopThreshold)) effBottom=\(format(effectiveBottomThreshold)) raw=\(rawCandidate.rawValue) cand=\(candidateStatus.rawValue)(\(candidateStatusCount)) stable=\(status.rawValue) sawDown=\(sawDescending) sawUp=\(sawAscending) repMinElbow=\(format(currentRepMinElbowAngleDegrees)) rep=\(completedRepCount) done=\(done)")
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.3f", value)
    }
}
