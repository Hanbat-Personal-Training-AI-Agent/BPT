import Foundation
/// Streaming JSONL driver. Public synthetic or authorized local evidence only; no geometry/inference.
@main struct NativeBridgeReplay {
    static func main() throws {
        while let line = readLine() {
            let frame = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            var metrics = frame["metrics"] as! [String: Any]
            if CommandLine.arguments.contains("--app-shaped") {
                metrics = Dictionary(uniqueKeysWithValues: CoachingCriteriaBridge.nativeMetricNames.compactMap { name in
                    guard let original = metrics[name] as? [String: Any] else { return nil }
                    let codable = original.filter { ["rawValue", "value", "reasons"].contains($0.key) && !($0.value is NSNull) }
                    return (name, codable as Any)
                })
            }
            let source = frame["source"] as! [String: Any], context = frame["context"] as! [String: Any]
            let request = try CoachingCriteriaBridge.request(metrics: metrics, source: source, context: context)
            let summary = try CoachingCriteriaBridge.summary(metrics: metrics, source: source, context: context)
            let data = try JSONSerialization.data(withJSONObject: ["request": request, "summary": summary], options: [.sortedKeys])
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        }
    }
}
