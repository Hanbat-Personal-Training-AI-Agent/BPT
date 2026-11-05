import Foundation

/// The four capture directions.
///
/// Yaw is counter-clockwise seen from above (the user turning to their own left is positive),
/// 0 = facing the camera. The raw value names the side of the body the camera sees, and is
/// the label the fitting pipeline reads from the manifest:
///
/// | view         | yaw  | camera sees             | user was asked to        | UI label |
/// |--------------|------|-------------------------|--------------------------|----------|
/// | `front`      | 0    | front                   | face the camera          | 정면     |
/// | `rightfront` | +60  | right-front side        | turn left                | 왼쪽     |
/// | `back`       | 180  | back                    | keep turning             | 뒷면     |
/// | `leftfront`  | −60  | left-front side         | keep turning (≈ right)   | 오른쪽   |
///
/// The UI names the turn, not the visible side, so "왼쪽" is `rightfront`.
enum CalibrationView: String, CaseIterable {
    case front
    case leftfront
    case rightfront
    case back

    var nominalYawDeg: Double {
        switch self {
        case .front: return 0
        case .leftfront: return -60
        case .rightfront: return 60
        case .back: return 180
        }
    }

    var fileName: String { "view_\(rawValue).jpg" }

    /// Same wording as the capture screen chips (the direction the user turns).
    var koreanName: String {
        switch self {
        case .front: return "정면"
        case .rightfront: return "왼쪽"
        case .back: return "뒷면"
        case .leftfront: return "오른쪽"
        }
    }

    /// What to say right after this view is captured, to send the user to the next one.
    var nextStepInstruction: String {
        switch self {
        case .front: return "왼쪽으로 돌아!"
        case .rightfront: return "계속 돌아서 등 보여 줘!"
        case .back: return "거의 끝! 계속 돌아!"
        case .leftfront: return ""
        }
    }

    /// One continuous turn to the user's left: front, left-oblique, back, right-oblique.
    static let recommendedOrder: [CalibrationView] = [.front, .rightfront, .back, .leftfront]
}

/// COCO-17 keypoint in normalized image coordinates (0...1), unmirrored.
struct CalibrationKeypoint: Equatable {
    var x: Double
    var y: Double
    var score: Double

    init(x: Double, y: Double, score: Double) {
        self.x = x
        self.y = y
        self.score = score
    }
}

enum CocoJoint: Int {
    case nose = 0, leftEye, rightEye, leftEar, rightEar
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle

    /// Shoulders, elbows, wrists, hips, knees and ankles: all must be confident to judge a frame.
    static let required: [CocoJoint] = [
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist,
        .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]
}

/// Device attitude and shake, from CoreMotion.
struct CalibrationDeviceState: Equatable {
    var rollDeg: Double = 0
    var pitchDeg: Double = 0
    var userAccelerationG: Double = 0
    var rotationRateRadPerSec: Double = 0
    var gravity: [Double] = [0, -1, 0]
    var isAvailable: Bool = true
    /// CoreMotion sample time, when available; not assumed equal to camera PTS.
    var timestamp: TimeInterval?

    static let still = CalibrationDeviceState()
}

/// Face detection result for the frame (Apple Vision). This, not RTMPose's face/ear scores,
/// is what tells "facing the camera" from "back to the camera".
struct CalibrationFace: Equatable {
    var isDetected: Bool
    /// Head yaw relative to the camera; magnitude only is used, so the sign convention does not matter.
    var yawDeg: Double?
    /// False means detection failed, not that a successfully searched image has no face.
    var isReliable: Bool = true

    static let none = CalibrationFace(isDetected: false, yawDeg: nil)
    static let frontal = CalibrationFace(isDetected: true, yawDeg: 0)
    static let unknown = CalibrationFace(isDetected: false, yawDeg: nil, isReliable: false)
}

struct CalibrationFrame {
    var keypoints: [CalibrationKeypoint]
    /// width / height of the judged buffer; horizontal distances are multiplied by it to become height units.
    var aspect: Double
    var timestamp: TimeInterval
    var device: CalibrationDeviceState
    var face: CalibrationFace
}

/// Everything measured from one frame, in torso-relative units.
struct CalibrationMeasurement: Equatable {
    var torso: Double
    var shoulderWidth: Double
    var hipWidth: Double
    var headTop: Double
    var feet: Double
    var bodyHeight: Double
    var midX: Double
    var leftWristDrop: Double
    var rightWristDrop: Double
    var leftElbowRatio: Double
    var rightElbowRatio: Double
    var face: Double
    var noseOffset: Double
    /// Unmirrored image: the user's left shoulder sits on the image right while the chest faces the camera.
    var chestTowardsCamera: Bool
    var earLeft: Double
    var earRight: Double
    var wristReach: Double
    var ankleGapOverHipWidth: Double
    var meanRequiredConfidence: Double
}

/// Values captured from the front view that every later view is compared against.
struct CalibrationReference: Equatable {
    var shoulderRatio: Double  // ref_s = sw / T
    var hipRatio: Double       // ref_h = hw / T
    var noseOffset: Double     // o₀
    var feet: Double
    var midX: Double
    var face: Double
}

/// What the user is told, in priority order. The raw value is the Korean line shown and spoken.
enum CalibrationGuidance: Equatable {
    case holdPhoneUpright
    case holdPhoneStill
    case stepIntoFrame
    case showFullBody
    case stepBack
    case stepForward
    case moveLeft
    case moveRight
    case moveToCentre
    case returnToStart
    case openArmsWider
    case lowerArms
    case straightenElbows
    case widenFeet
    case faceCamera
    case keepTurning
    case turnedTooFar
    case faceForwardWithBody
    case holdStill
    case trackingUnavailable
    case saveFailed
    case captured(CalibrationView)
    case finished
    /// Played once when one view has not been captured for `viewTimeout` seconds.
    case timeoutSummary

