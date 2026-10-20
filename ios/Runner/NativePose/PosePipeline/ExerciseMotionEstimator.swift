import Foundation
import simd

/// Metadata from the same camera frame as the selected XS row. Camera evidence is deliberately
/// separate from a stationary joint: a moving camera cannot establish an image-space contact.
struct ExerciseMotionFrameContext {
    var timestamp: TimeInterval
    var fixedCameraEvidence = false
    var cameraMotion = false
    var gripConfirmed = false
    /// Supplied only by an identity-aware caller. A missing identity does not assert that the
    /// person is unchanged; tracking loss, set boundaries and orientation still clear the state.
    var personID: String?
    var phase: String?
}

/// A-H are explicit experiment selections. An absent/invalid environment value leaves the
/// existing XS -> Pose3DConstraints path intact.
enum ExerciseMotionVariant: String, CaseIterable {
    case A, B, C, D, E, F, G, H, HOLD

    static func environment(_ value: String?) -> Self? {
        value.flatMap { Self(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) }
    }

    var usesSoftBones: Bool { self == .E || self == .G || self == .H }
}

struct ExerciseMotionResult {
    var raw: [SIMD3<Double>]
    var corrected: [SIMD3<Double>]
    var correctionMagnitude: [Double]
    var uncertainty: [Double]
    var invalidForAssessment: Set<Int>
    var roles: [String]
    var contacts: [Int: String]
    var usedPrediction: [Bool]
    var phase: String?
    var diagnostics: [String: Any]

    /// The estimator uses image-height units to avoid a jump when the XS person crop changes.
    /// Only at the pipeline boundary are its values returned to the existing XS crop units.
    func rescaled(_ factor: Double) -> Self {
        var result = self
        result.raw = raw.map { $0 * factor }
        result.corrected = corrected.map { $0 * factor }
        result.correctionMagnitude = correctionMagnitude.map { $0 * factor }
        result.uncertainty = uncertainty.map { $0 * factor }
        result.diagnostics["estimator_to_model_scale"] = factor
        return result
    }

    /// JSON-safe values: a missing observation stays null rather than becoming a made-up joint.
    var dictionary: [String: Any] {
        func finite(_ x: Double) -> Any { x.isFinite ? x : NSNull() }
        func pose(_ p: [SIMD3<Double>]) -> [[Any]] { p.map { [finite($0.x), finite($0.y), finite($0.z)] } }
        return [
            "raw": pose(raw), "corrected": pose(corrected),
            "correction_magnitude": correctionMagnitude.map(finite),
            "uncertainty": uncertainty.map(finite),
            "invalid": (0..<17).map { invalidForAssessment.contains($0) },
            "roles": roles, "contacts": Dictionary(uniqueKeysWithValues: contacts.map { (String($0.key), $0.value) }),
            "used_prediction": usedPrediction, "phase": phase as Any? ?? NSNull(),
            "diagnostics": diagnostics,
        ]
    }
}

/// Explicitly sourced *estimated* body proportions. The legacy bone-target JSON intentionally
/// does not satisfy this contract: it may contain exact mocap lengths for an older experiment.
struct ExerciseMotionCalibrationProfile {
    let boneRatios: [String: Double]
    let confidence: Double
    let provenance: [String: Any]

    enum InvalidProfile: Error {
        case missingProvenance, unsupportedSource, invalidConfidence, noUsableRatios
    }

    static func load(_ data: Data) throws -> Self {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let source = obj["source_type"] as? String,
              let sourceID = obj["source_id"] as? String, !sourceID.isEmpty else {
            throw InvalidProfile.missingProvenance
        }
        guard ["rgb_smpl_calibration", "rgb_smpl_crossfit"].contains(source),
              obj["ground_truth_used"] as? Bool != true,
              obj["uses_evaluation_sequence"] as? Bool != true else {
            throw InvalidProfile.unsupportedSource
        }
        guard let reliability = obj["calibration_confidence"] as? NSNumber,
              CFGetTypeID(reliability) != CFBooleanGetTypeID(),
              reliability.doubleValue.isFinite, (0...1).contains(reliability.doubleValue) else {
            throw InvalidProfile.invalidConfidence
        }
        let values = obj["bone_ratios"] as? [String: Any] ?? [:]
        let edges = Set((1..<17).map { "\(BoneLengthConstraint.parents[$0])-\($0)" })
        var ratios: [String: Double] = [:]
        for (edge, value) in values where edges.contains(edge) {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue.isFinite, n.doubleValue > 0 else { continue }
            ratios[edge] = n.doubleValue
        }
        guard !ratios.isEmpty else { throw InvalidProfile.noUsableRatios }
        return Self(boneRatios: ratios, confidence: reliability.doubleValue,
                    provenance: obj.filter { $0.key != "bone_ratios" })
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self? {
        guard let path = environment["BPT_MOTION_PROFILE"], !path.isEmpty else { return nil }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : documents.appendingPathComponent(path)
        do { return try load(Data(contentsOf: url)) }
        catch {
            print("[MotionEstimator] profile unavailable: \(error)")
            return nil
        }
    }
}

/// Optional preparation evidence from the first 60 emitted usable XS observations. These are
/// uncertain observed proportions, not GT or a certificate that the starting posture was good.
struct ExerciseMotionOnlineCalibration {
    private(set) var samples = 0
    private var lengths: [String: [Double]] = [:]

