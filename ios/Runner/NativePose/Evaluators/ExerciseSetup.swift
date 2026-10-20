import Foundation
import simd

/// Personalized exercise setup — EXPERIMENTAL, OFF by default (only when Flutter sends `exerciseSetup: true`).
/// Mirrors pose_feedback/body/exercise_setup.py (`ExerciseSetup`, `measure`, `depth_share`); tests/fixtures/
/// exercise_setup_cases.json pins both. Evidence and limits: docs/results/setup_constraint_prereg.md §6.
///
/// It never says a pose is correct — SMPL β does not define an optimal stance or grip. It
/// 1. measures scale-free items on the 3D (XS after constraints, H36M17, pelvis-relative, camera axes) with an
///    observation quality (2D confidence of the joints it needs; a width lying mostly along the camera depth is XS's
///    depth guess → "depth_estimated", not a measurement);
/// 2. expresses widths relative to the same frame's hip / shoulder joint width (calibration cm are display only);
/// 3. is ready when every required item was observed for `stableFrames` frames in a row and moved less than its
///    tolerance (stillness, not correctness);
/// 4. compares only with a reference the user saved ("내 기준"); there is no built-in ideal band.
/// Widths are between joint centres (hips, shoulders, ankles, wrists): grip_width is a wrist-centre approximation of
/// the grip, not the bar contact.
struct ExerciseSetup {
    /// Python DEFAULTS — 임시값 until E1 (tuning subjects) replaces them.
    struct Params {
        var reliableConf = 0.5
        var lowConf = 0.3
        var depthMax = 0.7
        var stableFrames = 30
        var tolRatio = 0.10
        var tolDeg = 5.0
        /// Per-item tolerance overriding the per-kind one (Python tol_items; E1: 2 × measured repeatability).
        var tolItems: [String: Double] = [:]
    }

    enum Quality: String {
        case good, low, missing
        case depthEstimated = "depth_estimated"
        var usable: Bool { self == .good || self == .depthEstimated }
    }

    enum Phase: String {
        case unavailable, measuring, holding, ready
    }

    struct Item {
        let key: String
        let value: Double?
        let quality: Quality
        let required: Bool
        /// depth_share rounded to 0.001.
        let depth: Double
        var ref: Double?
        /// "increase" / "decrease" / nil (within tolerance); only when `ref` is set.
        var cue: String?
    }

    struct State {
        let phase: Phase
        let progress: Double
        let moving: Bool
        let items: [Item]
    }

    /// Flutter creationParams (`exerciseSetup: true`, optional `setupVariant`, `setupReference`, `bodyProfile`).
    struct Options {
        var variant: String?
        var reference: [String: Double] = [:]
        /// Calibration widths / lengths in cm, display only.
        var bodyProfile: [String: Double] = [:]

        init(variant: String? = nil, reference: [String: Double] = [:], bodyProfile: [String: Double] = [:]) {
            self.variant = variant
            self.reference = reference
            self.bodyProfile = bodyProfile
        }

        /// nil unless `exerciseSetup` is true (default off).
        init?(creationParams params: [String: Any]?) {
            guard let params, params["exerciseSetup"] as? Bool == true else { return nil }
            func numbers(_ value: Any?) -> [String: Double] {
                guard let map = value as? [String: Any] else { return [:] }
                return map.compactMapValues { ($0 as? NSNumber)?.doubleValue }
            }
            self.init(variant: params["setupVariant"] as? String, reference: numbers(params["setupReference"]),
                      bodyProfile: numbers(params["bodyProfile"]))
        }
    }

    // H36M17
    static let pelvis = 0, rHip = 1, rKnee = 2, rAnkle = 3, lHip = 4, lKnee = 5, lAnkle = 6, thorax = 8
    static let lShoulder = 11, lElbow = 12, lWrist = 13, rShoulder = 14, rElbow = 15, rWrist = 16

