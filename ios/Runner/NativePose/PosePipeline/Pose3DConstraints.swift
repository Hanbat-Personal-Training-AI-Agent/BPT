import Foundation
import simd

/// Anatomical constraints on the final MotionAGFormer-XS H36M17 output. Mirrors
/// pose_feedback/geometry/pose3d_constraints.py (tests/fixtures/live3d_parity.json pins both). Every limit below is a copy
/// of pose_feedback/geometry/anatomical_limits.json, the one config with the evidence per entry (PoseConstraintLimitsTests
/// fails when they differ).
///
/// Order: XS output → bone lengths (BoneLengthConstraint: calibration cm when present, else the session's
/// running median lengths, L/R averaged, else population ratios) → knee depth flip (θ < −30°: detected, reflected on
/// squats) → knee hyperextension clamp (θ ≥ −15°, KneeHingeLimit) → interior joint-angle limits (knee/elbow flexion,
/// hip, shoulder, spine). No smoothing.
/// Each step reports how far it moved the pose; `Report.bad` (moved more than `badAngleDegrees` /
/// `badBoneFraction`) is the "3D 불량" quality signal (MotionAGFormerLive state bad3D).
/// Stateful only through the session bone-length median (`apply` is mutating).
struct Pose3DConstraints {
    struct AngleLimit {
        let name: String
        /// Angle between (refTo − refFrom) and (child − joint); out of [minDegrees, maxDegrees] the child
        /// subtree is rotated about `joint` in that plane onto the nearest limit.
        let refFrom: Int, refTo: Int, joint: Int, child: Int
        var minDegrees: Double
        var maxDegrees: Double
    }

    struct Report {
        /// Largest |constrained − observed| / observed over the constrained segments (0 when off).
        var boneMaxCorrection = 0.0
        var boneSource = "none"
        var kneeHyperextended = false
        var kneeCorrectionDegrees = 0.0
        /// Rotation the hyperextension clamp applied (θ < −kneeClampDegrees → −kneeClampDegrees), largest leg.
        var kneeClampDegrees = 0.0
        /// Legs whose knee was reflected across the hip–ankle line (depth flip fixed; interior angle and bone lengths kept).
        var kneesReflected = 0
        /// name → degrees moved (only limits that fired).
        var angleCorrections: [String: Double] = [:]
        /// H36M17 joints whose 3D is not trusted this frame: a flipped knee (detection only), the subtree of a joint an
        /// angle limit moved more than `badAngleDegrees`, or every joint when the bone gate is set and exceeded.
        /// Metrics that need one of them are skipped; the others stay valid (per-metric invalidation).
        var invalidJoints: Set<Int> = []
        var bad = false
        var maxAngleCorrection: Double { max(kneeCorrectionDegrees, kneeClampDegrees, angleCorrections.values.max() ?? 0) }
    }

    var enabled = true
    var boneLengths = true
    /// Calibration boneLengthData.segments (cm). nil = session median / population prior.
    var calibrationTargetsCm: [String: Double]?
    /// Relative segment lengths for the first `sessionMinFrames` frames (only ratios matter): Fit3D mocap, 8 subjects,
    /// upper arm / thigh 0.60–0.63, forearm / thigh 0.54–0.57, shin / thigh 0.95–1.06 (lift_app.md S2).
    var priorLengths: [String: Double] = [
        "right_hip-right_knee": 1.0, "left_hip-left_knee": 1.0,
        "right_knee-right_ankle": 1.0, "left_knee-left_ankle": 1.0,
        "left_shoulder-left_elbow": 0.61, "right_shoulder-right_elbow": 0.61,
        "left_elbow-left_wrist": 0.55, "right_elbow-right_wrist": 0.55,
    ]
    /// Session median replaces the prior after this many frames.
    var sessionMinFrames = 30
    var sessionWindowFrames = 300
    /// Knee θ < −30°: the XS knee is not trusted (S3/T2) — marked invalid (detection, no correction at this limit).
    var knee = KneeHingeLimit.Config(enabled: false, limitDegrees: 30)
    /// Hyperextension clamp: θ below −15° is rotated back onto −15° (a knee never bends backwards past it: CDC normal
    /// extension 1.0–1.6°, Beighton hypermobility > 10°, Fit3D squat/push-up/row never below −10°). nil = off. 제안값.
    var kneeClampDegrees: Double? = 15
    /// Knee depth flip fix (S3: in 100% of flagged legs the XS knee sits on the wrong side of the hip–ankle line in depth):
    /// reflect the knee across that line, so θ turns positive with the same interior angle and segment lengths. The frame
    /// then stays usable. false = detection only (the flip marks bad3D). Fit3D S6: right on squats (17/17 closer to mocap),
    /// a coin flip on push-ups (40% / 30% closer) — so callers turn it on for the squat only. 제안값.
    var reflectFlippedKnee = false
    var angleLimits: [AngleLimit] = Pose3DConstraints.defaultAngleLimits
    /// bad3D: an angle limit had to move a joint more than this, or the knee depth flipped. 제안값(사용자 미승인).
    var badAngleDegrees = 20.0
    /// Bone corrections are applied but do not mark bad3D by default (nil): at 0.30 they flagged 43% of normal Fit3D
    /// push-up frames and do not predict angle error (S5). Set a fraction to gate on them.
    var badBoneFraction: Double?

