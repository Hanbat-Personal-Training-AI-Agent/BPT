import Foundation
import simd

// Form warnings shared by PushUpEvaluator, SquatEvaluator, BarbellRowEvaluator, BenchPressEvaluator and
// DeadliftEvaluator, following
// docs/research/form_feedback_spec.md (keys = lib/features/workout/data/kori_feedback_lines.dart).
//
// The evaluator calls `observe` every frame (once its stable status is known), `beginRep` when it
// starts a rep, `recordCurrentFrame` while the rep is open and `finishRep` when it counts the rep.
// Only frames inside that interval are judged. Metrics come from the camera-near side (higher
// confidence, with hysteresis), signed (no abs), in 2D, and from MotionAGFormer 3D when the caller
// has it (H36M17, y down; `measure3D`: the same quantities as 2D). Frames whose MotionAGFormerLive state is
// not ok get no 3D metrics. With `form3DRequired` (lift-app, 3D running) the delivered keys come from the 3D
// judgement and the 2D judgement is kept beside it for comparison; otherwise warnings fire from 2D.
//
// Delivery (spec 등급): 우선 = right after the rep, 개선 = only when the same key also fired on the
// previous rep, 셋업 = first rep only, 참고 = once at set end (`endSet`, scope "set", n = reps in the
// set). One key per rep (scope "rep", highest grade), a spoken key is not repeated for `cooldownReps`
// reps, praise_fixed once when the key spoken on the previous rep is gone. Fired keys that were not
// chosen stay in the report / log / set counts (worstJoint) only.
//
// Nothing reaches Flutter unless its key is in `FormCommonConfig.enabledFeedbackKeys` (default since
// 2026-10-20, user: every key that has a Flutter line; bench press / deadlift keys wait for theirs): rules
// still run for disabled keys and every would-be warning stays in `FormRepReport.warnings`, the session
// log and pose-replay (which enables every key). Thresholds are still unvalidated (임시값).
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
    /// tracking_lost: required joints missing this many frames in a row (1.0 s at 30 fps) once the set
    /// has started; never said inside a rep — deferred to the first frame after it while the loss lasts.
    /// Halpe26 push-up hips/ankles sit around 0.22–0.30 confidence for 15–112 frames mid-rep on normal
    /// Exercise3D sets (outputs/rep_validation/I_setup_keys.md). 임시값 — 테스트 영상으로 조정
    var trackingLostFrames = 30
    /// Forward/back (nose x vs ear x) flips only after this many agreeing frames. 임시값 — 테스트 영상으로 조정
    var facingFlipFrames = 5
    /// onFeedback keys sent to Flutter (scope "rep" or "set"), per key, e.g. ["pushup_hip_sag", "praise_fixed"].
    /// Default: the real judgement reaches the user (2026-10-20, user: "데모 경고 빼고 실제 우리 파이프라인대로
    /// 평가해서 넣어줘") — every key except those still without a Flutter line. Was setup_full_body and
    /// tracking_lost only (form warnings log only). Since 2026-10-22 (D-M-04) the high-false-alarm keys
    /// (`FormWarningTracker.quietByDefault`) are also left out; they are still judged and logged.
    var enabledFeedbackKeys: Set<String> = FormWarningTracker.allKeys
        .subtracting(FormWarningTracker.keysWithoutFlutterLines)
        .subtracting(FormWarningTracker.quietByDefault)
    /// Side-view gate (row, push-up): once decided, the side flips only past the exercise's cutoff ± this. 임시값 — 테스트 영상으로 조정
    var sideViewHysteresis = 0.03
    /// Side-view gate: rolling window (frames, ~5 s) / frames needed before the first decision (nil until then).
    var sideViewWindowFrames = 150
    var sideViewMinFrames = 30
    /// Posture keys come from the 3D judgement (MotionAGFormerLive running). A rep without enough usable
    /// 3D frames gets no posture keys (formSource "3d_unavailable") — never the 2D judgement instead.
    /// false = no 3D pipeline: 2D judgement (old behaviour, tests). lift-app turns it on wherever 3D runs.
    var form3DRequired = false
    /// A rep's 3D judgement needs at least this fraction of its frames in state ok. 임시값 — 테스트 영상으로 조정
    var min3DRepFraction = 0.5
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
    /// Side-view gate for rep judging (median shoulder width / torso length <= this = side; same
    /// window and hysteresis as the row). Push-up-specific: the row's 0.56 does not split push-up
    /// views (Exercise3D medians: 10–35° 0.06–0.53, 40° 0.50–0.75, 48° 0.44–0.48, 70–88° 1.8–2.8 —
    /// the torso foreshortens towards a front camera). 1.0 = every cam ≤ 48° side, every cam ≥ 70° not.
    var sideViewMaxShoulderRatio = 1.0
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
    /// `sideViewWindowFrames` frames <= this = side. Depends on the RTMPose input: with the person crop
    /// (CameraPreviewOptions.personCropInput) Exercise3D rows give, as 150-frame rolling medians, cams
    /// 20–36° from side 0.16–0.63 and rear cams 76–81° 0.69–1.27; 0.66 = midway between the tuning
    /// subject's side max (0.62) and rear min (0.71). The old stretched input needs 0.56 (side 0.10–0.57,
    /// rear 0.64–1.82). docs/decisions.md 2026-10-10 트랙 B.
    var sideViewMaxShoulderRatio = 0.66
    /// row_shrug (개선, 실험): off until normal vs shrug footage separates it. 임시값 — 테스트 영상으로 조정
    var shrugEnabled = false
    /// row_shrug: ear–shoulder distance shrinks by more than this fraction of its rep-start value. 임시값 — 테스트 영상으로 조정
    var shrugEarShoulderDrop = 0.20
    /// row_shrug: frames whose nose→ear head angle moved more than this from the rep start are skipped (deg). 임시값 — 테스트 영상으로 조정
    var shrugMaxHeadAngleChangeDegrees = 15.0
}

/// Bench press (side view: camera beside the bench). Every key here is off (no wrong-form footage yet;
/// docs/research/form_feedback_spec.md). Bar path, arch and scapular retraction are not judged (not
/// observable in 2D).
struct BenchPressFormConfig {
    /// bench_shallow (개선): rep min elbow angle larger than the baseline by more than this (deg). 임시값 — 테스트 영상으로 조정
    var shallowOverBaselineDegrees = 15.0
    /// bench_no_lockout (참고): rep max elbow angle smaller than the set max by more than this (deg). 임시값 — 테스트 영상으로 조정
    var noLockoutBelowSetMaxDegrees = 10.0
    /// bench_hips_up (우선): hip rises above its rep-start height by more than this × torso length. 임시값 — 테스트 영상으로 조정
    var hipLiftRatio = 0.10
}

