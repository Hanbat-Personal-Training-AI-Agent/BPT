import Foundation
import simd

/// Live MotionAGFormer-XS: past frames only. Mirrors pose_feedback/body/live_motionagformer.py
/// `LiveMotionAGFormer` (tests/fixtures/live3d_parity.json pins both).
///
/// Every camera frame is pushed (with its 2D payload). Frame t gets its 3D from the window that ends
/// `lookahead` frames later, [t + L − 26, t + L], output row 26 − L — the same window as the offline
/// pose-replay / Python `run_live_motionagformer_sequence`, so frame t comes out L frames late, together
/// with its own 2D payload (time alignment: evaluators see 2D and 3D of the same frame).
/// `cadence` k > 1 runs the model once per k frames and takes k consecutive rows of that one output
/// (rows 26 − L − k + 1 … 26 − L): every frame still gets its own 3D, with lookahead L … L + k − 1.
/// `flush()` (set end) emits the last L frames with the window clamped at the newest frame, like offline.
///
/// States (never hidden, never replaced by 2D):
/// - warmingUp: fewer than 27 real frames since the start / the last reset — no 3D.
/// - trackingLost: this frame's 2D has fewer than `minJoints` joints at `minConfidence` — no 3D for it.
///   `resetAfterLostFrames` such frames in a row clear the window (the sequence is broken), so the
///   person's return starts a new warm-up.
/// - bad3D: 3D exists but the anatomical constraints had to move it a lot (Pose3DConstraints) — 3D is
///   reported, judging skips it.
/// - ok.
enum Pose3DState: String {
    case warmingUp = "warming_up"
    case trackingLost = "tracking_lost"
    case bad3D = "bad_3d"
    case ok
}

struct Lifted3DFrame {
    let frameIndex: Int
    let state: Pose3DState
    /// Real frames in the window when this frame was emitted (0…27).
    let filled: Int
    /// XS output row, unconstrained (nil when warming up / tracking lost).
    let raw: [SIMD3<Double>]?
    /// After Pose3DConstraints (nil when `raw` is nil).
    let pose3D: [SIMD3<Double>]?
    let constraints: Pose3DConstraints.Report?
    /// Output row of the 27-frame window this frame was read from (26 − effective lookahead).
    let row: Int?

    /// 3D the evaluators may judge with: only in state ok.
    var usable3D: [SIMD3<Double>]? { state == .ok ? pose3D : nil }
}

struct MotionAGFormerLive<Payload> {
    static var window: Int { 27 }
    var lookahead = 5
    var cadence = 1
    var minJoints = 6
    var minConfidence = 0.3
    /// 0.5 s at 30 fps.
    var resetAfterLostFrames = 15
    var constraints = Pose3DConstraints()
    /// [27 × 17 × 3] input (x, y, confidence) → [27 × 17 × 3] output, row-major. Core ML in the app.
    let predict: ([Float]) throws -> [Float]

    private struct Entry {
        let frameIndex: Int
        let payload: Payload
        let input: [[Float]]
        let valid: Bool
    }

    private var normalizer = MotionAGFormerInputNormalizer()
    private var entries: [Entry] = []
    /// Trailing entries not emitted yet.
    private var pending = 0
    /// Real frames pushed since the last reset.
    private var realFrames = 0
    private var lostRun = 0
    /// Model runs (cost accounting).
    private(set) var inferences = 0

    init(lookahead: Int = 5, cadence: Int = 1, predict: @escaping ([Float]) throws -> [Float]) {
        precondition((0..<Self.window).contains(lookahead) && cadence >= 1 && lookahead + cadence <= Self.window)
        self.lookahead = lookahead
        self.cadence = cadence
        self.predict = predict
    }

    /// Latency added by the window: lookahead frames (+ up to cadence − 1 waiting for the batch).
    var delayFrames: Int { lookahead + cadence - 1 }

