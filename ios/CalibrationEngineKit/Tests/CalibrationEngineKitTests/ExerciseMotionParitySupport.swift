import Foundation
#if canImport(CalibrationEngineKit)
@testable import CalibrationEngineKit
#endif

/// Also compiled directly with the two small production sources for CPU-light parity while
/// the phone owns the long-running device experiment lock.
enum ExerciseMotionParity {
    static func verify(_ url: URL) throws -> (checked: Int, largestError: Double, errors: [String]) {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let tolerance = root["tolerance"] as! Double
        var checked = 0, largest = 0.0, errors: [String] = []
        func compare(_ got: Any, _ expected: Any, _ path: String) {
            if expected is NSNull {
                if !(got is NSNull) { errors.append("\(path): expected null") }
            } else if let e = expected as? NSNumber, let g = got as? NSNumber {
                let delta = abs(e.doubleValue - g.doubleValue)
                largest = max(largest, delta)
                if delta > tolerance { errors.append("\(path): \(g) != \(e), diff=\(delta)") }
            } else if let e = expected as? String, let g = got as? String {
                if e != g { errors.append("\(path): \(g) != \(e)") }
            } else if let e = expected as? [Any], let g = got as? [Any] {
                if e.count != g.count { errors.append("\(path): array count"); return }
                for i in e.indices { compare(g[i], e[i], "\(path)[\(i)]") }
            } else if let e = expected as? [String: Any], let g = got as? [String: Any] {
                for k in e.keys.sorted() {
                    guard let value = g[k] else { errors.append("\(path).\(k): missing"); continue }
                    compare(value, e[k]!, "\(path).\(k)")
                }
            } else { errors.append("\(path): type mismatch") }
        }
        func pose(_ value: Any) -> [SIMD3<Double>] {
            (value as! [[Any]]).map { row in SIMD3(row.map { ($0 as? NSNumber)?.doubleValue ?? .nan }) }
        }
        for c in root["cases"] as! [[String: Any]] {
            let expected = c["expected"] as! [String: [String: [String: Any]]]
            for variant in ExerciseMotionVariant.allCases {
                var estimator = ExerciseMotionEstimator(
                    exercise: c["exercise"] as! String, variant: variant,
                    boneProfile: c["bone_profile"] as? [String: Double],
                    calibrationConfidence: c["calibration_confidence"] as! Double)
                for (index, frame) in (c["frames"] as! [[String: Any]]).enumerated() {
                    let context = frame["context"] as! [String: Any]
                    let result = estimator.update(
                        raw: pose(frame["raw"]!), screen2D: pose(frame["screen2d"]!),
                        timestamp: frame["timestamp"] as! Double,
                        fixedCamera: context["fixed_camera"] as? Bool ?? false,
                        cameraMotion: context["camera_motion"] as? Bool ?? false,
                        personID: context["person_id"].map { String(describing: $0) },
                        phase: context["phase"] as? String,
                        gripConfirmed: context["grip_confirmed"] as? Bool ?? false)
                    if let want = expected[variant.rawValue]?[String(index)] {
                        checked += 1
                        compare(result.dictionary, want, "\(c["name"]!)/\(variant.rawValue)/\(index)")
                    }
                }
            }
        }
        return (checked, largest, errors)
    }
}
