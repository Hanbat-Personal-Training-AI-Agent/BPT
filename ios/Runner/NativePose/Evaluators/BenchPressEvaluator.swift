import Foundation

struct BenchPressEvaluatorConfig {
    var benchPressMinJointConfidence = 0.30
    var topElbowAngleThreshold = 145.0
    var bottomElbowAngleThreshold = 110.0
    var validBottomElbowAngleThreshold = 125.0
    /// Adaptive top/bottom only once the elbow has moved this much. Was 20: fidgeting with the racked
    /// bar before the set (91–126°) made 117° a "top" and counted it (Exercise3D bench).
    var minRequiredElbowRange = 50.0
    var adaptiveTopRangeFraction = 0.75
    var adaptiveBottomRangeFraction = 0.30
    var elbowAngleDeltaThreshold = 1.5
    var elbowAngleDeltaLookbackFrames = 3
    var positionConfirmationFrames = 2
    var statusConfirmationFrames = 3
    var minStatusDurationFrames = 4
    var forceTransitionFrames = 8
    var maxUnknownFramesWithValidDepth = 10
    var bottomEscapeMarginDegrees = 10.0
    var minRepDepthNorm = 0.10
    var depthWindowSize = 30
    var depthRangeReliableThreshold = 0.04
    var maxStoredRepSummaries = 100
    /// A rep may start only after a stable top (lockout) has been seen this set. Off = the old behaviour,
    /// where the first frames (hands on the racked bar, elbows bent) or the unrack could open a rep
    /// (Exercise3D bench: 8 of 10 extra reps, outputs/rep_validation/K_bench_deadlift.md).
    var repStartRequiresTop = true
    /// The rep is counted when the top is reached, but the form tracker keeps recording this many
    /// more frames (0.5 s at 30 fps) before judging it, so the lockout (max elbow angle) is inside the
    /// judged frames: the top state starts at ~75% of the elbow range, well before full extension.
    var lockoutWindowFrames = 15
    /// Measure from one arm when only that arm's shoulder/elbow/wrist are confident. Side view hides
    /// the far arm: on Exercise3D side push-ups (the closest RTMPose data to a lying lifter) the
    /// both-arms gate fails on 1–76% of frames per camera (outputs/rep_validation/K_bench_deadlift.md).
    var allowOneArm = true
}

final class BenchPressEvaluator {
    private enum COCO17 {
        static let leftShoulder = 5
        static let rightShoulder = 6
        static let leftElbow = 7
        static let rightElbow = 8
        static let leftWrist = 9
        static let rightWrist = 10
    }

    private struct Measurements {
        let pressDepthNorm: Double?
        let pressDepthDeltaNorm: Double?
        let leftElbowAngleDegrees: Double?
        let rightElbowAngleDegrees: Double?
        let avgElbowAngleDegrees: Double?
        let elbowAngleDeltaDegrees: Double?
        let depthSignalReliable: Bool
        let wristShoulderDeltaY: Double?
        let armLength: Double?
        let valid: Bool
    }

    private let config: BenchPressEvaluatorConfig
    private var stableStatus: BenchPressStatus = .unknown
    private var candidateStatus: BenchPressStatus = .unknown
    private var candidateStatusCount = 0
    private var statusFrameCount = 0
    private var didInitializeStableStatus = false
    private var unknownFramesWithValidDepth = 0

    private var topWristShoulderDeltaBaseline: Double?
    private var provisionalMinWristShoulderDeltaY: Double?
    private var previousPressDepthNorm: Double?
    private var depthWindow: [Double] = []
    private var elbowAngleHistory: [Double] = []
    private var observedMinElbowAngle: Double?
    private var observedMaxElbowAngle: Double?
    private var effectiveTopThreshold = 145.0
    private var effectiveBottomThreshold = 110.0

