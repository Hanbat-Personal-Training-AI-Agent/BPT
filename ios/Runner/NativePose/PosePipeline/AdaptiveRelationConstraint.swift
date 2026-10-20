import Foundation
import simd

/// Confidence-aware adaptive relation constraint on the final 3D — EXPERIMENTAL, OFF by default
/// (`MotionAGFormerLive.adaptive` nil; the camera turns it on only with BPT_ADAPTIVE_3D=1).
/// Mirrors pose_feedback/geometry/adaptive_relations.py `AdaptiveRelations`; tests/fixtures/adaptive_relations_cases.json
/// pins both. Rules and their evaluation: docs/results/setup_constraint_prereg.md.
///
/// Runs after Pose3DConstraints on the XS H36M17 output (pelvis-relative, camera axes, crop units). A relation is the
/// camera-frame vector between two joints, v = P[b] − P[a], kept in px (crop units × `unit`, so a crop change does not
/// change it). Two contacts that stay put (both feet on the floor, both hands on the floor or one bar) with a static
/// camera keep v constant although each joint moves in pelvis-relative coordinates: the pelvis cancels out.
/// This is NOT a world-frame contact constraint — XS has no global position, so a single contact is never anchored.
/// - observed joint (2D confidence ≥ reliableConf): never changed, whatever the relation says.
/// - a relation is established only from `initFrames` frames in a row with both joints observed and a spread
///   ≤ initSpread × body scale. Before that (setup) there is no constraint at all.
/// - both observed: a small deviation (≤ trackTol × scale) moves the reference slowly (EMA `beta`: gradual foot shifts
///   are followed); `reanchorFrames` deviating frames in a row replace it (real motion: re-anchor, no snap back).
/// - one observed, the other not: the other joint becomes w·target + (1 − w)·XS, target = anchor + reference (or, with
///   `ballBase` set, XS pulled back onto a ball around it — only implausible XS guesses move),
///   w = (1 − r)·exp(−gap / decayFrames), r = confidence ramp lowConf…reliableConf, gap = frames since it was last
///   observed. σ² = spread² + growth·gap (× scale) is reported, never hidden.
/// - gap > maxGapFrames: no fill for that joint (expired); with confidence < lowConf that joint (a joint of an
///   established relation) is reported invalid (posture metrics that need it are skipped) instead of being held.
/// - neither observed: no anchor, XS is kept (invalid as above when the gap is long and the confidence low).
struct AdaptiveRelationConstraint {
    /// Python DEFAULTS. Tuned on Fit3D tuning subjects only (prereg §2); 제안값(사용자 미승인).
    struct Params {
        var reliableConf = 0.5
        var lowConf = 0.3
        var initFrames = 15
        var initSpread = 0.10
        var trackTol = 0.08
        var beta = 0.05
        var reanchorFrames = 6
        var decayFrames = 45.0
        var maxGapFrames = 90
        var growth = 0.0004
        var scaleWindow = 300
        /// Fraction of the body scale; nil = fill replaces XS. Set: XS is kept while within (ballBase + ballGrowth·gap) × scale
        /// of anchor + reference and only pulled back onto that ball when farther (a plausible XS guess is never replaced).
        var ballBase: Double? = nil
        var ballGrowth = 0.0
    }

    struct Relation: Equatable {
        let name: String
        let a: Int
        let b: Int
    }

    struct Report {
        struct RelationState {
            var state = "none"
            var event: String?
            /// |v − reference| / scale (both joints observed, established only).
            var dev: Double?
        }

        struct Fill {
            let w: Double
            let sigma: Double
            let gap: Int
        }

        var relations: [String: RelationState] = [:]
        var filled: [Int: Fill] = [:]
        /// Ascending.
        var invalid: [Int] = []
        var scale: Double?
    }

    // H36M17
    static let rHip = 1, rKnee = 2, rAnkle = 3, lHip = 4, lKnee = 5, lAnkle = 6, lWrist = 13, rWrist = 16