    mutating func observe(_ raw: [SIMD3<Double>], screen: [SIMD3<Double>]) {
        guard samples < 60 else { return }
        samples += 1
        for (a, b) in ExerciseMotionEstimator.edges {
            guard screen[a].z >= 0.45, screen[b].z >= 0.45,
                  [raw[a].x, raw[a].y, raw[a].z, raw[b].x, raw[b].y, raw[b].z].allSatisfy(\.isFinite) else { continue }
            let length = simd_length(raw[a] - raw[b])
            if length > 1e-6 { lengths["\(a)-\(b)", default: []].append(length) }
        }
    }

    var boneRatios: [String: Double] {
        guard samples == 60 else { return [:] }
        func median(_ values: [Double]) -> Double {
            let v = values.sorted(), n = values.count
            return n % 2 == 1 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2])
        }
        let medians = lengths.filter { $0.value.count >= 30 }.mapValues(median)
        var legs: [Double] = []
        for (thigh, shank) in [("1-2", "2-3"), ("4-5", "5-6")] {
            if let a = medians[thigh], let b = medians[shank] { legs.append(a + b) }
        }
        guard !legs.isEmpty else { return [:] }
        let scale = legs.reduce(0, +) / Double(legs.count)
        return medians.mapValues { $0 / scale }
    }
}

/// Numeric parity with pose_feedback/geometry/exercise_motion.py. This operates on root-relative
/// image-height units; neither its trajectory state nor a contact is an absolute world position.
struct ExerciseMotionEstimator {
    let exercise: String
    let variant: ExerciseMotionVariant
    var boneProfile: [String: Double]
    var calibrationConfidence: Double

    static let edges = [(0, 1), (1, 2), (2, 3), (0, 4), (4, 5), (5, 6), (0, 7), (7, 8),
                        (8, 9), (9, 10), (8, 11), (11, 12), (12, 13), (8, 14), (14, 15), (15, 16)]
    static let parent = Dictionary(uniqueKeysWithValues: edges.map { ($0.1, $0.0) })
    static let distal = [2, 3, 5, 6, 12, 13, 15, 16]
    private static let nan3 = SIMD3<Double>(repeating: .nan)
    private static let nan2 = SIMD2<Double>(repeating: .nan)
    private var p = Array(repeating: SIMD3<Double>.zero, count: 17)
    private var v = Array(repeating: SIMD3<Double>.zero, count: 17)
    private var p00 = Array(repeating: 0.0, count: 17)
    private var p01 = Array(repeating: 0.0, count: 17)
    private var p11 = Array(repeating: 0.0, count: 17)
    private var initialized = Array(repeating: false, count: 17)
    private var lastSeen = Array(repeating: -Double.infinity, count: 17)
    private var lastObserved = Array(repeating: nan3, count: 17)
    private var previousScreen = Array(repeating: nan2, count: 17)
    private var candidateRaw = Array(repeating: nan3, count: 17)
    private var candidateCount = Array(repeating: 0, count: 17)
    private var time: Double?
    private var personID: String?
    private var scale = 0.3
    private var contacts: [Int: Contact] = [:]
    private var gripHistory: [Double] = []
    private var gripReference: Double?
    private var gripSeen: Double?
    private var previousPhaseDistance: Double?
    private var phaseSpeed = 0.0
    private var phase = "unknown"
    private var phaseElbowPosition: [Int: SIMD3<Double>] = [:]
    private var phaseElbowVelocity: [Int: SIMD3<Double>] = [:]
    private var resetReason = "initialization"

