import Foundation

enum BenchPressStatus: String {
    case top
    case lowering
    case bottom
    case pressing
    case unknown
}

struct BenchPressFrameResult {
    let frameIndex: Int
    let status: BenchPressStatus
    let rawStatusCandidate: BenchPressStatus?
    let candidateStatus: BenchPressStatus?
    let candidateStatusCount: Int
    let statusFrameCount: Int
    let rep: Int
    let done: Bool
    let pressDepthNorm: Double?
    let pressDepthDeltaNorm: Double?
    let leftElbowAngleDegrees: Double?
    let rightElbowAngleDegrees: Double?
    let avgElbowAngleDegrees: Double?
    let elbowAngleDeltaDegrees: Double?
    let observedMinElbowAngleDegrees: Double?
    let observedMaxElbowAngleDegrees: Double?
    let effectiveTopElbowThreshold: Double?
    let effectiveBottomElbowThreshold: Double?
    let depthSignalReliable: Bool
    let currentRepMaxDepthNorm: Double?
    let currentRepMinElbowAngleDegrees: Double?
    let repStarted: Bool
    let sawLowering: Bool
    let sawPressing: Bool
    let lastCompletedRepSummary: BenchPressRepSummary?

    // New HUD/debug fields
    let hadElbowExtensionDuringRep: Bool
    let bottomFrameExists: Bool
    let lastStableStatus: String
    let transitionedToTop: Bool
    let shouldCompleteRep: Bool
    let sawBottom: Bool

    var dictionary: [String: Any] {
        [
            "frame_index": frameIndex,
            "status": status.rawValue,
            "raw_status_candidate": rawStatusCandidate.map { $0.rawValue as Any } ?? NSNull(),
            "candidate_status": candidateStatus.map { $0.rawValue as Any } ?? NSNull(),
            "candidate_status_count": candidateStatusCount,
            "status_frame_count": statusFrameCount,
            "rep": rep,
            "done": done,
            "press_depth_norm": jsonValue(pressDepthNorm),
            "press_depth_delta_norm": jsonValue(pressDepthDeltaNorm),
            "left_elbow_angle_degrees": jsonValue(leftElbowAngleDegrees),
            "right_elbow_angle_degrees": jsonValue(rightElbowAngleDegrees),
            "avg_elbow_angle_degrees": jsonValue(avgElbowAngleDegrees),
            "elbow_angle_delta_degrees": jsonValue(elbowAngleDeltaDegrees),
            "observed_min_elbow_angle_degrees": jsonValue(observedMinElbowAngleDegrees),
            "observed_max_elbow_angle_degrees": jsonValue(observedMaxElbowAngleDegrees),
            "effective_top_elbow_threshold": jsonValue(effectiveTopElbowThreshold),
            "effective_bottom_elbow_threshold": jsonValue(effectiveBottomElbowThreshold),
            "depth_signal_reliable": depthSignalReliable,
            "current_rep_max_depth_norm": jsonValue(currentRepMaxDepthNorm),
            "current_rep_min_elbow_angle_degrees": jsonValue(currentRepMinElbowAngleDegrees),
            "rep_started": repStarted,
            "saw_lowering": sawLowering,
            "saw_pressing": sawPressing,
            "last_completed_rep_summary": lastCompletedRepSummary.map { $0.dictionary as Any } ?? NSNull(),
            
            // New HUD/debug fields
            "had_elbow_extension_during_rep": hadElbowExtensionDuringRep,
            "bottom_frame_exists": bottomFrameExists,
            "last_stable_status": lastStableStatus,
            "transitioned_to_top": transitionedToTop,
            "should_complete_rep": shouldCompleteRep,
            "saw_bottom": sawBottom,
        ]
    }

    private func jsonValue(_ value: Double?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }
}

struct BenchPressRepSummary {
    let repIndex: Int
    let startFrame: Int
    let bottomFrame: Int?
    let endFrame: Int?
    let maxDepthNorm: Double?
    let minElbowAngleDegrees: Double?
    /// Filled when the form tracker closes the rep (after the lockout window, see
    /// `BenchPressEvaluatorConfig.lockoutWindowFrames`).
    var warnings: [String]

    var dictionary: [String: Any] {
        [
            "rep_index": repIndex,
            "start_frame": startFrame,
            "bottom_frame": bottomFrame.map { $0 as Any } ?? NSNull(),
            "end_frame": endFrame.map { $0 as Any } ?? NSNull(),
            "max_depth_norm": maxDepthNorm.map { $0 as Any } ?? NSNull(),
            "min_elbow_angle_degrees": minElbowAngleDegrees.map { $0 as Any } ?? NSNull(),
            "warnings": warnings,
        ]
    }
}

struct BenchPressSessionSummary {
    let completedRepCount: Int
    let repCount: Int
    let avgMaxDepthNorm: Double?
    let maxDepthNorm: Double?
    let minElbowAngleDegrees: Double?

    var dictionary: [String: Any] {
        [
            "completed_rep_count": completedRepCount,
            "rep_count": repCount,
            "avg_max_depth_norm": avgMaxDepthNorm.map { $0 as Any } ?? NSNull(),
            "max_depth_norm": maxDepthNorm.map { $0 as Any } ?? NSNull(),
            "min_elbow_angle_degrees": minElbowAngleDegrees.map { $0 as Any } ?? NSNull(),
        ]
    }
}