    /// item → (H36M joints it needs, exercises where it is required for ready, tolerance in degrees).
    static let items: [String: (joints: [Int], requiredIn: Set<FormExercise>, degrees: Bool)] = [
        "feet_width": ([rAnkle, lAnkle, rHip, lHip], [.squat, .pushUp, .barbellRow], false),
        "feet_width_shoulder": ([rAnkle, lAnkle, rShoulder, lShoulder], [], false),
        "foot_symmetry": ([rAnkle, lAnkle, rHip, lHip], [], false),
        "foot_stagger": ([rAnkle, lAnkle, rHip, lHip, rKnee, lKnee], [], false),
        "shoulder_over_pelvis": ([rShoulder, lShoulder, rHip, lHip], [], false),
        "torso_incline": ([rShoulder, lShoulder, rHip, lHip], [.squat, .pushUp, .barbellRow], true),
        "hand_width": ([rWrist, lWrist, rShoulder, lShoulder], [.pushUp], false),
        "wrist_ahead": ([rWrist, lWrist, rShoulder, lShoulder, rElbow, lElbow], [], false),
        "body_line": ([rShoulder, lShoulder, rHip, lHip, rAnkle, lAnkle], [], false),
        "grip_width": ([rWrist, lWrist, rShoulder, lShoulder], [.barbellRow], false),
    ]

    static func keys(_ exercise: FormExercise) -> [String] {
        switch exercise {
        case .squat: return ["feet_width", "feet_width_shoulder", "foot_symmetry", "foot_stagger", "shoulder_over_pelvis", "torso_incline"]
        case .pushUp: return ["hand_width", "wrist_ahead", "feet_width", "body_line", "torso_incline"]
        case .barbellRow: return ["feet_width", "grip_width", "shoulder_over_pelvis", "torso_incline"]
        case .benchPress, .deadlift: return []
        }
    }

    /// Width items: the vectors whose depth share decides "depth_estimated" (numerator, reference width).
    static let widthVectors: [String: [(Int, Int)]] = [
        "feet_width": [(rAnkle, lAnkle), (rHip, lHip)], "feet_width_shoulder": [(rAnkle, lAnkle), (rShoulder, lShoulder)],
        "hand_width": [(rWrist, lWrist), (rShoulder, lShoulder)], "grip_width": [(rWrist, lWrist), (rShoulder, lShoulder)],
    ]

    let exercise: FormExercise
    var params: Params
    /// User-saved {item: value} ("내 기준").
    var reference: [String: Double]
    /// Snapshot {item: median over the ready window} once ready.
    private(set) var ready: [String: Double]?
    private var window: [(values: [String: Double], quality: [String: Quality], posePx: [SIMD3<Double>])] = []

    init(exercise: FormExercise, reference: [String: Double] = [:], params: Params = Params()) {
        self.exercise = exercise
        self.reference = reference
        self.params = params
    }

    mutating func reset() {
        window = []
        ready = nil
    }

    // MARK: measurement

    private static func unit(_ v: SIMD3<Double>) -> SIMD3<Double>? {
        let n = simd_length(v)
        return n > 1e-9 ? v / n : nil
    }

