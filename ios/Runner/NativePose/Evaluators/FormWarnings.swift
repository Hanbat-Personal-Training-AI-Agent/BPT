import Foundation
import simd

// Form warnings shared by PushUpEvaluator, SquatEvaluator and BarbellRowEvaluator, following
// docs/research/form_feedback_spec.md (keys = lib/features/workout/data/kori_feedback_lines.dart).
//
// The evaluator calls `observe` every frame (once its stable status is known), `beginRep` when it
// starts a rep, `recordCurrentFrame` while the rep is open and `finishRep` when it counts the rep.
// Only frames inside that interval are judged. Metrics come from the camera-near side (higher
// confidence, with hysteresis), signed (no abs), in 2D, and from MotionAGFormer 3D when the caller
// has it (H36M17, y down); "3D 불량" frames (knee hinge θ < −limit) get no 3D metrics. Warnings fire
// from 2D only; 3D is logged.
//
// Delivery (spec 등급): 우선 = right after the rep, 개선 = only when the same key also fired on the
// previous rep, 셋업 = first rep only, 참고 = set summary only (sent `silent`). One spoken key per rep
// (highest grade), a spoken key is not repeated for `cooldownReps` reps, praise_fixed once when the
// key spoken on the previous rep is gone.
//
// Nothing reaches Flutter unless its key is in `FormCommonConfig.enabledFeedbackKeys` (default
// empty = log only): rules still run and every would-be warning stays in `FormRepReport.warnings`,
// the session log and pose-replay (which enables every key).
//
// Every threshold is TEMPORARY (임시값 — 테스트 영상으로 조정); tune with
//   swift run -c release --package-path ios/CalibrationEngineKit pose-replay --exercise <name> <video>

/// Shared knobs.
struct FormCommonConfig {
    /// Joint confidence to use a keypoint (same as the evaluators). 임시값 — 테스트 영상으로 조정
    var minJointConfidence = 0.30
    /// The other side must beat the current side's mean confidence by this much to take over. 임시값 — 테스트 영상으로 조정
    var sideSwitchMargin = 0.08
    /// Baseline = median of each metric over this many first reps. 임시값 — 테스트 영상으로 조정
    var baselineRepCount = 3
    /// Trend rules compare the mean of the last N reps with the first N (needs 2N reps). 임시값 — 테스트 영상으로 조정
    var trendRepCount = 3
    /// Front view when shoulder width / torso length >= this (side view is ~0-0.3). 임시값 — 테스트 영상으로 조정
    var frontViewShoulderRatio = 0.5
    /// A rep counts as front view when at least this fraction of its frames is. 임시값 — 테스트 영상으로 조정
    var frontViewRepFraction = 0.5
    /// Knee hinge detection limit for "3D 불량" (KneeHingeLimit default). 임시값 — 테스트 영상으로 조정
    var hingeLimitDegrees = 10.0
    /// A spoken key stays quiet for this many following reps. 임시값 — 테스트 영상으로 조정
    var cooldownReps = 3
    /// setup_full_body: required joints missing this many frames in a row before the first rep. 임시값 — 테스트 영상으로 조정
    var setupFullBodyFrames = 45
    /// tracking_lost: required joints missing this many frames in a row once the set has started. 임시값 — 테스트 영상으로 조정
    var trackingLostFrames = 15
    /// Forward/back (nose x vs ear x) flips only after this many agreeing frames. 임시값 — 테스트 영상으로 조정
    var facingFlipFrames = 5
    /// onFeedback keys sent to Flutter (spoken or silent), per key, e.g. ["pushup_hip_sag", "praise_fixed"].
    /// Default none: warnings are judged and logged only. `FormWarningTracker.allKeys` turns everything on.
    var enabledFeedbackKeys: Set<String> = []
}

/// Push-up (side view).
struct PushUpFormConfig {
    /// pushup_hip_sag (우선): hip below the shoulder–ankle line by more than this × line length.
    /// Exercise3D p99 (outputs/rep_validation/E_warning_dist_coco17.md).
    var hipSagDeviation = 0.140
    /// pushup_hip_pike (개선): hip above the shoulder–ankle line by more than this × line length. 임시값 — 테스트 영상으로 조정
    var hipPikeDeviation = 0.08
    /// pushup_shallow (개선): rep min elbow angle larger than the baseline by more than this (deg). 임시값 — 테스트 영상으로 조정
    var shallowOverBaselineDegrees = 15.0
    /// pushup_no_lockout (참고): rep max elbow angle smaller than the set max by more than this (deg). 임시값 — 테스트 영상으로 조정
    var noLockoutBelowSetMaxDegrees = 10.0
    /// pushup_head_drop (참고): ear moves floor-side of the shoulder–hip line, vs the rep's top, by more than this × torso length.
    /// Exercise3D p99 (E_warning_dist_coco17.md).
    var headDropDeviation = 0.376
    /// pushup_head_up (참고): same, upwards. 임시값 — 테스트 영상으로 조정
    var headUpDeviation = 0.15
    /// pushup_hand_position (셋업): first-rep top wrist ahead of the shoulder (towards the head) by more than this × arm length. 임시값 — 테스트 영상으로 조정
    var handForwardRatio = 0.35
    /// pushup_hand_position (셋업): or behind the shoulder (towards the feet) by more than this × arm length. 임시값 — 테스트 영상으로 조정
    var handBackwardRatio = 0.35
    /// pushup_depth_fade (참고): mean min elbow angle of the last N reps − first N reps above this (deg). 임시값 — 테스트 영상으로 조정
    var depthFadeDegrees = 15.0
}

