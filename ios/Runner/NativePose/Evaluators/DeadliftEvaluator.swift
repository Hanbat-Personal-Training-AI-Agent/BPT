import Foundation

struct DeadliftEvaluatorConfig {
    var minJointConfidence = 0.30
    /// Bar back down = wrist below this point between knee (0) and ankle (1). Was 0.50: Exercise3D
    /// (bar on blocks) and Fit3D side-cam pulls stop at 0.10–0.36, so no rep ever ended.
    var wristLowerShinRatio = 0.0
    var elbowHipBlockToleranceRatio = 0.05
    var conservativeBottomProgressThreshold = 0.10

    // 2D hip-above-ankle progress:
    // bottom/setup ≈ 0
    // top/lockout = larger
    var initialBottomProgressThreshold = 0.12
    var loweringBottomProgressThreshold = 0.22
    /// Was 0.28: Exercise3D / Fit3D lockouts sit 0.14–0.25 leg lengths above the bottom.
    var topProgressThreshold = 0.10

    // Direction thresholds
    var risingProgressDeltaThreshold = 0.006
    var loweringProgressDeltaThreshold = -0.004

    // Arm/bar proxy direction
    var barDropDeltaThreshold = 0.006
    var barDropVelocityThreshold = 0.012

    // Top extension
    var topHipAngleThreshold = 150.0
    var topKneeAngleThreshold = 150.0

    // State stabilization
    var statusConfirmationFrames = 3
    var minStatusDurationFrames = 4

    // Fast transitions
    var topExitConfirmationFrames = 2
    var minTopDurationFrames = 2
    var loweringBottomConfirmationFrames = 1
    var minLoweringDurationFrames = 1

    // Fallback bottom after lowering
    var minLoweringFramesForFallbackBottom = 18

    // Baseline / histories
    var baselineWarmupFrames = 15
    var baselineClearLowerRatio = 0.03
    var progressLookbackFrames = 4
    var armProxyLookbackFrames = 4

    // Unknown handling
    var maxUnknownFramesWithValidDepth = 10
    var forceTransitionFrames = 8

    // Arm proxy bottom
    var armProxyBottomTolerance = 0.25

    var maxStoredRepSummaries = 100

    /// A stable bottom → top step with no `rising` in between (slow or short pulls: the hip-height
    /// range is only 0.14–0.25 leg lengths, so raw `rising` between the 0.12 bottom band and the top
    /// rarely shows) starts the rep there. Off = such reps are never started (old behaviour).
    var directBottomToTopStartsRep = true
}

final class DeadliftEvaluator {
    private enum COCO17 {
        static let leftShoulder = 5
        static let rightShoulder = 6
        static let leftElbow = 7
        static let rightElbow = 8
        static let leftWrist = 9
        static let rightWrist = 10
        static let leftHip = 11
        static let rightHip = 12
        static let leftKnee = 13
        static let rightKnee = 14
        static let leftAnkle = 15
        static let rightAnkle = 16
    }

    private struct ProgressSample {
        let progress: Double
    }

    private struct ArmProxySample {
        let yNorm: Double
    }

    private struct Measurements {
        let source: String
        let motion3DAvailable: Bool
        let valid: Bool

        let liftProgressNorm: Double?
        let progressDelta1: Double?
        let progressVelocityWindow: Double?

        let hipHeightAboveAnkle: Double?
        let bottomHeightBaseline: Double?
        let legLength: Double?

        let leftHipAngleDegrees: Double?
        let rightHipAngleDegrees: Double?
        let avgHipAngleDegrees: Double?

        let leftKneeAngleDegrees: Double?
        let rightKneeAngleDegrees: Double?
        let avgKneeAngleDegrees: Double?

        let torsoLeanAngleDegrees: Double?
        let torsoLeanDeltaDegrees: Double?
        let shoulderHeightNorm: Double?
        let shoulderHeightDeltaNorm: Double?

        let armBarProxyYNorm: Double?
        let armBarProxyDelta1: Double?
        let armBarProxyVelocityWindow: Double?
        let bottomArmProxyBaseline: Double?
        let armProxyNearBottom: Bool

        let wristProxyY: Double?
        let wristLowerShinY: Double?
        let wristBelowLowerShin: Bool
        let elbowProxyY: Double?
        let hipCenterY: Double?
        let elbowAboveWaist: Bool

        // Raw joint Y for debug
        let leftWristY: Double?
        let rightWristY: Double?
        let kneeY: Double?
        let ankleY: Double?
    }

    private let config: DeadliftEvaluatorConfig

    private var stableStatus: DeadliftStatus = .idle
    private var candidateStatus: DeadliftStatus = .idle
    private var candidateStatusCount = 0
    private var statusFrameCount = 0
    private var didInitializeStableStatus = false
    private var unknownFramesWithValidDepth = 0

    private var bottomHeightBaseline: Double?
    private var baselineWarmupCount = 0
    private var progressHistory: [ProgressSample] = []

    private var armProxyHistory: [ArmProxySample] = []
    private var bottomArmProxyBaseline: Double?

    private var currentLoweringTrigger = "none"
    private var currentBottomTrigger = "none"

    private var repStarted = false
    private var sawRising = false
    private var reachedTop = false
    private var sawLowering = false

    private var currentRepStartFrame: Int?
    private var currentRepTopFrame: Int?
    private var currentRepMaxLiftProgressNorm: Double?
    private var currentRepMaxHipAngleDegrees: Double?
    private var currentRepMaxKneeAngleDegrees: Double?