    init(exercise: String, variant: ExerciseMotionVariant = .G,
         boneProfile: [String: Double]? = nil, calibrationConfidence: Double = 0) {
        let name = exercise.replacingOccurrences(of: "-", with: "_")
        precondition(["pushup", "squat", "barbell_row"].contains(name))
        self.exercise = name
        self.variant = variant
        self.boneProfile = boneProfile ?? [:]
        self.calibrationConfidence = Self.clamp(calibrationConfidence, 0, 1)
        reset(reason: "initialization")
    }

    mutating func reset(reason: String = "explicit") {
        if reason == "person_change" {
            boneProfile = [:]
            calibrationConfidence = 0
        }
        p = Array(repeating: .zero, count: 17)
        v = Array(repeating: .zero, count: 17)
        p00 = Array(repeating: 0, count: 17)
        p01 = Array(repeating: 0, count: 17)
        p11 = Array(repeating: 0, count: 17)
        initialized = Array(repeating: false, count: 17)
        lastSeen = Array(repeating: -.infinity, count: 17)
        lastObserved = Array(repeating: Self.nan3, count: 17)
        previousScreen = Array(repeating: Self.nan2, count: 17)
        candidateRaw = Array(repeating: Self.nan3, count: 17)
        candidateCount = Array(repeating: 0, count: 17)
        time = nil
        personID = nil
        scale = 0.3
        contacts = Dictionary(uniqueKeysWithValues: (exercise == "pushup" ? [3, 6, 13, 16] : [3, 6])
            .map { ($0, Contact()) })
        gripHistory = []
        gripReference = nil
        gripSeen = nil
        previousPhaseDistance = nil
        phaseSpeed = 0
        phase = "unknown"
        phaseElbowPosition = [:]
        phaseElbowVelocity = [:]
        resetReason = reason
    }

    mutating func setBoneProfile(_ ratios: [String: Double], confidence: Double) {
        let edges = Set(Self.edges.map { "\($0.0)-\($0.1)" })
        precondition(ratios.allSatisfy { edges.contains($0.key) && $0.value.isFinite && $0.value > 0 })
        boneProfile = ratios
        calibrationConfidence = Self.clamp(confidence, 0, 1)
    }

    private struct Contact {
        var state = "UNINITIALIZED"
        var anchor: SIMD2<Double>?
        var history: [SIMD2<Double>] = []
        var candidate: [SIMD2<Double>] = []
        var lastSeen: Double?

        mutating func update(_ point: SIMD2<Double>, reliable: Bool, now: Double, scale: Double, enabled: Bool) {
            guard enabled else { self = Contact(); return }
            let radius = 0.035 * scale, release = 0.10 * scale
            guard reliable, ExerciseMotionEstimator.finite(point) else {
                if anchor != nil {
                    state = "OCCLUDED"
                    if lastSeen == nil || now - lastSeen! > 0.5 {
                        anchor = nil
                        state = "UNINITIALIZED"
                        history = []
                        candidate = []
                    }
                }
                return
            }
            lastSeen = now
            if anchor == nil && !["MOVING", "REACQUIRE"].contains(state) {
                ExerciseMotionEstimator.append(point, to: &history, limit: 8)
                if history.count == 8 {
                    let mid = ExerciseMotionEstimator.median2(history)
                    if history.map({ simd_length($0 - mid) }).max()! <= radius {
                        anchor = mid
                        state = "CONTACT"
                    }
                }
                return
            }
            if ["MOVING", "REACQUIRE"].contains(state) {
                state = "REACQUIRE"
                ExerciseMotionEstimator.append(point, to: &candidate, limit: 5)
                if candidate.count == 5 {
                    let mid = ExerciseMotionEstimator.median2(candidate)
                    if candidate.map({ simd_length($0 - mid) }).max()! <= radius {
                        anchor = mid
                        state = "CONTACT"
                        candidate = []
                    }
                }
                return
            }
            guard let anchor else { return }
            if simd_length(point - anchor) <= release {
                state = "CONTACT"
                candidate = []
                return
            }
            ExerciseMotionEstimator.append(point, to: &candidate, limit: 5)
            if candidate.count >= 3 {
                let h = Array(candidate.suffix(3)), mid = ExerciseMotionEstimator.median2(Array(candidate.suffix(3)))
                let step0 = h[1] - h[0], step1 = h[2] - h[1]
                let stable = h.map { simd_length($0 - mid) }.max()! <= radius
                let coherent = simd_dot(step0, step1) >= 0 && max(simd_length(step0), simd_length(step1)) <= 0.25 * scale
                if stable || coherent {
                    self.anchor = nil
                    state = "MOVING"
                    history = []
                    candidate = []
                }
            }
        }
    }