    /// {item: value} for the exercise's items (missing = not measurable). Ratios are scale-free; torso_incline in degrees.
    static func measure(_ P: [SIMD3<Double>], exercise: FormExercise, up: SIMD3<Double> = FormGeometry.up3D) -> [String: Double] {
        var out: [String: Double] = [:]
        let len = { (a: Int, b: Int) in simd_length(P[a] - P[b]) }
        let hipw = len(lHip, rHip), shw = len(lShoulder, rShoulder)
        let leg = (len(rHip, rKnee) + len(rKnee, rAnkle) + len(lHip, lKnee) + len(lKnee, lAnkle)) / 2
        let arm = (len(rShoulder, rElbow) + len(rElbow, rWrist) + len(lShoulder, lElbow) + len(lElbow, lWrist)) / 2
        let lr = unit(P[lHip] - P[rHip])
        let trunk = P[thorax] - P[pelvis]
        for key in keys(exercise) {
            var v: Double?
            switch key {
            case "feet_width" where hipw > 1e-9:
                v = len(lAnkle, rAnkle) / hipw
            case "feet_width_shoulder" where shw > 1e-9:
                v = len(lAnkle, rAnkle) / shw
            case "foot_symmetry":
                if let lr {
                    let mid = (P[lHip] + P[rHip]) / 2
                    v = (simd_dot(P[lAnkle] - mid, lr) + simd_dot(P[rAnkle] - mid, lr)) / hipw
                }
            case "foot_stagger":
                if lr != nil, leg > 1e-9, let fwd = unit(simd_cross(P[lHip] - P[rHip], up)) {
                    v = simd_dot(P[lAnkle] - P[rAnkle], fwd) / leg
                }
            case "shoulder_over_pelvis":
                if let lr { v = simd_dot((P[lShoulder] + P[rShoulder]) / 2 - (P[lHip] + P[rHip]) / 2, lr) / hipw }
            case "torso_incline" where simd_length(trunk) > 1e-9:
                v = acos(max(-1, min(1, simd_dot(trunk, up) / simd_length(trunk)))) * (180.0 / Double.pi)
            case "hand_width" where shw > 1e-9, "grip_width" where shw > 1e-9:
                v = len(lWrist, rWrist) / shw
            case "wrist_ahead" where arm > 1e-9:
                if let head = unit(trunk - up * simd_dot(trunk, up)) {
                    v = simd_dot((P[lWrist] + P[rWrist]) / 2 - (P[lShoulder] + P[rShoulder]) / 2, head) / arm
                }
            case "body_line":
                v = FormGeometry.signedLineDeviation3D(point: P[pelvis], a: P[thorax], b: (P[rAnkle] + P[lAnkle]) / 2, up: up)
            default:
                break
            }
            if let v, v.isFinite { out[key] = v }
        }
        return out
    }

    /// Largest |z| / |v| over the vectors a width item is made of (0 = image plane, 1 = along the camera depth).
    static func depthShare(_ P: [SIMD3<Double>], key: String) -> Double {
        (widthVectors[key] ?? []).map { a, b in abs(P[b].z - P[a].z) / max(simd_length(P[b] - P[a]), 1e-9) }.max() ?? 0
    }

    func quality(_ P: [SIMD3<Double>], _ confidence: [Double], key: String) -> Quality {
        let c = (Self.items[key]?.joints ?? []).map { confidence[$0] }.min() ?? 0
        if c < params.lowConf { return .missing }
        if c < params.reliableConf { return .low }
        return Self.depthShare(P, key: key) > params.depthMax ? .depthEstimated : .good
    }

    func tolerance(_ key: String) -> Double {
        if let t = params.tolItems[key] { return t }
        return Self.items[key]?.degrees == true ? params.tolDeg : params.tolRatio
    }

    /// At ready: {name: (median px vector, p90 deviation px)} over the ready window — the stable relation the adaptive
    /// constraint starts from (AdaptiveRelationConstraint.seedReference, variant F). Empty without a window.
    func seeds(_ relations: [AdaptiveRelationConstraint.Relation]) -> [String: (ref: SIMD3<Double>, spread: Double)] {
        guard !window.isEmpty else { return [:] }
        var out: [String: (ref: SIMD3<Double>, spread: Double)] = [:]
        for rel in relations {
            let v = window.map { $0.posePx[rel.b] - $0.posePx[rel.a] }
            let ref = AdaptiveRelationConstraint.median3(v)
            out[rel.name] = (ref, Self.percentile90(v.map { simd_length($0 - ref) }))
        }
        return out
    }

    /// numpy percentile(…, 90), linear interpolation.
    static func percentile90(_ values: [Double]) -> Double {
        let v = values.sorted()
        guard v.count > 1 else { return v.first ?? 0 }
        let pos = Double(v.count - 1) * 0.9, lo = Int(pos.rounded(.down)), t = pos - Double(lo)
        guard lo + 1 < v.count else { return v[lo] }
        return t >= 0.5 ? v[lo + 1] - (v[lo + 1] - v[lo]) * (1 - t) : v[lo] + (v[lo + 1] - v[lo]) * t
    }

    // MARK: per frame

