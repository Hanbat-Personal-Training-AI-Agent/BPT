import Foundation
import simd

/// Push-up wrist floor anchor on the 2D — EXPERIMENTAL, OFF by default (`BPT_WRIST_ANCHOR=1`, or Flutter
/// `--dart-define=BPT_WRIST_ANCHOR=true` → creationParams `wristAnchor`). Mirrors pose_feedback/geometry/wrist_anchor.py;
/// tests/fixtures/wrist_anchor_cases.json pins both. Rules and how the values were chosen:
/// docs/results/setup_constraint_prereg.md §8 (user 2026-10-20 21:15: a small hand move is fine, a wrist flying off is
/// not — the same principle as the feet).
///
/// Per wrist (COCO17 px): once the set is underway (`active`: rep ≥ 1 or setup ready) and the wrist and elbow were seen
/// reliably (confidence ≥ initConf) for initFrames frames within r of each other, their median is the floor reference
/// (r = radius × the 2D forearm of those frames; v2 — v1 also took low-confidence frames and frames before the set and
/// locked onto a screen-edge guess, §8 change log). Then an observed wrist within r is
/// kept and the reference follows it slowly (beta); a wrist out of r or not observed is replaced by the reference with
/// confidence heldConf (just under the evaluators' 0.30 joint gate: never a new observation, still the floor contact for
/// the push-up height samples) — "held". Observed positions out of r that stay within r/2 of each other for
/// reanchorFrames frames are a moved hand: the reference jumps there. The output feeds the overlay, the XS input and the
/// evaluators alike.
struct WristFloorAnchor {
    /// Python DEFAULTS. radius / conf / reanchorFrames: §8 rules on Fit3D tuning subjects s03–s05 (Home
    /// 20261020-wrist-tune). 제안값 (사용자 미승인).
    struct Params {
        var conf = 0.1
        var radius = 1.0
        var reanchorFrames = 15
        var initFrames = 15
        var beta = 0.05
        var heldConf = 0.29
        var initConf = 0.5
    }

    enum State: String {
        case none, observed, held, reanchored
    }

    private struct Memory {
        var ref: SIMD2<Double>?
        var forearm = 0.0
        var initRun: [(p: SIMD2<Double>, forearm: Double)] = []
        var out: [SIMD2<Double>] = []
    }

    /// Set by the platform view factory when Flutter sent `wristAnchor: true` (dart-define BPT_WRIST_ANCHOR).
    nonisolated(unsafe) static var enabledByFlutter = false

    /// COCO17 (wrist, elbow): left, right.
    static let wrists = [(9, 7), (10, 8)]
    var params: Params
    private var memory: [Int: Memory] = [:]

    init(params: Params = Params()) {
        self.params = params
        reset()
    }

    mutating func reset() {
        memory = Dictionary(uniqueKeysWithValues: Self.wrists.map { ($0.0, Memory()) })
    }

    private static func median(_ points: [SIMD2<Double>]) -> SIMD2<Double> {
        SIMD2(AdaptiveRelationConstraint.median(points.map(\.x)), AdaptiveRelationConstraint.median(points.map(\.y)))
    }

    private static func spread(_ points: [SIMD2<Double>], around c: SIMD2<Double>) -> Double {
        points.map { simd_length($0 - c) }.max() ?? 0
    }

    /// `k` COCO17 px → the same with the wrists anchored, and each wrist's state. `active`: the push-up set is underway
    /// (a reference is only taken then; one taken stays).
    mutating func update(_ k: [PoseKeypoint], active: Bool = true) -> (keypoints: [PoseKeypoint], states: [Int: State]) {
        guard k.count == 17 else { return (k, [:]) }
        var out = k, states: [Int: State] = [:]
        let p = params
        for (w, e) in Self.wrists {
            guard var m = memory[w] else { continue }
            defer { memory[w] = m }
            let point = SIMD2(k[w].x, k[w].y), seen = k[w].confidence >= p.conf
            guard let ref = m.ref else {
                states[w] = State.none
                guard active, k[w].confidence >= p.initConf, k[e].confidence >= p.initConf else { m.initRun = []; continue }
                m.initRun = Array((m.initRun + [(point, hypot(k[w].x - k[e].x, k[w].y - k[e].y))]).suffix(p.initFrames))
                if m.initRun.count == p.initFrames {
                    let pts = m.initRun.map(\.p), f = AdaptiveRelationConstraint.median(m.initRun.map(\.forearm)), med = Self.median(pts)
                    if f > 1e-6 && Self.spread(pts, around: med) <= p.radius * f {
                        m = Memory(ref: med, forearm: f)
                    }
                }
                continue
            }
            let r = p.radius * m.forearm
            if seen && simd_length(point - ref) <= r {
                m.ref = ref + p.beta * (point - ref)
                m.out = []
                states[w] = .observed
                continue
            }
            if seen {  // observed out of the radius: a jump, or the hand was put down elsewhere
                m.out = Array((m.out + [point]).suffix(p.reanchorFrames))
                let med = Self.median(m.out)
                if m.out.count == p.reanchorFrames && Self.spread(m.out, around: med) <= r / 2 {
                    m.ref = med
                    m.out = []
                    states[w] = .reanchored
                    continue
                }
            } else {
                m.out = []
            }
            out[w] = PoseKeypoint(x: ref.x, y: ref.y, confidence: p.heldConf)
            states[w] = .held
        }
        return (out, states)
    }
}