    /// Candidate relations (Python RELATIONS). Fit3D mocap E0 (tuning s03–s05): feet move 14–22 mm (squat) / 2–5 mm (row) /
    /// 23–50 mm (push-up) from their setup value during the set, hands 31–40 mm (push-up), grip 27–64 mm (row).
    static func relations(for exercise: FormExercise) -> [Relation] {
        let feet = Relation(name: "feet", a: rAnkle, b: lAnkle), hands = Relation(name: "hands", a: rWrist, b: lWrist)
        switch exercise {
        case .squat: return [feet]
        case .pushUp:
            return [feet, hands, Relation(name: "hand_foot_r", a: rAnkle, b: rWrist), Relation(name: "hand_foot_l", a: lAnkle, b: lWrist)]
        case .barbellRow: return [feet, hands]
        case .benchPress, .deadlift: return []
        }
    }

    private struct RelationMemory {
        var ref: SIMD3<Double>?
        var spread = 0.0
        var initRun: [SIMD3<Double>] = []
        var out: [SIMD3<Double>] = []
    }

    var params: Params
    let relations: [Relation]
    private var scaleHistory: [Double] = []
    private var memory: [String: RelationMemory] = [:]
    /// Joint → frame index when last observed (the first frame stands in until then).
    private var lastSeen: [Int: Int] = [:]
    private var firstFrame: Int?

    init(exercise: FormExercise, params: Params = Params(), relations: [Relation]? = nil) {
        self.params = params
        self.relations = relations ?? Self.relations(for: exercise)
        reset()
    }

    mutating func reset() {
        scaleHistory = []
        memory = Dictionary(uniqueKeysWithValues: relations.map { ($0.name, RelationMemory()) })
        lastSeen = [:]
        firstFrame = nil
    }

    /// Median observed leg length (thigh + shin, px) — the body scale of the thresholds.
    var scale: Double? { scaleHistory.isEmpty ? nil : Self.median(scaleHistory) }

    /// Exercise setup confirmed a stable relation (px): start from it instead of waiting for `initFrames`.
    mutating func seedReference(name: String, refPx: SIMD3<Double>, spreadPx: Double = 0) {
        guard memory[name] != nil else { return }
        memory[name] = RelationMemory(ref: refPx, spread: spreadPx)
    }

