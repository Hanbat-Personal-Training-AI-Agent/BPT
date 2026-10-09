import Foundation
import simd

/// Knee hyperextension clamp for MotionAGFormer H36M17 3D output (`selected3D`, [17,3]).
/// Mirrors pose_feedback/geometry/hinge_limit.py; both are pinned by
/// tests/fixtures/knee_hinge_limit_cases.json.
///
/// Per leg: u = knee - hip, v = ankle - knee, a = (L hip - R hip) projected onto the plane
/// perpendicular to u, normalized; theta = atan2((u x v) . a, u . v). theta > 0 is normal
/// flexion, theta < 0 hyperextension (sign checked on real MotionAGFormer-XS output).
/// theta < -limit rotates the shin about a around the knee onto -limit (ankle only, length kept).
/// Not wired into the app yet; call right after selected3D (after any bone-length fix).
enum KneeHingeLimit {
    struct Config {
        /// Off by default. The 92% squat_03 firing came from the old `screen` input normalisation; with
        /// `person_crop` it is 0% (docs/research/rtmpose_motionagformer_image_to_pose_pipeline.md §13.1).
        var enabled = false
        var limitDegrees = 10.0
    }

    struct LegReport: Equatable {
        /// Before correction; nil when degenerate.
        var thetaDegrees: Double?
        var corrected = false
        /// Rotation applied towards flexion, >= 0.
        var correctionDegrees = 0.0
        var degenerate: Bool { thetaDegrees == nil }
    }

    struct Result {
        var joints: [SIMD3<Double>]
        var right: LegReport
        var left: LegReport
    }

    static let minBoneLength = 1e-6
    static let minSinParallel = 0.05
    private static let rHip = 1, lHip = 4

    static func apply(_ joints: [SIMD3<Double>], config: Config = Config()) -> Result {
        precondition(joints.count == 17, "H36M17 expects 17 joints")
        var out = joints
        var reports: [LegReport] = []
        for (hip, knee, ankle) in [(1, 2, 3), (4, 5, 6)] {
            guard let (theta, axis) = kneeTheta(joints, hip: hip, knee: knee, ankle: ankle) else {
                reports.append(LegReport(thetaDegrees: nil))
                continue
            }
            var report = LegReport(thetaDegrees: theta)
            if config.enabled, theta < -config.limitDegrees {
                let correction = -config.limitDegrees - theta
                let phi = correction * .pi / 180
                let v = joints[ankle] - joints[knee]
                let vRot = v * cos(phi) + simd_cross(axis, v) * sin(phi) + axis * simd_dot(axis, v) * (1 - cos(phi))
                out[ankle] = joints[knee] + vRot
                report.corrected = true
                report.correctionDegrees = correction
            }
            reports.append(report)
        }
        return Result(joints: out, right: reports[0], left: reports[1])
    }

    /// Signed knee flexion in degrees and the hinge axis, or nil if degenerate.
    static func kneeTheta(_ j: [SIMD3<Double>], hip: Int, knee: Int, ankle: Int) -> (Double, SIMD3<Double>)? {
        let u = j[knee] - j[hip]
        let v = j[ankle] - j[knee]
        let lr = j[lHip] - j[rHip]
        let nu = simd_length(u), nv = simd_length(v), nl = simd_length(lr)
        guard nu >= minBoneLength, nv >= minBoneLength, nl >= minBoneLength else { return nil }
        let uHat = u / nu
        var a = lr - uHat * simd_dot(lr, uHat)
        let na = simd_length(a)
        guard na >= minSinParallel * nl else { return nil }  // pelvis axis ~ parallel to thigh
        a /= na
        // Shin along the hinge axis has no defined flexion angle.
        guard simd_length(v - a * simd_dot(v, a)) >= minSinParallel * nv else { return nil }
        let theta = atan2(simd_dot(simd_cross(u, v), a), simd_dot(u, v)) * 180 / .pi
        return (theta, a)
    }
}