/// Deadlift (side view). Every key here is off (no wrong-form footage yet). Lumbar flexion and bar
/// path are not judged (not observable in 2D).
struct DeadliftFormConfig {
    /// deadlift_hips_first (우선): pull window after the lowest hip frame (frames). 임시값 — 테스트 영상으로 조정
    var hipsFirstWindowFrames = 10
    /// deadlift_hips_first (우선): torso angle grows by more than this in that window (deg), and the hip rises faster than the shoulder. 임시값 — 테스트 영상으로 조정
    var hipsFirstTorsoRiseDegrees = 8.0
    /// deadlift_no_lockout (참고): rep max hip or knee angle smaller than the set max by more than this (deg). 임시값 — 테스트 영상으로 조정
    var noLockoutBelowSetMaxDegrees = 10.0
    /// deadlift_lean_back (참고): torso leans back past vertical by more than this at any frame (deg). 임시값 — 테스트 영상으로 조정
    var leanBackDegrees = 15.0
}

enum FormExercise: String {
    case pushUp = "pushup"
    case squat
    case barbellRow = "barbell_row"
    case benchPress = "bench_press"
    case deadlift
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

/// onFeedback `scope`: "rep" = said right after a rep (or a setup / tracking line), "set" = set summary at set end.
enum FormFeedbackScope: String {
    case rep, set
}

/// One onFeedback call {key, n?, scope}.
struct FormFeedbackEvent: Equatable {
    let key: String
    let n: Int?
    var scope: FormFeedbackScope = .rep
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

    /// Angle difference wrapped to (-180, 180].
    static func wrapDegrees(_ d: Double) -> Double {
        let r = remainder(d, 360)
        return r == -180 ? 180 : r
    }

    /// Angles in (-180, 180] made continuous (each step wrapped), so max − min / mean stay right
    /// when a sequence crosses ±180 (e.g. 179 → -179 is a 2° step, not 358°).
    static func unwrapDegrees(_ a: [Double]) -> [Double] {
        var out: [Double] = []
        for v in a { out.append(out.last.map { $0 + wrapDegrees(v - $0) } ?? v) }
        return out
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

    /// "Up" in the XS output frame (image x right, y down, z away from the camera) from CoreMotion gravity (device
    /// frame: x right, y up the screen, z out of the screen), phone in portrait. Front camera: the image is mirrored
    /// (x flips) and "away from the camera" is +z of the device. Upright phone → (0, −1, 0) = `up3D`.
    /// Hypothesis: XS depth (z) sign follows the camera frame — not verified on a device yet (lift_app.md).
    static func cameraUp(gravity g: SIMD3<Double>, frontCamera: Bool) -> SIMD3<Double> {
        let image = SIMD3<Double>(frontCamera ? -g.x : g.x, -g.y, frontCamera ? g.z : -g.z)
        return simd_length(image) > 1e-6 ? -simd_normalize(image) : up3D
    }

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
        return signedLineDeviation3D(point: j[0], a: j[8], b: (j[3] + j[6]) * 0.5, up: up)
    }

    /// `signedLineDeviation2D` in 3D: offset of `point` from the line a–b along "down" made
    /// perpendicular to the line, over |a − b|; nil when the line is within ~17° of vertical.
    static func signedLineDeviation3D(point: SIMD3<Double>, a: SIMD3<Double>, b: SIMD3<Double>,
                                      up: SIMD3<Double> = up3D) -> Double? {
        let d = b - a
        let length = simd_length(d)
        guard length > 1e-8 else { return nil }
        let dHat = d / length
        let n = -up - dHat * simd_dot(dHat, -up)
        guard simd_length(n) >= 0.3 else { return nil }
        return simd_dot(point - a, simd_normalize(n)) / length
    }

    /// Interior angle at b (deg), nil if a bone is ~0.
    static func angle3D(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Double? {
        let u = a - b, v = c - b
        guard simd_length(u) > 1e-8, simd_length(v) > 1e-8 else { return nil }
        return atan2(simd_length(simd_cross(u, v)), simd_dot(u, v)) * 180 / .pi
    }

    /// H36M17 joints of one body side (shoulder, elbow, wrist, hip, knee, ankle).
    static func h36mSide(_ side: FormSide) -> (shoulder: Int, elbow: Int, wrist: Int, hip: Int, knee: Int, ankle: Int) {
        side == .left ? (11, 12, 13, 4, 5, 6) : (14, 15, 16, 1, 2, 3)
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
    var has3D = false
    var bad3D = false
    /// MotionAGFormerLive state of this frame (nil = caller gave no 3D pipeline state).
    var state3D: Pose3DState?
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
    /// Every key whose condition held, in rule order, from `formSource` (the keys that are delivered).
    let warnings: [String]
    /// The one key said after this rep (a warning or praise_fixed), if any.
    let spoken: String?
    /// 2D judgement of the same rep (kept for comparison only when formSource is 3D).
    var warnings2D: [String] = []
    /// 3D judgement; nil when the rep had too few usable 3D frames.
    var warnings3D: [String]?
    /// "3d", "3d_unavailable" (3D required but missing: no posture keys) or "2d" (no 3D pipeline).
    var formSource = "2d"
    /// Rep frames per MotionAGFormerLive state.
    var states3D: [String: Int] = [:]

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
            "warnings_2d": warnings2D,
            "warnings_3d": warnings3D.map { $0 as Any } ?? NSNull(),
            "form_source": formSource,
            "states_3d": states3D,
            "grades": warnings.map { FormWarningTracker.grade(of: $0).name },
            "spoken": spoken.map { $0 as Any } ?? NSNull(),
        ]
    }
}

extension FormRepReport {
    /// Test-mode (video mode) caption of this rep's real judgement: rep, validity, every fired key (참고 = reference,
    /// 로그 = not enabled for Flutter), what was sent to Flutter, and 1–2 key metrics of the judged source.
    func debugCaption(sent: [String], enabled: Set<String>) -> String {
        let source = formSource == "3d" ? "3D" : formSource == "2d" ? "2D" : "판정 불가(3D 부족)"
        let states = ["ok", "partial_3d", "bad_3d", "tracking_lost", "warming_up"].compactMap { k in
            states3D[k].map { "\(k.replacingOccurrences(of: "_3d", with: "")) \($0)" } }.joined(separator: "·")
        let fired: [String] = warnings.map { key in
            let reference = FormWarningTracker.grade(of: key) == .reference ? "(참고)" : ""
            let logOnly = enabled.contains(key) ? "" : "(로그)"
            return key + reference + logOnly
        }
        let m: [String: Double] = formSource == "3d" ? metrics3D : metrics2D
        func f(_ name: String, _ label: String, _ digits: Int) -> String? {
            guard let v = m[name] else { return nil }
            return label + " " + String(format: "%.\(digits)f", v)
        }
        var metric: [String?]
        switch exercise {
        case .squat: metric = [f("knee_min", "무릎 최소", 0), f("torso_at_bottom", "바닥 몸통", 0)]
        case .pushUp: metric = [f("hip_dev_min", "엉덩이 선 최소", 2), f("hip_dev_max", "최대", 2)]
        case .barbellRow:
            var range: String?
            if let hi = m["torso_max"], let lo = m["torso_min"] { range = "범위 " + String(format: "%.0f", hi - lo) }
            metric = [f("torso_mean", "몸통 평균", 0), range]
        default: metric = [f("elbow_min", "팔꿈치 최소", 0)]
        }
        let head: String = "#\(repIndex) " + source + (states.isEmpty ? "" : " (" + states + ")")
        let firedLine: String = "울림: " + (fired.isEmpty ? "없음" : fired.joined(separator: ", "))
        let sentLine: String = "보냄: " + (sent.isEmpty ? "없음" : sent.joined(separator: ", "))
        let metricLine: String = metric.compactMap { $0 }.joined(separator: " · ")
        return [head, firedLine, sentLine, metricLine].filter { !$0.isEmpty }.joined(separator: "\n")
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
        .benchPress: [
            ("setup_side_view", .setup), ("bench_hips_up", .priority), ("bench_shallow", .improve),
            ("bench_no_lockout", .reference),
        ],
        .deadlift: [
            ("setup_side_view", .setup), ("deadlift_hips_first", .priority), ("deadlift_no_lockout", .reference),
            ("deadlift_lean_back", .reference),
        ],
    ]