    private mutating func updatePhase(_ raw: [SIMD3<Double>], confidence: [Double], dt: Double) -> Bool {
        guard exercise == "barbell_row" else {
            phase = "unknown"
            return false
        }
        var elbowTurning = false
        for j in [12, 15] {
            guard confidence[j] >= 0.45, Self.finite(raw[j]) else {
                phaseElbowPosition[j] = nil
                phaseElbowVelocity[j] = nil
                continue
            }
            if let previous = phaseElbowPosition[j] {
                let velocity = (raw[j] - previous) / dt
                let old = phaseElbowVelocity[j] ?? .zero
                let oldNorm = simd_length(old), norm = simd_length(velocity)
                if oldNorm > 0.1 * scale, norm > 0.05 * scale,
                   simd_length(raw[j] - previous) < 0.1 * scale, simd_dot(old, velocity) < -0.2 * oldNorm * norm {
                    elbowTurning = true
                }
                phaseElbowVelocity[j] = 0.5 * old + 0.5 * velocity
            }
            phaseElbowPosition[j] = raw[j]
        }
        guard [11, 13, 14, 16].map({ confidence[$0] }).min()! >= 0.45,
              [11, 13, 14, 16].allSatisfy({ Self.finite(raw[$0]) }) else {
            previousPhaseDistance = nil
            phaseSpeed = 0
            phase = elbowTurning ? "transition" : "unknown"
            return elbowTurning
        }
        let distance = 0.5 * (simd_length(raw[13] - raw[11]) + simd_length(raw[16] - raw[14]))
        var turning = elbowTurning
        if let previousPhaseDistance {
            let speed = (distance - previousPhaseDistance) / dt
            turning = turning || (speed * phaseSpeed < 0 && abs(phaseSpeed) > 0.1 * scale)
            phaseSpeed = 0.5 * phaseSpeed + 0.5 * speed
            phase = turning || abs(phaseSpeed) < 0.05 * scale ? "transition" : phaseSpeed < 0 ? "pulling" : "lowering"
        }
        previousPhaseDistance = distance
        return turning
    }

