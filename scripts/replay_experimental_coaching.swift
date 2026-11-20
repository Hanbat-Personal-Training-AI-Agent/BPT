import Foundation
import simd

/// Numeric logs only. Compile with the production module; no video, model inference, or network.
/// swiftc ios/Runner/NativePose/Evaluators/ExperimentalCoaching.swift scripts/replay_experimental_coaching.swift -o /tmp/bpt-coaching-replay
@main enum CoachingReplay {
    static func main() throws {
        var results: [[String: Any]] = []
        for path in CommandLine.arguments.dropFirst() {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            var engine = ExperimentalCoaching()
            var distributions: [String: [Double]] = [:]
            var available: [String: Int] = [:]
            var reasons: [String: Int] = [:]
            var candidates: [String: Int] = [:]
            var frames = 0
            func pose(_ value: Any?) -> [SIMD3<Double>]? {
                guard let a = value as? [Double], a.count == 51 else { return nil }
                return stride(from: 0, to: 51, by: 3).map { SIMD3(a[$0], a[$0+1], a[$0+2]) }
            }
            for line in source.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      row["type"] as? String == "frame", let time = row["arrival_host"] as? Double else { continue }
                frames += 1
                let names = ["barbellRow":"barbell_row", "pushUp":"pushup", "benchPress":"bench_press"]
                let exercise = names[row["exercise"] as? String ?? ""] ?? (row["exercise"] as? String ?? "unknown")
                let up = (row["up"] as? [Double]).flatMap { $0.count == 3 ? SIMD3($0[0],$0[1],$0[2]) : nil }
                let frame = ExperimentalCoaching.Frame(time:time, exercise:exercise, phase:row["phase"] as? String,
                    state:row["state"] as? String ?? "unknown", raw:pose(row["pose3d_raw"]), corrected:pose(row["pose3d"]),
                    confidence:row["confidence_h36m"] as? [Double], invalid:(row["invalid"] as? [Int]).map(Set.init),up:up)
                let output = engine.update(frame)
                for (key, metric) in output.metrics {
                    if let value = metric.value { distributions[key,default:[]].append(value) }
                    if metric.available { available[key,default:0] += 1 }
                    for reason in metric.reasons { reasons[reason,default:0] += 1 }
                }
                for candidate in output.candidates { candidates[candidate.assessment,default:0] += 1 }
            }
            var summary: [String: Any] = [:]
            for (key, values) in distributions {
                let ordered = values.sorted()
                func percentile(_ p: Double) -> Double { ordered[Int(Double(ordered.count-1)*p)] }
                summary[key] = ["count":ordered.count,"p05":percentile(0.05),"median":percentile(0.5),"p95":percentile(0.95),
                                "fully_supported_frames":available[key,default:0]]
            }
            results.append(["file":URL(fileURLWithPath:path).lastPathComponent,"frames":frames,"metrics":summary,
                            "candidate_assessments":candidates,"metric_reason_occurrences":reasons,
                            "interpretation":"Corrected geometry distributions only. Missing raw/mask/support/phase/profile stays withheld; no accuracy claim."])
        }
        let data = try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
    }
}
