import XCTest
@testable import CalibrationEngineKit

/// Rep-state transitions found with outputs/rep_validation (Exercise3D replay).
final class RepTransitionTests: XCTestCase {
    private func kp(_ x: Double, _ y: Double, _ c: Double = 0.9) -> PoseKeypoint { PoseKeypoint(x: x, y: y, confidence: c) }

    /// Side-view squat, both legs on top of each other.
    private func squatPose(hip: PoseKeypoint, knee: PoseKeypoint) -> [PoseKeypoint] {
        var k = [PoseKeypoint](repeating: kp(0, -300), count: 17)
        k[11] = hip; k[12] = hip; k[13] = knee; k[14] = knee; k[15] = kp(0, 400); k[16] = kp(0, 400)
        return k
    }

    private func squatReps(_ poses: [[PoseKeypoint]]) -> Int {
        let evaluator = SquatEvaluator()
        var rep = 0
        for (i, pose) in poses.enumerated() { rep = evaluator.evaluate(frameIndex: i, coco17: pose).rep }
        return rep
    }

    func testSquatFastRepWithoutDescendingOrAscendingCounts() {
        // top → bottom → top with no in-between frames: stable status goes top → bottom → top by
        // forced transitions and never shows descending/ascending.
        let top = squatPose(hip: kp(0, 0), knee: kp(0, 200))
        let bottom = squatPose(hip: kp(-150, 220), knee: kp(50, 250))
        let rep = Array(repeating: top, count: 10) + Array(repeating: bottom, count: 20) + Array(repeating: top, count: 20)
        XCTAssertEqual(squatReps(rep + rep), 2)
    }

    func testSquatStandingSwayCountsNothing() {
        // 20 s of standing: ±20 px sideways sway and a 20 px (5% of the leg) vertical bob.
        let poses = (0..<600).map { i -> [PoseKeypoint] in
            let t = Double(i) / 30
            let dx = 20 * sin(2 * .pi * 0.5 * t), dy = 20 * (1 - cos(2 * .pi * 0.7 * t)) / 2
            return squatPose(hip: kp(dx, dy), knee: kp(dx, 200 + dy / 2))
        }
        XCTAssertEqual(squatReps(poses), 0)
    }
}
