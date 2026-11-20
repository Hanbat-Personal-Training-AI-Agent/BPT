import Foundation

/// Trial-only launch/file configuration shared by the app and pure Swift regression package.
enum DemoConfig {
    static let values: [String: String] = {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: documents.appendingPathComponent("bpt_demo.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.mapValues { "\($0)" }
    }()
    static let environment = ProcessInfo.processInfo.environment.merging(values) { _, file in file }
    static func url(_ key: String) -> URL? {
        guard let path = environment[key], !path.isEmpty else { return nil }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : documents.appendingPathComponent(path)
    }
}