    /// Every key the tracker can send: the rules plus praise_fixed, setup_full_body, tracking_lost.
    static let allKeys = Set(rules.values.flatMap { $0.map(\.key) } + ["praise_fixed", "praise_good", "setup_full_body", "tracking_lost"])

    /// Rep metrics every praise needs: without them "no warning" may only mean "could not measure" (never praise that).
    static let praiseMetrics: [FormExercise: [String]] = [
        .pushUp: ["hip_dev_min", "hip_dev_max", "elbow_min", "elbow_max"],
        .squat: ["knee_min", "knee_max", "hip_angle_max"],
        .barbellRow: ["torso_min", "torso_max", "elbow_behind_max"],
    ]

    /// Bench press / deadlift keys (track G): their lines are drafted in docs/progress/2026-10-10.md for the
    /// teammate who owns kori_feedback_lines.dart. They stay off until the dart file has them.
    static let keysWithoutFlutterLines: Set<String> = [
        "bench_hips_up", "bench_shallow", "bench_no_lockout",
        "deadlift_hips_first", "deadlift_no_lockout", "deadlift_lean_back",
    ]

    /// Keys with a Flutter line that stay off by default (D-M-04, 2026-10-22, user: "추천대로 진행"): on
    /// held-out normal reps they false-alarm 10–90 % (docs/results/rules_calib.md). Judged and logged only.
    static let quietByDefault: Set<String> = [
        "squat_no_lockout", "squat_knee_valgus",
        "pushup_no_lockout", "pushup_hip_pike", "pushup_shallow", "pushup_head_up",
    ]

    static func grade(of key: String) -> FormGrade {
        for list in rules.values { if let rule = list.first(where: { $0.key == key }) { return rule.grade } }
        return .setup  // setup_full_body, tracking_lost
    }

    let exercise: FormExercise
    var common = FormCommonConfig()
    var pushUp = PushUpFormConfig()
    var squat = SquatFormConfig()
    var row = BarbellRowFormConfig()
    /// "Up" for 3D metrics (camera −y by default; FormGeometry.cameraUp(gravity:) when the camera feeds gravity).
    var up3D = FormGeometry.up3D
    var bench = BenchPressFormConfig()
    var deadlift = DeadliftFormConfig()

    /// Every frame given a 3D pose / of those, "3D 불량" (knee hinge θ < −limit), whole session.
    private(set) var sessionFrames3D = 0
    private(set) var sessionBad3DFrames = 0
    /// Reps per warning key this session (the `n` sent with onFeedback).
    private(set) var warningRepCounts: [String: Int] = [:]
    /// Reps per warning key in the current set (cleared by `endSet`; worstJoint and set-scope `n`).
    private(set) var setWarningRepCounts: [String: Int] = [:]
    private(set) var reports: [FormRepReport] = []
    private(set) var side: FormSide?
    /// Side-view gate (row: `BarbellRowFormConfig.sideViewMaxShoulderRatio`, push-up:
    /// `PushUpFormConfig.sideViewMaxShoulderRatio`); nil until `sideViewMinFrames` frames. Squat leaves it nil.
    private(set) var sideView: Bool?
    private var shoulderRatios: [Double] = []
    private var sideViewGuided = false

    private var facing: Double?
    private var facingCandidateRun = 0
    private var current: FormFrameSample?
    /// Same quantities measured on the 3D pose of the same frame (nil when it has no usable 3D).
    private var current3D: FormFrameSample?
    private var repFrames: [FormFrameSample] = []
    private var repFrames3D: [FormFrameSample] = []
    private var repMetrics: [[String: Double]] = []
    private var repMetrics3D: [[String: Double]] = []
    private var lastRecordedFrame = Int.min
    private var missingRun = 0
    private var repOpen = false
    private var trackingLostSent = false
    private var lastSpokenRep: [String: Int] = [:]
    private var previousFired: Set<String> = []
    private var previousSpoken: String?
    private var events: [FormFeedbackEvent] = []

    init(exercise: FormExercise) {
        self.exercise = exercise
        if exercise == .barbellRow { common.enabledFeedbackKeys.insert("setup_side_view") }
    }