/// Squat (side view; knee valgus front view only).
struct SquatFormConfig {
    /// squat_hips_first (우선): early-ascent window after the deepest frame (frames). 임시값 — 테스트 영상으로 조정
    var hipsFirstWindowFrames = 8
    /// squat_hips_first (우선): torso angle grows by more than this in that window (deg), and the hip rises faster than the shoulder. 임시값 — 테스트 영상으로 조정
    var hipsFirstTorsoRiseDegrees = 8.0
    /// squat_shallow (개선): rep min knee angle larger than the baseline by more than this (deg). 임시값 — 테스트 영상으로 조정
    var shallowOverBaselineDegrees = 15.0
    /// squat_no_lockout (참고): rep max knee or hip angle smaller than the set max by more than this (deg). 임시값 — 테스트 영상으로 조정
    var noLockoutBelowSetMaxDegrees = 10.0
    /// squat_lean_drift (참고): mean bottom torso angle of the last N reps − first N reps above this (deg). 임시값 — 테스트 영상으로 조정
    var leanDriftDegrees = 8.0
    /// squat_depth_fade (참고): mean min knee angle of the last N reps − first N reps above this (deg). 임시값 — 테스트 영상으로 조정
    var depthFadeDegrees = 10.0
    /// squat_knee_valgus (우선, front view): knee gap / ankle gap below this from the bottom through the ascent. 임시값 — 테스트 영상으로 조정
    var valgusKneeAnkleGapRatio = 1.0
    /// squat_heel_rise (개선, Halpe26 only): (heel y − big-toe y) / shin drops by more than this vs the rep start. 임시값 — 테스트 영상으로 조정
    var heelRiseShinRatio = 0.05
    /// squat_heel_rise: off for now (not judged with either model; the metric is still logged).
    var heelRiseEnabled = false
    /// squat_heel_rise: heel / big-toe confidence below this skips the frame. 임시값 — 테스트 영상으로 조정
    var footMinConfidence = 0.30
}

/// Barbell row (side view).
struct BarbellRowFormConfig {
    /// row_torso_swing (우선): torso angle max − min within the rep above this (deg). Exercise3D p99 (E_warning_dist_coco17.md).
    var torsoSwingRangeDegrees = 39.9
    /// row_standing_up (개선): rep mean torso angle more upright than the baseline by more than this (deg). 임시값 — 테스트 영상으로 조정
    var standingUpDegrees = 10.0
    /// row_short_pull (개선): peak elbow distance behind the shoulder–hip line smaller than the baseline by more than this × torso length. 임시값 — 테스트 영상으로 조정
    var shortPullBelowBaseline = 0.10
    /// row_head_up (참고): ear moves above the shoulder–hip line, vs the rep start, by more than this × torso length. 임시값 — 테스트 영상으로 조정
    var headUpDeviation = 0.15
    /// Side-view gate (rep counting + warnings): median shoulder width / torso length over the last
    /// `sideViewWindowFrames` frames <= this = side. Exercise3D rows: cams 20–36° from side 0.11–0.51,
    /// rear cams 76–81° 0.66–0.84; 0.56 = the widest 36° subject (0.509) scaled to 40° (× sin40/sin36).
    var sideViewMaxShoulderRatio = 0.56
    /// Once decided, the side flips only past the cutoff ± this. 임시값 — 테스트 영상으로 조정
    var sideViewHysteresis = 0.03
    /// Rolling window (frames, ~5 s) / frames needed before the first decision (nil until then).
    var sideViewWindowFrames = 150
    var sideViewMinFrames = 30
    /// row_shrug (개선, 실험): off until normal vs shrug footage separates it. 임시값 — 테스트 영상으로 조정
    var shrugEnabled = false
    /// row_shrug: ear–shoulder distance shrinks by more than this fraction of its rep-start value. 임시값 — 테스트 영상으로 조정
    var shrugEarShoulderDrop = 0.20
    /// row_shrug: frames whose nose→ear head angle moved more than this from the rep start are skipped (deg). 임시값 — 테스트 영상으로 조정
    var shrugMaxHeadAngleChangeDegrees = 15.0
}

enum FormExercise: String {
    case pushUp = "pushup"
    case squat
    case barbellRow = "barbell_row"
}

enum FormSide: String {
    case left, right
}

/// Spec 등급, highest first.
enum FormGrade: Int, Comparable {
    case priority = 0   // 우선
    case improve = 1    // 개선
    case setup = 2      // 셋업
    case reference = 3  // 참고

    static func < (a: FormGrade, b: FormGrade) -> Bool { a.rawValue < b.rawValue }
    var name: String { ["priority", "improve", "setup", "reference"][rawValue] }
}

/// One onFeedback call: `silent` = record for the set summary only (참고 / not chosen this rep).
struct FormFeedbackEvent: Equatable {
    let key: String
    let n: Int?
    let silent: Bool
}

// MARK: - Geometry

enum FormGeometry {
    /// COCO17 joints of one body side.
    struct SideJoints {
        let ear, shoulder, elbow, wrist, hip, knee, ankle: Int
    }

    static let nose = 0
    static let left = SideJoints(ear: 3, shoulder: 5, elbow: 7, wrist: 9, hip: 11, knee: 13, ankle: 15)
    static let right = SideJoints(ear: 4, shoulder: 6, elbow: 8, wrist: 10, hip: 12, knee: 14, ankle: 16)
    static func joints(_ side: FormSide) -> SideJoints { side == .left ? left : right }

