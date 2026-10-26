import Foundation
import simd

/// Observation diagnostics only. No speech, pose correction, inferred ideal baseline, or lumbar diagnosis.
/// The app enables logging explicitly with BPT_EXPERIMENTAL_COACHING=1; the default path never calls this.
struct ExperimentalCoaching {
    struct Frame {
        let time: Double
        let exercise: String
        let phase: String?
        let state: String
        let raw: [SIMD3<Double>]?
        let corrected: [SIMD3<Double>]?
        let confidence: [Double]?
        let invalid: Set<Int>?
        let up: SIMD3<Double>?
    }
    /// Supplied explicitly by a caller after approval; never learned from initial repetitions.
    /// Thresholds are experimental candidate settings, not a validated catalogue or medical norms.
    struct Profile {
        let exercise: String
        let variant: String
        let approved: Bool
        let upperArmRange: ClosedRange<Double>?
        let legExtensionDegrees: Double
        let elbowFlexionDegrees: Double
        let sustainSeconds: Double
    }
    struct Metric: Codable {
        let value: Double?
        let rawValue: Double?
        let reasons: [String]
        var available: Bool { value != nil && reasons.isEmpty }
    }
    struct Candidate: Codable {
        let key: String
        let assessment: String
        let reasons: [String]
    }
    struct Output: Codable {
        let time: Double
        let metrics: [String: Metric]
        let candidates: [Candidate]
    }
    private struct History {
        let time: Double
        let phase: String
        let exercise: String
        let metrics: [String: Metric]
    }
    private var history: History?
    private var since: [String: Double] = [:]
    private var previousTime: Double?
    var minConfidence = 0.5
    var maxCorrectionDegrees = 10.0
    var maxGapSeconds = 0.25