    func reset() {
        sessionFrames3D = 0
        sessionBad3DFrames = 0
        warningRepCounts = [:]
        setWarningRepCounts = [:]
        reports = []
        side = nil
        sideView = nil
        shoulderRatios = []
        sideViewGuided = false
        facing = nil
        facingCandidateRun = 0
        current = nil
        current3D = nil
        repFrames = []
        repFrames3D = []
        repMetrics = []
        repMetrics3D = []
        lastRecordedFrame = .min
        missingRun = 0
        repOpen = false
        trackingLostSent = false
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
    /// `feet`: Halpe26 toes/heels or nil. `pose3DState`: MotionAGFormerLive state of this frame (the 3D
    /// is measured only in state ok); nil = old callers, then the knee hinge check alone decides bad 3D.
    func observe(frameIndex: Int, coco17: [PoseKeypoint], pose3D: [SIMD3<Double>]? = nil,
                 pose3DState: Pose3DState? = nil, feet: FootKeypoints? = nil, phase: String) {
        guard coco17.count == 17 else {
            current = nil
            current3D = nil
            return
        }
        let side = updateSide(coco17)
        var sample = FormFrameSample(frame: frameIndex, phase: phase, side: side)
        measure2D(coco17, feet: feet, side: side, into: &sample)
        current3D = nil
        var state = pose3DState
        if let pose3D, pose3D.count == 17 {
            sample.has3D = true
            sessionFrames3D += 1
            if state == nil {
                let hinge = KneeHingeLimit.apply(pose3D, config: .init(enabled: false, limitDegrees: common.hingeLimitDegrees))
                state = hinge.bad3D ? .bad3D : .ok
            }
            if state == .bad3D {
                sample.bad3D = true
                sessionBad3DFrames += 1
            } else if state == .ok || state == .partial3D {
                // partial3D: untrusted joints are NaN; every metric that needs one comes out nil (sanitised below).
                var s3 = FormFrameSample(frame: frameIndex, phase: phase, side: side)
                measure3D(pose3D, like: sample, into: &s3)
                s3.state3D = state
                current3D = s3
            }
        }
        sample.state3D = state
        current = sample
        updateTracking(sample)
        if exercise == .pushUp || exercise == .barbellRow { updateSideView(sample) }
    }

    /// The 2D quantities, measured on the H36M17 3D pose (same names and signs, view-independent
    /// angles). Camera-view fields (front view, shoulder ratio) stay the 2D ones — they describe the camera.
    /// "Down" is the camera +y (no gravity yet, D-D-07). Ear/nose quantities have no H36M17 joint: head (10) is used for
    /// the head-line deviation, shrug and heel quantities stay nil.
    private func measure3D(_ j: [SIMD3<Double>], like s2: FormFrameSample, into s: inout FormFrameSample) {
        let k = FormGeometry.h36mSide(s2.side)
        let up = up3D
        s.requiredOK = true
        s.has3D = true
        s.state3D = .ok
        s.frontView = s2.frontView
        s.shoulderRatio = s2.shoulderRatio
        s.elbow = FormGeometry.angle3D(j[k.shoulder], j[k.elbow], j[k.wrist])
        s.knee = FormGeometry.angle3D(j[k.hip], j[k.knee], j[k.ankle])
        s.hipAngle = FormGeometry.angle3D(j[k.shoulder], j[k.hip], j[k.knee])
        s.torso = FormGeometry.signedTorsoAngle3D(j, up: up)
        s.hipDeviation = FormGeometry.signedHipDeviation3D(j, up: up)
        s.headDeviation = FormGeometry.signedLineDeviation3D(point: j[10], a: j[0], b: j[8], up: up)
        let trunk = j[8] - j[0], torsoLength = simd_length(trunk)
        if torsoLength > 1e-8 {
            // XS output is pelvis-relative, so 3D hip height is always 0 (S7 finding): hip / shoulder heights and the
            // torso length that normalises their speeds come from the 2D sample of the same frame (image y, absolute).
            s.torsoLength = s2.torsoLength
            s.hipY = s2.hipY
            s.shoulderY = s2.shoulderY
            // Back normal in the trunk's sagittal plane: −(L hip − R hip) × trunk, as the 2D "behind the torso".
            let chest = simd_cross(j[4] - j[1], trunk)
            if simd_length(chest) > 1e-8 {
                s.elbowBehind = simd_dot(j[k.elbow] - j[0], -simd_normalize(chest)) / torsoLength
            }
        }
        let arm = simd_length(j[k.shoulder] - j[k.elbow]) + simd_length(j[k.elbow] - j[k.wrist])
        let headward = trunk - up * simd_dot(trunk, up)
        if arm > 1e-8, simd_length(headward) > 1e-8 {
            // Horizontal, towards the head (2D: image x towards the facing side ≈ the head in a side push-up).
            s.wristAhead = simd_dot(j[k.wrist] - j[k.shoulder], simd_normalize(headward)) / arm
        }
        let lr = j[4] - j[1]
        if simd_length(lr) > 1e-8 {
            let u = simd_normalize(lr)
            let ankleGap = simd_dot(j[6] - j[3], u)
            if abs(ankleGap) > 1e-6 { s.kneeAnkleGapRatio = simd_dot(j[5] - j[2], u) / ankleGap }
        }
        // NaN joints (partial3D) give NaN metrics: drop them, keep the rest.
        for key in [\FormFrameSample.elbow, \.knee, \.hipAngle, \.torso, \.hipDeviation, \.headDeviation,
                    \.wristAhead, \.elbowBehind, \.kneeAnkleGapRatio] where s[keyPath: key]?.isFinite == false {
            s[keyPath: key] = nil
        }
    }

    /// Rolling-median shoulder ratio vs the cutoff, with hysteresis. For the row the first "not
    /// side" queues setup_side_view once per session (셋업: said once, like the per-rep setup rule).
    private func updateSideView(_ sample: FormFrameSample) {
        guard let ratio = sample.shoulderRatio else { return }
        shoulderRatios.append(ratio)
        if shoulderRatios.count > common.sideViewWindowFrames { shoulderRatios.removeFirst() }
        guard shoulderRatios.count >= common.sideViewMinFrames, let median = Self.median(shoulderRatios) else { return }
        let cut = exercise == .pushUp ? pushUp.sideViewMaxShoulderRatio : row.sideViewMaxShoulderRatio
        let h = common.sideViewHysteresis
        let next = switch sideView {
        case nil: median <= cut
        case true?: median <= cut + h
        case false?: median < cut - h
        }
        if exercise == .barbellRow, next == false, !sideViewGuided, reports.isEmpty {
            sideViewGuided = true
            emit(FormFeedbackEvent(key: "setup_side_view", n: nil))
        }
        sideView = next
    }

    func beginRep() {
        repOpen = true
        repFrames = []
        repFrames3D = []
        recordCurrentFrame()
    }

    func recordCurrentFrame() {
        guard let current, repFrames.last?.frame != current.frame else { return }
        repFrames.append(current)
        if let current3D { repFrames3D.append(current3D) }
        lastRecordedFrame = current.frame
    }

    /// Call when the evaluator counts the rep; the report's `warnings` go into the rep summary.
    @discardableResult
    func finishRep(repIndex: Int) -> FormRepReport {
        recordCurrentFrame()
        repOpen = false
        let frames = repFrames, frames3D = repFrames3D
        repFrames = []
        repFrames3D = []
        let metrics = metrics2D(frames, isFirstRep: reports.isEmpty)
        let fired2D = judge(metrics, history: repMetrics, repIndex: repIndex)
        repMetrics.append(metrics)
        if repMetrics.count > 100 { repMetrics.removeFirst() }
        // 3D: the same aggregation and rules on the 3D samples, with its own baseline history.
        var states: [String: Int] = [:]
        for f in frames { states[f.state3D?.rawValue ?? "none", default: 0] += 1 }
        let enough3D = !frames.isEmpty && Double(frames3D.count) >= common.min3DRepFraction * Double(frames.count)
        var metrics3D: [String: Double] = [:]
        var fired3D: [String]?
        if !frames3D.isEmpty {
            metrics3D = metrics2D(frames3D, isFirstRep: repMetrics3D.isEmpty)
        }
        if enough3D {
            fired3D = judge(metrics3D, history: repMetrics3D, repIndex: repIndex)
            repMetrics3D.append(metrics3D)
            if repMetrics3D.count > 100 { repMetrics3D.removeFirst() }
        }
        let formSource = !common.form3DRequired ? "2d" : (fired3D == nil ? "3d_unavailable" : "3d")
        let fired = common.form3DRequired ? (fired3D ?? []) : fired2D
        for key in fired {
            warningRepCounts[key, default: 0] += 1
            setWarningRepCounts[key, default: 0] += 1
        }
        let spoken = deliver(fired, repIndex: repIndex,
                             judged: judgedForPraise(frames: frames, metrics: common.form3DRequired ? metrics3D : metrics,
                                                     judged3D: fired3D != nil))
        let sides = frames.map(\.side)
        let report = FormRepReport(
            exercise: exercise,
            repIndex: repIndex,
            startFrame: frames.first?.frame ?? -1,
            endFrame: frames.last?.frame ?? -1,
            side: (sides.filter { $0 == .left }.count * 2 >= sides.count ? FormSide.left : .right).rawValue,
            metrics2D: metrics,
            metrics3D: metrics3D,
            frames3D: frames.filter(\.has3D).count,
            bad3DFrames: frames.filter(\.bad3D).count,
            warnings: fired,
            spoken: spoken,
            warnings2D: fired2D,
            warnings3D: fired3D,
            formSource: formSource,
            states3D: states
        )
        reports.append(report)
        if reports.count > 100 { reports.removeFirst() }
        return report
    }

    // MARK: Delivery

    /// Set end (Flutter `endSet`): queues one scope "set" event per 참고 key that fired in the set
    /// (n = its reps in the set, rule order) and returns the set's per-key rep counts, then clears them.
    @discardableResult
    func endSet() -> [String: Int] {
        let counts = setWarningRepCounts
        setWarningRepCounts = [:]
        for (key, grade) in Self.rules[exercise] ?? [] where grade == .reference {
            if let n = counts[key] { emit(FormFeedbackEvent(key: key, n: n, scope: .set)) }
        }
        return counts
    }

    /// The rep was judged on usable data, so "nothing fired" means good form, not "unknown": the judgement came from
    /// the required source (3D when form3DRequired), every frame was fully usable (3D ok — no warming up, tracking lost,
    /// bad or partial 3D; 2D: required joints visible) and the exercise's key metrics exist.
    private func judgedForPraise(frames: [FormFrameSample], metrics: [String: Double], judged3D: Bool) -> Bool {
        guard !frames.isEmpty, let needed = Self.praiseMetrics[exercise], needed.allSatisfy({ metrics[$0] != nil }) else { return false }
        if common.form3DRequired { return judged3D && frames.allSatisfy { $0.state3D == .ok } }
        return frames.allSatisfy(\.requiredOK)
    }

    /// Picks the one key said after this rep and queues it (scope "rep"). A rep judged on usable data with nothing fired
    /// gets praise_good (not on a rep that said a warning or praise_fixed, at most once per `cooldownReps` + 1 reps).
    private func deliver(_ fired: [String], repIndex: Int, judged: Bool = false) -> String? {
        let eligible = fired.filter { key in
            let grade = Self.grade(of: key)
            guard grade != .reference, common.enabledFeedbackKeys.contains(key) else { return false }
            if let last = lastSpokenRep[key], repIndex - last <= common.cooldownReps { return false }
            return grade != .improve || previousFired.contains(key)
        }
        var spoken = eligible.min { Self.grade(of: $0) < Self.grade(of: $1) }  // stable: first in rule order
        if let key = spoken {
            lastSpokenRep[key] = repIndex
            // n only for set scope: rep-scope lines have no {n}, and the app adds `n ?? 1` per event to feedbackCounts.
            emit(FormFeedbackEvent(key: key, n: nil))
        } else if let last = previousSpoken, !fired.contains(last), common.enabledFeedbackKeys.contains("praise_fixed") {
            spoken = "praise_fixed"
            emit(FormFeedbackEvent(key: "praise_fixed", n: nil))
        } else if judged, fired.isEmpty, common.enabledFeedbackKeys.contains("praise_good"),
                  lastSpokenRep["praise_good"].map({ repIndex - $0 > common.cooldownReps }) ?? true {
            spoken = "praise_good"
            lastSpokenRep["praise_good"] = repIndex
            emit(FormFeedbackEvent(key: "praise_good", n: nil))
        }
        previousFired = Set(fired)
        previousSpoken = spoken == "praise_fixed" || spoken == "praise_good" ? nil : spoken
        return spoken
    }

    /// setup_full_body before the first rep, tracking_lost once the set has started: once per run of
    /// frames missing a required joint. tracking_lost waits until no rep is open (an abandoned rep
    /// stops recording frames, so it no longer counts as open).
    private func updateTracking(_ sample: FormFrameSample) {
        guard !sample.requiredOK else {
            missingRun = 0
            trackingLostSent = false
            return
        }
        missingRun += 1
        let inRep = repOpen && lastRecordedFrame == sample.frame - 1
        let started = !reports.isEmpty || inRep
        if started {
            if missingRun >= common.trackingLostFrames, !trackingLostSent, !inRep {
                trackingLostSent = true
                emit(FormFeedbackEvent(key: "tracking_lost", n: nil))
            }
        } else if missingRun == common.setupFullBodyFrames {
            emit(FormFeedbackEvent(key: "setup_full_body", n: nil))
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
        // Bench: lying, the bench hides the legs. Deadlift: same chain as the squat. 임시값 — 테스트 영상으로 조정
        case .benchPress: [j.shoulder, j.elbow, j.wrist]
        case .deadlift: [j.shoulder, j.hip, j.knee, j.ankle]
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
        let torso = FormGeometry.unwrapDegrees(vals(\.torso))
        put("torso_min", torso.min())
        put("torso_max", torso.max())
        put("torso_mean", torso.isEmpty ? nil : FormGeometry.wrapDegrees(torso.reduce(0, +) / Double(torso.count)))
        put("hip_dev_min", vals(\.hipDeviation).min())
        put("hip_dev_max", vals(\.hipDeviation).max())
        if let head0 = firstValue(\.headDeviation) {
            put("head_dev_change_min", vals(\.headDeviation).min().map { $0 - head0 })
            put("head_dev_change_max", vals(\.headDeviation).max().map { $0 - head0 })
        }
        put("elbow_behind_max", vals(\.elbowBehind).max())

        /// Hips-first: torso angle rise and hip vs shoulder rise speed over `windowFrames` after frames[b].
        func putHipsFirst(from b: Int, windowFrames: Int) {
            let bottom = frames[b]
            let window = frames[b...].prefix(windowFrames + 1)
            if let t0 = bottom.torso, let rise = vals(\.torso, window).map({ FormGeometry.wrapDegrees($0 - t0) }).max() {
                put("hips_first_torso_rise", rise)
            }
            if let end = window.last(where: { $0.hipY != nil && $0.shoulderY != nil }),
               let h0 = bottom.hipY, let s0 = bottom.shoulderY, let length = bottom.torsoLength,
               end.frame > bottom.frame {
                let dt = Double(end.frame - bottom.frame)
                put("hips_first_hip_rise_speed", (h0 - end.hipY!) / length / dt)
                put("hips_first_shoulder_rise_speed", (s0 - end.shoulderY!) / length / dt)
            }
        }

        switch exercise {
        case .pushUp:
            // pushup_hand_position: first rep, most extended (top) frame.
            if isFirstRep, let top = frames.filter({ $0.elbow != nil }).max(by: { $0.elbow! < $1.elbow! }) {
                put("first_rep_top_wrist_ahead", top.wristAhead)
            }
        case .squat:
            let kneeMin = vals(\.knee).min()
            if let b = frames.firstIndex(where: { $0.knee != nil && $0.knee == kneeMin }) {
                put("torso_at_bottom", frames[b].torso)
                putHipsFirst(from: b, windowFrames: squat.hipsFirstWindowFrames)
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
                    let d = abs(FormGeometry.wrapDegrees(a - e0.headAngle!))
                    return d <= row.shrugMaxHeadAngleChangeDegrees
                }
                if let low = kept.compactMap(\.earShoulder).min() { put("ear_shoulder_drop", 1 - low / start) }
            }
        case .benchPress:
            // bench_hips_up: hip rise vs the rep start (image y down), over the rep-start torso length.
            if let start = frames.first(where: { $0.hipY != nil && $0.torsoLength != nil }), let top = vals(\.hipY).min() {
                put("hip_lift_max", (start.hipY! - top) / start.torsoLength!)
            }
        case .deadlift:
            // Lowest hip before the lockout (max hip angle) = start of the pull.
            let lockout = frames.indices.filter { frames[$0].hipAngle != nil }.max { frames[$0].hipAngle! < frames[$1].hipAngle! }
            let pull = frames[..<(lockout ?? frames.endIndex)]
            if let b = pull.indices.filter({ pull[$0].hipY != nil }).max(by: { pull[$0].hipY! < pull[$1].hipY! }) {
                putHipsFirst(from: b, windowFrames: deadlift.hipsFirstWindowFrames)
            }
        }
        return m
    }

    static func median(_ values: [Double]) -> Double? {
        let v = values.sorted()
        guard !v.isEmpty else { return nil }
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }

    // MARK: Rules (run on the 2D metrics and, separately, on the same metrics measured in 3D)

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
            // The gate already said it (updateSideView) when it decided before this first rep.
            fire("setup_side_view", firstRep && !sideView && !sideViewGuided)
            guard sideView else { break }
            let c = row
            if let lo = m["torso_min"], let hi = m["torso_max"] { fire("row_torso_swing", hi - lo > c.torsoSwingRangeDegrees) }
            // More upright = smaller forward torso angle.
            if let v = m["torso_mean"], history.count >= common.baselineRepCount,
               let b = Self.median(history.prefix(common.baselineRepCount).compactMap { $0["torso_mean"] }) {
                fire("row_standing_up", FormGeometry.wrapDegrees(b - v) > c.standingUpDegrees)
            }
            if let v = m["elbow_behind_max"], history.count >= common.baselineRepCount,
               let b = Self.median(history.prefix(common.baselineRepCount).compactMap { $0["elbow_behind_max"] }) {
                fire("row_short_pull", b - v > c.shortPullBelowBaseline)
            }
            if c.shrugEnabled { fire("row_shrug", over("ear_shoulder_drop", c.shrugEarShoulderDrop)) }
            fire("row_head_up", under("head_dev_change_min", -c.headUpDeviation))
        case .benchPress:
            fire("setup_side_view", firstRep && !sideView)
            guard sideView else { break }
            let c = bench
            fire("bench_hips_up", over("hip_lift_max", c.hipLiftRatio))
            fire("bench_shallow", overBaseline("elbow_min", c.shallowOverBaselineDegrees))
            fire("bench_no_lockout", belowSetMax("elbow_max", c.noLockoutBelowSetMaxDegrees))
        case .deadlift:
            fire("setup_side_view", firstRep && !sideView)
            guard sideView else { break }
            let c = deadlift
            if let rise = m["hips_first_torso_rise"], let hip = m["hips_first_hip_rise_speed"],
               let shoulder = m["hips_first_shoulder_rise_speed"] {
                fire("deadlift_hips_first", rise > c.hipsFirstTorsoRiseDegrees && hip > shoulder)
            }
            fire("deadlift_no_lockout", belowSetMax("hip_angle_max", c.noLockoutBelowSetMaxDegrees) == true
                 || belowSetMax("knee_max", c.noLockoutBelowSetMaxDegrees) == true)
            fire("deadlift_lean_back", under("torso_min", -c.leanBackDegrees))
        }
        return (Self.rules[exercise] ?? []).map(\.key).filter(fired.contains)
    }
}