    mutating func update(raw: [SIMD3<Double>], screen2D screen: [SIMD3<Double>], timestamp now: Double,
                         fixedCamera: Bool = false, cameraMotion: Bool = false, personID: String? = nil,
                         phase trustedPhase: String? = nil, gripConfirmed: Bool = false) -> ExerciseMotionResult {
        precondition(raw.count == 17 && screen.count == 17 && now.isFinite)
        let personChanged = self.personID != nil && self.personID != personID
        if personChanged {
            boneProfile = [:]
            calibrationConfidence = 0
        }
        if cameraMotion { reset(reason: "camera_motion") }
        else if personChanged { reset(reason: "person_change") }
        else if let time, now <= time || now - time > 0.5 { reset(reason: "timestamp_discontinuity") }
        let dt = time.map { max(1e-4, now - $0) } ?? (1.0 / 30)
        time = now
        self.personID = personID
        if let currentScale = Self.leg(raw) { scale = max(currentScale, 1e-4) }
        let s = scale
        let conf = screen.map { $0.z.isNaN ? 0 : Self.clamp($0.z, 0, 1) }
        let finite = (0..<17).map { Self.finite(raw[$0]) && Self.finite(Self.xy(screen[$0])) }
        let measured = (0..<17).map { finite[$0] && conf[$0] >= 0.3 }
        let reliable = (0..<17).map { finite[$0] && conf[$0] >= 0.45 }
        let adaptive = variant == .G || variant == .H
        let kalman = [.D, .E, .G, .H].contains(variant)
        let contactEnabled = [.F, .G, .H].contains(variant)
        let kinEnabled = variant.usesSoftBones && calibrationConfidence > 0
        var turning = variant == .H ? updatePhase(raw, confidence: conf, dt: dt) : false
        if variant == .H, let trustedPhase, ["pulling", "transition", "lowering"].contains(trustedPhase) {
            phase = trustedPhase
            turning = turning || trustedPhase == "transition"
        }
        if turning { for j in [12, 13, 15, 16] { v[j] *= 0.3 } }

        var pred = (0..<17).map { p[$0] + dt * v[$0] }
        var accepted = measured
        let innovation = (0..<17).map { simd_length(raw[$0] - pred[$0]) }
        var rejected = Array(repeating: false, count: 17)
        if adaptive {
            for j in 0..<17 {
                guard initialized[j], measured[j], innovation[j] > 0.25 * s else {
                    candidateCount[j] = 0
                    continue
                }
                let delta2 = Self.xy(screen[j]) - previousScreen[j]
                let delta3 = Self.xy(raw[j]) - Self.xy(lastObserved[j])
                let agreement = Self.finite(delta2) && Self.finite(delta3)
                    && simd_length(delta2) > 0.01 * s && simd_dot(delta2, delta3) > 0
                var plausible = true
                if let parent = Self.parent[j], Self.finite(lastObserved[j]), Self.finite(lastObserved[parent]) {
                    let oldLength = simd_length(lastObserved[j] - lastObserved[parent])
                    let newLength = simd_length(raw[j] - raw[parent])
                    plausible = 0.4 * oldLength <= newLength && newLength <= 1.8 * max(oldLength, 1e-6)
                }
                let persistent = Self.finite(candidateRaw[j]) && simd_length(raw[j] - candidateRaw[j]) < 0.12 * s
                candidateCount[j] = reliable[j] && plausible && (agreement || persistent) ? candidateCount[j] + 1 : 0
                candidateRaw[j] = raw[j]
                accepted[j] = candidateCount[j] >= 3
                rejected[j] = !accepted[j]
                if accepted[j] {
                    pred[j] = raw[j]
                    v[j] = .zero
                    p00[j] = pow(0.03 * s, 2)
                }
            }
        }
        var corrected = raw
        var usedPrediction = Array(repeating: false, count: 17)
        var uncertainty = conf.map { (0.015 + 0.10 * (1 - $0)) * s }
        for j in 0..<17 {
            if !initialized[j] {
                if measured[j] {
                    p[j] = raw[j]
                    pred[j] = raw[j]
                    lastObserved[j] = raw[j]
                    lastSeen[j] = now
                    p00[j] = pow(0.03 * s, 2)
                    p11[j] = pow(0.5 * s, 2)
                    initialized[j] = true
                } else {
                    uncertainty[j] = s
                    continue
                }
            }
            let elapsed = now - lastSeen[j]
            if kalman {
                let acc2 = pow(1.5 * s, 2)
                let pp = p00[j] + 2 * dt * p01[j] + dt * dt * p11[j] + acc2 * pow(dt, 4) / 4
                let pv = p01[j] + dt * p11[j] + acc2 * pow(dt, 3) / 2
                let vv = p11[j] + acc2 * dt * dt
                p[j] = pred[j]
                if accepted[j] {
                    let std = (adaptive ? (0.015 + 0.10 * (1 - conf[j])) : 0.03) * s
                    let den = pp + std * std
                    let kp = pp / den, kv = pv / den
                    let residual = raw[j] - pred[j]
                    p[j] += kp * residual
                    v[j] += kv * residual
                    p00[j] = max(0, (1 - kp) * pp)
                    p01[j] = (1 - kp) * pv
                    p11[j] = max(0, vv - kv * pv)
                } else {
                    p00[j] = pp
                    p01[j] = pv
                    p11[j] = vv
                    usedPrediction[j] = true
                }
                corrected[j] = p[j]
                uncertainty[j] = sqrt(max(p00[j], 0))
            } else if variant == .B {
                if finite[j] {
                    let alpha = 1 - exp(-dt / 0.08)
                    p[j] += alpha * (raw[j] - p[j])
                }
                corrected[j] = p[j]
                usedPrediction[j] = !finite[j]
            } else if variant == .C || variant == .HOLD {
                if measured[j] {
                    if Self.finite(lastObserved[j]), elapsed > 1e-4 {
                        let velocity = (raw[j] - lastObserved[j]) / elapsed
                        v[j] = velocity * min(1, 3 * s / max(simd_length(velocity), 1e-9))
                    }
                    p[j] = raw[j]
                } else {
                    if variant == .C {
                        let step = max(0, min(dt, 0.35 - max(0, elapsed - dt)))
                        p[j] += v[j] * step
                    }
                    usedPrediction[j] = true
                }
                corrected[j] = p[j]
                uncertainty[j] = (0.03 + 0.5 * elapsed) * s
            } else if measured[j] {
                p[j] = raw[j]
            }
            if accepted[j] {
                lastSeen[j] = now
                lastObserved[j] = raw[j]
            }
            if finite[j] { previousScreen[j] = Self.xy(screen[j]) }
        }

        let supportAvailable = fixedCamera && !cameraMotion
        let leg2D = Self.leg(screen.map { SIMD3($0.x, $0.y, 0) }) ?? 0.3
        var contactUsed: [Int] = []
        var ratios: [Double] = []
        for (a, b) in Self.edges {
            let d2 = simd_length(Self.xy(screen[a]) - Self.xy(screen[b]))
            if reliable[a], reliable[b], d2 > 0.02 * leg2D {
                ratios.append(simd_length(Self.xy(raw[a]) - Self.xy(raw[b])) / d2)
            }
        }
        let xyScale = ratios.count >= 4 ? Self.median(ratios) : nil
        for j in contacts.keys.sorted() {
            contacts[j]?.update(Self.xy(screen[j]), reliable: reliable[j] && !rejected[j], now: now,
                                scale: leg2D, enabled: contactEnabled && supportAvailable)
            if contactEnabled, supportAvailable, !accepted[j], let contact = contacts[j],
               let anchor = contact.anchor, contact.state == "OCCLUDED", reliable[0],
               let xyScale, let lastSeen = contact.lastSeen, now - lastSeen <= 0.35, initialized[j] {
                let target = (anchor - Self.xy(screen[0])) * xyScale
                let delta = target - Self.xy(corrected[j])
                if Self.finite(delta) {
                    let shift = delta * min(1, 0.10 * s / max(simd_length(delta), 1e-9))
                    corrected[j].x += shift.x
                    corrected[j].y += shift.y
                    uncertainty[j] = max(uncertainty[j], 0.10 * s)
                    usedPrediction[j] = true
                    contactUsed.append(j)
                }
            }
        }

        var kinematicUsed: [Int] = []
        if kinEnabled {
            for j in Self.distal {
                let a = Self.parent[j]!
                guard let ratio = boneProfile["\(a)-\(j)"], !reliable[j], reliable[a],
                      Self.finite(corrected[a]), Self.finite(corrected[j]) else { continue }
                let target = ratio * s
                guard target.isFinite, target > 0 else { continue }
                let vector = corrected[j] - corrected[a], length = simd_length(vector)
                let tolerance = 0.15 + 0.25 * (1 - calibrationConfidence)
                let desired = Self.clamp(length, target * (1 - tolerance), target * (1 + tolerance))
                if length > 1e-8, abs(length - desired) > 1e-8 {
                    let correction = vector * (desired / length - 1) * calibrationConfidence
                    corrected[j] += correction * min(1, 0.10 * s / max(simd_length(correction), 1e-9))
                    uncertainty[j] = max(uncertainty[j], 0.08 * s)
                    usedPrediction[j] = true
                    kinematicUsed.append(j)
                }
            }
        }

        if contactEnabled, exercise == "barbell_row", gripConfirmed {
            if reliable[13], reliable[16] {
                let distance = simd_length(raw[13] - raw[16])
                gripSeen = now
                if let gripReference, !(0.8 * gripReference...1.2 * gripReference).contains(distance) {
                    self.gripReference = nil
                    gripHistory = []
                }
                Self.append(distance, to: &gripHistory, limit: 8)
                if gripHistory.count == 8, gripHistory.max()! - gripHistory.min()! < 0.1 * s {
                    gripReference = Self.median(gripHistory)
                }
            } else if let gripReference, let gripSeen, now - gripSeen <= 0.5 {
                for (j, other) in [(13, 16), (16, 13)] {
                    if !reliable[j], reliable[other], Self.finite(corrected[j]), Self.finite(corrected[other]) {
                        let vector = corrected[j] - corrected[other], length = simd_length(vector)
                        let desired = Self.clamp(length, 0.8 * gripReference, 1.2 * gripReference)
                        if length > 1e-8 {
                            let delta = vector * (desired / length - 1)
                            corrected[j] += delta * min(0.5, 0.10 * s / max(simd_length(delta), 1e-9))
                            usedPrediction[j] = true
                        }
                    }
                }
            } else if let gripSeen, now - gripSeen > 0.5 {
                gripReference = nil
                gripHistory = []
            }
        } else {
            gripReference = nil
            gripSeen = nil
            gripHistory = []
        }
        let age = lastSeen.map { now - $0 }
        for j in 0..<17 {
            uncertainty[j] = max(uncertainty[j], usedPrediction[j] ? (0.03 + 0.3 * min(age[j], 2)) * s : 0)
        }
        let correction = (0..<17).map { simd_length(corrected[$0] - raw[$0]) }
        let invalid = Set((0..<17).filter {
            !Self.finite(corrected[$0]) || !initialized[$0] || age[$0] > 0.5
                || uncertainty[$0] > 0.15 * s || correction[$0] > 0.08 * s || usedPrediction[$0]
        })
        var roles = Array(repeating: "dynamic_joint", count: 17)
        for j in 0..<17 {
            if let contact = contacts[j], contactEnabled, supportAvailable {
                roles[j] = ["CONTACT", "OCCLUDED"].contains(contact.state) ? "contact_anchor" : "dynamic_joint"
            } else if [13, 16].contains(j), gripReference != nil { roles[j] = "relative_anchor" }
            if usedPrediction[j] { roles[j] = "temporarily_occluded_joint" }
            if !initialized[j] || age[j] > 0.5 || uncertainty[j] > 0.15 * s { roles[j] = "uncertain_joint" }
        }
        return ExerciseMotionResult(
            raw: raw, corrected: corrected, correctionMagnitude: correction, uncertainty: uncertainty,
            invalidForAssessment: invalid, roles: roles, contacts: contacts.mapValues(\.state),
            usedPrediction: usedPrediction, phase: phase,
            diagnostics: ["scale": s, "fixed_camera": supportAvailable, "contact_corrected": contactUsed,
                          "bone_corrected": kinematicUsed, "rejected_joints": (0..<17).filter { rejected[$0] },
                          "calibration_used": kinEnabled && !boneProfile.isEmpty,
                          "grip_used": gripReference != nil, "last_reset_reason": resetReason,
                          "variant": variant.rawValue, "timestamp": now])
    }

