import Foundation

/// Experimental image-space display guard, OFF unless explicitly enabled. Never accepts or emits 3D.
/// A corridor is a short uncertainty allowance, not an observation or proof of ground contact.
/// Caller must provide analysis-image coordinates, source PTS, independently measured body scale,
/// trustworthy wrist evidence and camera stability. No inferred output may feed XS or coaching.
struct PushUpSupportCorridor2D {
    struct Point: Equatable {
        var x: Double
        var y: Double
        var finite: Bool { x.isFinite && y.isFinite }
        func distance(to p: Point) -> Double { hypot(x - p.x, y - p.y) }
    }
    struct Observation {
        var point: Point?
        var confidence: Double
        /// Independent evidence that this is an observed wrist of the tracked person (not a prediction).
        /// Confidence alone does not establish visibility or resolve swapped/duplicated hands.
        var reliablyObserved: Bool
        /// External checks against neighboring joints/side identity and broad anatomy plausibility.
        /// This is a reliability veto, never a target pose or an exact forearm-length constraint.
        var neighborEvidenceConsistent: Bool
        /// External temporal correspondence evidence, allowing coherent real movement.
        var temporalEvidenceConsistent: Bool
    }
    struct Context: Equatable {
        var session: String
        var camera: String
        var tracker: String
        var person: String
        /// False/unknown camera stability cannot support a stationary image-space anchor.
        var fixedCamera: Bool
    }
    struct Input {
        var sourcePTS: Double
        var context: Context
        var isPushUp: Bool
        var supportActive: Bool
        /// Positive finite analysis-image body length, independent of wrist/forearm correction.
        var bodyScale: Double
        var left: Observation
        var right: Observation
    }
    struct Config {
        var enabled = false
        var reliableConfidence = 0.7
        var acquisitionSeconds = 0.12
        var minimumSamples = 3
        var maximumSampleGap = 0.15
        var stableRadius = 0.025
        var corridorRadius = 0.06
        var maximumOcclusionSeconds = 0.35
        var valid: Bool {
            [reliableConfidence, acquisitionSeconds, maximumSampleGap, stableRadius,
             corridorRadius, maximumOcclusionSeconds].allSatisfy(\.isFinite)
                && reliableConfidence >= 0 && acquisitionSeconds > 0
                && minimumSamples >= 2 && maximumSampleGap > 0 && stableRadius > 0
                && corridorRadius >= stableRadius && maximumOcclusionSeconds > 0
        }
    }
    enum Reason: String {
        case disabled, inactive, cameraUnstable, invalidInput
        case observedAcquiring, observedSupport, observedReleased
        case inferredCorridor, unobservedWithoutAnchor, occlusionExpired
    }
    struct WristResult {
        let raw: Observation
        /// Nil means hide this wrist and adjacent skeleton segments. Inferred points need distinct styling.
        let displayPoint: Point?
        let reason: Reason
        let inferred: Bool
        let assessmentEligible: Bool
        /// Includes elbow-angle/hand-position advice that depends on this wrist.
        var armAndHandCoachingEligible: Bool { assessmentEligible && !inferred }
        let anchor: Point?
        let occlusionAge: Double?
        /// Nil when no finite raw point exists; never report a fictitious zero correction.
        let correctionMagnitude: Double?
    }
    struct Result {
        let sourcePTS: Double
        let left: WristResult
        let right: WristResult
        /// Consumers without per-joint visibility must withhold the skeleton on true.
        var withholdSkeleton: Bool { left.displayPoint == nil || right.displayPoint == nil }
    }
    private struct Sample { let point: Point; let pts: Double }
    private struct Memory {
        var anchor: Point?
        var anchorScale: Double?
        var lastObserved: Double?
        var samples: [Sample] = []
    }
    var config: Config
    private var context: Context?
    private var lastPTS: Double?
    private var left = Memory()
    private var right = Memory()