// MARK: - Overlay: live posture colour (display only)

/// A body edge the camera overlay draws (COCO17, lower index first). No face, head or neck: head rules are judged and
/// voiced but have no segment to colour.
enum OverlaySegment: Hashable {
    case edge(Int, Int)

    /// Shoulders, arms, trunk sides, hips, legs.
    static let edges: [OverlaySegment] = [[5, 6], [5, 7], [7, 9], [6, 8], [8, 10], [5, 11], [6, 12], [11, 12],
                                          [11, 13], [13, 15], [12, 14], [14, 16]].map { OverlaySegment.edge($0[0], $0[1]) }
}

/// When a rule's per-frame quantity means something. Rep-extremum rules (depth, lockout, peak pull) only near their
/// phase; elsewhere the rule does not apply.
enum OverlayPhase {
    case always, inRep, bottom, top, bottomOrAscending, ascending

    func matches(_ phase: String, repOpen: Bool) -> Bool {
        switch self {
        case .always: true
        case .inRep: repOpen
        case .bottom: phase == "bottom"
        case .top: phase == "top"
        case .bottomOrAscending: phase == "bottom" || phase == "ascending"
        case .ascending: phase == "ascending"
        }
    }
}

/// A rule's quantity on one frame: not applicable here (view, no baseline yet → plain green), unknown (the joints it
/// needs are partial / low confidence → dim green), or a value.
enum OverlayValue {
    case notApplicable, unknown
    case value(Double)