    /// Kori's voice (the app's goose mascot): casual 반말, first person, short and upbeat,
    /// "잠깐!" before a correction and "좋아" when it is going well. Shown in the speech bubble
    /// and read out by the TTS, so every line has to work spoken as well as written.
    var message: String {
        switch self {
        case .holdPhoneUpright: return "폰 똑바로 세워 줘!"
        case .holdPhoneStill: return "폰 흔들려! 고정해 줘"
        case .stepIntoFrame: return "화면 안으로 들어와!"
        case .showFullBody: return "몸이 다 보여야 해!"
        case .stepBack: return "뒤로 한 걸음!"
        case .stepForward: return "앞으로 한 걸음!"
        case .moveLeft: return "왼쪽으로 한 걸음!"
        case .moveRight: return "오른쪽으로 한 걸음!"
        case .moveToCentre: return "가운데로 와!"
        case .returnToStart: return "처음 자리로 돌아와!"
        case .openArmsWider: return "팔 더 벌려!"
        case .lowerArms: return "팔 조금 내려!"
        case .straightenElbows: return "팔꿈치 쭉 펴!"
        case .widenFeet: return "다리 더 벌려!"
        case .faceCamera: return "카메라 봐 줘!"
        case .keepTurning: return "좋아, 계속 돌아!"
        case .turnedTooFar: return "너무 돌았어! 살짝 돌아와"
        case .faceForwardWithBody: return "고개도 몸이랑 같이 돌려!"
        case .holdStill: return "좋아, 그대로!"
        case .trackingUnavailable: return "잠깐 놓쳤어! 그대로 있어"
        case .saveFailed: return "저장 실패! 공간 확인해 줘"
        case .captured(let view):
            let next = view.nextStepInstruction
            return next.isEmpty ? "\(view.koreanName) 찍었어!" : "\(view.koreanName) 찍었어! \(next)"
        case .finished: return "끝! 수고했어"
        case .timeoutSummary: return "천천히 해도 돼! 팔 벌리고 제자리에서 돌아"
        }
    }

    /// Spoken immediately, cutting off whatever is being said.
    var interrupts: Bool {
        switch self {
        case .captured, .finished, .returnToStart, .timeoutSummary: return true
        default: return false
        }
    }
}

/// When a guidance line may be spoken. The checks run every frame, so the guidance can flip
/// between lines several times a second; speaking each flip came out as rapid-fire chatter.
/// A line waits until it has been the guidance for `settle` seconds and the voice has been quiet
/// for `gap` seconds (`repeatAfter` before the same line again). Interrupting lines skip both.
struct GuidanceSpeechGate {
    var settle: Double
    var gap: Double
    private var candidate: String?
    private var candidateSince = 0.0

    init(settle: Double, gap: Double) {
        self.settle = settle
        self.gap = gap
    }

    /// `quietSince`: when the last line ended (its start while it is still playing).
    mutating func shouldSpeak(_ guidance: CalibrationGuidance, now: Double, isSpeaking: Bool,
                              lastSpoken: String?, quietSince: Double, repeatAfter: Double) -> Bool {
        let message = guidance.message
        if message != candidate {
            candidate = message
            candidateSince = now
        }
        let same = message == lastSpoken
        if guidance.interrupts { return !same || now - quietSince >= repeatAfter }
        guard !isSpeaking, now - candidateSince >= settle else { return false }
        return now - quietSince >= (same ? repeatAfter : gap)
    }
}

/// What the engine decided for one frame.
struct CalibrationEngineOutput {
    var guidance: CalibrationGuidance
    /// The view this frame matches, if any.
    var classifiedView: CalibrationView?
    /// The view the guidance is steering the user towards.
    var targetView: CalibrationView?
    var capturedViews: [CalibrationView]
    /// 0...1 over the stillness hold.
    var holdProgress: Double
    /// True when nothing is blocking the capture except the hold timer.
    var isPassing: Bool
    /// Set on the frame the capture fires; the session writes the image for this view.
    var capture: CalibrationCaptureRequest?
    var measurement: CalibrationMeasurement?
    var didTimeOut: Bool
    /// Identity of the continuous hold; prevents reuse of an earlier hold's best image.
    var holdStartedAt: TimeInterval?
}

struct CalibrationCaptureRequest {
    let id: UUID
    var view: CalibrationView
    /// Frames from this timestamp onwards are the stillness window to pick the best confidence from.
    var holdStartedAt: TimeInterval
    var measurement: CalibrationMeasurement
    var reference: CalibrationReference
    var r: Double?
    var delta: Double?
    var isLastView: Bool
}

/// One frame in flight. The capture queue acquires; the processing queue releases.
final class CalibrationFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false

    func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !busy else { return false }
        busy = true
        return true
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        busy = false
    }
}

/// How far the camera buffer still is from level, so the analysed picture always stands upright.
enum CalibrationRotation {
    /// Clockwise degrees (0/90/180/270) to turn a buffer the connection rotated by `applied` so it matches
    /// the horizon-level angle `horizon` (both AVCaptureConnection.videoRotationAngle values).
    static func residualDegrees(horizon: Double, applied: Double) -> Int {
        guard horizon.isFinite, applied.isFinite else { return 0 }
        return (((Int(((horizon - applied) / 90).rounded()) % 4) + 4) % 4) * 90
    }
}