    /// Mean confidence of a side's body joints (ear to ankle).
    static func sideScore(_ coco17: [PoseKeypoint], _ side: FormSide) -> Double {
        let j = joints(side)
        let ids = [j.ear, j.shoulder, j.elbow, j.wrist, j.hip, j.knee, j.ankle]
        return ids.map { coco17[$0].confidence }.reduce(0, +) / Double(ids.count)
    }

    /// Interior angle at b (deg), nil if a bone is ~0.
    static func angle(_ a: PoseKeypoint, _ b: PoseKeypoint, _ c: PoseKeypoint) -> Double? {
        let ux = a.x - b.x, uy = a.y - b.y, vx = c.x - b.x, vy = c.y - b.y
        let nu = hypot(ux, uy), nv = hypot(vx, vy)
        guard nu > 1e-8, nv > 1e-8 else { return nil }
        return acos(min(max((ux * vx + uy * vy) / (nu * nv), -1), 1)) * 180 / .pi
    }

    /// Trunk (hip → shoulder) vs image vertical, deg. 0 upright, > 0 leaning towards `facing`
    /// (+1 = nose on the +x side of the ear), < 0 leaning back. Image y is down.
    static func signedTorsoAngle2D(shoulder: PoseKeypoint, hip: PoseKeypoint, facing: Double) -> Double? {
        let dx = shoulder.x - hip.x, dy = shoulder.y - hip.y
        guard hypot(dx, dy) > 1e-8 else { return nil }
        return atan2(facing * dx, -dy) * 180 / .pi
    }

    /// Signed distance of `point` from the line a–b over |a − b| (cross-product sign); > 0 = floor
    /// side (image +y: hip sag / head drop), < 0 = above (pike / head up). nil when the line is within
    /// ~17° of vertical, where "floor side" is not defined.
    static func signedLineDeviation2D(point: PoseKeypoint, a: PoseKeypoint, b: PoseKeypoint) -> Double? {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 1e-8 else { return nil }
        var nx = -dy / length, ny = dx / length
        guard abs(ny) >= 0.3 else { return nil }
        if ny < 0 { nx = -nx; ny = -ny }
        return ((point.x - a.x) * nx + (point.y - a.y) * ny) / length
    }

    /// Signed distance of `point` behind the hip→shoulder line (towards the subject's back, i.e.
    /// away from `facing`) over the torso length.
    static func distanceBehindTorso2D(point: PoseKeypoint, shoulder: PoseKeypoint, hip: PoseKeypoint, facing: Double) -> Double? {
        let tx = shoulder.x - hip.x, ty = shoulder.y - hip.y
        let length = hypot(tx, ty)
        guard length > 1e-8 else { return nil }
        // Upright facing +x: trunk (0, -1) → back normal (-1, 0).
        let bx = facing * ty / length, by = -facing * tx / length
        return ((point.x - hip.x) * bx + (point.y - hip.y) * by) / length
    }

    // H36M17: 0 pelvis, 1 R hip, 3 R ankle, 4 L hip, 6 L ankle, 8 thorax. MotionAGFormer output is
    // y down (pose_feedback/geometry/README.md) and right-handed, so up = -y and the subject's
    // forward = (L hip − R hip) × up.
    static let up3D = SIMD3<Double>(0, -1, 0)

    /// 3D trunk (pelvis → thorax) vs vertical, deg; > 0 forward lean, < 0 backward.
    static func signedTorsoAngle3D(_ j: [SIMD3<Double>], up: SIMD3<Double> = up3D) -> Double? {
        guard j.count == 17 else { return nil }
        let forward = simd_cross(j[4] - j[1], up)
        let trunk = j[8] - j[0]
        guard simd_length(forward) > 1e-8, simd_length(trunk) > 1e-8 else { return nil }
        return atan2(simd_dot(trunk, simd_normalize(forward)), simd_dot(trunk, up)) * 180 / .pi
    }

    /// 3D pelvis offset from the thorax–ankle-centre line over the line length; > 0 = floor side,
    /// same meaning as `signedLineDeviation2D`.
    static func signedHipDeviation3D(_ j: [SIMD3<Double>], up: SIMD3<Double> = up3D) -> Double? {
        guard j.count == 17 else { return nil }
        let s = j[8], a = (j[3] + j[6]) * 0.5
        let d = a - s
        let length = simd_length(d)
        guard length > 1e-8 else { return nil }
        let dHat = d / length
        let n = -up - dHat * simd_dot(dHat, -up)
        guard simd_length(n) >= 0.3 else { return nil }
        return simd_dot(j[0] - s, simd_normalize(n)) / length
    }
}

// MARK: - Per-frame sample and per-rep report

struct FormFrameSample {
    var frame: Int
    var phase: String
    var side: FormSide
    var requiredOK = false
    var elbow: Double?
    var knee: Double?
    var hipAngle: Double?
    var torso: Double?
    var hipDeviation: Double?
    var headDeviation: Double?
    var headAngle: Double?
    var wristAhead: Double?
    var elbowBehind: Double?
    var earShoulder: Double?
    var hipY: Double?
    var shoulderY: Double?
    var torsoLength: Double?
    var frontView: Bool?
    var shoulderRatio: Double?
    var kneeAnkleGapRatio: Double?
    var heelToe: Double?
    var torso3D: Double?
    var hipDeviation3D: Double?
    var has3D = false
    var bad3D = false
}