    private var repStarted = false
    private var sawLowering = false
    private var sawPressing = false
    private var currentRepStartFrame: Int?
    private var currentRepBottomFrame: Int?
    private var currentRepMaxDepthNorm: Double?
    private var currentRepMinElbowAngleDegrees: Double?
    private var currentRepDepthSignalReliable = false
    private var completedRepCount = 0
    private(set) var completedRepSummaries: [BenchPressRepSummary] = []
    /// setup_full_body / tracking_lost and the (off) bench_* warnings; see FormWarnings.swift.
    let formTracker = FormWarningTracker(exercise: .benchPress)

    private var hadElbowExtensionDuringRep = false
    private var lastNonUnknownStableStatus: BenchPressStatus = .unknown
    private var sawBottom = false
    private var sawTop = false
    /// Counted rep whose form report waits for the lockout window: (rep index, frames recorded since).
    private var pendingFormRep: (index: Int, frames: Int)?

    var sessionSummary: BenchPressSessionSummary {
        makeSessionSummary()
    }

    init(config: BenchPressEvaluatorConfig = BenchPressEvaluatorConfig()) {
        self.config = config
        self.effectiveTopThreshold = config.topElbowAngleThreshold
        self.effectiveBottomThreshold = config.bottomElbowAngleThreshold
    }

    func reset() {
        stableStatus = .unknown
        candidateStatus = .unknown
        candidateStatusCount = 0
        statusFrameCount = 0
        didInitializeStableStatus = false
        unknownFramesWithValidDepth = 0
        topWristShoulderDeltaBaseline = nil
        provisionalMinWristShoulderDeltaY = nil
        previousPressDepthNorm = nil
        depthWindow = []
        elbowAngleHistory = []
        observedMinElbowAngle = nil
        observedMaxElbowAngle = nil
        effectiveTopThreshold = config.topElbowAngleThreshold
        effectiveBottomThreshold = config.bottomElbowAngleThreshold
        repStarted = false
        sawLowering = false
        sawPressing = false
        currentRepStartFrame = nil
        currentRepBottomFrame = nil
        currentRepMaxDepthNorm = nil
        currentRepMinElbowAngleDegrees = nil
        currentRepDepthSignalReliable = false
        completedRepCount = 0
        completedRepSummaries = []
        hadElbowExtensionDuringRep = false
        lastNonUnknownStableStatus = .unknown
        sawBottom = false
        sawTop = false
        pendingFormRep = nil
        formTracker.reset()
    }