    /// Interior-angle limits (H36M17) = anatomical_limits.json: Fit3D mocap p0.1 / p99.9 over 47 exercises, 8 subjects,
    /// checked against normal ROM (CDC): knee ≥ 41°, elbow ≥ 22°, hip ≥ 32°, spine ≥ 120° (row p0.1 123°), shoulder
    /// (trunk-down vs upper arm) ≤ 172°. 제안값(사용자 미승인).
    static let defaultAngleLimits: [AngleLimit] = [
        AngleLimit(name: "right_knee_flexion", refFrom: 2, refTo: 1, joint: 2, child: 3, minDegrees: 41, maxDegrees: 180),
        AngleLimit(name: "left_knee_flexion", refFrom: 5, refTo: 4, joint: 5, child: 6, minDegrees: 41, maxDegrees: 180),
        AngleLimit(name: "right_elbow_flexion", refFrom: 15, refTo: 14, joint: 15, child: 16, minDegrees: 22, maxDegrees: 180),
        AngleLimit(name: "left_elbow_flexion", refFrom: 12, refTo: 11, joint: 12, child: 13, minDegrees: 22, maxDegrees: 180),
        // Hip: trunk (pelvis → thorax) vs thigh; 180 = standing, small = deep flexion.
        AngleLimit(name: "right_hip", refFrom: 0, refTo: 8, joint: 1, child: 2, minDegrees: 32, maxDegrees: 180),
        AngleLimit(name: "left_hip", refFrom: 0, refTo: 8, joint: 4, child: 5, minDegrees: 32, maxDegrees: 180),
        AngleLimit(name: "right_shoulder", refFrom: 8, refTo: 0, joint: 14, child: 15, minDegrees: 0, maxDegrees: 172),
        AngleLimit(name: "left_shoulder", refFrom: 8, refTo: 0, joint: 11, child: 12, minDegrees: 0, maxDegrees: 172),
        // Spine: pelvis–spine–thorax interior angle.
        AngleLimit(name: "spine", refFrom: 7, refTo: 0, joint: 7, child: 8, minDegrees: 120, maxDegrees: 180),
    ]

    /// `joint` and every joint below it in the H36M17 tree.
    static func subtree(_ joint: Int) -> Set<Int> {
        var out: Set<Int> = [], stack = [joint]
        while let k = stack.popLast() {
            out.insert(k)
            stack += children[k]
        }
        return out
    }

    static let children: [[Int]] = {
        var c = Array(repeating: [Int](), count: 17)
        for (j, p) in BoneLengthConstraint.parents.enumerated() where p >= 0 { c[p].append(j) }
        return c
    }()

    private var history: [String: [Double]] = [:]

    mutating func resetSessionBoneHistory() { history = [:] }