    init(config: Config = Config()) { self.config = config }
    mutating func reset() {
        context = nil; lastPTS = nil; left = Memory(); right = Memory()
    }
    mutating func update(_ input: Input) -> Result {
        func bypass(_ reason: Reason, observedOnly: Bool) -> Result {
            func wrist(_ o: Observation) -> WristResult {
                let reliable = Self.reliable(o, config: config)
                let p = o.point.flatMap { $0.finite && (!observedOnly || reliable) ? $0 : nil }
                return WristResult(raw: o, displayPoint: p, reason: reason, inferred: false,
                                   assessmentEligible: reliable && p != nil && reason != .invalidInput, anchor: nil,
                                   occlusionAge: nil, correctionMagnitude: p == nil ? nil : 0)
            }
            return Result(sourcePTS: input.sourcePTS, left: wrist(input.left), right: wrist(input.right))
        }
        guard config.enabled else { reset(); return bypass(.disabled, observedOnly: false) }
        guard config.valid, input.sourcePTS.isFinite, input.bodyScale.isFinite, input.bodyScale > 0,
              (input.bodyScale * config.corridorRadius).isFinite else {
            reset(); return bypass(.invalidInput, observedOnly: true)
        }
        guard input.isPushUp && input.supportActive else { reset(); return bypass(.inactive, observedOnly: true) }
        guard input.context.fixedCamera else { reset(); return bypass(.cameraUnstable, observedOnly: true) }
        let discontinuity = context != nil && (context != input.context || lastPTS.map {
            input.sourcePTS <= $0 || input.sourcePTS - $0 > config.maximumSampleGap
        } == true)
        if discontinuity { reset() }
        context = input.context; lastPTS = input.sourcePTS
        let l = Self.updateWrist(input.left, pts: input.sourcePTS, scale: input.bodyScale,
                                 config: config, memory: &left)
        let r = Self.updateWrist(input.right, pts: input.sourcePTS, scale: input.bodyScale,
                                 config: config, memory: &right)
        return Result(sourcePTS: input.sourcePTS, left: l, right: r)
    }
    private static func reliable(_ o: Observation, config: Config) -> Bool {
        config.reliableConfidence.isFinite && config.reliableConfidence >= 0
            && o.reliablyObserved && o.neighborEvidenceConsistent && o.temporalEvidenceConsistent
            && o.confidence.isFinite && o.confidence >= config.reliableConfidence
            && o.point?.finite == true
    }
    private static func updateWrist(_ raw: Observation, pts: Double, scale: Double,
                                    config: Config, memory m: inout Memory) -> WristResult {
        func result(_ point: Point?, _ reason: Reason, _ inferred: Bool, _ eligible: Bool) -> WristResult {
            WristResult(raw: raw, displayPoint: point, reason: reason, inferred: inferred,
                        assessmentEligible: eligible, anchor: m.anchor,
                        occlusionAge: m.lastObserved.map { pts - $0 },
                        correctionMagnitude: point.flatMap { p in raw.point.flatMap {
                            let distance = p.distance(to: $0)
                            return $0.finite && distance.isFinite ? distance : nil
                        } })
        }
        if reliable(raw, config: config), let p = raw.point {
            var released = false
            if let anchor = m.anchor, let anchorScale = m.anchorScale,
               p.distance(to: anchor) > config.corridorRadius * min(scale, anchorScale) {
                // Credible real movement passes immediately. No positional anatomy rule can veto it.
                m = Memory(); released = true
            }
            m.lastObserved = pts
            if m.anchor == nil {
                if let first = m.samples.first, p.distance(to: first.point) > config.stableRadius * scale {
                    m.samples = []
                }
                m.samples.append(Sample(point: p, pts: pts))
                // Bound history independent of source frame rate; require duration AND sample count.
                m.samples = Array(m.samples.suffix(256))
                if m.samples.count >= config.minimumSamples, let first = m.samples.first,
                   pts - first.pts >= config.acquisitionSeconds {
                    m.anchor = p; m.anchorScale = scale; m.samples = []
                }
            }
            return result(p, released ? .observedReleased : (m.anchor == nil ? .observedAcquiring : .observedSupport), false, true)
        }
        // Untrusted samples never acquire, relocate, or extend the anchor's lifetime.
        m.samples = []
        guard let anchor = m.anchor, let anchorScale = m.anchorScale, let last = m.lastObserved else {
            return result(nil, .unobservedWithoutAnchor, false, false)
        }
        guard pts - last <= config.maximumOcclusionSeconds else {
            let age = pts - last
            m = Memory()
            return WristResult(raw: raw, displayPoint: nil, reason: .occlusionExpired, inferred: false,
                               assessmentEligible: false, anchor: nil, occlusionAge: age, correctionMagnitude: nil)
        }
        // Soft radial allowance in camera/image coordinates; never an exact forearm constraint.
        let radius = config.corridorRadius * min(scale, anchorScale)
        var display = anchor
        if let p = raw.point, p.finite {
            let distance = p.distance(to: anchor)
            if distance <= radius { display = p }
            else if distance.isFinite {
                display = Point(x: anchor.x + (p.x - anchor.x) * radius / distance,
                                y: anchor.y + (p.y - anchor.y) * radius / distance)
            }
        }
        return result(display, .inferredCorridor, true, false)
    }
}