    static func measured(_ v: Double?) -> OverlayValue { v.map { $0.isFinite ? .value($0) : .unknown } ?? .unknown }

    var number: Double? {
        if case let .value(v) = self { return v }
        return nil
    }
}

/// One table for the overlay colour: rule → segments (judged side) → per-frame quantity → normal (severity 0) and the
/// rule's own threshold (severity 1, read from the tracker config, so a threshold change moves the colour with it).
/// severity = clamp((value − normal) / (threshold − normal), 0, 1). Display only: judge() does not read this.
/// `normal` is the ideal value (a straight line, no change, the baseline), except valgus: knees 25% wider than the
/// ankles (display anchor, 제안값). Not coloured: head rules (no head is drawn), trend rules (depth_fade, lean_drift),
/// setup rules (hand_position, side view) and rules that are off (heel_rise, shrug).
struct OverlayRule {
    let key: String
    let phase: OverlayPhase
    let segments: (FormSide) -> [OverlaySegment]
    let normal: Double
    let threshold: (FormWarningTracker) -> Double
    let value: (FormWarningTracker, FormFrameSample) -> OverlayValue

    static func severity(_ value: Double, normal: Double, threshold: Double) -> Double {
        guard threshold != normal else { return 0 }
        return min(max((value - normal) / (threshold - normal), 0), 1)
    }