    private static func leg(_ pose: [SIMD3<Double>]) -> Double? {
        var values: [Double] = []
        for (a, b, c) in [(1, 2, 3), (4, 5, 6)] where finite(pose[a]) && finite(pose[b]) && finite(pose[c]) {
            let value = simd_length(pose[a] - pose[b]) + simd_length(pose[b] - pose[c])
            if value > 1e-6 { values.append(value) }
        }
        return values.isEmpty ? nil : median(values)
    }

    private static func finite(_ p: SIMD3<Double>) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
    private static func finite(_ p: SIMD2<Double>) -> Bool { p.x.isFinite && p.y.isFinite }
    private static func xy(_ p: SIMD3<Double>) -> SIMD2<Double> { SIMD2(p.x, p.y) }
    private static func clamp(_ x: Double, _ low: Double, _ high: Double) -> Double { min(max(x, low), high) }
    private static func median(_ values: [Double]) -> Double {
        let v = values.sorted(), n = values.count
        return n % 2 == 1 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2])
    }
    private static func median2(_ values: [SIMD2<Double>]) -> SIMD2<Double> {
        SIMD2(median(values.map(\.x)), median(values.map(\.y)))
    }
    private static func append<T>(_ item: T, to array: inout [T], limit: Int) {
        array.append(item)
        if array.count > limit { array.removeFirst(array.count - limit) }
    }
}

/// Numeric experiment trace for a real camera session. Video-as-camera already records these
/// fields in VideoRunLog; callers create this only for an explicitly enabled real-camera run.
final class ExerciseMotionTrace: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.bpt.motion.trace", qos: .utility)
    private var handle: FileHandle?

    init?() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("motion_estimator_runs", isDirectory: true)
        let url = directory.appendingPathComponent("run_\(UUID().uuidString).jsonl")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: url, options: .withoutOverwriting)
            handle = try FileHandle(forWritingTo: url)
        } catch { return nil }
    }

    func write(_ fields: [String: Any]) {
        queue.async { [self] in
            guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
            try? handle?.write(contentsOf: data + Data("\n".utf8))
        }
    }

    func close() {
        queue.async { [self] in
            try? handle?.close()
            handle = nil
        }
    }
}