    /// Push one frame (COCO17 in frame pixels; Halpe26 callers pass its first 17 joints, which are COCO17
    /// in the same order). Returns the frames that became ready, oldest first.
    mutating func push(frameIndex: Int, coco17: [PoseKeypoint], imageWidth: Int, imageHeight: Int,
                       payload: Payload) throws -> [(Payload, Lifted3DFrame)] {
        let valid = coco17.count == 17 && coco17.filter { $0.confidence >= minConfidence }.count >= minJoints
        var out: [(Payload, Lifted3DFrame)] = []
        if valid {
            lostRun = 0
        } else {
            lostRun += 1
            if lostRun >= resetAfterLostFrames || entries.isEmpty {
                if !entries.isEmpty {
                    out += try flush()
                }
                out.append((payload, Lifted3DFrame(frameIndex: frameIndex, state: .trackingLost, filled: 0,
                                                   raw: nil, pose3D: nil, constraints: nil, row: nil)))
                return out
            }
        }
        let h36m = try PoseCoordinateTransforms.coco17ToH36M17(coco17)
        let input = normalizer.normalize(h36m, imageWidth: imageWidth, imageHeight: imageHeight)
        entries.append(Entry(frameIndex: frameIndex, payload: payload, input: input, valid: valid))
        pending += 1
        realFrames += 1
        if entries.count > Self.window { entries.removeFirst() }

        let ready = pending - lookahead
        guard ready > 0 else { return out }
        if realFrames < Self.window {
            out += emitWithout3D(count: ready)
        } else if ready >= cadence {
            out += try emitWindow(endingAt: entries.count - 1, count: ready, extraLookahead: 0)
        }
        return out
    }

    /// Emits every pending frame (window clamped at the newest frame) and resets. Call at set end.
    mutating func flush() throws -> [(Payload, Lifted3DFrame)] {
        var out: [(Payload, Lifted3DFrame)] = []
        if realFrames < Self.window {
            out = emitWithout3D(count: pending)
        } else {
            // Oldest pending frame first, each from its own clamped window ([t + L − 26, t + L], t + L
            // past the newest frame repeats the newest frame).
            while pending > 0 {
                let p = entries.count - pending
                let shortfall = p + lookahead - (entries.count - 1)
                if shortfall <= 0 {
                    out += try emitWindow(endingAt: p + lookahead, count: 1, extraLookahead: 0)
                } else {
                    out += try emitWindow(endingAt: entries.count - 1, count: 1, extraLookahead: shortfall)
                }
            }
        }
        reset()
        return out
    }

    mutating func reset() {
        normalizer = MotionAGFormerInputNormalizer()
        entries = []
        pending = 0
        realFrames = 0
        lostRun = 0
    }

    private mutating func emitWithout3D(count: Int) -> [(Payload, Lifted3DFrame)] {
        let start = entries.count - pending
        let emitted = entries[start..<(start + count)].map { e in
            (e.payload, Lifted3DFrame(frameIndex: e.frameIndex, state: e.valid ? .warmingUp : .trackingLost,
                                      filled: realFrames, raw: nil, pose3D: nil, constraints: nil, row: nil))
        }
        pending -= count
        return emitted
    }

    /// Runs the model on the 27 entries ending at `end` (the newest entry repeated `extraLookahead`
    /// more times on the right), emits the `count` oldest pending frames.
    private mutating func emitWindow(endingAt end: Int, count: Int, extraLookahead: Int) throws -> [(Payload, Lifted3DFrame)] {
        let w = Self.window
        var input = [Float](repeating: 0, count: w * 17 * 3)
        for t in 0..<w {
            let source = entries[min(max(end + extraLookahead - (w - 1) + t, 0), end)].input
            for j in 0..<17 { for c in 0..<3 { input[(t * 17 + j) * 3 + c] = source[j][c] } }
        }
        let output = try predict(input)
        precondition(output.count == w * 17 * 3, "MotionAGFormer output must be [27, 17, 3]")
        inferences += 1
        let start = entries.count - pending
        var emitted: [(Payload, Lifted3DFrame)] = []
        for p in start..<(start + count) {
            let e = entries[p]
            let row = (w - 1) - (end + extraLookahead - p)
            let raw = (0..<17).map { j in
                SIMD3<Double>((0..<3).map { Double(output[(row * 17 + j) * 3 + $0]) })
            }
            guard e.valid else {
                emitted.append((e.payload, Lifted3DFrame(frameIndex: e.frameIndex, state: .trackingLost, filled: realFrames,
                                                         raw: raw, pose3D: nil, constraints: nil, row: row)))
                continue
            }
            let (fixed, report) = constraints.apply(raw)
            emitted.append((e.payload, Lifted3DFrame(frameIndex: e.frameIndex, state: report.bad ? .bad3D : .ok,
                                                     filled: min(realFrames, w), raw: raw, pose3D: fixed,
                                                     constraints: report, row: row)))
        }
        pending -= count
        return emitted
    }
}

