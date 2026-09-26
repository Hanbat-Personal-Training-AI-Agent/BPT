import Foundation

/// Every threshold the calibration judging engine uses.
///
/// Nothing in `CalibrationEngine` hardcodes a number: the values below are the
/// starting point from the spec and are expected to be tuned on a real device.
struct CalibrationConfig {
    struct Device {
        var maxRollDeg: Double = 3.0
        var maxPitchDeg: Double = 12.0
        var maxUserAccelerationG: Double = 0.04
        var maxRotationRateRadPerSec: Double = 0.08
    }

    struct Framing {
        var minKeypointConfidence: Double = 0.3
        var maxBodyHeight: Double = 0.82
        var minBodyHeight: Double = 0.60
        var minHeadTop: Double = 0.02
        var maxFeet: Double = 0.98
        var maxCentreOffset: Double = 0.10
        /// Head top sits this many torso lengths above the shoulder midpoint.
        var headTopTorsoFactor: Double = 0.75
        /// Soles sit this many torso lengths below the lowest ankle.
        var feetTorsoFactor: Double = 0.06
    }

    struct Stance {
        var maxFeetDrift: Double = 0.03
        var maxCentreDrift: Double = 0.08
    }

    struct APose {
        var maxWristDrop: Double = 0.97
        var minWristDrop: Double = 0.60
        var minElbowRatio: Double = 0.38
        var maxElbowRatio: Double = 0.75
        /// Front view only: horizontal distance from the body centre to the nearer wrist, in torso lengths.
        var minWristReach: Double = 0.8
        var minAnkleGapOverHipWidth: Double = 0.9
        var maxAnkleGapOverHipWidth: Double = 2.6
    }

    struct ViewClassification {
        var frontMinFace: Double = 0.5
        var frontMaxNoseOffset: Double = 0.08
        var frontMaxEarDifference: Double = 0.25

        var obliqueMinFace: Double = 0.4
        var obliqueMinR: Double = 0.31
        var obliqueMaxR: Double = 0.67
        var obliqueMinDelta: Double = 0.12
        var obliqueNearEarMin: Double = 0.5
        var obliqueFarEarMax: Double = 0.3
        /// Both ears this visible inside the oblique r band means the head is turned back to the camera.
        var turnedHeadEarMin: Double = 0.4

        var backMaxFace: Double = 0.35
        var backFaceRefFactor: Double = 0.5
        var backMaxEar: Double = 0.3
        var backMinR: Double = 0.85

        /// r = shoulderWeight * (sw/T)/ref_s + (1 - shoulderWeight) * (hw/T)/ref_h
        var shoulderWeight: Double = 0.6
    }

    struct Capture {
        var maxMotion: Double = 0.015
        var holdDuration: Double = 0.8
        var cooldown: Double = 1.5
        var viewTimeout: Double = 30.0
        var jpegQuality: Double = 0.95
    }

    struct Voice {
        var repeatIntervalMin: Double = 3.0
        var repeatIntervalMax: Double = 4.5
        var beepIntervalMax: Double = 0.9
        var beepIntervalMin: Double = 0.15
    }

    var device = Device()
    var framing = Framing()
    var stance = Stance()
    var aPose = APose()
    var view = ViewClassification()
    var capture = Capture()
    var voice = Voice()

    static let `default` = CalibrationConfig()
}