    /// `pose` crop units (nil when this frame has no usable 3D), `confidence` H36M 2D confidences, `unit` px per crop unit.
    /// unavailable (no usable 3D) → measuring (a required item not observed well) → holding (all observed; `moving` when the
    /// window is full but an item moved more than its tolerance) → ready.
    mutating func update(_ pose: [SIMD3<Double>]?, confidence: [Double], usable: Bool = true,
                         up: SIMD3<Double> = FormGeometry.up3D, unit: Double = 1) -> State {
        let keys = Self.keys(exercise)
        let required = keys.filter { Self.items[$0]?.requiredIn.contains(exercise) == true }
        guard let P = pose, usable, confidence.count == 17 else {
            window = []
            return State(phase: ready != nil ? .ready : .unavailable, progress: 0, moving: false, items: [])
        }
        let values = Self.measure(P, exercise: exercise, up: up)
        var q: [String: Quality] = [:]
        for k in keys { q[k] = values[k] != nil ? quality(P, confidence, key: k) : .missing }
        if !required.allSatisfy({ q[$0]?.usable == true }) {
            window = []  // stillness is counted over frames in a row with every required item observed
        } else {
            window.append((values, q, P.map { $0 * unit }))
            if window.count > params.stableFrames { window.removeFirst() }
        }
        let full = window.count == params.stableFrames
        let moving = full && !required.allSatisfy { k in
            let v = window.compactMap { $0.values[k] }
            return (v.max() ?? 0) - (v.min() ?? 0) <= tolerance(k)
        }
        if ready == nil && full && !required.isEmpty && !moving {
            var snapshot: [String: Double] = [:]
            for k in keys {
                let v = window.compactMap { $0.values[k] }
                if !v.isEmpty { snapshot[k] = AdaptiveRelationConstraint.median(v) }
            }
            ready = snapshot
        }
        let items = keys.map { k -> Item in
            var item = Item(key: k, value: values[k], quality: q[k] ?? .missing, required: required.contains(k),
                            depth: (Self.depthShare(P, key: k) * 1000).rounded(.toNearestOrEven) / 1000)
            if let ref = reference[k], item.quality == .good, let value = values[k] {
                item.ref = ref
                let d = value - ref
                item.cue = abs(d) <= tolerance(k) ? nil : (d < 0 ? "increase" : "decrease")
            }
            return item
        }
        let phase: Phase = ready != nil ? .ready : (window.isEmpty ? .measuring : .holding)
        return State(phase: phase, progress: min(1, Double(window.count) / Double(params.stableFrames)), moving: moving, items: items)
    }
}

/// onPoseUpdate `setup` payload (Flutter NativeSetupStatus). Values are ratios of the same frame's joint widths (or
/// degrees); `approx` marks grip_width (wrist centres, not the bar contact).
enum ExerciseSetupBridge {
    static func payload(_ state: ExerciseSetup.State, exercise: FormExercise, variant: String?,
                        snapshot: [String: Double]?) -> [String: Any] {
        var out: [String: Any] = [
            "exercise": exercise.rawValue, "phase": state.phase.rawValue, "progress": state.progress, "moving": state.moving,
            "items": state.items.map { item -> [String: Any] in
                var d: [String: Any] = ["key": item.key, "quality": item.quality.rawValue, "required": item.required, "depth": item.depth]
                if let v = item.value { d["value"] = v }
                if let r = item.ref {
                    d["ref"] = r
                    d["cue"] = item.cue ?? NSNull()
                }
                if item.key == "grip_width" { d["approx"] = true }
                return d
            },
        ]
        if let variant { out["variant"] = variant }
        if let snapshot { out["snapshot"] = snapshot }
        return out
    }

    /// What must change before a new payload goes out: phase, progress in 10% steps, moving, per item quality / cue and
    /// the value rounded to 0.05 (degrees to 1°).
    static func signature(_ state: ExerciseSetup.State) -> String {
        let items = state.items.map { item -> String in
            let step = ExerciseSetup.items[item.key]?.degrees == true ? 1.0 : 0.05
            let value = item.value.map { String(Int(($0 / step).rounded())) } ?? "-"
            return "\(item.key):\(item.quality.rawValue):\(item.cue ?? "-"):\(value)"
        }
        return "\(state.phase.rawValue)|\(Int(state.progress * 10))|\(state.moving)|" + items.joined(separator: ",")
    }
}