    /// `pose` crop units (after Pose3DConstraints), `confidence` H36M 2D confidences of the same frame, `unit` px per
    /// crop unit. Frame indices may jump over frames without 3D. Unfilled joints are returned exactly as given.
    mutating func update(_ pose: [SIMD3<Double>], confidence: [Double], frame: Int, unit: Double) -> ([SIMD3<Double>], Report) {
        precondition(pose.count == 17 && confidence.count == 17, "H36M17 expects 17 joints")
        let p = params
        let x = pose.map { $0 * unit }
        let seen = confidence.map { $0 >= p.reliableConf }
        if firstFrame == nil { firstFrame = frame }
        let first = firstFrame ?? frame
        for j in 0..<17 where seen[j] { lastSeen[j] = frame }
        recordScale(x, confidence)
        var report = Report()
        report.scale = scale
        guard let s = report.scale else { return (pose, report) }
        var estimates: [Int: [(target: SIMD3<Double>, w: Double, sigma: Double)]] = [:]
        for rel in relations {
            var m = memory[rel.name] ?? RelationMemory()
            let a = rel.a, b = rel.b
            let v = x[b] - x[a]
            var rr = Report.RelationState()
            if seen[a] && seen[b] {
                if m.ref == nil {
                    m.initRun.append(v)
                    if m.initRun.count > p.initFrames { m.initRun.removeFirst() }
                    if m.initRun.count == p.initFrames {
                        let med = Self.median3(m.initRun)
                        let spread = m.initRun.map { simd_length($0 - med) }.max() ?? 0
                        if spread <= p.initSpread * s {
                            m.ref = med
                            m.spread = spread
                            m.initRun = []
                            rr.event = "established"
                        }
                    }
                } else if let ref = m.ref {
                    let dev = simd_length(v - ref)
                    rr.dev = dev / s
                    if dev <= p.trackTol * s {
                        m.ref = ref + p.beta * (v - ref)
                        m.out = []
                    } else {
                        m.out.append(v)
                        if m.out.count >= p.reanchorFrames {
                            let med = Self.median3(m.out)
                            m.ref = med
                            m.spread = m.out.map { simd_length($0 - med) }.max() ?? 0
                            m.out = []
                            rr.event = "reanchored"
                        }
                    }
                }
            } else if m.ref == nil {
                m.initRun = []  // an init run needs consecutive frames with both joints observed
            }
            memory[rel.name] = m
            guard let ref = m.ref else {
                report.relations[rel.name] = rr
                continue
            }
            rr.state = "established"
            report.relations[rel.name] = rr
            guard seen[a] != seen[b] else { continue }
            let (anchor, other, sign) = seen[a] ? (a, b, 1.0) : (b, a, -1.0)
            let gap = frame - (lastSeen[other] ?? first)
            guard gap <= p.maxGapFrames else { continue }
            let r = min(max((confidence[other] - p.lowConf) / (p.reliableConf - p.lowConf), 0), 1)
            let w = (1 - r) * exp(-Double(gap) / p.decayFrames)
            let sigma = sqrt((m.spread / s) * (m.spread / s) + p.growth * Double(gap))
            var target = x[anchor] + sign * ref
            if let base = p.ballBase {
                let radius = (base + p.ballGrowth * Double(gap)) * s
                let off = x[other] - target, dist = simd_length(off)
                target = dist <= radius ? x[other] : target + off * (radius / dist)
            }
            estimates[other, default: []].append((target, w, sigma))
        }
        var out = pose
        for (j, est) in estimates {
            var w = 0.0, target = SIMD3<Double>.zero
            for e in est {
                w += e.w
                target += e.target
            }
            w /= Double(est.count)
            target /= Double(est.count)
            out[j] = (w * target + (1 - w) * x[j]) / unit
            report.filled[j] = Report.Fill(w: w, sigma: est.map(\.sigma).min() ?? 0, gap: frame - (lastSeen[j] ?? first))
        }
        // Only joints of an established relation (ones this constraint could fill) are flagged when the fill expired;
        // every other joint keeps the plain XS behaviour (device 2026-10-20: flagging every long-low joint marked 61% of
        // squat frames partial because of the hidden far arm, which no relation touches).
        let held = Set(relations.filter { memory[$0.name]?.ref != nil }.flatMap { [$0.a, $0.b] })
        for j in held.sorted() where !seen[j] && confidence[j] < p.lowConf && frame - (lastSeen[j] ?? first) > p.maxGapFrames
            && report.filled[j] == nil {
            report.invalid.append(j)
        }
        return (out, report)
    }

    private mutating func recordScale(_ x: [SIMD3<Double>], _ confidence: [Double]) {
        var legs: [Double] = []
        for (h, k, a) in [(Self.rHip, Self.rKnee, Self.rAnkle), (Self.lHip, Self.lKnee, Self.lAnkle)]
            where min(confidence[h], confidence[k], confidence[a]) >= params.reliableConf {
            legs.append(simd_length(x[h] - x[k]) + simd_length(x[k] - x[a]))
        }
        guard !legs.isEmpty else { return }
        scaleHistory.append(legs.reduce(0, +) / Double(legs.count))
        if scaleHistory.count > params.scaleWindow { scaleHistory.removeFirst() }
    }

    /// Python `_median`: middle value, or the mean of the two middle values.
    static func median(_ values: [Double]) -> Double {
        let v = values.sorted(), n = v.count
        return n % 2 == 1 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2])
    }

    static func median3(_ vectors: [SIMD3<Double>]) -> SIMD3<Double> {
        SIMD3(median(vectors.map(\.x)), median(vectors.map(\.y)), median(vectors.map(\.z)))
    }
}
