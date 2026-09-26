import Foundation

/// The four capture directions, in the order the guidance recommends walking through them.
///
/// Yaw is counter-clockwise seen from above (the user turning to their own left is positive),
/// 0 = facing the camera. `leftfront` shows the user's left-front side, i.e. they turned right.
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

    var koreanName: String {
        switch self {
        case .front: return "정면"
        case .leftfront: return "왼쪽 옆면"
        case .rightfront: return "오른쪽 옆면"
        case .back: return "뒷면"
        }
    }

    /// One continuous turn: front, then keep turning the same way.
    static let recommendedOrder: [CalibrationView] = [.front, .leftfront, .back, .rightfront]
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

struct CalibrationFrame {
    var keypoints: [CalibrationKeypoint]
    /// width / height of the judged buffer; horizontal distances are multiplied by it to become height units.
    var aspect: Double
    var timestamp: TimeInterval
    var device: CalibrationDeviceState
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
    case keepTurning
    case turnedTooFar
    case faceForwardWithBody
    case holdStill
    case captured(CalibrationView)
    case finished

    var message: String {
        switch self {
        case .holdPhoneUpright: return "휴대폰을 세로로 똑바로 세워주세요"
        case .holdPhoneStill: return "휴대폰을 고정해주세요"
        case .stepIntoFrame: return "화면 안으로 들어와 주세요"
        case .showFullBody: return "머리부터 발끝까지 보이게 서주세요"
        case .stepBack: return "뒤로 물러나주세요"
        case .stepForward: return "앞으로 와주세요"
        case .moveLeft: return "왼쪽으로 이동해주세요"
        case .moveRight: return "오른쪽으로 이동해주세요"
        case .moveToCentre: return "화면 가운데로 이동해주세요"
        case .returnToStart: return "처음 자리로 돌아와 주세요"
        case .openArmsWider: return "팔을 몸에서 더 벌려 A자를 만들어주세요"
        case .lowerArms: return "팔을 조금 내려주세요"
        case .straightenElbows: return "팔꿈치를 펴주세요"
        case .widenFeet: return "발을 어깨너비로 벌려주세요"
        case .keepTurning: return "천천히 계속 돌아주세요"
        case .turnedTooFar: return "너무 돌았어요, 살짝 돌아오세요"
        case .faceForwardWithBody: return "고개는 몸과 같은 방향으로, 시선만 화면으로 봐주세요"
        case .holdStill: return "그대로 멈춰주세요"
        case .captured(let view): return "\(view.koreanName) 촬영 완료"
        case .finished: return "촬영이 모두 끝났어요"
        }
    }

    /// Spoken immediately, cutting off whatever is being said.
    var interrupts: Bool {
        switch self {
        case .captured, .finished, .returnToStart: return true
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