    private var topProgressNorm: Double?
    private var topArmProxyYNorm: Double?
    private var progressDropFromTop: Double?
    private var armBarProxyDropFromTop: Double?
    private var elapsedLoweringFrames = 0
    private var framesSinceTop = 0

    private var completedRepCount = 0
    private(set) var completedRepSummaries: [DeadliftRepSummary] = []
    /// setup_full_body / tracking_lost and the (off) deadlift_* warnings; see FormWarnings.swift.
    let formTracker = FormWarningTracker(exercise: .deadlift)

    var sessionSummary: DeadliftSessionSummary {
        makeSessionSummary()
    }

    init(config: DeadliftEvaluatorConfig = DeadliftEvaluatorConfig()) {
        self.config = config
    }

    func reset() {
        stableStatus = .idle
        candidateStatus = .idle
        candidateStatusCount = 0
        statusFrameCount = 0
        didInitializeStableStatus = false
        unknownFramesWithValidDepth = 0

        bottomHeightBaseline = nil
        baselineWarmupCount = 0
        progressHistory.removeAll(keepingCapacity: true)

        armProxyHistory.removeAll(keepingCapacity: true)
        bottomArmProxyBaseline = nil

        currentLoweringTrigger = "none"
        currentBottomTrigger = "none"

        repStarted = false
        sawRising = false
        reachedTop = false
        sawLowering = false

        currentRepStartFrame = nil
        currentRepTopFrame = nil
        currentRepMaxLiftProgressNorm = nil
        currentRepMaxHipAngleDegrees = nil
        currentRepMaxKneeAngleDegrees = nil

        topProgressNorm = nil
        topArmProxyYNorm = nil
        progressDropFromTop = nil
        armBarProxyDropFromTop = nil
        elapsedLoweringFrames = 0
        framesSinceTop = 0

        completedRepCount = 0
        completedRepSummaries.removeAll(keepingCapacity: true)
        formTracker.reset()
    }

    func evaluate(
        frameIndex: Int,
        coco17: [PoseKeypoint],
        selected3D: [[Float]]? = nil,
        pose3D: [SIMD3<Double>]? = nil,
        pose3DState: Pose3DState? = nil
    ) -> DeadliftFrameResult {
        let measurements = computeMeasurements(
            coco17: coco17,
            selected3D: selected3D
        )

        let rawCandidate = classifyRawStatusCandidate(measurements)
        let previousStatus = stableStatus
        let status = updateStableStatus(
            rawCandidate: rawCandidate,
            measurements: measurements
        )

        formTracker.observe(frameIndex: frameIndex, coco17: coco17, pose3D: pose3D, pose3DState: pose3DState, phase: status.rawValue)
        let done = updateRepState(
            frameIndex: frameIndex,
            previousStatus: previousStatus,
            status: status,
            measurements: measurements
        )
        if repStarted { formTracker.recordCurrentFrame() }

        if frameIndex % 30 == 0 {
            printDebugSample(
                frameIndex: frameIndex,
                rawCandidate: rawCandidate,
                status: status,
                previousStatus: previousStatus,
                done: done,
                measurements: measurements
            )
        }

        let progressDroppedEnough = progressDropFromTop.map { $0 > 0.04 } ?? false
        let elapsedEnough = elapsedLoweringFrames >= config.minLoweringFramesForFallbackBottom

        return DeadliftFrameResult(
            frameIndex: frameIndex,
            status: status,
            rawStatusCandidate: rawCandidate,
            candidateStatus: candidateStatus,
            candidateStatusCount: candidateStatusCount,
            statusFrameCount: statusFrameCount,
            rep: completedRepCount,
            done: done,

            source: measurements.source,
            motion3DAvailable: measurements.motion3DAvailable,

            liftProgressNorm: measurements.liftProgressNorm,
            liftDepthDeltaNorm: measurements.progressDelta1,
            hipYVelocity: measurements.progressVelocityWindow,
            hipCenterY: measurements.hipHeightAboveAnkle,
            bottomHipYBaseline: measurements.bottomHeightBaseline,
            legLength: measurements.legLength,

            leftHipAngleDegrees: measurements.leftHipAngleDegrees,
            rightHipAngleDegrees: measurements.rightHipAngleDegrees,
            avgHipAngleDegrees: measurements.avgHipAngleDegrees,

            leftKneeAngleDegrees: measurements.leftKneeAngleDegrees,
            rightKneeAngleDegrees: measurements.rightKneeAngleDegrees,
            avgKneeAngleDegrees: measurements.avgKneeAngleDegrees,

            torsoLeanAngleDegrees: measurements.torsoLeanAngleDegrees,
            torsoLeanDeltaDegrees: measurements.torsoLeanDeltaDegrees,
            shoulderHeightNorm: measurements.shoulderHeightNorm,
            shoulderHeightDeltaNorm: measurements.shoulderHeightDeltaNorm,

            loweringTrigger: currentLoweringTrigger,
            currentRepMaxLiftDepthNorm: currentRepMaxLiftProgressNorm,
            currentRepMaxHipAngleDegrees: currentRepMaxHipAngleDegrees,
            currentRepMaxKneeAngleDegrees: currentRepMaxKneeAngleDegrees,

            repStarted: repStarted,
            sawRising: sawRising,
            reachedTop: reachedTop,
            sawLowering: sawLowering,
            lastCompletedRepSummary: completedRepSummaries.last,

            armBarProxyYNorm: measurements.armBarProxyYNorm,
            armBarProxyDelta1: measurements.armBarProxyDelta1,
            armBarProxyVelocityWindow: measurements.armBarProxyVelocityWindow,
            bottomArmProxyBaseline: measurements.bottomArmProxyBaseline,
            armProxyNearBottom: measurements.armProxyNearBottom,

            hipNearBottom: measurements.liftProgressNorm.map {
                $0 < config.loweringBottomProgressThreshold
            } ?? false,

            strictProgressBottom: measurements.liftProgressNorm.map {
                $0 < config.initialBottomProgressThreshold
            } ?? false,

            loweringTriggerReason: currentLoweringTrigger,
            bottomTriggerReason: currentBottomTrigger,

            progressDropFromTop: progressDropFromTop,
            progressDroppedEnoughFromTop: progressDroppedEnough,
            elapsedLoweringFrames: elapsedLoweringFrames,
            elapsedLoweringFramesEnough: elapsedEnough,
            loweringToBottomConfirmationFrames: config.loweringBottomConfirmationFrames,

            topProgressNorm: topProgressNorm,
            topArmProxyYNorm: topArmProxyYNorm,
            armBarProxyDropFromTop: armBarProxyDropFromTop,
            framesSinceTop: framesSinceTop,
            realDescentAfterTop: progressDroppedEnough || elapsedEnough,
            shouldCompleteRepAtBottom: repStarted && reachedTop && currentRepTopFrame != nil,
            wristProxyY: measurements.wristProxyY,
            wristLowerShinY: measurements.wristLowerShinY,
            wristBelowLowerShin: measurements.wristBelowLowerShin,
            elbowProxyY: measurements.elbowProxyY,
            elbowAboveWaist: measurements.elbowAboveWaist
        )
    }