    /// `projectBoneLengths=false` retains the bone report/gate and all existing angle gates, while
    /// avoiding a second hard bone projection after an experimental soft personalized estimator.
    mutating func apply(_ input: [SIMD3<Double>], projectBoneLengths: Bool = true) -> ([SIMD3<Double>], Report) {
        precondition(input.count == 17, "H36M17 expects 17 joints")
        var report = Report()
        guard enabled else { return (input, report) }
        var joints = input

        if boneLengths {
            let targets: [String: Double]
            if let calibrationTargetsCm, !calibrationTargetsCm.isEmpty {
                targets = calibrationTargetsCm
                report.boneSource = "calibration"
            } else if let session = sessionTargets() {
                targets = session
                report.boneSource = "session"
            } else {
                targets = priorLengths
                report.boneSource = "prior"
            }
            record(input)
            let bones = BoneLengthConstraint.apply(joints, targetsCm: targets)
            if projectBoneLengths { joints = bones.joints }
            report.boneMaxCorrection = bones.segments.values.filter(\.constrained)
                .map { abs($0.output - $0.observed) / max($0.observed, BoneLengthConstraint.minBoneLength) }.max() ?? 0
        }

        if reflectFlippedKnee {
            for (hip, kneeJoint, ankle) in [(1, 2, 3), (4, 5, 6)] {
                guard let (theta, _) = KneeHingeLimit.kneeTheta(joints, hip: hip, knee: kneeJoint, ankle: ankle),
                      theta < -knee.limitDegrees else { continue }
                let line = joints[ankle] - joints[hip]
                guard simd_length(line) > 1e-9 else { continue }
                let a = simd_normalize(line), v = joints[kneeJoint] - joints[hip]
                joints[kneeJoint] = joints[hip] + 2 * a * simd_dot(v, a) - v
                report.kneesReflected += 1
            }
        }
        let hinge = KneeHingeLimit.apply(joints, config: knee)
        joints = hinge.joints
        report.kneeHyperextended = hinge.bad3D
        report.kneeCorrectionDegrees = max(hinge.right.correctionDegrees, hinge.left.correctionDegrees)
        if let limit = kneeClampDegrees {
            let clamp = KneeHingeLimit.apply(joints, config: .init(enabled: true, limitDegrees: limit))
            joints = clamp.joints
            report.kneeClampDegrees = max(clamp.right.correctionDegrees, clamp.left.correctionDegrees)
        }

        for limit in angleLimits {
            if let moved = Self.clamp(&joints, limit), moved > 0 {
                report.angleCorrections[limit.name] = moved
                if moved > badAngleDegrees { report.invalidJoints.formUnion(Self.subtree(limit.child)) }
            }
        }
        if !knee.enabled {
            if hinge.right.hyperextended { report.invalidJoints.insert(2) }
            if hinge.left.hyperextended { report.invalidJoints.insert(5) }
        }
        if let gate = badBoneFraction, report.boneMaxCorrection > gate { report.invalidJoints = Set(0..<17) }
        report.bad = !report.invalidJoints.isEmpty
        return (joints, report)
    }

    /// Session targets: per-segment median of the observed lengths, left and right averaged.
    func sessionTargets() -> [String: Double]? {
        guard (history.values.map(\.count).min() ?? 0) >= sessionMinFrames, history.count == priorLengths.count else { return nil }
        var medians: [String: Double] = [:]
        for (name, values) in history { medians[name] = FormWarningTracker.median(values) }
        var out: [String: Double] = [:]
        for name in medians.keys {
            let mirror = name.replacingOccurrences(of: "left", with: "#").replacingOccurrences(of: "right", with: "left")
                .replacingOccurrences(of: "#", with: "right")
            out[name] = ((medians[name] ?? 0) + (medians[mirror] ?? medians[name] ?? 0)) / 2
        }
        return out
    }

    private mutating func record(_ joints: [SIMD3<Double>]) {
        for c in 1..<17 {
            let name = BoneLengthConstraint.segmentNames[c - 1]
            guard priorLengths[name] != nil else { continue }
            let length = simd_length(joints[c] - joints[BoneLengthConstraint.parents[c]])
            guard length > BoneLengthConstraint.minBoneLength else { continue }
            history[name, default: []].append(length)
            if history[name]!.count > sessionWindowFrames { history[name]!.removeFirst() }
        }
    }

    /// Rotates the subtree of `limit.child` about `limit.joint` so the angle lands on the nearest limit.
    /// Returns the degrees moved, nil when the plane is undefined (parallel / zero-length vectors).
    static func clamp(_ j: inout [SIMD3<Double>], _ limit: AngleLimit) -> Double? {
        let a = j[limit.refTo] - j[limit.refFrom], b = j[limit.child] - j[limit.joint]
        let na = simd_length(a), nb = simd_length(b)
        guard na > 1e-9, nb > 1e-9 else { return nil }
        let cross = simd_cross(a, b)
        let sinAB = simd_length(cross) / (na * nb)
        let theta = atan2(simd_length(cross), simd_dot(a, b)) * 180 / .pi
        let target = min(max(theta, limit.minDegrees), limit.maxDegrees)
        guard target != theta else { return 0 }
        guard sinAB > 0.05 else { return nil }
        let axis = cross / simd_length(cross)
        let phi = (target - theta) * .pi / 180
        let pivot = j[limit.joint]
        var stack = [limit.child]
        while let k = stack.popLast() {
            let v = j[k] - pivot
            j[k] = pivot + v * cos(phi) + simd_cross(axis, v) * sin(phi) + axis * simd_dot(axis, v) * (1 - cos(phi))
            stack += children[k]
        }
        return abs(target - theta)
    }
}
