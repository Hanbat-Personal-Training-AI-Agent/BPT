import Foundation

/// Keypoint-only reliability PROXY. Does not detect visibility, occlusion, camera motion or true person identity.
/// All coordinates are analysis-image pixels; body scale excludes arms/wrists. No ideal-push-up pose gate.
struct PushUpSupportEvidence2D {
    typealias Corridor = PushUpSupportCorridor2D
    enum CameraEvidence: String { case unknown, controlledReplayAssertion }
    struct Frame {
        var keypoints: [PoseKeypoint]
        var sourcePTS: Double
        var width: Double
        var height: Double
        var rotation: Int
        /// Must change on session, tracker/person selection and crop coordinate/region changes.
        var epoch: String
        var supportActive: Bool
        var cameraEvidence: CameraEvidence
        var sameHandRejected: Bool = false
    }
    struct Output {
        let corridor: Corridor.Result
        let evidence: [Corridor.Observation]
        let bodyScale: Double
        let reset: Bool
        /// Conservative arm-coaching veto includes the elbow and wrist; coordinates remain untouched in raw.
        var invalid3DJoints: Set<Int> {
            var out: Set<Int> = []
            if !corridor.left.armAndHandCoachingEligible { out.formUnion([12,13]) }
            if !corridor.right.armAndHandCoachingEligible { out.formUnion([15,16]) }
            return out
        }
        func assessmentState(_ raw: Pose3DState?) -> Pose3DState? {
            raw == .ok && !invalid3DJoints.isEmpty ? .partial3D : raw
        }
        func assessmentConfidence(_ raw: [Double]?) -> [Double]? {
            guard var out = raw, out.count == 17 else { return raw }
            for i in invalid3DJoints { out[i] = 0 }
            return out
        }
        var uncertainJoints: Set<Int> {
            Set([(9, corridor.left), (10, corridor.right)].compactMap { $0.1.inferred ? $0.0 : nil })
        }
        /// Override AFTER smoothing: genuine observed motion is immediate; hidden/inferred points cannot be revived.
        func display(over smoothed: [PoseKeypoint]) -> [PoseKeypoint] {
            guard smoothed.count == 17 else { return smoothed }
            var out = smoothed
            for (index, result) in [(9, corridor.left), (10, corridor.right)] {
                if let p = result.displayPoint {
                    out[index] = PoseKeypoint(x: p.x, y: p.y, confidence: result.inferred ? 0.31 : result.raw.confidence)
                } else { out[index] = PoseKeypoint(x: 0, y: 0, confidence: 0) }
            }
            return out
        }
        /// Separate assessment copy only; original raw/XS inputs and raw3D never mutated.
        func assessment2D(_ raw: [PoseKeypoint]) -> [PoseKeypoint] {
            guard raw.count == 17 else { return raw }
            var out = raw
            for (index, result) in [(9, corridor.left), (10, corridor.right)] {
                let disagreement = result.raw.point.map { p in
                    p.distance(to: Corridor.Point(x: raw[index].x, y: raw[index].y)) > 0.03 * bodyScale
                } ?? true
                if !result.armAndHandCoachingEligible || disagreement { out[index].confidence = 0 }
            }
            return out
        }
        func assessment3D(_ raw: [SIMD3<Double>]?) -> [SIMD3<Double>]? {
            guard var out = raw, out.count == 17 else { return raw }
            for index in invalid3DJoints { out[index] = SIMD3(repeating: .nan) }
            return out
        }
    }
    private var corridor: Corridor
    private var previous: Frame?
    init(enabled: Bool = false) { var config = Corridor.Config(); config.enabled = enabled; corridor = Corridor(config: config) }
    mutating func reset() { previous = nil; corridor.reset() }
    mutating func update(_ frame: Frame) -> Output {
        let scale = Self.scale(frame.keypoints)
        let prev = previous
        let discontinuity = prev.map {
            $0.epoch != frame.epoch || $0.width != frame.width || $0.height != frame.height
                || $0.rotation != frame.rotation || $0.cameraEvidence != frame.cameraEvidence
                || frame.sourcePTS <= $0.sourcePTS || frame.sourcePTS - $0.sourcePTS > 0.15
                || Self.personDiscontinuity($0.keypoints, frame.keypoints, scale: scale)
        } ?? true
        if discontinuity { corridor.reset() }
        let correspond = discontinuity ? nil : prev
        let evidence = [Self.evidence(frame, previous: correspond, wrist: 9, elbow: 7, shoulder: 5, scale: scale),
                        Self.evidence(frame, previous: correspond, wrist: 10, elbow: 8, shoulder: 6, scale: scale)]
        let context = Corridor.Context(session: frame.epoch, camera: "\(frame.width)x\(frame.height)/\(frame.rotation)",
                                       tracker: frame.epoch, person: frame.epoch,
                                       fixedCamera: frame.cameraEvidence == .controlledReplayAssertion)
        let result = corridor.update(.init(sourcePTS: frame.sourcePTS, context: context, isPushUp: true,
                                           supportActive: frame.supportActive, bodyScale: scale,
                                           left: evidence[0], right: evidence[1]))
        previous = frame.sourcePTS.isFinite && scale.isFinite ? frame : nil
        return Output(corridor: result, evidence: evidence, bodyScale: scale, reset: discontinuity)
    }
    private static func point(_ k: PoseKeypoint) -> Corridor.Point { .init(x: k.x, y: k.y) }
    private static func usable(_ k: PoseKeypoint) -> Bool {
        k.x.isFinite && k.y.isFinite && k.confidence.isFinite && k.confidence >= 0.3
    }
    static func scale(_ k: [PoseKeypoint]) -> Double {
        guard k.count == 17 else { return .nan }
        let lengths = [(5, 11), (6, 12)].compactMap { a, b -> Double? in
            guard usable(k[a]), usable(k[b]) else { return nil }
            let distance = point(k[a]).distance(to: point(k[b]))
            return distance.isFinite && distance > 1 ? distance : nil
        }
        return lengths.isEmpty ? .nan : lengths.reduce(0, +) / Double(lengths.count)
    }
    private static func personDiscontinuity(_ a: [PoseKeypoint], _ b: [PoseKeypoint], scale: Double) -> Bool {
        let oldScale = Self.scale(a)
        guard oldScale.isFinite, scale.isFinite, a.count == 17, b.count == 17 else { return true }
        if max(oldScale, scale) / min(oldScale, scale) > 1.5 { return true }
        return [5, 6, 11, 12].filter { usable(a[$0]) && usable(b[$0]) }
            .contains { point(a[$0]).distance(to: point(b[$0])) > 0.5 * min(oldScale, scale) }
    }
    private static func evidence(_ f: Frame, previous: Frame?, wrist: Int, elbow: Int, shoulder: Int,
                                 scale: Double) -> Corridor.Observation {
        guard f.keypoints.count == 17 else {
            return .init(point: nil, confidence: 0, reliablyObserved: false,
                         neighborEvidenceConsistent: false, temporalEvidenceConsistent: false)
        }
        let k = f.keypoints, p = point(k[wrist])
        let onImage = p.finite && f.width.isFinite && f.height.isFinite
            && p.x >= 0 && p.x <= f.width && p.y >= 0 && p.y <= f.height
        let forearm = p.distance(to: point(k[elbow]))
        // Deliberately broad measurement plausibility, not an ideal angle/forearm target.
        let neighbor = scale.isFinite && usable(k[elbow]) && usable(k[shoulder])
            && forearm > 0.015 * scale && forearm < 2 * scale
        var temporal = false
        if let previous, previous.keypoints.count == 17 {
            let dt = f.sourcePTS - previous.sourcePTS, old = previous.keypoints[wrist]
            // Consecutive raw correspondence; an isolated high-score jump fails, a coherent new trajectory can pass.
            temporal = dt > 0 && dt <= 0.15 && usable(old)
                && p.distance(to: point(old)) <= scale * (0.03 + 6 * dt)
        }
        return .init(point: p, confidence: k[wrist].confidence,
                     reliablyObserved: onImage && !f.sameHandRejected,
                     neighborEvidenceConsistent: neighbor, temporalEvidenceConsistent: temporal)
    }
}

/// Atomic experiment eligibility/reset snapshot crossing MainActor and the serial capture queue.
/// Eligibility is readiness history only, never current contact or visibility evidence.
final class PushUpSupportExperimentControl: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var eligible = false
    func markReady() { lock.lock(); defer { lock.unlock() }; eligible = true }
    func reset() { lock.lock(); defer { lock.unlock() }; generation += 1; eligible = false }
    func snapshot() -> (generation: Int, eligible: Bool) {
        lock.lock(); defer { lock.unlock() }; return (generation, eligible)
    }
}
