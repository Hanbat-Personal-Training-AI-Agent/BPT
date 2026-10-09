import Foundation
import simd

/// Bone-length constraint for MotionAGFormer H36M17 3D output (`selected3D`, [17,3]).
/// Mirrors pose_feedback/geometry/bone_lengths.py; both are pinned by
/// tests/fixtures/bone_length_cases.json.
///
/// Targets are the calibration's boneLengthData.segments (cm). MotionAGFormer output is
/// root-relative in normalized screen units, so only proportions are used: per frame
/// s = median(observed / target) over the constrained segments, and each constrained segment
/// becomes target * s (blended with the observed length by `blend`). Walking the tree from the
/// pelvis, every child keeps its direction and its subtree moves with it; unconstrained
/// segments keep their length. Not wired into the app yet; call right after selected3D,
/// before KneeHingeLimit.
enum BoneLengthConstraint {
    static let joints = [
        "pelvis", "right_hip", "right_knee", "right_ankle", "left_hip", "left_knee", "left_ankle",
        "spine", "thorax", "neck", "head",
        "left_shoulder", "left_elbow", "left_wrist", "right_shoulder", "right_elbow", "right_wrist",
    ]
    static let parents = [-1, 0, 1, 2, 0, 4, 5, 0, 7, 8, 9, 8, 11, 12, 8, 14, 15]
    /// segmentNames[child - 1] is the "<parent>-<child>" key of boneLengthData.segments.
    static let segmentNames = (1..<17).map { "\(joints[parents[$0]])-\(joints[$0])" }
    /// Limbs only: torso/head joints are synthesized in the app, and the app pelvis is the
    /// midpoint of COCO hip landmarks rather than SMPL hip joint centers.
    static let defaultSegments: Set<String> = [
        "right_hip-right_knee", "right_knee-right_ankle", "left_hip-left_knee", "left_knee-left_ankle",
        "left_shoulder-left_elbow", "left_elbow-left_wrist", "right_shoulder-right_elbow", "right_elbow-right_wrist",
    ]
    static let minBoneLength = 1e-6

    struct Config {
        var enabled = true
        var segments = BoneLengthConstraint.defaultSegments
        /// 1 = hard constraint, 0 = observed length.
        var blend = 1.0
    }

    struct SegmentReport: Equatable {
        var observed: Double
        var output: Double
        var targetCm: Double?
        var constrained = false
        var degenerate: Bool
    }

    struct Result {
        var joints: [SIMD3<Double>]
        /// Model units per cm; nil when nothing was constrained (joints are then the input).
        var scale: Double?
        var segments: [String: SegmentReport]
    }

    static func apply(_ input: [SIMD3<Double>], targetsCm: [String: Double], config: Config = Config()) -> Result {
        precondition(input.count == 17, "H36M17 expects 17 joints")
        precondition(config.segments.isSubset(of: segmentNames), "unknown segment")
        precondition((0...1).contains(config.blend), "blend must be in [0, 1]")
        var observed = [0.0]
        var use = [false]
        var ratios: [Double] = []
        var reports: [String: SegmentReport] = [:]
        for c in 1..<17 {
            let name = segmentNames[c - 1]
            let length = simd_length(input[c] - input[parents[c]])
            let target = targetsCm[name]
            let degenerate = length < minBoneLength
            let used = config.enabled && config.segments.contains(name) && target != nil && !degenerate
            if used, let target { ratios.append(length / target) }
            observed.append(length)
            use.append(used)
            reports[name] = SegmentReport(observed: length, output: length, targetCm: target, degenerate: degenerate)
        }
        guard !ratios.isEmpty else { return Result(joints: input, scale: nil, segments: reports) }

        ratios.sort()
        let n = ratios.count
        let scale = n % 2 == 1 ? ratios[n / 2] : 0.5 * (ratios[n / 2 - 1] + ratios[n / 2])
        var out = input
        for c in 1..<17 {
            let p = parents[c]
            var d = input[c] - input[p]
            if use[c], let target = targetsCm[segmentNames[c - 1]] {
                let length = observed[c] + config.blend * (target * scale - observed[c])
                d = d / observed[c] * length
                reports[segmentNames[c - 1]]?.constrained = true
                reports[segmentNames[c - 1]]?.output = length
            }
            out[c] = out[p] + d
        }
        return Result(joints: out, scale: scale, segments: reports)
    }

    /// Calibration result JSON (status response, result, or boneLengthData) -> {segment: cm}.
    /// Drops appDefinitionDiffers segments, non-H36M17 names and values that are missing,
    /// non-numeric, non-finite or <= 0.
    static func loadTargets(json: Data) throws -> [String: Double] {
        guard var obj = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [:] }
        if let inner = obj["result"] as? [String: Any] { obj = inner }
        if let inner = obj["boneLengthData"] as? [String: Any] { obj = inner }
        let segments = obj["segments"] as? [String: Any] ?? [:]
        let skip = Set(obj["appDefinitionDiffers"] as? [String] ?? [])
        var targets: [String: Double] = [:]
        for name in segmentNames where !skip.contains(name) {
            // JSON booleans also bridge to NSNumber; reject them like the Python loader does.
            guard let number = segments[name] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
            let value = number.doubleValue
            if value.isFinite, value > 0 { targets[name] = value }
        }
        return targets
    }
}