    // MARK: - Measurements

    private func computeMeasurements(
        coco17: [PoseKeypoint],
        selected3D: [[Float]]?
    ) -> Measurements {
        let motion3DAvailable = isValid3D(selected3D)

        guard coco17.count == 17,
              lowerBodyJointsAreConfident(coco17) else {
            return Measurements(
                source: "2d_body",
                motion3DAvailable: motion3DAvailable,
                valid: false,
                liftProgressNorm: nil,
                progressDelta1: nil,
                progressVelocityWindow: nil,
                hipHeightAboveAnkle: nil,
                bottomHeightBaseline: bottomHeightBaseline,
                legLength: nil,
                leftHipAngleDegrees: nil,
                rightHipAngleDegrees: nil,
                avgHipAngleDegrees: nil,
                leftKneeAngleDegrees: nil,
                rightKneeAngleDegrees: nil,
                avgKneeAngleDegrees: nil,
                torsoLeanAngleDegrees: nil,
                torsoLeanDeltaDegrees: nil,
                shoulderHeightNorm: nil,
                shoulderHeightDeltaNorm: nil,
                armBarProxyYNorm: nil,
                armBarProxyDelta1: nil,
                armBarProxyVelocityWindow: nil,
                bottomArmProxyBaseline: bottomArmProxyBaseline,
                armProxyNearBottom: false,
                wristProxyY: nil,
                wristLowerShinY: nil,
                wristBelowLowerShin: false,
                elbowProxyY: nil,
                hipCenterY: nil,
                elbowAboveWaist: false,
                leftWristY: nil,
                rightWristY: nil,
                kneeY: nil,
                ankleY: nil
            )
        }

        let leftShoulder = coco17[COCO17.leftShoulder]
        let rightShoulder = coco17[COCO17.rightShoulder]
        let leftHip = coco17[COCO17.leftHip]
        let rightHip = coco17[COCO17.rightHip]
        let leftKnee = coco17[COCO17.leftKnee]
        let rightKnee = coco17[COCO17.rightKnee]
        let leftAnkle = coco17[COCO17.leftAnkle]
        let rightAnkle = coco17[COCO17.rightAnkle]

        let shoulderCenter = average(leftShoulder, rightShoulder)
        let hipCenter = average(leftHip, rightHip)
        let ankleCenter = average(leftAnkle, rightAnkle)

        let legLength = max(averageLegLength2D(coco17), 1.0)

        // image y increases downward.
        // ankleY - hipY is larger when hip is higher above ankles.
        let hipHeight = ankleCenter.y - hipCenter.y

        updateBottomHeightBaseline(
            hipHeight: hipHeight,
            normLength: legLength
        )

        let baseline = bottomHeightBaseline ?? hipHeight
        let progress = max(0.0, (hipHeight - baseline) / legLength)

        let (progressDelta1, progressVelocityWindow) = updateProgressHistory(
            progress: progress
        )

        let leftHipAngle = Self.angle2D(
            a: leftShoulder,
            b: leftHip,
            c: leftKnee
        )

        let rightHipAngle = Self.angle2D(
            a: rightShoulder,
            b: rightHip,
            c: rightKnee
        )

        let leftKneeAngle = Self.angle2D(
            a: leftHip,
            b: leftKnee,
            c: leftAnkle
        )

        let rightKneeAngle = Self.angle2D(
            a: rightHip,
            b: rightKnee,
            c: rightAnkle
        )

        let avgHipAngle = averageValid(leftHipAngle, rightHipAngle)
        let avgKneeAngle = averageValid(leftKneeAngle, rightKneeAngle)

        let torsoLean = torsoLeanAngle2D(
            shoulderCenter: shoulderCenter,
            hipCenter: hipCenter
        )

        let shoulderHeightNorm = (ankleCenter.y - shoulderCenter.y) / legLength

        let (armProxyYNorm, armProxyDelta1, armProxyVelocityWindow) =
            computeArmProxy(coco17: coco17, normLength: legLength)

        if let armProxyYNorm {
            updateBottomArmProxyBaseline(
                yNorm: armProxyYNorm,
                currentProgress: progress
            )
        }

        let armNearBottom: Bool
        if let armProxyYNorm,
           let bottomArmProxyBaseline {
            armNearBottom = armProxyYNorm >= bottomArmProxyBaseline - config.armProxyBottomTolerance
        } else {
            armNearBottom = false
        }

        let minConf = config.minJointConfidence
        let leftWrist = coco17[COCO17.leftWrist]
        let rightWrist = coco17[COCO17.rightWrist]
        let leftElbow = coco17[COCO17.leftElbow]
        let rightElbow = coco17[COCO17.rightElbow]

        let leftWristValid = leftWrist.confidence >= minConf
        let rightWristValid = rightWrist.confidence >= minConf
        let leftElbowValid = leftElbow.confidence >= minConf
        let rightElbowValid = rightElbow.confidence >= minConf
        let leftKneeValid = leftKnee.confidence >= minConf
        let rightKneeValid = rightKnee.confidence >= minConf
        let leftAnkleValid = leftAnkle.confidence >= minConf
        let rightAnkleValid = rightAnkle.confidence >= minConf
        let leftHipValid = leftHip.confidence >= minConf
        let rightHipValid = rightHip.confidence >= minConf

        // 1. Define lower-shin threshold (wristLowerShinY)
        var leftLowerShin: Double? = nil
        if leftKneeValid && leftAnkleValid {
            leftLowerShin = leftKnee.y + (leftAnkle.y - leftKnee.y) * config.wristLowerShinRatio
        }
        var rightLowerShin: Double? = nil
        if rightKneeValid && rightAnkleValid {
            rightLowerShin = rightKnee.y + (rightAnkle.y - rightKnee.y) * config.wristLowerShinRatio
        }
        
        let wristLowerShinY: Double?
        if let l = leftLowerShin, let r = rightLowerShin {
            wristLowerShinY = (l + r) * 0.5
        } else if let l = leftLowerShin {
            wristLowerShinY = l
        } else if let r = rightLowerShin {
            wristLowerShinY = r
        } else {
            wristLowerShinY = nil
        }

        // 2. Define wrist/bar proxy
        let wristProxyY: Double?
        if leftWristValid && rightWristValid {
            wristProxyY = (leftWrist.y + rightWrist.y) * 0.5
        } else if leftWristValid {
            wristProxyY = leftWrist.y
        } else if rightWristValid {
            wristProxyY = rightWrist.y
        } else {
            wristProxyY = nil
        }

        // 3. New bottom trigger: wristBelowLowerShin
        var wristBelowLowerShin = false
        if let wristProxyY = wristProxyY, let wristLowerShinY = wristLowerShinY {
            wristBelowLowerShin = wristProxyY >= wristLowerShinY
        }

        // 4. Hard bottom block: elbowAboveWaist
        let hipCenterY: Double?
        if leftHipValid && rightHipValid {
            hipCenterY = (leftHip.y + rightHip.y) * 0.5
        } else if leftHipValid {
            hipCenterY = leftHip.y
        } else if rightHipValid {
            hipCenterY = rightHip.y
        } else {
            hipCenterY = nil
        }

        let elbowProxyY: Double?
        if leftElbowValid && rightElbowValid {
            elbowProxyY = (leftElbow.y + rightElbow.y) * 0.5
        } else if leftElbowValid {
            elbowProxyY = leftElbow.y
        } else if rightElbowValid {
            elbowProxyY = rightElbow.y
        } else {
            elbowProxyY = nil
        }

        var elbowAboveWaist = false
        if let elbowProxyY = elbowProxyY, let hipCenterY = hipCenterY {
            let elbowHipTolerance = legLength * config.elbowHipBlockToleranceRatio
            elbowAboveWaist = elbowProxyY < (hipCenterY - elbowHipTolerance)
        } else {
            if elbowProxyY == nil {
                print("DeadliftEvaluator: no elbow is valid for elbowAboveWaist check")
            }
        }

        return Measurements(
            source: "2d_body",
            motion3DAvailable: motion3DAvailable,
            valid: true,
            liftProgressNorm: progress,
            progressDelta1: progressDelta1,
            progressVelocityWindow: progressVelocityWindow,
            hipHeightAboveAnkle: hipHeight,
            bottomHeightBaseline: baseline,
            legLength: legLength,

            leftHipAngleDegrees: leftHipAngle,
            rightHipAngleDegrees: rightHipAngle,
            avgHipAngleDegrees: avgHipAngle,

            leftKneeAngleDegrees: leftKneeAngle,
            rightKneeAngleDegrees: rightKneeAngle,
            avgKneeAngleDegrees: avgKneeAngle,

            torsoLeanAngleDegrees: torsoLean,
            torsoLeanDeltaDegrees: nil,
            shoulderHeightNorm: shoulderHeightNorm,
            shoulderHeightDeltaNorm: nil,

            armBarProxyYNorm: armProxyYNorm,
            armBarProxyDelta1: armProxyDelta1,
            armBarProxyVelocityWindow: armProxyVelocityWindow,
            bottomArmProxyBaseline: bottomArmProxyBaseline,
            armProxyNearBottom: armNearBottom,

            wristProxyY: wristProxyY,
            wristLowerShinY: wristLowerShinY,
            wristBelowLowerShin: wristBelowLowerShin,
            elbowProxyY: elbowProxyY,
            hipCenterY: hipCenterY,
            elbowAboveWaist: elbowAboveWaist,
            leftWristY: leftWristValid ? leftWrist.y : nil,
            rightWristY: rightWristValid ? rightWrist.y : nil,
            kneeY: {
                if leftKneeValid && rightKneeValid {
                    return (leftKnee.y + rightKnee.y) * 0.5
                } else if leftKneeValid {
                    return leftKnee.y
                } else if rightKneeValid {
                    return rightKnee.y
                }
                return nil
            }(),
            ankleY: {
                if leftAnkleValid && rightAnkleValid {
                    return (leftAnkle.y + rightAnkle.y) * 0.5
                } else if leftAnkleValid {
                    return leftAnkle.y
                } else if rightAnkleValid {
                    return rightAnkle.y
                }
                return nil
            }()
        )
    }