    func evaluate(frameIndex: Int, coco17: [PoseKeypoint], pose3D: [SIMD3<Double>]? = nil,
                  pose3DState: Pose3DState? = nil) -> BenchPressFrameResult {
        let measurements = computeMeasurements(coco17: coco17)
        let rawCandidate = classifyRawStatusCandidate(measurements)
        let lastStable = stableStatus
        var status = updateStableStatus(rawCandidate: rawCandidate, measurements: measurements)
        updateTopBaselineIfNeeded(status: status, measurements: measurements)
        formTracker.observe(frameIndex: frameIndex, coco17: coco17, pose3D: pose3D, pose3DState: pose3DState, phase: status.rawValue)
        
        let transitionedToTop = (lastStable != .top && status == .top)
        
        let repUpdate = updateRepState(
            frameIndex: frameIndex,
            previousStatus: lastStable,
            status: status,
            measurements: measurements,
            transitionedToTop: transitionedToTop
        )
        if let override = repUpdate.statusOverride {
            status = override
        }
        previousPressDepthNorm = measurements.pressDepthNorm

        if status != .unknown {
            lastNonUnknownStableStatus = status
        }
        if repStarted {
            formTracker.recordCurrentFrame()
        } else if let pending = pendingFormRep, !repUpdate.done {
            formTracker.recordCurrentFrame()
            pendingFormRep = (pending.index, pending.frames + 1)
            if pending.frames + 1 >= config.lockoutWindowFrames { finishPendingFormRep() }
        }

        let shouldComplete = shouldCompleteBenchPressRep(measurements: measurements, transitionedToTop: transitionedToTop, lastStable: lastStable)

        if frameIndex % 30 == 0 {
            printDebugSample(
                frameIndex: frameIndex,
                rawCandidate: rawCandidate,
                status: status,
                lastStableStatus: lastStable,
                transitionedToTop: transitionedToTop,
                done: repUpdate.done,
                measurements: measurements
            )
        }

        return BenchPressFrameResult(
            frameIndex: frameIndex,
            status: status,
            rawStatusCandidate: rawCandidate,
            candidateStatus: candidateStatus,
            candidateStatusCount: candidateStatusCount,
            statusFrameCount: statusFrameCount,
            rep: completedRepCount,
            done: repUpdate.done,
            pressDepthNorm: measurements.pressDepthNorm,
            pressDepthDeltaNorm: measurements.pressDepthDeltaNorm,
            leftElbowAngleDegrees: measurements.leftElbowAngleDegrees,
            rightElbowAngleDegrees: measurements.rightElbowAngleDegrees,
            avgElbowAngleDegrees: measurements.avgElbowAngleDegrees,
            elbowAngleDeltaDegrees: measurements.elbowAngleDeltaDegrees,
            observedMinElbowAngleDegrees: observedMinElbowAngle,
            observedMaxElbowAngleDegrees: observedMaxElbowAngle,
            effectiveTopElbowThreshold: effectiveTopThreshold,
            effectiveBottomElbowThreshold: effectiveBottomThreshold,
            depthSignalReliable: measurements.depthSignalReliable,
            currentRepMaxDepthNorm: currentRepMaxDepthNorm,
            currentRepMinElbowAngleDegrees: currentRepMinElbowAngleDegrees,
            repStarted: repStarted,
            sawLowering: sawLowering,
            sawPressing: sawPressing,
            lastCompletedRepSummary: completedRepSummaries.last,
            hadElbowExtensionDuringRep: hadElbowExtensionDuringRep,
            bottomFrameExists: currentRepBottomFrame != nil,
            lastStableStatus: lastStable.rawValue,
            transitionedToTop: transitionedToTop,
            shouldCompleteRep: shouldComplete,
            sawBottom: sawBottom
        )
    }