    private static func side(_ s: FormSide) -> FormGeometry.SideJoints { FormGeometry.joints(s) }
    private static func trunk(_ s: FormSide) -> [OverlaySegment] { let j = side(s); return [.edge(j.shoulder, j.hip)] }
    private static func arm(_ s: FormSide) -> [OverlaySegment] {
        let j = side(s); return [.edge(j.shoulder, j.elbow), .edge(j.elbow, j.wrist)]
    }
    private static func thigh(_ s: FormSide) -> [OverlaySegment] { let j = side(s); return [.edge(j.hip, j.knee)] }
    private static func leg(_ s: FormSide) -> [OverlaySegment] { let j = side(s); return [.edge(j.hip, j.knee), .edge(j.knee, j.ankle)] }
    /// Squat side-view rules do not apply in a front view (judge()), valgus only there.
    private static func sideOnly(_ s: FormFrameSample, _ v: () -> OverlayValue) -> OverlayValue { s.frontView == true ? .notApplicable : v() }

    static let table: [FormExercise: [OverlayRule]] = [
        .pushUp: [
            OverlayRule(key: "pushup_hip_sag", phase: .always, segments: { trunk($0) + leg($0) }, normal: 0,
                        threshold: { $0.pushUp.hipSagDeviation }, value: { _, s in .measured(s.hipDeviation) }),
            OverlayRule(key: "pushup_hip_pike", phase: .always, segments: { trunk($0) + leg($0) }, normal: 0,
                        threshold: { -$0.pushUp.hipPikeDeviation }, value: { _, s in .measured(s.hipDeviation) }),
            OverlayRule(key: "pushup_shallow", phase: .bottom, segments: { arm($0) }, normal: 0,
                        threshold: { $0.pushUp.shallowOverBaselineDegrees },
                        value: { t, s in t.liveOverBaseline("elbow_min", s.elbow) }),
            OverlayRule(key: "pushup_no_lockout", phase: .top, segments: { arm($0) }, normal: 0,
                        threshold: { $0.pushUp.noLockoutBelowSetMaxDegrees },
                        value: { t, s in t.liveBelowSetMax("elbow_max", \.elbow, s.elbow) }),
        ],
        .squat: [
            OverlayRule(key: "squat_knee_valgus", phase: .bottomOrAscending, segments: { _ in
                [.edge(11, 13), .edge(13, 15), .edge(12, 14), .edge(14, 16)] }, normal: 1.25,
                        threshold: { $0.squat.valgusKneeAnkleGapRatio },
                        value: { _, s in s.frontView == true ? .measured(s.kneeAnkleGapRatio) : .notApplicable }),
            OverlayRule(key: "squat_shallow", phase: .bottom, segments: { leg($0) }, normal: 0,
                        threshold: { $0.squat.shallowOverBaselineDegrees },
                        value: { t, s in sideOnly(s) { t.liveOverBaseline("knee_min", s.knee) } }),
            OverlayRule(key: "squat_no_lockout", phase: .top, segments: { trunk($0) + leg($0) }, normal: 0,
                        threshold: { $0.squat.noLockoutBelowSetMaxDegrees },
                        value: { t, s in sideOnly(s) {
                            let k = t.liveBelowSetMax("knee_max", \.knee, s.knee), h = t.liveBelowSetMax("hip_angle_max", \.hipAngle, s.hipAngle)
                            return [k, h].compactMap(\.number).max().map { .value($0) } ?? .unknown
                        } }),
            OverlayRule(key: "squat_hips_first", phase: .ascending, segments: { trunk($0) + thigh($0) }, normal: 0,
                        threshold: { $0.squat.hipsFirstTorsoRiseDegrees },
                        value: { t, s in sideOnly(s) { t.liveTorsoRiseSinceBottom(s) } }),
        ],
        .barbellRow: [
            OverlayRule(key: "row_torso_swing", phase: .inRep, segments: { trunk($0) }, normal: 0,
                        threshold: { $0.row.torsoSwingRangeDegrees }, value: { t, s in t.liveTorsoRange(s) }),
            OverlayRule(key: "row_standing_up", phase: .inRep, segments: { trunk($0) }, normal: 0,
                        threshold: { $0.row.standingUpDegrees },
                        value: { t, s in t.liveFromBaseline("torso_mean", s.torso) { b, v in FormGeometry.wrapDegrees(b - v) } }),
            OverlayRule(key: "row_short_pull", phase: .top, segments: { arm($0) }, normal: 0,
                        threshold: { $0.row.shortPullBelowBaseline },
                        value: { t, s in t.liveFromBaseline("elbow_behind_max", s.elbowBehind) { b, v in b - v } }),
        ],
    ]
}