struct FormRepReport {
    let exercise: FormExercise
    let repIndex: Int
    let startFrame: Int
    let endFrame: Int
    let side: String
    let metrics2D: [String: Double]
    let metrics3D: [String: Double]
    let frames3D: Int
    let bad3DFrames: Int
    /// Every key whose condition held, in rule order.
    let warnings: [String]
    /// The one key said after this rep (a warning or praise_fixed), if any.
    let spoken: String?

    var dictionary: [String: Any] {
        [
            "exercise": exercise.rawValue,
            "rep_index": repIndex,
            "start_frame": startFrame,
            "end_frame": endFrame,
            "side": side,
            "metrics_2d": metrics2D,
            "metrics_3d": metrics3D,
            "frames_3d": frames3D,
            "bad_3d_frames": bad3DFrames,
            "warnings": warnings,
            "grades": warnings.map { FormWarningTracker.grade(of: $0).name },
            "spoken": spoken.map { $0 as Any } ?? NSNull(),
        ]
    }
}

// MARK: - Tracker

final class FormWarningTracker {
    /// Rule order and grade per exercise (spec tables).
    static let rules: [FormExercise: [(key: String, grade: FormGrade)]] = [
        .pushUp: [
            ("setup_side_view", .setup), ("pushup_hip_sag", .priority), ("pushup_hip_pike", .improve),
            ("pushup_shallow", .improve), ("pushup_no_lockout", .reference), ("pushup_head_drop", .reference),
            ("pushup_head_up", .reference), ("pushup_hand_position", .setup), ("pushup_depth_fade", .reference),
        ],
        .squat: [
            ("squat_hips_first", .priority), ("squat_knee_valgus", .priority), ("squat_shallow", .improve),
            ("squat_heel_rise", .improve), ("squat_no_lockout", .reference), ("squat_lean_drift", .reference),
            ("squat_depth_fade", .reference),
        ],
        .barbellRow: [
            ("setup_side_view", .setup), ("row_torso_swing", .priority), ("row_standing_up", .improve),
            ("row_short_pull", .improve), ("row_shrug", .improve), ("row_head_up", .reference),
        ],
    ]

    /// Every key the tracker can send: the rules plus praise_fixed, setup_full_body, tracking_lost.
    static let allKeys = Set(rules.values.flatMap { $0.map(\.key) } + ["praise_fixed", "setup_full_body", "tracking_lost"])

    static func grade(of key: String) -> FormGrade {
        for list in rules.values { if let rule = list.first(where: { $0.key == key }) { return rule.grade } }
        return .setup  // setup_full_body, tracking_lost
    }

    let exercise: FormExercise
    var common = FormCommonConfig()
    var pushUp = PushUpFormConfig()
    var squat = SquatFormConfig()
    var row = BarbellRowFormConfig()

    /// Every frame given a 3D pose / of those, "3D 불량" (knee hinge θ < −limit), whole session.
    private(set) var sessionFrames3D = 0
    private(set) var sessionBad3DFrames = 0
    /// Reps per warning key this session (the `n` sent with onFeedback).
    private(set) var warningRepCounts: [String: Int] = [:]
    private(set) var reports: [FormRepReport] = []
    private(set) var side: FormSide?
    /// Barbell row side-view gate (see `BarbellRowFormConfig.sideViewMaxShoulderRatio`); nil until
    /// `sideViewMinFrames` frames. Other exercises leave it nil.
    private(set) var sideView: Bool?
    private var shoulderRatios: [Double] = []

    private var facing: Double?
    private var facingCandidateRun = 0
    private var current: FormFrameSample?
    private var repFrames: [FormFrameSample] = []
    private var repMetrics: [[String: Double]] = []
    private var lastRecordedFrame = Int.min
    private var missingRun = 0
    private var lastSpokenRep: [String: Int] = [:]
    private var previousFired: Set<String> = []
    private var previousSpoken: String?
    private var events: [FormFeedbackEvent] = []

    init(exercise: FormExercise) {
        self.exercise = exercise
    }

    func reset() {
        sessionFrames3D = 0
        sessionBad3DFrames = 0
        warningRepCounts = [:]
        reports = []
        side = nil
        sideView = nil
        shoulderRatios = []
        facing = nil
        facingCandidateRun = 0
        current = nil
        repFrames = []
        repMetrics = []
        lastRecordedFrame = .min
        missingRun = 0
        lastSpokenRep = [:]
        previousFired = []
        previousSpoken = nil
        events = []
    }

    /// onFeedback calls produced since the last drain, in order.
    func drainEvents() -> [FormFeedbackEvent] {
        defer { events = [] }
        return events
    }

    /// Every frame, once the evaluator's status for it is known. `pose3D`: H36M17 selected3D or nil;
    /// `feet`: Halpe26 toes/heels or nil.
    func observe(frameIndex: Int, coco17: [PoseKeypoint], pose3D: [SIMD3<Double>]? = nil,
                 feet: FootKeypoints? = nil, phase: String) {
        guard coco17.count == 17 else {
            current = nil
            return
        }
        let side = updateSide(coco17)
        var sample = FormFrameSample(frame: frameIndex, phase: phase, side: side)
        measure2D(coco17, feet: feet, side: side, into: &sample)
        if let pose3D, pose3D.count == 17 {
            sample.has3D = true
            sessionFrames3D += 1
            let hinge = KneeHingeLimit.apply(pose3D, config: .init(enabled: false, limitDegrees: common.hingeLimitDegrees))
            if hinge.bad3D {
                sample.bad3D = true
                sessionBad3DFrames += 1
            } else {
                sample.torso3D = FormGeometry.signedTorsoAngle3D(pose3D)
                sample.hipDeviation3D = FormGeometry.signedHipDeviation3D(pose3D)
            }
        }
        current = sample
        updateTracking(sample)
        if exercise == .barbellRow { updateSideView(sample) }
    }

