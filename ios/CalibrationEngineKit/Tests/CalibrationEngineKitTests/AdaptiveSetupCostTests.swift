import Foundation
import simd
import XCTest
@testable import CalibrationEngineKit

/// E6 (docs/results/setup_constraint.md): per-frame cost of the experimental modules on top of XS. Off unless
/// BPT_COST=1 (timing, not logic): BPT_COST=1 swift test -c release --filter AdaptiveSetupCostTests.
final class AdaptiveSetupCostTests: XCTestCase {
    func testPerFrameCost() throws {
        guard ProcessInfo.processInfo.environment["BPT_COST"] == "1" else { throw XCTSkip("set BPT_COST=1") }
        var rng = SystemRandomNumberGenerator()
        func pose(_ t: Int) -> [SIMD3<Double>] {
            let drop = 0.15 * (1 - cos(2 * .pi * Double(t) / 40))
            var p = [SIMD3<Double>](repeating: .zero, count: 17)
            p[1] = [-0.1, 0, 0.02]; p[4] = [0.1, 0, -0.02]; p[7] = [0, -0.25, 0]; p[8] = [0, -0.5, 0.02]; p[9] = [0, -0.6, 0.03]
            p[10] = [0, -0.7, 0.04]; p[11] = [0.17, -0.5, 0]; p[14] = [-0.17, -0.5, 0]; p[12] = [0.2, -0.25, 0.1 + drop]
            p[15] = [-0.2, -0.25, 0.1 + drop]; p[2] = [-0.16, 0.45 - drop / 2, 0.15 + drop]; p[5] = [0.16, 0.45 - drop / 2, 0.15 + drop]
            p[6] = [0.2, 0.9 - drop, 0.05]; p[3] = [-0.2, 0.9 - drop, -0.05]; p[13] = [0.22, -0.05 - drop, 0.25]; p[16] = [-0.22, -0.05 - drop, 0.25]
            return p.map { $0 + SIMD3(Double.random(in: -0.003...0.003, using: &rng), 0, 0) }
        }
        let n = 9000
        let frames = (0..<n).map { pose($0) }
        let confs: [[Double]] = (0..<n).map { t in
            var c = [Double](repeating: 0.85, count: 17)
            if t % 150 < 20 { c[6] = 0.1; c[13] = 0.2 }  // a joint occluded 13% of the time: the fill path runs
            return c
        }
        for exercise in [FormExercise.squat, .pushUp, .barbellRow] {
            var adaptive = AdaptiveRelationConstraint(exercise: exercise)
            var setup = ExerciseSetup(exercise: exercise)
            var t0 = DispatchTime.now().uptimeNanoseconds
            for t in 0..<n { _ = adaptive.update(frames[t], confidence: confs[t], frame: t, unit: 200) }
            let adaptiveUs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1000 / Double(n)
            t0 = DispatchTime.now().uptimeNanoseconds
            for t in 0..<n { _ = setup.update(frames[t], confidence: confs[t], usable: true, up: SIMD3(0, -1, 0), unit: 200) }
            let setupUs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1000 / Double(n)
            print("E6 cost \(exercise.rawValue): adaptive \(String(format: "%.1f", adaptiveUs)) us/frame, setup \(String(format: "%.1f", setupUs)) us/frame")
            XCTAssertLessThan(adaptiveUs, 1000)  // sanity only: 1 ms would be 3% of the 33 ms frame budget
        }
    }
}