#if canImport(CoreML)
import CoreML

enum MotionAGFormerCoreML {
    static let inputName = "input_2d_sequence"
    static let outputName = "pred_3d_sequence"

    /// `MotionAGFormerLive.predict` backed by the XS Core ML model ([1,27,17,3] fp32 in, fp16/fp32 out).
    static func predictor(_ model: MLModel) -> ([Float]) throws -> [Float] {
        { values in
            let w = MotionAGFormerLive<Int>.window
            let input = try MLMultiArray(shape: [1, NSNumber(value: w), 17, 3], dataType: .float32)
            let pointer = input.dataPointer.bindMemory(to: Float.self, capacity: values.count)
            for i in values.indices { pointer[i] = values[i] }
            let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputName: input]))
            guard let pred = output.featureValue(for: outputName)?.multiArrayValue else {
                throw NSError(domain: "MotionAGFormerCoreML", code: 1, userInfo: [NSLocalizedDescriptionKey: "no \(outputName)"])
            }
            return MLShapedArray<Float>(converting: pred).scalars
        }
    }
}
#endif

/// MediaPipe wrists into the MotionAGFormer input only (2D evaluators keep RTMPose). Mirrors
/// pose_feedback/body/motionagformer_wrist_source.py: `reject_crossed_mediapipe_wrists` (a hand closer to the
/// other side's RTMPose wrist is dropped) then `build_motionagformer_input_2d(wrist_source="mediapipe")` (x/y
/// replaced, RTMPose confidence kept). A missing hand keeps the RTMPose wrist. Hands must come from the same
/// frame (the camera runs them on the same image, synchronously). Sides follow the RTMPose wrist the crop was
/// built on, so a mirrored front camera stays consistent with the body's labels.
/// Halpe26: its first 17 joints are COCO17, wrists 9 / 10 as here.
enum MotionAGFormerWristSource {
    static let leftWrist = 9, rightWrist = 10, leftElbow = 7, rightElbow = 8
    /// Keep a MediaPipe wrist only within this × the RTMPose forearm of the RTMPose wrist (Python
    /// gate_mediapipe_wrists; Fit3D S4: MediaPipe never beat RTMPose, 0.25 was the least harmful gate). 제안값. nil = no gate.
    static let defaultMaxShiftForearm = 0.25

    struct Result {
        var input: [PoseKeypoint]
        var replacedLeft = false
        var replacedRight = false
    }

    static func input(raw: [PoseKeypoint], left: PosePoint?, right: PosePoint?,
                      maxShiftForearm: Double? = defaultMaxShiftForearm) -> Result {
        var result = Result(input: raw)
        guard raw.count == 17 else { return result }
        func distance(_ p: PosePoint, _ k: PoseKeypoint) -> Double { hypot(p.x - k.x, p.y - k.y) }
        for (point, own, other, elbow) in [(left, leftWrist, rightWrist, leftElbow), (right, rightWrist, leftWrist, rightElbow)] {
            guard let point, distance(point, raw[own]) <= distance(point, raw[other]) else { continue }
            if let k = maxShiftForearm {
                let forearm = hypot(raw[own].x - raw[elbow].x, raw[own].y - raw[elbow].y)
                guard distance(point, raw[own]) < k * forearm else { continue }
            }
            result.input[own] = PoseKeypoint(x: point.x, y: point.y, confidence: raw[own].confidence)
            if own == leftWrist { result.replacedLeft = true } else { result.replacedRight = true }
        }
        return result
    }
}