    /// Rolling-median shoulder ratio vs the cutoff, with hysteresis. Turning "not side" queues
    /// setup_side_view (sent only if enabled, like every key).
    private func updateSideView(_ sample: FormFrameSample) {
        guard let ratio = sample.shoulderRatio else { return }
        shoulderRatios.append(ratio)
        if shoulderRatios.count > row.sideViewWindowFrames { shoulderRatios.removeFirst() }
        guard shoulderRatios.count >= row.sideViewMinFrames, let median = Self.median(shoulderRatios) else { return }
        let cut = row.sideViewMaxShoulderRatio, h = row.sideViewHysteresis
        let next = switch sideView {
        case nil: median <= cut
        case true?: median <= cut + h
        case false?: median < cut - h
        }
        if next == false && sideView != false { emit(FormFeedbackEvent(key: "setup_side_view", n: nil, silent: false)) }
        sideView = next
    }

    func beginRep() {
        repFrames = []
        recordCurrentFrame()
    }

    func recordCurrentFrame() {
        guard let current, repFrames.last?.frame != current.frame else { return }
        repFrames.append(current)
        lastRecordedFrame = current.frame
    }

    /// Call when the evaluator counts the rep; the report's `warnings` go into the rep summary.
    @discardableResult
    func finishRep(repIndex: Int) -> FormRepReport {
        recordCurrentFrame()
        let frames = repFrames
        repFrames = []
        let metrics = metrics2D(frames, isFirstRep: reports.isEmpty)
        let fired = judge(metrics, history: repMetrics, repIndex: repIndex)
        repMetrics.append(metrics)
        if repMetrics.count > 100 { repMetrics.removeFirst() }
        for key in fired { warningRepCounts[key, default: 0] += 1 }
        let spoken = deliver(fired, repIndex: repIndex)
        let sides = frames.map(\.side)
        let report = FormRepReport(
            exercise: exercise,
            repIndex: repIndex,
            startFrame: frames.first?.frame ?? -1,
            endFrame: frames.last?.frame ?? -1,
            side: (sides.filter { $0 == .left }.count * 2 >= sides.count ? FormSide.left : .right).rawValue,
            metrics2D: metrics,
            metrics3D: Self.metrics3D(frames),
            frames3D: frames.filter(\.has3D).count,
            bad3DFrames: frames.filter(\.bad3D).count,
            warnings: fired,
            spoken: spoken
        )
        reports.append(report)
        if reports.count > 100 { reports.removeFirst() }
        return report
    }

    // MARK: Delivery

    /// Picks the one spoken key, queues it and every other fired key as `silent`.
    private func deliver(_ fired: [String], repIndex: Int) -> String? {
        let eligible = fired.filter { key in
            let grade = Self.grade(of: key)
            guard grade != .reference, common.enabledFeedbackKeys.contains(key) else { return false }
            if let last = lastSpokenRep[key], repIndex - last <= common.cooldownReps { return false }
            return grade != .improve || previousFired.contains(key)
        }
        var spoken = eligible.min { Self.grade(of: $0) < Self.grade(of: $1) }  // stable: first in rule order
        if let key = spoken {
            lastSpokenRep[key] = repIndex
            emit(FormFeedbackEvent(key: key, n: warningRepCounts[key], silent: false))
        } else if let last = previousSpoken, !fired.contains(last), common.enabledFeedbackKeys.contains("praise_fixed") {
            spoken = "praise_fixed"
            emit(FormFeedbackEvent(key: "praise_fixed", n: nil, silent: false))
        }
        for key in fired where key != spoken {
            emit(FormFeedbackEvent(key: key, n: warningRepCounts[key], silent: true))
        }
        previousFired = Set(fired)
        previousSpoken = spoken == "praise_fixed" ? nil : spoken
        return spoken
    }

    /// setup_full_body before the first rep, tracking_lost once the set has started: once per run of
    /// frames missing a required joint.
    private func updateTracking(_ sample: FormFrameSample) {
        guard !sample.requiredOK else {
            missingRun = 0
            return
        }
        missingRun += 1
        let started = !reports.isEmpty || lastRecordedFrame == sample.frame - 1
        if started, missingRun == common.trackingLostFrames {
            emit(FormFeedbackEvent(key: "tracking_lost", n: nil, silent: false))
        } else if !started, missingRun == common.setupFullBodyFrames {
            emit(FormFeedbackEvent(key: "setup_full_body", n: nil, silent: false))
        }
    }

    /// Queues an onFeedback call only for an enabled key.
    private func emit(_ event: FormFeedbackEvent) {
        if common.enabledFeedbackKeys.contains(event.key) { events.append(event) }
    }

    // MARK: Side, 2D metrics

    private func updateSide(_ coco17: [PoseKeypoint]) -> FormSide {
        let l = FormGeometry.sideScore(coco17, .left), r = FormGeometry.sideScore(coco17, .right)
        switch side {
        case .left where r > l + common.sideSwitchMargin: side = .right
        case .right where l > r + common.sideSwitchMargin: side = .left
        case nil: side = l >= r ? .left : .right
        default: break
        }
        return side!
    }

