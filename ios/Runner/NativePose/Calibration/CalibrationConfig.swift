import Foundation

/// Every threshold the calibration judging engine uses.
///
/// Nothing in `CalibrationEngine` hardcodes a number. Values are the starting point for
/// real-device tuning; `debug_frames.csv` in each session folder records what they see.
struct CalibrationConfig {
    struct Device {
        var maxRollDeg: Double = 3.0
        var maxPitchDeg: Double = 12.0
        var maxUserAccelerationG: Double = 0.04
        var maxRotationRateRadPerSec: Double = 0.08
    }

    struct Framing {
        var minKeypointConfidence: Double = 0.3
        /// The outline on the capture screen *is* this target: drawn this tall (in buffer
        /// heights, head top to feet as measured below), centred, standing on the user's feet.
        /// Passing the size and centre gates means the user fills the outline, so the screen
        /// never says "good" while the outline and the body disagree.
        var guideBodyHeight: Double = 0.62
        var bodyHeightTolerance: Double = 0.07
        var minBodyHeight: Double { guideBodyHeight - bodyHeightTolerance }
        var maxBodyHeight: Double { guideBodyHeight + bodyHeightTolerance }
        var minHeadTop: Double = 0.02
        var maxFeet: Double = 0.98
        var maxCentreOffset: Double = 0.06
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

    /// Which way the body faces comes from geometry (RTMPose) plus face detection (Vision).
    ///
    /// RTMPose keypoint scores are not visibility: from behind it still scores the ears
    /// 0.5–1.0 and the face 0.55–0.85, so nothing here thresholds them.
    struct ViewClassification {
        /// Front: a face looking at the camera, nose over the shoulder midline.
        var frontMaxFaceYawDeg: Double = 20
        var frontMaxNoseOffset: Double = 0.08

        /// ±60°: r in this band, nose swung off the midline, face still visible.
        /// r reads wider than |cos yaw| on real bodies (RTMPose puts the hidden far shoulder and
        /// hip on the outline): six held ~50–60° views of three People Snapshot subjects gave
        /// r 0.48–0.74 with Vision head yaw 41–71°, so the upper bound is 0.75 rather than cos 48°.
        var obliqueMinR: Double = 0.31
        var obliqueMaxR: Double = 0.75
        var obliqueMinDelta: Double = 0.12
        /// A face this close to frontal on an oblique body means the head turned back to the camera.
        var turnedHeadMaxFaceYawDeg: Double = 20

        /// Back: no face, shoulders and hips back to (nearly) full width. On the People Snapshot
        /// replays, faceless frames at 165–195° had r ≥ 0.90 in 97% of cases, while back-obliques
        /// (120–150°, 210–240°) reached 0.90 in only 19% (0.80 let half of them through).
        var backMinR: Double = 0.90

        /// r = shoulderWeight * (sw/T)/ref_s + (1 - shoulderWeight) * (hw/T)/ref_h
        var shoulderWeight: Double = 0.6
    }

    struct Capture {
        /// Torso lengths / second; equivalent to the former 0.015/frame at 30 Hz.
        /// A rate conversion, not a newly validated real-device threshold.
        var maxMotionPerSecond: Double = 0.45
        var maxFrameGap: Double = 0.25
        var minimumHoldSamples: Int = 5
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