    private func updateBottomHeightBaseline(
        hipHeight: Double,
        normLength: Double
    ) {
        if bottomHeightBaseline == nil {
            bottomHeightBaseline = hipHeight
        }

        if baselineWarmupCount < config.baselineWarmupFrames {
            bottomHeightBaseline = min(bottomHeightBaseline ?? hipHeight, hipHeight)
            baselineWarmupCount += 1
            return
        }

        let clearlyLower = hipHeight < (bottomHeightBaseline ?? hipHeight) - normLength * config.baselineClearLowerRatio

        if stableStatus == .bottom ||
            stableStatus == .idle ||
            stableStatus == .unknown ||
            stableStatus == .lowering ||
            clearlyLower {
            bottomHeightBaseline = min(bottomHeightBaseline ?? hipHeight, hipHeight)
        }
    }

    private func updateProgressHistory(
        progress: Double
    ) -> (Double?, Double?) {
        let previous = progressHistory.last?.progress

        progressHistory.append(ProgressSample(progress: progress))

        let maxCount = max(config.progressLookbackFrames + 1, 2)
        if progressHistory.count > maxCount {
            progressHistory.removeFirst(progressHistory.count - maxCount)
        }

        let delta1 = previous.map { progress - $0 }

        let windowDelta: Double?
        if progressHistory.count > config.progressLookbackFrames {
            let past = progressHistory[progressHistory.count - 1 - config.progressLookbackFrames]
            windowDelta = progress - past.progress
        } else {
            windowDelta = nil
        }

        return (delta1, windowDelta)
    }