    private func measure2D(_ k: [PoseKeypoint], feet: FootKeypoints?, side: FormSide, into s: inout FormFrameSample) {
        let c = common.minJointConfidence
        func p(_ i: Int) -> PoseKeypoint? { k[i].confidence >= c ? k[i] : nil }
        let j = FormGeometry.joints(side)
        let ear = p(j.ear), shoulder = p(j.shoulder), elbow = p(j.elbow), wrist = p(j.wrist)
        let hip = p(j.hip), knee = p(j.knee), ankle = p(j.ankle), nose = p(FormGeometry.nose)

        let required: [Int] = switch exercise {
        case .pushUp: [j.shoulder, j.elbow, j.wrist, j.hip, j.ankle]
        case .squat: [j.shoulder, j.hip, j.knee, j.ankle]
        case .barbellRow: [j.shoulder, j.elbow, j.wrist, j.hip]
        }
        s.requiredOK = required.allSatisfy { p($0) != nil }

        // Forward/back from the nose x relative to the ear, with hysteresis; kept through frames
        // where it can't be read.
        if let nose, let ear, abs(nose.x - ear.x) > 1 {
            let seen: Double = nose.x > ear.x ? 1 : -1
            if facing == nil || seen == facing {
                facing = seen
                facingCandidateRun = 0
            } else {
                facingCandidateRun += 1
                if facingCandidateRun >= common.facingFlipFrames {
                    facing = seen
                    facingCandidateRun = 0
                }
            }
        }
        if let shoulder, let elbow, let wrist {
            s.elbow = FormGeometry.angle(shoulder, elbow, wrist)
            let arm = hypot(shoulder.x - elbow.x, shoulder.y - elbow.y) + hypot(elbow.x - wrist.x, elbow.y - wrist.y)
            if arm > 1e-8, let facing { s.wristAhead = facing * (wrist.x - shoulder.x) / arm }
        }
        if let hip, let knee, let ankle { s.knee = FormGeometry.angle(hip, knee, ankle) }
        if let shoulder, let hip, let knee { s.hipAngle = FormGeometry.angle(shoulder, hip, knee) }
        if let nose, let ear { s.headAngle = atan2(nose.y - ear.y, nose.x - ear.x) * 180 / .pi }
        if let shoulder, let hip {
            s.hipY = hip.y
            s.shoulderY = shoulder.y
            let torso = hypot(shoulder.x - hip.x, shoulder.y - hip.y)
            if torso > 1e-8 { s.torsoLength = torso }
            if let facing {
                s.torso = FormGeometry.signedTorsoAngle2D(shoulder: shoulder, hip: hip, facing: facing)
                if let elbow { s.elbowBehind = FormGeometry.distanceBehindTorso2D(point: elbow, shoulder: shoulder, hip: hip, facing: facing) }
            }
            if let ankle { s.hipDeviation = FormGeometry.signedLineDeviation2D(point: hip, a: shoulder, b: ankle) }
            if let ear {
                s.headDeviation = FormGeometry.signedLineDeviation2D(point: ear, a: hip, b: shoulder)
                if torso > 1e-8 { s.earShoulder = hypot(ear.x - shoulder.x, ear.y - shoulder.y) / torso }
            }
        }
        if let ls = p(5), let rs = p(6), let lh = p(11), let rh = p(12) {
            let torso = hypot((ls.x + rs.x - lh.x - rh.x) / 2, (ls.y + rs.y - lh.y - rh.y) / 2)
            if torso > 1e-8 {
                s.shoulderRatio = abs(ls.x - rs.x) / torso
                let front = s.shoulderRatio! >= common.frontViewShoulderRatio
                s.frontView = front
                // Signed: crossed knees go negative.
                if front, let lk = p(13), let rk = p(14), let la = p(15), let ra = p(16), abs(la.x - ra.x) > 1 {
                    s.kneeAnkleGapRatio = (lk.x - rk.x) / (la.x - ra.x)
                }
            }
        }
        if let feet, let knee, let ankle {
            let heel = side == .left ? feet.leftHeel : feet.rightHeel
            let toe = side == .left ? feet.leftBigToe : feet.rightBigToe
            let shin = hypot(knee.x - ankle.x, knee.y - ankle.y)
            if heel.confidence >= squat.footMinConfidence, toe.confidence >= squat.footMinConfidence, shin > 1e-8 {
                s.heelToe = (heel.y - toe.y) / shin
            }
        }
    }

    // MARK: Aggregation