    mutating func update(_ frame: Frame, profile: Profile? = nil) -> Output {
        if !frame.time.isFinite || previousTime.map({ frame.time <= $0 || frame.time - $0 > maxGapSeconds }) == true {
            history = nil; since.removeAll()
        }
        previousTime = frame.time
        var metrics: [String: Metric] = [:]
        func measure(_ ids: [Int], _ fn: ([SIMD3<Double>]) -> Double?) -> Metric {
            let corrected = frame.corrected.flatMap { $0.count == 17 ? fn($0) : nil }
            let raw = frame.raw.flatMap { $0.count == 17 ? fn($0) : nil }
            var reasons: [String] = []
            if !["ok", "partial_3d"].contains(frame.state) { reasons.append("unusable_3d") }
            if let invalid = frame.invalid {
                if !invalid.isDisjoint(with: ids) { reasons.append("invalid_joint") }
            } else { reasons.append("missing_invalid_mask") }
            if let c = frame.confidence, c.count == 17 {
                if ids.contains(where: { !c[$0].isFinite || c[$0] < minConfidence }) { reasons.append("low_joint_support") }
            } else { reasons.append("missing_joint_support") }
            if raw == nil { reasons.append("missing_raw_geometry") }
            if corrected == nil { reasons.append("missing_geometry") }
            if let a = raw, let b = corrected, abs(a - b) > maxCorrectionDegrees { reasons.append("correction_disagreement") }
            return Metric(value: corrected, rawValue: raw, reasons: reasons)
        }
        for (side, hip, knee, ankle, shoulder, elbow, wrist) in [
            ("right", 1, 2, 3, 14, 15, 16), ("left", 4, 5, 6, 11, 12, 13)
        ] {
            metrics[side + "KneeDeg"] = measure([hip, knee, ankle]) { Self.angle($0[hip] - $0[knee], $0[ankle] - $0[knee]) }
            metrics[side + "ElbowDeg"] = measure([shoulder, elbow, wrist]) { Self.angle($0[shoulder] - $0[elbow], $0[wrist] - $0[elbow]) }
            metrics[side + "HipDeg"] = measure([hip, knee, 8]) { Self.angle($0[8] - $0[hip], $0[knee] - $0[hip]) }
            // Projection into body frontal plane removes forward/backward shoulder flexion.
            // Absolute abduction from the caudal trunk axis; not a camera-plane elbow angle.
            metrics[side + "UpperArmDeg"] = measure([0, 8, 11, 14, shoulder, elbow]) { j in
                guard let down = Self.unit(j[0] - j[8]), let lateral = Self.unit(j[11] - j[14]),
                      let normal = Self.unit(simd_cross(down, lateral)) else { return nil }
                let arm = j[elbow] - j[shoulder]
                return Self.angle(down, arm - simd_dot(arm, normal) * normal)
            }
        }
        var trunk = measure([0, 8]) { j in
            guard let up = frame.up else { return nil }
            return Self.angle(j[8] - j[0], up)
        }
        if frame.up == nil { trunk = Metric(value: trunk.value, rawValue: trunk.rawValue, reasons: trunk.reasons + ["missing_gravity"]) }
        metrics["trunkInclineDeg"] = trunk
        let phase = frame.phase ?? ""
        if history?.phase != phase || history?.exercise != frame.exercise {
            history = nil; since.removeAll()
        }
        let prior = history
        // Baseline is only the beginning of the same uninterrupted movement phase, never an ideal pose.
        if history == nil, frame.time.isFinite { history = History(time: frame.time, phase: phase, exercise: frame.exercise, metrics: metrics) }
        var candidates: [Candidate] = []
        func profileReasons(_ variant: String) -> [String] {
            guard let p = profile, p.approved, p.exercise == frame.exercise, p.variant == variant,
                  p.sustainSeconds.isFinite, p.sustainSeconds > 0,
                  p.legExtensionDegrees.isFinite, p.legExtensionDegrees > 0,
                  p.elbowFlexionDegrees.isFinite, p.elbowFlexionDegrees > 0 else { return ["approved_profile_required"] }
            return []
        }
        func metricReasons(_ keys: [String], baseline: Bool = false) -> [String] {
            var reasons = keys.flatMap { metrics[$0]?.reasons ?? ["missing_geometry"] }
            if baseline {
                if let prior { reasons += keys.flatMap { prior.metrics[$0]?.reasons ?? ["missing_baseline"] } }
                else { reasons.append("phase_baseline_required") }
            }
            return Array(Set(reasons)).sorted()
        }
        func delta(_ key: String) -> Double {
            guard let now = metrics[key]?.value, let start = prior?.metrics[key]?.value else { return 0 }
            return now - start
        }
        func emit(_ key: String, reasons: [String], condition: Bool) {
            if !reasons.isEmpty || !condition { since[key] = nil }
            else if since[key] == nil { since[key] = frame.time }
            let sustained = since[key].map { frame.time - $0 >= (profile?.sustainSeconds ?? .infinity) } ?? false
            candidates.append(Candidate(key: key, assessment: !reasons.isEmpty ? "withheld" : sustained ? "candidate" : "not_triggered",
                                        reasons: Array(Set(reasons)).sorted()))
        }
        if frame.exercise == "barbell_row" {
            let keys = ["leftKneeDeg", "rightKneeDeg", "leftElbowDeg", "rightElbowDeg"]
            let reasons = profileReasons("strict_row") + metricReasons(keys, baseline: true) + (phase == "pulling" ? [] : ["pulling_phase_required"])
            let legs = min(delta(keys[0]), delta(keys[1])) >= (profile?.legExtensionDegrees ?? .infinity)
            let arms = min(-delta(keys[2]), -delta(keys[3])) >= (profile?.elbowFlexionDegrees ?? .infinity)
            // Coincident joint motion only: cannot establish force, intentional cheating, or bar travel.
            emit("row_leg_drive", reasons: reasons, condition: legs && arms)
        }
        if frame.exercise == "pushup" {
            let keys = ["leftUpperArmDeg", "rightUpperArmDeg"]
            let range = profile?.upperArmRange
            var reasons = profileReasons("approved_pushup") + metricReasons(keys)
            if range == nil || range?.lowerBound.isFinite != true || range?.upperBound.isFinite != true { reasons.append("approved_upper_arm_range_required") }
            if !["descending", "bottom", "ascending"].contains(phase) { reasons.append("active_phase_required") }
            emit("pushup_elbow_flare", reasons: reasons, condition: keys.contains { key in
                guard let value = metrics[key]?.value, let range else { return false }
                return !range.contains(value)
            })
        }
        if frame.exercise == "deadlift" {
            let keys = ["leftElbowDeg", "rightElbowDeg"]
            let reasons = profileReasons("double_overhand_deadlift") + metricReasons(keys, baseline: true) + (phase == "rising" ? [] : ["rising_phase_required"])
            emit("deadlift_arm_pull", reasons: reasons,
                 condition: keys.contains { -delta($0) >= (profile?.elbowFlexionDegrees ?? .infinity) })
        }
        // An unobservable phase must not become a later valid baseline.
        if metrics.values.allSatisfy({ !$0.available }) { history = nil }
        return Output(time: frame.time.isFinite ? frame.time : 0, metrics: metrics, candidates: candidates)
    }
    static func unit(_ v: SIMD3<Double>) -> SIMD3<Double>? {
        let length = simd_length(v)
        guard length.isFinite, length > 1e-8 else { return nil }
        return v / length
    }
    static func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double? {
        guard let a = unit(a), let b = unit(b) else { return nil }
        return acos(max(-1, min(1, simd_dot(a, b)))) * 180 / .pi
    }
}
