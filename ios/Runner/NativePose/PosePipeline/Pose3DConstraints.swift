import Foundation
import simd

/// Anatomical constraints on the final MotionAGFormer-XS H36M17 output. Mirrors
/// pose_feedback/geometry/pose3d_constraints.py (tests/fixtures/pose3d_constraints_cases.json pins both).
///
/// Order: XS output → bone lengths (BoneLengthConstraint: calibration cm when present, else the session's
/// running median lengths, L/R averaged, else population ratios) → knee hyperextension (KneeHingeLimit)
/// → interior joint-angle limits (knee/elbow flexion, hip, shoulder, spine). No smoothing.
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
        /// name → degrees moved (only limits that fired).
        var angleCorrections: [String: Double] = [:]
        var bad = false
        var maxAngleCorrection: Double { max(kneeCorrectionDegrees, angleCorrections.values.max() ?? 0) }
    }

    var enabled = true
    var boneLengths = true
    /// Calibration boneLengthData.segments (cm). nil = session median / population prior.
    var calibrationTargetsCm: [String: Double]?
    /// Relative segment lengths when nothing better exists (only ratios matter). 임시값 — Fit3D 모캡으로 확인.
    var priorLengths: [String: Double] = [
        "right_hip-right_knee": 1.0, "left_hip-left_knee": 1.0,
        "right_knee-right_ankle": 1.0, "left_knee-left_ankle": 1.0,
        "left_shoulder-left_elbow": 0.76, "right_shoulder-right_elbow": 0.76,
        "left_elbow-left_wrist": 0.60, "right_elbow-right_wrist": 0.60,
    ]
    /// Session median replaces the prior after this many frames.
    var sessionMinFrames = 30
    var sessionWindowFrames = 300
    /// Correction stays off until its false-positive cause is fixed (D-12, lift_app.md); detection marks bad.
    var knee = KneeHingeLimit.Config(enabled: false, limitDegrees: 10)
    var angleLimits: [AngleLimit] = Pose3DConstraints.defaultAngleLimits
    /// 임시값 — Fit3D 모캡·XS 분포로 확인.
    var badAngleDegrees = 20.0
    var badBoneFraction = 0.30

    /// Interior-angle limits (H36M17). 임시값: literature ROM norms, to be replaced by Fit3D mocap p0.1–p99.9.
    static let defaultAngleLimits: [AngleLimit] = [
        // Knee / elbow flexion ≤ 155° → interior angle ≥ 25°.
        AngleLimit(name: "right_knee_flexion", refFrom: 2, refTo: 1, joint: 2, child: 3, minDegrees: 25, maxDegrees: 180),
        AngleLimit(name: "left_knee_flexion", refFrom: 5, refTo: 4, joint: 5, child: 6, minDegrees: 25, maxDegrees: 180),
        AngleLimit(name: "right_elbow_flexion", refFrom: 15, refTo: 14, joint: 15, child: 16, minDegrees: 25, maxDegrees: 180),
        AngleLimit(name: "left_elbow_flexion", refFrom: 12, refTo: 11, joint: 12, child: 13, minDegrees: 25, maxDegrees: 180),
        // Hip: trunk (pelvis → thorax) vs thigh; 180 = standing, small = deep flexion.
        AngleLimit(name: "right_hip", refFrom: 0, refTo: 8, joint: 1, child: 2, minDegrees: 20, maxDegrees: 180),
        AngleLimit(name: "left_hip", refFrom: 0, refTo: 8, joint: 4, child: 5, minDegrees: 20, maxDegrees: 180),
        // Spine: pelvis–spine–thorax interior angle.
        AngleLimit(name: "spine", refFrom: 7, refTo: 0, joint: 7, child: 8, minDegrees: 120, maxDegrees: 180),
    ]

    static let children: [[Int]] = {
        var c = Array(repeating: [Int](), count: 17)
        for (j, p) in BoneLengthConstraint.parents.enumerated() where p >= 0 { c[p].append(j) }
        return c
    }()

    private var history: [String: [Double]] = [:]

    mutating func apply(_ input: [SIMD3<Double>]) -> ([SIMD3<Double>], Report) {
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
            joints = bones.joints
            report.boneMaxCorrection = bones.segments.values.filter(\.constrained)
                .map { abs($0.output - $0.observed) / max($0.observed, BoneLengthConstraint.minBoneLength) }.max() ?? 0
        }

        let hinge = KneeHingeLimit.apply(joints, config: knee)
        joints = hinge.joints
        report.kneeHyperextended = hinge.bad3D
        report.kneeCorrectionDegrees = max(hinge.right.correctionDegrees, hinge.left.correctionDegrees)

        for limit in angleLimits {
            if let moved = Self.clamp(&joints, limit), moved > 0 { report.angleCorrections[limit.name] = moved }
        }
        report.bad = report.maxAngleCorrection > badAngleDegrees || report.boneMaxCorrection > badBoneFraction
            || (report.kneeHyperextended && !knee.enabled)
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