    func metrics2D(_ frames: [FormFrameSample], isFirstRep: Bool) -> [String: Double] {
        var m: [String: Double] = [:]
        func put(_ name: String, _ value: Double?) { if let value { m[name] = value } }
        func vals(_ key: KeyPath<FormFrameSample, Double?>, _ slice: ArraySlice<FormFrameSample>? = nil) -> [Double] {
            (slice ?? frames[...]).compactMap { $0[keyPath: key] }
        }
        func firstValue(_ key: KeyPath<FormFrameSample, Double?>) -> Double? { frames.lazy.compactMap { $0[keyPath: key] }.first }

        let views = frames.compactMap(\.frontView)
        if !views.isEmpty { put("front_view_fraction", Double(views.filter { $0 }.count) / Double(views.count)) }
        put("elbow_min", vals(\.elbow).min())
        put("elbow_max", vals(\.elbow).max())
        put("knee_min", vals(\.knee).min())
        put("knee_max", vals(\.knee).max())
        put("hip_angle_max", vals(\.hipAngle).max())
        let torso = vals(\.torso)
        put("torso_min", torso.min())
        put("torso_max", torso.max())
        put("torso_mean", torso.isEmpty ? nil : torso.reduce(0, +) / Double(torso.count))
        put("hip_dev_min", vals(\.hipDeviation).min())
        put("hip_dev_max", vals(\.hipDeviation).max())
        if let head0 = firstValue(\.headDeviation) {
            put("head_dev_change_min", vals(\.headDeviation).min().map { $0 - head0 })
            put("head_dev_change_max", vals(\.headDeviation).max().map { $0 - head0 })
        }
        put("elbow_behind_max", vals(\.elbowBehind).max())

        switch exercise {
        case .pushUp:
            // pushup_hand_position: first rep, most extended (top) frame.
            if isFirstRep, let top = frames.filter({ $0.elbow != nil }).max(by: { $0.elbow! < $1.elbow! }) {
                put("first_rep_top_wrist_ahead", top.wristAhead)
            }
        case .squat:
            let kneeMin = vals(\.knee).min()
            if let b = frames.firstIndex(where: { $0.knee != nil && $0.knee == kneeMin }) {
                let bottom = frames[b]
                put("torso_at_bottom", bottom.torso)
                let window = frames[b...].prefix(squat.hipsFirstWindowFrames + 1)
                if let t0 = bottom.torso, let t1 = vals(\.torso, window).max() { put("hips_first_torso_rise", t1 - t0) }
                if let end = window.last(where: { $0.hipY != nil && $0.shoulderY != nil }),
                   let h0 = bottom.hipY, let s0 = bottom.shoulderY, let length = bottom.torsoLength,
                   end.frame > bottom.frame {
                    let dt = Double(end.frame - bottom.frame)
                    put("hips_first_hip_rise_speed", (h0 - end.hipY!) / length / dt)
                    put("hips_first_shoulder_rise_speed", (s0 - end.shoulderY!) / length / dt)
                }
            }
            // Front view: bottom = lowest hip, then through the ascent.
            let hipYMax = vals(\.hipY).max()
            if let b = frames.firstIndex(where: { $0.hipY != nil && $0.hipY == hipYMax }) {
                put("knee_ankle_gap_ratio_min", vals(\.kneeAnkleGapRatio, frames[b...]).min())
            }
            if let h0 = firstValue(\.heelToe), let low = vals(\.heelToe).min() { put("heel_rise_max", h0 - low) }
        case .barbellRow:
            if let e0 = frames.first(where: { $0.earShoulder != nil && $0.headAngle != nil }),
               let start = e0.earShoulder, start > 1e-8 {
                let kept = frames.filter {
                    guard let a = $0.headAngle, $0.earShoulder != nil else { return false }
                    let d = abs(remainder(a - e0.headAngle!, 360))
                    return d <= row.shrugMaxHeadAngleChangeDegrees
                }
                if let low = kept.compactMap(\.earShoulder).min() { put("ear_shoulder_drop", 1 - low / start) }
            }
        }
        return m
    }

    static func metrics3D(_ frames: [FormFrameSample]) -> [String: Double] {
        var m: [String: Double] = [:]
        let torso = frames.compactMap(\.torso3D), hip = frames.compactMap(\.hipDeviation3D)
        if !torso.isEmpty {
            m["torso_min"] = torso.min()
            m["torso_max"] = torso.max()
            m["torso_mean"] = torso.reduce(0, +) / Double(torso.count)
        }
        if !hip.isEmpty {
            m["hip_dev_min"] = hip.min()
            m["hip_dev_max"] = hip.max()
        }
        return m
    }

    static func median(_ values: [Double]) -> Double? {
        let v = values.sorted()
        guard !v.isEmpty else { return nil }
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }

    // MARK: Rules (2D only)