/// The overlay's view of one frame: severities of the segments that have a measured rule, and the segments whose
/// quantities are unknown (dim green). Every other drawn segment is plain green (no issue / rule not applicable).
struct OverlayState {
    var severity: [OverlaySegment: Double] = [:]
    var uncertain: Set<OverlaySegment> = []
}

extension FormWarningTracker {
    /// Live posture state for the frame just observed, from the same source the warnings come from (the 3D sample when
    /// form3DRequired, else 2D). No usable 3D this frame (warming up, tracking lost, bad 3D) → every segment uncertain.
    func liveSeverity() -> OverlayState {
        var out = OverlayState()
        guard let s = common.form3DRequired ? current3D : current, let side else {
            out.uncertain = Set(OverlaySegment.edges)
            return out
        }
        // judge()'s side-view gate (row: the session gate once decided; otherwise this frame's view): nothing applies.
        if exercise == .pushUp || exercise == .barbellRow,
           !((exercise == .barbellRow ? sideView : nil) ?? (s.frontView != true)) { return out }
        var unknown: Set<OverlaySegment> = []
        for rule in OverlayRule.table[exercise] ?? [] where rule.phase.matches(s.phase, repOpen: repOpen) {
            switch rule.value(self, s) {
            case .notApplicable: continue
            case .unknown: unknown.formUnion(rule.segments(side))
            case let .value(v):
                let severity = OverlayRule.severity(v, normal: rule.normal, threshold: rule.threshold(self))
                for seg in rule.segments(side) { out.severity[seg] = max(out.severity[seg] ?? 0, severity) }
            }
        }
        out.uncertain = unknown.subtracting(out.severity.keys)  // a measured rule on the segment wins
        return out
    }

    private var liveRepFrames: [FormFrameSample] { common.form3DRequired ? repFrames3D : repFrames }
    private var liveHistory: [[String: Double]] { common.form3DRequired ? repMetrics3D : repMetrics }

    /// judge()'s baseline: median of the first `baselineRepCount` reps (nil until they exist).
    fileprivate func liveBaseline(_ name: String) -> Double? {
        guard liveHistory.count >= common.baselineRepCount else { return nil }
        return Self.median(liveHistory.prefix(common.baselineRepCount).compactMap { $0[name] })
    }

    /// f(baseline, live value); no baseline yet → not applicable, no live value → unknown.
    fileprivate func liveFromBaseline(_ name: String, _ value: Double?, _ f: (Double, Double) -> Double) -> OverlayValue {
        guard let b = liveBaseline(name) else { return .notApplicable }
        return .measured(value.map { f(b, $0) })
    }

    fileprivate func liveOverBaseline(_ name: String, _ value: Double?) -> OverlayValue {
        liveFromBaseline(name, value) { b, v in v - b }
    }

    /// belowSetMax: the set's best so far (earlier reps and this rep's frames) minus the live value.
    fileprivate func liveBelowSetMax(_ name: String, _ key: KeyPath<FormFrameSample, Double?>, _ value: Double?) -> OverlayValue {
        guard let value else { return .unknown }
        let best = (liveHistory.compactMap { $0[name] } + liveRepFrames.compactMap { $0[keyPath: key] } + [value]).max() ?? value
        return .measured(best - value)
    }

    /// Torso angle max − min within the rep so far, this frame included (row_torso_swing).
    fileprivate func liveTorsoRange(_ s: FormFrameSample) -> OverlayValue {
        guard let t = s.torso else { return .unknown }
        let torso = FormGeometry.unwrapDegrees(liveRepFrames.compactMap(\.torso) + [t])
        return .measured((torso.max() ?? t) - (torso.min() ?? t))
    }

    /// Torso rise since the rep's deepest (min knee) frame — squat_hips_first's angle part (its hip-faster-than-shoulder
    /// part is not shown).
    fileprivate func liveTorsoRiseSinceBottom(_ s: FormFrameSample) -> OverlayValue {
        let frames = liveRepFrames.filter { $0.knee != nil }
        guard let bottom = frames.min(by: { $0.knee! < $1.knee! }), let t0 = bottom.torso else { return .notApplicable }
        return .measured(s.torso.map { FormGeometry.wrapDegrees($0 - t0) })
    }
}

/// Display-only smoothing of the overlay colour: severity (time constant `tau`, ~200 ms) and opacity (1 = measured or
/// not applicable, `dimOpacity` = uncertain). An uncertain segment snaps to severity 0 (dim green, never red).
struct OverlaySeverityTrack {
    var tau = 0.2
    var dimOpacity = 0.4
    private var shown: [OverlaySegment: (severity: Double, opacity: Double)] = [:]
    private var last: Double?

    /// Every drawn segment → (severity, opacity) to draw.
    mutating func update(_ state: OverlayState, at now: Double) -> [OverlaySegment: (severity: Double, opacity: Double)] {
        let dt = last.map { min(max(now - $0, 0), 1) } ?? 0
        last = now
        let a = 1 - exp(-dt / tau)
        for seg in OverlaySegment.edges {
            let uncertain = state.uncertain.contains(seg)
            let target = (severity: uncertain ? 0 : state.severity[seg] ?? 0, opacity: uncertain ? dimOpacity : 1.0)
            let old = shown[seg] ?? target
            shown[seg] = (severity: uncertain ? 0 : old.severity + a * (target.severity - old.severity),
                          opacity: old.opacity + a * (target.opacity - old.opacity))
        }
        return shown
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

// MARK: - Ready pose (first rep)

/// Pre-set motion guard: the first rep may start only after the start pose has been held still —
/// stable status = start pose and the evaluator's motion signal within `tolerance` of where the run
/// began — for `holdFrames` frames (~1 s; scale with the frame rate). Stays armed afterwards.
/// `holdFrames == 0` = off (armed from the start).
struct ReadyPoseGate {
    var holdFrames: Int
    var tolerance: Double
    private var anchor: Double?
    private var run = 0
    private(set) var armed: Bool

    init(holdFrames: Int, tolerance: Double) {
        self.holdFrames = holdFrames
        self.tolerance = tolerance
        armed = holdFrames <= 0
    }

    mutating func update(atStartPose: Bool, value: Double?) {
        guard !armed else { return }
        guard atStartPose, let value else {
            anchor = nil
            run = 0
            return
        }
        if let anchor, abs(value - anchor) <= tolerance {
            run += 1
        } else {
            anchor = value
            run = 1
        }
        armed = run >= holdFrames
    }
}
