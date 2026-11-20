import XCTest
@testable import CalibrationEngineKit

/// Source-contract counterexamples; synthetic metrics are not form ground truth.
final class CriteriaCounterexamplesTests: XCTestCase {
    func testQuietPositiveIsStillJudged() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        let key = "pushup_shallow"
        XCTAssertTrue(FormWarningTracker.quietByDefault.contains(key))
        XCTAssertFalse(tracker.common.enabledFeedbackKeys.contains(key))
        XCTAssertTrue(tracker.judge(["elbow_min": 150, "front_view_fraction": 0],
                                   history: Array(repeating: ["elbow_min": 90], count: 3), repIndex: 4).contains(key))
    }
    func testKnownPositiveSurvivesMissingOtherQuantityButIsNotConfirmedCorrection() {
        let tracker = FormWarningTracker(exercise: .squat)
        var assessed = Set<String>()
        let fired = tracker.judge(["knee_max": 140, "front_view_fraction": 0],
                                  history: [["knee_max": 180]], repIndex: 2, assessed: { assessed = $0 })
        XCTAssertTrue(fired.contains("squat_no_lockout"))
        XCTAssertFalse(assessed.contains("squat_no_lockout"), "Missing hip prevents a complete negative/correction certificate")
    }
    func testSameLimitedFirstThreeDoNotEstablishAbsoluteDepth() {
        for exercise in [FormExercise.pushUp, .squat, .barbellRow] {
            let tracker = FormWarningTracker(exercise: exercise)
            let limited = ["elbow_min": 150.0, "knee_min": 150.0, "torso_mean": 15.0,
                           "elbow_behind_max": 0.01, "front_view_fraction": 0.0]
            let fired = tracker.judge(limited, history: Array(repeating: limited, count: 3), repIndex: 4)
            XCTAssertFalse(fired.contains("pushup_shallow"))
            XCTAssertFalse(fired.contains("squat_shallow"))
            XCTAssertFalse(fired.contains("row_short_pull"))
            // Relative equality is expected here, not evidence those baselines are correct form.
        }
    }
    func testHipsFirstNeedsSpeedConjunctionNotTorsoColorAlone() {
        let tracker = FormWarningTracker(exercise: .squat)
        let base = ["front_view_fraction": 0.0, "hips_first_torso_rise": 20.0,
                    "hips_first_hip_rise_speed": 1.0, "hips_first_shoulder_rise_speed": 2.0]
        XCTAssertFalse(tracker.judge(base, history: [], repIndex: 1).contains("squat_hips_first"))
        var faster = base; faster["hips_first_hip_rise_speed"] = 3
        XCTAssertTrue(tracker.judge(faster, history: [], repIndex: 1).contains("squat_hips_first"))
    }
}