    /// Keys whose condition holds for this rep, in rule order. `history` = earlier reps' metrics.
    func judge(_ m: [String: Double], history: [[String: Double]], repIndex: Int) -> [String] {
        var fired: Set<String> = []
        func fire(_ key: String, _ condition: Bool?) { if condition == true { fired.insert(key) } }
        func over(_ name: String, _ t: Double) -> Bool? { m[name].map { $0 > t } }
        func under(_ name: String, _ t: Double) -> Bool? { m[name].map { $0 < t } }
        /// (current − baseline median of the first reps) > t; nil until the baseline exists.
        func overBaseline(_ name: String, _ t: Double) -> Bool? {
            guard history.count >= common.baselineRepCount, let v = m[name],
                  let b = Self.median(history.prefix(common.baselineRepCount).compactMap { $0[name] }) else { return nil }
            return v - b > t
        }
        /// Current is below the set's max (this rep included) by more than t.
        func belowSetMax(_ name: String, _ t: Double) -> Bool? {
            guard let v = m[name], let best = (history.compactMap { $0[name] } + [v]).max() else { return nil }
            return best - v > t
        }
        /// mean(last N reps, this one included) − mean(first N) > t; needs 2N reps.
        func trend(_ name: String, _ t: Double) -> Bool? {
            let all = history + [m]
            let n = common.trendRepCount
            guard all.count >= 2 * n else { return nil }
            let first = all.prefix(n).compactMap { $0[name] }, last = all.suffix(n).compactMap { $0[name] }
            guard first.count == n, last.count == n else { return nil }
            return last.reduce(0, +) / Double(n) - first.reduce(0, +) / Double(n) > t
        }
        // Row: the session gate when decided, else the per-rep front-view fraction.
        let sideView = (exercise == .barbellRow ? self.sideView : nil)
            ?? ((m["front_view_fraction"] ?? 0) < common.frontViewRepFraction)
        let firstRep = history.isEmpty

        switch exercise {
        case .pushUp:
            fire("setup_side_view", firstRep && !sideView)
            guard sideView else { break }
            let c = pushUp
            fire("pushup_hip_sag", over("hip_dev_max", c.hipSagDeviation))
            fire("pushup_hip_pike", under("hip_dev_min", -c.hipPikeDeviation))
            fire("pushup_shallow", overBaseline("elbow_min", c.shallowOverBaselineDegrees))
            fire("pushup_no_lockout", belowSetMax("elbow_max", c.noLockoutBelowSetMaxDegrees))
            fire("pushup_head_drop", over("head_dev_change_max", c.headDropDeviation))
            fire("pushup_head_up", under("head_dev_change_min", -c.headUpDeviation))
            if let ahead = m["first_rep_top_wrist_ahead"] {
                fire("pushup_hand_position", ahead > c.handForwardRatio || ahead < -c.handBackwardRatio)
            }
            fire("pushup_depth_fade", trend("elbow_min", c.depthFadeDegrees))
        case .squat:
            let c = squat
            if sideView {
                if let rise = m["hips_first_torso_rise"], let hip = m["hips_first_hip_rise_speed"],
                   let shoulder = m["hips_first_shoulder_rise_speed"] {
                    fire("squat_hips_first", rise > c.hipsFirstTorsoRiseDegrees && hip > shoulder)
                }
                fire("squat_shallow", overBaseline("knee_min", c.shallowOverBaselineDegrees))
                fire("squat_no_lockout", belowSetMax("knee_max", c.noLockoutBelowSetMaxDegrees) == true
                     || belowSetMax("hip_angle_max", c.noLockoutBelowSetMaxDegrees) == true)
                fire("squat_lean_drift", trend("torso_at_bottom", c.leanDriftDegrees))
                fire("squat_depth_fade", trend("knee_min", c.depthFadeDegrees))
            } else {
                fire("squat_knee_valgus", under("knee_ankle_gap_ratio_min", c.valgusKneeAnkleGapRatio))
            }
            if c.heelRiseEnabled { fire("squat_heel_rise", over("heel_rise_max", c.heelRiseShinRatio)) }
        case .barbellRow:
            fire("setup_side_view", firstRep && !sideView)
            guard sideView else { break }
            let c = row
            if let lo = m["torso_min"], let hi = m["torso_max"] { fire("row_torso_swing", hi - lo > c.torsoSwingRangeDegrees) }
            // More upright = smaller forward torso angle.
            if let v = m["torso_mean"], history.count >= common.baselineRepCount,
               let b = Self.median(history.prefix(common.baselineRepCount).compactMap { $0["torso_mean"] }) {
                fire("row_standing_up", b - v > c.standingUpDegrees)
            }
            if let v = m["elbow_behind_max"], history.count >= common.baselineRepCount,
               let b = Self.median(history.prefix(common.baselineRepCount).compactMap { $0["elbow_behind_max"] }) {
                fire("row_short_pull", b - v > c.shortPullBelowBaseline)
            }
            if c.shrugEnabled { fire("row_shrug", over("ear_shoulder_drop", c.shrugEarShoulderDrop)) }
            fire("row_head_up", under("head_dev_change_min", -c.headUpDeviation))
        }
        return (Self.rules[exercise] ?? []).map(\.key).filter(fired.contains)
    }
}

// MARK: - Session log

/// Debug-build JSONL of per-rep form reports (2D + 3D metrics, warnings, "3D 불량" counts) under
/// Documents/workout_form_logs/, plus one `session` line on close. Same idea as CalibrationDebugLog.
final class WorkoutFormLog {
    static let isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private let queue = DispatchQueue(label: "com.bpt.workout.formlog")
    private var handle: FileHandle?  // queue only
    let url: URL

    init?(exercise: FormExercise, rootDirectory: URL? = nil) {
        guard Self.isEnabled || rootDirectory != nil else { return nil }
        let fileManager = FileManager.default
        guard let root = rootDirectory ?? (try? fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                                                 appropriateFor: nil, create: true)
            .appendingPathComponent("workout_form_logs", isDirectory: true)) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        url = root.appendingPathComponent("\(exercise.rawValue)_\(formatter.string(from: Date())).jsonl")
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try Data().write(to: url)
            handle = try FileHandle(forWritingTo: url)
        } catch {
            return nil
        }
    }

    func append(_ report: FormRepReport) {
        write(report.dictionary)
    }

    func close(_ tracker: FormWarningTracker) {
        write([
            "session": true,
            "exercise": tracker.exercise.rawValue,
            "reps": tracker.reports.count,
            "frames_3d": tracker.sessionFrames3D,
            "bad_3d_frames": tracker.sessionBad3DFrames,
            "warning_rep_counts": tracker.warningRepCounts,
            "side_view": tracker.sideView.map { $0 as Any } ?? NSNull(),
        ])
        queue.async { [self] in
            try? handle?.close()
            handle = nil
        }
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        queue.async { [self] in
            try? handle?.write(contentsOf: data + Data("\n".utf8))
        }
    }
}