    private func computeArmProxy(
        coco17: [PoseKeypoint],
        normLength: Double
    ) -> (Double?, Double?, Double?) {
        let minConf = config.minJointConfidence

        let leftWristValid =
            coco17[COCO17.leftWrist].confidence >= minConf

        let rightWristValid =
            coco17[COCO17.rightWrist].confidence >= minConf

        let leftElbowValid =
            coco17[COCO17.leftElbow].confidence >= minConf

        let rightElbowValid =
            coco17[COCO17.rightElbow].confidence >= minConf

        let y: Double?

        if leftWristValid && rightWristValid {
            y = (coco17[COCO17.leftWrist].y + coco17[COCO17.rightWrist].y) * 0.5
        } else if leftElbowValid && rightElbowValid {
            y = (coco17[COCO17.leftElbow].y + coco17[COCO17.rightElbow].y) * 0.5
        } else if leftWristValid {
            y = coco17[COCO17.leftWrist].y
        } else if rightWristValid {
            y = coco17[COCO17.rightWrist].y
        } else if leftElbowValid {
            y = coco17[COCO17.leftElbow].y
        } else if rightElbowValid {
            y = coco17[COCO17.rightElbow].y
        } else {
            y = nil
        }

        guard let y else {
            return (nil, nil, nil)
        }

        let yNorm = y / max(normLength, 1.0)

        let previous = armProxyHistory.last?.yNorm
        armProxyHistory.append(ArmProxySample(yNorm: yNorm))

        let maxCount = max(config.armProxyLookbackFrames + 1, 2)
        if armProxyHistory.count > maxCount {
            armProxyHistory.removeFirst(armProxyHistory.count - maxCount)
        }

        let delta1 = previous.map { yNorm - $0 }

        let windowDelta: Double?
        if armProxyHistory.count > config.armProxyLookbackFrames {
            let past = armProxyHistory[armProxyHistory.count - 1 - config.armProxyLookbackFrames]
            windowDelta = yNorm - past.yNorm
        } else {
            windowDelta = nil
        }

        return (yNorm, delta1, windowDelta)
    }

    private func updateBottomArmProxyBaseline(
        yNorm: Double,
        currentProgress: Double
    ) {
        if bottomArmProxyBaseline == nil {
            bottomArmProxyBaseline = yNorm
        }

        if baselineWarmupCount < config.baselineWarmupFrames {
            bottomArmProxyBaseline = max(bottomArmProxyBaseline ?? yNorm, yNorm)
            return
        }

        let nearBottom = currentProgress < config.loweringBottomProgressThreshold

        if stableStatus == .bottom ||
            stableStatus == .idle ||
            stableStatus == .unknown ||
            (stableStatus == .lowering && nearBottom) {
            bottomArmProxyBaseline = max(bottomArmProxyBaseline ?? yNorm, yNorm)
        }
    }

    // MARK: - State machine

