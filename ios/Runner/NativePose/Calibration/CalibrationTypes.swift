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
        case .front: return "이제 왼쪽으로 천천히 돌아 줘"
        case .rightfront: return "계속 돌아서 등을 보여 줘"
        case .back: return "거의 다 왔어! 계속 천천히 돌아 줘"
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

    static let still = CalibrationDeviceState()
}

/// Face detection result for the frame (Apple Vision). This, not RTMPose's face/ear scores,
/// is what tells "facing the camera" from "back to the camera".
struct CalibrationFace: Equatable {
    var isDetected: Bool
    /// Head yaw relative to the camera; magnitude only is used, so the sign convention does not matter.
    var yawDeg: Double?

    static let none = CalibrationFace(isDetected: false, yawDeg: nil)
    static let frontal = CalibrationFace(isDetected: true, yawDeg: 0)
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
    case captured(CalibrationView)
    case finished
    /// Played once when one view has not been captured for `viewTimeout` seconds.
    case timeoutSummary

    /// Kori's voice (the app's goose mascot): casual 반말, first person, short and upbeat,
    /// "잠깐!" before a correction and "좋아" when it is going well. Shown in the speech bubble
    /// and read out by the TTS, so every line has to work spoken as well as written.
    var message: String {
        switch self {
        case .holdPhoneUpright: return "폰이 기울었어! 세로로 똑바로 세워 줘"
        case .holdPhoneStill: return "폰이 흔들려! 꽉 고정해 줘"
        case .stepIntoFrame: return "어디 있어? 화면 안으로 들어와 줘!"
        case .showFullBody: return "머리부터 발끝까지 다 보이게 서 줘!"
        case .stepBack: return "너무 가까워! 뒤로 조금만 가 줘"
        case .stepForward: return "조금만 앞으로 와 줘!"
        case .moveLeft: return "왼쪽으로 한 걸음만 가 줘!"
        case .moveRight: return "오른쪽으로 한 걸음만 가 줘!"
        case .moveToCentre: return "화면 가운데로 와 줘!"
        case .returnToStart: return "잠깐! 처음 섰던 자리로 돌아와 줘"
        case .openArmsWider: return "팔을 몸에서 조금 더 떼서 A자로!"
        case .lowerArms: return "팔을 조금만 내려 줘!"
        case .straightenElbows: return "팔꿈치 쭉 펴 줘!"
        case .widenFeet: return "발은 어깨너비로 벌려 줘!"
        case .faceCamera: return "먼저 카메라를 정면으로 봐 줘!"
        case .keepTurning: return "좋아, 천천히 계속 돌아 줘!"
        case .turnedTooFar: return "앗, 너무 돌았어! 살짝만 돌아와 줘"
        case .faceForwardWithBody: return "고개는 몸이랑 같은 방향! 눈만 화면 봐 줘"
        case .holdStill: return "좋아, 그대로 멈춰!"
        case .captured(let view):
            let next = view.nextStepInstruction
            return next.isEmpty ? "\(view.koreanName) 찍었어!" : "\(view.koreanName) 찍었어! \(next)"
        case .finished: return "다 찍었어! 수고했어"
        case .timeoutSummary: return "천천히 해도 돼! 팔은 A자, 발은 제자리, 천천히 돌면 돼"
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
}

struct CalibrationCaptureRequest {
    var view: CalibrationView
    /// Frames from this timestamp onwards are the stillness window to pick the sharpest frame from.
    var holdStartedAt: TimeInterval
    var measurement: CalibrationMeasurement
    var reference: CalibrationReference
    var r: Double?
    var delta: Double?
    var isLastView: Bool
}