    private func computeMeasurements(coco17: [PoseKeypoint]) -> Measurements {
        let leftOK = coco17.count == 17 && armIsConfident(COCO17.leftShoulder, COCO17.leftElbow, COCO17.leftWrist, coco17)
        let rightOK = coco17.count == 17 && armIsConfident(COCO17.rightShoulder, COCO17.rightElbow, COCO17.rightWrist, coco17)
        guard leftOK && rightOK || config.allowOneArm && (leftOK || rightOK) else {
            return Measurements(
                pressDepthNorm: nil,
                pressDepthDeltaNorm: nil,
                leftElbowAngleDegrees: nil,
                rightElbowAngleDegrees: nil,
                avgElbowAngleDegrees: nil,
                elbowAngleDeltaDegrees: nil,
                depthSignalReliable: false,
                wristShoulderDeltaY: nil,
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

        let shoulderCenter = leftOK && rightOK ? average(leftShoulder, rightShoulder) : leftOK ? leftShoulder : rightShoulder
        let wristCenter = leftOK && rightOK ? average(leftWrist, rightWrist) : leftOK ? leftWrist : rightWrist
        let leftArm = distance(leftShoulder, leftElbow) + distance(leftElbow, leftWrist)
        let rightArm = distance(rightShoulder, rightElbow) + distance(rightElbow, rightWrist)
        let armLength = max(leftOK && rightOK ? (leftArm + rightArm) * 0.5 : leftOK ? leftArm : rightArm, 1.0)
        let wristShoulderDeltaY = wristCenter.y - shoulderCenter.y
        provisionalMinWristShoulderDeltaY = min(provisionalMinWristShoulderDeltaY ?? wristShoulderDeltaY, wristShoulderDeltaY)
        let baseline = topWristShoulderDeltaBaseline ?? provisionalMinWristShoulderDeltaY ?? wristShoulderDeltaY
        let pressDepthNorm = max(0.0, (wristShoulderDeltaY - baseline) / armLength)
        let pressDepthDeltaNorm = optionalDiff(pressDepthNorm, previousPressDepthNorm)
        updateDepthWindow(pressDepthNorm)
        let depthSignalReliable = currentDepthRange() >= config.depthRangeReliableThreshold

        let leftElbowAngle = leftOK ? Self.angle2D(a: leftShoulder, b: leftElbow, c: leftWrist) : nil
        let rightElbowAngle = rightOK ? Self.angle2D(a: rightShoulder, b: rightElbow, c: rightWrist) : nil
        let avgElbowAngle = averageValid(leftElbowAngle, rightElbowAngle)
        updateElbowCalibrationAndEffectiveThresholds(avgElbowAngle)
        let elbowDelta = updateElbowAngleHistoryAndDelta(avgElbowAngle)

        return Measurements(
            pressDepthNorm: pressDepthNorm,
            pressDepthDeltaNorm: pressDepthDeltaNorm,
            leftElbowAngleDegrees: leftElbowAngle,
            rightElbowAngleDegrees: rightElbowAngle,
            avgElbowAngleDegrees: avgElbowAngle,
            elbowAngleDeltaDegrees: elbowDelta,
            depthSignalReliable: depthSignalReliable,
            wristShoulderDeltaY: wristShoulderDeltaY,
            armLength: armLength,
            valid: true
        )
    }

    private func classifyRawStatusCandidate(_ measurements: Measurements) -> BenchPressStatus {
        guard measurements.valid, let elbow = measurements.avgElbowAngleDegrees else { return .unknown }
        let elbowDelta = measurements.elbowAngleDeltaDegrees

        if elbow >= effectiveTopThreshold {
            return .top
        }

        if elbow <= effectiveBottomThreshold {
            if elbowDelta.map({ $0 > config.elbowAngleDeltaThreshold }) ?? false {
                return .pressing
            }
            return .bottom
        }

        if elbowDelta.map({ $0 < -config.elbowAngleDeltaThreshold }) ?? false {
            return .lowering
        }
        if elbowDelta.map({ $0 > config.elbowAngleDeltaThreshold }) ?? false {
            return .pressing
        }

        if measurements.depthSignalReliable {
            let reasonablyFlexed = elbow <= config.validBottomElbowAngleThreshold
            if reasonablyFlexed,
               measurements.pressDepthNorm.map({ $0 >= config.minRepDepthNorm }) ?? false {
                return .bottom
            }
        }

        return .unknown
    }

    private func updateStableStatus(rawCandidate: BenchPressStatus, measurements: Measurements) -> BenchPressStatus {
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

        if stableStatus == .bottom {
            let extending = measurements.elbowAngleDeltaDegrees.map { $0 > config.elbowAngleDeltaThreshold } ?? false
            let clearlyAboveBottom = measurements.avgElbowAngleDegrees
                .map { $0 > effectiveBottomThreshold + config.bottomEscapeMarginDegrees } ?? false
            if extending || clearlyAboveBottom {
                stableStatus = .pressing
                candidateStatus = .pressing
                candidateStatusCount = max(candidateStatusCount, 1)
                statusFrameCount = 0
                return stableStatus
            }
        }

        if repStarted,
           stableStatus == .pressing,
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

        if (candidateStatus == .top || candidateStatus == .bottom),
           candidateStatus != stableStatus,
           candidateStatusCount >= config.positionConfirmationFrames,
           isAllowedTransition(from: stableStatus, to: candidateStatus) {
            stableStatus = candidateStatus
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

    private func fastPositionTransition(_ measurements: Measurements) -> BenchPressStatus? {
        if stableStatus == .pressing,
           candidateStatus == .top,
           measurements.avgElbowAngleDegrees.map({ $0 >= effectiveTopThreshold }) ?? false {
            return .top
        }
        if stableStatus == .lowering,
           candidateStatus == .bottom,
           measurements.avgElbowAngleDegrees.map({ $0 <= effectiveBottomThreshold }) ?? false {
            return .bottom
        }
        return nil
    }

    private func initialStableStatus(_ measurements: Measurements) -> BenchPressStatus {
        if let elbow = measurements.avgElbowAngleDegrees, elbow >= effectiveTopThreshold {
            return .top
        }
        if measurements.avgElbowAngleDegrees.map({ $0 <= effectiveBottomThreshold }) ?? false {
            return .bottom
        }
        return .unknown
    }

    private func unknownFallbackStatus(_ measurements: Measurements) -> BenchPressStatus {
        if let elbow = measurements.avgElbowAngleDegrees {
            if elbow >= effectiveTopThreshold { return .top }
            if elbow <= effectiveBottomThreshold { return .bottom }
        }
        return .unknown
    }

    private func isAllowedTransition(from current: BenchPressStatus, to next: BenchPressStatus) -> Bool {
        guard current != next else { return false }
        switch current {
        case .unknown:
            return next == .top || next == .lowering || next == .bottom
        case .top:
            return next == .lowering
        case .lowering:
            return next == .bottom || next == .pressing || next == .top
        case .bottom:
            return next == .pressing || next == .lowering || next == .top
        case .pressing:
            return next == .top || next == .lowering
        }
    }

    private func updateTopBaselineIfNeeded(status: BenchPressStatus, measurements: Measurements) {
        guard status == .top,
              let elbow = measurements.avgElbowAngleDegrees,
              elbow >= effectiveTopThreshold,
              let deltaY = measurements.wristShoulderDeltaY else { return }
        topWristShoulderDeltaBaseline = min(topWristShoulderDeltaBaseline ?? deltaY, deltaY)
    }

    private func updateRepState(
        frameIndex: Int,
        previousStatus: BenchPressStatus,
        status: BenchPressStatus,
        measurements: Measurements,
        transitionedToTop: Bool
    ) -> (done: Bool, statusOverride: BenchPressStatus?) {
        if status == .top { sawTop = true }
        let mayStart = sawTop || !config.repStartRequiresTop
        if status == .bottom && !repStarted && mayStart {
            finishPendingFormRep()
            formTracker.beginRep()
            repStarted = true
            sawBottom = true
            sawLowering = true
            currentRepBottomFrame = frameIndex
            if currentRepStartFrame == nil {
                currentRepStartFrame = frameIndex
            }
            if let elbow = measurements.avgElbowAngleDegrees {
                currentRepMinElbowAngleDegrees = min(currentRepMinElbowAngleDegrees ?? elbow, elbow)
            }
            if let depth = measurements.pressDepthNorm {
                currentRepMaxDepthNorm = max(currentRepMaxDepthNorm ?? depth, depth)
            }
            currentRepDepthSignalReliable = currentRepDepthSignalReliable || measurements.depthSignalReliable
        }

        if status == .lowering && (previousStatus == .top || previousStatus == .unknown) && mayStart {
            startRep(frameIndex: frameIndex)
        }

        if repStarted {
            updateCurrentRep(measurements)
            
            if status == .lowering {
                sawLowering = true
            }
            
            if status == .bottom {
                sawBottom = true
            }
            
            if currentRepBottomFrame == nil {
                let sufficientlyFlexed = measurements.avgElbowAngleDegrees.map { $0 <= config.validBottomElbowAngleThreshold } ?? false
                if status == .bottom {
                    currentRepBottomFrame = frameIndex
                } else if previousStatus == .lowering && status == .pressing && sufficientlyFlexed {
                    currentRepBottomFrame = frameIndex
                }
            }
            
            if status == .pressing {
                sawPressing = true
            }
            
            if let delta = measurements.elbowAngleDeltaDegrees, delta > config.elbowAngleDeltaThreshold {
                hadElbowExtensionDuringRep = true
            }
        }

        var done = false
        var statusOverride: BenchPressStatus? = nil
        
        let shouldComplete = shouldCompleteBenchPressRep(measurements: measurements, transitionedToTop: transitionedToTop, lastStable: previousStatus)
        
        if shouldComplete {
            done = completeRep(frameIndex: frameIndex, measurements: measurements)
            if done {
                stableStatus = .top
                candidateStatus = .top
                candidateStatusCount = 1
                statusFrameCount = 0
                statusOverride = .top
            }
        }

        if transitionedToTop && !shouldComplete && repStarted {
            resetCurrentRep()
        }

        return (done, statusOverride)
    }

    private func startRep(frameIndex: Int) {
        finishPendingFormRep()
        formTracker.beginRep()
        repStarted = true
        sawLowering = true
        sawPressing = false
        sawBottom = false
        hadElbowExtensionDuringRep = false
        currentRepStartFrame = frameIndex
        currentRepBottomFrame = nil
        currentRepMaxDepthNorm = nil
        currentRepMinElbowAngleDegrees = nil
        currentRepDepthSignalReliable = false
    }

    private func updateCurrentRep(_ measurements: Measurements) {
        if let depth = measurements.pressDepthNorm {
            currentRepMaxDepthNorm = max(currentRepMaxDepthNorm ?? depth, depth)
        }
        if let elbow = measurements.avgElbowAngleDegrees {
            currentRepMinElbowAngleDegrees = min(currentRepMinElbowAngleDegrees ?? elbow, elbow)
        }
        currentRepDepthSignalReliable = currentRepDepthSignalReliable || measurements.depthSignalReliable
    }

    private func isCurrentRepValid() -> Bool {
        guard repStarted else { return false }
        let hasLoweringOrBottom = sawLowering || currentRepBottomFrame != nil || sawBottom
        let elbowValid = currentRepMinElbowAngleDegrees.map {
            $0 <= config.validBottomElbowAngleThreshold || $0 <= effectiveBottomThreshold
        } ?? false
        let depthValid = currentRepDepthSignalReliable
            && (currentRepMaxDepthNorm.map { $0 >= config.minRepDepthNorm } ?? false)
        return hasLoweringOrBottom && (elbowValid || depthValid)
    }

    private func shouldCompleteBenchPressRep(measurements: Measurements, transitionedToTop: Bool, lastStable: BenchPressStatus) -> Bool {
        guard repStarted else { return false }
        
        let hasLoweringOrBottom = sawLowering || currentRepBottomFrame != nil || sawBottom
        let elbowValid = currentRepMinElbowAngleDegrees.map {
            $0 <= config.validBottomElbowAngleThreshold || $0 <= effectiveBottomThreshold
        } ?? false
        let depthValid = currentRepDepthSignalReliable
            && (currentRepMaxDepthNorm.map { $0 >= config.minRepDepthNorm } ?? false)
            
        let hasBottomDepth = elbowValid || depthValid
        
        if transitionedToTop {
            if lastStable == .unknown {
                // Fallback for: pressing -> unknown -> top OR lowering -> unknown -> top
                let isFallbackSequence = (lastNonUnknownStableStatus == .pressing || lastNonUnknownStableStatus == .lowering || lastNonUnknownStableStatus == .bottom)
                let elbowAtTopValid = measurements.avgElbowAngleDegrees.map { $0 >= effectiveTopThreshold } ?? false
                let minElbowValid = currentRepMinElbowAngleDegrees.map { $0 <= config.validBottomElbowAngleThreshold } ?? false
                
                if isFallbackSequence && minElbowValid && elbowAtTopValid && hasLoweringOrBottom {
                    return true
                }
            } else {
                // Standard non-top -> top transition
                if hasLoweringOrBottom && hasBottomDepth {
                    return true
                }
            }
        }
        
        return false
    }

    private func completeRep(frameIndex: Int, measurements: Measurements) -> Bool {
        updateCurrentRep(measurements)
        guard isCurrentRepValid(), let startFrame = currentRepStartFrame else { return false }
        completedRepCount += 1
        let summary = BenchPressRepSummary(
            repIndex: completedRepCount,
            startFrame: startFrame,
            bottomFrame: currentRepBottomFrame,
            endFrame: frameIndex,
            maxDepthNorm: currentRepMaxDepthNorm,
            minElbowAngleDegrees: currentRepMinElbowAngleDegrees,
            warnings: []
        )
        completedRepSummaries.append(summary)
        trimCompletedRepSummaries()
        pendingFormRep = (completedRepCount, 0)
        if config.lockoutWindowFrames <= 0 { finishPendingFormRep() }
        let minElbowText = currentRepMinElbowAngleDegrees.map { String(format: "%.1f", $0) } ?? "-"
        let depthText = currentRepMaxDepthNorm.map { String(format: "%.3f", $0) } ?? "-"
        print("Bench press rep completed: rep=\(completedRepCount) frame=\(frameIndex) maxDepth=\(depthText) minElbow=\(minElbowText) done=true")
        resetCurrentRep()
        return true
    }

    /// Judges the counted rep (its frames + the lockout window) and stores the warnings in its summary.
    private func finishPendingFormRep() {
        guard let pending = pendingFormRep else { return }
        pendingFormRep = nil
        let warnings = formTracker.finishRep(repIndex: pending.index).warnings
        if let i = completedRepSummaries.lastIndex(where: { $0.repIndex == pending.index }) {
            completedRepSummaries[i].warnings = warnings
        }
    }

    private func resetCurrentRep() {
        repStarted = false
        sawLowering = false
        sawPressing = false
        sawBottom = false
        hadElbowExtensionDuringRep = false
        currentRepStartFrame = nil
        currentRepBottomFrame = nil
        currentRepMaxDepthNorm = nil
        currentRepMinElbowAngleDegrees = nil
        currentRepDepthSignalReliable = false
    }

    private func trimCompletedRepSummaries() {
        if completedRepSummaries.count > config.maxStoredRepSummaries {
            completedRepSummaries.removeFirst(completedRepSummaries.count - config.maxStoredRepSummaries)
        }
    }

    private func makeSessionSummary() -> BenchPressSessionSummary {
        let depths = completedRepSummaries.compactMap { $0.maxDepthNorm }
        return BenchPressSessionSummary(
            completedRepCount: completedRepCount,
            repCount: completedRepCount,
            avgMaxDepthNorm: average(depths),
            maxDepthNorm: depths.max(),
            minElbowAngleDegrees: completedRepSummaries.compactMap { $0.minElbowAngleDegrees }.min()
        )
    }

    private func armIsConfident(_ shoulder: Int, _ elbow: Int, _ wrist: Int, _ coco17: [PoseKeypoint]) -> Bool {
        [shoulder, elbow, wrist].allSatisfy { coco17[$0].confidence >= config.benchPressMinJointConfidence }
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

    private func updateElbowCalibrationAndEffectiveThresholds(_ angle: Double?) {
        if let angle {
            observedMinElbowAngle = min(observedMinElbowAngle ?? angle, angle)
            observedMaxElbowAngle = max(observedMaxElbowAngle ?? angle, angle)
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

    private func optionalDiff(_ current: Double?, _ previous: Double?) -> Double? {
        guard let current, let previous else { return nil }
        return current - previous
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
        rawCandidate: BenchPressStatus,
        status: BenchPressStatus,
        lastStableStatus: BenchPressStatus,
        transitionedToTop: Bool,
        done: Bool,
        measurements: Measurements
    ) {
        let bottomFrameStr = currentRepBottomFrame.map { String($0) } ?? "nil"
        print("BenchPress debug frame=\(frameIndex) stable=\(status.rawValue) raw=\(rawCandidate.rawValue) cand=\(candidateStatus.rawValue)(\(candidateStatusCount)) lastStable=\(lastStableStatus.rawValue) transitionedToTop=\(transitionedToTop) elbow=\(format(measurements.avgElbowAngleDegrees)) effTop=\(format(effectiveTopThreshold)) effBottom=\(format(effectiveBottomThreshold)) repMinElbow=\(format(currentRepMinElbowAngleDegrees)) repStarted=\(repStarted) sawLowering=\(sawLowering) sawBottom=\(sawBottom) sawPressing=\(sawPressing) hadElbowExt=\(hadElbowExtensionDuringRep) bottomFrame=\(bottomFrameStr) rep=\(completedRepCount) done=\(done)")
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.3f", value)
    }
}