    private func classifyRawStatusCandidate(
        _ measurements: Measurements
    ) -> DeadliftStatus {
        currentLoweringTrigger = "none"
        currentBottomTrigger = "none"

        guard measurements.valid,
              let progress = measurements.liftProgressNorm else {
            return .unknown
        }

        // 1. LOWERING -> BOTTOM
        // Bottom is triggered ONLY by wristBelowLowerShin.
        // No progress-based, elapsed-frame, or arm-proxy fallback triggers.
        if stableStatus == .lowering,
           repStarted,
           reachedTop {
            if measurements.elbowAboveWaist {
                currentBottomTrigger = "blocked_elbow_above_waist"
                return .lowering
            }

            if measurements.wristBelowLowerShin {
                currentBottomTrigger = "wristBelowLowerShin"
                return .bottom
            }

            currentBottomTrigger = "not_low_enough"
            return .lowering
        }

        // 2. INITIAL / IDLE BOTTOM
        if !repStarted ||
            stableStatus == .idle ||
            stableStatus == .unknown ||
            stableStatus == .bottom {
            if progress < config.initialBottomProgressThreshold {
                currentBottomTrigger = "initialProgressBottom"
                return .bottom
            }
        }

        // 3. TOP -> LOWERING
        if stableStatus == .top || stableStatus == .lowering {
            let armDeltaDrop =
                measurements.armBarProxyDelta1.map {
                    $0 > config.barDropDeltaThreshold
                } ?? false

            let armWindowDrop =
                measurements.armBarProxyVelocityWindow.map {
                    $0 > config.barDropVelocityThreshold
                } ?? false

            let progressDrop =
                measurements.progressDelta1.map {
                    $0 < config.loweringProgressDeltaThreshold
                } ?? false

            if armDeltaDrop {
                currentLoweringTrigger = "armDeltaDrop"
                return .lowering
            }

            if armWindowDrop {
                currentLoweringTrigger = "armWindowDrop"
                return .lowering
            }

            if progressDrop {
                currentLoweringTrigger = "progressDrop"
                return .lowering
            }
        }

        // 4. TOP
        let hipExtended =
            measurements.avgHipAngleDegrees.map {
                $0 > config.topHipAngleThreshold
            } ?? false

        let kneeExtended =
            measurements.avgKneeAngleDegrees.map {
                $0 > config.topKneeAngleThreshold
            } ?? false

        if progress > config.topProgressThreshold &&
            hipExtended &&
            kneeExtended {
            return .top
        }

        // 5. RISING
        let canRise =
            stableStatus == .bottom ||
            stableStatus == .rising ||
            stableStatus == .idle ||
            stableStatus == .unknown

        if canRise {
            let deltaRise =
                measurements.progressDelta1.map {
                    $0 > config.risingProgressDeltaThreshold
                } ?? false

            let windowRise =
                measurements.progressVelocityWindow.map {
                    $0 > config.risingProgressDeltaThreshold
                } ?? false

            if deltaRise || windowRise {
                return .rising
            }
        }

        return .unknown
    }

    private func updateStableStatus(
        rawCandidate: DeadliftStatus,
        measurements: Measurements
    ) -> DeadliftStatus {
        if !didInitializeStableStatus {
            didInitializeStableStatus = true

            if rawCandidate == .bottom || rawCandidate == .top {
                stableStatus = rawCandidate
                candidateStatus = rawCandidate
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

        if stableStatus == .unknown || stableStatus == .idle,
           measurements.liftProgressNorm != nil {
            unknownFramesWithValidDepth += 1

            if unknownFramesWithValidDepth > config.maxUnknownFramesWithValidDepth,
               rawCandidate == .unknown {
                candidateStatus = .bottom
                candidateStatusCount = max(
                    candidateStatusCount,
                    config.statusConfirmationFrames
                )
            }
        } else if stableStatus != .unknown && stableStatus != .idle {
            unknownFramesWithValidDepth = 0
        }

        // Fast top -> lowering
        if stableStatus == .top,
           candidateStatus == .lowering,
           candidateStatusCount >= config.topExitConfirmationFrames,
           statusFrameCount >= config.minTopDurationFrames {
            stableStatus = .lowering
            statusFrameCount = 0
            return stableStatus
        }

        // Fast lowering -> bottom
        if stableStatus == .lowering,
           candidateStatus == .bottom,
           candidateStatusCount >= config.loweringBottomConfirmationFrames,
           statusFrameCount >= config.minLoweringDurationFrames {
            stableStatus = .bottom
            statusFrameCount = 0
            return stableStatus
        }

        let candidateReady =
            candidateStatus != stableStatus &&
            candidateStatus != .unknown &&
            candidateStatusCount >= config.statusConfirmationFrames &&
            statusFrameCount >= config.minStatusDurationFrames

        if candidateReady {
            let transitionAllowed =
                isAllowedTransition(from: stableStatus, to: candidateStatus)

            let forceTransition =
                candidateStatusCount >= config.forceTransitionFrames

            if transitionAllowed || forceTransition {
                stableStatus = candidateStatus
                statusFrameCount = 0
                return stableStatus
            }
        }

        statusFrameCount += 1
        return stableStatus
    }

    private func isAllowedTransition(
        from current: DeadliftStatus,
        to next: DeadliftStatus
    ) -> Bool {
        guard current != next else {
            return false
        }

        switch current {
        case .idle:
            return next == .bottom || next == .rising

        case .unknown:
            return next == .bottom || next == .rising || next == .top

        case .bottom:
            return next == .rising

        case .rising:
            return next == .top || next == .bottom

        case .top:
            return next == .lowering

        case .lowering:
            return next == .bottom
        }
    }

    // MARK: - Rep logic

    private func updateRepState(
        frameIndex: Int,
        previousStatus: DeadliftStatus,
        status: DeadliftStatus,
        measurements: Measurements
    ) -> Bool {
        var done = false

        if status == .rising &&
            (previousStatus == .bottom ||
             previousStatus == .unknown ||
             previousStatus == .idle) {
            startRep(frameIndex: frameIndex)
        }

        if config.directBottomToTopStartsRep,
           status == .top,
           !repStarted,
           previousStatus == .bottom || previousStatus == .unknown || previousStatus == .idle {
            startRep(frameIndex: frameIndex)
        }

        if repStarted && (status == .rising || status == .top) {
            updateCurrentRep(measurements)
        }

        // Top means lockout accepted. It never increments rep.
        if repStarted,
           !reachedTop,
           status == .top {
            markTopReached(
                frameIndex: frameIndex,
                measurements: measurements
            )
        }

        if repStarted,
           reachedTop,
           status == .top {
            framesSinceTop += 1
        }

        if repStarted,
           reachedTop,
           status == .lowering {
            if !sawLowering {
                sawLowering = true
                elapsedLoweringFrames = 0
            }

            elapsedLoweringFrames += 1

            let currentProgress = measurements.liftProgressNorm ?? 0.0
            let topProgress =
                topProgressNorm ??
                currentRepMaxLiftProgressNorm ??
                currentProgress

            progressDropFromTop = topProgress - currentProgress

            if let currentArm = measurements.armBarProxyYNorm,
               let topArm = topArmProxyYNorm {
                armBarProxyDropFromTop = currentArm - topArm
            } else {
                armBarProxyDropFromTop = nil
            }
        }

        // Count only on stable lowering -> stable bottom.
        if previousStatus == .lowering,
           status == .bottom,
           repStarted,
           reachedTop,
           currentRepTopFrame != nil {
            done = completeRepAtBottom(
                frameIndex: frameIndex,
                measurements: measurements
            )
        }

        if status == .bottom,
           !done,
           repStarted,
           !reachedTop {
            resetCurrentRep()
        }

        return done
    }

    private func startRep(frameIndex: Int) {
        if repStarted && !reachedTop {
            return
        }

        formTracker.beginRep()
        repStarted = true
        sawRising = true
        reachedTop = false
        sawLowering = false

        currentRepStartFrame = frameIndex
        currentRepTopFrame = nil
        currentRepMaxLiftProgressNorm = nil
        currentRepMaxHipAngleDegrees = nil
        currentRepMaxKneeAngleDegrees = nil

        topProgressNorm = nil
        topArmProxyYNorm = nil
        progressDropFromTop = nil
        armBarProxyDropFromTop = nil
        elapsedLoweringFrames = 0
        framesSinceTop = 0
    }

    private func updateCurrentRep(
        _ measurements: Measurements
    ) {
        if let progress = measurements.liftProgressNorm {
            currentRepMaxLiftProgressNorm =
                max(currentRepMaxLiftProgressNorm ?? progress, progress)
        }

        if let hipAngle = measurements.avgHipAngleDegrees {
            currentRepMaxHipAngleDegrees =
                max(currentRepMaxHipAngleDegrees ?? hipAngle, hipAngle)
        }

        if let kneeAngle = measurements.avgKneeAngleDegrees {
            currentRepMaxKneeAngleDegrees =
                max(currentRepMaxKneeAngleDegrees ?? kneeAngle, kneeAngle)
        }
    }

    private func markTopReached(
        frameIndex: Int,
        measurements: Measurements
    ) {
        updateCurrentRep(measurements)

        reachedTop = true
        currentRepTopFrame = frameIndex
        topProgressNorm = measurements.liftProgressNorm
        topArmProxyYNorm = measurements.armBarProxyYNorm

        progressDropFromTop = nil
        armBarProxyDropFromTop = nil
        elapsedLoweringFrames = 0
        framesSinceTop = 0
    }


    private func completeRepAtBottom(
        frameIndex: Int,
        measurements: Measurements
    ) -> Bool {
        updateCurrentRep(measurements)

        guard repStarted,
              reachedTop,
              let startFrame = currentRepStartFrame,
              let topFrame = currentRepTopFrame else {
            return false
        }

        let maxProgress =
            currentRepMaxLiftProgressNorm ??
            measurements.liftProgressNorm ??
            0.0

        let maxHipAngle = currentRepMaxHipAngleDegrees
        let maxKneeAngle = currentRepMaxKneeAngleDegrees

        completedRepCount += 1

        let summary = DeadliftRepSummary(
            repIndex: completedRepCount,
            startFrame: startFrame,
            topFrame: topFrame,
            endFrame: frameIndex,
            maxLiftDepthNorm: maxProgress,
            maxHipAngleDegrees: maxHipAngle,
            maxKneeAngleDegrees: maxKneeAngle,
            warnings: formTracker.finishRep(repIndex: completedRepCount).warnings
        )

        completedRepSummaries.append(summary)
        trimCompletedRepSummaries()

        print(
            "Deadlift rep completed at bottom: " +
            "rep=\(completedRepCount) " +
            "frame=\(frameIndex) " +
            "topFrame=\(topFrame) " +
            "maxProgress=\(String(format: "%.3f", maxProgress)) " +
            "done=true"
        )

        resetCurrentRep()
        return true
    }

    private func resetCurrentRep() {
        repStarted = false
        sawRising = false
        reachedTop = false
        sawLowering = false

        currentRepStartFrame = nil
        currentRepTopFrame = nil
        currentRepMaxLiftProgressNorm = nil
        currentRepMaxHipAngleDegrees = nil
        currentRepMaxKneeAngleDegrees = nil

        topProgressNorm = nil
        topArmProxyYNorm = nil
        progressDropFromTop = nil
        armBarProxyDropFromTop = nil
        elapsedLoweringFrames = 0
        framesSinceTop = 0
    }

    private func trimCompletedRepSummaries() {
        if completedRepSummaries.count > config.maxStoredRepSummaries {
            completedRepSummaries.removeFirst(
                completedRepSummaries.count - config.maxStoredRepSummaries
            )
        }
    }

    private func makeSessionSummary() -> DeadliftSessionSummary {
        let maxDepths = completedRepSummaries.map { $0.maxLiftDepthNorm }

        return DeadliftSessionSummary(
            completedRepCount: completedRepCount,
            repCount: completedRepCount,
            avgMaxLiftDepthNorm: average(maxDepths),
            maxLiftDepthNorm: maxDepths.max(),
            maxHipAngleDegrees: completedRepSummaries.compactMap {
                $0.maxHipAngleDegrees
            }.max(),
            maxKneeAngleDegrees: completedRepSummaries.compactMap {
                $0.maxKneeAngleDegrees
            }.max()
        )
    }

    // MARK: - Debug

    private func printDebugSample(
        frameIndex: Int,
        rawCandidate: DeadliftStatus,
        status: DeadliftStatus,
        previousStatus: DeadliftStatus,
        done: Bool,
        measurements: Measurements
    ) {
        let coco17Info = buildCoco17DebugInfo(measurements)

        print(
            "Deadlift debug frame=\(frameIndex) " +
            "stable=\(status.rawValue) " +
            "raw=\(rawCandidate.rawValue) " +
            "cand=\(candidateStatus.rawValue)(\(candidateStatusCount)) " +
            "prev=\(previousStatus.rawValue) " +
            "wristProxyY=\(format(measurements.wristProxyY)) " +
            coco17Info +
            "wristLowerShinRatio=\(config.wristLowerShinRatio) " +
            "wristLowerShinY=\(format(measurements.wristLowerShinY)) " +
            "wristBelowLowerShin=\(measurements.wristBelowLowerShin) " +
            "elbowProxyY=\(format(measurements.elbowProxyY)) " +
            "hipCenterY=\(format(measurements.hipCenterY)) " +
            "elbowAboveWaist=\(measurements.elbowAboveWaist) " +
            "bottomTriggerReason=\(currentBottomTrigger) " +
            "repStarted=\(repStarted) " +
            "reachedTop=\(reachedTop) " +
            "topFrameExists=\(currentRepTopFrame != nil) " +
            "rep=\(completedRepCount) " +
            "done=\(done)"
        )
    }

    private func buildCoco17DebugInfo(
        _ measurements: Measurements
    ) -> String {
        return "leftWristY=\(format(measurements.leftWristY)) " +
            "rightWristY=\(format(measurements.rightWristY)) " +
            "kneeY=\(format(measurements.kneeY)) " +
            "ankleY=\(format(measurements.ankleY)) "
    }

    // MARK: - Geometry helpers

    private func lowerBodyJointsAreConfident(
        _ coco17: [PoseKeypoint]
    ) -> Bool {
        [
            COCO17.leftShoulder,
            COCO17.rightShoulder,
            COCO17.leftHip,
            COCO17.rightHip,
            COCO17.leftKnee,
            COCO17.rightKnee,
            COCO17.leftAnkle,
            COCO17.rightAnkle
        ].allSatisfy { index in
            coco17.indices.contains(index) &&
            coco17[index].confidence >= config.minJointConfidence
        }
    }

    private func isValid3D(
        _ selected3D: [[Float]]?
    ) -> Bool {
        guard let selected3D,
              selected3D.count == 17 else {
            return false
        }

        return selected3D.allSatisfy { $0.count >= 3 }
    }

    private func averageLegLength2D(
        _ coco17: [PoseKeypoint]
    ) -> Double {
        let left =
            distance(coco17[COCO17.leftHip], coco17[COCO17.leftKnee]) +
            distance(coco17[COCO17.leftKnee], coco17[COCO17.leftAnkle])

        let right =
            distance(coco17[COCO17.rightHip], coco17[COCO17.rightKnee]) +
            distance(coco17[COCO17.rightKnee], coco17[COCO17.rightAnkle])

        return max((left + right) * 0.5, 1.0)
    }

    private func average(
        _ values: [Double]
    ) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0.0, +) / Double(values.count)
    }

    private func averageValid(
        _ a: Double?,
        _ b: Double?
    ) -> Double? {
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

    private func average(
        _ a: PoseKeypoint,
        _ b: PoseKeypoint
    ) -> PoseKeypoint {
        PoseKeypoint(
            x: (a.x + b.x) * 0.5,
            y: (a.y + b.y) * 0.5,
            confidence: (a.confidence + b.confidence) * 0.5
        )
    }

    private func distance(
        _ a: PoseKeypoint,
        _ b: PoseKeypoint
    ) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func torsoLeanAngle2D(
        shoulderCenter: PoseKeypoint,
        hipCenter: PoseKeypoint
    ) -> Double? {
        let dx = shoulderCenter.x - hipCenter.x
        let dy = shoulderCenter.y - hipCenter.y
        let norm = sqrt(dx * dx + dy * dy)

        guard norm > 1e-8 else {
            return nil
        }

        return abs(atan2(dx, dy)) * 180.0 / .pi
    }

    private static func angle2D(
        a: PoseKeypoint,
        b: PoseKeypoint,
        c: PoseKeypoint
    ) -> Double? {
        let ux = a.x - b.x
        let uy = a.y - b.y
        let vx = c.x - b.x
        let vy = c.y - b.y

        let uNorm = sqrt(ux * ux + uy * uy)
        let vNorm = sqrt(vx * vx + vy * vy)

        guard uNorm > 1e-8,
              vNorm > 1e-8 else {
            return nil
        }

        let cosine = min(
            max((ux * vx + uy * vy) / (uNorm * vNorm), -1.0),
            1.0
        )

        return acos(cosine) * 180.0 / .pi
    }

    private func format(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "-"
        }

        return String(format: "%.3f", value)
    }
}